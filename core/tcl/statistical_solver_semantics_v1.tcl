# SPDX-License-Identifier: GPL-3.0-or-later
# Part of STATISTICAL_RESULT_SEMANTICS_API_v1. No optimization or estimation.
proc ::GX::StatisticsV1::_orthogonalXYAssumptions {} {
    return {{Independent X and Y measurement errors are represented by supplied positive absolute standard uncertainties; no axis or cross-observation correlation is modeled} {One true predictor coordinate per observation pair is fitted together with the physical model parameters} {Parameter covariance is a local Gauss-Newton approximation after eliminating latent-coordinate tangents; it is not scaled by observed residual variance} {Normalized XY distance is unsigned; the separate physical coordinate corrections retain fitted-minus-observed signs and their respective axis units} {Ordinary functional-response R squared does not describe this objective; local convergence does not establish a global optimum or physical model validity}}
}
proc ::GX::StatisticsV1::_orthogonalXYDataFields {result} {
    set n [expr {int([dict get $result quantities n value])}];set context [dict get $result context]
    set independent [_get $context x_unit unspecified];set response [_get $context y_unit unspecified]
    if {[_get $context orientation y_of_x] eq "x_of_y"} {set independent [_get $context y_unit unspecified];set response [_get $context x_unit unspecified]}
    set fields {}
    foreach {name unit label definition} [list adjusted_x $independent {Fitted latent predictor} {Observed predictor plus fitted predictor correction in the original supplied units} predicted $response {Response at fitted latent predictor} {Model response at the fitted latent predictor, not at the observed predictor} residuals 1 {Normalized XY distance} {Unsigned Euclidean norm of the two standardized coordinate corrections} weighted_residuals 1 {Normalized XY distance} {Same normalized XY distance; no additional response-only weight is applied}] {
        dict set fields $name [dict create kind vector value_kind real unit $unit shape [list $n 1] label $label definition $definition]
    }
    foreach {name units label definition} [list coordinate_corrections [list $independent $response] {Physical coordinate corrections} {Fitted minus observed predictor and response coordinates; each column retains its own physical units} normalized_corrections {1 1} {Standardized coordinate corrections} {Physical predictor and response corrections divided by their respective supplied standard uncertainties}] {
        dict set fields $name [dict create kind matrix value_kind real unit per_column column_units $units column_ids {independent_correction response_correction} shape [list $n 2] label $label definition $definition]
    }
    dict set fields source_row_positions [dict create kind vector value_kind integer unit 1 shape [list $n 1] minimum 1 label {Retained input row} definition {One-based row in the input arrays before explicit omission; a Dataset Selection has its own original-row mapping}]
    if {[string match dataset_* [_get [dict get $result provenance] operation {}]]} {
        dict set fields source_row_ordinals [dict create kind vector value_kind integer unit 1 shape [list $n 1] minimum 1 label {Original Dataset row} definition {Exact one-based uint64 source Dataset row before Selection and explicit omission}]
    }
    return $fields
}
proc ::GX::StatisticsV1::_solverReceipt {receipt parameters numerical context} {
    if {[_get $receipt schema {}] eq "gxtxt.callback_solver_receipt.v1"} {return [_callbackSolverReceipt $receipt $parameters $numerical $context]}
    set fields {schema method requested_solver backend_version derivative_method termination solver_message converged iterations function_evaluations jacobian_evaluations solver_seconds solver_objective threads_used parameter_scales initial_parameters lower_bounds upper_bounds fixed_mask function_tolerance gradient_tolerance parameter_tolerance max_iterations max_seconds strategy loss loss_scale linear_solver jacobi_scaling iteration_convention}
    _keys $receipt [concat $fields {multistart orthogonal_xy}] solver_receipt
    foreach field $fields {if {![dict exists $receipt $field]} {_error "Solver receipt lacks $field"}}
    foreach {field expected} {schema gxtxt.numeric_solver_receipt.v1 method ceres derivative_method automatic_differentiation iteration_convention ceres_iteration_records_including_initial_state} {
        if {[dict get $receipt $field] ne $expected} {_error "Unsupported solver receipt $field"}
    }
    set odr [expr {[_get $context fit_geometry vertical_response] eq "orthogonal_xy"}]
    if {$odr!=[dict exists $receipt orthogonal_xy]} {_error {Solver geometry contradicts the statistical context}}
    set expectedLinear dense_qr
    if {$odr} {
        set geometry [dict get $receipt orthogonal_xy]
        _keys $geometry {schema nuisance_parameter_count residual_component_count jacobian_convention sigma_semantics} orthogonal_xy
        foreach {field expected} {schema gxtxt.numeric_orthogonal_xy_receipt.v1 jacobian_convention projected_model_parameter_tangent_after_independent_latent_x_elimination sigma_semantics independent_absolute_axis_standard_uncertainties} {
            if {[_get $geometry $field {}] ne $expected} {_error "Invalid orthogonal XY $field"}
        }
        set n [_get $geometry nuisance_parameter_count {}];set components [_get $geometry residual_component_count {}]
        if {![_finite $n]||$n<1||$n>200000||$n!=floor($n)||![_finite $components]||$components!=2*$n} {_error {Invalid orthogonal XY residual or nuisance count}}
        if {[dict exists $numerical n]&&[dict get $numerical n]!=$n} {_error {Orthogonal XY nuisance count differs from observation pairs}}
        if {[dict exists $numerical rank]&&[dict exists $numerical dof]&&[dict get $numerical dof]!=$n-[dict get $numerical rank]} {_error {Orthogonal XY degrees of freedom must account for every latent coordinate}}
        if {$n>2048} {set expectedLinear dense_schur}
        if {[dict get $receipt loss] ne "linear"} {_error {This orthogonal XY backend requires quadratic loss}}
    }
    if {[dict get $receipt linear_solver] ne $expectedLinear} {_error {Unsupported solver receipt linear_solver}}
    foreach {field allowed} {requested_solver {auto ceres} strategy {levenberg_marquardt dogleg} loss {linear huber cauchy soft_l1 arctan tukey} termination {CONVERGENCE NO_CONVERGENCE FAILURE USER_SUCCESS USER_FAILURE}} {
        if {[dict get $receipt $field] ni $allowed} {_error "Unknown solver receipt $field"}
    }
    foreach field {converged jacobi_scaling} {if {![string is boolean -strict [dict get $receipt $field]]} {_error "Solver receipt $field must be boolean"}}
    if {![dict get $receipt jacobi_scaling]} {_error {This backend requires its declared Jacobian scaling}}
    if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.+_-]*)$} [dict get $receipt backend_version]]} {_error {Invalid solver backend version}}
    set message [dict get $receipt solver_message]
    if {[string length $message]>8192||[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f]} $message]} {_error {Invalid bounded solver message}}
    foreach field {iterations function_evaluations jacobian_evaluations threads_used max_iterations} {
        set value [dict get $receipt $field]
        set minimum [expr {$field in {threads_used max_iterations} ? 1 : ($field in {function_evaluations jacobian_evaluations} ? -1 : 0)}]
        if {![_finite $value]||$value!=floor($value)||$value<$minimum} {_error "Invalid solver count $field"}
    }
    if {[dict get $receipt max_iterations]>100000||[dict get $receipt iterations]>[dict get $receipt max_iterations]+1} {_error {Solver iteration count exceeds the recorded limit}}
    foreach field {function_tolerance gradient_tolerance parameter_tolerance solver_seconds max_seconds loss_scale} {
        set value [dict get $receipt $field]
        if {![_finite $value]||$value<0||($field in {max_seconds loss_scale}&&$value==0)} {_error "Invalid solver setting $field"}
    }
    set converged [dict get $receipt converged]
    set termination [dict get $receipt termination]
    if {$converged!=($termination in {CONVERGENCE USER_SUCCESS})} {_error {Convergence flag contradicts solver termination}}
    if {[dict exists $numerical converged]&&$converged!=[dict get $numerical converged]} {_error {Convergence receipt contradicts numerical facts}}
    if {[_get $context solver unspecified] ne "ceres"} {_error {Solver receipt contradicts the recorded method}}
    if {[_get $context loss linear] ne [dict get $receipt loss]} {_error {Solver receipt contradicts the recorded loss}}
    set objective [dict get $receipt solver_objective]
    if {$converged&&(![_finite $objective]||$objective<0)} {_error {A converged solver requires a finite nonnegative objective}}
    if {!$converged&&![_finite $objective]&&![string equal -nocase $objective NaN]} {_error {Invalid failed solver objective}}
    set count [llength $parameters]
    if {$count<1||$count>128} {_error {Solver receipt requires one to 128 identified parameters}}
    foreach field {initial_parameters parameter_scales lower_bounds upper_bounds fixed_mask} {
        if {[llength [dict get $receipt $field]]!=$count} {_error "Solver $field length differs from parameter identity count"}
    }
    foreach parameter $parameters initial [dict get $receipt initial_parameters] scale [dict get $receipt parameter_scales] lower [dict get $receipt lower_bounds] upper [dict get $receipt upper_bounds] fixed [dict get $receipt fixed_mask] {
        if {![_finite $initial]||![_finite $scale]||$scale<=0||(![_finite $lower]&&![_infinite $lower -1])||(![_finite $upper]&&![_infinite $upper 1])} {_error {Invalid solver parameter value, scale or bound}}
        if {$lower>$upper||$initial<$lower||$initial>$upper} {_error {Initial parameter is outside its recorded bounds}}
        if {$fixed ni {0 1 0.0 1.0}||($lower==$upper&&!$fixed)} {_error {Invalid solver fixed mask}}
        if {($fixed&&[dict get $parameter role] ne "fixed")||(!$fixed&&[dict get $parameter role] ne "free")} {_error {Solver fixed mask contradicts parameter roles}}
        if {[dict exists $parameter value]} {
            set value [dict get $parameter value]
            if {![_finite $value]||$value<$lower||$value>$upper||($fixed&&$value!=$initial)} {_error {Estimated parameter contradicts recorded bounds or fixed value}}
        }
    }
    set meanings [dict create CONVERGENCE {The backend stopping criteria were satisfied. This does not establish a global optimum or validate the model.} NO_CONVERGENCE {The backend stopped before satisfying convergence criteria. Inspect the recorded message and limits; parameter uncertainty is unavailable.} FAILURE {The backend reported failure. The returned state cannot certify a successful fit.} USER_SUCCESS {The backend callback reported success. This does not establish a global optimum or validate the model.} USER_FAILURE {The backend callback stopped the fit with failure.}]
    if {[dict exists $receipt multistart]} {_multistartReceipt [dict get $receipt multistart] $receipt $parameters $context}
    return [dict create status value converged $converged method ceres reason [dict get $meanings $termination] diagnostics $receipt]
}
proc ::GX::StatisticsV1::_multistartReceipt {multi parent parameters context} {
    set fields {schema mode requested_count seed next_seed generator strategy_version initials range_lower range_upper max_seconds execution_policy cancellation_policy selection_policy trials selected_index converged_count attempted_count completed_count error_count elapsed_seconds}
    _keys $multi $fields multistart
    foreach key $fields {if {![dict exists $multi $key]} {_error "Multistart receipt lacks $key"}}
    foreach {key expected} {schema gxtxt.numeric_multistart_receipt.v1 strategy_version 1 execution_policy sequential_one_thread_per_trial cancellation_policy worker_cancellation_discards_incomplete_result selection_policy {lowest_finite_objective_among_converged_else_provisional;first_index_breaks_exact_ties}} {
        if {[dict get $multi $key] ne $expected} {_error "Unsupported multistart $key"}
    }
    foreach key {requested_count seed next_seed selected_index converged_count attempted_count completed_count error_count} {
        set value [dict get $multi $key]
        if {![_finite $value]||$value!=floor($value)||$value<0} {_error "Invalid multistart count $key"}
    }
    set count [dict get $multi requested_count];set p [llength $parameters];set mode [dict get $multi mode]
    if {$count<2||$count>64||$mode ni {explicit uniform}||[llength [dict get $multi initials]]!=$count||[llength [dict get $multi trials]]!=$count} {_error {Invalid multistart mode or dimensions}}
    foreach key {max_seconds elapsed_seconds} {if {![_finite [dict get $multi $key]]||[dict get $multi $key]<0} {_error "Invalid multistart $key"}}
    if {[dict get $multi max_seconds]<=0||[dict get $multi max_seconds]>86400} {_error {Invalid overall multistart limit}}
    if {$mode eq "uniform"} {
        if {[dict get $multi generator] ne "park_miller_16807_v1"||[dict get $multi seed]<1||[dict get $multi seed]>2147483646||[dict get $multi next_seed]<1||[dict get $multi next_seed]>2147483646||[llength [dict get $multi range_lower]]!=$p||[llength [dict get $multi range_upper]]!=$p} {_error {Invalid reproducible multistart generator or range}}
        foreach lo [dict get $multi range_lower] hi [dict get $multi range_upper] lb [dict get $parent lower_bounds] ub [dict get $parent upper_bounds] {
            if {![_finite $lo]||![_finite $hi]||$lo>$hi||$lo<$lb||$hi>$ub} {_error {Multistart range violates solver bounds}}
        }
    } elseif {[dict get $multi generator] ne "none"||[dict get $multi seed]!=0||[dict get $multi next_seed]!=0||[dict get $multi range_lower] ne {}||[dict get $multi range_upper] ne {}} {_error {Explicit starts must not invent a random generator}}
    set index 0;set attempted 0;set completed 0;set errors 0;set converged 0;set best 0;set bestObjective Inf;set bestConverged 0;set stopped 0
    foreach trial [dict get $multi trials] start [dict get $multi initials] {
        incr index
        if {[llength $start]!=$p||[dict get $trial index]!=$index||[llength [dict get $trial initial_parameters]]!=$p} {_error {Multistart trial identity or initial shape differs}}
        foreach value $start captured [dict get $trial initial_parameters] lb [dict get $parent lower_bounds] ub [dict get $parent upper_bounds] fixed [dict get $parent fixed_mask] original [lindex [dict get $multi initials] 0] {
            if {![_finite $value]||![_finite $captured]||$value!=$captured||$value<$lb||$value>$ub||($fixed&&$value!=$original)} {_error {Multistart initial value violates captured bounds or fixed parameters}}
        }
        if {$mode eq "uniform"&&$index>1} {
            foreach value $start lo [dict get $multi range_lower] hi [dict get $multi range_upper] fixed [dict get $parent fixed_mask] {if {!$fixed&&($value<$lo||$value>$hi)} {_error {Generated start lies outside its recorded range}}}
        }
        set status [dict get $trial status];set message [dict get $trial message]
        if {[string length $message]>2048||[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f]} $message]} {_error {Invalid multistart message}}
        if {$status eq "completed"} {
            _keys $trial {index initial_parameters status message parameters solver_receipt} multistart_trial
            if {$stopped||$message ne {}||[llength [dict get $trial parameters]]!=$p} {_error {Invalid completed multistart trial}}
            set receipt [dict get $trial solver_receipt]
            if {[dict exists $receipt multistart]||[dict get $receipt threads_used]!=1} {_error {Recursive or parallel multistart trial is unsupported}}
            set trialParameters {}
            foreach parameter $parameters value [dict get $trial parameters] {dict set parameter value $value;lappend trialParameters $parameter}
            _solverReceipt $receipt $trialParameters [dict create converged [dict get $receipt converged]] $context
            foreach key {initial_parameters} {foreach a [dict get $receipt $key] b $start {if {$a!=$b} {_error {Trial solver initial values differ from recorded starts}}}}
            foreach key {parameter_scales lower_bounds upper_bounds fixed_mask function_tolerance gradient_tolerance parameter_tolerance max_iterations strategy loss loss_scale linear_solver jacobi_scaling requested_solver backend_version derivative_method} {
                if {[dict get $receipt $key] ne [dict get $parent $key]} {_error "Multistart trials changed common solver policy $key"}
            }
            if {[_get $receipt orthogonal_xy {}] ne [_get $parent orthogonal_xy {}]} {_error {Multistart trials changed the orthogonal XY geometry}}
            if {[dict get $receipt max_seconds]>[dict get $multi max_seconds]} {_error {Trial time limit exceeds the overall limit}}
            incr attempted;incr completed
            set ok [dict get $receipt converged];if {$ok} {incr converged}
            set objective [dict get $receipt solver_objective]
            if {[_finite $objective]&&$objective>=0&&($best==0||($ok&&!$bestConverged)||($ok==$bestConverged&&$objective<$bestObjective))} {set best $index;set bestObjective $objective;set bestConverged $ok}
        } elseif {$status in {error not_run_time_limit}} {
            _keys $trial {index initial_parameters status message} multistart_trial
            if {$message eq {}} {_error {Unsuccessful multistart trial needs a reason}}
            if {$status eq "error"} {if {$stopped} {_error {Trial executed after the time limit}};incr errors;incr attempted} else {set stopped 1}
        } else {_error {Unknown multistart trial status}}
    }
    foreach {key actual} [list attempted_count $attempted completed_count $completed error_count $errors converged_count $converged selected_index $best] {
        if {[dict get $multi $key]!=$actual} {_error "Multistart $key differs from actual trial outcomes"}
    }
    if {$best==0} {_error {Multistart selected no finite candidate}}
    if {$stopped&&[dict get $multi elapsed_seconds]<[dict get $multi max_seconds]} {_error {Unattempted starts lack an expired overall limit}}
    set chosen [lindex [dict get $multi trials] [expr {$best-1}]]
    foreach parameter $parameters value [dict get $chosen parameters] {if {[dict get $parameter value]!=$value} {_error {Selected multistart parameters differ from the returned fit}}}
    dict for {key value} [dict get $chosen solver_receipt] {if {[dict get $parent $key] ne $value} {_error "Selected trial differs from the returned solver receipt: $key"}}
}
proc ::GX::StatisticsV1::solverReport {result {details 0}} {
    validate $result
    if {![string is boolean -strict $details]} {_error {Solver report details must be boolean}}
    set solver [dict get $result solver]
    if {[dict get $solver status] ne "value"} {return "Solver status: unavailable — [dict get $solver reason]"}
    set lines {}
    if {$details} {lappend lines "Solver: [dict get $solver method]" "Convergence: [expr {[dict get $solver converged] ? {reported} : {not reached}}]"}
    if {![dict exists $solver diagnostics]} {
        if {[dict exists $result provenance smoothing]} {
            lappend lines {The smoothing system was solved. A numerical solution does not validate the model or its statistical assumptions.}
        } else {
            lappend lines [expr {[dict get $solver converged] ? {The solver reports completion. Detailed stopping reason was not recorded; inspect model suitability and residuals.} : {The solver did not report convergence. Detailed stopping reason was not recorded.}}]
        }
        return [join $lines \n]
    }
    if {[dict get $solver diagnostics schema] eq "gxtxt.callback_solver_receipt.v1"} {return [_callbackSolverReport $solver $details]}
    lappend lines [dict get $solver reason]
    set receipt [dict get $solver diagnostics]
    if {[dict exists $receipt orthogonal_xy]} {
        set geometry [dict get $receipt orthogonal_xy]
        lappend lines "XY uncertainty fit: [dict get $geometry nuisance_parameter_count] latent coordinates; independent absolute uncertainties on both axes."
        lappend lines {The objective is the sum of squared normalized coordinate corrections. Local parameter covariance eliminates the fitted latent coordinates; ordinary response R squared does not apply.}
    }
    if {$details} {lappend lines "Iteration records (including initial state): [dict get $receipt iterations]"}
    if {[dict exists $receipt multistart]} {
        set multi [dict get $receipt multistart]
        lappend lines "Multistart: [dict get $multi attempted_count]/[dict get $multi requested_count] attempted, [dict get $multi converged_count] converged; selected start [dict get $multi selected_index]."
        lappend lines {The lowest recorded objective among converged trials is selected; this does not certify a global optimum. If none converged, the retained finite result is provisional.}
        if {$details} {
            foreach key {mode generator strategy_version seed next_seed max_seconds elapsed_seconds execution_policy cancellation_policy selection_policy range_lower range_upper} {lappend lines "Multistart $key: [dict get $multi $key]"}
            foreach trial [dict get $multi trials] {
                lappend lines "Start [dict get $trial index]: [dict get $trial status]; initial parameters: [dict get $trial initial_parameters]"
                if {[dict get $trial status] eq "completed"} {
                    set detail [dict get $trial solver_receipt]
                    lappend lines "  [dict get $detail termination]; objective: [dict get $detail solver_objective]; parameters: [dict get $trial parameters]"
                } else {lappend lines "  [dict get $trial message]"}
            }
        }
    }
    if {$details} {
        lappend lines "Backend message: [dict get $receipt solver_message]"
        foreach field {backend_version requested_solver termination strategy derivative_method linear_solver jacobi_scaling threads_used function_evaluations jacobian_evaluations solver_seconds solver_objective function_tolerance gradient_tolerance parameter_tolerance max_iterations max_seconds loss loss_scale parameter_scales initial_parameters lower_bounds upper_bounds fixed_mask} {
            lappend lines "$field: [dict get $receipt $field]"
        }
    }
    return [join $lines \n]
}
