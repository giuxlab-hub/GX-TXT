# SPDX-License-Identifier: GPL-3.0-or-later
# Existing statistical-owner variants. The public owner validates scientific
# meaning; these declarations preserve each field, lexical value and ordering.
proc ::GX::_workspaceStatisticsRecord {name fields} {
    nativeWorkspaceShapeRegister $name [list record [dict merge {api_id text api_version int schema text} $fields]]
}
proc ::GX::WorkspaceStatistics::optionalResultEncode {result} {
    if {$result eq {}} {return {object {}}}
    return [resultEncode $result]
}
proc ::GX::WorkspaceStatistics::optionalSolverEncode {receipt} {
    if {$receipt eq {}} {return {object {}}}
    return [solverEncode $receipt]
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::optionalResultEncode ::GX::nativeWorkspaceScientificDecode
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::optionalSolverEncode ::GX::nativeWorkspaceScientificDecode
::GX::nativeWorkspaceShapeRegister statistical_optional_result {codec ::GX::WorkspaceStatistics::optionalResultEncode}
::GX::_workspaceStatisticsRecord statistical_solver_policy_subset {
    lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real} parameter_scales {array real}
    loss text loss_scale real strategy text function_tolerance real gradient_tolerance real parameter_tolerance real max_iterations real
    backend text backend_version text requested_solver text max_function_evaluations real
}
::GX::_workspaceStatisticsRecord statistical_column_meaning {label text value_kind text unit text definition text quantity text role text status text reason text axis text axes text}
::GX::_workspaceStatisticsRecord statistical_profile {
    status text reason text parameter_id text unit text source_operation text source_model_id text coefficient_space text response_unit text weight_semantics text noise_model text
    objective text threshold_distribution text threshold_method text interval_policy text execution_policy text model_source_sha256 text model_binding_sha256 text
    source_model_sha256 text source_binding_sha256 text ledger_sha256 text
    confidence real search_lower real search_upper real initial_step real parameter_tolerance real max_seconds real estimate real
    max_refits int original_fit_count int n real p real free_parameter_count real parameter_index int workspace_bytes_max int work_units_max int
    attempted_count int successful_count int failed_count int workspace_bytes_bound int baseline_improved bool baseline_sse scientific_real threshold scientific_real elapsed_seconds real
    source_parameters {array real} parameter_ids {array text} parameter_units {array text} parameter_roles {array text} assumptions {array text}
    solver_policy {named statistical_solver_policy_subset} observation_signature {named statistical_observation_signature}
    settings {named statistical_profile} plan {named statistical_profile} interval {named statistical_profile} lower {named statistical_profile} upper {named statistical_profile}
    value scientific_real searched_value scientific_real likelihood_ratio scientific_real bracket_inside scientific_real bracket_outside scientific_real message text
    request {record {source_request {named statistical_request} numeric {named statistical_profile}}}
}
::GX::nativeWorkspaceShapeRegister gxtxt.fit_profile_interpretation.v1 {named statistical_profile}
::GX::_workspaceStatisticsRecord statistical_bootstrap_settings {method text replicates int seed int confidence real max_seconds real}
::GX::_workspaceStatisticsRecord statistical_bootstrap_plan {
    method text replicates int seed int confidence real max_seconds real status text reason text interval_method text interval_policy text source_operation text source_model_id text
    coefficient_space text response_unit text coordinate_space text weight_semantics text noise_model text model_source_sha256 text model_binding_sha256 text simulation_scale_policy text
    generator text normal_transform text execution_policy text cancellation_policy text
    n {number_or_symbol {{}}} p {number_or_symbol {{}}} rank {number_or_symbol {{}}} dof {number_or_symbol {{}}} free_parameter_count {number_or_symbol {{}}}
    workspace_bytes_max int resample_values_max int work_units_max int residual_scale scientific_real
    parameter_ids {array text} parameter_units {array text} parameter_roles {array text} assumptions {array text} source_parameters {array real}
    solver_policy {named statistical_solver_policy_subset} observation_signature {named statistical_observation_signature} propagation_basis {named statistical_polynomial_basis}
}
::GX::_workspaceStatisticsRecord statistical_bootstrap_numeric {
    method text source_operation text generator text normal_transform text execution_policy text cancellation_policy text interval_method text interval_policy text quantile_definition text
    weight_semantics text simulation_scale_policy text source_model_sha256 text source_binding_sha256 text summary_status text summary_message text
    n int p int free_parameter_count int replicates int attempted_count int successful_count int regular_count int boundary_count int rank_failure_count int nonconverged_count int
    nonfinite_count int solver_error_count int not_completed_count int seed int next_seed int strategy_version int original_fit_count int workspace_bytes_bound int
    confidence real max_seconds real elapsed_seconds real tail_resolution real simulation_scale scientific_real observation_signature {named statistical_observation_signature}
    source_parameters {array real} parameter_standard_errors {array scientific_real} ci_lower {array scientific_real} ci_upper {array scientific_real} parameter_ids {array text} messages {array text}
    parameter_covariance {array {array scientific_real}}
}
::GX::_workspaceStatisticsRecord gxtxt.regression_bootstrap_interpretation.v1 {
    status text reason text request {record {source_request {named statistical_request} numeric {named statistical_bootstrap_numeric}}} plan {named statistical_bootstrap_plan}
    parameters {array {record {id text unit text role text interval_status text interval_reason text estimate scientific_real standard_error scientific_real confidence real lower scientific_real upper scientific_real}}}
    covariance {record {status text population text value {array {array scientific_real}} parameter_ids {array text} parameter_units {array text}}} assumptions {array text} warnings {array text}
}
::GX::_workspaceStatisticsRecord statistical_influence_plan {status text reason text response_unit text coordinate_space text weight_semantics text
    n {number_or_symbol {{}}} p {number_or_symbol {{}}} rank {number_or_symbol {{}}} dof {number_or_symbol {{}}} assumptions {array text}}
::GX::_workspaceStatisticsRecord statistical_influence_numeric {
    method text weight_semantics text scale_method text row_identity text n int p int rank int dof int input_count int leverage_roundoff_count int deletion_available_count int scaled_available_count int
    high_leverage_count int high_cook_count int fit_count int block_rows int residual_scale scientific_real near_one_tolerance real maximum_leverage real leverage_sum real maximum_cook_distance scientific_real
    leverage_review_threshold real cook_review_threshold real factorization_reused bool
}
::GX::_workspaceStatisticsRecord gxtxt.regression_influence_interpretation.v1 {row_count int plan {named statistical_influence_plan} columns {map {named statistical_column_meaning}}
    assumptions {array text} request {record {source_request {named statistical_request} numeric {named statistical_influence_numeric}}}}
::GX::_workspaceStatisticsRecord statistical_sequence_context {residual_unit text coordinate_space text population text order_label text residual_convention text source_sha256 text}
::GX::_workspaceStatisticsRecord statistical_sequence_numeric {
    numeric_api text operation text nonfinite_policy text ordering text key_storage_class text tie_policy text input_residual_sha256 text input_order_sha256 text ordered_residual_sha256 text
    ordered_keys_sha256 text sign_zero_policy text runs_reference text runs_continuity_correction text durbin_watson_definition text autocorrelation_definition text
    input_count int n int omitted_count int tie_count int positive_count int negative_count int zero_count int runs int work_units int
    generated_input_positions bool constant_sequence bool zero_sequence bool p_values_computed bool runs_expected scientific_real runs_variance scientific_real runs_z scientific_real durbin_watson scientific_real
    lags {array real} lag_pair_count {array real} autocorrelation {array scientific_real}
}
::GX::_workspaceStatisticsRecord gxtxt.residual_sequence_interpretation.v1 {row_count int metrics {map {record {label text unit text definition text status text reason text value scientific_real}}}
    autocorrelation_label text autocorrelation_unit text assumptions {array text} request {record {numeric {named statistical_sequence_numeric} context {named statistical_sequence_context}}}}
::GX::_workspaceStatisticsRecord statistical_digitization_summary {
    numeric_api text operation text mode text pixel_distribution text propagation text source_linearization_sha256 text rationale text state_sha256 text point_count int calibration_input_count int
    coordinate_units {array text} has_shared_calibration bool has_xy_correlation bool maximum_absolute_xy_correlation real correlation_roundoff_tolerance real
}
::GX::_workspaceStatisticsRecord gxtxt.digitization_interpretation.v1 {status text summary {named statistical_digitization_summary}
    context {record {source_document_id text source_document_sha256 text source_dataset_id text source_sha256 text row_identity text point_ids_sha256 text}}
    columns {map {named statistical_column_meaning}} assumptions {array text}}
::GX::_workspaceStatisticsRecord gxtxt.digitization_fit_plan.v1 {status text reason text kind text orientation text response_axis text predictor_axis text source_state_sha256 text source_linearization_sha256 text assumptions {array text}}
::GX::_workspaceStatisticsRecord statistical_gls_context {response_unit text covariance_unit text noise_model text design_label text parameter_ids {array text} parameter_units {array text}}
::GX::_workspaceStatisticsRecord statistical_gls_numeric {
    numeric_api text operation text covariance_semantics text uncertainty_status text singular_policy text whitening_method text covariance_sha256 text effective_covariance_sha256 text
    nonfinite_policy text row_policy text regularization text coefficients {array real} standard_errors {array scientific_real} covariance {array {array scientific_real}} whitened_sequence {named statistical_sequence_numeric}
    observation_count int parameter_count int covariance_rank int covariance_nullity int exact_constraint_rank int stochastic_parameter_count int dof int objective real physical_sse real physical_rmse real
    covariance_scale scientific_real minimum_covariance_eigenvalue real covariance_eigenvalue_cutoff real eigen_relative_tolerance real symmetry_relative_tolerance real constraint_relative_tolerance real
    covariance_asymmetry real exact_constraint_error real exact_constraint_limit real scaled_design_condition real observation_signature {named statistical_observation_signature}
}
proc ::GX::WorkspaceStatistics::glsQuantitiesEncode {quantities} {
    set fields {};dict for {name item} $quantities {
        switch -- $name {
            covariance {set unit {record {row_units {array text} column_units {array text}}};set shape {array {array scientific_real}}}
            standard_errors {set unit {array text};set shape {array scientific_real}}
            n - effective_n - p - dof - objective - physical_rmse {set unit text;set shape scientific_real}
            default {error "Unknown GLS quantity '$name'"}
        }
        dict set fields $name [::GX::nativeWorkspaceEncode [list record [dict create status text kind text label text unit $unit definition text value $shape reason text parameter_ids {array text}]] $item]
    };return [list object $fields]
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::glsQuantitiesEncode ::GX::nativeWorkspaceScientificDecode
::GX::_workspaceStatisticsRecord gxtxt.gls_interpretation.v1 {request {record {numeric {named statistical_gls_numeric} context {named statistical_gls_context}}}
    parameters {array {named statistical_parameter}} quantities {codec ::GX::WorkspaceStatistics::glsQuantitiesEncode} whitened_diagnostics {named gxtxt.residual_sequence_interpretation.v1} assumptions {array text}}
::GX::nativeWorkspaceShapeRegister statistical_gls {named gxtxt.gls_interpretation.v1}
::GX::_workspaceStatisticsRecord statistical_comparison_entry {id text result {named statistical_result} binding {named statistical_observation_binding} numeric {named statistical_selection_numeric}}
::GX::_workspaceStatisticsRecord statistical_nested_plan {
    status text reason text method text reduced_id text full_id text source_id text source_sha256 text rows_sha256 text response_sha256 text weights_sha256 text predictors_sha256 text
    x_variable_id text y_variable_id text x_unit text y_unit text orientation text noise_model text weight_semantics text
    n {number_or_symbol {{}}} reduced_p {number_or_symbol {{}}} full_p {number_or_symbol {{}}} numerator_df {number_or_symbol {{}}} denominator_df {number_or_symbol {{}}}
    reduced_sse {number_or_symbol {{}}} full_sse {number_or_symbol {{}}}
}
::GX::_workspaceStatisticsRecord statistical_nested_numeric {numeric_api text operation text status text reason text plan {named statistical_nested_plan} f_statistic scientific_real p_value scientific_real
    numerator_df real denominator_df real sse_reduction real sse_roundoff_clamped bool}
::GX::_workspaceStatisticsRecord gxtxt.nested_f_interpretation.v1 {status text reason text plan {named statistical_nested_plan}
    quantities {map {record {label text unit text status text reason text definition text value scientific_real}}} assumptions {array text}
    request {record {reduced {named statistical_comparison_entry} full {named statistical_comparison_entry} numeric {named statistical_nested_numeric}}}}
::GX::_workspaceStatisticsRecord gxtxt.model_comparison.v1 {criterion text status text reasons {array text} ranked_ids {array text} assumptions {array text}
    rows {array {record {id text model_id text status text reason text unit text plan {named statistical_selection_plan} value {number_or_symbol {{}}} n {number_or_symbol {{}}}
        free_parameter_count {number_or_symbol {{}}} numeric {named statistical_selection_numeric}}}}
    request {record {entries {array {named statistical_comparison_entry}} criterion text}}}
::GX::_workspaceStatisticsRecord statistical_characteristics {
    numeric_api text operation text status text reason text shape_status text monotonic text period_status text order_policy text nonfinite_policy text purpose text
    observation_count int distinct_predictors int peak_count int trough_count int duplicate_predictors bool positive_predictors bool response_one_sign bool constant_response bool linear_like bool
    periodic_hint bool saturating_hint bool fitted bool accepted bool predictor_minimum scientific_real predictor_maximum scientific_real response_minimum scientific_real response_maximum scientific_real
    period scientific_real tail_slope_ratio scientific_real
    thresholds {record {relative_flat_tolerance real monotonic_fraction real linearity_tolerance real prominence real period_tolerance real saturation_ratio real}}
    observation_signature {named statistical_observation_signature}
}
::GX::_workspaceStatisticsRecord gxtxt.fit_suggestions.v1 {
    comparison_status text comparison_reason text suggested_ids {array text} assumptions {array text}
    suggestions {array {record {id text model_id text label text status text reason text suggested bool priority int options {record {degree int order int period real}}}}}
    comparison {named gxtxt.model_comparison.v1}
    request {record {numeric {named statistical_characteristics} candidates {array {record {id text model_id text label text}}}
        context {record {x_unit text y_unit text orientation text x_variable_id text y_variable_id text observation_binding {named statistical_observation_binding}}}
        entries {array {named statistical_comparison_entry}} criterion text}}
}
::GX::_workspaceStatisticsRecord statistical_physical_rule {id text label text parameter_id text unit text kind text severity text rationale text enabled bool
    lower real upper real lower_inclusive bool upper_inclusive bool maximum_fraction real}
::GX::_workspaceStatisticsRecord gxtxt.physical_plausibility_review.v1 {
    status text assessment text coefficient_space text rule_count int evaluated_count int advisory_count int invalid_domain_count int disabled_count int unavailable_count int
    checks {array {record {rule {named statistical_physical_rule} parameter_role text status text outcome text reason text limits {record {lower real upper real lower_inclusive bool upper_inclusive bool}} value real}}}
    assumptions {array text} request {record {source {named statistical_result} rules {array {named statistical_physical_rule}} context {record {domain {record {minimum real maximum real unit text}}}}}}
}
::GX::_workspaceStatisticsRecord statistical_derived_definition {id text label text expression text unit text constants {array {record {id text unit text value real}}}}
::GX::_workspaceStatisticsRecord statistical_derived_plan {
    source_model_id text coefficient_space text status text reason text parameter_ids {array text} parameter_aliases {array text} parameter_units {array text} parameter_roles {array text}
    parameter_values {array real} free_indices {array int} source_covariance {array {array real}} definitions {array {named statistical_derived_definition}}
}
::GX::_workspaceStatisticsRecord statistical_propagation_numeric {covariance {array {array real}} jacobian {array {array real}} input_covariance {array {array real}}
    standard_uncertainty {array real} input_count int output_count int method text input_kind text}
::GX::_workspaceStatisticsRecord statistical_derived_numeric {
    numeric_api text operation text derivative_method text plan {named statistical_derived_plan} fit_performed bool propagation_indices {array int}
    properties {array {record {id text value_status text reason text source_sha256 text binding_sha256 text value scientific_real derivative_valid bool}}}
    propagation {named statistical_propagation_numeric}
}
::GX::_workspaceStatisticsRecord gxtxt.derived_properties.v1 {
    request {record {source {named statistical_result} numeric {named statistical_derived_numeric}}} plan {named statistical_derived_plan}
    properties {array {record {id text label text expression text unit text constants {array {record {id text unit text value real}}}
        value_status text reason text standard_uncertainty_status text standard_uncertainty_reason text source_sha256 text binding_sha256 text value scientific_real standard_uncertainty real}}}
    propagation {named statistical_optional_result} assumptions {array text}
}
::GX::_workspaceStatisticsRecord statistical_log_plan {status text reason text response_unit text center_role text mean_status text mean_reason text transform {named statistical_response_transform}
    reference real log_standard_deviation {number_or_symbol {{}}} assumptions {array text}}
::GX::_workspaceStatisticsRecord statistical_log_numeric {base text interval_kind text method text n int interval_available_count int reference real
    log_standard_deviation {number_or_symbol {{}}} log_bias_correction {number_or_symbol {{}}} confidence {number_or_symbol {{}}} mean_available bool}
::GX::_workspaceStatisticsRecord gxtxt.log_response_interpretation.v1 {row_count int interval_available_count int confidence {number_or_symbol {{}}}
    plan {named statistical_log_plan} columns {map {named statistical_column_meaning}} assumptions {array text}
    request {record {source_request {named statistical_request} prediction_request {named statistical_request} numeric {named statistical_log_numeric}}}}
