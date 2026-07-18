# Research reset: from state amplification to announcement risk rotation

> **Superseded evidence notice (2026-07-18).** This document records the
> research path based on event windows constructed before the Barchart/ECB
> timezone error was discovered. Those Barchart outcomes were measured roughly
> six or seven hours after the scheduled release. The Step-18 through Step-21
> empirical conclusions below, including `FAIL_RISK_RESOLUTION`, are void until
> all twenty-one steps are rerun under `timezone_v1`. See
> `TIMEZONE_CORRECTION_PROTOCOL.md`. The document is retained as an audit trail,
> not as the current assessment of the hypothesis.

## Historical bottom line (superseded)

Before discovery of the clock error, the working conclusion was that the
original headline claim should be retired. That conclusion is no longer
supported by a valid event-window measurement and must not be cited as a
result. The same applies to the apparent Bund--equity contrast described
below.

The revised working paper asks whether ECB announcements merely inject a common monetary shock or instead create risk in one cross-asset direction while resolving pre-existing uncertainty in another. This question uses the paired cross-asset structure of the data, does not depend on the weak support of squared OIS surprises, and yields a falsifiable matrix restriction.

## Historical post-Step-20 update (superseded)

Step 20 identifies the negative, equity-dominated direction but not the
positive Bund-dominated direction. The bootstrap interval for the smallest
eigenvalue lies below zero, whereas the interval for the largest eigenvalue
crosses zero. The project therefore does not claim simultaneous risk creation
and resolution. Its surviving proposition is narrower: scheduled ECB
announcements may resolve pre-existing equity risk relative to normal
intraday continuation.

Step 21 is the binding bias-adjusted test of that proposition. It applies
common-support trimming, leave-year-out control-only continuation models and a
bootstrap that re-estimates the entire nuisance and matching procedure. The
locked specification and pass/fail rule are recorded in `STEP21_PROTOCOL.md`.

## What happened to the original project

| Stage | Maintained idea | What the audit changes |
| --- | --- | --- |
| Original levels model | Signed target surprises shift a positive volatility outcome, with a slope affine in the pre-announcement state. | A volatility measure is quadratic by construction. A signed linear shock is not the natural primitive. The `asinh` transformation is numerically the identity at the observed scale. |
| State-amplification result | The interaction between the signed surprise and pre-announcement tension is the main channel. | The original state window overlaps the original outcome window. Mechanical covariance and outcome scale can generate a large levels interaction. |
| Continuous/jump localization | The interaction is concentrated in bipower variation rather than jump variation. | Roughly ten five-minute returns are too few for a strong continuous-versus-jump interpretation. Truncated `RV-BV` is a descriptive split, not a formal jump classification. |
| Base--multiplier rewrite | Tension scales the volatility base; the relative multiplier is invariant to the state. | The log-state interaction is statistically weak, but failure to reject is not invariance. The paper also moves between `E[log QV|X]` and `log E[QV|X]`, which are distinct objects. |
| Non-event counterfactual | Squared surprise energy explains volatility beyond normal pre/post propagation. | The normal continuation model predicts ordinary days well, but the monetary slope and state interaction fail wild-bootstrap, two-stage-bootstrap and matched-placebo validation. |
| Support validation | The OIS energy regressor supplies enough independent event variation. | Surprise energy is dominated by one or two events and is highly collinear with its state interaction. Deleting those events changes the interaction materially. |

The sufficient-state or quasi-Markov interpretation is therefore no longer part of the core paper. It was an interpretation of a response surface that the decisive counterfactual does not identify.

## The fact that survives

Across the stacked, two-stage and matched designs, the Euro Bund coefficient relative to Euro Stoxx is stable and positive for abnormal log bipower and realized variance, while it is negative for the jump share. Direct paired date calculations give the same sign and are not driven by the largest OIS surprises. This is not yet a paper: a simple announcement-versus-control volatility contrast has close predecessors. It is, however, the empirical clue from which a sharper proposition can be built.

## Revised economic object

For date \(d\) and five-minute interval \(m\), collect standardized futures returns in

\[
r_{dm}=\begin{bmatrix}r^{FX}_{dm} & r^{GG}_{dm}\end{bmatrix}'.
\]

For equally long pre- and post-release windows, define the realized second-moment matrices

\[
Q_d^- = \frac{1}{M}\sum_{m\in\mathcal W^-} r_{dm}r_{dm}',
\qquad
Q_d^+ = \frac{1}{M}\sum_{m\in\mathcal W^+} r_{dm}r_{dm}',
\qquad
D_d=Q_d^+-Q_d^-.
\]

Each ECB date is matched to non-event dates using only pre-release covariance, slow volatility, release-clock regime, weekday and calendar proximity. The estimand is

\[
A = E\!\left[D_d-\sum_{c\in\mathcal C(d)}w_{dc}D_c\mid d\in ECB\right].
\]

This is the abnormal change in the joint second-moment matrix, not a coefficient on a noisy surprise measure.

## A null with economic content

If an announcement only adds one innovation \(u_d\) with loading vector \(b\), while the background covariance evolves as on matched ordinary days, then

\[
A=\sigma_u^2bb'.
\]

The matrix must be positive semidefinite and have rank no greater than one. This is the additive one-shock null.

Now suppose the announcement both reveals news and resolves an uncertainty factor \(\eta_d\) that was active before the release:

\[
A=\sigma_u^2bb'-\sigma_\eta^2cc'.
\]

The positive component is risk injected by announcement news; the negative component is risk removed when uncertainty is resolved. If \(b\) and \(c\) span different cross-asset directions, \(A\) is indefinite. Its signed spectral decomposition is

\[
A=\lambda_+v_+v_+'+\lambda_-v_-v_-',
\qquad \lambda_+>0>\lambda_-.
\]

The labels “news creation” and “uncertainty resolution” are earned only if the eigenvalue signs survive date bootstrap and matched placebos and if the loadings have an economically coherent, stable interpretation.

## Decisive outcomes

1. **Indefinite matrix survives.** The confidence interval for \(\lambda_+\) lies above zero, that for \(\lambda_-\) lies below zero, and matched-placebo probabilities support both signs jointly. This is the route to a revised working paper on creation and resolution of risk.
2. **Positive semidefinite, approximately rank-one matrix.** The data support an additive announcement shock, but not the state-amplification story. The paper becomes narrower and must be positioned against the announcement covariance/rank literature.
3. **Unstable or placebo-like spectrum.** The surviving root contrast was another fragile summary. The project should be retired rather than expanded with additional specifications.

## Econometric discipline

- The unit of inference is the event date, not the duplicated event--asset row.
- FX and GG must be observed on the same exact return grid.
- Pre and post windows must have equal duration and no overlap.
- Return scaling is estimated on non-event dates only; diagonal scaling cannot manufacture or remove matrix indefiniteness.
- Matching uses only variables known before the pseudo-release clock.
- OIS surprises are secondary mechanism variables. They do not define the treatment or the principal estimand.
- Eigenvalue signs, eigenvector loadings, the GG-minus-FX diagonal contrast, bootstrap intervals and matched-placebo tails are reported together.
- No search over windows, states or transformations is allowed before the principal test is evaluated.

## Working-paper architecture if the test survives

1. Motivation: scheduled announcements may simultaneously create news risk and resolve policy uncertainty.
2. Identification: matched non-event changes and the additive one-shock matrix restriction.
3. Data: paired Euro Stoxx 50 and Euro Bund five-minute futures, exact event-time grid and pre-information contract selection.
4. Main result: signed spectrum of the abnormal second-moment matrix.
5. Dynamics: a pre-declared cumulative version of the matrix across the ten post-release bars, used to show when the positive and negative components emerge.
6. Mechanisms: target/path surprises, hiking regime and communication subsamples only after the unconditional matrix result is established.
7. Robustness: alternative match counts, leave-event-out spectra, clock/weekday placebos and window perturbations declared in advance.

The title should remain provisional until the spectrum is known. A viable placeholder is *News and Relief: Risk Rotation at ECB Announcements*.
