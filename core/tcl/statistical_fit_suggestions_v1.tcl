# Advisory model eligibility and captured comparison reuse. Shape arithmetic
# belongs to Numeric; no candidate is fitted or accepted here.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::fitSuggestions {numeric candidates context {entries {}} {criterion aicc}} {
    _suggestionFacts $numeric
    _keys $context {x_unit y_unit orientation x_variable_id y_variable_id observation_binding} fit_suggestion_context
    set orientation [_get $context orientation y_of_x]
    if {$orientation ni {y_of_x x_of_y}} {_error {Source advice requires a functional orientation}}
    foreach key {x_variable_id y_variable_id} {if {[dict exists $context $key]} {_physicalText [dict get $context $key] $key 256}}
    foreach key {x_unit y_unit} {_physicalText [dict get $context $key] $key 256}
    if {[llength $candidates]>64||[llength $entries]>64} {_error {Model suggestions support at most 64 explicit candidates or retained fits}}
    if {$criterion ni {aic aicc}} {_error {The advisory assistant supports explicit AIC or AICc ranking}}
    if {[dict exists $context observation_binding]} {_observationBinding [dict get $context observation_binding]}
    set n [dict get $numeric observation_count];set shape [expr {[dict get $numeric shape_status] eq "value"}]
    set constant [dict get $numeric constant_response];set rows {};set ids {};set order {}
    foreach candidate $candidates {
        _keys $candidate {id model_id label} fit_suggestion_candidate
        foreach key {id model_id label} {if {![dict exists $candidate $key]} {_error "Candidate requires $key"}}
        set id [dict get $candidate id];set mid [dict get $candidate model_id]
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,127}$} $id]||$id in $ids} {_error {Suggestion candidate IDs must be distinct canonical identifiers}}
        _physicalText [dict get $candidate label] label 256;lappend ids $id
        set descriptor [model $mid]
        set row [dict merge $candidate [dict create status manual_definition suggested 0 priority 100 reason {An explicit scientific model or geometry definition is required; source shape alone cannot supply it} options {}]]
        set minimum 0;set hint 0;set reason {};set priority 80;set options {}
        switch -- $mid {
            math.numeric.linear {set minimum 2;set hint [dict get $numeric linear_like];set priority 10;set reason {A line is a simple functional baseline; endpoint-chord agreement is only a shape hint}}
            math.numeric.polynomial {set minimum 3;set hint [expr {$shape&&!$constant&&![dict get $numeric linear_like]}];set priority 50;set options {degree 2};set reason {A quadratic is an explicitly reviewable curvature candidate, not proof of a polynomial mechanism}}
            math.numeric.exponential {set minimum 3;set hint [expr {$shape&&!$constant&&[dict get $numeric monotonic] in {increasing decreasing}}];set priority [expr {[dict get $numeric saturating_hint]?10:40}];set reason {Monotonic or saturating shape can motivate an exponential; inspect offset, sign and physical mechanism}}
            math.numeric.power_law {set minimum 2;set hint [expr {$shape&&!$constant&&[dict get $numeric monotonic] in {increasing decreasing}}];set priority 45;set reason {Power-law candidates require strictly positive physical predictors; coordinate translation changes the scientific model}}
            math.numeric.gaussian {set minimum 4;set hint [expr {$shape&&[dict get $numeric peak_count]+[dict get $numeric trough_count]==1}];set priority 10;set reason {One prominent interior peak or trough motivates a signed Gaussian; check baseline and coverage}}
            math.numeric.fourier {set minimum 5;set hint [dict get $numeric periodic_hint];set priority 10;set reason {Repeated extrema suggest a period for explicit review; they do not establish stationarity or periodicity};if {$hint} {set options [dict create order 1 period [dict get $numeric period]]}}
            math.numeric.pchip {set minimum 2;set hint $shape;set priority 90;set reason {Interpolation can preserve sampled functional shape; it is not a regression likelihood candidate}}
            math.numeric.smoothing_spline {set minimum 3;set hint $shape;set priority 95;set reason {Smoothing requires explicit regularization review and its own complexity assumptions}}
        }
        if {$minimum} {
            set status eligible
            if {[dict get $numeric status] ne "value"||[dict get $numeric distinct_predictors]<$minimum||$n<$minimum} {set status unavailable;set reason {Insufficient distinct finite predictors or representable source range for this default candidate}}
            if {$mid eq "math.numeric.power_law"&&![dict get $numeric positive_predictors]} {set status unavailable;set reason {The physical predictor domain is not strictly positive}}
            if {$mid in {math.numeric.pchip math.numeric.smoothing_spline}&&[dict get $numeric duplicate_predictors]} {set status unavailable;set reason {This default functional candidate requires an explicit duplicate-predictor policy}}
            if {$mid in {math.numeric.gaussian math.numeric.exponential}&&$constant} {set status unavailable;set reason {A constant response does not identify this nonlinear shape's parameters}}
            if {$mid eq "math.numeric.fourier"&&!$hint} {set status manual_definition;set reason {No bounded repeated-extrema period hint is available; an explicit physically justified period is required}}
            dict set row status $status;dict set row reason $reason;dict set row options $options
            dict set row suggested [expr {$status eq "eligible"&&$hint}]
            dict set row priority [expr {[dict get $row suggested]?$priority:100}]
            if {[dict get $row suggested]} {lappend order [list [dict get $row priority] $id]}
        }
        lappend rows $row
    }
    set suggested {};foreach item [lsort -integer -index 0 $order] {lappend suggested [lindex $item 1]}
    set comparison {};set comparisonStatus unavailable;set comparisonReason {Choose at least two retained fitted candidates; suggestions have no fitted score}
    if {[llength $entries]>=2} {
        if {![dict exists $context observation_binding]} {set comparisonReason {Current source row identity is required to rank retained fits in this assistant}} else {
            set binding [dict get $context observation_binding];set matching 1
            foreach entry $entries {
                set plan [modelSelectionPlan [dict get $entry result] [dict get $entry binding]]
                foreach key {source_id source_sha256 rows_sha256} {if {[dict get $plan $key] ne [dict get $binding $key]} {set matching 0}}
                if {[dict get $plan n]!=$n||[dict get $plan response_sha256] ne [dict get $numeric observation_signature response_sha256]} {set matching 0}
                if {[dict get $plan orientation] ne $orientation} {set matching 0}
                foreach key {x_variable_id y_variable_id} {if {[dict exists $context $key]&&[dict get $context $key] ne [dict get $plan $key]} {set matching 0}}
                set predictorUnit [expr {$orientation eq "x_of_y"?[dict get $plan y_unit]:[dict get $plan x_unit]}]
                set responseUnit [expr {$orientation eq "x_of_y"?[dict get $plan x_unit]:[dict get $plan y_unit]}]
                if {$predictorUnit ne [dict get $context x_unit]||$responseUnit ne [dict get $context y_unit]} {set matching 0}
                set result [dict get $entry result]
                set signature [_get [dict get $result provenance] physical_observation_signature [_get [dict get $result provenance] observation_signature {}]]
                if {![dict exists $signature predictors_sha256]||[dict get $signature predictors_sha256] ne [dict get $numeric observation_signature predictors_sha256]} {set matching 0}
            }
            if {!$matching} {set comparisonReason {Retained fits differ from the assistant's exact current source population, axis identities, orientation, units or predictor/response coordinates}} else {
                set comparison [modelComparison $entries $criterion];set comparisonStatus [dict get $comparison status]
                set comparisonReason [expr {$comparisonStatus eq "value"?"Existing CORE comparison of captured fitted scores; no refit":[join [dict get $comparison reasons] {; }]}]
            }
        }
    }
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.fit_suggestions.v1 \
        request [dict create numeric $numeric candidates $candidates context $context entries $entries criterion $criterion] \
        suggestions $rows suggested_ids $suggested comparison $comparison comparison_status $comparisonStatus comparison_reason $comparisonReason \
        assumptions {{Source shape hints are deterministic heuristics with captured thresholds, not model probabilities or goodness-of-fit scores} {No candidate is fitted, selected or accepted automatically} {Eligibility of a simple default does not establish convergence, physical validity or identifiable uncertainty} {AIC and AICc ranking uses only captured fitted candidates with compatible exact observations, weights and likelihoods} {Shape hints use physical source coordinates before optional fit translations and do not use measurement-error weights}}]
}
proc ::GX::StatisticsV1::_suggestionFacts {numeric} {
    set fields {schema numeric_api operation status reason observation_count distinct_predictors duplicate_predictors predictor_minimum predictor_maximum response_minimum response_maximum positive_predictors response_one_sign constant_response shape_status monotonic linear_like peak_count trough_count periodic_hint period_status period saturating_hint tail_slope_ratio thresholds observation_signature order_policy nonfinite_policy purpose fitted accepted}
    _keys $numeric $fields fit_characteristics
    foreach key $fields {if {![dict exists $numeric $key]} {_error "Source characteristics require $key"}}
    foreach {key wanted} {schema gxtxt.fit_characteristics.v1 numeric_api NUMERIC_API_v1 operation fit_characteristics purpose advisory_shape_hints_only nonfinite_policy error order_policy stable_predictor_sort_for_shape_only} {if {[dict get $numeric $key] ne $wanted} {_error "Unexpected source-characteristic $key"}}
    foreach key {observation_count distinct_predictors peak_count trough_count} {set value [dict get $numeric $key];if {![_finite $value]||$value<0||$value!=floor($value)||$value>1000000} {_error {Invalid source characteristic count}}}
    set n [dict get $numeric observation_count];set distinct [dict get $numeric distinct_predictors]
    if {$n<2||$distinct<1||$distinct>$n} {_error {Invalid finite predictor population}}
    foreach key {duplicate_predictors positive_predictors response_one_sign constant_response linear_like periodic_hint saturating_hint fitted accepted} {_physicalBoolean [dict get $numeric $key]}
    if {[dict get $numeric fitted]||[dict get $numeric accepted]||[dict get $numeric duplicate_predictors]!=($distinct<$n)} {_error {Characteristics cannot claim fitting/acceptance or contradictory duplicate handling}}
    foreach key {predictor_minimum predictor_maximum response_minimum response_maximum} {if {![_finite [dict get $numeric $key]]} {_error {Source extrema must be finite}}}
    if {[dict get $numeric predictor_minimum]>[dict get $numeric predictor_maximum]||[dict get $numeric response_minimum]>[dict get $numeric response_maximum]} {_error {Source extrema must be ordered}}
    set xmin [dict get $numeric predictor_minimum];set ymin [dict get $numeric response_minimum];set ymax [dict get $numeric response_maximum]
    if {[dict get $numeric positive_predictors]!=($xmin>0)||[dict get $numeric response_one_sign]!=($ymin>0||$ymax<0)||[dict get $numeric constant_response]!=($ymin==$ymax)} {_error {Source sign/constant facts contradict captured extrema}}
    set peaks [dict get $numeric peak_count];set troughs [dict get $numeric trough_count]
    if {$peaks+$troughs>$n-2} {_error {Interior extremum counts exceed the source population}}
    if {([dict get $numeric shape_status] eq "value")!=([dict get $numeric status] eq "value"&&$distinct==$n)} {_error {Ordered shape status contradicts source availability or duplicate policy}}
    if {[dict get $numeric periodic_hint]&&([dict get $numeric shape_status] ne "value"||!(($peaks>=3&&$troughs>=2)||($troughs>=3&&$peaks>=2)))} {_error {A repeated-extrema period needs sufficient captured interior extrema}}
    foreach key {status shape_status period_status} {if {[dict get $numeric $key] ni {value unavailable}} {_error {Invalid source-characteristic status}}}
    if {[dict get $numeric monotonic] ni {unavailable constant nearly_constant increasing decreasing mixed}} {_error {Unknown monotonic shape hint}}
    if {[dict get $numeric periodic_hint]} {if {[dict get $numeric period_status] ne "value"||![_finite [dict get $numeric period]]||[dict get $numeric period]<=0} {_error {A period hint needs a finite positive interval}}} elseif {[dict get $numeric period_status] ne "unavailable"||![string equal -nocase [dict get $numeric period] NaN]} {_error {An unavailable period must not invent an interval}}
    set ratio [dict get $numeric tail_slope_ratio];if {!([_finite $ratio]&&$ratio>=0)&&![string equal -nocase $ratio NaN]} {_error {Invalid saturation slope ratio}}
    set thresholds [dict get $numeric thresholds];set names {relative_flat_tolerance monotonic_fraction linearity_tolerance prominence period_tolerance saturation_ratio};_keys $thresholds $names characteristic_thresholds
    foreach name $names lower {0 0.5 0 0 0 0} upper {0.001 1 0.25 1 0.5 1} {
        set value [dict get $thresholds $name];if {![_finite $value]||$value<$lower||$value>$upper||($name eq "prominence"&&$value==0)} {_error {Invalid captured shape threshold}}
    }
    set signature [_fitObservationSignature [dict get $numeric observation_signature]]
    if {[dict get $signature n]!=$n||![dict exists $signature predictors_sha256]||[dict get $signature predictor_count]!=1} {_error {Source characteristic signature differs from its scalar predictor population}}
}
proc ::GX::StatisticsV1::_suggestionValidate {result} {
    set request [dict get $result request];_keys $request {numeric candidates context entries criterion} fit_suggestion_request
    set expected [fitSuggestions [dict get $request numeric] [dict get $request candidates] [dict get $request context] [dict get $request entries] [dict get $request criterion]]
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $result]]} {_error {Model suggestion fields changed}}
    foreach key {api_id api_version schema comparison_status comparison_reason} {if {[dict get $expected $key] ne [dict get $result $key]} {_error "Model suggestion changed $key"}}
    foreach key {suggested_ids assumptions} {if {[llength [dict get $expected $key]]!=[llength [dict get $result $key]]} {_error "Model suggestion changed $key"};foreach a [dict get $expected $key] b [dict get $result $key] {if {$a ne $b} {_error "Model suggestion changed $key"}}}
    if {[llength [dict get $expected suggestions]]!=[llength [dict get $result suggestions]]} {_error {Suggestion candidate count changed}}
    foreach a [dict get $expected suggestions] b [dict get $result suggestions] {
        if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {_error {Suggestion candidate fields changed}}
        foreach key {id model_id label status reason} {if {[dict get $a $key] ne [dict get $b $key]} {_error "Suggestion changed $key"}}
        foreach key {suggested priority} {if {![_finite [dict get $b $key]]||[dict get $a $key]!=[dict get $b $key]} {_error "Suggestion changed $key"}}
        set ao [dict get $a options];set bo [dict get $b options]
        if {[lsort [dict keys $ao]] ne [lsort [dict keys $bo]]} {_error {Suggested settings changed}}
        dict for {key value} $ao {if {![_finite [dict get $bo $key]]||$value!=[dict get $bo $key]} {_error {Suggested setting value changed}}}
    }
    if {[dict get $expected comparison] eq {}} {if {[dict get $result comparison] ne {}} {_error {Suggestion invented a fitted comparison}}} else {
        validate [dict get $result comparison]
        if {[dict get $expected comparison ranked_ids] ne [dict get $result comparison ranked_ids]||[dict get $expected comparison request] ne [dict get $result comparison request]} {_error {Suggestion comparison request changed}}
    }
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::fitSuggestionsReport {result} {
    validate $result
    set numeric [dict get $result request numeric];set context [dict get $result request context]
    set lines [list {Advisory model suggestions} "Exact finite observations: [dict get $numeric observation_count]; distinct predictors: [dict get $numeric distinct_predictors]" "Shape: [dict get $numeric monotonic]; prominent peaks: [dict get $numeric peak_count]; troughs: [dict get $numeric trough_count]" "Saturation hint: [dict get $numeric saturating_hint]; repeated-pattern hint: [dict get $numeric periodic_hint]"]
    if {[dict get $numeric periodic_hint]} {lappend lines "Candidate period: [dict get $numeric period] [dict get $context x_unit]"}
    foreach row [dict get $result suggestions] {lappend lines "\n[dict get $row label]: [dict get $row status][expr {[dict get $row suggested]?{ — shape suggestion}:{}}]" [dict get $row reason];if {[dict get $row options] ne {}} {lappend lines "Review settings: [dict get $row options]"}}
    lappend lines "\nFitted-candidate ranking: [dict get $result comparison_status]" [dict get $result comparison_reason]
    if {[dict get $result comparison] ne {}} {lappend lines [report [dict get $result comparison]]}
    return [join [concat $lines {{}} [dict get $result assumptions]] \n]
}
