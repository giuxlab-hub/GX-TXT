# SPDX-License-Identifier: GPL-3.0-or-later
# Typed projections of the existing Viewer Provider scene/layer contracts.
# Semicolon protocol vectors remain lexical text under that public contract.
::GX::nativeWorkspaceShapeRegister scene3d {record {
    camera_position text camera_target text camera_up text projection text navigation_cube_visible bool
    orthographic_height real near_clip real far_clip real clipping_planes text clip_box text scene_mode text
    background_rgb text background_bottom_rgb text background_gradient bool lighting bool lighting_ambient real lighting_diffuse real lighting_specular real
    lighting_direction text lighting_color text lighting_intensity real lighting_lights text
    axes_world bool axes_local_layer text axes_reference_marker text axes_size_pixels real orientation_indicator_visible bool
    working_plane_origin text working_plane_normal text working_plane_u_axis text working_plane_visible bool active_timeline_id text
    marker_definitions {array {record {id text layer_id text occurrence_index int local_point text kind text size_pixels real color text visible bool}}}
    measurement_definitions {array {record {id text kind text marker_a text marker_b text marker_c text visible bool show_value bool color text size_pixels real line_width real}}}
    curve_definitions {array {record {id text kind text source_layer text occurrence_index int origin text normal text u_axis text visible bool color text line_width real opacity real join_tolerance real}}}
    timeline_definitions {array {record {id text unit text times {array real} tracks {array {record {id text frames {array text}}}} current_frame int current_time real range_first int range_last int rate real loop text state text}}}
    field_definitions {array {record {id text kind text timeline_id text source_track text source_layer text vector_array_index int scalar_array_index int seed_kind text seed_points {array text} seed_origin text seed_u text seed_v text seed_u_count int seed_v_count int direction text step_size real time_step real min_magnitude real tube_radius real max_steps int max_points int max_memory_bytes int origin text u_step text v_step text u_count int v_count int scalar_name text value real}}}
}}
::GX::nativeWorkspaceShapeRegister texture3d {record {
    schema text resource {resource {named resource_metadata}} source_geometry_sha256 text source_triangle int occurrence_index int local_anchor text
    anchor_u real anchor_v real width real height real rotation_radians real flip_u bool flip_v bool working_unit text image_width int image_height int image_bit_depth int
    mapping {record {source_resource {resource {named resource_metadata}} target_working_unit text target_physical_width real target_physical_height real mapping_policy text}} provenance {named resource_metadata}
}}
proc ::GX::_nativeWorkspaceTexture3DEncode {value} {
    if {$value eq {}} {return {text {}}}
    return [nativeWorkspaceEncode {named texture3d} $value]
}
::GX::nativeWorkspaceShapeRegister layer3d {record {
    kind text source_mode text dataset_id text resource_path text sha256 text format text format_version text source_path_hint text
    x_variable_id text y_variable_id text z_variable_id text visible bool opacity real colormap text scalar_range text color_array text scalar_array text vector_array text radius_array text opacity_array text
    tube_radius real isovalues text volume_transfer text volume_sample_distance real layer_order int source_dataset_id text source_dataset_sha256 text source_update_policy text representation text base_color text
    line_width real point_size real sphere_glyphs {codec ::GX::_nativeWorkspaceOptionalBool3DEncode} backface_culling bool scalar_coloring bool local_transform text texture {codec ::GX::_nativeWorkspaceTexture3DEncode}
    absolute_path text attributes {map {record {kind text variable_ids text unit text semantic_role text resource_path text sha256 text format text format_version text}}}
}}
proc ::GX::_nativeWorkspaceOptionalBool3DEncode {value} {if {$value eq {}} {return {text {}}};return [nativeWorkspaceEncode bool $value]}
::GX::nativeWorkspaceShapeRegister figure3d {record {
    tick_labels {array {array text}} physical_axis_ranges {array {array real}} axes_grid_visible bool colorbar_visible bool bounds_min text bounds_max text axis_min text axis_max text
    x_label text y_label text z_label text title text legend text scalar_label text scalar_min real scalar_max real palette {array text}
    aspect_policy {record {mode text normalized_box {array real}}}
    native_style {record {font_size real axis_label_font_size real title_font_size real legend_font_size real legend_x real legend_y real legend_alignment int
        legend_background bool legend_border bool legend_background_r real legend_background_g real legend_background_b real legend_border_r real legend_border_g real legend_border_b real
        margin_left real margin_right real margin_top real margin_bottom real xgrid bool ygrid bool zgrid bool grid_r real grid_g real grid_b real}}
}}
