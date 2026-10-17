# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter consumes captured Numeric scores and public CORE comparison policy.
proc ::GX::DatasetCurveFit::_validateModelSelection {result} {
    if {![dict exists $result model_selection]} {
        if {[dict exists $result observation_binding]||[dict exists $result comparison_rows_resource]} {error {Comparison evidence is incomplete}}
        return legacy_unverified
    }
    set binding [dict get $result observation_binding]
    set training [dict get $result statistical_results training]
    set expected [::GX::StatisticsV1::modelSelectionPlan $training $binding]
    if {$expected ne [dict get $result model_selection plan]} {error {Captured comparison plan differs from CORE interpretation}}
    set entry [dict create id captured_fit result $training binding $binding]
    if {[dict get $expected status] eq "value"} {
        dict set entry numeric [dict get $result model_selection numeric]
    } elseif {[dict exists $result model_selection numeric]} {error {Ineligible fit has unexpected information criteria}}
    ::GX::StatisticsV1::modelComparison [list $entry] aic
    if {[dict exists $result comparison_rows_resource]} {
        set resource [::GX::interactiveDocumentResourceInfo [dict get $result comparison_rows_resource]]
        set n [dict get $training quantities n value]
        if {[dict exists $training context complex]} {set n [dict get $training context complex observation_rows]}
        if {[dict get $resource sha256] ne [dict get $binding rows_sha256]||[dict get $resource metadata format] ne "uint64_le"||[dict get $resource size_bytes]!=8*$n||[dict get $resource metadata row_count]!=$n} {error {Comparison training-row identity changed}}
    }
    return validated
}
proc ::GX::DatasetCurveFit::compareFits {key fitIds {criterion aicc}} {
    variable state
    _assertSession $key
    if {[llength $fitIds]<2||[llength $fitIds]>64} {error {Choose two to 64 accepted fits}}
    set entries {}
    foreach id $fitIds {
        set record [lindex $state($key,records) [_recordIndex $key $id]]
        _validateAcceptedStatistics $record
        set result [dict get $record provenance]
        if {![dict exists $result model_selection]} {error "[dict get $record label] has no captured comparison evidence; rerun it explicitly"}
        set entry [dict create id [dict get $record fit_curve_id] result [dict get $result statistical_results training] binding [dict get $result observation_binding]]
        if {[dict exists $result model_selection numeric]} {dict set entry numeric [dict get $result model_selection numeric]}
        lappend entries $entry
    }
    return [::GX::StatisticsV1::modelComparison $entries $criterion]
}
proc ::GX::DatasetCurveFit::resultNestedF {reducedReference fullReference} {
    set entries {}
    foreach reference [list $reducedReference $fullReference] {
        set record [_recipeResultRecord $reference];set p [dict get $record provenance]
        if {![dict exists $p observation_binding]} {error {This accepted fit lacks original observation identity; explicitly preview and accept it again before comparison}}
        lappend entries [dict create id "[dict get $reference document_id].[dict get $reference fit_curve_id]" result [dict get $p statistical_results training] binding [dict get $p observation_binding]]
    }
    lassign $entries reduced full
    set plan [::GX::StatisticsV1::nestedFPlan $reduced $full];set numeric {}
    if {[dict get $plan status] eq "value"} {
        ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
        set numeric [::GX::NumericAPIv1::nestedFTest $plan]
    }
    return [::GX::StatisticsV1::nestedFInterpretation $reduced $full $numeric]
}
proc ::GX::DatasetCurveFit::_comparisonWindow {w} {
    variable state
    set d $w.modelComparison
    if {[winfo exists $d]} {raise $d;return}
    toplevel $d;wm title $d {Compare accepted models};wm transient $d $w
    ttk::label $d.help -text {Select accepted fits from the same training observations. Lower scores rank only the selected candidates; accepting a model remains an explicit action.} -wraplength 790
    pack $d.help -fill x -padx 12 -pady 10
    frame $d.candidates
    listbox $d.candidates.list -selectmode extended -exportselection 0 -height 6 -yscrollcommand [list $d.candidates.scroll set]
    ttk::scrollbar $d.candidates.scroll -orient vertical -command [list $d.candidates.list yview]
    pack $d.candidates.scroll -side right -fill y;pack $d.candidates.list -fill both -expand 1
    pack $d.candidates -fill x -padx 12
    set state($w,comparisonIds) {};set index 0
    foreach record $state($w,records) {
        lappend state($w,comparisonIds) [dict get $record fit_curve_id]
        $d.candidates.list insert end "[dict get $record fit_curve_id]: [dict get $record label]"
        if {[dict get $record source_curve_id] eq $state($w,activeSource)} {$d.candidates.list selection set $index}
        incr index
    }
    ttk::frame $d.actions
    ttk::label $d.actions.label -text Criterion
    set state($w,comparisonCriterion) aicc
    ttk::combobox $d.actions.criterion -textvariable ::GX::DatasetCurveFit::state($w,comparisonCriterion) -values {rmse aic aicc bic} -state readonly -width 8
    ttk::button $d.actions.compare -text Compare -command [list ::GX::DatasetCurveFit::_comparisonRefresh $w]
    ttk::button $d.actions.nested -text {Nested F (first → second)} -command [list ::GX::DatasetCurveFit::_comparisonNestedF $w]
    ttk::button $d.actions.close -text Close -command [list destroy $d]
    pack $d.actions.label $d.actions.criterion $d.actions.compare $d.actions.nested -side left -padx 4
    pack $d.actions.close -side right;pack $d.actions -fill x -padx 8 -pady 8
    ttk::treeview $d.results -columns {fit n p value status reason} -show headings -height 8
    foreach {column title width} {fit Fit 100 n N 65 p {Free p} 65 value Score 125 status Status 90 reason Reason 340} {
        $d.results heading $column -text $title;$d.results column $column -width $width -minwidth 40 -stretch [expr {$column eq "reason"}]
    }
    pack $d.results -fill both -expand 1 -padx 12
    set state($w,comparisonStatus) {};set state($w,comparisonResult) {}
    ttk::label $d.status -textvariable ::GX::DatasetCurveFit::state($w,comparisonStatus) -wraplength 790
    pack $d.status -fill x -padx 12 -pady 10
    wm minsize $d 760 430
    _comparisonRefresh $w
}
proc ::GX::DatasetCurveFit::_comparisonNestedF {w} {
    variable state
    set d $w.modelComparison;set indices [$d.candidates.list curselection]
    $d.results delete [$d.results children {}];set state($w,comparisonResult) {}
    if {[llength $indices]!=2} {set state($w,comparisonStatus) {Select exactly two fits in list order: reduced model first, full model second. The full polynomial must have more coefficients.};return}
    try {
        _assertSession $w
        set references {};foreach index $indices {lappend references [resultReference $state($w,documentId) [lindex $state($w,comparisonIds) $index]]}
        set result [resultNestedF {*}$references]
        set state($w,comparisonResult) $result
        set state($w,comparisonStatus) [::GX::StatisticsV1::report $result]
    } on error {message options} {set state($w,comparisonStatus) $message}
}
proc ::GX::DatasetCurveFit::_comparisonRefresh {w} {
    variable state
    set d $w.modelComparison;set ids {}
    foreach index [$d.candidates.list curselection] {lappend ids [lindex $state($w,comparisonIds) $index]}
    $d.results delete [$d.results children {}];set state($w,comparisonResult) {}
    if {[catch {set result [compareFits $w $ids $state($w,comparisonCriterion)]} message]} {set state($w,comparisonStatus) $message;return}
    set state($w,comparisonResult) $result
    set title [string toupper [dict get $result criterion]]
    if {[dict get $result criterion] eq "rmse"} {append title " ([dict get [lindex [dict get $result rows] 0] unit])"}
    $d.results heading value -text $title
    foreach row [dict get $result rows] {
        set score [dict get $row value]
        if {$score ne {}} {set score [format %.10g $score]}
        set status [dict get $row status];if {$status eq "value"} {set status available}
        $d.results insert {} end -id [dict get $row id] -values [list [dict get $row id] [dict get $row n] [dict get $row free_parameter_count] $score [string totitle $status] [dict get $row reason]]
    }
    if {[dict get $result status] eq "value"} {
        set state($w,comparisonStatus) "Order: [join [dict get $result ranked_ids] {, }]. [join [dict get $result assumptions] \n]"
    } else {set state($w,comparisonStatus) "No comparable ranking. [join [dict get $result reasons] \n]"}
}
