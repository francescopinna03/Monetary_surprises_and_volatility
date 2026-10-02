function cfg = Final_window_config()
    cfg.version = "final_analysis_v1";
    cfg.barMinutes = 5;
    cfg.prEndpoints = (5:5:25)';
    cfg.pcEndpoints = (5:5:45)';
    cfg.preEndpoints = (-55:5:-5)';
    cfg.primaryRoots = ["fx", "gg"];
    cfg.robustnessRoots = ["fx", "gg", "hf", "hr"];
end
