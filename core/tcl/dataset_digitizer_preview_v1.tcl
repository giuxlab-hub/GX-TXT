# SPDX-License-Identifier: GPL-3.0-or-later
# Additive published-Dataset representation in the existing shared Preview.
namespace eval ::GX::DigitizerPreview {variable state {};variable serial 0}
proc ::GX::datasetDigitizerPreviewClear {} {
    variable ::GX::DigitizerPreview::state
    dict for {key record} $state {
        if {[dict exists $record visibility_after]} {after cancel [dict get $record visibility_after];datasetDigitizerPreviewVisibilitySave $key}
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
    set record [dict get $state $token]
    if {![dict exists $record images $id]} {error {Prepared source image is unavailable}}
    set imageInfo [dict get $record images $id]
    lassign [dict get $imageInfo size] width height
    set photo [image create photo -file [dict get $imageInfo path]]
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
            set budget [expr {max(6,2048/max(1,[dict size [dict get $record curves]]))}]
            if {[llength $sourcePoints]>$budget} {
                native2DEnsure;set scene [::GX::Native2D::core scene]
                try {
                    ::GX::Native2D::core sample_begin $scene [llength $sourcePoints] $budget 0
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
    if {[dict exists $record canvas]} {[dict get $record canvas] itemconfigure [dict get $record curves $curve tag] -state [expr {$show?"normal":"hidden"}]}
    set hidden {}
    dict for {identity data} [dict get $record curves] {
        if {![set ::GX::DigitizerPreview::visible($token,$identity)]} {lappend hidden [dict create filter_variable_id [dict get $record curve_variable] predicate not_equal value $identity]}
    }
    dict set ::GX::ui(previewMap,filters) @hidden_filters $hidden
    set ::GX::ui(previewRasterVisibility) [dict create identity [dict get $record visibility_identity] hidden $hidden]
    if {[dict exists $record visibility_after]} {after cancel [dict get $record visibility_after]}
    dict set state $token visibility_after [after 750 [list ::GX::datasetDigitizerPreviewVisibilitySave $token]]
}
proc ::GX::datasetDigitizerPreviewVisibilitySave {token} {
    variable ::GX::DigitizerPreview::state
    if {![dict exists $state $token]} return
    set record [dict get $state $token]
    if {[dict get $record session_token] ne [interactiveDocumentSessionToken]} return
    set hidden {};dict for {curve data} [dict get $record curves] {if {!$::GX::DigitizerPreview::visible($token,$curve)} {lappend hidden [dict create filter_variable_id [dict get $record curve_variable] predicate not_equal value $curve]}}
    set saved [datasetPreviewConfigurationRead [dict get $record dataset_id]]
    if {![dict exists $saved version]} {set saved [dict create version 1 selections {} ordering {} types {}]}
    dict set saved selections @hidden_filters $hidden
    _datasetFrameworkMetadataUpdate $::GX::currentSession [dict get $record dataset_id] [dict create dataset_preview $saved]
    dict unset state $token visibility_after
}
proc ::GX::datasetDigitizerPreviewHasRecord {id} {
    dict for {token record} $::GX::DigitizerPreview::state {if {[dict get $record dataset_id] eq $id && [dict size [dict get $record curves]]} {return 1}}
    return 0
}
proc ::GX::datasetDigitizerPreviewAttachNative {id w model {parent {}}} {
    variable ::GX::DigitizerPreview::state
    if {![datasetDigitizerPreviewHasRecord $id]} {return 0}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    dict for {token record} $state {
        if {[dict get $record dataset_id] ne $id || ![dict size [dict get $record curves]]} continue
        set path [expr {$parent eq {}?"$w.retainedXY":"$parent.retainedXY"}];set mapping {}
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1 retain_presentation 1}
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
        if {$parent eq {}} {$w window create end -window $path} else {pack $path -fill both -expand 1}
        return 1
    }
    return 0
}
proc ::GX::datasetDigitizerPreviewPrepare {id selections dimensions directory {processedSelection {}}} {
    set manifest [datasetPreviewCurveManifest $id]
    if {$manifest eq {}} {return {}}
    set md [datasetMetadataRead $::GX::currentSession $id]
    set columns [dict get $manifest columns]
    set raster [dict get $manifest raster_points_available]
    set result [dict create dataset_id $id metadata $md curve_variable [dict get $columns curve_key] curves {} images {} raster_available $raster]
    set source [datasetPublicationV2DictDefault $md curve_digitizer.source_dataset_id {}]
    set expected [datasetPublicationV2DictDefault $md curve_digitizer.source_sha256 {}]
    if {$source ne {} && $expected ne {}} {
        if {[catch {
            set payload [sessionInspectionDatasetPayload $source $::GX::currentSession]
            if {[dict get $payload sha256] ne $expected} {error {Source image changed; aligned overlay refused}}
            set sizes [_native2DRasterHelper info [dict get $payload path]]
            set artifact [datasetPreviewImageArtifact [dict get $payload path] $directory 1]
            set target [file join $directory raster.png]
            if {[dict get $artifact path] ne $target} {file copy -force [dict get $artifact path] $target}
            dict set result images $source [dict create path $target size $sizes sha256 $expected]
            dict set result main_image $source;dict set result original_image $source
        } message]} {dict set result image_message $message}
    }
    dict set result processed_candidates {}
    if {[dict exists $result original_image]} {
        modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1
        foreach candidate [datasetRegistryIds] {
            if {$candidate eq $source || ![::GX::CurveDigitizerImage::hasManifest $candidate]} continue
            if {![catch {datasetDigitizerPreviewAlignedLineage $candidate $source}]} {dict lappend result processed_candidates $candidate}
        }
        if {$processedSelection ne {}} {
            set candidate [dict get $processedSelection dataset_id]
            if {$candidate ni [dict get $result processed_candidates] || [dict get $processedSelection identity] ne [curveSourceDatasetIdentity $::GX::currentSession $candidate]} {error {Processed image selection changed or no longer preserves source geometry}}
            set payload [sessionInspectionDatasetPayload $candidate $::GX::currentSession]
            set artifact [datasetPreviewImageArtifact [dict get $payload path] $directory 1]
            set target [file join $directory processed-raster.png]
            file copy -force [dict get $artifact path] $target
            dict set result images $candidate [dict create path $target size [_native2DRasterHelper info [dict get $payload path]] sha256 [dict get $payload sha256]]
            dict set result main_image $candidate
        }
    }
    set ids [lsort -unique [dict values $columns]]
    set filters [datasetPublicationV2DictDefault $selections @predicates {}]
    foreach dimension $dimensions {
        set vid [dict get $dimension variable_id];set values [datasetPublicationV2DictDefault $selections $vid {}]
        if {$values ne {}} {lappend filters [dict create filter_variable_id $vid predicate in_set values $values]}
    }
    set filters [graphSeriesNormalizeFilters $id $filters]
    foreach filter $filters {set vid [dict get $filter filter_variable_id];if {$vid ni $ids} {lappend ids $vid}}
    set stream [tableStreamOpenDataset $::GX::currentSession $id $ids 2048 {numeric_transport values}]
    set curves {};set seen {};set count 0
    try {
        while 1 {
            set chunk [tableStreamNext $stream];set values [dict get $chunk values]
            for {set i 0} {$i<[dict get $chunk row_count]} {incr i} {
                set accepted 1
                foreach filter $filters {if {![::GX::GraphSelectionAPIv1::_matchesFilter [lindex [dict get $values [dict get $filter filter_variable_id]] $i] $filter]} {set accepted 0;break}}
                if {!$accepted} continue
                set row {};dict for {role vid} $columns {dict set row $role [lindex [dict get $values $vid] $i]}
                set curve [dict get $row curve_key];set order [dict get $row point_order]
                if {![string is entier -strict $order]} {error {Invalid published within-curve point identity}}
                if {![dict exists $curves $curve]} {dict set curves $curve [dict create label [dict get $row curve_name] points {} unique_points 0]}
                set identity [list $curve $order];set point [list $order]
                if {$raster} {
                    lappend point [dict get $row raster_x] [dict get $row raster_y]
                    foreach value [lrange $point 1 end] {if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Nonfinite source raster coordinate}}}
                }
                if {[dict exists $seen $identity]} {if {[dict get $seen $identity] ne $point} {error {Calibration realizations disagree on source raster identity}};continue}
                if {[incr count]>65536} {error {Source overlay exceeds 65536 unique points; canonical data remain complete}}
                dict set seen $identity $point
                set data [dict get $curves $curve];dict incr data unique_points
                if {$raster} {dict lappend data points $point}
                dict set curves $curve $data
            }
            if {[dict get $chunk eof]} break
        }
    } finally {tableStreamClose $stream}
    dict for {curve data} $curves {dict set data points [lsort -integer -index 0 [dict get $data points]];dict set curves $curve $data}
    dict set result curves $curves;dict set result unique_point_count $count
    modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_QUALITY_API_v2
    if {[::GX::CurveDigitizerQuality::hasReport $id]} {
        set quality [::GX::CurveDigitizerQuality::read $id];dict set result quality $quality
        if {![catch {exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python dataset_digitizer_quality_summary_v1.py] << [dict get $quality report_json]} lines]} {
            set text {};foreach line [split $lines \n] {if {$line ne {}} {lappend text [encoding convertfrom utf-8 [binary decode base64 -strict $line]]}}
            dict set result quality_summary [join $text \n]
        }
    }
    return $result
}
proc ::GX::datasetDigitizerPreviewRender {w id {prepared {}}} {
    variable ::GX::DigitizerPreview::state;variable ::GX::DigitizerPreview::serial
    if {$prepared eq {}} {return 0}
    set token digitizer-preview-[incr serial]
    set record [dict merge $prepared [dict create dataset_id $id session_token [interactiveDocumentSessionToken] photos {} widgets {} text_widget $w visibility_identity [list [datasetPreviewCacheSource $id] $::GX::ui(previewMap,filters)]]]
    dict set state $token $record
    $w insert end "Curve Digitalizer publication — canonical source identities\n"
    if {![dict get $record raster_available]} {$w insert end "Original raster point coordinates are unavailable in this historical publication. No aligned markers are inferred.\n"}
    if {[llength [datasetPublicationV2DictDefault $record processed_candidates {}]]} {
        set selector $w.processed$serial
        ttk::combobox $selector -state readonly -values [linsert [dict get $record processed_candidates] 0 {Original source image}]
        $selector set [expr {[dict get $record main_image] eq [dict get $record original_image]?"Original source image":[dict get $record main_image]}]
        uiFieldSelectorWithinViewer $selector .top
        bind $selector <<ComboboxSelected>> [list ::GX::datasetDigitizerPreviewProcessedSelect $token $selector]
        set selectedRecord [dict get $state $token];dict lappend selectedRecord widgets $selector;dict set state $token $selectedRecord
        $w insert end "Geometry-preserving source image: ";$w window create end -window $selector;$w insert end "\n"
    }
    if {[dict exists $record main_image]} {datasetDigitizerPreviewImage $w [dict get $record main_image] {Verified source image} $token [dict get $record raster_available]}
    if {[dict exists $record image_message]} {$w insert end "Source image: [dict get $record image_message]\n"}
    set table $w.digitizerCurves$serial;ttk::labelframe $table -text {Retained curve visibility}
    set record [dict get $state $token];dict lappend record widgets $table
    set hidden [datasetPublicationV2DictDefault $::GX::ui(previewMap,filters) @hidden_filters {}]
    set palette {#0876bd #c84427 #238b45 #8849a3 #a67513 #008b8b #ba3377};set i 0
    dict for {curve data} [dict get $record curves] {
        set show 1;foreach filter $hidden {if {[dict get $filter value] eq $curve} {set show 0}}
        set ::GX::DigitizerPreview::visible($token,$curve) $show
        if {![dict exists $data tag]} {dict set data tag curve_$i;dict set data color [lindex $palette [expr {$i%7}]];dict set data displayed_points 0;dict set record curves $curve $data}
        if {!$show && [dict exists $record canvas]} {[dict get $record canvas] itemconfigure [dict get $data tag] -state hidden}
        ttk::checkbutton $table.show$i -text {Show / Hide} -variable ::GX::DigitizerPreview::visible($token,$curve) -command [list ::GX::datasetDigitizerPreviewToggle $token $curve]
        ttk::label $table.label$i -text [dict get $data label] -foreground [dict get $data color]
        ttk::label $table.count$i -text "[dict get $data unique_points] unique source points"
        grid $table.show$i $table.label$i $table.count$i -sticky w -padx 8 -pady 2
        incr i
    }
    dict set state $token $record
    $w window create end -window $table;$w insert end "\nVisibility changes retain XY geometry and the source overlay; they do not rerun a reader or Job.\n"
    if {[dict exists $record quality]} {
        $w insert end "Published Quality — physical accuracy and uncertainty are not inferred\n[datasetPublicationV2DictDefault $record quality_summary {}]\n"
        ttk::button $table.report -text {Inspect full Quality report…} -command [list ::GX::datasetDigitizerQualityInspect [dict get $record quality report_json]]
        grid $table.report -columnspan 3 -sticky w -padx 8 -pady 5
    } else {$w insert end "Quality report is unavailable in this historical Dataset. Missing uncertainty does not imply zero.\n"}
    datasetDigitizerPreviewFinish $w $id
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
