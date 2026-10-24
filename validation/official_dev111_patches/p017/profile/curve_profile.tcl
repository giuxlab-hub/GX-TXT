# SPDX-License-Identifier: GPL-3.0-or-later
# Sourced by history_profile.tcl; explicit actual command timings, not pointer-input acceptance.
set traceTimes {};set traceStacks {}
proc traceMeasure {name args} {
    set op [lindex $args end]
    if {$op eq {enter}} {dict lappend ::traceStacks $name [clock microseconds]} else {
        set stack [dict get $::traceStacks $name];set start [lindex $stack end]
        dict set ::traceStacks $name [lrange $stack 0 end-1]
        dict lappend ::traceTimes $name [expr {[clock microseconds]-$start}]
    }
}
proc curveRecord {w} {
    if {[dict exists $::GX::ScientificHistory::viewers $w]} {return [::GX::scientificHistoryViewerRecord $w]}
    return $::GX::CurveWorkbench::st($w,scientificRecipe)
}
proc curveProfile {} {
    ::GX::modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
    set w [::GX::CurveWorkbench::open {workspace_id new workspace_name {P017 synthetic CAD performance}}]
    wm geometry $w 1280x840+10+10
    update
    set config [::GX::CurveWorkbench::_coordinateConfigurationDefault]
    dict set config x_unit mm;dict set config y_unit mm
    set ::GX::CurveWorkbench::st($w,coordinateConfiguration) $config
    set values [dict create name {Profile retained Line} family line closed 0 controls {{0 0} {1 1}} radius_x 1 radius_y 1 rotation 0 angle_start 0 angle_sweep 90 samples 2]
    set id [::GX::CurveWorkbench::_sketchApply $w [::GX::interactiveDocumentSessionToken] {} $values]
    update
    set ::GX::CurveWorkbench::st($w,stripView) History
    if {[info commands ::GX::scientificHistoryViewerStripSet] ne {} && [dict exists $::GX::ScientificHistory::viewers $w]} {
        ::GX::scientificHistoryViewerStripSet $w {mode History}
    } else {::GX::CurveWorkbench::_timelineSwitch $w}
    set traced {}
    foreach name {
        ::GX::CurveWorkbench::_snapshotIds ::GX::CurveWorkbench::_recipeState
        ::GX::CurveWorkbench::_history ::GX::CurveWorkbench::_timelineRender
        ::GX::CurveWorkbench::_save ::GX::CurveWorkbench::_writeWorkspace
        ::GX::CurveWorkbench::_draw ::GX::CurveWorkbench::_curveList
        ::GX::CurveWorkbench::_pointList ::GX::CurveWorkbench::_changed
        ::GX::scientificHistoryViewerChanged ::GX::scientificHistoryViewerRefresh
        ::GX::scientificHistoryAppend ::GX::scientificHistoryValidate
        ::GX::scientificHistoryState ::GX::scientificRecipeAppend
        ::GX::scientificRecipeEncode ::GX::scientificRecipeApplyPatch
        ::GX::interactiveDocumentRead ::GX::interactiveDocumentUpdate
        ::GX::_interactiveDocumentWritePayload ::GX::workbenchRecoveryCheckpoint
        ::GX::_workbenchRecoveryRead ::GX::_workbenchRecoveryWrite
        ::GX::_workbenchRecoveryDigest
    } {
        if {[info commands $name] ne {}} {trace add execution $name {enter leave} [list traceMeasure $name];lappend traced $name}
    }
    set perOperation {};set i 0;set maxMoves 400;set finishAfter -1
    if {[info exists ::env(GXTXT_PROFILE_MOVES)]} {set maxMoves $::env(GXTXT_PROFILE_MOVES)}
    while {$i<$maxMoves} {
        incr i
        set ::traceTimes {};set ::traceStacks {}
        set uiStart [clock microseconds];set ::profileTick 0
        after 0 {set ::profileTick [clock microseconds]}
        set begin [clock microseconds]
        ::GX::CurveWorkbench::_cadTransformApply $w translate [list $id] {0 0} [dict create dx 0.01 dy 0.001]
        set accepted [clock microseconds]
        update
        assert {$::profileTick>0} {Queued UI timer did not execute}
        set elapsed [expr {$accepted-$begin}];set ui [expr {$::profileTick-$uiStart}]
        set r [curveRecord $w];set bytes [string bytelength $r]
        set steps [llength [dict get $r steps]]
        set traceSummary {}
        dict for {name timings} $::traceTimes {
            set total 0;foreach t $timings {incr total $t}
            dict set traceSummary $name [dict create calls [llength $timings] total_us $total]
        }
        lappend perOperation [dict create move $i steps $steps record_bytes $bytes acceptance_us $elapsed ui_latency_us $ui stages $traceSummary]
        if {$i<=3 || $i%20==0 || $bytes>=7600000} {
            puts "CURVE_MOVE $i steps=$steps bytes=$bytes acceptance_us=$elapsed ui_latency_us=$ui";flush stdout
            emit curve_progress.tcldict $perOperation
        }
        if {$i in {1 64 128 192 240} || ($bytes>=7600000 && $finishAfter<0)} {
            catch {exec timeout 10 import -window [winfo id $w] [file join $::out curve_move_$i.png]}
            emit curve_record_$i.tcldict $r
        }
        if {$bytes>=7600000 && $finishAfter<0} {set finishAfter [expr {$i+3}]}
        if {$finishAfter>0 && $i>=$finishAfter && ![info exists ::env(GXTXT_PROFILE_MOVES)]} break
        if {$bytes>=8300000} break
    }
    foreach name $traced {trace remove execution $name {enter leave} [list traceMeasure $name]}
    emit curve_operations.tcldict $perOperation
    set r [curveRecord $w]
    emit curve_summary.tcldict [dict create framework $::framework mode actual_mapped_curve_GUI_with_API_invoked_CAD total_moves $i record_bytes [string bytelength $r] retained_steps [llength [dict get $r steps]] history_visible 1 scientific_workload {One retained Line; repeated true translate commands with normal history/persistence and rendering} pointer_input_acceptance 0]
    measure [llength [dict get $r steps]] curve_capture {::GX::CurveWorkbench::_recipeState $w}
    if {[info commands ::GX::CurveWorkbench::_timelineRender] ne {}} {measure [llength [dict get $r steps]] curve_timeline {::GX::CurveWorkbench::_timelineRender $w}}
    measure [llength [dict get $r steps]] curve_explicit_save {::GX::CurveWorkbench::_saveExplicit $w} 1
    emit curve_final_record.tcldict [curveRecord $w]
    ::GX::CurveWorkbench::_close $w
}
