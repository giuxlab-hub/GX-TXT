# SPDX-License-Identifier: GPL-3.0-or-later
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
        set choice $st($w,historyRecoveryChoice)
        if {$choice eq {}} {set info [::GX::workbenchRecoveryPrompt $document $w]} else {
            set info [::GX::workbenchRecoveryInspect $document]
            if {[dict get $info status] ni {clean absent corrupt}} {
                if {$choice eq {cancel}} {error {Workspace recovery cancelled}}
                set info [::GX::workbenchRecoveryResolve $document [expr {$choice eq {recover} ? {recover} : {saved}}]]
            }
        }
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
