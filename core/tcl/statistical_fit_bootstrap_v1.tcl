# Public inference contract for parameter refits; Numeric owns every draw/refit.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_bootstrapSettings {settings} {
    _keys $settings {method replicates seed confidence max_seconds} bootstrap_settings
    set settings [dict merge {method pairs replicates 1000 seed 1 confidence .95 max_seconds 60} $settings]
    if {[dict get $settings method] ni {pairs residual parametric_gaussian}} {_error {Choose pairs, residual or parametric_gaussian bootstrap}}
    foreach {name lo hi} {replicates 20 10000 seed 1 2147483646} {
        set value [dict get $settings $name]
        if {![_finite $value]||$value!=floor($value)||$value<$lo||$value>$hi} {_error "Bootstrap $name must be an integer from $lo to $hi"}
        dict set settings $name [expr {int($value)}]
    }
    foreach name {confidence max_seconds} {if {![_finite [dict get $settings $name]]} {_error "Bootstrap $name must be finite"}}
    if {[dict get $settings confidence]<=0||[dict get $settings confidence]>=1||[dict get $settings max_seconds]<=0||[dict get $settings max_seconds]>3600} {_error {Bootstrap confidence must lie in (0,1) and time budget in (0,3600] seconds}}
    return $settings
}
proc ::GX::StatisticsV1::bootstrapSettings {{settings {}}} {return [_bootstrapSettings $settings]}
proc ::GX::StatisticsV1::_bootstrapAssumptions {method} {
    set common {{Parameter bootstrap refits the supplied estimator on generated observations; it is distinct from bootstrapping a sample mean or repeatedly drawing from an asymptotic covariance} {Percentile intervals have approximate repeated-sampling coverage conditional on the model and sampling assumptions; they are not posterior credible intervals or simultaneous confidence regions} {All requested replicates must converge with full free-parameter rank and without active-bound events before nominal percentile intervals are available; failed or unfinished trials remain in the audit} {Sequential refits use the recorded isolated random sequence and start from the captured fitted parameters; nonlinear results remain conditional on the recorded local solver and basin} {Finite-replicate tail resolution and degenerate parameter distributions require review; fixed parameters remain fixed declarations rather than estimated uncertainty}}
    switch $method {
        pairs {lappend common {Whole predictor/response/precision rows are sampled together with replacement; observation tuples are assumed independent and identically distributed, and this treats the design as random}}
        residual {lappend common {The design and relative precision pattern are fixed; standardized errors are assumed independent with a common distribution. Centered weighted residuals are scaled to the captured estimated residual standard deviation before sampling}}
        parametric_gaussian {lappend common {The design is fixed and independent Gaussian response errors are simulated. Absolute precisions use their declared variance; relative or unweighted fits use the captured estimated weighted residual scale}}
    }
    return $common
}
proc ::GX::StatisticsV1::bootstrapPlan {source {settings {}}} {
    validate $source;set settings [_bootstrapSettings $settings]
    if {[_get $source schema {}] ne "gxtxt.statistical_result.v1"} {_error {Bootstrap requires one captured fitted statistical result}}
    set context [dict get $source context];set numerical [dict get $source request numerical];set provenance [dict get $source provenance]
    set plan [dict merge [dict create api_id STATISTICAL_FIT_BOOTSTRAP_PLAN_v1 api_version 1 status not_applicable reason {Parameter bootstrap requires a captured scalar response regression with an evaluable fitted model} interval_method percentile interval_policy all_requested_regular_converged source_operation [_get $provenance operation {}] source_model_id [dict get $source model id] coefficient_space [_get $context coefficient_space original_physical] response_unit [dict get $source residual unit] coordinate_space [dict get $source residual coordinate_space] weight_semantics [_get $context weight_semantics unweighted] noise_model [_get $context noise_model unspecified] parameter_ids {} parameter_units {} parameter_roles {} source_parameters {} solver_policy {} model_source_sha256 [_get $provenance model_source_sha256 {}] model_binding_sha256 [_get $provenance model_binding_sha256 {}] observation_signature {} residual_scale NaN simulation_scale_policy none generator park_miller_16807_v1 normal_transform box_muller_pairs_v1 execution_policy sequential_one_thread_per_refit cancellation_policy worker_cancellation_discards_incomplete_result workspace_bytes_max 536870912 resample_values_max 10000000 work_units_max 128000000 assumptions [_bootstrapAssumptions [dict get $settings method]]] $settings]
    if {[dict exists $context smoothing]} {dict set plan status unavailable;dict set plan reason {Independent resampling does not preserve smoothing-induced correlations};return $plan}
    foreach name {n p rank dof} {dict set plan $name [_get $numerical $name {}]}
    dict set plan free_parameter_count [_get $numerical free_parameter_count [_get $numerical p {}]]
    if {[dict get $source model profile] ni {regression nonlinear_regression}||[dict get $plan source_operation] ni {least_squares linear_regression polynomial_fit nonlinear_fit}||[_get $context sample_role training] ne "training"||[_get $context orientation y_of_x] ni {y_of_x x_of_y}||[_get $context fit_geometry vertical_response] ne "vertical_response"} {return $plan}
    foreach name {n p rank dof free_parameter_count} {if {![_finite [dict get $plan $name]]} {dict set plan status unavailable;dict set plan reason "Captured fit lacks $name";return $plan}}
    set n [dict get $plan n];set p [dict get $plan p];set free [dict get $plan free_parameter_count];set reps [dict get $plan replicates]
    if {$n<2||$p<1||$p>128||$free<1||[dict get $plan rank]!=$free||$n>1000000||$n*$reps>10000000||$n*$p*$reps>128000000||80*$n*$p+160*$n+32*$reps*$p+64*$p*$p>536870912} {dict set plan status unavailable;dict set plan reason {Bootstrap requires full free-parameter rank and fits within the recorded row, replicate-work and 512 MiB workspace budgets};return $plan}
    if {[_get $context constraints unknown] ni {none inactive_bounds fixed_parameters}||([dict exists $numerical converged]&&![dict get $numerical converged])} {dict set plan status unavailable;dict set plan reason {Original fit must converge without active or unclassified constraints};return $plan}
    if {[dict get $plan weight_semantics] ni {unweighted relative inverse_variance}||![dict exists $provenance observation_signature]} {dict set plan status unavailable;dict set plan reason {Bootstrap requires the original response/precision signature and declared weight meaning};return $plan}
    dict set plan observation_signature [_fitObservationSignature [dict get $provenance observation_signature]]
    if {![dict exists $plan observation_signature predictors_sha256]} {dict set plan status unavailable;dict set plan reason {Captured fit predates the exact retained-predictor binding required for parameter refits};return $plan}
    foreach parameter [dict get $source parameters] {
        if {![dict exists $parameter value]||![_finite [dict get $parameter value]]} {_error {Bootstrap requires every fitted and fixed parameter value}}
        foreach {sourceKey target} {id parameter_ids unit parameter_units role parameter_roles value source_parameters} {dict lappend plan $target [dict get $parameter $sourceKey]}
    }
    if {[llength [dict get $plan parameter_ids]]!=$p} {_error {Bootstrap parameter identities differ from the fitted count}}
    set scale [dict get $source quantities weighted_residual_standard_deviation]
    if {[dict get $scale status] eq "value"&&[_finite [dict get $scale value]]&&[dict get $scale value]>0} {dict set plan residual_scale [dict get $scale value]}
    set method [dict get $plan method]
    if {$method eq "pairs"} {dict set plan simulation_scale_policy aligned_case_triplets} else {
        if {[_get $context loss linear] ne "linear"} {dict set plan reason {Residual and Gaussian bootstrap require the recorded ordinary response least-squares loss; use case resampling for a supported robust estimator};return $plan}
        if {$method eq "residual"} {
            if {[dict get $plan weight_semantics] eq "inverse_variance"} {dict set plan reason {Residual resampling estimates an error distribution; absolute precisions require explicit Gaussian simulation or case resampling};return $plan}
            dict set plan simulation_scale_policy centered_weighted_residuals_captured_scale
        } elseif {[dict get $plan noise_model] eq "independent_gaussian_known_sigma"&&[dict get $plan weight_semantics] eq "inverse_variance"} {
            dict set plan simulation_scale_policy gaussian_absolute_precision
        } elseif {[dict get $plan noise_model] eq "independent_gaussian_estimated_variance"&&[dict get $plan weight_semantics] in {unweighted relative}} {
            dict set plan simulation_scale_policy gaussian_estimated_relative_scale
        } else {dict set plan reason {Gaussian simulation requires an explicit Gaussian noise assumption consistent with actual absolute or estimated precisions};return $plan}
        if {[dict get $plan simulation_scale_policy] ne "gaussian_absolute_precision"&&![_finite [dict get $plan residual_scale]]} {dict set plan status unavailable;dict set plan reason {This resampling method needs a positive captured residual scale; zero or unidentified noise cannot produce a confidence claim};return $plan}
    }
    if {[dict exists $source request solver_receipt]} {
        set receipt [dict get $source request solver_receipt]
        foreach name {lower_bounds upper_bounds fixed_mask parameter_scales loss loss_scale strategy function_tolerance gradient_tolerance parameter_tolerance max_iterations} {if {[dict exists $receipt $name]} {dict set plan solver_policy $name [dict get $receipt $name]}}
        if {[_get $receipt schema {}] eq "gxtxt.callback_solver_receipt.v1"} {
            foreach name {backend backend_version requested_solver max_function_evaluations} {dict set plan solver_policy $name [dict get $receipt $name]}
        }
    }
    if {[dict exists $provenance polynomial_propagation_basis]} {dict set plan propagation_basis [_polynomialPropagationBasis [dict get $provenance polynomial_propagation_basis] $p 0]}
    dict set plan status value;dict set plan reason {};return $plan
}
proc ::GX::StatisticsV1::_bootstrapFields {} {
    return {schema method source_operation n p free_parameter_count replicates attempted_count successful_count regular_count boundary_count rank_failure_count nonconverged_count nonfinite_count solver_error_count not_completed_count confidence seed next_seed generator normal_transform strategy_version execution_policy cancellation_policy max_seconds elapsed_seconds interval_method interval_policy quantile_definition tail_resolution weight_semantics simulation_scale_policy simulation_scale observation_signature source_parameters parameter_ids source_model_sha256 source_binding_sha256 summary_status summary_message messages parameter_covariance parameter_standard_errors ci_lower ci_upper original_fit_count workspace_bytes_bound}
}
proc ::GX::StatisticsV1::bootstrapInterpretation {source raw} {
    _keys $raw [_bootstrapFields] bootstrap_numeric
    foreach name [_bootstrapFields] {if {![dict exists $raw $name]} {_error "Bootstrap receipt lacks $name"}}
    set settings {};foreach name {method replicates seed confidence max_seconds} {dict set settings $name [dict get $raw $name]}
    set plan [bootstrapPlan $source $settings]
    if {[dict get $plan status] ne "value"} {_error [dict get $plan reason]}
    if {[dict get $raw schema] ne "gxtxt.fit_bootstrap_numeric.v1"||[dict get $raw strategy_version]!=1||[dict get $raw original_fit_count]!=0||[dict get $raw quantile_definition] ne "Hyndman-Fan type 7 linear interpolation"} {_error {Bootstrap must preserve its actual refit, quantile and no-original-refit contract}}
    foreach name {method source_operation generator normal_transform execution_policy cancellation_policy interval_method interval_policy weight_semantics simulation_scale_policy} {if {[dict get $raw $name] ne [dict get $plan $name]} {_error "Bootstrap $name differs from its CORE plan"}}
    foreach name {n p free_parameter_count} {if {![_finite [dict get $raw $name]]||[dict get $raw $name]!=[dict get $plan $name]} {_error "Bootstrap $name differs from the original fit"}}
    set reps [dict get $plan replicates];set p [dict get $plan p];set n [dict get $plan n]
    foreach name {attempted_count successful_count regular_count boundary_count rank_failure_count nonconverged_count nonfinite_count solver_error_count not_completed_count} {
        set value [dict get $raw $name]
        if {![_finite $value]||$value!=floor($value)||$value<0||$value>$reps} {_error "Invalid bootstrap count $name"}
    }
    set failures 0;foreach name {rank_failure_count nonconverged_count nonfinite_count solver_error_count} {set failures [expr {$failures+[dict get $raw $name]}]}
    set success [dict get $raw successful_count];set regular [dict get $raw regular_count];set boundary [dict get $raw boundary_count];set pending [dict get $raw not_completed_count]
    if {$success!=$regular+$boundary||$reps!=$success+$failures+$pending||[dict get $raw attempted_count]<$success+$failures||[dict get $raw attempted_count]>min($reps,$success+$failures+1)} {_error {Bootstrap trial accounting is inconsistent}}
    set next [dict get $raw next_seed]
    if {![_finite $next]||$next!=floor($next)||$next<1||$next>2147483646||![_finite [dict get $raw elapsed_seconds]]||[dict get $raw elapsed_seconds]<0} {_error {Invalid bootstrap sequence or elapsed time}}
    set workspace [dict get $raw workspace_bytes_bound]
    if {![_finite $workspace]||$workspace!=floor($workspace)||$workspace<80*$n*$p+176*$n+32*$reps*$p+64*$p*$p||$workspace>536870912} {_error {Bootstrap workspace receipt is outside its actual bounded shape}}
    if {![_finite [dict get $raw tail_resolution]]||abs([dict get $raw tail_resolution]-($reps-1)*(1-[dict get $plan confidence])/2)>1e-12*max(1,$reps)} {_error {Bootstrap tail-resolution receipt differs from the actual replicate count}}
    set signature [_fitObservationSignature [dict get $raw observation_signature]]
    foreach name {schema encoding response_sha256 weights_sha256 predictors_sha256} {if {![dict exists $signature $name]||[dict get $signature $name] ne [dict get $plan observation_signature $name]} {_error {Bootstrap observations differ from the captured fitted source}}}
    foreach name {n log_weight_sum predictor_count} {if {![dict exists $signature $name]||[dict get $signature $name]!=[dict get $plan observation_signature $name]} {_error {Bootstrap observation shape or precision normalization changed}}}
    foreach {actual expected} {source_model_sha256 model_source_sha256 source_binding_sha256 model_binding_sha256} {if {[dict get $raw $actual] ne [dict get $plan $expected]} {_error {Bootstrap model identity differs from its captured source}}}
    if {[dict get $raw parameter_ids] ne [dict get $plan parameter_ids]||[llength [dict get $raw source_parameters]]!=$p} {_error {Bootstrap parameter order or count changed}}
    foreach actual [dict get $raw source_parameters] expected [dict get $plan source_parameters] {if {![_finite $actual]||$actual!=$expected} {_error {Bootstrap source parameter value changed}}}
    set scale [dict get $raw simulation_scale]
    if {[dict get $plan method] eq "pairs"} {
        if {![string equal -nocase $scale NaN]} {_error {Case resampling must not invent a simulation noise scale}}
    } else {
        set expected [expr {[dict get $plan simulation_scale_policy] eq "gaussian_absolute_precision"?1:[dict get $plan residual_scale]}]
        if {![_finite $scale]||$scale!=$expected||$scale<=0} {_error {Bootstrap noise scale differs from the captured inference plan}}
    }
    if {[dict get $raw summary_status] ni {value insufficient_successful_replicates nonfinite_summary}||[llength [dict get $raw messages]]>8||[string length [dict get $raw summary_message]]>512} {_error {Invalid bounded bootstrap summary status or diagnostics}}
    foreach message [dict get $raw messages] {if {[string length $message]>512} {_error {Bootstrap trial diagnostic is not bounded}}}
    set hasSummary [expr {[dict get $raw summary_status] eq "value"}]
    if {($success<2)!=([dict get $raw summary_status] eq "insufficient_successful_replicates")} {_error {Bootstrap summary availability differs from successful trial count}}
    foreach name {parameter_standard_errors ci_lower ci_upper} {if {[llength [dict get $raw $name]]!=$p} {_error "Bootstrap $name shape differs from parameter identities"}}
    set matrix [dict get $raw parameter_covariance]
    if {[llength $matrix]!=$p} {_error {Bootstrap covariance row count changed}}
    foreach row $matrix {if {[llength $row]!=$p} {_error {Bootstrap covariance column count changed}}}
    set complete [expr {$regular==$reps&&$hasSummary}]
    for {set i 0} {$i<$p} {incr i} {
        for {set j 0} {$j<$p} {incr j} {
            set value [lindex $matrix $i $j]
            if {$hasSummary} {
                if {![_finite $value]||($i==$j&&$value<0)} {_error {Available bootstrap covariance must be finite with nonnegative variances}}
                set mirror [lindex $matrix $j $i]
                if {![_finite $mirror]||abs($value-$mirror)>1e-12*max(abs($value),abs($mirror))} {_error {Bootstrap covariance lost symmetry}}
            } elseif {![string equal -nocase $value NaN]} {_error {Unavailable bootstrap covariance must retain NaN}}
        }
        set se [lindex [dict get $raw parameter_standard_errors] $i]
        if {$hasSummary} {if {![_finite $se]||$se<0} {_error {Available bootstrap standard errors must be finite and nonnegative}}} elseif {![string equal -nocase $se NaN]} {_error {Unavailable bootstrap standard errors must retain NaN}}
        set lower [lindex [dict get $raw ci_lower] $i];set upper [lindex [dict get $raw ci_upper] $i]
        if {$complete} {if {![_finite $lower]||![_finite $upper]||$lower>$upper} {_error {Completed bootstrap percentile bounds must be finite and ordered}}} elseif {![string equal -nocase $lower NaN]||![string equal -nocase $upper NaN]} {_error {Failed, boundary or unfinished trials cannot silently produce nominal confidence intervals}}
    }
    set reason {};set status value
    if {!$complete} {set status unavailable;set reason {Nominal intervals require every requested refit to converge with full free rank, no active-bound events and a finite summary}}
    set rows {};set index 0
    foreach id [dict get $plan parameter_ids] unit [dict get $plan parameter_units] role [dict get $plan parameter_roles] estimate [dict get $plan source_parameters] {
        set rowStatus $status;set rowReason $reason
        if {$role eq "fixed"} {set rowStatus not_applicable;set rowReason {This parameter was held fixed; bootstrap does not estimate its uncertainty}} elseif {$complete&&[lindex [dict get $raw parameter_standard_errors] $index]==0} {set rowStatus undefined;set rowReason {The empirical parameter distribution is degenerate; a zero-width interval is not a demonstrated confidence claim}}
        set lower NaN;set upper NaN
        if {$rowStatus eq "value"} {set lower [lindex [dict get $raw ci_lower] $index];set upper [lindex [dict get $raw ci_upper] $index]}
        lappend rows [dict create id $id unit $unit role $role estimate $estimate standard_error [lindex [dict get $raw parameter_standard_errors] $index] interval_status $rowStatus interval_reason $rowReason confidence [dict get $plan confidence] lower $lower upper $upper]
        incr index
    }
    set warnings {}
    if {[dict get $raw tail_resolution]<1} {lappend warnings {The requested quantiles use extreme boundary order statistics; these finite-replicate intervals are unreliable}}
    if {!$complete&&$hasSummary} {lappend warnings {Covariance and standard errors describe successful replicates only; they do not replace the unavailable nominal intervals}}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.regression_bootstrap_interpretation.v1 request [dict create source_request [dict remove [dict get $source request] parameter_uncertainty] numeric $raw] plan $plan status $status reason $reason parameters $rows covariance [dict create status [expr {$hasSummary?"value":"unavailable"}] value $matrix population successful_replicates_only parameter_ids [dict get $plan parameter_ids] parameter_units [dict get $plan parameter_units]] assumptions [dict get $plan assumptions] warnings $warnings]
}
proc ::GX::StatisticsV1::_bootstrapReinterpret {request} {
    _keys $request {source_request numeric} bootstrap_request
    return [bootstrapInterpretation [interpret [dict get $request source_request]] [dict get $request numeric]]
}
# Typed equality permits equivalent binary64 spellings across Tcl/Python/Octave.
# Identifiers, units, policy strings and field sets remain exact; no tolerance or
# inference is introduced by this transport comparison.
proc ::GX::StatisticsV1::_bootstrapCompare {kind expected actual} {
    if {$kind eq "number"} {
        if {[string equal -nocase $expected NaN]&&[string equal -nocase $actual NaN]} {return}
        if {[catch {expr {double($expected)==double($actual)}} same]||!$same} {_error {Bootstrap numerical field differs from CORE interpretation}}
        return
    }
    if {$kind in {vector matrix parameters}} {
        if {[llength $expected]!=[llength $actual]} {_error "Bootstrap $kind shape changed"}
        set child [dict get {vector number matrix vector parameters parameter} $kind]
        foreach e $expected a $actual {_bootstrapCompare $child $e $a};return
    }
    set numeric {};set vectors {};set matrices {};set nested {}
    switch $kind {
        plan {set numeric {api_version n p rank dof free_parameter_count replicates seed confidence max_seconds residual_scale workspace_bytes_max resample_values_max work_units_max};set vectors {source_parameters};set nested {solver_policy solver_policy observation_signature signature propagation_basis basis}}
        parameter {set numeric {estimate standard_error confidence lower upper}}
        covariance {set matrices {value}}
        signature {set numeric {n log_weight_sum response_offset predictor_count}}
        solver_policy {set numeric {loss_scale function_tolerance gradient_tolerance parameter_tolerance max_iterations max_function_evaluations};set vectors {lower_bounds upper_bounds fixed_mask parameter_scales}}
        basis {set numeric {query_center query_scale};set vectors {source_parameters};set matrices {source_covariance}}
        default {_error {Unknown bootstrap comparison contract}}
    }
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error "Bootstrap $kind fields changed"}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in $numeric&&$value ne {}} {_bootstrapCompare number $value $other} elseif {$key in $vectors} {_bootstrapCompare vector $value $other} elseif {$key in $matrices} {_bootstrapCompare matrix $value $other} elseif {[dict exists $nested $key]} {_bootstrapCompare [dict get $nested $key] $value $other} elseif {$value ne $other} {_error "Bootstrap $kind field '$key' differs from CORE interpretation"}
    }
}
proc ::GX::StatisticsV1::_bootstrapReport {result} {
    validate $result;set raw [dict get $result request numeric];set plan [dict get $result plan]
    set lines [list "Parameter bootstrap: [dict get $plan method]; [dict get $result status]" "Requested [dict get $raw replicates]; successful [dict get $raw successful_count]; regular [dict get $raw regular_count]; boundary [dict get $raw boundary_count]; not completed [dict get $raw not_completed_count]" "Rank failures [dict get $raw rank_failure_count]; nonconverged [dict get $raw nonconverged_count]; nonfinite [dict get $raw nonfinite_count]; solver errors [dict get $raw solver_error_count]" "Percentile confidence [dict get $plan confidence]; seed [dict get $raw seed]; generator [dict get $raw generator]; next seed [dict get $raw next_seed]"]
    if {[dict get $result reason] ne {}} {lappend lines [dict get $result reason]}
    lappend lines "Parameter coordinates: [dict get $plan coefficient_space]; response residual coordinates: [dict get $plan coordinate_space] ([dict get $plan response_unit])"
    lappend lines "Finite-replicate tail resolution: [dict get $raw tail_resolution] order-statistic positions per requested tail; increasing replicates reduces Monte Carlo quantile error, without correcting invalid sampling assumptions"
    foreach row [dict get $result parameters] {lappend lines "[dict get $row id] ([dict get $row unit]): estimate [dict get $row estimate]; bootstrap SE [dict get $row standard_error]; interval [dict get $row interval_status] \[[dict get $row lower], [dict get $row upper]\] [dict get $row interval_reason]"}
    return [join [concat $lines [dict get $result warnings] [dict get $result assumptions]] \n]
}
proc ::GX::StatisticsV1::_bootstrapDataFields {result} {
    set plan [dict get $result plan];set shape [list [dict get $plan replicates] [dict get $plan p]]
    set fields [dict create parameter_samples [dict create label {Bootstrap parameter draws} kind matrix value_kind real shape $shape unit per_parameter parameter_ids [dict get $plan parameter_ids] parameter_units [dict get $plan parameter_units] definition {One attempted resampling trial per row, in recorded sequence order; failed or unfinished trials retain NaN, and fixed columns retain their declared values} nonfinite_status unavailable nonfinite_reason {The corresponding refit did not yield a finite full-rank converged result}]]
    dict set fields replicate_status [dict create label {Bootstrap replicate status} kind vector value_kind integer unit 1 shape [list [dict get $plan replicates] 1] minimum 0 maximum 7 definition {0 not attempted; 1 regular converged; 2 rank failure; 3 nonconverged; 4 nonfinite or changed fixed value; 5 solver error; 6 converged at an active bound; 7 generated sample stopped at the time budget}]
    dict set fields replicate_seed [dict create label {Bootstrap trial seed} kind vector value_kind integer unit 1 shape [list [dict get $plan replicates] 1] minimum 0 maximum 2147483646 definition {Park-Miller state before generating this trial; zero marks a trial not attempted}]
    return $fields
}
