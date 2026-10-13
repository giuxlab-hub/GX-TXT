# SPDX-License-Identifier: GPL-3.0-or-later
# A comparison is an explicit reference/target/method request, independent of
# the primary property focus. Drawing another curve never retargets that request.
proc ::GX::CurveWorkbench::_comparisonEvaluate {w config} {
    variable st
    set reference [dict get $config reference];set target [dict get $config target];set method [dict get $config method]
    if {![dict exists $st($w,curves) $reference]||![dict exists $st($w,curves) $target]||$reference eq $target} {error {Comparison needs distinct valid reference and target curves}}
    if {$method eq "geometry"} {return [_geometricComparisonEvaluate $w $reference $target 257]}
    lassign [_evaluatedObject $w $reference] a temporaryA
    try {
        lassign [_evaluatedObject $w $target] b temporaryB
        try {set receipt [::GX::Native2D::core compare_lod $st($w,scene) $a $b $method 4096]} finally {if {$temporaryB} {::GX::Native2D::core delete $st($w,scene) $b}}
    } finally {if {$temporaryA} {::GX::Native2D::core delete $st($w,scene) $a}}
    return [dict create definition $config fingerprints [dict create $reference [_measurementFingerprint $w $reference] $target [_measurementFingerprint $w $target]] receipt $receipt]
}
proc ::GX::CurveWorkbench::_comparisonRefresh {w} {
    variable st
    if {![info exists st($w,comparisonEnabled)]||!$st($w,comparisonEnabled)||$st($w,comparisonConfig) eq {}} {
        set st($w,residual) {};set st($w,comparisonText) {Comparison inactive};_drawResidual $w;return
    }
    set config $st($w,comparisonConfig);set record $st($w,comparisonRecord)
    if {$record eq {}||[_measurementState $w $record] ne "current"} {
        if {[catch {set record [_comparisonEvaluate $w $config]} message]} {
            set st($w,comparisonEnabled) 0;set st($w,residual) {};set st($w,comparisonText) "Comparison inactive: $message";_drawResidual $w;return
        }
        set st($w,comparisonRecord) $record
    }
    set st($w,compareMethod) [dict get $config method]
    set st($w,residual) [dict get $record receipt]
    if {[dict get $config method] eq "geometry"} {set st($w,lastGeometricComparison) $record}
    set st($w,comparisonText) "Comparing [dict get [_record $w [dict get $config target]] name] against [dict get [_record $w [dict get $config reference]] name] ([dict get $config method])"
    _drawResidual $w
}
proc ::GX::CurveWorkbench::_compare {w} {
    variable st
    set config [dict create reference $st($w,reference) target [_active $w] method $st($w,compareMethod)]
    # Evaluate before changing state. A rejected request cannot activate stale
    # residuals or replace a previously valid comparison.
    set record [_comparisonEvaluate $w $config];set before [_snapshotIds $w {}]
    set st($w,comparisonConfig) $config;set st($w,comparisonRecord) $record;set st($w,comparisonEnabled) 1
    _comparisonRefresh $w;_history $w $before {};_draw $w
    set st($w,status) $st($w,comparisonText)
    return [dict get $record receipt]
}
proc ::GX::CurveWorkbench::_comparisonToggle {w} {
    variable st
    if {$st($w,comparisonEnabled)} {_compare $w} else {set st($w,residual) {};_comparisonRefresh $w;_draw $w;_save $w}
}
proc ::GX::CurveWorkbench::_changed {w} {
    variable st
    # Preserve established geometry/history/persistence orchestration; its old
    # implicit comparison call has been removed at the shared edit boundary.
    _comparisonRefresh $w
    _changed_comparison_base $w
    _comparisonRefresh $w
    _draw $w
}
rename ::GX::CurveWorkbench::_referenceSelect ::GX::CurveWorkbench::_referenceSelect_comparison057_base
proc ::GX::CurveWorkbench::_referenceSelect {w} {
    variable st
    _referenceSelect_comparison057_base $w
    set st($w,comparisonEnabled) 0;set st($w,comparisonConfig) {};set st($w,comparisonRecord) {}
    _comparisonRefresh $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_buildComparisonActivation {w} {
    variable st
    ttk::checkbutton $w.validation.enabled -text {Comparison enabled} -variable ::GX::CurveWorkbench::st($w,comparisonEnabled) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_comparisonToggle $w]]
    ttk::label $w.validation.state -textvariable ::GX::CurveWorkbench::st($w,comparisonText)
    pack $w.validation.enabled $w.validation.state -side left -padx 3
    bind $w.validation.method <<ComboboxSelected>> [list ::GX::CurveWorkbench::_comparisonMethodChanged $w]
}

proc ::GX::CurveWorkbench::_comparisonMethodChanged {w} {
    variable st
    set st($w,comparisonEnabled) 0;set st($w,comparisonConfig) {};set st($w,comparisonRecord) {}
    _comparisonRefresh $w;_save $w
}
