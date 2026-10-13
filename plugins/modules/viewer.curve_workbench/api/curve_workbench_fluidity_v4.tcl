# SPDX-License-Identifier: GPL-3.0-or-later
# Camera state changes immediately in Native. Drawing is bounded to one pending
# frame and persistence to one checkpoint after a burst, retaining close/save
# and semantic-edit recovery behavior through the existing save authority.
proc ::GX::CurveWorkbench::_viewDrawLater {w} {
    variable st
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
    if {[info exists st($w,viewDrawPending)]&&$st($w,viewDrawPending) ne {}} {
        after cancel $st($w,viewDrawPending);_viewDrawNow $w
    }
    return 0

    return 1
}

