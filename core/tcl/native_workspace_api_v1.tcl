# SPDX-License-Identifier: GPL-3.0-or-later
# Session/GUI transport for the native domain. Only handles, provider contracts
# and weak lifecycle context live here; canonical saved state lives in C++.
namespace eval ::GX::NativeWorkspace {variable handle {};variable sessionToken {};variable providers {}}
proc ::GX::_nativeWorkspaceLibraryRequire {} {
    if {![llength [info commands ::GX::workspaceNative]]} {load [file join $::GX::scriptDir core workspace libgxtxt_workspace[info sharedlibextension]] Gxtxt_workspace}
}
proc ::GX::nativeWorkspaceJsonDecode {json} {_nativeWorkspaceLibraryRequire;return [workspaceNative json_decode $json]}
proc ::GX::nativeWorkspaceJsonEncode {typed} {_nativeWorkspaceLibraryRequire;return [workspaceNative json_encode $typed]}
proc ::GX::nativeWorkspaceJsonStateEncode {payload} {
    if {[dict keys [dict remove $payload workspace_metadata]] ne {json}} {error {JSON Workspace transport requires exactly its explicit json field}}
    set typed [nativeWorkspaceJsonDecode [dict get $payload json]]
    if {[lindex $typed 0] ne {object}} {error {Workspace JSON state must be an object}}
    return $typed
}
proc ::GX::nativeWorkspaceJsonStateDecode {typed} {return [dict create json [nativeWorkspaceJsonEncode $typed]]}
proc ::GX::nativeWorkspaceJsonValidate {format version payload} {
    set typed [nativeWorkspaceJsonStateEncode $payload];set fields [lindex $typed 1]
    if {![dict exists $fields format] || [dict get $fields format] ne [list text $format] || ![dict exists $fields version] || [lindex [dict get $fields version] 1] ne $version} {error {Incompatible JSON Workspace format/version}}
}
proc ::GX::nativeWorkspaceApiInfo {} {
    return [dict create api_id NATIVE_WORKSPACE_API_v1 api_version 1 authority native_cpp typed_values 1 operations {create get open close query save save_as set_property set_state rename delete notes status flush history_save history_list history_get history_rename history_delete} asynchronous_save {save asynchronous=1} legacy_conversion 0]
}
proc ::GX::_nativeWorkspaceWriteAllowed {} {
    if {[info exists ::GX::Parameters::publicationPhase] && $::GX::Parameters::publicationPhase eq {prepare}} {error {Workspace writes are unavailable while Parameter listeners prepare their drafts}}
}
proc ::GX::_nativeWorkspaceRequire {} {
    variable ::GX::NativeWorkspace::handle
    variable ::GX::NativeWorkspace::sessionToken
    set token [interactiveDocumentSessionToken]
    if {$handle ne {} && $token ne $sessionToken} {workspaceNative close $handle;set handle {};set sessionToken {}}
    if {$handle eq {}} {
        _nativeWorkspaceLibraryRequire
        set next [workspaceNative open [file join [_interactiveDocumentRequireSession] metadata workspaces.sqlite]]
        try {
            dict for {provider descriptor} $::GX::NativeWorkspace::providers {_nativeWorkspaceRegisterOn $next $provider $descriptor}
        } on error {message options} {workspaceNative close $next;return -options $options $message}
        set handle $next;set sessionToken $token
        if {[catch {_nativeWorkspaceTransitionRecover $handle} message options]} {catch {workspaceNative close $handle};set handle {};set sessionToken {};return -options $options $message}
    }
    return $handle
}
proc ::GX::_nativeWorkspaceRegisterOn {handle provider descriptor} {
    workspaceNative register $handle $provider [dict get $descriptor module_id] [dict get $descriptor schema] [dict get $descriptor version] [dict get $descriptor required_fields]
}
proc ::GX::nativeWorkspaceProviderRegister {provider descriptor} {
    foreach field {module_id schema version required_fields} {if {![dict exists $descriptor $field]} {error "Native Workspace provider requires $field"}}
    if {[dict exists $::GX::NativeWorkspace::providers $provider] && [dict get $::GX::NativeWorkspace::providers $provider] ne $descriptor} {error {Native Workspace provider contract cannot change in a running application}}
    if {$::GX::NativeWorkspace::handle ne {}} {_nativeWorkspaceRegisterOn $::GX::NativeWorkspace::handle $provider $descriptor}
    dict set ::GX::NativeWorkspace::providers $provider $descriptor
}
proc ::GX::nativeWorkspaceCloseSession {} {
    if {$::GX::NativeWorkspace::handle ne {}} {workspaceNative close $::GX::NativeWorkspace::handle;set ::GX::NativeWorkspace::handle {};set ::GX::NativeWorkspace::sessionToken {}}
}
proc ::GX::nativeWorkspaceFlushAll {} {
    if {$::GX::NativeWorkspace::handle ne {}} {return [workspaceNative flush_all $::GX::NativeWorkspace::handle]}
    return durable
}
proc ::GX::nativeWorkspaceCreate {provider name typedState {typedProperties {object {}}} {typedProvenance {object {}}} {asynchronous 0}} {
    _nativeWorkspaceWriteAllowed
    if {![string is boolean -strict $asynchronous]} {error {Async Save flag must be boolean}}
    set handle [_nativeWorkspaceRequire]
    foreach typed [list $typedState $typedProperties $typedProvenance] {_nativeWorkspaceScientificOwnersAdmit $handle $typed}
    set receipt [workspaceNative create $handle $provider $name $typedState $typedProperties $typedProvenance]
    if {!$asynchronous} {set receipt [workspaceNative flush $handle [dict get $receipt id]]}
    return $receipt
}
proc ::GX::nativeWorkspaceGet {id} {return [workspaceNative get [_nativeWorkspaceRequire] $id]}
proc ::GX::nativeWorkspaceOpen {id} {set snapshot [nativeWorkspaceGet $id];_workspaceProvider [dict get $snapshot provider_id];return $snapshot}
proc ::GX::nativeWorkspaceClose {id} {return [nativeWorkspaceFlush $id]}
proc ::GX::nativeWorkspaceProperties {id} {return [workspaceNative properties [_nativeWorkspaceRequire] $id]}
proc ::GX::nativeWorkspaceSetProperties {expected typedProperties {asynchronous 0}} {
    _nativeWorkspaceWriteAllowed
    if {![string is boolean -strict $asynchronous]} {error {Async Save flag must be boolean}}
    set handle [_nativeWorkspaceRequire];_nativeWorkspaceScientificOwnersAdmit $handle $typedProperties
    set receipt [workspaceNative save_properties $handle [dict get $expected id] [dict get $expected generation] [dict get $expected revision] $typedProperties]
    if {!$asynchronous} {set receipt [nativeWorkspaceFlush [dict get $receipt id]]}
    return $receipt
}
proc ::GX::nativeWorkspaceSetState {expected typedState} {return [nativeWorkspaceSave $expected $typedState [nativeWorkspaceProperties [dict get $expected id]]]}
proc ::GX::nativeWorkspaceSetProperty {expected name typedValue} {
    set properties [lindex [nativeWorkspaceProperties [dict get $expected id]] 1]
    dict set properties $name $typedValue
    return [nativeWorkspaceSetProperties $expected [list object $properties]]
}
proc ::GX::nativeWorkspaceMetadata {id} {return [workspaceNative metadata [_nativeWorkspaceRequire] $id]}
proc ::GX::_nativeWorkspaceExists {id} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq {}} {return 0}
    if {$::GX::NativeWorkspace::handle eq {} && ![file isfile [file join $::GX::currentSession metadata workspaces.sqlite]]} {return 0}
    if {[catch {nativeWorkspaceMetadata $id} value options]} {
        if {[dict get $options -errorcode] eq {GX WORKSPACE MISSING}} {return 0}
        return -options $options $value
    }
    return 1
}
proc ::GX::_nativeWorkspaceRegistryProjection {session legacy} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq {} || [file normalize $session] ne [file normalize $::GX::currentSession]} {return $legacy}
    if {$::GX::NativeWorkspace::handle eq {} && ![file isfile [file join $session metadata workspaces.sqlite]]} {return $legacy}
    for {set offset 0} {1} {incr offset 10000} {
        set rows [nativeWorkspaceQuery {} {} {} $offset 10000]
        foreach item $rows {dict set item native_workspace 1;dict set legacy [dict get $item id] $item}
        if {[llength $rows]<10000} break
    }
    return $legacy
}
proc ::GX::_nativeWorkspaceDocumentRead {id} {
    set metadata [nativeWorkspaceMetadata $id]
    set descriptor [_workspaceProvider [dict get $metadata provider_id]]
    if {[dict get $metadata format] ne [dict get $descriptor schema] || [dict get $metadata format_version] ni [datasetPublicationV2DictDefault $descriptor accepted_versions [list [dict get $descriptor version]]]} {error {Native Workspace schema is incompatible; use metadata inspection or confirmed Delete}}
    set item [nativeWorkspaceGet $id]
    set provider [dict get $item provider_id]
    if {[dict exists $::GX::SessionWorkspace::providers $provider decode]} {
        set state [uplevel #0 [list {*}[dict get $::GX::SessionWorkspace::providers $provider decode] [dict get $item state]]]
    } else {set state [nativeWorkspaceDecode [dict get $item state]]}
    set properties [nativeWorkspaceDecode [dict get $item properties]]
    set metadata [dict merge [dict create name [dict get $item name] preview {} note {}] $properties]
    dict set metadata name [dict get $item name]
    if {[dict get $item notes] ne {}} {dict set metadata note [dict create api_id NOTE_DOCUMENT_API_v1 workspace_id $id native_notes 1]}
    dict set state workspace_metadata $metadata
    dict set item payload $state
    dict set item typed_properties [dict get $item properties]
    dict set item origin [nativeWorkspaceDecode [dict get $item provenance]]
    return [dict remove $item state properties provenance notes]
}
proc ::GX::nativeWorkspaceQuery {{provider {}} {owner {}} {prefix {}} {offset 0} {limit 1000}} {return [workspaceNative query [_nativeWorkspaceRequire] $provider $owner $prefix $offset $limit]}
proc ::GX::nativeWorkspaceSave {expected typedState typedProperties {asynchronous 0}} {
    _nativeWorkspaceWriteAllowed
    if {![string is boolean -strict $asynchronous]} {error {Async Save flag must be boolean}}
    set handle [_nativeWorkspaceRequire]
    foreach typed [list $typedState $typedProperties] {_nativeWorkspaceScientificOwnersAdmit $handle $typed}
    set receipt [workspaceNative save $handle [dict get $expected id] [dict get $expected generation] [dict get $expected revision] $typedState $typedProperties]
    if {!$asynchronous} {set receipt [workspaceNative flush $handle [dict get $receipt id]]}
    return $receipt
}
proc ::GX::nativeWorkspaceSaveAs {id name} {
    _nativeWorkspaceWriteAllowed
    set source [nativeWorkspaceMetadata $id]
    _workspaceProvider [dict get $source provider_id]
    set handle [_nativeWorkspaceRequire]
    _nativeWorkspaceScientificOwnersAdmit $handle [workspaceNative resource_references $handle $id]
    set receipt [workspaceNative duplicate $handle $id [dict get $source generation] [dict get $source revision] $name]
    sessionWorkspaceViewsChanged
    return $receipt
}
proc ::GX::nativeWorkspaceCheckpoint {} {if {$::GX::NativeWorkspace::handle ne {}} {return [workspaceNative checkpoint $::GX::NativeWorkspace::handle]};return durable}
proc ::GX::nativeWorkspaceLineage {id} {return [workspaceNative lineage [_nativeWorkspaceRequire] $id]}
proc ::GX::_nativeWorkspaceHasResources {typed} {
    lassign $typed kind value
    if {$kind eq {resource}} {return 1}
    if {$kind eq {object}} {dict for {key item} $value {if {[_nativeWorkspaceHasResources $item]} {return 1}}}
    if {$kind eq {array}} {foreach item $value {if {[_nativeWorkspaceHasResources $item]} {return 1}}}
    return 0
}
proc ::GX::nativeWorkspaceRename {expected name} {return [_nativeWorkspaceMutation rename $expected $name]}
proc ::GX::nativeWorkspaceNotes {expected text} {return [_nativeWorkspaceMutation notes $expected $text]}
proc ::GX::nativeWorkspaceDelete {expected confirmed} {
    if {![string is boolean -strict $confirmed] || !$confirmed} {error {Workspace Delete requires explicit confirmation}}
    return [_nativeWorkspaceMutation delete $expected 1]
}
proc ::GX::_nativeWorkspaceMutation {operation expected value} {
    _nativeWorkspaceWriteAllowed
    set handle [_nativeWorkspaceRequire]
    set before [nativeWorkspaceMetadata [dict get $expected id]]
    set receipt [workspaceNative $operation $handle [dict get $expected id] [dict get $expected generation] [dict get $expected revision] $value]
    set receipt [workspaceNative flush $handle [dict get $receipt id]]
    if {$operation in {rename notes}} {_nativeWorkspaceMetadataAdvanced $before [nativeWorkspaceMetadata [dict get $receipt id]]}
    return $receipt
}
proc ::GX::nativeWorkspaceStatus {id} {return [workspaceNative status [_nativeWorkspaceRequire] $id]}
proc ::GX::nativeWorkspaceFlush {id} {return [workspaceNative flush [_nativeWorkspaceRequire] $id]}
proc ::GX::nativeWorkspaceHistorySave {expected name typedRecord typedAuxiliary typedContext} {
    _nativeWorkspaceWriteAllowed
    set handle [_nativeWorkspaceRequire]
    set before [nativeWorkspaceMetadata [dict get $expected id]]
    foreach typed [list $typedRecord $typedAuxiliary $typedContext] {_nativeWorkspaceScientificOwnersAdmit $handle $typed}
    set receipt [workspaceNative history_save $handle [dict get $expected id] [dict get $expected generation] [dict get $expected revision] $name $typedRecord $typedAuxiliary $typedContext]
    set archive [dict get $receipt archive_id]
    set receipt [workspaceNative flush $handle [dict get $receipt id]]
    _nativeWorkspaceMetadataAdvanced $before [nativeWorkspaceMetadata [dict get $receipt id]]
    return [dict merge $receipt [dict create archive_id $archive]]
}
proc ::GX::nativeWorkspaceHistoryList {id} {return [workspaceNative history_list [_nativeWorkspaceRequire] $id]}
proc ::GX::nativeWorkspaceHistoryGet {id archive} {return [workspaceNative history_get [_nativeWorkspaceRequire] $id $archive]}
proc ::GX::nativeWorkspaceHistoryRename {expected archive name} {return [_nativeWorkspaceHistoryMutation history_rename $expected $archive $name]}
proc ::GX::nativeWorkspaceHistoryDelete {expected archive confirmed} {
    if {![string is boolean -strict $confirmed] || !$confirmed} {error {History archive Delete requires explicit confirmation}}
    return [_nativeWorkspaceHistoryMutation history_delete $expected $archive 1]
}
proc ::GX::_nativeWorkspaceHistoryMutation {operation expected archive value} {
    _nativeWorkspaceWriteAllowed
    set handle [_nativeWorkspaceRequire]
    set before [nativeWorkspaceMetadata [dict get $expected id]]
    workspaceNative $operation $handle [dict get $expected id] [dict get $expected generation] [dict get $expected revision] $archive $value
    set receipt [workspaceNative flush $handle [dict get $expected id]]
    _nativeWorkspaceMetadataAdvanced $before [nativeWorkspaceMetadata [dict get $expected id]]
    return $receipt
}

proc ::GX::_nativeWorkspaceScientificOwnersAdmit {handle typed} {
    lassign $typed kind value
    if {$kind eq {resource}} {
        set reference [nativeWorkspaceDecode $typed]
        # Consult the existing managed-resource authority, including its retired
        # owner marker. A descriptor cannot declare its own trusted generation.
        _documentResourceIdentity $reference
        set owner [dict get $reference document_id]
        set generation [_documentResourceOwnerGeneration $owner]
        if {$generation ne [dict get $reference owner_generation]} {error {Scientific resource owner generation changed}}
        workspaceNative register_resource_owner $handle $owner $generation
    }
    if {$kind in {object resource}} {dict for {key child} $value {_nativeWorkspaceScientificOwnersAdmit $handle $child}}
    if {$kind eq {array}} {foreach child $value {_nativeWorkspaceScientificOwnersAdmit $handle $child}}
}
proc ::GX::_nativeWorkspaceResourceReferences {typed resultName} {
    upvar 1 $resultName result
    lassign $typed kind value
    if {$kind eq {resource}} {
        set reference [nativeWorkspaceDecode $typed]
        dict set result [list [dict get $reference document_id] [dict get $reference owner_generation] [dict get $reference sha256]] $reference
    }
    if {$kind in {object resource}} {dict for {key child} $value {_nativeWorkspaceResourceReferences $child result}}
    if {$kind eq {array}} {foreach child $value {_nativeWorkspaceResourceReferences $child result}}
}
# Explicit collection/deletion boundaries traverse native typed roots, including
# archives that are independent of the active P017 timeline. Ordinary GUI/query
# actions do not invoke this complete retention scan.
proc ::GX::_nativeWorkspaceRetainedReferences {{exclude {}}} {
    set references {}
    if {$::GX::NativeWorkspace::handle eq {} && ![file isfile [file join [_interactiveDocumentRequireSession] metadata workspaces.sqlite]]} {return $references}
    set typed [workspaceNative retained_references [_nativeWorkspaceRequire] $exclude]
    foreach reference [nativeWorkspaceDecode $typed] {
        dict set references [list [dict get $reference document_id] [dict get $reference owner_generation] [dict get $reference sha256]] $reference
    }
    return $references
}
proc ::GX::_nativeWorkspaceRetiredGeneration {document} {
    if {![file isfile [file join [_interactiveDocumentRequireSession] metadata workspaces.sqlite]]} {return {}}
    if {[catch {workspaceNative retired_owner_generation [_nativeWorkspaceRequire] $document} generation options]} {
        if {[dict get $options -errorcode] eq {GX WORKSPACE MISSING}} {return {}}
        return -options $options $generation
    }
    return $generation
}
proc ::GX::_nativeWorkspaceResourcePins {document excludeOwner referencesName} {
    upvar 1 $referencesName references
    set exclude [expr {$excludeOwner?$document:{}}]
    dict for {key reference} [_nativeWorkspaceRetainedReferences $exclude] {
        if {[dict get $reference document_id] ne $document} continue
        set sha [dict get $reference sha256]
        if {![dict exists $references $sha]} {
            if {[dict exists $reference metadata] && [_documentResourceDisposable [dict get $reference metadata]]} {_documentResourceIdentity $reference} else {interactiveDocumentResourceInfo [_documentResourceProvenanceReference $reference]}
            dict set references $sha [dict remove $reference metadata]
        }
    }
}
proc ::GX::_nativeWorkspaceMetadataAdvanced {before after {preview {}} {metadataProperties {}}} {
    # Notes/Name change neither the typed saved model nor staged properties.
    # Rebase only viewers still holding this exact unchanged scientific stamp.
    set stamp [list [dict get $before generation] [dict get $before revision] [dict get $before sha256]]
    if {[info exists ::GX::ViewerGui::instances]} {dict for {window instance} $::GX::ViewerGui::instances {
        if {[datasetPublicationV2DictDefault $instance workspace_id {}] eq [dict get $before id] && [datasetPublicationV2DictDefault $instance token {}] eq [interactiveDocumentSessionToken] && [datasetPublicationV2DictDefault $instance workspace_stamp {}] eq $stamp} {
            dict set ::GX::ViewerGui::instances $window workspace_stamp [list [dict get $after generation] [dict get $after revision] [dict get $after sha256]]
            if {$preview ne {}} {
                foreach field {workspace_properties saved_workspace_properties} {
                    set properties [lindex [dict get $instance $field] 1]
                    dict set properties preview $preview
                    dict set ::GX::ViewerGui::instances $window $field [list object $properties]
                }
            }
            if {$metadataProperties ne {}} {
                foreach field {workspace_properties saved_workspace_properties} {
                    set properties [lindex [dict get $::GX::ViewerGui::instances $window $field] 1]
                    dict for {key value} $metadataProperties {
                        if {$value eq {@gxtxt.workspace.property.remove}} {dict unset properties $key} else {dict set properties $key $value}
                    }
                    dict set ::GX::ViewerGui::instances $window $field [list object $properties]
                }
            }
        }
    }}
    if {[info exists ::GX::SessionWorkspace::adapters]} {
        dict for {window adapter} $::GX::SessionWorkspace::adapters {
            if {[dict get $adapter token] ne [interactiveDocumentSessionToken] || ![winfo exists $window] || [winfo id $window] != [dict get $adapter window_id]} continue
            if {[dict exists $adapter callbacks metadata_advanced]} {
                if {[catch {uplevel #0 [list {*}[dict get $adapter callbacks metadata_advanced] $before $after]} message]} {
                    # Persistence has already committed. A stale client remains
                    # protected by its old receipt; do not report a false failure.
                    puts stderr "Workspace metadata notification: $message"
                }
            }
        }
    }
    if {[info exists ::GX::Native3DGeometry::scenes]} {
        dict for {token scene} $::GX::Native3DGeometry::scenes {
            if {[dict get $scene session_token] eq [interactiveDocumentSessionToken] && [dict get $scene document_id] eq [dict get $before id] && [dict get $scene generation] eq [dict get $before generation] && [dict get $scene revision] eq [dict get $before revision]} {dict set ::GX::Native3DGeometry::scenes $token revision [dict get $after revision]}
        }
    }
    if {[llength [info commands workspaceExternalMetadataAdvanced]] && [catch {workspaceExternalMetadataAdvanced $before $after} message]} {puts stderr "Workspace desktop metadata notification: $message"}
}

# Explicit shape adapters preserve scientific strings. They never guess whether
# text is a dictionary, an array, a label or executable code.
proc ::GX::nativeWorkspaceEncode {shape value {depth 0}} {
    if {$depth>64} {error {Typed Workspace adapter exceeds nesting bound}}
    lassign $shape kind contract
    switch -- $kind {
        text - int - bool - real - null {return [list $kind $value]}
        typed {return $value}
        named {return [nativeWorkspaceEncode [dict get $::GX::WorkspaceScientificCodec::shapes $contract] $value [expr {$depth+1}]]}
        codec {return [uplevel #0 [list {*}$contract $value]]}
        tuple {
            if {[llength $value]!=[llength $contract]} {error {Workspace tuple differs from its declared schema}}
            set values {};foreach item $value shape $contract {lappend values [nativeWorkspaceEncode $shape $item [expr {$depth+1}]]}
            return [list array $values]
        }
        number_or_symbol {
            if {$value in $contract} {return [list text $value]}
            return [list real $value]
        }
        scientific_real {
            if {[string tolower $value] in {nan inf +inf -inf infinity +infinity -infinity}} {
                return [nativeWorkspaceEncode {record {classification text value text}} [dict create classification scientific_nonfinite value $value] [expr {$depth+1}]]
            }
            return [list real $value]
        }
        map {
            set fields {};dict for {key item} $value {dict set fields $key [nativeWorkspaceEncode $contract $item [expr {$depth+1}]]}
            return [list object $fields]
        }
        array {
            set values {};foreach item $value {lappend values [nativeWorkspaceEncode $contract $item [expr {$depth+1}]]}
            return [list array $values]
        }
        record {
            set fields {};dict for {key item} $value {
                if {![dict exists $contract $key]} {error "Workspace schema has no typed field '$key'"}
                dict set fields $key [nativeWorkspaceEncode [dict get $contract $key] $item [expr {$depth+1}]]
            }
            return [list object $fields]
        }
        resource {
            set fields {};dict for {key item} $value {
                set subshape [expr {$key eq {size_bytes}?{int}:{text}}]
                if {$key eq {metadata}} {set subshape $contract}
                dict set fields $key [nativeWorkspaceEncode $subshape $item [expr {$depth+1}]]
            }
            return [list resource $fields]
        }
        default {error "Unsupported native Workspace adapter shape '$kind'"}
    }
}
proc ::GX::nativeWorkspaceDecode {typed {depth 0}} {
    if {$depth>64 || [llength $typed]!=2} {error {Invalid typed Workspace value}}
    lassign $typed kind value
    switch -- $kind {
        text - int - bool - real - null {return $value}
        object - resource {set result {};dict for {key item} $value {dict set result $key [nativeWorkspaceDecode $item [expr {$depth+1}]]};return $result}
        array {set result {};foreach item $value {lappend result [nativeWorkspaceDecode $item [expr {$depth+1}]]};return $result}
        default {error {Unsupported typed Workspace kind}}
    }
}

# Script-facing typed graph admission reuses each existing scientific owner.
# Numeric spellings may differ in a projection, but kinds, values, ordered
# containers and scientific text must agree; the submitted graph is retained.
proc ::GX::nativeWorkspaceScriptValidate {provider typedState} {
    set descriptor [_workspaceProvider $provider]
    set payload [uplevel #0 [list {*}[datasetPublicationV2DictDefault $descriptor decode ::GX::nativeWorkspaceDecode] $typedState]]
    _workspaceValidatePayload $provider $payload [dict get $descriptor version] 1
    set encoded [uplevel #0 [list {*}[dict get $descriptor encode] $payload]]
    _nativeWorkspaceLibraryRequire
    if {![workspaceNative typed_equivalent $typedState $encoded]} {error {Typed script state differs from its declared native provider schema}}
}

proc ::GX::nativeWorkspacePortableDrain {session} {
    set database [file join [file normalize $session] metadata workspaces.sqlite]
    if {![file isfile $database]} {return durable}
    _nativeWorkspaceLibraryRequire
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [file normalize $session]} {
        set handle [_nativeWorkspaceRequire]
        workspaceNative flush_all $handle
        return [workspaceNative checkpoint $handle]
    }
    # A noncurrent Session must have no writer. Never copy an unsettled WAL or
    # interrupt a live store in another Session/process.
    set temporary [workspaceNative open $database]
    try {workspaceNative checkpoint $temporary} finally {workspaceNative close $temporary}
    return durable
}
