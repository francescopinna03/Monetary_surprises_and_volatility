import argparse
import json
from pathlib import Path
import pandas as pd
from .audit import audit
from . import bar_label as barlabel
from .bridge import bridge
from .build import control_build
from .calibrate import calibrate
from . import ecb_calendar
from .decisions import DECISIONS, load_decisions, write_template
from .estimate import estimate
from .exploratory import exploratory
from .freeze import freeze
from .protocol import specification, resolution_gate, clock_reference
from .quality import quality_audit
from .readiness import report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    a = sub.add_parser('audit', help='Read timestamps, volume and EA covariates; never compute event outcomes')
    a.add_argument('--data-root', type=Path, required=True)
    a.add_argument('--raw-dir', type=Path, action='append')
    a.add_argument('--output', type=Path, required=True)
    b = sub.add_parser('bridge', help='Use only a previously frozen generation build')
    b.add_argument('--generation-build', type=Path, required=True)
    b.add_argument('--output', type=Path, required=True)
    b.add_argument('--draws', type=int, help='Override for generation-only diagnostics; always recorded')
    q = sub.add_parser('quality', help='Audit OHLC, exact price grids and pre-only selection; never compute event outcomes')
    q.add_argument('--audit-dir', type=Path, required=True)
    q.add_argument('--data-root', type=Path, required=True)
    q.add_argument('--output', type=Path, required=True)
    q.add_argument('--canonical-raw-dir', type=Path)
    q.add_argument('--candidate-semantics', choices=['interval_start', 'interval_end'], default='interval_start')
    r = sub.add_parser('readiness', help='Validate audit provenance and report all remaining blockers')
    r.add_argument('--quality-dir', type=Path, required=True)
    r.add_argument('--output', type=Path, required=True)
    r.add_argument('--bridge-dir', type=Path)
    r.add_argument('--build-dir', type=Path)
    r.add_argument('--calibration-dir', type=Path)
    cc = sub.add_parser('calendar-candidates', help='Resolve the ECB annual indices; writes candidates, never verified rows')
    cc.add_argument('--data-root', type=Path, required=True)
    cc.add_argument('--output', type=Path, required=True)
    cc.add_argument('--first-year', type=int, default=2000)
    cc.add_argument('--last-year', type=int, default=2012)
    cc.add_argument('--cache-dir', type=Path, help='Archive of fetched pages; defaults to OUTPUT/pages')
    cc.add_argument('--ordinary-sample', type=int, default=20, help='Random ordinary rows opened to validate the extractor')
    cp = sub.add_parser('calendar-promote', help='Promote reviewed candidates under a written rule and a named reviewer')
    cp.add_argument('--candidates', type=Path, required=True)
    cp.add_argument('--reviewed-queue', type=Path, required=True)
    cp.add_argument('--output', type=Path, required=True)
    cp.add_argument('--reviewer', required=True)
    cp.add_argument('--rule', required=True)
    th = sub.add_parser('trading-hours-template', help='Write the published Eurex schedule template; never fills it in')
    th.add_argument('--output', type=Path, default=Path('config/eurex_trading_hours.csv'))
    bl = sub.add_parser('bar-label-evidence', help='Decide bar-label semantics at the session boundary, not at an announcement')
    bl.add_argument('--primary-files', type=Path, required=True, help='primary_files.csv from the quality audit')
    bl.add_argument('--schedule', type=Path, default=Path('config/eurex_trading_hours.csv'))
    bl.add_argument('--output', type=Path, required=True)
    bl.add_argument('--minimum-days', type=int, default=20)
    bp = sub.add_parser('bar-label-promote', help='Write bar_label_evidence_v2.csv from decided session evidence')
    bp.add_argument('--evidence', type=Path, required=True)
    bp.add_argument('--output', type=Path, required=True)
    bp.add_argument('--reviewer', required=True)
    bp.add_argument('--rule', required=True)
    d = sub.add_parser('decisions-template', help='Write the reviewed-decisions template; never fills it in')
    d.add_argument('--output', type=Path, default=DECISIONS)
    c = sub.add_parser('control-build', help='Protected build: controls and event pre-quantities only')
    c.add_argument('--quality-dir', type=Path, required=True)
    c.add_argument('--data-root', type=Path, required=True)
    c.add_argument('--output', type=Path, required=True)
    c.add_argument('--generation-build', type=Path, help='Optional: slow-state validation on generation data')
    k = sub.add_parser('calibrate', help='Outcome-free power calibration on the protected build')
    k.add_argument('--build', type=Path, required=True)
    k.add_argument('--output', type=Path, required=True)
    k.add_argument('--bridge-dir', type=Path)
    f = sub.add_parser('freeze', help='Construct confirmation outcomes once and freeze the specification')
    f.add_argument('--quality-dir', type=Path, required=True)
    f.add_argument('--data-root', type=Path, required=True)
    f.add_argument('--build', type=Path, required=True)
    f.add_argument('--calibration', type=Path, required=True)
    f.add_argument('--bridge-dir', type=Path, required=True)
    f.add_argument('--destination', type=Path, required=True)
    f.add_argument('--already-opened', type=Path, help='Frozen build whose outcomes were already estimated; marks this build as a re-estimation')
    e = sub.add_parser('estimate', help='Estimate the frozen v2 build')
    e.add_argument('--build', type=Path, required=True)
    e.add_argument('--output', type=Path, required=True)
    e.add_argument('--smoke', action='store_true')
    x = sub.add_parser('exploratory', help='Post-opening analyses on an already-opened frozen build')
    x.add_argument('--build', type=Path, required=True)
    x.add_argument('--output', type=Path, required=True)
    x.add_argument('--calibration', type=Path)
    x.add_argument('--smoke', action='store_true')
    sub.add_parser('check-protocol', help='Report unresolved pre-freeze gates')
    args = parser.parse_args()
    if args.mode == 'audit':
        audit(args.data_root, args.raw_dir or [args.data_root/'Raw/Barchart_futures_confirmation'], args.output)
    elif args.mode == 'bridge':
        bridge(args.generation_build, args.output, args.draws)
    elif args.mode == 'quality':
        quality_audit(args.audit_dir, args.data_root, args.output, args.canonical_raw_dir, args.candidate_semantics)
    elif args.mode == 'readiness':
        report(args.quality_dir, args.output, args.bridge_dir, args.build_dir, args.calibration_dir)
    elif args.mode == 'calendar-candidates':
        ecb_calendar.build_candidates(args.data_root, args.output, range(args.first_year, args.last_year+1),
                                      args.cache_dir, ordinary_sample=args.ordinary_sample)
    elif args.mode == 'calendar-promote':
        ecb_calendar.promote(args.candidates, args.reviewed_queue, args.output, args.reviewer, args.rule)
    elif args.mode == 'trading-hours-template':
        print('Template written:', barlabel.write_schedule_template(args.output))
    elif args.mode == 'bar-label-evidence':
        barlabel.session_evidence(pd.read_csv(args.primary_files), args.schedule, args.output,
                                  minimum_days=args.minimum_days)
    elif args.mode == 'bar-label-promote':
        barlabel.promote(args.evidence, args.output, args.reviewer, args.rule)
    elif args.mode == 'decisions-template':
        print('Template written:', write_template(args.output))
    elif args.mode == 'control-build':
        control_build(args.quality_dir, args.data_root, args.output, specification(), args.generation_build)
    elif args.mode == 'calibrate':
        calibrate(args.build, args.output, specification(), args.bridge_dir)
    elif args.mode == 'freeze':
        freeze(args.quality_dir, args.data_root, args.build, args.calibration, args.bridge_dir,
               args.destination, specification(), args.already_opened)
    elif args.mode == 'estimate':
        estimate(args.build, args.output, args.smoke)
    elif args.mode == 'exploratory':
        exploratory(args.build, args.output, args.calibration, args.smoke)
    else:
        spec = specification(); family = spec['primary_family']
        try:
            decisions = {k: v['choice'] for k, v in load_decisions().items()}
        except ValueError as exc:
            decisions = str(exc)
        result = dict(status=spec['status'], confirmation_estimation_enabled=False, decisions=decisions,
            historical_clock_tests=bool(clock_reference().passed.all()),
            primary_resolution=resolution_gate(family['draws'], family['size'], family['alpha']),
            blocking_items=spec['required_before_freeze'])
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
