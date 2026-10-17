# SPDX-License-Identifier: GPL-3.0-or-later
# UI/data adaptation only. Numeric validates and executes the solver policy.
proc ::GX::DatasetCurveFit::_solverDefaults {} {
    return {solver auto strategy levenberg_marquardt max_iterations 1200 max_seconds 3600 function_tolerance 1e-12 gradient_tolerance 1e-12 parameter_tolerance 1e-12 loss linear loss_scale 1 lower_bounds {} upper_bounds {} fixed_mask {} parameter_scales {} multistart_mode single multistart_count 8 multistart_seed 1 multistart_max_seconds 60 multistart_lower {} multistart_upper {} multistart_initials {}}
}
proc ::GX::DatasetCurveFit::_solverOptionNodes {model initial options} {
    set policy [::GX::datasetPublicationV2DictDefault $options solver_options {}]
    if {$policy eq {}} {return [::GX::ScientificTransportv1::struct {}]}
    if {$model ni {exponential power_law gaussian components regions formula rational implicit complex_response}&& !($model in {linear polynomial}&&[dict get [_measurementOptions $options] kind] eq "sigma_xy")} {error {Solver controls apply to nonlinear models or linear/polynomial models with both-axis uncertainties}}
    set defaults [_solverDefaults];set nodes {};set count [llength $initial]
    dict for {key value} $policy {
        if {![dict exists $defaults $key]} {error "Unknown nonlinear solver setting: $key"}
        if {$key in {solver strategy loss multistart_mode}} {
            set permitted [dict get {solver {auto ceres} strategy {levenberg_marquardt dogleg} loss {linear huber cauchy soft_l1 arctan tukey} multistart_mode {single explicit uniform}} $key]
            if {$value ni $permitted} {error "Unknown $key choice"}
            dict set nodes $key [::GX::ScientificTransportv1::text $value]
        } elseif {$key eq "multistart_initials"} {
            if {$value eq {}} continue
            set rows [llength $value];set packed {}
            foreach row $value {if {[llength $row]!=$count} {error "Each multistart initial row needs $count parameters"};foreach number $row {_finite $number {Multistart initial value}}}
            if {$rows<1||$rows>63} {error {Supply one to 63 additional initial rows}}
            for {set column 0} {$column<$count} {incr column} {foreach row $value {lappend packed [lindex $row $column]}}
            dict set nodes $key [::GX::ScientificTransportv1::array [list $rows $count] $packed]
        } elseif {$key in {lower_bounds upper_bounds fixed_mask parameter_scales multistart_lower multistart_upper}} {
            if {$value eq {}} continue
            if {[llength $value]!=$count} {error "$key requires $count values in canonical parameter order"}
            foreach number $value {
                if {$key eq "lower_bounds"&&$number eq "-Inf"||$key eq "upper_bounds"&&$number in {Inf +Inf}} continue
                set numeric [_finite $number $key]
                if {$key eq "fixed_mask"&&$numeric ni {0 1 0.0 1.0}} {error {Fixed parameters require a 0/1 mask}}
                if {$key eq "parameter_scales"&&$numeric<=0} {error {Parameter scales must be positive}}
            }
            dict set nodes $key [::GX::ScientificTransportv1::array [list $count 1] $value]
        } else {
            set numeric [_finite $value $key]
            if {$numeric<0||($key in {max_seconds loss_scale max_iterations}&&$numeric==0)} {error "$key is outside its valid range"}
            if {$key eq "max_iterations"&&($numeric!=floor($numeric)||$numeric>100000)} {error {Iteration limit must be an integer from 1 to 100000}}
            if {$key eq "multistart_count"&&($numeric!=floor($numeric)||$numeric<2||$numeric>64)} {error {Multistart count must be an integer from 2 to 64}}
            if {$key eq "multistart_seed"&&($numeric!=floor($numeric)||$numeric<1||$numeric>2147483646)} {error {Multistart seed must be an integer from 1 to 2147483646}}
            if {$key eq "multistart_max_seconds"&&($numeric<=0||$numeric>86400)} {error {Multistart total seconds must be in (0,86400]}}
            dict set nodes $key [::GX::ScientificTransportv1::array {1 1} [list $value]]
        }
    }
    return [::GX::ScientificTransportv1::struct $nodes]
}
proc ::GX::DatasetCurveFit::_solverSettings {w} {
    variable state
    set model $state($w,model)
    if {$model eq "registered"} {return [_registeredSolverDialog $w]}
    if {$model ni {exponential power_law gaussian components regions formula rational implicit complex_response}&& !($model in {linear polynomial}&&$state($w,measurementKind) eq "sigma_xy")} {error {Choose a nonlinear model or a linear/polynomial model with both-axis uncertainties for native solver settings}}
    set fields {}
    foreach {key label choices} {solver Solver {auto ceres} strategy {Trust-region strategy} {levenberg_marquardt dogleg} loss {Residual loss} {linear huber cauchy soft_l1 arctan tukey} multistart_mode {Starting strategy} {single explicit uniform}} {
        dict set fields $key [dict create type choice label $label values $choices]
    }
    foreach {key label} {max_iterations {Maximum iterations} max_seconds {Maximum solver seconds} function_tolerance {Relative objective tolerance} gradient_tolerance {Gradient tolerance} parameter_tolerance {Parameter tolerance} loss_scale {Robust loss scale in weighted residual units}} {
        dict set fields $key [dict create type number label $label required 1]
    }
    foreach {key label} {lower_bounds {Lower bounds (-Inf for unbounded)} upper_bounds {Upper bounds (Inf for unbounded)} fixed_mask {Fixed parameters (1 fixed, 0 free)} parameter_scales {Positive physical parameter scales}} {
        dict set fields $key [dict create type string label "$label; blank = automatic/default"]
    }
    foreach {key label} {multistart_count {Total starts including current initial values (2–64)} multistart_seed {Uniform-start seed (1–2147483646)} multistart_max_seconds {Overall multistart time limit in seconds}} {dict set fields $key [dict create type number label $label required 1]}
    foreach {key label} {multistart_lower {Uniform starting range lower values} multistart_upper {Uniform starting range upper values} multistart_initials {Explicit additional initial rows; separate rows with semicolons}} {dict set fields $key [dict create type string label $label]}
    set values [dict merge [_solverDefaults] [::GX::datasetPublicationV2DictDefault $state($w,solverSettings) $model {}]]
    dict set values multistart_initials [join [dict get $values multistart_initials] {; }]
    if {$model eq "implicit"} {foreach name [dict keys $fields multistart_*] {dict unset fields $name;dict unset values $name};if {![dict exists $state($w,solverSettings) implicit]} {dict set values max_iterations 400;dict set values max_seconds 30}}
    if {$model eq "complex_response"} {
        foreach name [dict keys $fields] {if {[string match multistart_* $name]||$name in {loss loss_scale lower_bounds upper_bounds fixed_mask}} {dict unset fields $name;dict unset values $name}}
        if {![dict exists $state($w,solverSettings) complex_response]} {dict set values max_iterations 400;dict set values max_seconds 30}
    }
    ::GX::uiFieldFormCreate $w.solverSettings {Native nonlinear solver settings} $fields $values [list ::GX::DatasetCurveFit::_solverApply $w $state($w,activeSource) $model] $w
    if {$model eq "components"} {set ids [dict get [_prepareComponents $w [_uiFitOptions $w]] parameter_ids]} elseif {$model eq "regions"} {set ids [dict get [_prepareRegions $w [_uiFitOptions $w]] parameter_ids]} elseif {$model eq "complex_response"} {set ids [dict get [_prepareComplex $w [_uiFitOptions $w]] parameter_ids]} elseif {$model eq "implicit"} {set ids [dict get [_prepareImplicit $w [_uiFitOptions $w]] parameter_ids]} elseif {$model eq "formula"} {set ids [dict get [_prepareFormula $w [_uiFitOptions $w]] parameter_ids]} else {set ids [dict get [::GX::StatisticsV1::model math.numeric.$model] parameter_ids]}
    if {$model eq "polynomial"} {set ids {};for {set power $state($w,degree)} {$power>=0} {incr power -1} {lappend ids power_$power}}
    ttk::label $w.solverSettings.note -text "Parameter vectors use this order: [join $ids {, }]. Enter space-separated values. Initial parameters remain in the Fit panel. Robust-loss uncertainty requires a separately validated estimator; the ordinary covariance interval is unavailable." -wraplength 600
    pack $w.solverSettings.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_solverApply {w owner model values} {
    variable state
    if {$owner ne $state($w,activeSource)||$model ne $state($w,model)} {error {Active source or model changed; reopen solver settings}}
    if {$model eq "components"} {set count [llength [dict get [_prepareComponents $w [_uiFitOptions $w]] parameter_ids]]} elseif {$model eq "regions"} {set count [llength [dict get [_prepareRegions $w [_uiFitOptions $w]] parameter_ids]]} elseif {$model eq "complex_response"} {set count [llength [dict get [_prepareComplex $w [_uiFitOptions $w]] parameter_ids]]} elseif {$model eq "implicit"} {set count [llength [dict get [_prepareImplicit $w [_uiFitOptions $w]] parameter_ids]]} elseif {$model eq "rational"} {set count [llength [dict get [_prepareRational $w [_uiFitOptions $w]] parameter_ids]]} elseif {$model eq "formula"} {set count [llength [dict get [_prepareFormula $w [_uiFitOptions $w]] parameter_ids]]} else {set count [llength [dict get [::GX::StatisticsV1::model math.numeric.$model] parameter_ids]]}
    if {$model eq "polynomial"} {set count [expr {$state($w,degree)+1}]}
    if {[dict exists $values multistart_initials]} {
        set rows {};foreach row [split [dict get $values multistart_initials] {;}] {if {[string trim $row] ne {}} {lappend rows [string trim $row]}}
        dict set values multistart_initials $rows
    }
    set options [dict create solver_options $values]
    if {$state($w,measurementKind) eq "sigma_xy"} {dict set options measurement [dict create kind sigma_xy variable_id $state($w,measurementVariable) independent_variable_id $state($w,measurementIndependentVariable)]}
    _solverOptionNodes $model [lrepeat $count 0] $options
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    dict set state($w,solverSettings) $model $values
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Solver settings saved for this source and model. Preview again; exact effective settings accompany the result.}
}
