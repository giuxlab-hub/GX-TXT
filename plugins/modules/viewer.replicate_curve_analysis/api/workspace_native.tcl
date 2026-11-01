# SPDX-License-Identifier: GPL-3.0-or-later
# Independent Replicate persistence adapter; numerical and source authorities
# retain their existing contracts, units, uncertainty meaning and resource bytes.
namespace eval ::GX::ReplicateWorkspace {}
::GX::nativeWorkspaceShapeRegister replicate_coordinate_context {record {
    schema_version int revision int source_sha256 text dataset_id text persistent bool
    variables {map {record {source {map text} display_unit text view_factor real view_pivot real calibration_factor real input_origin real output_origin real}}}
}}
::GX::nativeWorkspaceShapeRegister replicate_source_binding {record {
    schema text kind text dataset_id text source_revision text
    source_identity {record {dataset_id text sha256 text schema_identity text}} roles {map text}
    publication {record {mode text selected_ids {array text} primary_id text provenance text}}
    selection {record {curve_key text calibration_key text}}
    selection_filters {array {named curve_filter}} additional_filters {array {named curve_filter}}
    calibration_identity {record {measurement_id text configuration_id text source_dataset_id text source_sha256 text
        identity {record {available bool reason text dataset_id text calibration_id text sha256 text source_sha256 text}}}}
    declared_calibration_realization_id text
    uncertainty {record {status text reason text scope text owner_errorcode {array text} schema text point_count int
        dataset_sha256 text source_dataset_id text source_integrity text selected_subset_mapping text shared_factor_covariance text}}
    source_descriptor {named curve_descriptor} qualifications {array text}
}}
::GX::nativeWorkspaceShapeRegister replicate_trace {record {
    dataset_id text x_variable_id text y_variable_id text curve_variable_id text curve_key text
    physical_feature_id text observation_id text point_set_id text calibration_realization_id text source_group_id text frame_id text
    filters {array {named curve_filter}} coordinate_context {named replicate_coordinate_context} source_revision text
    topology text order_variable_id text landmark_id text direction text phase_index int source_binding {named replicate_source_binding}
}}
::GX::nativeWorkspaceShapeRegister replicate_request {record {
    analysis_id text method text design text grid_points int reference_frame {record {id text declaration text x_unit text y_unit text}}
    traces {array {named replicate_trace}} correspondence text independent_observation_count int session_token text
    localization_uncertainty text calibration_uncertainty text
}}
::GX::nativeWorkspaceShapeRegister replicate_column_binding {named statistical_column_binding}
::GX::nativeWorkspaceShapeRegister replicate_result {record {
    analysis_id text columns {map {array scientific_real}} units {map text}
    metadata {record {analysis.statistical_results {map {named replicate_column_binding}}}}
    original_traces {map {record {points {array {array scientific_real}} source_rows {array int} descriptor {named curve_descriptor} identity {named replicate_trace}}}}
    aligned_traces {map {array {array scientific_real}}} roles {map text}
    source_rows {map {record {dataset_id text source_rows {array int} observation_id text point_set_id text calibration_realization_id text curve_key text}}}
    qualifications {record {design text independent_observations int shared_calibration_covariance text confidence_interval text prediction_interval text localization_uncertainty text calibration_uncertainty text covariance_definition text topology text}}
}}
::GX::nativeWorkspaceShapeRegister replicate_workspace {record {
    format text request {named replicate_request} hidden {map bool} result {named replicate_result} result_resource {resource {named resource_metadata}}
    published_dataset text plot_ref {record {graph_id text variant_id text}} visibility_initialized bool
    view_axes {array {record {panel_id text axis text limits {array real} plot_rect {array real} scale text direction text aspect text
        ticks {array {record {value real display_value real label text device real}}}}}}
}}
proc ::GX::ReplicateWorkspace::encode {payload} {tailcall ::GX::nativeWorkspaceShapePayloadEncode [dict get $::GX::WorkspaceScientificCodec::shapes replicate_workspace] $payload}
proc ::GX::ReplicateWorkspace::decode {typed} {tailcall ::GX::nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes replicate_workspace] $typed}
