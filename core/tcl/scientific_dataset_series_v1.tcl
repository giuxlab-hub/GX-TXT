# SPDX-License-Identifier: GPL-3.0-or-later
# Multi-series consultation uses CORE Curve Source streams and explicit filters.
proc ::GX::scientificDatasetSeriesBuild {w numeric} {
    variable ::GX::DatasetViewer::state
    set p $w.views.plot.series;ttk::frame $p;pack $p -fill x -padx 5
    set state($w,numeric) $numeric;set state($w,series) {};set state($w,queue) {}
    ttk::label $p.label -text {Overlay Y (Ctrl selects):}
    listbox $p.variables -listvariable ::GX::DatasetViewer::state($w,numeric) -selectmode extended -exportselection 0 -height 3 -width 24
    pack $p.label $p.variables -side left -padx 4
    ttk::frame $p.filters;pack $p.filters -side left -padx 4
    scientificDatasetFilterControls $p.filters $state($w,id) ::GX::DatasetViewer::state $w 1
    set state($w,memberVariable) {};set state($w,members) {}
}

proc ::GX::scientificDatasetMembersRead {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[catch {
        datasetViewerCheck $w
        set chunk [tableStreamNext $state($w,memberStream)]
        foreach member [dict get [lindex [dict get $chunk columns] 0] values] {
            if {$member ni $state($w,members)} {lappend state($w,members) $member}
            if {[llength $state($w,members)]>1024} {error {More than 1024 family members; the canonical table retains access to the complete family.}}
        }
        if {[dict get $chunk eof]} {
            tableStreamClose $state($w,memberStream);unset state($w,memberStream)
            $w.views.plot.series.members selection set 0
            set state($w,status) {Select family members explicitly, then Plot; each member is a separate trace.}
        } else {set state($w,memberScan) [after 1 [list ::GX::scientificDatasetMembersRead $w]]}
    } message]} {
        if {[info exists state($w,memberStream)]} {tableStreamClose $state($w,memberStream);unset state($w,memberStream)}
        if {[info exists state($w,id)]} {set state($w,status) $message}
    }
}
proc ::GX::scientificDatasetViewerSelection {w} {
    variable ::GX::DatasetViewer::state
    if {$state($w,x) eq {}||$state($w,y) eq {}} {error {Choose explicit X and Y variables.}}
    set ys [list $state($w,y)]
    foreach index [$w.views.plot.series.variables curselection] {set id [lindex $state($w,numeric) $index];if {$id ni $ys} {lappend ys $id}}
    set unit [dict get [datasetVariableV3ById $state($w,id) $state($w,y)] unit]
    foreach id $ys {if {[dict get [datasetVariableV3ById $state($w,id) $id] unit] ne $unit} {error {Overlay variables must declare the same unit. Inspect different units separately; no automatic conversion is applied.}}}
    set requests [scientificDatasetFilterRequests $state($w,dimensions) $state($w,filters) $state($w,separate)]
    if {[llength $ys]*[llength $requests]>16} {error {Select up to 16 visible traces at once.}}
    return [list $state($w,x) $ys $requests]
}
proc ::GX::scientificDatasetViewerPlot {w} {
    variable ::GX::DatasetViewer::state
    if {[catch {
        datasetViewerCheck $w;scientificDatasetViewerCancel $w
        if {$state($w,source) ne {}} {curveSourceClose $state($w,source);set state($w,source) {}}
        set state($w,plottedRequest) [scientificDatasetViewerSelection $w]
        lassign $state($w,plottedRequest) x ys requests
        set state($w,coordinateContext) [datasetCoordinateRead $::GX::currentSession $state($w,id)]
        scientificDatasetCoordinateOverlay $state($w,coordinateContext) $ys
        set state($w,queue) {};set state($w,series) {}
        foreach filters $requests {foreach y $ys {lappend state($w,queue) [list $y $filters]}}
        if {$state($w,scene) ne {}} {::GX::Native2D::core destroy $state($w,scene);set state($w,scene) {}}
        scientificDatasetViewerNext $w
    } message]} {if {[info exists state($w,id)]} {set state($w,status) $message}}
}
proc ::GX::scientificDatasetViewerNext {w} {
    variable ::GX::DatasetViewer::state
    if {![llength $state($w,queue)]} {scientificDatasetViewerFit $w;return}
    lassign [lindex $state($w,queue) 0] y filters;set state($w,queue) [lrange $state($w,queue) 1 end]
    set state($w,loading) [list $y $filters]
    set request [dict create dataset_id $state($w,id) x_variable_id [lindex $state($w,plottedRequest) 0] y_variable_id $y display_budget 4096]
    dict set request filters $filters
    if {[info exists state($w,ordering)] && $state($w,ordering) ne {}} {dict set request order_variable_id $state($w,ordering)}
    set state($w,source) [curveSourceOpen $::GX::currentSession $request [list ::GX::scientificDatasetOpeningProgress $w $state($w,epoch)]]
    set state($w,job) [curveSourceDisplayAsync $state($w,source) [list ::GX::scientificDatasetViewerReady $w] [list ::GX::scientificDatasetViewerProgress $w]]
}
proc ::GX::scientificDatasetViewerReady {w receipt} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set state($w,job) {}
    if {[dict get $receipt status] ne "ok"} {set state($w,status) [datasetPublicationV2DictDefault $receipt message {Loading cancelled}];return}
    if {[catch {
        datasetViewerCheck $w;set display [dict get $receipt display]
        if {[datasetCoordinateRead $::GX::currentSession $state($w,id)] ne $state($w,coordinateContext)} {error {Coordinate settings changed during loading; select Plot again}}
        lassign $state($w,loading) y filters
        set display [scientificDatasetCoordinateDisplay $state($w,coordinateContext) [lindex $state($w,plottedRequest) 0] $y $display]
        if {$state($w,scene) eq {}} {
            set state($w,scene) [scientificDatasetDisplayScene $display]
            ::GX::Native2D::core aspect $state($w,scene) $state($w,aspect)
        } else {
            scientificDatasetCoordinateAddTrace $state($w,scene) $display [llength $state($w,series)]
        }
        lassign $state($w,loading) y filters
        set member [join $filters {; }]
        lappend state($w,series) [dict create y $y member $member filters $filters display $display]
        curveSourceClose $state($w,source);set state($w,source) {}
        scientificDatasetViewerCoordinateLegend $w
        set state($w,status) "[scientificDatasetFilterMode $state($w,dimensions) $state($w,filters) $state($w,separate)] — [llength $state($w,series)] trace(s); last trace: [dict get $display row_count] canonical rows, [llength [dict get $display points]] displayed points. Gaps retained; reduced: [dict get $display reduced]. Drag to Pan; wheel zooms."
        scientificDatasetViewerNext $w
    } message]} {if {[info exists state($w,id)]} {set state($w,status) $message}}
}
proc ::GX::scientificDatasetViewerPoint {w x y} {
    variable ::GX::DatasetViewer::state
    if {$state($w,scene) eq {}} return
    set distance 12;set hit {}
    foreach series $state($w,series) {
        set display [dict get $series display];set i 0
        foreach p [dict get $display points] {
            lassign [::GX::Native2D::core device $state($w,scene) $p] px py
            set d [expr {hypot($px-$x,$py-$y)}]
            if {$d<$distance} {set distance $d;set hit "[dict get $series y] [dict get $series member] · canonical row [expr {1+[lindex [dict get $display source_rows] $i]}] · displayed X/Y: $p [dict get $display coordinate_presentation display_units] · canonical X/Y: [lindex [dict get $display canonical_points] $i]"}
            incr i
        }
    }
    if {$hit ne {}} {set state($w,status) $hit}
}

proc ::GX::scientificDatasetOpeningProgress {w epoch receipt} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]||$state($w,epoch)!=$epoch} {error {Scientific source opening cancelled}}
    datasetViewerCheck $w
    set state($w,status) "Counting canonical rows: [dict get $receipt completed_rows]. Cancel remains available."
}
