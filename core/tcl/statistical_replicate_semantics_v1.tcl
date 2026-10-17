# Aligned replicate profiles: CORE meaning only; Numeric owns all arithmetic.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_replicateAssumptions {mode sampling} {
    set assumptions {{Aligned coordinate rows summarize contributing curves, not the original raw point count} {Plus/minus spread and SEM envelopes are descriptive; they are not confidence or prediction intervals}}
    if {$mode eq "labelled_traces_anova"} {
        lappend assumptions {Source components use a one-way random-effects moment estimator with unequal group counts; negative between-source variance estimates are truncated to zero and explicitly flagged} {Physical variance attribution requires independent exchangeable source effects and a common within-source variance; curve labels alone do not establish these assumptions}
    } else {
        lappend assumptions {Unlabelled clouds provide no independent replicate count or sampling SEM} {Local residual RMS and spread of source locations are combined heuristically; they can overlap and are not identified physical variance components} {A coordinate with unavailable local dispersion has unavailable components; valid neighbouring coordinates remain usable}
    }
    if {$sampling eq "independent_traces"} {lappend assumptions {SEM assumes independent contributing traces with a common sampling distribution; this caller-declared assumption is not verified from labels}} else {lappend assumptions {No independent-trace sampling model was declared; SEM is unavailable}}
    return $assumptions
}
proc ::GX::StatisticsV1::_validateReplicate {numerical context} {
    set mode [_get $context mode {}];set sampling [_get $context sampling_model {}]
    if {$mode ni {labelled_traces_anova unlabelled_point_cloud}||$sampling ni {unspecified independent_traces}||![dict exists $context y_unit]} {_error {Replicate profiles require actual response units, mode and sampling model}}
    if {$mode eq "unlabelled_point_cloud"&&$sampling ne "unspecified"} {_error {Cloud profiles cannot infer independent repeat sampling}}
    set method [expr {$mode eq "labelled_traces_anova" ? "one_way_random_effects_unequal_counts_nonnegative_between" : "local_residual_rms_plus_source_location_spread"}]
    if {[_get $context component_method {}] ne $method||[_get $context assumptions {}] ne [_replicateAssumptions $mode $sampling]} {_error {Replicate profile must preserve the CORE method and assumption definitions}}
    foreach key {replicate_trace_count replicate_source_count} {
        set value [_get $numerical $key {}]
        if {![_finite $value]||$value<1||$value!=floor($value)} {_error {Replicate trace and source counts must be positive integers}}
    }
    set n [dict get $numerical replicate_trace_count];set ns [dict get $numerical replicate_source_count]
    if {$ns>$n||($mode eq "unlabelled_point_cloud"&&$ns!=$n)} {_error {Replicate source identities disagree with the contributing curve count}}
    set available [_get $numerical replicate_components_available {}]
    if {![_finite $available]||$available ni {0 0.0 1 1.0}||($available&&$ns<2)} {_error {Invalid source-component availability fact}}
    if {$mode eq "labelled_traces_anova"} {
        set df [_get $numerical replicate_within_df {}]
        if {![_finite $df]||$df!=$n-$ns||$available!=($ns>=2&&$df>0)} {_error {Replicate within-source count and component eligibility disagree}}
        if {$available} {
            set coefficient [_get $numerical replicate_component_coefficient {}]
            set clamped [_get $numerical replicate_between_clamped {}]
            if {![_finite $coefficient]||$coefficient<=0||$clamped ni {0 0.0 1 1.0}} {_error {Source components require positive group coefficient and explicit truncation fact}}
        }
    }
    foreach key {replicate_dispersion replicate_sem replicate_within replicate_between replicate_total} {
        set value [_get $numerical $key {}]
        if {[_finite $value]&&$value<0} {_error {Replicate spread facts must be nonnegative}}
    }
}
proc ::GX::StatisticsV1::_replicatePolicy {quantity profile numerical context} {
    if {$profile ne "replicate_profile"} {return {not_applicable {Quantity requires a registered aligned replicate profile}}}
    set mode [dict get $context mode];set n [dict get $numerical replicate_trace_count]
    if {$quantity in {replicate_within_df replicate_component_coefficient replicate_between_clamped}&&$mode eq "unlabelled_point_cloud"} {return {not_applicable {Cloud residual scatter is not a labelled random-effects ANOVA decomposition}}}
    if {$quantity in {replicate_sem replicate_lower_sem replicate_upper_sem}} {
        if {$mode eq "unlabelled_point_cloud"||[dict get $context sampling_model] ne "independent_traces"} {return {unavailable {An independent-trace sampling model is required; labels and raw point count do not establish it}}}
    }
    if {$quantity in {replicate_dispersion replicate_lower_std replicate_upper_std replicate_sem replicate_lower_sem replicate_upper_sem}&&$n<2} {return {undefined {A single contributing curve does not identify sample dispersion or SEM}}}
    if {$quantity in {replicate_within replicate_between replicate_total replicate_lower_total replicate_upper_total replicate_between_clamped replicate_component_coefficient}&&![dict get $numerical replicate_components_available]} {return {unavailable {Source decomposition lacks replicated groups or valid local dispersion at this coordinate}}}
    return {value {}}
}
