# SPDX-License-Identifier: GPL-3.0-or-later
# Existing activated inspection choice is the only selection authority.
proc ::GX::datasetPageTabChanged {} {
    datasetPageEditState
    # Notebook unmapping retains the one active preview and its viewing state.
    # Refresh validates identity even while hidden, but only generates when shown.
    refreshCsvPreview
}
proc ::GX::datasetPreviewVisible {} {
    expr {[winfo exists .top.nb.channels.views] && [.top.nb.channels.views select] eq ".top.nb.channels.views.preview" && [.top.nb select] eq ".top.nb.channels"}
}
proc ::GX::datasetPageEditState {} {
    set button .top.nb.channels.browser.tools.edit
    if {![winfo exists $button]} return
    set section [lindex [split [.top.nb.channels.views select] .] end]
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    set enabled [expr {$mode eq "imported" && $id ne {} && $section in {metadata notes temporal}}]
    $button state [expr {$enabled?"!disabled":"disabled"}]
    set tip [expr {$enabled?"Edit [dict get {metadata Metadata notes Notes temporal {Temporal Sets}} $section] for $id":"Edit is available for canonical Metadata, Notes and Temporal Sets"}]
    bind $button <Enter> [list ::GX::native2DViewportTooltipShow %W $tip]
}
proc ::GX::datasetPageContextEdit {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported" || $id eq {}} {error {Activate a canonical Dataset first.}}
    switch [lindex [split [.top.nb.channels.views select] .] end] {
        metadata {datasetMetadataOpenSelectedFromGui}
        notes {datasetNotesOpenSelected}
        temporal {temporalSetGuiOpen}
    }
}
proc ::GX::datasetPageForceRefresh {} {
    datasetPreviewStop
    unset -nocomplain ::GX::ui(previewSignature)
    # A deliberate force refresh does not revoke an explicit Clear.
    refreshDatasetInspectionChoices
    refreshNativeVariablesGui
    refreshCsvPreview
}
proc ::GX::datasetBrowserCatalogDrain {} {
    variable ui
    unset -nocomplain ui(datasetBrowserAfter)
    # Responsive Preview generation can drain a queued catalog callback inside
    # another refresh. A callback whose receipts were consumed is a no-op.
    if {![info exists ui(datasetBrowserReceipts)]} return
    set receipts $ui(datasetBrowserReceipts);unset ui(datasetBrowserReceipts)
    foreach receipt $receipts {datasetBrowserCatalogRefresh $receipt}
}
proc ::GX::datasetPreviewStamp {} {
    set choice $::GX::variableDatasetChoice
    set token [dict get [datasetCatalogSnapshot] session_token]
    lassign [datasetInspectionParseChoice $choice] mode id
    if {$mode eq "imported" && [datasetField $id id {}] ne {}} {
        set path [datasetResolvePath $::GX::currentSession $id]
        return [list $token $choice [datasetViewerStamp $id $path] [datasetMetadataRead $::GX::currentSession $id]]
    }
    set path [dict get [datasetInspectionSelectedInfo $choice] path]
    set stat {}
    if {[file isfile $path]} {file stat $path st;set stat [list $st(size) $st(mtime) $st(ctime)]}
    return [list $token $choice $path $stat [array get ::GX::cfg]]
}
proc ::GX::datasetPreviewStop {} {
    variable ui
    variable ::GX::DatasetViewer::previewJob
    if {![info exists ui(previewEpoch)]} {set ui(previewEpoch) 0}
    incr ui(previewEpoch)
    if {[info exists ui(previewCacheWatch)]} {after cancel $ui(previewCacheWatch)}
    unset -nocomplain ui(previewCacheWatch) ui(previewSignature) ui(previewSourceStamp) ui(previewGenerating)
    if {$previewJob ne {}} {datasetViewerClose $previewJob;set previewJob {}}
    native3DPreviewRelease .top.nb.preview.txt
    datasetPreviewBinaryTaskStop
    datasetDigitizerPreviewClear
    if {[winfo exists .top.nb.preview.geometry]} {place forget .top.nb.preview.geometry}
    if {$::GX::DatasetViewer::previewImage ne {}} {catch {image delete $::GX::DatasetViewer::previewImage};set ::GX::DatasetViewer::previewImage {}}
    if {[info exists ui(preview)] && [winfo exists $ui(preview)]} {previewDescriptorClearWidgetArtifact $ui(preview)}
}
# Rendering identity deliberately excludes scroll positions and the Native3D
# camera: those belong to the retained widgets/worker. No scientific reads here.
proc ::GX::datasetPreviewCacheSignature {} {
    variable ui
    set options {}
    foreach key {previewMap,id previewMap,x previewMap,y previewMap,filters previewMap,separate} {
        if {[info exists ui($key)]} {set value $ui($key);if {$key eq "previewMap,filters"} {set value [dict remove $value @hidden_filters]};lappend options $key $value}
    }
    set settings [previewSettingsLoad];set ordered {}
    foreach key [lsort [dict keys $settings]] {lappend ordered $key [dict get $settings $key]}
    lappend options settings $ordered graphics_policy [native3dGraphicsPolicy]
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"} {
        set channels {};foreach key [lsort [array names ::GX::ch]] {lappend channels $key $::GX::ch($key)}
        lappend options channels $channels
    }
    return [list [datasetPreviewStamp] $options]
}
proc ::GX::datasetPreviewCacheWatch {} {
    variable ui
    unset -nocomplain ui(previewCacheWatch)
    if {![info exists ui(previewSignature)]} return
    if {![winfo exists $ui(preview)] || [catch {set signature [datasetPreviewCacheSignature]}] || $signature ne $ui(previewSignature)} {
        datasetPreviewStop
        return
    }
    set ui(previewCacheWatch) [after 1000 ::GX::datasetPreviewCacheWatch]
}
proc ::GX::datasetPreviewClear {} {
    variable ui
    datasetPreviewStop
    set ui(previewMap,status) {Visualization cleared; filters retained.}
    set ui(previewCleared) [list [dict get [datasetCatalogSnapshot] session_token] $::GX::variableDatasetChoice]
    unset -nocomplain ui(previewSignature)
    refreshCsvPreview
}
proc ::GX::datasetPreviewRender {} {
    unset -nocomplain ::GX::ui(previewCleared) ::GX::ui(previewSignature)
    refreshCsvPreview
}
proc ::GX::datasetPreviewToolsPlace {} {
    variable ui
    set f .top.nb.preview;set p $f.actions
    if {![winfo exists $p] || ![winfo exists $f.txt]} return
    set width [winfo width $f.txt];set height [winfo height $f.txt]
    set pw [winfo reqwidth $p];set ph [winfo reqheight $p]
    if {![info exists ui(previewToolsXY)]} {set x [expr {$width-$pw-12}];set y 10} else {lassign $ui(previewToolsXY) x y}
    set x [expr {max(0,min($x,$width-$pw))}];set y [expr {max(0,min($y,$height-$ph))}]
    if {[winfo exists $f.geometry] && [winfo manager $f.geometry] ne {} && $x+$pw>$width-240 && $y<130} {set y [expr {min(140,max(0,$height-$ph))}]}
    place $p -in $f.txt -x $x -y $y
    raise $p
}
proc ::GX::datasetPreviewToolsDrag {phase X Y} {
    variable ui
    if {$phase eq "start"} {set ui(previewToolsDrag) [list $X $Y [dict get [place info .top.nb.preview.actions] -x] [dict get [place info .top.nb.preview.actions] -y]];return}
    if {![info exists ui(previewToolsDrag)]} return
    lassign $ui(previewToolsDrag) sx sy x y
    set ui(previewToolsXY) [list [expr {$x+$X-$sx}] [expr {$y+$Y-$sy}]]
    datasetPreviewToolsPlace
    set ui(previewToolsXY) [list [dict get [place info .top.nb.preview.actions] -x] [dict get [place info .top.nb.preview.actions] -y]]
}
proc ::GX::datasetPreviewActionsState {} {
    set f .top.nb.preview
    if {![winfo exists $f.actions]} return
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    set tabular 0
    if {$mode eq "imported" && $id ne {}} {catch {set page [datasetPreviewPage $::GX::currentSession $id [dict create count 1]];set tabular [dict get $page available]}}
    $f.actions.pages state [expr {$tabular?"!disabled":"disabled"}]
    set visual [expr {[dict size $::GX::DigitizerPreview::state]>0 || $::GX::DatasetViewer::previewImage ne {} || $::GX::DatasetViewer::previewJob ne {} || [info exists ::GX::previewBinaryTaskState] && $::GX::previewBinaryTaskState in {running ready} || [info exists ::GX::previewArtifactImages($f.txt)]}]
    $f.actions.clear state [expr {$visual?"!disabled":"disabled"}]
    $f.actions.copy state [expr {[$f.txt compare end-1c > 1.0]?"!disabled":"disabled"}]
    datasetPageEditState
    datasetPreviewToolsPlace
}
rename ::GX::refreshCsvPreview ::GX::refreshCsvPreview_before_sync
proc ::GX::refreshCsvPreview {} {
    variable ui
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} return
    datasetPageEditState
    datasetBrowserRefresh
    # Responsive scientific reads service Tk events. Keep a reentrant refresh
    # from starting another build for the same in-flight identity.
    if {[info exists ui(previewGenerating)]} {
        if {$ui(previewGenerating)==$ui(previewEpoch) && ![catch {set source [datasetPreviewStamp]}] && $source eq $ui(previewSourceStamp)} return
        datasetPreviewStop
    }
    if {[info exists ui(previewSignature)]} {
        if {[catch {set signature [datasetPreviewCacheSignature]}] || $signature ne $ui(previewSignature)} {datasetPreviewStop}
    }
    if {![datasetPreviewVisible]} return
    set stamp [datasetPreviewStamp]
    if {[info exists ui(previewSignature)]} {
        # Actions already describe this cached preview. Rechecking table support
        # would read a scientific page on every otherwise free notebook return.
        if {$::GX::DatasetViewer::previewJob ne {}} {meshDatasetPreviewResize}
        datasetPreviewToolsPlace
        return
    }
    datasetPreviewStop
    set epoch $ui(previewEpoch)
    set ui(previewSourceStamp) $stamp
    set ui(previewGenerating) $epoch
    set identity [lrange $stamp 0 1]
    if {[info exists ui(previewCleared)] && $ui(previewCleared) ne $identity} {unset ui(previewCleared)}
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {[winfo exists .top.nb.preview.mapping] && ($mode ne "imported" || [dict get [datasetViewerDescribe $id] target] ne "scientific")} {grid remove .top.nb.preview.mapping}
    grid remove .top.nb.preview.buttons
    pack forget .top.nb.preview.buttons.apply .top.nb.preview.buttons.render
    try {
        if {[info exists ui(previewCleared)]} {
            pack .top.nb.preview.buttons.render -side left -padx 4
            grid .top.nb.preview.buttons -row 0 -column 0 -sticky ew
            if {$mode eq "imported" && [dict get [datasetViewerDescribe $id] target] eq "scientific"} {scientificDatasetPreviewControls $id [scientificDatasetAxes $id]} elseif {[winfo exists .top.nb.preview.mapping]} {grid remove .top.nb.preview.mapping}
            set ui(previewMap,status) {Visualization cleared; filters reconciled.}
            set w $ui(preview)
            if {$::GX::DatasetViewer::previewImage ne {}} {catch {image delete $::GX::DatasetViewer::previewImage};set ::GX::DatasetViewer::previewImage {}}
            previewDescriptorClearWidgetArtifact $w
            $w configure -state normal;$w delete 1.0 end
            $w insert end "Dataset: $id\nVisualization cleared. Scientific source is unchanged. Select Render to show it again, or activate another Dataset.\n\n"
            if {$mode eq "imported"} {datasetPreviewRenderSchema $w $id;datasetPreviewRenderMetadata $w $::GX::currentSession $id}
            $w configure -state disabled
        } else {
            ::GX::refreshCsvPreview_before_sync
        }
    } finally {
        if {$epoch==$ui(previewEpoch)} {unset -nocomplain ui(previewGenerating)}
    }
    # Generic Pending detection is automatic; explicit Apply belongs to legacy single input.
    if {$mode eq "single" && $::GX::cfg(acquisition_module) ne "acq.generic_csv" && [info exists ::GX::cfg(input_csv)] && [file isfile $::GX::cfg(input_csv)] && ![datasetPreviewUnsafeTextInput $::GX::cfg(input_csv)]} {.top.nb.preview.buttons.apply state !disabled;pack .top.nb.preview.buttons.apply -side left -padx 4;grid .top.nb.preview.buttons -row 0 -column 0 -sticky ew}
    if {$epoch==$ui(previewEpoch)} {
        datasetPreviewActionsState
        # Controls reconcile defaults/filters during generation; freeze their
        # final values so the first return does not invalidate its own cache.
        set ui(previewSignature) [datasetPreviewCacheSignature]
        set ui(previewCacheWatch) [after 1000 ::GX::datasetPreviewCacheWatch]
    }
}
