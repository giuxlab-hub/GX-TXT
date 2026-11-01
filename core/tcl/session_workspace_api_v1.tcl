# SPDX-License-Identifier: GPL-3.0-or-later
# Native C++ owns Workspaces. The existing Document facade exposes native
# identity metadata to scientific owners; it has no alternative Workspace writer.
namespace eval ::GX::SessionWorkspace {variable providers {};variable views {};variable refreshTimer {}}
proc ::GX::sessionWorkspaceApiInfo {} {
    return [dict create api_id SESSION_WORKSPACE_API_v1 api_version 1 operations {list get available_name create update rename delete validate note_read note_write preview_set export import} managed_destinations 1]
}
proc ::GX::sessionWorkspaceProviderRegister {provider descriptor} {
    variable ::GX::SessionWorkspace::providers
    foreach field {module_id type schema version validate open} {if {![dict exists $descriptor $field]} {error "Workspace provider needs $field"}}
    if {![dict exists $descriptor native_contract] || [dict get $descriptor native_contract] ne {NATIVE_WORKSPACE_API_v1}} {error {Workspace provider requires NATIVE_WORKSPACE_API_v1; obsolete persistence providers are unsupported}}
    _interactiveDocumentValidateOwner [dict get $descriptor module_id] $provider
    if {[dict exists $descriptor native_contract]} {
        if {[dict get $descriptor native_contract] ne {NATIVE_WORKSPACE_API_v1}} {error {Incompatible native Workspace provider contract}}
        foreach field {encode native_required_fields} {if {![dict exists $descriptor $field]} {error "Native Workspace provider needs $field"}}
        nativeWorkspaceProviderRegister $provider [dict create module_id [dict get $descriptor module_id] schema [dict get $descriptor schema] version [dict get $descriptor version] required_fields [dict get $descriptor native_required_fields]]
    }
    dict set providers $provider $descriptor
}
proc ::GX::sessionWorkspaceProviderDiscover {module} {
    set data $::GX::moduleCatalog($module,dict)
    nativeWorkspaceDescriptorAdmission $data "Module $module"
    foreach provider [splitList [descriptorValue $data workspaces ids {}]] {
        set section workspace.$provider
        set entry [descriptorValue $data $section entrypoint {}]
        set root [file normalize [file dirname [moduleField $module descriptor]]]
        set file [file normalize [file join $root $entry]]
        if {$entry eq {} || ![string match ${root}/* $file] || ![file isfile $file]} {error {Invalid Workspace provider contribution}}
        set viewer [descriptorValue $data $section viewer_provider {}]
        # Generated native Viewers use CORE validation/codecs. Metadata discovery
        # need not source their module facade and register a loaded backend.
        # Activate the installed Viewer normally only when its Workspace opens.
        set lazy [expr {[descriptorValue $data meta kind {}] eq {viewer} && $entry eq {api/viewer.tcl}
            && {RESTRICTED_VIEWER_CLIENT_API_v1} in [splitList [descriptorValue $data public_apis ids {}]]
            && $viewer ne {} && [descriptorValue $data viewer.$viewer activation_api {}] eq {RESTRICTED_VIEWER_CLIENT_API_v1}
            && [descriptorValue $data $section validate {}] eq {::GX::viewerGuiDesignStateValidate}
            && [descriptorValue $data $section encode {}] eq {::GX::viewerGuiWorkspaceEncode}
            && [descriptorValue $data $section decode {}] eq {::GX::viewerGuiWorkspaceDecode}
            && [descriptorValue $data $section native_contract {}] eq {NATIVE_WORKSPACE_API_v1}}]
        if {!$lazy} {source $file}
        set descriptor [dict create module_id $module]
        foreach field {type schema version validate open} {dict set descriptor $field [descriptorValue $data $section $field {}]}
        foreach field {native_contract encode decode native_required_fields validate_deep} {set value [descriptorValue $data $section $field {}];if {$value ne {} || $field eq {native_required_fields}} {dict set descriptor $field $value}}
        if {$viewer ne {}} {dict set descriptor viewer_provider $viewer}
        if {$lazy} {dict set descriptor open [list ::GX::_workspaceGeneratedViewerOpen $module $viewer]}
        set versions [descriptorValue $data $section accepted_versions {}]
        if {$versions ne {}} {dict set descriptor accepted_versions [splitList $versions]}
        sessionWorkspaceProviderRegister $provider $descriptor
    }
}
proc ::GX::_workspaceGeneratedViewerOpen {module viewer context} {
    if {$context ne {} && ![catch {sessionWorkspaceGet $context} item]} {set context [dict create workspace_id [dict get $item workspace_id]]}
    return [viewerOpen $module $viewer $context]
}
proc ::GX::_workspaceProvider {provider} {
    variable ::GX::SessionWorkspace::providers
    if {![dict exists $providers $provider]} {error "Workspace provider '$provider' is unavailable"}
    set descriptor [dict get $providers $provider]
    set module [dict get $descriptor module_id]
    if {$provider eq {print_composition} && $module eq {framework.printing} && [dict get $descriptor schema] eq {gxtxt.print_composition.v1}} {return $descriptor}
    if {[moduleField $module descriptor {}] eq {}} {error "Workspace provider '$provider' is not installed"}
    set enabled [moduleIsEnabled $module]
    if {[moduleField $module kind {}] eq {viewer} && [dict exists $descriptor viewer_provider]} {
        set viewer [dict get $descriptor viewer_provider]
        set enabled [expr {$viewer in [viewerProviderIds $module] && [viewerProviderEnabled $module $viewer]}]
    }
    if {!$enabled} {error "Workspace provider '$provider' is not enabled"}
    return $descriptor
}
proc ::GX::_workspaceValidatePayload {provider payload version {deep 0}} {
    set descriptor [_workspaceProvider $provider]
    if {$version ni [datasetPublicationV2DictDefault $descriptor accepted_versions [list [dict get $descriptor version]]]} {error "Unsupported workspace schema version '$version'"}
    if {[string bytelength $payload]>16777216} {error {Workspace payload exceeds 16 MiB; use managed resources for large scientific values}}
    if {[catch {dict size $payload}]} {error {Workspace payload must be a dictionary}}
    uplevel #0 [list {*}[dict get $descriptor validate] $payload]
    if {$deep&&[dict exists $descriptor validate_deep]} {uplevel #0 [list {*}[dict get $descriptor validate_deep] $payload]}
}
proc ::GX::sessionWorkspaceList {} {
    variable currentSession
    if {$currentSession eq {}||![file isdirectory $currentSession]} {return {}}
    variable ::GX::SessionWorkspace::providers
    set result {}
    foreach doc [interactiveDocumentList] {
        set provider [dict get $doc provider_id]
        if {[datasetPublicationV2DictDefault $doc native_workspace 0]} {
            lappend result [_sessionWorkspaceDescribeMetadata $doc]
        } elseif {[_sessionWorkspaceKnownObsolete $doc]} {lappend result [_sessionWorkspaceDescribeMetadata $doc]}
    }
    return $result
}
proc ::GX::sessionWorkspaceGet {id} {
    if {![_nativeWorkspaceExists $id]} {error {Obsolete or incompatible Workspace cannot be opened, modified or converted. Create a new native Workspace.}}
    set metadata [dict merge [nativeWorkspaceMetadata $id] {native_workspace 1}]
    if {![dict get [_sessionWorkspaceDescribeMetadata $metadata] compatible]} {error {Workspace provider/schema is unavailable or incompatible; saved state is preserved}}
    set doc [interactiveDocumentRead $id];set provider [dict get $doc provider_id]
    set descriptor [_workspaceProvider $provider]
    if {[dict get $doc format] ne [dict get $descriptor schema]} {error {Document is not a registered workspace}}
    set payload [dict get $doc payload]
    set metadata [datasetPublicationV2DictDefault $payload workspace_metadata [dict create name "[dict get $descriptor type] $id" preview {} note {}]]
    return [dict merge [dict remove $doc payload] [dict create workspace_id $id name [dict get $metadata name] type [dict get $descriptor type] schema [dict get $doc format] schema_version [dict get $doc format_version] preview [dict get $metadata preview] note [dict get $metadata note] payload [dict remove $payload workspace_metadata]]]
}
proc ::GX::sessionWorkspaceMetadata {id} {
    if {[_nativeWorkspaceExists $id]} {
        return [_sessionWorkspaceDescribeMetadata [dict merge [nativeWorkspaceMetadata $id] {native_workspace 1}]]
    }
    set metadata [interactiveDocumentMetadata $id]
    if {![_sessionWorkspaceKnownObsolete $metadata]} {error {Document is not a recognized Workspace}}
    return [_sessionWorkspaceDescribeMetadata $metadata]
}
proc ::GX::_sessionWorkspaceKnownObsolete {metadata} {
    set provider [dict get $metadata provider_id]
    if {[dict get $metadata module_id] eq {viewer.scientific_worksheet} && $provider eq {scientific_worksheet} && [dict get $metadata format] eq {scientific_worksheet.v1}} {return 1}
    if {[dict get $metadata module_id] eq {plot.dataset} && $provider eq {native_3d} && [dict get $metadata format] in {gxtxt.plot_dataset.interactive_scene gxtxt.plot_dataset.native_v4_scene}} {return 1}
    if {[dict exists $::GX::SessionWorkspace::providers $provider] && [dict get $metadata module_id] eq [dict get $::GX::SessionWorkspace::providers $provider module_id] && [dict get $metadata format] eq [dict get $::GX::SessionWorkspace::providers $provider schema]} {return 1}
    return [expr {[dict get $metadata module_id] eq {analysis.octave_script} && $provider eq {octave_script_editor} && [dict get $metadata format] eq {gxtxt.octave_script.document}}]
}
proc ::GX::_sessionWorkspaceDescribeMetadata {metadata} {
    set provider [dict get $metadata provider_id];set native [datasetPublicationV2DictDefault $metadata native_workspace 0]
    set type {Unavailable provider};set compatible 0
    if {[dict exists $::GX::SessionWorkspace::providers $provider]} {
        set descriptor [dict get $::GX::SessionWorkspace::providers $provider]
        set type [dict get $descriptor type]
        set compatible [expr {$native && [dict get $metadata format] eq [dict get $descriptor schema] && [dict get $metadata format_version] in [datasetPublicationV2DictDefault $descriptor accepted_versions [list [dict get $descriptor version]]] && ![catch {_workspaceProvider $provider}]}]
    }
    if {!$native} {set type "Obsolete $type"}
    if {!$native && $provider eq {octave_script_editor}} {set type {Obsolete Octave Workspace}}
    set name [expr {$native?[dict get $metadata name]:"Obsolete $provider [dict get $metadata id]"}]
    return [dict merge $metadata [dict create workspace_id [dict get $metadata id] name $name type $type schema [dict get $metadata format] schema_version [dict get $metadata format_version] native_workspace $native compatible $compatible preview [expr {$native && [datasetPublicationV2DictDefault $metadata has_preview 0]?{native_preview 1}:{}}] note [expr {$native && [datasetPublicationV2DictDefault $metadata has_notes 0]?{native_notes 1}:{}}]]]
}
proc ::GX::_workspaceName {name {except {}}} {
    set name [string trim $name];_interactiveDocumentValidateSingleLine $name {Workspace name}
    if {$name eq {}||[string length $name]>160} {error {Workspace name must contain 1..160 characters}}
    foreach item [sessionWorkspaceList] {if {[dict get $item workspace_id] ne $except&&[dict get $item name] eq $name} {error "Workspace name '$name' already exists"}}
    return $name
}
# Suggested presentation names use the same canonical Workspace inventory.
proc ::GX::sessionWorkspaceAvailableName {preferred} {
    set preferred [string trim $preferred]
    _interactiveDocumentValidateSingleLine $preferred {Workspace name}
    if {$preferred eq {} || [string length $preferred]>150} {error {Preferred Workspace name must contain 1..150 characters}}
    set used [lmap item [sessionWorkspaceList] {dict get $item name}]
    set name $preferred;set index 1
    while {$name in $used} {set name "$preferred [incr index]"}
    return $name
}
proc ::GX::sessionWorkspaceCreate {provider name payload {asynchronous 0} {typedProperties {object {}}}} {
    set descriptor [_workspaceProvider $provider];set version [dict get $descriptor version]
    set name [_workspaceName $name];_workspaceValidatePayload $provider $payload $version 1
    set state [uplevel #0 [list {*}[dict get $descriptor encode] $payload]]
    set provenance [nativeWorkspaceEncode {named origin} [_originCreate native_workspace [dict create session_origin [sessionOriginRead [_interactiveDocumentRequireSession]]]]]
    set receipt [nativeWorkspaceCreate $provider $name $state $typedProperties $provenance $asynchronous]
    sessionWorkspaceViewsChanged
    return [dict merge [sessionWorkspaceGet [dict get $receipt id]] $receipt]
}
proc ::GX::sessionWorkspaceUpdate {id payload {expected {}} {asynchronous 0} {typedProperties {}}} {
    if {![_nativeWorkspaceExists $id]} {error {Obsolete Workspace updates and conversion are unsupported}}
    if {$expected eq {} || [dict get $expected id] ne $id} {error {Native Workspace Save requires this object's held generation/revision receipt}}
    set workspace [sessionWorkspaceMetadata $id]
    set descriptor [_workspaceProvider [dict get $workspace provider_id]]
    _workspaceValidatePayload [dict get $workspace provider_id] $payload [dict get $workspace schema_version] 1
    set state [uplevel #0 [list {*}[dict get $descriptor encode] $payload]]
    if {$typedProperties eq {}} {set typedProperties [nativeWorkspaceProperties $id]}
    set receipt [nativeWorkspaceSave $expected $state $typedProperties $asynchronous]
    sessionWorkspaceViewsChanged
    return [dict merge [sessionWorkspaceGet $id] $receipt]
}
proc ::GX::sessionWorkspacePromote {id {name {}}} {
    if {![_nativeWorkspaceExists $id]} {error {Obsolete Workspace promotion/conversion is unsupported}}
    return [sessionWorkspaceGet $id]
}
proc ::GX::sessionWorkspaceRename {id name} {
    if {![_nativeWorkspaceExists $id]} {error {Obsolete Workspace cannot be renamed or converted}}
    nativeWorkspaceRename [nativeWorkspaceMetadata $id] [_workspaceName $name $id]
    sessionWorkspaceViewsChanged
    return [sessionWorkspaceMetadata $id]
}
proc ::GX::sessionWorkspaceDelete {id {confirmed 0} {expected {}}} {
    if {[_nativeWorkspaceExists $id]} {
        if {!$confirmed} {error {Workspace Delete requires explicit confirmation}}
        if {[llength [info commands _historyDocumentBarrier]]} {_historyDocumentBarrier $id}
        set metadata [nativeWorkspaceMetadata $id]
        if {$expected ne {}} {
            foreach field {id generation revision} {if {[dict get $expected $field] ne [dict get $metadata $field]} {error {Workspace changed before Delete; refresh and confirm the current object}}}
        }
        set plan [_documentResourceDeletePlan $id]
        try {nativeWorkspaceDelete $metadata 1} on error {message options} {_documentResourceDeleteRollback $plan;return -options $options $message}
        _documentResourceDeleteCommit $id $plan
        _interactiveDocumentDeletedNotify [dict merge $metadata [dict create event deleted document_id $id owner_generation [dict get $metadata generation] session_token [interactiveDocumentSessionToken]]]
        sessionWorkspaceViewsChanged
        return 1
    }
    if {![string is boolean -strict $confirmed] || !$confirmed} {error {Obsolete Workspace Delete requires explicit confirmation}}
    set metadata [sessionWorkspaceMetadata $id]
    if {$expected ne {}} {foreach field {id generation revision} {if {[dict get $expected $field] ne [dict get $metadata $field]} {error {Obsolete Workspace changed before Delete; refresh and confirm again}}}}
    set path [_noteDocumentManagedPath $id]
    interactiveDocumentDelete $id
    if {[file exists $path]} {file delete -- $path}
    return 1
}
proc ::GX::sessionWorkspaceValidate {id} {
    set workspace [sessionWorkspaceGet $id]
    _workspaceValidatePayload [dict get $workspace provider_id] [dict get $workspace payload] [dict get $workspace schema_version] 1
    if {[_nativeWorkspaceExists $id]} {
        set snapshot [nativeWorkspaceGet $id];set references {}
        foreach field {state properties provenance} {_nativeWorkspaceResourceReferences [dict get $snapshot $field] references}
        foreach reference [dict values $references] {interactiveDocumentResourceInfo $reference}
        return [dict create valid 1 resource_count [dict size $references] workspace_id $id]
    }
    set references {};set budget 0
    _documentResourceReferences [dict get [interactiveDocumentRead $id] payload] $id 0 budget references
    if {[dict get $workspace note] ne {}} {noteDocumentRead $id}
    return [dict create valid 1 resource_count [dict size $references] workspace_id $id]
}
proc ::GX::managedResourceWrite {document metadata bytes} {
    set writer [interactiveDocumentResourceOpenWriter $document $metadata]
    try {
        for {set i 0} {$i<[string length $bytes]} {incr i 1048576} {interactiveDocumentResourceAppend $writer [string range $bytes $i [expr {$i+1048575}]]}
        set resource [interactiveDocumentResourceFinalize $writer];set writer {}
        return $resource
    } finally {if {$writer ne {}} {interactiveDocumentResourceAbort $writer}}
}
# Explicit new typed graph adoption. Plain scientific strings are never parsed.
proc ::GX::managedResourceCopyTree {document typed} {
    sessionWorkspaceMetadata $document
    if {![_nativeWorkspaceExists $document]} {error {Typed resource adoption requires a native Workspace}}
    if {[string bytelength $typed]>67108864} {error {Typed resource tree transport exceeds its bound}}
    _nativeWorkspaceLibraryRequire
    workspaceNative typed_equivalent $typed $typed
    set mapping {}
    return [_nativeWorkspaceResourceCopyNode $document $typed mapping 0]
}
proc ::GX::_nativeWorkspaceResourceCopyNode {document typed mappingName depth} {
    upvar 1 $mappingName mapping
    if {$depth>64} {error {Typed resource tree exceeds nesting bound}}
    lassign $typed kind value
    if {$kind in {object resource}} {
        set fields {};dict for {key child} $value {dict set fields $key [_nativeWorkspaceResourceCopyNode $document $child mapping [expr {$depth+1}]]}
        if {$kind eq {resource}} {
            set reference [nativeWorkspaceDecode [list resource $fields]]
            set original [_documentResourceProvenanceReference $reference]
            set identity [list [dict get $original document_id] [dict get $original owner_generation] [dict get $original sha256]]
            if {![dict exists $mapping $identity]} {dict set mapping $identity [managedResourceCopy $document $original]}
            set copied [dict get $mapping $identity]
            # Only owner/generation change; each original occurrence keeps its
            # own exact typed metadata and scalar annotations.
            dict set fields document_id [list text [dict get $copied document_id]]
            dict set fields owner_generation [list text [dict get $copied owner_generation]]
        }
        return [list $kind $fields]
    }
    if {$kind eq {array}} {
        set children {};foreach child $value {lappend children [_nativeWorkspaceResourceCopyNode $document $child mapping [expr {$depth+1}]]};return [list array $children]
    }
    return $typed
}
proc ::GX::sessionWorkspaceResourceCopyTreeUtf8 {document value} {error {Serialized Tcl resource-tree transport is retired; use NATIVE_WORKSPACE_API_v1 resource_copy_tree with explicit native nodes}}
proc ::GX::managedResourceCopy {document reference} {
    # A retained Job result can be adopted by another real Workspace without
    # borrowing the producing Document's generation or deriving private paths.
    set info [interactiveDocumentResourceInfo $reference]
    set reader [interactiveDocumentResourceOpenReader $reference]
    set writer {}
    try {
        set writer [interactiveDocumentResourceOpenWriter $document [dict get $info metadata]]
        while {1} {
            set page [interactiveDocumentResourceNext $reader 1048576]
            interactiveDocumentResourceAppend $writer [dict get $page bytes]
            if {[dict get $page eof]} break
        }
        set result [interactiveDocumentResourceFinalize $writer];set writer {}
        if {[dict get $result sha256] ne [dict get $info sha256]||[dict get $result size_bytes]!=[dict get $info size_bytes]} {error {Resource content changed during ownership transfer}}
        return $result
    } finally {
        interactiveDocumentResourceCloseReader $reader
        if {$writer ne {}} {interactiveDocumentResourceAbort $writer}
    }
}
proc ::GX::sessionWorkspacePreviewSet {id reference} {
    if {[_nativeWorkspaceExists $id]} {
        interactiveDocumentResourceInfo $reference
        if {[dict get $reference document_id] ne $id || [dict get $reference metadata format] ni {image.png image.svg}} {error {Preview must be an image owned by this Workspace}}
        set snapshot [nativeWorkspaceMetadata $id];set properties [lindex [nativeWorkspaceProperties $id] 1]
        dict set properties preview [nativeWorkspaceEncode {resource {named resource_metadata}} $reference]
        nativeWorkspaceSetProperties $snapshot [list object $properties]
        _nativeWorkspaceMetadataAdvanced $snapshot [nativeWorkspaceMetadata $id] [dict get $properties preview]
        sessionWorkspaceViewsChanged
        return [sessionWorkspaceMetadata $id]
    }
    error {Obsolete Workspace preview writes are unsupported}
}
proc ::GX::_noteDocumentPath {id} {error {File-backed obsolete Workspace notes are unsupported}}
proc ::GX::_noteDocumentManagedPath {id} {
    if {![interactiveDocumentExists $id]} {error {Note owner does not exist}}
    set session [_interactiveDocumentRequireSession];set path $session
    foreach part [list notes workspaces "$id.md"] {
        set path [file join $path $part]
        if {![catch {file lstat $path status}]&&$status(type) eq "link"} {error {Note document symlinks are forbidden}}
    }
    return $path
}
proc ::GX::noteDocumentRead {id} {
    if {[_nativeWorkspaceExists $id]} {return [dict create workspace_id $id text [workspaceNative notes_get [_nativeWorkspaceRequire] $id] format GX-Markup]}
    error {Obsolete Workspace note body reads are unsupported}
}
proc ::GX::noteDocumentWrite {id text} {
    if {[string length [encoding convertto utf-8 $text]]>1048576} {error {Note source exceeds 1 MiB}}
    if {[_nativeWorkspaceExists $id]} {
        set before [nativeWorkspaceMetadata $id]
        nativeWorkspaceNotes $before $text
        _nativeWorkspaceMetadataAdvanced $before [nativeWorkspaceMetadata $id]
        sessionWorkspaceViewsChanged
        return [noteDocumentRead $id]
    }
    error {Obsolete Workspace note writes are unsupported}
}
proc ::GX::noteDocumentOpen {id {mode view}} {
    set workspace [sessionWorkspaceMetadata $id];set text [dict get [noteDocumentRead $id] text]
    set token [interactiveDocumentSessionToken];set receipt [_workspaceHostReceipt $id]
    if {$mode eq "edit"} {return [openMarkupEditor "Notes — [dict get $workspace name]" $text [list ::GX::sessionWorkspaceHostNoteSave $token $receipt $id]]}
    if {$mode ne "view"} {error {Note mode must be view or edit}}
    set window .workspaceNoteView;catch {destroy $window};toplevel $window;wm title $window "Notes — [dict get $workspace name]"
    text $window.text -wrap word -width 80 -height 25;pack $window.text -fill both -expand 1
    markupConfigurePreviewTags $window.text;markupRenderStringToWidget $window.text $text;$window.text configure -state disabled
    ttk::button $window.edit -text Edit -command [list ::GX::sessionWorkspaceHostNoteEdit $token $receipt $id];pack $window.edit -side bottom
    return $window
}
proc ::GX::sessionWorkspaceOpen {id} {
    set workspace [sessionWorkspaceGet $id];sessionWorkspaceValidate $id
    set descriptor [_workspaceProvider [dict get $workspace provider_id]]
    set module [dict get $descriptor module_id]
    if {$module eq {framework.printing} && [dict get $workspace provider_id] eq {print_composition}} {return [printStudioOpenWorkspace $id]}
    foreach api [modulePublicApiIds $module] {modulePublicApiActivate $module $api}
    set context [parameterContext [dict get [_datasetPrivateModuleContext $module] capability] $id]
    parameterList $context
    return [_datasetPrivateWithModule $module [list {*}[dict get $descriptor open] $id]]
}
proc ::GX::_workspaceCurveValidate {payload} {
    foreach key {version curves next active view reference target external_feedback} {if {![dict exists $payload $key]} {error "Curve workspace is missing $key"}}
    if {[dict get $payload version]!=2||![string is entier -strict [dict get $payload next]]||[dict get $payload next]<0||[catch {dict size [dict get $payload curves]}]} {error {Unsupported Curve workspace payload}}
}
proc ::GX::_workspaceCurveValidateDeep {payload} {
    native2DEnsure;set scene [::GX::Native2D::core scene]
    try {
        ::GX::Native2D::core view $scene [dict get $payload view]
        dict for {id record} [dict get $payload curves] {
            foreach key {id name source samples x y parents operations representation visible locked edited breaks} {if {![dict exists $record $key]} {error "Curve $id is missing $key"}}
            if {[dict get $record id] ne $id} {error {Curve identity mismatch}}
            if {[dict exists $record working_unit]&&[dict get $record working_unit] ne {}} {unitRegistryConversionPlan [dict get $record working_unit] [dict get $record working_unit]}
            if {[datasetPublicationV2DictDefault $record dataset_binding_only 0]} {
                if {[dict get $record source] eq {}||[dict get $record edited]||[dict get $record samples] ne {}||[dict exists $record sketch_definition]||[dict exists $record geometry_resource]} {error {Dataset binding cannot contain a second geometry authority}}
                foreach key {source_request source_descriptor point_count} {if {![dict exists $record $key]} {error "Dataset binding is missing $key"}}
                foreach key {dataset_id x_variable_id y_variable_id} {if {![dict exists $record source_request $key]} {error "Dataset request is missing $key"}}
                if {[dict get $record source_request dataset_id] ne [dict get $record source]} {error {Dataset source binding identity mismatch}}
                if {![string is entier -strict [dict get $record point_count]]||[dict get $record point_count]<1} {error {Dataset binding requires a positive authoritative point count}}
            } elseif {[dict exists $record sketch_definition]} {
                set object [::GX::Native2D::core sketch_create $scene [dict get $record sketch_definition] 2]
                ::GX::Native2D::core delete $scene $object
            } elseif {[dict exists $record geometry_resource]} {
                set resource [dict get $record geometry_resource]
                set count [dict get $resource metadata point_count]
                if {![string is entier -strict $count]||$count<1||[dict get $resource metadata format] ne "native2d.float64_xy_le_v1"||[dict get $resource size_bytes]!=16*$count} {error {Invalid retained geometry resource shape}}
            } else {
                set points {};foreach sample [dict get $record samples] {lappend points [list [dict get $sample x] [dict get $sample y]]}
                if {$points eq {}} {error {Curve has no retained geometry or samples}}
                set object [::GX::Native2D::core add $scene $points];::GX::Native2D::core delete $scene $object
            }
        }
        if {[dict exists $payload cad_workspace reference_images]} {
            dict for {id record} [dict get $payload cad_workspace reference_images] {
                unitRegistryConversionPlan [dict get $record state length_unit] m
                lassign [_native2DImageDimensions [dict get $record resource]] width height
                if {$width!=[dict get $record state width]||$height!=[dict get $record state height]} {error {Raster dimensions differ from retained image state}}
                set object [::GX::Native2D::core image_create $scene [dict get $record state]]
                if {[dict get $record state resource_id] ne [dict get $record resource sha256]} {error {Raster resource identity mismatch}}
                ::GX::Native2D::core delete $scene $object
            }
        }
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::_workspaceCurveOpen {id} {
    modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
    return [::GX::CurveWorkbench::open [dict create workspace_id $id]]
}
# Curve Workbench declares its independent native provider in module.ini.
# Native capsules own typed Workspace transport. ZIP helpers handle only files.
proc ::GX::_nativeWorkspacePortableRun {operation args} {
    return [exec [runtimeToolRequired python] [file join $::GX::scriptDir core python native_workspace_portable_v1.py] $operation {*}$args 2>@1]
}
proc ::GX::sessionWorkspaceExport {id} {
    set item [sessionWorkspaceMetadata $id]
    if {![dict get $item native_workspace] || ![dict get $item compatible]} {error {Export requires an available native Workspace provider; obsolete Tcl packages are unsupported}}
    set handle [_nativeWorkspaceRequire];set root [_documentResourceRoot $id];file mkdir $root
    set f [file tempfile temporary [file join $root .native-export-]];close $f;file delete -- $temporary
    set stage "$temporary.stage";set archive "$temporary.zip";file mkdir $stage
    try {
        _nativeWorkspaceScientificOwnersAdmit $handle [workspaceNative resource_references $handle $id]
        workspaceNative capsule_export $handle $id [dict get $item generation] [dict get $item revision] [file join $stage workspace.native]
        foreach typed [lindex [workspaceNative resource_references $handle $id] 1] {
            set ref [nativeWorkspaceDecode $typed];interactiveDocumentResourceInfo $ref
            set directory [file join $stage resources [dict get $ref document_id]];file mkdir $directory
            file copy -- [file join [_documentResourceRoot [dict get $ref document_id] 1] [dict get $ref sha256].blob] [file join $directory [dict get $ref sha256].blob]
        }
        _nativeWorkspacePortableRun export $stage $archive
        set after [nativeWorkspaceMetadata $id]
        if {[dict get $after generation] ne [dict get $item generation] || [dict get $after revision] ne [dict get $item revision]} {error {Workspace changed during export}}
        return [interactiveDocumentResourceImportNumeric $id $archive {format gxtxt.workspace.zip native_contract NATIVE_WORKSPACE_API_v1}]
    } finally {file delete -force -- $stage $archive}
}
proc ::GX::_workspaceRemapResources args {error {Obsolete Tcl Workspace resource conversion is unsupported; use typed native resource adoption}}
proc ::GX::sessionWorkspaceImport {resource {name {}}} {
    interactiveDocumentResourceInfo $resource
    if {[dict get $resource metadata format] ne "gxtxt.workspace.zip"} {error {Import requires a managed Workspace package resource}}
    set path [file join [_documentResourceRoot [dict get $resource document_id]] [dict get $resource sha256].blob]
    return [_sessionWorkspaceImportPath $path $name]
}
# Verified package metadata is provenance, not authentication. Foreign IDs are
# retained as inert source receipts, never resolved against the receiving Session.
proc ::GX::_nativeWorkspaceTypedReferences {typed resultName} {
    upvar 1 $resultName result
    lassign $typed kind data
    if {$kind eq {resource}} {
        set ref [nativeWorkspaceDecode $typed];set key [list [dict get $ref document_id] [dict get $ref owner_generation] [dict get $ref sha256]]
        if {[dict exists $result $key] && [dict get $result $key size_bytes] ne [dict get $ref size_bytes]} {error {Conflicting packaged resource sizes}}
        dict set result $key $ref
    }
    if {$kind in {resource object}} {dict for {key value} $data {_nativeWorkspaceTypedReferences $value result}}
    if {$kind eq {array}} {foreach value $data {_nativeWorkspaceTypedReferences $value result}}
}
proc ::GX::_sessionWorkspaceImportPath {path {name {}} {expectedProvider {}}} {
    _nativeWorkspaceWriteAllowed
    set session [_interactiveDocumentRequireSession];set stage [file join $session metadata .native-workspace-import-[pid]-[clock clicks]]
    try {
        _nativeWorkspacePortableRun extract $path $stage
        set capsule [file join $stage workspace.native];_nativeWorkspaceLibraryRequire
        set typed [workspaceNative capsule_inspect $capsule];set fields [lindex $typed 1]
        set provider [lindex [dict get $fields provider] 1]
        if {$expectedProvider ne {} && $provider ne $expectedProvider} {error {Package belongs to a different provider}}
        set descriptor [_workspaceProvider $provider]
        foreach {field expected} [list owner [dict get $descriptor module_id] schema [dict get $descriptor schema] schema_version [dict get $descriptor version]] {if {[dict get $fields $field] ne [list text $expected]} {error {Native package provider/schema mismatch}}}
        # Decode only the explicitly typed provider state for its published
        # semantic admission. No legacy payload parser/converter is involved.
        nativeWorkspaceScriptValidate $provider [dict get $fields state]
        set refs {};_nativeWorkspaceTypedReferences $typed refs
        set registry [_interactiveDocumentRegistryRead $session];set handle [_nativeWorkspaceRequire]
        set plan [file join $stage resource-plan];set f [open $plan {WRONLY CREAT EXCL}]
        try {
            set paths {}
            dict for {key ref} $refs {
                set owner [dict get $ref document_id];set generation [dict get $ref owner_generation]
                if {[dict exists $registry $owner]} {
                    if {[dict get $registry $owner generation] ne $generation} {error {Imported resource owner generation conflicts with this Session}}
                    workspaceNative register_resource_owner $handle $owner $generation
                } elseif {![catch {set existing [_documentResourceOwnerGeneration $owner]}] && $existing ne $generation} {error {Imported retired resource owner generation conflicts with this Session}}
                set rel "resources/$owner/[dict get $ref sha256].blob"
                set blob [file join $stage {*}[split $rel /]]
                if {![file isfile $blob] || [file size $blob]!=[dict get $ref size_bytes] || [sha256File $blob] ne [dict get $ref sha256]} {error {Packaged immutable resource is missing/corrupt}}
                dict set paths $rel 1
            }
            foreach rel [dict keys $paths] {puts $f $rel}
        } finally {close $f}
        # Plan is operational metadata, excluded from package member inventory.
        set externalPlan "$stage.plan";file rename -- $plan $externalPlan
        try {_nativeWorkspacePortableRun adopt $stage $session $externalPlan} finally {file delete -- $externalPlan}
        set receipt [workspaceNative capsule_import $handle $capsule $name]
        sessionWorkspaceViewsChanged
        return [sessionWorkspaceGet [dict get $receipt id]]
    } finally {if {[file exists $stage]} {file delete -force -- $stage}}
}
proc ::GX::_workspacePackageReferences {value depth resultName} {
    upvar 1 $resultName result
    if {$depth>64} {error {Workspace resource nesting exceeds limit}}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        set compact [expr {![dict exists $value metadata]}]
        set value [_documentResourceProvenanceReference $value]
        set sha [dict get $value sha256]
        if {![regexp {^[a-f0-9]{64}$} $sha]} {error {Invalid packaged resource identity}}
        if {[dict exists $result $sha]&&[dict get $result $sha size_bytes]!=[dict get $value size_bytes]} {error {Conflicting resource sizes}}
        if {!$compact || ![dict exists $result $sha]} {dict set result $sha $value}
        _workspacePackageReferences [dict get $value metadata] [expr {$depth+1}] result
        return
    }
    if {[catch {llength $value} n]} return
    foreach item $value {if {$item ne $value} {_workspacePackageReferences $item [expr {$depth+1}] result}}
}
rename ::GX::buildSessionFileExplorerGui ::GX::buildSessionFileExplorerGui_workspace056_base
proc ::GX::buildSessionFileExplorerGui {} {
    buildSessionFileExplorerGui_workspace056_base
    set f .top.nb.sessionfiles
    if {![winfo exists $f.workspaceArea]} {
        ttk::labelframe $f.workspaceArea -text Workspaces
        sessionWorkspaceBuild $f.workspaceArea
    }
    sessionPageSelect
}
proc ::GX::managedResourceWriteBase64 {document metadata encoded} {
    if {[string length $encoded]>5592408} {error {Managed write exceeds the bounded 4 MiB data contract}}
    set bytes [binary decode base64 -strict $encoded]
    if {[string length $bytes]>4194304} {error {Managed write exceeds 4 MiB}}
    return [managedResourceWrite $document $metadata $bytes]
}
proc ::GX::managedResourceReadBase64 {reference start count} {return [binary encode base64 -maxlen 0 [interactiveDocumentResourceReadChunk $reference $start $count]]}
proc ::GX::managedResourceNumericWidths {} {
    return {bool 1 int8 1 uint8 1 int16 2 uint16 2 int32 4 uint32 4 int64 8 uint64 8 float32 4 float64 8 complex64 8 complex128 16}
}
proc ::GX::managedResourceNumericOwner {document} {
    _documentResourceRoot $document
    return [_documentResourceOwnerGeneration $document]
}
proc ::GX::managedResourceImportNumeric {document generation path metadata} {
    if {[managedResourceNumericOwner $document] ne $generation} {error {Numeric resource owner generation changed}}
    foreach key {format dtype endian order columns row_count} {if {![dict exists $metadata $key]} {error "Numeric resource metadata requires $key"}}
    set widths [managedResourceNumericWidths];set dtype [dict get $metadata dtype]
    if {![dict exists $widths $dtype]||[dict get $metadata endian] ne "little"||[dict get $metadata order] ne "C"} {error {Unsupported numeric resource dtype/order/endian}}
    set columns [dict get $metadata columns];set rows [dict get $metadata row_count];set count [llength $columns]
    if {$count<1||$count>128||[llength [lsort -unique $columns]]!=$count||![string is entier -strict $rows]||$rows<0} {error {Numeric resource needs 1..128 distinct columns and a nonnegative row count}}
    foreach column $columns {if {[string trim $column] eq {}||[regexp {[\x00-\x1f]} $column]} {error {Numeric column identities must be nonempty single-line text}}}
    switch [dict get $metadata format] {
        gxtxt.numeric_matrix_le_v1 {}
        float64_interleaved_le {if {$dtype ne "float64"} {error {Interleaved binary64 resources require float64 values}}}
        uint64_le {if {$dtype ne "uint64"||$count!=1} {error {Exact row resources require one uint64 column}}}
        native2d.uint8_break_before_v1 {
            if {$dtype ne "uint8"||$columns ne {break_before}||$rows<1} {error {Native2D gaps need a nonempty uint8 break_before column}}
            dict set metadata point_count $rows
        }
        native2d.float64_xy_le_v1 {
            if {$dtype ne "float64"||$columns ne {x y}||$rows<1} {error {Native2D geometry needs nonempty float64 X/Y columns}}
            dict set metadata point_count $rows
        }
        default {error {Unsupported typed numeric resource format}}
    }
    set bytes [expr {$rows*$count*[dict get $widths $dtype]}]
    if {$bytes>536870912||![file isfile $path]||[file type $path] eq "link"||[file size $path]!=$bytes} {error {Numeric resource payload differs from its bounded declared shape}}
    return [interactiveDocumentResourceImportNumeric $document $path $metadata]
}
proc ::GX::managedResourceNumericPage {reference start count} {
    set info [interactiveDocumentResourceInfo $reference];set metadata [dict get $info metadata]
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<0||$count>65536} {error {Numeric resource pages require a nonnegative start and 0..65536 rows}}
    set format [dict get $metadata format];set width 8
    switch $format {
        gxtxt.numeric_matrix_le_v1 {
            set dtype [dict get $metadata dtype];set widths [managedResourceNumericWidths]
            if {![dict exists $widths $dtype]||[dict get $metadata endian] ne "little"||[dict get $metadata order] ne "C"} {error {Unsupported numeric resource dtype/order/endian}}
            set width [dict get $widths $dtype];set columns [dict get $metadata columns]
        }
        float64_interleaved_le {set dtype float64;set columns [dict get $metadata columns]}
        native2d.float64_xy_le_v1 {set dtype float64;set columns {x y}}
        uint64_le {set dtype uint64;set columns {value}}
        native2d.uint8_break_before_v1 {set dtype uint8;set width 1;set columns {value}}
        default {error "Resource format '$format' has no declared fixed-width numeric page contract"}
    }
    set nc [llength $columns]
    if {$nc<1||$nc>128||[llength [lsort -unique $columns]]!=$nc} {error {Numeric resource columns must have 1..128 unique identities}}
    set size [dict get $info size_bytes];set stride [expr {$width*$nc}]
    if {$size%$stride} {error {Numeric resource size differs from its declared row width}}
    set total [expr {$size/$stride}]
    if {[dict exists $metadata row_count]&&[dict get $metadata row_count]!=$total} {error {Numeric resource row count differs from its owned payload}}
    if {$start>$total} {error {Numeric resource page starts outside the resource}}
    set n [expr {min($count,$total-$start)}]
    if {$n*$stride>1048576} {error {Numeric resource pages may contain at most 1 MiB; request fewer rows}}
    set bytes [interactiveDocumentResourceReadChunk $reference [expr {$start*$stride}] [expr {$n*$stride}]]
    return [dict create schema gxtxt.numeric_resource_page.v1 dtype $dtype endian little order C columns $columns start $start row_count $n total_rows $total source_sha256 [dict get $info sha256] bytes $bytes]
}
proc ::GX::managedResourceApiInfo {} {return [dict create api_id MANAGED_RESOURCE_API_v1 api_version 1 operations {write read info copy write_numeric read_numeric} write_bytes_max 4194304 read_bytes_max 1048576 numeric_write_bytes_max 536870912 numeric_page_rows_max 65536 numeric_dtypes [dict keys [managedResourceNumericWidths]] arbitrary_paths 0]}
proc ::GX::noteDocumentApiInfo {} {return [dict create api_id NOTE_DOCUMENT_API_v1 api_version 1 operations {read write} storage UTF-8.md editor GX-Markup graphical_editor host_only]}

# Compare immutable subtrees before traversing them. Camera-only updates keep
# scientific records/resources byte-identical; walking every sampled value on
# pointer release would otherwise turn a tiny view change into a long UI stall.
# Changed branches still use the full resource parser and ownership validation.
proc ::GX::_workspaceChangedResourceReferences {value prior depth resultName} {
    upvar 1 $resultName result
    if {$value eq $prior} return
    if {$depth>64} {error {Workspace resource nesting exceeds limit}}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        _workspacePackageReferences $value $depth result
        return
    }
    if {[catch {llength $value} n]} return
    if {[catch {llength $prior}]} {set prior {}}
    set index 0
    foreach item $value {
        if {$item ne $value} {_workspaceChangedResourceReferences $item [lindex $prior $index] [expr {$depth+1}] result}
        incr index
    }
}
proc ::GX::_workspacePreflightResources {payload {prior {}}} {
    set changed {}
    _workspaceChangedResourceReferences $payload $prior 0 changed
    dict for {sha resource} $changed {
        if {[_documentResourceDisposable [dict get $resource metadata]]} {_documentResourceIdentity $resource} else {interactiveDocumentResourceInfo $resource}
    }
}

# UI subscriptions contain widget paths only. Listing/identity continue to come
# from the existing Document registry; an idle refresh never owns saved state.
proc ::GX::sessionWorkspaceViewsChanged {} {
    if {![llength [info commands winfo]]} return
    if {$::GX::SessionWorkspace::views eq {} && $::GX::SessionWorkspace::titles eq {}} return
    if {$::GX::SessionWorkspace::refreshTimer eq {}} {set ::GX::SessionWorkspace::refreshTimer [after idle ::GX::sessionWorkspaceViewsRefresh]}
}
proc ::GX::sessionWorkspaceViewsRefresh {} {
    set ::GX::SessionWorkspace::refreshTimer {}
    sessionWorkspaceViewerTitlesRefresh
    # An empty Session page is a valid UI state. A Document token is meaningful
    # only while a Session is open; asking for one here used to raise at idle.
    if {$::GX::currentSession eq {}||![file isdirectory $::GX::currentSession]} {
        set signature [list no-session]
    } else {
        set signature [list [interactiveDocumentSessionToken]]
        foreach workspace [sessionWorkspaceList] {lappend signature [list [dict get $workspace workspace_id] [dict get $workspace name] [dict get $workspace type] [dict get $workspace provider_id] [dict get $workspace preview] [dict get $workspace generation] [dict get $workspace revision]]}
    }
    dict for {frame prior} $::GX::SessionWorkspace::views {
        if {![winfo exists $frame]} {dict unset ::GX::SessionWorkspace::views $frame;continue}
        if {$prior eq $signature} continue
        set selected [$frame.tree selection]
        sessionWorkspaceGuiAction $frame refresh
        if {[llength $selected]==1&&[$frame.tree exists $selected]} {$frame.tree selection set $selected}
        dict set ::GX::SessionWorkspace::views $frame $signature
    }
}
foreach command {sessionWorkspaceCreate sessionWorkspaceUpdate sessionWorkspaceRename sessionWorkspaceDelete sessionWorkspacePreviewSet _sessionWorkspaceImportPath} {
    rename ::GX::$command ::GX::${command}_workspace_ui_base
    proc ::GX::$command args [format {
        set result [::GX::%s_workspace_ui_base {*}$args]
        ::GX::sessionWorkspaceViewsChanged
        return $result
    } $command]
}
rename ::GX::sessionFileExplorerPopulate ::GX::sessionFileExplorerPopulate_workspace056_base
proc ::GX::sessionFileExplorerPopulate {} {
    set result [sessionFileExplorerPopulate_workspace056_base]
    sessionWorkspaceViewsChanged
    return $result
}

source [file join [file dirname [info script]] session_workspace_viewer_gui.tcl]

source [file join [file dirname [info script]] session_workspace_gui_host.tcl]
source [file join [file dirname [info script]] workspace_external_host_v1.tcl]
