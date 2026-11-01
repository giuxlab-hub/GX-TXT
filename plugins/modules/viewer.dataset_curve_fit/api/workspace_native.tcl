# SPDX-License-Identifier: GPL-3.0-or-later
# Independent Fitter persistence adapters; frozen receipts and resource bytes
# retain their original scientific owners and exact existing digest contracts.
namespace eval ::GX::DatasetCurveFit {}
::GX::nativeWorkspaceShapeRegister fitter_result_reference {record {schema text document_id text generation text fit_curve_id text provenance_sha256 text}}
::GX::nativeWorkspaceShapeRegister fitter_template {record {
    format text recipe text requirements {map {record {unit text value_kind text rank int dtype text}}} origin_result {named fitter_result_reference}
}}
proc ::GX::DatasetCurveFit::templateWorkspaceEncode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_template] $payload}
proc ::GX::DatasetCurveFit::templateWorkspaceDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_template] $typed}
::GX::nativeWorkspaceShapeRegister fitter_formula_recipe {record {
    expression text predictor_ids {array text} predictor_units {array text} response_unit text
    parameters {array {record {id text unit text initial real lower scientific_real upper scientific_real fixed real}}}
}}
::GX::nativeWorkspaceShapeRegister fitter_surface_source {record {dataset_id text layout text x_variable_id text y_variable_id text z_variable_id text sigma_variable_id text}}
::GX::nativeWorkspaceShapeRegister fitter_surface_options {record {nonfinite text noise_model text max_iterations real max_seconds real}}
::GX::nativeWorkspaceShapeRegister fitter_surface_binding {record {
    schema text dataset_id text layout text request {named fitter_surface_source} dataset_identity {record {dataset_id text sha256 text schema_identity text}}
    roles {map {map text}} original_shape {array int} original_count int index_base int index_order text input_sha256 {map text}
}}
::GX::nativeWorkspaceShapeRegister fitter_surface_result {record {
    schema text id text name text binding {named fitter_surface_binding} recipe {named fitter_formula_recipe} options {named fitter_surface_options}
    statistics {named statistical_result} domain {array {array real}} declaration_sha256 text
    state_resource {resource {named resource_metadata}} state_sha256 text observations_resource {resource {named resource_metadata}} observations_sha256 text
    indices_resource {resource {named resource_metadata}} indices_sha256 text input_resources {map {resource {named resource_metadata}}}
}}
::GX::nativeWorkspaceShapeRegister fitter_surface_draft {record {
    dataset text x text y text z text sigma text layout text nonfinite text noise text max_iterations text max_seconds text expression text
    name text selected text qx text qy text dataset_out text nx text ny text xmin text xmax text ymin text ymax text style text
    parameters {array {record {id text unit text initial text lower text upper text fixed bool}}}
}}
::GX::nativeWorkspaceShapeRegister fitter_surface_workspace {record {
    version int source {named fitter_surface_source} recipe {named fitter_formula_recipe} settings {named fitter_surface_options}
    preview {named fitter_surface_result} records {array {named fitter_surface_result}}
    controls {record {name text selected text qx text qy text dataset_out text nx text ny text xmin text xmax text ymin text ymax text style text editor {named fitter_surface_draft}}}
}}
proc ::GX::DatasetCurveFit::surfaceWorkspaceEncode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_surface_workspace] $payload}
proc ::GX::DatasetCurveFit::surfaceWorkspaceDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_surface_workspace] $typed}
::GX::nativeWorkspaceShapeRegister fitter_filter {record {variable text operator text value text}}
::GX::nativeWorkspaceShapeRegister fitter_identity {record {dataset_id text sha256 text schema_identity text}}
::GX::nativeWorkspaceShapeRegister fitter_sample_descriptor {record {
    sample_id text title text description text axes {map {map text}} generator_id text generator_version int producer_module text producer_version text
    generator_parameters {record {count int index_first int index_last int parameter_rule text random_seed text center {array real} radius real angle_interval {array text}
        radius_noise text control_points {array {array real}} breakpoint real slopes {array real} function text}}
    model_provenance {map text} expected_result {record {model text center {array real} radius real control_points {array {array real}} metric text tolerance real
        monotonicity text reference_function text period real order_min int dc real cosine_coefficients {array real} sine_coefficients {array real}}}
}}
::GX::nativeWorkspaceShapeRegister fitter_source_provenance {record {
    source_kind text source_curve_id text source_dataset_id text source_x_variable_id text source_y_variable_id text source_sha256 text
    source_filters {array {named fitter_filter}} source_axes {map {map text}} source_transform_manifest {named transform_manifest} source_curve_source_id text
    source_scientific_fingerprints {array {named fitter_identity}} source_sample_id text source_sample_descriptor {named fitter_sample_descriptor}
    logarithm_lineage {named fitter_logarithm_lineage} smoothing_lineage {named fitter_smoothing_lineage} baseline_lineage {named fitter_baseline_lineage} baseline_correction {named fitter_baseline_receipt}
}}
::GX::nativeWorkspaceShapeRegister fitter_solver_policy {record {
    solver text strategy text loss text multistart_mode text max_iterations real max_seconds real function_tolerance real gradient_tolerance real parameter_tolerance real loss_scale real
    lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real} parameter_scales {array real}
    multistart_count real multistart_seed real multistart_max_seconds real multistart_lower {array real} multistart_upper {array real} multistart_initials {array {array real}}
    method text max_function_evaluations real
}}
::GX::nativeWorkspaceShapeRegister fitter_smoothing_options {record {smoothing_selection text gcv_lambda_bounds {array real} gcv_grid_count real gcv_refinement_evaluations real}}
::GX::nativeWorkspaceShapeRegister fitter_knot_options {record {degree int knots {array real} boundary text endpoint_slopes {array real} extrapolation text x_unit text y_unit text}}
::GX::nativeWorkspaceShapeRegister fitter_bootstrap_options {record {method text replicates int seed int confidence real max_seconds real}}
::GX::nativeWorkspaceShapeRegister fitter_profile_options {record {parameter_id text confidence real search_lower real search_upper real initial_step real parameter_tolerance real max_refits int max_seconds real}}
::GX::nativeWorkspaceShapeRegister fitter_covariance_options {record {dataset_id text variable_id text source_dataset_id text response_variable_id text row_binding text covariance_semantics text singular_policy text}}
::GX::nativeWorkspaceShapeRegister fitter_measurement_options {record {kind text variable_id text independent_variable_id text nonfinite text}}
::GX::nativeWorkspaceShapeRegister fitter_parameter_constraint {record {initial real lower scientific_real upper scientific_real fixed real}}
::GX::nativeWorkspaceShapeRegister fitter_component_recipe {record {components {array {record {id text model_id text initial_parameters {array real} bindings {map text}}}}
    parameters {map {named fitter_parameter_constraint}} x_unit text y_unit text}}
::GX::nativeWorkspaceShapeRegister fitter_region_recipe {record {
    regions {array {record {id text model_id text}}} breakpoints {array {record {id text initial real lower real upper real fixed real continuity text}}}
    origin real fit_windows {array {array real}} parameters {map {named fitter_parameter_constraint}} x_unit text y_unit text
}}
::GX::nativeWorkspaceShapeRegister fitter_rational_recipe {record {numerator_degree int denominator_degree int x_unit text y_unit text parameters {array {record {id text unit text initial real lower scientific_real upper scientific_real fixed real}}} domain {array real} pole_tolerance real}}
::GX::nativeWorkspaceShapeRegister fitter_implicit_recipe {record {formula {named fitter_formula_recipe} residual_mode text normalization {record {value real unit text role text}}}}
::GX::nativeWorkspaceShapeRegister fitter_implicit_branch {record {response_index int bracket {array real} continuous_branch_declared bool independent_domain {array real} x_tolerance real response_tolerance real max_iterations int}}
::GX::nativeWorkspaceShapeRegister fitter_complex_recipe {record {predictor_id text predictor_unit text channels {array {record {id text unit text real_expression text imaginary_expression text}}}
    parameters {array {record {id text unit text initial real lower scientific_real upper scientific_real fixed real}}}}}
::GX::nativeWorkspaceShapeRegister fitter_registered_definition {record {
    format text parameter_ids {array text} parameter_units {array text} initial {array real} lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real}
    predictor_unit text response_unit text predictor_shape {array text} response_shape {array text} parameter_shape {array text} predictor_domain text description text
}}
::GX::nativeWorkspaceShapeRegister fitter_registered_model {record {entrypoint text contract text declaration text reference text callable_id text language text version text revision int
    source_sha256 text declaration_sha256 text definition {named fitter_registered_definition} name text}}
::GX::nativeWorkspaceShapeRegister fitter_registered_state {record {
    kind text schema_version int parameters {array real} parameter_ids {array text} parameter_units {array text} source_sha256 text binding_sha256 text predictor_domain text
    lower_bounds {array scientific_real} upper_bounds {array scientific_real} fixed_mask {array real} initial_parameters {array real} solver text iterations real converged bool exitflag real function_evaluations real message text
}}
::GX::nativeWorkspaceShapeRegister fitter_polar_frame {record {origin {array real} theta_zero real clockwise bool degrees bool angle_unit text unwrap_policy text angle_cut real}}
::GX::nativeWorkspaceShapeRegister fitter_complex_channel {record {channel_id text representation text first_variable_id text second_variable_id text phase_unit text reference real first_descriptor {map text} second_descriptor {map text}}}
::GX::nativeWorkspaceShapeRegister fitter_complex_covariance {record {layout text values {array {array real}} component_units {array text} dataset_id text variable_id text source_dataset_id text row_binding text}}
::GX::nativeWorkspaceShapeRegister fitter_complex_display {record {channel_id text projection text reference {record {value real unit text}}}}
::GX::nativeWorkspaceShapeRegister fitter_complex_data {record {channels {array {named fitter_complex_channel}} covariance {named fitter_complex_covariance} display {named fitter_complex_display}}}
::GX::nativeWorkspaceShapeRegister fitter_complex_binding {record {
    schema text source_identity {named fitter_source_provenance} input_dataset_identity {named fitter_identity} original_count int channels {array {named fitter_complex_channel}}
    covariance {named fitter_complex_covariance} display {named fitter_complex_display} row_index_base int training_rows_sha256 text
    covariance_variable_descriptor {map text} covariance_dataset_identity {named fitter_identity} covariance_input_sha256 text input_sha256 {map text}
    source_rows_sha256 text owned_sha256 {map text} numeric_covariance_sha256 {map text}
}}
::GX::nativeWorkspaceShapeRegister fitter_unit_affine_plan {record {
    source_unit text target_unit text source_definition {map text} target_definition {map text} source_to_canonical text base_scale_ratio real target_from_canonical text
    direction text input_unit text output_unit text affine bool scale real offset real reason text
}}
::GX::nativeWorkspaceShapeRegister fitter_measurement_axis {record {variable_id text variable_descriptor {map text} input_unit text value_unit text conversion_plan {named fitter_unit_affine_plan} scale_factor real offset_applied bool}}
::GX::nativeWorkspaceShapeRegister fitter_measurement_binding {record {
    kind text variable_id text independent_variable_id text nonfinite text schema text source_dataset_id text source_identities {array {named fitter_identity}}
    variable_descriptor {map text} input_unit text value_unit text response_unit text orientation text conversion_plan {named fitter_unit_affine_plan} scale_factor real offset_applied bool
    independent_measurement {named fitter_measurement_axis} digitization {named fitter_digitization_measurement}
}}
::GX::nativeWorkspaceShapeRegister fitter_measurement_selection {record {kind text nonfinite_policy text weight_semantics text input_count int fit_count int omitted_nonfinite_count int zero_precision_count int scale_factor real independent_scale_factor real row_identity text}}
::GX::nativeWorkspaceShapeRegister fitter_digitization_publication {record {
    schema text dataset_id text payload_sha256 text point_count int x_variable_id text y_variable_id text sigma_x_variable_id text sigma_y_variable_id text point_id_variable_id text
    resources {record {configuration {resource {named resource_metadata}} points {resource {named resource_metadata}} state {resource {named resource_metadata}}
        values {resource {named resource_metadata}} interpretation {resource {named resource_metadata}}}}
}}
::GX::nativeWorkspaceShapeRegister fitter_digitization_measurement {record {binding {named fitter_digitization_publication} meaning {named gxtxt.digitization_interpretation.v1}
    source_identity {named fitter_identity} fit_plan {named gxtxt.digitization_fit_plan.v1}}}
::GX::nativeWorkspaceShapeRegister fitter_digitization_covariance {record {schema text source {named fitter_digitization_publication} source_identity {named fitter_identity}
    axis text variable_id text resource {resource {named resource_metadata}} fit_plan {named gxtxt.digitization_fit_plan.v1} covariance_identity {named fitter_identity}}}
::GX::nativeWorkspaceShapeRegister fitter_covariance_binding {record {
    dataset_id text variable_id text source_dataset_id text response_variable_id text row_binding text covariance_semantics text singular_policy text
    schema text variable_descriptor {map text} response_unit text covariance_unit text original_count int orientation text source_identity {named fitter_identity} covariance_dataset_identity {named fitter_identity}
    row_index_base int training_rows_sha256 text digitization {named fitter_digitization_covariance} input_bytes_sha256 text input_dtype text used_bytes_sha256 text numeric_covariance_sha256 text
}}
::GX::nativeWorkspaceShapeRegister fitter_template_binding {record {schema text template_id text template_generation text template_sha256 text original_dataset_id text target_dataset_id text target_sha256 text variable_mapping {map text} selection_policy text dropped_original_row_picks int}}
::GX::nativeWorkspaceShapeRegister fitter_influence_link {record {row int point {array real}}}
::GX::nativeWorkspaceShapeRegister fitter_options {record {
    influence_diagnostics bool smoothing_lambda real period real orientation text noise_model text confidence real prediction_band text
    covariance {named fitter_covariance_options} profile {named fitter_profile_options} bootstrap {named fitter_bootstrap_options}
    knot_options {named fitter_knot_options} smoothing_options {named fitter_smoothing_options} registered_model {named fitter_registered_model}
    component_recipe {named fitter_component_recipe} rational_recipe {named fitter_rational_recipe} rational_extrapolation text formula_recipe {named fitter_formula_recipe}
    implicit_recipe {named fitter_implicit_recipe} implicit_branch {named fitter_implicit_branch} complex_recipe {named fitter_complex_recipe} complex_data {named fitter_complex_data}
    region_recipe {named fitter_region_recipe} prediction_sigma text prediction_weights text measurement {named fitter_measurement_options} solver_options {named fitter_solver_policy}
    translation_u {record {mode text delta real}} translation_v {record {mode text delta real}} polar_frame {named fitter_polar_frame}
    topology text parameterization text parameter_variable_id text user_period real closure_tolerance real
    covariance_binding {named fitter_covariance_binding} measurement_binding {named fitter_measurement_binding} complex_binding {named fitter_complex_binding}
}}
set ::GX::DatasetCurveFit::nativeSourceFields {}
foreach field {dataset x y sourceSha sourceKind sourceStatus sourceError scientific_source_id model scope domain min max initial period smoothing noiseModel
    predictionBand predictionSigma predictionWeights measurementKind measurementVariable measurementIndependentVariable measurementMissing rationalExtrapolation implicitBranch
    orientation topology parameterization parameterVariable userPeriod closureTolerance translationUMode translationVMode} {dict set ::GX::DatasetCurveFit::nativeSourceFields $field text}
set ::GX::DatasetCurveFit::nativeSourceFields [dict merge $::GX::DatasetCurveFit::nativeSourceFields {
    filters {array {named fitter_filter}} loadedBinding {tuple {text text text {array {named fitter_filter}}}}
    sourceTransformManifest {named transform_manifest} sourceIdentities {array {named fitter_identity}} selected {array int}
    selection_state {named native_selection} savedSelection {named native_selection} sourcePointCount int sourceStyle {named native_style} viewBounds {array real}
    degree int samples int confidence real translationUDelta real translationVDelta real influenceDiagnostics bool
    covarianceSettings {named fitter_covariance_options} bootstrapSettings {named fitter_bootstrap_options} profileSettings {named fitter_profile_options}
    solverSettings {map {named fitter_solver_policy}} smoothingSettings {named fitter_smoothing_options} knotSettings {map {named fitter_knot_options}}
    componentRecipe {named fitter_component_recipe} regionRecipe {named fitter_region_recipe} formulaRecipe {named fitter_formula_recipe} rationalRecipe {named fitter_rational_recipe}
    implicitRecipe {named fitter_implicit_recipe} implicitBranch {named fitter_implicit_branch} complexRecipe {named fitter_complex_recipe} complexData {named fitter_complex_data}
    registeredModel {named fitter_registered_model} polarFrame {named fitter_polar_frame} templateBinding {named fitter_template_binding} recipePointMask {named native_point_mask}
    influenceLinkedPoint {named fitter_influence_link} preview_receipt {named fitter_result} previewAccepted bool
}]
::GX::nativeWorkspaceShapeRegister fitter_source_state [list record $::GX::DatasetCurveFit::nativeSourceFields]
unset ::GX::DatasetCurveFit::nativeSourceFields
::GX::nativeWorkspaceShapeRegister fitter_workspace {record {
    version int workspace_sources {array {record {id text visible bool state {named fitter_source_state}}}} active_source text next_source int next_fit int
    records {array {named fitter_accepted_record}} presentation {named presentation2d} view_bounds {array real} panel {record {visible bool fraction real residual_axis text}}
}}
proc ::GX::DatasetCurveFit::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_workspace] $payload}
proc ::GX::DatasetCurveFit::workspaceDecode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes fitter_workspace] $typed}
::GX::nativeWorkspaceShapeRegister fitter_input_policy {record {schema text model text order text duplicates text aggregation text endpoint text removed_terminal_endpoint bool parameterization text observation_count real model_input_count real}}
::GX::nativeWorkspaceShapeRegister fitter_preprocessing {record {
    schema text status text reason text source {codec ::GX::DatasetCurveFit::nativePreprocessingSourceEncode} source_request {named curve_request} selection_descriptor {named native_point_mask}
    original_count int original_count_status text filtered_count int finite_count int selected_count int nonfinite_count int selection_excluded_count int
    fit_count int model_input_count int region_count int finite_policy text duplicate_policy text order_policy text row_identity_kind text model_policy {named fitter_input_policy}
    stages {map text} excluded_ids {map {record {kind text stage text from text subtract text start int stop_exclusive int reason text}}}
    coordinate_transform {record {orientation text source_axes {map {map text}} translation {named statistical_translation} smoothing {named statistical_smoothing} baseline_correction {named statistical_baseline_correction} response_transform {named statistical_response_transform}}}
}}
proc ::GX::DatasetCurveFit::nativePreprocessingSourceEncode {source} {
    if {[dict exists $source api_id] && [dict get $source api_id] eq {CURVE_SOURCE_API_v1}} {set name curve_descriptor} else {set name fitter_source_provenance}
    return [::GX::nativeWorkspaceEncode [list named $name] $source]
}
::GX::nativeWorkspaceShapeRegister fitter_log_transform {record {schema text provider text operation text base text reference real source_dataset_id text source_sha256 text
    source_variable_id text source_unit text output_variable_id text output_unit text domain text noise_semantics text}}
::GX::nativeWorkspaceShapeRegister fitter_logarithm_lineage {array {record {variable_id text transform {named fitter_log_transform} inverse_eligible bool inverse_reason text}}}
::GX::nativeWorkspaceShapeRegister fitter_baseline_options {record {method text lambda real p real max_iterations real tolerance real grid_policy text nonfinite text value real estimator text degree real}}
::GX::nativeWorkspaceShapeRegister fitter_baseline_estimator {record {
    iterations real converged bool relative_weight_change real lambda real p real max_iterations real tolerance real difference_order real grid_policy text grid_uniform bool
    x_step scientific_real grid_tolerance real solver text weight_semantics text uncertainty_policy text
}}
::GX::nativeWorkspaceShapeRegister fitter_baseline_receipt {record {
    schema text provider text source_dataset_id text source_sha256 text x_variable_id text original_y_variable_id text baseline_variable_id text corrected_variable_id text row_variable_id text
    row_identity text method text original_n int estimated_n int omitted_n int options {named fitter_baseline_options} estimator {named fitter_baseline_estimator} uncertainty_policy text
}}
::GX::nativeWorkspaceShapeRegister fitter_baseline_lineage {array {record {variable_id text correction {named fitter_baseline_receipt}}}}
::GX::nativeWorkspaceShapeRegister fitter_smooth_options {record {method text window real degree real robust_iterations real nonfinite text}}
::GX::nativeWorkspaceShapeRegister fitter_smooth_estimator {record {
    method text n real window real degree real robust_iterations real original_n real selected_n real index_base real nonfinite_policy text row_order text schema text
}}
::GX::nativeWorkspaceShapeRegister fitter_smooth_receipt {record {
    schema text provider text source_dataset_id text source_sha256 text x_variable_id text original_y_variable_id text smoothed_variable_id text residual_variable_id text row_variable_id text
    row_identity text method text original_n int smoothed_n int omitted_n int options {named fitter_smooth_options} estimator {named fitter_smooth_estimator} uncertainty_policy text
}}
::GX::nativeWorkspaceShapeRegister fitter_smoothing_lineage {array {record {variable_id text smoothing {named fitter_smooth_receipt}}}}
::GX::nativeWorkspaceShapeRegister fitter_model_selection {record {plan {named statistical_selection_plan} numeric {named statistical_selection_numeric}}}
::GX::nativeWorkspaceShapeRegister fitter_region_selection {record {schema text selected_mask {array real} source_row_positions {array real} fit_windows {array {array real}}
    input_count real retained_count real excluded_count real index_base real selection_rule text scope text boundary_ownership text row_identity text selection_stage text}}
::GX::nativeWorkspaceShapeRegister fitter_output_domain {record {schema text status text row_count int outside_count int reference_domain text reference_basis text boundary_policy text intrinsic_policy text coordinate_space text}}
::GX::nativeWorkspaceShapeRegister fitter_observation_binding {record {schema text source_id text source_sha256 text rows_sha256 text}}
::GX::nativeWorkspaceShapeRegister fitter_alias {record {
    status text label text unit text kind text reason text definition text value scientific_real convention text interpretation text id text quantity text unit_text text sample_role text
}}
::GX::nativeWorkspaceShapeRegister fitter_registered_execution {record {reference text callable_id text source_sha256 text declaration_sha256 text revision int language text entrypoint text}}
set ::GX::DatasetCurveFit::nativeResultFields [lindex [dict get $::GX::WorkspaceScientificCodec::shapes fitter_source_provenance] 1]
foreach field {model parameters model_state_json scope initial physical_formula accepted_name producer_framework_version export_domain training_domain training_domain_basis
    translation_algorithm translation_u_mode translation_v_mode translation_u_original_bounds translation_v_original_bounds translation_u_transformed_bounds translation_v_transformed_bounds
    model_state_storage parameters_storage grid_kind residual_convention r2_convention zero_normal_sign_policy residual_columns metric_unit coordinate_mode independent_axis angle_unit unwrap_policy
    topology parameterization prediction_display_note numeric_model_state_sha256 registered_model_state_sha256 complex_model_state_sha256 rational_state_sha256 knot_binding_sha256 fit_curve_id} {dict set ::GX::DatasetCurveFit::nativeResultFields $field text}
foreach field {output_n source_n train_n point_count exact_source_rows output_extrapolated_count residual_stride model_state_bytes parameter_count degree} {dict set ::GX::DatasetCurveFit::nativeResultFields $field int}
foreach field {converged parametric translation_inverse_applied display_is_scientific_data} {dict set ::GX::DatasetCurveFit::nativeResultFields $field bool}
foreach field {translation_u_delta translation_v_delta translation_u_margin translation_v_margin angular_min angular_max train_rmse train_r2 source_rmse source_r2
    train_geometric_rmse source_geometric_rmse train_geometric_dispersion_score source_geometric_dispersion_score train_max_geometric_distance source_max_geometric_distance} {dict set ::GX::DatasetCurveFit::nativeResultFields $field scientific_real}
foreach field {geometry_resource preview_geometry_resource preview_residual_plot_resource residual_resource model_state_resource source_rows_resource comparison_rows_resource
    profile_values_resource profile_parameters_resource profile_status_resource profile_messages_resource bootstrap_parameters_resource bootstrap_status_resource bootstrap_seed_resource
    influence_resource influence_input_rows_resource influence_source_rows_resource region_membership_resource measurement_resource measurement_rows_resource training_rows_resource orthogonal_resource
    prediction_resource prediction_lower_resource prediction_upper_resource prediction_gap_resource covariance_resource registered_source_resource
    complex_training_observations_resource complex_source_observations_resource complex_training_covariance_resource complex_source_covariance_resource
    preprocessing_input_rows_resource preprocessing_nonfinite_rows_resource preprocessing_unselected_rows_resource preprocessing_selected_rows_resource preprocessing_model_rows_resource preprocessing_region_rows_resource} {dict set ::GX::DatasetCurveFit::nativeResultFields $field {resource {named resource_metadata}}}
foreach field {preprocessing_input_rows preprocessing_nonfinite_rows preprocessing_unselected_rows preprocessing_selected_rows preprocessing_fit_rows preprocessing_model_rows preprocessing_region_rows selected_indices fitted_indices fitted_breaks} {dict set ::GX::DatasetCurveFit::nativeResultFields $field {array int}}
set ::GX::DatasetCurveFit::nativeResultFields [dict merge $::GX::DatasetCurveFit::nativeResultFields {
    orientation text options {named fitter_options} translation {named statistical_translation} polar_frame {named fitter_polar_frame}
    statistical_results {map {named statistical_result}} statistical_aliases {map {named fitter_alias}} observation_binding {named fitter_observation_binding}
    model_input_policy {named fitter_input_policy} preprocessing {named fitter_preprocessing} output_domain {named fitter_output_domain}
    output_domain_resource {resource {named resource_metadata}} output_domain_values {array real} numeric_model_types {map text} complex_model_types {map text}
    complex_conversion_types {map text}
    registered_model_state {named fitter_registered_state} registered_execution {named fitter_registered_execution}
    fitted {array {array real}} residual {array {array real}} residual_display {array {array real}} residual_rows {array int}
    selection_descriptor {named native_point_mask} recipe_producers {map text} template_binding {named fitter_template_binding}
    parameter_variable_descriptor {map text} measurement_binding {named fitter_measurement_binding} measurement_selection {named fitter_measurement_selection}
    covariance_binding {named fitter_covariance_binding} complex_binding {named fitter_complex_binding} complex_conversion {named fitter_complex_conversion}
    model_selection {named fitter_model_selection} region_selection {named fitter_region_selection} prediction_plan {named statistical_prediction_plan}
}]
proc ::GX::DatasetCurveFit::nativeDomainEncode {domain} {
    if {$domain eq {source}} {return [list text $domain]}
    if {[lindex $domain 0] eq {parameter}} {set shape {tuple {text real real int}}} else {set shape {tuple {real real int}}}
    return [::GX::nativeWorkspaceEncode $shape $domain]
}
dict set ::GX::DatasetCurveFit::nativeResultFields domain {codec ::GX::DatasetCurveFit::nativeDomainEncode}
proc ::GX::DatasetCurveFit::nativeResultEncode {result} {
    variable nativeResultFields
    set fields $nativeResultFields
    foreach prefix {numeric complex} {
        if {[dict exists $result ${prefix}_model_state]} {
            dict set fields ${prefix}_model_state [::GX::nativeWorkspaceTransportShape [dict get $result ${prefix}_model_types] value [dict get $result ${prefix}_model_state]]
        }
    }
    if {[dict exists $result complex_conversion]} {dict set fields complex_conversion [::GX::nativeWorkspaceTransportShape [dict get $result complex_conversion_types] value [dict get $result complex_conversion]]}
    if {[dict exists $result model] && [dict get $result model] eq {registered}} {dict set fields initial {array real}}
    return [::GX::nativeWorkspaceEncode [list record $fields] $result]
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::DatasetCurveFit::nativeResultEncode ::GX::nativeWorkspaceScientificDecode
::GX::nativeWorkspaceShapeRegister fitter_result {codec ::GX::DatasetCurveFit::nativeResultEncode}
::GX::nativeWorkspaceShapeRegister fitter_accepted_record {record {
    label text color {array real} visible bool points {array {array real}} model text parameters text model_state_json text scope text
    domain {codec ::GX::DatasetCurveFit::nativeDomainEncode} rmse scientific_real r2 scientific_real provenance {named fitter_result}
    source_curve_id text fit_curve_id text point_count int geometry_resource {resource {named resource_metadata}}
}}
