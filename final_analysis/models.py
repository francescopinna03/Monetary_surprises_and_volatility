from __future__ import annotations
import numpy as np
import pandas as pd
from scipy import stats

class DesignGate(ValueError):
    pass

def holm(p):
    p = np.asarray(p, float); out = np.full(len(p), np.nan)
    valid = np.flatnonzero(np.isfinite(p)); order = valid[np.argsort(p[valid])]
    out[order] = np.minimum(1, np.maximum.accumulate(p[order] * np.arange(len(order),0,-1)))
    return out

def design(y, x, clusters, min_clusters=30):
    y, x = np.asarray(y,float), np.asarray(x,float)
    _, g = np.unique(np.asarray(clusters).astype(str), return_inverse=True)
    n, k = x.shape; G = g.max()+1
    if G < min_clusters or n <= k or not np.isfinite(x).all() or not np.isfinite(y).all():
        raise DesignGate(f'insufficient_or_nonfinite: n={n}, G={G}, k={k}')
    scale = np.sqrt(np.mean(x*x,axis=0)); scale[scale == 0] = 1
    z = x/scale
    if np.linalg.matrix_rank(z) < k:
        raise DesignGate(f'rank_deficient: rank={np.linalg.matrix_rank(z)}, k={k}')
    inv = np.linalg.inv(z.T@z); A = inv@z.T
    return y,z,g,scale,A,inv,(G/(G-1))*((n-1)/(n-k))

def clustered(y,x,clusters,min_clusters=30):
    y,z,g,scale,A,inv,cor = design(y,x,clusters,min_clusters)
    b = A@y; residual = y-z@b
    scores = np.zeros((g.max()+1,z.shape[1])); np.add.at(scores,g,z*residual[:,None])
    V = cor*inv@scores.T@scores@inv
    return dict(beta=b/scale,V=V/scale[:,None]/scale[None,:],residual=residual,G=g.max()+1,
                r2=1-residual@residual/np.sum((y-y.mean())**2))

def wild_test(y,x,clusters,columns,B,rng,min_clusters=30):
    y,z,g,scale,A,inv,cor = design(y,x,clusters,min_clusters)
    columns=np.asarray(columns,int); R=np.eye(z.shape[1])[columns]
    b=A@y
    restricted=b-inv@R.T@np.linalg.solve(R@inv@R.T,R@b)
    fitted=z@restricted; residual=y-fitted
    G=g.max()+1
    signs=rng.choice([-1.,1.],size=(G,B))
    ys=np.column_stack([y, fitted[:,None]+residual[:,None]*signs[g]])
    bs=A@ys; es=ys-z@bs
    scores=np.zeros((G,z.shape[1],B+1))
    np.add.at(scores,g,z[:,:,None]*es[:,None,:])
    influence=np.einsum('ik,gkb->gib',R@inv,scores)
    cov=cor*np.einsum('gib,gjb->bij',influence,influence)
    d=(R@bs).T
    if np.any(np.linalg.matrix_rank(cov) < len(columns)):
        raise DesignGate('singular_cluster_restriction_covariance')
    w=np.einsum('bi,bi->b',d,np.linalg.solve(cov,d[:,:,None])[:,:,0])/len(columns)
    p=(1+np.count_nonzero(w[1:] >= w[0]))/(B+1)
    return float(p),float(w[0]),w[1:]

def normal_matrix(t,kind,meta=None):
    p=t[f'log_{kind}_pre'].to_numpy(float); s=t.slow5_log_rv.to_numpy(float)
    trend=(t.trade_date-pd.Timestamp('2013-01-01')).dt.days.to_numpy()/365.25
    if meta is None: meta=np.array([np.mean(p),np.mean(s),np.mean(trend)])
    p=p-meta[0];s=s-meta[1];trend=trend-meta[2]
    X=np.column_stack([np.ones(len(t)),p,p*p,s,t.trade_date.ge('2022-07-21'),trend,
                       *[t.trade_date.dt.weekday.eq(i) for i in [0,1,2,4]],
                       *[t.trade_date.dt.month.eq(i) for i in range(2,13)]])
    return X.astype(float),meta

def counterfactual(w,spec,screen=False):
    w=w.copy(); diagnostics=[]
    for col in ['state_z','crossfit_state_z']+[p+k for k in ['BV','RV'] for p in ['cf_log_','abnormal_log_','crossfit_abnormal_log_']]:
        w[col]=np.nan
    screen_rows=w[w.phase.eq('PR')] if screen=='pr' else w
    excluded=screen_rows.groupby('trade_date').us_0830_candidate.max() if screen else None
    w['screen_ok']=~w.trade_date.map(excluded).fillna(False) if screen else True
    for phase in ['PR','PC']:
        for root in spec['robustness_roots']:
            ix=w.index[w.phase.eq(phase)&w.root_code.eq(root)]
            T=w.loc[ix]
            state_control=(~T.is_event)&T.screen_ok&T.pre_coverage.eq(1)&T.state_log_BV_pre.notna()
            state=T.loc[state_control,'state_log_BV_pre'];mu=state.mean();sd=state.std()
            if sd>0: w.loc[ix,'state_z']=(T.state_log_BV_pre-mu)/sd
            for kind in ['BV','RV']:
                cols=[f'log_{kind}_pre',f'log_{kind}_post','slow5_log_rv']
                ok=T.window_eligible&T.screen_ok&np.isfinite(T[cols]).all(axis=1)
                train=ok&~T.is_event
                if train.sum()<spec['minimum_controls']:
                    diagnostics.append(dict(phase=phase,root_code=root,outcome=kind,status='too_few_controls',n_controls=int(train.sum())))
                    continue
                X,meta=normal_matrix(T[train],kind)
                if np.linalg.matrix_rank(X)<X.shape[1]:
                    status='nuisance_rank_deficient_reported'
                else: status='ok'
                beta=np.linalg.lstsq(X,T.loc[train,f'log_{kind}_post'],rcond=None)[0]
                pred=normal_matrix(T[ok],kind,meta)[0]@beta
                w.loc[T.index[ok],f'cf_log_{kind}']=pred
                w.loc[T.index[ok],f'abnormal_log_{kind}']=T.loc[ok,f'log_{kind}_post']-pred
                losses=[]
                for year in sorted(T.trade_date.dt.year.unique()):
                    tr=train&T.trade_date.dt.year.ne(year);te=ok&T.trade_date.dt.year.eq(year)
                    if tr.sum()<spec['minimum_controls'] or not te.any():continue
                    Xtr,m=normal_matrix(T[tr],kind)
                    b=np.linalg.lstsq(Xtr,T.loc[tr,f'log_{kind}_post'],rcond=None)[0]
                    phat=normal_matrix(T[te],kind,m)[0]@b
                    w.loc[T.index[te],f'crossfit_abnormal_log_{kind}']=T.loc[te,f'log_{kind}_post']-phat
                    st=T.loc[state_control&T.trade_date.dt.year.ne(year),'state_log_BV_pre']
                    w.loc[T.index[te],'crossfit_state_z']=(T.loc[te,'state_log_BV_pre']-st.mean())/st.std()
                    actual=T.loc[te,f'log_{kind}_post'].to_numpy()
                    control=(~T.loc[te,'is_event']).to_numpy()
                    losses.extend((actual[control]-phat[control])**2)
                diagnostics.append(dict(phase=phase,root_code=root,outcome=kind,status=status,
                    n_controls=int(train.sum()),rank=int(np.linalg.matrix_rank(X)),n_parameters=X.shape[1],
                    control_loyo_rmse=float(np.sqrt(np.mean(losses))) if losses else np.nan))
    return w,pd.DataFrame(diagnostics)

def jk_rotation(M,q=.5):
    M=np.asarray(M,float)
    if len(M)<8 or not np.isfinite(M).all() or np.linalg.matrix_rank(M)<2:
        raise DesignGate('insufficient_rank_for_JK_rotation')
    Q,R=np.linalg.qr(M,mode='reduced');sgn=np.sign(np.diag(R));sgn[sgn==0]=1
    Q=Q*sgn;R=sgn[:,None]*R
    lo=np.arctan(R[0,1]/R[1,1]) if R[0,1]>0 else 0
    hi=np.pi/2 if R[0,1]>=0 else np.arctan(-R[1,1]/R[0,1])
    angle=(1-q)*lo+q*hi
    P=np.array([[np.cos(angle),np.sin(angle)],[-np.sin(angle),np.cos(angle)]])
    D=np.diag([R[0,0]*np.cos(angle),R[0,0]*np.sin(angle)])
    U=Q@P@D;C=np.linalg.solve(D,P.T@R)
    if not np.allclose(U@C,M) or not np.allclose(U.sum(axis=1),M[:,0]) or not C[0,1]<0<C[1,1]:
        raise DesignGate('JK reconstruction/sign failure')
    return U,C

def shock_indicators(w,ea,spec):
    nets=w.pivot(index=['trade_date','phase'],columns='root_code',values='net_post')
    flags=w.groupby(['trade_date','phase']).is_event.first()
    scales=nets[~flags].std()
    if not (scales[['fx','hf','hr']]>0).all():raise DesignGate('degenerate_curve_scale')
    z=nets/scales
    out=nets.reset_index()[['trade_date','phase']]
    out['schatz_aligned_u']=-z.hf.to_numpy();out['schatz_aligned_z']=z.fx.to_numpy()
    out['schatz_bobl_aligned_u']=-(z.hf+z.hr).to_numpy()/2
    out['schatz_bobl_aligned_z']=z.fx.to_numpy()
    source=ea.rename(columns={'event_date':'trade_date'})
    out=out.merge(source[['trade_date','phase','OIS_1M','OIS_1Y','STOXX50E','lag1','history3']],on=['trade_date','phase'],how='left',validate='one_to_one')
    out['ois1y_expost_u']=out.OIS_1Y/10;out['ois1y_expost_z']=out.STOXX50E
    for phase in ['PR','PC']:
        E=ea[ea.phase.eq(phase)&ea.event_date.ne('2008-10-08')].copy()
        ois=['OIS_1M','OIS_3M','OIS_6M','OIS_1Y'];ok=np.isfinite(E[ois]).all(axis=1)
        M=E.loc[ok,ois].to_numpy();sd=M.std(axis=0,ddof=1)
        if len(M)<8 or np.any(sd<=0): raise DesignGate('EA PCA scale/rank gate')
        Z=M/sd;_,_,vt=np.linalg.svd(Z,full_matrices=False);loading=vt[0]
        if loading[-1]<0:loading=-loading
        score=Z@loading;score=score/score.std(ddof=1)*M[:,-1].std(ddof=1)/10
        mapping=pd.Series(score,index=E.loc[ok,'event_date'])
        ix=out.phase.eq(phase)
        out.loc[ix,'ea_pc1_expost_u']=out.loc[ix,'trade_date'].map(mapping)
        out.loc[ix,'ea_pc1_expost_z']=out.loc[ix,'STOXX50E']
    return out,pd.DataFrame({'root_code':scales.index,'pooled_phase_control_sd':scales.values})

def quadratic(M,state,root):
    u,z=M[:,0],M[:,1]
    Q=np.column_stack([u*u,z*z,2*u*z])
    roots=sorted(pd.unique(root));F=np.column_stack([np.asarray(root)==r for r in roots[1:]]) if len(roots)>1 else np.empty((len(root),0))
    return np.column_stack([np.ones(len(M)),Q,state,Q*state[:,None],F]).astype(float)

def residual_partial_r2(y,base,block):
    r0=y-base@np.linalg.lstsq(base,y,rcond=None)[0]
    full=np.column_stack([base,block]);r1=y-full@np.linalg.lstsq(full,y,rcond=None)[0]
    den=r0@r0
    return float(1-r1@r1/den) if den>0 else np.nan

def finite_history(t,spec,rng,B):
    cols=['abnormal_log_BV','state_z','OIS_1M','lag1','history3']
    T=t[np.isfinite(t[cols]).all(axis=1)].copy()
    counts=T.groupby('trade_date').root_code.nunique()
    T=T[T.trade_date.isin(counts[counts==len(spec['primary_roots'])].index)]
    E=T.groupby('trade_date')[cols].mean().sort_index()
    if len(E)<spec['minimum_event_clusters']:raise DesignGate('history_event_sample_below_gate')
    y=E.abnormal_log_BV.to_numpy();eps=E.OIS_1M.to_numpy()/10;s=E.state_z.to_numpy()
    base=np.column_stack([np.ones(len(E)),eps,np.abs(eps),E.index>=pd.Timestamp('2022-07-21')]).astype(float)
    state=np.column_stack([s,eps*s,np.abs(eps)*s]);H=E[['lag1','history3']].to_numpy()
    model=np.column_stack([base,state]);full=np.column_stack([model,H]);g=E.index.astype(str)
    pr_state=residual_partial_r2(y,base,state);pr_history=residual_partial_r2(y,model,H)
    p,_,null=wild_test(y,full,g,range(model.shape[1],full.shape[1]),B,rng,spec['minimum_event_clusters'])
    boot=[]
    for _ in range(spec['power_replications']):
        ix=rng.integers(0,len(E),len(E))
        if np.linalg.matrix_rank(full[ix])==full.shape[1]:
            boot.append(residual_partial_r2(y[ix],model[ix],H[ix]))
    upper=float(np.quantile(boot,.95)) if boot else np.nan
    Hres=H-model@np.linalg.lstsq(model,H,rcond=None)[0]
    Hres=Hres/np.sqrt(np.mean(Hres*Hres,axis=0))
    fit0=model@np.linalg.lstsq(model,y,rcond=None)[0];errors=y-fit0
    sigma=np.sqrt(np.mean(errors*errors));critical=float(np.quantile(null,.95))
    power=[];n=len(y);rep=spec['power_replications']
    for direction in range(Hres.shape[1]):
        for r2 in spec['power_partial_r2_grid']:
            signal=sigma*np.sqrt(r2/(1-r2))*Hres[:,direction]
            reject=0
            for _ in range(rep):
                ys=fit0+signal+errors*rng.choice([-1,1],n)
                f=clustered(ys,full,g,spec['minimum_event_clusters'])
                d=f['beta'][-2:];v=f['V'][-2:,-2:]
                stat=d@np.linalg.solve(v,d)/2
                reject+=stat>critical
            power.append(dict(direction=direction+1,partial_r2=r2,rejection_rate=reject/rep,n_events=n,replications=rep))
    power=pd.DataFrame(power)
    floor=[]
    for direction,S in power.groupby('direction'):
        pwr=S.rejection_rate.to_numpy();z=stats.norm.ppf(.975)
        lower=(pwr+z*z/(2*rep)-z*np.sqrt(pwr*(1-pwr)/rep+z*z/(4*rep*rep)))/(1+z*z/rep)
        power.loc[S.index,'power_lower_95']=lower
        ok=S.partial_r2[(S.partial_r2>0)&(lower>=spec['power_target'])]
        floor.append(float(ok.min()) if len(ok) else np.nan)
    all_floors=np.isfinite(floor).all()
    decision='finite_history_not_resolved'
    if upper<spec['history_partial_r2_margin'] and all_floors and max(floor)<=spec['history_partial_r2_margin']:
        decision='specified_history_increment_below_margin_conditionally'
    return pd.DataFrame([dict(n_events=len(E),partial_r2_state=pr_state,partial_r2_history=pr_history,
        p_wild_history=p,history_partial_r2_upper95_percentile=upper,r2_80_worst_tested_direction=max(floor) if all_floors else np.nan,
        decision=decision,inference_scope='fixed_indicators_and_counterfactual_two_observed_history_variables')]),power
