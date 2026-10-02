function calibration = Run_step28_calibration_only()
    path = string(getenv('STEP28_SBB_SPECIFICATION'));
    assert(strlength(path)>0, 'STEP28_CALIBRATION_SPEC_REQUIRED');
    out = string(getenv('STEP28_CALIBRATION_OUTPUT'));
    assert(strlength(out)>0 && exist(out,'dir')~=7, 'STEP28_CALIBRATION_FRESH_OUTPUT_REQUIRED');
    specification = Step28_sbb_specification(path);
    mkdir(out);
    copyfile(path, fullfile(out, 'specification.csv'));
    Step28_gates_self_test();
    calibration = Step28_sample_size_calibration(struct(         'meetingGrid', specification.calibration_meeting_grid,         'frontierEigengap', specification.calibration_frontier_eigengap,         'projectorTolerance', specification.calibration_projector_tolerance,         'trueRank', specification.calibration_true_rank,         'positions', specification.calibration_positions,         'replications', specification.calibration_replications,         'parallelDraws', specification.spectral_parallel_draws,         'parallelQuantile', specification.spectral_parallel_quantile,         'reconstructionFolds', specification.spectral_reconstruction_folds, 'seed', specification.bootstrap_seed));
    writetable(calibration.profile, fullfile(out, 'step28_sample_size_calibration.csv'));
    save(fullfile(out, 'calibration.mat'), 'calibration', 'specification');
    status = table("complete_synthetic_calibration", false, false,         calibration.minimum_meetings, string(calibration.status), File_sha256(path),         'VariableNames', {'status','event_outcomes_read','empirical_gate_run', 'minimum_meetings','calibration_status','specification_sha256'});
    writetable(status, fullfile(out, 'status.csv'));
    disp(status);
end
