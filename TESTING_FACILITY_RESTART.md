# Restart of the testing facility, 13 September 2026

*Record written on 13 September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `97aff55`. Paths refer to the author's machine at that date.*

Base: the facility ZIP archive and the GitHub reference `eaab00546b9919ef735c21a7bc64cea50b5860d8`. The main command is `bash Run_testing_facility.sh`, executed inside `~/Desktop/Monetary_surprises_testing_facility/Monetary_surprises_clone`. It creates no commit, publishes nothing to the repository and does not invoke the v2 freeze or estimation.

## Stages of the restart

1. It classifies the CSV files by contract year and moves those of 2000–2012 from `~/Desktop/Econometrics_data/Raw/Barchart_futures` to `Barchart_futures_confirmation`, in the same `Raw` directory. It keeps the whole life cycle of each contract and writes the plan, the hashes and a counter of the moves. It rejects collisions, unknown files, links and subfolders, and it does not delete duplicates in order to decide which version to use. It can be repeated.
2. It looks for the frozen build `final_resume_20260911_174739_4124` in the consolidated archive, and then in the earlier run, which is used as a read-only source. It verifies the hashes of the build and copies exactly the required inputs into `facility/runs/restart_*/generation/Econometrics_data`. It does not copy all outputs, does not inherit unrelated cleaned files and does not copy the new raw files. If the data root does not yet contain the two frozen manifests, it uses only the small archive `Raw/Certification/generation_recovery_20260911`, again after the SHA-256 check against `status.json`.
3. It runs `Run_final_matlab_checks` in that copy, selecting only the 2013–2025 events before the windows are built. The September build also includes 5 February and 19 March 2026, which are excluded and recorded, leaving the original frozen manifests and selection intact.
4. It writes `shrinkage_1se_comparison.csv`, verifying that the selected penalty is indeed the strongest within the band. The comparison with the `last` rule uses the same cross-validation just obtained and does **not** reconstruct the April results. The post-selection coefficients remain descriptive.
5. It runs the inventory and the quality audit with the explicit confirmation directory only. It also produces the opening and closing pairs by month, converted from UTC to Europe/Berlin. It does not search for CSV files in the Desktop or Downloads folders.
6. It runs `Run_step28_calibration_only` on the grid already declared, up to 500 meetings. This entry point does not call `Step28_sbb_panel`, the data gate, the empirical spectral gate or the bridge estimation. The result of the calibration is to be observed, and no negative outcome is imposed.

The command writes results and logs in `facility/runs/restart_*` and a ZIP archive `Monetary_surprises_restart_*_results.zip` in the facility. A failed MATLAB stage does not prevent the independent Python audits. Errors are reported in `status.json` and give exit code 2. The ZIP archive excludes copies of raw and cleaned files. The synthetic calibration can take a long time, and the log reports the current rank and G.

To repeat only one part:

```bash
bash Run_testing_facility.sh --mode generation
bash Run_testing_facility.sh --mode repair
bash Run_testing_facility.sh --mode evidence
bash Run_testing_facility.sh --mode calibration
```

`generation` includes the auxiliary checks and the synthetic calibration. `calibration` requires no empirical archive. `--generation-build`, `--recovery-root` and `--data-root` allow different paths without changing the code, and `MATLAB_BIN` and `PYTHON_BIN` accept full paths to the executables. `repair` repeats the separation, the generation auxiliaries and the complete confirmation audit, but does not rerun the Step 28 calibration already completed.

To see only the separation plan, before applying it:

```bash
../python_env/bin/python facility_archive.py \
  --data-root "$HOME/Desktop/Econometrics_data" \
  --output "../runs/split_preview_$(date +%Y%m%d_%H%M%S)"
```

The main launcher applies the separation authorized by the checklist. An interruption during the moves keeps the journal and the lock, in which case `archive/status.json` and `archive/archive_plan.csv` must be read before intervening, and the lock must not be removed blindly.

## Corrections to the checklist

`Run_final_matlab_checks` does not include Step 28. Moreover, `Run_step28_gates` is not a purely synthetic command, since after the calibration it reads the empirical panel and may proceed to the subsequent gates. For item 2.2 of the checklist the new entry point `Run_step28_calibration_only` must be used.

The separation by contract year protects the inputs but does not define event dates, because contracts have a life cycle. For this reason the auxiliary rerun also checks the dates in the frozen selection before extracting the window prices. The complete historical MATLAB pipeline is distinct from this rerun, is not started automatically and must not be used as a confirmatory estimator.

## Documentary evidence on Eurex trading hours

[Circular 160/05, p. 2](https://www.eurexchange.com/resource/blob/291688/ef9332b8a52784228080a520919ec537/data/cf1602005e.pdf.pdf) gives **21 November 2005** as the date of the extension to 22:00. The [contract specifications in force from 21 November 2005, p. 10](https://www.eurex.com/resource/blob/334472/1c0ac054e1cec9974271e8a20a5588a5/data/cs_history_21112005_en.pdf.pdf) show, in the table of changes, the move from 08:00–19:00 to 08:00–22:00 for Schatz, Bobl and Bund. The text extraction of the PDF must not be used to choose between struck-through and new figures, and the page was checked visually.

In the metadata of the attached inventory `20260912_152519_9603`, the first session whose last label is at 22:00 Europe/Berlin is exactly 2005-11-21 for all three roots. The coincidence confirms the date of the change, not the bar semantics.

The [2011 Eurex calendar, p. 1](https://www.eurex.com/resource/blob/283130/b4c195865615cd3f92287e355a06efe4/data/tradingcalendar_2011_en.pdf) gives 08:00–22:00 for the curve but **07:50–22:00 for FESX**, so the two `all` rows of the checklist are not a valid schedule for every root. The official archive of the calendars is https://www.eurex.com/ex-en/trade/trading-calendar/trading-calendar-archive.

`config/eurex_trading_hours.csv` is filled in with 35 rows referring to documented periods. The reviewer named for the documentary reading is Codex, not Francesco Pinna. The URLs and hashes of the thirteen downloaded calendars are in `eurex_trading_hours_sources.json`. The files for 2001–2003 contain the calendar of dates but not the table of hours, so those days remain without a schedule instead of inheriting presumed hours. The years 2000, 2004, the last part of 2005 and 2006–2012 are covered, hence at least one year in every three-year cell of the protocol. The bar evidence is produced as a candidate and is not promoted automatically.

The [2000 calendar, p. 2](https://www.eurex.com/resource/blob/289252/e667a61086fff75980e01a01b367eda5/data/tradingcalendar_2000_en.pdf) gives 08:00–19:00 for the three curve roots, and the [2012 calendar, p. 1 and note 5](https://www.eurex.com/resource/blob/284994/e988f1cef4437150c0a74a5a8f285d64/data/tradingcalendar_2012_en.pdf) also confirms the auction after the end of continuous trading.

The two-boundary test can be inconclusive even with an exact schedule. In the metadata a first bar at 08:00 and a last bar at 19:00 or 22:00 are frequent, and this pair matches neither of the two pairs expected by the current test. A last trade or a print at the boundary must not be turned into automatic evidence of `interval_start` or `interval_end`. If the test remains open, evidence from the provider is needed, and the threshold is not lowered to let the gate pass.

## Order of the two quality audits

The first `--mode evidence` produces `confirmation_quality_first/primary_files.csv`. If a reviewed schedule already exists, it also produces `bar_label_candidates`. Otherwise, `--mode evidence` must be run again after the schedule has been completed. The promotion of the candidates requires the reviewer and the rule already described in `CONFIRMATION_EVIDENCE_V2.md`, and the launcher does not sign on behalf of the reviewer.

After `bar_label_evidence_v2.csv` has been promoted into `Econometrics_data/Raw/Certification`, `--mode evidence` must be repeated, and the new execution writes `confirmation_quality_second` and consumes the new evidence. Redoing the inventory in that pass also avoids reusing the hashes of a calendar modified after the first audit. The name "second" alone does not certify the result, and `all_nonempty_files_label_verified` and the other fields of `status.json` must be checked.

## Open items before the v2 estimation

The completed calendar queue is not contained in the facility ZIP archive. The promotion and the cross-checks listed in the checklist remained, and the 179 meetings were a forecast and not a count certified by this intervention.

The review of the bar evidence, the five decisions, the protected build and the reading of the floors before the freeze also remained, as the checklist requires. These modules already exist in the attached code. Two limits must remain visible, namely that `readiness.py` keeps some fixed `False` values (session review and external timing) and that `freeze.py` does not treat that report as a single gate, and that `calibrate.py` uses OIS 1Y as a proxy for the Schatz coordinate that is used in the primary estimation, so its floors do not automatically certify power in the other metric. The freeze must not be started merely because the commands exist or because the calendar has been promoted.

This delivery closes the start of the work that could be executed on that day. It does not declare the confirmation closed and does not start the pipeline on the unified sample.
