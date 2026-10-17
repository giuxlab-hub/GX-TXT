# SPDX-License-Identifier: GPL-3.0-or-later
# A comparison is an explicit reference/target/method request, independent of
# the primary property focus. Drawing another curve never retargets that request.
proc ::GX::CurveWorkbench::_comparisonEvaluate {w config} {
    variable st
    set reference [dict get $config reference];set target [dict get $config target];set method [dict get $config method]
    if {![dict exists $st($w,curves) $reference]||![dict exists $st($w,curves) $target]||$reference eq $target} {error {Comparison needs distinct valid reference and target curves}}
    set options [_coordinateComparisonOptions $w $reference $target $method]
    if {$method eq "geometry"} {
        set record [_geometricComparisonEvaluate $w $reference $target 257 $options]
        dict set record coordinate_presentation_signature [_coordinateComparisonSignature $w $config]
        return $record
    }
    lassign [_evaluatedObject $w $reference] a temporaryA
    try {
        lassign [_evaluatedObject $w $target] b temporaryB
        try {set receipt [::GX::native2DComparison $st($w,scene) $a $b $method 4096 [_coordinateUnits [_record $w $reference]] [_coordinateUnits [_record $w $target]] [dict create producer viewer.curve_workbench reference $reference target $target evaluated_representation [_comparisonRepresentation $w $reference $target]] $options]} finally {if {$temporaryB} {::GX::Native2D::core delete $st($w,scene) $b}}
    } finally {if {$temporaryA} {::GX::Native2D::core delete $st($w,scene) $a}}
    return [dict create definition $config fingerprints [dict create $reference [_measurementFingerprint $w $reference] $target [_measurementFingerprint $w $target]] receipt $receipt coordinate_presentation_signature [_coordinateComparisonSignature $w $config]]
}
proc ::GX::CurveWorkbench::_comparisonRefresh {w} {
    variable st
    if {![info exists st($w,comparisonEnabled)]||!$st($w,comparisonEnabled)||$st($w,comparisonConfig) eq {}} {
        set st($w,residual) {};set st($w,comparisonText) {Comparison inactive};_drawResidual $w;return
    }
    set config $st($w,comparisonConfig);set record $st($w,comparisonRecord)
    if {$record eq {}||[_measurementState $w $record] ne "current"||![dict exists $record receipt statistics]||![dict exists $record coordinate_presentation_signature]||[dict get $record coordinate_presentation_signature] ne [_coordinateComparisonSignature $w $config]} {
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
    set st($w,status) "$st($w,comparisonText): [::GX::StatisticsV1::report [dict get $record receipt statistics reference] {n rmse mae max_abs_error}]"
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

proc ::GX::CurveWorkbench::_comparisonRepresentation {w reference target} {
    set result {}
    foreach id [list $reference $target] {
        set record [_record $w $id]
        dict set result $id [dict create representation [dict get $record representation] evaluation [expr {[dict get $record representation] eq "spline" ? "spline_16_subdivisions_per_span" : "native_vertices"}]]
    }
    return $result
}
