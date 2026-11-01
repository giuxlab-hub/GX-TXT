# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative Viewer adapters. These encode declared GUI contracts, never infer
# scientific types from Tcl parseability or a Tcl object's current cache type.
namespace eval ::GX::ViewerWorkspaceCodec {variable bindings {};variable domains {}}
proc ::GX::viewerGuiWorkspaceProviderEnsure {module provider design mode handlers context} {
    set enabled 0;foreach component [dict get $design components] {if {[dict get $component type] eq {workspace}} {set enabled 1;break}}
    if {!$enabled} {return {}}
    set wp [datasetPublicationV2DictDefault $context workspace_provider [string map {. _ - _} $module]_${provider}_interface_state]
    set open [datasetPublicationV2DictDefault $context workspace_open [list ::GX::viewerGuiDesignWorkspaceOpen $module $provider $design $mode $handlers]]
    sessionWorkspaceProviderRegister $wp [dict create module_id $module viewer_provider $provider type {Designed Viewer state} schema gxtxt.viewer_interface_state.v1 version 1 validate ::GX::viewerGuiDesignStateValidate open $open native_contract NATIVE_WORKSPACE_API_v1 encode ::GX::viewerGuiWorkspaceEncode decode ::GX::viewerGuiWorkspaceDecode native_required_fields {schema text values object bindings object choices object visibility object domain_state object design object}]
    return [dict create provider $wp open $open]
}
proc ::GX::viewerWorkspaceCodecRegister {kind key callback} {
    if {$kind ni {bindings domains} || ![llength $callback]} {error {Invalid Viewer Workspace codec contribution}}
    dict set ::GX::ViewerWorkspaceCodec::$kind $key $callback
}
proc ::GX::_viewerWorkspaceDesignEncode {design} {
    set fields {};set capabilities [viewerGuiComponentCapabilities]
    dict for {key value} $design {
        switch -- $key {
            components {
                set items {}
                foreach component $value {
                    set encoded {};set type [dict get $component type]
                    dict for {field data} $component {
                        if {$field eq {properties}} {
                            set properties {}
                            dict for {property setting} $data {
                                set datatype [dict get $capabilities $type properties $property]
                                set shape [dict get {dictionary {map text} list {array text} boolean bool number real string text choice text identifier text} $datatype]
                                if {$property eq {command_icons}} {set shape {map {record {icon text icon_disabled text icon_hover text icon_selected text presentation text icon_position text icon_size int icon_spacing int}}}}
                                if {$property eq {scientific_sweep_axes}} {set shape {map {map text}}}
                                if {$type eq {cad_sketch} && $property eq {plane}} {set shape {record {origin {array real} normal {array real} u_axis {array real}}}}
                                dict set properties $property [nativeWorkspaceEncode $shape $setting]
                            }
                            dict set encoded $field [list object $properties]
                        } else {dict set encoded $field [nativeWorkspaceEncode [expr {$field eq {layout}?{map text}:{text}}] $data]}
                    }
                    lappend items [list object $encoded]
                }
                dict set fields $key [list array $items]
            }
            requirements {dict set fields $key [nativeWorkspaceEncode {map int} $value]}
            shell {dict set fields $key [nativeWorkspaceEncode {record {inspector_width int status text}} $value]}
            origin {dict set fields $key [nativeWorkspaceEncode {map text} $value]}
            handlers {dict set fields $key [nativeWorkspaceEncode {map {record {arguments {array text} effect text label text default text available bool}}} $value]}
            catalog - contract_visualizer {dict set fields $key [nativeWorkspaceEncode {map text} $value]}
            icons {dict set fields $key [nativeWorkspaceEncode {map {record {title text category text license text source_format text source_data text sha256 text png text png_sha256 text width int height int alpha bool}}} $value]}
            schema - title - module_id - provider_id - version - geometry - initial_action - target {dict set fields $key [list text $value]}
            default {error "Undeclared Viewer design field '$key'"}
        }
    }
    return [list object $fields]
}
proc ::GX::_viewerWorkspaceValuesEncode {design values} {
    set components {};foreach component [dict get $design components] {dict set components [dict get $component id] $component}
    set fields {}
    dict for {id value} $values {
        if {![dict exists $components $id]} {error "Saved GUI property '$id' is undeclared"}
        set component [dict get $components $id];set type [dict get $component type];set shape text
        if {$type in {checkbutton toggle}} {set shape bool}
        if {$type eq {list}} {set shape {array int}}
        if {$type eq {api_catalog}} {set shape {record {query text surface text offset int selectedRecord text}}}
        if {$type eq {progress}} {set shape real}
        if {$type eq {field}} {
            set datatype [datasetPublicationV2DictDefault [dict get $component properties] datatype string]
            if {$datatype in {integer double number boolean}} {set shape [dict get {integer int double real number real boolean bool} $datatype]}
        }
        dict set fields $id [nativeWorkspaceEncode $shape $value]
    }
    return [list object $fields]
}
proc ::GX::viewerGuiWorkspaceEncode {payload {template {}}} {
    if {[dict exists $payload design]} {set template [dict get $payload design]}
    if {$template eq {}} {error {A typed Viewer Workspace requires its declared interface schema}}
    set fields {}
    dict for {key value} $payload {
        switch -- $key {
            schema {dict set fields $key [list text $value]}
            values {dict set fields $key [_viewerWorkspaceValuesEncode $template $value]}
            design {dict set fields $key [_viewerWorkspaceDesignEncode $value]}
            choices {dict set fields $key [nativeWorkspaceEncode {map {array text}} $value]}
            visibility {dict set fields $key [nativeWorkspaceEncode {map bool} $value]}
            gui_properties {dict set fields $key [nativeWorkspaceEncode {record {geometry text}} $value]}
            custom_state {dict set fields $key $value}
            bindings - domain_state {
                set result {};set kind [expr {$key eq {bindings}?{bindings}:{domains}}]
                dict for {id record} $value {
                    set codec [expr {$kind eq {bindings}?[dict get $record kind]:$id}]
                    if {![dict exists [set ::GX::ViewerWorkspaceCodec::$kind] $codec]} {error "Native Viewer Workspace codec '$codec' is unavailable"}
                    dict set result $id [uplevel #0 [list {*}[dict get [set ::GX::ViewerWorkspaceCodec::$kind] $codec] $record]]
                }
                dict set fields $key [list object $result]
            }
            history {dict set fields $key [nativeWorkspaceHistoryEncode $value [list ::GX::viewerGuiWorkspaceEncodeState $template]]}
            default {error "Undeclared Viewer Workspace field '$key'"}
        }
    }
    return [list object $fields]
}
proc ::GX::viewerGuiWorkspaceEncodeState {design state} {
    # History patches may remove an optional field with the published sentinel.
    set fields {};dict for {key value} $state {
        if {$value eq {@gxtxt.recipe.delete}} {dict set fields $key [list text $value]} else {
            dict set fields $key [dict get [lindex [viewerGuiWorkspaceEncode [dict create $key $value] $design] 1] $key]
        }
    }
    return [list object $fields]
}
proc ::GX::viewerGuiWorkspaceDecode {typed} {
    set result {}
    dict for {key value} [lindex $typed 1] {
        if {$key eq {custom_state}} {dict set result $key $value} elseif {$key eq {bindings}} {dict set result $key [_viewerWorkspaceBindingsDecode $value]} elseif {$key eq {domain_state}} {dict set result $key [_viewerWorkspaceDomainsDecode $value]} elseif {$key eq {history}} {
            dict set result $key [nativeWorkspaceHistoryDecode $value ::GX::viewerGuiWorkspaceDecode]
        } else {dict set result $key [nativeWorkspaceDecode $value]}
    }
    return $result
}
proc ::GX::nativeWorkspaceHistoryDecode {typed decodeState} {
    set record {}
    dict for {key value} [lindex $typed 1] {
        if {$key eq {base}} {dict set record $key [uplevel #0 [list {*}$decodeState $value]]} elseif {$key eq {steps}} {
            set steps {};foreach step [lindex $value 1] {
                set decoded {};dict for {field data} [lindex $step 1] {
                    if {$field eq {patch}} {dict set decoded $field [uplevel #0 [list {*}$decodeState $data]]} else {dict set decoded $field [nativeWorkspaceDecode $data]}
                };lappend steps $decoded
            };dict set record $key $steps
        } else {dict set record $key [nativeWorkspaceDecode $value]}
    }
    return $record
}
proc ::GX::nativeWorkspaceHistoryEncode {record encodeState} {
    set fields {}
    dict for {key value} $record {
        switch -- $key {
            base {dict set fields $key [uplevel #0 [list {*}$encodeState $value]]}
            steps {
                set steps {}
                foreach step $value {
                    set item {};dict for {field data} $step {
                        switch -- $field {
                            patch {set encoded [uplevel #0 [list {*}$encodeState $data]]}
                            api_version - timestamp {set encoded [list int $data]}
                            parameters {set encoded [nativeWorkspaceEncode {map text} $data]}
                            targets - result_ids {set encoded [nativeWorkspaceEncode {array text} $data]}
                            default {set encoded [list text $data]}
                        }
                        dict set item $field $encoded
                    }
                    lappend steps [list object $item]
                }
                dict set fields $key [list array $steps]
            }
            cursor - legacy_import {dict set fields $key [list int $value]}
            required_apis {dict set fields $key [nativeWorkspaceEncode {array text} $value]}
            sources {dict set fields $key [nativeWorkspaceEncode {array {record {source_kind text dataset_id text fingerprint text request {named curve_request}}}} $value]}
            plugin_versions {dict set fields $key [nativeWorkspaceEncode {map text} $value]}
            default {dict set fields $key [list text $value]}
        }
    }
    return [list object $fields]
}
proc ::GX::_viewerWorkspaceCppEncode {record} {
    return [nativeWorkspaceEncode {record {snapshot {map text} callback_contract text state {record {values {array real} counter int}}}} $record]
}
::GX::viewerWorkspaceCodecRegister domains restricted_cpp ::GX::_viewerWorkspaceCppEncode
proc ::GX::_viewerWorkspaceMarkdownAssetMetadataEncode {metadata} {
    # Existing resource fields retain their public typed semantics. Managed
    # Resource metadata extensions remain explicitly inert text, never inferred
    # objects, callbacks or additional scientific/resource authority.
    lassign [dict get $::GX::WorkspaceScientificCodec::shapes resource_metadata] kind declared
    set fields {}
    dict for {key value} $metadata {
        set shape [datasetPublicationV2DictDefault $declared $key text]
        dict set fields $key [nativeWorkspaceEncode $shape $value]
    }
    return [list object $fields]
}
proc ::GX::_viewerWorkspaceMarkdownEncode {drafts} {
    set resource {resource {codec ::GX::_viewerWorkspaceMarkdownAssetMetadataEncode}}
    set baseline [list record [dict create dataset_id text kind text contract text format text media_type text producer text immutable bool sha256 text revision text assets [list map $resource]]]
    set shape [list record [dict create schema text text text baseline $baseline baseline_text text \
        assets [list map $resource] view {record {source bool rendered bool outline bool properties bool resources bool}} \
        cursor text selection {array text} splitters {map {array real}} yview {array real} xview {array real} zoom real destination_id text]]
    set fields {}
    dict for {component draft} $drafts {
        if {[dict get $draft schema] ne {gxtxt.markdown_draft.v1}} {error {Unsupported Markdown Workspace draft}}
        foreach key {text baseline_text} {
            set value [dict get $draft $key]
            if {[string length [encoding convertto utf-8 $value]]>4194304 || [string first \x00 $value]>=0} {error {Markdown Workspace text exceeds its UTF-8 bound}}
        }
        _documentAssetsValidate [dict get $draft assets]
        if {[dict exists $draft baseline assets]} {_documentAssetsValidate [dict get $draft baseline assets]}
        foreach key {xview yview} {if {[dict exists $draft $key] && [llength [dict get $draft $key]] ni {1 2}} {error {Markdown scroll state requires one anchor or a legacy pair of finite fractions}}}
        if {[dict exists $draft selection] && [llength [dict get $draft selection]] ni {0 2}} {error {Markdown selection requires zero or two source indices}}
        dict for {splitter positions} [datasetPublicationV2DictDefault $draft splitters {}] {
            if {![regexp {^[a-z][a-z0-9_]{0,127}$} $splitter] || [llength $positions]>16} {error {Invalid Markdown splitter state}}
            foreach fraction $positions {if {![string is double -strict $fraction] || !($fraction>=0 && $fraction<=1)} {error {Markdown splitter fractions must be between zero and one}}}
        }
        dict set fields $component [nativeWorkspaceEncode $shape $draft]
    }
    return [list object $fields]
}
::GX::viewerWorkspaceCodecRegister domains markdown_drafts ::GX::_viewerWorkspaceMarkdownEncode
proc ::GX::_viewerWorkspaceUmlEncode {drafts} {
    if {[dict size $drafts]>64 || [string bytelength $drafts]>16777216} {error {UML draft domain exceeds its 64-document/16 MiB bound}}
    set baseline {record {dataset_id text kind text contract text format text media_type text producer text immutable bool sha256 text revision text declared_profile text}}
    set shape [list record [dict create schema text text text baseline $baseline baseline_text text last_valid_source text selected text \
        view {record {source bool diagram bool outline bool properties bool diagnostics bool}} splitters {array real} \
        viewport {record {mode text zoom real pan {array real} selected text}} cursor text selection {array text} xview {array real} yview {array real} destination_id text]]
    set fields {}
    dict for {component draft} $drafts {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $component]} {error {Invalid UML draft component identity}}
        _umlEditorDraftValidate $draft
        dict set fields $component [nativeWorkspaceEncode $shape $draft]
    }
    return [list object $fields]
}
::GX::viewerWorkspaceCodecRegister domains uml_drafts ::GX::_viewerWorkspaceUmlEncode
