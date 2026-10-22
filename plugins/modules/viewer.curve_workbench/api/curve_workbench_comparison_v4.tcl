# SPDX-License-Identifier: GPL-3.0-or-later
# A comparison is an explicit reference/target/method request, independent of
# the primary property focus. Drawing another curve never retargets that request.
# Read-only binding to the actual committed comparison owner. Neither capture
# nor validation evaluates geometry, saves a Workspace or publishes a Dataset.
proc ::GX::CurveWorkbench::_comparisonDisplayProvenance {w config} {
    set result {}
    foreach role {reference target} {
        set id [dict get $config $role];set curve [_record $w $id]
        set descriptor [::GX::datasetPublicationV2DictDefault $curve source_descriptor {}]
        set source [dict get $curve source]
        set provenance [dict create geometry_id $id source_kind [expr {$source eq {} ? {editable_geometry} : {cached_source_geometry}}] dataset_id $source captured_source_descriptor $descriptor]
        if {$descriptor ne {}} {
            if {[catch {set status [::GX::curveSourceValidateSnapshot [_session] $descriptor]} message]} {set status [dict create status unavailable reason $message]}
            dict set provenance source_status_at_admission $status
        }
        dict set result $role $provenance
    }
    return $result
}
proc ::GX::CurveWorkbench::comparisonDisplaySource {w} {
    variable st
    if {![info exists st($w,token)] || ![winfo exists $w]} {error {Comparison window is closed}}
    set config $st($w,comparisonConfig);set record $st($w,comparisonRecord)
    set generation {}
    if {$st($w,document) ne {}} {set generation [dict get [::GX::interactiveDocumentRead $st($w,document)] generation]}
    set binding [dict create api_id CURVE_WORKBENCH_API_v1 api_version 1         window $w incarnation [winfo id $w] session_token $st($w,token)         document_id $st($w,document) owner_generation $generation definition $config         comparison_identity $record]
    comparisonDisplayValidate $binding $record
    dict set binding source_provenance [_comparisonDisplayProvenance $w $config]
    return $binding
}
proc ::GX::CurveWorkbench::comparisonDisplayValidate {binding record} {
    variable st
    foreach field {api_id api_version window incarnation session_token document_id owner_generation definition comparison_identity} {
        if {![dict exists $binding $field]} {error "Comparison display binding is missing $field"}
    }
    if {[dict get $binding api_id] ne {CURVE_WORKBENCH_API_v1} || [dict get $binding api_version]!=1} {error {Invalid comparison display binding}}
    set w [dict get $binding window]
    if {![_windowCurrent $w [dict get $binding incarnation] [dict get $binding session_token]]} {error {Comparison window or Session changed; reopen it}}
    if {![info exists st($w,comparisonEnabled)] || !$st($w,comparisonEnabled) || $st($w,comparisonConfig) eq {}} {error {Comparison is inactive; select Compare to refresh}}
    set config $st($w,comparisonConfig)
    foreach field {reference target method} {if {![dict exists $config $field]} {error {Comparison has no explicit reference, target and method}}}
    if {$config ne [dict get $binding definition] || $record eq {} || $record ne $st($w,comparisonRecord) ||
        $record ne [dict get $binding comparison_identity]} {error {Comparison definition or result changed; select Compare to refresh}}
    if {$st($w,residual) ne [dict get $record receipt]} {error {Displayed comparison receipt is no longer active}}
    if {[_measurementState $w $record] ne {current}} {error {Comparison geometry changed; select Compare to refresh}}
    if {![dict exists $record coordinate_presentation_signature] || [dict get $record coordinate_presentation_signature] ne [_coordinateComparisonSignature $w $config]} {error {Comparison coordinate presentation changed; select Compare to refresh}}
    if {$st($w,document) ne [dict get $binding document_id]} {error {Comparison Document owner changed; select Compare to refresh}}
    if {$st($w,document) ne {}} {
        set owner [::GX::interactiveDocumentRead $st($w,document)]
        set generation [dict get $owner generation]
        if {$generation ne [dict get $binding owner_generation] ||
            [info exists st($w,ownerGeneration)] && $generation ne $st($w,ownerGeneration)} {error {Comparison Document owner was replaced; reopen it}}
    } elseif {[dict get $binding owner_generation] ne {}} {error {Unsaved comparison has no Document generation}}
    foreach role {reference target} {
        set curve [_record $w [dict get $config $role]]
        foreach key {geometry_resource row_resource gap_resource} {
            if {[dict exists $curve $key]} {::GX::interactiveDocumentResourceInfo [dict get $curve $key]}
        }
    }
    set result [dict create valid 1]
    if {[dict exists $binding source_provenance]} {dict set result source_provenance [dict get $binding source_provenance]}
    return $result
}

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
