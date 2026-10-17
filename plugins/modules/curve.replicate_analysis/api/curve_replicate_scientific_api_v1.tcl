# SPDX-License-Identifier: GPL-3.0-or-later
# Public CORE orchestration; Numeric, Statistics, Curve Source, Publication and
# Script Job remain the sole numerical, source, storage and process authorities.
namespace eval ::GX::Replicate {variable root [file dirname [file dirname [info script]]]}
proc ::GX::Replicate::capabilities {} {
    return [dict create api_id CURVE_REPLICATE_ANALYSIS_API_v1 api_version 1 methods {yx xy_path} designs {repeatability calibration_sensitivity hierarchical} operations {capabilities preflight submit status cancel result publish describe_output} maximum_traces 64 maximum_points_per_trace 65536 maximum_xy_vertices 4096 maximum_grid 2048 uncertainty {descriptive_dispersion conditional_independent_sem Numeric_random_effects} shared_factor_covariance unavailable implicit_analysis_enable 0]
}
proc ::GX::Replicate::preflight {request} {
    set session $::GX::currentSession
    if {$session eq {}} {error {Open a Session before a Replicate study}}
    foreach key {analysis_id method design reference_frame traces} {if {![dict exists $request $key]} {error "Replicate request requires '$key'"}}
    set aid [::GX::datasetPublicationV2ValidateId analysis [dict get $request analysis_id]]
    if {[dict get $request method] ni {yx xy_path} || [dict get $request design] ni {repeatability calibration_sensitivity hierarchical}} {error {Unsupported Replicate method/design}}
    set frame [dict get $request reference_frame]
    foreach key {id declaration x_unit y_unit} {if {![dict exists $frame $key] || [dict get $frame $key] eq {}} {error {Declare and verify a common physical coordinate frame and units explicitly}}}
    if {[dict get $frame declaration] ne "explicit_user_verified"} {error {A common frame must be explicitly verified; matching unit strings alone do not establish it}}
    if {[dict get $request method] eq "xy_path"} {::GX::unitRegistryConversionPlan [dict get $frame y_unit] [dict get $frame x_unit]}
    set count [llength [dict get $request traces]]
    if {$count<1 || $count>64} {error {A Replicate study supports 1–64 explicitly identified traces}}
    set grid [::GX::datasetPublicationV2DictDefault $request grid_points 200]
    ::GX::uiFieldNormalize {type integer min 3 max 2048} $grid;dict set request grid_points $grid
    set observations {};set pointSets {};set features {};set sources {};set traces {}
    foreach trace [dict get $request traces] {
        foreach key {dataset_id x_variable_id y_variable_id physical_feature_id curve_key observation_id point_set_id calibration_realization_id source_group_id frame_id} {
            if {![dict exists $trace $key] || [dict get $trace $key] eq {}} {error "Each trace requires independent identity '$key'"}
        }
        if {[dict get $trace frame_id] ne [dict get $frame id]} {error {Incompatible coordinate frames: provide an explicit CORE transform before analysis}}
        set id [dict get $trace dataset_id]
        foreach axis {x y} {
            set variable [::GX::datasetVariableV3ById $id [dict get $trace ${axis}_variable_id]]
            if {[dict get $variable rank]!=1 || [dict get $variable value_kind] ni {number elapsed_time}} {error {Replicate axes require real row-oriented canonical Variables}}
            ::GX::unitRegistryConversionPlan [dict get $variable unit] [dict get $frame ${axis}_unit]
        }
        set snapshot [::GX::datasetCoordinateRead $session $id]
        if {[dict exists $trace coordinate_context] && [dict get $trace coordinate_context] ne $snapshot} {error {Source calibration/coordinate context changed}}
        dict set trace coordinate_context $snapshot
        dict set trace source_revision [::GX::datasetRevisionToken $id $session]
        if {[dict exists $trace curve_variable_id]} {
            set filters [::GX::datasetPublicationV2DictDefault $trace filters {}]
            set curveFilter [lindex [::GX::graphSeriesNormalizeFilters $id [list [dict create filter_variable_id [dict get $trace curve_variable_id] predicate exact_equal value [dict get $trace curve_key]]]] 0]
            set filters [lsort -unique [::GX::graphSeriesNormalizeFilters $id $filters]]
            # Preparation can validate an already normalized recipe again.
            # Duplicating this binding changes its identity and rejects the
            # completed GUI Job even though the scientific inputs are identical.
            if {$curveFilter ni $filters} {lappend filters $curveFilter}
            dict set trace filters [::GX::graphSeriesNormalizeFilters $id $filters]
        }
        if {[dict get $request method] eq "xy_path"} {
            foreach key {topology order_variable_id landmark_id direction} {if {![dict exists $trace $key] || [dict get $trace $key] eq {}} {error "Ordered XY paths require '$key'"}}
            if {[dict get $trace topology] ni {open closed} || [dict get $trace direction] ni {forward reverse}} {error {Declare open/closed topology and traversal direction}}
            if {[dict get $trace topology] eq "closed" && ![dict exists $trace phase_index]} {error {Closed contours require an explicit source start landmark/phase index}}
        }
        lappend traces $trace
        dict set observations [dict get $trace observation_id] 1
        dict lappend pointSets [dict get $trace point_set_id] [dict get $trace observation_id]
        dict set features [dict get $trace physical_feature_id] 1
        dict set sources [dict get $trace source_group_id] 1
    }
    if {[dict size $features]!=1} {error {Distinct physical features must be analyzed in separate studies}}
    set design [dict get $request design]
    if {$design ne "calibration_sensitivity"} {
        if {[dict size $observations]!=$count || [dict size $pointSets]!=$count} {error {Repeated calibrations of one point set are not independent observations; select calibration_sensitivity}}
    } elseif {[dict size $pointSets]!=1 || [dict size $observations]!=1} {error {Calibration sensitivity requires one shared observation and point set}}
    if {$design eq "hierarchical" && ([dict size $sources]<2 || $count<=[dict size $sources])} {error {Hierarchical components need independent sources and within-source repeats}}
    dict set request traces $traces
    dict set request independent_observation_count [expr {$design eq "calibration_sensitivity"?1:[dict size $observations]}]
    dict set request session_token [::GX::interactiveDocumentSessionToken]
    return $request
}
proc ::GX::Replicate::submit {request} {
    variable root
    set request [preflight $request]
    set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $request]]
    set f [::open [file join $root runtime replicate_scientific_job.py] r];try {set code [read $f]} finally {close $f}
    set code [string map [list @REQUEST_BASE64@ $encoded] $code]
    set sid replicate_study_[clock clicks]
    set registered [::GX::scriptRegistrySave session $sid "Replicate study [dict get $request analysis_id]" $code {language Python required_apis {CURVE_REPLICATE_ANALYSIS_API_v1;NUMERIC_API_v1;STATISTICAL_RESULT_SEMANTICS_API_v1;CURVE_SOURCE_API_v1;DATASET_METADATA_API_v1;UNIT_REGISTRY_API_v1;NATIVE_2D_GEOMETRY_API_v1}}]
    set job [::GX::scriptJobSubmit session:$sid {}]
    return [dict create job_id [dict get $job id] request $request source_sha256 [dict get $registered sha256] script_id $sid]
}
proc ::GX::Replicate::status {ticket} {return [::GX::scriptJobDescribe [dict get $ticket job_id]]}
proc ::GX::Replicate::cancel {ticket} {return [::GX::scriptJobCancel [dict get $ticket job_id]]}
proc ::GX::Replicate::result {ticket} {
    set request [dict get $ticket request]
    if {[dict get $request session_token] ne [::GX::interactiveDocumentSessionToken]} {error {Study belongs to another Session lifetime}}
    foreach trace [dict get $request traces] {if {[::GX::datasetRevisionToken [dict get $trace dataset_id] $::GX::currentSession] ne [dict get $trace source_revision]} {error {Study source changed; results cannot be adopted}}}
    set job [status $ticket]
    if {[dict get $job state] ne "COMPLETED"} {error {Study has no completed result}}
    foreach key {session reference source_sha256} {if {![dict exists $job $key]} {error {Job lacks authenticated study identity}}}
    if {[file normalize [dict get $job session]] ne [file normalize $::GX::currentSession] || [dict get $job reference] ne "session:[dict get $ticket script_id]" || [dict get $job source_sha256] ne [dict get $ticket source_sha256]} {error {Job identity differs from the submitted study}}
    set registered [::GX::scriptRegistryRead session [dict get $ticket script_id]]
    if {[dict get $registered sha256] ne [dict get $ticket source_sha256]} {error {Study script source changed}}
    set f [::open [dict get $registered source_path] r];try {set source [read $f]} finally {close $f}
    set encodedRequest [binary encode base64 -maxlen 0 [encoding convertto utf-8 $request]]
    if {[string first $encodedRequest $source]<0} {error {Study request differs from its immutable registered source}}
    set text {};set offset 0
    while 1 {set page [::GX::scriptJobLogRead [dict get $ticket job_id] $offset 65536];append text [dict get $page content];if {[string bytelength $text]>33554432} {error {Study result exceeds bounded 32 MiB control receipt}};if {[dict get $page eof]} break;set offset [dict get $page next_offset]}
    if {![regexp -line {^GXTXT_REPLICATE_RESULT:([A-Za-z0-9+/=]+)$} $text -> encoded]} {error {Completed Job has no Replicate scientific receipt}}
    set result [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    if {[dict get $result analysis_id] ne [dict get $request analysis_id]} {error {Study result identity differs}}
    return $result
}
proc ::GX::Replicate::publish {ticket} {
    return [::GX::_datasetPrivateWithModule curve.replicate_analysis ::GX::Replicate::_publish $ticket]
}
proc ::GX::Replicate::_publish {ticket} {
    set result [result $ticket];set request [dict get $ticket request]
    return [::GX::datasetAuthorityTransaction $::GX::currentSession ::GX::Replicate::_publishProducts $request $result]
}
proc ::GX::Replicate::_writeProduct {id columns units metadata sources {types {}}} {
    set first [lindex [dict keys $columns] 0]
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession curve.replicate_analysis [dict create dataset_id $id contract table.generic storage auto dataset_namespace "[::GX::datasetNamespaceForModule curve.replicate_analysis]/studies/[dict get $metadata replicate.study analysis_id]" structured_metadata $metadata source_dataset_ids $sources producer_version [::GX::moduleField curve.replicate_analysis version] expected_rows [llength [dict get $columns $first]]]]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        dict for {vid values} $columns {::GX::datasetPublicationV2DeclareVariable $writer $vid [dict create name $vid dtype [::GX::datasetPublicationV2DictDefault $types $vid float64] unit [dict get $units $vid] dimension_ids row]}
        ::GX::datasetPublicationV2Append $writer row $columns
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {catch {::GX::datasetPublicationV2Abort $writer};return -options $options $message}
}
proc ::GX::Replicate::_publishProducts {request result} {
    foreach key {original_traces aligned_traces} {if {![dict exists $result $key] || ![dict size [dict get $result $key]]} {error {Study receipt has no original/aligned trace products; rerun with the current public service}}}
    set prefix "replicate.[dict get $result analysis_id]"
    set outputs [dict create profile $prefix.profile traces $prefix.traces summary $prefix.summary]
    set metadata [dict get $result metadata]
    dict set metadata replicate.study $request
    dict set metadata replicate.qualifications [dict get $result qualifications]
    dict set metadata replicate.roles [dict get $result roles]
    dict set metadata replicate.outputs $outputs
    dict set metadata replicate.source_rows [dict get $result source_rows]
    set sources [lsort -unique [lmap trace [dict get $request traces] {dict get $trace dataset_id}]]
    set profile [_writeProduct $prefix.profile [dict get $result columns] [dict get $result units] $metadata $sources]
    # The trace table carries unbound captured profile prototypes as reference
    # interpretation, explicitly scoped to the first common coordinate only.
    set facts {}
    dict for {key binding} [dict get $metadata analysis.statistical_results] {dict set facts reference_$key [dict get $binding prototype]}
    dict set metadata analysis.statistical_results $facts
    dict set metadata replicate.statistical_scope {Reference profile quantities at the first common coordinate; full per-coordinate interpretation belongs to the linked profile Dataset.}
    dict set metadata replicate.roles {x x y y stage stage trace_index trace_index point_index point_index source_row source_row parameter parameter}
    dict set metadata replicate.trace_stage {0 original canonical source rows; 1 explicitly aligned derived samples; source_row -1 is a derived sample with no invented observation ordinal}
    set columns [dict create x {} y {} stage {} trace_index {} point_index {} source_row {} parameter {}]
    set n 0
    dict for {key trace} [::GX::datasetPublicationV2DictDefault $result original_traces {}] {
        set i 0
        foreach point [dict get $trace points] row [dict get $trace source_rows] {
            lassign $point x y
            foreach field {x y stage trace_index point_index source_row parameter} value [list $x $y 0 $n $i $row NaN] {dict lappend columns $field $value}
            incr i
        }
        set i 0
        foreach point [dict get $result aligned_traces $key] parameter [dict get $result columns parameter] {
            lassign $point x y
            foreach field {x y stage trace_index point_index source_row parameter} value [list $x $y 1 $n $i -1 $parameter] {dict lappend columns $field $value}
            incr i
        }
        incr n
    }
    set units [dict create x [dict get $result units x_mean] y [dict get $result units y_mean] stage 1 trace_index 1 point_index 1 source_row 1 parameter [dict get $result units parameter]]
    set traces [_writeProduct $prefix.traces $columns $units $metadata $sources {stage int64 trace_index int64 point_index int64 source_row int64}]
    set summaryColumns [dict create feature_index 1 trace_count $n independent_observation_count [dict get $request independent_observation_count] common_parameter_start [lindex [dict get $result columns parameter] 0] common_parameter_end [lindex [dict get $result columns parameter] end]]
    set units [dict create feature_index 1 trace_count 1 independent_observation_count 1 common_parameter_start [dict get $result units parameter] common_parameter_end [dict get $result units parameter]]
    dict set metadata replicate.roles {feature feature_index traces trace_count independent_observations independent_observation_count common_domain_start common_parameter_start common_domain_end common_parameter_end}
    set summary [_writeProduct $prefix.summary $summaryColumns $units $metadata $sources]
    return [dict merge $profile [dict create outputs $outputs dataset_ids [dict values $outputs]]]
}
proc ::GX::Replicate::describe_output {id} {
    set metadata [::GX::datasetMetadataRead $::GX::currentSession $id]
    foreach key {replicate.study replicate.roles replicate.source_rows} {if {![dict exists $metadata $key]} {error {Dataset is not a durable Replicate study output}}}
    return [dict create dataset_id $id metadata $metadata schema [::GX::datasetVariableSchemaV3 $id]]
}
