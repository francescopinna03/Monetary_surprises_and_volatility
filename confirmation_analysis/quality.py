from pathlib import Path
import json
import numpy as np
import pandas as pd
from .audit import source_events, calendar_review
from .protocol import (digest, dump, timestamp, new_output, specification,
                       code_hashes, clock_reference)

MINUTE = 60_000_000_000
PRICE_COLUMNS = ['Open', 'High', 'Low', 'Latest']


def read_prices(path):
    columns = ['Time', *PRICE_COLUMNS, 'Volume']
    try:
        raw = pd.read_csv(path, dtype=str, usecols=columns)
    except pd.errors.EmptyDataError:
        raw = pd.DataFrame(columns=columns)
    footer = raw.Time.fillna('').str.contains(r'download|barchart', case=False)
    raw = raw.loc[~footer].copy()
    wall = pd.to_datetime(raw.Time, format='mixed', errors='coerce')
    if not pd.api.types.is_datetime64_any_dtype(wall) or wall.dt.tz is not None:
        raise ValueError('Raw timestamps must be naive America/Chicago wall times')
    utc = wall.dt.tz_localize('America/Chicago', ambiguous='NaT', nonexistent='NaT').dt.tz_convert('UTC')
    try:
        utc = utc.dt.as_unit('ns')
    except AttributeError:
        utc = utc.astype('datetime64[ns, UTC]')
    numeric = {}
    for name in PRICE_COLUMNS + ['Volume']:
        cleaned = raw[name].astype('string').str.replace(',', '', regex=False)
        numeric[name] = pd.to_numeric(cleaned, errors='coerce').astype('float64')
    values = pd.DataFrame(numeric, index=raw.index)
    finite = np.isfinite(values.to_numpy(dtype='float64', na_value=np.nan)).all(axis=1)
    positive = values[PRICE_COLUMNS].gt(0).all(axis=1)
    ohlc = (values.High.ge(values[['Open', 'Low', 'Latest']].max(axis=1)) &
            values.Low.le(values[['Open', 'High', 'Latest']].min(axis=1)))
    duplicate = utc.notna() & utc.duplicated(keep=False)
    valid = utc.notna() & finite & positive & values.Volume.ge(0) & ohlc & ~duplicate
    flags = dict(n_rows=len(raw), n_invalid_timestamps=int(utc.isna().sum()),
        n_nonfinite_core=int((~finite).sum()), n_nonpositive_price=int((~positive).sum()),
        n_negative_volume=int(values.Volume.lt(0).sum()),
        n_ohlc_inconsistent=int((~ohlc).sum()), n_duplicate_rows=int(duplicate.sum()),
        n_low_volume=int(values.Volume.le(1).sum()), n_valid_core=int(valid.sum()))
    t = values.assign(label_utc=utc, valid_core=valid).loc[utc.notna()].copy()
    t = t.sort_values('label_utc').drop_duplicates('label_utc', keep='first').reset_index(drop=True)
    return t, flags


def isolated_spikes(t, cutoff):
    eligible = t.valid_core & t.end_utc.le(cutoff)
    g = t.loc[eligible]
    result = pd.Series(False, index=t.index)
    if len(g) < 3:
        return result
    x = g.Latest.to_numpy(float)
    times = g.end_utc.astype('int64').to_numpy()
    days = g.end_utc.dt.floor('D').astype('int64').to_numpy()
    median = (x[:-2] + x[2:]) / 2
    ratio = np.maximum(x[1:-1]/median, median/x[1:-1])
    r1, r2 = np.log(x[1:-1]/x[:-2]), np.log(x[2:]/x[1:-1])
    mask = ((days[:-2] == days[1:-1]) & (days[1:-1] == days[2:]) &
        (np.diff(times)[:-1] <= 60*MINUTE) & (np.diff(times)[1:] <= 60*MINUTE) &
        (ratio >= 5) & (np.abs(r1) >= 1) & (np.abs(r2) >= 1) & (np.sign(r1) != np.sign(r2)))
    result.loc[g.index[1:-1]] = mask
    return result


def window_check(t, anchor, offsets):
    offsets = np.asarray(offsets, dtype=int)
    if len(offsets) == 0 or np.any(np.diff(offsets) != 5):
        raise ValueError('Window endpoints must be a nonempty five-minute grid')
    end = anchor.value + offsets*MINUTE
    support = np.unique(np.r_[end-5*MINUTE, end])
    times = t.end_utc.astype('int64').to_numpy()
    position = np.searchsorted(times, support)
    present = position < len(times)
    ix = np.minimum(position, max(len(times)-1, 0))
    if len(times):
        present &= times[ix] == support
        core = present & t.valid_core.to_numpy()[ix]
        spike = isolated_spikes(t, pd.Timestamp(end[-1], tz='UTC')).to_numpy()
        spike_count = int(np.sum(present & spike[ix]))
        low = int(np.sum(present & (t.Volume.to_numpy()[ix] <= 1)))
    else:
        core = np.zeros(len(support), bool); spike_count = low = 0
    valid_times = set(support[core])
    n_pairs = sum(int(e in valid_times and e-5*MINUTE in valid_times) for e in end)
    start = pd.Timestamp(support[0], tz='UTC')
    finish = pd.Timestamp(support[-1], tz='UTC')
    within = bool(len(times) and times[0] <= support[0] and times[-1] >= support[-1])
    endpoints = t[t.end_utc.isin(pd.to_datetime(end, utc=True)) & t.valid_core]
    reasons = []
    if not within: reasons.append('outside_observed_session_span')
    if n_pairs != len(end): reasons.append('missing_or_invalid_exact_price_pair')
    if spike_count: reasons.append('isolated_spike_requires_review')
    return dict(support_start_utc=start.isoformat(), support_end_utc=finish.isoformat(),
        n_required_prices=len(support), n_present_prices=int(present.sum()),
        n_valid_pairs=n_pairs, n_required_pairs=len(end), coverage=n_pairs/len(end),
        inside_observed_session=within, complete_price_grid=not reasons,
        n_isolated_spikes=spike_count, n_low_volume_prices=low,
        endpoint_volume=float(endpoints.Volume.sum()), reason='|'.join(reasons))


def select_candidate(candidates):
    return sorted(candidates, key=lambda r: (
        -int(r['pre']['complete_price_grid']), -r['pre']['coverage'],
        -r['pre']['endpoint_volume'], r['file_name'], r['input_path']))[0]


def primary_files(inventory, canonical_raw_dir=None):
    t = inventory.copy()
    if t.input_path.duplicated().any():
        raise ValueError('Duplicate inventory path')
    t = t[t.root_code.isin(['gg', 'hf', 'hr', 'fx']) & t.contract_year.between(2000, 2012)]
    t = t[t.root_code.ne('fx') | t.contract_year.ge(2011)].copy()
    if canonical_raw_dir is not None:
        directory = Path(canonical_raw_dir).expanduser().resolve()
        if not directory.is_dir():
            raise ValueError('Canonical raw directory does not exist')
        t['source_priority'] = t.input_path.map(lambda p: 0 if Path(p).resolve().is_relative_to(directory) else 1)
    else:
        t['source_priority'] = t.input_path.map(
            lambda p: 0 if '/Raw/Barchart_futures/' in Path(p).as_posix() else 1)
    t = t.sort_values(['source_priority', 'input_path'])
    return t.drop_duplicates(['root_code', 'contract_year', 'expiry_code']).copy()


def label_semantics(evidence, row, candidate):
    if evidence is None:
        return candidate, False
    lo = 2000 + 3*((int(row.contract_year)-2000)//3)
    cell = evidence[evidence.root_code.eq(row.root_code) & evidence.period_start.eq(lo)]
    if len(cell) != 1:
        return candidate, False
    e = cell.iloc[0]
    if str(e.verified).lower() != 'true':
        return candidate, False
    if e.bar_label_semantics not in ('interval_start', 'interval_end'):
        raise ValueError('Unknown verified bar-label semantics')
    if not str(e.evidence_source).startswith(('https://', 'http://')) or not str(e.reviewer).strip():
        raise ValueError('Bar-label evidence requires source and reviewer')
    if len(str(e.representative_sha256)) != 64:
        raise ValueError('Bar-label evidence must bind a representative file hash')
    return e.bar_label_semantics, True


def quality_audit(audit_dir, data_root, output, canonical_raw_dir=None, candidate_semantics='interval_start'):
    audit_dir, data_root = Path(audit_dir), Path(data_root)
    if candidate_semantics not in ('interval_start', 'interval_end'):
        raise ValueError('Unknown candidate semantics')
    metadata = json.loads((audit_dir/'status.json').read_text())
    if metadata.get('confirmation_outcomes_computed') is not False:
        raise ValueError('Expected an outcome-free inventory')
    inventory = pd.read_csv(audit_dir/'raw_inventory_v2.csv')
    for name, expected in metadata.get('table_hashes', {}).items():
        if Path(name).name != name or digest(audit_dir/name) != expected:
            raise ValueError('Inventory table hash mismatch')
    for row in inventory.itertuples():
        if metadata['source_hashes'].get(row.input_path) != row.sha256:
            raise ValueError('Inventory/source manifest mismatch')
    primary_path = audit_dir/'primary_files_v2.csv'
    if canonical_raw_dir is None and primary_path.exists():
        primary = pd.read_csv(primary_path)
        keys = ['root_code', 'contract_year', 'expiry_code']
        if primary.duplicated(keys).any() or not set(primary.input_path).issubset(set(inventory.input_path)):
            raise ValueError('Invalid primary source manifest')
        primary = primary[primary.root_code.ne('fx') | primary.contract_year.ge(2011)]
    else:
        primary = primary_files(inventory, canonical_raw_dir)
    if primary.empty:
        raise ValueError('No primary contract files')
    source = data_root/'Raw/EA-EMPD/EA-EMPD.xlsx'
    previous_ea_hashes = [h for p, h in metadata['source_hashes'].items()
                          if Path(p).name == 'EA-EMPD.xlsx']
    if previous_ea_hashes != [digest(source)]:
        raise ValueError('EA-EMPD changed since inventory; rebuild metadata first')
    cert = data_root/'Raw/Certification'
    official = cert/'ecb_calendar_verified_v2.csv'
    label_file = cert/'bar_label_evidence_v2.csv'
    ea = source_events(source)
    calendar = calendar_review(ea, official if official.exists() else None)
    evidence = pd.read_csv(label_file, dtype={'representative_sha256': str}).fillna('') if label_file.exists() else None
    if evidence is not None:
        required = {'root_code', 'period_start', 'verified', 'bar_label_semantics',
                    'evidence_source', 'reviewer', 'representative_sha256'}
        if not required.issubset(evidence) or evidence.duplicated(['root_code', 'period_start']).any():
            raise ValueError('Invalid bar-label evidence schema')
        for ev in evidence.itertuples():
            if str(ev.verified).lower() == 'true':
                match = primary[primary.sha256.eq(ev.representative_sha256) & primary.root_code.eq(ev.root_code)
                    & primary.contract_year.between(ev.period_start, min(ev.period_start+2, 2012)) & primary.n_rows.gt(0)]
                if len(match) != 1:
                    raise ValueError('Representative evidence hash not in the primary period inventory')
    spec = specification()
    clock_reference()
    out = new_output(output)
    dump(out/'status.json', dict(status='running_quality_only', confirmation_outcomes_computed=False))
    sources = {str(p.resolve()): digest(p) for p in [source, audit_dir/'status.json', audit_dir/'raw_inventory_v2.csv']}
    for p in [official, label_file]:
        if p.exists(): sources[str(p.resolve())] = digest(p)
    cache, summaries, session_rows = {}, [], []
    for row in primary.itertuples():
        path = Path(row.input_path)
        if digest(path) != row.sha256:
            raise ValueError(f'Raw file changed since inventory: {path.name}')
        semantics, verified = label_semantics(evidence, row, candidate_semantics)
        t, flags = read_prices(path)
        t['end_utc'] = t.label_utc + pd.Timedelta(minutes=5 if semantics == 'interval_start' else 0)
        t['trade_date'] = t.end_utc.dt.tz_convert('Europe/Berlin').dt.strftime('%Y-%m-%d')
        sources[str(path.resolve())] = row.sha256
        summaries.append(dict(input_path=str(path), file_name=path.name, root_code=row.root_code,
            contract_year=int(row.contract_year), expiry_code=row.expiry_code, sha256=row.sha256,
            semantics=semantics, bar_label_verified=verified, **flags))
        for date, g in t.groupby('trade_date'):
            if not '2000-01-01' <= date <= '2012-12-31': continue
            cache.setdefault((date, row.root_code), []).append(dict(input_path=str(path), file_name=path.name,
                root_code=row.root_code, frame=g, bar_label_verified=verified))
            session_rows.append(dict(trade_date=date, input_path=str(path), root_code=row.root_code,
                n_bars=len(g), first_end_utc=g.end_utc.min().isoformat(), last_end_utc=g.end_utc.max().isoformat(),
                n_gaps_over_5min=int(g.end_utc.diff().gt(pd.Timedelta(minutes=5)).sum()),
                session_status='observed_grid_not_exchange_calendar'))
    primary.to_csv(out/'primary_files.csv', index=False)
    pd.DataFrame(summaries).to_csv(out/'price_quality_files.csv', index=False)
    pd.DataFrame(session_rows).to_csv(out/'primary_sessions.csv', index=False)
    events = {d: g.set_index('phase') for d, g in calendar.groupby('event_date')}
    preferred, windows, ranks = [], [], []
    event_keys = {(d, r) for d in events for r in spec['roots']}
    for date, root in sorted(set(cache) | event_keys):
        if pd.Timestamp(date).weekday() >= 5 and date not in events: continue
        event = events.get(date)
        anchors, present, verified = {}, {}, {}
        for phase, wall_time in [('PR', '13:45'), ('PC', '14:30')]:
            row = event.loc[phase] if event is not None else None
            verified[phase] = row is not None and row.calendar_status in ('verified_present', 'verified_absent')
            present[phase] = row is None or row.calendar_status != 'verified_absent'
            anchors[phase] = (pd.Timestamp(row.event_datetime_utc).tz_convert('UTC')
                if row is not None and row.calendar_status == 'verified_present' else
                pd.Timestamp(date+' '+wall_time).tz_localize('Europe/Berlin').tz_convert('UTC'))
        candidates = cache.get((date, root), [])
        for c in candidates:
            c['pre'] = window_check(c['frame'], anchors['PR'], spec['pre_pr_return_endpoints_minutes'])
        chosen = select_candidate(candidates) if candidates else None
        for c in candidates:
            ranks.append(dict(trade_date=date, root_code=root, input_path=c['input_path'],
                selected=c is chosen, pre_complete=c['pre']['complete_price_grid'], pre_coverage=c['pre']['coverage'],
                pre_volume=c['pre']['endpoint_volume'], pre_reason=c['pre']['reason']))
        preferred.append(dict(trade_date=date, root_code=root, is_event=date in events,
            input_path=chosen['input_path'] if chosen else '', selection_uses_post_pr=False,
            selection_status='selected_pre_only' if chosen else 'no_candidate_contract',
            calendar_verified=verified['PR'] if event is not None else False,
            bar_label_verified=chosen['bar_label_verified'] if chosen else False))
        for phase in ['PR', 'PC']:
            base = dict(trade_date=date, root_code=root, phase=phase, is_event=date in events,
                actual_phase_status=('present' if present[phase] else 'absent') if verified[phase] else 'unverified',
                calendar_verified=verified[phase], input_path=chosen['input_path'] if chosen else '',
                confirmation_outcome_computed=False)
            if chosen is None:
                windows.append(dict(**base, window='phase', reason='no_candidate_contract', complete_price_grid=False))
                continue
            checks = [('state', anchors['PR'], spec['pre_pr_return_endpoints_minutes']),
                      ('phase', anchors[phase], spec[phase.lower()+'_return_endpoints_minutes'])]
            if phase == 'PC':
                checks.append(('normal_pre', anchors['PC'], spec['pc_normal_pre_return_endpoints_minutes']))
            for name, anchor, offsets in checks:
                check = window_check(chosen['frame'], anchor, offsets)
                check.pop('endpoint_volume')
                overlap = (phase == 'PR' and name == 'phase' and verified['PC'] and present['PC']
                    and pd.Timestamp(check['support_end_utc']) > anchors['PC'])
                windows.append(dict(**base, window=name, **check,
                    bar_label_verified=chosen['bar_label_verified'], pr_overlaps_pc=overlap,
                    diagnostic_only=not (verified[phase] and verified['PR'] and chosen['bar_label_verified']),
                    actual_phase_eligible=bool(present[phase] and present['PR'] and verified[phase] and verified['PR']
                        and chosen['bar_label_verified'] and check['complete_price_grid'] and not overlap)))
    pd.DataFrame(preferred).to_csv(out/'preferred_contracts.csv', index=False)
    pd.DataFrame(ranks).to_csv(out/'contract_selection_candidates.csv', index=False)
    window_table = pd.DataFrame(windows)
    window_table.to_csv(out/'window_quality.csv', index=False)
    phase_rows = []
    for (date, root, phase), g in window_table.groupby(['trade_date', 'root_code', 'phase']):
        expected = {'state', 'phase', 'normal_pre'} if phase == 'PC' else {'state', 'phase'}
        full = set(g.window) == expected and g.complete_price_grid.eq(True).all()
        reasons = sorted({s for r in g.reason.fillna('') for s in r.split('|') if s})
        if not set(g.window) == expected: reasons.append('required_window_missing')
        if not g.calendar_verified.eq(True).all(): reasons.append('calendar_unverified_or_control_clock_candidate')
        if not g.get('bar_label_verified', pd.Series(False, index=g.index)).eq(True).all(): reasons.append('bar_label_unverified')
        if g.actual_phase_status.eq('absent').any(): reasons.append('actual_phase_absent')
        if g.get('pr_overlaps_pc', pd.Series(False, index=g.index)).eq(True).any(): reasons.append('pr_overlaps_pc')
        phase_rows.append(dict(trade_date=date, root_code=root, phase=phase, is_event=bool(g.is_event.iloc[0]),
            input_path=g.input_path.iloc[0], complete_all_price_grids=bool(full),
            certified_event_price_eligibility=bool(full and g.get('actual_phase_eligible',
                pd.Series(False, index=g.index)).eq(True).all()),
            exclusion_reasons='|'.join(reasons), confirmation_outcome_computed=False))
    pd.DataFrame(phase_rows).to_csv(out/'phase_eligibility.csv', index=False)
    calendar.drop(columns=['OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y', 'STOXX50E']).to_csv(out/'calendar_review.csv', index=False)
    dump(out/'specification.json', spec)
    tables = {p.name: digest(p) for p in out.iterdir() if p.is_file() and p.name != 'status.json'}
    if any(digest(p) != h for p, h in sources.items()):
        raise ValueError('Input changed during quality audit')
    status = dict(status='complete_quality_audit_not_frozen', created_utc=timestamp(),
        confirmation_outcomes_computed=False, confirmation_outcome_tables_read=False,
        raw_prices_read_for_quality_only=True, confirmation_estimation_enabled=False,
        n_primary_files=len(primary), n_primary_files_with_bars=sum(s['n_rows'] > 0 for s in summaries),
        all_nonempty_files_label_verified=bool(any(s['n_rows'] > 0 for s in summaries) and
            all(s['bar_label_verified'] for s in summaries if s['n_rows'] > 0)),
        verified_calendar_rows=int(calendar.calendar_status.str.startswith('verified_').sum()),
        expected_calendar_rows=len(calendar), duplicate_policy='all_duplicate_labels_invalid_pending_review',
        spike_policy='flag_only_scoped_at_each_window_cutoff_pending_cleaning_review',
        control_clock_policy='historical_regular_schedule_diagnostic_pending_session_review',
        table_hashes=tables, source_hashes=sources, code_hashes=code_hashes())
    dump(out/'status.json', status)
    print('Quality audit complete. No event outcomes, calibration, freeze or estimation.', flush=True)
    return status
