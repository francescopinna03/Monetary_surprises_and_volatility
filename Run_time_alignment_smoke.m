%% TIME-ALIGNMENT SMOKE RUN: PREFLIGHT AND STEPS 1--5 ONLY.

clear; clc;

repoDir = fileparts(mfilename('fullpath'));
diary(fullfile(repoDir, 'time_alignment_smoke_run.log'));

fprintf('Time-alignment smoke start %s\n', string(datetime('now')));
fprintf('Data root: %s\n', Get_project_root());

fprintf('\n[preflight] Time_alignment_self_test\n');
Time_alignment_self_test();

fprintf('\n[1/5] Audit_Barchart\n');
Audit_Barchart;

fprintf('\n[2/5] Clean_raw_files\n');
Clean_raw_files;

fprintf('\n[3/5] Contract_event_day\n');
Contract_event_day;

fprintf('\n[4/5] Event_panel_construction\n');
Event_panel_construction;

fprintf('\n[audit] Event_time_alignment_audit\n');
Event_time_alignment_audit;

fprintf('\n[5/5] Event_windows\n');
Event_windows;

fprintf('\nTime-alignment smoke end %s\n', string(datetime('now')));
diary off;
