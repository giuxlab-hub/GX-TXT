# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveWorkbench::_recoveryCheckpoint {w operation} {
    variable st
    if {$st($w,document) eq ""} return
    if {[catch {::GX::workbenchRecoveryCheckpoint $st($w,document) [dict create operation $operation module_id viewer.curve_workbench module_version $::GX::CurveWorkbench::version api_id NATIVE2D_API_v1 api_version 1]} message]} {
        set st($w,recoveryNotice) "Workspace committed; recovery checkpoint unavailable: $message"
    } else {set st($w,recoveryNotice) ""}
}
rename ::GX::CurveWorkbench::_history ::GX::CurveWorkbench::_history_recovery_base
proc ::GX::CurveWorkbench::_history {w before ids} {_history_recovery_base $w $before $ids;_recoveryCheckpoint $w edit}
foreach action {undo redo} {
    rename ::GX::CurveWorkbench::$action ::GX::CurveWorkbench::${action}_recovery_base
    proc ::GX::CurveWorkbench::$action {w} [format {
        %s_recovery_base $w
        _recoveryCheckpoint $w %s
    } $action $action]
}
rename ::GX::CurveWorkbench::_load ::GX::CurveWorkbench::_load_recovery_base
proc ::GX::CurveWorkbench::_load {w} {
    variable st
    set docs [::GX::interactiveDocumentList viewer.curve_workbench curve_workbench]
    if {[info exists ::GX::CurveWorkbench::openingWorkspace]} {
        set requested $::GX::CurveWorkbench::openingWorkspace
        if {$requested eq "new"} {set docs {}} elseif {$requested ne {}} {set docs [list [::GX::interactiveDocumentRead $requested]]}
    }
    if {$docs ne {}} {
        set document [dict get [lindex $docs 0] id]
        set info [::GX::workbenchRecoveryPrompt $document $w]
        if {[dict get $info status] eq "corrupt"} {set st($w,recoveryNotice) "Recovery journal is corrupt; normal saved document remains available: [dict get $info reason]"}
    }
    set result [_load_recovery_base $w]
    if {$st($w,document) ne ""&&[dict get [::GX::workbenchRecoveryInspect $st($w,document)] status] ne "corrupt"} {
        if {[catch {::GX::workbenchRecoveryBegin $st($w,document)} message]} {set st($w,recoveryNotice) "Recovery journal unavailable: $message"}
    }
    return $result
}
proc ::GX::CurveWorkbench::_buildRecovery {w} {
    variable st
    ttk::label $w.recoveryWarning -textvariable ::GX::CurveWorkbench::st($w,recoveryNotice) -foreground #A32B20 -wraplength 900
    trace add variable ::GX::CurveWorkbench::st($w,recoveryNotice) write [list ::GX::CurveWorkbench::_recoveryNoticeShow $w]
    bind $w <Destroy> +[list ::GX::CurveWorkbench::_recoveryNoticeDispose $w %W]
    _recoveryNoticeShow $w
    $w.publish.save configure -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_saveExplicit $w]]
}

proc ::GX::CurveWorkbench::_recoveryNoticeShow {w args} {
    variable st
    if {![winfo exists $w.recoveryWarning]} return
    if {$st($w,recoveryNotice) eq {}} {pack forget $w.recoveryWarning} else {pack $w.recoveryWarning -side bottom -fill x -before $w.main -padx 8 -pady 4}
}
proc ::GX::CurveWorkbench::_recoveryNoticeDispose {w actual} {
    variable st;if {$w ne $actual} return
    catch {trace remove variable ::GX::CurveWorkbench::st($w,recoveryNotice) write [list ::GX::CurveWorkbench::_recoveryNoticeShow $w]}
}
