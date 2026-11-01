# SPDX-License-Identifier: GPL-3.0-or-later
# Inert design bindings only. A model never grants native, Registry or Dataset
# authority; the current runtime owner must independently admit every command.
proc ::GX::viewerGuiRoleMapApiInfo {} {
    return [dict create schema gxtxt.viewer_gui_role_maps.v1 version 1 properties {script_library_components scientific_preview_components} operations {viewerGuiClientRoleMaps} authority none empty_maps unbound max_utf8_bytes 8192]
}
proc ::GX::_viewerGuiClientRoleMapSpec {property} {
    switch -- $property {
        script_library_components {
            return [dict create target viewer required {
                scope_filter choice language_filter choice search_query entry
                records table record_scope field record_language field
                record_id field record_name field record_version field
                record_description field record_required_apis field
                record_identity log operation_status status
                source_files panel registered_source panel parameter_definitions panel
            } optional {} managed {source_files registered_source parameter_definitions}]
        }
        scientific_preview_components {
            return [dict create target preview required {values table metadata table source table} optional {
                frame_view panel frame_variable choice frame_x_dimension choice
                frame_y_dimension choice frame_indices field
            } managed {frame_view}]
        }
        default {error {Unknown native client role map}}
    }
}
proc ::GX::_viewerGuiClientRoleMapsValidate {design} {
    set definitions {};set children {};set claimed {};set result {}
    foreach component [dict get $design components] {
        dict set definitions [dict get $component id] $component
        dict lappend children [dict get $component parent] [dict get $component id]
    }
    foreach component [dict get $design components] {
        set form [dict get $component id];set properties [dict get $component properties]
        foreach property {script_library_components scientific_preview_components} {
            if {![dict exists $properties $property]} continue
            if {[dict get $component type] ne {section}} {error {Native client role maps belong to a section}}
            set roles [dict get $properties $property]
            if {[string bytelength $roles]>8192 || [catch {dict size $roles}] || [llength $roles]!=2*[dict size $roles]} {error {Native client role map requires a bounded dictionary with unique role keys}}
            if {![dict size $roles]} continue
            set spec [_viewerGuiClientRoleMapSpec $property]
            if {[datasetPublicationV2DictDefault $design target viewer] ne [dict get $spec target]} {error {Native client role map does not match the design target}}
            if {$property eq {scientific_preview_components} && [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $design preview {}] runtime {}] ne {managed_cpp}} {error {Scientific role maps require a managed C++ Preview}}
            set required [dict get $spec required];set optional [dict get $spec optional]
            set allowed [dict merge $required $optional]
            foreach role [dict keys $required] {if {![dict exists $roles $role]} {error "Native client role map is missing '$role'"}}
            set optionalCount 0
            foreach role [dict keys $optional] {if {[dict exists $roles $role]} {incr optionalCount}}
            if {$optionalCount && $optionalCount!=[dict size $optional]} {error {Scientific frame controls must be declared together}}
            dict for {role id} $roles {
                if {![dict exists $allowed $role]} {error "Unknown native client role '$role'"}
                if {![regexp {^[a-z][a-z0-9_]{0,63}$} $id] || ![dict exists $definitions $id]} {error {Native client role must name an actual declared component ID}}
                if {[dict get $definitions $id type] ne [dict get $allowed $role]} {error "Native client role '$role' has the wrong component type"}
                # No aliases within or between controllers: one managed source
                # surface/table cannot silently acquire a second owner.
                if {[dict exists $claimed $id]} {error {Native client role components cannot be shared or aliased}}
                dict set claimed $id [list $form $property $role]
                if {$role in [dict get $spec managed] && [dict exists $children $id]} {error {CORE-managed native client panels must have no declared children}}
            }
            dict set result $form $property $roles
        }
    }
    return $result
}
proc ::GX::viewerGuiClientRoleMaps {design} {
    # Validate the complete declarative model before exposing bindings. The
    # returned strings identify components, never paths, widgets or grants.
    set design [viewerGuiDesignValidate $design]
    return [_viewerGuiClientRoleMapsValidate $design]
}
