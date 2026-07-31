function endTime = Canonical_bar_end_time(providerTimeUtc, barMinutes, barSemantics)
%CANONICAL_BAR_END_TIME Convert provider labels to interval-end UTC clocks.

    providerTimeUtc = Parse_utc_datetime(providerTimeUtc);
    barSemantics = string(barSemantics);
    if barSemantics == "interval_start"
        endTime = providerTimeUtc + minutes(barMinutes);
    elseif barSemantics == "interval_end"
        endTime = providerTimeUtc;
    else
        error('BAR_SEMANTICS_UNRESOLVED: expected interval_start or interval_end.');
    end
end
