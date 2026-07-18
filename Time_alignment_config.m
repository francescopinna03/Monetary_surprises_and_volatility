function cfg = Time_alignment_config()
%TIME_ALIGNMENT_CONFIG Frozen clock conventions for the replication pipeline.
%
% Barchart futures exports used by this project are wall-clock timestamps in
% America/Chicago. ECB calendar times are Frankfurt/Berlin wall-clock times.
% Every comparison is carried out on timezone-neutral datetime values whose
% displayed clock is UTC. The timezone is deliberately stripped only after
% conversion so CSV round-trips cannot silently apply the computer's locale.

    cfg = struct();
    cfg.schema_version = "timezone_v1";
    cfg.raw_provider = "Barchart";
    cfg.raw_time_zone = "America/Chicago";
    cfg.event_time_zone = "Europe/Berlin";
    cfg.analysis_time_zone = "UTC";
    cfg.cleaned_time_column = "Time";
    cfg.cleaned_time_semantics = "timezone-neutral datetime displaying UTC";
    cfg.bar_label_semantics = "provider label used as the five-minute return endpoint";
end
