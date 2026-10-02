import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
from zipfile import ZipFile, ZIP_DEFLATED
from facility_archive import digest, dump, split_archive, frozen_copy

REPO = Path(__file__).resolve().parent
BUILD_NAME = 'final_resume_20260911_174739_4124'


def matlab_binary():
    explicit = os.environ.get('MATLAB_BIN')
    candidates = ([explicit] if explicit else []) + [shutil.which('matlab')]
    candidates += [str(p) for p in sorted(Path('/Applications').glob('MATLAB_*.app/bin/matlab'), reverse=True)]
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    raise FileNotFoundError('MATLAB not available; set MATLAB_BIN to its executable. Python evidence can still run.')


def execute(command, log, env):
    with Path(log).open('w') as stream:
        with subprocess.Popen(command, cwd=REPO, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, bufsize=1) as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                stream.write(line); stream.flush()
            code = process.wait()
    if code:
        raise RuntimeError(f'Process exit {code}; see {log}')


def session_report(audit_dir, out):
    import pandas as pd
    from confirmation_analysis.bar_label import decide_day
    out.mkdir(parents=True, exist_ok=False)
    source = Path(audit_dir)/'sessions_v2.csv'
    sessions = pd.read_csv(source)
    primary = pd.read_csv(Path(audit_dir)/'primary_files_v2.csv')
    sessions = sessions[sessions.input_path.isin(primary.input_path)].copy()
    for name in ['first', 'last']:
        sessions[name+'_berlin'] = pd.to_datetime(sessions[name+'_label_utc'], utc=True).dt.tz_convert('Europe/Berlin').dt.strftime('%H:%M')
    sessions['month'] = sessions.trade_date.str[:7]
    pairs = sessions.groupby(['root_code','month','first_berlin','last_berlin']).size().rename('n_contract_days').reset_index()
    pairs.to_csv(out/'monthly_boundary_pairs.csv', index=False)
    transition = sessions[sessions.root_code.isin(['gg','hf','hr']) & sessions.last_berlin.ge('21:55')]
    transition.sort_values('trade_date').groupby('root_code').head(1).to_csv(out/'first_late_close.csv', index=False)
    supported = sessions[(sessions.trade_date.ge('2005-11-21') & sessions.trade_date.le('2005-12-31') & sessions.root_code.ne('fx')) |
                         (sessions.trade_date.ge('2011-01-01') & sessions.trade_date.le('2011-12-31'))].copy()
    supported['boundary_diagnostic'] = [decide_day(r.first_berlin, r.last_berlin,
        '07:50' if r.root_code == 'fx' else '08:00', '22:00', 5) for r in supported.itertuples()]
    supported.groupby(['root_code','boundary_diagnostic']).size().rename('n_contract_days').to_csv(out/'supported_epoch_diagnostic.csv')
    dump(out/'status.json', dict(status='metadata_diagnostics_only', source_sha256=digest(source),
        announcement_outcomes_computed=False, bar_labels_promoted=False,
        warning='Boundary diagnostics are not provider certification. Open/close endpoint prints can make both-convention comparisons inconclusive.'))


def shrinkage_summary(analysis, out):
    import numpy as np
    import pandas as pd
    rows = []
    for outcome, g in pd.read_csv(Path(analysis)/'shrinkage_cv_path.csv').groupby('depvar', sort=False):
        g = g.sort_values('lambda', ascending=False).reset_index(drop=True)
        best = g.cv_mse.idxmin()
        band = float(g.loc[best, 'cv_mse'] + g.loc[best, 'cv_se'])
        admissible = g[g.cv_mse.le(band)]
        strongest, weakest = float(admissible['lambda'].max()), float(admissible['lambda'].min())
        chosen = float(g.lambda_chosen.iloc[0])
        if not np.isclose(chosen, strongest, rtol=1e-10, atol=0):
            raise ValueError(f'1-SE rule violated for {outcome}: chosen {chosen}, strongest {strongest}')
        rows.append(dict(outcome=outcome, lambda_chosen=chosen, one_se_threshold=band,
            old_last_rule_lambda_on_same_cv=weakest, penalty_ratio=strongest/weakest if weakest else None,
            interpretation='Descriptive comparison of selection rules on this CV path; not April estimates'))
    pd.DataFrame(rows).to_csv(out,index=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--facility', type=Path, default=REPO.parent)
    parser.add_argument('--data-root', type=Path, default=Path.home()/'Desktop/Econometrics_data')
    parser.add_argument('--generation-build', type=Path)
    parser.add_argument('--recovery-root', type=Path,
        default=Path.home()/'Desktop/Monetary_surprises_FULL_rqjB5J/Econometrics_data')
    parser.add_argument('--mode', choices=['today','generation','repair','evidence','calibration'], default='today')
    args = parser.parse_args()
    facility, data = args.facility.expanduser().resolve(), args.data_root.expanduser().resolve()
    if REPO.parent != facility:
        raise ValueError('Run this code from Monetary_surprises_testing_facility/Monetary_surprises_clone')
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + str(os.getpid())
    out = facility/'runs'/('restart_'+stamp)
    out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PYTHONUNBUFFERED='1', OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1',
               FACILITY_CODE_ROOT=str(REPO), PYTHON_BIN=sys.executable, SURPRISE_SOURCE='EA_EMPD')
    stages = []
    def stage(name, function):
        print('\n>>> '+name, flush=True)
        try:
            function()
            stages.append(dict(stage=name, status='complete'))
            return True
        except Exception as exc:
            print(str(exc), flush=True)
            (out/(name+'_error.txt')).write_text(traceback.format_exc())
            stages.append(dict(stage=name, status='blocked_or_failed', error=str(exc)))
            return False
        finally:
            dump(out/'stages.json', stages)
    def python_stage(name, *arguments):
        execute([sys.executable, '-m', 'confirmation_analysis.run', *map(str, arguments)], out/(name+'.log'), env)
    def generation():
        candidates = ([args.generation_build.expanduser()] if args.generation_build else
            [data/'Raw/Certification'/BUILD_NAME, args.recovery_root.expanduser()/'Raw/Certification'/BUILD_NAME])
        build = next((p for p in candidates if (p/'status.json').is_file()), None)
        if build is None:
            raise FileNotFoundError('Frozen generation build missing. Checked: '+', '.join(map(str,candidates)))
        matlab = matlab_binary()
        local_data = out/'generation/Econometrics_data'
        local_build = frozen_copy(data, build, local_data, REPO, args.recovery_root.expanduser())
        genenv = dict(env, ECONOMETRICS_DATA_ROOT=str(local_data), FINAL_ANALYSIS_BUILD=str(local_build), FINAL_GENERATION_ONLY='1')
        execute([matlab, '-batch', "cd(getenv('FACILITY_CODE_ROOT')); disp(version); Run_final_matlab_checks"], out/'generation_matlab.log', genenv)
        shrinkage_summary(local_data/'Output/analysis', out/'shrinkage_1se_comparison.csv')
    def calibration():
        calenv = dict(env, STEP28_SBB_SPECIFICATION=str(REPO/'Raw/Certification/step28_sbb_specification_extended_calibration.csv'),
                      STEP28_CALIBRATION_OUTPUT=str(out/'step28_calibration'))
        calenv.pop('ECONOMETRICS_DATA_ROOT', None)
        calenv.pop('FINAL_ANALYSIS_BUILD', None)
        execute([matlab_binary(), '-batch', "cd(getenv('FACILITY_CODE_ROOT')); disp(version); Run_step28_calibration_only"], out/'step28_calibration.log', calenv)
    archive = facility/('Monetary_surprises_restart_'+stamp+'_results.zip')
    try:
        dump(out/'run_inputs.json', dict(facility=str(facility), data_root=str(data), mode=args.mode,
            code_hashes={str(p.relative_to(REPO)):digest(p) for p in sorted(REPO.rglob('*'))
                         if p.is_file() and p.suffix in {'.m','.py','.sh','.json'} and '.git' not in p.parts},
            confirmation_estimation_requested=False))
        separated = args.mode == 'calibration' or stage('archive_separation', lambda: split_archive(data, out/'archive', apply=True))
        if not separated:
            return 2
        if args.mode in ['today','generation','repair']:
            stage('generation_auxiliary', generation)
        if args.mode in ['generation','calibration']:
            stage('step28_synthetic_calibration', calibration)
        if args.mode in ['today','repair','evidence']:
            audit = out/'confirmation_inventory/audit'
            ok = stage('confirmation_inventory', lambda: python_stage('confirmation_inventory', 'audit',
                '--data-root',data,'--raw-dir',data/'Raw/Barchart_futures_confirmation','--output',audit))
            if ok:
                stage('session_boundaries', lambda: session_report(audit, out/'session_boundaries'))
                pass_name = 'confirmation_quality_second' if (data/'Raw/Certification/bar_label_evidence_v2.csv').is_file() else 'confirmation_quality_first'
                first = out/pass_name
                ok = stage(pass_name, lambda: python_stage(pass_name, 'quality',
                    '--audit-dir',audit,'--data-root',data,'--canonical-raw-dir',data/'Raw/Barchart_futures_confirmation','--output',first))
                schedule = REPO/'config/eurex_trading_hours.csv'
                if ok and schedule.is_file():
                    stage('bar_label_candidates', lambda: python_stage('bar_label_candidates', 'bar-label-evidence',
                        '--primary-files',first/'primary_files.csv','--schedule',schedule,'--output',out/'bar_label_candidates'))
                elif ok:
                    stages.append(dict(stage='bar_label_candidates', status='awaiting_reviewed_schedule',
                        path=str(schedule)))
                if ok:
                    stage('readiness', lambda: python_stage('readiness','readiness','--quality-dir',first,'--output',out/'readiness'))
        if args.mode == 'today':
            stage('step28_synthetic_calibration', calibration)
        return 2 if any(s['status']=='blocked_or_failed' for s in stages) else 0
    finally:
        dump(out/'status.json', dict(status='completed_requested_stages' if stages and all(s['status']=='complete' for s in stages) else 'completed_with_open_items',
             stages=stages, confirmation_freeze_performed=False, confirmation_estimation_performed=False))
        with ZipFile(archive,'w',ZIP_DEFLATED) as package:
            for path in sorted(out.rglob('*')):
                relative = path.relative_to(out)
                if not path.is_file() or 'Raw' in relative.parts or 'cleaned' in relative.parts:
                    continue
                package.write(path,str(relative))
        print('\nZIP da caricare: '+str(archive), flush=True)
        print('Freeze di conferma non eseguito. Leggere status.json e i risultati delle fasi completate.', flush=True)


if __name__ == '__main__':
    sys.exit(main())
