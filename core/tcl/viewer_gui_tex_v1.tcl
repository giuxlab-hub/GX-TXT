# SPDX-License-Identifier: GPL-3.0-or-later
# TeX form composition within Viewer GUI Host. Document/Resource/Source Surface,
# managed TeX execution, PDF and File Publication retain their existing owners.
# Integration hooks and typed SDK admission are required before author use.
proc ::GX::_viewerGuiTeXDesignValidate {design {complete 0}} {
    set definitions {};foreach component [dict get $design components] {dict set definitions [dict get $component id] $component}
    set required {tex_source tex_pdf tex_projects tex_assets tex_diagnostics tex_log tex_status tex_info tex_source_status tex_pdf_status}
    foreach component [dict get $design components] {
        set p [dict get $component properties];set present 0
        foreach key $required {if {[dict exists $p $key]} {incr present}}
        if {!$present} continue
        if {[dict get $component type] ne {section} || $present!=[llength $required]} {error {A TeX form requires a section and its complete source/PDF/project/assets/diagnostics/status references}}
        foreach {key types} {tex_source document tex_pdf document tex_projects {choice combobox} tex_assets table tex_diagnostics table tex_log log tex_status {label status} tex_info {label status log} tex_source_status {label status} tex_pdf_status {label status}} {
            set id [dict get $p $key]
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types} {error "Invalid TeX form reference $key"}
        }
        set source [dict get $definitions [dict get $p tex_source] properties]
        if {[dict get $source kind] ne {tex} || [datasetPublicationV2DictDefault $source mode {}] ne {editable} || [dict get $definitions [dict get $p tex_pdf] properties kind] ne {pdf}} {error {TeX requires an editable tex document and an existing PDF document component}}
    }
    foreach component [dict get $design components] {
        if {[dict get $component type] ne {document} || [dict get $component properties kind] ne {tex}} continue
        set count 0
        foreach owner [dict get $design components] {if {[datasetPublicationV2DictDefault [dict get $owner properties] tex_source {}] eq [dict get $component id]} {incr count}}
        if {$count>1 || ($complete && $count!=1)} {error {Each TeX source must belong to exactly one complete declared article form}}
    }
}
proc ::GX::_viewerGuiTeXForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the article Viewer}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || ![dict exists $c properties tex_source]} {error {Declare the complete TeX article form}}
    return [dict get $c properties]
}
proc ::GX::_viewerGuiTeXRecord {window form {allowNoSession 0}} {
    _viewerGuiTeXForm $window $form
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms $form]} {error {Article editor is not initialized}}
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    if {[datasetPublicationV2DictDefault $r invalid {}] ne {}} {error [dict get $r invalid]}
    if {!$allowNoSession && [dict get $::GX::ViewerGui::instances $window token] eq {}} {error {Open a Session and reopen the article Viewer before editing}}
    if {[dict get $r document_id] ne {} && [dict get $r session_token] ne [interactiveDocumentSessionToken]} {error {Article belongs to the previous Session; reopen its Viewer}}
    return $r
}
proc ::GX::_viewerGuiTeXStamp {workspace} {
    set p [dict get $workspace payload]
    set assets {};foreach name [lsort [dict keys [dict get $p assets]]] {dict set assets $name [dict get $p assets $name sha256]}
    set source [dict get $p source]
    return [dict create document_id [dict get $workspace workspace_id] generation [dict get $workspace generation] source_revision [dict get $p source_revision] source_sha256 [expr {$source eq {} ? {} : [dict get $source sha256]}] assets $assets]
}
proc ::GX::_viewerGuiTeXCurrent {window form} {
    set r [_viewerGuiTeXRecord $window $form]
    if {[dict get $r document_id] eq {}} {error {Create or open an article first}}
    set item [interactiveDocumentTeXRead [dict get $r document_id]]
    if {[_viewerGuiTeXStamp $item] ne [dict get $r stamp]} {error {Article source/assets changed in another window; preserve your draft and reopen the article}}
    return $item
}
proc ::GX::_viewerGuiTeXDirty {window form} {
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    return [expr {[sourceSurfaceGet [dict get $r source_widget]] ne [dict get $r saved_source]}]
}
proc ::GX::_viewerGuiTeXRemember {window form workspace} {
    # Persist association and revision identities, never an additional source.
    set p [dict get $workspace payload];set state [viewerGuiDesignContextGet $window]
    dict set state tex_projects $form [dict create document_id [dict get $workspace workspace_id] generation [dict get $workspace generation] source_revision [dict get $p source_revision] source_sha256 [expr {[dict get $p source] eq {} ? {} : [dict get $p source sha256]}]]
    viewerGuiDesignContextSet $window $state
}
proc ::GX::_viewerGuiTeXSetText {window form key text} {
    set p [_viewerGuiTeXForm $window $form]
    viewerGuiDesignTextSet $window [dict get $p $key] $text
}
proc ::GX::_viewerGuiTeXChanged {window form} {
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms $form] || ![viewerGuiDesignGuard $window]} return
    if {[datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window tex_forms $form] invalid {}] ne {}} return
    set dirty [_viewerGuiTeXDirty $window $form]
    _viewerGuiTeXSetText $window $form tex_source_status [expr {$dirty ? {Unsaved source changes. Build saves the exact draft first.} : {Source matches the saved article revision.}}]
    set r [_viewerGuiTeXRecord $window $form]
    set current [expr {!$dirty && [datasetPublicationV2DictDefault $r pdf_saved_current 0]}]
    _viewerGuiTeXSetText $window $form tex_pdf_status [expr {$current ? {PDF matches the saved source/assets revision.} : {No current PDF. Previous successful output, if any, is retained as stale.}}]
}
proc ::GX::_viewerGuiTeXInitialize {window context} {
    _viewerGuiTeXDesignValidate [dict get $::GX::ViewerGui::instances $window design] 1
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {
        if {[dict get $component type] ne {section} || ![dict exists $component properties tex_source]} continue
        set form [dict get $component id];set p [dict get $component properties]
        set module [dict get $::GX::ViewerGui::instances $window module];set viewer [dict get $::GX::ViewerGui::instances $window provider]
        set provider [string map {. _ - _} ${module}_${viewer}_${form}_tex_article]
        interactiveDocumentTeXRegister $module $provider $viewer
        set container [dict get $::GX::ViewerGui::instances $window widgets [dict get $p tex_source]]
        foreach child [winfo children $container] {destroy $child}
        set enabled [expr {[dict get $::GX::ViewerGui::instances $window token] ne {} && [dict get $::GX::ViewerGui::instances $window mode] ne {demo}}]
        set text [sourceSurfaceCreate $container.source [dict create mode [expr {$enabled ? {editable} : {read_only}}] language tex find_bar 1 change_command [list ::GX::_viewerGuiTeXChanged $window $form]]]
        pack $container.source -fill both -expand 1
        viewerGuiSourceScopeAttach $window [dict get $p tex_source] $text
        dict set ::GX::ViewerGui::instances $window tex_forms $form [dict create source_widget $text provider $provider document_id {} session_token {} stamp {} saved_source {} diagnostics {} build_state idle build_identity {} pdf_saved_current 0]
        if {!$enabled} {_viewerGuiTeXSetText $window $form tex_status {Open a Session and reopen this Viewer to edit a LaTeX article.};continue}
        viewerGuiDesignTeXCommand $window $form refresh
        if {[dict exists $context tex_document_id] && [dict get [interactiveDocumentTeXRead [dict get $context tex_document_id]] provider_id] eq $provider} {_viewerGuiTeXOpen $window $form [dict get $context tex_document_id]}
    }
    set workspace 0
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {if {[dict get $c type] eq {workspace}} {set workspace 1}}
    if {[dict exists $::GX::ViewerGui::instances $window tex_forms] && !$workspace} {wm protocol $window WM_DELETE_WINDOW [list ::GX::_viewerGuiTeXClose $window]}
}
proc ::GX::_viewerGuiTeXPrepare {window form} {
    if {![_viewerGuiTeXDirty $window $form]} {return 1}
    set decision [tk_messageBox -parent $window -type yesnocancel -default cancel -icon question -title {Article source changes} -message {Save the current article source before changing articles? Yes saves; No discards the editable draft; Cancel keeps editing.}]
    _viewerGuiTeXRecord $window $form
    if {$decision eq {cancel}} {return 0}
    if {$decision eq {yes}} {_viewerGuiTeXSave $window $form}
    return 1
}
proc ::GX::_viewerGuiTeXAssociationPrepare {window form} {
    if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {return -code error -errorcode {GX HISTORY EDIT_CANCELLED} {Article association change cancelled}}
    # History confirmation is a nested event loop; recheck the live form and
    # Session before any canonical article is created or associated.
    return [_viewerGuiTeXRecord $window $form]
}
proc ::GX::_viewerGuiTeXOpen {window form document} {
    set r [_viewerGuiTeXRecord $window $form]
    set item [interactiveDocumentTeXRead $document]
    if {[dict get $item provider_id] ne [dict get $r provider]} {error {Select an article belonging to this declared Viewer form}}
    set source [interactiveDocumentTeXReadSource $document]
    set associationChanged [expr {[dict get $r document_id] ne $document}]
    set r [_viewerGuiTeXAssociationPrepare $window $form]
    if {[dict exists $r await_timer]} {after cancel [dict get $r await_timer];dict unset r await_timer}
    if {[dict exists $r lifecycle]} {interactiveDocumentLifecycleUnsubscribe [dict get $r lifecycle]}
    viewerGuiDocumentRelease $window [dict get [_viewerGuiTeXForm $window $form] tex_pdf]
    _viewerGuiTeXPDFReset $window $form
    dict set r document_id $document;dict set r session_token [interactiveDocumentSessionToken];dict set r stamp [_viewerGuiTeXStamp $item];dict set r saved_source $source
    dict set r build_identity {};dict set r build_state [dict get [interactiveDocumentTeXStatus $document] status]
    dict set r lifecycle [interactiveDocumentLifecycleSubscribe [list ::GX::_viewerGuiTeXLifecycle $window $form [dict get $item generation]] $window $document]
    dict set ::GX::ViewerGui::instances $window tex_forms $form $r
    sourceSurfaceSet [dict get $r source_widget] $source
    _viewerGuiTeXRemember $window $form $item
    _viewerGuiTeXRefresh $window $form
    viewerGuiDesignValueSet $window [dict get [_viewerGuiTeXForm $window $form] tex_projects] $document
    if {$associationChanged && ![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {Open article association}}
    if {[dict get $r build_state] ne {idle}} {_viewerGuiTeXAwait $window $form}
    return [dict create status opened document_id $document source_revision [dict get $item payload source_revision]]
}
proc ::GX::_viewerGuiTeXSave {window form} {
    set item [_viewerGuiTeXCurrent $window $form];set r [_viewerGuiTeXRecord $window $form]
    set source [sourceSurfaceGet [dict get $r source_widget]]
    set saved [interactiveDocumentTeXSave [dict get $item workspace_id] $source [dict get $item payload assets]]
    dict set ::GX::ViewerGui::instances $window tex_forms $form stamp [_viewerGuiTeXStamp $saved]
    dict set ::GX::ViewerGui::instances $window tex_forms $form saved_source $source
    _viewerGuiTeXRemember $window $form $saved
    _viewerGuiTeXRefresh $window $form
    return [dict create status saved document_id [dict get $saved workspace_id] source_revision [dict get $saved payload source_revision]]
}
proc ::GX::_viewerGuiTeXNew {window form dialog values} {
    set r [_viewerGuiTeXRecord $window $form]
    if {![_viewerGuiTeXPrepare $window $form]} return
    set name [_workspaceName [dict get $values name]]
    set r [_viewerGuiTeXAssociationPrepare $window $form]
    set item [interactiveDocumentTeXCreate [dict get $r provider] $name]
    _viewerGuiTeXOpen $window $form [dict get $item workspace_id]
    destroy $dialog
}
proc ::GX::_viewerGuiTeXReadResource {reference {limit 1048576}} {
    interactiveDocumentResourceInfo $reference
    set bytes {};set count [expr {min($limit,[dict get $reference size_bytes])}]
    for {set start 0} {$start<$count} {incr start 1048576} {append bytes [interactiveDocumentResourceReadChunk $reference $start [expr {min(1048576,$count-$start)}]]}
    return [encoding convertfrom utf-8 $bytes]
}
proc ::GX::_viewerGuiTeXRefresh {window form} {
    set r [_viewerGuiTeXRecord $window $form];set p [_viewerGuiTeXForm $window $form]
    set choices {};foreach item [sessionWorkspaceList] {if {[dict get $item schema] eq {gxtxt.tex_project.v1} && [dict get $item provider_id] eq [dict get $r provider]} {lappend choices [dict get $item workspace_id]}}
    viewerGuiDesignChoicesSet $window [dict get $p tex_projects] $choices
    if {[dict get $r document_id] eq {}} {
        foreach key {tex_assets tex_diagnostics} {viewerGuiDesignTableSet $window [dict get $p $key] {}}
        foreach key {tex_log tex_info tex_source_status tex_pdf_status} {_viewerGuiTeXSetText $window $form $key {No article is open.}}
        viewerGuiDesignValueSet $window [dict get $p tex_projects] {}
        _viewerGuiTeXSetText $window $form tex_status {Create a new article or select and open a saved article.}
        return
    }
    set item [_viewerGuiTeXCurrent $window $form];set payload [dict get $item payload]
    set assets {}
    dict for {name ref} [dict get $payload assets] {
        set state available;if {[catch {interactiveDocumentResourceInfo $ref} why]} {set state $why}
        lappend assets [list $name [datasetPublicationV2DictDefault [dict get $ref metadata] format {}] [dict get $ref size_bytes] $state]
    }
    viewerGuiDesignTableSet $window [dict get $p tex_assets] [lrange $assets 0 999]
    set build [dict get $payload last_build]
    set diagnostics {};set rows {}
    foreach diagnostic [datasetPublicationV2DictDefault $build diagnostics {}] {
        if {[llength $rows]>=1000} break
        lappend rows [list [dict get $diagnostic severity] [dict get $diagnostic file] [dict get $diagnostic line] [dict get $diagnostic message]]
        lappend diagnostics $diagnostic
    }
    viewerGuiDesignTableSet $window [dict get $p tex_diagnostics] $rows
    dict set ::GX::ViewerGui::instances $window tex_forms $form diagnostics $diagnostics
    if {[dict exists $build log]} {
        set log [_viewerGuiTeXReadResource [dict get $build log] 1000000]
        if {[dict get $build log size_bytes]>1000000} {append log "\nOutput limited to the first 1000000 bytes; full managed log retained."}
        _viewerGuiTeXSetText $window $form tex_log $log
    } else {_viewerGuiTeXSetText $window $form tex_log {No compiler log is available for this article revision.}}
    _viewerGuiTeXSetText $window $form tex_info "[dict get $item name] · [dict get $item workspace_id]\nSaved source revision [dict get $payload source_revision] · [llength $assets] linked assets (first 1000 shown).\nConfigured runtime: [runtimeToolResolve latex]"
    set status [interactiveDocumentTeXStatus [dict get $item workspace_id]]
    set current [expr {[dict get $status pdf_status] eq {current}}]
    dict set ::GX::ViewerGui::instances $window tex_forms $form build_state [dict get $status status]
    dict set ::GX::ViewerGui::instances $window tex_forms $form pdf_saved_current $current
    _viewerGuiTeXChanged $window $form
    _viewerGuiTeXSetText $window $form tex_status "Build: [dict get $status status] · Last result: [datasetPublicationV2DictDefault $build status none]"
}
proc ::GX::_viewerGuiTeXBuilt {window form document generation identity receipt} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window tex_forms $form]} return
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    if {[dict get $r document_id] ne $document || [dict get $r stamp generation] ne $generation || ([dict get $r build_identity] ne {} && [dict get $r build_identity] ne $identity)} return
    dict set ::GX::ViewerGui::instances $window tex_forms $form build_state [dict get $receipt status]
    if {[catch {_viewerGuiTeXRefresh $window $form} message]} {_viewerGuiTeXSetText $window $form tex_status $message}
    viewerGuiTraceEmit $window $form source_changed [dict create status [dict get $receipt status] authority INTERACTIVE_DOCUMENT_API_v1]
}
proc ::GX::_viewerGuiTeXAwait {window form} {
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms $form] || ![winfo exists $window]} return
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    if {[dict exists $r await_timer]} {after cancel [dict get $r await_timer]}
    dict set ::GX::ViewerGui::instances $window tex_forms $form await_timer [after 750 [list ::GX::_viewerGuiTeXAwaitCheck $window $form [dict get $r document_id] [dict get $r stamp generation]]]
}
proc ::GX::_viewerGuiTeXAwaitCheck {window form document generation} {
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms $form] || ![winfo exists $window]} return
    dict unset ::GX::ViewerGui::instances $window tex_forms $form await_timer
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    if {[dict get $r document_id] ne $document || [dict get $r stamp generation] ne $generation || ![viewerGuiDesignGuard $window]} return
    if {[catch {set state [interactiveDocumentTeXStatus $document]} message]} {_viewerGuiTeXSetText $window $form tex_status $message;return}
    if {[dict get $state status] eq {idle}} {
        if {[catch {_viewerGuiTeXRefresh $window $form} message]} {_viewerGuiTeXSetText $window $form tex_status $message}
    } else {_viewerGuiTeXAwait $window $form}
}
proc ::GX::_viewerGuiTeXPreview {window form} {
    set item [_viewerGuiTeXCurrent $window $form];set good [dict get $item payload last_good_pdf]
    if {$good eq {}} {error {Build the article before opening a PDF preview}}
    set reference [dict get $good resource]
    if {[dict get $reference document_id] ne [dict get $item workspace_id]} {error {TeX PDF belongs to another Workspace}}
    interactiveDocumentResourceInfo $reference
    set component [dict get [_viewerGuiTeXForm $window $form] tex_pdf]
    viewerGuiDocumentRelease $window $component
    set reader [datasetMediaViewerOpenResource $reference "[dict get $item name] · PDF source revision [dict get $good source_revision]"]
    dict set ::GX::ViewerGui::instances $window document_readers $component $reader
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    foreach child [winfo children $widget] {destroy $child}
    ttk::label $widget.opened -text "Native PDF reader opened for source revision [dict get $good source_revision]. Source/PDF status above reports whether it is current." -wraplength 440
    bind $widget.opened <Configure> +[list ::GX::_uiFieldComponentTextWrap $widget.opened 440 %W %w]
    pack $widget.opened -fill x -padx 8 -pady 8
    return [dict create status opened document_id [dict get $item workspace_id] source_revision [dict get $good source_revision]]
}
proc ::GX::_viewerGuiTeXPDFReset {window form} {
    set component [dict get [_viewerGuiTeXFormUnchecked $window $form] tex_pdf]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    foreach child [winfo children $widget] {destroy $child}
    ttk::label $widget.empty -text {Build the article, then open its managed PDF preview.} -wraplength 440
    bind $widget.empty <Configure> +[list ::GX::_uiFieldComponentTextWrap $widget.empty 440 %W %w]
    pack $widget.empty -fill x -padx 8 -pady 8
}
proc ::GX::_viewerGuiTeXDiagnostic {window form} {
    set item [_viewerGuiTeXCurrent $window $form];set r [_viewerGuiTeXRecord $window $form];set p [_viewerGuiTeXForm $window $form]
    if {![dict exists $item payload last_build source_revision] || [dict get $r diagnostics] eq {}} {error {Build the article first; no compiler diagnostics are available}}
    if {[_viewerGuiTeXDirty $window $form] || [dict get $item payload last_build source_revision]!=[dict get $item payload source_revision]} {error {Diagnostic belongs to an older source; save and build the current draft before following its location}}
    set table [uiFieldComponentTableWidget [dict get $::GX::ViewerGui::instances $window widgets [dict get $p tex_diagnostics]]]
    set selected [$table selection]
    if {[llength $selected]!=1} {error {Select one actual compiler diagnostic}}
    set index [lsearch -exact [$table children {}] [lindex $selected 0]]
    set d [lindex [dict get $r diagnostics] $index]
    if {$index<0 || $d eq {} || ![dict get $d source_link] || [dict get $d line]<1} {error {The native compiler did not provide an exact source location for this diagnostic}}
    if {[dict get $d file] eq {main.tex}} {sourceSurfaceLocation [dict get $r source_widget] [dict get $d line]} else {
        set name [dict get $d file]
        if {![dict exists $item payload assets $name]} {error {Diagnostic asset is no longer part of this article}}
        set dialog $window.tex_diagnostic_asset
        if {[winfo exists $dialog]} {destroy $dialog}
        uiFieldDialogCreate $dialog $window "Compiler source: $name"
        set source [sourceSurfaceCreate $dialog.source [dict create mode read_only language tex find_bar 1]]
        pack $dialog.source -fill both -expand 1
        sourceSurfaceSet $source [_viewerGuiTeXReadResource [dict get $item payload assets $name] 16777216]
        sourceSurfaceLocation $source [dict get $d line]
        uiFieldDialogPresent $dialog $source
    }
    return [dict create status located file [dict get $d file] line [dict get $d line]]
}
proc ::GX::_viewerGuiTeXSaveAssets {window form assets} {
    set item [_viewerGuiTeXCurrent $window $form];set r [_viewerGuiTeXRecord $window $form]
    set source [sourceSurfaceGet [dict get $r source_widget]]
    set saved [interactiveDocumentTeXSave [dict get $item workspace_id] $source $assets]
    dict set ::GX::ViewerGui::instances $window tex_forms $form stamp [_viewerGuiTeXStamp $saved]
    dict set ::GX::ViewerGui::instances $window tex_forms $form saved_source $source
    _viewerGuiTeXRemember $window $form $saved
    _viewerGuiTeXRefresh $window $form
    return $saved
}
proc ::GX::_viewerGuiTeXAssetApply {window form expected path dialog values} {
    set item [_viewerGuiTeXCurrent $window $form]
    if {[_viewerGuiTeXStamp $item] ne $expected} {error {Article changed while the asset dialog was open; reopen the dialog}}
    set name [dict get $values name]
    _interactiveDocumentTeXName $name
    if {$name eq {main.tex}} {error {main.tex is edited in the source editor}}
    if {[dict exists $item payload assets $name]} {
        if {[tk_messageBox -parent $dialog -type yesno -default no -icon question -title {Replace article asset} -message "Replace the linked asset '$name'? Previous compiled output will be retained as stale when inputs change."] ne {yes}} return
        set item [_viewerGuiTeXCurrent $window $form]
        if {[_viewerGuiTeXStamp $item] ne $expected} {error {Article changed during confirmation; reopen the asset dialog}}
    }
    set assets [dict get $item payload assets]
    dict set assets $name [interactiveDocumentTeXImportAsset [dict get $item workspace_id] $name $path]
    _viewerGuiTeXSaveAssets $window $form $assets
    destroy $dialog
}
proc ::GX::_viewerGuiTeXExportCollisions {path assets} {
    set targets [list [file normalize $path]]
    foreach name [dict keys $assets] {lappend targets [file join [file dirname [file normalize $path]] [_interactiveDocumentTeXName $name]]}
    set existing {}
    foreach target $targets {
        if {![file exists $target]} continue
        if {![file isfile $target] || [file type $target] ne {file}} {error "Export destination is not a regular file: $target"}
        dict set existing $target [sha256File $target]
    }
    return $existing
}
proc ::GX::_viewerGuiTeXDispose {window} {
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms]} return
    dict for {form r} [dict get $::GX::ViewerGui::instances $window tex_forms] {
        if {[dict exists $r lifecycle]} {interactiveDocumentLifecycleUnsubscribe [dict get $r lifecycle]}
        if {[dict exists $r await_timer]} {after cancel [dict get $r await_timer]}
    }
}
proc ::GX::_viewerGuiTeXClose {window} {
    set forms [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] tex_forms {}]]
    set dirty 0;foreach form $forms {if {[_viewerGuiTeXDirty $window $form]} {set dirty 1}}
    if {$dirty} {
        set answer [tk_messageBox -parent $window -type yesnocancel -default cancel -icon question -title {Article source changes} -message {Save the edited article source before closing? Yes saves; No discards unsaved drafts; Cancel keeps editing.}]
        if {$answer eq {cancel}} return
        if {$answer eq {yes}} {foreach form $forms {if {[_viewerGuiTeXDirty $window $form]} {_viewerGuiTeXSave $window $form}}}
    }
    destroy $window
}
proc ::GX::_viewerGuiTeXLifecycle {window form generation event} {
    if {![dict exists $::GX::ViewerGui::instances $window tex_forms $form] || ![winfo exists $window]} return
    set r [dict get $::GX::ViewerGui::instances $window tex_forms $form]
    if {[dict get $r document_id] ne [dict get $event document_id] || [dict get $r session_token] ne [dict get $event session_token] || $generation ne [dict get $event owner_generation]} return
    set message "Article [dict get $event event]; the retained draft is read-only. Reopen a current article Viewer."
    dict set ::GX::ViewerGui::instances $window tex_forms $form invalid $message
    if {[dict exists $r await_timer]} {after cancel [dict get $r await_timer];dict unset ::GX::ViewerGui::instances $window tex_forms $form await_timer}
    viewerGuiDocumentRelease $window [dict get [_viewerGuiTeXFormUnchecked $window $form] tex_pdf]
    _viewerGuiTeXPDFReset $window $form
    sourceSurfaceConfigure [dict get $r source_widget] {mode read_only}
    set component [dict get [_viewerGuiTeXFormUnchecked $window $form] tex_status]
    viewerGuiDesignTextSet $window $component $message
}
proc ::GX::_viewerGuiTeXFormUnchecked {window form} {return [dict get [viewerGuiDesignComponent $window $form] properties]}
proc ::GX::_viewerGuiTeXRestoreCheck {window context} {
    dict for {form r} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] tex_forms {}] {
        set desired [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $context tex_projects {}] $form {}]
        set id [datasetPublicationV2DictDefault $desired document_id {}]
        if {$id ne {}} {
            set item [interactiveDocumentTeXRead $id]
            if {[dict get $item provider_id] ne [dict get $r provider] || [dict get $item generation] ne [dict get $desired generation]} {error {Saved article association belongs to another provider or Document generation}}
        }
        if {$id eq [dict get $r document_id] && $id ne {}} {
            _viewerGuiTeXCurrent $window $form
        } elseif {[_viewerGuiTeXDirty $window $form]} {error {Save or discard the article draft before restoring a different article association}}
    }
}
proc ::GX::_viewerGuiTeXRestore {window} {
    set context [viewerGuiDesignContextGet $window]
    dict for {form r} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] tex_forms {}] {
        set desired [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $context tex_projects {}] $form {}]
        set id [datasetPublicationV2DictDefault $desired document_id {}]
        if {$id eq [dict get $r document_id]} continue
        if {$id ne {}} {_viewerGuiTeXOpen $window $form $id;continue}
        if {[dict exists $r lifecycle]} {interactiveDocumentLifecycleUnsubscribe [dict get $r lifecycle];dict unset r lifecycle}
        if {[dict exists $r await_timer]} {after cancel [dict get $r await_timer];dict unset r await_timer}
        viewerGuiDocumentRelease $window [dict get [_viewerGuiTeXForm $window $form] tex_pdf]
        _viewerGuiTeXPDFReset $window $form
        dict set r document_id {};dict set r session_token {};dict set r stamp {};dict set r saved_source {};dict set r diagnostics {};dict set r build_identity {};dict set r pdf_saved_current 0
        dict set ::GX::ViewerGui::instances $window tex_forms $form $r
        sourceSurfaceSet [dict get $r source_widget] {}
        _viewerGuiTeXRefresh $window $form
    }
}
proc ::GX::viewerGuiDesignTeXCommand {window form operation} {
    set r [_viewerGuiTeXRecord $window $form [expr {$operation eq {refresh}}]];set p [_viewerGuiTeXForm $window $form]
    if {$operation eq {refresh} && [dict get $::GX::ViewerGui::instances $window token] eq {}} {
        _viewerGuiTeXSetText $window $form tex_status {Open a Session and reopen this Viewer to edit a LaTeX article.}
        return [dict create status unavailable reason no_session]
    }
    switch -- $operation {
        refresh {_viewerGuiTeXRefresh $window $form;return [dict create status refreshed]}
        new {
            set dialog $window.tex_new_article
            uiFieldFormCreate $dialog {New LaTeX article} {name {type string required 1 label Name}} {name {Scientific article}} [list ::GX::_viewerGuiTeXNew $window $form $dialog] $window
            return [dict create status awaiting_name]
        }
        open {
            set id [dict get [viewerGuiDesignValues $window] [dict get $p tex_projects]]
            if {![_viewerGuiTeXPrepare $window $form]} {return [dict create status cancelled]}
            return [_viewerGuiTeXOpen $window $form $id]
        }
        save {return [_viewerGuiTeXSave $window $form]}
        build - rebuild {
            set item [_viewerGuiTeXCurrent $window $form]
            if {[dict get [interactiveDocumentTeXStatus [dict get $item workspace_id]] status] ne {idle}} {error {Cancel or finish the current article build first}}
            _viewerGuiTeXSave $window $form
            set r [_viewerGuiTeXRecord $window $form];set engine pdflatex
            set runtime [file tail [runtimeToolRequired latex]]
            if {$runtime in {xelatex lualatex}} {set engine $runtime}
            set identity "tex-build#[clock clicks]"
            set result [interactiveDocumentTeXBuild [dict get $r document_id] [list ::GX::_viewerGuiTeXBuilt $window $form [dict get $r document_id] [dict get $r stamp generation] $identity] $engine $window]
            dict set ::GX::ViewerGui::instances $window tex_forms $form build_identity $identity
            dict set ::GX::ViewerGui::instances $window tex_forms $form build_state running
            _viewerGuiTeXSetText $window $form tex_status {Native TeX build running. Source edits remain available; changed revisions reject stale completion.}
            return $result
        }
        cancel {
            if {[dict get $r document_id] eq {}} {return [dict create status idle]}
            return [interactiveDocumentTeXCancel [dict get $r document_id] [dict get $r stamp generation]]
        }
        preview {return [_viewerGuiTeXPreview $window $form]}
        diagnostic_open {return [_viewerGuiTeXDiagnostic $window $form]}
        import_assets {
            _viewerGuiTeXCurrent $window $form
            set path [workspaceOpenFile acquisition_dir -parent $window -title {Add or replace an article asset}]
            if {$path eq {}} {return [dict create status cancelled]}
            set item [_viewerGuiTeXCurrent $window $form];set dialog $window.tex_asset
            uiFieldFormCreate $dialog {Article asset filename} {name {type string required 1 label {Relative project filename (for example sections/body.tex)}}} [dict create name [file tail $path]] [list ::GX::_viewerGuiTeXAssetApply $window $form [_viewerGuiTeXStamp $item] $path $dialog] $window
            return [dict create status awaiting_asset_name]
        }
        remove_asset {
            set item [_viewerGuiTeXCurrent $window $form]
            set table [uiFieldComponentTableWidget [dict get $::GX::ViewerGui::instances $window widgets [dict get $p tex_assets]]]
            if {[llength [$table selection]]!=1} {error {Select one linked asset to remove}}
            set name [lindex [$table item [lindex [$table selection] 0] -values] 0]
            if {![dict exists $item payload assets $name]} {error {Selected asset is no longer linked}}
            set expected [_viewerGuiTeXStamp $item]
            if {[tk_messageBox -parent $window -type yesno -default no -icon question -title {Remove article asset} -message "Remove the linked asset '$name' from this article?"] ne {yes}} {return [dict create status cancelled]}
            set item [_viewerGuiTeXCurrent $window $form]
            if {[_viewerGuiTeXStamp $item] ne $expected} {error {Article changed during confirmation; select the asset again}}
            set assets [dict get $item payload assets];dict unset assets $name
            _viewerGuiTeXSaveAssets $window $form $assets
            return [dict create status removed filename $name]
        }
        export_tex - export_pdf - export_assets {
            set item [_viewerGuiTeXCurrent $window $form]
            if {[_viewerGuiTeXDirty $window $form]} {error {Save the edited source before exporting its exact revision}}
            set kind [expr {$operation eq {export_pdf} ? {pdf} : {source}}]
            set extension [expr {$kind eq {pdf} ? {.pdf} : {.tex}}]
            set path [workspaceSaveFile export_dir -parent $window -title {Export exact article revision and linked assets} -defaultextension $extension -initialfile "[dict get $item name]$extension"]
            if {$path eq {}} {return [dict create status cancelled]}
            set expected [_viewerGuiTeXStamp $item]
            set assets [dict get $item payload assets]
            set collisions [_viewerGuiTeXExportCollisions $path $assets];set policy create_only
            if {[dict size $collisions]} {
                set names [dict keys $collisions]
                set message "Replace all [llength $names] existing files in this export bundle?\n[join [lrange $names 0 19] \n]"
                if {[llength $names]>20} {append message "\nAdditional [expr {[llength $names]-20}] files in the selected article's linked-asset paths will also be replaced."}
                if {[tk_messageBox -parent $window -type yesno -default no -icon question -title {Replace article export bundle} -message $message] ne {yes}} {return [dict create status cancelled]}
                set policy replace
            }
            set item [_viewerGuiTeXCurrent $window $form]
            if {[_viewerGuiTeXStamp $item] ne $expected || [_viewerGuiTeXDirty $window $form]} {error {Article changed during export selection; select Export again}}
            if {[_viewerGuiTeXExportCollisions $path $assets] ne $collisions} {error {Export destinations changed during confirmation; select Export again}}
            return [interactiveDocumentTeXExport [dict get $item workspace_id] $kind $path $policy 1]
        }
        import_source {
            if {![_viewerGuiTeXPrepare $window $form]} {return [dict create status cancelled]}
            set path [workspaceOpenFile acquisition_dir -parent $window -title {Import UTF-8 TeX article} -filetypes {{{TeX source} {.tex}}}]
            if {$path eq {}} {return [dict create status cancelled]}
            _viewerGuiTeXRecord $window $form
            if {![file isfile $path] || [file type $path] ne {file} || [file size $path]>16777216} {error {Select a regular TeX file within 16 MiB}}
            set channel [open $path rb];try {set bytes [read $channel 16777217]} finally {close $channel}
            set source [encoding convertfrom utf-8 $bytes]
            if {[encoding convertto utf-8 $source] ne $bytes} {error {TeX source must contain exact UTF-8}}
            set name [sessionWorkspaceAvailableName [file rootname [file tail $path]]]
            set r [_viewerGuiTeXAssociationPrepare $window $form]
            set item [interactiveDocumentTeXCreate [dict get $r provider] $name]
            interactiveDocumentTeXSave [dict get $item workspace_id] $source {}
            return [_viewerGuiTeXOpen $window $form [dict get $item workspace_id]]
        }
        default {error {TeX command must be new, open, save, build, rebuild, cancel, import_assets, remove_asset, export_tex, export_pdf, export_assets, refresh, preview, import_source or diagnostic_open}}
    }
}
