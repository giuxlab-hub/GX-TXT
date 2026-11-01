# SPDX-License-Identifier: GPL-3.0-or-later
# Scientific/logical adapter only. Shared CORE owns advanced relationship input,
# native proposals, editing widgets, annotation interaction and presentation.
proc ::GX::CurveWorkbench::_advancedRelationships {w} {
    variable st
    # Restored relationships may render during window construction, before the
    # command-install pass sets this existing local selection preference.
    if {![info exists st($w,selectionTarget)]} {set st($w,selectionTarget) local}
    return [[_cadCanvas $w] advanced]
}
proc ::GX::CurveWorkbench::_advancedConstraintAdmit {w event} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken] || ![_cadCanvasGuard $w $event]} {error {Session or Document changed; reopen Curve Workbench}}
    if {[dict exists $event specification]} {_constraintCoordinateGuard $w [dict get $event specification]}
    return 1
}
proc ::GX::CurveWorkbench::_advancedConstraintAdopt {w id spec receipt affected before} {
    variable st
    set reverse [_logicalNativeMap $w]
    set definition [dict remove $receipt id valid geometry_supported measured_value residual angular_residual enforcement general_solver]
    foreach key {a b axis} {if {[dict get $definition $key]==0} {dict unset definition $key} else {dict set definition $key [dict get $reverse [dict get $definition $key]]}}
    if {$id eq {}} {set id constraint[incr st($w,nextConstraint)]}
    dict set st($w,constraints) $id [dict create id $id name [_constraintTitle [dict get $spec kind]] native [dict get $receipt id] definition $definition]
    try {
        foreach logical $affected {if {[dict exists [_record $w $logical] sketch_definition]} {_syncSamples $w $logical}}
        _history $w $before $affected
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,selectedRelationship) $id;set st($w,constraintTool) {};_constraintRefresh $w;_draw $w
    set st($w,status) "[_constraintTitle [dict get $spec kind]] — [expr {[dict get $receipt driven]?{reference measurement}:{Native2D relationship committed}}]."
    return $id
}
proc ::GX::CurveWorkbench::_advancedDimensionGuard {w token incarnation} {return [_windowCurrent $w $incarnation $token]}
proc ::GX::CurveWorkbench::_advancedDimensionParse {w ids key spec text} {
    _coordinateControlCheck $w $ids $key
    _save $w
    return [_dimensionInput $w $spec $text]
}
proc ::GX::CurveWorkbench::_advancedDimensionCommit {w logical event} {
    variable st
    set id [_constraintCommit $w $logical [dict get $event specification]]
    if {$id eq {}} {error {History is not editable at the selected step}}
    dict set st($w,constraints) $id expression [dict get $event expression]
    _save $w
    return $id
}
proc ::GX::CurveWorkbench::_advancedDimensionAccepted {w event} {
    variable st
    foreach key {dimRefs dimSpec dimAnnotation dimExisting} {set st($w,$key) {}}
    set st($w,constraintTool) dimension;set st($w,toolLabel) {Dimension — select the next geometry, or Esc for Select.}
    # The shared editor closes, clears its proposal and requests the final frame
    # after this adoption hook. Drawing here duplicates that owned refresh.
    if {[winfo exists $w.right.viewport.canvas]} {focus $w.right.viewport.canvas}
}
proc ::GX::CurveWorkbench::_advancedDimensionCancelled {w reason} {
    variable st
    foreach key {dimRefs dimSpec dimAnnotation dimExisting} {set st($w,$key) {}}
    if {$reason eq {escape}} {set st($w,constraintTool) {};set st($w,toolLabel) {Select — geometry, handles, constraints or dimensions.}}
}
