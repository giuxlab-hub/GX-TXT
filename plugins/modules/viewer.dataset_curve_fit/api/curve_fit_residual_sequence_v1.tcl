# SPDX-License-Identifier: GPL-3.0-or-later
# Retained resource adapter and presentation; all scientific meaning comes from CORE.
proc ::GX::DatasetCurveFit::resultResidualSequence {reference options} {
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    foreach key [dict keys $options] {if {$key ni {order max_lag nonfinite}} {error "Unknown residual sequence option '$key'"}}
    if {![dict exists $options order]||[dict get $options order] ni {retained source_rows predictor predicted}} {error {Declare order=retained, source_rows, predictor or predicted explicitly}}
    if {[dict get $options order] eq "predicted"&&[dict get $p model] eq "implicit"} {error {Implicit equation residuals require retained rows or an observed coordinate order, not a predicted response}}
    set order [dict get $options order];set n [dict get $p source_n]
    if {$n<2||$n>1000000} {error {Residual sequence diagnostics require 2..1000000 retained rows}}
    # Reuse the public page boundary's exact resource/column identity checks.
    resultResidualPage $reference 0 1
    set columns [split [dict get $p residual_columns] ,];set width [llength $columns]
    set predictor 1
    if {[dict get $p parametric]||[dict get $p orientation] eq "r_of_theta"} {set predictor 6} elseif {[dict get $p orientation] eq "x_of_y"} {set predictor 2}
    if {$order eq "predicted"&&[dict get $p parametric]} {error {Geometric fits have no single predicted response; choose their parameter or retained row order}}
    if {$order eq "predictor"&&$predictor>$width} {error {This retained model has no explicit predictor/parameter residual column}}
    set lag [expr {min(10,$n-1)}];if {[dict exists $options max_lag]} {set lag [dict get $options max_lag]}
    if {![string is entier -strict $lag]||$lag<1||$lag>min(64,$n-1)} {error {max_lag must be an integer from 1 to min(64,N-1)}}
    set policy error;if {[dict exists $options nonfinite]} {set policy [dict get $options nonfinite]}
    if {$policy ni {error omit}} {error {Declare nonfinite=error or explicit omit}}
    set source [dict get $p statistical_results evaluation];::GX::StatisticsV1::validate $source
    set context [dict create residual_unit [dict get $source residual unit] coordinate_space [dict get $source residual coordinate_space] population fitted_residuals order_label [dict get {retained {retained evaluation row order} source_rows {ascending exact canonical source row} predictor {ascending retained predictor or geometric parameter} predicted {ascending predicted response}} $order] residual_convention [dict get $source residual definition] source_sha256 [dict get $p source_sha256]]
    if {[dict get $p model] eq "complex_response"} {
        dict set context residual_unit [dict get $p complex_binding source_identity source_axes y unit]
        dict set context coordinate_space original_physical
        dict set context residual_convention "display projection [dict get $p options complex_data display projection]: observed minus predicted; joint Cartesian covariance objective is separate"
    }
    set fields [dict create order [::GX::ScientificTransportv1::text $order] nonfinite [::GX::ScientificTransportv1::text $policy] max_lag [::GX::ScientificTransportv1::array {1 1} [list $lag]] predictor_column [::GX::ScientificTransportv1::array {1 1} [list $predictor]]]
    set residuals [::GX::ScientificTransportv1::resourceArray [dict get $p residual_resource] [list $width $n]]
    set rows [::GX::ScientificTransportv1::resourceArray [dict get $p source_rows_resource] [list $n 1] uint64]
    return [::GX::ScientificTransportv1::withCapturedColumns viewer.dataset_curve_fit dataset_curve_fit_residual_sequence_v1 residual_sequence describe $residuals $rows [::GX::ScientificTransportv1::empty] [::GX::ScientificTransportv1::struct $fields] {lags lag_pair_count autocorrelation} [list ::GX::DatasetCurveFit::_sequenceCaptured $reference $context]]
}
proc ::GX::DatasetCurveFit::_sequenceCaptured {reference context transported path} {
    _recipeResultRecord $reference
    set raw [dict get $transported values sample];set capture [dict get $transported values capture]
    set names [dict get $capture fields]
    if {$names ne {}} {
        set n [dict get $capture row_count]
        if {$names ne {lags lag_pair_count autocorrelation}||$n<1||$n>64||![file isfile $path]||[file size $path]!=24*$n} {error {Captured residual sequence vectors have invalid identities or lengths}}
        set channel [::open $path rb];try {set bytes [read $channel]} finally {::close $channel}
        binary scan $bytes q* values;set offset 0
        foreach name $names {dict set raw $name [lrange $values $offset [expr {$offset+$n-1}]];incr offset $n}
    }
    return [::GX::StatisticsV1::residualSequenceInterpretation $raw $context]
}
proc ::GX::DatasetCurveFit::_sequenceDetails {w} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted fit for residual sequence diagnostics}}
    set record [lindex $state($w,records) [lindex $selected 0]];_saveState $w
    set state($w,sequenceReference) [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set state($w,sequenceOrder) retained;set state($w,sequenceLag) [expr {min(10,[dict get $record provenance source_n]-1)}];set state($w,sequenceNonfinite) error
    set d $w.sequenceDetails;if {[winfo exists $d]} {destroy $d}
    toplevel $d;wm title $d {Residual sequence diagnostics};wm transient $d $w
    ttk::frame $d.controls;pack $d.controls -side top -fill x -padx 8 -pady 8
    foreach {id label values} {sequenceOrder Order {retained source_rows predictor predicted} sequenceLag {Maximum lag} {} sequenceNonfinite {Nonfinite pairs} {error omit}} {
        ttk::label $d.controls.${id}Label -text $label;pack $d.controls.${id}Label -side left -padx 4
        if {$values ne {}} {ttk::combobox $d.controls.$id -state readonly -values $values -textvariable ::GX::DatasetCurveFit::state($w,$id) -width 13} else {ttk::spinbox $d.controls.$id -from 1 -to 64 -textvariable ::GX::DatasetCurveFit::state($w,$id) -width 4}
        pack $d.controls.$id -side left -padx 4
    }
    ttk::button $d.controls.calculate -text {Describe retained residuals} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_sequenceRefresh $w]];pack $d.controls.calculate -side right
    ttk::scrollbar $d.scroll -command [list $d.report yview];pack $d.scroll -side right -fill y
    text $d.report -wrap word -width 100 -height 27 -yscrollcommand [list $d.scroll set];pack $d.report -fill both -expand 1
    $d.report insert end {Choose the order explicitly, then describe the retained residuals. No fit is repeated. Omitting nonfinite pairs joins surviving rows. These descriptive statistics do not establish independence or authorize removing observations.}
    $d.report configure -state disabled;wm geometry $d 1000x650;bind $d <Escape> [list destroy $d]
}
proc ::GX::DatasetCurveFit::_sequenceRefresh {w} {
    variable state
    set result [resultResidualSequence $state($w,sequenceReference) [dict create order $state($w,sequenceOrder) max_lag $state($w,sequenceLag) nonfinite $state($w,sequenceNonfinite)]]
    set state($w,sequenceResult) $result
    set text $w.sequenceDetails.report;$text configure -state normal;$text delete 1.0 end;$text insert end [::GX::StatisticsV1::report $result];$text configure -state disabled
    return $result
}
