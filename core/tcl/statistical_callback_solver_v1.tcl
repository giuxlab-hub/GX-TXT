# SPDX-License-Identifier: GPL-3.0-or-later
# CORE interpretation of captured Script callback solver facts. No optimization.
proc ::GX::StatisticsV1::_callbackSolverReceipt {receipt parameters numerical context} {
    set fields {schema method requested_solver strategy backend backend_version derivative_method iteration_convention iterations function_evaluations jacobian_evaluations callback_evaluations exitflag converged solver_message solver_seconds solver_objective loss max_function_evaluations function_tolerance gradient_tolerance parameter_tolerance parameter_scales initial_parameters lower_bounds upper_bounds fixed_mask condition_convention scale_convention}
    _keys $receipt $fields callback_solver_receipt
    foreach field $fields {if {![dict exists $receipt $field]} {_error "Callback solver receipt lacks $field"}}
    foreach {field expected} {schema gxtxt.callback_solver_receipt.v1 backend scipy.optimize.least_squares derivative_method forward_finite_difference_free_parameters loss linear condition_convention unit_norm_free_jacobian_columns scale_convention physical_parameter_equals_scaled_parameter_times_scale} {
        if {[dict get $receipt $field] ne $expected} {_error "Unsupported callback solver $field"}
    }
    foreach {field allowed} {method {least_squares fixed_evaluation} requested_solver {auto least_squares scipy_least_squares} strategy {trf dogbox}} {
        if {[dict get $receipt $field] ni $allowed} {_error "Unknown callback solver $field"}
    }
    if {[_get $context solver unspecified] ne [dict get $receipt method]||[_get $context loss linear] ne "linear"||[_get $context fit_geometry vertical_response] ne "vertical_response"} {_error {Callback solver receipt contradicts method, loss or residual geometry}}
    if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.+_-]*$} [dict get $receipt backend_version]]} {_error {Invalid callback backend version}}
    set message [dict get $receipt solver_message]
    if {[string length $message]>8192||[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f]} $message]} {_error {Invalid bounded callback solver message}}
    foreach field {iterations function_evaluations jacobian_evaluations callback_evaluations max_function_evaluations exitflag} {
        set value [dict get $receipt $field]
        if {![_finite $value]||$value!=floor($value)} {_error "Invalid callback solver integer $field"}
    }
    set limit [dict get $receipt max_function_evaluations];set evaluations [dict get $receipt function_evaluations]
    if {$limit<1||$limit>2000000||$evaluations<1||$evaluations>$limit||[dict get $receipt callback_evaluations]<$evaluations||[dict get $receipt jacobian_evaluations]<-1} {_error {Callback solver evaluation counts contradict the recorded budget}}
    set exitflag [dict get $receipt exitflag];set converged [dict get $receipt converged]
    if {$exitflag ni {-1 0 1 2 3 4}||![string is boolean -strict $converged]||$converged!=($exitflag>0)||([dict exists $numerical converged]&&$converged!=[dict get $numerical converged])} {_error {Callback convergence contradicts termination facts}}
    foreach field {function_tolerance gradient_tolerance parameter_tolerance} {
        if {![_finite [dict get $receipt $field]]||[dict get $receipt $field]<=2.220446049250313e-16} {_error "Invalid callback tolerance $field"}
    }
    foreach field {solver_seconds solver_objective} {
        if {![_finite [dict get $receipt $field]]||[dict get $receipt $field]<0} {_error "Invalid callback solver $field"}
    }
    if {[dict exists $numerical sse]&&[dict get $receipt solver_objective]!=[dict get $numerical sse]} {_error {Callback objective differs from the captured weighted SSE}}
    set count [llength $parameters]
    if {$count<1||$count>128} {_error {Callback solver requires one to 128 physical parameters}}
    foreach field {initial_parameters parameter_scales lower_bounds upper_bounds fixed_mask} {
        if {[llength [dict get $receipt $field]]!=$count} {_error "Callback $field differs from canonical parameter order"}
    }
    set free 0
    foreach parameter $parameters initial [dict get $receipt initial_parameters] scale [dict get $receipt parameter_scales] lower [dict get $receipt lower_bounds] upper [dict get $receipt upper_bounds] fixed [dict get $receipt fixed_mask] {
        if {![_finite $initial]||![_finite $scale]||$scale<=0||(![_finite $lower]&&![_infinite $lower -1])||(![_finite $upper]&&![_infinite $upper 1])||$lower>$upper||$initial<$lower||$initial>$upper} {_error {Invalid callback initial parameter, scale or bounds}}
        if {$fixed ni {0 1 0.0 1.0}||($lower==$upper&&!$fixed)} {_error {Invalid callback fixed mask}}
        if {($fixed&&[dict get $parameter role] ne "fixed")||(!$fixed&&[dict get $parameter role] ne "free")} {_error {Callback fixed mask contradicts parameter roles}}
        if {!$fixed} {incr free}
        if {[dict exists $parameter value]} {
            set value [dict get $parameter value]
            if {![_finite $value]||$value<$lower||$value>$upper||($fixed&&$value!=$initial)} {_error {Callback estimate contradicts bounds or fixed value}}
        }
    }
    if {[dict exists $numerical free_parameter_count]&&[dict get $numerical free_parameter_count]!=$free} {_error {Callback free count contradicts parameter roles}}
    if {$free==0} {
        if {[dict get $receipt method] ne "fixed_evaluation"||[dict get $receipt iteration_convention] ne "optimizer_not_invoked"||[dict get $receipt iterations]!=0||$exitflag!=1||$evaluations!=1||[dict get $receipt callback_evaluations]!=1||[dict get $receipt jacobian_evaluations]!=0} {_error {All-fixed callback receipt must describe one evaluation without optimization}}
        set reason {All parameters were fixed. The model was evaluated once; no optimizer or parameter estimation was performed.}
    } else {
        if {[dict get $receipt method] ne "least_squares"||[dict get $receipt iteration_convention] ne "not_reported_by_scipy"||[dict get $receipt iterations]!=-1} {_error {SciPy callback optimizer iterations are unavailable, not its function-evaluation count}}
        set reasons [dict create -1 {The solver rejected its input.} 0 {The function-evaluation limit was reached before convergence.} 1 {The gradient stopping criterion was satisfied.} 2 {The objective-change stopping criterion was satisfied.} 3 {The parameter-step stopping criterion was satisfied.} 4 {Both objective-change and parameter-step stopping criteria were satisfied.}]
        set reason "[dict get $reasons $exitflag] Local stopping does not establish a global optimum or validate the scientific model."
    }
    return [dict create status value converged $converged method [dict get $receipt method] reason $reason diagnostics $receipt]
}
proc ::GX::StatisticsV1::_callbackSolverReport {solver details} {
    set receipt [dict get $solver diagnostics];set lines [list [dict get $solver reason]]
    if {$details} {
        lappend lines "Backend: [dict get $receipt backend] [dict get $receipt backend_version]; strategy: [dict get $receipt strategy]."
        lappend lines "Function evaluations: [dict get $receipt function_evaluations] of [dict get $receipt max_function_evaluations]; actual callback invocations (including numerical Jacobians and final prediction): [dict get $receipt callback_evaluations]."
        if {[dict get $receipt method] eq "least_squares"} {lappend lines {Optimizer iteration count: unavailable from this backend; function evaluations are not iterations.}}
        lappend lines "Backend message: [dict get $receipt solver_message]"
        foreach field {requested_solver derivative_method jacobian_evaluations solver_seconds solver_objective function_tolerance gradient_tolerance parameter_tolerance parameter_scales initial_parameters lower_bounds upper_bounds fixed_mask condition_convention scale_convention} {lappend lines "$field: [dict get $receipt $field]"}
    }
    return [join $lines \n]
}
