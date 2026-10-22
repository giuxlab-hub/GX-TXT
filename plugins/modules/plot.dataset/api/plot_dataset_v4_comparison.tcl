# SPDX-License-Identifier: GPL-3.0-or-later
# Derived numerical comparison display. The existing comparison owner retains
# geometry, sampling, Numeric/Statistics facts and publication authority.
proc ::GX::PlotDatasetAPIv4::_comparisonValidate {model} {
    if {![dict exists $model derived_comparison]} {return}
    set source [dict get $model derived_comparison]
    ::GX::modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
    if {![llength [info commands ::GX::CurveWorkbench::comparisonDisplayValidate]]} {
        error {Curve Workbench lacks its public comparison display source validation}
    }
    set validation [::GX::CurveWorkbench::comparisonDisplayValidate [dict get $source owner_binding] [dict get $source comparison_record]]
    if {![dict exists $validation valid] || ![dict get $validation valid]} {error {Numerical comparison owner is no longer current}}
    return $validation
}

proc ::GX::PlotDatasetAPIv4::comparisonModel {ownerBinding comparisonRecord {options {}}} {
    _ready
    set source [dict create owner_binding $ownerBinding comparison_record $comparisonRecord \
        point_identity_kind derived_statistic canonical_dataset_rows 0 statistics_authority STATISTICAL_RESULT_SEMANTICS_API_v1]
    set validation [_comparisonValidate [dict create derived_comparison $source]]
    if {[dict exists $validation source_provenance]} {
        dict set source source_provenance_at_admission [dict get $validation source_provenance]
    } elseif {[dict exists $ownerBinding source_provenance]} {
        dict set source source_provenance_at_admission [dict get $ownerBinding source_provenance]
    }
    set receipt [dict get $comparisonRecord receipt]
    foreach field {rows max_index statistics coordinate_frame unit} {
        if {![dict exists $receipt $field]} {error "Numerical comparison receipt is missing $field"}
    }
    set rows [dict get $receipt rows];set count [llength $rows]
    if {$count<2 || $count>4096} {error {Numerical comparison display requires two to 4096 admitted comparison samples}}
    dict set source comparison_display_rows $count
    dict set source maximum_marker_duplicates_display_point 1
    set points {}
    foreach row $rows {
        if {[llength $row]<2} {error {Comparison display row has no abscissa and deviation}}
        set point [lrange $row 0 1]
        foreach value $point {
            if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Comparison display coordinates must be finite}}
        }
        lappend points $point
    }
    set maximum [dict get $receipt max_index]
    if {![string is entier -strict $maximum] || $maximum<0 || $maximum>=$count} {error {Comparison maximum must address an actual displayed sample}}
    if {[dict exists $receipt row_indices]} {
        set indices [dict get $receipt row_indices]
        if {[llength $indices]!=$count} {error {Comparison evaluation indices do not match displayed rows}}
        foreach index $indices {if {![string is entier -strict $index] || $index<0} {error {Comparison evaluation indices require exact nonnegative integers}}}
        if {[dict exists $receipt max_source_index] && [lindex $indices $maximum] ne [dict get $receipt max_source_index]} {error {Comparison maximum evaluation identity disagrees with its display index}}
    }
    dict for {role interpretation} [dict get $receipt statistics] {::GX::StatisticsV1::validate $interpretation}
    set method [dict get $ownerBinding definition method]
    if {$method ni {x path geometry}} {error {Unsupported planar comparison display method}}
    set unit [dict get $receipt unit]
    set xUnit $unit
    if {$method eq {x}} {set xUnit [lindex [dict get $receipt coordinate_frame output_units] 0]}
    set xLabel [dict get {x {Reference X} path {Reference path distance} geometry {Sampled reference path distance}} $method]
    set yLabel [expr {$method eq {geometry}?{Distance to curve}:{Signed residual}}]
    if {$xUnit ne {}} {append xLabel " ($xUnit)"}
    if {$unit ne {}} {append yLabel " ($unit)"}
    # These are derived comparison/evaluation identities, never source Dataset
    # row ordinals. Preserve the complete scientific receipt without computing
    # statistics from reduced display samples.
    set common [dict create axis left point_identity_kind derived_statistic row_count 0]
    set line [dict merge $common [dict create id deviation label $yLabel kind line points $points \
        style {color #b12535 line_width 2 marker none}]]
    set marker [dict merge $common [dict create id maximum_deviation label {Maximum deviation} kind scatter \
        points [list [lindex $points $maximum]] style {color #e6b433 marker circle marker_fill solid marker_size 5 line_style none}]]
    set model [dict create title [_get $options title {}] \
        panels [list [dict create id main axes [dict create x [dict create label $xLabel] left [dict create label $yLabel]] series [list $line $marker]]] \
        native_presentation [_get $options native_presentation {legend {placement none}}] derived_comparison $source]
    _modelChecks $model
    return $model
}
