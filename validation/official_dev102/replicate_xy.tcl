source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
proc runStudy {request} {
    set ticket [::GX::Replicate::submit $request]
    set job [::GX::scriptJobWait [dict get $ticket job_id] 180]
    save job_[dict get $request analysis_id] $job
    if {[dict get $job state] ne "COMPLETED"} {error "Scientific Job failed: [dict get $request analysis_id]"}
    set result [::GX::Replicate::result $ticket];save result_[dict get $request analysis_id] $result
    return $result
}
proc publishSource {id xs ys} {
    return [::GX::datasetPublicationV2PublishSeries $::session viewer.curve_digitizer [dict create dataset_id $id contract table.generic storage hdf5 x_values $xs y_values $ys x_variable {variable_id coordinate_unseen unit mm} y_variable {variable_id response_unseen unit mm} extra_variables [list [dict create descriptor {variable_id point_order dtype int64 unit 1} values [lmap x $xs {incr ::order}]]]]]
}
proc fixtureTrace {id index} {return [dict create dataset_id $id x_variable_id coordinate_unseen y_variable_id response_unseen order_variable_id point_order physical_feature_id physical_feature curve_key edge observation_id observation_$index point_set_id points_$index calibration_realization_id calibration_$index source_group_id source_1 frame_id laboratory topology open landmark_id common_start direction forward]}
proc request {name method traces {design repeatability}} {return [dict create analysis_id $name method $method design $design grid_points 41 correspondence anchored_source_arclength reference_frame {id laboratory declaration explicit_user_verified x_unit mm y_unit mm} traces $traces localization_uncertainty 0]}
try {
    set ::session [::GX::createNewSession replicate_xy_dev102]
    ::GX::modulePublicApiActivate curve.replicate_analysis CURVE_REPLICATE_ANALYSIS_API_v1
    set traces {};set ::order 0
    foreach {number offset} {1 -.1 2 0 3 .1} {set id open_$number;publishSource $id {0 2 2 1} [lmap y {0 0 2 2} {expr {$y+$offset}}];lappend traces [fixtureTrace $id $number]}
    set result [runStudy [request returning_open xy_path $traces]]
    check {abs([lindex [dict get $result columns y_mean] 0])<1e-12 && abs([lindex [dict get $result columns x_mean] end]-1)<1e-12 && abs([lindex [dict get $result columns y_std] 0]-.1)<1e-12} {Open returning XY consensus and sample dispersion match translated analytic paths}
    set invalid [request cannot_be_yx yx $traces]
    set ticket [::GX::Replicate::submit $invalid];set job [::GX::scriptJobWait [dict get $ticket job_id] 120]
    check {[dict get $job state] eq "FAILED" && [catch {::GX::Replicate::result $ticket}]} {13 nonmonotonic XY path cannot silently execute Y(X)}
    set closed {}
    foreach {number count phase reversed} {1 16 0 0 2 24 5 0 3 32 9 1} {
        set points {}
        for {set i 0} {$i<$count} {incr i} {set theta [expr {2*acos(-1)*($i+$phase)/$count}];if {$reversed} {set theta [expr {-$theta}]};lappend points [list [expr {10+2*cos($theta)}] [expr {-3+2*sin($theta)}]]}
        set id closed_$number;publishSource $id [lmap p $points {lindex $p 0}] [lmap p $points {lindex $p 1}]
        set t [fixtureTrace $id closed_$number];dict set t topology closed;dict set t phase_index [expr {($count-$phase)%$count}];dict set t direction [expr {$reversed?"reverse":"forward"}]
        lappend closed $t
    }
    set result [runStudy [request periodic_circle xy_path $closed]]
    set error 0;set i 0
    foreach x [dict get $result columns x_mean] y [dict get $result columns y_mean] {
        set theta [expr {2*acos(-1)*$i/40.}];set error [expr {max($error,abs($x-(10+2*cos($theta))),abs($y-(-3+2*sin($theta))))}];incr i
    }
    check {$error<.001 && abs([lindex [dict get $result columns x_mean] 0]-[lindex [dict get $result columns x_mean] end])<1e-12} {Closed circle supports unequal densities, shifted phase and reversed traversal with analytic error below 0.001 mm}
    save circle_error $error
    set sensitivity {}
    foreach t $traces {dict set t point_set_id shared_points;dict set t observation_id shared_observation;lappend sensitivity $t}
    set result [runStudy [request calibration_sensitivity xy_path $sensitivity calibration_sensitivity]]
    check {[dict get $result qualifications independent_observations]==1 && [string equal -nocase [lindex [dict get $result columns y_sem] 0] nan]} {06 and 10 shared calibration sensitivity reports one observation and unavailable SEM}
    set single [runStudy [request single_observation xy_path [list [lindex $traces 0]]]]
    check {[string equal -nocase [lindex [dict get $single columns y_sem] 0] nan]} {10 one observation cannot establish an independent SEM}
    set hierarchy {}
    foreach {number offset source} {1 0 A 2 2 A 3 10 B 4 12 B} {set id hierarchy_$number;publishSource $id {0 1 2 3} [lmap x {0 1 2 3} {expr {$x+$offset}}];set t [fixtureTrace $id hierarchy_$number];dict set t source_group_id $source;lappend hierarchy $t}
    set result [runStudy [request hierarchical_sources yx $hierarchy hierarchical]]
    check {abs([lindex [dict get $result columns y_within] 0]-sqrt(2))<1e-12 && abs([lindex [dict get $result columns y_between] 0]-7)<1e-12 && [string equal -nocase [lindex [dict get $result columns y_sem] 0] nan]} {Clustered source design preserves independently verified within/between moments without a naive trace SEM}
    publishSource crossed {0 2 0 2} {0 2 2 0}
    set t [fixtureTrace crossed crossed];dict set t topology closed;dict set t phase_index 0
    set ticket [::GX::Replicate::submit [request self_crossing xy_path [list $t]]];set job [::GX::scriptJobWait [dict get $ticket job_id] 120]
    check {[dict get $job state] eq "FAILED"} {Self-intersecting contours refuse through Native2D geometry authority}
    save result [dict create status PASS checks $checks session $::session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
