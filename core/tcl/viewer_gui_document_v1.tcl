# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative bindings to existing read-only Dataset document/paging owners.
# No file reader, decoder, cache, source editor or publication authority here.
namespace eval ::GX::MarkdownHost {variable serial 0;variable result}
proc ::GX::_viewerGuiMarkdownMount {window component widget {datasetId {}}} {
    set definition [viewerGuiDesignComponent $window $component]
    set properties [dict get $definition properties]
    set kind [dict get $properties kind]
    if {$datasetId ne {} && ![viewerGuiDocumentCompatible $datasetId $kind]} {error {Document component requires its matching canonical Dataset}}
    foreach child [winfo children $widget] {destroy $child}
    set module [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] actor_module [dict get $::GX::ViewerGui::instances $window module]]
    set capability [dict get [_datasetPrivateModuleContext $module] capability]
    set options [dict create mode [datasetPublicationV2DictDefault $properties mode read_only] \
        pane [datasetPublicationV2DictDefault $properties pane rendered] dataset_id $datasetId \
        capability $capability toolbar 0 on_change [list ::GX::_viewerGuiMarkdownChanged $window $component] on_command [list ::GX::_viewerGuiMarkdownHostCommand $window $component]]
    if {$kind eq {uml}} {
        dict set options kind uml
        dict set options pane [datasetPublicationV2DictDefault $properties pane diagram]
        set operations [dict get $::GX::ViewerGui::instances $window uml_operations]
        if {[dict get $::GX::ViewerGui::instances $window mode] eq {demo}} {set operations {umlDocumentRead umlDocumentParse umlDocumentLayout umlDocumentEdit}}
        dict set options uml_operations $operations
    }
    set handle [documentEditorMount $widget.document $options]
    pack $widget.document -fill both -expand 1
    dict set ::GX::ViewerGui::instances $window document_editors $component $handle
    if {$kind eq {uml}} {dict set ::GX::ViewerGui::instances $window uml_history_document_stamp $component [_viewerGuiUmlHistoryStamp [documentEditorCommand $handle inspect]]}
    if {[dict get $options mode] eq {editable}} {
        ttk::label $widget.identity -anchor w -justify left -padding {6 3} -wraplength 650
        pack $widget.identity -side top -fill x -before $widget.document
        bind $widget.identity <Configure> [list $widget.identity configure -wraplength %w]
        dict set ::GX::ViewerGui::instances $window document_identity_widgets $component $widget.identity
        _viewerGuiMarkdownFeedback $window $component [documentEditorCommand $handle inspect]
    }
    return $handle
}
proc ::GX::_viewerGuiMarkdownFeedback {window component receipt} {
    if {![dict exists $::GX::ViewerGui::instances $window document_identity_widgets $component]} return
    set label [dict get $::GX::ViewerGui::instances $window document_identity_widgets $component]
    if {![winfo exists $label]} return
    set id [dict get $receipt dataset_id]
    set source [expr {$id eq {} ? {New document (no canonical Dataset)} : $id}]
    set state [expr {[dict get $receipt dirty] ? {Modified draft} : ($id eq {} ? {New draft} : {Document saved})}]
    set permission [expr {[dict get $receipt can_replace] ? {Save Existing available} : {Publish New available}}]
    if {$::GX::currentSession eq {}} {set permission {Open a Session to publish}}
    if {[dict get $receipt status] eq {session_changed}} {set state {Session changed — draft retained};set permission {Reopen before saving}}
    $label configure -text "Document: $source\n$state · $permission"
}
proc ::GX::_viewerGuiMarkdownChanged {window component handle receipt} {
    if {![dict exists $::GX::ViewerGui::instances $window document_editors $component] || [dict get $::GX::ViewerGui::instances $window document_editors $component] ne $handle} return
    if {[datasetPublicationV2DictDefault $receipt kind markdown] eq {uml}} {
        set stamp [_viewerGuiUmlHistoryStamp $receipt]
        set previous [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] uml_history_document_stamp {}] $component $stamp]
        if {$previous ne $stamp && ![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {
            scientificHistoryViewerRecordOperation $window "Edit UML $component"
        }
        dict set ::GX::ViewerGui::instances $window uml_history_document_stamp $component $stamp
    }
    viewerGuiTraceEmit $window $component source_changed $receipt
    _viewerGuiMarkdownFeedback $window $component $receipt
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerGuiUmlHistoryStamp {receipt} {
    set stamp {};foreach key {source_sha256 dataset_id sha256 revision} {lappend stamp [datasetPublicationV2DictDefault $receipt $key {}]}
    return $stamp
}
proc ::GX::_viewerGuiUmlHistoryBeforeSave {window} {
    if {![dict exists $::GX::ScientificHistory::viewers $window]} return
    dict for {component handle} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] document_editors {}] {
        set record [_documentEditorRecord $handle]
        if {[datasetPublicationV2DictDefault [dict get $record options] kind markdown] eq {uml} && [dict get $record options mode] eq {editable}} {
            # Save must commit the same current cursor/panels/viewport intent
            # that its existing History will later restore. No canonical write.
            scientificHistoryViewerRecordOperation $window {Save UML draft presentation}
            break
        }
    }
}
proc ::GX::_viewerGuiMarkdownZoomHandler {instance action} {
    if {$action ni {fit zoom_in zoom_out} || [dict get $instance mode] ne {runtime}
        || ![dict exists $instance handlers $action] || ![dict exists $instance design handlers $action]
        || [dict get $instance design handlers $action effect] ne {presentation}
        || ![dict size [datasetPublicationV2DictDefault $instance document_editors {}]]} {return 0}
    if {$action eq {fit}} {
        set editors [dict get $instance document_editors]
        if {[dict size $editors]!=1} {return 0}
        set record [_documentEditorRecord [lindex [dict values $editors] 0]]
        if {[datasetPublicationV2DictDefault [dict get $record options] kind markdown] ne {uml}} {return 0}
    }
    # Preserve existing reserved Plot/Native viewport navigation. A document-only
    # client can own its explicitly declared native presentation commands.
    foreach item [dict get $instance design components] {
        if {[dict get $item type] in {plot native2d native3d}} {return 0}
    }
    return 1
}
proc ::GX::viewerGuiDesignResourceLeaseAcquire {window} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer resource handoff requires its current Session}}
    set owners {}
    try {
        dict for {component handle} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] document_editors {}] {
            set record [_documentEditorRecord $handle]
            set previous {}
            foreach assets [list [dict get $record assets] [datasetPublicationV2DictDefault [dict get $record baseline] assets {}]] {
                if {![dict size $assets] || $assets eq $previous} continue
                set previous $assets
                _documentAssetsValidate $assets
                # Existing Document deletion closes its readers. Hold draft
                # AND baseline references in ordinary CORE asset carriers
                # BEFORE destroying the old editor; no body or byte copy.
                set owner [_datasetDocumentAssetOwnerCreate core.document_source viewer_handoff [dict create operation viewer_handoff component $component]]
                lappend owners $owner
                set id [dict get $owner document_id]
                set payload [dict get [interactiveDocumentRead $id] payload]
                dict set payload retained_assets $assets
                interactiveDocumentUpdate $id $payload
            }
        }
        return $owners
    } on error {message options} {
        viewerGuiDesignResourceLeaseRelease $owners
        return -options $options $message
    }
}
proc ::GX::viewerGuiDesignResourceLeaseRelease {owners} {
    # The replacement must adopt these references before release. On a failed
    # replacement the host restores its prior draft while the carrier is live.
    foreach owner $owners {_datasetDocumentAssetOwnerClose core.document_source $owner}
}
proc ::GX::_viewerGuiMarkdownHostCommand {window component handle operation} {
    if {![dict exists $::GX::ViewerGui::instances $window document_editors $component] || [dict get $::GX::ViewerGui::instances $window document_editors $component] ne $handle} {error {Document command belongs to another or closed host}}
    set admitted {save_existing publish_new zoom_in zoom_out zoom_reset}
    set record [_documentEditorRecord $handle]
    if {[datasetPublicationV2DictDefault [dict get $record options] kind markdown] eq {uml} && [dict get $record options mode] eq {editable}} {lappend admitted new open}
    if {$operation ni $admitted} {error {Document focused command is outside its finite host contract}}
    if {![dict exists $::GX::ViewerGui::instances $window design handlers $operation]} {error {Document save command is not declared in the parent Viewer}}
    return [viewerGuiDesignAction $window $operation]
}
proc ::GX::_viewerGuiMarkdownCapture {window} {
    if {![dict exists $::GX::ViewerGui::instances $window document_editors]} return
    set drafts {};set umlDrafts {}
    dict for {component handle} [dict get $::GX::ViewerGui::instances $window document_editors] {
        set definition [viewerGuiDesignComponent $window $component]
        if {[datasetPublicationV2DictDefault [dict get $definition properties] mode read_only] eq {editable}} {
            if {[dict get $definition properties kind] eq {uml}} {dict set umlDrafts $component [documentEditorCommand $handle capture]} else {dict set drafts $component [documentEditorCommand $handle capture]}
        }
    }
    dict set ::GX::ViewerGui::instances $window domain_state markdown_drafts $drafts
    if {[dict size $umlDrafts]} {dict set ::GX::ViewerGui::instances $window domain_state uml_drafts $umlDrafts
    } elseif {[dict exists $::GX::ViewerGui::instances $window domain_state uml_drafts]} {dict unset ::GX::ViewerGui::instances $window domain_state uml_drafts}
}
proc ::GX::_viewerGuiMarkdownRestore {window state} {
    dict for {component draft} [datasetPublicationV2DictDefault $state uml_drafts {}] {
        set definition [viewerGuiDesignComponent $window $component]
        if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne {uml} || [datasetPublicationV2DictDefault [dict get $definition properties] mode read_only] ne {editable}} {error {Saved UML draft requires its declared editable document}}
        documentEditorCommand [dict get $::GX::ViewerGui::instances $window document_editors $component] restore $draft
    }

    dict for {component draft} [datasetPublicationV2DictDefault $state markdown_drafts {}] {
        set definition [viewerGuiDesignComponent $window $component]
        if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne {markdown} || [datasetPublicationV2DictDefault [dict get $definition properties] mode read_only] ne {editable}} {error {Saved Markdown draft requires its declared editable document}}
        set handle [dict get $::GX::ViewerGui::instances $window document_editors $component]
        documentEditorCommand $handle restore $draft
    }
}
proc ::GX::_viewerGuiMarkdownChoose {window title prompt values} {
    variable ::GX::MarkdownHost::serial
    variable ::GX::MarkdownHost::result
    set dialog $window.markdown_choose[incr serial]
    set result($dialog) {}
    toplevel $dialog;wm title $dialog $title;wm transient $dialog $window
    ttk::label $dialog.prompt -text $prompt -wraplength 480
    if {$values eq {}} {ttk::entry $dialog.value -width 48} else {ttk::combobox $dialog.value -values $values -state readonly -width 48;$dialog.value set [lindex $values 0]}
    ttk::frame $dialog.buttons
    ttk::button $dialog.buttons.ok -text OK -command [list ::GX::_viewerGuiMarkdownChooseAccept $dialog]
    ttk::button $dialog.buttons.cancel -text Cancel -command [list destroy $dialog]
    pack $dialog.prompt $dialog.value -fill x -padx 12 -pady 8
    pack $dialog.buttons.ok $dialog.buttons.cancel -side left -padx 4
    pack $dialog.buttons -anchor e -padx 8 -pady 8
    bind $dialog <Return> [list ::GX::_viewerGuiMarkdownChooseAccept $dialog]
    bind $dialog <Escape> [list destroy $dialog]
    wm protocol $dialog WM_DELETE_WINDOW [list destroy $dialog]
    focus $dialog.value;grab $dialog;tkwait window $dialog
    set value $result($dialog);unset result($dialog)
    return $value
}
proc ::GX::_viewerGuiMarkdownChooseAccept {dialog} {
    set ::GX::MarkdownHost::result($dialog) [$dialog.value get]
    destroy $dialog
}
proc ::GX::viewerGuiDesignDocumentCommand {window component operation} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the Viewer}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ni {markdown uml}} {error {Document commands require a declared Markdown or UML document}}
    set handle [dict get $::GX::ViewerGui::instances $window document_editors $component]
    set receipt [documentEditorCommand $handle inspect]
    set kind [dict get $definition properties kind];set title [expr {$kind eq {uml}?{UML}:{Markdown}}]
    set request {}
    if {$kind eq {uml} && $operation in {export_source export_png export_svg}} {
        set format [string range $operation 7 end]
        set extension [expr {$format eq {source}?{puml}:$format}]
        set expected [dict get $receipt source_sha256]
        set destination [tk_getSaveFile -parent $window -title "Export UML $format" -defaultextension .$extension -filetypes [list [list "UML $format" .$extension]]]
        if {$destination eq {}} {return $receipt}
        if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window document_editors $component] || [dict get $::GX::ViewerGui::instances $window document_editors $component] ne $handle || [dict get [documentEditorCommand $handle inspect] source_sha256] ne $expected} {error {UML source or Session changed while choosing the export destination}}
        set artifact [documentEditorCommand $handle export [dict create format $format]]
        try {
            set publication [filePublicationCopy [dict get $artifact path] $destination [dict get $artifact sha256] replace]
            return [dict merge [dict remove $artifact allocation path] [dict create status exported publication $publication]]
        } finally {umlDocumentExportRelease $artifact}
    }
    if {$operation in {new new_sequence open} && [dict get $receipt dirty]} {
        set answer [tk_messageBox -parent $window -icon question -type yesnocancel -message {Save the document draft before continuing?}]
        if {$answer eq {cancel}} {return $receipt}
        if {$answer eq {yes}} {
            set save [expr {[dict get $receipt can_replace]?{save_existing}:{publish_new}}]
            viewerGuiDesignDocumentCommand $window $component $save
            if {[dict get [documentEditorCommand $handle inspect] dirty]} {return $receipt}
        }
        dict set request discard_confirmed 1
    }
    if {$operation eq {open}} {
        set choices [uiFieldDatasetChoices $kind]
        if {![llength $choices]} {error "No canonical $title Dataset is available in this Session"}
        set id [_viewerGuiMarkdownChoose $window "Open $title Document" "Choose a canonical $title Dataset." $choices]
        if {$id eq {}} {return $receipt}
        dict set request dataset_id $id
    } elseif {$operation eq {publish_new}} {
        set snapshot [documentEditorCommand $handle capture]
        set baseline [dict get $snapshot baseline]
        if {$baseline eq {}} {set summary {No canonical Dataset is selected.}
        } else {set summary "Source Dataset: [dict get $baseline dataset_id]\nProducer: [dict get $baseline producer]\nImmutable: [dict get $baseline immutable]"}
        append summary "\n\nPublish New creates a separate canonical Dataset and keeps the source.\nReview the new destination Dataset ID:"
        set id [_viewerGuiMarkdownChoose $window "Publish $title Document" $summary {}]
        if {$id eq {}} {return $receipt}
        dict set request dataset_id $id
    }
    if {![viewerGuiDesignGuard $window]} {error {Session changed while choosing a document}}
    if {[catch {set result [documentEditorCommand $handle $operation $request]} reason options]} {
        if {$operation ne {save_existing}} {return -options $options $reason}
        set answer [tk_messageBox -parent $window -icon warning -type yesno -default no -title {Save Existing was refused} -message "$reason\n\nThe draft is retained. Publish it as a new Dataset instead?"]
        if {$answer ne {yes}} {return [documentEditorCommand $handle inspect]}
        return [viewerGuiDesignDocumentCommand $window $component publish_new]
    }
    _viewerGuiMarkdownCapture $window
    return $result
}
proc ::GX::viewerGuiDocumentRelease {window component} {
    if {[dict exists $::GX::ViewerGui::instances $window document_editors $component]} {
        set handle [dict get $::GX::ViewerGui::instances $window document_editors $component]
        dict unset ::GX::ViewerGui::instances $window document_editors $component
        catch {documentEditorCommand $handle dispose}
    }
    if {[dict exists $::GX::ViewerGui::instances $window document_html_controls $component]} {
        dict unset ::GX::ViewerGui::instances $window document_html_controls $component
    }
    if {[dict exists $::GX::ViewerGui::instances $window document_html $component]} {
        set handle [dict get $::GX::ViewerGui::instances $window document_html $component]
        dict unset ::GX::ViewerGui::instances $window document_html $component
        catch {::GX::HTMLViewer::detach $handle}
    }
    if {![dict exists $::GX::ViewerGui::instances $window document_readers $component]} return
    set owner [dict get $::GX::ViewerGui::instances $window document_readers $component]
    dict unset ::GX::ViewerGui::instances $window document_readers $component
    datasetViewerClose $owner
}
proc ::GX::viewerGuiDesignDocumentInspect {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the Viewer}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne {pdf}} {error {PDF inspection requires a declared PDF document component}}
    if {![dict exists $::GX::ViewerGui::instances $window document_readers $component]} {return [dict create content_kind pdf state unbound read_only 1]}
    set owner [dict get $::GX::ViewerGui::instances $window document_readers $component]
    if {[catch {datasetMediaViewerInspect $owner} receipt]} {return [dict create content_kind pdf state closed status $receipt read_only 1]}
    return [dict merge [dict create content_kind pdf] $receipt]
}
proc ::GX::viewerGuiDocumentCompatible {id kind} {
    if {$::GX::currentSession eq {}} {return 0}
    set contract [datasetField $id contract [datasetField $id kind {}]]
    switch $kind {
        markdown {return [expr {[datasetDocumentKind $id] eq {markdown}}]}
        uml {return [expr {[datasetDocumentKind $id] eq {uml}}]}
        html {return [expr {[datasetDocumentKind $id] eq {html}}]}
        pdf {return [expr {$contract eq {document.pdf} && [dict get [datasetViewerDescribe $id] target] eq {pdf}}]}
        code {return [expr {$contract eq {code.source} || ($contract eq {document.text} && [datasetDocumentKind $id] in {{} code xml})}]}
        table {
            if {$contract in {image.raster document.pdf document.text code.source geometry.mesh model.cad} || [string tolower [datasetField $id format {}]] ni {csv tsv hdf5 h5}} {return 0}
            set variables [datasetVariableSchemaV3 $id]
            if {![llength $variables]} {return 0}
            foreach variable $variables {if {[dict get $variable rank] != 1} {return 0}}
            return 1
        }
        default {error {Document kind must be Markdown, HTML, PDF, code or table}}
    }
}
proc ::GX::viewerGuiDesignDocumentBind {window component selector} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the Viewer}}
    set definition [viewerGuiDesignComponent $window $component]
    set choice [viewerGuiDesignComponent $window $selector]
    if {[dict get $definition type] ne {document} || [dict get $choice type] ne {dataset_selector}} {error {Document binding requires declared document and Dataset selector components}}
    set kind [dict get $definition properties kind]
    if {[datasetPublicationV2DictDefault [dict get $choice properties] content_kind {}] ne $kind} {error {Document selector compatibility must match the document kind}}
    set id $::GX::ViewerGui::values($window,$selector)
    return [_viewerGuiDocumentBindDataset $window $component $id]
}
proc ::GX::_viewerGuiDocumentRestoreCheck {window component binding} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the Viewer}}
    return [_viewerGuiDocumentBindingCheck [viewerGuiDesignComponent $window $component] $binding]
}
# Pure source admission shared by normal Restore and explicit Workspace review.
# It never mounts readers/widgets or restores a saved scientific state.
proc ::GX::_viewerGuiDocumentBindingCheck {definition binding} {
    set id [dict get $binding dataset_id]
    if {[dict get $definition type] ne {document} || [dict get $definition properties kind] ne [dict get $binding content_kind] || ![viewerGuiDocumentCompatible $id [dict get $binding content_kind]]} {error {Saved document binding no longer matches its canonical Dataset contract}}
    set payload [sessionInspectionDatasetPayload $id]
    # Runtime Session tokens, file paths and inode stamps are rebuilt by the
    # existing reader. Scientific identity/schema/content must remain exact.
    if {[dict get $payload sha256] ne [dict get $binding source_sha256]} {error {Saved document Dataset content changed; select and Open it explicitly}}
    set stamp [dict get $binding stamp]
    if {[lindex $stamp 0] eq {remote}} {
        if {[datasetViewerStamp $id [dict get $payload path]] ne $stamp} {error {Saved remote document Dataset revision changed; select and Open it explicitly}}
    } elseif {[sessionInspectionDataset $id] ne [lindex $stamp 0] || [datasetVariableSchemaV3 $id] ne [lindex $stamp 1]} {error {Saved document Dataset identity or variable schema changed; select and Open it explicitly}}
}
proc ::GX::_viewerGuiDocumentBindDataset {window component id} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the Viewer}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {document}} {error {Document binding requires a declared document component}}
    set kind [dict get $definition properties kind]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    viewerGuiDocumentRelease $window $component
    # Clear former content before any new source admission. Empty selection is
    # the ordinary initial consultation state, not a failed compiled event.
    foreach child [winfo children $widget] {destroy $child}
    if {[dict exists $::GX::ViewerGui::instances $window bindings $component]} {dict unset ::GX::ViewerGui::instances $window bindings $component}
    if {$id eq {}} {
        if {$::GX::currentSession eq {}} {
            set prompt "No Session is open. Open a Session to select a canonical $kind Dataset."
        } elseif {![llength [uiFieldDatasetChoices $kind]]} {
            set prompt "No compatible canonical $kind Dataset is available in this Session."
        } else {set prompt {Select a compatible canonical Dataset, then Open.}}
        ttk::label $widget.empty -text $prompt -wraplength 500
        pack $widget.empty -fill both -expand 1 -padx 12 -pady 12
        set receipt [dict create status awaiting_selection content_kind $kind read_only 1]
        viewerGuiTraceEmit $window $component source_changed $receipt
        return $receipt
    }
    if {[catch {
        if {![viewerGuiDocumentCompatible $id $kind]} {error {Select a compatible canonical Dataset in the current Session}}
        set payload [sessionInspectionDatasetPayload $id]
    } reason options]} {
        ttk::label $widget.unavailable -text $reason -wraplength 500
        pack $widget.unavailable -fill both -expand 1 -padx 12 -pady 12
        viewerGuiTraceEmit $window $component source_changed [dict create status unavailable reason $reason]
        return -options $options $reason
    }
    set stamp [datasetViewerStamp $id [dict get $payload path]]
    if {$kind in {markdown uml}} {
        _viewerGuiMarkdownMount $window $component $widget $id
    } elseif {$kind eq {html}} {
        set documentWindowId [winfo id $window];set documentWidgetId [winfo id $widget]
        set handle {}
        if {[catch {
            ttk::frame $widget.controls
            ttk::frame $widget.controls.navigation
            ttk::frame $widget.controls.magnification
            ttk::frame $widget.content
            ttk::label $widget.status -text {Loading HTML document} -wraplength 500
            foreach {action label} {back Back forward Forward home Home reload Reload stop Stop} {
                ttk::button $widget.controls.$action -text $label -state disabled
                pack $widget.controls.$action -in $widget.controls.navigation -side left -padx 2
            }
            ttk::label $widget.controls.zoomLabel -text {Zoom:}
            foreach {action label} {smaller Smaller larger Larger reset Reset} {
                ttk::button $widget.controls.$action -text $label -state disabled
            }
            ttk::combobox $widget.controls.zoom -state disabled -width 5 -values {50 75 100 125 150 175 200 225 250 275 300}
            pack $widget.controls.zoomLabel $widget.controls.smaller $widget.controls.zoom $widget.controls.larger $widget.controls.reset -in $widget.controls.magnification -side left -padx 2
            pack $widget.controls.navigation $widget.controls.magnification -side top -fill x -pady 2
            pack $widget.controls -side top -fill x
            pack $widget.status -side bottom -fill x
            pack $widget.content -fill both -expand 1
            set attached [::GX::HTMLViewer::attach $widget.content [dict create purpose dataset]]
            set handle [dict get $attached handle]
            dict set ::GX::ViewerGui::instances $window document_html $component $handle
            set ids {}
            foreach path [concat [list $window $widget $widget.content $widget.status $widget.controls $widget.controls.navigation $widget.controls.magnification $widget.controls.zoomLabel] [lmap name {back forward home reload stop smaller larger reset zoom} {set path $widget.controls.$name}]] {dict set ids $path [winfo id $path]}
            set context [dict create window $window widget $widget handle $handle widget_ids $ids session [interactiveDocumentSessionToken] viewer_token [dict get $::GX::ViewerGui::instances $window token] dataset_id $id source_sha256 [dict get $payload sha256] path [dict get $payload path] stamp $stamp generation [expr {[dict get $attached generation]+1}]]
            dict set ::GX::ViewerGui::instances $window document_html_controls $component [dict create context $context pending {}]
            foreach action {back forward home reload stop} {$widget.controls.$action configure -command [list ::GX::_viewerGuiHtmlNavigate $window $component $context $action]}
            foreach action {smaller larger reset} {$widget.controls.$action configure -command [list ::GX::_viewerGuiHtmlZoom $window $component $context $action]}
            bind $widget.controls.zoom <<ComboboxSelected>> [list ::GX::_viewerGuiHtmlZoom $window $component $context choice]
            bind $widget.content <<GXHTMLChanged>> [list ::GX::_viewerGuiHtmlChanged $window $component $context %d]
            bind $widget.content <Destroy> [list ::GX::_viewerGuiHtmlDestroyed $window $component $context %W]
            ::GX::HTMLViewer::load $handle [dict create kind dataset dataset_id $id]
        } reason]} {
            if {$handle ne {}} {
                if {[dict exists $::GX::ViewerGui::instances $window document_html $component] && [dict get $::GX::ViewerGui::instances $window document_html $component] eq $handle} {viewerGuiDocumentRelease $window $component
                } else {catch {::GX::HTMLViewer::detach $handle}}
            }
            if {[winfo exists $window] && [winfo id $window] eq $documentWindowId && [winfo exists $widget] && [winfo id $widget] eq $documentWidgetId} {
                foreach name {back forward home reload stop smaller larger reset zoom} {
                    if {[winfo exists $widget.controls.$name]} {$widget.controls.$name configure -state disabled}
                }
                if {[winfo exists $widget.status]} {$widget.status configure -text {Interactive HTML is unavailable in this installation.}}
                viewerGuiTraceEmit $window $component source_changed [dict create status unavailable content_kind html reason $reason read_only 1]
            }
            return [dict create status unavailable content_kind html read_only 1]
        }
    } elseif {$kind eq {table}} {
        pack [datasetPreviewCreateTable $widget.table $::GX::currentSession $id] -fill both -expand 1
    } elseif {$kind eq {code}} {
        set read [datasetDocumentRead $id 4194304]
        set notice [expr {[dict get $read complete] ? {Read-only canonical source; execution and Save disabled.} : {First 4 Mi characters only; original source preserved.}}]
        set text [sourceSurfaceCreate $widget.source [dict create mode read_only language [sourceSurfaceDatasetLanguage $id] notice $notice find_bar 1]]
        pack $widget.source -fill both -expand 1
        sourceSurfaceSet $text [dict get $read source]
    } else {
        # The existing dedicated PDF viewer owns pages/navigation/zoom/decoder.
        # Reuse its established official read-only open route, with no OCR.
        set reader [datasetMediaViewerOpen $id pdf]
        # Runtime-only owner association; never part of saved canonical bindings.
        dict set ::GX::ViewerGui::instances $window document_readers $component $reader
        ttk::label $widget.opened -text "PDF opened in the CORE read-only reader: $id" -wraplength 500
        pack $widget.opened -fill x -padx 12 -pady 12
    }
    dict set ::GX::ViewerGui::instances $window bindings $component [dict create kind document content_kind $kind dataset_id $id session [interactiveDocumentSessionToken] path [dict get $payload path] stamp $stamp source_sha256 [dict get $payload sha256]]
    if {$kind in {markdown uml} && [datasetPublicationV2DictDefault [dict get $definition properties] mode read_only] eq {editable}} {
        # The shared editor retains its own immutable source snapshot and draft.
        # External edits make Save stale; they must never destroy this draft.
        dict unset ::GX::ViewerGui::instances $window bindings $component
    }
    if {![dict exists $::GX::ViewerGui::instances $window document_watch]} {dict set ::GX::ViewerGui::instances $window document_watch [after 1000 [list ::GX::_viewerGuiDocumentWatch $window]]}
    set receipt [dict create status bound dataset_id $id content_kind $kind source_sha256 [dict get $payload sha256] read_only [expr {$kind ni {markdown uml} || [datasetPublicationV2DictDefault [dict get $definition properties] mode read_only] ne {editable}}] owner [dict get {uml uml_document_api_v1.tcl markdown document_source_api_v1.tcl html html_viewer_api_v1.tcl pdf dataset_viewer_api_v1.tcl code source_surface_api_v1.tcl table dataset_preview_paging_v1.tcl} $kind]]
    viewerGuiTraceEmit $window $component source_changed $receipt
    return $receipt
}
proc ::GX::_viewerGuiDocumentWatch window {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} return
    dict unset ::GX::ViewerGui::instances $window document_watch
    dict for {id binding} [dict get $::GX::ViewerGui::instances $window bindings] {
        if {[datasetPublicationV2DictDefault $binding kind {}] ne {document}} continue
        if {[catch {
            if {[dict get $binding session] ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Viewer.}}
            if {[datasetViewerStamp [dict get $binding dataset_id] [dict get $binding path]] ne [dict get $binding stamp]} {error {Canonical Dataset revision changed; select and Open again.}}
        } reason]} {
            set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
            viewerGuiDocumentRelease $window $id
            foreach child [winfo children $widget] {destroy $child}
            ttk::label $widget.stale -text $reason -wraplength 500
            pack $widget.stale -fill both -expand 1
            dict unset ::GX::ViewerGui::instances $window bindings $id
            viewerGuiTraceEmit $window $id source_changed [dict create status stale reason $reason]
        }
    }
    dict set ::GX::ViewerGui::instances $window document_watch [after 1000 [list ::GX::_viewerGuiDocumentWatch $window]]
}

# All controls remain inside the existing typed owner. Pure value predicates
# below are also used by bounded source-only tests; they confer no GUI authority.
proc ::GX::_viewerGuiHtmlContextMatch {expected current} {
    foreach key {window widget handle widget_ids session viewer_token} {
        if {![dict exists $current $key] || [dict get $current $key] ne [dict get $expected $key]} {return 0}
    }
    return 1
}
proc ::GX::_viewerGuiHtmlReceiptMatch {context receipt {allowUnbound 0}} {
    foreach key {handle generation state source zoom_percent completed_request_id} {if {![dict exists $receipt $key]} {return 0}}
    if {[dict get $receipt handle] ne [dict get $context handle]} {return 0}
    if {![string is integer -strict [dict get $receipt generation]] || [dict get $receipt state] ni {starting loading ready unavailable closing closed stale}} {return 0}
    set zoom [dict get $receipt zoom_percent]
    if {![string is integer -strict $zoom] || $zoom<50 || $zoom>300 || $zoom%25} {return 0}
    if {$allowUnbound && [dict get $receipt source] eq {} && [dict get $receipt generation]==0 && [dict get $receipt state] in {starting loading}} {return 1}
    if {[dict get $receipt generation] ne [dict get $context generation]} {return 0}
    set source [dict get $receipt source]
    foreach key {kind dataset_id source_sha256} {if {![dict exists $source $key]} {return 0}}
    return [expr {[dict get $source kind] eq {dataset} && [dict get $source dataset_id] eq [dict get $context dataset_id] && [dict get $source source_sha256] eq [dict get $context source_sha256]}]
}
proc ::GX::_viewerGuiHtmlZoomTarget {percent action {choice {}}} {
    if {![string is integer -strict $percent] || $percent<50 || $percent>300 || $percent%25} {error {Invalid actual HTML zoom}}
    switch -- $action {
        smaller {return [expr {max(50,$percent-25)}]}
        larger {return [expr {min(300,$percent+25)}]}
        reset {return 100}
        choice {
            if {![string is integer -strict $choice] || $choice<50 || $choice>300 || $choice%25} {error {Invalid selected HTML zoom}}
            return $choice
        }
        default {error {Unknown HTML zoom control}}
    }
}
proc ::GX::_viewerGuiHtmlZoomPending {pending context receipt} {
    set result [dict create pending $pending error {}]
    if {$pending eq {} || ![_viewerGuiHtmlReceiptMatch $context $receipt]} {return $result}
    if {[dict get $receipt state] in {unavailable closed stale}} {
        return [dict create pending {} error presentation_unavailable]
    }
    # A later resize, visibility or unsolicited receipt cannot complete zoom.
    if {[dict get $receipt completed_request_id] ne [dict get $pending request_id]} {return $result}
    dict set result pending {}
    if {([dict exists $receipt last_error] && [dict get $receipt last_error] ne {}) || [dict get $receipt zoom_percent] ne [dict get $pending percent]} {dict set result error zoom_not_confirmed}
    return $result
}
proc ::GX::_viewerGuiHtmlOwned {window component context} {
    if {[catch {
        set instance [dict get $::GX::ViewerGui::instances $window]
        if {[dict get $instance document_html_controls $component context] ne $context || [dict get $instance widgets $component] ne [dict get $context widget]} {return 0}
        set ids {}
        foreach path [dict keys [dict get $context widget_ids]] {
            if {![winfo exists $path]} {return 0}
            dict set ids $path [winfo id $path]
        }
        set current [dict create window $window widget [dict get $instance widgets $component] handle [dict get $instance document_html $component] widget_ids $ids session [dict get $context session] viewer_token [dict get $instance token]]
        set owned [_viewerGuiHtmlContextMatch $context $current]
    } result]} {return 0}
    return $owned
}
proc ::GX::_viewerGuiHtmlCurrent {window component context} {
    if {![_viewerGuiHtmlOwned $window $component $context]} {return {}}
    if {[catch {
        if {![viewerGuiDesignGuard $window] || [interactiveDocumentSessionToken] ne [dict get $context session] || [datasetViewerStamp [dict get $context dataset_id] [dict get $context path]] ne [dict get $context stamp]} {error {HTML source or Session changed}}
        set receipt [::GX::HTMLViewer::inspect [dict get $context handle]]
        if {![_viewerGuiHtmlReceiptMatch $context $receipt 1]} {error {HTML presentation identity changed}}
    }]} {return {}}
    return $receipt
}
proc ::GX::_viewerGuiHtmlDisable {window component context} {
    if {![_viewerGuiHtmlOwned $window $component $context]} return
    set widget [dict get $context widget]
    foreach name {back forward home reload stop smaller larger reset zoom} {$widget.controls.$name configure -state disabled}
}
proc ::GX::_viewerGuiHtmlAbandon {window component context text} {
    if {![_viewerGuiHtmlOwned $window $component $context]} return
    _viewerGuiHtmlDisable $window $component $context
    [dict get $context widget].status configure -text $text
    viewerGuiDocumentRelease $window $component
}
proc ::GX::_viewerGuiHtmlDestroyed {window component context actual} {
    if {$actual ne "[dict get $context widget].content"} return
    if {[dict exists $::GX::ViewerGui::instances $window document_html_controls $component context] && [dict get $::GX::ViewerGui::instances $window document_html_controls $component context] eq $context} {viewerGuiDocumentRelease $window $component}
}
proc ::GX::_viewerGuiHtmlNavigate {window component context action} {
    set receipt [_viewerGuiHtmlCurrent $window $component $context]
    if {$receipt eq {}} {_viewerGuiHtmlAbandon $window $component $context {HTML source or Session changed; reopen the current document.};return}
    if {![_viewerGuiHtmlReceiptMatch $context $receipt] || [dict get $receipt state] ni {ready loading}} return
    set pending [dict get $::GX::ViewerGui::instances $window document_html_controls $component pending]
    if {$action ne {stop} && ($pending ne {} || [dict get $receipt state] ne {ready})} return
    if {[catch {::GX::HTMLViewer::navigate [dict get $context handle] [dict create action $action]}]} {
        if {[_viewerGuiHtmlOwned $window $component $context]} {[dict get $context widget].status configure -text {HTML navigation is unavailable; reopen the current document.}}
    }
}
proc ::GX::_viewerGuiHtmlZoom {window component context action} {
    set receipt [_viewerGuiHtmlCurrent $window $component $context]
    if {$receipt eq {}} {_viewerGuiHtmlAbandon $window $component $context {HTML source or Session changed; reopen the current document.};return}
    if {![_viewerGuiHtmlReceiptMatch $context $receipt] || [dict get $receipt state] ne {ready}} return
    set widget [dict get $context widget]
    set choice [$widget.controls.zoom get]
    # A combobox edit is a requested value, never an observed native zoom.
    $widget.controls.zoom set [dict get $receipt zoom_percent]
    if {[dict get $::GX::ViewerGui::instances $window document_html_controls $component pending] ne {}} return
    if {[catch {set percent [_viewerGuiHtmlZoomTarget [dict get $receipt zoom_percent] $action $choice]}]} return
    if {[catch {
        set requested [::GX::HTMLViewer::navigate [dict get $context handle] [dict create action zoom percent $percent]]
        if {![_viewerGuiHtmlOwned $window $component $context]} return
        set request [dict get $requested request_id]
        if {$request eq {}} {error {Missing HTML zoom request identity}}
        dict set ::GX::ViewerGui::instances $window document_html_controls $component pending [dict create request_id $request percent $percent]
        _viewerGuiHtmlChanged $window $component $context {}
    }]} {
        if {[_viewerGuiHtmlOwned $window $component $context]} {
            _viewerGuiHtmlAbandon $window $component $context {HTML zoom is unavailable; reopen the current document.}
        }
    }
}
proc ::GX::_viewerGuiHtmlChanged {window component context eventData} {
    if {![_viewerGuiHtmlOwned $window $component $context]} return
    set receipt [_viewerGuiHtmlCurrent $window $component $context]
    set widget [dict get $context widget]
    if {$receipt eq {}} {
        _viewerGuiHtmlAbandon $window $component $context {HTML source or Session changed; reopen the current document.}
        return
    }
    if {[dict get $receipt state] in {unavailable closing closed stale}} {
        _viewerGuiHtmlAbandon $window $component $context {Interactive HTML is unavailable; reopen the current document.}
        return
    }
    set error {}
    if {![catch {dict size $eventData}] && [dict exists $eventData receipt]} {
        set snapshot [dict get $eventData receipt]
        if {![catch {set next [_viewerGuiHtmlZoomPending [dict get $::GX::ViewerGui::instances $window document_html_controls $component pending] $context $snapshot]}]} {
            dict set ::GX::ViewerGui::instances $window document_html_controls $component pending [dict get $next pending]
            set error [dict get $next error]
        }
    }
    set pending [dict get $::GX::ViewerGui::instances $window document_html_controls $component pending]
    set admitted [_viewerGuiHtmlReceiptMatch $context $receipt]
    set ready [expr {$admitted && [dict get $receipt state] eq {ready}}]
    foreach name {back forward home reload} {
        set enabled [expr {$ready && $pending eq {}}]
        if {$name in {back forward}} {set enabled [expr {$enabled && [dict get $receipt can_$name]}]}
        $widget.controls.$name configure -state [expr {$enabled?{normal}:{disabled}}]
    }
    $widget.controls.stop configure -state [expr {$admitted && [dict get $receipt state] in {ready loading}?{normal}:{disabled}}]
    foreach name {smaller larger reset} {
        set enabled [expr {$ready && $pending eq {}}]
        if {$name eq {smaller} && [dict get $receipt zoom_percent]==50} {set enabled 0}
        if {$name eq {larger} && [dict get $receipt zoom_percent]==300} {set enabled 0}
        $widget.controls.$name configure -state [expr {$enabled?{normal}:{disabled}}]
    }
    $widget.controls.zoom configure -state [expr {$ready && $pending eq {}?{readonly}:{disabled}}]
    $widget.controls.zoom set [expr {$admitted?[dict get $receipt zoom_percent]:{}}]
    $widget.status configure -text [expr {$error ne {}?{HTML zoom was not confirmed; use the current observed zoom or reopen the document.}:[dict get $receipt status]}]
    viewerGuiTraceEmit $window $component presentation_changed $receipt
}
