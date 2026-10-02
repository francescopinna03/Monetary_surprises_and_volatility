#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import shutil
import sys
import zipfile
import numpy as np
import pandas as pd
import scipy
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parents[1]))
from confirmation_analysis.functional_form import functional_form, BASES, design_with_state, basis_comparison
from confirmation_analysis.cross_epoch import cross_epoch, cone_contrast, contrast_result, holm_fixed

REPO=Path(__file__).resolve().parents[1]

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def run(inputs,out,draws=19999):
    inputs,out=Path(inputs),Path(out)
    m=json.loads((inputs/'input_manifest.json').read_text())
    if m.get('status')!='derived_from_already_opened_results':raise ValueError('Opened, audited input bundle required')
    if draws<199 or int(draws)!=draws:raise ValueError('At least 199 integer draws required; production uses 19999')
    for name,h in m['table_hashes'].items():
        if Path(name).name!=name or sha(inputs/name)!=h:raise ValueError('Input hash mismatch: '+name)
    protocol=inputs/'analysis_protocol.json'
    if not protocol.is_file():raise ValueError('Declared exploratory comparison protocol required')
    names=['historical_native','generation_native','generation_harmonized_native_state','historical_common','generation_common']
    ts={n:pd.read_csv(inputs/(n+'.csv'),parse_dates=['trade_date']) for n in names}
    for n,t in ts.items():
        lo,hi=('2000-01-01','2012-12-31') if n.startswith('historical') else ('2013-01-01','2025-12-31')
        if not t.trade_date.between(lo,hi).all() or t.trade_date.duplicated().any() or not np.isfinite(t[['u','z','crossfit_state_z','crossfit_abnormal_log_BV']]).all().all():raise ValueError('Invalid period/event table: '+n)
    out.mkdir(parents=True,exist_ok=False)
    (out/'inputs').mkdir()
    for p in inputs.iterdir():
        if p.suffix in ['.csv','.json']:shutil.copy2(p,out/'inputs'/p.name)
    code=['scripts/Run_cross_epoch_checks.py','scripts/Prepare_cross_epoch_inputs.py','confirmation_analysis/cross_epoch.py','confirmation_analysis/functional_form.py','confirmation_analysis/inference.py','confirmation_analysis/cones.py','confirmation_analysis/nuisance.py','final_analysis/models.py']
    for name in code:
        dest=out/'executed_code'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(REPO/name,dest)
    manifest={'status':'running','created_utc':datetime.now(timezone.utc).isoformat(),'draws':draws,'seed':20260916,'profile':'full' if draws==19999 else 'smoke_only','inference_scope':'exploratory after opening; conditional on precomputed outcomes, regressors, support and targets','raw_prices_read':False,'code_sha256':{n:sha(REPO/n) for n in code},'input_manifest_sha256':sha(inputs/'input_manifest.json'),'analysis_protocol_sha256':sha(protocol),'python':sys.version,'numpy':np.__version__,'pandas':pd.__version__,'scipy':scipy.__version__,'platform':platform.platform(),'source_limitations':m['limitations']}
    def save_manifest(): (out/'run_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    save_manifest()
    try:
        spec={'minimum_event_clusters':30}
        for n in ['historical_native','generation_native','generation_harmonized_native_state']:
            print('Functional diagnostics: '+n,flush=True)
            folder=out/n;folder.mkdir()
            tables=functional_form(ts[n],spec,'u','z',draws,20260912+7000)
            for label,t in tables.items():t.to_csv(folder/(label+'.csv'),index=False)
            rows=[];T=ts[n];y=T.crossfit_abnormal_log_BV.to_numpy();g=T.trade_date.astype(str)
            for j,(basis,fn) in enumerate(BASES.items()):
                X=design_with_state(fn,T.u.to_numpy(),T.z.to_numpy(),T.crossfit_state_z.to_numpy())
                r=contrast_result(y,X,g,cone_contrast(fn),draws,20260916+j*100)
                rows.append({'basis':basis,'functional':'MP minus CBI at own-era metric, r=1 and native state=0',**r})
            tab=pd.DataFrame(rows);tab['p_holm_exploratory_4']=holm_fixed(tab.p_wild);tab.to_csv(folder/'native_cone_tests.csv',index=False)
        for n in ['historical_common','generation_common']:
            folder=out/n;folder.mkdir()
            fits,paired,summary=basis_comparison(ts[n],spec,'u','z')
            fits.to_csv(folder/'basis_fits.csv',index=False);paired.to_csv(folder/'basis_paired_annual_errors.csv',index=False)
            pd.DataFrame([summary]).to_csv(folder/'basis_summary.csv',index=False)
        print('Direct epoch contrasts and composition diagnostics',flush=True)
        tables=cross_epoch(ts['historical_common'],ts['generation_common'],draws=draws,seed=20260916)
        for label,t in tables.items():t.to_csv(out/(label+'.csv'),index=False)
        manifest['status']='complete_exploratory_cross_epoch';manifest['completed_utc']=datetime.now(timezone.utc).isoformat()
        manifest['table_sha256']={str(p.relative_to(out)):sha(p) for p in out.rglob('*.csv')}
        save_manifest()
    except BaseException as exc:
        manifest['status']='failed';manifest['error']=repr(exc);save_manifest();raise
    zip_path=out.with_name(out.name+'_results.zip')
    with zipfile.ZipFile(zip_path,'x',zipfile.ZIP_DEFLATED) as z:
        for p in out.rglob('*'):
            if p.is_file():z.write(p,p.relative_to(out))
    print('Completed: '+str(zip_path),flush=True)
    return out


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--inputs',required=True,type=Path);p.add_argument('--out',type=Path);p.add_argument('--draws',type=int,default=19999)
    a=p.parse_args();out=a.out or REPO.parent/'runs'/('cross_epoch_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
    run(a.inputs,out,a.draws)
