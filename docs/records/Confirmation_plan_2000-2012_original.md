# Confirmation plan for the 2000–2012 sample

*Record written on 12 September 2026 in Italian and translated into English. The original text is preserved in the repository history, under the name `docs/Piano_conferma_2000-2012_originale.md`, at commit `0f6daab`.*

**Project:** State-Dependent Transmission of ECB Monetary Surprises
**Date:** 12 September 2026
**Status:** draft protocol, to be frozen before any estimation on 2000–2012

---

## 0. Principles

The plan has a single purpose, which is to turn the 181 meetings of 2000–2012 into a valid confirmation sample. A sample serves for confirmation if three conditions hold together.

1. No estimation is performed on it before the specification is frozen.
2. The hypotheses to be confirmed are written in executable form, with direction, family, number of replications and margins, and derive from the 2013–2025 generation sample alone.
3. Every choice that the new sample imposes, such as the source of the equity coordinate, the treatment of OIS gaps and the scale of the variables, is declared in advance and validated on the generation sample, never on the confirmation sample.

The inferential principle that governs the section on rotation is the following: **confirmatory inference is performed on rotation-invariant functionals, and the rotation serves for interpretation, not for testing.** The reasons are given in Section 3.

---

## 1. Samples and register

### 1.1 Definitions

| Sample | Meetings | Role | Constraints |
|---|---|---|---|
| Generation | 2013–2025, about 110 | Produced the hypotheses; used for the bridge validation (§3.4) and for pooled sensitivities | Already seen; produces no confirmation |
| Confirmation | 2000–2012, 181 | Confirmatory estimation | Never seen; no estimation before the v2 freeze |
| Pooled | 2000–2025, about 291 | Descriptive only, and for the power frontiers | Produces no confirmation |

1999 is excluded because contracts expiring in 1999 do not exist in the Barchart archive. The meeting of 2 December 1999 falls in the rollover zone of the March 2000 contract and will be excluded by the quality panel, not by hand.

### 1.2 Event register

The register is built from EA-EMPD, from the `Date_time` column of the `GC_PR` and `GC_PC` rows. From 2000 to 2012 the press release is always at 13:45 CET and the press conference at 14:30 CET. The register must be cross-checked against the published ECB calendar, meeting by meeting, and every discrepancy is recorded and not corrected silently.

The register includes every meeting, every root and every phase, even when the contract or the surprise is missing, as in the v1 protocol. It adds three new columns:

- `equity_source`: `fx_futures` if the fx root is available in the phase, `ea_empd_stoxx50e` otherwise;
- `ois1m_available`: true or false, from the `OIS_1M` column;
- `era`: `2000-2007`, `2008-2012` or `2013-2025`, for the sensitivities by epoch.

### 1.3 Expected coverage

From a reading of EA-EMPD there are 24 meetings in 2000, 24 in 2001 and 133 from 2002 to 2012. `STOXX50E` and `OIS_1Y` are complete for all of them. `OIS_1M` is missing for 7 meetings of 2000, 2 of 2001 and 6 in 2001–2012. The effective sample of each model is fixed by the sample register produced by the estimation, with the exclusions by model, outcome and indicator, and no artificially common N is imposed.

---

## 2. Data

### 2.1 Barchart

164 files, namely the four quarterly maturities of each year from 2000 to 2012 for `gg`, `hf` and `hr` (156 files) and the 2011–2012 maturities for `fx` (8 files). Each file carries the whole life of the contract, of which the front-month quarter is the usable part. The non-event days of the same files provide the control pool, about 3,200 additional root-days per root, without a separate download.

### 2.2 EA-EMPD

Columns used, all by phase (`GC_PR`, `GC_PC`):

- `OIS_1M`, `OIS_3M`, `OIS_6M`, `OIS_1Y`: the policy coordinate in the external branches;
- `STOXX50E`: the equity coordinate when fx is not available (from 2000 to June 2011, and as a robustness branch everywhere).

The EA-EMPD windows are those of the dataset, closing at about +15 to +25 minutes for the press release and at about +70 to +80 minutes for the press conference. The consequence for the press-conference phase is discussed in §3.8.

### 2.3 US releases

`Raw/Certification/us_releases.csv` is to be built with the columns `release_id`, `timestamp_utc` and `source_url` from the BLS and DoL archives for 2000–2026. Jobless claims are released every Thursday at 8:30 ET, and every meeting until 2014 took place on a Thursday. Until 2022, 8:30 ET fell at 14:30 Frankfurt time, exactly at the start of the press conference. This is a constant exposure, present identically on Thursday control days, and matching by day neutralizes it on average. The verified file changes the status from `candidate_screen_only` to `verified` and allows the exclusion sensitivity on the press-release branch alone, where the exposure varies.

---

## 3. Use of the MP/CBI rotation

This is the central section. It fixes what the rotation is, what depends on it and what does not, where its coordinates come from in the two samples, and on which objects confirmatory inference is performed.

### 3.1 Objects

For each meeting and phase the **vector of observed surprises**, of dimension 2, is observed:

- the policy coordinate, a scalar, positive when rates rise in the window;
- the equity coordinate, a scalar, positive when the index rises in the window.

It is denoted x_{e,p} = (u_{e,p}, z_{e,p})', as in the note on Steps 22–28. Both coordinates are expressed in standard deviations, with the scale fixed according to §3.5.

The **rotation matrix**, of dimension 2×2, is R(θ), with θ an angle. The rotated vector is η_{e,p}(θ) = R(θ)' x_{e,p}, whose components are called MP and CBI. The sign restrictions of Jarociński and Karadi define the **identified set** Θ_p, the interval of angles for which the MP component moves rates and equities in opposite directions and the CBI component moves them in the same direction. The existing code (`JK_median_rotation.m`) estimates Θ_p and takes its median θ_50, and the audit uses the quantiles 0.1, 0.25, 0.5, 0.75 and 0.9 of the set.

The **response model** is the quadratic surface of the earlier levels. For the outcome y_{i,e,p}, the log of the abnormal bipower variation of asset i in phase p:

    y_{i,e,p} = α_p + Γ_p' s_e + λ_i + x_{e,p}' A_p(s_e) x_{e,p} + error,    A_p(s) = A_{p,0} + s · A_{p,1}.

A_{p,0} is the **symmetric 2×2 matrix of the surface at zero state**, with entries a_{11} (curvature along u), a_{22} (curvature along z) and a_{12} (cross term). A_{p,1} is the matrix of the modulation by the state s_e, the pre-announcement state standardized on control days. Everything is estimated in the **raw quadratic basis** (u², z², 2uz), without rotation.

### 3.2 Invariant and non-invariant quantities

By the proposition on rotational invariance already in the note, for every θ there exists B = R(θ)' A R(θ) such that x'Ax = η'Bη. Hence:

**Invariant under rotation** (parameters of the model, not of the representation):

- the estimated surface and its predicted values;
- the three entries of A in the raw basis, a_{11}, a_{12} and a_{22};
- the trace, determinant, eigenvalues and eigenvectors of A;
- every mean of the quadratic form over a cone defined by the **signs of the raw coordinates**, because the MP and CBI cones are defined by sign(u) and sign(z) and not by θ.

**Not invariant** (parameters of the representation):

- the coefficient labelled "MP energy", that is, the (1,1) entry of B(θ);
- the coefficient labelled "CBI energy", the (2,2) entry of B(θ);
- their contrast at a fixed θ.

The result on the generation sample, a positive MP energy with a wild p-value of 0.003, stable over the grid, is a statement about B(θ) along five values of θ. It is robust in the sensitivities performed, but its p-value depends on θ and the family of 896 tests could not confirm it. The plan restates it as a statement about A.

### 3.3 The two confirmatory hypotheses, in invariant form

The **mean cone curvature** is defined as the mean of the quadratic form d'Ad along the unit directions d that fall in the cone, with uniform weight on the angle. Since the form is even in d, the cones are pairs of opposite quadrants, the MP cone being {u>0, z<0} ∪ {u<0, z>0} and the CBI cone {u>0, z>0} ∪ {u<0, z<0}.

With d(φ) = (cos φ, sin φ), the mean over the MP cone is the integral over φ ∈ (−π/2, 0) divided by π/2. The computation gives, in closed form:

    ā_MP  = (a_{11} + a_{22})/2 − (2/π) · a_{12}
    ā_CBI = (a_{11} + a_{22})/2 + (2/π) · a_{12}
    ā_MP − ā_CBI = −(4/π) · a_{12}

The two confirmatory hypotheses are:

**H1 (energy in the MP sector raises the abnormal bipower variation of the press release):** ā_MP > 0 in the press-release phase, Bund-only outcome.

**H2 (the MP sector matters more than the CBI sector):** ā_MP − ā_CBI > 0 in the press-release phase, Bund-only outcome. It is equivalent to a_{12} < 0, so that the surface is higher where rates and equities move in opposite directions.

Both are linear combinations of the coefficients in the raw basis and are tested with the same wild cluster bootstrap by meeting already in `models.py`, without estimating any θ. They are directional, because the direction was generated on 2013–2025, so the p-values are one-sided, as declared in the freeze. They form a family of two tests with Holm.

The explicit MP−CBI contrast, which the report of 11 September flagged as never having been run, is H2. It is also the point at which the earlier statement "CBI is not significant" becomes a verifiable statement.

### 3.4 Sources of the coordinates and bridge validation

In the generation sample the policy coordinate is the Schatz log return with its sign reversed over the window of the phase, and the equity coordinate is the net fx return over the same window. Both close with the outcome and form the **aligned** pair.

In the confirmation sample the policy coordinate remains the aligned Schatz, since `hf` exists from March 2000. The equity coordinate does not, because fx exists only from June 2011. From 2000 to June 2011 the only equity coordinate is the EA-EMPD `STOXX50E`, measured over the EA-EMPD press-release window, which closes between +15 and +25 minutes. For the press-release phase it is therefore **nearly aligned** with the outcome (PR, PR+25] and contains no information later than the outcome.

Replacing fx with STOXX50E changes the coordinate on which H1 and H2 were generated. The substitution must be validated on the sample where both exist, June 2011 to 2025. This **bridge validation** is performed before the v2 freeze, on the generation sample alone together with the 18 months of 2011H2–2012, and comprises four checks with declared thresholds:

1. the correlation between z from fx and z from STOXX50E in the press-release phase, meeting by meeting, with a threshold of 0.90;
2. the overlap of the identified sets Θ_PR estimated with the two coordinates, with the median θ_50 under STOXX50E required to fall within Θ_PR estimated with fx;
3. the replication of ā_MP and a_{12} on 2013–2025 with STOXX50E in place of fx, with the same sign and a wild p-value within a factor of three of the value obtained with fx;
4. the stability of the scale, with the standard deviation of STOXX50E over the 2013–2025 meetings compared with that of fx over control days, the ratio lying within [0.7, 1.4].

If the four checks pass, STOXX50E is the declared equity coordinate for 2000–2011H1 and fx for 2011H2–2012. If check 1 or check 3 fails, the declared fallback is to use STOXX50E for **all** of 2000–2012, so that the coordinate is homogeneous within the confirmation sample, and to report the discrepancy with fx as a limitation. The fallback is chosen now, not later.

### 3.5 Scale of the coordinates

The scale determines the cones, since a more compressed coordinate narrows its cone. The rule is:

- policy coordinate: the standard deviation of the aligned Schatz over the pooled press-release control days, without centring, as in v1, since control days exist for the whole of 2000–2012;
- equity coordinate from fx: the standard deviation over control days, as in v1;
- equity coordinate from STOXX50E: no control days exist, because EA-EMPD contains only event days, so the coordinate is standardized over the `GC_PR` meetings of the **confirmation sample**, without centring. This uses event data but not the outcome, and it is not updated after the estimation. Check 4 of the bridge validation verifies that this scale is comparable to that on control days.

### 3.6 Residual role of θ

After §3.2 and §3.3 the rotation has three uses, all descriptive:

- **reading**: the tables report B(θ_50) next to A, because "MP energy" is the language of the literature, and the caption states that B depends on θ while A does not;
- **audit**: the grid of five values of θ remains as a sensitivity, without Holm and without confirmatory claims;
- **consistency with the cones**: the tables report whether the principal eigenvector of A falls in the MP cone and whether Θ_PR in the confirmation sample overlaps Θ_PR in the generation sample. These are diagnostics, not tests.

No confirmatory p-value is computed at a fixed θ.

### 3.7 Modulation by the state

A_{p,1} is the matrix of the dependence on the state. In the generation sample the MP × state modulation was unstable (0.054 on the full sample, 0.304 without the first 5). It does not enter the primary family. It is reported as a **declared secondary hypothesis** in invariant form, ā_MP computed on A_{p,1}, with a two-sided wild p-value. It is the second-order version of the original question, and its expected outcome is discussed in §6.

### 3.8 The press-conference phase

For the press conference, the EA-EMPD STOXX50E closes 25 to 35 minutes after the outcome window (PC, PC+45] and is therefore **ex post**, as already established. Before June 2011 there is no aligned equity coordinate for the press conference. The consequences are as follows:

- PR–PC heterogeneity with aligned indicators can be replicated only on 2011H2–2012, about 18 meetings, and cannot be confirmed out of sample, which must be stated as such;
- on 2000–2011H1 the press-conference surface is estimated with EA-EMPD coordinates as an **ex-post branch**, with the same label as in v1, for descriptive purposes only;
- H1 and H2 are defined on the press-release phase alone for precisely this reason.

---

## 4. Changes to the pipeline, stage by stage

The names are those of the modules in the repository.

### 4.1 Ingestion and raw audit (`Audit_Barchart.m`, `Clean_raw_files.m`, `File_sha256.m`)

- Extend the inventory to the 164 files, with a SHA-256 hash for each in the data manifest.
- `Contract_event_day.m`: map the two-digit suffix `00` to `12` explicitly to 2000–2012, and add a test that rejects any year before 1999 or after the current year.
- Add the **session length by file** to the audit, with bars per day and the first and last intraday timestamps. In 2000 a trading day has 128 to 132 bars, in 2006 it has 169. The table goes into the manifest.
- Spikes and low-volume bars: the same rule as in v1 (removal of the isolated spike, flag without deletion).

### 4.2 Certification of clock and bar labels (`Audit_timezone_provenance.m`, `Audit_bar_label_convention.m`, `Event_time_alignment_audit.m`, `Run_time_alignment_smoke.m`)

- Re-certify `interval_start` → `interval_end_utc` on the deep archive, with the same test as in v1 on at least one file per root and per three-year period (2000, 2003, 2006, 2009, 2012).
- Extend the daylight-saving self-tests. Until 2006 US daylight saving time began on the first Sunday of April and ended on the last Sunday of October, and from 2007 it runs from the second Sunday of March to the first Sunday of November. Europe is unchanged, with the last Sunday of March and of October. In the weeks of misalignment the CT–Frankfurt offset is not seven hours. Two examples with an ECB meeting inside the misalignment are to be included in the self-test, **1 April 2004** (Europe already on summer time, the US not, giving eight hours) and **4 November 2004** (Europe already back, the US not, giving six hours). The IANA conversion `America/Chicago` handles them, and the test serves to prove that no part of the code assumes a fixed offset.
- `Event_time_alignment_audit.m`: verify for each meeting of 2000–2012 that the Bund volume peak falls in the bars 13:45–13:55 CET. This is the empirical alignment test already performed by hand on ten meetings.

### 4.3 Windows and panels (`Event_windows.m`, `Phase_window_construction.m`, `Press_release_panel.m`, `PR_bar_panel.m`)

- Windows as in the v1 protocol: PR (PR, PR+25], PC (PC, PC+45], state (PR−60, PR−5], and continuation prediction from the pre-PR window for PR and from (PC−25, PC−5] for PC. No parameter changes.
- Add the **session gate**, requiring every control window to fall entirely within the session of the day, with days that do not allow it excluded from the control pool and the reason recorded. In 2000 the state window (12:45, 13:40] CET lies within the session, and the gate serves for cases of delayed opening or early closing.
- A single bar extractor for realized variance and bipower variation, as already corrected in v1.

### 4.4 Contract selection (`Contract_event_day.m`, `preferred_contracts.csv`)

- The same rule as in v1: completeness and pre-PR coverage, then pre-PR volume, then the file name, with no post-PR variable.
- In the early years the choice between the expiring and the next contract around the March, June, September and December rolls is more delicate, because volume migrates within a few days. The pre-PR ranking handles it, but the table of the contracts chosen for each meeting must be published in the manifest.

### 4.5 Reading EA-EMPD (`Locate_ea_policy_dataset.m`, `Read_ea_policy_window.m`, `Require_surprise_source_manifest.m`)

- Extend the reading to 2000–2012 for `GC_PR` and `GC_PC`.
- Add `STOXX50E` as a column read and propagated in the register, with `equity_source` by meeting and phase.
- Treatment of missing `OIS_1M`: no filling. The EA-EMPD first-principal-component branch requires all four maturities and loses those meetings, while the `OIS_1Y` branch loses none. Both remain external branches, and the primary coordinate is the aligned Schatz.

### 4.6 Shock components (`Build_JK_shock_components.m`, `JK_median_rotation.m`, `Apply_JK_shock_fit.m`)

- `Build_JK_shock_components.m`: add the construction of the pair (u, z) with z from `STOXX50E` when `equity_source = ea_empd_stoxx50e`, with the scale of §3.5.
- `JK_median_rotation.m`: estimate Θ_p and θ_50 separately on the generation and on the confirmation sample, save both, and never use a rotation estimated on the pooled sample for a test.
- New module `Cone_functionals.m` (a name free of collisions), which receives A in the raw basis and returns ā_MP, ā_CBI and their difference with the formulae of §3.3, including a numerical self-test against direct integration over a grid of angles.

### 4.7 Counterfactual (`Announcement_counterfactual.m`, `Announcement_phase_counterfactual.m`, `Announcement_counterfactual_validation.m`)

- The normal-continuation model is estimated by annual fold on control days only, as in v1. With 13 more years the pool grows by about 3,200 root-days per root, and the functional form is unchanged.
- Matching by weekday is trivial in 2000–2014, because every meeting falls on a Thursday, so the control days are the non-ECB Thursdays.
- The standardization of the state uses control days only, by fold.
- Add the flag `us_release_verified` from the file of §2.3.

### 4.8 Historical MATLAB battery (Steps 9–21, `Run_pipeline.m`)

- It is not the entry point of the confirmation. It is rerun only to regenerate manifests and canonical windows on the extended archive and for the auxiliary rerun `Run_final_matlab_checks` (windows, shrinkage with the corrected one-standard-error rule, gate 28).
- The modules with four-root outcomes remain labelled as sensitivities.

### 4.9 Steps 22–25 (`Phase_component_contrasts.m`, `Invariant_phase_attribution.m`)

- The PR–PC surface contrast with aligned indicators is computed on the pooled 2011H2–2025 sample for descriptive purposes only, labelled "not confirmed out of sample". On 2000–2011H1 only the ex-post branch exists.
- The invariant geometry (Rayleigh quotient on Σ^{1/2} ΔA Σ^{1/2}) remains descriptive.

### 4.10 Steps 26–27 (`Long_horizon_phase_attribution.m`, `Rank_one_feasibility.m`, `Dynamic_jump_frontier.m`)

- No confirmatory rerun. Step 27B is to be reported with the collinearity figure of the null (96.96 percent of the jump explained by the basis) as a property of the design. If an updated figure is wanted, power is recalibrated at N = 291 for documentation only, without estimating the operator.

### 4.11 Step 28 (`Run_step28.m`, `Run_step28_gates.m`, `Step28_sample_size_calibration.m`)

- Rerun only the **outcome-free calibration**, with the grid extended to G = 300, to record where N = 291 stands relative to the criteria. The exploratory diagnostics placed the passing of the rank criterion alone at 300 and of the joint criterion at 500. The expected outcome is that the projector criterion remains unmet, so that Step 28 remains blocked and the updated figure enters the section on limits. No bridge estimation.

---

## 5. v2 specification of the Python runner

New build `final_analysis_v2` and new `final_analysis_spec_v2.json`. The v1 specification has seen 2013–2025 and does not touch 2000–2012.

### 5.1 Order of execution

1. **Bridge** (new `bridge` mode): performs the four checks of §3.4 on 2011H2–2025 and writes `bridge_decision.json` with the outcome and the declared equity coordinate. It forbids the next step if the file is missing.
2. **Ex-ante calibration** (new `calibrate` mode): with the design matrix of the confirmation sample and control days only, without any event outcome, it computes the power of H1 and H2 by signal injection and the R²₈₀ floor of the sufficiency branch, and writes the margins into the specification. It uses the Wilson lower bound, as in v1.
3. **Freeze**: hashes of code, specification, data and tables, with `prior_results_seen=true` for 2013–2025 and `false` for 2000–2012, both in the manifest.
4. **Estimate** on the confirmation sample only.
5. Descriptive **pooled estimate**, in a separate and labelled directory.

### 5.2 Families

| Family | Tests | Correction | Replications |
|---|---|---|---|
| `primary_confirmation` | H1: ā_MP > 0; H2: ā_MP − ā_CBI > 0. Press-release phase, Bund only, abnormal log bipower variation, zero state | Holm over 2, one-sided | B = 19,999 |
| `secondary_declared` | Modulation ā_MP(A₁), two-sided; signed and absolute scalar interaction; sufficiency interval; H1 and H2 on realized variance; H1 and H2 by epoch, 2000–2007 and 2008–2012 | Holm within the family, reported as secondary | B = 19,999 |
| `sensitivity_descriptive` | θ grid, leave-top-K, four roots, EA-EMPD OIS and first-principal-component branches, US screen, ex-post press conference | None, and no claim | B = 999 |

The resolution gate requires 1/(B+1) ≤ 0.05/m for every family carrying a claim. With B = 19,999 and m = 2 the Holm threshold is 0.025 and the smallest attainable p-value is 0.00005. The gate is mechanical in the freeze and blocks the build if violated.

### 5.3 Level 1

- Mean branch: as in v1, the signed and absolute OIS1M surprise divided by ten. On 2000–2001 the meetings without `OIS_1M` drop out, with a sensitivity using `OIS_1Y`.
- Sufficiency branch: history block on `OIS_1Y` (first lag and the mean of the three preceding surprises), because it is complete, with `OIS_1M` as a sensitivity. The precision margin is no longer 0.02 but the value that the calibration of §5.1 returns as attainable at power 0.80. The finite rule remains a bound below the margin together with adequate power at that scale.

### 5.4 Inference

Wild cluster bootstrap by meeting with the restricted null imposed, Rademacher signs common to the assets and phases of the meeting, CR1 and the plus-one correction, as in v1. The p-values remain **conditional** on the measured indicators and on the estimated counterfactual, and the manifest states this.

---

## 6. Expected outcomes

The arithmetic below uses the 1/√N scaling of standard errors and the 1/N scaling of detectable partial R². It is an expectation, not a promise.

**H1.** On 2013–2025 the MP energy had a wild p-value of 0.003 with 110 meetings, that is, about t ≈ 3. If the effect has the same size in 2000–2012, one expects t ≈ 3.8 with 181 meetings and a one-sided p-value of the order of 10⁻⁴, and t ≈ 4.9 on the pooled sample of 291. H1 has good chances of confirmation **if the effect is stable across the epoch**. The main risk is heterogeneity, since 2000–2007 had neither forward guidance nor asset purchases and the MP/CBI composition may differ, which is why the sensitivity by epoch is included.

**H2.** Never tested, so its power is fixed by the calibration. As an order of magnitude, if CBI is null with a standard error similar to that of MP, the contrast has t ≈ t_MP/√2, about 2.1 with 110 meetings and 2.7 with 181, for a one-sided p-value of about 0.004. It is less certain than H1 and more informative.

**Modulation by the state.** With 110 meetings it was unstable and changed sign under trimming. With 181 meetings the band narrows by a factor of 0.78, and if the true effect is close to zero the expected outcome is a tighter null. This is the most useful outcome for the original question, an interval that excludes economically large modulations.

**Sufficiency.** The floor at power 0.80 was 0.20 with 103 meetings. One expects about 0.11 with 181 and 0.07 with 291. The figure does not reach 0.02, so the question remains an interval, although an interval of half the width. It must be stated in these terms, and the ex-ante calibration fixes the number before the estimation.

**PR–PC heterogeneity.** It cannot be confirmed out of sample because fx is absent before 2011. On the pooled 2011H2–2025 sample the gain in power is marginal (from 114 to about 130 meetings), and the finding remains suggestive.

**Step 28.** N = 291 remains below the joint requirement of about 500 and at the edge of the rank criterion alone, so it remains a result about the design.

### 6.1 Declared decision tree

- H1 and H2 confirmed: the paper has a strong empirical result, generated and confirmed on disjoint samples, with the nulls and the frontiers as its second part.
- H1 confirmed, H2 not: announcement energy matters but the MP/CBI composition cannot be separated, and the paper concentrates on the first order and declares the second as not established.
- H1 not confirmed: heterogeneity across epochs as the main reading, with the 2000–2007 and 2008–2012 sensitivity in support, and the paper keeps the architecture of Track A, with the failed replication as a result.

None of the three outcomes requires a new specification on the confirmation sample. If one is needed, the sample has ceased to serve for confirmation.

---

## 7. Operational sequence

| Week | Activity | Output |
|---|---|---|
| 1 | Download of the 164 files; raw audit; 2000–2012 register from EA-EMPD; verified US calendar | v2 data manifest, `event_registry_v2.csv`, `us_releases.csv` |
| 1–2 | Re-certification of clock and bar labels on the deep archive; 2004 daylight-saving self-test; alignment audit by meeting | extended certification manifests |
| 2 | Windows, panels, preferred contracts and counterfactual on the whole of 2000–2025, without estimating H1 or H2 | panels and control pool |
| 2 | Bridge validation on 2011H2–2025 | `bridge_decision.json` |
| 3 | Ex-ante calibration; writing and freezing of the v2 specification | frozen `final_analysis_v2` |
| 3 | Estimation on the confirmation sample; descriptive pooled estimation | v2 tables |
| 4–6 | Writing; Step 28 recalibrated for the section on limits; auxiliary MATLAB rerun | draft of the paper |

Two sequencing constraints are not negotiable: the bridge validation precedes the freeze, and the freeze precedes any reading of a 2000–2012 outcome, including a chart.
