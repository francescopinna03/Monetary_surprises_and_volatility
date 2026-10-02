from pathlib import Path
import itertools
import re
import numpy as np
import pandas as pd
from .protocol import (digest, dump, timestamp, new_output, specification,
                       code_hashes, parse_contract, clock_reference)

CALENDAR_COLUMNS = ['event_date', 'phase', 'actual_phase_present', 'event_datetime_utc',
                    'source_url', 'verification_status', 'notes']


def source_events(path):
    columns = ['Date_time', 'Event_type', 'OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y', 'STOXX50E']
    t = pd.read_excel(path, sheet_name='EA-EMPD', usecols=columns)
    t = t[t.Event_type.isin(['GC_PR', 'GC_PC'])].copy()
    t['source_datetime'] = pd.to_datetime(t.Date_time, errors='raise')
    t['event_date'] = t.source_datetime.dt.strftime('%Y-%m-%d')
    t['phase'] = t.Event_type.str.removeprefix('GC_')
    if t.duplicated(['event_date', 'phase']).any():
        raise ValueError('Duplicate EA-EMPD source phase date')
    return t[t.source_datetime.dt.year.between(2000, 2012)].copy()


def audit_file(path, meta):
    t = pd.read_csv(path, usecols=['Time', 'Volume'], dtype=str)
    raw = pd.to_datetime(t.Time, format='mixed', errors='coerce')
    footer = t.Time.fillna('').str.contains('download|barchart', case=False)
    bad = int((raw.isna() & ~footer).sum())
    valid = raw.notna()
    naive = pd.DatetimeIndex(raw[valid])
    if naive.tz is not None:
        raise ValueError('Raw CSV unexpectedly has timezone-aware timestamps')
    utc = naive.tz_localize('America/Chicago', ambiguous='NaT', nonexistent='NaT').tz_convert('UTC')
    ambiguous = int(utc.isna().sum())
    volumes = pd.to_numeric(t.loc[valid, 'Volume'].str.replace(',', '', regex=False), errors='coerce').to_numpy()
    frame = pd.DataFrame({'utc': utc, 'raw_wall': naive, 'volume': volumes})
    frame = frame[frame.utc.notna()].sort_values('utc')
    frame['trade_date'] = frame.utc.dt.tz_convert('Europe/Berlin').dt.strftime('%Y-%m-%d')
    sessions = []
    for date, g in frame.groupby('trade_date'):
        times = g.utc.drop_duplicates().sort_values()
        gaps = times.diff().dt.total_seconds().dropna()/60
        sessions.append(dict(file_name=path.name, input_path=str(path), **meta, trade_date=date,
            n_bars=len(g), first_label_raw=str(g.raw_wall.min()), last_label_raw=str(g.raw_wall.max()),
            first_label_utc=str(times.min()), last_label_utc=str(times.max()),
            n_gaps_over_5min=int(gaps.gt(5).sum()),
            max_gap_minutes=float(gaps.max()) if len(gaps) else None,
            n_duplicate_labels=int(g.utc.duplicated().sum()),
            session_status='observed_span_only_not_a_certified_trading_calendar'))
    flags = [] if len(frame) else ['no_timestamped_bars']
    for name, count in [('invalid_timestamps', bad), ('ambiguous_or_nonexistent_wall_times', ambiguous),
                        ('duplicate_timestamps', int(frame.utc.duplicated().sum())),
                        ('invalid_volume', int(np.sum(~np.isfinite(volumes) | (volumes < 0))))]:
        if count:
            flags.append(name)
    return dict(n_rows=len(frame), n_bad_datetime=bad, n_ambiguous_wall_times=ambiguous,
                n_invalid_volume=int(np.sum(~np.isfinite(volumes) | (volumes < 0))),
                status='review' if flags else 'metadata_ok_prices_not_checked',
                flags='|'.join(flags)), sessions


def calendar_review(ea, official=None):
    dates = sorted(ea.event_date.unique())
    grid = pd.DataFrame(itertools.product(dates, ['PR', 'PC']), columns=['event_date', 'phase'])
    t = grid.merge(ea, on=['event_date', 'phase'], how='left', validate='one_to_one')
    t['source_window_present'] = t.source_datetime.notna()
    t['source_clock_candidate_utc'] = t.source_datetime.dt.tz_localize('Europe/Berlin').dt.tz_convert('UTC').astype(str)
    t['weekday'] = pd.to_datetime(t.event_date).dt.day_name()
    t['calendar_status'] = 'unverified_source_window_is_not_proof_of_an_event'
    t['event_datetime_utc'] = ''
    t['actual_phase_present'] = ''
    t['calendar_source_url'] = ''
    if official is not None:
        c = pd.read_csv(official, dtype=str).fillna('')
        if not set(CALENDAR_COLUMNS).issubset(c.columns) or c.duplicated(['event_date', 'phase']).any():
            raise ValueError('Invalid verified calendar schema or duplicate key')
        for row in c.itertuples():
            if row.verification_status != 'verified':
                continue
            if not row.source_url.startswith('https://www.ecb.europa.eu/'):
                raise ValueError('Verified ECB calendar row needs an official source URL')
            if row.actual_phase_present not in ('true', 'false'):
                raise ValueError('Verified actual_phase_present must be true or false')
            if row.actual_phase_present == 'true':
                instant = pd.Timestamp(row.event_datetime_utc)
                if instant.tzinfo is None:
                    raise ValueError('Verified event timestamp needs an explicit offset')
                if instant.tz_convert('Europe/Berlin').strftime('%Y-%m-%d') != row.event_date:
                    raise ValueError('Verified event timestamp/date mismatch')
            ix = t.event_date.eq(row.event_date) & t.phase.eq(row.phase)
            t.loc[ix, ['calendar_status', 'event_datetime_utc', 'actual_phase_present', 'calendar_source_url']] = [
                'verified_present' if row.actual_phase_present == 'true' else 'verified_absent',
                row.event_datetime_utc, row.actual_phase_present, row.source_url]
    t['timing_exception_review'] = t.event_date.isin(['2001-09-17', '2008-10-08'])
    t['actual_pc_requires_specific_evidence'] = t.phase.eq('PC') & t.event_date.lt('2001-12-01')
    return t


def audit(root, raw_dirs, out):
    spec = specification()
    out = new_output(out)
    dump(out/'status.json', {'status': 'running_metadata_only', 'confirmation_outcomes_read': False})
    source = Path(root)/'Raw/EA-EMPD/EA-EMPD.xlsx'
    ea = source_events(source)
    official = Path(root)/'Raw/Certification/ecb_calendar_verified_v2.csv'
    calendar = calendar_review(ea, official if official.exists() else None)
    calendar.drop(columns=['OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y', 'STOXX50E']).to_csv(out/'calendar_review.csv', index=False)
    template = calendar[['event_date', 'phase']].copy()
    for name in CALENDAR_COLUMNS[2:]:
        template[name] = ''
    template.to_csv(out/'ecb_calendar_verified_v2_TEMPLATE.csv', index=False)
    clock_reference().to_csv(out/'historical_clock_self_test.csv', index=False)
    files, sessions, ignored = [], [], []
    raw_dirs = [Path(directory).resolve() for directory in raw_dirs]
    paths = set()
    for directory in raw_dirs:
        directory = Path(directory)
        if not directory.is_dir():
            raise FileNotFoundError(f'Raw directory missing: {directory}')
        paths.update(p.resolve() for p in directory.rglob('*.csv')
                     if re.match(r'^(fx|gg|hf|hr)[hmuz]\d{2}_intraday-', p.name.lower()))
    for path in sorted(paths):
        try:
            meta = parse_contract(path.name)
        except ValueError as exc:
            ignored.append(dict(file_name=path.name, reason=str(exc)))
            continue
        if not 2000 <= meta['contract_year'] <= 2012:
            continue
        row = dict(file_name=path.name, input_path=str(path), **meta, sha256=digest(path), bytes=path.stat().st_size)
        try:
            counts, days = audit_file(path, meta)
            row.update(counts)
            sessions.extend(days)
        except (ValueError, KeyError, pd.errors.ParserError) as exc:
            row.update(status='metadata_parse_failed', flags=str(exc), n_rows=0)
        files.append(row)
        print(f'Metadata {len(files)}: {path.name}', flush=True)
    f = pd.DataFrame(files, columns=['file_name', 'input_path', 'root_code', 'expiry_code', 'contract_year',
        'sha256', 'bytes', 'n_rows', 'n_bad_datetime', 'n_ambiguous_wall_times', 'n_invalid_volume', 'status', 'flags'])
    f.to_csv(out/'raw_inventory_v2.csv', index=False)
    session_cols = ['file_name', 'input_path', 'root_code', 'expiry_code', 'contract_year', 'trade_date', 'n_bars',
        'first_label_raw', 'last_label_raw', 'first_label_utc', 'last_label_utc',
        'n_gaps_over_5min', 'max_gap_minutes', 'n_duplicate_labels', 'session_status']
    days = pd.DataFrame(sessions, columns=session_cols)
    days.to_csv(out/'sessions_v2.csv', index=False)
    pd.DataFrame(ignored, columns=['file_name', 'reason']).to_csv(out/'ignored_files_v2.csv', index=False)
    expected = [(root, year, expiry) for root in ['gg', 'hf', 'hr'] for year in range(2000, 2013) for expiry in 'HMUZ']
    expected += [('fx', year, expiry) for year in (2011, 2012) for expiry in 'HMUZ']
    coverage = []
    for asset, year, expiry in expected:
        cell = f[f.root_code.eq(asset) & f.contract_year.eq(year) & f.expiry_code.eq(expiry)]
        n = len(cell)
        with_bars = int(cell.n_rows.gt(0).sum())
        metadata_ok = int((cell.n_rows.gt(0) & cell.status.eq('metadata_ok_prices_not_checked')).sum())
        status = ('missing' if n == 0 else 'no_timestamped_bars' if with_bars == 0
                  else 'duplicate_candidates_review' if n > 1
                  else 'metadata_review' if metadata_ok == 0 else 'present_with_bars_prices_not_checked')
        coverage.append(dict(root_code=asset, contract_year=year, expiry_code=expiry,
                             n_files=n, n_files_with_bars=with_bars,
                             n_files_metadata_ok=metadata_ok, status=status))
    pd.DataFrame(coverage).to_csv(out/'contract_coverage_v2.csv', index=False)
    def source_rank(path):
        path = Path(path).resolve()
        for rank, directory in enumerate(raw_dirs):
            try:
                path.relative_to(directory)
                return rank
            except ValueError:
                continue
        return len(raw_dirs)
    if f.empty:
        primary = f.copy()
    else:
        f['_source_rank'] = f.input_path.map(source_rank)
        primary = (f.dropna(subset=['root_code', 'contract_year', 'expiry_code'])
                     .sort_values(['root_code', 'contract_year', 'expiry_code', '_source_rank', 'input_path'])
                     .drop_duplicates(['root_code', 'contract_year', 'expiry_code'], keep='first'))
        f.drop(columns=['_source_rank'], inplace=True)
    primary_paths = set(primary.input_path) if not primary.empty else set()
    primary.to_csv(out/'primary_files_v2.csv', index=False)
    primary_days = days[days.input_path.isin(primary_paths)]
    records = []
    for event in calendar.itertuples():
        year = int(event.event_date[:4])
        for asset in spec['roots']:
            candidates = primary_days[primary_days.trade_date.eq(event.event_date) & primary_days.root_code.eq(asset)]
            fx_present = bool((primary_days.trade_date.eq(event.event_date) & primary_days.root_code.eq('fx')).any())
            rows = dict(event_date=event.event_date, phase=event.phase, root_code=asset,
                role='confirmation', era='2000-2007' if year < 2008 else '2008-2012',
                source_window_present=event.source_window_present, calendar_status=event.calendar_status,
                timing_exception_review=event.timing_exception_review,
                ois1m_available=bool(np.isfinite(event.OIS_1M)),
                ois1y_available=bool(np.isfinite(event.OIS_1Y)),
                ea_equity_available=bool(np.isfinite(event.STOXX50E)),
                ea_pc1_available=bool(np.isfinite([event.OIS_1M, event.OIS_3M, event.OIS_6M, event.OIS_1Y]).all()),
                n_contracts_with_date=len(candidates),
                equity_source='pending_bridge_and_window_audit',
                equity_source_candidate='fx_futures' if fx_present else 'ea_empd_stoxx50e',
                phase_price_eligibility='not_evaluated_pre_freeze',
                confirmation_outcome_computed=False)
            records.append(rows)
    pd.DataFrame(records).to_csv(out/'event_registry_v2.csv', index=False)
    labels = []
    for asset in spec['roots']:
        for start in [2000, 2003, 2006, 2009, 2012]:
            subset = primary[primary.root_code.eq(asset) & primary.n_rows.gt(0) &
                             primary.contract_year.between(start, min(start+2, 2012))]
            labels.append(dict(root_code=asset, period_start=start,
                representative_file='' if subset.empty else subset.iloc[0].file_name,
                representative_sha256='' if subset.empty else subset.iloc[0].sha256,
                bar_label_semantics='', evidence_source='', reviewer='', verified=False,
                status='no_file_in_period' if subset.empty else 'provider_evidence_required'))
    pd.DataFrame(labels).to_csv(out/'bar_label_evidence_TEMPLATE.csv', index=False)
    source_hashes = {str(source.resolve()): digest(source)}
    if official.exists():
        source_hashes[str(official.resolve())] = digest(official)
    source_hashes.update(dict(zip(f.input_path, f.sha256)))
    status = dict(status='complete_metadata_audit_not_frozen', created_utc=timestamp(),
        confirmation_outcomes_read=False, confirmation_outcomes_computed=False,
        code_hashes=code_hashes(), source_hashes=source_hashes,
        n_event_dates=int(ea.event_date.nunique()), n_source_pr=int(ea.phase.eq('PR').sum()),
        n_source_pc=int(ea.phase.eq('PC').sum()), n_raw_files=len(f), n_registry_rows=len(records),
        n_raw_files_with_bars=int(f.n_rows.gt(0).sum()),
        n_raw_files_without_bars=int(f.n_rows.fillna(0).eq(0).sum()),
        n_expected_contracts_present=sum(row['n_files'] > 0 for row in coverage),
        n_expected_contracts_with_bars=sum(row['n_files_with_bars'] > 0 for row in coverage),
        n_expected_contracts_metadata_ok=sum(row['n_files_metadata_ok'] > 0 for row in coverage),
        n_primary_contracts_with_bars=int(primary.n_rows.gt(0).sum()) if not primary.empty else 0,
        n_primary_contracts_metadata_ok=int(primary.status.eq('metadata_ok_prices_not_checked').sum()) if not primary.empty else 0,
        n_duplicate_candidate_cells=int(sum(row['n_files'] > 1 for row in coverage)),
        archive_coverage_certified=False,
        expected_contract_cells=len(expected),
        ois1m_missing_by_source_phase={phase: int(g.OIS_1M.isna().sum()) for phase, g in ea.groupby('phase')},
        verified_calendar_rows=int(calendar.calendar_status.str.startswith('verified_').sum()),
        table_hashes={p.name: digest(p) for p in out.glob('*.csv')},
        required_before_freeze=spec['required_before_freeze'])
    dump(out/'status.json', status)
    print(f"Audit complete: {status['n_raw_files']} files, {status['n_event_dates']} dates; no confirmation outcomes computed.", flush=True)
    return status
