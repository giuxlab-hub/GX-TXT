# SPDX-License-Identifier: GPL-3.0-or-later
# Independent persistence adapter. Logical geometry, constraints, units and
# scientific History retain their original owners; native handles are omitted.
namespace eval ::GX::CurveWorkbench {}
::GX::nativeWorkspaceShapeRegister cwb_view {tuple {real real real real real real {array real}}}
::GX::nativeWorkspaceShapeRegister cwb_configuration {record {schema text x_unit text y_unit text allow_heterogeneous bool}}
::GX::nativeWorkspaceShapeRegister cwb_semantic_ref {record {logical text kind text index int}}
::GX::nativeWorkspaceShapeRegister cwb_pivot {record {mode text point {array real}}}
::GX::nativeWorkspaceShapeRegister cwb_gizmo {record {visible bool mode text radius_px real handle_px real line_width real axes_angle real mirror_a {array real} mirror_b {array real} x_color {array real} y_color {array real} rotation_color {array real} pivot_color {array real}}}
::GX::nativeWorkspaceShapeRegister cwb_coordinate_context {record {schema_version int revision int source_sha256 text dataset_id text persistent bool variables {map {record {source {map text} display_unit text view_factor real view_pivot real calibration_factor real input_origin real output_origin real}}}}}
::GX::nativeWorkspaceShapeRegister cwb_coordinate_view {record {basis text reference {array real} applied text}}
::GX::nativeWorkspaceShapeRegister cwb_coordinate_conversion {record {schema_version int operation text source_units {array text} target_units {array text} matrix {array real} source_dataset_modified bool existing_geometry_modified bool}}
::GX::nativeWorkspaceShapeRegister cwb_coordinate_relation {record {unit text canonical_unit text value_kind text name text variable_id text display_label text dtype text rank int dimension_ids {array text} coordinate_role text semantic_role text axis_kind text conversion_kind text conversion_api text coordinate_relation text}}
::GX::nativeWorkspaceShapeRegister cwb_declaration {record {schema text units {array text} previous_units {array text} rationale text operation text numeric_values_changed bool source_dataset_modified bool curve_ids {array text}}}
::GX::nativeWorkspaceShapeRegister cwb_frame_origin {record {units {array text} relations {map {named cwb_coordinate_relation}} snapshot {named cwb_coordinate_context} variables {map text} assumptions {map text} conversions {array {named cwb_coordinate_conversion}}}}
::GX::nativeWorkspaceShapeRegister cwb_fragment_definition {record {parent text parameter bool first real last real}}
::GX::nativeWorkspaceShapeRegister cwb_sampling {record {method text first real last real total int fragment_id text definition {named cwb_fragment_definition} geometry_authority text}}
::GX::nativeWorkspaceShapeRegister cwb_series_parameters {record {rows int columns int step_u {array real} step_v {array real} include_origin bool positions int angle_step real pivot {array real} rotate_geometry bool circular bool spacing_x real spacing_y real column_y real row_x real}}
::GX::nativeWorkspaceShapeRegister cwb_extension_operation {record {operation text target_ids {array text} matrix {array real} name text definition {named native_sketch_definition} display_samples int working_unit text points {array {array real}} attributes {map text} encoded text}}
::GX::nativeWorkspaceShapeRegister cwb_planar_context {record {document_id text revision int generation text sha256 text session_token text mode text staged_origin bool}}
::GX::nativeWorkspaceShapeRegister cwb_planar_provenance {record {operation text source_contour int approximation text}}
::GX::nativeWorkspaceShapeRegister cwb_plane {record {origin {array real} normal {array real} u_axis {array real} v_axis {array real} working_unit text orientation text}}
::GX::nativeWorkspaceShapeRegister cwb_planar_reference {record {resource {resource {named resource_metadata}} width int height int plane {named cwb_plane} working_unit text scale real translation {array real}
    camera {record {projection text orthographic_height real camera_target text camera_position text camera_up text near_clip real far_clip real}}
    pixel_convention text viewing_side text clipping text source_sha256 text}}
::GX::nativeWorkspaceShapeRegister cwb_fit_transfer {record {schema text source_reference {named fitter_result_reference} coordinate_units {array text}
    geometry {record {schema text status text reason text parameter_domain {array real} parameter_breaks {array real} parameter_mapping text fit_performed bool definition {named native_sketch_definition}
        domain_basis text training_domain_status text sampling {record {method text source_count int indices {array int} point_count int error_bound text}}}}}}
::GX::nativeWorkspaceShapeRegister cwb_endpoint {record {point {array real} derivative {array real} point_index int}}
::GX::nativeWorkspaceShapeRegister cwb_bridge {record {kind text controls {array {array real}} start {named cwb_endpoint} end {named cwb_endpoint}
    start_derivative {array real} end_derivative {array real} c0 bool c1_start bool c1_end bool tangent_start bool tangent_end bool subdivisions int tolerance real parameter_policy text
    point {array real} from_fragment {tuple {text int int bool}} to_fragment {tuple {text int int bool}}}}
# The owner's older operation labels are explicitly text. Structured operations
# carry the declared 'operation' discriminator; unknown structured fields reject.
proc ::GX::CurveWorkbench::workspaceOperationEncode {operation} {
    if {[catch {dict exists $operation operation} structured] || !$structured} {return [list text $operation]}
    set fields {operation text api_id text family text authority text source text source_object text source_document text source_feature text
        target_curve text relationship text geometry_operation text source_authority text sampling_policy text policy text lifecycle text
        name text dataset text object text representation text rationale text schema text working_unit text copy_policy text
        first real last real tolerance real source_index int target_index int start int count int ordinal int junction int part_index int reference int
        reversed bool closed bool periodic bool originals_preserved bool inputs_preserved bool input_preserved bool source_preserved bool merge bool
        numeric_values_changed bool source_dataset_modified bool
        targets {array text} inputs {array text} indices {array int} logical_index {array int} units {array text} previous_units {array text}
        matrix {array real} frame {array real} pivot {array real} sampling {named cwb_sampling} definition {named native_sketch_definition}
        fragment_id text source_reference {named fitter_result_reference} provenance {map text} input_provenance {array {codec ::GX::CurveWorkbench::workspaceConversionEncode}}}
    set kind [dict get $operation operation]
    switch -- $kind {
        fragment_materialization {dict set fields definition {named cwb_fragment_definition}}
        extension_transaction {dict set fields parameters {array {named cwb_extension_operation}}}
        series - parametric_rectangular_series {dict set fields parameters {named cwb_series_parameters}}
        default {dict set fields parameters {record {dx real dy real angle real degrees real sx real sy real ax real ay real bx real by real scale real scale_x real scale_y real x real y real pivot_x real pivot_y real copy bool matrix {array real} pivot {array real} translation {array real}}}}
    }
    return [::GX::nativeWorkspaceEncode [list record $fields] $operation]
}
proc ::GX::CurveWorkbench::workspaceOperationDecode {typed} {tailcall ::GX::nativeWorkspaceScientificDecode $typed}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::CurveWorkbench::workspaceOperationEncode ::GX::CurveWorkbench::workspaceOperationDecode
proc ::GX::CurveWorkbench::workspaceConversionEncode {record} {
    if {[dict exists $record schema] && [dict get $record schema] eq {gxtxt.fitter_workbench_transfer.v1}} {return [::GX::nativeWorkspaceEncode {named cwb_fit_transfer} $record]}
    if {![dict exists $record operation]} {error {Conversion provenance requires its declared transfer schema or operation discriminator}}
    tailcall workspaceOperationEncode $record
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::CurveWorkbench::workspaceConversionEncode ::GX::CurveWorkbench::workspaceOperationDecode
::GX::nativeWorkspaceShapeRegister cwb_curve {record {
    id text name text source text x text y text source_x_name text source_y_name text filter text filter_value text family text order text
    parents {array text} ancestors {array {named cwb_curve}} operations {array {codec ::GX::CurveWorkbench::workspaceOperationEncode}}
    samples {array {record {x scientific_real y scientific_real row int order text point_id text}}}
    control_points {array {record {x scientific_real y scientific_real row int order text point_id text}}}
    representation text visible bool locked bool edited bool selectable bool reference bool breaks {array int}
    dataset_binding_only bool point_count int source_request {named curve_request} source_descriptor {named curve_descriptor} source_state text
    geometry_resource {resource {named resource_metadata}} row_resource {resource {named resource_metadata}} gap_resource {resource {named resource_metadata}}
    direction {named native_direction} sketch_definition {named native_sketch_definition} sketch_samples int geometry_authority text
    working_unit text sketch_units {array text} coordinate_units {array text} coordinate_relations {map {named cwb_coordinate_relation}}
    coordinate_snapshot {named cwb_coordinate_context} coordinate_snapshot_variables {map text} source_assumed_units {map text}
    coordinate_conversions {array {named cwb_coordinate_conversion}} coordinate_declarations {array {named cwb_declaration}} coordinate_frame_origins {array {named cwb_frame_origin}}
    sketch_attributes {map text} attributes {map text} display_style text materialization_sampling {named cwb_sampling} bridge_descriptors {array {named cwb_bridge}}
    materialization_policy {record {source_samples text bridge_subdivisions int spline_subdivisions int analytic_bridge_controls_retained bool}}
    retained_fit {record {schema text source_reference {named fitter_result_reference} record {named fitter_accepted_record} immutable_import_snapshot bool}}
    conversion_provenance {codec ::GX::CurveWorkbench::workspaceConversionEncode} sketch_provenance {named cwb_planar_provenance}
}}
::GX::nativeWorkspaceShapeRegister cwb_constraint {record {id text name text expression text definition {record {
    kind text a text b text axis text a_index int b_index int axis_index int value real tolerance real angular_tolerance real curvature_tolerance real
    disabled bool solved bool driven bool placed bool branch int annotation {array real} anchor {array real}
}}}}
::GX::nativeWorkspaceShapeRegister cwb_group {record {name text members {array text} visible bool locked bool sketch_attributes {map text}}}
::GX::nativeWorkspaceShapeRegister cwb_fragment {record {id text name text definition {named cwb_fragment_definition} state text sketch_attributes {map text}}}
::GX::nativeWorkspaceShapeRegister cwb_layer {record {id text name text properties {record {visible bool locked bool selectable bool order int opacity real}} members {array text}}}
::GX::nativeWorkspaceShapeRegister cwb_selection_set {record {id text name text members {array {record {kind text id text index int topology_identity text}}} states {array {record {valid bool missing bool}}}}}
::GX::nativeWorkspaceShapeRegister cwb_saved_view {record {name text snapshot {record {view_state {named view2d} curve_visibility {map bool} group_visibility {map bool} layer_visibility {map bool} coordinate_units {map {array text}}}}}}
::GX::nativeWorkspaceShapeRegister cwb_series {record {name text sources {array text} members {array text} cells {map {array text}} parameters {named cwb_series_parameters} frame {array real} origin_policy text}}
::GX::nativeWorkspaceShapeRegister cwb_parameters {map {record {formula text label text description text unit text type text min scientific_real max scientific_real editable bool}}}
::GX::nativeWorkspaceShapeRegister cwb_image {record {id text name text resource {resource {named resource_metadata}} state {named reference_image} planar_reference {named cwb_planar_reference}}}
::GX::nativeWorkspaceShapeRegister cwb_comparison_definition {record {reference text target text derived text method text budget int}}
::GX::nativeWorkspaceShapeRegister cwb_comparison_frame {record {schema_version int method text reference_units {array text} target_units {array text} output_units {array text} reference_matrix {array real} target_matrix {array real}}}
::GX::nativeWorkspaceShapeRegister cwb_comparison_receipt {record {
    count int count_a int count_b int max_index int max_source_index int sample_budget int display_rows int display_is_scientific_data bool row_indices {array int}
    max_absolute real mean_absolute real rmse real rms_a_to_b real rms_b_to_a real hausdorff real minimum_distance real length_a real length_b real length_difference real area_a real area_b real area_difference real
    symmetric_rmse real hausdorff_sampled real closest_distance real area_supported bool projection_exact_a bool projection_exact_b bool
    closest_a {array real} closest_b {array real} sampling_a text sampling_b text policy text rows {array {tuple {real real real {array real} {array real}}}}
    projection_exact bool closest_exact bool coordinate_frame {named cwb_comparison_frame} statistics {map {named statistical_result}} unit text area_unit text
}}
::GX::nativeWorkspaceShapeRegister cwb_comparison {record {definition {named cwb_comparison_definition} fingerprints {map text} sources {map {record {dataset_id text descriptor {named curve_descriptor}}}} receipt {named cwb_comparison_receipt} coordinate_presentation_signature text}}
::GX::nativeWorkspaceShapeRegister cwb_measurement {record {id text name text definition {record {kind text a text b text a_index int b_index int pair_budget int sample_budget int}}
    receipt {record {value real unit_power int angular bool exact bool point_a {array real} point_b {array real} policy text unit text unit_declared bool comparison_summary {named cwb_comparison_receipt}}}
    fingerprints {map text} sources {map {record {dataset_id text descriptor {named curve_descriptor}}}}
}}
::GX::nativeWorkspaceShapeRegister cwb_cad {record {
    publication_arrangement text publication_representation text groups {map {named cwb_group}} next_group int active text selection {array text}
    target_group text target_scope text tool text object_snap bool pivot {named cwb_pivot} gizmo {named cwb_gizmo}
    grid {named cwb_grid} presentation {named presentation2d} view_requested {named cwb_view}
    coordinate_presentation {map {map text}} coordinate_view {named cwb_coordinate_view} coordinate_frame_views {map {record {view {named cwb_view} presentation {named presentation2d} coordinate_view {named cwb_coordinate_view}}}}
    coordinate_configuration {named cwb_configuration} coordinate_metric text planar_context {named cwb_planar_context} bridge_tolerance real
    point_selection {named native_selection} sketch_dataset {record {id text sha256 text}} constraints {map {named cwb_constraint}} next_constraint int measurements {map {named cwb_measurement}} next_measurement int
    sketch_attributes {map text} fragments {map {named cwb_fragment}} next_fragment int selection_sets {map {named cwb_selection_set}} next_selection_set int
    layers {map {named cwb_layer}} next_layer int curve_visibility {map bool} saved_views {map {named cwb_saved_view}} next_saved_view int
    series_containers {map {named cwb_series}} next_series int geometric_comparison {named cwb_comparison} comparison_method text show_constraints bool show_dimensions bool
    viewport_preferences {map bool} reference_images {map {named cwb_image}} next_image int semantic_selection {array {named cwb_semantic_ref}}
    explicit_comparison {record {enabled bool config {named cwb_comparison_definition} record {named cwb_comparison}}}
    parameter_definitions {named cwb_parameters} session_parameters {named cwb_parameters}
    scientific_recipe {codec ::GX::CurveWorkbench::workspaceHistoryEncode} history_auxiliary {named cwb_auxiliary}
}}
# Reuse the existing exact Native2D grid declaration.
::GX::nativeWorkspaceShapeRegister cwb_grid [dict get [lindex [dict get $::GX::WorkspaceScientificCodec::shapes presentation2d] 1] grid]
set ::GX::CurveWorkbench::workspaceAuxFields {
    next int nextGroup int nextConstraint int nextMeasurement int nextFragment int nextSelectionSet int nextLayer int nextSavedView int nextSeries int nextImage int
    active text reference text target text externalFeedback text bridgeKind text bridgeSubdivisions int bridgeTolerance real fragments {array {tuple {text int int bool}}} composeName text resultId text
    cadGroup text cadTarget text cadTool text cadObjectSnap bool coordinatePresentation {map {map text}} coordinateView {named cwb_coordinate_view}
    coordinateFrameViews {map {record {view {named cwb_view} presentation {named presentation2d} coordinate_view {named cwb_coordinate_view}}}}
    metric text directionShown bool gridShown bool gridSnap bool leftVisible bool listVisible bool pointsVisible bool composeVisible bool compareVisible bool
    comparisonEnabled bool comparisonConfig {named cwb_comparison_definition} comparisonRecord {named cwb_comparison} lastGeometricComparison {named cwb_comparison}
    publicationArrangement text publicationRepresentation text showConstraints bool showDimensions bool
}
::GX::nativeWorkspaceShapeRegister cwb_auxiliary [list record [dict create format text fields [list record $::GX::CurveWorkbench::workspaceAuxFields] native {record {view_requested {named cwb_view} aspect text background {array real} grid {named cwb_grid} presentation {named presentation2d} gizmo {named cwb_gizmo} pivot {named cwb_pivot}}} selection {array {named cwb_semantic_ref}} point_selection {named native_selection}]]
proc ::GX::CurveWorkbench::workspaceHistoryStateEncode {state} {
    set fields {};dict for {id record} $state {
        if {$id eq {@cad}} {set encoded [::GX::nativeWorkspaceEncode {named cwb_cad} $record]} elseif {$record in {{} @gxtxt.recipe.delete}} {set encoded [list text $record]} else {set encoded [::GX::nativeWorkspaceEncode {named cwb_curve} $record]}
        dict set fields $id $encoded
    };return [list object $fields]
}
proc ::GX::CurveWorkbench::workspaceHistoryEncode {record} {
    set typed [::GX::nativeWorkspaceHistoryEncode $record ::GX::CurveWorkbench::workspaceHistoryStateEncode]
    if {[dict exists $record steps]} {
        set steps {};foreach step [dict get $record steps] encoded [lindex [dict get [lindex $typed 1] steps] 1] {
            set fields [lindex $encoded 1]
            if {[dict exists $step parameters]} {dict set fields parameters [::GX::nativeWorkspaceEncode {map {array {codec ::GX::CurveWorkbench::workspaceOperationEncode}}} [dict get $step parameters]]}
            foreach key {undo_auxiliary auxiliary} {if {[dict exists $step $key]} {dict set fields $key [::GX::nativeWorkspaceEncode {named cwb_auxiliary} [dict get $step $key]]}}
            lappend steps [list object $fields]
        }
        set fields [lindex $typed 1];dict set fields steps [list array $steps];set typed [list object $fields]
    }
    return $typed
}
proc ::GX::CurveWorkbench::workspaceHistoryDecode {typed} {tailcall ::GX::nativeWorkspaceScientificDecode $typed}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::CurveWorkbench::workspaceHistoryEncode ::GX::CurveWorkbench::workspaceHistoryDecode
::GX::nativeWorkspaceShapeRegister cwb_workspace {record {
    version int curves {map {named cwb_curve}} next int active text selected_indices {array int} view {named cwb_view} reference text target text external_feedback text
    view_requested {named cwb_view} aspect text grid {named cwb_grid} background {array real} presentation {named presentation2d}
    composition_settings {record {bridge_kind text subdivisions int tolerance real}} cad_workspace {named cwb_cad} selection_descriptor {named native_selection}
    coordinate_configuration {named cwb_configuration}
}}
proc ::GX::CurveWorkbench::workspaceEncode {payload} {tailcall ::GX::nativeWorkspaceEncode {named cwb_workspace} [dict remove $payload workspace_metadata]}
proc ::GX::CurveWorkbench::workspaceDecode {typed} {tailcall ::GX::nativeWorkspaceScientificDecode $typed}
