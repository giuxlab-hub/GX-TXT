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
# GUI choices project stable logical IDs. They never follow property focus.
proc ::GX::CurveWorkbench::_comparisonControls {w} {
    variable st
    if {[info exists st($w,comparisonControls)]} {return $st($w,comparisonControls)}
    return {}
}
proc ::GX::CurveWorkbench::_comparisonChoices {w} {
    variable st
    if {![info exists st($w,comparisonTarget)]} {set st($w,comparisonTarget) {}}
    set names {};set map {}
    dict for {id record} $st($w,curves) {
        if {[catch {_pointCount $record} count] || $count<2} continue
        if {[dict exists $record sketch_definition family] && [dict get $record sketch_definition family] eq {construction_line}} continue
        set label "[dict get $record name]  ·  $id"
        lappend names $label;dict set map $label $id
    }
    set st($w,referenceMap) $map
    set p [_comparisonControls $w]
    foreach {role variable widget} {reference reference reference target comparisonTarget targetPath} {
        set id $st($w,$variable);set label {}
        if {$id ne {}} {
            if {[dict exists $st($w,curves) $id]} {set label "[dict get [_record $w $id] name]  ·  $id"} else {set label "Unavailable · $id"}
        }
        set st($w,${role}Label) $label
        if {[winfo exists $p.curves.$widget] && [$p.curves.$widget cget -values] ne $names} {$p.curves.$widget configure -values $names}
    }
}
proc ::GX::CurveWorkbench::_comparisonDraft {w} {
    variable st
    return [dict create reference $st($w,reference) target $st($w,comparisonTarget) method $st($w,compareMethod)]
}
proc ::GX::CurveWorkbench::_comparisonRefresh {w} {
    variable st
    if {![info exists st($w,comparisonConfig)]} return
    set config $st($w,comparisonConfig)
    # Existing Workspace/Undo payload is the only persistent definition owner.
    # A newly restored/committed definition updates the controls once. Ordinary
    # focus changes do not rewrite the user's in-progress explicit choices.
    if {![info exists st($w,comparisonOwnerConfig)] || $st($w,comparisonOwnerConfig) ne $config} {
        set st($w,comparisonOwnerConfig) $config
        if {$config ne {}} {
            set st($w,reference) [dict get $config reference]
            set st($w,comparisonTarget) [dict get $config target]
            set st($w,compareMethod) [dict get $config method]
        }
    }
    _comparisonChoices $w
    set draft [_comparisonDraft $w];set record $st($w,comparisonRecord)
    set state {Not yet compared};set detail {Choose two different paths and select Compare.}
    set st($w,comparisonResults) {}
    set pairValid 1
    foreach role {reference target} {
        set id [dict get $draft $role]
        if {$id eq {} || ![dict exists $st($w,curves) $id] || $id ni [dict values $st($w,referenceMap)]} {
            set pairValid 0
            if {$id ne {}} {set state Unavailable;set detail "The $role path is no longer available. Select a path explicitly."}
        }
    }
    if {$pairValid && [dict get $draft reference] eq [dict get $draft target]} {set pairValid 0;set state Unavailable;set detail {Reference and Target must be different paths.}}
    if {$pairValid && [catch {_coordinateComparisonOptions $w [dict get $draft reference] [dict get $draft target] [dict get $draft method]} reason]} {set pairValid 0;set state Unavailable;set detail $reason}
    set current 0
    if {$pairValid && $config ne {} && $record ne {}} {
        if {$draft ne $config} {
            set state Stale;set detail {The selected pair or method changed. Select Compare to produce its results.}
        } elseif {!$st($w,comparisonEnabled)} {
            set state {Not yet compared};set detail {Select Compare to activate this pair.}
        } elseif {[catch {
            if {[_measurementState $w $record] ne {current} || ![dict exists $record receipt statistics] || ![dict exists $record coordinate_presentation_signature] || [dict get $record coordinate_presentation_signature] ne [_coordinateComparisonSignature $w $config]} {error {Geometry or coordinate presentation changed. Select Compare again.}}
            # Capture/validate only: never evaluate from a refresh or panel open.
            set st($w,residual) [dict get $record receipt]
            comparisonDisplaySource $w
        } reason]} {
            set state Stale;set detail $reason
        } else {set current 1;set state Completed;set detail {Current comparison of the selected paths.}}
    }
    if {$current} {
        set receipt [dict get $record receipt]
        set summary [::GX::StatisticsV1::report [dict get $receipt statistics reference] {n rmse mae max_abs_error}]
        if {[dict exists $receipt unit]} {append summary "\nUnit: [dict get $receipt unit]"} elseif {[dict exists $receipt units]} {append summary "\nUnits: [dict get $receipt units]"}
        set st($w,comparisonResults) $summary
        if {[dict get $config method] eq {geometry}} {set st($w,lastGeometricComparison) $record}
    } else {set st($w,residual) {}}
    if {[info exists st($w,comparisonError)] && $st($w,comparisonError) ne {}} {set state Unavailable;set detail $st($w,comparisonError)}
    set st($w,comparisonText) "$state — $detail"
    set reason [_comparisonPublicationReason $w]
    set st($w,comparisonPublicationText) [expr {$reason eq {} ? {Publishes the current geometric deviation samples with their existing sampling/projection provenance.} : $reason}]
    set p [_comparisonControls $w]
    if {[winfo exists $p.curves.compare]} {
        $p.curves.compare state [expr {$pairValid?{!disabled}:{disabled}}]
        $p.curves.publish state [expr {$reason eq {}?{!disabled}:{disabled}}]
    }
    _drawResidual $w
}
proc ::GX::CurveWorkbench::_comparisonPublicationReason {w} {
    variable st
    if {![info exists st($w,comparisonTarget)] || $st($w,comparisonConfig) eq {} || ![dict exists $st($w,comparisonConfig) method] || [dict get $st($w,comparisonConfig) method] ne {geometry}} {return {Publish deviations requires an explicit, completed Geometry comparison.}}
    if {[_comparisonDraft $w] ne $st($w,comparisonConfig) || !$st($w,comparisonEnabled) || $st($w,comparisonRecord) eq {} || $st($w,lastGeometricComparison) ne $st($w,comparisonRecord)} {return {Select Compare for the chosen Geometry pair before publishing deviations.}}
    if {[catch {comparisonDisplaySource $w} reason]} {return "Publication unavailable: $reason"}
    return {}
}
proc ::GX::CurveWorkbench::_comparisonPublishCurrentApply {w token record values} {
    variable st
    if {![info exists st($w,lastGeometricComparison)] || $record ne $st($w,lastGeometricComparison)} {error {Comparison changed while publication was open; reopen Publish deviations.}}
    tailcall _comparisonPublishApply $w $token $values
}
proc ::GX::CurveWorkbench::_compare {w} {
    variable st
    set config [_comparisonDraft $w]
    # Scientific validation/evaluation stays with the existing comparison owner.
    set record [_comparisonEvaluate $w $config];set before [_snapshotIds $w {}]
    set st($w,comparisonConfig) $config;set st($w,comparisonRecord) $record;set st($w,comparisonEnabled) 1
    set st($w,comparisonError) {}
    _comparisonRefresh $w;_history $w $before {};_draw $w
    set st($w,status) "Comparison completed: [dict get [_record $w [dict get $config reference]] name] → [dict get [_record $w [dict get $config target]] name] ([dict get $config method]). Results in Compare / residuals."
    return [dict get $record receipt]
}
proc ::GX::CurveWorkbench::_comparisonRun {w} {
    variable st
    set st($w,comparisonError) {};set st($w,comparisonText) {Computing the selected comparison…}
    if {[catch {_compare $w} reason]} {set st($w,comparisonError) $reason;_comparisonRefresh $w;_draw $w}
}
proc ::GX::CurveWorkbench::_comparisonToggle {w} {
    variable st
    if {$st($w,comparisonEnabled)} {_comparisonRun $w} else {_comparisonRefresh $w;_draw $w;_save $w}
}
proc ::GX::CurveWorkbench::_changed {w} {
    _comparisonRefresh $w
    _changed_comparison_base $w
    _comparisonRefresh $w
    _draw $w
}
rename ::GX::CurveWorkbench::_referenceSelect ::GX::CurveWorkbench::_referenceSelect_comparison057_base
proc ::GX::CurveWorkbench::_referenceSelect {w} {_comparisonSelectionChanged $w reference}
proc ::GX::CurveWorkbench::_comparisonSelectionChanged {w role} {
    variable st
    set field [expr {$role eq {reference}?{reference}:{comparisonTarget}}]
    if {[dict exists $st($w,referenceMap) $st($w,${role}Label)]} {set st($w,$field) [dict get $st($w,referenceMap) $st($w,${role}Label)]}
    set st($w,comparisonError) {}
    _comparisonRefresh $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_comparisonMethodChanged {w} {
    variable st;set st($w,comparisonError) {}
    _comparisonRefresh $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_buildComparison {w} {
    variable st
    set p [_comparisonControls $w]
    ::GX::uiFieldComponentCreate $p.curves section {title {Curve Comparison}} {} {}
    ::GX::uiFieldComponentCreate $p.measures section {title {Geometric Measurements}} {} {}
    pack $p.curves $p.measures -fill x -padx 2 -pady 3
    foreach {key caption variable callback} {
        reference {Reference path} referenceLabel reference
        targetPath {Target path} targetLabel target
        method {Method} compareMethod method
    } {
        ::GX::uiFieldComponentCreate $p.curves.${key}Label label [dict create text $caption wraplength 90] {} {}
        if {$callback eq {method}} {set command [list ::GX::CurveWorkbench::_comparisonMethodChanged $w]} else {set command [list ::GX::CurveWorkbench::_comparisonSelectionChanged $w $callback]}
        ::GX::uiFieldComponentCreate $p.curves.$key combobox {width 16} ::GX::CurveWorkbench::st($w,$variable) $command
    }
    $p.curves.method configure -values {x path geometry}
    ::GX::uiFieldComponentCreate $p.curves.compare action {label Compare} {} [list ::GX::CurveWorkbench::_comparisonRun $w]
    ::GX::uiFieldComponentCreate $p.curves.state status {wraplength 300} {} {}
    $p.curves.state configure -textvariable ::GX::CurveWorkbench::st($w,comparisonText)
    ::GX::uiFieldComponentCreate $p.curves.results status {wraplength 300} {} {}
    $p.curves.results configure -textvariable ::GX::CurveWorkbench::st($w,comparisonResults)
    ::GX::uiFieldComponentCreate $p.curves.publish action {label {Publish deviations…}} {} [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_comparisonPublishOpen $w]]
    ::GX::uiFieldComponentCreate $p.curves.publishHint status {wraplength 300} {} {}
    $p.curves.publishHint configure -textvariable ::GX::CurveWorkbench::st($w,comparisonPublicationText)
    set row 0
    foreach key {reference targetPath method} {
        grid $p.curves.${key}Label -row $row -column 0 -sticky w -padx 2 -pady 2
        grid $p.curves.$key -row $row -column 1 -sticky ew -padx 2 -pady 2
        incr row
    }
    foreach key {compare state results publish publishHint} {grid $p.curves.$key -row $row -column 0 -columnspan 2 -sticky ew -pady 3;incr row}
    grid columnconfigure $p.curves 1 -weight 1
    foreach {key caption} {metric Metric expected {Expected value}} {
        ::GX::uiFieldComponentCreate $p.measures.${key}Label label [dict create text $caption wraplength 90] {} {}
    }
    ::GX::uiFieldComponentCreate $p.measures.metric combobox {width 16} ::GX::CurveWorkbench::st($w,metricLabel) [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateMetricSelect $w]]
    ::GX::uiFieldComponentCreate $p.measures.expected entry {width 12} ::GX::CurveWorkbench::st($w,target) {}
    ::GX::uiFieldComponentCreate $p.measures.evaluate action {label Evaluate} {} [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_metrics $w]]
    ::GX::uiFieldComponentCreate $p.measures.result status {wraplength 300} {} {}
    $p.measures.result configure -textvariable ::GX::CurveWorkbench::st($w,metricText)
    grid $p.measures.metricLabel -row 0 -column 0 -sticky w -padx 2 -pady 2
    grid $p.measures.metric -row 0 -column 1 -sticky ew -padx 2 -pady 2
    grid $p.measures.expectedLabel -row 1 -column 0 -sticky w -padx 2 -pady 2
    grid $p.measures.expected -row 1 -column 1 -sticky ew -padx 2 -pady 2
    grid $p.measures.evaluate -row 2 -column 0 -columnspan 2 -sticky ew -pady 3
    grid $p.measures.result -row 3 -column 0 -columnspan 2 -sticky ew -pady 3
    grid columnconfigure $p.measures 1 -weight 1
    $w.toolbar.view.menu add command -label {Compare / residuals} -command [list ::GX::CurveWorkbench::_comparisonPanelOpen $w]
}
proc ::GX::CurveWorkbench::_buildComparisonActivation {w} {_comparisonRefresh $w}

proc ::GX::CurveWorkbench::_comparisonRepresentation {w reference target} {
    set result {}
    foreach id [list $reference $target] {
        set record [_record $w $id]
        dict set result $id [dict create representation [dict get $record representation] evaluation [expr {[dict get $record representation] eq "spline" ? "spline_16_subdivisions_per_span" : "native_vertices"}]]
    }
    return $result
}
