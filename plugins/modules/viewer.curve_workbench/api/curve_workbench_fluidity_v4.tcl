# SPDX-License-Identifier: GPL-3.0-or-later
# Camera state changes immediately in Native. Existing UI timers coalesce
# redraw and presentation capture after a burst. CORE owns auxiliary acceptance,
# ordered background persistence and Save/Close durability; no disk work runs here.
proc ::GX::CurveWorkbench::_viewDrawLater {w} {
    variable st
    if {[info exists st($w,drag)] && $st($w,drag) ne {} && [dict get $st($w,drag) mode] eq {pan}} {_viewportDrawLater $w;return}
    # Semantic drag requests retain their original16ms owner and end adaptation.
    _wheelDrawCancel $w
    if {![info exists st($w,viewDrawPending)]||$st($w,viewDrawPending) eq {}} {
        set st($w,viewDrawPending) [after 16 [list ::GX::CurveWorkbench::_viewDrawNow $w]]
    }
}
proc ::GX::CurveWorkbench::_viewDrawNow {w} {
    variable st
    if {![winfo exists $w.right.viewport.canvas]||![info exists st($w,scene)]} return
    set st($w,viewDrawPending) {}
    _draw $w
}
proc ::GX::CurveWorkbench::_viewPersistLater {w} {
    variable st
    # Keep the original failed-restore diagnostic visible. Configure/camera
    # events must not repeatedly open save-error dialogs for a protected payload.
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} return
    if {[info exists st($w,viewSavePending)]} {after cancel $st($w,viewSavePending)}
    set st($w,viewSavePending) [after 350 [list ::GX::CurveWorkbench::_viewPersistNow $w]]
}
proc ::GX::CurveWorkbench::_viewPersistNow {w} {
    variable st
    if {![winfo exists $w.right.viewport.canvas]||![info exists st($w,scene)]} return
    set st($w,viewSavePending) {}
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} return
    _safe $w [list ::GX::CurveWorkbench::_save $w]
}
proc ::GX::CurveWorkbench::_pointerUpFrame {w x y} {
    variable st
    if {[info exists st($w,drag)] && $st($w,drag) ne {} && [dict get $st($w,drag) mode] eq {pan} && [info exists st($w,wheelScheduler)]} {
        ::GX::guiUpdateSchedulerFinish $st($w,wheelScheduler)
    }
    if {[info exists st($w,viewDrawPending)]&&$st($w,viewDrawPending) ne {}} {
        after cancel $st($w,viewDrawPending);_viewDrawNow $w
    }
    return 0

    return 1
}


# Viewport wheel/pan/resize requests use the CORE global profile. Every zoom
# still executes synchronously; semantic point/selection edits retain local16ms.
# Transfer a pending frame between owners, never maintain two redraw queues.
proc ::GX::CurveWorkbench::_wheelDrawLater {w} {_viewportDrawLater $w}
proc ::GX::CurveWorkbench::_viewportDrawLater {w} {
    variable st
    if {![info exists st($w,scene)] || ![info exists st($w,token)]} return
    if {[info exists st($w,viewDrawPending)] && $st($w,viewDrawPending) ne {}} {
        after cancel $st($w,viewDrawPending);set st($w,viewDrawPending) {}
    }
    if {![info exists st($w,wheelScheduler)]} {
        set st($w,wheelScheduler) [::GX::guiUpdateSchedulerCreate $w.right.viewport.canvas [list ::GX::CurveWorkbench::_draw $w] [dict create profile global policy adaptive normal_ms 16 activity_window_ms 80 rapid_count 8 quiet_ms 80 guard [list ::GX::CurveWorkbench::_windowCurrent $w [winfo id $w] $st($w,token)]]]
    }
    ::GX::guiUpdateSchedulerRequest $st($w,wheelScheduler)
}
proc ::GX::CurveWorkbench::_wheelDrawCancel {w} {
    variable st
    if {[info exists st($w,wheelScheduler)]} {::GX::guiUpdateSchedulerCancel $st($w,wheelScheduler)}
}
proc ::GX::CurveWorkbench::_wheelDrawDispose {w} {
    variable st
    if {[info exists st($w,wheelScheduler)]} {
        ::GX::guiUpdateSchedulerDispose $st($w,wheelScheduler)
        unset st($w,wheelScheduler)
    }
}
