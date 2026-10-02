import argparse
from pathlib import Path
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
PAPER = REPO/'reference_outputs'/'paper'
CROSS = REPO/'reference_outputs'/'cross_epoch_20260916'
LABELS = {'H_2000_2012': 'ECB 2000--2012', 'G_2013_2025': 'ECB 2013--2025', 'FED_2008_2026': 'FOMC 2008--2026'}


def f(x, d=3):
    return '' if x is None or not np.isfinite(float(x)) else f'{float(x):.{d}f}'


def write(out, name, header, rows, caption, label, note=''):
    body = '\n'.join(' & '.join(r)+r' \\' for r in rows)
    tex = ('\\begin{table}[H]\\centering\\small\n\\caption{'+caption+'}\\label{'+label+'}\n\\resizebox{\\textwidth}{!}{\\begin{tabular}{l'
           + 'r'*(len(header)-1)+'}\\toprule\n'+' & '.join(header)+r' \\'+'\\midrule\n'+body+'\n\\bottomrule\\end{tabular}}\n'
           + ('\\begin{minipage}{0.95\\textwidth}\\footnotesize\\vspace{2pt} '+note+'\\end{minipage}\n' if note else '')+'\\end{table}\n')
    (out/f'{name}.tex').write_text(tex)


def mean_branch(out):
    rows = []
    for key, lab in [('historical_native', 'ECB 2000--2012'), ('generation_harmonized_native_state', 'ECB 2013--2025')]:
        m = pd.read_csv(CROSS/key/'mean_branch_with_equity.csv').set_index('term')
        rows.append([lab, f(m.loc['abs_u', 'estimate']), f(m.loc['abs_u', 'p_wild']), f(m.loc['abs_z', 'estimate']), f(m.loc['abs_z', 'p_wild']), f(m.loc['u', 'p_wild']), f(m.loc['z', 'p_wild'])])
    r = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_mean_branch.csv')
    r = r[r.measure.eq('BV') & r.period.eq('all')].iloc[0]
    rows.append(['FOMC 2008--2026', f(r.abs_u_estimate), f(r.abs_u_p_wild), f(r.abs_z_estimate), f(r.abs_z_p_wild), f(r.u_p_wild), f(r.z_p_wild)])
    write(out, 'meanbranch', ['Sample', '$|u|$', '$p$', '$|z|$', '$p$', '$p$ for $u$', '$p$ for $z$'], rows,
          'Mean branch with both coordinates: coefficients on the absolute and signed coordinates.', 'tab:meanbranch')


def basis(out):
    rows = []
    for key, lab in [('historical_native', 'ECB 2000--2012'), ('generation_harmonized_native_state', 'ECB 2013--2025')]:
        b = pd.read_csv(CROSS/key/'basis_summary.csv').iloc[0]
        rows.append([lab, f(b.mean_mse_degree2), f(b.mean_mse_degree1), f(b.mean_mse_quadratic_angles_radial1), f'{int(b.folds_won_by_degree1)}/{int(b.n_folds)}'])
    b = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_basis_summary.csv')
    b = b[b.measure.eq('BV')].iloc[0]
    rows.append(['FOMC 2008--2026', f(b.mean_mse_degree2), f(b.mean_mse_degree1), f(b.mean_mse_quadratic_angles_radial1), f'{int(b.folds_won_by_degree1)}/{int(b.n_folds)}'])
    write(out, 'basis', ['Sample', 'Quadratic, $r^2$', 'Absolute, $r$', 'Quadratic angles, $r$', 'Years won by $r$'], rows,
          'Leave-one-year-out mean squared prediction error of three radial bases.', 'tab:basis')


def minute(out):
    m = pd.read_csv(PAPER/'ecb_minute_20260928'/'minute_robustness_measures.csv')
    order = ['BV5_from_1min', 'BV', 'BV_excl1', 'BV_excl5', 'RV', 'MedRV', 'MinRV', 'TBV_postwindow', 'VOL']
    rows = []
    for meas in order:
        row = [meas.replace('_', ' ')]
        for smp in ['H_2000_2012', 'G_2013_2025']:
            x = m[m['sample'].eq(smp) & m.measure.eq(meas)].iloc[0]
            row += [str(int(x.n_events)), f(x.abs_u_estimate), f(x.abs_u_p_wild), f(x.abs_z_estimate), f(x.abs_z_p_wild), f'{int(x.folds_won_by_degree1)}/13']
        rows.append(row)
    write(out, 'minute', ['Measure']+['$n$', '$|u|$', '$p$', '$|z|$', '$p$', '$r$ wins']*2, rows,
          'One-minute outcomes, ECB 2000--2012 (left) and 2013--2025 (right).', 'tab:minute')


def exponent_and_elasticity(out):
    e = pd.read_csv(PAPER/'ecb_design_information_20260928'/'radial_exponent_profile.csv').assign()
    fe = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_radial_exponent_profile.csv').assign(sample='FED_2008_2026')
    mc = pd.read_csv(PAPER/'measurement_check_20260930'/'measurement_check.csv').set_index(['sample', 'measure'])
    spec = [('H_2000_2012', 'BV'), ('H_2000_2012', 'BV_excl5'), ('H_2000_2012', 'VOL'), ('G_2013_2025', 'BV'), ('G_2013_2025', 'BV_excl5'), ('G_2013_2025', 'VOL'), ('FED_2008_2026', 'BV'), ('FED_2008_2026', 'VOL')]
    rows_e, rows_l = [], []
    for smp, meas in spec:
        src = fe if smp == 'FED_2008_2026' else e
        q = src[src['sample'].eq(smp) & src.measure.eq(meas) & src.angular_basis.eq('quadratic_angles')].iloc[0]
        lab = f'{LABELS[smp]}, {meas.replace("_", " ")}'
        rows_e.append([lab, str(int(q.n_events)), f(q.exponent_hat, 2), f'{q.lr_interval_low:.2f}--{q.lr_interval_high:.2f}', f(q.lr_at_exponent_1, 1), f(q.lr_at_exponent_2, 1), f(q.cv_mse_exponent_1), f(q.cv_mse_exponent_2)])
        iv = mc.loc[(smp, meas)] if (smp, meas) in mc.index else None
        ivc = [f(iv.elasticity_ols, 2), f(iv.elasticity_iv, 2)+' ('+f(iv.se_iv_hc1, 2)+')', f(iv.first_stage_f, 0)] if iv is not None and np.isfinite(iv.get('elasticity_iv', np.nan)) else ['--', '--', '--']
        rows_l.append([lab, f(q.mean_elasticity_log_radius, 2)+' ('+f(q.mean_elasticity_se_cr1, 2)+')']+ivc)
    write(out, 'exponent', ['Sample and measure', '$n$', '$\\hat p$', '95\\% LR interval', 'LR at 1', 'LR at 2', 'CV error at 1', 'CV error at 2'], rows_e,
          'Radial exponent: point estimate, likelihood-ratio interval and out-of-sample errors at exponents one and two.', 'tab:exponent')
    write(out, 'elasticity', ['Sample and measure', 'Angular mean (SE)', 'Isotropic OLS', 'Isotropic IV (SE)', 'First-stage $F$'], rows_l,
          'Mean elasticity under the logarithmic law, least squares and instrumented.', 'tab:elasticity')


def measurement(out):
    rows = []
    for r in pd.read_csv(PAPER/'measurement_check_20260930'/'measurement_check.csv').itertuples():
        need = 'none on the grid' if not np.isfinite(r.noise_multiple_needed) else f(r.noise_multiple_needed, 2)
        rows.append([LABELS[r.sample], r.measure.replace('_', ' '), str(int(r.n_tail)), f(r.exponent_tail, 2), f(r.lr_at_1_tail, 2), f(r.observed_exponent, 2), need, r.verdict.replace('_', ' ')])
    write(out, 'measurement', ['Sample', 'Measure', '$n$ tail', 'Tail $\\hat p$', 'LR at 1', 'Full $\\hat p$', 'Noise multiple needed', 'Verdict'], rows,
          'Measurement-error check.', 'tab:measurement')


def fomc(out):
    d = PAPER/'fomc_replication_20260929'
    rows = [[r.id, f(r.estimate), f(r.p_one_sided, 4), f(r.p_holm, 4), 'yes' if r.rejected_at_5pct else 'no'] for r in pd.read_csv(d/'fed_primary_family.csv').itertuples()]
    write(out, 'fedfamily', ['Test', 'Estimate', 'One-sided $p$', 'Holm $p$', 'Rejected at 5\\%'], rows, 'Pre-registered family on the FOMC sample.', 'tab:fedfamily')
    fm = pd.read_csv(d/'fed_mean_branch.csv'); rows = []
    for meas in ['BV', 'BV25', 'RV', 'MedRV', 'MinRV', 'VOL']:
        for per in ['all', 'zero_lower_bound', 'positive_rates']:
            r = fm[fm.measure.eq(meas) & fm.period.eq(per)].iloc[0]
            rows.append([meas if per == 'all' else '', per.replace('_', ' '), str(int(r.n_events)), f(r.abs_u_estimate), f(r.abs_u_p_wild), f(r.abs_z_estimate), f(r.abs_z_p_wild)])
    write(out, 'feddesc', ['Measure', 'Period', '$n$', '$|u|$', '$p$', '$|z|$', '$p$'], rows, 'FOMC sample, descriptive mean branch by measure and period.', 'tab:feddesc')
    rows = [[r.measure, str(int(r.n_events)), f(r.abs_u_estimate), f(r.abs_u_p_wild), f(r.abs_z_estimate), f(r.abs_z_p_wild)]
            for r in pd.read_csv(PAPER/'fomc_post_replication_20260930'/'fed_post_replication_split.csv').itertuples()]
    write(out, 'fedpost', ['Measure', '$n$', '$|u|$', '$p$', '$|z|$', '$p$'], rows, 'FOMC sample, post-replication split of the window.', 'tab:fedpost')


def sector_and_symmetry(out):
    si = pd.read_csv(PAPER/'ecb_design_information_20260928'/'sector_contrast_information.csv')
    fs = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_sector_contrast_information.csv').assign(sample='FED_2008_2026')
    rows = []
    for df, smp in [(si, 'H_2000_2012'), (si, 'G_2013_2025'), (fs, 'FED_2008_2026')]:
        q = df[df['sample'].eq(smp) & df.measure.eq('BV') & df.angular_basis.eq('quadratic_angles') & df.radial_exponent.eq(1.0)].iloc[0]
        rows.append([LABELS[smp], str(int(q.n_mp)), str(int(q.n_cbi)), f(q.mp_minus_cbi), f(q.se_cr1), f(q.information_retention_vs_independent_signs, 2), f'{q.meetings_for_80pct_power_observed_design:,.0f}'])
    write(out, 'sector', ['Sample', '$n$ policy', '$n$ information', 'Policy minus information', 'SE', 'Retention', 'Meetings for 80\\% power'], rows,
          'Sector contrast at unit amplitude and the meetings required to detect it.', 'tab:sector')
    od = pd.read_csv(PAPER/'ecb_design_information_20260928'/'central_symmetry_odd_block.csv')
    fo = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_central_symmetry_odd_block.csv').assign(sample='FED_2008_2026')
    rows = [[LABELS[r.sample], r.measure.replace('_', ' '), str(int(r.n_events)), f(r.partial_r2_odd_block), f(r.p_wild_joint_odd_block)] for r in pd.concat([od, fo]).itertuples()]
    write(out, 'odd', ['Sample', 'Measure', '$n$', 'Partial $R^2$ of signed block', 'Joint wild $p$'], rows, 'Central symmetry.', 'tab:odd')
    jd = pd.read_csv(PAPER/'ecb_minute_20260928'/'minute_jump_descriptives.csv')
    rows = [[LABELS[r.sample], 'announcements' if r.is_event else 'controls', str(int(r.n)), f(r.median_jump_share, 2), f(r.share_bns_1pct, 3), f(r.median_BV_excl1_over_BV, 2), f(r.median_BV_excl5_over_BV, 2), f'{r.median_VOL:,.0f}'] for r in jd.itertuples()]
    write(out, 'jumpdesc', ['Sample', 'Days', '$n$', 'Jump share', 'BNS at 1\\%', 'BV w/o min.\\ 1 / BV', 'BV w/o min.\\ 1--5 / BV', 'Volume'], rows, 'One-minute descriptives of the post-release window.', 'tab:jumpdesc')


def frozen_and_common(out):
    e = pd.read_csv(PAPER/'ecb_confirmation_20260915'/'primary_tests.csv')
    write(out, 'frozen', ['Frozen hypothesis', 'Estimate', 'Wild $p$', 'Holm $p$'], [[r.hypothesis.replace('_', ' '), f(r.estimate), f(r.p_wild), f(r.p_holm)] for r in e.itertuples()],
          'Frozen confirmation tests on the ECB 2000--2012 sample.', 'tab:frozen')
    c = pd.read_csv(CROSS/'common_metric_cone_tests.csv'); rows = []
    for b in ['degree2_quadratic', 'quadratic_angles_radial1', 'degree1_absolute', 'absolute_angles_radial2']:
        x = c[c.basis.eq(b)].set_index('comparison')
        rows.append([b.replace('_', ' '), f(x.loc['2000_2012', 'estimate']), f(x.loc['2013_2025', 'estimate']), f(x.loc['later_minus_earlier', 'estimate']), f(x.loc['later_minus_earlier', 'se_cr1']), f(x.loc['later_minus_earlier', 'p_wild']), f(x.loc['later_minus_earlier', 'p_holm_exploratory_family'])])
    write(out, 'commontarget', ['Basis', '2000--2012', '2013--2025', 'Difference', 'SE', 'Wild $p$', 'Holm--12'], rows, 'Sector contrast at a common target across the two ECB periods.', 'tab:commontarget')


def figures(out, event_panels):
    try:
        import matplotlib
    except ImportError:
        print('figures skipped: install matplotlib to draw them')
        return
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams.update({'font.size': 9, 'font.family': 'serif'})
    ch = pd.read_csv(PAPER/'ecb_design_information_20260928'/'radial_exponent_curves.csv')
    cf = pd.read_csv(PAPER/'fomc_replication_20260929'/'fed_radial_exponent_curves.csv')
    fig, ax = plt.subplots(figsize=(5.2, 3.0))
    for lab, c in [('ECB 2000--2012', ch[ch['sample'].eq('H_2000_2012') & ch.measure.eq('BV') & ch.angular_basis.eq('quadratic_angles')]),
                   ('ECB 2013--2025', ch[ch['sample'].eq('G_2013_2025') & ch.measure.eq('BV') & ch.angular_basis.eq('quadratic_angles')]),
                   ('FOMC 2008--2026', cf[cf.measure.eq('BV') & cf.angular_basis.eq('quadratic_angles')])]:
        ax.plot(c.exponent, c.lr, label=lab, lw=1.2)
    ax.axhline(3.84, color='0.5', lw=.8, ls='--'); ax.set_ylim(0, 30); ax.set_xlabel('radial exponent'); ax.set_ylabel('likelihood ratio'); ax.legend(frameon=False, fontsize=7)
    plt.tight_layout(); plt.savefig(out/'fig_exponent.pdf'); plt.close()
    g = pd.read_csv(PAPER/'measurement_check_20260930'/'measurement_simulation_grid.csv')
    mc = pd.read_csv(PAPER/'measurement_check_20260930'/'measurement_check.csv').set_index(['sample', 'measure'])
    fig, ax = plt.subplots(figsize=(5.2, 3.0))
    for smp in ['H_2000_2012', 'G_2013_2025', 'FED_2008_2026']:
        x = g[g['sample'].eq(smp) & g.measure.eq('BV') & g.status.eq('simulated')]
        line, = ax.plot(x.noise_multiple, x.median_exponent, 'o-', lw=1.1, ms=3.5, label=LABELS[smp])
        ax.axhline(mc.loc[(smp, 'BV'), 'observed_exponent'], color=line.get_color(), lw=.8, ls='--')
    ax.set_xlabel('noise multiple'); ax.set_ylabel('median simulated exponent'); ax.legend(frameon=False, fontsize=7)
    plt.tight_layout(); plt.savefig(out/'fig_simulation.pdf'); plt.close()
    if event_panels is None:
        print('fig_central skipped: pass --event-panels with the FOMC event panel to draw it')
        return
    panels = {'ECB 2000--2012': pd.read_csv(CROSS/'inputs'/'historical_native.csv'), 'ECB 2013--2025': pd.read_csv(CROSS/'inputs'/'generation_harmonized_native_state.csv'),
              'FOMC 2008--2026': pd.read_csv(Path(event_panels)/'fed_primary_event_panel.csv')}
    fig, axes = plt.subplots(1, 3, figsize=(9.5, 3.1), sharey=True)
    for ax, (name, t) in zip(axes, panels.items()):
        r = np.hypot(t.u, t.z); ok = r > 0
        lr, y, s = np.log(r[ok]), t.crossfit_abnormal_log_BV[ok].to_numpy(), t.crossfit_state_z[ok].to_numpy()
        b = np.linalg.lstsq(np.column_stack([np.ones(len(y)), s, lr]), y, rcond=None)[0]
        ax.scatter(lr, y, s=9, alpha=.45, color='0.35', linewidths=0)
        grid = np.linspace(lr.min(), lr.max(), 50); ax.plot(grid, b[0]+b[2]*grid, color='black', lw=1.2)
        ax.set_title(f'{name}, slope {b[2]:.2f}'); ax.set_xlabel('log amplitude')
    axes[0].set_ylabel('abnormal log bipower variation')
    plt.tight_layout(); plt.savefig(out/'fig_central.pdf'); plt.close()


def main():
    p = argparse.ArgumentParser(prog='python scripts/Make_paper_tables.py')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--event-panels', type=Path)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    for step in [mean_branch, basis, minute, exponent_and_elasticity, measurement, fomc, sector_and_symmetry, frozen_and_common]:
        step(a.output)
    figures(a.output, a.event_panels)
    print(f'tables and figures written to {a.output}')


if __name__ == '__main__':
    main()
