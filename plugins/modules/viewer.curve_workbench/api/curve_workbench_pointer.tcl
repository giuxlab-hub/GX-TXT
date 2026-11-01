# SPDX-License-Identifier: GPL-3.0-or-later
# One pointer dispatcher. Feature stages return 1 when they own the event and
# 0 to continue; they never call another stage or historical handler version.
# Keep this priority explicit: semantic selection yields to precise overlays,
# modal construction/constraints, then CAD and scientific editing/navigation.
proc ::GX::CurveWorkbench::_mouseDown {w x y state} {
    foreach handler {
        _pointerDownPart _pointerDownSelection _pointerDownImage _pointerDownViewport
        _pointerDownConstruction _pointerDownConstraint _pointerDownRetained
        _pointerDownJoin _pointerDownTransform _pointerDownScientific
    } {
        if {[$handler $w $x $y $state]} return
    }
}
proc ::GX::CurveWorkbench::_mouseMove {w x y} {
    foreach handler {
        _pointerMovePart _pointerMoveSelection _pointerMoveViewport _pointerMoveAnnotation
        _pointerMoveControl _pointerMoveTransform _pointerMoveScientific
    } {
        if {[$handler $w $x $y]} return
    }
}
proc ::GX::CurveWorkbench::_mouseUp {w x y} {
    # Semantic point/box commits already draw their final state. Other gestures
    # flush the existing pending frame before their own release/commit stage.
    foreach handler {
        _pointerUpPart _pointerUpSelection _pointerUpFrame _pointerUpViewport
        _pointerUpConstraint _pointerUpControl _pointerUpTransform
        _pointerUpScientific
    } {
        if {[$handler $w $x $y]} return
    }
}

# Viewport-only gesture: independent of construction, semantic selection and Undo.
proc ::GX::CurveWorkbench::_middlePan {w phase x y} {
    set event [dict get {start pan_start move pan_move end pan_end} $phase]
    [_cadCanvas $w] event $event $x $y
}
