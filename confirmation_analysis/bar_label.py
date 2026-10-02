import json
from pathlib import Path
import numpy as np
import pandas as pd
from .protocol import digest, dump, timestamp, new_output, code_hashes
from .quality import read_prices

SCHEDULE_COLUMNS = ['root_code', 'period_start_date', 'period_end_date', 'session_open_wall',
                    'session_close_wall', 'timezone', 'source_url', 'reviewer', 'notes']
SEMANTICS = ('interval_start', 'interval_end')


def write_schedule_template(path):
    path = Path(path)
    if path.exists():
        raise FileExistsError(f'Refusing to overwrite a trading-hours file: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(columns=SCHEDULE_COLUMNS).to_csv(path, index=False)
    return path


def load_schedule(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError('EUREX_SCHEDULE_MISSING: supply config/eurex_trading_hours.csv with its source')
    t = pd.read_csv(path, dtype=str).fillna('')
    if not set(SCHEDULE_COLUMNS).issubset(t.columns):
        raise ValueError('EUREX_SCHEDULE_SCHEMA: missing columns')
    if t.empty:
        raise ValueError('EUREX_SCHEDULE_EMPTY: the template carries no reviewed epoch')
    if t.timezone.nunique() != 1:
        raise ValueError('EUREX_SCHEDULE_TIMEZONE: one exchange timezone per schedule file')
    for row in t.itertuples():
        if not str(row.source_url).startswith('https://') or not str(row.reviewer).strip():
            raise ValueError('EUREX_SCHEDULE_UNSOURCED: every epoch needs a source URL and a reviewer')
        try:
            for field in ('session_open_wall', 'session_close_wall'):
                pd.Timestamp('2000-01-03 '+getattr(row, field)).tz_localize(row.timezone)
            start, stop = pd.Timestamp(row.period_start_date), pd.Timestamp(row.period_end_date)
        except (ValueError, TypeError) as exc:
            raise ValueError(f'EUREX_SCHEDULE_TIME: unusable epoch clock ({exc})') from exc
        if pd.isna(start) or pd.isna(stop) or stop < start:
            raise ValueError('EUREX_SCHEDULE_RANGE: unusable epoch range')
    for root, g in t.groupby('root_code'):
        g = g.sort_values('period_start_date')
        starts = pd.to_datetime(g.period_start_date).to_numpy()
        stops = pd.to_datetime(g.period_end_date).to_numpy()
        if np.any(starts[1:] <= stops[:-1]):
            raise ValueError(f'EUREX_SCHEDULE_OVERLAP: overlapping epochs for {root}')
    return t


def applicable(schedule, root_code, date):
    rows = schedule[(schedule.root_code.isin([root_code, 'all'])) &
                    (schedule.period_start_date <= date) & (schedule.period_end_date >= date)]
    if rows.empty:
        return None
    exact = rows[rows.root_code.eq(root_code)]
    return (exact if len(exact) else rows).iloc[0]


def day_boundaries(t, timezone):
    g = t[t.valid_core].copy()
    if g.empty:
        return pd.DataFrame(columns=['trade_date', 'first_wall', 'last_wall', 'n_bars'])
    local = g.label_utc.dt.tz_convert(timezone)
    g = g.assign(trade_date=local.dt.strftime('%Y-%m-%d'), wall=local.dt.strftime('%H:%M'))
    out = g.groupby('trade_date').wall.agg(first_wall='min', last_wall='max', n_bars='size')
    return out.reset_index()


def decide_day(first_wall, last_wall, open_wall, close_wall, bar_minutes):
    step = pd.Timedelta(minutes=bar_minutes)
    opened = pd.Timestamp('2000-01-03 '+open_wall)
    closed = pd.Timestamp('2000-01-03 '+close_wall)
    starts = first_wall == opened.strftime('%H:%M') and last_wall == (closed-step).strftime('%H:%M')
    ends = first_wall == (opened+step).strftime('%H:%M') and last_wall == closed.strftime('%H:%M')
    if starts and not ends:
        return 'interval_start'
    if ends and not starts:
        return 'interval_end'
    return 'inconclusive'


def file_evidence(row, schedule, bar_minutes):
    path = Path(row.input_path)
    if digest(path) != row.sha256:
        raise ValueError(f'Raw file changed since inventory: {path.name}')
    t, _ = read_prices(path)
    counts = {name: 0 for name in SEMANTICS+('inconclusive', 'no_schedule')}
    observed = []
    timezone = ''
    for day in day_boundaries(t, schedule.timezone.iloc[0]).itertuples():
        epoch = applicable(schedule, row.root_code, day.trade_date)
        if epoch is None:
            counts['no_schedule'] += 1
            continue
        timezone = epoch.timezone
        verdict = decide_day(day.first_wall, day.last_wall, epoch.session_open_wall,
                             epoch.session_close_wall, bar_minutes)
        counts[verdict] += 1
        observed.append(dict(trade_date=day.trade_date, first_wall=day.first_wall, last_wall=day.last_wall,
                             session_open_wall=epoch.session_open_wall, session_close_wall=epoch.session_close_wall,
                             verdict=verdict, source_url=epoch.source_url))
    days = pd.DataFrame(observed)
    conclusive = [name for name in SEMANTICS if counts[name]]
    decision = conclusive[0] if len(conclusive) == 1 else 'inconclusive'
    return dict(root_code=row.root_code, contract_year=int(row.contract_year), expiry_code=row.expiry_code,
        input_path=str(path), file_name=path.name, sha256=row.sha256, n_rows=int(row.n_rows),
        period_start=2000+3*((int(row.contract_year)-2000)//3), timezone=timezone,
        n_days=len(days), n_days_interval_start=counts['interval_start'],
        n_days_interval_end=counts['interval_end'], n_days_inconclusive=counts['inconclusive'],
        n_days_without_schedule=counts['no_schedule'],
        modal_first_wall=days.first_wall.mode().iat[0] if len(days) else '',
        modal_last_wall=days.last_wall.mode().iat[0] if len(days) else '',
        schedule_source_url=days.source_url.iat[0] if len(days) else '',
        file_decision=decision), days.assign(input_path=str(path), root_code=row.root_code)


def material_support(support, minority_share, minority_days):
    kept, dropped = dict(support), {}
    present = [name for name in support if support[name]]
    if len(present) > 1:
        total = sum(support.values())
        minority = min(present, key=lambda name: support[name])
        count = support[minority]
        if count < minority_days or count/total < minority_share:
            kept[minority], dropped[minority] = 0, count
    return kept, dropped


def cell_decisions(files, minimum_days, minority_share=0.01, minority_days=3):
    rows = []
    for (root, period), g in files.groupby(['root_code', 'period_start']):
        observed = {name: int(g[f'n_days_{name}'].sum()) for name in SEMANTICS}
        support, dropped = material_support(observed, minority_share, minority_days)
        agreeing = [name for name in SEMANTICS if support[name]]
        decision = agreeing[0] if len(agreeing) == 1 and support[agreeing[0]] >= minimum_days else 'inconclusive'
        usable = g.iloc[:0]
        if decision in SEMANTICS:
            usable = g[g.file_decision.eq(decision) & g.n_rows.gt(0)].sort_values(
                [f'n_days_{decision}', 'input_path'], ascending=[False, True])
        sources = [s for s in g.schedule_source_url if str(s).strip()]
        rows.append(dict(root_code=root, period_start=int(period), bar_label_semantics=decision,
            n_files=len(g), n_days_interval_start=observed['interval_start'],
            n_days_interval_end=observed['interval_end'],
            n_days_discarded_minority=int(sum(dropped.values())),
            discarded_minority_verdicts='|'.join(f'{k}:{v}' for k, v in sorted(dropped.items())),
            minority_share_threshold=minority_share, minority_days_threshold=minority_days,
            n_days_inconclusive=int(g.n_days_inconclusive.sum()),
            n_days_without_schedule=int(g.n_days_without_schedule.sum()),
            minimum_days=minimum_days, evidence_source=sources[0] if sources else '',
            representative_sha256=usable.sha256.iat[0] if len(usable) else '',
            representative_file=usable.file_name.iat[0] if len(usable) else '',
            conflict=bool(support['interval_start'] and support['interval_end'])))
    return pd.DataFrame(rows).sort_values(['root_code', 'period_start']).reset_index(drop=True)


def session_evidence(primary, schedule_path, out, bar_minutes=5, minimum_days=20,
                     minority_share=0.01, minority_days=3):
    out = new_output(out)
    schedule = load_schedule(schedule_path)
    files, days = [], []
    for row in primary.itertuples():
        summary, observed = file_evidence(row, schedule, bar_minutes)
        files.append(summary)
        days.append(observed)
    files = pd.DataFrame(files)
    cells = cell_decisions(files, minimum_days, minority_share, minority_days)
    daily = pd.concat(days, ignore_index=True) if days else pd.DataFrame()
    schedule.to_csv(out/'trading_hours_used.csv', index=False)
    files.to_csv(out/'bar_label_files.csv', index=False)
    cells.to_csv(out/'bar_label_cells.csv', index=False)
    daily.to_csv(out/'bar_label_session_days.csv', index=False)
    status = dict(status='bar_label_session_evidence_not_promoted', created_utc=timestamp(),
        confirmation_outcomes_computed=False, method='session_boundary_only_no_announcement_window',
        bar_minutes=bar_minutes, minimum_days=minimum_days, n_files=len(files), n_cells=len(cells),
        n_cells_decided=int(cells.bar_label_semantics.isin(SEMANTICS).sum()),
        n_cells_conflicting=int(cells.conflict.sum()),
        schedule_sha256=digest(schedule_path), table_hashes={p.name: digest(p) for p in out.glob('*.csv')},
        code_hashes=code_hashes())
    dump(out/'status.json', status)
    print(json.dumps({k: v for k, v in status.items() if k not in ('code_hashes', 'table_hashes')}, indent=2), flush=True)
    return status


def promote(evidence_dir, output, reviewer, rule):
    evidence_dir = Path(evidence_dir)
    if not str(reviewer).strip() or not str(rule).strip():
        raise ValueError('PROMOTION_UNSIGNED: a reviewer name and a written rule are required')
    manifest = json.loads((evidence_dir/'status.json').read_text())
    if manifest.get('status') != 'bar_label_session_evidence_not_promoted':
        raise ValueError('Expected a session-evidence directory')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(evidence_dir/name) != expected:
            raise ValueError(f'Evidence table changed: {name}')
    cells = pd.read_csv(evidence_dir/'bar_label_cells.csv')
    decided = cells[cells.bar_label_semantics.isin(SEMANTICS) & ~cells.conflict].copy()
    if decided.representative_sha256.astype(str).str.len().ne(64).any():
        raise ValueError('Every promoted cell needs a 64-character representative hash')
    out = decided[['root_code', 'period_start', 'bar_label_semantics', 'evidence_source',
                   'representative_sha256']].copy()
    out['verified'] = True
    out['reviewer'] = reviewer
    out['promotion_rule'] = rule
    out = out[['root_code', 'period_start', 'verified', 'bar_label_semantics', 'evidence_source',
               'reviewer', 'representative_sha256', 'promotion_rule']]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(output, index=False)
    record = dict(status='bar_label_verified_by_named_reviewer', created_utc=timestamp(),
        reviewer=reviewer, rule=rule, method='session_boundary_only_no_announcement_window',
        evidence_status_sha256=digest(evidence_dir/'status.json'), output_sha256=digest(output),
        n_cells_total=len(cells), n_cells_promoted=len(out),
        n_cells_left_open=int(len(cells)-len(out)), code_hashes=code_hashes())
    dump(output.with_name(output.stem+'_promotion.json'), record)
    print(json.dumps({k: v for k, v in record.items() if k != 'code_hashes'}, indent=2), flush=True)
    return record
