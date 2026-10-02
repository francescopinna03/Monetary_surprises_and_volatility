#!/usr/bin/env python3
import argparse
from pathlib import Path
import hashlib
import json
import numpy as np
import pandas as pd
from final_analysis.models import counterfactual, clustered
from confirmation_analysis.nuisance import counterfactual_v2
from confirmation_analysis.functional_form import design_with_state, degree2_basis, cone_means_numeric


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def control_slow(w):
    parts = []
    for root, t in w[w.phase.eq('PR')].groupby('root_code'):
        if t.trade_date.duplicated().any():
            raise ValueError('Duplicate root-days')
        ctrl = t[~t.is_event].sort_values('trade_date').copy()
        ctrl['slow_state_new'] = ctrl.log_day_rv.rolling(5, min_periods=5).mean()
        target = t[['trade_date']].sort_values('trade_date')
        j = pd.merge_asof(target, ctrl[['trade_date', 'slow_state_new']], on='trade_date',
                          direction='backward', allow_exact_matches=False)
        j['root_code'] = root
        parts.append(j)
    return w.merge(pd.concat(parts), on=['trade_date','root_code'], how='left', validate='many_to_one')


def prepare(generation, historical, bridge, out):
    generation, historical, bridge, out = map(Path, (generation, historical, bridge, out))
    gm = json.loads((generation/'status.json').read_text())
    hm = json.loads((historical/'estimated/run_manifest.json').read_text())
    hs = json.loads((historical/'frozen_manifest/specification.json').read_text())
    bm = json.loads((bridge/'bridge_decision.json').read_text())
    if gm['status'] != 'frozen' or hm['status'] != 'complete_reestimation_after_opening':
        raise ValueError('Requires frozen generation and already opened historical re-estimation')
    if bm['generation_build_manifest_sha256'] != sha(generation/'status.json'):
        raise ValueError('Generation build does not match the archived bridge')
    if hm['build_manifest_sha256'] != sha(historical/'frozen_manifest/status.json'):
        raise ValueError('Historical manifest mismatch')
    hstatus = json.loads((historical/'frozen_manifest/status.json').read_text())
    if sha(historical/'frozen_manifest/specification.json') != hstatus['specification_sha256']:
        raise ValueError('Historical specification hash mismatch')
    for name in ['windows.csv','ea_source.csv','specification.json']:
        expected = gm['specification_sha256'] if name == 'specification.json' else gm['table_hashes'][name]
        if sha(generation/name) != expected:
            raise ValueError('Generation file hash mismatch: '+name)
    model = Path(__file__).resolve().parent/'final_analysis/models.py'
    if sha(model) != gm['code_hashes']['final_analysis/models.py']:
        raise ValueError('Archived generation counterfactual code differs')
    w = pd.read_csv(generation/'windows.csv', parse_dates=['trade_date'])
    if not w.is_event.isin([True,False]).all() or (w.is_event & w.trade_date.lt('2013-01-01')).any():
        raise ValueError('Generation event dates/flags invalid')
    w = w[w.trade_date.between('2013-01-01','2025-12-31')].copy()
    ea = pd.read_csv(generation/'ea_source.csv', parse_dates=['event_date'])
    ea = ea[ea.phase.eq('PR') & ea.event_date.between('2013-01-01','2025-12-31')]
    gs = json.loads((generation/'specification.json').read_text())
    pr = w[w.phase.eq('PR')]
    nets = pr.pivot(index='trade_date',columns='root_code',values='net_post')
    flags = pr.groupby('trade_date').is_event.first()
    sd = float(nets.loc[~flags,'hf'].std())
    zsd = float((ea.STOXX50E/100).std())
    if not np.isclose(sd,bm['scales']['hf_pr_control_sd'],rtol=1e-12) or not np.isclose(zsd,bm['scales']['external_pr_generation_event_sd_fractional_return'],rtol=1e-12):
        raise ValueError('Bridge coordinate scales not reproduced')
    coords = nets.loc[flags,['hf','fx']].reset_index().merge(ea[['event_date','STOXX50E']],left_on='trade_date',right_on='event_date',validate='one_to_one')
    coords['u']=-coords.hf/sd; coords['z']=coords.STOXX50E/100/zsd
    coords = coords[np.isfinite(coords[['u','z','fx']]).all(axis=1)]
    normal,_ = counterfactual(w,gs)
    def event_panel(n):
        b = n[n.is_event & n.phase.eq('PR') & n.root_code.eq('gg')]
        t = coords[['trade_date','u','z']].merge(b[['trade_date','window_eligible','crossfit_state_z','crossfit_abnormal_log_BV','state_log_BV_pre']],on='trade_date',validate='one_to_one')
        return t[t.window_eligible & np.isfinite(t[['crossfit_state_z','crossfit_abnormal_log_BV']]).all(axis=1)].drop(columns='window_eligible').sort_values('trade_date').reset_index(drop=True)
    native_g = event_panel(normal)
    X = design_with_state(degree2_basis,native_g.u.to_numpy(),native_g.z.to_numpy(),native_g.crossfit_state_z.to_numpy())
    b = clustered(native_g.crossfit_abnormal_log_BV,X,native_g.trade_date)['beta']
    cone = cone_means_numeric(degree2_basis,b[1:4])
    old = pd.read_csv(bridge/'bridge_cone_tests.csv').query("source == 'ea_empd_stoxx50e'").set_index('hypothesis')
    for key, val in [('H1_MP_cone_mean',cone['mp']),('H2_MP_minus_CBI',cone['difference'])]:
        if not np.isclose(val,old.loc[key,'estimate'],rtol=1e-7,atol=1e-9):
            raise ValueError('Archived bridge estimate not reproduced: '+key)
    hw = pd.read_csv(historical/'estimated/counterfactual_windows.csv',parse_dates=['trade_date'])
    if not hw.is_event.isin([True,False]).all(): raise ValueError('Invalid historical event flags')
    native_h = pd.read_csv(historical/'estimated/primary_sample_registry.csv',parse_dates=['trade_date']).rename(columns={'u_primary':'u','z_primary':'z'})
    native_h = native_h.drop(columns=['input_path'],errors='ignore')
    if not native_h.trade_date.between('2000-01-01','2012-12-31').all(): raise ValueError('Invalid historical period')
    hnormal,_ = counterfactual_v2(hw,hs)
    hbund=hnormal[hnormal.is_event & hnormal.root_code.eq('gg') & hnormal.phase.eq('PR')]
    ht = native_h.merge(hbund[['trade_date','crossfit_abnormal_log_BV','crossfit_state_z','state_log_BV_pre']],on='trade_date',suffixes=('','_reproduced'),validate='one_to_one')
    for col in ['crossfit_abnormal_log_BV','crossfit_state_z']:
        if not np.allclose(ht[col],ht[col+'_reproduced'],rtol=1e-8,atol=1e-8): raise ValueError('Historical continuation not reproduced: '+col)
    native_h = ht.drop(columns=['crossfit_abnormal_log_BV_reproduced','crossfit_state_z_reproduced'])
    corrected_w = control_slow(w)
    corrected_w['slow5_log_rv'] = corrected_w.slow_state_new
    revised,_ = counterfactual(corrected_w,gs)
    revised_g = event_panel(revised)
    if set(revised_g.trade_date) != set(native_g.trade_date): raise ValueError('Harmonization changed generation sample; review exclusions first')
    controls = normal[(~normal.is_event) & normal.phase.eq('PR') & normal.root_code.eq('gg') & normal.pre_coverage.eq(1)]
    mu, sig = float(controls.state_log_BV_pre.mean()), float(controls.state_log_BV_pre.std())
    common_g = revised_g.copy()
    common_g['crossfit_state_z']=(common_g.state_log_BV_pre-mu)/sig
    common_h = native_h.copy()
    hpr=hw[hw.phase.eq('PR')]
    hnets=hpr.pivot(index='trade_date',columns='root_code',values='net_post')
    hflags=hpr.groupby('trade_date').is_event.first()
    hsd=float(hnets.loc[~hflags,'hf'].std())
    mapped=common_h.trade_date.map(hnets.hf)
    if not np.allclose(native_h.u,-mapped/hsd,atol=1e-10): raise ValueError('Historical PR-only Schatz scale not reproduced')
    common_h['u']=-mapped/sd
    common_h['z']=native_h.z*hs['external_scales']['stoxx50e_fraction']/zsd
    common_h['crossfit_state_z']=(common_h.state_log_BV_pre-mu)/sig
    for label,ww,tt in [('historical',hw,native_h),('generation',w,native_g)]:
        rows=ww[ww.phase.eq('PR') & ww.root_code.eq('gg') & ww.trade_date.isin(tt.trade_date)]
        if len(rows)!=len(tt) or not rows.post_coverage.eq(1).all() or not rows.n_post_returns.eq(5).all():
            raise ValueError(label+' PR window count/coverage mismatch')
    out.mkdir(parents=True,exist_ok=False)
    tables={'historical_native':native_h,'generation_native':native_g,'generation_harmonized_native_state':revised_g,'historical_common':common_h,'generation_common':common_g}
    for name,t in tables.items(): t.to_csv(out/(name+'.csv'),index=False)
    sources=[generation/n for n in ['status.json','specification.json','windows.csv','ea_source.csv']]+[historical/n for n in ['estimated/run_manifest.json','estimated/primary_sample_registry.csv','estimated/counterfactual_windows.csv','frozen_manifest/status.json','frozen_manifest/specification.json']]+[bridge/n for n in ['bridge_decision.json','bridge_cone_tests.csv']]
    delta=revised_g.crossfit_abnormal_log_BV-native_g.crossfit_abnormal_log_BV
    manifest={'status':'derived_from_already_opened_results','generation_events':len(native_g),'historical_events':len(native_h),'bridge_point_estimates_reproduced':cone,'historical_outcomes_reproduced':True,'common_scales':{'schatz_generation_pr_controls_sd':sd,'equity_generation_ea_event_sd':zsd,'state_generation_pr_control_mean':mu,'state_generation_pr_control_sd':sig},'native_historical_schatz_pr_sd':hsd,'generation_slow_state_change':{'mean_abs_outcome_change':float(np.abs(delta).mean()),'max_abs_outcome_change':float(np.abs(delta).max())},'source_hashes':{str(p):sha(p) for p in sources},'table_hashes':{p.name:sha(p) for p in out.glob('*.csv')},'raw_prices_read':False,'confirmation_pre_freeze_guard_modified':False,'inference_scope':'conditional on fixed normal outcomes, indicators and common target; after-opening exploratory','windows':'PR five returns ending +5,+10,+15,+20,+25 minutes; actual support (0,+25]; checked against archived definitions and counts, not re-certified from prices','limitations':['2013-2025 source is frozen September 11 generation build, NOT a fresh full pipeline run','historical source is September 15 after-opening re-estimation','EA external equity is the same source family in both periods; source window is not made identical to Schatz by scaling','inherited US release calendar remains candidate-only','cross-epoch state uses a fixed generation control scale; annual prediction diagnostics retain native leave-year-out state']}
    (out/'input_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k not in ['source_hashes','table_hashes']},indent=2))
    return manifest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for key in ['generation','historical','bridge','out']:p.add_argument('--'+key,required=True,type=Path)
    a=p.parse_args();prepare(a.generation,a.historical,a.bridge,a.out)
