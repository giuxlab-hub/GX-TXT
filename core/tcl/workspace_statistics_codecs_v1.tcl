# SPDX-License-Identifier: GPL-3.0-or-later
# Typed projections of the existing CORE statistical contracts. No estimation,
# reinterpretation, hash replacement or scientific resource materialization.
namespace eval ::GX::WorkspaceStatistics {}
::GX::nativeWorkspaceShapeRegister statistical_parameter {record {id text label text unit text role text value real}}
::GX::nativeWorkspaceShapeRegister statistical_observation_binding {record {schema text source_id text source_sha256 text rows_sha256 text}}
::GX::nativeWorkspaceShapeRegister statistical_model {record {id text owner text label text profile text parameter_convention text description text parameter_ids {array text}}}
::GX::nativeWorkspaceShapeRegister statistical_variable_lineage {record {dataset_id text variable_id text source_row int selection_id text}}
::GX::nativeWorkspaceShapeRegister statistical_conditional_units {record {
    schema text model_id text parameter_id text exponent_id text predictor_unit text response_unit text unit_expression text status text
    exponent_status text exponent_role text covariance_basis text reference_magnitude real reason text exponent_value real
}}
set ::GX::WorkspaceStatistics::context {}
foreach field {orientation residual_sign comparison_metric comparison_direction x_unit y_unit z_unit radial_unit x_variable_id y_variable_id weight_unit weight_semantics noise_model constraints covariance_scaling coefficient_space zero_normal_sign_policy sample_role solver method loss sampling_model mean_se_model quantile_definition alternative approximation effect_name ci_status inference mad_scale input_kind input_semantics asd_unit psd_unit power_unit zero_policy averaging peak_policy variance_correction insufficient_policy mode component_method normalization fundamental_mode signal_zero noise_zero window detrend spur_search timing_operation spectral_operation sidedness family link initialization empty_cluster_policy convergence_evidence fit_geometry smoother_predictor_unit smoother_dof_convention} {dict set ::GX::WorkspaceStatistics::context $field text}
foreach field {confidence reference_rms sample_rate fundamental_hz fundamental_bin level_floor component_level_floor} {dict set ::GX::WorkspaceStatistics::context $field real}
foreach field {group_index output_index guard_bins iteration_limit track_harmonics exclude_dc_bins} {dict set ::GX::WorkspaceStatistics::context $field int}
foreach field {has_intercept exclude_dc peak_resolved signal_zero noise_zero} {dict set ::GX::WorkspaceStatistics::context $field bool}
foreach field {assumptions output_ids output_units cluster_ids} {dict set ::GX::WorkspaceStatistics::context $field {array text}}
foreach field {translation regional_fit baseline_correction response_transform smoothing gls implicit complex rational surface knot_spline} {dict set ::GX::WorkspaceStatistics::context $field [list named statistical_$field]}
dict set ::GX::WorkspaceStatistics::context conditional_parameter_units {named statistical_conditional_units}
::GX::nativeWorkspaceShapeRegister statistical_context [list record $::GX::WorkspaceStatistics::context]
unset ::GX::WorkspaceStatistics::context
::GX::nativeWorkspaceShapeRegister statistical_selection_plan {record {
    api_id text api_version int status text reason text observation_status text source_model_id text source_id text source_sha256 text rows_sha256 text
    n {number_or_symbol {{}}} free_parameter_count {number_or_symbol {{}}} weighted_sse {number_or_symbol {{}}} log_weight_sum {number_or_symbol {{}}}
    response_sha256 text weights_sha256 text x_variable_id text y_variable_id text x_unit text y_unit text orientation text noise_model text weight_semantics text scale_model text approximation text
}}
::GX::nativeWorkspaceShapeRegister statistical_selection_numeric {record {numeric_api text operation text plan {named statistical_selection_plan} n real free_parameter_count real likelihood_parameter_count real
    log_likelihood scientific_real aic scientific_real aicc scientific_real bic scientific_real aicc_computed bool variance_mle scientific_real}}
::GX::nativeWorkspaceShapeRegister statistical_polynomial_basis {record {api_id text api_version int kind text source_parameters {array real} source_covariance {array {array real}} query_center real query_scale real}}
::GX::nativeWorkspaceShapeRegister statistical_translation_axis {record {physical_axis text variable_id text unit text mode text delta real margin real original_bounds text transformed_bounds text}}
::GX::nativeWorkspaceShapeRegister statistical_translation {record {version int algorithm text inverse_applied bool orientation text coefficient_space text forward text inverse text residual_space text source_dataset_id text u {named statistical_translation_axis} v {named statistical_translation_axis}}}
::GX::nativeWorkspaceShapeRegister statistical_observation_signature {record {schema text n real encoding text response_sha256 text weights_sha256 text log_weight_sum real response_offset real fit_response_sha256 text predictor_count real predictors_sha256 text}}
::GX::nativeWorkspaceShapeRegister statistical_baseline_correction {record {schema text method text source_dataset_id text source_sha256 text original_y_variable_id text baseline_variable_id text corrected_variable_id text uncertainty_policy text}}
::GX::nativeWorkspaceShapeRegister statistical_smoothing {record {schema text bindings {array {record {variable_id text method text source_dataset_id text source_sha256 text original_y_variable_id text smoothed_variable_id text uncertainty_policy text}}}}}
::GX::nativeWorkspaceShapeRegister statistical_response_transform {record {schema text base text reference real source_dataset_id text source_sha256 text source_variable_id text source_unit text variable_id text inverse_eligible bool inverse_reason text}}
::GX::nativeWorkspaceShapeRegister statistical_regional_fit {record {schema text region_counts {array real} breakpoint_ids {array text} breakpoint_values {array real} breakpoint_fixed {array real} continuity {array text} sample_coincidence_counts {array real}}}
::GX::nativeWorkspaceShapeRegister statistical_smoothing_receipt {record {
    schema text solver text trace_method text precision text workspace_bytes_bound int
    smoothing_selection {record {method text evaluations int criterion text selected_lambda real selected_edf real selected_gcv scientific_real boundary_optimum bool lambda_bounds {array real}
        grid_count int refinement_budget int candidate_columns {array text} candidates {array {array real}} guarantee text}}
}}
::GX::nativeWorkspaceShapeRegister statistical_knot_spline {record {schema text numeric_api text model text method_class text degree int continuity_order int boundary_condition text knot_count int domain {array real} source_count int basis_dimension int state_sha256 text predictor_unit text response_unit text inference_scope text}}
::GX::nativeWorkspaceShapeRegister statistical_implicit {record {
    schema text numeric_api text operation text declaration_sha256 text residual_mode text residual_unit text objective_unit_rule text normalization {record {value real unit text role text}}
    fit_geometry text residual_definition text measurement_error_distance bool observation_count int parameter_ids {array text} parameter_units {array text} predictor_ids {array text} predictor_units {array text}
    equation_source_sha256 text equation_binding_sha256 text response_branch text uncertainty_scope text normalization_is_measurement_sigma bool
}}
::GX::nativeWorkspaceShapeRegister statistical_complex {record {
    schema text numeric_api text operation text declaration_sha256 text parameter_ids {array text} parameter_units {array text} channel_ids {array text} channel_units {array text}
    component_ids {array text} component_units {array text} component_order text predictor_id text predictor_unit text observation_rows int response_count int residual_component_count int
    covariance_semantics text covariance_layout text covariance_sha256 text effective_covariance_sha256 text whitening text independence text objective text phase_policy text
    physical_predictor_sha256 text physical_observation_sha256 text normalized_formula_source_sha256 text normalized_formula_binding_sha256 text regularization text uncertainty_scope text
}}
::GX::nativeWorkspaceShapeRegister statistical_rational_domain {record {
    schema text status text reason text domain {array real} coordinate_unit text denominator_constant real numerator_degree int denominator_degree int
    denominator_coefficients_descending {array real} denominator_coefficient_bound real relative_margin_lower_bound real pole_tolerance real interval_nodes int method text root_method text
    poles_real_imag {array {array real}} possible_common_factor bool cancellation_policy text parameters {array real} declaration_sha256 text source_sha256 text binding_sha256 text
}}
::GX::nativeWorkspaceShapeRegister statistical_rational {record {schema text numeric_api text operation text domain_receipt {named statistical_rational_domain} observation_domain {array real}
    parameter_ids {array text} parameter_units {array text} predictor_unit text response_unit text fit_geometry text normalization text approximation text inference_scope text evaluation_count real evaluation_domain {array real}}}
::GX::nativeWorkspaceShapeRegister statistical_surface_observations {record {
    schema text layout text original_shape {array int} original_count int retained_count int nonfinite_count int nonfinite_policy text source_linear_index_base int source_linear_order text
    duplicate_policy text sorting_performed bool interpolation_performed bool original_xy_sha256 text original_z_sha256 text
}}
::GX::nativeWorkspaceShapeRegister statistical_surface {record {
    schema text numeric_api text operation text declaration_sha256 text formula_source_sha256 text formula_binding_sha256 text predictor_ids {array text} predictor_units {array text}
    response_id text response_unit text parameter_ids {array text} parameter_units {array text} observation_receipt {named statistical_surface_observations}
    retained_xy_sha256 text retained_z_sha256 text source_indices_sha256 text observation_domain {record {bounds {array {array real}} meaning text}}
    fit_geometry text predictor_error_model text interpolation_performed bool uncertainty_scope text
}}
::GX::nativeWorkspaceShapeRegister statistical_provenance {record {
    numeric_api text operation text producer text source_variables {array {named statistical_variable_lineage}} selection_id text dataset_binding {map text}
    source_identity {codec ::GX::WorkspaceStatistics::sourceIdentityEncode} source_selection {array text} finite_scalar_policy text signal_operation text table_row_id text
    model_source_sha256 text model_binding_sha256 text sampling_seed int random_generator text numeric_backend text numeric_backend_version text group_name text
    reduction_input_shape {array int} reduction_output_shape {array int} reduction_requested_dimension int reduction_nan_policy text reduction_dimension int
    native_api text reduction_binding text method text sampling_policy text
    reference_vertices int target_vertices int reference_samples int target_samples int reference_tessellated bool target_tessellated bool projection_policy text extrema_policy text
    tessellation {record {sample_budget int linear_deflection real angular_deflection real weld_tolerance real max_triangles int max_output_bytes int}} coordinate_space text plane {record {origin {array real} normal {array real} u_axis {array real}}} section_tolerance real display_rows int display_is_scientific_data bool max_source_index int
    reference text target text evaluated_representation {map {record {representation text evaluation text}}} coordinate_frame {named native_comparison_frame}
    count_a int count_b int sample_budget int sampling_a text sampling_b text projection_exact_a bool projection_exact_b bool policy text
    observation_signature {named statistical_observation_signature} physical_observation_signature {named statistical_observation_signature}
    polynomial_propagation_basis {named statistical_polynomial_basis} smoothing {named statistical_smoothing_receipt}
    prediction_source_request {named statistical_request} prediction_plan {named statistical_prediction_plan} model_evaluation_kind text
    binding_resource {resource {named resource_metadata}} binding_row_start int
    analysis_id text study_design text correspondence text training_fit_geometry text
    complex_binding {named fitter_complex_binding} covariance_binding {named fitter_covariance_binding} measurement_binding {named fitter_measurement_binding} measurement_selection {named fitter_measurement_selection}
}}
proc ::GX::WorkspaceStatistics::sourceIdentityEncode {identity} {
    if {$identity eq {explicit_point_input}} {return [list text $identity]}
    return [::GX::nativeWorkspaceEncode {named fitter_source_provenance} $identity]
}
::GX::nativeWorkspaceShapeRegister statistical_inference_plan {record {
    api_id text api_version int status text reason text confidence real source_model_id text coefficient_space text parameter_ids {array text} parameter_units {array text}
    source_parameters {array real} source_covariance {array {array real}} degrees_of_freedom {number_or_symbol {{}}} distribution text approximation text interval_status text interval_reason text
    polynomial_basis {named statistical_polynomial_basis}
}}
::GX::nativeWorkspaceShapeRegister statistical_prediction_plan {record {
    api_id text api_version int kind text status text reason text parameter_plan {named statistical_inference_plan} all_parameter_ids {array text} all_parameter_values {array real} free_parameter_indices {array int}
    response_unit text orientation text source_operation text model_source_sha256 text model_binding_sha256 text observation_noise_policy text observation_scale {number_or_symbol {{}}} critical_value {number_or_symbol {{}}}
    coverage text assumption text fit_geometry text propagation_basis {named statistical_polynomial_basis}
}}
::GX::nativeWorkspaceShapeRegister statistical_parameter_uncertainty_numeric {record {numeric_api text operation text plan {named statistical_inference_plan} correlation {array {array real}} lower {array real} upper {array real} critical_value real}}
::GX::nativeWorkspaceShapeRegister statistical_parameter_uncertainty_request {record {confidence real numeric {named statistical_parameter_uncertainty_numeric}}}
::GX::nativeWorkspaceShapeRegister statistical_parameter_uncertainty {record {
    api_version int parameter_ids {array text} parameter_units {array text} coefficient_space text
    correlation {record {status text reason text unit text value {array {array real}}}}
    intervals {record {status text reason text confidence real distribution text approximation text coverage text lower {array real} upper {array real} critical_value real}}
    provenance {record {numeric_api text operation text}}
}}
::GX::nativeWorkspaceShapeRegister statistical_numeric_solver {record {
    schema text method text requested_solver text backend_version text derivative_method text termination text solver_message text
    converged bool jacobi_scaling bool iterations int function_evaluations int jacobian_evaluations int threads_used int max_iterations int
    solver_seconds real solver_objective scientific_real function_tolerance real gradient_tolerance real parameter_tolerance real max_seconds real loss_scale real
    parameter_scales {array real} initial_parameters {array real} lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real}
    strategy text loss text linear_solver text iteration_convention text multistart {named statistical_multistart}
    orthogonal_xy {record {schema text nuisance_parameter_count int residual_component_count int jacobian_convention text sigma_semantics text}}
}}
::GX::nativeWorkspaceShapeRegister statistical_multistart {record {
    schema text mode text requested_count int seed int next_seed int generator text strategy_version int initials {array {array real}} range_lower {array real} range_upper {array real}
    max_seconds real execution_policy text cancellation_policy text selection_policy text selected_index int converged_count int attempted_count int completed_count int error_count int elapsed_seconds real
    trials {array {record {index int initial_parameters {array real} status text message text parameters {array real} solver_receipt {named statistical_numeric_solver}}}}
}}
::GX::nativeWorkspaceShapeRegister statistical_callback_solver {record {
    schema text method text requested_solver text strategy text backend text backend_version text derivative_method text iteration_convention text
    iterations real function_evaluations real jacobian_evaluations real callback_evaluations real exitflag real converged bool solver_message text solver_seconds real solver_objective scientific_real
    loss text max_function_evaluations int function_tolerance real gradient_tolerance real parameter_tolerance real parameter_scales {array real} initial_parameters {array real}
    lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real} condition_convention text scale_convention text
}}
::GX::nativeWorkspaceShapeRegister statistical_solver_receipt {codec ::GX::WorkspaceStatistics::solverEncode}
proc ::GX::WorkspaceStatistics::solverEncode {receipt} {
    switch -- [dict get $receipt schema] {
        gxtxt.numeric_solver_receipt.v1 {set shape statistical_numeric_solver}
        gxtxt.callback_solver_receipt.v1 {set shape statistical_callback_solver}
        default {error {Unsupported statistical solver receipt schema}}
    }
    return [::GX::nativeWorkspaceEncode [list named $shape] $receipt]
}
proc ::GX::WorkspaceStatistics::numericalShape {facts} {
    set fields {};set catalog [::GX::StatisticsV1::quantities]
    dict for {field value} $facts {
        if {$field in {quantile_probabilities harmonic_orders}} {set shape {array scientific_real}
        } elseif {$field eq {converged}} {set shape bool
        } elseif {[dict exists $catalog $field]} {set shape [dict get {scalar scientific_real vector {array scientific_real} matrix {array {array scientific_real}}} [dict get $catalog $field kind]]
        } elseif {$field in {p free_parameter_count response_variance distribution_variance tail_tolerance input_count output_count component_count total_component_variance relative_floor}} {set shape scientific_real
        } else {error "Undeclared statistical numerical fact '$field'"}
        dict set fields $field $shape
    };return [list record $fields]
}
proc ::GX::WorkspaceStatistics::numericalEncode {facts} {tailcall ::GX::nativeWorkspaceEncode [numericalShape $facts] $facts}
::GX::nativeWorkspaceShapeRegister statistical_request {record {
    model_id text context {named statistical_context} numerical {codec ::GX::WorkspaceStatistics::numericalEncode} provenance {named statistical_provenance}
    parameters {array {named statistical_parameter}} parameter_uncertainty {named statistical_parameter_uncertainty_request} solver_receipt {named statistical_solver_receipt}
}}
proc ::GX::WorkspaceStatistics::quantityShape {name item context} {
    set definition [dict get [::GX::StatisticsV1::quantities] $name]
    if {[dict get $item kind] ne [dict get $definition kind]} {error {Statistical quantity differs from its public kind}}
    set numeric [dict get {scalar scientific_real vector {array scientific_real} matrix {array {array scientific_real}}} [dict get $definition kind]]
    set unit text
    switch -- [dict get $definition unit] {
        coordinate_columns {set unit {record {column_units {array text}}}}
        parameter_products - output_products {set unit {record {row_units {array text} column_units {array text}}}}
        parameter_units - output_units {set unit {array text}}
        squared_response - cubic_predictor {set unit {tuple {text text int}}}
        covariance_eigen_unit {
            set units [::GX::datasetPublicationV2DictDefault $context output_units {}]
            if {[llength $units] && [llength [lsort -unique $units]]==1 && [lindex $units 0] ni {{} unspecified}} {set unit {tuple {text text int}}}
        }
        spectral_weight {if {[::GX::datasetPublicationV2DictDefault $context input_semantics {}] eq {amplitude}} {set unit {tuple {text text int}}}}
        weight - weighted_sum {if {[::GX::datasetPublicationV2DictDefault $context weight_semantics unweighted] eq {inverse_variance}} {set unit {tuple {text text int}}}}
    }
    if {$name eq {sse} && ([dict exists $context gls] || [dict exists $context complex] || [::GX::datasetPublicationV2DictDefault $context weight_semantics unweighted] eq {inverse_variance})} {set unit {tuple {text text int}}}
    return [list record [dict create status text label text unit $unit kind text reason text definition text value $numeric endpoint text scale text \
        convention text interpretation text parameter_ids {array text} coefficient_space text scaling text row_ids {array text} column_ids {array text} \
        element_ids {array text} output_ids {array text} output_index int probabilities {array real} estimator text approximation text method text confidence {number_or_symbol {{}}} alternative text]]
}
::GX::nativeWorkspaceShapeRegister statistical_result_scalar {record {
    api_id text api_version int schema text model {named statistical_model} residual {map text} parameters {array {named statistical_parameter}}
    solver {record {status text reason text method text converged bool diagnostics {named statistical_solver_receipt}}}
    context {named statistical_context} provenance {named statistical_provenance} assumptions {array text} request {named statistical_request}
    parameter_uncertainty {named statistical_parameter_uncertainty}
}}
::GX::nativeWorkspaceShapeRegister statistical_variable_schema {record {variable_id text unit text dtype text rank int shape {array int} dimension_ids {array text}}}
::GX::nativeWorkspaceShapeRegister statistical_column_binding {record {
    api_id text api_version int schema text prototype {named statistical_result} column_variables {map text} row_count int row_start int
    seal {record {payload_sha256 text variable_schema {array {named statistical_variable_schema}}}}
}}
::GX::nativeWorkspaceShapeRegister statistical_resource_binding {record {
    api_id text api_version int schema text prototype {named statistical_result} column_variables {map text} row_count int row_start int resource {resource {named resource_metadata}}
}}
::GX::nativeWorkspaceShapeRegister statistical_result {codec ::GX::WorkspaceStatistics::resultEncode}
proc ::GX::WorkspaceStatistics::resultEncode {result} {
    set schema [dict get $result schema]
    switch -- $schema {
        gxtxt.statistical_result.v1 {
            set fields {};set shape [dict get $::GX::WorkspaceScientificCodec::shapes statistical_result_scalar]
            dict for {field value} $result {
                if {$field eq {quantities}} {
                    set quantities {};dict for {name item} $value {dict set quantities $name [::GX::nativeWorkspaceEncode [quantityShape $name $item [dict get $result context]] $item]}
                    dict set fields $field [list object $quantities]
                } else {dict set fields $field [dict get [lindex [::GX::nativeWorkspaceEncode $shape [dict create $field $value]] 1] $field]}
            };return [list object $fields]
        }
        gxtxt.statistical_result.column_binding.v1 {set name statistical_column_binding}
        gxtxt.statistical_result.resource_binding.v1 {set name statistical_resource_binding}
        gxtxt.statistical_result.table.v1 {return [tableEncode $result]}
        default {
            if {![dict exists $::GX::WorkspaceScientificCodec::shapes $schema]} {error "Statistical native schema '$schema' is unavailable"}
            set name $schema
        }
    }
    return [::GX::nativeWorkspaceEncode [list named $name] $result]
}
proc ::GX::WorkspaceStatistics::tableEncode {result} {
    set shape {record {
        api_id text api_version int schema text model {named statistical_model} context {named statistical_context} provenance {named statistical_provenance}
        row_ids {array text} row_count int
        request {record {model_id text context {named statistical_context} provenance {named statistical_provenance} row_ids {array text} numerical_columns {map {array scientific_real}}}}
    }}
    set fields {};dict for {field value} $result {
        if {$field eq {columns}} {
            set columns {};dict for {name column} $value {
                set columnShape [list record [dict create definition [quantityShape $name [dict get $column definition] [dict get $result context]] \
                    states {array {record {status text reason text}}} state int state_ids {array int} values {array scientific_real}]]
                dict set columns $name [::GX::nativeWorkspaceEncode $columnShape $column]
            };dict set fields $field [list object $columns]
        } else {dict set fields $field [dict get [lindex [::GX::nativeWorkspaceEncode $shape [dict create $field $value]] 1] $field]}
    };return [list object $fields]
}
# Nonfinite descriptors are an explicit typed scientific tag emitted only for
# declared numeric fields, never a parseability test of ordinary text.
proc ::GX::nativeWorkspaceScientificDecode {typed {depth 0}} {
    if {$depth>64} {error {Scientific native graph exceeds nesting bound}}
    lassign $typed kind value
    if {$kind eq {object} && [dict keys $value] eq {classification value} && [dict get $value classification] eq {text scientific_nonfinite}} {
        return [nativeWorkspaceShapeDecode scientific_real $typed]
    }
    switch -- $kind {
        object - resource {set result {};dict for {key child} $value {dict set result $key [nativeWorkspaceScientificDecode $child [expr {$depth+1}]]};return $result}
        array {set result {};foreach child $value {lappend result [nativeWorkspaceScientificDecode $child [expr {$depth+1}]]};return $result}
        default {return [nativeWorkspaceDecode $typed]}
    }
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::resultEncode ::GX::nativeWorkspaceScientificDecode
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::numericalEncode ::GX::nativeWorkspaceScientificDecode
::GX::nativeWorkspaceCodecDecodeRegister ::GX::WorkspaceStatistics::solverEncode ::GX::nativeWorkspaceScientificDecode
