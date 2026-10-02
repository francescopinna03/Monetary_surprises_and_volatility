import numpy as np
import pandas as pd


def normal_matrix_v2(t, kind, meta=None, origin='2000-01-01'):
    p = t[f'log_{kind}_pre'].to_numpy(float)
    s = t.slow_state.to_numpy(float)
    trend = (t.trade_date - pd.Timestamp(origin)).dt.days.to_numpy()/365.25
    if meta is None:
        meta = np.array([np.mean(p), np.mean(s), np.mean(trend)])
    p, s, trend = p-meta[0], s-meta[1], trend-meta[2]
    X = np.column_stack([np.ones(len(t)), p, p*p, s, trend,
                         *[t.trade_date.dt.weekday.eq(i) for i in [0, 1, 2, 4]],
                         *[t.trade_date.dt.month.eq(i) for i in range(2, 13)]])
    return X.astype(float), meta


def counterfactual_v2(w, spec, screen=False):
    w = w.copy()
    diagnostics = []
    for col in ['state_z', 'crossfit_state_z'] + [p+k for k in ['BV', 'RV']
                                                  for p in ['cf_log_', 'abnormal_log_', 'crossfit_abnormal_log_']]:
        w[col] = np.nan
    screen_rows = w[w.phase.eq('PR')] if screen == 'pr' else w
    excluded = screen_rows.groupby('trade_date').us_0830_candidate.max() if screen else None
    w['screen_ok'] = ~w.trade_date.map(excluded).fillna(False) if screen else True
    for phase in ['PR', 'PC']:
        for root in spec['roots']:
            ix = w.index[w.phase.eq(phase) & w.root_code.eq(root)]
            if not len(ix):
                continue
            T = w.loc[ix]
            state_control = (~T.is_event) & T.screen_ok & T.pre_coverage.eq(1) & T.state_log_BV_pre.notna()
            state = T.loc[state_control, 'state_log_BV_pre']
            mu, sd = state.mean(), state.std()
            if sd > 0:
                w.loc[ix, 'state_z'] = (T.state_log_BV_pre-mu)/sd
            for kind in ['BV', 'RV']:
                cols = [f'log_{kind}_pre', f'log_{kind}_post', 'slow_state']
                ok = T.window_eligible & T.screen_ok & np.isfinite(T[cols]).all(axis=1)
                train = ok & ~T.is_event
                if train.sum() < spec['minimum_controls']:
                    diagnostics.append(dict(phase=phase, root_code=root, outcome=kind,
                                            status='too_few_controls', n_controls=int(train.sum())))
                    continue
                X, meta = normal_matrix_v2(T[train], kind)
                rank = int(np.linalg.matrix_rank(X))
                status = 'ok' if rank == X.shape[1] else 'nuisance_rank_deficient_reported'
                beta = np.linalg.lstsq(X, T.loc[train, f'log_{kind}_post'], rcond=None)[0]
                pred = normal_matrix_v2(T[ok], kind, meta)[0] @ beta
                w.loc[T.index[ok], f'cf_log_{kind}'] = pred
                w.loc[T.index[ok], f'abnormal_log_{kind}'] = T.loc[ok, f'log_{kind}_post']-pred
                losses = []
                for year in sorted(T.trade_date.dt.year.unique()):
                    tr = train & T.trade_date.dt.year.ne(year)
                    te = ok & T.trade_date.dt.year.eq(year)
                    if tr.sum() < spec['minimum_controls'] or not te.any():
                        continue
                    Xtr, m = normal_matrix_v2(T[tr], kind)
                    b = np.linalg.lstsq(Xtr, T.loc[tr, f'log_{kind}_post'], rcond=None)[0]
                    phat = normal_matrix_v2(T[te], kind, m)[0] @ b
                    w.loc[T.index[te], f'crossfit_abnormal_log_{kind}'] = T.loc[te, f'log_{kind}_post']-phat
                    st = T.loc[state_control & T.trade_date.dt.year.ne(year), 'state_log_BV_pre']
                    if st.std() > 0:
                        w.loc[T.index[te], 'crossfit_state_z'] = (T.loc[te, 'state_log_BV_pre']-st.mean())/st.std()
                    actual = T.loc[te, f'log_{kind}_post'].to_numpy()
                    control = (~T.loc[te, 'is_event']).to_numpy()
                    losses.extend((actual[control]-phat[control])**2)
                diagnostics.append(dict(phase=phase, root_code=root, outcome=kind, status=status,
                    n_controls=int(train.sum()), rank=rank, n_parameters=X.shape[1],
                    control_loyo_rmse=float(np.sqrt(np.mean(losses))) if losses else np.nan))
    return w, pd.DataFrame(diagnostics)
