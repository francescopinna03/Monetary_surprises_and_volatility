diary(fullfile(fileparts(mfilename('fullpath')), 'pipeline_run.log'));

fprintf('Pipeline start %s\n', string(datetime('now')));
fprintf('Data root: %s\n', Get_project_root());

fprintf('\n[ 1/17] Audit_Barchart\n');
Audit_Barchart;

fprintf('\n[ 2/17] Clean_raw_files\n');
Clean_raw_files;

fprintf('\n[ 3/17] Contract_event_day\n');
Contract_event_day;

fprintf('\n[ 4/17] Event_panel_construction\n');
Event_panel_construction;

fprintf('\n[ 5/17] Event_windows\n');
Event_windows;

fprintf('\n[ 6/17] Press_release_panel\n');
Press_release_panel;

fprintf('\n[ 7/17] Regression_fractional\n');
Regression_fractional;

fprintf('\n[ 8/17] PR_signal_model\n');
PR_signal_model;

fprintf('\n[ 9/17] State_vector_panel\n');
State_vector_panel;

fprintf('\n[10/17] State_dependent_models\n');
State_dependent_models;

fprintf('\n[11/17] Shock_purification_models\n');
Shock_purification_models;

fprintf('\n[12/17] Functional_state_models\n');
Functional_state_models;

fprintf('\n[13/17] Volatility_components\n');
Volatility_components;

fprintf('\n[14/17] Hierarchical_shrinkage\n');
Hierarchical_shrinkage;

fprintf('\n[15/17] PR_bar_panel\n');
PR_bar_panel;

fprintf('\n[16/17] BNS_volatility\n');
BNS_volatility;

fprintf('\n[17/17] Quasi_markov_residual_predictability\n');
Quasi_markov_residual_predictability;

fprintf('\nPipeline end %s\n', string(datetime('now')));

diary off;
