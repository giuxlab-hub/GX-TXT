# SPDX-License-Identifier: GPL-3.0-or-later
# Schema adapters for existing scientific owners. Shapes are selected by public
# contract/field identity, never by Tcl cache type or dict/list parseability.
namespace eval ::GX::WorkspaceScientificCodec {variable shapes {};variable decoders {}}
proc ::GX::nativeWorkspaceCodecDecodeRegister {encode decode} {
    if {[dict exists $::GX::WorkspaceScientificCodec::decoders $encode] && [dict get $::GX::WorkspaceScientificCodec::decoders $encode] ne $decode} {error {Scientific codec decoder cannot change at runtime}}
    dict set ::GX::WorkspaceScientificCodec::decoders $encode $decode
}
proc ::GX::nativeWorkspaceShapeRegister {name shape} {
    if {[dict exists $::GX::WorkspaceScientificCodec::shapes $name] && [dict get $::GX::WorkspaceScientificCodec::shapes $name] ne $shape} {error "Scientific Workspace shape '$name' cannot change at runtime"}
    dict set ::GX::WorkspaceScientificCodec::shapes $name $shape
}
proc ::GX::_nativeWorkspaceOriginEncode {origin} {
    set fields {}
    dict for {key value} $origin {
        switch -- $key {
            version {set shape int}
            creator_installation - created_at - creation_kind {set shape text}
            events {set shape {array {map text}}}
            parent {set shape {codec ::GX::_nativeWorkspaceOriginParentEncode}}
            default {error "Undeclared scientific origin field '$key'"}
        }
        dict set fields $key [nativeWorkspaceEncode $shape $value]
    }
    return [list object $fields]
}
proc ::GX::_nativeWorkspaceOriginParentEncode {parent} {
    set fields {}
    dict for {key value} $parent {
        switch -- $key {
            session_origin - source_origin - origin_snapshot {set shape {named origin}}
            source_dataset_origins {set shape {map {named origin}}}
            document_id - source_id - source_session_id - source_installation - source_sha256 {set shape text}
            revision {set shape int}
            default {error "Undeclared scientific origin parent '$key'"}
        }
        dict set fields $key [nativeWorkspaceEncode $shape $value]
    }
    return [list object $fields]
}
::GX::nativeWorkspaceShapeRegister origin {codec ::GX::_nativeWorkspaceOriginEncode}
::GX::nativeWorkspaceShapeRegister document_receipt {record {id text document_id text module_id text provider_id text format text format_version text generation text revision int sha256 text storage_name text created_at text updated_at text origin {named origin} native_workspace bool}}
::GX::nativeWorkspaceShapeRegister source_guard {record {document_id text generation text revision int sha256 text}}
::GX::nativeWorkspaceShapeRegister em_model {record {kind text model_id text formulation text half_width_m real height_m real mesh_size_m real radius_m real current_density_A_m2 real mu_r real voltage_V real eps_r real}}
::GX::nativeWorkspaceShapeRegister diagram {codec ::GX::_nativeWorkspaceDiagramEncode}
proc ::GX::_nativeWorkspaceDiagramEncode {payload} {
    set shapes {schema text catalog text next_id int junctions {map {array real}} wires {map {record {start {array text} end {array text} route {array {array real}}}}} labels {map {record {endpoint {array text} text text offset {array real}}}}}
    set fields {};set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    dict for {key value} $payload {
        if {$key eq {components}} {
            set components {};dict for {id component} $value {dict set components $id [_nativeWorkspaceDiagramComponentEncode $catalog $component]}
            dict set fields $key [list object $components]
        } else {dict set fields $key [nativeWorkspaceEncode [dict get $shapes $key] $value]}
    }
    return [list object $fields]
}
proc ::GX::_nativeWorkspaceDiagramComponentEncode {catalog component} {
    # Attribute kinds are contributed by the owning symbol catalog. The model
    # already admitted/normalized numeric attributes through that same owner.
    set fields {}
    dict for {key value} $component {
        if {$key eq {attributes}} {
            set attributes {};set symbol [dict get $catalog symbols [dict get $component kind]]
            dict for {attribute data} $value {
                set datatype [dict get $symbol attributes $attribute type]
                dict set attributes $attribute [nativeWorkspaceEncode [expr {$datatype eq {number}?{real}:{text}}] $data]
            }
            dict set fields $key [list object $attributes]
        } else {
            dict set fields $key [nativeWorkspaceEncode [dict get {kind text name text position {array real} rotation int} $key] $value]
        }
    }
    return [list object $fields]
}
proc ::GX::_nativeWorkspaceDocumentStampEncode {stamp} {
    # Dataset INI fields and variable descriptors are published lexical maps;
    # each field is retained separately. File identity counters are integers.
    if {[lindex $stamp 0] eq {remote}} {set shape {tuple {text text text text {array {map text}}}}} else {set shape {tuple {{map text} {array {map text}} int int int int {map text}}}}
    return [nativeWorkspaceEncode $shape $stamp]
}
::GX::nativeWorkspaceShapeRegister document_binding {record {kind text content_kind text dataset_id text session text path text source_sha256 text stamp {codec ::GX::_nativeWorkspaceDocumentStampEncode}}}
::GX::nativeWorkspaceShapeRegister curve_filter {record {filter_variable_id text predicate text dtype text value text lower text upper text values {array text}}}
::GX::nativeWorkspaceShapeRegister curve_request {record {dataset_id text x_variable_id text y_variable_id text member_id text filters {array {named curve_filter}} selection_id text start int count int display_budget int transform_manifest {named transform_manifest} order_variable_id text}}
::GX::nativeWorkspaceShapeRegister curve_binding {record {kind text source_id text request {named curve_request}}}
::GX::nativeWorkspaceShapeRegister transform_source {record {
    dataset_id text member_id text variable_ids {array text} variable_map {map text} x_variable_id text y_variable_id text
    start int count int rows {array int} row_operation text row_filters {array {named curve_filter}} selection_filters {array {named curve_filter}} selection_operation text
    family_coordinates {map real} convert_units {map text} assume_units {map text} selection_id text order_variable_ids {array text} reverse bool
    native_geometry {record {xy_resource {resource {named resource_metadata}} row_resource {resource {named resource_metadata}} gap_resource {resource {named resource_metadata}} x_variable {map text} y_variable {map text}}}
}}
::GX::nativeWorkspaceShapeRegister transform_manifest {record {
    api_id text api_version int operation text sources {array {named transform_source}}
    output {record {dataset_id text member_outputs {map text} contract text storage text display_name text notes text}}
    schema_policy {map text} metadata_policy text
    options {record {
        variable_ids {array text} rename {map text} display_labels {map text} start int count int reorder {array text}
        ranges {array {array int}} steps {array {array int}} keys {array {array text}} mode text join text duplicate_policy text representation text x_tolerance real
        member_id text members {array text} member_variable_id text source_member_ids {array text} family_axes {array text} family_units {map text} target_units {map text}
        x_variable_id text y_variable_id text matrix {array real} metadata {map text} metadata_overrides {map text}
        include_lineage bool lineage_prefix text order_variable_ids {array text} descending bool preserve_auxiliary bool calibration_variable_ids {array text} expected_coordinate_revision int
        polar_output {record {representation text frame {record {origin {array real} theta_zero real clockwise bool degrees bool}} x_variable_id text y_variable_id text theta_variable_id text radius_variable_id text angle_defined_variable_id text}}
        baseline_options {record {method text lambda real p real max_iterations real tolerance real grid_policy text nonfinite text value real estimator text degree real}}
        smoothing_options {record {method text window real degree real robust_iterations real nonfinite text}}
        logarithms {array {record {source_variable_id text output_variable_id text reference real}}}
        baseline_variable_id text corrected_variable_id text row_variable_id text smoothed_variable_id text residual_variable_id text
    }}
}}
::GX::nativeWorkspaceShapeRegister curve_descriptor {record {api_id text api_version int source_id text source_kind text row_identity_kind text request {named curve_request} row_count int variables {array {map text}} source_identities {array {record {dataset_id text sha256 text schema_identity text}}} display_budget int display_is_scientific_data bool batch_context {record {session_origin {named origin} continuity_policy text continuity_variable_id text}}}}
::GX::nativeWorkspaceShapeRegister view2d {record {
    viewport {tuple {real real real real real real {array real}}}
    grid {record {enabled bool visible bool snap_enabled bool major_visible bool minor_visible bool axes_visible bool spacing_x real spacing_y real angle real major_width real minor_width real axes_width real major_style int minor_style int axes_style int major_interval int origin {array real} major_color {array real} minor_color {array real} axes_color {array real}}}
    background {array real} aspect text coordinate_mode text
    polar {record {origin {array real} theta_zero real clockwise bool degrees bool radius_min real radius_max real angle_min real angle_span real radial_spacing real angular_spacing real radial_major_interval int angular_major_interval int}}
    axis_presentation {map {record {title text unit_label text ticks {record {placement text step {number_or_symbol {auto}} format text precision int}} context {record {kind text source_unit text target_unit text image_id int image_resource_id text}}}}}
}}
::GX::nativeWorkspaceShapeRegister diagram_binding {record {kind text document_id text document_receipt {named document_receipt} payload {named diagram} view_state {named view2d}}}
proc ::GX::_viewerWorkspaceShapeEncode {shape value} {return [nativeWorkspaceEncode $shape $value]}
# Scientific Transport supplies this type tree at the existing native Numeric
# boundary. Consume its declared kinds; never discover a shape from Tcl text.
proc ::GX::nativeWorkspaceTransportShape {types path value {depth 0}} {
    if {$depth>32} {error {Scientific transport shape exceeds nesting bound}}
    if {![dict exists $types $path]} {error "Scientific transport lacks a declared kind for '$path'"}
    switch -- [dict get $types $path] {
        struct {
            set fields {};dict for {field child} $value {dict set fields $field [nativeWorkspaceTransportShape $types $path.$field $child [expr {$depth+1}]]}
            return [list record $fields]
        }
        cell {
            set shapes {};set index 0;foreach child $value {lappend shapes [nativeWorkspaceTransportShape $types $path.item[incr index] $child [expr {$depth+1}]]}
            return [list tuple $shapes]
        }
        number {return scientific_real}
        integer {return int}
        string {return text}
        boolean {return bool}
        vector {return {array scientific_real}}
        matrix {return {array {array scientific_real}}}
        tensor {return {record {shape {array int} values {array scientific_real}}}}
        complex_number {return {record {real scientific_real imaginary scientific_real}}}
        complex_vector {return {record {real {array scientific_real} imaginary {array scientific_real}}}}
        complex_matrix {return {record {real {array {array scientific_real}} imaginary {array {array scientific_real}}}}}
        complex_tensor {return {record {shape {array int} real {array scientific_real} imaginary {array scientific_real}}}}
        default {error "Unsupported declared scientific transport kind '[dict get $types $path]'"}
    }
}
proc ::GX::nativeWorkspaceTransportSubtypes {types prefix} {
    set result {};dict for {path kind} $types {
        if {$path eq $prefix} {dict set result value $kind} elseif {[string first $prefix. $path]==0} {dict set result value[string range $path [string length $prefix] end] $kind}
    };return $result
}
proc ::GX::nativeWorkspaceShapePayloadEncode {shape payload} {
    set fields {}
    dict for {key value} $payload {
        if {$value eq {@gxtxt.recipe.delete}} {dict set fields $key [list text $value]} elseif {$key in {history scientific_history}} {
            dict set fields $key [nativeWorkspaceHistoryEncode $value [list ::GX::nativeWorkspaceShapePayloadEncode $shape]]
        } else {dict set fields $key [dict get [lindex [nativeWorkspaceEncode $shape [dict create $key $value]] 1] $key]}
    }
    return [list object $fields]
}
proc ::GX::nativeWorkspaceShapeDecode {shape typed {depth 0}} {
    if {$depth>64} {error {Scientific Workspace decoding exceeds nesting bound}}
    lassign $shape kind contract;lassign $typed actual value
    switch -- $kind {
        named {return [nativeWorkspaceShapeDecode [dict get $::GX::WorkspaceScientificCodec::shapes $contract] $typed [expr {$depth+1}]]}
        scientific_real {
            if {$actual eq {real}} {return $value}
            if {$actual ne {object}} {error {A scientific number needs a real or explicit nonfinite descriptor}}
            set marker [nativeWorkspaceDecode $typed]
            if {[lsort [dict keys $marker]] ne {classification value} || [dict get $marker classification] ne {scientific_nonfinite} || [string tolower [dict get $marker value]] ni {nan inf +inf -inf infinity +infinity -infinity}} {error {Invalid explicit scientific nonfinite descriptor}}
            return [dict get $marker value]
        }
        record - map {
            if {$actual ne {object}} {error {Scientific Workspace record must be an object}}
            set result {}
            dict for {field child} $value {
                if {$kind eq {record} && $field in {history scientific_history}} {dict set result $field [nativeWorkspaceHistoryDecode $child [list ::GX::nativeWorkspaceShapeDecode $shape]];continue}
                set childShape [expr {$kind eq {map}?$contract:[dict get $contract $field]}]
                if {[lindex $child 0] eq {text} && [lindex $child 1] eq {@gxtxt.recipe.delete}} {dict set result $field @gxtxt.recipe.delete} else {dict set result $field [nativeWorkspaceShapeDecode $childShape $child [expr {$depth+1}]]}
            }
            return $result
        }
        array - tuple {
            if {$actual ne {array}} {error {Scientific Workspace collection must be an array}}
            if {$kind eq {tuple} && [llength $value]!=[llength $contract]} {error {Scientific Workspace tuple differs from its declared shape}}
            set result {};set index 0
            foreach child $value {set childShape [expr {$kind eq {array}?$contract:[lindex $contract $index]}];lappend result [nativeWorkspaceShapeDecode $childShape $child [expr {$depth+1}]];incr index}
            return $result
        }
        resource {
            if {$actual ne {resource}} {error {Scientific resource field must retain its managed-reference kind}}
            set result {};dict for {field child} $value {
                if {$field eq {metadata}} {dict set result $field [nativeWorkspaceShapeDecode $contract $child [expr {$depth+1}]]} else {dict set result $field [nativeWorkspaceDecode $child]}
            };return $result
        }
        codec {
            if {[dict exists $::GX::WorkspaceScientificCodec::decoders $contract]} {return [uplevel #0 [list {*}[dict get $::GX::WorkspaceScientificCodec::decoders $contract] $typed]]}
            return [nativeWorkspaceDecode $typed]
        }
        number_or_symbol {
            if {$actual eq {real} || ($actual eq {text} && $value in $contract)} {return $value}
            error {Scientific numeric/symbol field differs from its declared contract}
        }
        text - int - real - bool - null {
            if {$actual ne $kind} {error "Scientific scalar requires '$kind', received '$actual'"}
            return $value
        }
        default {return [nativeWorkspaceDecode $typed]}
    }
}
::GX::nativeWorkspaceShapeRegister presentation2d [list record [dict remove [lindex [dict get $::GX::WorkspaceScientificCodec::shapes view2d] 1] viewport axis_presentation]]
::GX::nativeWorkspaceShapeRegister plot_style {record {color text line_style text marker text marker_fill text line_width {number_or_symbol {{} auto inherit}} marker_size {number_or_symbol {{} auto inherit}} opacity {number_or_symbol {{} auto inherit}}}}
# PlotSpec v2 declares semicolon strings, not Tcl lists. Preserve the exact
# source spelling/captions; only explicit historical typed arrays are converted.
::GX::nativeWorkspaceShapeRegister plot_axis_values {record {label text display_unit text scale text direction text min {number_or_symbol {{} auto}} max {number_or_symbol {{} auto}} major_step {number_or_symbol {{} auto}} minor_grid {number_or_symbol {{} auto off}}}}
proc ::GX::_nativeWorkspacePlotAxisEncode {axis} {
    set ordinary $axis
    foreach field {tick_positions tick_labels} {catch {dict unset ordinary $field}}
    set typed [nativeWorkspaceEncode {named plot_axis_values} $ordinary]
    if {[dict exists $axis tick_positions] != [dict exists $axis tick_labels]} {error {Plot Workspace tick positions and captions require the same paired source}}
    if {[dict exists $axis tick_positions]} {
        set positions [dict get $axis tick_positions];set labels [dict get $axis tick_labels]
        if {$positions ne {} || $labels ne {}} {
            set fields [lindex $typed 1]
            foreach field {tick_positions tick_labels} {dict set fields $field [list text [dict get $axis $field]]}
            lset typed 1 $fields
        }
    }
    return $typed
}
proc ::GX::_nativeWorkspacePlotAxisDecode {typed} {
    lassign $typed kind fields
    if {$kind ne {object}} {error {Plot Workspace axis requires its declared object}}
    set ordinary $fields
    foreach field {tick_positions tick_labels} {catch {dict unset ordinary $field}}
    set axis [nativeWorkspaceShapeDecode {named plot_axis_values} [list object $ordinary]]
    if {[dict exists $fields tick_positions] != [dict exists $fields tick_labels]} {error {Plot Workspace has an incomplete tick pair; review its original source}}
    if {![dict exists $fields tick_positions]} {return $axis}
    foreach field {tick_positions tick_labels} {if {[llength [dict get $fields $field]]!=2} {error {Malformed typed Plot Workspace tick source}}}
    lassign [dict get $fields tick_positions] positionKind positions
    lassign [dict get $fields tick_labels] labelKind labels
    if {$positionKind eq {text} && $labelKind eq {text}} {
        if {$positions eq {} && $labels eq {}} {return $axis}
        # Exact canonical source, including Unicode/whitespace/order. Actual
        # Plot semantic validation remains in the public Plot owner on restore.
        dict set axis tick_positions $positions;dict set axis tick_labels $labels
        return $axis
    }
    if {$positionKind ne {array} || $labelKind ne {array}} {error {Plot Workspace tick source mixes canonical text and legacy types; no source was reconstructed}}
    if {[llength $positions]!=[llength $labels]} {error {Legacy Plot Workspace position/caption counts differ; original caption boundaries cannot be reconstructed}}
    if {![llength $positions]} {return $axis}
    set positionText {};set labelText {}
    foreach position $positions label $labels {
        if {[llength $position]!=2 || [llength $label]!=2} {error {Legacy Plot Workspace tick elements require explicit scalar boundaries}}
        lassign $position pk value
        if {$pk ni {real int} || ![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {error {Legacy Plot Workspace has an invalid numeric tick scalar; no source was reconstructed}}
        lassign $label lk caption
        if {$lk ne {text} || [string trim $caption] eq {} || [regexp {[\x00\r\n;]} $caption]} {error {Legacy Plot Workspace caption cannot be represented losslessly by the declared semicolon source}}
        lappend positionText $value;lappend labelText $caption
    }
    dict set axis tick_positions [join $positionText {;}]
    dict set axis tick_labels [join $labelText {;}]
    return $axis
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::_nativeWorkspacePlotAxisEncode ::GX::_nativeWorkspacePlotAxisDecode
::GX::nativeWorkspaceShapeRegister plot_axis {codec ::GX::_nativeWorkspacePlotAxisEncode}
::GX::nativeWorkspaceShapeRegister plot_error {record {mode text variable_id text lower_variable_id text upper_variable_id text}}
::GX::nativeWorkspaceShapeRegister plot_series {record {
    id text dataset_id text x_variable_id text y_variable_id text axis text kind text label text
    family_variable_id text family_label_prefix text secondary_variable_id text ordering_variable_id text
    row_filters {array {named curve_filter}} source_row_ordinals {array int} source_row_continuity bool
    enabled bool order int style {named plot_style} step_mode text
    x_error {named plot_error} y_error {named plot_error}
    band {record {lower_variable_id text upper_variable_id text draw_center bool}}
    bar_bounds {record {lower_variable_id text upper_variable_id text}}
    bar_width real bar_baseline real histogram_bins {number_or_symbol {auto}} histogram_normalization text
    box_whisker_iqr real box_show_outliers bool
    cell_field {record {schema text nodes_dataset_id text node_id_variable_id text x_variable_id text y_variable_id text cell_id_variable_id text node_variable_ids {array text} scalar_variable_id text}}
}}
::GX::nativeWorkspaceShapeRegister plot_annotation {record {id text type text axis text value real min real max real x real y real label text color text line_width real line_style text opacity real}}
# The native renderer projection contains source configuration declarations,
# not scientific samples. Its setting values remain literal text, including
# empty/inherit/auto values, units and exact caption spelling. Known nested
# Level Scale records and panel-name lists retain their declared structure.
::GX::nativeWorkspaceShapeRegister plot_level_scale_source {record {scale text quantity_kind text amplitude_basis text reference_value text reference_unit text zero_policy text}}
proc ::GX::_nativeWorkspacePlotPresentationAxesEncode {axes} {
    set result {}
    dict for {key value} $axes {
        if {$key in {y_level_scale y2_level_scale z_level_scale}} {
            levelScaleValidate $value
            set shape {named plot_level_scale_source}
        } elseif {$key eq {panels}} {set shape {array text}} else {set shape text}
        dict set result $key [nativeWorkspaceEncode $shape $value]
    }
    return [list object $result]
}
proc ::GX::_nativeWorkspacePlotPresentationAxesDecode {typed} {
    lassign $typed kind fields
    if {$kind ne {object}} {error {Native Plot presentation axes require an object}}
    set result {}
    dict for {key value} $fields {
        if {$key in {y_level_scale y2_level_scale z_level_scale}} {set shape {named plot_level_scale_source}} elseif {$key eq {panels}} {set shape {array text}} else {set shape text}
        set decoded [nativeWorkspaceShapeDecode $shape $value]
        if {$key in {y_level_scale y2_level_scale z_level_scale}} {levelScaleValidate $decoded}
        dict set result $key $decoded
    }
    return $result
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::_nativeWorkspacePlotPresentationAxesEncode ::GX::_nativeWorkspacePlotPresentationAxesDecode
::GX::nativeWorkspaceShapeRegister plot_native_presentation_values {record {
    schema text graphics {map text} legend {map text}
    axes {codec ::GX::_nativeWorkspacePlotPresentationAxesEncode}
    panels {map {codec ::GX::_nativeWorkspacePlotPresentationAxesEncode}}
    layout {map text} plot_config {map text}
}}
proc ::GX::_nativeWorkspacePlotPresentationEncode {presentation} {
    if {![dict exists $presentation schema] || [dict get $presentation schema] ne {GXTXT_NATIVE_GRAPH_PRESENTATION_v1}} {error {Unsupported native Plot Workspace presentation schema}}
    return [nativeWorkspaceEncode {named plot_native_presentation_values} $presentation]
}
proc ::GX::_nativeWorkspacePlotPresentationDecode {typed} {
    set presentation [nativeWorkspaceShapeDecode {named plot_native_presentation_values} $typed]
    if {![dict exists $presentation schema] || [dict get $presentation schema] ne {GXTXT_NATIVE_GRAPH_PRESENTATION_v1}} {error {Unsupported native Plot Workspace presentation schema}}
    return $presentation
}
::GX::nativeWorkspaceCodecDecodeRegister ::GX::_nativeWorkspacePlotPresentationEncode ::GX::_nativeWorkspacePlotPresentationDecode
::GX::nativeWorkspaceShapeRegister plot_native_presentation {codec ::GX::_nativeWorkspacePlotPresentationEncode}
::GX::nativeWorkspaceShapeRegister comparison_source {record {kind text dataset_id text x_variable_id text y_variable_id text library_id text entry_id text sha256 text schema_sha256 text revision text semantic_sha256 text session_origin text sample_count int x_unit text y_unit text x_meaning {map text} y_meaning {map text} label text}}
::GX::nativeWorkspaceShapeRegister comparison_configuration {record {schema text sources {array {named comparison_source}} mode text normalization text offset real denominator_floor real interpolation text domain text single_source_consultation bool}}
::GX::viewerWorkspaceCodecRegister domains comparison_forms [list ::GX::_viewerWorkspaceShapeEncode {map {record {sources {array {named comparison_source}}}}}]
::GX::nativeWorkspaceShapeRegister plot_spec {record {schema text graph_type text graph_id text title text multi_panel bool defaults {record {style {named plot_style}}} panels {array {record {id text title text axes {map {named plot_axis}} series {array {named plot_series}} annotations {array {named plot_annotation}}}}} output {map text} native_presentation {named plot_native_presentation} comparison {named comparison_configuration}}}
::GX::nativeWorkspaceShapeRegister plot_binding {record {kind text spec {named plot_spec} context {map text} visibility {map {map bool}} view_axes {array {record {panel_id text axis text limits {array real} scale text direction text}}}}}
::GX::viewerWorkspaceCodecRegister bindings plot [list ::GX::_viewerWorkspaceShapeEncode {named plot_binding}]
proc ::GX::_viewerWorkspaceBindingsDecode {typed} {
    lassign $typed kind fields
    if {$kind ne {object}} {return [nativeWorkspaceDecode $typed]}
    set result {}
    dict for {component binding} $fields {
        set isPlot [expr {[lindex $binding 0] eq {object} && [dict exists [lindex $binding 1] kind] && [dict get [lindex $binding 1] kind] eq {text plot}}]
        if {$isPlot} {dict set result $component [nativeWorkspaceShapeDecode {named plot_binding} $binding]
        } else {dict set result $component [nativeWorkspaceDecode $binding]}
    }
    return $result
}

::GX::nativeWorkspaceShapeRegister raster_source {record {dataset_id text dataset_identity {map text} variable_schema {array {map text}} source_sha256 text origin {named origin}}}
::GX::nativeWorkspaceShapeRegister reference_image {record {resource_id text length_unit text width real height real scale real rotation real opacity real calibrated_distance real visible bool locked bool calibrated bool translation {array real} calibration {array {array real}}}}
::GX::nativeWorkspaceShapeRegister native_direction {record {present bool visible bool forward bool interpolation int fraction real offset_px real length_px real line_width real head_scale real color {array real}}}
::GX::nativeWorkspaceShapeRegister native_style {record {visible bool selectable bool selected bool locked bool layer int order int line_style int marker int line_width real color {array real}}}
::GX::nativeWorkspaceShapeRegister native_selection_region {record {bounds {array real} mode text}}
::GX::nativeWorkspaceShapeRegister native_selection {record {base_selected bool regions {array {named native_selection_region}} manual {array {tuple {int int}}}}}
::GX::nativeWorkspaceShapeRegister native_point_mask {record {api_id text base_selected bool regions {array {named native_selection_region}} manual_rows {map int}}}
::GX::nativeWorkspaceShapeRegister native_comparison_frame {record {schema_version int method text reference_units {array text} target_units {array text} output_units {array text} reference_matrix {array real} target_matrix {array real}}}
::GX::nativeWorkspaceShapeRegister native_sketch_definition {record {
    family text controls {array {array real}} matrix {array real} parts {array {record {definition {named native_sketch_definition} reversed bool}}}
    nodes {array int} closed bool tolerance real radius_x real radius_y real rotation real angle_start real angle_sweep real
    tangents {array {tuple {int {array real} {array real}}}} segments {array {record {family text first int last int}}}
}}
::GX::nativeWorkspaceShapeRegister resource_metadata {record {
    format text media_type text encoding text role text filename text language text origin {codec ::GX::_nativeWorkspaceResourceOriginEncode}
    dependencies {array {resource {named resource_metadata}}}
    row_count int variable_schema {array {named statistical_variable_schema}} original_field_shapes {map {array int}}
    dtype text endian text order text shape {array int} unit text column_ids {array text} column_units {array text}
    columns {array text} source_curve_id text fit_curve_id text coordinate_space text boundary_ownership text index_base int
    row_index_base int model text sample_role text component_ids {array text} component_units {array text} entry_units text
    source_kind text source_dataset_id text source_sha256 text source_job_id text source_output_token text source_generation text
    scientific_authority bool disposable bool point_count int width int height int source_snapshot_origin_sha256 text
    millimeters_per_working_unit real input_unit text assumed_input_unit bool source_id text geometry_sha256 text geometry_placement text geometry_role text bounds_min {array real} bounds_max {array real} transform {array real}
    native_kind text geometry_authority text working_unit text sketch_attributes {map text}
    sketch_definition {named native_sketch_definition}
    native_direction {named native_direction} reference_image {named reference_image} image_resource {resource {named resource_metadata}}
    geometry_metadata {record {working_unit text source_kind text source_id text image_resource {resource {named resource_metadata}} raster_dataset {named raster_source}}}
    source_revision int inputs {map text} geometry {resource {named resource_metadata}}
}}
::GX::nativeWorkspaceShapeRegister raster_snapshot {record {
    schema text document_id text generation text view_state {named view2d}
    layers {array {record {key int name text attributes {map text} properties {record {visible bool selectable bool locked bool order int opacity real}}}}}
    images {array {record {resource {resource {named resource_metadata}} name text style {record {visible bool selectable bool selected bool locked bool layer int order int line_style int marker int line_width real color {array real}}}}}}
}}
::GX::nativeWorkspaceShapeRegister raster_binding {record {
    kind text document_id text document_receipt {named document_receipt} source {named raster_source} snapshot {named raster_snapshot} presentation_view_state {named view2d}
    interaction {record {tool text roi_id text annotation_id text annotation_generation text pivot {record {mode text point {array real} available bool}}}}
}}
::GX::viewerWorkspaceCodecRegister bindings raster [list ::GX::_viewerWorkspaceShapeEncode {named raster_binding}]
::GX::nativeWorkspaceShapeRegister circuit_parameters {record {analysis text step_seconds real stop_seconds real ac_grid text points int start_hz real stop_hz real source text dc_start real dc_stop real dc_step real override_component text override_value real component_values text}}
::GX::nativeWorkspaceShapeRegister scientific_job {record {job_id text state text provider_id text source_guard {named source_guard} parameters {named circuit_parameters} circuit_sha256 text destination text provider_version text dataset_id text sweep_case text node_id text session_id text backend text last_status text last_error text publication_error text}}
::GX::viewerWorkspaceCodecRegister domains scientific_jobs [list ::GX::_viewerWorkspaceShapeEncode {map {named scientific_job}}]
::GX::viewerWorkspaceCodecRegister domains scientific_netlists [list ::GX::_viewerWorkspaceShapeEncode {map {record {source_guard {named source_guard} parameters {named circuit_parameters} job_id text dataset_id text dataset_sha256 text provider_id text provider_version text text text normalized_parameters {named circuit_parameters}}}}]
::GX::viewerWorkspaceCodecRegister domains scientific_campaigns [list ::GX::_viewerWorkspaceShapeEncode {map {record {
    identity int source_guard {named source_guard} destination text expected_cases int jobs {map {named scientific_job}}
    axes {map {record {component_id text name text unit text grid {codec ::GX::_nativeWorkspaceUniformGridEncode}}}}
    admission_failures {array {record {index int id text state text error text error_code {array text} reason text stdout text stderr text}}}
    coordination {record {state text cancel_requested bool requested_workers int worker_count int total int completed int success_count int error_count int cancelled_count int not_executed_count int fallback_reason text started_at int finished_at int completion_order {array int} run_id text api_version int}}
}}}]
proc ::GX::_nativeWorkspaceUniformGridEncode {grid} {
    set shapes {x {array real} n int step real start real stop_requested real stop_actual real mode text}
    set fields {}
    dict for {key value} $grid {
        if {$key eq {step} && [string equal -nocase $value NaN]} {
            if {[dict get $grid n]!=1 || [dict get $grid mode] ne {count}} {error {Undefined grid step requires the public single-point count grid}}
            dict set fields $key [nativeWorkspaceEncode {record {classification text value text reason text}} [dict create classification scientific_nonfinite value $value reason single_point_uniform_grid]]
        } else {dict set fields $key [nativeWorkspaceEncode [dict get $shapes $key] $value]}
    }
    return [list object $fields]
}
proc ::GX::_viewerWorkspaceDomainsDecode {typed} {
    set result [nativeWorkspaceDecode $typed]
    if {[lindex $typed 0] ne {object}} {return $result}
    set fields [lindex $typed 1]
    if {![dict exists $fields scientific_campaigns]} {return $result}
    dict for {form campaign} [lindex [dict get $fields scientific_campaigns] 1] {
        if {![dict exists [lindex $campaign 1] axes]} continue
        dict for {axis descriptor} [lindex [dict get [lindex $campaign 1] axes] 1] {
            set grid [dict get [lindex $descriptor 1] grid];set step [dict get [lindex $grid 1] step]
            if {[lindex $step 0] ne {object}} continue
            set marker [nativeWorkspaceDecode $step]
            if {[lsort [dict keys $marker]] ne {classification reason value} || [dict get $marker classification] ne {scientific_nonfinite} || [dict get $marker reason] ne {single_point_uniform_grid} || ![string equal -nocase [dict get $marker value] NaN] || [dict get $result scientific_campaigns $form axes $axis grid n]!=1 || [dict get $result scientific_campaigns $form axes $axis grid mode] ne {count}} {error {Invalid explicit undefined uniform-grid step}}
            dict set result scientific_campaigns $form axes $axis grid step [dict get $marker value]
        }
    }
    return $result
}
proc ::GX::_nativeWorkspaceResourceOriginEncode {value} {
    if {$value in {canonical_circuit native2d_raster scientific_job native2d_preview}} {return [list text $value]}
    return [_nativeWorkspaceOriginEncode $value]
}
proc ::GX::_nativeWorkspaceOptionalResourceEncode {reference} {
    if {$reference eq {}} {return {object {}}}
    return [nativeWorkspaceEncode {resource {named resource_metadata}} $reference]
}
::GX::nativeWorkspaceShapeRegister tex_build {record {
    status text response text source_revision int session_token text owner_generation text inputs {map text} inputs_after {map text} source_integrity bool
    configured_runtime text driver text engine text convergence text diagnostics_scope text export_authority text
    invocations {array {record {command {array text} returncode int working_directory text elapsed_ms real}}}
    diagnostics {array {record {file text line int column int severity text source_link bool scope text native_invocation int message text}}}
    log_sha256 text log_bytes int pdf_sha256 text pdf_bytes int log {resource {named resource_metadata}} pdf {resource {named resource_metadata}}
    message text errorcode {array text}
}}
::GX::nativeWorkspaceShapeRegister tex_workspace {record {source {codec ::GX::_nativeWorkspaceOptionalResourceEncode} source_revision int assets {map {resource {named resource_metadata}}} last_build {named tex_build} last_good_pdf {record {source_revision int inputs {map text} resource {resource {named resource_metadata}}}}}}
proc ::GX::nativeWorkspaceTeXEncode {payload} {
    set fields {}
    dict for {key value} $payload {
        if {$value eq {@gxtxt.recipe.delete}} {dict set fields $key [list text $value]} elseif {$key eq {history}} {dict set fields $key [nativeWorkspaceHistoryEncode $value ::GX::nativeWorkspaceTeXEncode]} else {
            set shape [dict get $::GX::WorkspaceScientificCodec::shapes tex_workspace]
            dict set fields $key [dict get [lindex [nativeWorkspaceEncode $shape [dict create $key $value]] 1] $key]
        }
    }
    return [list object $fields]
}
proc ::GX::nativeWorkspaceEMEncode {payload} {return [nativeWorkspaceEncode {record {model {named em_model} gmsh text getdp text}} $payload]}
foreach {domain shape} {
    cad_sketches {map {record {document_id text}}}
    tex_projects {map {record {document_id text generation text source_revision int source_sha256 text}}}
    workbench_documents {map {record {document_id text generation text}}}
    numeric_results {map {named source_guard}}
    numeric_statistics {map {record {document_id text generation text revision int sha256 text source_result_document text operation text}}}
    em_models {map {record {document_id text generation text job_id text model {named em_model}}}}
    pcb_source_bindings {map {record {document_id text stamp {record {document_id text generation text revision int sha256 text pair_stamp text resource_stamps {map {record {sha256 text size_bytes int owner_generation text}}}}}}}}
} {::GX::viewerWorkspaceCodecRegister domains $domain [list ::GX::_viewerWorkspaceShapeEncode $shape]}
foreach {kind shape} {document {named document_binding} native2d {named curve_binding} diagram {named diagram_binding}} {::GX::viewerWorkspaceCodecRegister bindings $kind [list ::GX::_viewerWorkspaceShapeEncode $shape]}
