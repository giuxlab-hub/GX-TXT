# SPDX-License-Identifier: GPL-3.0-or-later
# Source notes are associations on existing canonical document Datasets.
# Their local drafts belong to the existing Registry/Project attachment owner.
namespace eval ::GX::SourceNotes {}
proc ::GX::sourceNoteApiInfo {} {
    return [dict create api_id SOURCE_NOTE_API_v1 api_version 1 operations {association source} host_request_operations {describe read write snapshot} \
        host_operations {sourceNoteRead sourceNoteWrite sourceNoteSnapshot sourceNoteAssetRead sourceNoteAssociation sourceNoteSource sourceNoteOpen} \
        source_owners {python_script octave_script cpp_viewer_project} project_source_languages {cpp python} \
        persistence {canonical Dataset in applicable Session; explicit local draft or portable source snapshot otherwise} implicit_publication 0]
}
proc ::GX::_sourceNoteSessionToken {} {
    if {$::GX::currentSession eq {}} {return {}}
    return [interactiveDocumentSessionToken]
}
proc ::GX::_sourceNoteReference {sourceRef} {
    if {[catch {dict size $sourceRef}] || [lsort [dict keys $sourceRef]] ne {owner reference}} {error {Source reference requires its fixed owner and inert reference dictionary}}
    set owner [dict get $sourceRef owner]
    if {$owner ni {python_script octave_script cpp_viewer_project}} {error {Unknown source note owner}}
    set reference [dict get $sourceRef reference]
    if {[catch {dict size $reference}] || [string bytelength $reference]>16384} {error {Source reference exceeds its bound}}
    foreach key [dict keys $reference] {if {$key ni {reference relative owner_key file_key project_key expected_source_sha256}} {error {Unknown source reference field}}}
    if {![dict exists $reference relative]} {error {Source reference requires its declared relative filename}}
    return $sourceRef
}
proc ::GX::_sourceNoteOwner {operation sourceRef {request {}}} {
    _sourceNoteReference $sourceRef
    set owner [dict get $sourceRef owner]
    set command [expr {$owner eq {cpp_viewer_project} ? {::GX::ViewerDevelopmentWorkspace::sourceNoteOwner} : {::GX::scriptSourceNoteOwner}}]
    if {![llength [info commands $command]]} {error {The original source owner is not currently available}}
    set result [$command $operation [dict get $sourceRef reference] $request]
    if {$operation eq {asset_read}} {return $result}
    foreach key {owner created owner_key file_key relative language source_sha256 source_revision authoring_revision owner_revision text source reference} {if {![dict exists $result $key]} {error "Source owner omitted its $key receipt"}}
    if {[dict get $result owner] ne $owner} {error {Source owner identity changed}}
    set expected [datasetPublicationV2DictDefault [dict get $sourceRef reference] expected_source_sha256 {}]
    if {$expected ne {} && $expected ne [dict get $result source_sha256]} {error {Requested source snapshot changed; the note was not retargeted}}
    return $result
}
proc ::GX::_sourceNoteActor {capability sourceRef} {
    set actor [_documentActor $capability]
    set expected [dict get {python_script analysis.python_script octave_script analysis.octave_script cpp_viewer_project viewer.development_workspace} [dict get [_sourceNoteReference $sourceRef] owner]]
    if {$actor ne $expected} {error {Only the actual source editor owner may attach or save its source note}}
    return $actor
}
proc ::GX::_sourceNoteFind {source} {
    if {$::GX::currentSession eq {} || [dict get $source owner_key] eq {} || [dict get $source file_key] eq {}} {return {}}
    set found {}
    foreach id [datasetRegistryIds] {
        if {[datasetField $id contract {}] ne {document.text}} continue
        set metadata [datasetPrivateMetadataRead $::GX::currentSession $id]
        if {![dict exists $metadata _gxtxt.framework.source_note_v1]} continue
        set association [dict get $metadata _gxtxt.framework.source_note_v1]
        if {[catch {_sourceNoteAssociationValidate $association}]} continue
        if {[dict get $association owner] eq [dict get $source owner] && [dict get $association owner_key] eq [dict get $source owner_key] && [dict get $association file_key] eq [dict get $source file_key]} {lappend found $id}
    }
    if {[llength $found]>1} {error {Multiple canonical notes claim this exact source; choose and review the conflicting Datasets}}
    return [lindex $found 0]
}
proc ::GX::sourceNoteRead {capability sourceRef} {
    _documentActor $capability
    if {$::GX::currentSession ne {} && ![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::sourceNoteRead $capability $sourceRef]}
    _sourceNoteReference $sourceRef
    set source [_sourceNoteOwner read_local $sourceRef]
    set reference [dict get $sourceRef reference]
    dict set reference relative [dict get $source relative]
    foreach key {owner_key file_key} {if {[dict get $source $key] ne {}} {dict set reference $key [dict get $source $key]}}
    dict set sourceRef reference $reference
    set id [_sourceNoteFind $source]
    set session [_sourceNoteSessionToken]
    set result [dict create state [expr {[dict get $source created] ? ($session eq {} ? {local_draft} : {pending_session_attachment}) : {uncreated}}] \
        text [dict get $source text] assets {} dataset_id {} session $session revision {} sha256 {} source $source source_ref $sourceRef metadata {} association {state unassociated}]
    if {$id ne {}} {
        set description [datasetDocumentDescribe $id [dict create capability $capability]]
        set read [datasetDocumentRead $id 4194304]
        if {![dict get $read complete] || [datasetRevisionToken $id] ne [dict get $description revision]} {error {Canonical source note changed during reading}}
        foreach key {assets revision sha256 metadata association can_replace} {dict set result $key [dict get $description $key]}
        dict set result text [dict get $read source];dict set result dataset_id $id;dict set result state canonical
    }
    return $result
}
proc ::GX::_sourceNoteWriteCheck {capability sourceRef request} {
    _sourceNoteActor $capability $sourceRef
    foreach key {expected_session expected_owner_revision expected_authoring_revision expected_source_sha256} {if {![dict exists $request $key]} {error "Source note save requires $key"}}
    if {[dict get $request expected_session] ne [_sourceNoteSessionToken]} {error {Source note belongs to a changed Session; draft retained}}
    set source [_sourceNoteOwner describe $sourceRef]
    foreach {field expected} {owner_revision expected_owner_revision authoring_revision expected_authoring_revision source_sha256 expected_source_sha256} {
        if {[dict get $source $field] ne [dict get $request $expected]} {error {Source or note attachment changed; reopen before saving, draft retained}}
    }
    return $source
}
proc ::GX::sourceNoteWrite {capability sourceRef request} {
    foreach key [dict keys $request] {if {$key ni {text assets expected_session expected_revision expected_sha256 expected_owner_revision expected_authoring_revision expected_source_sha256 dataset_id}} {error {Unknown source note save field}}}
    if {![dict exists $request text]} {error {Source note save requires its exact Markdown text}}
    set source [_sourceNoteWriteCheck $capability $sourceRef $request]
    set ownerRequest [dict create expected_owner_revision [dict get $source owner_revision] expected_authoring_revision [dict get $source authoring_revision]]
    if {$::GX::currentSession eq {}} {
        if {[dict size [datasetPublicationV2DictDefault $request assets {}]]} {error {Managed images require an applicable Session; local Markdown draft retained}}
        dict set ownerRequest text [dict get $request text]
        _sourceNoteOwner write_local $sourceRef $ownerRequest
        return [sourceNoteRead $capability $sourceRef]
    }
    set materialized [dict create assets {} owner {}]
    try {
        # A pending source-project snapshot has no canonical resource owner.
        # Adopt its verified PNG closure only on this explicit Session Save.
        # Existing canonical saves retain the normal explicit-empty removal.
        if {[_sourceNoteFind $source] eq {} && [dict size [datasetPublicationV2DictDefault $source asset_snapshots {}]]} {
            set materialized [sourceNoteAssetsMaterialize $capability $sourceRef $source [dict get $request expected_session]]
            dict set request assets [dict merge [dict get $materialized assets] [datasetPublicationV2DictDefault $request assets {}]]
        }
        set source [_sourceNoteOwner ensure_identity $sourceRef $ownerRequest]
        return [datasetAuthorityTransaction $::GX::currentSession ::GX::_sourceNoteCanonicalWrite $capability $sourceRef $source $request]
    } finally {
        if {[dict get $materialized owner] ne {}} {datasetDocumentAssetOwnerClose $capability [dict get $materialized owner]}
    }
}
proc ::GX::_sourceNoteCanonicalWrite {capability sourceRef source request} {
    _documentSessionCheck [dict get $request expected_session]
    set current [_sourceNoteOwner describe $sourceRef]
    foreach key {owner_key file_key source_sha256 source_revision owner_revision authoring_revision} {if {[dict get $current $key] ne [dict get $source $key]} {error {Source changed before canonical note publication}}}
    set id [_sourceNoteFind $source]
    set save [dict create text [dict get $request text] expected_session [dict get $request expected_session]]
    if {$id ne {}} {
        foreach key {expected_revision expected_sha256} {if {![dict exists $request $key] || [dict get $request $key] eq {}} {error {A canonical note now exists; reopen it before replacing this draft}};dict set save $key [dict get $request $key]}
        if {[dict exists $request dataset_id] && [dict get $request dataset_id] ne $id} {error {Source note Save cannot retarget its canonical Dataset}}
        dict set save mode replace_existing
    } else {
        if {[datasetPublicationV2DictDefault $request expected_revision {}] ne {}} {error {Original canonical note is unavailable; explicitly review a new attachment}}
        set id [datasetPublicationV2DictDefault $request dataset_id note_[dict get $source owner_key]_[dict get $source file_key]]
        datasetPublicationV2ValidateId dataset $id
        dict set save mode new
    }
    dict set save dataset_id $id
    if {[dict exists $request assets]} {dict set save assets [dict get $request assets]}
    set association [dict create schema gxtxt.source_note.v1]
    foreach key {owner owner_key file_key relative language source_sha256 source_revision reference} {dict set association $key [dict get $source $key]}
    foreach key {project_id project_name} {if {[dict exists $source $key]} {dict set association $key [dict get $source $key]}}
    _sourceNoteAssociationValidate $association
    datasetDocumentWrite $capability $save
    _datasetFrameworkMetadataUpdate $::GX::currentSession $id [dict create source_note_v1 $association]
    return [sourceNoteRead $capability $sourceRef]
}
proc ::GX::sourceNoteSnapshot {capability sourceRef request} {
    set source [_sourceNoteWriteCheck $capability $sourceRef $request]
    set note [sourceNoteRead $capability $sourceRef]
    if {[dict get $note state] ne {canonical}} {return $note}
    foreach {field expected} {revision expected_revision sha256 expected_sha256} {
        if {![dict exists $request $expected] || [dict get $request $expected] ne [dict get $note $field]} {error {Canonical note changed before the reviewed portable snapshot}}
    }
    set ownerRequest [dict create text [dict get $note text] expected_owner_revision [dict get $source owner_revision] expected_authoring_revision [dict get $source authoring_revision]]
    set plan {}
    try {
        if {[dict size [dict get $note assets]] || [dict size [datasetPublicationV2DictDefault $source asset_snapshots {}]]} {
            set plan [sourceNoteAssetPlanBuild $source $sourceRef [dict get $note assets]]
            dict set ownerRequest asset_plan $plan
        }
        set saved [_sourceNoteOwner write_local $sourceRef $ownerRequest]
    } finally {if {$plan ne {}} {sourceNoteAssetPlanClose $plan}}
    dict set note source $saved;dict set note portable_snapshot 1;dict set note assets_present [expr {[dict size [dict get $note assets]]>0}]
    return $note
}
proc ::GX::sourceNoteRequest {capability operation request} {
    set sourceRef [dict get $request source_ref]
    switch -- $operation {
        describe - read {return [sourceNoteRead $capability $sourceRef]}
        write {return [sourceNoteWrite $capability $sourceRef [dict remove $request source_ref]]}
        snapshot {return [sourceNoteSnapshot $capability $sourceRef [dict remove $request source_ref]]}
        default {error {Unknown source note operation}}
    }
}
proc ::GX::sourceNoteAssetRead {capability sourceRef request} {
    _sourceNoteActor $capability $sourceRef
    set required {name start count expected_owner_revision expected_authoring_revision expected_asset_sha256}
    if {[catch {dict size $request}] || [lsort [dict keys $request]] ne [lsort $required]} {error {Source image read requires its exact bounded owner revision request}}
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} [dict get $request name]]} {error {Invalid logical source image name}}
    foreach key {expected_authoring_revision expected_asset_sha256} {if {![regexp {^[a-f0-9]{64}$} [dict get $request $key]]} {error {Source image read requires the exact attachment and asset SHA}}}
    set start [dict get $request start];set count [dict get $request count]
    if {![string is entier -strict $start] || $start<0 || $start>4194304 || ![string is entier -strict $count] || $count<1 || $count>1048576} {error {Source image reads are bounded to1MiB per chunk}}
    set result [_sourceNoteOwner asset_read $sourceRef $request]
    if {[catch {dict size $result}] || [lsort [dict keys $result]] ne {bytes_base64 count eof offset sha256 size_bytes}} {error {Source image owner returned an invalid chunk receipt}}
    foreach key {offset count size_bytes} {if {![string is entier -strict [dict get $result $key]]} {error {Source image owner returned non-integer bounds}}}
    set size [dict get $result size_bytes];set actual [dict get $result count]
    if {$size<24 || $size>4194304 || $actual<0 || $actual>$count || [dict get $result offset]!=$start || $start+$actual>$size || [dict get $result sha256] ne [dict get $request expected_asset_sha256]} {error {Source image chunk identity or bounds changed}}
    if {![string is boolean -strict [dict get $result eof]] || [dict get $result eof]!=($start+$actual==$size) || (!$actual && ![dict get $result eof])} {error {Source image owner returned an inconsistent end-of-file receipt}}
    set encoded [dict get $result bytes_base64]
    if {[string length $encoded]>1398104 || ![regexp {^[A-Za-z0-9+/]*={0,2}$} $encoded] || [string length [binary decode base64 $encoded]]!=$actual} {error {Source image owner returned invalid bounded bytes}}
    return $result
}
proc ::GX::_sourceNoteAssociatedReference {association} {
    set reference [dict create relative [dict get $association relative] owner_key [dict get $association owner_key] file_key [dict get $association file_key]]
    dict set reference reference [dict get $association reference]
    return [dict create owner [dict get $association owner] reference $reference]
}
proc ::GX::sourceNoteSource {datasetId} {
    set metadata [datasetPrivateMetadataRead [_interactiveDocumentRequireSession] $datasetId]
    if {![dict exists $metadata _gxtxt.framework.source_note_v1]} {return [dict create state unassociated diagnostic {This document has no associated source.} source {}]}
    set association [dict get $metadata _gxtxt.framework.source_note_v1]
    if {[catch {_sourceNoteAssociationValidate $association} reason]} {return [dict create state invalid diagnostic "Invalid source association: $reason" source {}]}
    set result [dict create state unavailable diagnostic {The original source owner is unavailable.} source {} \
        owner [dict get $association owner] relative [dict get $association relative] language [dict get $association language]]
    foreach key {project_id project_name} {dict set result $key [datasetPublicationV2DictDefault $association $key {}]}
    if {[catch {set current [_sourceNoteOwner describe [_sourceNoteAssociatedReference $association]]} reason]} {
        dict set result diagnostic "Associated source is missing or unavailable: $reason"
        return $result
    }
    if {[dict get $current source_sha256] ne [dict get $association source_sha256] || [dict get $current source_revision] ne [dict get $association source_revision]} {
        dict set result state revised;dict set result diagnostic {The source revision changed. The note remains readable; its original code snapshot is not silently replaced.}
    } elseif {[dict get $current relative] ne [dict get $association relative]} {
        dict set result state renamed;dict set result diagnostic "The same source identity was renamed to [dict get $current relative]. Reopen its Notes tab to review the association."
    } else {
        set code [dict get $current source]
        if {[string length [encoding convertto utf-8 $code]]>4194304 || [string first \x00 $code]>=0} {dict set result diagnostic {Associated source exceeds the bounded UTF-8 consultation contract.};return $result}
        dict set result state current;dict set result diagnostic {Exact current source identity and revision verified.};dict set result source $code
    }
    return $result
}
proc ::GX::sourceNoteAssociation {datasetId} {
    set metadata [datasetPrivateMetadataRead [_interactiveDocumentRequireSession] $datasetId]
    if {![dict exists $metadata _gxtxt.framework.source_note_v1]} {return {state unassociated}}
    set association [dict get $metadata _gxtxt.framework.source_note_v1]
    if {[catch {_sourceNoteAssociationValidate $association} reason]} {return [dict create state unassociated source_state invalid diagnostic $reason]}
    set source [sourceNoteSource $datasetId]
    set result [dict create state associated source_state [dict get $source state] diagnostic [dict get $source diagnostic] \
        source_filename [dict get $association relative] language [dict get $association language] owner [dict get $association owner] \
        source_sha256 [dict get $association source_sha256] source_ref [_sourceNoteAssociatedReference $association]]
    foreach key {project_id project_name source_label} {dict set result $key [datasetPublicationV2DictDefault $association $key {}]}
    return $result
}
proc ::GX::sourceNoteOpen {datasetId {resolution {}}} {
    set association [sourceNoteAssociation $datasetId]
    if {$resolution eq {}} {set resolution [contractVisualizerResolve [datasetField $datasetId contract {}] open $datasetId]}
    if {[dict get $resolution status] ne {selected} || ![dict exists $resolution dataset_reference]} {error {No admitted Markdown editor is available for this Dataset}}
    set reference [_datasetViewerReferenceValidate [dict get $resolution dataset_reference]]
    if {[dict get $reference dataset_id] ne $datasetId || [contractVisualizerResolve [datasetField $datasetId contract {}] open $datasetId] ne $resolution} {error {Source-note editor selection changed before dispatch}}
    if {[dict get $resolution dataset_revision] ne [datasetRevisionToken $datasetId]} {error {Source note changed before editor dispatch}}
    if {[dict get $association state] eq {associated} && [llength [info commands ::GX::sourceNoteSourceUiOpen]]} {
        set actor [dict get {python_script analysis.python_script octave_script analysis.octave_script cpp_viewer_project viewer.development_workspace} [dict get $association owner]]
        # CORE dispatches to the actual registered source owner, just as the
        # Viewer owner dispatches to its target module. No caller capability or
        # foreign producer grant is reused by the source editor.
        if {![catch {_datasetPrivateWithModule $actor [list ::GX::sourceNoteSourceUiOpen [dict get $association source_ref]]} opened]} {return $opened}
    }
    return [viewerOpen [dict get $resolution module_id] [dict get $resolution viewer_id] [dict create dataset_id $datasetId dataset_reference [dict get $resolution dataset_reference] open_role contract_visualizer]]
}
proc ::GX::_sourceNoteAssociationValidate {association} {
    set required {schema owner owner_key file_key relative language source_sha256 source_revision reference}
    if {[catch {dict size $association}] || [string bytelength $association]>16384} {error {Invalid bounded source-note association}}
    foreach key $required {if {![dict exists $association $key]} {error "Source-note association lacks $key"}}
    foreach key [dict keys $association] {if {$key ni [concat $required {source_label project_id project_name}]} {error {Unknown source-note association field}}}
    if {[dict get $association schema] ne {gxtxt.source_note.v1}} {error {Unknown source-note association schema}}
    set owner [dict get $association owner]
    # cpp_viewer_project is the historical stable Development Workspace owner
    # identity, including genuine Acquisition projects. Registered Python
    # helpers retain their actual language; no Script Registry owner is forged.
    set languages {python_script python octave_script octave cpp_viewer_project {cpp python}}
    set language [dict get $association language]
    if {![dict exists $languages $owner] || $language ni [dict get $languages $owner]} {error {Invalid source-note owner/language}}
    foreach key {owner_key file_key} {if {![regexp {^[a-f0-9]{32}$} [dict get $association $key]]} {error {Invalid stable source-note identity}}}
    foreach key {source_sha256 source_revision} {if {![regexp {^[a-f0-9]{64}$} [dict get $association $key]]} {error {Invalid source-note revision/SHA}}}
    set relative [dict get $association relative]
    if {[string length $relative]>240 || ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*(/[A-Za-z_][A-Za-z0-9_.-]*)*$} $relative]} {error {Invalid portable source-note relative path}}
    set extension [file extension $relative]
    if {($owner eq {python_script} && $extension ne {.py}) || ($owner eq {octave_script} && $extension ne {.m}) || ($owner eq {cpp_viewer_project} && (($language eq {cpp} && $extension ni {.c .cc .cpp .cxx .h .hh .hpp .hxx}) || ($language eq {python} && ($extension ne {.py} || ![string match helpers/* $relative]))))} {error {Source-note filename does not match its language/registered project role}}
    set reference [dict get $association reference]
    if {$owner eq {cpp_viewer_project}} {
        if {$reference ne "project:[dict get $association owner_key]"} {error {C++ note reference does not match its project key}}
    } elseif {![regexp {^(user|session):[A-Za-z][A-Za-z0-9_.-]*$} $reference]} {error {Invalid qualified Script Registry note reference}}
    foreach key {source_label project_id project_name} {
        if {[dict exists $association $key] && ([string length [dict get $association $key]]>512 || [regexp {[\x00-\x1f]} [dict get $association $key]])} {error {Source-note label must be bounded inert single-line text}}
    }
    return $association
}

# Generic portable copy/import NEVER creates a primary live source attachment.
# Keep its inert origin separately; only the exact source owner can reassociate.
proc ::GX::sourceNotePortableMetadata {metadata sourceDatasetId newDatasetId} {
    datasetPublicationV2ValidateId dataset $sourceDatasetId
    datasetPublicationV2ValidateId dataset $newDatasetId
    # Every producer grant is scoped to the original Dataset/revision. Generic
    # copies must never retain it, including ordinary unassociated documents.
    catch {dict unset metadata _gxtxt.framework.file_edit_grant}
    set primary _gxtxt.framework.source_note_v1
    set originKey _gxtxt.framework.source_note_origin_v1
    if {[dict exists $metadata $primary]} {
        set association [dict get $metadata $primary]
        _sourceNoteAssociationValidate $association
        dict set metadata $originKey [dict create schema gxtxt.source_note_lineage.v1 \
            source_dataset_id $sourceDatasetId received_dataset_id $newDatasetId source_association $association]
        dict unset metadata $primary
    } elseif {[dict exists $metadata $originKey]} {
        set origin [dict get $metadata $originKey]
        if {[catch {dict size $origin}] || [lsort [dict keys $origin]] ne {received_dataset_id schema source_association source_dataset_id} || [string bytelength $origin]>32768 || [datasetPublicationV2DictDefault $origin schema {}] ne {gxtxt.source_note_lineage.v1}} {error {Invalid source-note origin lineage}}
        _sourceNoteAssociationValidate [dict get $origin source_association]
        foreach key {received_dataset_id source_dataset_id} {datasetPublicationV2ValidateId dataset [dict get $origin $key]}
        dict set origin received_dataset_id $newDatasetId
        dict set metadata $originKey $origin
    }
    return $metadata
}
source [file join [file dirname [info script]] source_note_assets_v1.tcl]
