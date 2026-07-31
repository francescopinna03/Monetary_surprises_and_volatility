%% DRIVER FOR CERTIFICATION, PHASE WINDOWS, MP-CBI SHOCKS AND COUNTERFACTUALS.

clear; clc;

mode = lower(strtrim(string(getenv('PHASE_EXTENSION_MODE'))));
if strlength(mode) == 0
    mode = "all";
end
if ~ismember(mode, ["certify", "build", "all"])
    error('PHASE_EXTENSION_MODE must be certify, build or all.');
end

fprintf('Phase extension start %s | mode=%s\n', string(datetime('now')), mode);

if ismember(mode, ["certify", "all"])
    fprintf('\n[certification] Window_semantics_certification\n');
    Window_semantics_self_test();
    Window_semantics_certification;
end

if ismember(mode, ["build", "all"])
    fprintf('\n[22/27] Phase windows, shock components and counterfactuals\n');
    Phase_window_self_test();
    Shock_component_self_test();
    Phase_window_construction;
    Shock_component_construction;

    previousPhase = string(getenv('ANNOUNCEMENT_PHASE'));
    for phase = ["PR", "PC", "ME"]
        setenv('ANNOUNCEMENT_PHASE', phase);
        Announcement_phase_counterfactual();
    end
    setenv('ANNOUNCEMENT_PHASE', previousPhase);

    fprintf('\n[23/27] Component_sufficiency_analysis\n');
    Component_sufficiency_self_test();
    Component_sufficiency_analysis();

    fprintf('\n[24/27] Phase_component_contrasts\n');
    Phase_component_contrast_self_test();
    Phase_component_contrasts();

    fprintf('\n[25/27] Invariant_phase_attribution\n');
    Invariant_phase_attribution_self_test();
    Invariant_phase_attribution();

    fprintf('\n[26/27] Long_horizon_phase_attribution\n');
    Long_horizon_phase_attribution_self_test();
    Long_horizon_phase_attribution();
end

fprintf('Phase extension end %s | mode=%s\n', string(datetime('now')), mode);
