# Exact-source parameter preparation and ephemeral manual display.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_parameterFingerprint {key} {
    variable state
    _assertLoaded $key
    set result [list [_sourceProvenance $key] [_selectionDescriptor $key] [_uiFitOptions $key]]
    foreach field {model scope degree initial domain min max samples} {lappend result $state($key,$field)}
    return $result
}
proc ::GX::DatasetCurveFit::_parameterClear {key} {
    variable state
    if {[info exists state($key,parameterAfter)]} {after cancel $state($key,parameterAfter)}
    if {[info exists state($key,parameterDirectory)]} {file delete -force -- $state($key,parameterDirectory)}
    foreach field {parameterAfter parameterDirectory parameterFingerprint parameterView manualPoints} {unset -nocomplain state($key,$field)}
}
proc ::GX::DatasetCurveFit::parameterPrepare {key} {
    variable state
    set fingerprint [_parameterFingerprint $key]
    if {[info exists state($key,parameterFingerprint)]&&$state($key,parameterFingerprint) eq $fingerprint} {return $state($key,parameterView)}
    _parameterClear $key
    set model $state($key,model)
    set geometric [expr {$model in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial}}]
    if {$model ni {linear polynomial exponential power_law gaussian components formula rational regions registered circular_arc quadratic_bezier cubic_bezier parametric_polynomial fourier}||$state($key,orientation) ni {y_of_x x_of_y r_of_theta parametric}} {error {Manual parameter controls require a supported finite parameter declaration}}
    if {$geometric != ($state($key,orientation) eq "parametric")} {error {Manual model geometry and orientation differ}}
    if {$geometric} {_geometricMetricUnit $key}
    if {$state($key,orientation) eq "r_of_theta"} {
        if {$model ni {linear polynomial exponential power_law gaussian}} {error {Radial manual controls require a built-in scalar model}}
        _geometricMetricUnit $key
    }
    set options [_uiFitOptions $key]
    # Preparation has no uncertainty/influence computation or accepted result.
    dict unset options bootstrap;dict unset options profile;dict set options influence_diagnostics 0;dict set options prediction_band none
    set initial {};foreach value [split $state($key,initial) ,] {if {[string trim $value] ne {}} {lappend initial [_finite [string trim $value] {Initial parameter}]}}
    if {$model eq "rational"} {set resolved [_prepareRational $key $options];set initial [dict get $resolved initial_parameters]}
    if {$model eq "formula"} {set resolved [_prepareFormula $key $options];set initial [dict get $resolved initial_parameters]}
    if {$model eq "components"} {set resolved [_prepareComponents $key $options];set initial [dict get $resolved initial_parameters]}
    if {$model eq "regions"} {set resolved [_prepareRegions $key $options];set initial [dict get $resolved initial_parameters]}
    set domain source
    if {$state($key,domain) eq "range"} {
        set lo [_finite $state($key,min) {Domain minimum}];set hi [_finite $state($key,max) {Domain maximum}];set n $state($key,samples)
        if {$hi<=$lo||![string is integer -strict $n]||$n<2||$n>10000} {error {Output domain needs increasing bounds and 2–10000 samples}}
        set domain [list $lo $hi $n]
        if {$geometric} {if {$lo<0||$hi>1} {error {Parameter output domain must lie in [0,1]}};set domain [linsert $domain 0 parameter]}
    }
    if {$model eq "registered"} {
        _parameterRegisteredCollect
        if {$initial eq {}} {set initial [dict get $state($key,registeredModel) definition initial]}
        set registered [_registeredFitValidate [_sourceProvenance $key] [dict create model registered initial $initial options $options]]
        dict set options registered_model $registered
    }
    set channel [file tempfile directory];::close $channel;file delete $directory;file mkdir $directory
    dict set options parameter_context [file join $directory context.ini]
    try {
        set scope $state($key,scope)
        if {$scope ni {all selected}} {error {Choose all or selected observations}}
        if {$state($key,sourceToken) ne {}} {
            set mask {};if {$scope eq "selected"} {set mask [_selectionDescriptor $key]}
            set companions [_measurementCompanions $key $model $options]
            set progress {};if {[info exists state($key,loading)]&&$state($key,loading)} {set progress [list ::GX::DatasetCurveFit::_stagingProgress $key]}
            set view [::GX::curveSourceWithNumericInput $state($key,sourceToken) [list ::GX::DatasetCurveFit::_numericSource $key $model $state($key,degree) $initial $scope {} $domain $options] $mask $progress {} $companions]
        } else {
            set source [sourcePoints $key];set training $source
            if {$scope eq "selected"} {set training {};foreach index [selectedIndices $key] {lappend training [lindex $source $index]}}
            set host {};if {[info exists state($key,loading)]&&$state($key,loading)} {set host $key}
            set view [_runNumeric $model $state($key,degree) $initial $training $source $domain $options {} {} $host]
        }
        if {$fingerprint ne [_parameterFingerprint $key]} {error {Source or fitting settings changed during parameter preparation}}
        set state($key,parameterDirectory) $directory;set state($key,parameterFingerprint) $fingerprint;set state($key,parameterView) $view
        return $view
    } on error {message details} {file delete -force -- $directory;return -options $details $message}
}
proc ::GX::DatasetCurveFit::parameterEvaluate {key parameters} {
    variable state;variable root
    if {![info exists state($key,parameterFingerprint)]||$state($key,parameterFingerprint) ne [_parameterFingerprint $key]} {_parameterClear $key;error {Source or settings changed; prepare parameters again}}
    set fingerprint $state($key,parameterFingerprint)
    if {[llength $parameters]!=[llength [dict get $state($key,parameterView) parameter_ids]]} {error {Supply exactly one value per declared parameter}}
    foreach value $parameters {_finite $value {Manual parameter}}
    if {$state($key,model) eq "registered"} {return [_parameterRegisteredEvaluate $key $parameters]}
    set directory $state($key,parameterDirectory);set channel [file tempfile valuesFile [file join $directory values-]];::close $channel;file delete $valuesFile
    set resultFile ${valuesFile}.result;set run {}
    try {
        ::GX::ScientificTransportv1::writeResult $valuesFile [dict create parameters [::GX::ScientificTransportv1::array [list [llength $parameters] 1] $parameters]]
        set environment [dict create GXDCF_PARAMETER_CONTEXT [file join $directory context.ini] GXDCF_PARAMETER_VALUES $valuesFile GXDCF_PARAMETER_RESULT $resultFile GXDCF_NUMERIC_API_DIR [::GX::NumericAPIv1::octaveApiDir] GXDCF_CORE_OCTAVE_DIR [file join $root core octave]]
        set executable [auto_execok octave-cli];if {$executable eq {}} {error {GNU Octave is required}}
        set run [::GX::parallelExecutionNewRunId curve_parameters];set progress {}
        if {[info exists state($key,loading)]&&$state($key,loading)} {set state($key,numericRun) $run;set progress [list ::GX::DatasetCurveFit::_numericProgress $key]}
        set task [dict create id parameters argv [list {*}$executable --quiet --no-gui --path [file join $root plugins modules viewer.dataset_curve_fit runtime] --eval {dataset_curve_fit_parameters('evaluate')}]]
        set execution [::GX::parallelExecutionExecute [list $task] [dict create kind process command_builder ::GX::DatasetCurveFit::_numericCommand environment $environment] [dict create workers 1 run_id $run progress_command $progress]]
        set result [lindex [dict get $execution results] 0]
        if {[dict get $execution state] eq "cancelled"} {error {Manual parameter evaluation cancelled}}
        if {[dict get $result state] ne "success"} {error [dict get $result stderr]}
        if {$fingerprint ne [_parameterFingerprint $key]} {error {Source or settings changed during parameter evaluation}}
        return [dict get [::GX::ScientificTransportv1::readResult $resultFile] values view]
    } finally {
        if {$run ne {}} {::GX::parallelExecutionRelease $run}
        if {[info exists state($key,numericRun)]} {set state($key,numericRun) {}}
        file delete -force -- $valuesFile $resultFile
    }
}
proc ::GX::DatasetCurveFit::recipeParameterView {encoded {parameters {}}} {
    set key [new]
    try {
        recipeLoadSettings $key $encoded 1
        set result [parameterPrepare $key]
        if {$parameters ne {}} {dict set result curve [parameterEvaluate $key $parameters]}
        return $result
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::_parameterRecipeValues {model recipe ids values} {
    if {$model in {formula rational}} {
        set rows {};foreach row [dict get $recipe parameters] {
            dict set row initial [lindex $values [lsearch -exact $ids [dict get $row id]]];lappend rows $row
        };dict set recipe parameters $rows
    } else {
        set breakIds {}
        if {$model eq "regions"} {
            set breaks {};foreach row [dict get $recipe breakpoints] {
                set id [dict get $row id];lappend breakIds $id;dict set row initial [lindex $values [lsearch -exact $ids $id]];lappend breaks $row
            };dict set recipe breakpoints $breaks
        }
        foreach id $ids value $values {if {$id ni $breakIds} {dict set recipe parameters $id initial $value}}
    }
    return $recipe
}
proc ::GX::DatasetCurveFit::recipeParametersSet {encoded parameters} {
    set key [new]
    try {
        recipeLoadSettings $key $encoded 1
        set view [parameterPrepare $key];parameterEvaluate $key $parameters
        set recipe [_recipeDecode $encoded];set model [dict get $recipe fit model]
        dict set recipe fit initial $parameters
        if {$model in {formula rational components regions}} {
            set option [dict get {formula formula_recipe rational rational_recipe components component_recipe regions region_recipe} $model]
            dict set recipe fit options $option [_parameterRecipeValues $model [dict get $recipe fit options $option] [dict get $view parameter_ids] $parameters]
        }
        set result [::GX::scientificRecipeEncode $recipe];recipeValidate $result;return $result
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::_parameterSettings {w} {
    variable state
    set d $w.parameterView;if {[winfo exists $d]} {raise $d;return}
    set saved [_operationBegin $w]
    try {set view [parameterPrepare $w]} finally {_operationEnd $w $saved}
    set state($d,fingerprint) $state($w,parameterFingerprint);set state($d,ids) [dict get $view parameter_ids]
    set state($d,status) {Manual curve only. Apply stores initial values; fitting and accepting remain explicit.}
    if {[dict exists $view direct_model]&&[dict get $view direct_model]} {set state($d,status) {Manual direct-model curve. Apply stores these values for exploration; direct fitting independently solves the source data.}}
    toplevel $d;wm title $d {Initial parameters and manual curve};wm transient $d $w
    wm geometry $d 760x460;wm minsize $d 620 320
    wm protocol $d WM_DELETE_WINDOW [list ::GX::DatasetCurveFit::_parameterDialogClose $w $d]
    ttk::frame $d.actions -padding 8;pack $d.actions -side bottom -fill x
    foreach {id label action} {suggest {Suggest initials} _parameterSuggest evaluate {Evaluate now} _parameterLive apply {Apply initial values} _parameterApply} {
        ttk::button $d.actions.$id -text $label -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::$action $w $d]];pack $d.actions.$id -side left -padx 4
    }
    if {[dict get $view status] ne "proposed"} {$d.actions.suggest configure -state disabled;set state($d,status) [dict get $view reason]}
    ttk::button $d.actions.close -text Close -command [list ::GX::DatasetCurveFit::_parameterDialogClose $w $d];pack $d.actions.close -side right
    set body [::GX::scrollableDialogBody $d]
    ttk::label $body.help -text "Values use the model's declared units and fitting coordinates. The dashed purple curve is a bounded display (at most 1024 points). Live edits evaluate after a short pause; they do not fit or create uncertainty estimates." -wraplength 680 -justify left
    pack $body.help -fill x -padx 8 -pady 8
    ttk::frame $body.rows;pack $body.rows -fill x -padx 8;set i 0
    foreach id [dict get $view parameter_ids] value [dict get $view current_parameters] lower [dict get $view lower_bounds] upper [dict get $view upper_bounds] fixed [dict get $view fixed_mask] {
        set state($d,value,$i) $value
        ttk::label $body.rows.id$i -text $id;ttk::entry $body.rows.value$i -textvariable ::GX::DatasetCurveFit::state($d,value,$i) -width 24
        ttk::label $body.rows.bound$i -text [expr {$fixed?"Fixed":"Bounds: $lower to $upper"}]
        grid $body.rows.id$i -row $i -column 0 -sticky w -padx 4 -pady 3;grid $body.rows.value$i -row $i -column 1 -sticky ew -padx 4;grid $body.rows.bound$i -row $i -column 2 -sticky w -padx 4
        if {$fixed} {$body.rows.value$i configure -state readonly}
        bind $body.rows.value$i <KeyRelease> [list ::GX::DatasetCurveFit::_parameterSchedule $w $d]
        incr i
    }
    grid columnconfigure $body.rows 1 -weight 1
    ttk::label $body.status -textvariable ::GX::DatasetCurveFit::state($d,status) -wraplength 680 -justify left;pack $body.status -fill x -padx 8 -pady 8
    _parameterSchedule $w $d
}
proc ::GX::DatasetCurveFit::_parameterValues {w d} {
    variable state
    if {![info exists state($w,parameterFingerprint)]||$state($d,fingerprint) ne [_parameterFingerprint $w]} {error {Source or settings changed; close and reopen parameter controls}}
    set values {};set i 0
    foreach id $state($d,ids) {lappend values [_finite $state($d,value,$i) "Parameter $id"];incr i}
    return $values
}
proc ::GX::DatasetCurveFit::_parameterSchedule {w d} {
    variable state
    if {[info exists state($w,parameterAfter)]} {after cancel $state($w,parameterAfter)}
    set state($w,parameterAfter) [after 300 [list ::GX::DatasetCurveFit::_parameterLive $w $d]]
}
proc ::GX::DatasetCurveFit::_parameterLive {w d} {
    variable state
    if {![winfo exists $w]||![winfo exists $d]} return
    if {[info exists state($w,parameterAfter)]} {after cancel $state($w,parameterAfter);unset state($w,parameterAfter)}
    if {[info exists state($w,loading)]&&$state($w,loading)} {_parameterSchedule $w $d;return}
    set saved [_operationBegin $w]
    try {
        set values [_parameterValues $w $d];set result [parameterEvaluate $w $values]
        if {$values ne [_parameterValues $w $d]} {return}
        set state($w,manualPoints) [dict get $result points]
        set state($d,status) "Manual curve evaluated at [dict get $result display_count] display points. No fit or accepted result was created."
    } on error {message details} {
        unset -nocomplain state($w,manualPoints);if {[winfo exists $d]} {set state($d,status) $message}
    } finally {_operationEnd $w $saved;if {[winfo exists $w]} {redraw $w}}
}
proc ::GX::DatasetCurveFit::_parameterSuggest {w d} {
    variable state
    _parameterValues $w $d
    set view $state($w,parameterView)
    if {[dict get $view status] ne "proposed"} {error [dict get $view reason]}
    set i 0;foreach value [dict get $view suggested_parameters] {set state($d,value,$i) $value;incr i}
    _parameterLive $w $d
}
proc ::GX::DatasetCurveFit::_parameterApply {w d} {
    variable state
    set values [_parameterValues $w $d]
    set saved [_operationBegin $w]
    try {parameterEvaluate $w $values} finally {_operationEnd $w $saved}
    if {$values ne [_parameterValues $w $d]} {error {Parameters changed during validation; apply again}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set model $state($w,model)
    if {$model in {formula rational components regions}} {
        set field [dict get {formula formulaRecipe rational rationalRecipe components componentRecipe regions regionRecipe} $model]
        set state($w,$field) [_parameterRecipeValues $model $state($w,$field) $state($d,ids) $values]
    }
    set state($w,initial) [join $values ,]
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    _parameterDialogClose $w $d
    set state($w,status) {Initial parameters saved. Preview fit explicitly to optimize; ordinary linear/polynomial least squares has no iterative starting parameters.}
}
proc ::GX::DatasetCurveFit::_parameterDialogClose {w d} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {set state($w,sourceCancelled) 1;after 100 [list ::GX::DatasetCurveFit::_parameterDialogClose $w $d];return}
    _parameterClear $w
    if {[winfo exists $d]} {destroy $d}
    foreach key [array names state "$d,*"] {unset state($key)}
    if {[winfo exists $w]} {redraw $w}
}
