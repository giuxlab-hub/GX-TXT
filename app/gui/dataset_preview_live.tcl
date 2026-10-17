# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation of prepared CORE Preview representations; no source reader,
# scheduler, numerical engine or persistent selection authority lives here.
namespace eval ::GX::PreviewLive {variable active {};variable epoch 0}
proc ::GX::datasetPreviewLiveEligible {id} {
    expr {[datasetField $id format] in {csv hdf5 h5} && [datasetField $id contract [datasetField $id kind]] ni {geometry.sketch}}
}
proc ::GX::datasetPreviewLiveShell {} {
    set f .top.nb.preview;set w $f.txt
    if {[winfo exists $f.live]} {return $f.live}
    grid remove $w $f.sy $f.sx
    ttk::frame $f.live;grid $f.live -row 2 -column 0 -columnspan 2 -sticky nsew -padx 5
    ttk::frame $f.live.actions;pack $f.live.actions -fill x
    foreach {id label operation} {fit Fit fit zoomIn {Zoom in} zoom_in zoomOut {Zoom out} zoom_out} {
        ttk::button $f.live.actions.$id -text $label -command [list ::GX::datasetPreviewLiveView $operation]
        pack $f.live.actions.$id -side left -padx 3 -pady 3
    }
    ttk::button $f.live.actions.cancel -text {Cancel preparation} -command ::GX::datasetPreviewLiveCancel
    ttk::label $f.live.actions.status -text {Preparing a source-verified scientific view…} -anchor w
    pack $f.live.actions.cancel -side right -padx 4;pack $f.live.actions.status -fill x -expand 1 -padx 8
    ttk::panedwindow $f.live.panes -orient vertical;pack $f.live.panes -fill both -expand 1
    ttk::frame $f.live.graph;ttk::frame $f.live.details
    $f.live.panes add $f.live.graph -weight 4;$f.live.panes add $f.live.details -weight 1
    ttk::label $f.live.graph.loading -text {Loading canonical curves asynchronously…} -anchor center
    pack $f.live.graph.loading -fill both -expand 1
    grid $w -in $f.live.details -row 0 -column 0 -sticky nsew
    raise $w
    ttk::scrollbar $f.live.details.sy -command [list $w yview];ttk::scrollbar $f.live.details.sx -orient horizontal -command [list $w xview]
    $w configure -yscrollcommand [list $f.live.details.sy set] -xscrollcommand [list $f.live.details.sx set]
    grid $f.live.details.sy -row 0 -column 1 -sticky ns;grid $f.live.details.sx -row 1 -column 0 -sticky ew
    grid columnconfigure $f.live.details 0 -weight 1;grid rowconfigure $f.live.details 0 -weight 1
    bind $f.live.panes <Map> [list ::GX::_datasetPreviewLiveInitialSplit $f.live.panes %W]
    return $f.live
}
proc ::GX::_datasetPreviewLiveInitialSplit {panes mapped} {
    if {$mapped ne $panes} return
    after idle [list ::GX::_datasetPreviewLiveSplit $panes]
    bind $panes <Map> {}
}
proc ::GX::_datasetPreviewLiveSplit {panes} {if {[winfo exists $panes] && [llength [$panes panes]]>1} {$panes sashpos 0 [expr {int([winfo height $panes]*.72)}]}}
proc ::GX::datasetPreviewLiveRelease {} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    incr epoch
    if {[dict exists $active key]} {datasetPreviewCacheCancel [dict get $active key]}
    set active {}
    set f .top.nb.preview
    if {![winfo exists $f.live]} return
    datasetDigitizerPreviewClear
    previewDescriptorClearWidgetArtifact $f.txt
    grid remove $f.txt
    $f.txt configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.txt -in $f -row 2 -column 0 -sticky nsew -padx {5 0};grid $f.sy;grid $f.sx
    destroy $f.live
}
proc ::GX::datasetPreviewLiveCancel {} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    incr epoch
    if {[dict exists $active key]} {datasetPreviewCacheCancel [dict get $active key]}
    if {[winfo exists .top.nb.preview.live.actions.status]} {.top.nb.preview.live.actions.status configure -text {Preparation cancelled; the last successful view is retained.}}
}
proc ::GX::datasetPreviewLiveOptions {id} {
    set options [datasetPreviewConfigurationRead $id]
    set options [dict remove $options last_render version schema_identity types]
    foreach axis {x y z} {if {[info exists ::GX::ui(previewMap,$axis)]} {dict set options $axis $::GX::ui(previewMap,$axis)}}
    if {[info exists ::GX::ui(previewMap,filters)]} {dict set options selections $::GX::ui(previewMap,filters)}
    return $options
}
proc ::GX::datasetPreviewLiveActivate {id {explicit 0}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    set token [interactiveDocumentSessionToken]
    set restoreOptions {}
    if {[dict exists $active id] && [dict get $active id] eq $id && [dict get $active token] eq $token && !$explicit} {
        if {[dict exists $active source] && [dict get $active source] ne [datasetPreviewCacheSource $id]} {.top.nb.preview.live.actions.status configure -text {Previous render — scientific source changed. Select Render to refresh.}}
        return
    }
    if {![dict exists $active id] || [dict get $active id] ne $id || [dict get $active token] ne $token} {
        datasetPreviewLiveRelease
        set active [dict create id $id token $token source [datasetPreviewCacheSource $id]]
        datasetPreviewLiveShell
        set w .top.nb.preview.txt;$w configure -state normal;$w delete 1.0 end;$w insert end "Dataset: $id\nPreparing scientific data through a managed CORE Job. The GUI remains available.\n";$w configure -state disabled
        set saved [datasetPreviewConfigurationRead $id]
        if {[dict exists $saved last_render key]} {
            set restoreOptions [dict get $saved last_render options]
            set prior [datasetPreviewCacheRead $id [dict get $saved last_render key] 1]
            if {$prior ne {}} {
                datasetPreviewLiveAdopt $id $prior 1
                if {[datasetField $id storage_provider {}] eq "remote"} {
                    set generation [incr epoch]
                    dict set active key [datasetPreviewCacheRequest $id [dict get $prior options] [list ::GX::_datasetPreviewLiveReady $id $token $generation 0]]
                }
                return
            }
        }
    }
    set options [expr {$explicit?[datasetPreviewLiveOptions $id]:$restoreOptions}]
    if {$explicit} {dict set active source [datasetPreviewCacheSource $id]}
    set generation [incr epoch]
    .top.nb.preview.live.actions.status configure -text {Preparing source-verified Preview in CORE Job Supervisor…}
    dict set active key [datasetPreviewCacheRequest $id $options [list ::GX::_datasetPreviewLiveReady $id $token $generation $explicit]]
}
proc ::GX::_datasetPreviewLiveReady {id token generation explicit response} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    if {$generation!=$epoch || ![dict exists $active id] || [dict get $active id] ne $id || $token ne [interactiveDocumentSessionToken] || ![winfo exists .top.nb.preview.live]} return
    if {[dict get $response status] eq "preparing"} {.top.nb.preview.live.actions.status configure -text "Preview preparation: [dict get $response state] — scientific data remain in CORE";return}
    if {[dict get $response status] ne "ready"} {.top.nb.preview.live.actions.status configure -text "Preview unavailable: [dict get $response message]";return}
    set result [datasetPreviewCacheRead $id [dict get $response key]]
    if {$result eq {}} {.top.nb.preview.live.actions.status configure -text {Source changed or prepared Preview failed integrity validation; Render again.};return}
    datasetPreviewLiveAdopt $id $result [dict get $response cache_hit]
    if {$explicit} {
        set saved [datasetPreviewConfigurationRead $id]
        dict set saved last_render [dict create key [dict get $result key] options [dict get $result options]]
        _datasetFrameworkMetadataUpdate $::GX::currentSession $id [dict create dataset_preview $saved]
    }
}
proc ::GX::datasetPreviewLiveAdopt {id result cacheHit} {
    variable ::GX::PreviewLive::active
    set f .top.nb.preview;set w $f.txt;set current [datasetPublicationV2DictDefault $result current 1]
    if {[dict exists $result axes]} {scientificDatasetPreviewControls $id [dict get $result axes] [datasetPublicationV2DictDefault $result dimensions {}]}
    datasetDigitizerPreviewClear
    previewDescriptorClearWidgetArtifact $w
    foreach child [winfo children $f.live.graph] {destroy $child}
    $w configure -state normal;$w delete 1.0 end
    $w insert end "Dataset: $id\n[datasetPublicationV2DictDefault $result description {}]\n"
    if {[dict exists $result digitizer] && [dict get $result digitizer] ne {}} {datasetDigitizerPreviewRender $w $id [dict get $result digitizer]}
    if {[dict exists $result native_model]} {
        if {"$f.live.graph" ni [$f.live.panes panes]} {$f.live.panes insert 0 $f.live.graph -weight 4}
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state !disabled}
        set model [dict get $result native_model]
        if {!$current} {
            # Keep the previous frame as an explicitly stale representation.
            # Live source subscriptions cannot declare that old receipt current.
            set panels {};foreach panel [dict get $model panels] {set series {};foreach item [dict get $panel series] {lappend series [dict remove $item source_descriptor source_descriptors]};dict set panel series $series;lappend panels $panel};dict set model panels $panels
        }
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        if {![datasetDigitizerPreviewAttachNative $id $w $model $f.live.graph]} {
            ::GX::PlotDatasetAPIv4::widgetCreate $f.live.graph.retainedXY $model {prepared_model 1 retain_presentation 1}
            pack $f.live.graph.retainedXY -fill both -expand 1
        }
        $w insert end "[dict get $result row_count] canonical rows; [dict get $result displayed_points] display points. Full scientific data remain canonical.\nWheel zooms; middle drag pans; Fit restores the complete bounds.\n"
    } else {
        if {"$f.live.graph" in [$f.live.panes panes]} {$f.live.panes forget $f.live.graph}
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state disabled}
        if {[dict exists $result media_artifact]} {
            set directory [datasetPreviewCachePath $::GX::currentSession [dict get $result key]]
            set descriptor [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact [dict get $result media_artifact]] $directory]
            previewDescriptorRenderTextWidget $w $descriptor
        } else {$w insert end [datasetPublicationV2DictDefault $result description {No applicable graphical Preview.}]}
    }
    $w configure -state disabled
    raise $w
    dict set active key [dict get $result key];dict set active source [dict get $result source]
    set text [expr {$current?($cacheHit?"Session cache hit — source-verified retained Preview":"Prepared retained Preview — source-verified"):"Previous render — scientific source changed"}]
    if {$current && $cacheHit} {
        set selected [datasetPreviewLiveOptions $id];set rendered [dict get $result options]
        foreach field {x y z selections ordering processed_image} {
            if {[datasetPublicationV2DictDefault $selected $field {}] ne [datasetPublicationV2DictDefault $rendered $field {}] && [dict exists $rendered $field]} {set text {Previous render — settings changed. Select Render to apply.};break}
        }
    }
    if {[dict exists $result remote_unverified]} {set text {Previous remote render — verifying authoritative source availability and revision…}}
    $f.live.actions.status configure -text $text
}
proc ::GX::datasetPreviewLiveView {operation} {
    set path .top.nb.preview.live.graph.retainedXY
    if {![winfo exists $path]} return
    switch $operation {
        fit {::GX::PlotDatasetAPIv4::widgetView $path fit}
        zoom_in {::GX::PlotDatasetAPIv4::widgetView $path zoom main 1.25 .5 .5}
        zoom_out {::GX::PlotDatasetAPIv4::widgetView $path zoom main .8 .5 .5}
    }
}
proc ::GX::datasetPreviewLiveSettingsChanged {} {
    if {[winfo exists .top.nb.preview.live.actions.status]} {.top.nb.preview.live.actions.status configure -text {Previous render — settings changed. Select Render to apply.}}
}
