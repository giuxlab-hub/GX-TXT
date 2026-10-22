# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical display buffers retain their original samples. All interpretation
# and viewport magnification use DATASET_METADATA_API_v1 coordinate operations.
proc ::GX::scientificDatasetCoordinateDisplay {context x y display} {
    if {[dict exists $display canonical_points]} {set points [dict get $display canonical_points]} else {set points [dict get $display points]}
    if {[llength $points]>4096} {error {Scientific coordinate display is bounded to4096 points per trace}}
    set converted {};set units {};set factors {};set pivots {}
    foreach axis {0 1} vid [list $x $y] {
        set values [lmap point $points {lindex $point $axis}]
        set settings [scientificDatasetCoordinateSettings $context $vid]
        if {[dict exists $context variables $vid]} {
            set source [dict get $settings source]
            if {[dict get $source value_kind] eq "elapsed_time"&&[dict get $source value_format] eq "hms"} {set values [elapsedTimeConvert $values [dict get $source unit]]}
        }
        if {[dict exists $context variables $vid]} {set result [datasetCoordinateSnapshotValues $context $vid $values {mode canonical}]} else {set result [dict create values $values unit [dict get $settings display_unit]]}
        lappend converted [dict get $result values];lappend units [dict get $result unit]
        lappend factors [dict get $settings view_factor]
        lappend pivots [dict get $settings view_pivot]
    }
    set shown {};foreach a [lindex $converted 0] b [lindex $converted 1] {lappend shown [list $a $b]}
    dict set display canonical_points $points;dict set display points $shown
    if {[dict exists $display full_bounds]} {
        set exact [datasetPublicationV2DictDefault $display canonical_full_bounds [dict get $display full_bounds]]
        dict set display canonical_full_bounds $exact
        set next $exact
        foreach lo {0 1} hi {2 3} vid [list $x $y] {
            set values [list [lindex $exact $lo] [lindex $exact $hi]]
            if {[dict exists $context variables $vid]} {set values [dict get [datasetCoordinateSnapshotValues $context $vid $values {mode canonical}] values]}
            set values [lsort -real $values];lset next $lo [lindex $values 0];lset next $hi [lindex $values end]
        }
        dict set display full_bounds $next
    }
    dict set display coordinate_presentation [dict create schema gxtxt.scientific_coordinate_presentation.v1 context $context variable_ids [list $x $y] display_units $units view_factors $factors canonical_view_pivots $pivots calibration_applied 0 source_values_modified 0]
    return $display
}

proc ::GX::scientificDatasetCoordinateLabel {context vid} {
    set unit [dict get [scientificDatasetCoordinateSettings $context $vid] display_unit]
    return [expr {$unit eq {}?{undeclared}:$unit}]
}
proc ::GX::scientificDatasetCoordinateNotice {presentation} {
    set context [dict get $presentation context];set parts {}
    foreach axis {X Y} vid [dict get $presentation variable_ids] {
        set settings [scientificDatasetCoordinateSettings $context $vid]
        lappend parts "$axis [scientificDatasetCoordinateLabel $context $vid], view ×[dict get $settings view_factor] about source [dict get $settings view_pivot]"
    }
    return "[join $parts {; }]. Canonical values; numerical calibration is not applied."
}
proc ::GX::scientificDatasetCoordinateOverlay {context ys} {
    set common {}
    foreach y $ys {
        set settings [scientificDatasetCoordinateSettings $context $y];set policy {}
        foreach key {unit canonical_unit to_canonical from_canonical} {lappend policy [dict get $settings source $key]}
        foreach key {display_unit view_factor view_pivot} {lappend policy [dict get $settings $key]}
        if {$common ne {}&&$policy ne $common} {error {Overlay Y variables require the same coordinate relation, display unit and magnification/pivot. Inspect different coordinate policies separately.}}
        set common $policy
    }
}
proc ::GX::scientificDatasetViewerCoordinateRefresh {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,coordinateContext)]||![info exists state($w,series)]||$state($w,opening)||$state($w,job) ne {}||$state($w,queue) ne {}||!$state($w,plotCurrent)} return
    set context [datasetCoordinateRead $::GX::currentSession $state($w,id)]
    if {$context eq $state($w,coordinateContext)} return
    set ys [lmap series $state($w,series) {dict get $series y}]
    scientificDatasetCoordinateOverlay $context $ys
    set updated {}
    foreach series $state($w,series) {
        dict set series display [scientificDatasetCoordinateDisplay $context [lindex $state($w,plottedRequest) 0] [dict get $series y] [dict get $series display]]
        lappend updated $series
    }
    if {![llength $updated]} return
    if {![scientificDatasetViewerAdopt $w $updated $context]} return
    set state($w,series) $updated;set state($w,coordinateContext) $context
    scientificDatasetViewerCoordinateLegend $w
    set state($w,status) [scientificDatasetCoordinateNotice [dict get [lindex $updated 0] display coordinate_presentation]]
}

proc ::GX::scientificDatasetViewerCoordinateLegend {w} {
    variable ::GX::DatasetViewer::state
    set context $state($w,coordinateContext);set xv [datasetVariableV3ById $state($w,id) [lindex $state($w,plottedRequest) 0]];set labels {}
    foreach series $state($w,series) {
        set y [dict get $series y];set v [datasetVariableV3ById $state($w,id) $y]
        lappend labels "[dict get $v canonical] ([scientificDatasetCoordinateLabel $context $y]) [dict get $series member]"
    }
    set state($w,legend) "X: [dict get $xv canonical] ([scientificDatasetCoordinateLabel $context [lindex $state($w,plottedRequest) 0]])    Y: [join $labels { | }]"
}

proc ::GX::scientificDatasetCoordinateSettings {context vid} {
    if {[dict exists $context variables $vid]} {return [dict get $context variables $vid]}
    # Boolean and other legacy axes outside the coordinate API's real-number
    # contract keep their existing canonical presentation. Never forge a
    # supported numeric schema or reinterpret an already decoded source value.
    set source [datasetVariableV3ById [dict get $context dataset_id] $vid]
    return [dict create source $source display_unit [dict get $source unit] view_factor 1 view_pivot 0 policy_applicable 0]
}
proc ::GX::scientificDatasetCoordinateSourceStamp {stamp} {
    lset stamp 0 [dict remove [lindex $stamp 0] structured_metadata_file structured_metadata_api_version structured_metadata_updated_at structured_metadata_revision metadata_display_name]
    return $stamp
}
