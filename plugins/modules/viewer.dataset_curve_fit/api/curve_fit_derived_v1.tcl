# Fitter adapts retained parameter identities to the public CORE/Numeric owners.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::derivedDefinitions {reference} {
    set p [dict get [_recipeResultRecord $reference] provenance]
    set source [dict get $p statistical_results training]
    set context [dict get $source context];set definitions {};set aliases {};set index 0;set lookup {}
    foreach parameter [dict get $source parameters] {
        dict set lookup [dict get $parameter id] p$index
        lappend aliases [dict merge $parameter [dict create alias p$index]];incr index
    }
    set orientation [::GX::datasetPublicationV2DictDefault $context orientation y_of_x]
    set u [dict get $p translation u];set v [dict get $p translation v]
    set du [dict create id du value [dict get $u delta] unit [dict get $u unit]]
    set dv [dict create id dv value [dict get $v delta] unit [dict get $v unit]]
    set unit [dict get $u unit]
    if {[dict get $p model] eq "linear"&&$orientation in {y_of_x x_of_y}&&[dict exists $lookup intercept]&&[dict exists $lookup slope]} {
        set target [dict create id target value 0 unit [dict get $v unit]]
        lappend definitions [dict create id threshold label {Threshold at target response} expression "(target+dv-[dict get $lookup intercept])/[dict get $lookup slope]-du" unit $unit constants [list $target $du $dv]]
    }
    if {[dict get $p model] eq "exponential"&&$orientation in {y_of_x x_of_y}&&[dict exists $lookup rate]} {
        lappend definitions [dict create id characteristic_interval label {Characteristic e-folding interval} expression "1/abs([dict get $lookup rate])" unit $unit constants {}]
    }
    if {[dict exists $p numeric_model_state regional_composition recipe breakpoints]} {
        foreach bp [dict get $p numeric_model_state regional_composition recipe breakpoints] {
            set id [dict get $bp id]
            if {[dict exists $lookup $id]} {lappend definitions [dict create id knee_[llength $definitions] label "Knee: $id" expression "[dict get $lookup $id]-du" unit $unit constants [list $du]]}
        }
    }
    return [dict create schema gxtxt.fitter_derived_definitions.v1 parameters $aliases definitions $definitions coefficient_space [::GX::datasetPublicationV2DictDefault $context coefficient_space original_physical]]
}
proc ::GX::DatasetCurveFit::resultDerived {reference definitions} {
    set source [dict get [_recipeResultRecord $reference] provenance statistical_results training]
    set plan [::GX::StatisticsV1::derivedPropertiesPlan $source $definitions]
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set numeric [::GX::NumericAPIv1::derivedProperties $plan]
    set meaning [::GX::StatisticsV1::derivedPropertiesInterpretation $source $numeric]
    _recipeResultRecord $reference
    set receipt [dict create schema gxtxt.fitter_derived_receipt.v1 reference $reference numeric $numeric]
    return [dict create schema gxtxt.fitter_derived_result.v1 interpretation $meaning report [::GX::StatisticsV1::derivedPropertiesReport $source $numeric] receipt_utf8 [encoding convertto utf-8 $receipt]]
}
proc ::GX::DatasetCurveFit::resultDerivedPublishText {text datasetId} {
    # The Script host transports Unicode text, not Python bytes repr. Encode
    # only after entering Tcl, before the existing opaque UTF-8 receipt reader.
    return [resultDerivedPublish [encoding convertto utf-8 $text] $datasetId]
}
proc ::GX::DatasetCurveFit::resultDerivedPublish {encoded datasetId} {
    variable version
    ::GX::datasetPublicationV2ValidateId dataset $datasetId
    if {[string length $encoded]>16777216} {error {Derived receipt exceeds16 MiB}}
    set receipt [encoding convertfrom utf-8 $encoded]
    if {[dict get $receipt schema] ne "gxtxt.fitter_derived_receipt.v1"} {error {Invalid derived property receipt}}
    set reference [dict get $receipt reference];set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    set source [dict get $p statistical_results training];set numeric [dict get $receipt numeric]
    set meaning [::GX::StatisticsV1::derivedPropertiesInterpretation $source $numeric]
    set report [::GX::StatisticsV1::derivedPropertiesReport $source $numeric]
    set definitions {};set columns {}
    foreach row [dict get $meaning properties] {
        set id [dict get $row id];set label [dict get $row label];set unit [dict get $row unit]
        foreach field {value standard_uncertainty} suffix {value uncertainty} {
            if {[dict get $row ${field}_status] ne "value"} continue
            set column ${id}_$suffix
            dict set definitions $column [dict create display_label "$label — $suffix" dtype float64 unit $unit]
            dict set columns $column [list [dict get $row $field]]
        }
    }
    if {![dict size $columns]} {error {No finite derived values are available to publish}}
    # A top-level CORE API record participates in canonical publication and
    # metadata replacement validation; auxiliary text never owns the meaning.
    set metadata [dict create derived_properties $meaning derived_properties.source_reference $reference derived_properties.report_lines [split $report \n]]
    set definition [dict create dataset_id $datasetId contract table.generic storage hdf5 replace_owned 0 display_name $datasetId structured_metadata $metadata provenance [dict create producer viewer.dataset_curve_fit producer_version $version operation derived_properties]]
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession viewer.dataset_curve_fit $definition];set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        dict for {id spec} $definitions {::GX::datasetPublicationV2DeclareVariable $writer $id [dict merge $spec {rank 1 dimension_ids row coordinate_role data axis_kind explicit}]}
        ::GX::datasetPublicationV2Append $writer row $columns
        set result [::GX::datasetPublicationV2Finalize $writer];set writer {};return $result
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
}
proc ::GX::DatasetCurveFit::_derivedOpen {w} {
    variable state
    set selection [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selection]!=1} {error {Select one accepted fit}}
    set record [lindex $state($w,records) [lindex $selection 0]]
    set state($w,derivedReference) [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set data [derivedDefinitions $state($w,derivedReference)]
    set definitions [dict get $data definitions]
    lappend definitions [dict create id custom label {Custom parameter expression} expression {} unit 1 constants {}]
    set state($w,derivedDefinitions) $definitions;set state($w,derivedChoice) [dict get [lindex $definitions 0] label]
    set state($w,derivedDataset) fit_derived;set state($w,derivedResult) {}
    set d $w.derived;if {[winfo exists $d]} {destroy $d};toplevel $d;wm title $d {Derived physical properties};wm transient $d $w
    ttk::combobox $d.choice -state readonly -values [lmap item $definitions {dict get $item label}] -textvariable ::GX::DatasetCurveFit::state($w,derivedChoice)
    grid $d.choice -row 0 -column 0 -columnspan 2 -sticky ew
    bind $d.choice <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_derivedSelect $w]
    set row 1
    foreach field {Expression Unit Target Dataset} label {{Parameter expression} {Output unit} {Target response (threshold only)} {New Dataset ID}} {
        ttk::label $d.l$field -text $label;ttk::entry $d.e$field -textvariable ::GX::DatasetCurveFit::state($w,derived$field)
        grid $d.l$field -row $row -column 0 -sticky w;grid $d.e$field -row $row -column 1 -sticky ew;incr row
    }
    set aliases "Coefficient space: [dict get $data coefficient_space]\n"
    foreach parameter [dict get $data parameters] {append aliases "[dict get $parameter alias] = [dict get $parameter id] ([dict get $parameter unit]), [dict get $parameter role]\n"}
    ttk::label $d.aliases -text $aliases -wraplength 760;grid $d.aliases -row 5 -column 0 -columnspan 2 -sticky w
    ttk::frame $d.actions;grid $d.actions -row 6 -column 0 -columnspan 2 -sticky ew
    ttk::button $d.actions.evaluate -text {Evaluate properties} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_derivedEvaluate $w]]
    ttk::button $d.actions.publish -text {Publish evaluated result} -state disabled -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_derivedPublish $w]]
    pack $d.actions.evaluate $d.actions.publish -side left -padx 4 -pady 4
    text $d.report -height 17 -width 95 -wrap word -state disabled -yscrollcommand [list $d.scroll set]
    ttk::scrollbar $d.scroll -command [list $d.report yview]
    grid $d.report -row 7 -column 0 -columnspan 2 -sticky nsew;grid $d.scroll -row 7 -column 2 -sticky ns
    grid columnconfigure $d 1 -weight 1;grid rowconfigure $d 7 -weight 1;wm geometry $d 900x690
    bind $d <Escape> [list destroy $d];_derivedSelect $w
}
proc ::GX::DatasetCurveFit::_derivedSelect {w} {
    variable state
    foreach item $state($w,derivedDefinitions) {if {[dict get $item label] eq $state($w,derivedChoice)} {set state($w,derivedDefinition) $item;break}}
    set state($w,derivedExpression) [dict get $state($w,derivedDefinition) expression];set state($w,derivedUnit) [dict get $state($w,derivedDefinition) unit];set state($w,derivedTarget) 0
    $w.derived.eTarget configure -state [expr {[dict get $state($w,derivedDefinition) id] eq "threshold"?"normal":"disabled"}]
}
proc ::GX::DatasetCurveFit::_derivedEvaluate {w} {
    variable state
    set item $state($w,derivedDefinition);dict set item expression $state($w,derivedExpression);dict set item unit $state($w,derivedUnit)
    set constants {}
    foreach c [dict get $item constants] {if {[dict get $c id] eq "target"} {dict set c value $state($w,derivedTarget)};lappend constants $c}
    dict set item constants $constants
    set result [resultDerived $state($w,derivedReference) [list $item]];set state($w,derivedResult) $result
    $w.derived.report configure -state normal;$w.derived.report delete 1.0 end;$w.derived.report insert end [dict get $result report];$w.derived.report configure -state disabled
    $w.derived.actions.publish configure -state normal
    return $result
}
proc ::GX::DatasetCurveFit::_derivedPublish {w} {
    variable state
    if {$state($w,derivedResult) eq {}} {error {Evaluate a property first}}
    set result [resultDerivedPublish [dict get $state($w,derivedResult) receipt_utf8] $state($w,derivedDataset)]
    set state($w,status) "Published evaluated physical properties as [dict get $result dataset_id]."
    return $result
}
