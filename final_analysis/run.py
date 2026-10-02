from __future__ import annotations
import argparse
import json
from pathlib import Path
import platform
import subprocess
from datetime import datetime, timezone
import numpy as np
import pandas as pd
import scipy
from .data import certify, build_windows, load_ea, sha256, read_dates, load_calendar
from .models import counterfactual, shock_indicators
from .battery import phase_battery, mean_battery

REPO=Path(__file__).resolve().parents[1]
SPEC=REPO/'Raw/Certification/final_analysis_spec_v1.json'

def dump(path,obj):
    path.write_text(json.dumps(obj,indent=2,sort_keys=True,default=str,allow_nan=False)+'\n')

def code_fingerprint():
    paths=sorted((REPO/'final_analysis').glob('*.py'))+[SPEC]
    return {str(p.relative_to(REPO)):sha256(p) for p in paths}

def freeze(root,destination):
    if destination.exists():raise FileExistsError(f'Refusing to replace frozen build: {destination}')
    spec,semantics,hashes=certify(root,SPEC)
    assert spec['bar_minutes']==5 and spec['minimum_return_coverage']==1
    destination.mkdir(parents=True)
    dump(destination/'status.json',dict(status='building',prior_results_seen=True))
    w,registry,candidates=build_windows(root,spec,semantics)
    ea=load_ea(root)
    indicators,scales=shock_indicators(w,ea,spec)
    registry=registry.merge(indicators,on=['trade_date','phase'],how='left',validate='many_to_one')
    for v in spec['phase_indicators']:
        registry[v+'_available']=np.isfinite(registry[[v+'_u',v+'_z']]).all(axis=1)
    registry['BV_log_available']=registry.BV_post.gt(0)&registry.price_status.eq('eligible')
    registry['RV_log_available']=registry.RV_post.gt(0)&registry.price_status.eq('eligible')
    q=pd.read_csv(root/'Output/diagnostics/contract_day_quality.csv')
    q['trade_date']=read_dates(q.trade_date).dt.normalize()
    selected=candidates[candidates.selected].rename(columns={'event_date':'trade_date'})
    preferred=selected.merge(q,on=['trade_date','root_code','file_name_clean'],validate='one_to_one')
    preferred['event_date']=preferred.trade_date
    preferred=preferred.merge(load_calendar(root),on='event_date',how='inner',validate='many_to_one')
    preferred['prelim_eligible']=preferred.pre_coverage.eq(1)
    for col in ['pr_datetime_utc','pc_datetime_utc']:
        preferred[col]=preferred[col].dt.strftime('%Y-%m-%d %H:%M:%S')
    tables={'preferred_contracts':preferred,'windows':w,'event_registry':registry,'contract_candidates':candidates,'indicators':indicators,'indicator_scales':scales,'ea_source':ea}
    for name,t in tables.items():t.to_csv(destination/(name+'.csv'),index=False)
    dump(destination/'specification.json',spec)
    dump(destination/'input_hashes.json',hashes)
    pd.DataFrame(hashes.items(),columns=['relative_path','sha256']).to_csv(destination/'input_hashes.csv',index=False)
    stamp=dict(schema_version=spec['schema_version'],status='frozen',created_utc=datetime.now(timezone.utc).isoformat(),
        code_hashes=code_fingerprint(),prior_results_seen=True,source_hashes=hashes,
        table_hashes={name+'.csv':sha256(destination/(name+'.csv')) for name in tables},
        specification_sha256=sha256(destination/'specification.json'),
        n_calendar_events=int(registry.trade_date.nunique()),n_root_phase_rows=len(registry),
        n_primary_eligible=int((registry.primary_asset&registry.price_status.eq('eligible')).sum()),
        us_calendar_status='provided_calendar' if (root/'Raw/Certification/us_releases.csv').exists() else 'candidate_screen_only')
    dump(destination/'status.json',stamp)
    print(json.dumps({k:v for k,v in stamp.items() if k not in ['code_hashes','source_hashes','table_hashes']},indent=2),flush=True)

def estimate(root,build,out,smoke=False):
    if out.exists():raise FileExistsError(f'Refusing to overwrite an analysis: {out}')
    manifest=json.loads((build/'status.json').read_text())
    if manifest['status']!='frozen':raise ValueError('Build did not finish')
    if manifest['code_hashes']!=code_fingerprint():raise ValueError('Code/spec changed after freeze; create a new build')
    _,_,hashes=certify(root,SPEC)
    if hashes!=manifest['source_hashes']:raise ValueError('Source data changed after freeze')
    for name,h in manifest['table_hashes'].items():
        if sha256(build/name)!=h:raise ValueError(f'Frozen table modified: {name}')
    if sha256(build/'specification.json')!=manifest['specification_sha256']:raise ValueError('Frozen specification modified')
    spec=json.loads((build/'specification.json').read_text())
    out.mkdir(parents=True)
    dump(out/'run_manifest.json',dict(status='running',mode='smoke' if smoke else 'frozen_full'))
    w=pd.read_csv(build/'windows.csv',parse_dates=['trade_date'])
    indicators=pd.read_csv(build/'indicators.csv',parse_dates=['trade_date'])
    ea=pd.read_csv(build/'ea_source.csv',parse_dates=['event_date'])
    rng=np.random.default_rng(spec['seed'])
    if smoke:
        spec=dict(spec,wild_cluster_draws=19,power_replications=19,
                  rotation_quantiles=[.5],leave_top_k=[0,1],power_partial_r2_grid=[0,.02,.1])
    B=spec['wild_cluster_draws']
    W,normal=counterfactual(w,spec)
    W.to_csv(out/'counterfactual_windows.csv',index=False);normal.to_csv(out/'normal_diagnostics.csv',index=False)
    mean,oos,history,power,mean_sample=mean_battery(W,ea,spec,rng,B)
    for name,t in [('mean_tests',mean),('mean_oos_predictions',oos),('finite_history',history),('history_power',power),('mean_sample_registry',mean_sample)]:
        t.to_csv(out/(name+'.csv'),index=False)
    phase,geometry,samples=phase_battery(W,indicators,spec,rng,B)
    for name,t in [('phase_tests',phase),('phase_geometry',geometry),('phase_sample_registry',samples)]:t.to_csv(out/(name+'.csv'),index=False)
    WS,normalS=counterfactual(w,spec,screen=True)
    normalS.to_csv(out/'us_screen_normal_diagnostics.csv',index=False)
    phaseS,geometryS,samplesS=phase_battery(WS,indicators,spec,rng,B,'exclude_0830_candidates')
    for name,t in [('us_screen_phase_tests',phaseS),('us_screen_phase_geometry',geometryS),('us_screen_sample_registry',samplesS)]:t.to_csv(out/(name+'.csv'),index=False)
    WPR,normalPR=counterfactual(w,spec,screen='pr')
    normalPR.to_csv(out/'us_pr_screen_normal_diagnostics.csv',index=False)
    meanPR,oosPR,historyPR,powerPR,mean_samplePR=mean_battery(WPR,ea,spec,rng,B)
    for name,t in [('mean_tests',meanPR),('mean_oos_predictions',oosPR),('finite_history',historyPR),('history_power',powerPR),('mean_sample_registry',mean_samplePR)]:
        t.to_csv(out/('us_pr_screen_'+name+'.csv'),index=False)
    flow=w[w.is_event].groupby(['phase','root_code']).agg(n_calendar_with_contract=('trade_date','nunique'),n_complete_windows=('window_eligible','sum'),n_candidate_overlaps=('us_0830_candidate','sum'),n_verified_overlaps=('verified_us_release','sum'))
    flow.to_csv(out/'event_flow.csv')
    exclusions=phase.groupby(['indicator','outcome','sample','universe','test'],dropna=False).status.value_counts().rename('n').reset_index()
    exclusions.to_csv(out/'model_gate_counts.csv',index=False)
    git_sha=subprocess.run(['git','rev-parse','HEAD'],cwd=REPO,text=True,capture_output=True).stdout.strip()
    dirty=bool(subprocess.run(['git','status','--porcelain'],cwd=REPO,text=True,capture_output=True).stdout)
    result=dict(status='complete_smoke_not_for_inference' if smoke else 'complete_conditional_inference',
        mode='smoke' if smoke else 'frozen_full',created_utc=datetime.now(timezone.utc).isoformat(),git_sha=git_sha,git_dirty=dirty,
        code_hashes=code_fingerprint(),build_manifest_sha256=sha256(build/'status.json'),draws=B,
        power_replications=spec['power_replications'],seed=spec['seed'],us_calendar_status=manifest['us_calendar_status'],
        primary_outcome=spec['outcome_primary'],bootstrap_scope=spec['bootstrap_scope'],
        python=platform.python_version(),numpy=np.__version__,pandas=pd.__version__,scipy=scipy.__version__,
        claim_gate='conditional_inference_only_macro_calendar_status_recorded',closed_extensions=spec['closed_extensions'])
    dump(out/'run_manifest.json',result)
    print(json.dumps(result,indent=2),flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=['freeze','estimate'])
    p.add_argument('--data-root',type=Path,required=True)
    p.add_argument('--build',type=Path,required=True)
    p.add_argument('--output',type=Path)
    p.add_argument('--smoke',action='store_true')
    a=p.parse_args();root=a.data_root.resolve();build=a.build.resolve()
    if a.mode=='freeze':
        if a.smoke: p.error('--smoke applies only to estimate')
        freeze(root,build)
    else:
        if a.output is None:p.error('--output is required for estimate')
        estimate(root,build,a.output.resolve(),a.smoke)

if __name__=='__main__':main()
