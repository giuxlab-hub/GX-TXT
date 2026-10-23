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
    bind $f.live <Destroy> [list ::GX::datasetPreviewLiveDestroyed $f.live %W]
    ttk::frame $f.live.actions;pack $f.live.actions -fill x
    foreach {id label operation} {fit Fit fit zoomIn {Zoom in} zoom_in zoomOut {Zoom out} zoom_out} {
        ttk::button $f.live.actions.$id -text $label -command [list ::GX::datasetPreviewLiveView $operation]
        pack $f.live.actions.$id -side left -padx 3 -pady 3
    }
    ttk::button $f.live.actions.cancel -text {Cancel preparation} -command ::GX::datasetPreviewLiveCancel
    ttk::label $f.live.actions.status -text {Preparing a source-verified scientific view…} -anchor w
    pack $f.live.actions.cancel -side right -padx 4;pack $f.live.actions.status -fill x -expand 1 -padx 8
    ttk::notebook $f.live.panes;pack $f.live.panes -fill both -expand 1
    ttk::frame $f.live.panes.plot;ttk::frame $f.live.panes.source;ttk::frame $f.live.panes.quality
    $f.live.panes add $f.live.panes.plot -text Plot
    $f.live.panes add $f.live.panes.source -text {Source image}
    $f.live.panes add $f.live.panes.quality -text Quality
    ttk::label $f.live.panes.plot.loading -text {Loading canonical curves asynchronously…} -anchor center -justify left -wraplength 600 -padding 12
    pack $f.live.panes.plot.loading -fill both -expand 1
    bind $f.live.panes.plot.loading <Configure> [list $f.live.panes.plot.loading configure -wraplength %w]
    grid $w -in $f.live.panes.source -row 0 -column 0 -sticky nsew
    raise $w
    ttk::scrollbar $f.live.panes.source.sy -command [list $w yview];ttk::scrollbar $f.live.panes.source.sx -orient horizontal -command [list $w xview]
    $w configure -yscrollcommand [list $f.live.panes.source.sy set] -xscrollcommand [list $f.live.panes.source.sx set]
    grid $f.live.panes.source.sy -row 0 -column 1 -sticky ns;grid $f.live.panes.source.sx -row 1 -column 0 -sticky ew
    grid columnconfigure $f.live.panes.source 0 -weight 1;grid rowconfigure $f.live.panes.source 0 -weight 1
    return $f.live
}
proc ::GX::datasetPreviewLiveDestroyed {expected actual} {
    if {$expected eq $actual} {datasetPreviewLiveRelease 0}
}
proc ::GX::datasetPreviewLiveRelease {{restore 1}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
    incr epoch
    if {[dict exists $active key]} {datasetPreviewCacheCancel [dict get $active key]}
    if {[dict exists $active subscription]} {datasetCatalogUnsubscribe [dict get $active subscription]}
    if {[info exists ::GX::ui(previewCacheWatch)]} {after cancel $::GX::ui(previewCacheWatch);unset ::GX::ui(previewCacheWatch)}
    native3DPreviewRelease .top.nb.preview.live.panes.plot
    set active {}
    datasetDigitizerPreviewClear
    if {!$restore} return
    set f .top.nb.preview
    if {![winfo exists $f.live]} return
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
    datasetPreviewLiveSetStatus {Preparation cancelled; the last successful view is retained.}
}
proc ::GX::datasetPreviewLiveOptions {id} {
    set options [datasetPreviewConfigurationRead $id]
    set options [dict remove $options last_render version schema_identity types retained_visibility]
    foreach axis {x y z} {if {[info exists ::GX::ui(previewMap,$axis)]} {dict set options $axis $::GX::ui(previewMap,$axis)}}
    if {[info exists ::GX::ui(previewMap,filters)]} {dict set options selections $::GX::ui(previewMap,filters)}
    return $options
}
proc ::GX::datasetPreviewLiveWatchStamp {} {
    variable ::GX::PreviewLive::active
    set id [dict get $active id];set ids [list $id]
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
    return $stamp
}
proc ::GX::datasetPreviewLiveCheck {{force 0}} {
    variable ::GX::PreviewLive::active
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
    if {[catch {set current [datasetPreviewCacheKey $id [dict get $active rendered_options]]}] || $current ne [dict get $active rendered_key]} {
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
proc ::GX::datasetPreviewLiveActivate {id {explicit 0}} {
    variable ::GX::PreviewLive::active;variable ::GX::PreviewLive::epoch
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
    set options [expr {$explicit?[datasetPreviewLiveOptions $id]:$restoreOptions}]
    if {$explicit} {dict set active source [datasetPreviewCacheSource $id]}
    set generation [incr epoch]
    datasetPreviewLiveSetStatus {Preparing source-verified Preview in CORE Job Supervisor…}
    dict set active key [datasetPreviewCacheRequest $id $options [list ::GX::_datasetPreviewLiveReady $id $token $generation $explicit]]
}
proc ::GX::_datasetPreviewLivePersistReceipt {id token result} {
    # Receipt persistence never materializes automatically discovered scientific
    # controls. Recheck the actual preparation identity after widget adoption.
    if {$token ne [interactiveDocumentSessionToken] ||
        ![datasetPublicationV2DictDefault $result current 1] ||
        [dict get $result source] ne [datasetPreviewCacheSource $id] ||
        [dict get $result key] ne [datasetPreviewCacheKey $id [dict get $result options]]} {return 0}
    set metadata [datasetPrivateMetadataRead $::GX::currentSession $id]
    set saved [datasetPublicationV2DictDefault $metadata _gxtxt.framework.dataset_preview {}]
    if {$saved ne {} && (![dict exists $saved version] || [dict get $saved version]!=1)} {return 0}
    dict set saved version 1
    dict set saved last_render [dict create key [dict get $result key] options [dict get $result options]]
    _datasetFrameworkMetadataUpdate $::GX::currentSession $id [dict create dataset_preview $saved]
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
    if {[dict get $response status] ne "ready"} {datasetPreviewLiveSetStatus "Preview unavailable: [dict get $response message]";return}
    if {[catch {datasetPreviewCacheRead $id [dict get $response key]} result]} {
        # Ready means preparation finished, not that the source is still
        # available at this callback. Keep strict read errors local to this
        # asynchronous consumer, just as for later widget admission errors.
        datasetPreviewLiveSetStatus "Preview unavailable: $result Select Render to retry."
        return
    }
    if {$result eq {}} {datasetPreviewLiveSetStatus {Source changed or prepared Preview failed integrity validation; Render again.};return}
    if {[catch {datasetPreviewLiveAdopt $id $result [dict get $response cache_hit]} reason]} {
        # A prepared source can change between cache admission and widget
        # admission. Report this asynchronous failure without publishing it as
        # the last render or surfacing a repeated Tk background exception.
        datasetPreviewLiveSetStatus "Preview unavailable: $reason Select Render to retry."
        return
    }
    if {[datasetPublicationV2DictDefault $result current 1]} {
        if {[catch {_datasetPreviewLivePersistReceipt $id $token $result} persisted] || !$persisted} {
            datasetPreviewLiveSetStatus {The prepared view is retained; its saved render receipt was not updated. Select Render to refresh.}
        }
    }
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
    if {[dict exists $result axes]} {scientificDatasetPreviewControls $id [dict get $result axes] [datasetPublicationV2DictDefault $result dimensions {}]}
    datasetDigitizerPreviewClear
    previewDescriptorClearWidgetArtifact $w
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
        $f.live.panes tab $f.live.panes.plot -state normal
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state !disabled}
        if {!$reused && ![datasetDigitizerPreviewAttachNative $id $w $model $f.live.panes.plot]} {
            ::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1 retain_presentation 1}
            pack $path -fill both -expand 1
        }
        $w insert end "[dict get $result row_count] canonical rows; [dict get $result displayed_points] display points. Full scientific data remain canonical.\nWheel zooms; middle drag pans; Fit restores the complete bounds.\n"
    } else {
        $f.live.panes tab $f.live.panes.plot -state disabled
        $f.live.panes select $f.live.panes.source
        foreach button {fit zoomIn zoomOut} {$f.live.actions.$button state disabled}
        if {[dict exists $result media_artifact]} {
            set directory [datasetPreviewCachePath $::GX::currentSession [dict get $result key]]
            set descriptor [previewDescriptorNormalize [dict create preview_kind artifact preview_artifact [dict get $result media_artifact]] $directory]
            previewDescriptorRenderTextWidget $w $descriptor
        } else {$w insert end [datasetPublicationV2DictDefault $result description {No applicable graphical Preview.}]}
    }
    $w configure -state disabled
    raise $w
    datasetPreviewLiveQuality $id $result
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
proc ::GX::datasetPreviewLiveView {operation} {
    set path .top.nb.preview.live.panes.plot.retainedXY
    if {![winfo exists $path]} return
    .top.nb.preview.live.panes select .top.nb.preview.live.panes.plot
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
proc ::GX::datasetPreviewLiveSetStatus {text} {
    variable ::GX::PreviewLive::active
    if {$active ne {}} {dict set active status_2d $text}
    # Before the first successful adoption, the initial loading surface is the
    # whole presentation. Project the same lifecycle message there and in its
    # source pane; a terminal error must not leave either claiming preparation.
    # Adoption removes this placeholder, so an accepted frame/source is never
    # overwritten by a later failure, cancellation or previous-render notice.
    set loading .top.nb.preview.live.panes.plot.loading
    if {[dict exists $active id] && [winfo exists $loading]} {
        $loading configure -text $text
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
    set xyz [native3DPreviewXYZStatus .top.nb.preview.live.panes.plot [dict get $active id]]
    if {$xyz ne {}} {set text $xyz}
    $label configure -text $text
}
