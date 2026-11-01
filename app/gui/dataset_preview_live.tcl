# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation of prepared CORE Preview representations; no source reader,
# scheduler, numerical engine or persistent selection authority lives here.
namespace eval ::GX::PreviewLive {variable active {};variable epoch 0;variable extensionComposition 0}
proc ::GX::datasetPreviewLiveEligible {id} {
    if {[datasetField $id format] in {csv hdf5 h5} && [datasetField $id contract [datasetField $id kind]] ni {geometry.sketch}} {return 1}
    # Other data retain their original fallback unless a compatible installed
    # component can contribute to the existing prepared Preview notebook.
    foreach provider [datasetPreviewProviders $id] {
        if {[dict get $provider available] && [datasetPublicationV2DictDefault $provider profile native] eq {presentation}} {return 1}
    }
    return 0
}
proc ::GX::datasetPreviewLiveShell {} {
    set f .top.nb.preview;set w $f.txt
    if {[winfo exists $f.live]} {return $f.live}
    grid remove $w $f.sy $f.sx
    ttk::frame $f.live;grid $f.live -row 2 -column 0 -columnspan 2 -sticky nsew -padx 5
    bind $f.live <Destroy> [list ::GX::datasetPreviewLiveDestroyed $f.live %W]
    ttk::frame $f.live.actions;pack $f.live.actions -fill x -pady {1 0}
    ttk::frame $f.live.actions.nav
    pack $f.live.actions.nav -side left -padx {1 7}
    foreach {id label operation} {fit Fit fit zoomIn {Zoom +} zoom_in zoomOut {Zoom -} zoom_out} {
        ttk::button $f.live.actions.$id -text $label -width 0 -command [list ::GX::datasetPreviewLiveView $operation]
        pack $f.live.actions.$id -in $f.live.actions.nav -side left -padx 1 -pady 1
    }
    ttk::button $f.live.actions.cancel -text {Cancel preparation} -width 0 -command ::GX::datasetPreviewLiveCancel
    ttk::label $f.live.actions.status -text {Preparing a source-verified scientific view…} -anchor w -takefocus 1 -cursor hand2
    bind $f.live.actions.status <Configure> {::GX::datasetPreviewLiveRefreshStatus}
    bind $f.live.actions.status <FocusIn> [list ::GX::datasetPreviewLiveStatusTip $f.live.actions.status]
    bind $f.live.actions.status <FocusOut> [list ::GX::native2DViewportTooltipHide $f.live.actions.status]
    bind $f.live.actions.status <Escape> [format {%s;break} [list ::GX::native2DViewportTooltipHide $f.live.actions.status]]
    foreach sequence {<Button-1> <Return> <KP_Enter> <space>} {bind $f.live.actions.status $sequence {::GX::datasetPreviewLiveStatusInspect;break}}
    pack $f.live.actions.cancel -side right -padx 3
    pack $f.live.actions.status -side left -fill x -expand 1 -padx {2 5}
    ttk::frame $f.live.selection
    ttk::label $f.live.selection.label -text Preview
    ttk::combobox $f.live.selection.choice -state readonly -width 42 -textvariable ::GX::ui(previewPrimaryChoice)
    ttk::label $f.live.selection.reason -anchor w -wraplength 680
    pack $f.live.selection.label -side left -padx 4
    pack $f.live.selection.choice -side left -padx 4
    pack $f.live.selection.reason -side left -fill x -expand 1 -padx 6
    bind $f.live.selection.choice <<ComboboxSelected>> ::GX::datasetPreviewLivePrimarySelected
    bind $f.live.selection.choice <FocusIn> [list ::GX::datasetPreviewLiveSelectionTip $f.live.selection.choice]
    bind $f.live.selection.choice <FocusOut> [list ::GX::native2DViewportTooltipHide $f.live.selection.choice]
    bind $f.live.selection.choice <Escape> [list ::GX::native2DViewportTooltipHide $f.live.selection.choice]
    ttk::notebook $f.live.panes;pack $f.live.panes -fill both -expand 1
    _uiFieldNotebookAttach $f.live.panes
    bind $f.live.panes <<NotebookTabChanged>> +::GX::datasetPreviewLiveNavigationRefresh
    foreach name {plot source quality table details choice} {ttk::frame $f.live.panes.$name}
    $f.live.panes add $f.live.panes.details -text Preview
    ttk::label $f.live.panes.details.loading -text {Preparing Dataset Preview…} -padding 12
    pack $f.live.panes.details.loading -fill both -expand 1
    ttk::label $f.live.panes.plot.loading -text {Loading canonical curves asynchronously…} -anchor center -justify left -wraplength 600 -padding 12
    pack $f.live.panes.plot.loading -fill both -expand 1
    bind $f.live.panes.plot.loading <Configure> [list $f.live.panes.plot.loading configure -wraplength %w]
    # Reuse the original image controls inside the existing source pane. Their
    # widgets/callbacks retain their CORE owner and are hidden with that pane.
    if {[winfo exists $f.imageTools]} {
        foreach button {out actual in fit} {$f.imageTools.$button configure -width 0}
        grid $f.imageTools -in $f.live.panes.source -row 0 -column 0 -columnspan 2 -sticky ew
        grid remove $f.imageTools
        raise $f.imageTools
    }
    grid $w -in $f.live.panes.source -row 1 -column 0 -sticky nsew
    raise $w
    ttk::scrollbar $f.live.panes.source.sy -command [list $w yview];ttk::scrollbar $f.live.panes.source.sx -orient horizontal -command [list $w xview]
    $w configure -yscrollcommand [list $f.live.panes.source.sy set] -xscrollcommand [list $f.live.panes.source.sx set]
    grid $f.live.panes.source.sy -row 1 -column 1 -sticky ns;grid $f.live.panes.source.sx -row 2 -column 0 -sticky ew
    grid columnconfigure $f.live.panes.source 0 -weight 1;grid rowconfigure $f.live.panes.source 1 -weight 1
    return $f.live
}
proc ::GX::datasetPreviewLivePrimarySelected {} {
    variable ::GX::PreviewLive::active
    if {![dict exists $active id] || ![info exists ::GX::ui(previewPrimaryChoices)] || ![dict exists $::GX::ui(previewPrimaryChoices) $::GX::ui(previewPrimaryChoice)]} return
    set component [dict get $::GX::ui(previewPrimaryChoices) $::GX::ui(previewPrimaryChoice)]
    if {$component eq {}} return
    dict set active primary_component $component
    native2DViewportTooltipHide
    # Existing preparation/cache owners admit native providers; the selection
    # widget never loads a renderer or creates a second provider registry.
    datasetPreviewLiveActivate [dict get $active id] 1
    datasetPreviewLiveSetStatus {Preparing selected Preview; the previous successful view remains until preparation completes.}
}
proc ::GX::datasetPreviewLiveSelectionTip {choice} {
    if {![winfo exists $choice] || ![winfo exists [winfo parent $choice].reason]} return
    native2DViewportTooltipShow $choice "Preview: [$choice get]\n[[winfo parent $choice].reason cget -text]"
}
proc ::GX::datasetPreviewLiveHeaderLayout {showSelector} {
    set root .top.nb.preview.live;set actions $root.actions;set frame $root.selection
    if {![winfo exists $actions] || ![winfo exists $frame]} return
    set compact $showSelector
    foreach button {fit zoomIn zoomOut} {if {![$actions.$button instate disabled]} {set compact 0}}
    set signature [list [winfo id $actions] $compact $showSelector]
    if {[info exists ::GX::ui(previewHeaderLayout)] && $::GX::ui(previewHeaderLayout) eq $signature} return
    set ::GX::ui(previewHeaderLayout) $signature
    # No renderer or work is changed. Reclaim the duplicate disabled navigation
    # row for managed presentations while retaining every usable host command.
    foreach widget [list $frame $actions.nav $actions.status $actions.cancel] {
        if {[winfo manager $widget] eq {grid}} {grid forget $widget}
        if {[winfo manager $widget] eq {pack}} {pack forget $widget}
    }
    if {$compact} {
        pack forget $frame.reason
        $frame.choice configure -width 1
        pack configure $frame.choice -fill x -expand 1
        $actions.status configure -width 1
        grid columnconfigure $actions 0 -weight 4 -minsize 140
        grid columnconfigure $actions 1 -weight 1 -minsize 40
        grid columnconfigure $actions 2 -weight 0 -minsize 0
        grid $frame -in $actions -row 0 -column 0 -sticky ew -padx 3 -pady 3
        grid $actions.status -row 0 -column 1 -sticky ew -padx 5
        grid $actions.cancel -row 0 -column 2 -sticky e -padx 3
        raise $frame
    } else {
        foreach column {0 1 2} {grid columnconfigure $actions $column -weight 0 -minsize 0}
        $frame.choice configure -width 42
        pack configure $frame.choice -fill none -expand 0
        pack $frame.reason -side left -fill x -expand 1 -padx 6
        $actions.status configure -width {}
        pack $actions.nav -side left -padx {1 7}
        pack $actions.cancel -side right -padx 3
        pack $actions.status -side left -fill x -expand 1 -padx {2 5}
        if {$showSelector} {pack $frame -fill x -before $root.panes -padx 3 -pady 3}
    }
}
proc ::GX::datasetPreviewLiveStandardTabs {id representation} {
    set notebook .top.nb.preview.live.panes
    set context [_datasetPreviewProviderContext $id $representation]
    set available [dict get $context availability]
    set current [$notebook select]
    set previous {};foreach pane [$notebook tabs] {if {[$notebook tab $pane -state] ne {hidden}} {lappend previous $pane}}
    foreach name {plot source quality table details choice} {
        if {"$notebook.$name" in [$notebook tabs]} {$notebook hide $notebook.$name}
    }
    set panes {}
    if {[dict get $available native_model]} {$notebook add $notebook.plot -text Plot;lappend panes $notebook.plot}
    if {[dict get $available table]} {
        foreach child [winfo children $notebook.table] {destroy $child}
        if {![catch {datasetPreviewCreateTable $notebook.table.inspector $::GX::currentSession $id}]} {
            pack $notebook.table.inspector -fill both -expand 1
            $notebook add $notebook.table -text Table;lappend panes $notebook.table
        }
    }
    set curveControls [datasetPublicationV2DictDefault $available curve_controls 0]
    if {[dict get $available source_image] || $curveControls || [dict get $available media_artifact]} {
        set label [expr {[dict get $available source_image]?{Source image}:($curveControls?{Curve details}:{Preview})}]
        $notebook add $notebook.source -text $label;lappend panes $notebook.source
    }
    if {[dict get $available quality]} {$notebook add $notebook.quality -text Quality;lappend panes $notebook.quality}
    if {![llength $panes]} {
        foreach child [winfo children $notebook.details] {destroy $child}
        ttk::label $notebook.details.summary -text [datasetPublicationV2DictDefault $representation description {No graphical Preview is available for this Dataset. Standard Dataset inspection remains available.}] -padding 12 -wraplength 700 -justify left
        pack $notebook.details.summary -fill x -anchor nw
        $notebook add $notebook.details -text Details;lappend panes $notebook.details
    }
    if {$current in $panes && $current in $previous} {$notebook select $current} else {$notebook select [lindex $panes 0]}
    return $context
}
proc ::GX::datasetPreviewLiveDestroyed {expected actual} {
    if {$expected eq $actual} {datasetPreviewLiveRelease 0}
}
proc ::GX::datasetPreviewLiveRelease {{restore 1}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    incr epoch
    datasetPreviewGuiRelease
    if {[dict exists $active key]} {datasetPreviewCacheCancel [dict get $active key]}
    if {[dict exists $active subscription]} {datasetCatalogUnsubscribe [dict get $active subscription]}
    if {[info exists ::GX::ui(previewCacheWatch)]} {after cancel $::GX::ui(previewCacheWatch);unset ::GX::ui(previewCacheWatch)}
    native3DPreviewRelease .top.nb.preview.live.panes.plot
    set active {}
    unset -nocomplain ::GX::ui(previewExtensionTabs) ::GX::ui(previewPrimaryChoices) ::GX::ui(previewPrimaryChoice)
    datasetDigitizerPreviewClear
    if {!$restore} return
    set f .top.nb.preview
    if {![winfo exists $f.live]} return
    datasetPreviewImageRelease $f.txt
    previewDescriptorClearWidgetArtifact $f.txt
    if {[winfo exists $f.imageTools]} {
        grid forget $f.imageTools
        grid $f.imageTools -in $f -row 0 -column 0 -sticky ew
        grid remove $f.imageTools
    }
    grid remove $f.txt
    $f.txt configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.txt -in $f -row 2 -column 0 -sticky nsew -padx {5 0};grid $f.sy;grid $f.sx
    destroy $f.live
}
proc ::GX::datasetPreviewLiveCancel {} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    incr epoch
    if {[dict exists $active key]} {datasetPreviewCacheCancel [dict get $active key]}
    if {[dict exists $active id] && [dict exists $active token] && ![datasetPreviewLiveRetainSelection [dict get $active id] [dict get $active token] $epoch]} return
    datasetPreviewLiveSetStatus {Preparation cancelled; the last successful view is retained.}
}
proc ::GX::datasetPreviewLiveOptions {id} {
    set options [datasetPreviewConfigurationRead $id]
    set options [dict remove $options last_render version schema_identity types retained_visibility]
    foreach axis {x y z} {if {[info exists ::GX::ui(previewMap,$axis)]} {dict set options $axis $::GX::ui(previewMap,$axis)}}
    if {[info exists ::GX::ui(previewMap,filters)]} {dict set options selections $::GX::ui(previewMap,filters)}
    if {[dict exists $::GX::PreviewLive::active primary_component]} {dict set options primary_component [dict get $::GX::PreviewLive::active primary_component]}
    if {[dict exists $::GX::PreviewLive::active id] && [dict get $::GX::PreviewLive::active id] eq $id && [dict exists $::GX::PreviewLive::active source_window]} {
        set request [dict get $::GX::PreviewLive::active source_window]
        dict set options source_window $request
        dict set options x [dict get $request x_variable_id]
        dict set options y [dict get $request y_variable_id]
        dict set options ordering {}
    }
    return $options
}
proc ::GX::datasetPreviewLiveWatchStamp {} {
    variable ::GX::PreviewLive::active
    set id [dict get $active id];set ids [concat [list $id] [datasetPublicationV2DictDefault $active extension_dependency_ids {}]]
    set md [datasetMetadataRead $::GX::currentSession $id]
    if {[dict exists $md curve_digitizer.source_dataset_id]} {lappend ids [dict get $md curve_digitizer.source_dataset_id]}
    if {[dict exists $active rendered_options processed_image dataset_id]} {lappend ids [dict get $active rendered_options processed_image dataset_id]}
    set stamp {}
    foreach dependency [lsort -unique $ids] {
        set state missing
        catch {
            set path [datasetResolvePath $::GX::currentSession $dependency]
            set state [datasetViewerStamp $dependency $path]
            lappend state metadata [datasetMetadataRead $::GX::currentSession $dependency]
        }
        lappend stamp $dependency $state
    }
    lappend stamp components [datasetPreviewProviderIdentity $id]
    return $stamp
}
proc ::GX::datasetPreviewLiveCheck {{force 0}} {
    variable ::GX::PreviewLive::active
    datasetPreviewGuiRefresh
    if {![dict exists $active rendered_key] || ![winfo exists .top.nb.preview.live]} return
    if {[catch {interactiveDocumentSessionToken} reason]} {
        datasetPreviewLiveSetStatus "Previous render — $reason Reopen the Session to refresh."
        return
    }
    if {[dict get $active token] ne $reason} {datasetPreviewLiveRelease;return}
    set failed [catch {set stamp [datasetPreviewLiveWatchStamp]}]
    if {!$force && !$failed && [dict exists $active watch_stamp] && $stamp eq [dict get $active watch_stamp]} return
    if {!$failed} {dict set active watch_stamp $stamp}
    set id [dict get $active id]
    set sameSource [expr {[dict exists $active representation source] && ![catch {datasetPreviewCacheSource $id} currentSource] && [dict get $active representation source] eq $currentSource}]
    # Retained visibility/preferences can change the watch stamp without
    # changing scientific source, provider assets or render policy. Keep the
    # current panes and their managed generation in that case. Session/token
    # checks above and source/provider/key invalidation below remain in force.
    set keyCurrent 0
    if {![catch {set current [datasetPreviewCacheKey $id [dict get $active rendered_options]]}]} {
        set keyCurrent [expr {$current eq [dict get $active rendered_key]}]
    }
    if {$sameSource && $keyCurrent} return
    if {[dict exists $active representation] && $sameSource} {
        set notebook .top.nb.preview.live.panes
        set windowId [winfo id $notebook]
        set owner [list [dict get $active id] [dict get $active token] $::GX::PreviewLive::epoch $reason]
        datasetPreviewLiveExtensionTabs $id [dict get $active representation]
        if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner]} return
    }
    if {!$keyCurrent} {
        datasetPreviewLiveSetStatus {Previous render — scientific source or linked image changed. Select Render to refresh.}
        if {![datasetPublicationV2DictDefault $active stale_qualified 0]} {
            datasetDigitizerPreviewQualifyPrevious $id
            set parent .top.nb.preview.live.panes.quality
            if {[winfo exists $parent.explanation]} {$parent.explanation configure -text {Previous-render published Quality report and CORE source receipt. Neither provider fields nor the old CORE observation describe current source bytes after this change. Select Render to verify again. Published diagnostics do not infer physical accuracy or uncertainty.}}
            set tree $parent.table.rows
            if {[winfo exists $tree]} {
                foreach {row value} {quality2 {Provider report from previous render} quality4 {Provider digest from previous render} host_source_status {Previous render; refresh required} host_source_digest {Not revalidated after source change} host_source_checked_at {Previous preparation; Render to refresh} host_source_reason {Source identity changed since this receipt. Render to verify.}} {
                    if {[$tree exists $row]} {set values [$tree item $row -values];lset values 0 $value;$tree item $row -values $values}
                }
                if {[winfo exists $parent.detail.value]} {datasetPreviewLiveQualityDetail $tree $parent.detail.value}
            }
            dict set active stale_qualified 1
        }
    }
}
proc ::GX::datasetPreviewLiveCatalogChanged {receipt} {
    # Committed public publications invalidate presentation immediately. The
    # common Preview observer covers external filesystem changes between events.
    datasetPreviewLiveCheck 1
}
proc ::GX::datasetPreviewLiveActivate {id {explicit 0} {sourceRequest {}}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    if {[dict get [datasetViewerDescribe $id] target] ne {scientific} && [winfo exists .top.nb.preview.mapping]} {grid remove .top.nb.preview.mapping}
    if {[catch {interactiveDocumentSessionToken} token]} {
        datasetPreviewLiveSetStatus "Preview unavailable: $token Reopen the Session to retry."
        return
    }
    set restoreOptions {}
    if {[dict exists $active id] && [dict get $active id] eq $id && [dict get $active token] eq $token && !$explicit} {
        datasetPreviewLiveCheck 1
        return
    }
    if {![dict exists $active id] || [dict get $active id] ne $id || [dict get $active token] ne $token} {
        # Retire the previous presentation through the common owner, including
        # its legacy signature/watch. A legacy timer must not cancel this new
        # managed representation after its first activation.
        datasetPreviewStop
        set active [dict create id $id token $token source [datasetPreviewCacheSource $id]]
        dict set active subscription [datasetCatalogSubscribe ::GX::datasetPreviewLiveCatalogChanged]
        set ::GX::ui(previewCacheWatch) [after 1000 ::GX::datasetPreviewCacheWatch]
        datasetPreviewLiveShell
        set w .top.nb.preview.txt;$w configure -state normal;$w delete 1.0 end;$w insert end "Dataset: $id\nPreparing scientific data through a managed CORE Job. The GUI remains available.\n";$w configure -state disabled
        set saved [datasetPreviewConfigurationRead $id]
        if {[dict exists $saved last_render key]} {
            set restoreOptions [dict get $saved last_render options]
            set prior [datasetPreviewCacheRead $id [dict get $saved last_render key] 1]
            if {$prior ne {}} {
                datasetPreviewLiveAdopt $id $prior 1
                if {![dict get $prior current] || [datasetField $id storage_provider {}] eq "remote"} {
                    set generation [incr epoch]
                    dict set active key [datasetPreviewCacheRequest $id [dict get $prior options] [list ::GX::_datasetPreviewLiveReady $id $token $generation 0]]
                }
                return
            }
        }
    }
    if {$sourceRequest ne {}} {dict set active source_window [_datasetPreviewSourceRequestNormalize $id $sourceRequest]}
    set options [expr {$explicit?[datasetPreviewLiveOptions $id]:$restoreOptions}]
    if {$explicit} {dict set active source [datasetPreviewCacheSource $id]}
    set generation [incr epoch]
    datasetPreviewLiveSetStatus {Preparing source-verified Preview in CORE Job Supervisor…}
    dict set active key [datasetPreviewCacheRequest $id $options [list ::GX::_datasetPreviewLiveReady $id $token $generation $explicit]]
}
proc ::GX::_datasetPreviewLivePersistReceipt {id token result} {
    set session $::GX::currentSession
    if {![datasetAuthorityActive $session]} {
        return [datasetAuthorityTransaction $session ::GX::_datasetPreviewLivePersistReceipt $id $token $result]
    }
    # Receipt persistence never materializes automatically discovered scientific
    # controls. Recheck the actual preparation identity after widget adoption.
    if {$token ne [interactiveDocumentSessionToken] ||
        ![datasetPublicationV2DictDefault $result current 1] ||
        [dict get $result source] ne [datasetPreviewCacheSource $id] ||
        [dict get $result key] ne [datasetPreviewCacheKey $id [dict get $result options]]} {return 0}
    set metadata [datasetPrivateMetadataRead $::GX::currentSession $id]
    set saved [datasetPublicationV2DictDefault $metadata _gxtxt.framework.dataset_preview {}]
    if {$saved ne {} && (![dict exists $saved version] || [dict get $saved version]!=1)} {return 0}
    set previous $saved
    dict set saved version 1
    dict set saved last_render [dict create key [dict get $result key] options [dict get $result options]]
    if {$saved eq $previous} {return 1}
    set before [datasetRevisionToken $id $session]
    _datasetFrameworkMetadataUpdate $session $id [dict create dataset_preview $saved]
    set after [datasetRevisionToken $id $session]
    # The successful view was mounted before this CORE-owned private receipt
    # commit. Acknowledge only that exact transaction in current readonly panes;
    # foreign stale baselines and editable drafts keep their full revision guard.
    _previewCppReceiptCommitted $id $token $before $after [dict get [sessionInspectionDatasetPayload $id] sha256]
    return 1
}
proc ::GX::_datasetPreviewLiveReady {id token generation explicit response} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    if {$generation!=$epoch || ![dict exists $active id] || [dict get $active id] ne $id || ![winfo exists .top.nb.preview.live]} return
    if {[catch {interactiveDocumentSessionToken} current]} {
        datasetPreviewLiveSetStatus "Preview unavailable: $current Reopen the Session to retry."
        return
    }
    if {$token ne $current} return
    if {[dict get $response status] eq "preparing"} {datasetPreviewLiveSetStatus "Preview preparation: [dict get $response state] — scientific data remain in CORE";return}
    if {[dict get $response status] ne "ready"} {if {![datasetPreviewLiveRetainSelection $id $token $generation]} return;datasetPreviewLiveSetStatus "Preview unavailable: [dict get $response message] The previous successful view is retained.";return}
    if {[catch {datasetPreviewCacheRead $id [dict get $response key]} result]} {
        # Ready means preparation finished, not that the source is still
        # available at this callback. Keep strict read errors local to this
        # asynchronous consumer, just as for later widget admission errors.
        if {![datasetPreviewLiveRetainSelection $id $token $generation]} return
        datasetPreviewLiveSetStatus "Preview unavailable: $result Select Render to retry."
        return
    }
    if {$result eq {}} {if {![datasetPreviewLiveRetainSelection $id $token $generation]} return;datasetPreviewLiveSetStatus {Source changed or prepared Preview failed integrity validation; Render again.};return}
    if {[catch {datasetPreviewLiveAdopt $id $result [dict get $response cache_hit]} reason]} {
        # A prepared source can change between cache admission and widget
        # admission. Report this asynchronous failure without publishing it as
        # the last render or surfacing a repeated Tk background exception.
        if {![datasetPreviewLiveRetainSelection $id $token $generation]} return
        datasetPreviewLiveSetStatus "Preview unavailable: $reason Select Render to retry."
        return
    }
    if {$generation!=$epoch || ![dict exists $active id] || [dict get $active id] ne $id || [dict get $active token] ne $token} return
    if {[datasetPublicationV2DictDefault $result current 1]} {
        if {[catch {_datasetPreviewLivePersistReceipt $id $token $result} persisted] || !$persisted} {
            datasetPreviewLiveSetStatus {The prepared view is retained; its saved render receipt was not updated. Select Render to refresh.}
        }
    }
}
proc ::GX::datasetPreviewLiveRecoveryCurrent {id token generation} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    expr {$generation==$epoch && [dict exists $active id] && [dict exists $active token] && [dict get $active id] eq $id && [dict get $active token] eq $token && [winfo exists .top.nb.preview.live.panes] && ![catch {interactiveDocumentSessionToken} current] && $current eq $token}
}
proc ::GX::datasetPreviewLiveRetainSelection {id token generation} {
    variable ::GX::PreviewLive::active
    if {![datasetPreviewLiveRecoveryCurrent $id $token $generation]} {return 0}
    if {![dict exists $active representation] || ![dict exists $active rendered_key]} {return 1}
    set successful [datasetPublicationV2DictDefault $active successful_primary_component {}]
    if {$successful eq {}} {dict unset active primary_component} else {dict set active primary_component $successful}
    dict set active key [dict get $active rendered_key]
    dict unset active selection_applied
    # Reconcile the control against the retained successful presentation. A
    # failed requested provider is never displayed as the active result.
    if {[dict exists $active representation source] && ![catch {datasetPreviewCacheSource $id} currentSource] && [dict get $active representation source] eq $currentSource} {
        catch {datasetPreviewLiveExtensionTabs $id [dict get $active representation]}
    } else {
        # Never join an old model/Quality report with freshly read scientific
        # metadata. Keep its existing previous-render qualification and restore
        # the control without calling any provider against that stale frame.
        if {[info exists ::GX::ui(previewPrimaryChoices)]} {dict for {label component} $::GX::ui(previewPrimaryChoices) {if {$component eq $successful} {set ::GX::ui(previewPrimaryChoice) $label;break}}}
        catch {datasetPreviewLiveCheck 1}
    }
    return [datasetPreviewLiveRecoveryCurrent $id $token $generation]
}
proc ::GX::datasetPreviewLiveAdopt {id result cacheHit} {
    variable ::GX::PreviewLive::active
    set f .top.nb.preview;set w $f.txt;set current [datasetPublicationV2DictDefault $result current 1]
    set path $f.live.panes.plot.retainedXY;set reused 0
    if {[dict exists $result native_model]} {
        set model [dict get $result native_model]
        if {!$current} {
            # Keep the previous frame as an explicitly stale representation.
            # Live source subscriptions cannot declare that old receipt current.
            set panels {};foreach panel [dict get $model panels] {set series {};foreach item [dict get $panel series] {lappend series [dict remove $item source_descriptor source_descriptors]};dict set panel series $series;lappend panels $panel};dict set model panels $panels
        }
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        if {[winfo exists $path] && ![datasetDigitizerPreviewHasRecord $id] && [datasetPublicationV2DictDefault $result digitizer {}] eq {}} {
            # The public controller preflights source guards before replacing
            # its buffers. Keep the accepted ordinary numeric view intact if
            # this late admission fails. Digitizer overlays retain their own
            # existing attachment/release owner and are not bypassed here.
            ::GX::PlotDatasetAPIv4::widgetConfigure $path $model {prepared_model 1 retain_presentation 1}
            set reused 1
        }
        if {!$reused} {
            # Digitizer attachment creates its controller through the common
            # owner after its overlay is built. Reject stale replacement source
            # snapshots before clearing the accepted overlay/text/controller.
            ::GX::PlotDatasetAPIv4::widgetValidateSources $model {prepared_model 1 retain_presentation 1}
        }
    }
    # A Render request can fail or be cancelled. Retire the accepted XYZ host
    # only when a replacement has reached adoption and source admission.
    native3DPreviewRelease $f.live.panes.plot
    if {[dict get [datasetViewerDescribe $id] target] eq {scientific} && [dict exists $result axes]} {
        scientificDatasetPreviewControls $id [dict get $result axes] [datasetPublicationV2DictDefault $result dimensions {}]
    } elseif {[winfo exists $f.mapping]} {grid remove $f.mapping}
    datasetDigitizerPreviewClear
    datasetPreviewImageRelease $w
    previewDescriptorClearWidgetArtifact $w
    if {[winfo exists $w.imageProperties]} {destroy $w.imageProperties}
    foreach child [winfo children $f.live.panes.plot] {if {!$reused || $child ne $path} {destroy $child}}
    $w configure -state normal;$w delete 1.0 end
    $w insert end "Dataset: $id\n[datasetPublicationV2DictDefault $result description {}]\n"
    if {[dict exists $result digitizer] && [dict get $result digitizer] ne {}} {
        # A restored previous representation has its own preparation source.
        # Never recertify its old curves with today's source identity.
        set digitizer [dict get $result digitizer]
        dict set digitizer prepared_source [dict get $result source]
        datasetDigitizerPreviewRender $w $id $digitizer
    }
    if {[dict exists $result native_model]} {
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state !disabled}
        if {!$reused && ![datasetDigitizerPreviewAttachNative $id $w $model $f.live.panes.plot]} {
            ::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1 retain_presentation 1}
            pack $path -fill both -expand 1
        }
        $w insert end "[dict get $result row_count] canonical rows; [dict get $result displayed_points] display points. Full scientific data remain canonical.\nWheel zooms; middle drag pans; Fit restores the complete bounds.\n"
    } else {
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state disabled}
        if {[dict exists $result media_artifact]} {
            set directory [datasetPreviewCachePath $::GX::currentSession [dict get $result key]]
            set class [datasetPreviewMediaClass [datasetField $id media_type] [datasetField $id format] [datasetField $id contract [datasetField $id kind]] [datasetField $id path]]
            if {$class eq {image}} {
                # Standard is the actual preexisting CORE image presenter,
                # including properties and manual zoom/Fit, not a text-only
                # descriptor substitute when a companion happens to be active.
                datasetPreviewImagePresent $w $id [dict get $result media_artifact] $directory {} {compact_scale_label 1}
            } else {
                set descriptor [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact [dict get $result media_artifact]] $directory]
                previewDescriptorRenderTextWidget $w $descriptor
            }
        } else {$w insert end [datasetPublicationV2DictDefault $result description {No applicable graphical Preview.}]}
    }
    $w configure -state disabled
    raise $w
    if {[winfo exists $f.imageTools]} {raise $f.imageTools}
    # Every successful adoption retires the initial loading placeholders,
    # including the hidden Details slot. A later status update must never
    # mistake an accepted media surface for an initial text-only placeholder.
    foreach pane {plot details} {
        set loading $f.live.panes.$pane.loading
        if {[winfo exists $loading]} {destroy $loading}
    }
    datasetPreviewLiveQuality $id $result
    datasetPreviewLiveStandardTabs $id $result
    if {![dict exists $active primary_component] && [dict exists $result options primary_component]} {dict set active primary_component [dict get $result options primary_component]}
    set notebook $f.live.panes
    set windowId [winfo id $notebook]
    set owner [list [datasetPublicationV2DictDefault $active id {}] [datasetPublicationV2DictDefault $active token {}] $::GX::PreviewLive::epoch [interactiveDocumentSessionToken]]
    datasetPreviewLiveExtensionTabs $id $result
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner]} return
    dict set active key [dict get $result key];dict set active source [dict get $result source]
    dict set active rendered_key [dict get $result key];dict set active rendered_options [dict get $result options]
    dict set active stale_qualified 0
    dict set active watch_stamp [datasetPreviewLiveWatchStamp]
    set text [expr {$current?($cacheHit?"Session cache hit — source-verified retained Preview":"Prepared retained Preview — source-verified"):"Previous render — scientific source changed"}]
    if {$current && $cacheHit} {
        set selected [datasetPreviewLiveOptions $id];set rendered [dict get $result options]
        foreach field {x y z selections ordering processed_image} {
            if {[datasetPublicationV2DictDefault $selected $field {}] ne [datasetPublicationV2DictDefault $rendered $field {}] && [dict exists $rendered $field]} {set text {Previous render — settings changed. Select Render to apply.};break}
        }
    }
    if {[dict exists $result remote_unverified]} {set text {Previous remote render — verifying authoritative source availability and revision…}}
    if {$current && [dict exists $result digitizer unavailable_selection]} {set text {Selected processed image is unavailable. Choose Original source image to render the verified original.}}
    set visibilityNotice [_datasetDigitizerPreviewVisibilityNotice $id]
    if {$visibilityNotice ne {}} {append text " — $visibilityNotice"}
    datasetPreviewLiveSetStatus $text
    datasetPreviewActionsState
    if {!$current} {datasetPreviewLiveCheck 1}
}
proc ::GX::datasetPreviewLiveQuality {id representation} {
    set parent .top.nb.preview.live.panes.quality
    foreach child [winfo children $parent] {destroy $child}
    set quality {};set rows {}
    if {[dict exists $representation digitizer quality]} {set quality [dict get $representation digitizer quality]}
    if {$quality eq {}} {
        ttk::label $parent.empty -text {No published Quality report is available for this Dataset. Missing diagnostics or uncertainty do not imply zero error. Preview does not infer accuracy from the image.} -wraplength 600 -justify left -padding 16
        pack $parent.empty -fill x -anchor nw
        bind $parent.empty <Configure> [list $parent.empty configure -wraplength %w]
        return
    }
    ttk::label $parent.explanation -text {Published Curve Digitizer Quality v2 · read-only. Provider fields are reported unchanged; the separate CORE receipt describes source-byte verification at preparation. Image/spacing diagnostics do not establish physical accuracy or uncertainty.} -wraplength 800 -justify left -padding 8
    pack $parent.explanation -fill x
    bind $parent.explanation <Configure> [list $parent.explanation configure -wraplength %w]
    ttk::frame $parent.table;pack $parent.table -fill both -expand 1 -padx 8
    set tree $parent.table.rows
    ttk::treeview $tree -columns {value unit meaning} -show {tree headings} -selectmode browse -height 12
    $tree heading #0 -text Diagnostic;$tree column #0 -width 240 -minwidth 140 -stretch 1
    foreach {column title width} {value Value 240 unit Unit 70 meaning Meaning 480} {$tree heading $column -text $title;$tree column $column -width $width -minwidth 60 -stretch 1}
    ttk::scrollbar $parent.table.y -command [list $tree yview]
    ttk::scrollbar $parent.table.x -orient horizontal -command [list $tree xview]
    $tree configure -yscrollcommand [list $parent.table.y set] -xscrollcommand [list $parent.table.x set]
    grid $tree -row 0 -column 0 -sticky nsew;grid $parent.table.y -row 0 -column 1 -sticky ns;grid $parent.table.x -row 1 -column 0 -sticky ew
    grid rowconfigure $parent.table 0 -weight 1;grid columnconfigure $parent.table 0 -weight 1
    foreach {field label unit meaning} {
        source_dataset_id {Source Dataset} {} {Canonical image identity recorded by the publication}
        source_integrity {Provider-reported source integrity} {} {Unchanged installed-provider result; this field alone is not independent CORE current-byte verification}
        source_sha256 {Published source SHA256} {} {Original image fingerprint; not a calibration measurement}
        source_current_sha256 {Provider-reported source SHA256} {} {Digest reported by the installed provider; its implementation determines whether it was measured or read from recorded metadata}
        status {Published quality status} {} {Publisher's diagnostic status, not measured accuracy}
        issue_count {Reported issues} count {Published diagnostic count}
        unique_raster_point_count {Unique raster points} count {Source point identities; publication may contain multiple calibration realizations}
        published_row_count {Published rows} count {Actual rows recorded by the publisher}
        curve_count Curves count {Published curve identities}
        calibration_realization_count {Calibration realizations} count {Alternative declared calibrations, not repeated physical measurements}
        segment_count Segments count {Published within-curve segments}
        image_evidence_available {Image evidence available} {} {Local raster evidence does not establish physical accuracy}
        accuracy_status {Physical accuracy} {} {The public Quality contract does not infer measured accuracy}
        uncertainty_status {Uncertainty declaration} {} {Absent declaration is not zero uncertainty; declared propagation retains its published assumptions}
    } {
        set value [datasetPublicationV2DictDefault $quality $field {}]
        if {$value eq {}} {set value {Not supplied}}
        lappend rows [dict create label $label value $value unit $unit meaning $meaning]
    }
    lappend rows {*}[datasetPublicationV2DictDefault [dict get $representation digitizer] quality_rows {}]
    set ordinal 0
    foreach row $rows {$tree insert {} end -id quality[incr ordinal] -text [dict get $row label] -values [list [dict get $row value] [dict get $row unit] [dict get $row meaning]]}
    # Existing numeric Quality row IDs remain stable, including summary rows.
    # New host observations have semantic IDs for stale-render qualification.
    set verification [datasetPublicationV2DictDefault [dict get $representation digitizer] host_source_verification \
        [dict create status unverified reason {This representation has no independent CORE source receipt. Render to verify.}]]
    foreach {field row label meaning} {
        status host_source_status {CORE source-byte verification} {Independent existing canonical/resource owner check for this preparation only}
        observed_sha256 host_source_digest {CORE observed source SHA256} {Actual source bytes verified by the named owner, or observed only after a failed canonical check; status and reason remain authoritative}
        published_expected_sha256 host_source_expected {Publication source SHA256} {Expected source identity retained by the publication; never replaced with newly observed bytes}
        registered_expected_sha256 host_source_registered {Registered source SHA256 at preparation} {Recorded canonical identity; not itself a current-byte measurement}
        method host_source_method {CORE verification owner} {Existing public owner used by the host; no provider output or registry meaning is changed}
        checked_at_utc host_source_checked_at {CORE observation time (UTC)} {Preparation observation time; a stale render requires a new check}
        reason host_source_reason {CORE verification details} {Missing, rejected or unsupported sources are not treated as verified}
    } {
        set value [datasetPublicationV2DictDefault $verification $field {}]
        if {$value eq {}} {set value {Not observed}}
        $tree insert {} end -id $row -text $label -values [list $value {} $meaning]
    }
    ttk::labelframe $parent.detail -text {Selected diagnostic} -padding 6
    text $parent.detail.value -height 4 -width 1 -wrap word -font TkDefaultFont -relief flat -highlightthickness 0
    $parent.detail.value insert 1.0 {Select a row to read its complete value, unit and meaning.}
    $parent.detail.value configure -state disabled
    ttk::scrollbar $parent.detail.scroll -command [list $parent.detail.value yview]
    $parent.detail.value configure -yscrollcommand [list $parent.detail.scroll set]
    grid $parent.detail.value -row 0 -column 0 -sticky nsew
    grid $parent.detail.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $parent.detail 0 -weight 1
    pack $parent.detail -fill x -padx 8 -pady 4
    bind $tree <<TreeviewSelect>> [list ::GX::datasetPreviewLiveQualityDetail $tree $parent.detail.value]
    ttk::frame $parent.actions;pack $parent.actions -fill x -padx 8 -pady 6
    ttk::button $parent.actions.full -text {Inspect full published report…} -command [list ::GX::datasetDigitizerQualityInspect [dict get $quality report_json]]
    ttk::button $parent.actions.copy -text {Copy full published report} -command [list ::GX::datasetMetadataCopyValue [dict get $quality report_json]]
    pack $parent.actions.full $parent.actions.copy -side left -padx 4
    # Reserve footer/detail space before the flexible table takes the remaining
    # viewport. A short viewport must not hide scientific details or actions.
    pack forget $parent.table $parent.detail $parent.actions
    pack $parent.actions -side bottom -fill x -padx 8 -pady 6
    pack $parent.detail -side bottom -fill x -padx 8 -pady 4
    pack $parent.table -side top -fill both -expand 1 -padx 8
}
proc ::GX::datasetPreviewLiveQualityDetail {tree label} {
    if {![winfo exists $tree] || ![winfo exists $label]} return
    set selected [lindex [$tree selection] 0]
    if {$selected eq {} || ![$tree exists $selected]} return
    lassign [$tree item $selected -values] value unit meaning
    if {$unit ne {}} {append value " $unit"}
    $label configure -state normal
    $label delete 1.0 end
    $label insert 1.0 "[$tree item $selected -text]\n$value\n$meaning"
    $label configure -state disabled
}
proc ::GX::datasetPreviewLiveNavigationTarget {} {
    set path .top.nb.preview.live.panes.plot.retainedXY
    set notebook .top.nb.preview.live.panes
    if {![winfo exists $notebook]} {return {}}
    set selected [$notebook select]
    if {[info exists ::GX::ui(previewExtensionTabs)] && [dict exists $::GX::ui(previewExtensionTabs) $selected]} {
        # Preserve the existing direct-Plot extension contract. Other managed
        # presentations own their view controls; never escape to a hidden CORE
        # pane or guess a private nested widget from the module's implementation.
        if {[winfo exists $selected.plot]} {return $selected.plot}
        return {}
    }
    if {![winfo exists $path] || "$notebook.plot" ni [$notebook tabs] || [$notebook tab $notebook.plot -state] eq {hidden}} {return {}}
    return $path
}
proc ::GX::datasetPreviewLiveNavigationRefresh {} {
    set root .top.nb.preview.live
    if {![winfo exists $root.actions.fit]} return
    set state [expr {[datasetPreviewLiveNavigationTarget] eq {}?{disabled}:{!disabled}}]
    foreach button {fit zoomIn zoomOut} {$root.actions.$button state $state}
    datasetPreviewLiveHeaderLayout [expr {[info exists ::GX::ui(previewPrimaryChoices)] && [dict size $::GX::ui(previewPrimaryChoices)]>1}]
}
proc ::GX::datasetPreviewLiveView {operation} {
    if {$operation ni {fit zoom_in zoom_out}} {error {Unknown Preview navigation operation}}
    set path [datasetPreviewLiveNavigationTarget]
    if {$path eq {}} {
        datasetPreviewLiveNavigationRefresh
        datasetPreviewLiveSetStatus {Use the current Preview's view controls, or select Standard for CORE navigation.}
        return
    }
    set notebook .top.nb.preview.live.panes
    $notebook select [winfo parent $path]
    if {[catch {
        switch $operation {
            fit {::GX::PlotDatasetAPIv4::widgetView $path fit}
            zoom_in {::GX::PlotDatasetAPIv4::widgetView $path zoom main 1.25 .5 .5}
            zoom_out {::GX::PlotDatasetAPIv4::widgetView $path zoom main .8 .5 .5}
        }
    } reason]} {
        # Buttons are UI notifications just like wheel/Fit gestures. Keep the
        # public controller's strict guards, but report a rejected old render
        # in the existing status rather than a repeated Tk background dialog.
        datasetPreviewLiveSetStatus "Previous render — $reason Select Render to refresh."
    }
}
proc ::GX::datasetPreviewLiveSettingsChanged {} {
    datasetPreviewLiveSetStatus {Previous render — settings changed. Select Render to apply.}
}

# Keep the retained 2D generation message even while its independently admitted
# XYZ overlay is visible. Closing 3D restores that exact message; no source or
# options revision is acknowledged by this presentation-only reconciliation.
proc ::GX::datasetPreviewLiveSetStatus {text {level info}} {
    variable ::GX::PreviewLive::active
    if {$level ni {info error}} {error {Unknown Preview status presentation level}}
    if {$active ne {}} {dict set active status_2d $text;dict set active status_level_2d $level}
    # Before the first successful adoption, the initial loading surface is the
    # whole presentation. Project the same lifecycle message there and in its
    # source pane; a terminal error must not leave either claiming preparation.
    # Adoption removes this placeholder, so an accepted frame/source is never
    # overwritten by a later failure, cancellation or previous-render notice.
    set initial 0
    if {[dict exists $active id]} {
        foreach pane {plot details} {
            set loading .top.nb.preview.live.panes.$pane.loading
            if {[winfo exists $loading]} {$loading configure -text $text;set initial 1}
        }
    }
    if {$initial} {
        set source .top.nb.preview.txt
        if {[winfo exists $source]} {
            $source configure -state normal
            $source delete 1.0 end
            $source insert end "Dataset: [dict get $active id]\n$text\n"
            $source configure -state disabled
        }
    }
    datasetPreviewLiveRefreshStatus
}
proc ::GX::datasetPreviewLiveRefreshStatus {} {
    variable ::GX::PreviewLive::active
    set label .top.nb.preview.live.actions.status
    if {![winfo exists $label] || ![dict exists $active id]} return
    set text [datasetPublicationV2DictDefault $active status_2d {Preparing a source-verified scientific view…}]
    set level [datasetPublicationV2DictDefault $active status_level_2d info]
    set xyz [native3DPreviewXYZStatus .top.nb.preview.live.panes.plot [dict get $active id]]
    if {$xyz ne {}} {set text $xyz;set level info}
    dict set active status_visible_full $text
    set font [$label cget -font]
    if {$font eq {}} {set font [ttk::style lookup TLabel -font]}
    if {$font eq {}} {set font TkDefaultFont}
    set available [expr {max(1,[winfo width $label]-4)}]
    set summary [string map [list \n { } \r { } \t { }] $text]
    if {$level eq {error}} {set summary {Refused…}}
    if {[string length $summary]>256} {set summary "[string range $summary 0 252]…"}
    while {[string length $summary]>1 && [font measure $font $summary]>$available} {
        set summary "[string range $summary 0 end-2]…"
    }
    if {[$label cget -text] ne $summary} {$label configure -text $summary}
    native2DViewportTooltip $label "$text\n\nClick or press Enter for the complete status."
}
proc ::GX::datasetPreviewLiveStatusTip {label} {
    variable ::GX::PreviewLive::active
    if {[dict exists $active status_visible_full]} {native2DViewportTooltipShow $label "[dict get $active status_visible_full]\n\nClick or press Enter for the complete status."}
}
proc ::GX::datasetPreviewLiveStatusCopy {text} {clipboard clear;clipboard append -- $text}
proc ::GX::datasetPreviewLiveStatusInspect {} {
    variable ::GX::PreviewLive::active
    set owner .top.nb.preview.live.actions.status
    if {![winfo exists $owner] || ![dict exists $active status_visible_full]} return
    set text "Dataset: [dict get $active id]\nStatus snapshot\n\n[dict get $active status_visible_full]"
    set frame .top.nb.preview.live.selection
    if {[winfo exists $frame] && [winfo manager $frame] ne {}} {append text "\n\nPreview: [$frame.choice get]\n[$frame.reason cget -text]"}
    set w .gxDatasetPreviewStatus
    if {[winfo exists $w]} {uiFieldDialogClose $w}
    native2DViewportTooltipHide $owner
    uiFieldDialogCreate $w $owner {Preview status snapshot} 760x420
    ttk::frame $w.body
    ::text $w.body.text -wrap word -font TkTextFont -width 1 -height 1 -yscrollcommand [list $w.body.scroll set]
    ttk::scrollbar $w.body.scroll -orient vertical -command [list $w.body.text yview]
    grid $w.body.text -row 0 -column 0 -sticky nsew
    grid $w.body.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $w.body 0 -weight 1;grid rowconfigure $w.body 0 -weight 1
    $w.body.text insert 1.0 $text;$w.body.text configure -state disabled
    bind $w.body.text <Control-a> [list $w.body.text tag add sel 1.0 end]
    ttk::frame $w.buttons
    ttk::button $w.buttons.copy -text {Copy status} -command [list ::GX::datasetPreviewLiveStatusCopy $text]
    ttk::button $w.buttons.close -text Close -command [list ::GX::datasetPreviewLiveStatusClose $w]
    pack $w.buttons.copy $w.buttons.close -side left -padx 4
    pack $w.buttons -side bottom -anchor e -padx 6 -pady 6
    pack $w.body -fill both -expand 1 -padx 6 -pady 6
    bind $w <Escape> [list ::GX::datasetPreviewLiveStatusClose $w]
    wm protocol $w WM_DELETE_WINDOW [list ::GX::datasetPreviewLiveStatusClose $w]
    uiFieldDialogPresent $w $w.buttons.close
}
proc ::GX::datasetPreviewLiveStatusClose {window} {
    uiFieldDialogClose $window
    set label .top.nb.preview.live.actions.status
    if {[winfo exists $label] && [winfo ismapped $label]} {focus $label}
}

# Compose module-owned descriptor data through the standard Preview renderers.
# These widgets are transient presentation, not another provider/module registry.
proc ::GX::datasetPreviewLiveExtensionCurrent {notebook windowId owner {composition {}}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    variable ::GX::PreviewLive::extensionComposition
    if {![winfo exists $notebook] || [winfo id $notebook] ne $windowId || [catch {interactiveDocumentSessionToken} session]} {return 0}
    if {$composition ne {} && $composition != $extensionComposition} {return 0}
    expr {$owner eq [list [datasetPublicationV2DictDefault $active id {}] [datasetPublicationV2DictDefault $active token {}] $epoch $session]}
}
proc ::GX::datasetPreviewLiveExtensionTabs {id representation} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    variable ::GX::PreviewLive::extensionComposition
    set notebook .top.nb.preview.live.panes
    if {![winfo exists $notebook] || [catch {interactiveDocumentSessionToken} session]} return
    if {![dict exists $active id] || [dict get $active id] ne $id || [dict get $active token] ne $session} return
    # Managed mounts service Tk while their worker is pending. A nested refresh
    # can have the same Dataset/Session/epoch and still replace this composition.
    set composition [incr extensionComposition]
    set windowId [winfo id $notebook]
    set owner [list [datasetPublicationV2DictDefault $active id {}] [datasetPublicationV2DictDefault $active token {}] $epoch $session]
    set previous {};set priorPanes {}
    if {[info exists ::GX::ui(previewExtensionTabs)]} {
        set selected [$notebook select]
        if {[dict exists $::GX::ui(previewExtensionTabs) $selected]} {set previous [dict get $::GX::ui(previewExtensionTabs) $selected]}
        set priorPanes [dict keys $::GX::ui(previewExtensionTabs)]
    }
    set contributions [datasetPreviewProviderTabs $id $representation]
    # Module activation/callbacks can service Tk. An obsolete composition must
    # never remove or populate the replacement Dataset's notebook.
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
    foreach pane $priorPanes {
        if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
        if {[winfo exists $pane]} {destroy $pane}
    }
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
    set ::GX::ui(previewExtensionTabs) {}
    set diagnostics [dict get $contributions diagnostics]
    set selection [datasetPublicationV2DictDefault $contributions selection {}]
    set ordinal 0;set dependencies {};set componentPanes {};set primaryPanes {}
    foreach tab [dict get $contributions tabs] {
        if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
        set pane $notebook.extension${composition}_[incr ordinal]
        ttk::frame $pane
        set paneId [winfo id $pane]
        set failed [catch {
            if {[dict get $tab kind] eq {gui}} {
                set plot $notebook.plot.retainedXY
                if {![winfo exists $plot]} {set plot {}}
                _datasetPreviewGuiMount [dict get $tab component_id] $id $pane $representation $plot [list ::GX::datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition] [dict get $tab id]
                set rendered 1
            } else {set rendered [previewDescriptorTabRender $pane $tab $representation]}
        } reason]
        if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} {
            if {[winfo exists $pane] && [winfo id $pane] eq $paneId} {destroy $pane}
            return
        }
        if {$failed} {
            lappend diagnostics "[dict get $tab component_id]: $reason"
            destroy $pane;continue
        }
        if {!$rendered} {destroy $pane;continue}
        if {[dict get $tab kind] eq {table}} {lappend dependencies [dict get $tab dataset_id]}
        $notebook add $pane -text [dict get $tab label]
        set identity [list [dict get $tab component_id] [dict get $tab id]]
        dict set ::GX::ui(previewExtensionTabs) $pane $identity
        set component [dict get $tab component_id]
        if {![dict exists $componentPanes $component] || ([datasetPublicationV2DictDefault $tab role complementary] eq {primary} && $component ni $primaryPanes)} {dict set componentPanes $component $pane}
        if {[datasetPublicationV2DictDefault $tab role complementary] eq {primary}} {lappend primaryPanes $component}
        if {$identity eq $previous} {$notebook select $pane}
    }
    set identity [datasetPreviewProviderIdentity $id]
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
    dict set active extension_dependency_ids [lsort -unique $dependencies]
    dict set active representation $representation
    dict set active extensions_identity $identity
    dict set active extension_diagnostics $diagnostics
    if {[llength $diagnostics]} {
        # Errors never replace or suppress the working standard Preview.
        set pane $notebook.extensionDiagnostics${composition}
        ttk::frame $pane
        ttk::label $pane.message -text [join $diagnostics \n] -justify left -wraplength 650 -padding 12
        pack $pane.message -fill x -anchor nw
        bind $pane.message <Configure> [list $pane.message configure -wraplength %w]
        $notebook add $pane -text {Component status}
        dict set ::GX::ui(previewExtensionTabs) $pane status
    }
    datasetPreviewLiveSelection $id $representation $selection $componentPanes
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
    set resolution [contractVisualizerResolve [datasetField $id contract [datasetField $id kind {}]] preview $id]
    if {![datasetPreviewLiveExtensionCurrent $notebook $windowId $owner $composition]} return
    if {[dict get $resolution status] eq {selected}} {
        set module [dict get $resolution module_id]
        set declaration [_datasetPreviewProviderDescriptor $module]
        if {[datasetPublicationV2DictDefault $declaration runtime {}] eq {managed_cpp} && [dict exists $componentPanes $module] && [datasetPublicationV2DictDefault $active successful_primary_component {}] eq $module} {
            # A successfully admitted document presentation owns its three
            # canonical panes. Keep the standard fallback when admission fails.
            foreach name {plot source quality table details choice} {if {"$notebook.$name" in [$notebook tabs]} {$notebook hide $notebook.$name}}
            if {[$notebook select] ni [dict keys $::GX::ui(previewExtensionTabs)]} {$notebook select [dict get $componentPanes $module]}
        }
    }
}
proc ::GX::datasetPreviewLiveSelection {id representation selection componentPanes} {
    variable ::GX::PreviewLive::active
    set frame .top.nb.preview.live.selection;set notebook .top.nb.preview.live.panes
    set components [datasetPublicationV2DictDefault $selection primary_components {}]
    set core [datasetPublicationV2DictDefault $selection core_specialized 0]
    set conflict [datasetPublicationV2DictDefault $selection conflict 0]
    set chosen [datasetPublicationV2DictDefault $active primary_component {}]
    set default [datasetPublicationV2DictDefault $selection default_component {}]
    set actualNative {}
    if {[dict exists $representation native_provider component_id] && ![catch {datasetPreviewNativeReceiptCurrent $id [dict get $representation native_provider]} valid] && $valid} {set actualNative [dict get $representation native_provider component_id]}
    set pending [expr {[dict exists $active key] && [dict get $active key] ne [datasetPublicationV2DictDefault $representation key {}]}]
    set fallback 0
    if {$chosen ne {} && $chosen ne {generic} && $chosen ni $components} {
        dict unset active primary_component;set chosen {};set fallback 1
    } elseif {!$pending && $chosen ne {} && $chosen ne {generic} && ![dict exists $componentPanes $chosen] && $chosen ne $actualNative} {
        dict set active primary_component generic;set chosen generic;set fallback 1
    }
    if {$default ne {} && ![dict exists $componentPanes $default] && $default ne $actualNative} {set default {};set fallback 1}
    set choices {};set labels {}
    if {$conflict && $chosen eq {}} {lappend labels {Choose a Preview…};dict set choices {Choose a Preview…} {}}
    lappend labels Standard;dict set choices Standard generic
    foreach component [lsort -dictionary $components] {
        set label [moduleField $component name $component]
        set base $label;set ordinal 1
        while {[dict exists $choices $label]} {set label "$base ([incr ordinal])"}
        lappend labels $label;dict set choices $label $component
    }
    set ::GX::ui(previewPrimaryChoices) $choices
    set displayed [expr {$chosen ne {}?$chosen:($default ne {}?$default:($conflict?{}:{generic}))}]
    set ::GX::ui(previewPrimaryChoice) Standard
    dict for {label component} $choices {if {$component eq $displayed} {set ::GX::ui(previewPrimaryChoice) $label;break}}
    $frame.choice configure -values $labels
    $frame.reason configure -text [expr {$fallback?{Selected Preview unavailable; standard inspection remains available.}:($chosen ne {} && $chosen ne {generic}?{Explicit replacement Preview selected.}:($conflict?{Several compatible previews are available; choose one.}:($default ne {}?{Specialized view for this Dataset.}:{Standard view for this Dataset.})))}]
    native2DViewportTooltipHide $frame.choice
    native2DViewportTooltip $frame.choice "Preview: [$frame.choice get]\n[$frame.reason cget -text]"
    set choice $frame.choice
    if {[focus -displayof $choice] eq $choice} {datasetPreviewLiveSelectionTip $choice}
    datasetPreviewLiveHeaderLayout [expr {[llength $components]>0}]
    set signature [list $id [interactiveDocumentSessionToken] [datasetPublicationV2DictDefault $representation key {}] $chosen $components $default $core $conflict]
    set apply [expr {![dict exists $active selection_applied] || [dict get $active selection_applied] ne $signature}]
    dict set active selection_applied $signature
    if {!$pending} {dict set active successful_primary_component [expr {$displayed ne {generic} && ($chosen ne {} || !$core)?$displayed:{}}]}
    # Explicit replacement is a host presentation choice, independent of the
    # provider's default companion/primary declaration. Hide only after its
    # actual pane has mounted successfully. Remember prior tab visibility so
    # Standard/failure restores precisely those CORE surfaces.
    set replacement [expr {!$pending && $chosen ne {} && $chosen ne {generic} && [dict exists $componentPanes $chosen]}]
    if {[dict exists $active replacement_hidden_tabs]} {
        dict for {pane state} [dict get $active replacement_hidden_tabs] {
            if {[winfo exists $pane] && $pane in [$notebook tabs]} {$notebook tab $pane -state $state}
        }
        dict unset active replacement_hidden_tabs
    }
    if {$replacement} {
        set hidden {}
        foreach name {plot source quality table details choice} {
            set pane $notebook.$name
            if {$pane in [$notebook tabs]} {
                set state [$notebook tab $pane -state]
                if {$state ne {hidden}} {dict set hidden $pane $state;$notebook hide $pane}
            }
        }
        dict set active replacement_hidden_tabs $hidden
    }
    if {$conflict && $chosen eq {} && !$core} {
        if {![winfo exists $notebook.choice.message]} {
            ttk::label $notebook.choice.message -text {Several equally suitable Preview components are available. Select a Preview above. Generic Plot and Table inspection remain available in their tabs.} -wraplength 700 -justify left -padding 16
            pack $notebook.choice.message -fill x -anchor nw
        }
        $notebook add $notebook.choice -text {Choose Preview}
        if {$apply} {$notebook select $notebook.choice}
    } elseif {"$notebook.choice" in [$notebook tabs]} {$notebook hide $notebook.choice}
    if {!$apply} {datasetPreviewLiveNavigationRefresh;return}
    if {$replacement} {$notebook select [dict get $componentPanes $chosen]
    } elseif {$core || $chosen eq {generic}} {
        foreach name [expr {$core && $chosen eq {generic}?{table plot source details}:{plot table source details}}] {
            set pane $notebook.$name
            if {$pane in [$notebook tabs] && [$notebook tab $pane -state] ne {hidden}} {$notebook select $pane;break}
        }
    } elseif {$displayed ne {} && [dict exists $componentPanes $displayed]} {$notebook select [dict get $componentPanes $displayed]
    } elseif {$displayed ne {} && $displayed eq $actualNative && "$notebook.plot" in [$notebook tabs]} {$notebook select $notebook.plot}
    datasetPreviewLiveNavigationRefresh
}
