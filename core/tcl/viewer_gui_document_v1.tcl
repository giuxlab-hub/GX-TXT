# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative bindings to existing read-only Dataset document/paging owners.
# No file reader, decoder, cache, source editor or publication authority here.
proc ::GX::viewerGuiDocumentRelease {window component} {
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
        default {error {Document kind must be html, pdf, code or table}}
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
    if {$kind eq {html}} {
        text $widget.content -wrap word -state disabled
        ttk::scrollbar $widget.scroll -command [list $widget.content yview]
        $widget.content configure -yscrollcommand [list $widget.scroll set]
        datasetDocumentRender $widget.content $id
        set controls [documentPresentationZoomControls $widget.zoom $widget.content]
        grid $controls -row 0 -column 0 -columnspan 2 -sticky ew
        grid $widget.content -row 1 -column 0 -sticky nsew
        grid $widget.scroll -row 1 -column 1 -sticky ns
        grid columnconfigure $widget 0 -weight 1;grid rowconfigure $widget 1 -weight 1
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
    if {![dict exists $::GX::ViewerGui::instances $window document_watch]} {dict set ::GX::ViewerGui::instances $window document_watch [after 1000 [list ::GX::_viewerGuiDocumentWatch $window]]}
    set receipt [dict create status bound dataset_id $id content_kind $kind source_sha256 [dict get $payload sha256] read_only 1 owner [dict get {html document_source_api_v1.tcl pdf dataset_viewer_api_v1.tcl code source_surface_api_v1.tcl table dataset_preview_paging_v1.tcl} $kind]]
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
