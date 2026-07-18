diary(fullfile(fileparts(mfilename('fullpath')), 'pipeline_run.log'));

fprintf('Pipeline start %s\n', string(datetime('now')));
fprintf('Data root: %s\n', Get_project_root());

fprintf('\n[ 1/21] Audit_Barchart\n');
Audit_Barchart;

fprintf('\n[ 2/21] Clean_raw_files\n');
Clean_raw_files;

fprintf('\n[ 3/21] Contract_event_day\n');
Contract_event_day;

fprintf('\n[ 4/21] Event_panel_construction\n');
Event_panel_construction;

fprintf('\n[ 5/21] Event_windows\n');
Event_windows;

fprintf('\n[ 6/21] Press_release_panel\n');
Press_release_panel;

fprintf('\n[ 7/21] Regression_fractional\n');
Regression_fractional;

fprintf('\n[ 8/21] PR_signal_model\n');
PR_signal_model;

fprintf('\n[ 9/21] State_vector_panel\n');
State_vector_panel;

fprintf('\n[10/21] State_dependent_models\n');
State_dependent_models;

fprintf('\n[11/21] Shock_purification_models\n');
Shock_purification_models;

fprintf('\n[12/21] Functional_state_models\n');
Functional_state_models;

fprintf('\n[13/21] Volatility_components\n');
Volatility_components;

fprintf('\n[14/21] Hierarchical_shrinkage\n');
Hierarchical_shrinkage;

fprintf('\n[15/21] PR_bar_panel\n');
PR_bar_panel;

fprintf('\n[16/21] BNS_volatility\n');
BNS_volatility;

fprintf('\n[17/21] Quasi_markov_residual_predictability\n');
Quasi_markov_residual_predictability;

fprintf('\n[18/21] Announcement_counterfactual\n');
Announcement_counterfactual;

fprintf('\n[19/21] Announcement_counterfactual_validation\n');
Announcement_counterfactual_validation;

fprintf('\n[20/21] Announcement_risk_rotation\n');
Announcement_risk_rotation;

fprintf('\n[21/21] Announcement_risk_resolution\n');
Announcement_risk_resolution;

fprintf('\nPipeline end %s\n', string(datetime('now')));

diary off;
