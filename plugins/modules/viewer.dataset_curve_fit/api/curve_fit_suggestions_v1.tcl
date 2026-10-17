# Read-only source/model advice through the existing exact input worker and
# public Numeric/CORE authorities. No Workspace or accepted result is created.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_suggestionOptions {options} {
    foreach key [dict keys $options] {if {$key ni {orientation point_mask thresholds criterion}} {error "Unknown source-suggestion option: $key"}}
    set options [dict merge {orientation y_of_x point_mask {} thresholds {} criterion aicc} $options]
    if {[dict get $options orientation] ni {y_of_x x_of_y}} {error {Source suggestions require Y=f(X) or X=f(Y) orientation}}
    if {[dict get $options criterion] ni {aic aicc}} {error {Choose AIC or AICc for retained fitted candidates}}
    ::GX::curveSourcePointMaskValidate [dict get $options point_mask]
    return $options
}
proc ::GX::DatasetCurveFit::_suggestionInput {scene host options input} {
    set selected [expr {[dict get $options point_mask] ne {}}]
    set training [expr {$selected?[dict get $input training]:$input}]
    if {[dict get $training row_count]>1000000} {error {Source suggestions support at most 1000000 exact finite observations; choose an explicit smaller population}}
    set workerOptions [dict create characteristics_only 1 characteristic_thresholds [dict get $options thresholds] orientation [dict get $options orientation]]
    set result [_runNumeric linear 1 {} $training $input source $workerOptions $scene {} $host]
    if {[dict get $result numeric observation_count]!=[dict get $training row_count]} {error {Characterization lost the exact finite source population}}
    dict set result preprocessing [dict get $input preprocessing]
    return $result
}
proc ::GX::DatasetCurveFit::_suggestionFinish {captured axes sourceId sourceReceipt options references} {
    if {[llength $references]>64} {error {At most 64 retained candidates may be compared}}
    set context [dict create x_unit [dict get $axes x unit] y_unit [dict get $axes y unit]]
    if {[dict get $options orientation] eq "x_of_y"} {set context [dict create x_unit [dict get $axes y unit] y_unit [dict get $axes x unit]]}
    dict set context orientation [dict get $options orientation]
    foreach axis {x y} {dict set context ${axis}_variable_id [dict get $axes $axis variable_id]}
    if {[dict exists $captured binding]} {dict set context observation_binding [dict merge [dict get $captured binding] [dict create source_id $sourceId]]}
    set candidates {};foreach card [modelCards] {lappend candidates [dict create id [dict get $card model_id] model_id [dict get $card statistics_model_id] label [dict get $card label]]}
    set entries {}
    foreach ref $references {
        set p [dict get [_recipeResultRecord $ref] provenance]
        if {![dict exists $p observation_binding]} {error {An explicit retained candidate lacks observation identity; compare a verified result instead}}
        set entry [dict create id "[dict get $ref document_id].[dict get $ref fit_curve_id]" result [dict get $p statistical_results training] binding [dict get $p observation_binding]]
        if {[dict exists $p model_selection numeric]} {dict set entry numeric [dict get $p model_selection numeric]}
        lappend entries $entry
    }
    set result [::GX::StatisticsV1::fitSuggestions [dict get $captured numeric] $candidates $context $entries [dict get $options criterion]]
    set receipt [dict create source $sourceReceipt options $options preprocessing [::GX::datasetPublicationV2DictDefault $captured preprocessing {}]]
    return [dict create schema gxtxt.fitter_model_suggestions.v1 interpretation $result report [::GX::StatisticsV1::fitSuggestionsReport $result] source_receipt_utf8 $receipt]
}
proc ::GX::DatasetCurveFit::datasetSuggestions {sourceRequest {options {}} {references {}}} {
    set options [_suggestionOptions $options]
    set token {};set scene {}
    try {
        set token [::GX::curveSourceOpen $::GX::currentSession $sourceRequest]
        set descriptor [::GX::curveSourceDescribe $token];::GX::native2DEnsure;set scene [::GX::Native2D::core scene]
        set captured [::GX::curveSourceWithNumericInput $token [list ::GX::DatasetCurveFit::_suggestionInput $scene {} $options] [dict get $options point_mask]]
        set axes {};foreach axis {x y} {
            set id [dict get $sourceRequest ${axis}_variable_id]
            foreach variable [dict get $descriptor variables] {if {[dict get $variable variable_id] eq $id} {dict set axes $axis $variable;break}}
            if {![dict exists $axes $axis]} {error {Canonical source descriptor lost a selected variable}}
        }
        ::GX::curveSourceDescribe $token
        return [_suggestionFinish $captured $axes "dataset:[dict get $sourceRequest dataset_id]" $descriptor $options $references]
    } finally {if {$scene ne {}} {::GX::Native2D::core destroy $scene};if {$token ne {}} {::GX::curveSourceClose $token}}
}
proc ::GX::DatasetCurveFit::sourceSuggestions {key {scope all} {options {}} {references {}}} {
    variable state
    _assertLoaded $key
    if {$scope ni {all selected}} {error {Choose all or selected exact source points}}
    set options [_suggestionOptions [dict merge [dict create orientation $state($key,orientation)] $options]]
    if {[dict get $options point_mask] ne {}} {error {A live Fitter source uses its own explicit point selection}}
    if {$scope eq "selected"} {dict set options point_mask [_selectionDescriptor $key]}
    set source [_sourceProvenance $key];set snapshot [list $state($key,activeSource) $state($key,loadedBinding) [_selectionDescriptor $key]]
    set host [expr {[info exists state($key,loading)]&&$state($key,loading)?$key:{}}]
    if {$state($key,sourceToken) ne {}} {
        set progress [expr {$host ne {}?[list ::GX::DatasetCurveFit::_suggestionProgress $host]:{}}]
        set captured [::GX::curveSourceWithNumericInput $state($key,sourceToken) [list ::GX::DatasetCurveFit::_suggestionInput $state($key,scene) $host $options] [dict get $options point_mask] $progress]
    } else {
        set points [sourcePoints $key];set training $points;set rows $state($key,rows)
        if {$scope eq "selected"} {set training [::GX::Native2D::core export $state($key,selectionScene) $state($key,selectionObject)];set rows [lmap index [selectedIndices $key] {lindex $state($key,rows) $index}]}
        if {[llength $training]<2||[llength $training]>1000000} {error {Source suggestions require 2 to 1000000 exact finite points}}
        set workerOptions [dict create characteristics_only 1 characteristic_thresholds [dict get $options thresholds] orientation [dict get $options orientation] comparison_row_ids $rows]
        set captured [_runNumeric linear 1 {} $training $points source $workerOptions {} {} $host]
    }
    _assertLoaded $key
    if {[list $state($key,activeSource) $state($key,loadedBinding) [_selectionDescriptor $key]] ne $snapshot} {error {Source or selection changed during characterization; inspect the current source again}}
    set sourceId [::GX::datasetPublicationV2DictDefault $source source_dataset_id [::GX::datasetPublicationV2DictDefault $source source_sample_id {}]]
    return [_suggestionFinish $captured [dict get $source source_axes] "[dict get $source source_kind]:$sourceId" $source $options $references]
}
proc ::GX::DatasetCurveFit::_suggestionProgress {w progress} {
    variable state
    if {[dict exists $progress run_id]} {
        if {$state($w,sourceCancelled)} {::GX::parallelExecutionCancel [dict get $progress run_id]}
        set state($w,status) "Inspecting source: [dict get $progress message]. Escape cancels."
    } else {
        if {$state($w,sourceCancelled)} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} {Source inspection cancelled}}
        set state($w,status) "Reading exact source: [dict get $progress completed_rows] / [dict get $progress total_rows] rows. Escape cancels."
    }
}
proc ::GX::DatasetCurveFit::_suggestionOpen {w} {
    variable state
    _assertLoaded $w
    set d $w.modelSuggestions;catch {destroy $d};toplevel $d;wm title $d {Model suggestions};wm transient $d $w
    set state($w,suggestionScope) $state($w,scope);set state($w,suggestionCriterion) aicc;set state($w,suggestionResult) {};set state($w,suggestionClose) 0;set state($w,suggestionRunning) 0
    ttk::label $d.note -text {Inspect exact finite source points for advisory model ideas. Select optional retained fits below for AIC/AICc ranking. No model is fitted, selected or accepted automatically.} -wraplength 820
    pack $d.note -fill x -padx 8 -pady 8
    ttk::frame $d.options;pack $d.options -fill x
    ttk::label $d.options.scopeLabel -text {Source points};ttk::combobox $d.options.scope -state readonly -values {all selected} -textvariable ::GX::DatasetCurveFit::state($w,suggestionScope) -width 12
    ttk::label $d.options.criterionLabel -text {Retained-fit criterion};ttk::combobox $d.options.criterion -state readonly -values {aic aicc} -textvariable ::GX::DatasetCurveFit::state($w,suggestionCriterion) -width 8
    pack $d.options.scopeLabel $d.options.scope $d.options.criterionLabel $d.options.criterion -side left -padx 8
    listbox $d.candidates -height 5 -selectmode extended -exportselection 0;pack $d.candidates -fill x -padx 8 -pady 6
    set state($w,suggestionReferences) {}
    foreach record $state($w,records) {
        lappend state($w,suggestionReferences) [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
        $d.candidates insert end "[dict get $record fit_curve_id]: [dict get $record label]"
    }
    ttk::frame $d.actions;pack $d.actions -fill x
    ttk::button $d.actions.inspect -text {Inspect source and compare selected fits} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_suggestionRefresh $w]]
    ttk::button $d.actions.cancel -text Cancel -state disabled -command [list ::GX::DatasetCurveFit::_sourceCancel $w]
    ttk::button $d.actions.close -text Close -command [list ::GX::DatasetCurveFit::_suggestionClose $w]
    pack $d.actions.inspect $d.actions.cancel $d.actions.close -side left -padx 8 -pady 6
    ttk::frame $d.output;pack $d.output -fill both -expand 1
    text $d.output.text -height 26 -width 104 -wrap word -state disabled -yscrollcommand [list $d.output.scroll set]
    ttk::scrollbar $d.output.scroll -command [list $d.output.text yview];pack $d.output.scroll -side right -fill y;pack $d.output.text -fill both -expand 1
    bind $d <Escape> [list ::GX::DatasetCurveFit::_suggestionClose $w];wm protocol $d WM_DELETE_WINDOW [list ::GX::DatasetCurveFit::_suggestionClose $w]
}
proc ::GX::DatasetCurveFit::_suggestionClose {w} {
    variable state
    if {[info exists state($w,suggestionRunning)]&&$state($w,suggestionRunning)&&[info exists state($w,loading)]&&$state($w,loading)} {set state($w,suggestionClose) 1;_sourceCancel $w;return}
    destroy $w.modelSuggestions
}
proc ::GX::DatasetCurveFit::_suggestionRefresh {w} {
    variable state
    set d $w.modelSuggestions;set references {}
    foreach index [$d.candidates curselection] {lappend references [lindex $state($w,suggestionReferences) $index]}
    set state($w,suggestionResult) {};set controls [_operationBegin $w];set state($w,suggestionRunning) 1;$d.actions.cancel configure -state normal
    try {
        set result [sourceSuggestions $w $state($w,suggestionScope) [dict create criterion $state($w,suggestionCriterion)] $references]
        set state($w,suggestionResult) $result
        $d.output.text configure -state normal;$d.output.text delete 1.0 end;$d.output.text insert end [dict get $result report];$d.output.text configure -state disabled
        set state($w,status) {Source advice is ready. Review model assumptions and choose any subsequent fit explicitly.}
    } finally {
        set state($w,suggestionRunning) 0
        _operationEnd $w $controls
        if {[winfo exists $d.actions.cancel]} {$d.actions.cancel configure -state disabled}
        if {$state($w,suggestionClose)&&[winfo exists $d]} {destroy $d}
    }
}
