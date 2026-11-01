# SPDX-License-Identifier: GPL-3.0-or-later
# Subordinate of document_source_api_v1. Dataset/File Publication and managed
# resources retain all persistence, transaction, permission and blob ownership.
namespace eval ::GX::DocumentSource {variable editors {};variable editorSerial 0}
proc ::GX::documentSourceApiInfo {} {
    return [dict create api_id DOCUMENT_SOURCE_API_v1 api_version 1 operations {describe read write} \
        host_operations {documentEditorMount documentEditorCommand markupRenderStringToWidget markdownNavigationContext markupNavigationInspect markupNavigationFollow} text_bytes_max 4194304 \
        contract document.text media_type text/markdown renderer GX-Markup editor shared \
        replacement_policy {same producer or explicit revision-bound producer grant}]
}
proc ::GX::_documentSessionCheck {expected} {
    set session [_interactiveDocumentRequireSession]
    if {$expected eq {} || $expected ne [interactiveDocumentSessionToken]} {error {Document Session changed; reopen before continuing}}
    return $session
}
proc ::GX::_documentActor {capability} {
    set actor [_parameterOwner $capability]
    if {$::GX::DatasetPrivate::activeContext ne {} && [dict get $::GX::DatasetPrivate::activeContext module_id] ne $actor} {error {Document capability does not match the active module}}
    return $actor
}
proc ::GX::_documentCanReplace {id actor} {
    set contract [datasetField $id contract {}]
    if {$contract ni {document.text document.uml} || [string is true -strict [datasetField $id immutable 0]]} {return 0}
    expr {([datasetField $id source_module {}] eq $actor && [datasetField $id dataset_file_publication_api_version {}] eq {1}) || [_datasetFileEditGrant $::GX::currentSession $id $actor $contract]}
}
proc ::GX::datasetDocumentDescribe {id {options {}}} {
    set session [_interactiveDocumentRequireSession]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetDocumentDescribe $id $options]}
    if {[dict exists $options expected_session]} {_documentSessionCheck [dict get $options expected_session]}
    set contract [datasetField $id contract {}]
    if {$contract ni {document.text document.uml}} {error {Choose a canonical text or UML document Dataset}}
    set actor {};if {[dict exists $options capability] && [dict get $options capability] ne {}} {set actor [_documentActor [dict get $options capability]]}
    set revision [datasetRevisionToken $id $session]
    set payload [sessionInspectionDatasetPayload $id]
    set private [datasetPrivateMetadataRead $session $id]
    set assets [datasetPublicationV2DictDefault $private _gxtxt.framework.document_assets_v1 {}]
    set association [dict create state unassociated]
    if {$contract eq {document.text} && [llength [info commands ::GX::sourceNoteAssociation]]} {set association [sourceNoteAssociation $id]}
    return [dict create dataset_id $id kind [datasetDocumentKind $id] contract $contract \
        format [datasetField $id format {}] media_type [datasetField $id media_type {}] \
        producer [datasetField $id source_module {}] immutable [datasetField $id immutable 0] \
        sha256 [dict get $payload sha256] revision $revision session [interactiveDocumentSessionToken] \
        metadata [datasetMetadataRead $session $id] assets $assets association $association \
        can_replace [expr {$actor ne {} && [_documentCanReplace $id $actor]}]]
}
proc ::GX::_documentAssetsValidate {assets} {
    if {[catch {dict size $assets} n] || $n>32} {error {Document assets require at most32 named managed resources}}
    set total 0
    dict for {name reference} $assets {
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} $name]} {error {Invalid logical document asset name}}
        set info [interactiveDocumentResourceInfo $reference]
        set count [dict get $info size_bytes];incr total $count
        if {$count>4194304 || $total>16777216} {error {Document images exceed managed resource bounds}}
    }
    return $assets
}
proc ::GX::_datasetDocumentAssetOwnerCreate {actor purpose origin} {
    if {[catch {dict size $origin}] || [string bytelength $origin]>4096} {error {Asset origin must be a bounded inert dictionary}}
    set created [interactiveDocumentCreate $actor markdown_assets gxtxt.markdown_assets.v1 1 \
        [dict create schema gxtxt.markdown_assets.v1 purpose $purpose origin $origin assets {}]]
    return [dict create schema gxtxt.markdown_asset_owner.v1 document_id [dict get $created id] \
        owner_generation [dict get $created generation] session [interactiveDocumentSessionToken] module_id $actor]
}
proc ::GX::datasetDocumentAssetOwnerCreate {capability {origin {}}} {
    return [_datasetDocumentAssetOwnerCreate [_documentActor $capability] editor $origin]
}
proc ::GX::_datasetDocumentAssetOwnerCreateForImport {origin} {
    if {[catch {dict size $origin}] || [lsort [dict keys $origin]] ne {destination_dataset_id operation source_dataset_id}
        || [dict get $origin operation] ne {portable_dataset_import}} {error {Expected an explicit portable Dataset import origin}}
    foreach key {source_dataset_id destination_dataset_id} {datasetPublicationV2ValidateId dataset [dict get $origin $key]}
    return [_datasetDocumentAssetOwnerCreate core.document_source portable_import $origin]
}
proc ::GX::_datasetDocumentAssetOwnerValidate {actor owner {allowRetired 0}} {
    if {[catch {dict size $owner}] || [lsort [dict keys $owner]] ne {document_id module_id owner_generation schema session}
        || [dict get $owner schema] ne {gxtxt.markdown_asset_owner.v1} || [dict get $owner module_id] ne $actor} {error {Invalid document asset owner receipt}}
    _documentSessionCheck [dict get $owner session]
    set id [dict get $owner document_id]
    if {![interactiveDocumentIdValid $id]} {error {Invalid document asset owner identity}}
    if {[interactiveDocumentExists $id]} {
        set actual [interactiveDocumentMetadata $id]
        foreach {key expected} [list module_id $actor provider_id markdown_assets format gxtxt.markdown_assets.v1 generation [dict get $owner owner_generation]] {
            if {[dict get $actual $key] ne $expected} {error {Document asset owner identity/generation changed}}
        }
        return active
    }
    if {!$allowRetired} {error {Document asset owner is no longer active}}
    if {![catch {set generation [_documentResourceOwnerGeneration $id]} reason options]} {
        if {$generation ne [dict get $owner owner_generation]} {error {Retired document asset owner generation changed}}
        return retired
    }
    if {$reason ne {Document resource owner does not exist}} {return -options $options $reason}
    return closed
}
proc ::GX::datasetDocumentAssetOwnerValidate {capability owner} {
    return [_datasetDocumentAssetOwnerValidate [_documentActor $capability] $owner]
}
proc ::GX::_datasetDocumentAssetOwnerClose {actor owner} {
    set state [_datasetDocumentAssetOwnerValidate $actor $owner 1]
    set id [dict get $owner document_id]
    if {$state eq {active}} {interactiveDocumentDelete $id;return [dict create status closed document_id $id]}
    if {$state eq {retired}} {return [dict merge [dict create status retired document_id $id] [interactiveDocumentResourceCollect $id]]}
    return [dict create status already_closed document_id $id]
}
proc ::GX::datasetDocumentAssetOwnerClose {capability owner} {
    return [_datasetDocumentAssetOwnerClose [_documentActor $capability] $owner]
}
proc ::GX::_datasetDocumentAssetOwnerCloseForImport {owner} {
    return [_datasetDocumentAssetOwnerClose core.document_source $owner]
}
# A live editor can retain captured immutable references while their original
# carrier retires. This is an ordinary existing resource-owner payload, with no
# Markdown body, byte copy, serialized capability or new retention registry.
proc ::GX::datasetDocumentAssetOwnerRetain {capability assets {owner {}}} {
    if {$owner eq {} && $assets eq {}} {return {}}
    set actor [_documentActor $capability]
    if {[catch {dict size $assets} count] || $count>64} {error {Editor retention is bounded to64 draft/baseline image references}}
    set total 0
    dict for {key reference} $assets {
        set checked [interactiveDocumentResourceInfo $reference]
        set bytes [dict get $checked size_bytes];incr total $bytes
        if {$bytes>4194304 || $total>33554432} {error {Editor retention exceeds its two-snapshot image budget}}
    }
    if {$owner eq {} && $assets eq {}} {return {}}
    set created [expr {$owner eq {}}]
    if {$created} {set owner [datasetDocumentAssetOwnerCreate $capability {operation document_draft_retain}]}
    try {
        _datasetDocumentAssetOwnerValidate $actor $owner
        set document [dict get $owner document_id]
        set payload [dict get [interactiveDocumentRead $document] payload]
        dict set payload retained_assets $assets
        interactiveDocumentUpdate $document $payload
        return $owner
    } on error {message options} {
        if {$created} {catch {datasetDocumentAssetOwnerClose $capability $owner}}
        return -options $options $message
    }
}
proc ::GX::datasetDocumentAssetWrite {capability owner name metadata bytes} {
    _datasetDocumentAssetOwnerValidate [_documentActor $capability] $owner
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} $name] || [string length $bytes]>4194304} {error {Invalid asset name or bytes bound}}
    set document [dict get $owner document_id]
    set payload [dict get [interactiveDocumentRead $document] payload]
    set assets [dict get $payload assets]
    # Check count/aggregate before adding immutable bytes; a failed writer never
    # changes the existing owner payload or any canonical Dataset.
    if {![dict exists $assets $name] && [dict size $assets]>=32} {error {At most32 document assets are allowed}}
    set total [string length $bytes]
    dict for {other reference} $assets {if {$other ne $name} {incr total [dict get [interactiveDocumentResourceInfo $reference] size_bytes]}}
    if {$total>16777216} {error {Document assets exceed16MiB}}
    set resource [managedResourceWrite $document $metadata $bytes]
    dict set assets $name $resource;dict set payload assets $assets
    interactiveDocumentUpdate $document $payload
    return $resource
}
proc ::GX::datasetDocumentWrite {capability request} {
    set session [_documentWriteRequestCheck $capability $request]
    return [datasetAuthorityTransaction $session ::GX::_datasetDocumentWrite $capability $request]
}
proc ::GX::_documentWriteRequestCheck {capability request} {
    if {[catch {dict size $request}]} {error {Document write request must be a dictionary}}
    foreach key [dict keys $request] {
        if {$key ni {mode dataset_id text expected_session expected_revision expected_sha256 source_dataset_id source_revision assets}} {error "Unknown document write field '$key'"}
    }
    foreach key {mode dataset_id text expected_session} {if {![dict exists $request $key]} {error "Document write requires $key"}}
    set session [_documentSessionCheck [dict get $request expected_session]]
    _documentActor $capability
    if {[dict get $request mode] ni {new replace_existing}} {error {Document save mode must be new or replace_existing}}
    set bytes [encoding convertto utf-8 [dict get $request text]]
    if {[string length $bytes]>4194304 || [string first \x00 $bytes]>=0} {error {Document text must be bounded UTF-8 without NUL}}
    documentUtf8Prefix $bytes [string length $bytes]
    return $session
}
proc ::GX::_datasetDocumentWrite {capability request {kind markdown}} {
    if {$kind ni {markdown uml}} {error {Unsupported shared writable document kind}}
    set contract [expr {$kind eq {uml}?{document.uml}:{document.text}}]
    set format [expr {$kind eq {uml}?{puml}:{md}}]
    set media [expr {$kind eq {uml}?{text/vnd.plantuml}:{text/markdown}}]
    set label [expr {$kind eq {uml}?{UML}:{Markdown}}]
    set session [_documentSessionCheck [dict get $request expected_session]]
    set actor [_documentActor $capability];set id [dict get $request dataset_id]
    set mode [dict get $request mode];set exists [expr {[datasetField $id id {}] ne {}}]
    if {$mode eq {new} && $exists} {error {Dataset already exists; choose a new Dataset ID}}
    set metadata [dict create document.language $kind];set assets {}
    if {$kind eq {uml}} {
        set parsed [umlDocumentParse [dict get $request text]]
        if {![dict get $parsed valid]} {error {UML source has diagnostics; canonical document is unchanged and the draft is retained}}
        dict set metadata uml.profile [dict get $parsed profile]
        dict set metadata uml.family [dict get $parsed family]
        dict set metadata uml.parser_version [dict get $parsed parser_version]
        dict set metadata uml.source_sha256 [dict get $parsed source_sha256]
    }
    if {$mode eq {replace_existing}} {
        if {!$exists || [datasetDocumentKind $id] ne $kind || [datasetField $id contract {}] ne $contract} {error "Save Existing requires the same canonical $label Dataset"}
        if {$kind eq {uml}} {
            set declared [datasetPublicationV2DictDefault [datasetMetadataRead $session $id] uml.profile {}]
            if {$declared ne {} && $declared ne {gxtxt.plantuml.v1}} {error {Existing UML profile is unsupported; preserve the original and explicitly Publish New in the supported profile}}
        }
        foreach key {expected_revision expected_sha256} {if {![dict exists $request $key]} {error "Save Existing requires $key"}}
        if {[datasetRevisionToken $id $session] ne [dict get $request expected_revision] || [datasetField $id sha256 [datasetField $id canonical_sha256 {}]] ne [dict get $request expected_sha256]} {error {Document changed; draft retained, reopen or Publish New}}
        if {![_documentCanReplace $id $actor]} {error {Save Existing is not authorized; draft retained, use Publish New or an explicit producer grant}}
        set metadata [dict merge [datasetMetadataRead $session $id] $metadata]
        set assets [datasetPublicationV2DictDefault [datasetPrivateMetadataRead $session $id] _gxtxt.framework.document_assets_v1 {}]
    }
    if {[dict exists $request assets]} {set assets [dict get $request assets]}
    if {$kind eq {uml} && $assets ne {}} {error {This UML profile has no image/include assets; arbitrary attachments are not source authority}}
    _documentAssetsValidate $assets
    set publication [dict create dataset_id $id contract $contract format $format storage_kind text media_type $media \
        structured_metadata $metadata replace_owned [expr {$mode eq {replace_existing}}]]
    if {$mode eq {replace_existing}} {dict set publication expected_sha256 [dict get $request expected_sha256]}
    if {[dict exists $request source_dataset_id] && [dict get $request source_dataset_id] ne {}} {
        set source [dict get $request source_dataset_id]
        if {$mode ne {new} || ![dict exists $request source_revision]} {error {A new document copy requires its source revision}}
        set snapshot [dict get $request source_revision]
        if {[llength $snapshot]!=5 || [lindex $snapshot 0] ne {dataset-revision-v1} || [lindex $snapshot 1] ne $session || [lindex $snapshot 2] ne $source} {error {Copy lineage must identify a source revision in this Session}}
        set sourceRecord [lindex $snapshot 3]
        set sourceSha [datasetPublicationV2DictDefault $sourceRecord $source,sha256 [datasetPublicationV2DictDefault $sourceRecord $source,canonical_sha256 {}]]
        if {![regexp {^[a-f0-9]{64}$} $sourceSha]} {error {Copy lineage requires a valid source snapshot SHA}}
        set same [expr {[datasetRevisionToken $source $session] eq $snapshot}]
        if {$source eq $id} {error {Publish New must use a distinct Dataset ID}}
        dict set publication source_dataset_ids [list $source]
        dict set publication provenance "$label document copy of $source; original preserved"
        dict set metadata document.source_snapshot_sha256 $sourceSha
        dict set metadata document.source_revision_state [expr {$same?{current_verified}:{declared_prior_revision}}]
        dict set publication structured_metadata $metadata
    }
    set allocation [resourceManagementAllocate ${kind}_document_save [dict create category temporary lifetime request retention_seconds 0]]
    try {
        set path [file join [dict get $allocation path] draft.$format]
        set stream [open $path {WRONLY CREAT EXCL}]
        fconfigure $stream -translation binary -encoding binary
        try {puts -nonewline $stream [encoding convertto utf-8 [dict get $request text]]} finally {close $stream}
        dict set publication source_file $path
        datasetFilePublicationPublish $session $actor $publication
        if {$kind eq {markdown}} {_datasetFrameworkMetadataUpdate $session $id [dict create document_assets_v1 $assets]}
        return [datasetDocumentDescribe $id [dict create capability $capability]]
    } finally {documentInteractiveAllocationRelease $allocation}
}
proc ::GX::documentSourceRequest {capability operation request} {
    if {[catch {dict size $request}]} {error {Document request must be a dictionary}}
    switch -- $operation {
        describe {
            if {[datasetPublicationV2DictDefault $request dataset_id {}] eq {}} {
                _interactiveDocumentRequireSession;_documentActor $capability
                return [dict create dataset_id {} kind markdown contract document.text format md media_type text/markdown \
                    session [interactiveDocumentSessionToken] revision {} assets {} metadata {} association {state unassociated} can_create 1 can_replace 0 immutable 0]
            }
            return [datasetDocumentDescribe [dict get $request dataset_id] [dict merge $request [dict create capability $capability]]]
        }
        read {
            set description [datasetDocumentDescribe [dict get $request dataset_id] [dict merge $request [dict create capability $capability]]]
            set read [datasetDocumentRead [dict get $request dataset_id] [datasetPublicationV2DictDefault $request limit 4194304]]
            if {[datasetRevisionToken [dict get $request dataset_id]] ne [dict get $description revision]} {error {Document changed during reading}}
            return [dict merge $description $read]
        }
        write {return [datasetDocumentWrite $capability $request]}
        default {error {Document operation must be describe, read or write}}
    }
}

proc ::GX::_documentEditorPreviewReceiptCommitted {handle id token before after sha} {
    if {$::GX::DatasetPrivate::activeContext ne {} || ![datasetAuthorityActive $::GX::currentSession]} {error {Readonly Preview receipt acknowledgement requires its CORE transaction}}
    if {[catch {set record [_documentEditorRecord $handle]}]} {return 0}
    set options [dict get $record options];set baseline [dict get $record baseline]
    if {[datasetPublicationV2DictDefault $options kind markdown] eq {uml}} {
        return [_umlEditorPreviewReceiptCommitted $handle $id $token $before $after $sha]
    }
    if {[dict get $options mode] ne {read_only} || [datasetPublicationV2DictDefault $options kind markdown] ne {markdown}
        || ![dict exists $baseline dataset_id] || [dict get $baseline dataset_id] ne $id
        || [dict get $record session] ne $token || [dict get $baseline revision] ne $before
        || [dict get $baseline sha256] ne $sha || [datasetRevisionToken $id] ne $after} {return 0}
    set description [datasetDocumentDescribe $id]
    if {[dict get $description session] ne $token || [dict get $description revision] ne $after
        || [dict get $description sha256] ne $sha || [dict get $description assets] ne [dict get $baseline assets]} {return 0}
    set widget [dict get $record preview]
    if {$widget ne {} && [dict exists $::GX::MarkupNavigation::views $widget]} {
        set view [_markupNavigationView $widget];set context [dict get $view context]
        if {![dict exists $context identity] || [dict get $context identity] ne [list $token $before $sha]} {return 0}
        set next [markdownNavigationContext dataset $id [dict get $context options]]
        if {[dict get $next identity] ne [list $token $after $sha]} {return 0}
        # Only the transient authority context changes: preserve text, marks,
        # selection, focus, scroll, images, native worker and mounted pane IDs.
        dict set ::GX::MarkupNavigation::views $widget context $next
    }
    dict set ::GX::DocumentSource::editors $handle baseline $description
    return 1
}
proc ::GX::_documentEditorSessionToken {} {
    if {$::GX::currentSession eq {}} {return {}}
    return [interactiveDocumentSessionToken]
}
proc ::GX::documentEditorMount {parent options} {
    if {[datasetPublicationV2DictDefault $options kind markdown] eq {uml}} {return [umlEditorMount $parent $options]}
    variable ::GX::DocumentSource::editors
    variable ::GX::DocumentSource::editorSerial
    set options [dict merge {mode editable pane rendered initial {} dataset_id {} capability {} assets {} toolbar 0 on_change {} on_command {} asset_provider {}} $options]
    if {[dict get $options mode] ni {editable read_only}} {error {Document mode must be editable or read_only}}
    set handle document-editor#[incr editorSerial]
    set baseline {};set text [dict get $options initial];set assets [dict get $options assets]
    set id [dict get $options dataset_id]
    if {$id ne {}} {
        set baseline [datasetDocumentDescribe $id [dict create capability [dict get $options capability]]]
        set read [datasetDocumentRead $id]
        if {[dict get $options mode] eq {editable}} {set read [datasetDocumentRead $id 4194304];if {![dict get $read complete]} {error {Document exceeds the complete editable4MiB bound}}}
        set text [dict get $read source];set assets [dict get $baseline assets]
        if {[datasetRevisionToken $id] ne [dict get $baseline revision]} {error {Document changed before mounting}}
    }
    if {![winfo exists $parent]} {ttk::frame $parent}
    dict set editors $handle [dict create parent $parent options $options baseline $baseline baseline_text $text \
        assets $assets session [_documentEditorSessionToken] source {} preview {} \
        zoom 1.0 destination_id {} asset_owner {} photos {} image_pairs {} \
        splitters {main {.5}} layout_key main_source_rendered dragging 0 \
        view {source 1 rendered 1 outline 0 properties 0 resources 0}]
    if {[dict get $options mode] eq {editable}} {
        ttk::frame $parent.editor
        lassign [buildMarkupEditorWidget $parent.editor $text [list ::GX::_documentEditorChanged $handle] \
            [dict create toolbar [dict get $options toolbar] source_surface 1 image_command [list ::GX::_documentEditorImageRender $handle]]] source preview
        pack $parent.editor -fill both -expand 1
        dict set editors $handle source $source;dict set editors $handle preview $preview
    } else {
        set pane [dict get $options pane]
        if {$pane eq {source}} {
            set source [sourceSurfaceCreate $parent.source {mode read_only language markdown find_bar 1}]
            sourceSurfaceSet $source $text;pack $parent.source -fill both -expand 1
            dict set editors $handle source $source
        } elseif {$pane eq {associated_source}} {
            if {$id eq {} || ![llength [info commands ::GX::sourceNoteSource]]} {set message {No associated source is available.}
            } elseif {[catch {set associated [sourceNoteSource $id]} message]} {
                set message "Associated source unavailable: $message"
            } else {
                if {[dict get $associated state] eq {current}} {
                    set source [sourceSurfaceCreate $parent.source [dict create mode read_only language [dict get $associated language] find_bar 1]]
                    sourceSurfaceSet $source [dict get $associated source];pack $parent.source -fill both -expand 1
                    dict set editors $handle source $source;set message {}
                } else {set message [dict get $associated diagnostic]}
            }
            if {$message ne {}} {ttk::label $parent.unavailable -text $message -wraplength 500;pack $parent.unavailable -fill both -expand 1 -padx 12 -pady 12}
        } elseif {$pane in {rendered metadata}} {
            text $parent.content -wrap word -state disabled -exportselection 0
            ttk::scrollbar $parent.scroll -command [list $parent.content yview]
            $parent.content configure -yscrollcommand [list $parent.scroll set]
            pack $parent.scroll -side right -fill y;pack $parent.content -fill both -expand 1
            if {$pane eq {rendered}} {
                dict set editors $handle preview $parent.content
                markupRenderStringToWidget $parent.content $text [list ::GX::_documentEditorImageRender $handle] [_documentEditorNavigationContext $handle]
            } else {
                $parent.content configure -state normal
                foreach {key label} {dataset_id {Dataset ID} kind {Document kind} format Format media_type {Media type} producer Producer sha256 SHA256 immutable {Immutable source}} {
                    if {[dict exists $baseline $key]} {$parent.content insert end "$label: [dict get $baseline $key]\n\n"}
                }
                _documentAssociationInsert $parent.content [datasetPublicationV2DictDefault $baseline association {state unassociated}]
                $parent.content configure -state disabled
            }
            uiTextEditingAttach [winfo toplevel $parent] [list $parent.content]
            dict set editors $handle preview $parent.content
        } else {error {Read-only document pane must be rendered, source, metadata or associated_source}}
    }
    _documentEditorUiInit $handle
    set preview [dict get $editors $handle preview]
    if {$preview ne {}} {bind $preview <Configure> +[list ::GX::_documentEditorImagesFit $handle]}
    if {$preview ne {}} {
        ttk::label $parent.navigationStatus -textvariable ::GX::MarkupNavigation::status($preview) -wraplength 600 -anchor w
        pack $parent.navigationStatus -side bottom -fill x -padx 4
        bind $parent.navigationStatus <Configure> [list $parent.navigationStatus configure -wraplength %w]
    }
    bind $parent <Destroy> +[list ::GX::_documentEditorDestroyed $handle %W]
    if {[dict get $options mode] eq {editable} && [dict size $assets]} {dict set editors $handle asset_owner [datasetDocumentAssetOwnerRetain [dict get $options capability] $assets]}
    return $handle
}
proc ::GX::_documentEditorNavigationMessage {handle message} {
    set record [_documentEditorRecord $handle]
    set preview [dict get $record preview]
    if {$preview ne {}} {set ::GX::MarkupNavigation::status($preview) $message}
}
proc ::GX::_documentEditorNavigationContext {handle} {
    set record [_documentEditorRecord $handle];set baseline [dict get $record baseline]
    if {![dict exists $baseline dataset_id] || [dict get $baseline dataset_id] eq {}} {return {}}
    set options [dict create status_command [list ::GX::_documentEditorNavigationMessage $handle]]
    if {[catch {set context [markdownNavigationContext dataset [dict get $baseline dataset_id] $options]} reason]} {
        # Source/Session loss removes navigation authority, never the user's
        # visible editable draft or its normal source/Undo lifecycle.
        return [dict create schema gxtxt.markdown.navigation.v1 kind unavailable options $options diagnostic $reason]
    }
    # Preserve the mounted source revision, including while an unsaved draft is
    # edited. Fresh Registry state must not silently bless a stale open editor.
    dict set context identity [list [dict get $record session] [dict get $baseline revision] [dict get $baseline sha256]]
    return $context
}
proc ::GX::_documentEditorRecord {handle} {
    variable ::GX::DocumentSource::editors
    if {![dict exists $editors $handle]} {error {Document editor has closed}}
    set record [dict get $editors $handle]
    if {![winfo exists [dict get $record parent]]} {error {Document editor has closed}}
    return $record
}
proc ::GX::_documentEditorText {record} {
    set source [dict get $record source]
    if {$source ne {} && [winfo exists $source]} {return [$source get 1.0 end-1c]}
    return [dict get $record baseline_text]
}
proc ::GX::_documentEditorChanged {handle args} {
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    if {[datasetPublicationV2DictDefault [dict get $record options] kind markdown] eq {uml}} {return [_umlEditorChanged $handle {*}$args]}
    _documentEditorPanelsRefresh $handle
    _documentEditorZoom $handle [dict get $record zoom]
    set receipt [documentEditorCommand $handle inspect]
    set callback [dict get $record options on_change]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $receipt]}
    event generate [dict get $record parent] <<GXDocumentChanged>> -data $receipt
}
proc ::GX::_documentEditorDestroyed {handle actual} {
    variable ::GX::DocumentSource::editors
    if {![dict exists $editors $handle] || [dict get $editors $handle parent] ne $actual} return
    _documentEditorImagesClear $handle
    set owner [dict get $editors $handle asset_owner]
    if {$owner ne {}} {catch {datasetDocumentAssetOwnerClose [dict get $editors $handle options capability] $owner}}
    set source [dict get $editors $handle source]
    foreach array {markupPreviewBySource markupChangeCommand markupImageCommand} {catch {unset ::GX::${array}($source)}}
    dict unset editors $handle
}
proc ::GX::_documentEditorView {handle} {
    set record [_documentEditorRecord $handle];set parent [dict get $record parent];set pw $parent.editor.pw
    if {![winfo exists $pw]} {return}
    set view [dict get $record view]
    foreach {key pane} {source edit rendered preview outline outline properties properties resources resources} {
        set path $pw.$pane
        if {[dict get $view $key]} {
            if {$path ni [$pw panes]} {$pw add $path -weight 1}
        } elseif {$path in [$pw panes]} {$pw forget $path}
    }
    _documentEditorViewSplitters $handle
    # Restore logical ordering using the existing ttk pane owner, retaining widgets.
    set index 0
    foreach pane {edit preview outline properties resources} {if {"$pw.$pane" in [$pw panes]} {$pw insert $index $pw.$pane;incr index}}
}
proc ::GX::documentEditorCommand {handle operation {request {}}} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];set options [dict get $record options]
    if {[datasetPublicationV2DictDefault $options kind markdown] eq {uml}} {return [umlEditorCommand $handle $operation $request]}
    set source [dict get $record source];set parent [dict get $record parent]
    set baseline [dict get $record baseline];set editable [expr {[dict get $options mode] eq {editable}}]
    set text [_documentEditorText $record]
    set id [datasetPublicationV2DictDefault $baseline dataset_id {}]
    switch -- $operation {
        inspect {
            set valid [expr {[dict get $record session] eq [_documentEditorSessionToken]}]
            # Keypress/dirty notifications must not acquire the Dataset lock or
            # hash the canonical source. This is the admitted binding snapshot;
            # Save always rechecks the complete live revision and permission.
            set can [expr {$valid && $editable && [datasetPublicationV2DictDefault $baseline can_replace 0]}]
            if {$valid && $id ne {} && [datasetField $id sha256 [datasetField $id canonical_sha256 {}]] ne [dict get $baseline sha256]} {set can 0}
            return [dict create status [expr {$valid?{ready}:{session_changed}}] dataset_id $id \
                dirty [_documentEditorDirty $record $text] can_replace $can read_only [expr {!$editable}] \
                association [datasetPublicationV2DictDefault $baseline association {state unassociated}] \
                sha256 [datasetPublicationV2DictDefault $baseline sha256 {}] session [dict get $record session] permission_state binding_snapshot_revalidated_on_save]
        }
        draft_get {return [dict create text $text assets [dict get $record assets]]}
        capture {
            set saved {}
            if {$baseline ne {}} {
                foreach key {dataset_id kind contract format media_type producer immutable sha256 revision assets} {
                    if {[dict exists $baseline $key]} {dict set saved $key [dict get $baseline $key]}
                }
                dict set saved revision [lreplace [dict get $saved revision] 1 1 portable]
            }
            set state [dict create schema gxtxt.markdown_draft.v1 text $text baseline $saved baseline_text [dict get $record baseline_text] assets [dict get $record assets] view [dict get $record view] zoom [dict get $record zoom] destination_id [dict get $record destination_id] selection {} splitters [_documentEditorSplitters $handle]]
            if {$source ne {}} {
                dict set state cursor [$source index insert];dict set state yview [list [lindex [$source yview] 0]];dict set state xview [list [lindex [$source xview] 0]]
                dict set state selection [$source tag ranges sel]
            }
            return $state
        }
        restore {
            if {!$editable || [dict get $request schema] ne {gxtxt.markdown_draft.v1}} {error {Incompatible Markdown draft state}}
            set restored [dict get $request text]
            if {[string length [encoding convertto utf-8 $restored]]>4194304 || [string first \x00 $restored]>=0} {error {Saved Markdown draft exceeds bounds}}
            set assets [_documentAssetsValidate [dict get $request assets]]
            set baselineText [dict get $request baseline_text]
            if {[string length [encoding convertto utf-8 $baselineText]]>4194304 || [string first \x00 $baselineText]>=0} {error {Saved Markdown baseline exceeds bounds}}
            set view [dict merge [dict get $record view] [dict get $request view]]
            foreach key {source rendered outline properties resources} {if {![string is boolean -strict [dict get $view $key]]} {error {Saved pane visibility must be boolean}}}
            set saved [dict get $request baseline]
            if {$saved ne {}} {
                if {![catch {set current [datasetDocumentDescribe [dict get $saved dataset_id] [dict create capability [dict get $options capability]]]}]
                    && [_datasetRevisionPortableEqual [dict get $current revision] [dict get $saved revision]]} {set saved $current}
            }
            set selection [datasetPublicationV2DictDefault $request selection {}]
            if {[llength $selection] ni {0 2}} {error {Saved selection requires two Tk text indices or empty}}
            foreach index $selection {if {![regexp {^[1-9][0-9]*\.[0-9]+$} $index]} {error {Invalid saved text index}}}
            foreach field {xview yview} {
                if {![dict exists $request $field]} continue
                set fractions [dict get $request $field]
                if {[llength $fractions] ni {1 2}} {error {Saved scroll position requires one anchor or a legacy fraction pair}}
                foreach fraction $fractions {if {![string is double -strict $fraction] || $fraction<0 || $fraction>1} {error {Saved scroll anchor must be normalized}}}
            }
            set splitters [datasetPublicationV2DictDefault $request splitters {}]
            dict for {name ratios} $splitters {
                if {![regexp {^main(_(source|rendered|outline|properties|resources))*$} $name] || [llength $ratios]>4} {error {Invalid logical Markdown splitter}}
                set previous 0
                foreach ratio $ratios {if {![string is double -strict $ratio] || $ratio<$previous || $ratio>1} {error {Saved splitters must be normalized ordered ratios}};set previous $ratio}
            }
            set zoom [datasetPublicationV2DictDefault $request zoom 1.0]
            if {![string is double -strict $zoom] || $zoom<.5 || $zoom>3} {error {Invalid saved Markdown zoom}}
            set destination [datasetPublicationV2DictDefault $request destination_id {}]
            if {$destination ne {}} {datasetPublicationV2ValidateId dataset $destination}
            if {$saved ne {} && [dict exists $saved assets]} {_documentAssetsValidate [dict get $saved assets]}
            set retained {};set serial 0
            dict for {name reference} $assets {dict set retained draft[incr serial] $reference}
            if {$saved ne {} && [dict exists $saved assets]} {dict for {name reference} [dict get $saved assets] {dict set retained baseline[incr serial] $reference}}
            set owner [datasetDocumentAssetOwnerRetain [dict get $options capability] $retained [dict get $record asset_owner]]
            dict set editors $handle asset_owner $owner
            sourceSurfaceSet $source $restored
            dict set editors $handle assets $assets;dict set editors $handle baseline $saved
            dict set editors $handle baseline_text $baselineText
            dict set editors $handle destination_id $destination;dict set editors $handle zoom $zoom
            dict set editors $handle view $view;_documentEditorView $handle
            if {[dict exists $request cursor]} {catch {$source mark set insert [dict get $request cursor]}}
            foreach axis {x y} {if {[dict exists $request ${axis}view]} {catch {$source ${axis}view moveto [lindex [dict get $request ${axis}view] 0]}}}
            $source tag remove sel 1.0 end
            if {[llength $selection]} {$source tag add sel {*}$selection}
            _documentEditorSplittersRestore $handle $splitters
            markupSourceChanged $source
        }
        draft_set {
            if {!$editable} {error {Document is read-only}}
            set text [dict get $request text]
            if {[string length [encoding convertto utf-8 $text]]>4194304 || [string first \x00 $text]>=0} {error {Document draft exceeds text bounds}}
            sourceSurfaceSet $source $text
            if {[dict exists $request assets]} {dict set editors $handle assets [_documentAssetsValidate [dict get $request assets]]}
            markupSourceChanged $source
        }
        render {if {$editable} {markupSourceChanged $source}}
        zoom_in - zoom_out - zoom_reset {
            set factor [dict get $record zoom]
            switch -- $operation {zoom_in {set factor [expr {min(3.,$factor+.25)}]} zoom_out {set factor [expr {max(.5,$factor-.25)}]} zoom_reset {set factor 1.0}}
            _documentEditorZoom $handle $factor
        }
        insert_image - replace_image - remove_image {_documentEditorImage $handle $operation $request}
        view_source - view_rendered - view_outline - view_properties - view_resources {
            if {!$editable} {error {This read-only pane is controlled by its Preview host}}
            set key [string range $operation 5 end]
            dict set editors $handle view $key [expr {![dict get $record view $key]}]
            _documentEditorView $handle
        }
        reset_layout {
            if {$editable} {dict set editors $handle view {source 1 rendered 1 outline 0 properties 0 resources 0};dict set editors $handle splitters {main {.5}};dict set editors $handle layout_key main_source_rendered;_documentEditorView $handle}
        }
        new {
            if {!$editable} {error {Document is read-only}}
            if {[_documentEditorDirty $record $text] && ![datasetPublicationV2DictDefault $request discard_confirmed 0]} {error {Unsaved document draft; review Save/Discard/Cancel before New}}
            dict set editors $handle asset_owner [datasetDocumentAssetOwnerRetain [dict get $options capability] {} [dict get $record asset_owner]]
            sourceSurfaceSet $source {};dict set editors $handle baseline {};dict set editors $handle baseline_text {};dict set editors $handle assets {}
            markupSourceChanged $source
        }
        open {
            if {!$editable} {error {Document is read-only}}
            if {[_documentEditorDirty $record $text] && ![datasetPublicationV2DictDefault $request discard_confirmed 0]} {error {Unsaved document draft; review Save/Discard/Cancel before Open}}
            set description [datasetDocumentDescribe [dict get $request dataset_id] [dict create capability [dict get $options capability]]]
            set read [datasetDocumentRead [dict get $request dataset_id] 4194304]
            if {![dict get $read complete]} {error {Document exceeds the complete editable4MiB bound}}
            if {[datasetRevisionToken [dict get $request dataset_id]] ne [dict get $description revision]} {error {Document changed before opening}}
            set retained [datasetDocumentAssetOwnerRetain [dict get $options capability] [dict get $description assets] [dict get $record asset_owner]]
            sourceSurfaceSet $source [dict get $read source]
            dict set editors $handle asset_owner $retained
            dict set editors $handle baseline $description;dict set editors $handle baseline_text [dict get $read source]
            dict set editors $handle assets [dict get $description assets];dict set editors $handle session [dict get $description session]
            markupSourceChanged $source
        }
        save_existing - publish_new {
            if {!$editable} {error {Document is read-only}}
            set save [dict create mode [expr {$operation eq {save_existing}?{replace_existing}:{new}}] \
                dataset_id [expr {$operation eq {save_existing}?$id:[dict get $request dataset_id]}] text $text \
                expected_session [dict get $record session] assets [dict get $record assets]]
            if {$operation eq {save_existing}} {
                dict set save expected_revision [dict get $baseline revision];dict set save expected_sha256 [dict get $baseline sha256]
            } elseif {$id ne {}} {dict set save source_dataset_id $id;dict set save source_revision [dict get $baseline revision]}
            if {$operation eq {publish_new}} {dict set editors $handle destination_id [dict get $request dataset_id]}
            set saved [datasetDocumentWrite [dict get $options capability] $save]
            dict set editors $handle baseline $saved;dict set editors $handle baseline_text $text
            _documentEditorChanged $handle
        }
        cut - copy - paste - select_all - undo - redo {
            if {!$editable && $operation ni {copy select_all}} {error {Document is read-only}}
            uiTextEdit [winfo toplevel $parent] $operation
            if {$editable} {markupSourceChanged $source}
        }
        find - replace {
            if {$source eq {}} {error {Select the Source pane to search its literal text}}
            set surface [sourceSurfaceParent $source]
            if {$operation eq {replace}} {if {!$editable} {error {Document is read-only}};_sourceSurfaceReplaceControls $surface;focus $surface.find.replace.value
            } else {focus $surface.find.query}
        }
        heading1 - heading2 - heading3 - bold - italic - inline_code - code_block - bullet_list - numbered_list - table - link - quote - rule - color {
            if {!$editable} {error {Document is read-only}}
            focus $source
            switch -- $operation {
                heading1 - heading2 - heading3 {markupHeading $source [string index $operation end]}
                bold {markupWrapSelection $source ** **}
                italic {markupWrapSelection $source * *}
                inline_code {markupWrapSelection $source ` `}
                code_block {markupCodeBlock $source}
                color {markupChooseColor $source}
                bullet_list {$source insert insert "\n- Item\n"}
                numbered_list {$source insert insert "\n1. Item\n"}
                table {$source insert insert "\n| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |\n"}
                link {markupWrapSelection $source {[} {](https://example.org)}}
                quote {$source insert insert "\n> Quote\n"}
                rule {$source insert insert "\n---\n"}
            }
            markupSourceChanged $source
        }
        dispose {destroy $parent;return [dict create status closed]}
        default {error "Unsupported document editor operation '$operation'"}
    }
    return [documentEditorCommand $handle inspect]
}

source [file join [file dirname [info script]] source_note_api_v1.tcl]
source [file join [file dirname [info script]] document_editor_ui_v1.tcl]
