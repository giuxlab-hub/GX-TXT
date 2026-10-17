# SPDX-License-Identifier: GPL-3.0-or-later
# Additive published-Dataset representation in the existing shared Preview.
namespace eval ::GX::DigitizerPreview {variable state {};variable serial 0}
proc ::GX::datasetDigitizerPreviewClear {} {
    variable ::GX::DigitizerPreview::state
    dict for {key record} $state {
        if {[dict exists $record text_widget] && [winfo exists [dict get $record text_widget]]} {
            set w [dict get $record text_widget]
            foreach tag [$w tag names] {if {[string match digitizer_dataset_* $tag]} {$w tag delete $tag}}
        }
        foreach photo [dict get $record photos] {catch {image delete $photo}}
        foreach widget [dict get $record widgets] {catch {destroy $widget}}
    }
    set state {}
    array unset ::GX::DigitizerPreview::visible *
}
proc ::GX::datasetDigitizerPreviewLink {w id title} {
    variable ::GX::DigitizerPreview::serial
    set tag digitizer_dataset_[incr serial]
    $w insert end "$title: "
    $w insert end $id $tag;$w insert end "\n"
    $w tag configure $tag -foreground #145fa0 -underline 1
    $w tag bind $tag <Button-1> [list ::GX::datasetDigitizerPreviewActivate $id [interactiveDocumentSessionToken] [curveSourceDatasetIdentity $::GX::currentSession $id]]
    $w tag bind $tag <Enter> [list $w configure -cursor hand2]
    $w tag bind $tag <Leave> [list $w configure -cursor arrow]
}
proc ::GX::datasetDigitizerPreviewActivate {id token identity} {
    if {[catch {
        if {$token ne [interactiveDocumentSessionToken] || [curveSourceDatasetIdentity $::GX::currentSession $id] ne $identity} {error {Preview image identity changed. Render the current Dataset again.}}
        datasetBrowserActivate $id
    } reason]} {setStatus $reason 100}
}
proc ::GX::datasetDigitizerPreviewProcessedSelect {token widget} {
    variable ::GX::DigitizerPreview::state
    if {![dict exists $state $token]} return
    set record [dict get $state $token];set id [dict get $record dataset_id]
    if {[dict get $record session_token] ne [interactiveDocumentSessionToken]} {setStatus {Session changed; render again before selecting an image.} 100;return}
    set image [$widget get]
    set configuration [datasetPreviewConfigurationRead $id]
    if {$configuration eq {}} {set configuration [dict create version 1 selections [dict remove $::GX::ui(previewMap,filters) @hidden_filters] ordering $::GX::ui(previewMap,ordering) types $::GX::ui(previewMap,filterTypes)]}
    if {$image eq {Original source image}} {dict set configuration processed_image {}
    } else {
        if {$image ni [dict get $record processed_candidates]} {error {Image is not a verified geometry-preserving derivative}}
        dict set configuration processed_image [dict create dataset_id $image identity [curveSourceDatasetIdentity $::GX::currentSession $image]]
    }
    _datasetFrameworkMetadataUpdate $::GX::currentSession $id [dict create dataset_preview $configuration]
    datasetPreviewRender
}
proc ::GX::datasetDigitizerPreviewAlignedLineage {candidate source} {
    set chain [::GX::CurveDigitizerImage::lineage $candidate]
    if {$source ni [lmap link $chain {dict get $link dataset_id}]} {error {Different original source}}
    set geometry {}
    foreach link $chain {
        set payload [sessionInspectionDatasetPayload [dict get $link dataset_id] $::GX::currentSession]
        if {[dict get $payload sha256] ne [dict get $link output_sha256]} {error {Processed image lineage content changed}}
        set actual [_native2DRasterHelper info [dict get $payload path]]
        if {$geometry eq {}} {set geometry $actual} elseif {$geometry ne $actual} {error {Processed image lineage changed raster geometry}}
    }
    return $chain
}
proc ::GX::datasetDigitizerPreviewFinish {w id} {
    variable ::GX::DigitizerPreview::state
    dict for {token record} $state {
        if {[dict get $record dataset_id] ne $id || ![dict exists $record main_image]} continue
        if {[dict get $record main_image] ne [dict get $record original_image]} {
            $w insert end "\n"
            datasetDigitizerPreviewImage $w [dict get $record original_image] {Original image} $token
        }
    }
}
proc ::GX::datasetDigitizerPreviewImage {w id title token {overlay 0}} {
    variable ::GX::DigitizerPreview::state
    set payload [sessionInspectionDatasetPayload $id $::GX::currentSession]
    if {[datasetField $id contract {}] ne "image.raster"} {error {Associated Dataset is not a canonical Image Dataset}}
    set dimensions [_native2DRasterHelper info [dict get $payload path]]
    lassign $dimensions width height
    set tmp [file tempfile directory];close $tmp;file delete $directory;file mkdir $directory
    try {
        set artifact [datasetPreviewImageArtifact [dict get $payload path] $directory 1]
        if {$artifact eq {}} {error {A bounded source-aligned image preview is unavailable}}
        set photo [image create photo -file [dict get $artifact path]]
    } finally {file delete -force $directory}
    set record [dict get $state $token];dict lappend record photos $photo
    set canvas $w.digitizerImage[llength [dict get $record photos]]
    canvas $canvas -width [image width $photo] -height [image height $photo] -highlightthickness 0 -background white
    $canvas create image 0 0 -anchor nw -image $photo
    dict lappend record widgets $canvas
    dict set state $token $record
    datasetDigitizerPreviewLink $w $id $title
    $w window create end -window $canvas;$w insert end "\n"
    if {$overlay} {
        set expected [dict get $record metadata]
        foreach {field actual} [list curve_digitizer.image_width $width curve_digitizer.image_height $height] {
            if {[dict exists $expected $field] && [dict get $expected $field]!=$actual} {error {Source raster dimensions disagree with the publication; overlay refused}}
        }
        set sx [expr {double([image width $photo])/$width}];set sy [expr {double([image height $photo])/$height}]
        set palette {#0876bd #c84427 #238b45 #8849a3 #a67513 #008b8b #ba3377}
        set i 0
        dict for {curve data} [dict get $record curves] {
            set color [lindex $palette [expr {$i%[llength $palette]}]]
            set points {};set tag curve_$i
            set sourcePoints [dict get $data points];set shown $sourcePoints
            if {[llength $sourcePoints]>2048} {
                native2DEnsure;set scene [::GX::Native2D::core scene]
                try {
                    ::GX::Native2D::core sample_begin $scene [llength $sourcePoints] 2048 0
                    ::GX::Native2D::core sample_push $scene 0 [dict create dtype float64 values [lmap p $sourcePoints {lindex $p 1}]] [dict create dtype float64 values [lmap p $sourcePoints {lindex $p 2}]]
                    set reduced [::GX::Native2D::core sample_finish $scene]
                    set shown [lmap index [dict get $reduced source_rows] {lindex $sourcePoints $index}]
                } finally {::GX::Native2D::core destroy $scene}
            }
            foreach point $shown {
                lassign $point order px py
                set x [expr {($px+.5)*$sx}];set y [expr {($py+.5)*$sy}]
                lappend points $x $y
                $canvas create oval [expr {$x-2.5}] [expr {$y-2.5}] [expr {$x+2.5}] [expr {$y+2.5}] -outline $color -fill $color -tags [list $tag raster_point]
            }
            # Each curve has its own primitive and stable identity. No curve is
            # ever connected to another; raster rows repeat only across calibrations.
            if {[llength $points]>=4 && [llength $shown]==[llength $sourcePoints]} {
                set path {};set previous {}
                set at 0
                foreach p $sourcePoints {
                    set order [lindex $p 0]
                    if {$previous ne {} && $order!=$previous+1} {if {[llength $path]>=4} {$canvas create line {*}$path -fill $color -width 1 -tags $tag};set path {}}
                    lappend path {*}[lrange $points $at [expr {$at+1}]];incr at 2;set previous $order
                }
                if {[llength $path]>=4} {$canvas create line {*}$path -fill $color -width 1 -tags $tag}
            }
            dict set record curves $curve displayed_points [llength $shown]
            dict set record curves $curve color $color;dict set record curves $curve tag $tag
            incr i
        }
        dict set record canvas $canvas;dict set record source_size [list $width $height]
        dict set state $token $record
    }
    return $canvas
}
proc ::GX::datasetDigitizerPreviewToggle {token curve} {
    variable ::GX::DigitizerPreview::state
    if {![dict exists $state $token]} return
    set record [dict get $state $token]
    if {[dict get $record session_token] ne [interactiveDocumentSessionToken]} {error {Preview belongs to another Session lifetime}}
    set show [set ::GX::DigitizerPreview::visible($token,$curve)]
    if {[dict exists $record native_widget]} {
        foreach series [datasetPublicationV2DictDefault [dict get $record native_series] $curve {}] {::GX::PlotDatasetAPIv4::widgetVisibility [dict get $record native_widget] main $series $show}
    }
    [dict get $record canvas] itemconfigure [dict get $record curves $curve tag] -state [expr {$show?"normal":"hidden"}]
    set hidden {}
    dict for {identity data} [dict get $record curves] {
        if {![set ::GX::DigitizerPreview::visible($token,$identity)]} {lappend hidden [dict create filter_variable_id [dict get $record curve_variable] predicate not_equal value $identity]}
    }
    dict set ::GX::ui(previewMap,filters) @hidden_filters $hidden
    set ::GX::ui(previewRasterVisibility) [dict create identity [dict get $record visibility_identity] hidden $hidden]

}
proc ::GX::datasetDigitizerPreviewHasRecord {id} {
    dict for {token record} $::GX::DigitizerPreview::state {if {[dict get $record dataset_id] eq $id && [dict exists $record canvas]} {return 1}}
    return 0
}
proc ::GX::datasetDigitizerPreviewAttachNative {id w model} {
    variable ::GX::DigitizerPreview::state
    if {![datasetDigitizerPreviewHasRecord $id]} {return 0}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    dict for {token record} $state {
        if {[dict get $record dataset_id] ne $id || ![dict exists $record canvas]} continue
        set path $w.retainedXY;set mapping {}
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1}
        foreach series [dict get [lindex [dict get $model panels] 0] series] {
            foreach filter [dict get $series filters] {
                if {[dict get $filter filter_variable_id] eq [dict get $record curve_variable] && [dict get $filter predicate] eq "exact_equal"} {
                    set curve [dict get $filter value]
                    dict lappend mapping $curve [dict get $series id]
                    if {[info exists ::GX::DigitizerPreview::visible($token,$curve)] && !$::GX::DigitizerPreview::visible($token,$curve)} {::GX::PlotDatasetAPIv4::widgetVisibility $path main [dict get $series id] 0}
                }
            }
        }
        dict set record native_widget $path;dict set record native_series $mapping;dict lappend record widgets $path;dict set state $token $record
        $w window create end -window $path
        return 1
    }
    return 0
}
proc ::GX::datasetDigitizerPreviewRender {w id} {
    variable ::GX::DigitizerPreview::state
    variable ::GX::DigitizerPreview::serial
    set manifest [datasetPreviewCurveManifest $id]
    if {$manifest eq {}} {return 0}
    set columns [dict get $manifest columns]
    set md [datasetMetadataRead $::GX::currentSession $id]
    set token digitizer-preview-[incr serial]
    set visibilityIdentity [list [interactiveDocumentSessionToken] [curveSourceDatasetIdentity $::GX::currentSession $id] [dict remove $::GX::ui(previewMap,filters) @hidden_filters]]
    set hidden {}
    if {[info exists ::GX::ui(previewRasterVisibility)] && [dict get $::GX::ui(previewRasterVisibility) identity] eq $visibilityIdentity} {set hidden [dict get $::GX::ui(previewRasterVisibility) hidden]}
    dict set ::GX::ui(previewMap,filters) @hidden_filters $hidden
    dict set state $token [dict create dataset_id $id session_token [interactiveDocumentSessionToken] metadata $md photos {} widgets {} curves {} text_widget $w curve_variable [dict get $columns curve_key] visibility_identity $visibilityIdentity]
    $w insert end "Curve Digitalizer publication — source raster and published Quality\n"
    if {![dict get $manifest raster_points_available]} {$w insert end "Original raster coordinates are unavailable in this historical publication.\n";return 1}
    set source [datasetPublicationV2DictDefault $md curve_digitizer.source_dataset_id {}]
    set expected [datasetPublicationV2DictDefault $md curve_digitizer.source_sha256 {}]
    set original $source;set main $source;set title {Original image}
    modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1
    if {$source eq {} || $expected eq {}} {error {The publication has no verifiable canonical source image identity}}
    set payload [sessionInspectionDatasetPayload $source $::GX::currentSession]
    if {![string equal -nocase [dict get $payload sha256] $expected]} {error {Source image changed; aligned overlay refused}}
    if {[::GX::CurveDigitizerImage::hasManifest $source]} {
        set chain [datasetDigitizerPreviewAlignedLineage $source $source]
        set original [dict get [lindex $chain end] dataset_id];set title {Processed image (verified identity raster transform)}
    }
    # A derivative can replace the main image only with an explicit forward
    # association. Reverse lineage alone cannot choose among processing branches.
    set processed [datasetPublicationV2DictDefault $md curve_digitizer.processed_dataset_id {}]
    set config [datasetPreviewConfigurationRead $id]
    set chosen [datasetPublicationV2DictDefault $config processed_image {}]
    if {$chosen ne {}} {
        set processed {}
        if {[catch {
            set selected [dict get $chosen dataset_id]
            if {[curveSourceDatasetIdentity $::GX::currentSession $selected] ne [dict get $chosen identity]} {error {Selected processed image changed}}
            set processed $selected
        } reason]} {$w insert end "$reason; using the verified source image.\n"}
    }
    if {$processed ne {}} {
        if {[catch {
            set chain [datasetDigitizerPreviewAlignedLineage $processed $source]
            sessionInspectionDatasetPayload $processed $::GX::currentSession
            set main $processed;set original [dict get [lindex $chain end] dataset_id]
            set title {Processed image (verified identity raster transform)}
        } reason]} {$w insert end "Associated processed image unavailable: $reason. Using the verified source image.\n"}
    }
    set candidates {}
    foreach candidate [sessionInspectionDatasetIds $::GX::currentSession] {
        if {$candidate eq $source || [datasetField $candidate contract {}] ne "image.raster"} continue
        if {[catch {
            set chain [datasetDigitizerPreviewAlignedLineage $candidate $source]
            sessionInspectionDatasetPayload $candidate $::GX::currentSession
            if {[llength $candidates]<64} {lappend candidates $candidate}
        }]} continue
    }
    if {$candidates ne {}} {
        set choice $w.digitizerProcessed$serial;ttk::frame $choice
        ttk::label $choice.label -text {Aligned background (explicit selection; no newest-image inference):}
        ttk::combobox $choice.value -values [linsert $candidates 0 {Original source image}] -state readonly -width 45
        $choice.value set [expr {$main eq $source?{Original source image}:$main}]
        bind $choice.value <<ComboboxSelected>> [list ::GX::datasetDigitizerPreviewProcessedSelect $token $choice.value]
        pack $choice.label $choice.value -side left -padx 3
        set record [dict get $state $token];dict lappend record widgets $choice;dict set record processed_candidates $candidates;dict set state $token $record
        $w window create end -window $choice;$w insert end "\n"
    }
    dict set state $token main_image $main
    dict set state $token original_image $original
    set ids [lsort -unique [dict values $columns]]
    set filters [datasetPublicationV2DictDefault $::GX::ui(previewMap,filters) @predicates {}]
    foreach d $::GX::ui(previewMap,dimensions) {
        set vid [dict get $d variable_id]
        set values [datasetPublicationV2DictDefault $::GX::ui(previewMap,filters) $vid {}]
        if {[llength $values]} {lappend filters [dict create filter_variable_id $vid predicate in_set values $values]}
    }
    set filters [graphSeriesNormalizeFilters $id $filters]
    foreach filter $filters {set vid [dict get $filter filter_variable_id];if {$vid ni $ids} {lappend ids $vid}}
    set stream [tableStreamOpenDataset $::GX::currentSession $id $ids 2048 {numeric_transport values}]
    set curves {};set identities {};set rows 0
    try {
        while 1 {
            set chunk [tableStreamNext $stream];set values [dict get $chunk values]
            for {set i 0} {$i<[dict get $chunk row_count]} {incr i} {
                set accepted 1
                foreach filter $filters {if {![::GX::GraphSelectionAPIv1::_matchesFilter [lindex [dict get $values [dict get $filter filter_variable_id]] $i] $filter]} {set accepted 0;break}}
                if {!$accepted} continue
                set row {}
                dict for {role vid} $columns {dict set row $role [lindex [dict get $values $vid] $i]}
                set curve [dict get $row curve_key];set order [dict get $row point_order]
                if {![string is entier -strict $order]} {error {Invalid published within-curve point identity}}
                set point [list $order [dict get $row raster_x] [dict get $row raster_y]]
                foreach value [lrange $point 1 end] {if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Nonfinite raster point; aligned overlay unavailable}}}
                set identity [list $curve $order]
                if {[dict exists $identities $identity]} {
                    if {[dict get $identities $identity] ne $point} {error {Calibration realizations disagree on original raster point identity}}
                    continue
                }
                # Finite retained raster receipt; refuse oversized overlays
                # truthfully rather than dropping a scientific source domain.
                if {[dict size $identities]>=65536} {error {Raster overlay exceeds 65536 unique points; canonical table retains the complete publication}}
                dict set identities $identity $point
                if {![dict exists $curves $curve]} {dict set curves $curve [dict create label [dict get $row curve_name] points {}]}
                set data [dict get $curves $curve];dict lappend data points $point;dict set curves $curve $data
                incr rows
            }
            if {[dict get $chunk eof]} break
        }
    } finally {tableStreamClose $stream}
    dict for {curve data} $curves {dict set data points [lsort -integer -index 0 [dict get $data points]];dict set curves $curve $data}
    dict set state $token curves $curves
    datasetDigitizerPreviewImage $w $main $title $token 1
    set table $w.digitizerCurves$serial;ttk::labelframe $table -text {Curve visibility — unique source points, independent of calibration realizations}
    set record [dict get $state $token];dict lappend record widgets $table;dict set state $token $record
    set i 0
    dict for {curve data} [dict get $record curves] {
        set show 1
        foreach filter $hidden {if {[dict get $filter value] eq $curve} {set show 0}}
        set ::GX::DigitizerPreview::visible($token,$curve) $show
        if {!$show} {[dict get $record canvas] itemconfigure [dict get $data tag] -state hidden}
        ttk::checkbutton $table.show$i -text {Show / Hide} -variable ::GX::DigitizerPreview::visible($token,$curve) -command [list ::GX::datasetDigitizerPreviewToggle $token $curve]
        ttk::label $table.label$i -text "[dict get $data label] — $curve" -foreground [dict get $data color]
        ttk::label $table.count$i -text "[llength [dict get $data points]] unique points; [dict get $data displayed_points] markers"
        grid $table.show$i $table.label$i $table.count$i -sticky w -padx 8 -pady 2
        incr i
    }
    $w window create end -window $table;$w insert end "\nAt most 2048 source markers per curve are shown. Reduced raster displays retain source extents and show markers without interpolated connecting lines.\nQuality — published snapshot (not the current editable draft)\n"
    modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_QUALITY_API_v2
    if {[::GX::CurveDigitizerQuality::hasReport $id]} {
        set quality [::GX::CurveDigitizerQuality::read $id]
        foreach {field label} {status {Diagnostic status} issue_count {Reported diagnostic issues} unique_raster_point_count {Reported unique raster points} published_row_count {Published rows} curve_count Curves calibration_realization_count {Calibration realizations} segment_count {Inspected segments} image_evidence_available {Image evidence available} accuracy_status {Physical accuracy assessment} uncertainty_status {Physical uncertainty declaration} source_integrity {Recorded source integrity}} {
            set value [datasetPublicationV2DictDefault $quality $field {}]
            if {$value eq {}} {set value {Not supplied}}
            $w insert end "$label: $value\n"
        }
        $w insert end "Diagnostic issues and image observations are not measured physical errors. Missing uncertainty does not imply zero uncertainty. Segment diagnostics may be bounded; raster points above come from the canonical Dataset.\n"
        if {[catch {
            set lines [exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python dataset_digitizer_quality_summary_v1.py] << [dict get $quality report_json]]
            foreach line [split $lines \n] {if {$line ne {}} {$w insert end "[encoding convertfrom utf-8 [binary decode base64 -strict $line]]\n"}}
        } reason]} {$w insert end "Detailed published Quality unavailable: $reason\n"}
        ttk::button $table.report -text {Inspect full Quality report…} -command [list ::GX::datasetDigitizerQualityInspect [dict get $quality report_json]]
        grid $table.report -columnspan 3 -sticky w -padx 8 -pady 5
        dict set state $token quality $quality
    } else {$w insert end "Quality v2 is unavailable in this historical Dataset. Accuracy and physical uncertainty have not been inferred; missing information is not zero errors.\n"}
    dict set state $token unique_point_count $rows
    $w insert end "\nCalibrated X/Y — independent scientific series\n"
    return 1
}
proc ::GX::datasetDigitizerQualityInspect {json} {
    set w .gxDigitizerQuality;catch {destroy $w};toplevel $w;wm title $w {Published Quality v2 report — read-only}
    text $w.value -width 100 -height 25 -wrap word -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.value yview]
    pack $w.scroll -side right -fill y;pack $w.value -fill both -expand 1
    $w.value insert 1.0 $json;$w.value configure -state disabled
    ttk::button $w.copy -text {Copy full report} -command [list ::GX::datasetMetadataCopyValue $json];pack $w.copy -anchor e
}
