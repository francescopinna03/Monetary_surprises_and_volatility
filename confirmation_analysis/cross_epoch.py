import numpy as np
import pandas as pd
from scipy.spatial import ConvexHull
from final_analysis.models import design, clustered
from .inference import wild_contrast
from .functional_form import BASES, PHI, design_with_state, sector_masks

VERSION = 'cross_epoch_v1_20260916'


def holm_fixed(values):
    p=np.asarray(values,float)
    q=np.where(np.isfinite(p),p,1.)
    order=np.argsort(q,kind='stable')
    out=np.empty(len(q));out[order]=np.minimum(1,np.maximum.accumulate(q[order]*np.arange(len(q),0,-1)))
    return out


def wild_t_interval(y,X,groups,c,draws,seed,batch=256):
    y,z,g,scale,A,inv,cor=design(y,X,groups,30)
    r=np.asarray(c,float)/scale
    b=A@y;res=y-z@b;v=z@(inv@r)
    G=int(g.max()+1)
    scores=np.zeros(G);np.add.at(scores,g,v*res)
    se=float(np.sqrt(cor*scores@scores));estimate=float(r@b)
    if not se>0:raise ValueError('Degenerate observed standard error')
    rng=np.random.default_rng(seed);ts=[]
    for start in range(0,draws,batch):
        n=min(batch,draws-start)
        signs=rng.choice([-1.,1.],size=(n,G)).T
        ys=(z@b)[:,None]+res[:,None]*signs[g]
        bs=A@ys;es=ys-z@bs
        scores=np.zeros((G,n));np.add.at(scores,g,v[:,None]*es)
        ses=np.sqrt(cor*np.sum(scores*scores,axis=0))
        if np.any(ses<=0) or not np.isfinite(ses).all(): raise ValueError('Degenerate bootstrap standard error')
        ts.extend(((r@bs-estimate)/ses).tolist())
    lo,hi=np.quantile(ts,[.025,.975])
    return {'ci95_low':float(estimate-hi*se),'ci95_high':float(estimate-lo*se),
            'ci_method':'unrestricted meeting wild bootstrap-t; pointwise; conditional on target and design'}


def contrast_result(y,X,g,c,draws,seed):
    r=wild_contrast(y,X,g,c,draws,np.random.default_rng(seed),alternative='two-sided',min_clusters=30)
    return {**r,**wild_t_interval(y,X,g,c,draws,seed+100000),
            'status':'exploratory_after_opening','scope':'conditional on measured indicators and fitted normal continuation; no generated-regressor or target uncertainty'}


def cone_contrast(fn,radius=1.,state=0.):
    u,z=radius*np.cos(PHI),radius*np.sin(PHI)
    X=design_with_state(fn,u,z,np.full(len(u),state))
    mp,cbi,_=sector_masks(u,z)
    return X[mp].mean(axis=0)-X[cbi].mean(axis=0)


def symmetric_decomposition(d_h,d_g,b_h,b_g):
    composition=(d_g-d_h)@((b_g+b_h)/2)
    response=((d_g+d_h)/2)@(b_g-b_h)
    total=d_g@b_g-d_h@b_h
    return {'composition':float(composition),'response':float(response),'total':float(total)}


def common_support(H,G,min_cell=8):
    T=pd.concat([H.assign(era='2000_2012'),G.assign(era='2013_2025')],ignore_index=True)
    mp,cbi,axis=sector_masks(T.u.to_numpy(),T.z.to_numpy())
    T['sector']=np.where(mp,'MP',np.where(cbi,'CBI','axis'))
    W=np.column_stack([np.abs(T.u),np.abs(T.z),T.crossfit_state_z])
    scale=W.std(axis=0,ddof=1)
    if np.any(scale<=0):raise ValueError('Degenerate support coordinates')
    W=W/scale;keep=~axis;reports=[]
    for era in ['2000_2012','2013_2025']:
        for sector in ['MP','CBI']:
            ix=T.era.eq(era).to_numpy() & T.sector.eq(sector).to_numpy()
            if ix.sum()<min_cell or np.linalg.matrix_rank(W[ix]-W[ix].mean(axis=0))<3:
                T['common_support']=False
                return T,pd.DataFrame([{'era':era,'sector':sector,'status':'insufficient_full_dimensional_cell','n_original':int(ix.sum())}]),False
            hull=ConvexHull(W[ix])
            inside=np.all(W@hull.equations[:,:3].T+hull.equations[:,3]<=1e-9,axis=1)
            keep &= inside
    T['common_support']=keep
    for era in ['2000_2012','2013_2025']:
        for sector in ['MP','CBI','axis']:
            ix=T.era.eq(era) & T.sector.eq(sector)
            reports.append({'era':era,'sector':sector,'n_original':int(ix.sum()),'n_common_support':int((ix & T.common_support).sum()),
                            'status':'geometric_overlap_only_not_a_density_test'})
    gate=all(r['n_common_support']>=min_cell for r in reports if r['sector']!='axis')
    return T,pd.DataFrame(reports),gate


def target_contrast(fn,T):
    cs=[]
    for (era,sector),t in T[T.common_support].groupby(['era','sector'],sort=True):
        u=np.abs(t.u.to_numpy());z=np.abs(t.z.to_numpy());s=t.crossfit_state_z.to_numpy()
        cs.append((design_with_state(fn,u,-z,s)-design_with_state(fn,u,z,s)).mean(axis=0))
    if len(cs)!=4:raise ValueError('All four support cells required')
    return np.mean(cs,axis=0)


def cross_epoch(H,G,draws=19999,seed=20260916):
    for label,t in [('historical',H),('generation',G)]:
        if t.trade_date.duplicated().any() or not np.isfinite(t[['u','z','crossfit_state_z','crossfit_abnormal_log_BV']]).all().all():
            raise ValueError('Invalid '+label+' event sample')
    if not H.trade_date.between('2000-01-01','2012-12-31').all() or not G.trade_date.between('2013-01-01','2025-12-31').all():
        raise ValueError('Overlapping or incorrect era dates')
    support,counts,gate=common_support(H,G)
    results=[];standardized=[];decompositions=[];gap_rows=[]
    y=np.r_[H.crossfit_abnormal_log_BV,G.crossfit_abnormal_log_BV]
    dates=pd.concat([H.trade_date,G.trade_date],ignore_index=True).astype(str)
    for model,(name,fn) in enumerate(BASES.items()):
        Xh=design_with_state(fn,H.u.to_numpy(),H.z.to_numpy(),H.crossfit_state_z.to_numpy())
        Xg=design_with_state(fn,G.u.to_numpy(),G.z.to_numpy(),G.crossfit_state_z.to_numpy())
        X=np.block([[Xh,np.zeros_like(Xh)],[np.zeros_like(Xg),Xg]])
        fit=clustered(y,X,dates);bh,bg=fit['beta'][:8],fit['beta'][8:]
        c=cone_contrast(fn)
        for j,(label,C) in enumerate([('2000_2012',np.r_[c,np.zeros(8)]),('2013_2025',np.r_[np.zeros(8),c]),('later_minus_earlier',np.r_[-c,c])]):
            results.append({'basis':name,'comparison':label,'functional':'uniform-angular MP minus CBI at common radius 1, common state 0',
                            **contrast_result(y,X,dates,C,draws,seed+model*100+j)})
        if gate:
            cstar=target_contrast(fn,support)
            for j,(label,C) in enumerate([('2000_2012',np.r_[cstar,np.zeros(8)]),('2013_2025',np.r_[np.zeros(8),cstar]),('later_minus_earlier',np.r_[-cstar,cstar])]):
                standardized.append({'basis':name,'comparison':label,'functional':'same empirical abs(u),abs(z),state in shared folded convex hull; equal weight to four era-sector cells',
                                     **contrast_result(y,X,dates,C,draws,seed+model*100+j+20)})
        else:
            for label in ['2000_2012','2013_2025','later_minus_earlier']:
                standardized.append({'basis':name,'comparison':label,'status':'not_estimable_common_support_gate','p_wild':np.nan})
        for subset in ['all_sector_events','common_support']:
            if subset=='common_support' and not gate:continue
            ds=[];observed=[]
            for era,t,xx in [('2000_2012',H,Xh),('2013_2025',G,Xg)]:
                target=support[support.era.eq(era)]
                use=np.ones(len(t),bool) if subset=='all_sector_events' else target.common_support.to_numpy()
                mp,cbi,_=sector_masks(t.u.to_numpy(),t.z.to_numpy())
                a,b=mp&use,cbi&use
                ds.append(xx[a].mean(axis=0)-xx[b].mean(axis=0))
                obs=float(t.crossfit_abnormal_log_BV[a].mean()-t.crossfit_abnormal_log_BV[b].mean());observed.append(obs)
                gap_rows.append({'basis':name,'subset':subset,'era':era,'n_mp':int(a.sum()),'n_cbi':int(b.sum()),'observed_sector_gap':obs,'fitted_sector_gap':float(ds[-1]@(bh if era=='2000_2012' else bg))})
            dh,dg=ds
            d=symmetric_decomposition(dh,dg,bh,bg)
            for j,(term,C) in enumerate([('composition',np.r_[(dg-dh)/2,(dg-dh)/2]),('response',np.r_[-(dg+dh)/2,(dg+dh)/2])]):
                r=contrast_result(y,X,dates,C,draws,seed+model*100+40+j+(10 if subset=='common_support' else 0))
                decompositions.append({'basis':name,'subset':subset,'component':term,'total_fitted_gap_change':d['total'],'observed_gap_change':observed[1]-observed[0],
                                       'residual_gap_change':observed[1]-observed[0]-d['total'],**r,
                                       'note':'Exact symmetric decomposition of fitted gaps, not causality. Targets and support fixed. Full sample includes extrapolation; restricted sample still imposes functional form.'})
    tables={'common_metric_cone_tests':pd.DataFrame(results),'common_support_standardized_tests':pd.DataFrame(standardized),'composition_decomposition':pd.DataFrame(decompositions),
            'sector_gaps':pd.DataFrame(gap_rows),'common_support_counts':counts,'common_support_registry':support}
    for name in ['common_metric_cone_tests','common_support_standardized_tests','composition_decomposition']:
        t=tables[name];t['p_holm_exploratory_family']=holm_fixed(t.p_wild);t['family_size']=len(t)
    for t in tables.values():t['diagnostic_version']=VERSION
    return tables
