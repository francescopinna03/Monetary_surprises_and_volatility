from __future__ import annotations
import numpy as np
import pandas as pd
from .models import (DesignGate, clustered, wild_test, jk_rotation, quadratic,
                     holm, finite_history, normal_matrix)

def paired(t, columns, roots):
    T=t[t.root_code.isin(roots)&t.is_event&t.window_eligible].copy()
    T=T[np.isfinite(T[columns]).all(axis=1)]
    n=T.groupby(['trade_date','root_code']).phase.nunique()
    keys=n[n==2].index
    return T.set_index(['trade_date','root_code']).loc[keys].reset_index().sort_values(['trade_date','root_code','phase'])

def test_row(t,X,columns,label,meta,spec,rng,B):
    y=t[meta['outcome']].to_numpy(float);g=t.trade_date.astype(str).to_numpy()
    try:
        fit=clustered(y,X,g,spec['minimum_event_clusters'])
        p,stat,_=wild_test(y,X,g,columns,B,rng,spec['minimum_event_clusters'])
        beta=fit['beta'][columns[0]] if len(columns)==1 else np.nan
        se=np.sqrt(fit['V'][columns[0],columns[0]]) if len(columns)==1 else np.nan
        return dict(**meta,test=label,status='estimated',n_rows=len(t),n_clusters=fit['G'],p_wild=p,
                    beta=beta,se_cr1=se,wald_f=stat,bootstrap_scope=spec['bootstrap_scope'])
    except DesignGate as exc:
        return dict(**meta,test=label,status=str(exc),n_rows=len(t),n_clusters=t.trade_date.nunique(),p_wild=np.nan,beta=np.nan,se_cr1=np.nan)

def qdesign(t,u,z):
    X=quadratic(t[[u,z]].to_numpy(),t.state_z.to_numpy(),t.root_code.to_numpy())
    return np.column_stack([X,t.trade_date.ge('2022-07-01')]).astype(float)

def rotated(t,u,z,q):
    T=t.copy()
    for phase in ['PR','PC']:
        E=T[T.phase.eq(phase)].drop_duplicates('trade_date').sort_values('trade_date')
        U,_=jk_rotation(E[[u,z]].to_numpy(),q)
        mp=pd.Series(U[:,0],index=E.trade_date);cbi=pd.Series(U[:,1],index=E.trade_date)
        ix=T.phase.eq(phase)
        T.loc[ix,'mp']=T.loc[ix,'trade_date'].map(mp)
        T.loc[ix,'cbi']=T.loc[ix,'trade_date'].map(cbi)
    return T

def phase_geometry(t,X,spec,meta,rng,B):
    y=t[meta['outcome']].to_numpy();g=t.trade_date.astype(str)
    fit=clustered(y,X,g,spec['minimum_event_clusters'])
    nblock=X.shape[1]//2
    level=fit['beta'][nblock+1:nblock+4];slope=fit['beta'][nblock+5:nblock+8]
    shocks=t.drop_duplicates(['trade_date','phase'])[['u','z']].to_numpy()
    covariance=np.cov(shocks.T);ev,U=np.linalg.eigh(covariance)
    if np.min(ev)<=0:raise DesignGate('degenerate_pooled_shock_covariance')
    sqrt=U@np.diag(np.sqrt(ev))@U.T
    def geom(b,state):
        d=b[nblock+1:nblock+4]+state*b[nblock+5:nblock+8]
        A=np.array([[d[0],d[2]],[d[2],d[1]]]);values=np.linalg.eigvalsh(sqrt@A@sqrt)
        return values[0],values[1]
    dates,idx=np.unique(g,return_inverse=True);A=np.linalg.pinv(X)
    residual=y-X@fit['beta']; samples=[]
    for _ in range(B):
        b=fit['beta']+A@(residual*rng.choice([-1.,1.],len(dates))[idx])
        samples.append([geom(b,state) for state in spec['state_levels']])
    samples=np.asarray(samples);rows=[]
    for i,state in enumerate(spec['state_levels']):
        low,high=geom(fit['beta'],state)
        interval=np.quantile(samples[:,i,:],[.025,.975],axis=0)
        rows.append(dict(**meta,state=state,eigenvalue_min=low,eigenvalue_max=high,
            eigenvalue_min_ci_low=interval[0,0],eigenvalue_min_ci_high=interval[1,0],
            eigenvalue_max_ci_low=interval[0,1],eigenvalue_max_ci_high=interval[1,1],
            interpretation='rotation_invariant_descriptive_geometry_fixed_shock_covariance_no_sector_dominance_claim'))
    return rows

def phase_battery(w,indicators,spec,rng,B,screen_name='all_events'):
    T=w.merge(indicators,on=['trade_date','phase'],how='left',validate='many_to_one')
    T=T[T.screen_ok].copy()
    rows=[];geometry=[];samples=[]
    for outcome in ['abnormal_log_BV','abnormal_log_RV']:
        allcoords=[f'{v}_{c}' for v in spec['phase_indicators'] for c in ['u','z']]
        common=paired(T,[outcome,'state_z']+allcoords,spec['primary_roots'])
        commonkeys=set(zip(common.trade_date,common.root_code))
        for indicator in spec['phase_indicators']:
            u,z=indicator+'_u',indicator+'_z'
            for universe,roots in [('primary_fx_gg',spec['primary_roots']),('four_root_sensitivity',spec['robustness_roots'])]:
                S=paired(T,[outcome,'state_z',u,z],roots).rename(columns={u:'u',z:'z'})
                variants=[('available_paired',S)]
                if universe=='primary_fx_gg':
                    variants.append(('common_all_indicators',S[[k in commonkeys for k in zip(S.trade_date,S.root_code)]]))
                for sample,S in variants:
                    meta=dict(indicator=indicator,outcome=outcome,screen=screen_name,universe=universe,sample=sample,
                              family='primary_phase' if indicator=='schatz_aligned' and outcome=='abnormal_log_BV' and universe=='primary_fx_gg' and sample=='available_paired' and screen_name=='all_events' else 'phase_sensitivity')
                    for r in S[['trade_date','root_code','phase']].itertuples(index=False):
                        samples.append(dict(**meta,trade_date=r.trade_date,root_code=r.root_code,phase=r.phase))
                    if not len(S):
                        rows.append(dict(**meta,test='phase_surface',status='empty_paired_sample',p_wild=np.nan));continue
                    base=qdesign(S,'u','z');pc=S.phase.eq('PC').to_numpy(float)
                    X=np.column_stack([base,base*pc[:,None]])
                    cols=[base.shape[1]+j for j in [1,2,3,5,6,7]]
                    rows.append(test_row(S,X,cols,'phase_surface',meta,spec,rng,B))
                    if universe!='primary_fx_gg' or sample!='available_paired':continue
                    if rows[-1]['status']=='estimated':
                        try: geometry.extend(phase_geometry(S,X,spec,meta,rng,B))
                        except DesignGate as exc: geometry.append(dict(**meta,status=str(exc)))
                    try: median=rotated(S,'u','z',.5)
                    except DesignGate as exc:
                        rows.append(dict(**meta,test='rotation_gate',status=str(exc),p_wild=np.nan));continue
                    ev=median.drop_duplicates(['trade_date','phase']).copy()
                    rankings={
                        'total':ev.assign(energy=ev.u**2+ev.z**2).groupby('trade_date').energy.sum(),
                        'mp':ev.assign(energy=ev.mp**2).groupby('trade_date').energy.sum(),
                        'cbi':ev.assign(energy=ev.cbi**2).groupby('trade_date').energy.sum()}
                    for ranking,energies in rankings.items():
                        ordered=energies.sort_values(ascending=False,kind='stable').index
                        for k in spec['leave_top_k']:
                            if k==0 and ranking!='total':continue
                            U=S[~S.trade_date.isin(ordered[:k])].copy()
                            quantiles=spec['rotation_quantiles'] if k==0 else [.5]
                            for q in quantiles:
                                try:V=rotated(U,'u','z',q)
                                except DesignGate as exc:
                                    rows.append(dict(**meta,test='trim_rotation_gate',ranking=ranking,top_k=k,rotation=q,status=str(exc),p_wild=np.nan));continue
                                for phase in ['PR','PC']:
                                    P=V[V.phase.eq(phase)]
                                    XP=qdesign(P,'mp','cbi')
                                    for col,label in [(1,'mp_energy'),(2,'cbi_energy'),(5,'mp_state_slope'),(6,'cbi_state_slope')]:
                                        m=dict(meta,phase=phase,ranking=ranking,top_k=k,rotation=q,family='component_sensitivity')
                                        rows.append(test_row(P,XP,[col],label,m,spec,rng,B))
                            if k>0:
                                b=qdesign(U,'u','z');XP=np.column_stack([b,b*U.phase.eq('PC').to_numpy()[:,None]])
                                m=dict(meta,ranking=ranking,top_k=k,family='influence_sensitivity')
                                rows.append(test_row(U,XP,[b.shape[1]+j for j in [1,2,3,5,6,7]],'phase_surface',m,spec,rng,B))
            print(f'Phase tests: {indicator}, {outcome}, {screen_name}',flush=True)
    R=pd.DataFrame(rows)
    if len(R):
        R['p_holm']=R.groupby('family',dropna=False).p_wild.transform(lambda x:holm(x.to_numpy()))
    return R,pd.DataFrame(geometry),pd.DataFrame(samples)

def mean_matrix(t,form,scope=''):
    eps=t.OIS_1M.to_numpy(float)/10
    if form=='absolute':eps=np.abs(eps)
    s=t[scope+'state_z'].to_numpy(float)
    return np.column_stack([np.ones(len(t)),eps,s,eps*s,t.trade_date.ge('2022-07-01'),t.root_code.eq('gg')]).astype(float)

def mean_oos(w,ea,spec,kind,form):
    T=w[w.phase.eq('PR')&w.root_code.isin(spec['primary_roots'])&w.screen_ok].copy()
    T=T.merge(ea[ea.phase.eq('PR')][['event_date','OIS_1M']],left_on='trade_date',right_on='event_date',how='left',validate='many_to_one')
    predictions=[]
    for year in sorted(T[T.is_event].trade_date.dt.year.unique()):
        E=[]
        for root,G in T.groupby('root_code'):
            cols=[f'log_{kind}_pre',f'log_{kind}_post','slow5_log_rv']
            valid=G.window_eligible&np.isfinite(G[cols]).all(axis=1)
            train=valid&~G.is_event&G.trade_date.dt.year.ne(year)
            event=valid&G.is_event&G.OIS_1M.notna()
            if train.sum()<spec['minimum_controls']:continue
            X,m=normal_matrix(G[train],kind);b=np.linalg.lstsq(X,G.loc[train,f'log_{kind}_post'],rcond=None)[0]
            V=G[event].copy();V['y']=V[f'log_{kind}_post']-normal_matrix(V,kind,m)[0]@b
            st=(~G.is_event)&G.screen_ok&G.pre_coverage.eq(1)&G.trade_date.dt.year.ne(year)
            sd=G.loc[st,'state_log_BV_pre'].std();mu=G.loc[st,'state_log_BV_pre'].mean()
            V['state_z']=(V.state_log_BV_pre-mu)/sd
            E.append(V)
        if not E:continue
        E=pd.concat(E);tr=E.trade_date.dt.year.ne(year);te=~tr
        if E.loc[tr,'trade_date'].nunique()<spec['minimum_event_clusters'] or not te.any():continue
        Xtr=mean_matrix(E[tr],form);Xte=mean_matrix(E[te],form)
        if np.linalg.matrix_rank(Xtr)<Xtr.shape[1]:continue
        full=Xte@np.linalg.lstsq(Xtr,E.loc[tr,'y'],rcond=None)[0]
        keep=[0,1,4,5]
        baseline=Xte[:,keep]@np.linalg.lstsq(Xtr[:,keep],E.loc[tr,'y'],rcond=None)[0]
        for j,(_,row) in enumerate(E[te].iterrows()):
            predictions.append(dict(trade_date=row.trade_date,root_code=row.root_code,outcome='abnormal_log_'+kind,
                form=form,actual=row.y,prediction_state=full[j],prediction_baseline=baseline[j],fold_year=int(year)))
    return pd.DataFrame(predictions)

def mean_battery(w,ea,spec,rng,B):
    T=w[w.phase.eq('PR')&w.is_event&w.window_eligible&w.screen_ok&w.root_code.isin(spec['primary_roots'])].copy()
    T=T.merge(ea[ea.phase.eq('PR')][['event_date','OIS_1M','lag1','history3']],left_on='trade_date',right_on='event_date',how='left',validate='many_to_one')
    rows=[];oos=[];samples=[]
    for kind in ['BV','RV']:
        outcome='abnormal_log_'+kind
        P=T[np.isfinite(T[[outcome,'state_z','OIS_1M']]).all(axis=1)].copy()
        ranking=P.drop_duplicates('trade_date').assign(energy=lambda s:s.OIS_1M.abs()).sort_values(['energy','trade_date'],ascending=[False,True]).trade_date
        for form in ['signed','absolute']:
            for k in spec['leave_top_k']:
                S=P[~P.trade_date.isin(ranking.iloc[:k])]
                meta=dict(outcome=outcome,form=form,top_k=k,family='primary_mean' if kind=='BV' and k==0 else 'mean_sensitivity')
                rows.append(test_row(S,mean_matrix(S,form),[3],'surprise_state_interaction',meta,spec,rng,B))
                for r in S[['trade_date','root_code']].itertuples(index=False):samples.append(dict(**meta,trade_date=r.trade_date,root_code=r.root_code))
            oos.append(mean_oos(w,ea,spec,kind,form))
    R=pd.DataFrame(rows)
    R['p_holm']=R.groupby('family').p_wild.transform(lambda x:holm(x.to_numpy()))
    try:history,power=finite_history(T,spec,rng,B)
    except DesignGate as exc:
        history=pd.DataFrame([dict(decision=str(exc))]);power=pd.DataFrame()
    return R,pd.concat(oos,ignore_index=True),history,power,pd.DataFrame(samples)
