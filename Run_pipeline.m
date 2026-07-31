diary(fullfile(fileparts(mfilename('fullpath')), 'pipeline_run.log'));

fprintf('Pipeline start %s\n', string(datetime('now')));
fprintf('Data root: %s\n', Get_project_root());

% The complete replication is an immutable final run.  Reduced-draw
% overrides are accepted only by the dedicated smoke-test wrappers; they must
% never leak into Run_pipeline through a caller's shell environment.
setenv('ANNOUNCEMENT_VALIDATION_DRAWS', '999');
setenv('ANNOUNCEMENT_ROTATION_DRAWS', '999');
setenv('ANNOUNCEMENT_RESOLUTION_MODE', 'final');
setenv('ANNOUNCEMENT_RESOLUTION_DRAWS', '999');
setenv('COMPONENT_SUFFICIENCY_DRAWS', '999');
setenv('PHASE_COMPONENT_CONTRAST_DRAWS', '999');
setenv('INVARIANT_ATTRIBUTION_DRAWS', '999');
setenv('LONG_HORIZON_ATTRIBUTION_DRAWS', '999');
setenv('RANK_ONE_FEASIBILITY_DRAWS', '999');
setenv('DYNAMIC_JUMP_FRONTIER_DRAWS', '999');
fprintf(['Locked inference draws: Steps 19--27 = 999; ' ...
    'Step 21 mode = final\n']);

fprintf('\n[preflight] Time_alignment_self_test\n');
Time_alignment_self_test();

fprintf('\n[ 1/27] Audit_Barchart\n');
Audit_Barchart;

fprintf('\n[ 2/27] Clean_raw_files\n');
Clean_raw_files;

fprintf('\n[ 3/27] Contract_event_day\n');
Contract_event_day;

fprintf('\n[ 4/27] Event_panel_construction\n');
Event_panel_construction;

fprintf('\n[audit] Event_time_alignment_audit\n');
Event_time_alignment_audit;

fprintf('\n[ 5/27] Event_windows\n');
Event_windows;

fprintf('\n[ 6/27] Press_release_panel\n');
Press_release_panel;

fprintf('\n[ 7/27] Regression_fractional\n');
Regression_fractional;

fprintf('\n[ 8/27] PR_signal_model\n');
PR_signal_model;

fprintf('\n[ 9/27] State_vector_panel\n');
State_vector_panel;

fprintf('\n[10/27] State_dependent_models\n');
State_dependent_models;

fprintf('\n[11/27] Shock_purification_models\n');
Shock_purification_models;

fprintf('\n[12/27] Functional_state_models\n');
Functional_state_models;

fprintf('\n[13/27] Volatility_components\n');
Volatility_components;

fprintf('\n[14/27] Hierarchical_shrinkage\n');
Hierarchical_shrinkage;

fprintf('\n[15/27] PR_bar_panel\n');
PR_bar_panel;

fprintf('\n[16/27] BNS_volatility\n');
BNS_volatility;

fprintf('\n[17/27] Quasi_markov_residual_predictability\n');
Quasi_markov_residual_predictability;

fprintf('\n[18/27] Announcement_counterfactual\n');
Announcement_counterfactual;

fprintf('\n[19/27] Announcement_counterfactual_validation\n');
Announcement_counterfactual_validation;

fprintf('\n[20/27] Announcement_risk_rotation\n');
Announcement_risk_rotation;

fprintf('\n[21/27] Announcement_risk_resolution\n');
Announcement_risk_resolution;

setenv('PHASE_EXTENSION_MODE', 'all');
Run_phase_extension;

fprintf('\n[27/27] Sequential rank-one and dynamic-jump feasibility\n');
Run_step27();

fprintf('\nPipeline end %s\n', string(datetime('now')));

diary off;
