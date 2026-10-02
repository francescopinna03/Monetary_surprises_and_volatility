# Diagnostics across epochs: findings and limits

*Record written on 16 September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `b89153c`.*

Analysis performed on 16 September 2026 on 160 meetings of 2000–2012 and 111 of 2013–2025. It uses the already opened archives supplied by the author and is neither a new confirmation nor a rerun of the 28 steps. All new results are exploratory. The sector test is two-sided and was not chosen in the observed direction.

## Operational conclusion

The quadratic form is not a good primary specification for describing these samples. The relation between the amplitude of the two coordinates and the abnormal bipower proxy survives the comparison between epochs. The MP–CBI ordering is sensitive to the angular form even when radial growth is linear. Composition matters, but the data do not authorize replacing "reversal" with "composition alone". These are distinct conclusions and must not be merged into a single verdict.

## Provenance and comparability

The recent sample comes from the frozen build of 11 September (`final_resume_20260911_174739_4124`), with manifest SHA-256 `d7ef6b78ccb6be4283a196da4afe3c55458b25e8147c225b5b595454bf281b85`. The bridge of 12 September was reproduced, with the EA equity coordinate giving an MP mean of 0.1819036957 and an MP–CBI difference of 0.0733387017. The comparison concerns this documented sample, not a hypothetical latest rerun of the pipeline.

The historical sample comes from the post-opening re-estimation of 15 September, build manifest `f3880de1a82a841373ffee1ac4c7383b56879061e6ea8a9bbdc4c9d6b3f81527`. Its outcomes and cross-fitted states were reproduced from the archived control days, and no raw price was read again.

The outcome is that of the Bund press release, the log of the bipower proxy minus the normal continuation estimated on control days. The five bars have endpoints at +5, +10, +15, +20 and +25 minutes, so the effective support is **(0, +25]** and not (+5, +25]. The archived definitions, the bar counts and the coverage were verified, without a new certification from prices. The same external EA equity source is kept in both epochs, so recent fx futures and historical external equity data are not mixed, although this does not make the external window identical to the Schatz window.

For the contrasts between epochs, both coordinates are expressed in the generation metric, with a Schatz standard deviation on press-release control days of 0.00017367797 and an EA equity standard deviation on recent events, as a fractional return, of 0.00422300643. The state is the pre-release log bipower variation, centred and scaled on recent Bund press-release control days. The native analyses keep instead their respective leave-one-year-out standardizations.

The slow state is harmonized to the five preceding control days, excluding event days. The continuations remain estimated separately by epoch, with leave-one-year-out validation and the 2022 timing dummy in the recent period, which is identically zero before 2013. The correction changes the recent outcome by 0.01852 in mean absolute value, with a maximum of 0.04101, without changing the 111 meetings, and the substantive diagnoses are unchanged.

## 1. Predictive performance of the quadratic form

Mean squared error, equally weighted mean over the 13 left-out years. For the recent period the harmonized slow state and the native leave-one-year-out interaction state are reported.

| Form | 2000–2012 | 2013–2025 |
|---|---:|---:|
| Quadratic angular profile, squared radius | 1.6451 | 2.7963 |
| Same angular profile, linear radius | **1.1330** | **1.3183** |
| Absolute angular profile, linear radius | 1.1332 | 1.3708 |
| Absolute angular profile, squared radius | 1.6641 | 2.9381 |
| Natural-spline reference with internal choice of the penalty | 1.6949 | 1.9469 |

With the same quadratic angular profile, linear growth reduces the mean squared error by 31 and 53 percent, winning in 12 of 13 and 11 of 13 years respectively. The result is descriptive, since the folds share training data and do not constitute 13 independent experiments. The validation is moreover conditional on the outcome and on the indicators already built, and is not a fully nested validation of the whole pipeline. It does not prove an exact r¹ law, but it makes imposing r² as the only lens unjustified.

## 2. Policy amplitude conditional on the equity coordinate

In the signed and absolute branch with both coordinates and all their interactions with the state:

| Term | 2000–2012: coefficient; Holm-9 p | 2013–2025: coefficient; Holm-9 p |
|---|---:|---:|
| Absolute Schatz value | 0.3727; **0.0108** | 0.3047; **0.0036** |
| Absolute equity value | 0.6912; **0.0348** | 0.8598; **0.0092** |

The coefficients in the table use the native metrics, so their magnitudes are not compared across epochs. Both positive associations survive the correction within the family of nine terms in each epoch. This contradicts the reading according to which, in the earlier period, the volatility content would be exclusively equity-related and the rate would carry none. It remains a conditional association and not the causal identification of two structural shocks, and the reported corrections do not retroactively cover the whole exploratory path of the project.

## 3. Dependence of the recent sector ordering on the angular form

With linear radial growth and the quadratic angular profile, the MP–CBI contrast in the native metric for 2013–2025 is **+0.3304**, with a two-sided wild p-value of **0.00635** and a Holm-adjusted value over the four models of **0.0254**. For 2000–2012 it is −0.1873, with p = 0.2257.

The absolute form, which predicts almost as well, gives instead +0.2123 in the recent period, with p = 0.18445, and −0.1795 in the earlier period, with p = 0.24235. It is therefore incorrect to say that no specification finds a recent ordering, and equally incorrect to say that the ordering is robust to the functional form.

The direct comparison in the **same metric**, at the same radius and state, gives:

| Model | Historical MP–CBI | Recent MP–CBI | Difference, recent − historical | Wild p of the difference | Holm-12 |
|---|---:|---:|---:|---:|---:|
| Quadratic | −0.0994 | +0.0711 | +0.1705 | 0.02170 | 0.2170 |
| Quadratic angles, linear radius | −0.2043 | +0.3464 | +0.5507 | 0.01145 | 0.12595 |
| Absolute angles, linear radius | −0.2011 | +0.2260 | +0.4270 | 0.07390 | 0.6651 |
| Absolute angles, quadratic radius | −0.0944 | +0.0460 | +0.1405 | 0.08645 | 0.6916 |

The exploratory family of 12 tests contains four models for three contrasts, each epoch and the difference. The difference in the model with linear radius and quadratic angles is of interest but does not survive this family. Equality cannot be inferred from the failure to reject, nor can an economic explanation of the crisis be inferred from the change in the sign of a point estimate.

## 4. Contribution of composition

Events lying exactly on the axes belong to neither of the two open sectors, 22 in the historical and 16 in the recent sample, and they remain included in the estimation of the surfaces. Among the others, the counts are 60 MP and 78 CBI in the earlier period, and 63 MP and 32 CBI in the recent one. In the upper tercile of the recent radius there are 32 MP events against only 5 CBI, so comparability in the tails is limited.

The intersection of the convex hulls in (|u|, |z|, state) across all four epoch–sector cells keeps 24 MP and 44 CBI historical events and 27 MP and 10 CBI recent ones. This is a geometric check of support and not a guarantee of density. The folding into absolute values exploits the central symmetry imposed by the forms considered.

Standardizing on **identical amplitudes of the two coordinates and an identical state**, with a common empirical distribution balanced across the four cells, the model with linear radius and quadratic angles gives −0.2392 in the earlier period and +0.3939 in the recent one, a difference of +0.6331 with a wild p-value of 0.0118 and a Holm-12 value of 0.1298. The model with absolute angles gives a difference of +0.5125, with p = 0.07105. The standardized contrast is an empirical functional and not a uniform angular mean over the circle.

The symmetric decomposition of the difference between **fitted** sector means, in the model with linear radius and quadratic angles, is:

- change in the observed composition of amplitudes, angles and state: **+0.8574**;
- change in the response coefficients: **+0.4398**;
- sum: +1.2972; observed difference: +1.4287; unexplained residual: +0.1314.

The composition component has a wild p-value of 0.00005 and a Holm-16 value of 0.0008, and the response component a p-value of 0.06895 and a Holm-16 value of 0.4137. These are tests conditional on the fixed empirical distributions and on the normal continuation. The decomposition on the whole sample may extrapolate, and within the common support the composition remains positive (+0.5819), but the target changes and the unexplained residual increases (+0.8175). A percentage "explained by composition" should therefore not be presented as a stable or causal parameter.

## Status of the claims

**To be kept:** a positive association between the amplitude of the surprises and abnormal bipower volatility in both epochs, the predictive inadequacy of quadratic growth relative to the linear alternatives considered, and documented and relevant differences in composition.

**To be withdrawn as established conclusions:** "in 2000–2012 only equity information matters", "the structural MP–CBI ordering has certainly reversed" and "everything depends on composition". The first two linear forms predict similarly and do not establish the same ordering with equal precision.

**To be circumscribed:** the sector heterogeneity across epochs is an exploratory result that depends on the angular form, with a signal present in some specifications and a reduced common support. The failure to reject does not demonstrate equivalence, and no economic equivalence threshold had been declared for these contrasts. No further specifications need to be pursued in order to close this part of the paper with this limit.

All tests use 19,999 wild draws by meeting. The CSV files also contain unrestricted pointwise 95 percent bootstrap-t intervals, which are not inversions of the restricted test and may give different verdicts in finite samples. The Holm p-values remain the reference for decisions within the declared families. The uncertainty from generated regressors, from the selection of the support and from the empirical target is not integrated. The US calendar remains the inherited one, with candidate coincidences and not verified releases. These are not confirmatory results or evidence of causality.

## Reproducibility

The package includes derived event inputs with SHA-256 hashes, provenance, the exploratory protocol written before the new comparisons between epochs, the executed sources and all tables. `Prepare_cross_epoch_inputs.py` rebuilds the inputs from the opened archives, and `Run_cross_epoch_checks.py` replicates the diagnostics using the included inputs. It modifies neither pre-existing outputs nor the guards of the protected sample. The patch added the comparison to the authorized clone and included the earlier functional correction where missing. No commit or push was performed.
