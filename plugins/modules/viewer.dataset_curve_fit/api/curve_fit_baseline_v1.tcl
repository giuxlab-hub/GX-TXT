# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter selects bindings; Dataset Transform and Numeric own processing.
proc ::GX::DatasetCurveFit::_baselineContext {source} {
    if {![dict exists $source baseline_correction]} {return {}}
    set context [dict create schema gxtxt.baseline_context.v1]
    foreach key {method source_dataset_id source_sha256 original_y_variable_id baseline_variable_id corrected_variable_id uncertainty_policy} {dict set context $key [dict get $source baseline_correction $key]}
    return $context
}
proc ::GX::DatasetCurveFit::_baselineSettings {w} {
    variable state
    _assertLoaded $w
    if {$state($w,sourceKind) ne "dataset"||$state($w,sourceTransformManifest) ne {}} {error {Baseline correction requires a canonical Dataset curve; materialize an edited curve first}}
    set d $w.baseline
    if {[winfo exists $d]} {raise $d;return}
    set state($d,owner) $state($w,activeSource)
    foreach {key value} {method asls lambda 100000 p 0.01 max_iterations 50 tolerance 0.000001 grid_policy uniform_x nonfinite error degree 2 estimator median} {set state($d,$key) $value}
    set state($d,output) $state($w,dataset)_baseline
    toplevel $d;wm title $d {Baseline correction};wm transient $d $w;wm geometry $d 720x580;wm minsize $d 500 380
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x
    ttk::button $d.actions.apply -text {Create corrected Dataset} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_baselineApply $w $d]]
    ttk::button $d.actions.cancel -text Cancel -command [list destroy $d];pack $d.actions.cancel $d.actions.apply -side right -padx 4
    set body [::GX::scrollableDialogBody $d];set state($d,body) $body
    ttk::label $body.help -text {Creates a new Dataset with all original columns, a baseline, corrected Y and original row identities. Uses the active Dataset filters; graphical fit rectangles are not baseline masks. The corrected curve is added as a separate source. Peak models are fitted afterwards. Estimated baseline uncertainty and induced correlations are not propagated into peak-fit intervals.} -wraplength 620 -justify left
    grid $body.help -row 0 -column 0 -columnspan 2 -sticky ew -pady 8
    set row 1
    foreach {key label choices} {
        method Method {asls constant linear polynomial}
        lambda {AsLS smoothing lambda} {}
        p {AsLS asymmetry p (positive peaks: below 0.5)} {}
        max_iterations {AsLS maximum iterations} {}
        tolerance {AsLS relative weight tolerance} {}
        grid_policy {AsLS sampling grid} {uniform_x sample_index}
        nonfinite {Nonfinite pairs} {error omit}
        degree {Polynomial degree} {}
        estimator {Constant estimator} {mean median}
        output {New Dataset ID} {}
    } {
        ttk::label $body.label_$key -text $label
        if {$choices eq {}} {ttk::entry $body.$key -textvariable ::GX::DatasetCurveFit::state($d,$key)} else {ttk::combobox $body.$key -state readonly -values $choices -textvariable ::GX::DatasetCurveFit::state($d,$key)}
        grid $body.label_$key -row $row -column 0 -sticky w -padx 4 -pady 4;grid $body.$key -row $row -column 1 -sticky ew -padx 4;incr row
    }
    grid columnconfigure $body 1 -weight 1
}
proc ::GX::DatasetCurveFit::_baselineCancelled {w args} {variable state;return $state($w,sourceCancelled)}
proc ::GX::DatasetCurveFit::_baselineProgress {w progress} {
    variable state
    set state($w,status) {Creating separate baseline and corrected Dataset…}
}
proc ::GX::DatasetCurveFit::_baselineApply {w d} {
    variable state
    if {$state($d,owner) ne $state($w,activeSource)} {error {Active source changed; reopen baseline settings}}
    set options [dict create method $state($d,method) nonfinite $state($d,nonfinite)]
    switch $state($d,method) {
        asls {foreach key {lambda p max_iterations tolerance} {dict set options $key [_finite $state($d,$key) $key]};dict set options grid_policy $state($d,grid_policy)}
        polynomial {dict set options degree [_finite $state($d,degree) degree]}
        constant {dict set options estimator $state($d,estimator)}
    }
    set filters {};set mapping [dict create = exact_equal != not_equal < less_than <= less_equal > greater_than >= greater_equal contains contains LIKE like]
    foreach filter $state($w,filters) {
        set operator [dict get $filter operator];set item [dict create filter_variable_id [dict get $filter variable]]
        if {$operator eq "between"} {lassign [dict get $filter value] lower upper;dict set item predicate between_inclusive;dict set item lower $lower;dict set item upper $upper} else {dict set item predicate [dict get $mapping $operator];dict set item value [dict get $filter value]}
        lappend filters $item
    }
    set source [dict create dataset_id $state($w,dataset) row_filters $filters]
    set manifest [dict create api_version 1 operation baseline_correct sources [list $source] options [dict create x_variable_id $state($w,x) y_variable_id $state($w,y) baseline_options $options] output [dict create dataset_id $state($d,output) display_name "$state($w,dataset): baseline-corrected $state($w,y)"]]
    set x $state($w,x);set controls [_operationBegin $w];$d.actions.apply configure -state disabled
    try {
        set result [::GX::datasetTransformExecuteResponsive $::GX::currentSession $manifest [dict create progress_command [list ::GX::DatasetCurveFit::_baselineProgress $w] cancel_command [list ::GX::DatasetCurveFit::_baselineCancelled $w]]]
        set id [dict get $result dataset_id];loadSource $w $id $x corrected_y {}
        destroy $d
        set state($w,translationUMode) off;set state($w,translationVMode) off
        set state($w,status) "Created $id. Original spectrum, baseline and corrected Y remain separate; select a peak model and preview its fit."
    } finally {
        if {[winfo exists $d.actions.apply]} {$d.actions.apply configure -state normal}
        _operationEnd $w $controls
    }
    _refreshFits $w;_saveState $w;redraw $w
}
