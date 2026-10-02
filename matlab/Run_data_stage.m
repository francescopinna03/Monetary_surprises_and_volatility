diary(fullfile(fileparts(mfilename('fullpath')), 'data_stage_run.log'));

fprintf('Data stage start %s\n', string(datetime('now')));
projectRoot = Get_project_root();
surpriseSource = Surprise_source_config(projectRoot);
setenv('SURPRISE_SOURCE', surpriseSource.source_id);
fprintf('Data root: %s\n', projectRoot);
fprintf('Surprise source: %s (%s)\n', surpriseSource.source_id, surpriseSource.dataset_name);

fprintf('\n[preflight] Time_alignment_self_test\n');
Time_alignment_self_test();

fprintf('\n[preflight] Surprise_source_self_test\n');
Surprise_source_self_test();

fprintf('\n[1/4] Audit_Barchart\n');
Audit_Barchart;

fprintf('\n[2/4] Clean_raw_files\n');
Clean_raw_files;

fprintf('\n[3/4] Contract_event_day\n');
Contract_event_day;

fprintf('\n[4/4] Event_panel_construction\n');
Event_panel_construction;

fprintf('\n[audit] Event_time_alignment_audit\n');
Event_time_alignment_audit;

Window_semantics_self_test;
Window_semantics_certification;

fprintf('\nData stage complete %s\n', string(datetime('now')));
diary off
