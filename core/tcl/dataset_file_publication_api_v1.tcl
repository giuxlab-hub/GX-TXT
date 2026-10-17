# GX-TXT Dataset File Publication API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Public, headless transaction for publishing an already-produced file as a
# Canonical Dataset. This reuses the normal Dataset Registry and Metadata API.

namespace eval ::GX {
    variable datasetFilePublicationApiVersion 1
}

proc ::GX::datasetFilePublicationDictDefault {dictionary key default} {
    return [expr {[dict exists $dictionary $key] ? [dict get $dictionary $key] : $default}]
}

proc ::GX::datasetFilePublicationSourceIds {value} {
    if {$value eq ""} { return {} }
    if {![regexp {[;,]} $value] && [llength $value] > 1} { set items $value } else { set items [split [string map {"," ";"} $value] ";"] }
    set out {}
    foreach id $items {
        set id [string trim $id]
        if {$id ne "" && [lsearch -exact $out $id] < 0} { lappend out $id }
    }
    return $out
}

proc ::GX::datasetFilePublicationExtension {format} {
    set extension [string tolower [string trimleft [string trim $format] .]]
    regsub -all {[^a-z0-9]+} $extension _ extension
    set extension [string trim $extension _]
    if {$extension eq ""} { set extension dat }
    return $extension
}

proc ::GX::datasetFilePublicationValidateText {path} {
    set fd [open $path rb]
    fconfigure $fd -translation binary -encoding binary
    try { set bytes [read $fd] } finally { close $fd }
    if {[catch {set text [encoding convertfrom utf-8 $bytes]}] || [encoding convertto utf-8 $text] ne $bytes} {
        error "Text publication source is not valid UTF-8"
    }
}

proc ::GX::datasetFilePublicationPlace {staged final} {
    file rename -- $staged $final
    return $final
}

proc ::GX::datasetFilePublicationCommitRegistry {session datasetId fields} {
    datasetRegister $datasetId $fields
    saveDatasetRegistry $session
}

proc ::GX::datasetFilePublicationRegistryFields {moduleId request target sha storageKind sourceIds} {
    set contract [string trim [dict get $request contract]]
    set format [string trim [dict get $request format]]
    set mediaType [string trim [dict get $request media_type]]
    return [list \
        kind $contract contract $contract format $format \
        storage_kind $storageKind storage_provider file media_type $mediaType \
        path $target columns "" variables "" units "" semantic_roles "" var_count 0 \
        source_module $moduleId producer_module $moduleId \
        producer_version [datasetFilePublicationDictDefault $request producer_version ""] \
        source_dataset_ids [join $sourceIds {;}] \
        source [datasetFilePublicationDictDefault $request source ""] \
        provenance [datasetFilePublicationDictDefault $request provenance ""] \
        notes [datasetFilePublicationDictDefault $request notes ""] \
        publication_api_version file-v1 dataset_file_publication_api_version 1 \
        variable_schema_api_version 3 canonical_sha256 $sha sha256 $sha \
        integrity_algorithm sha256 created_at [datasetFilePublicationDictDefault $request created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]] updated_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] \
        row_count 0 sample_count 0 immutable [expr {!![datasetFilePublicationDictDefault $request immutable 0]}]]
}

proc ::GX::datasetFilePublicationPublish {session moduleId request} {
    variable currentSession
    variable datasetRegistry
    if {$::GX::DatasetPrivate::activeContext ne {}} {set moduleId [dict get $::GX::DatasetPrivate::activeContext module_id]}

    if {[catch {dict size $request}]} { error "Dataset file publication request must be a dictionary" }
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "Dataset file publication session does not exist: $session" }
    set moduleId [datasetPublicationV2ValidateId module $moduleId]
    foreach key {dataset_id contract format source_file storage_kind media_type} {
        if {![dict exists $request $key] || [string trim [dict get $request $key]] eq ""} {
            error "Dataset file publication request is missing '$key'"
        }
    }
    set datasetId [datasetPublicationV2ValidateId dataset [dict get $request dataset_id]]
    set contract [string trim [dict get $request contract]]
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $contract]} { error "Invalid Dataset contract '$contract'" }
    set format [string trim [dict get $request format]]
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.+-]*$} $format]} { error "Invalid Dataset file format '$format'" }
    set storageKind [string tolower [string trim [dict get $request storage_kind]]]
    if {$storageKind ni {text binary}} { error "Dataset file publication storage_kind must be text or binary" }
    set mediaType [string trim [dict get $request media_type]]
    if {![regexp {^[^[:space:]/]+/[^[:space:]/]+$} $mediaType]} { error "Invalid Dataset media_type '$mediaType'" }
    if {[dict exists $request immutable]&&![string is boolean -strict [dict get $request immutable]]} {error {Dataset immutable policy must be boolean}}
    set sourceFile [file normalize [dict get $request source_file]]
    if {![file isfile $sourceFile]} { error "Dataset file publication source does not exist: $sourceFile" }
    if {[dict exists $request verified_reference]} {return [_datasetFilePublicationReference $session $moduleId $request]}
    if {$storageKind eq "text"} { datasetFilePublicationValidateText $sourceFile }

    set metadata [datasetFilePublicationDictDefault $request structured_metadata ""]
    if {$metadata ne ""} {
        if {[catch {dict size $metadata}]} { error "structured_metadata must be a dictionary" }
        # Use the existing portable serializer as a validation-only pass. The
        # authoritative write still goes through Dataset Metadata API v1.
        dict for {key value} $metadata {_datasetMetadataUserKey $key}
        _datasetMetadataPortableSerialize $metadata
    }

    set currentSession $session
    loadDatasetRegistry $session
    set replaceOwned [expr {[dict exists $request replace_owned] && [string is true -strict [dict get $request replace_owned]]}]
    set existing [datasetField $datasetId id ""]
    set namespace [_datasetPublicationNamespace $session $moduleId $request]
    set delegated [expr {$existing ne {} && $replaceOwned && [_datasetFileEditGrant $session $datasetId $moduleId $contract]}]
    if {$existing ne {} && !$delegated} {_datasetNamespaceRequireModuleWrite $session $moduleId $datasetId}
    if {$existing ne {} && [dict exists $request expected_sha256] && [dict get $request expected_sha256] ne [datasetField $datasetId sha256 [datasetField $datasetId canonical_sha256 {}]]} {error {Dataset changed since opening; reopen before committing}}
    set producer $moduleId
    if {$delegated} {
        set producer [datasetField $datasetId source_module {}]
        set private [datasetPrivateMetadataRead $session $datasetId]
        set namespace [dict get $private _gxtxt.framework.dataset_namespace]
    }
    if {$existing ne ""} {
        if {[string is true -strict [datasetField $datasetId immutable 0]]} {error "Dataset '$datasetId' is immutable"}
        if {!$replaceOwned} { error "Dataset ID '$datasetId' already exists" }
        set owner [datasetField $datasetId source_module [datasetField $datasetId producer_module ""]]
        if {(!$delegated && $owner ne $moduleId) || (!$delegated && [datasetField $datasetId dataset_file_publication_api_version ""] ne "1")} {
            error "Dataset ID '$datasetId' already exists and is not owned by this module through Dataset File Publication API v1"
        }
        set target [datasetField $datasetId path ""]
        if {$target eq ""} { error "Owned Dataset '$datasetId' has no publication target" }
    } else {
        set extension [datasetFilePublicationExtension $format]
        set target [file join datasets publications files "${datasetId}.${extension}"]
    }
    set target [datasetPublicationV2SafeRelative $target]
    set final [file normalize [file join $session $target]]
    set storageRoot [file normalize [expr {$delegated?[file join $session datasets]:[file join $session datasets publications files]}]]
    if {![_datasetDeletePathWithin $final $storageRoot]} { error "Dataset file publication target escapes managed Session storage" }
    if {$sourceFile eq $final} { error "Dataset file publication source must not be the authoritative target" }
    if {$existing eq "" && [file exists $final]} { error "Dataset file publication target already exists: $target" }

    # A replacement changes content, not the original record's history. An
    # explicitly present (even empty) request field remains authoritative.
    if {$existing ne ""} {
        foreach field {created_at source_dataset_ids source notes producer_version provenance} {
            if {![dict exists $request $field]} {dict set request $field [datasetField $datasetId $field ""]}
        }
    }
    set sourceIds [datasetFilePublicationSourceIds [datasetFilePublicationDictDefault $request source_dataset_ids {}]]
    foreach sourceId $sourceIds {
        datasetPublicationV2ValidateId source_dataset $sourceId
        if {$sourceId eq $datasetId} { error "Dataset file publication provenance may not reference the Dataset being published" }
        if {[datasetField $sourceId id ""] eq ""} { error "Source Dataset '$sourceId' is not registered in this session" }
    }

    set metadata [_scientificPublicationMetadata $session $datasetId $metadata $sourceIds]
    set registryPath [datasetRegistryPath $session]
    set metadataRel [datasetField $datasetId structured_metadata_file [_datasetMetadataRelativePath $datasetId]]
    if {[file pathtype $metadataRel] eq "absolute"} { error "Dataset metadata path must be session-relative" }
    set metadataPath [file normalize [file join $session $metadataRel]]
    if {![_datasetDeletePathWithin $metadataPath [file join $session metadata datasets]]} { error "Dataset metadata path is outside Session metadata storage" }
    datasetAuthorityEnlist $final
    datasetAuthorityEnlist $metadataPath
    datasetAuthorityEnlist $registryPath
    file mkdir [file dirname $final]
    set staged [file join [file dirname $final] ".[file tail $final].[pid].[clock clicks].partial"]
    try {
        file copy -- $sourceFile $staged
        set sha [sha256File $staged]
        if {[dict exists $request verified_source_sha256]&&$sha ne [dict get $request verified_source_sha256]} {error {Source changed during scientific import}}
        # The shared transaction already owns durable preimages of all three
        # authorities. Keep the original target until atomic replacement.
        if {$existing ne {}} {file rename -force -- $staged $final} else {datasetFilePublicationPlace $staged $final}
        set fields [datasetFilePublicationRegistryFields $producer $request $target $sha $storageKind $sourceIds]
        if {$delegated} {lappend fields last_editor_module $moduleId}
        datasetFilePublicationCommitRegistry $session $datasetId $fields
        if {$metadata ne ""} {
            datasetMetadataWrite $session $datasetId $metadata
            _datasetMetadataOriginRecord $session $datasetId module:$producer [dict keys $metadata]
        }
        _datasetFrameworkMetadataUpdate $session $datasetId [dict create dataset_namespace $namespace]
    } on error {failure options} {
        catch {file delete -force -- $staged}
        return -options $options "Dataset file publication failed: $failure"
    }
    return [dict create dataset_id $datasetId contract $contract format $format storage_kind $storageKind media_type $mediaType path $target sha256 $sha]
}

# Author convenience over the same owned-file publication transaction.
proc ::GX::datasetFilePublicationPublishAuto {session moduleId request} {
    if {[catch {dict size $request}]} {error "publish_auto requires a request dictionary"}
    foreach field {dataset_id source_file contract} {
        if {![dict exists $request $field] || [string trim [dict get $request $field]] eq ""} {error "publish_auto requires $field"}
    }
    set ext [string tolower [string trimleft [file extension [dict get $request source_file]] .]]
    set formatId [datasetFilePublicationDictDefault $request format_id ""]
    set matching {}
    if {$formatId ne ""} {
        if {$formatId ni [acquisitionFormatRegistryIds]} {error "Unknown acquisition format_id $formatId"}
        set matching [list $formatId]
    } else {
        foreach id [acquisitionFormatRegistryIds] {
            # Generic binary catch-all records match every extension. They do
            # not establish a scientific file format or MIME identity.
            if {[acquisitionFormatField $id canonical_formats ""] eq "binary" &&
                [acquisitionFormatField $id mime ""] eq "application/octet-stream"} {continue}
            foreach pattern [split [acquisitionFormatField $id extensions ""] ";"] {
                if {$pattern ne "" && [string match -nocase $pattern "file.$ext"]} {lappend matching $id;break}
            }
        }
    }
    set format [datasetFilePublicationDictDefault $request format ""]
    set mime [datasetFilePublicationDictDefault $request media_type ""]
    if {$format eq ""} {
        if {[llength $matching] == 1} {
            set formats [split [acquisitionFormatField [lindex $matching 0] canonical_formats ""] ";"]
            if {[llength $formats] == 1 && [lindex $formats 0] ni {"" binary text}} {set format [lindex $formats 0]}
        }
        if {$format eq "" && $ext ne ""} {set format $ext}
        if {$format eq ""} {error "Specify format for this file"}
    }
    if {$mime eq "" && [llength $matching] == 1} {
        set mime [acquisitionFormatField [lindex $matching 0] mime ""]
    }
    if {$mime eq "" || $mime eq "application/octet-stream"} {
        # Small standards fallback for formats whose acquisition plugin does
        # not currently declare a formal format record.
        set common [dict create png image/png jpg image/jpeg jpeg image/jpeg tif image/tiff tiff image/tiff wav audio/wav wave audio/wav pdf application/pdf]
        if {[dict exists $common $ext]} {set mime [dict get $common $ext]}
    }
    if {$mime eq "" || $mime eq "application/octet-stream"} {error "Specify media_type for this format"}
    set storage [datasetFilePublicationDictDefault $request storage_kind ""]
    if {$storage eq ""} {set storage [expr {[string match "text/*" $mime] ? "text" : "binary"}]}
    dict set request format $format
    dict set request media_type $mime
    dict set request storage_kind $storage
    if {[dict exists $request format_id]} {dict unset request format_id}
    return [datasetFilePublicationPublish $session $moduleId $request]
}

# A producer may hand one current file Dataset revision to one editor. The grant
# is stored on that Dataset, is revision-bound, and never grants namespace access.
proc ::GX::datasetFileEditAuthorize {capability session datasetId editor} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetFileEditAuthorize $capability $session $datasetId $editor]}
    set owner [_parameterOwner $capability]
    loadDatasetRegistry $session
    # Ownership, not the current user-assigned namespace, permits this exact
    # revision handoff. It does not authorize any ordinary namespace write.
    if {[datasetField $datasetId source_module {}] ne $owner || [datasetField $datasetId contract {}] ni {geometry.sketch document.pdf document.text}} {error {Only the file Dataset producer may authorize editing}}
    datasetPublicationV2ValidateId module $editor
    set grant [dict create dataset_id $datasetId session [file normalize $session] editor $editor owner $owner sha256 [datasetField $datasetId sha256 [datasetField $datasetId canonical_sha256 {}]] contract [datasetField $datasetId contract {}]]
    _datasetFrameworkMetadataUpdate $session $datasetId [dict create file_edit_grant $grant]
    return [dict create dataset_id $datasetId editor $editor revision [dict get $grant sha256]]
}
proc ::GX::_datasetFileEditGrant {session datasetId editor contract} {
    set private [datasetPrivateMetadataRead $session $datasetId]
    if {![dict exists $private _gxtxt.framework.file_edit_grant]} {return 0}
    set grant [dict get $private _gxtxt.framework.file_edit_grant]
    if {![dict exists $grant dataset_id] || ![dict exists $grant session] || [dict get $grant dataset_id] ne $datasetId || [dict get $grant session] ne [file normalize $session]} {return 0}
    expr {[dict get $grant editor] eq $editor && [dict get $grant owner] eq [datasetField $datasetId source_module {}] && [dict get $grant sha256] eq [datasetField $datasetId sha256 [datasetField $datasetId canonical_sha256 {}]] && [dict get $grant contract] eq $contract}
}

# Trusted source-reference branch of this same publication/transaction owner.
proc ::GX::_datasetFilePublicationReference {session moduleId request} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetFilePublicationReference $session $moduleId $request]}
    set id [dict get $request dataset_id]
    if {[datasetField $id id {}] ne {}||[datasetPublicationV2DictDefault $request replace_owned 0]} {error {Verified external references are CREATE-only}}
    set namespace [_datasetPublicationNamespace $session $moduleId $request]
    set source [dict get $request verified_reference]
    set verification [expr {[dict get $request storage_kind] eq {text}?{text}:{read}}]
    set current [_scientificIoCall [dict get $source source_root] $verification [dict get $source source_relative] 0 1 [dict get $source sha256]]
    if {[dict get $current identity] ne [dict get $source identity]} {error {External source changed during publication}}
    set metadataPath [file join $session [_datasetMetadataRelativePath $id]]
    datasetAuthorityEnlist [datasetRegistryPath $session]
    datasetAuthorityEnlist $metadataPath
    set fields [datasetFilePublicationRegistryFields $moduleId $request [dict get $request source_file] [dict get $source sha256] [dict get $request storage_kind] {}]
    lappend fields immutable 1 source_storage_policy reference source_raw [dict get $request source_file] source_sha256 [dict get $source sha256] external_source_root [dict get $source source_root] external_source_relative [dict get $source source_relative]
    datasetFilePublicationCommitRegistry $session $id $fields
    _datasetFrameworkMetadataUpdate $session $id [dict create dataset_namespace $namespace]
    return [dict create dataset_id $id contract [dict get $request contract] format [dict get $request format] sha256 [dict get $source sha256] policy reference readonly 1]
}
