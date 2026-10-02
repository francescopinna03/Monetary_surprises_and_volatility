# Provenance

## Status of the results

Every result of the paper belongs to one of three categories, recorded in the manifest of the run that produced it.

| Category | Meaning | Results |
|---|---|---|
| Frozen | Hypotheses, sample, specification and decisions fixed before any outcome of the sample was computed, with a single estimation | Cone tests on ECB 2000–2012 |
| Pre-registered | Hypotheses written in a protocol signed and committed before any outcome of the sample was computed | F1, F2 and F3 on FOMC 2008–2026 |
| Post-opening | Analyses designed after the outcomes of the sample had been seen | Every ECB result on the amplitude law, its shape, its robustness and the measurement-error check |

The ECB sample of 2013–2025 generated the original design and was never a confirmation sample. The ECB sample of 2000–2012 was frozen on 14 September 2026 and opened after its single estimation, with a declared second estimation on 15 September 2026 after a correction of scale. The amplitude law was found on both ECB samples after opening and was then tested on the FOMC sample, which had not been used for any earlier analysis.

## The FOMC protocol

The protocol `Raw/Certification/fed_protocol_v1.json` was signed on 29 September 2026, after the release times had been checked against the reaction of the two coordinates and the bar counts of every window had been tallied, and before any post-window price of the ten-year contract had been read. It was amended once, after its first signature and before it was committed or any run took place. The amendment rewrote F3, which in its first version stated only that the elasticity is below one and would therefore have been satisfied by a null effect, as an intersection–union test of a positive elasticity below one, added the completeness rule and set the review date in ISO format. The replication was run once under the committed protocol, whose hash, `296e6acb9bedc40e4f3f9254a66d39d44f3559e853f31f0a7d173ef4759a25a9`, is recorded in its manifest.

## Runs and archived outputs

The runs were executed in a private development repository. Their aggregate outputs and manifests are archived in `reference_outputs/paper` and `reference_outputs/cross_epoch_20260916`, with event-level panels excluded. Each manifest records the development commit, the hashes of the executed code and of the inputs, and the versions of the numerical libraries.

| Run | Date | Archive | Status |
|---|---|---|---|
| Confirmation freeze and second estimation | 14–15 September 2026 | `ecb_confirmation_20260915` | Frozen |
| Cross-period comparison | 16 September 2026 | `cross_epoch_20260916` | Post-opening |
| One-minute outcomes | 28 September 2026 | `ecb_minute_20260928` | Post-opening |
| Radial exponent and sector information | 28 September 2026 | `ecb_design_information_20260928` | Post-opening |
| FOMC replication | 29 September 2026 | `fomc_replication_20260929` | Pre-registered |
| FOMC post-replication decomposition | 30 September 2026 | `fomc_post_replication_20260930` | Descriptive |
| Measurement-error check | 30 September 2026 | `measurement_check_20260930` | Post-opening |

The code published here is the code of the development repository at the state of 30 September 2026, with comments removed from newly added files and the runners moved into `scripts/`. Because the integrity guards described below compare byte-level hashes, the manifest hashes refer to the development files and not to the published ones. Reproduction is verified on the results instead: rerunning the FOMC replication from this repository on the same inputs reproduces the archived family of tests exactly, and `scripts/Make_paper_tables.py` reproduces every number in the tables of the paper from the archived outputs.

## Integrity guards

Three mechanisms protect the results. Confirmatory stages refuse to estimate on a build whose code hashes differ from those recorded at the freeze, so that a frozen result cannot be recomputed with different code. The FOMC replication refuses to run without a signed protocol and records its hash. Post-opening analyses label their outputs as such and never overwrite confirmatory outputs. The first guard implies that the estimation on the frozen 2000–2012 build and the preparation of the cross-period inputs, both of which check the hashes of the code against frozen builds, cannot be re-executed on those builds with the published code. Their archived outputs remain the record, and every other stage runs from this repository.

## Research history

The main branch contains only what the paper uses. The tag `research-history-2026-10-02` preserves the repository as it stood before this reorganization, including the complete MATLAB pipeline of twenty-eight steps, the earlier sign-based, rotation and dynamic designs, the testing facility and their records.
