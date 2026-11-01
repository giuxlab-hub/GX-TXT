# SPDX-License-Identifier: GPL-3.0-or-later
# Persistence codecs only: the existing native geometry and P017 owners remain.
namespace eval ::GX::Workbench3D {}
::GX::nativeWorkspaceShapeRegister wb3_plane {record {origin {array real} normal {array real} u_axis {array real} v_axis {array real} working_unit text orientation text}}
::GX::nativeWorkspaceShapeRegister wb3_anchor {record {kind text point {array real} direction {array real} index int parameter real u real v real}}
::GX::nativeWorkspaceShapeRegister wb3_specification {record {kind text tolerance real matrix {array real} local_point {array real} world_point {array real} target real plane {named wb3_plane} plane2 {named wb3_plane} anchors {array {named wb3_anchor}} surface_object_id text}}
::GX::nativeWorkspaceShapeRegister wb3_style {record {base_color text opacity real representation text visible bool line_width real point_size real texture {named texture3d}}}
::GX::nativeWorkspaceShapeRegister wb3_origin {record {schema text document_id text module_id text provider_id text generation text revision int sha256 text object_id text geometry_sha256 text working_unit text session_origin {named origin} plane {named wb3_plane}}}
::GX::nativeWorkspaceShapeRegister wb3_binding {record {
    xy_resource {resource {named resource_metadata}} gap_resource {resource {named resource_metadata}} source_rows_resource {resource {named resource_metadata}} source_descriptor {named curve_descriptor} closed bool
    source_kind text source_dataset_id text source_sha256 text source_format text source_resource {resource {named resource_metadata}}
    input_unit text dataset_declared_unit text unit_policy text assumed_input_unit bool working_unit text coordinate_factor real
}}
::GX::nativeWorkspaceShapeRegister wb3_diagnostics {record {
    kind text geometry_role text geometry_sha256 text transform {array real} world_transform {array real} bounds_min {array real} bounds_max {array real}
    surface_area real volume real volume_defined bool topology_valid bool closed bool solids int point_count int cell_count int array_count int boundary_edges int nonmanifold_edges int orientation_conflicts int components int
    status text residual real iterations int converged bool constraint_status int maximum_residual real satisfied_count int
}}
::GX::nativeWorkspaceShapeRegister wb3_profile {record {
    contours {array {record {xy_resource {resource {named resource_metadata}} gap_resource {resource {named resource_metadata}} closed bool}}}
    source_bindings {array {named wb3_binding}} plane {named wb3_plane} tolerance real name text source_dataset_id text working_unit text assumed_coordinate_unit text
    display_geometry {resource {named resource_metadata}} visible bool locked bool attrs {map text} style {named wb3_style} geometry_role text
    source_kind text source_object_id text source_geometry {resource {named resource_metadata}} source_planar_document text planar_result_sha256 text origin_workspace {named wb3_origin}
    definitions {map {record {name text definition {named native_sketch_definition} units {array text} provenance {record {operation text source_contour int approximation text}}}}}
    provenance {record {operation text planar_document_id text planar_revision int source_sha256 text source_document_id text source_revision int approximation text original_preserved bool}}
}}
::GX::nativeWorkspaceShapeRegister wb3_object {record {
    kind text geometry {resource {named resource_metadata}} display_geometry {resource {named resource_metadata}} diagnostics {named wb3_diagnostics}
    name text visible bool locked bool group text attrs {map text} source_bindings {array {named wb3_binding}} provenance {codec ::GX::Workbench3D::workspaceProvenanceEncode} style {named wb3_style} geometry_role text
}}
::GX::nativeWorkspaceShapeRegister wb3_provenance {record {
    operation text parameters {named wb3_parameters} source_snapshots {map {named wb3_object}} kernel text boolean bool target_id text profile_snapshot {named wb3_profile}
    source_unit text target_unit text factor real source_geometry {resource {named resource_metadata}} source_object_id text
    api_id text api_version int replay_policy text module_id text action_id text plugin_version text config_snapshot {map text}
}}
proc ::GX::Workbench3D::workspaceProvenanceEncode {value} {if {$value eq {}} {return {text {}}};return [::GX::nativeWorkspaceEncode {named wb3_provenance} $value]}
::GX::nativeWorkspaceShapeRegister wb3_values {record {
    tolerance real enabled bool target real name text visible bool locked bool attributes {map text} geometry_role text recapture bool member_kind text index int parameter real u real v real selectable bool opacity real color text
}}
::GX::nativeWorkspaceShapeRegister wb3_operation {record {
    operation text parameters {named wb3_parameters} target_ids {array text} name text attributes {map text} encoded text
}}
::GX::nativeWorkspaceShapeRegister wb3_parameters {record {
    lengths {array real} radius real height real delta {array real} axis {array real} pivot {array real} radians real factors {array real} matrix {array real} mode text
    tolerance real linear_deflection real angular_deflection real weld_tolerance real max_triangles int max_output_bytes int max_items int max_vertices int level text
    local_points {array {array real}} world_points {array {array real}} plane {named wb3_plane} keep_positive bool constraints {array {named wb3_specification}}
    profile_id text distance real target text targets {array text} tools {array text} tool text result_policy text keep_tools bool keep_tool bool operation text
    source_kind text source_dataset_id text source_sha256 text source_format text source_resource {resource {named resource_metadata}} input_unit text dataset_declared_unit text unit_policy text assumed_input_unit bool working_unit text coordinate_factor real
    source_request {named curve_request} closed bool append_to text measurement_id text measurement_ids {array text} specification {named wb3_specification} constraint_id text constraint_ids {array text} values {named wb3_values}
    source_unit text target_unit text factor real physical_scale bool name text visible bool locked bool geometry_role text attributes {map text} base_color text opacity real representation text
    id text parameters {named wb3_values} comparison_id text reference text method text sample_budget int plane_origin {array real} plane_normal {array real} plane_u_axis {array real} section_tolerance real
    sketch_document_id text origin {named wb3_origin} planar_document text accepted_sha256 text placement {named texture3d} resource_sha256 text
    operations {array {named wb3_operation}} provenance {codec ::GX::Workbench3D::workspaceProvenanceEncode}
}}
::GX::nativeWorkspaceShapeRegister wb3_comparison_receipt {record {
    rows {array {record {direction int source_vertex int source {array real} projected {array real} distance real sample_index int position real signed_residual real}}}
    reference_rms real reference_mean real reference_max real symmetric_rms real hausdorff_sampled real closest_sampled real area_difference real volume_difference real
    reference_vertices int target_vertices int reference_samples int target_samples int volume_defined bool reference_tessellated bool target_tessellated bool
    closest_source {array real} closest_target {array real} bounds_min_difference {array real} bounds_max_difference {array real} sampling_policy text projection_policy text extrema_policy text
    tessellation {record {sample_budget int linear_deflection real angular_deflection real weld_tolerance real max_triangles int max_output_bytes int}}
    working_unit text area_unit text volume_unit text statistics {map {named statistical_result}}
    count int count_a int count_b int max_index int max_source_index int sample_budget int display_rows int display_is_scientific_data bool row_indices {array int}
    max_absolute real mean_absolute real rmse real rms_a_to_b real rms_b_to_a real hausdorff real minimum_distance real length_a real length_b real length_difference real area_a real area_b real
    symmetric_rmse real closest_distance real area_supported bool projection_exact_a bool projection_exact_b bool closest_a {array real} closest_b {array real} sampling_a text sampling_b text policy text projection_exact bool closest_exact bool
    coordinate_frame {named native_comparison_frame} unit text coordinate_space text plane {named wb3_plane} tolerance real section_policy text
    section_resources {array {record {input_points int contour_count int captured_plane {named wb3_plane} contours {array {record {xy_resource {resource {named resource_metadata}} closed bool point_count int}}}}}}
}}
::GX::nativeWorkspaceShapeRegister wb3_model {record {
    format text working_unit text objects {map {named wb3_object}} profiles {map {named wb3_profile}} next_object int next_profile int next_group int next_constraint int next_measurement int next_organization int next_comparison int
    recipe {codec ::GX::Workbench3D::workspaceEmptyRecipeEncode}
    groups {map {record {name text members {array text} attrs {map text}}}}
    constraints {map {record {object_id text specification {named wb3_specification} enabled bool status text residual {number_or_symbol {{}}} stale_reason text}}}
    measurements {map {record {object_id text specification {named wb3_specification} value real unit text source_geometry {resource {named resource_metadata}} source_surface_geometry {resource {named resource_metadata}} marker_ids {array text}}}}
    comparisons {map {record {name text reference text target text working_unit text reference_geometry {resource {named resource_metadata}} target_geometry {resource {named resource_metadata}} parameters {named wb3_parameters} receipt {named wb3_comparison_receipt}}}}
    views {map {record {name text view {named scene3d} working_unit text visibility {map bool} object_styles {map {named wb3_style}} layer_presentation {map {record {visible bool opacity real color {array real}}}}}}}
    selection_sets {map {record {name text members {array {record {object_id text source_geometry {resource {named resource_metadata}} anchor {named wb3_anchor}}}}}}}
    layers {map {record {name text members {array text} visible bool selectable bool locked bool opacity real color {array real}}}}
    attrs {map text} view {named scene3d} sketch_documents {map {record {document_id text working_unit text plane {named wb3_plane}}}}
    tool_settings {record {dataset text x text y text distance real mode text target text profile text nextName text primitive text dimensions {array real} radius real height real resultId text exportFormat text editAction text closedProfile bool includeProfile bool convertProfileUnits bool assumeProfileUnit bool extrusionTargets {array text} keepExtrusionTool bool}}
}}
proc ::GX::Workbench3D::workspaceEmptyRecipeEncode {value} {if {$value ne {}} {error {Obsolete private recipe fields cannot be converted into a native Workspace}};return {array {}}}
proc ::GX::Workbench3D::workspaceModelEncode {value} {
    set result {};dict for {key field} $value {
        if {$field eq {@gxtxt.recipe.delete}} {dict set result $key [list text $field]} else {
            set shape [dict get [lindex [dict get $::GX::WorkspaceScientificCodec::shapes wb3_model] 1] $key]
            dict set result $key [::GX::nativeWorkspaceEncode $shape $field]
        }
    };return [list object $result]
}
proc ::GX::Workbench3D::workspaceHistoryEncode {record} {
    set typed [::GX::nativeWorkspaceHistoryEncode $record ::GX::Workbench3D::workspaceModelEncode]
    if {[dict exists $record steps]} {
        set steps {};foreach step [dict get $record steps] encoded [lindex [dict get [lindex $typed 1] steps] 1] {
            set fields [lindex $encoded 1]
            if {[dict exists $step parameters]} {dict set fields parameters [::GX::nativeWorkspaceEncode {named wb3_parameters} [dict get $step parameters]]}
            lappend steps [list object $fields]
        }
        set fields [lindex $typed 1];dict set fields steps [list array $steps];set typed [list object $fields]
    };return $typed
}
proc ::GX::Workbench3D::workspaceEncode {payload} {
    set fields {};dict for {key value} [dict remove $payload workspace_metadata] {
        switch -- $key {
            model {set encoded [workspaceModelEncode $value]}
            undo - redo {if {$value ne {}} {error {Obsolete private Undo/Redo cannot be converted into native Workspaces}};set encoded {array {}}}
            allocation_counters {set encoded [::GX::nativeWorkspaceEncode {record {next_object int next_profile int next_group int next_constraint int next_measurement int next_organization int next_comparison int}} $value]}
            scientific_history {set encoded [workspaceHistoryEncode $value]}
            legacy_history_archive {set encoded [::GX::nativeWorkspaceEncode {resource {named resource_metadata}} $value]}
            default {error "Undeclared Workbench3D Workspace field '$key'"}
        };dict set fields $key $encoded
    };return [list object $fields]
}
proc ::GX::Workbench3D::workspaceValidate {payload} {workspaceEncode $payload}
proc ::GX::Workbench3D::workspaceDecode {typed} {return [::GX::nativeWorkspaceScientificDecode $typed]}
