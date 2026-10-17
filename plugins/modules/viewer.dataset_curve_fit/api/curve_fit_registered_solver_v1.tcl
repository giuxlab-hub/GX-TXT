# SPDX-License-Identifier: GPL-3.0-or-later
# UI/recipe validation. Numeric executes these settings and CORE validates its receipt.
proc ::GX::DatasetCurveFit::_registeredSolverDefaults {} {
    return {solver scipy_least_squares method trf max_function_evaluations 8000 function_tolerance 1e-8 gradient_tolerance 1e-8 parameter_tolerance 1e-8 parameter_scales {}}
}
proc ::GX::DatasetCurveFit::_registeredSolverOptions {definition options} {
    set defaults [_registeredSolverDefaults]
    set settings [::GX::datasetPublicationV2DictDefault $options solver_options {}]
    dict for {field value} $settings {if {![dict exists $defaults $field]} {error "Unknown registered callback solver setting: $field"}}
    set settings [dict merge $defaults $settings]
    if {[dict get $settings solver] ni {auto least_squares scipy_least_squares}||[dict get $settings method] ni {trf dogbox}} {error {Registered callbacks require SciPy least-squares with trf or dogbox}}
    set limit [_finite [dict get $settings max_function_evaluations] {Function-evaluation limit}]
    if {$limit!=floor($limit)||$limit<1||$limit>2000000} {error {Function-evaluation limit must be an integer from 1 to 2000000}}
    dict set settings max_function_evaluations [expr {int($limit)}]
    foreach field {function_tolerance gradient_tolerance parameter_tolerance} {
        set value [_finite [dict get $settings $field] $field]
        if {$value<=2.220446049250313e-16} {error {Callback tolerances must exceed binary64 machine epsilon}}
        dict set settings $field $value
    }
    set scales [dict get $settings parameter_scales]
    if {$scales ne {}} {
        if {[llength $scales]!=[llength [dict get $definition parameter_ids]]} {error {Callback parameter scales must match canonical parameter order}}
        foreach value $scales {if {[_finite $value {Physical parameter scale}]<=0} {error {Callback physical parameter scales must be positive}}}
    }
    return $settings
}
proc ::GX::DatasetCurveFit::_registeredSolverDialog {w} {
    variable state
    if {![info exists state($w,registeredModel)]||$state($w,registeredModel) eq {}} {error {Choose a declared registered model before opening callback solver settings}}
    set registered [_registeredModelValidate $state($w,registeredModel)]
    set settings [_registeredSolverOptions [dict get $registered definition] [dict create solver_options [::GX::datasetPublicationV2DictDefault $state($w,solverSettings) registered {}]]]
    set fields [dict create solver [dict create type choice label Backend values {scipy_least_squares}] method [dict create type choice label {Bounded least-squares method} values {trf dogbox}]]
    foreach {field label} {max_function_evaluations {Maximum solver function evaluations} function_tolerance {Relative objective tolerance} gradient_tolerance {Gradient tolerance} parameter_tolerance {Parameter-step tolerance}} {dict set fields $field [dict create type number label $label required 1]}
    dict set fields parameter_scales [dict create type string label {Positive physical parameter scales, space-separated (blank = 1 for every parameter)}]
    # Existing aliases select the same backend; the form displays its real name.
    dict set settings solver scipy_least_squares
    ::GX::uiFieldFormCreate $w.solverSettings {Registered callback solver settings} $fields $settings [list ::GX::DatasetCurveFit::_registeredSolverApply $w $state($w,activeSource) $registered] $w
    ttk::label $w.solverSettings.note -text "Parameter order: [join [dict get $registered definition parameter_ids] {, }]. Bounds and fixed roles come from the model declaration. The limit counts solver function evaluations; numerical Jacobians add callback invocations. Cancel uses the supervised Job." -wraplength 600
    pack $w.solverSettings.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_registeredSolverApply {w owner captured values} {
    variable state
    if {$state($w,activeSource) ne $owner||$state($w,model) ne "registered"} {error {Active source or model changed; reopen solver settings}}
    set current [_registeredModelValidate $state($w,registeredModel)]
    foreach field {reference callable_id source_sha256 declaration_sha256 revision} {if {[dict get $current $field] ne [dict get $captured $field]} {error {Registered declaration changed; reopen solver settings}}}
    set values [_registeredSolverOptions [dict get $current definition] [dict create solver_options $values]]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    dict set state($w,solverSettings) registered $values
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Callback solver settings saved. Preview submits a supervised Job and retains the actual backend, limits and stopping reason.}
}
