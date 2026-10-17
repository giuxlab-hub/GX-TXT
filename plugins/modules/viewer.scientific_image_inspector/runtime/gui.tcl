# Scientific Image Inspector Tk frontend. English-only user-visible strings.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {variable ui; array set ui {}}
proc ::GX::SII::guiError {message} {
    variable ui
    if {[info exists ui(status)]} {set ui(status) "Error: $message"}
    tk_messageBox -icon error -title {Scientific Image Inspector} -message $message
}
proc ::GX::SII::guiOpen {action scene} {
    variable ui
    package require Tk
    set w .scientific_image_inspector
    if {[winfo exists $w]} {
        wm deiconify $w
        raise $w
        if {$action eq "rerender"} {refreshSources}
        # Session Workspace Manager opens through the same Viewer backend.
        # An already-open toplevel must honor the requested exact Workspace.
        if {[dict exists $scene open_context workspace_id]} {
            workspaceOpen [dict get $scene open_context]
        } elseif {[dict exists $scene open_context dataset_id]} {
            set requested [dict get $scene open_context dataset_id]
            if {$requested ne {} && [lsearch -exact [datasetIds] $requested]>=0} {
                set ui(sourceId) $requested
                loadSource
            }
        }
        return $w
    }
    set ui(window) $w
    set ui(sourceId) ""
    set ui(documentId) ""
    set ui(workspaceName) ""
    set ui(workspaceDraft) 1
    set ui(steps) {}
    set ui(redo) {}
    set ui(roi) {}
    set ui(scope) all
    set ui(op) ""
    set ui(search) ""
    set ui(outputId) image.processed
    set ui(outputFormat) tiff16
    set ui(status) {Select an image.raster Dataset to inspect.}
    set ui(report) ""
    set ui(compare) 0
    set ui(pendingSteps) {}
    set ui(pending) 0
    set ui(target) Working
    set ui(grid) 0
    set ui(sync) 0
    set ui(figurePreviewActive) 0
    set ui(panels) {}
    set ui(annotations) {}
    set ui(annotationSerial) 0
    set ui(annotationActiveId) {}
    set ui(selectedAnnotationIds) {}
    set ui(selectionMode) object
    set ui(editDomain) image
    set ui(annotationClipboard) {}
    set ui(annotating) 0
    set ui(showAnnotationCoordinates) [annotationCoordinatePreference]
    set ui(annotationTool) Select
    set ui(annotationTransform) none
    set ui(canvasMode) view
    set ui(imageAnnotations) {}
    set ui(figureAnnotations) {}
    set ui(figureUndo) {}
    set ui(figureRedo) {}
    set ui(historyTimeline) {}
    set ui(historyBrowsing) 0
    set ui(historyCursor) 0
    set ui(historyStripView) Description
    set ui(historyStripVisible) 1
    set ui(zoom-original) 1.0
    set ui(zoom-processed) 1.0
    set ui(sessionToken) [::GX::interactiveDocumentSessionToken]
    set ui(cleanFiles) {}
    toplevel $w
    wm title $w {Scientific Image Inspector — GX-TXT}
    wm geometry $w 1420x850
    wm minsize $w 980 620
    wm protocol $w WM_DELETE_WINDOW ::GX::SII::guiClose
    createMenus $w
    ttk::frame $w.head -padding 5
    pack $w.head -side top -fill x
    ttk::label $w.head.l -text {Source Dataset:}
    ttk::combobox $w.head.ds -textvariable ::GX::SII::ui(sourceId) -width 42 -state readonly
    ttk::button $w.head.refresh -text Refresh -command ::GX::SII::refreshSources
    ttk::button $w.head.preview -text {Refresh image} -command ::GX::SII::renderImages
    ttk::button $w.head.fit -text {Fit view} -command ::GX::SII::fitViews
    ttk::button $w.head.original -text {Compare} -command ::GX::SII::toggleCompare
    ttk::button $w.head.approve -text {Accept preview} -command ::GX::SII::acceptPreview -state disabled
    ttk::button $w.head.discard -text {Discard preview} -command ::GX::SII::discardPreview -state disabled
    ttk::button $w.head.cancel -text {Cancel operation} -command ::GX::SII::cancel
    pack $w.head.l $w.head.ds $w.head.refresh $w.head.preview $w.head.fit $w.head.original $w.head.approve $w.head.discard $w.head.cancel -side left -padx 3
    bind $w.head.ds <<ComboboxSelected>> ::GX::SII::loadSource
    ttk::panedwindow $w.layout -orient horizontal
    pack $w.layout -fill both -expand yes
    # One scrollable inspector column. No list/navigation pane, Notebook, or
    # mutually exclusive pages: selected sections are stacked at full width.
    ttk::frame $w.layout.inspector -width 340
    ttk::frame $w.layout.main
    $w.layout add $w.layout.inspector -weight 0
    $w.layout add $w.layout.main -weight 1
    set inspector $w.layout.inspector
    canvas $inspector.scroll -highlightthickness 0 -borderwidth 0 \
        -background [ttk::style lookup TFrame -background]
    ttk::scrollbar $inspector.yscroll -orient vertical \
        -command [list $inspector.scroll yview]
    $inspector.scroll configure -yscrollcommand [list $inspector.yscroll set]
    pack $inspector.yscroll -side right -fill y
    pack $inspector.scroll -side left -fill both -expand yes
    set tab $inspector.tabs
    ttk::frame $tab
    set ui(sidebarWindow) [$inspector.scroll create window 0 0 -anchor nw -window $tab]
    bind $inspector.scroll <Configure> {::GX::SII::sidebarCanvasResize %w}
    bind $tab <Configure> ::GX::SII::sidebarContentResize
    # Native2D image canvases retain their own wheel bindings. The Viewer-level
    # fallback acts only on widgets belonging to the left inspector.
    bind $w <MouseWheel> {::GX::SII::sidebarWheel %W %D}
    bind $w <Button-4> {::GX::SII::sidebarWheel %W 120}
    bind $w <Button-5> {::GX::SII::sidebarWheel %W -120}
    foreach {id label} [sidebarCatalog] {
        ttk::labelframe $tab.$id -text $label -padding 6
    }
    buildSimpleTab $tab.simple
    buildFigureTab $tab.figure
    buildAnnotationsTab $tab.annotations
    buildSourceTab $tab.source
    buildAnalysisTab $tab.analyze
    # Operation catalog is hosted directly by Editor > Advanced; no duplicate.
    buildHistoryTab $tab.history
    buildPublishTab $tab.publish
    set ui(sidebarTabs) [sidebarConfiguredTabs]
    set ui(sidebarTemporary) {}
    sidebarRefresh
    set panes $w.layout.main.panes
    ttk::panedwindow $panes -orient horizontal
    pack $panes -fill both -expand yes
    foreach which {original processed} {
        ttk::frame $panes.$which
        $panes add $panes.$which -weight 1
        ttk::label $panes.$which.title -text [expr {$which eq "original" ? "Working image (accepted edits)" : "Adjustment preview (not accepted)"}] -anchor center
        pack $panes.$which.title -side top -fill x
        canvas $panes.$which.canvas -background #252a30 -highlightthickness 0 -cursor crosshair
        pack $panes.$which.canvas -fill both -expand yes
        bind $panes.$which.canvas <ButtonPress-2> [list ::GX::SII::guardEvent {Pan start} [list ::GX::SII::panStart $which %x %y]]
        bind $panes.$which.canvas <B2-Motion> [list ::GX::SII::guardEvent {Pan movement} [list ::GX::SII::panDrag $which %x %y]]
        # Right button belongs to the object's context menu (Curve Workbench model).
        # Middle button remains the ordinary image pan gesture.
        if {$which eq "original"} {
            bind $panes.$which.canvas <ButtonPress-3> {::GX::SII::guardEvent {Annotation context menu} [list ::GX::SII::workingCanvasContext %x %y %X %Y]}
        }
        # Pointer-centred zoom. Windows/macOS MouseWheel and X11 Button-4/5.
        bind $panes.$which.canvas <MouseWheel> "[list ::GX::SII::guardEvent {Wheel zoom} [list ::GX::SII::wheel $which %D %x %y]]; break"
        bind $panes.$which.canvas <Button-4> "[list ::GX::SII::guardEvent {Wheel zoom} [list ::GX::SII::wheel $which 120 %x %y]]; break"
        bind $panes.$which.canvas <Button-5> "[list ::GX::SII::guardEvent {Wheel zoom} [list ::GX::SII::wheel $which -120 %x %y]]; break"
        bind $panes.$which.canvas <Motion> [list ::GX::SII::guardEvent {Cursor inspection} [list ::GX::SII::showCursor $which %x %y]]
        if {$which eq "original"} {
            bind $panes.$which.canvas <ButtonPress-1> {::GX::SII::guardEvent {Annotation select / draw} [list ::GX::SII::canvasStart %x %y %s]}
            bind $panes.$which.canvas <B1-Motion> {::GX::SII::guardEvent {Annotation drag} [list ::GX::SII::canvasDrag %x %y]}
            bind $panes.$which.canvas <ButtonRelease-1> {::GX::SII::guardEvent {Annotation release} [list ::GX::SII::canvasCommit %x %y]}
            bind $panes.$which.canvas <Double-Button-1> {::GX::SII::guardEvent {Annotation double-click} [list ::GX::SII::canvasDoubleClick %x %y]}
        }
    }
    nativeCanvasCreate
    $panes forget $panes.processed
    if {[llength [info commands ::GX::sessionWorkspaceViewerTitle]]} {
        ::GX::sessionWorkspaceViewerTitle $w {Scientific Image Inspector — GX-TXT} \
            ::GX::SII::workspaceCurrent ::GX::SII::workspaceDraftName
    }
    ttk::label $w.footer -textvariable ::GX::SII::ui(status) -anchor w -padding 6
    pack $w.footer -fill x -side bottom
    historyStripCreate $w
    bind $w <F1> ::GX::SII::openManual
    bind $w <Escape> ::GX::SII::annotationEscape
    bind $w <Control-z> {::GX::SII::editUndo}
    bind $w <Control-y> {::GX::SII::editRedo}
    bind $w <Control-a> {::GX::SII::editSelectAll}
    bind $w <Control-c> {::GX::SII::editCopy}
    bind $w <Control-v> {::GX::SII::editPaste}
    bind $w <Control-Shift-Z> ::GX::SII::undoFigure
    bind $w <Control-Shift-Y> ::GX::SII::redoFigure
    refreshSources
    annotationMode 0
    if {[dict exists $scene open_context]} {
        set ctx [dict get $scene open_context]
        if {[dict exists $ctx workspace_id]} {
            workspaceOpen $ctx
            return $w
        }
        set wanted [get $ctx dataset_id ""]
        if {$wanted ne "" && [lsearch -exact [datasetIds] $wanted] >= 0} {
            set ui(sourceId) $wanted
            loadSource
        }
    }
    return $w
}
proc ::GX::SII::createMenus {w} {
    menu $w.menu
    $w configure -menu $w.menu
    foreach m {File Edit View Image Analyze History Workspace Configuration Help} {
        set k [string tolower $m]
        menu $w.menu.$k -tearoff 0
        $w.menu add cascade -label $m -menu $w.menu.$k
    }
    $w.menu.file add command -label {Refresh Source Datasets} -command ::GX::SII::refreshSources
    $w.menu.file add command -label {Copy Technical Report} -command ::GX::SII::copyReport
    $w.menu.file add separator
    $w.menu.file add command -label Close -command ::GX::SII::guiClose
    foreach {label shortcut action} {
        {Select All Annotations} Ctrl+A editSelectAll
        {Select None} {} editSelectNone
        {Copy Selected Annotations} Ctrl+C editCopy
        {Paste Annotations} Ctrl+V editPaste
        {Undo} Ctrl+Z editUndo
        {Redo} Ctrl+Y editRedo
    } {
        if {$label in {{Copy Selected Annotations} {Undo}}} {$w.menu.edit add separator}
        $w.menu.edit add command -label $label -accelerator $shortcut -command ::GX::SII::$action
    }
    $w.menu.view add checkbutton -label {Synchronized comparison} -variable ::GX::SII::ui(sync)
    $w.menu.view add checkbutton -label {Pixel grid} -variable ::GX::SII::ui(grid) -command ::GX::SII::displayBoth
    $w.menu.view add checkbutton -label {Show Description / History strip} -variable ::GX::SII::ui(historyStripVisible) -command ::GX::SII::historyStripShow
    $w.menu.view add command -label {Fit to window} -command ::GX::SII::fitViews
    $w.menu.view add command -label {Show / Hide pending adjustment} -command ::GX::SII::toggleCompare
    $w.menu.view add command -label {Actual display pixels (1:1 LOD preview)} -command ::GX::SII::actualPreviewPixels
    $w.menu.image add command -label {Basic Editor} -command {::GX::SII::editorSwitch basic}
    $w.menu.image add command -label {Advanced Editor} -command {::GX::SII::editorSwitch advanced}
    $w.menu.image add command -label {Figure Studio} -command {::GX::SII::sidebarSelect figure}
    $w.menu.image add command -label {Edit source image} -command ::GX::SII::editSourceImage
    $w.menu.image add checkbutton -label {Annotation mode} -variable ::GX::SII::ui(annotating) -command ::GX::SII::annotationModeChanged
    $w.menu.image add command -label {Annotation tools...} -command {::GX::SII::annotationMode 1}
    $w.menu.image add command -label {Image Information} -command ::GX::SII::showDetailed
    $w.menu.image add command -label {Restore original (keep source Dataset)} -command ::GX::SII::reset
    $w.menu.analyze add command -label {Compute statistics} -command ::GX::SII::computeStats
    $w.menu.analyze add command -label {Compute histogram} -command ::GX::SII::computeHistogram
    $w.menu.analyze add command -label {Read pixel at ROI origin} -command ::GX::SII::pixelRoi
    $w.menu.history add command -label {Edit annotations} -command {::GX::SII::annotationMode 1}
    $w.menu.history add command -label {Undo Figure Edit} -accelerator Ctrl+Shift+Z -command ::GX::SII::undoFigure
    $w.menu.history add command -label {Redo Figure Edit} -accelerator Ctrl+Shift+Y -command ::GX::SII::redoFigure
    $w.menu.history add separator
    $w.menu.history add command -label Undo -accelerator Ctrl+Z -command ::GX::SII::undo
    $w.menu.history add command -label Redo -accelerator Ctrl+Y -command ::GX::SII::redo
    # The Workspace menu delegates ownership, names, duplication and manager
    # actions to GX-TXT's existing SESSION_WORKSPACE_API_v1.
    if {[llength [info commands ::GX::sessionWorkspaceViewerMenu]]} {
        ::GX::sessionWorkspaceViewerMenu $w.menu.workspace scientific_image_inspector \
            [dict create current ::GX::SII::workspaceCurrent save ::GX::SII::saveState \
                         close ::GX::SII::workspaceClose open ::GX::SII::workspaceOpen] $w
    } else {
        $w.menu.workspace add command -label {Workspace API unavailable} -state disabled
    }
    $w.menu.history add separator
    $w.menu.history add command -label {Accept adjustment preview} -command ::GX::SII::acceptPreview
    $w.menu.history add command -label {Discard adjustment preview} -command ::GX::SII::discardPreview
    $w.menu.history add command -label {Restore original image} -command ::GX::SII::reset
    $w.menu.history add command -label {Save workspace} -command ::GX::SII::saveState
    $w.menu.configuration add command -label {Visible sidebar sections...} -command ::GX::SII::sidebarPreferencesDialog
    $w.menu.configuration add separator
    $w.menu.configuration add command -label {Viewer settings...} -command ::GX::SII::viewerSettingsDialog
    $w.menu.help add command -label {User Manual...} -accelerator F1 -command ::GX::SII::openManual
    $w.menu.help add separator
    $w.menu.help add command -label {About Scientific Image Inspector...} -command ::GX::SII::showAbout
}
# Sidebar visibility is a registered GX-TXT Configuration module field.
# Persistent choices select which panels are *stacked*, not which page replaces
# all the others. Menu access can temporarily reveal an unselected section.
proc ::GX::SII::sidebarCatalog {} {
    return {simple Editor figure Figures annotations Annotations source {Image Info} analyze Colors history History publish Publish}
}
proc ::GX::SII::sidebarConfigurationId {} {
    set fields [::GX::configurationModuleFields viewer.scientific_image_inspector]
    dict for {id descriptor} $fields {
        if {[dict get $descriptor module_key] eq "sidebar_tabs"} {return $id}
    }
    error {GX-TXT did not register the sidebar_tabs Configuration field}
}
proc ::GX::SII::sidebarConfiguredTabs {} {
    set default {simple figure}
    if {[llength [info commands ::GX::configurationResolve]]} {
        if {![catch {set conf [::GX::configurationResolve [sidebarConfigurationId]]}] && [dict exists $conf effective]} {
            set value [split [dict get $conf effective] ,]
            set result {}
            foreach item $value {
                # Previous versions exposed Advanced as an independent sidebar
                # section. Migrate the projection without rewriting User config.
                if {$item eq "operations"} {set item simple}
                if {[dict exists [sidebarCatalog] $item] && $item ni $result} {lappend result $item}
            }
            if {[llength $result]} {return $result}
        }
    }
    return $default
}
proc ::GX::SII::sidebarValidSections {selected} {
    set valid {}
    foreach id $selected {
        if {![dict exists [sidebarCatalog] $id]} {error "Unknown Workspace sidebar section: $id"}
        if {$id ni $valid} {lappend valid $id}
    }
    if {![llength $valid]} {error {Workspace must show at least one sidebar section}}
    return $valid
}
proc ::GX::SII::sidebarContentResize {} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set canvas $ui(window).layout.inspector.scroll
    $canvas configure -scrollregion [$canvas bbox all]
}
proc ::GX::SII::sidebarCanvasResize {width} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set canvas $ui(window).layout.inspector.scroll
    $canvas itemconfigure $ui(sidebarWindow) -width [expr {max(160, $width)}]
    sidebarContentResize
}
proc ::GX::SII::sidebarRefresh {} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set inspector $ui(window).layout.inspector
    set tabs $inspector.tabs
    set canvas $inspector.scroll
    set prior [lindex [$canvas yview] 0]
    set ui(sidebarOrder) {}
    foreach {id label} [sidebarCatalog] {
        set panel $tabs.$id
        pack forget $panel
        if {$id in $ui(sidebarTabs) || $id in $ui(sidebarTemporary)} {
            pack $panel -side top -fill x -expand 0 -anchor n -padx 4 -pady 4
            lappend ui(sidebarOrder) $id
        }
    }
    sidebarContentResize
    $canvas yview moveto $prior
}
proc ::GX::SII::sidebarReveal {id} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set canvas $ui(window).layout.inspector.scroll
    set tab $ui(window).layout.inspector.tabs
    set panel $tab.$id
    if {[winfo manager $panel] ne "pack"} return
    update idletasks
    set height [winfo height $tab]
    if {$height < 1} return
    # Scroll to the heading; preserving the single shared scrollable column.
    $canvas yview moveto [expr {double([winfo y $panel]) / $height}]
}
proc ::GX::SII::sidebarSelect {id} {
    if {$id eq "operations"} {editorSwitch advanced;return}
    if {$::GX::SII::ui(pending)} return
    variable ui
    if {![dict exists [sidebarCatalog] $id]} {error {Unknown sidebar section}}
    if {$id ni $ui(sidebarTabs) && $id ni $ui(sidebarTemporary)} {
        lappend ui(sidebarTemporary) $id
        sidebarRefresh
    }
    sidebarReveal $id
}
proc ::GX::SII::sidebarWheel {widget delta} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)] || $delta == 0} return
    set inspector $ui(window).layout.inspector
    if {$widget ne $inspector && ![string match "${inspector}.*" $widget]} return
    set canvas $inspector.scroll
    $canvas yview scroll [expr {$delta > 0 ? -3 : 3}] units
}
proc ::GX::SII::sidebarPreferencesDialog {} {
    variable ui
    set w $ui(window).sidebarPrefs
    if {[winfo exists $w]} {raise $w;return}
    toplevel $w
    wm title $w {Visible sidebar sections}
    wm transient $w $ui(window)
    ttk::label $w.tip -text {Choose visible panels for this Workspace. Apply changes immediately; hidden panels remain available from the menus.} -wraplength 300
    pack $w.tip -fill x -padx 12 -pady 10
    foreach {id label} [sidebarCatalog] {
        set ui(pref-$id) [expr {$id in $ui(sidebarTabs)}]
        ttk::checkbutton $w.$id -text $label -variable ::GX::SII::ui(pref-$id)
        pack $w.$id -anchor w -padx 14 -pady 2
    }
    ttk::frame $w.buttons;pack $w.buttons -fill x -pady 10 -padx 8
    ttk::button $w.buttons.save -text Apply -command ::GX::SII::sidebarPreferencesSave
    ttk::button $w.buttons.cancel -text Close -command [list destroy $w]
    pack $w.buttons.save $w.buttons.cancel -side left -padx 4
}
proc ::GX::SII::sidebarPreferencesSave {} {
    variable ui
    set selected {}
    foreach {id label} [sidebarCatalog] {
        if {$ui(pref-$id)} {lappend selected $id}
    }
    if {![llength $selected]} {guiError {Choose at least one visible section};return}
    # Apply immediately. Workspace is the authority for this Viewer-specific
    # layout. CORE SESSION_WORKSPACE_API_v1 persists its editable payload.
    # Avoid changing the global GX-TXT User defaults or another Workspace.
    set ui(sidebarTabs) $selected
    set ui(sidebarTemporary) {}
    sidebarRefresh
    if {$ui(sourceId) ne {} && [info exists ui(info)]} {
        if {![saveState]} {
            set ui(status) {Sidebar changed in memory, but Workspace save failed. Use Workspace > Save after resolving the error.}
            return 0
        }
        set ui(status) {Sidebar layout applied and saved to current Workspace.}
    } else {
        set ui(status) {Sidebar layout applied. It will be saved when an image Workspace is created.}
    }
    return 1
}
proc ::GX::SII::buildSourceTab {f} {
    ttk::label $f.label -text {Canonical image information and source metadata} -wraplength 350
    pack $f.label -fill x
    text $f.report -height 28 -width 35 -wrap word -state disabled
    ttk::scrollbar $f.v -orient vertical -command [list $f.report yview]
    $f.report configure -yscrollcommand [list $f.v set]
    pack $f.v -side right -fill y
    pack $f.report -fill both -expand yes
    ttk::frame $f.buttons
    pack $f.buttons -fill x
    ttk::button $f.buttons.details -text {Full metadata} -command ::GX::SII::showDetailed
    ttk::button $f.buttons.copy -text Copy -command ::GX::SII::copyReport
    pack $f.buttons.details $f.buttons.copy -side left -padx 2
}
proc ::GX::SII::buildAnalysisTab {f} {
    ttk::label $f.disclaimer -text {Analysis target is explicit: Working = accepted edits on the main canvas; Source = immutable source Dataset; Preview = unaccepted right-hand candidate. Encoded pixel values are not calibrated reflectance, absorbance or concentration. Histograms are 8-bit bins over all pixels in the selected area.} -wraplength 330
    pack $f.disclaimer -fill x -pady 4
    ttk::frame $f.controls
    pack $f.controls -fill x
    ttk::label $f.controls.t -text Image
    ttk::combobox $f.controls.target -values {Working Source Preview} -state readonly -width 9 -textvariable ::GX::SII::ui(target)
    set ::GX::SII::ui(target) Working
    ttk::label $f.controls.l -text Channel
    ttk::combobox $f.controls.channel -values {All Gray R G B A} -state readonly -textvariable ::GX::SII::ui(channel) -width 7
    set ::GX::SII::ui(channel) All
    ttk::button $f.controls.stats -text Statistics -command ::GX::SII::computeStats
    ttk::button $f.controls.hist -text Histogram -command ::GX::SII::computeHistogram
    pack $f.controls.t $f.controls.target $f.controls.l $f.controls.channel $f.controls.stats $f.controls.hist -side left -padx 2
    ttk::frame $f.quant
    pack $f.quant -fill x -pady 2
    ttk::label $f.quant.l -text {Quantized colors:}
    ttk::combobox $f.quant.n -values {8 16 32 64 128} -state readonly -width 5 -textvariable ::GX::SII::ui(paletteCount)
    set ::GX::SII::ui(paletteCount) 16
    ttk::button $f.quant.palette -text {Dominant palette} -command ::GX::SII::computePalette
    ttk::button $f.quant.channel -text {Preview channel} -command ::GX::SII::channelPreview
    pack $f.quant.l $f.quant.n $f.quant.palette $f.quant.channel -side left -padx 2
    ttk::checkbutton $f.useRoi -text {Analyze selected ROI (Working image only)} -variable ::GX::SII::ui(analysisUseRoi)
    set ::GX::SII::ui(analysisUseRoi) 0
    pack $f.useRoi -anchor w -pady 4
    ttk::label $f.roi -textvariable ::GX::SII::ui(roiLabel)
    set ::GX::SII::ui(roiLabel) {ROI: none (whole image)}
    pack $f.roi -fill x -pady 5
    canvas $f.chart -width 300 -height 155 -background white
    pack $f.chart -fill x
    text $f.result -height 16 -wrap word -width 35
    pack $f.result -fill both -expand 1
}
proc ::GX::SII::buildOperationsTab {f} {
    ttk::label $f.tip -text {Operations execute in order. Select a validated operation; forms are generated from the catalog.} -wraplength 330
    pack $f.tip -fill x
    ttk::entry $f.search -textvariable ::GX::SII::ui(search)
    pack $f.search -fill x -pady 5
    bind $f.search <KeyRelease> ::GX::SII::populateCatalog
    ttk::treeview $f.catalog -columns {family state} -show {tree headings} -height 12 -selectmode browse
    $f.catalog heading #0 -text Operation
    $f.catalog heading family -text Category
    $f.catalog heading state -text Status
    $f.catalog column #0 -width 140
    $f.catalog column family -width 85
    $f.catalog column state -width 80
    pack $f.catalog -fill both -expand 1
    bind $f.catalog <<TreeviewSelect>> ::GX::SII::selectOperation
    ttk::label $f.about -textvariable ::GX::SII::ui(operationAbout) -wraplength 330
    set ::GX::SII::ui(operationAbout) {Choose an operation above.}
    pack $f.about -fill x -pady 3
    ttk::labelframe $f.parameters -text Parameters
    pack $f.parameters -fill x
    ttk::frame $f.scope
    pack $f.scope -fill x -pady 3
    ttk::radiobutton $f.scope.all -text {Whole image} -variable ::GX::SII::ui(scope) -value all
    ttk::radiobutton $f.scope.roi -text {Selected ROI} -variable ::GX::SII::ui(scope) -value roi
    pack $f.scope.all $f.scope.roi -side left
    ttk::button $f.apply -text {Add processing step} -command ::GX::SII::addStep
    pack $f.apply -fill x -pady 4
    populateCatalog
}
proc ::GX::SII::buildHistoryTab {f} {
    ttk::label $f.intro -text {Reproducible ordered processing recipe. Removing a step never edits the canonical source.} -wraplength 330
    pack $f.intro -fill x
    listbox $f.steps -height 17
    pack $f.steps -fill both -expand yes -pady 6
    ttk::frame $f.buttons
    pack $f.buttons -fill x
    foreach {key name cmd} {undo Undo undo redo Redo redo remove {Remove selected} removeStep reset Reset reset save Save saveState} {
        ttk::button $f.buttons.$key -text $name -command ::GX::SII::$cmd
        pack $f.buttons.$key -side left -padx 2 -pady 3
    }
    ttk::label $f.label -text {History changes only the working recipe. Restore Original clears accepted processing; the source Dataset remains unchanged. Workspace is saved through GX-TXT.} -wraplength 330
    pack $f.label -fill x
}
proc ::GX::SII::buildPublishTab {f} {
    ttk::label $f.info -text {Publish the accepted working image and editable annotations as a new GX-TXT Dataset. No direct file export. All processing and provenance are stored in the manifest.} -wraplength 330
    pack $f.info -fill x -pady 6
    ttk::label $f.idl -text {New derived Dataset ID}
    ttk::entry $f.id -textvariable ::GX::SII::ui(outputId)
    ttk::label $f.formatl -text {Output format and precision}
    ttk::combobox $f.format -state readonly -values {tiff16 tiff32f png16} -textvariable ::GX::SII::ui(outputFormat)
    ttk::label $f.caveat -text {TIFF 32-bit float conversion uses Q16-HDRI. Lossless scientific fidelity depends on the input decoder and operations; ICC/physical calibration is not added.} -wraplength 330
    ttk::button $f.publish -text {Publish Working Image as Dataset...} -command ::GX::SII::publishDialog
    pack $f.idl $f.id $f.formatl $f.format $f.caveat $f.publish -fill x -pady 5
}
proc ::GX::SII::refreshSources {} {
    variable ui
    if {![info exists ui(window)]} return
    if {[catch {set ids [datasetIds]} msg]} {guiError $msg;return}
    $ui(window).head.ds configure -values $ids
    if {[lsearch -exact $ids $ui(sourceId)] < 0} {
        set ui(sourceId) ""
        set ui(status) {Choose a source image Dataset.}
    }
    # Only an explicit dataset_id open context, a user selection or a named
    # Workspace may choose a source. Never auto-open the first Registry entry.
}
proc ::GX::SII::checkSession {} {
    variable ui
    if {$ui(sessionToken) ne [::GX::interactiveDocumentSessionToken]} {error "GX-TXT Session changed; reopen Scientific Image Inspector."}
}
proc ::GX::SII::loadSource {} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(sourceId) eq ""} return
    if {[catch {
        checkSession
        set ui(info) [inspect $ui(sourceId)]
        discardPreview
        unset -nocomplain ui(restoreSnapshot)
        set ui(steps) {}; set ui(redo) {}; set ui(roi) {}; set ui(scope) all; set ui(documentId) ""
        set ui(roiLabel) {ROI: none (whole image)}
        lodReset
        foreach k {preview-original preview-processed scaled-original scaled-processed photo-original photo-processed processedInfo} {unset -nocomplain ui($k)}
        foreach c {original processed} {$ui(window).layout.main.panes.$c.canvas delete all}
        set ui(originalFile) [dict get $ui(info) path]
        set ui(workingFile) $ui(originalFile)
        set ui(workingInfo) $ui(info)
        set ui(processedFile) $ui(originalFile)
        # Source changes create a fresh draft; persisted Workspaces open explicitly
        # by Workspace ID. Never auto-select another editing history by Dataset.
        set ui(panels) {};set ui(annotations) {}
        set ui(annotationActiveId) {};set ui(selectedAnnotationIds) {}
        set ui(selectionMode) object;set ui(editDomain) image
        set ui(imageAnnotations) {};set ui(figureAnnotations) {}
        set ui(workspaceName) "";set ui(workspaceDraft) 1
        set ui(sidebarTabs) [sidebarConfiguredTabs];set ui(sidebarTemporary) {};sidebarRefresh
        if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {
            ::GX::sessionWorkspaceViewerTitlesRefresh
        }
        set ui(report) [formatReport $ui(info)]
        showReport
        refreshSteps
        refreshPanels;refreshAnnotations
        annotationMode 0
        historyStripReset
        if {[dict get $ui(info) pixel_count] > 25000000} {
            set ui(status) {Large source detected. Metadata loaded without raster decode. Click Generate preview to decode on demand.}
        } else {
            renderImages
        }
    } err]} {guiError $err}
}
proc ::GX::SII::formatReport {info} {
    set lines [list {Scientific Image Inspector — Technical image report} "Generated: [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]" "Source Dataset: [dict get $info id]" "Source SHA-256: [dict get $info sha256]" "Format: [dict get $info format] (ImageMagick: [get $info im_bytes {unavailable}])" "MIME: [get $info media_type {unavailable}]" "Original bytes: [dict get $info size_bytes]" "Dimensions: [dict get $info width] × [dict get $info height]" "Pixels: [dict get $info pixel_count]" "Aspect ratio: [format %.8g [expr {double([dict get $info width])/[dict get $info height]}]]" "Channel layout: [get $info channels unavailable]" "Bit depth: [get $info depth unavailable]" "Colorspace: [get $info colorspace unavailable]" "Type: [get $info type unavailable]" "Orientation: [get $info orientation unavailable]" "Frame/page count: [get $info frame_count unavailable]" "Density: [get $info resolution_x unavailable] × [get $info resolution_y unavailable] [get $info density_units unavailable]" "ImageMagick: [get $info engine unavailable]" {} {Source metadata (GX-TXT Metadata API):}]
    if {![dict size [get $info metadata {}]]} {lappend lines {No structured metadata available.}}
    dict for {k v} [get $info metadata {}] {lappend lines "$k: $v"}
    lappend lines {} {Interpretation: density/DPI does not establish specimen pixel calibration.} {Original metadata and ImageMagick-derived properties are different authorities.}
    return [join $lines \n]
}
proc ::GX::SII::showReport {} {
    variable ui
    set widget $ui(window).layout.inspector.tabs.source.report
    $widget configure -state normal
    $widget delete 1.0 end
    $widget insert end $ui(report)
    $widget configure -state disabled
}
proc ::GX::SII::showDetailed {} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        checkSession
        set full [detailedInfo [dict get $ui(info) path]]
        append ui(report) "\n\nImageMagick-derived detailed properties:\n$full"
        showReport
        sidebarSelect source
    } err]} {guiError $err}
}
proc ::GX::SII::copyReport {} {
    variable ui
    clipboard clear -displayof $ui(window)
    clipboard append -displayof $ui(window) $ui(report)
    set ui(status) {Technical report copied to clipboard.}
}
proc ::GX::SII::guiTemp {suffix} {
    variable ui
    set f [tempFile $suffix]
    lappend ui(cleanFiles) $f
    return $f
}
# Figure preview is an editing view, not a source raster. Switching back
# restores the image annotations and retains the panel recipe in the Workspace.
proc ::GX::SII::editSourceImage {{ask 0}} {
    variable ui
    if {![info exists ui(figurePreviewActive)] || !$ui(figurePreviewActive)} {
        set ui(status) {Already editing the source working image.}
        return 1
    }
    if {$ui(pending)} {
        set ui(status) {Accept or discard the pending image adjustment first.}
        return 0
    }
    if {$ask} {
        set answer [tk_messageBox -parent $ui(window) -title {Edit source image} -type yesno \
            -icon question -message {This Workspace shows a composed figure. Switch to the source working image to apply the adjustment?} \
            -detail {All figure panels and annotations remain in the Workspace; you can preview the composition again from Figures.}]
        if {$answer ne "yes"} {set ui(status) {Adjustment cancelled; figure composition remains visible.};return 0}
    }
    if {[catch {renderImages} err opts]} {
        eventFailure {Switch to source image} $err $opts
        return 0
    }
    set ui(status) {Editing source image. Figure panels and annotations remain in this Workspace.}
    if {$ui(documentId) ne {} && ![saveState]} {
        set ui(status) {Source view restored, but Workspace save failed; save again before closing.}
    }
    return 1
}
proc ::GX::SII::previewSteps {newSteps} {
    variable ui
    if {[historyReadOnly]} {return}
    checkSession
    if {$ui(sourceId) eq ""} {error {Select a canonical image Dataset first}}
    if {$ui(figurePreviewActive)} {
        if {![editSourceImage 1]} {return 0}
    }
    if {$ui(pending)} {error {Accept or discard the pending adjustment before starting another operation}}
    # A filter preview is a separate exclusive mode, never a hidden continuation
    # of annotation editing. Its completion returns to normal image mode.
    annotationMode 0
    set steps [validateSteps [concat $ui(steps) $newSteps]]
    set temporary [guiTemp .miff]
    set picture [guiTemp .png]
    if {[catch {
        processFile $ui(originalFile) $steps $temporary miff
        set details [inspectFile $temporary]
        previewFile $temporary $picture 2400 2400
    } error]} {
        catch {file delete -- $temporary};catch {file delete -- $picture}
        return -code error $error
    }
    set ui(pendingSteps) $steps
    set ui(pending) 1
    pendingUiRefresh
    set ui(processedFile) $temporary
    set ui(processedInfo) $details
    set ui(preview-processed) $picture
    set ui(native-size-processed) {}
    $ui(window).head.approve configure -state normal
    $ui(window).head.discard configure -state normal
    set ui(compare) 0
    toggleCompare
    set ui(status) {Right: pending adjustment; Left: accepted working image. Accept or discard the preview.}
}

# Exclusive processing-preview transaction: do not allow other editing actions,
# source changes, workspace switching or toolbar/filter re-entry while pending.
proc ::GX::SII::pendingUiRefresh {} {
    variable ui
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set locked $ui(pending)
    set w $ui(window)
    foreach name {file edit image analyze operations history workspace configuration} {
        catch {$w.menu entryconfigure [string totitle $name] -state [expr {$locked ? "disabled" : "normal"}]}
    }
    foreach widget [list $w.head.ds $w.head.refresh $w.head.preview] {
        if {$locked} {catch {$widget state disabled}} else {catch {$widget state !disabled}}
    }
    # Disable only actionable controls. Their internal values remain unchanged;
    # this is not a separate model or preferences authority.
    pendingSetChildren $w.layout.inspector.tabs $locked
    if {$locked} {
        set ui(status) {ADJUSTMENT PREVIEW — only zoom, pan, compare, Accept or Discard are available.}
    }
}
proc ::GX::SII::pendingSetChildren {parent locked} {
    variable ui
    foreach child [winfo children $parent] {
        if {[winfo class $child] in {TButton TEntry TCombobox TCheckbutton TRadiobutton TScale TMenubutton TSpinbox}} {
            if {$locked} {
                if {![info exists ui(pendingPrior-$child)]} {set ui(pendingPrior-$child) [expr {[$child instate disabled] ? "disabled" : "enabled"}]}
                $child state disabled
            } else {
                if {[info exists ui(pendingPrior-$child)]} {
                    if {$ui(pendingPrior-$child) eq "enabled"} {$child state !disabled}
                    unset ui(pendingPrior-$child)
                }
            }
        } elseif {[winfo class $child] in {Listbox Text Entry Scale Spinbox}} {
            if {$locked} {
                if {![info exists ui(pendingPrior-$child)]} {set ui(pendingPrior-$child) [$child cget -state]}
                catch {$child configure -state disabled}
            } else {
                if {[info exists ui(pendingPrior-$child)]} {catch {$child configure -state $ui(pendingPrior-$child)};unset ui(pendingPrior-$child)}
            }
        } elseif {[winfo class $child] eq {Treeview}} {
            # Treeview has no disabled state: GUI callbacks check the lock.
        }
        pendingSetChildren $child $locked
    }
}

proc ::GX::SII::acceptPreview {} {
    variable ui
    if {!$ui(pending)} return
    checkSession
    set accepted $ui(pendingSteps)
    set ui(steps) $accepted
    set ui(editDomain) image
    unset -nocomplain ui(restoreSnapshot)
    set ui(redo) {}
    discardPreview
    if {![renderImages]} {error {Unable to render accepted adjustment}}
    refreshSteps
    saveState
}
proc ::GX::SII::discardPreview {} {
    variable ui
    set ui(pending) 0
    set ui(pendingSteps) {}
    pendingUiRefresh
    if {![info exists ui(window)] || ![winfo exists $ui(window)]} return
    set panes $ui(window).layout.main.panes
    if {$ui(compare)} {catch {$panes forget $panes.processed}}
    set ui(compare) 0
    $ui(window).head.approve configure -state disabled
    $ui(window).head.discard configure -state disabled
    if {[info exists ui(workingFile)]} {set ui(processedFile) $ui(workingFile)}
    if {[info exists ui(workingInfo)]} {set ui(processedInfo) $ui(workingInfo)}
    if {[info exists ui(preview-original)]} {set ui(preview-processed) $ui(preview-original)}
    if {[info exists ui(sourceId)] && $ui(sourceId) ne ""} {
        set ui(status) {Working image: accepted operations only; source Dataset unchanged.}
    }
}
proc ::GX::SII::renderImages {} {
    variable ui
    if {$ui(sourceId) eq ""} {return 0}
    if {$ui(pending)} {discardPreview}
    if {$ui(figurePreviewActive)} {
        set ui(figureAnnotations) $ui(annotations)
        set ui(annotations) $ui(imageAnnotations)
    }
    set ui(figurePreviewActive) 0
    set ui(status) {Rendering accepted processing recipe; source Dataset is unchanged.}
    if {[catch {
        checkSession
        set previous [get [array get ui] workingFile {}]
        set working $ui(originalFile)
        if {[llength $ui(steps)]} {
            set working [guiTemp .miff]
            processFile $ui(originalFile) $ui(steps) $working miff
        }
        set ui(workingFile) $working
        set ui(workingInfo) [inspectFile $working]
        set ui(processedFile) $working
        set ui(processedInfo) $ui(workingInfo)
        set preview [guiTemp .png]
        previewFile $working $preview 2400 2400
        lodReset
        set ui(preview-original) $preview
        set ui(preview-processed) $preview
        if {[info exists ui(native-size-original)]} {set ui(native-size-original) {}}
        displayPreview original
        refreshAnnotations
        if {$previous ne {} && $previous ne $ui(originalFile) && $previous ne $working} {catch {file delete -- $previous}}
        set ui(status) "Working image: $ui(sourceId) | [llength $ui(steps)] accepted processing steps | source unchanged"
    } err]} {guiError $err;return 0}
    return 1
}
proc ::GX::SII::displayBoth {} {
    foreach k {original processed} {displayPreview $k}
    drawRoi
}
proc ::GX::SII::displayPreview {which} {
    variable ui
    if {![info exists ui(preview-$which)]} return
    set c $ui(window).layout.main.panes.$which.canvas
    if {![winfo exists $c]} return
    catch {image delete $ui(photo-$which)}
    catch {image delete $ui(scaled-$which)}
    set source [image create photo -file $ui(preview-$which)]
    set ui(photo-$which) $source
    set z $ui(zoom-$which)
    # Rational (integer numerator/denominator) for Tk photo copy, at most 4x.
    set numerator [expr {int(round($z * 8))}]
    if {$numerator < 2} {set numerator 2}
    set scaled [image create photo]
    $scaled copy $source -zoom $numerator $numerator -subsample 8 8
    set ui(scaled-$which) $scaled
    $c delete all
    $c create image 0 0 -image $scaled -anchor nw -tags img
    $c configure -scrollregion [list 0 0 [image width $scaled] [image height $scaled]]
}
proc ::GX::SII::panStart {which x y} {
    variable ui
    $ui(window).layout.main.panes.$which.canvas scan mark $x $y
}
proc ::GX::SII::panDrag {which x y} {
    variable ui
    $ui(window).layout.main.panes.$which.canvas scan dragto $x $y 1
}
proc ::GX::SII::wheel {which delta} {
    variable ui
    set factor [expr {$delta > 0 ? 1.25 : 0.8}]
    set ui(zoom-$which) [expr {max(0.25,min(4.0,$ui(zoom-$which)*$factor))}]
    displayPreview $which
    if {$which eq "processed"} {drawRoi}
}
proc ::GX::SII::fitViews {} {
    variable ui
    foreach which {original processed} {
        if {![info exists ui(photo-$which)]} continue
        set c $ui(window).layout.main.panes.$which.canvas
        set w [expr {max(100,[winfo width $c]-20)}]
        set h [expr {max(100,[winfo height $c]-20)}]
        set ui(zoom-$which) [expr {max(0.25,min(4.0,min(double($w)/[image width $ui(photo-$which)],double($h)/[image height $ui(photo-$which)])))}]
    }
    displayBoth
}
proc ::GX::SII::toggleCompare {} {
    variable ui
    if {!$ui(pending)} {
        set ui(status) {No pending adjustment. Select an operation to generate a comparison preview.}
        return
    }
    set panes $ui(window).layout.main.panes
    if {$ui(compare)} {
        $panes forget $panes.processed
        set ui(compare) 0
    } else {
        $panes add $panes.processed -weight 1
        set ui(compare) 1
        nativeDisplay processed
    }
}
proc ::GX::SII::toImageXY {which x y} {
    variable ui
    set c $ui(window).layout.main.panes.$which.canvas
    if {![info exists ui(scaled-$which)]} {return {}}
    set xCanvas [$c canvasx $x]
    set yCanvas [$c canvasy $y]
    set sw [image width $ui(scaled-$which)]
    set sh [image height $ui(scaled-$which)]
    if {$sw == 0 || $sh == 0 || $xCanvas < 0 || $yCanvas < 0 || $xCanvas >= $sw || $yCanvas >= $sh} {return {}}
    set i [expr {$which eq "original" ? $ui(info) : $ui(processedInfo)}]
    set iw [dict get $i width]
    set ih [dict get $i height]
    return [list [expr {min($iw-1,int(floor($xCanvas*$iw/double($sw))))}] [expr {min($ih-1,int(floor($yCanvas*$ih/double($sh))))}]]
}
proc ::GX::SII::showCursor {which x y} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {set point [toImageXY $which $x $y]}] || $point eq ""} return
    set label [expr {$which eq "original" ? "Working (accepted)" : "Preview (unaccepted)"}]
    set ui(status) "$label pixel (x,y): $point | Wheel zoom · middle-drag pan · right-click object/tools · left-drag select or ROI"
}
proc ::GX::SII::roiStart {x y} {
    variable ui
    set ui(dragStart) [toImageXY original $x $y]
}
proc ::GX::SII::roiDrag {x y} {
    variable ui
    if {![info exists ui(dragStart)] || $ui(dragStart) eq ""} return
    set pt [toImageXY original $x $y]
    if {$pt eq ""} return
    lassign $ui(dragStart) sx sy
    lassign $pt ex ey
    set left [expr {min($sx,$ex)}]
    set top [expr {min($sy,$ey)}]
    set ui(roi) [list $left $top [expr {abs($ex-$sx)+1}] [expr {abs($ey-$sy)+1}]]
    drawRoi
}
proc ::GX::SII::roiFinish {x y} {
    variable ui
    roiDrag $x $y
    unset -nocomplain ui(dragStart)
    if {[llength $ui(roi)] == 4} {
        set ui(scope) roi
        set ui(roiLabel) "ROI: $ui(roi) (working image pixels)"
        set ui(status) "IMAGE ROI selected: $ui(roi) — compatible operations now target this region."
    }
}
proc ::GX::SII::drawRoi {} {
    variable ui
    if {![llength $ui(roi)] || ![info exists ui(scaled-processed)]} return
    set c $ui(window).layout.main.panes.processed.canvas
    $c delete roi
    lassign $ui(roi) x y w h
    if {![info exists ui(processedInfo)]} return
    set info $ui(processedInfo)
    set iw [dict get $info width]
    set ih [dict get $info height]
    set sw [image width $ui(scaled-processed)]
    set sh [image height $ui(scaled-processed)]
    set p1x [expr {double($x)*$sw/$iw}]
    set p1y [expr {double($y)*$sh/$ih}]
    set p2x [expr {double($x+$w)*$sw/$iw}]
    set p2y [expr {double($y+$h)*$sh/$ih}]
    $c create rectangle $p1x $p1y $p2x $p2y -outline yellow -width 2 -tags roi
}
proc ::GX::SII::pixelAt {x y} {
    variable ui
    if {[catch {
        set xy [toImageXY original $x $y]
        if {$xy eq ""} return
        set result [pixel $ui(workingFile) {*}$xy]
        set t $ui(window).layout.inspector.tabs.analyze.result
        $t insert end "\nPixel $xy (accepted working image):\n$result\n"
        sidebarSelect analyze
    } err]} {guiError $err}
}
proc ::GX::SII::pixelRoi {} {
    variable ui
    if {$ui(roi) eq ""} {guiError {Select a ROI first.};return}
    lassign $ui(roi) x y w h
    pixelAtXY $x $y
}
proc ::GX::SII::pixelAtXY {x y} {
    variable ui
    if {[catch {
        set msg [pixel $ui(workingFile) $x $y]
        set w $ui(window).layout.inspector.tabs.analyze.result
        $w insert end "\nPixel $x, $y:\n$msg\n"
    } err]} {guiError $err}
}
proc ::GX::SII::chosenRoi {} {
    variable ui
    if {$ui(scope) eq "roi"} {
        if {$ui(roi) eq ""} {error "Select a region on the working canvas first"}
        return $ui(roi)
    }
    return {}
}
proc ::GX::SII::analysisFile {} {
    variable ui
    switch -- $ui(target) {
        Working {return $ui(workingFile)}
        Source {return $ui(originalFile)}
        Preview {
            if {!$ui(pending)} {error {No pending preview. Choose Working or Source instead.}}
            return $ui(processedFile)
        }
        default {error {Unknown analysis target}}
    }
}
proc ::GX::SII::analysisRoi {} {
    variable ui
    if {!$ui(analysisUseRoi)} {return {}}
    if {$ui(target) ne "Working"} {error {ROI coordinates refer to the Working image. Choose Working or disable ROI analysis.}}
    if {[llength $ui(roi)] != 4} {error {Select a ROI on the Working image before analyzing it}}
    return $ui(roi)
}
proc ::GX::SII::analysisTargetLabel {} {
    variable ui
    if {$ui(target) eq "Working" && $ui(figurePreviewActive)} {
        return {Working figure composition (8-bit preview, not publish resolution)}
    }
    return "$ui(target) image"
}
proc ::GX::SII::computeStats {} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        set roi [analysisRoi]
        set selectedFile [analysisFile]
        if {$ui(target) ne "Working" && $roi ne ""} {error "ROI belongs to the working raster. Choose Whole image for Source or Preview."}
        set d [stats $selectedFile $roi $ui(channel)]
        set w $ui(window).layout.inspector.tabs.analyze.result
        $w delete 1.0 end
        $w insert end "Statistics ([analysisTargetLabel], normalized pixel quantum range 0..1, channel $ui(channel))\nROI: [expr {$roi eq "" ? "whole image" : $roi}]\n"
        dict for {k v} $d {$w insert end "$k = $v\n"}
        sidebarSelect analyze
    } err]} {guiError $err}
}
proc ::GX::SII::computeHistogram {} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        set roi [analysisRoi]
        set selectedChannel [expr {$ui(channel) eq "All" ? "Gray" : $ui(channel)}]
        set selectedFile [analysisFile]
        if {$ui(target) ne "Working" && $roi ne ""} {error "ROI belongs to Working. Choose Whole image for Source or Preview."}
        set d [histogram $selectedFile $selectedChannel $roi]
        set bins [dict get $d bins]
        set total 0
        foreach b $bins {incr total $b}
        set graph $ui(window).layout.inspector.tabs.analyze.chart
        $graph delete all
        set high 1
        foreach v $bins {if {$v > $high} {set high $v}}
        set width [expr {max(280,[winfo width $graph])}]
        set height 150
        for {set i 0} {$i < 256} {incr i} {
            set val [lindex $bins $i]
            set x1 [expr {$i*$width/256.0}]
            set x2 [expr {($i+1)*$width/256.0}]
            set y1 [expr {$height-($val*$height/double($high))}]
            $graph create rectangle $x1 $y1 $x2 $height -outline {} -fill #236898
        }
        set t $ui(window).layout.inspector.tabs.analyze.result
        $t delete 1.0 end
        $t insert end "8-bit binned histogram ([analysisTargetLabel]); channel $selectedChannel\nROI: [expr {$roi eq "" ? "whole image" : $roi}]\nCounted samples: $total\nTotal 256 quantized bins; not a native 16-bit histogram.\n"
        sidebarSelect analyze
    } err]} {guiError $err}
}

proc ::GX::SII::computePalette {} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        set roi [analysisRoi]
        set selectedFile [analysisFile]
        if {$ui(target) ne "Working" && $roi ne ""} {error "ROI belongs to Working. Choose Whole image for Source or Preview."}
        set data [palette $selectedFile $roi $ui(paletteCount)]
        set t $ui(window).layout.inspector.tabs.analyze.result
        $t delete 1.0 end
        $t insert end "Quantized palette ([analysisTargetLabel]), maximum $ui(paletteCount) colors\n"
        $t insert end "The displayed colors are palette estimates, NOT original calibrated measurements.\n\n"
        foreach sample $data {
            lassign $sample count hex
            $t insert end "$hex : $count pixels\n"
        }
        sidebarSelect analyze
    } err]} {guiError $err}
}
proc ::GX::SII::channelPreview {} {
    variable ui
    if {$ui(sourceId) eq ""} return
    if {[catch {
        set chosen $ui(channel)
        if {$chosen eq "All"} {set chosen RGB}
        set args {}
        if {$chosen eq "Gray"} {set args {-colorspace Gray}}
        if {$chosen ni {Gray RGB}} {set args [list -channel $chosen -separate]}
        set file [guiTemp .png]
        run [list [magickPath] {*}[limits] [frame0 [analysisFile]] {*}$args             -thumbnail {1000x800>} -depth 8 PNG:$file] 35000
        set w $ui(window).channelInspection
        catch {destroy $w}
        toplevel $w
        wm title $w "Read-only $chosen channel — [analysisTargetLabel]"
        ttk::label $w.info -text "Display-only, 8-bit channel visualization. Source and working image unchanged."
        pack $w.info -fill x -padx 10 -pady 5
        set ui(channelPhoto) [image create photo -file $file]
        ttk::label $w.image -image $ui(channelPhoto)
        pack $w.image -fill both -expand 1
    } err]} {guiError $err}
}
proc ::GX::SII::populateCatalog {} {
    variable ui
    if {![info exists ui(window)]} return
    set tree $ui(window).layout.inspector.tabs.simple.advanced.operations.catalog
    $tree delete [$tree children {}]
    foreach spec [catalogList $ui(search)] {
        set id [dict get $spec id]
        set state [dict get [operationStatus $id] state]
        $tree insert {} end -id $id -text [dict get $spec label] -values [list [dict get $spec family] $state]
    }
}
proc ::GX::SII::selectOperation {} {
    variable ui
    if {$ui(pending)} return
    set f $ui(window).layout.inspector.tabs.simple.advanced.operations
    set selection [$f.catalog selection]
    if {[llength $selection] != 1} return
    set id [lindex $selection 0]
    set ui(op) $id
    set spec [catalogGet $id]
    set availability [operationStatus $id]
    set ui(operationAbout) "[dict get $spec about] — [dict get $availability state]: [dict get $availability reason]"
    foreach child [winfo children $f.parameters] {destroy $child}
    foreach field [dict get $spec params] {
        lassign $field name type default lo hi choices
        set ui(param-$name) $default
        ttk::frame $f.parameters.$name
        pack $f.parameters.$name -fill x -pady 1
        ttk::label $f.parameters.$name.l -text "[string totitle [string map {_ { }} $name]]:" -width 14
        pack $f.parameters.$name.l -side left
        if {$type eq "enum"} {
            ttk::combobox $f.parameters.$name.e -values $choices -state readonly -width 18 -textvariable ::GX::SII::ui(param-$name)
        } else {
            ttk::entry $f.parameters.$name.e -width 18 -textvariable ::GX::SII::ui(param-$name)
        }
        pack $f.parameters.$name.e -side left -expand yes -fill x
    }
    $f.scope.roi configure -state [expr {[dict get $spec roi] ? "normal" : "disabled"}]
    if {![dict get $spec roi]} {set ui(scope) all}
    $f.apply configure -state [expr {[dict get $availability state] eq "executable" ? "normal" : "disabled"}]
}
proc ::GX::SII::addStep {} {
    variable ui
    if {[historyReadOnly]} {return}
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(op) eq "" || $ui(sourceId) eq ""} return
    if {[catch {
        set spec [catalogGet $ui(op)]
        set params {}
        foreach field [dict get $spec params] {
            set key [lindex $field 0]
            dict set params $key $ui(param-$key)
        }
        set params [validate $ui(op) $params]
        set step [dict create op $ui(op) params $params scope $ui(scope) roi [chosenRoi]]
        previewSteps [list $step]
    } err]} {guiError $err}
}
proc ::GX::SII::refreshSteps {} {
    variable ui
    set w $ui(window).layout.inspector.tabs.history.steps
    $w delete 0 end
    set number 0
    foreach s $ui(steps) {
        set label [dict get [catalogGet [dict get $s op]] label]
        $w insert end "[incr number]. $label ([dict get $s scope]): [dict get $s params]"
    }
}
proc ::GX::SII::undo {} {
    variable ui
    if {[historyReadOnly]} {return}
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(pending)} {discardPreview;return}
    if {![llength $ui(steps)] && [info exists ui(restoreSnapshot)]} {
        set snapshot $ui(restoreSnapshot)
        unset ui(restoreSnapshot)
        set ui(steps) [dict get $snapshot steps]
        set ui(annotations) [dict get $snapshot annotations]
        set ui(imageAnnotations) [dict get $snapshot image_annotations]
        set ui(figureAnnotations) [dict get $snapshot figure_annotations]
        set priorMode [dict get $snapshot canvas_mode]
        set ui(panels) [dict get $snapshot panels]
        dict for {key value} [dict get $snapshot figure_settings] {set ui(figure-$key) $value}
        set ui(figurePreviewActive) 0
        renderImages
        if {$priorMode eq "figure" && [llength $ui(panels)]} {previewFigure}
        refreshSteps;refreshAnnotations;refreshPanels;saveState
        return
    }
    if {![llength $ui(steps)]} return
    lappend ui(redo) [lindex $ui(steps) end]
    set ui(steps) [lrange $ui(steps) 0 end-1]
    renderImages;refreshSteps;saveState
}
proc ::GX::SII::redo {} {
    variable ui
    if {[historyReadOnly]} {return}
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(pending)} {discardPreview;return}
    if {![llength $ui(redo)]} return
    lappend ui(steps) [lindex $ui(redo) end]
    set ui(redo) [lrange $ui(redo) 0 end-1]
    renderImages;refreshSteps;saveState
}
proc ::GX::SII::removeStep {} {
    variable ui
    if {[historyReadOnly]} {return}
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    set sel [$ui(window).layout.inspector.tabs.history.steps curselection]
    if {[llength $sel] != 1} return
    set ui(steps) [lreplace $ui(steps) [lindex $sel 0] [lindex $sel 0]]
    set ui(redo) {}
    renderImages; refreshSteps; saveState
}
proc ::GX::SII::reset {} {
    variable ui
    if {[historyReadOnly]} {return}
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(sourceId) eq ""} return
    if {[llength $ui(steps)] || [llength $ui(annotations)] || [llength $ui(panels)]} {
        set ui(restoreSnapshot) [dict create steps $ui(steps) annotations $ui(annotations) image_annotations $ui(imageAnnotations) figure_annotations $ui(figureAnnotations) canvas_mode [expr {$ui(figurePreviewActive) ? "figure" : "image"}] panels $ui(panels) figure_settings [figureSettings]]
    }
    discardPreview
    set ui(steps) {};set ui(redo) {};set ui(roi) {}
    set ui(annotations) {};set ui(imageAnnotations) {};set ui(figureAnnotations) {}
    set ui(annotationActiveId) {};set ui(selectedAnnotationIds) {}
    set ui(scope) all;set ui(selectionMode) object;set ui(editDomain) image
    set ui(panels) {};set ui(figurePreviewActive) 0
    set ui(roiLabel) {ROI: none (whole working image)}
    renderImages;refreshSteps;refreshPanels;refreshAnnotations;saveState
    set ui(status) {Original image restored in Workspace; source Dataset unchanged. Use Undo to recover previous working state.}
}
proc ::GX::SII::workspaceCurrent {} {
    variable ui
    return [expr {[info exists ui(documentId)] ? $ui(documentId) : ""}]
}
proc ::GX::SII::workspaceDraftName {} {
    variable ui
    return [expr {[info exists ui(workspaceName)] ? $ui(workspaceName) : ""}]
}
proc ::GX::SII::workspacePayload {} {
    variable ui
    checkSession
    if {$ui(sourceId) eq ""} {error {Choose an image before saving a Workspace}}
    return [dict create schema scientific_image_inspector.recipe.v2 source_id $ui(sourceId) \
        source_sha [dict get $ui(info) sha256] steps [validateSteps $ui(steps)] \
        panels $ui(panels) figure_settings [figureSettings] annotations $ui(annotations) annotation_layers_json [annotationsJson $ui(annotations)]         image_annotations [expr {$ui(figurePreviewActive) ? $ui(imageAnnotations) : $ui(annotations)}]         figure_annotations [expr {$ui(figurePreviewActive) ? $ui(annotations) : $ui(figureAnnotations)}]         canvas_mode [expr {$ui(figurePreviewActive) ? "figure" : "image"}] sidebar_sections $ui(sidebarTabs) history_timeline $ui(historyTimeline)]
}
proc ::GX::SII::saveState {} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Finish adjustment preview before saving the Workspace.};return 0}
    if {$ui(sourceId) eq ""} return
    if {$ui(historyBrowsing)} {set ui(status) {History browsing is read-only. Return to Latest before saving.};return 0}
    if {[catch {
        historyObserve
        set payload [workspacePayload]
        if {$ui(documentId) eq ""} {
            set name [expr {$ui(workspaceName) eq "" ? "Image Inspector — $ui(sourceId) [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]" : $ui(workspaceName)}]
            set receipt [::GX::sessionWorkspaceCreate scientific_image_inspector $name $payload]
            set ui(documentId) [dict get $receipt workspace_id]
        } else {
            set receipt [::GX::sessionWorkspaceUpdate $ui(documentId) $payload]
        }
        set ui(workspaceName) [dict get $receipt name]
        set ui(workspaceDraft) 0
        if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {::GX::sessionWorkspaceViewerTitlesRefresh}
        set ui(status) "Workspace saved: [dict get $receipt name]"
    } err options]} {
        # Autosave runs after every annotation gesture. Never convert an
        # invalid Native2D/History/Workspace receipt into a desktop-wide modal
        # background error while the user is drawing; preserve the work in
        # memory and report the rejected save in the status strip and stderr.
        eventFailure {Workspace save} $err $options
        return 0
    }
    return 1
}
proc ::GX::SII::workspaceClose {} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {error {Finish adjustment preview before changing Workspace}}
    checkSession
    # Clearing the active recipe never deletes its registered Workspace.
    if {$ui(documentId) ne "" && ![saveState]} {error {Save failed; current Workspace was not closed}}
    set ui(documentId) "";set ui(workspaceName) "";set ui(workspaceDraft) 1
    set ui(sidebarTabs) [sidebarConfiguredTabs];set ui(sidebarTemporary) {};sidebarRefresh
    discardPreview
    unset -nocomplain ui(restoreSnapshot)
    set ui(steps) {};set ui(redo) {};set ui(roi) {}
    set ui(panels) {};set ui(annotations) {}
    set ui(annotationActiveId) {};set ui(selectedAnnotationIds) {}
    set ui(scope) all;set ui(selectionMode) object;set ui(editDomain) image
    set ui(imageAnnotations) {};set ui(figureAnnotations) {}
    if {$ui(sourceId) ne ""} {renderImages;refreshSteps;refreshPanels;refreshAnnotations}
    historyStripReset
    annotationMode 0
    if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {::GX::sessionWorkspaceViewerTitlesRefresh}
    return {}
}
proc ::GX::SII::workspaceOpen {context} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {error {Finish adjustment preview before changing Workspace}}
    checkSession
    discardPreview
    set id [get $context workspace_id ""]
    if {$id eq "new"} {
        # Explicit New always switches away from the previous project.
        if {$ui(documentId) eq "" && ($ui(steps) ne {} || $ui(panels) ne {} || $ui(annotations) ne {})} {
            if {![saveState]} {error {Save current edits before opening a new Workspace}}
        }
        workspaceClose
        set ui(workspaceName) [get $context workspace_name ""]
        if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {::GX::sessionWorkspaceViewerTitlesRefresh}
        return
    }
    if {$id eq ""} {error {Workspace ID is required}}
    set record [::GX::sessionWorkspaceGet $id]
    if {[dict get $record provider_id] ne "scientific_image_inspector"} {
        error {Selected Workspace belongs to another Viewer}
    }
    set payload [dict get $record payload]
    workspaceValidate $payload
    set source [dict get $payload source_id]
    if {[lsearch -exact [datasetIds] $source]<0} {error "Workspace source is unavailable in this Session: $source"}
    set info [inspect $source]
    if {[dict get $info sha256] ne [dict get $payload source_sha]} {
        error {Workspace source SHA-256 mismatch: refusing to apply recipe to a changed image}
    }
    # Preflight all external references before replacing the visible project.
    set steps [validateSteps [get $payload steps {}]]
    if {$ui(documentId) ne "" && $ui(documentId) ne $id} {
        if {![saveState]} {error {Save failed; current Workspace remains open}}
    }
    if {$ui(sourceId) ne $source} {set ui(sourceId) $source;loadSource}
    if {[llength [info commands ::GX::sessionWorkspacePromote]]} {::GX::sessionWorkspacePromote $id}
    set ui(steps) $steps
    set ui(redo) {};set ui(roi) {};set ui(scope) all
    set ui(annotationActiveId) {};set ui(selectedAnnotationIds) {}
    set ui(selectionMode) object;set ui(editDomain) image
    set ui(panels) [get $payload panels {}]
    # Workspace-specific sidebar settings take precedence over global defaults.
    # No automatic migration of legacy Workspace layouts is required in alpha.
    set selected [get $payload sidebar_sections [sidebarConfiguredTabs]]
    set ui(sidebarTabs) [sidebarValidSections $selected]
    set ui(sidebarTemporary) {}
    sidebarRefresh
    set savedMode [get $payload canvas_mode image]
    set ui(imageAnnotations) [get $payload image_annotations [expr {$savedMode eq "image" ? [get $payload annotations {}] : {}}]]
    set ui(figureAnnotations) [get $payload figure_annotations [expr {$savedMode eq "figure" ? [get $payload annotations {}] : {}}]]
    set ui(annotations) $ui(imageAnnotations)
    foreach field {width height margin gutter layout background} {
        if {[dict exists $payload figure_settings $field]} {
            set ui(figure-$field) [dict get $payload figure_settings $field]
        }
    }
    set ui(figurePreviewActive) 0
    set ui(documentId) $id
    set ui(workspaceName) [dict get $record name]
    set ui(workspaceDraft) 0
    refreshSteps;refreshPanels;refreshAnnotations
    renderImages
    annotationMode 0
    if {$savedMode eq "figure" && [llength $ui(panels)]} {previewFigure}
    historyStripRestore [get $payload history_timeline {}]
    if {[llength [info commands ::GX::sessionWorkspaceViewerTitlesRefresh]]} {::GX::sessionWorkspaceViewerTitlesRefresh}
    set ui(status) "Workspace opened: [dict get $record name]"
    return $id
}
proc ::GX::SII::publishDialog {} {
    variable ui
    if {[info exists ui(pending)] && $ui(pending)} {set ui(status) {Accept or discard pending adjustment first.};return}
    if {$ui(sourceId) eq ""} return
    if {$ui(pending)} {guiError {Accept or discard the pending adjustment before publishing.};return}
    set result [tk_messageBox -type yesno -icon question -parent $ui(window) \
        -title {Publish derived Dataset} -message "Publish accepted working image as Dataset '$ui(outputId)' ($ui(outputFormat))?\nAll transformations and annotations will be preserved in its manifest.\nThe source Dataset will remain unchanged."]
    if {$result ne "yes"} return
    if {[catch {
        checkSession
        set workspaceId $ui(documentId)
        set isFigure $ui(figurePreviewActive)
        set usePanels [expr {$isFigure ? $ui(panels) : {}}]
        set useSettings [expr {$isFigure ? [figureSettings] : {}}]
        set manifest [makeManifest $ui(sourceId) $ui(steps) $usePanels $useSettings $ui(annotations) $ui(outputFormat) $workspaceId]
        if {$isFigure && [llength $ui(panels)]} {
            set published [figurePublish $ui(panels) [figureSettings] $ui(annotations) $ui(outputId) $ui(outputFormat) $manifest]
        } elseif {[llength $ui(annotations)]} {
            set metadata [dict get $manifest output]
            set settings [dict create width [dict get $ui(workingInfo) width] height [dict get $ui(workingInfo) height] margin 0 gutter 0 layout grid background #FFFFFF]
            set p [dict create source_id $ui(sourceId) source_sha [dict get $ui(info) sha256] steps $ui(steps)]
            set published [figurePublish [list $p] $settings $ui(annotations) $ui(outputId) $ui(outputFormat) $manifest]
        } else {
            set published [publish $ui(sourceId) $ui(steps) $ui(outputId) $ui(outputFormat) $manifest]
        }
        set ui(status) "Published Dataset: [dict get $published dataset_id] SHA-256 [dict get $published sha256] | manifest included"
        tk_messageBox -icon info -parent $ui(window) -title {Dataset published} -message $ui(status)
    } err]} {guiError $err}
}
proc ::GX::SII::showCapabilities {} {
    variable ui
    if {[catch {set capabilities [capabilities]} err]} {guiError $err;return}
    set w $ui(window).capabilities
    catch {destroy $w}
    toplevel $w
    wm title $w {ImageMagick capabilities and security policy}
    wm geometry $w 880x620
    text $w.t -wrap none
    ttk::scrollbar $w.sb -command [list $w.t yview]
    $w.t configure -yscrollcommand [list $w.sb set]
    pack $w.sb -side right -fill y
    pack $w.t -fill both -expand yes
    dict for {key val} $capabilities {$w.t insert end "\n======== $key ========\n$val\n"}
    $w.t configure -state disabled
}
proc ::GX::SII::openManual {} {
    variable ui
    set w $ui(window).manual
    if {[winfo exists $w]} {raise $w;focus $w;return}
    set path [file join $::GX::SII::root MANUAL.md]
    if {![file isfile $path]} {guiError {Viewer manual is missing};return}
    set ch [open $path r];fconfigure $ch -encoding utf-8
    try {set markdown [read $ch]} finally {close $ch}
    toplevel $w
    wm title $w {Scientific Image Inspector — User Manual}
    wm geometry $w 850x690
    # A complete manual needs in-window search; it is still a Viewer-only
    # reading surface, using CORE's markup renderer for the contents.
    set ui(manualQuery) {}
    ttk::frame $w.search -padding 5
    ttk::label $w.search.label -text {Find in manual:}
    ttk::entry $w.search.query -textvariable ::GX::SII::ui(manualQuery) -width 36
    ttk::button $w.search.next -text {Find next} -command ::GX::SII::manualFindNext
    pack $w.search.label $w.search.query $w.search.next -side left -padx 4
    pack $w.search -side top -fill x
    ttk::frame $w.body;pack $w.body -fill both -expand 1
    text $w.body.text -wrap word -padx 12 -pady 12
    ttk::scrollbar $w.body.scroll -command [list $w.body.text yview]
    $w.body.text configure -yscrollcommand [list $w.body.scroll set]
    pack $w.body.scroll -side right -fill y
    pack $w.body.text -side left -fill both -expand 1
    if {[llength [info commands ::GX::markupRenderStringToWidget]]} {
        ::GX::markupRenderStringToWidget $w.body.text $markdown
    } else {$w.body.text insert end $markdown}
    $w.body.text tag configure manual_hit -background #ffdf80 -foreground #202020
    $w.body.text configure -state disabled
    bind $w.search.query <Return> ::GX::SII::manualFindNext
    bind $w <F3> ::GX::SII::manualFindNext
    bind $w <Control-f> [list focus $w.search.query]
    bind $w <Escape> [list destroy $w]
}
# Search the rendered contents rather than parsing Markdown: F3/Return moves
# through text without activating untrusted links or changing the manual file.
proc ::GX::SII::manualFindNext {} {
    variable ui
    if {![info exists ui(window)]} return
    set w $ui(window).manual
    if {![winfo exists $w]} return
    set query [string trim $ui(manualQuery)]
    set t $w.body.text
    set prior [$t tag ranges manual_hit]
    set start [expr {[llength $prior]==2 ? [lindex $prior 1] : {1.0}}]
    $t tag remove manual_hit 1.0 end
    if {$query eq {}} {return}
    set pos [$t search -nocase -- $query $start end]
    if {$pos eq {}} {set pos [$t search -nocase -- $query 1.0 end]}
    if {$pos eq {}} {
        bell
        return
    }
    set finish [$t index "$pos + [string length $query] chars"]
    $t tag add manual_hit $pos $finish
    $t mark set insert $pos
    $t see $pos
}
proc ::GX::SII::guiClose {} {
    variable ui
    discardPreview
    lodReset
    tooltipHide
    nativeCanvasDispose
    if {[info exists ui(window)] && [winfo exists $ui(window)]} {destroy $ui(window)}
    foreach k {photo-original photo-processed scaled-original scaled-processed} {
        if {[info exists ui($k)]} {catch {image delete $ui($k)}}
    }
    if {[info exists ui(cleanFiles)]} {foreach f $ui(cleanFiles) {catch {file delete -- $f}}}
    cleanTemps
    array unset ui *
    variable localFiles
    set localFiles [dict create]
}

# Plugin-only information dialog; version always comes from the public API owner.
proc ::GX::SII::showAbout {} {
    variable version
    variable ui
    set w $ui(window).about
    if {[winfo exists $w]} {raise $w;focus $w;return}
    toplevel $w
    wm title $w {About Scientific Image Inspector}
    wm transient $w $ui(window)
    ttk::label $w.title -text {Scientific Image Inspector} -font TkHeadingFont
    ttk::label $w.version -text "Version $version"
    ttk::label $w.description -text {GX-TXT Viewer plugin — non-destructive image editing, annotation and Dataset publication.} -wraplength 380 -justify center
    ttk::label $w.license -text {GNU GPL v3 or later}
    ttk::button $w.close -text Close -command [list destroy $w]
    foreach child {title version description license close} {pack $w.$child -padx 16 -pady 6}
    bind $w <Escape> [list destroy $w]
}
