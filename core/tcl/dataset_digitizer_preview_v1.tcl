# SPDX-License-Identifier: GPL-3.0-or-later
# Additive published-Dataset representation in the existing shared Preview.
namespace eval ::GX::DigitizerPreview {variable state {};variable serial 0}
proc ::GX::datasetDigitizerPreviewClear {} {
    variable ::GX::DigitizerPreview::state
    foreach key [dict keys $state] {datasetDigitizerPreviewRelease $key}
    array unset ::GX::DigitizerPreview::visible *
}
proc ::GX::datasetDigitizerPreviewRelease {key} {
    variable ::GX::DigitizerPreview::state
    if {[dict exists $state $key]} {
        set record [dict get $state $key]
        if {[dict exists $record visibility_after]} {after cancel [dict get $record visibility_after];datasetDigitizerPreviewVisibilitySave $key}
        if {[dict exists $record text_widget] && [winfo exists [dict get $record text_widget]]} {
            set w [dict get $record text_widget]
            foreach tag [$w tag names] {if {[string match digitizer_dataset_* $tag]} {$w tag delete $tag}}
        }
        foreach photo [dict get $record photos] {catch {image delete $photo}}
        foreach widget [dict get $record widgets] {catch {destroy $widget}}
        dict unset state $key
    }
    array unset ::GX::DigitizerPreview::visible $key,*
}
proc ::GX::datasetDigitizerPreviewLink {w id title {titleTag {}}} {
    variable ::GX::DigitizerPreview::serial
    set tag digitizer_dataset_[incr serial]
    $w insert end "$title: " $titleTag
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
    dict set state $token $record
    set canvas $w.digitizerImage[llength [dict get $record photos]]
    canvas $canvas -width [image width $photo] -height [image height $photo] -highlightthickness 0 -background white
    $canvas create image 0 0 -anchor nw -image $photo
    dict lappend record widgets $canvas
    dict set state $token $record
    set labelTag digitizer_dataset_label_[incr ::GX::DigitizerPreview::serial]
    datasetDigitizerPreviewLink $w $id $title $labelTag
    set record [dict get $state $token];dict lappend record image_label_tags $labelTag;dict set state $token $record
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
proc ::GX::_datasetDigitizerPreviewVisibilityFilters {filters curveVariable} {
    # These are opaque presentation identities, not Graph Selection predicates.
    # Bounds apply to saved preferences, never to canonical curve membership.
    if {[string bytelength $curveVariable]>1024 || [string bytelength $filters]>1048576 ||
        [catch {llength $filters} count] || $count>4096} {error {Saved curve visibility exceeds its supported limits.}}
    set seen {};set result {}
    foreach filter $filters {
        if {[catch {lsort [dict keys $filter]} keys] || $keys ne {filter_variable_id predicate value} ||
            [dict get $filter filter_variable_id] ne $curveVariable ||
            [dict get $filter predicate] ne {not_equal} ||
            [string bytelength [dict get $filter value]]>16384} {error {Saved curve visibility is invalid.}}
        set value [dict get $filter value]
        if {[dict exists $seen $value]} {error {Saved curve visibility has duplicate identities.}}
        dict set seen $value 1
        lappend result [dict create filter_variable_id $curveVariable predicate not_equal value $value]
    }
    return $result
}
proc ::GX::_datasetDigitizerPreviewVisibilityRead {saved curveVariable} {
    if {[dict exists $saved retained_visibility]} {
        set preference [dict get $saved retained_visibility]
        if {[string bytelength $preference]>1048576 || [catch {lsort [dict keys $preference]} keys] ||
            $keys ne {hidden_filters version} || [dict get $preference version] ne {1}} {error {Saved curve visibility is invalid or unsupported.}}
        set hidden [dict get $preference hidden_filters]
    } else {
        # Presence, including a valid empty new list, takes precedence over this
        # historical location. Reading never migrates or rewrites either form.
        set hidden {}
        if {[dict exists $saved selections]} {set hidden [datasetPublicationV2DictDefault [dict get $saved selections] @hidden_filters {}]}
    }
    return [_datasetDigitizerPreviewVisibilityFilters $hidden $curveVariable]
}
proc ::GX::_datasetDigitizerPreviewVisibilityMerge {hidden curveVariable represented visible} {
    set byIdentity {}
    foreach filter [_datasetDigitizerPreviewVisibilityFilters $hidden $curveVariable] {
        dict set byIdentity [dict get $filter value] $filter
    }
    foreach curve $represented {
        if {![dict exists $visible $curve] || [dict get $visible $curve] ni {0 1}} {error {Curve visibility state is unavailable.}}
        if {[dict get $visible $curve]} {
            dict unset byIdentity $curve
        } else {dict set byIdentity $curve [dict create filter_variable_id $curveVariable predicate not_equal value $curve]}
    }
    # Entries outside the displayed scientific subset remain inactive intent.
    # This does not certify that they exist in a complete publication.
    set result {};dict for {curve filter} $byIdentity {lappend result $filter}
    return [_datasetDigitizerPreviewVisibilityFilters $result $curveVariable]
}
proc ::GX::_datasetDigitizerPreviewVisibilityStore {id source curveVariable represented visible} {
    if {$source eq {} || $source ne [datasetPreviewCacheSource $id]} {error {Preview source changed; saved visibility was not updated.}}
    set metadata [datasetPrivateMetadataRead $::GX::currentSession $id]
    set saved [datasetPublicationV2DictDefault $metadata _gxtxt.framework.dataset_preview {}]
    if {$saved ne {} && (![dict exists $saved version] || [dict get $saved version]!=1)} {error {Saved Preview configuration is unsupported; visibility was not updated.}}
    set hidden [_datasetDigitizerPreviewVisibilityRead $saved $curveVariable]
    set hidden [_datasetDigitizerPreviewVisibilityMerge $hidden $curveVariable $represented $visible]
    set preference [dict create version 1 hidden_filters $hidden]
    if {[string bytelength $preference]>1048576} {error {Saved curve visibility exceeds its supported limits.}}
    dict set saved version 1
    dict set saved retained_visibility $preference
    _datasetFrameworkMetadataUpdate $::GX::currentSession $id [dict create dataset_preview $saved]
    return $hidden
}
proc ::GX::_datasetDigitizerPreviewVisibilityCurrent {record} {
    if {[catch {
        set w [dict get $record text_widget]
        expr {[dict get $record session_token] eq [interactiveDocumentSessionToken] &&
            [winfo exists $w] && [winfo id $w] eq [dict get $record text_widget_xid] &&
            [dict get $record prepared_source] ne {} &&
            [dict get $record prepared_source] eq [datasetPreviewCacheSource [dict get $record dataset_id]]}
    } valid]} {return 0}
    return $valid
}
proc ::GX::_datasetDigitizerPreviewVisibilityRetire {token} {
    variable ::GX::DigitizerPreview::state
    if {[dict exists $state $token visibility_after]} {
        after cancel [dict get $state $token visibility_after]
        dict unset state $token visibility_after
    }
}
proc ::GX::_datasetDigitizerPreviewVisibilityNotice {id} {
    variable ::GX::DigitizerPreview::state
    dict for {token record} $state {
        if {[dict get $record dataset_id] eq $id && ![dict get $record visibility_valid]} {
            return {Saved curve visibility is invalid or too large; all curves in this view are shown and visibility changes are not saved.}
        }
    }
    return {}
}
proc ::GX::datasetDigitizerPreviewToggle {token curve} {
    variable ::GX::DigitizerPreview::state
    if {![dict exists $state $token]} return
    set record [dict get $state $token]
    if {![dict exists $record curves $curve]} return
    if {![_datasetDigitizerPreviewVisibilityCurrent $record]} {
        _datasetDigitizerPreviewVisibilityRetire $token
        if {[dict exists $record visibility_applied $curve]} {set ::GX::DigitizerPreview::visible($token,$curve) [dict get $record visibility_applied $curve]}
        setStatus {Preview source or Session changed. Render again before changing curve visibility.} 100
        return
    }
    set show [set ::GX::DigitizerPreview::visible($token,$curve)]
    if {[dict exists $record native_widget]} {
        foreach series [datasetPublicationV2DictDefault [dict get $record native_series] $curve {}] {::GX::PlotDatasetAPIv4::widgetVisibility [dict get $record native_widget] main $series $show}
    }
    if {[dict exists $record canvas]} {[dict get $record canvas] itemconfigure [dict get $record curves $curve tag] -state [expr {$show?"normal":"hidden"}]}
    dict set record visibility_applied $curve $show
    dict set state $token visibility_applied $curve $show
    set visible {}
    dict for {identity data} [dict get $record curves] {
        dict set visible $identity [expr {!![set ::GX::DigitizerPreview::visible($token,$identity)]}]
    }
    _datasetDigitizerPreviewVisibilityRetire $token
    if {![dict get $record visibility_valid] || [catch {
        set hidden [_datasetDigitizerPreviewVisibilityMerge [dict get $record hidden_filters] [dict get $record curve_variable] [dict keys [dict get $record curves]] $visible]
    }]} {
        setStatus {Visibility changed for this view; saved visibility preferences are invalid or exceed supported limits and were not updated.} 100
        return
    }
    if {[info exists ::GX::ui(previewMap,dataset)] && $::GX::ui(previewMap,dataset) eq [dict get $record dataset_id]} {
        dict set ::GX::ui(previewMap,filters) @hidden_filters $hidden
        set ::GX::ui(previewRasterVisibility) [dict create identity [dict get $record visibility_identity] hidden $hidden]
    }
    dict set state $token visibility_after [after 750 [list ::GX::datasetDigitizerPreviewVisibilitySave $token]]
}
proc ::GX::datasetDigitizerPreviewVisibilitySave {token} {
    variable ::GX::DigitizerPreview::state
    if {![dict exists $state $token]} return
    set record [dict get $state $token]
    # Retirement precedes every refusal, including Release's pending flush.
    _datasetDigitizerPreviewVisibilityRetire $token
    if {![_datasetDigitizerPreviewVisibilityCurrent $record] || ![dict get $record visibility_valid]} return
    set visible {};dict for {curve data} [dict get $record curves] {dict set visible $curve [expr {!!$::GX::DigitizerPreview::visible($token,$curve)}]}
    if {[catch {
        set hidden [_datasetDigitizerPreviewVisibilityStore [dict get $record dataset_id] [dict get $record prepared_source] [dict get $record curve_variable] [dict keys [dict get $record curves]] $visible]
    }]} {
        setStatus {Saved curve visibility could not be updated. The current view is retained.} 100
        return
    }
    if {[dict exists $state $token]} {dict set state $token hidden_filters $hidden}
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
        set seriesList [dict get [lindex [dict get $model panels] 0] series]
        # scientificModel normalizes input trace filters to model row_filters.
        # Missing predicates must refuse before creating a partial native widget.
        foreach series $seriesList {
            if {![dict exists $series row_filters] || [catch {llength [dict get $series row_filters]}]} {error {Prepared Digitizer Preview requires normalized row_filters}}
        }
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1 retain_presentation 1}
        foreach series $seriesList {
            foreach filter [dict get $series row_filters] {
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
# The canonical reader/predicate/sort owners remain authoritative. This private
# seam supplies bounded chunks to precompiled CORE; old runtimes retain the loop.
proc ::GX::_datasetDigitizerPreviewCollect {session id ids columns raster filters} {
    if {[llength [info commands ::gx::native2d::_preview_overlay]]} {
        set identity [curveSourceDatasetIdentity $session $id]
        set collector [::gx::native2d::_preview_overlay begin $columns $raster $filters]
        set stream {}
        try {
            set stream [tableStreamOpenDataset $session $id $ids 2048 {numeric_transport values}]
            while 1 {
                set chunk [tableStreamNext $stream]
                ::gx::native2d::_preview_overlay push $collector [dict get $chunk values] [dict get $chunk row_count]
                if {[dict get $chunk eof]} break
            }
            set result [::gx::native2d::_preview_overlay finish $collector]
            if {[curveSourceDatasetIdentity $session $id] ne $identity} {error {Source changed during raster overlay preparation}}
            return $result
        } finally {
            try {if {$stream ne {}} {tableStreamClose $stream}} finally {::gx::native2d::_preview_overlay destroy $collector}
        }
    }
    set stream [tableStreamOpenDataset $session $id $ids 2048 {numeric_transport values}]
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
    return [dict create curves $curves unique_point_count $count]
}
proc ::GX::datasetDigitizerPreviewPrepare {id selections dimensions directory {processedSelection {}} {nativeOverlay {}}} {
    set manifest [datasetPreviewCurveManifest $id]
    if {$manifest eq {}} {return {}}
    set md [datasetMetadataRead $::GX::currentSession $id]
    set columns [dict get $manifest columns]
    set raster [dict get $manifest raster_points_available]
    set result [dict create dataset_id $id metadata $md curve_variable [dict get $columns curve_key] curves {} images {} raster_available $raster]
    set source [datasetPublicationV2DictDefault $md curve_digitizer.source_dataset_id {}]
    set expected [datasetPublicationV2DictDefault $md curve_digitizer.source_sha256 {}]
    # This host receipt is independent of the installed provider's Quality
    # dictionary. Registry SHA fields retain their recorded canonical meaning.
    set verification [dict create schema gxtxt.preview.source_verification.v1 \
        dataset_id $source published_expected_sha256 $expected registered_expected_sha256 {} \
        observed_sha256 {} status unverified method {} checked_at_utc {} \
        reason {Source Dataset or a valid publication SHA-256 was not supplied.}]
    set payload {};set registered {};set validExpected [regexp {^[0-9a-fA-F]{64}$} $expected]
    if {$source ne {} && $validExpected} {
        if {[catch {set registered [sessionInspectionDataset $source $::GX::currentSession]} message]} {
            dict set verification status unavailable
            dict set verification reason $message
        } elseif {[datasetPublicationV2DictDefault $registered storage_provider {}] eq {remote}} {
            dict set verification registered_expected_sha256 [datasetPublicationV2DictDefault $registered canonical_sha256 {}]
            dict set verification status unsupported_remote
            dict set verification reason {This local-raster Preview does not provide a current remote-byte verification receipt.}
        } else {
            dict set verification registered_expected_sha256 [datasetPublicationV2DictDefault $registered canonical_sha256 {}]
            dict set verification method SESSION_INSPECTION_API_v1.datasetPayload
            if {[catch {set payload [sessionInspectionDatasetPayload $source $::GX::currentSession]} message]} {
                dict set verification status unavailable
                dict set verification reason $message
                # Only a failed canonical-payload check takes this recovery
                # observation path. Successful sources are not hashed twice.
                if {![catch {set linked [datasetViewerLinkedSourceIdentity $::GX::currentSession $source]}] && [dict exists $linked resource sha256]} {
                    set observed [dict get $linked resource sha256]
                    dict set verification observed_sha256 $observed
                    dict set verification method SESSION_INSPECTION_API_v1.resolveResource_after_payload_failure
                    set canonical [dict get $verification registered_expected_sha256]
                    if {![string equal -nocase $observed $expected] || ([regexp {^[0-9a-fA-F]{64}$} $canonical] && ![string equal -nocase $observed $canonical])} {
                        dict set verification status changed
                    } else {
                        # A later resource read cannot waive the original
                        # canonical-owner refusal or silently repair identity.
                        dict set verification status unverified
                    }
                }
            } else {
                set observed [dict get $payload sha256]
                dict set verification observed_sha256 $observed
                set canonical [dict get $verification registered_expected_sha256]
                if {![regexp {^[0-9a-fA-F]{64}$} $canonical]} {
                    dict set verification status unverified
                    dict set verification reason {The registered source has no valid canonical SHA-256 identity; current-byte verification cannot establish a registered match.}
                } elseif {![regexp {^[0-9a-fA-F]{64}$} $observed]} {
                    dict set verification status unverified
                    dict set verification reason {The payload owner returned no valid observed SHA-256; current-byte verification is unavailable.}
                } elseif {[string equal -nocase $observed $expected] && [string equal -nocase $observed $canonical]} {
                    dict set verification status verified
                    dict set verification reason {The current payload passed the canonical owner check and matches the publication source SHA-256.}
                } else {
                    dict set verification status changed
                    dict set verification reason {Current canonical source differs from the publication source; aligned overlay refused.}
                }
            }
            if {[dict get $verification observed_sha256] ne {}} {dict set verification checked_at_utc [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]}
        }
    }
    dict set result host_source_verification $verification
    if {[dict get $verification status] eq {verified}} {
        if {[catch {
            set sizes [_native2DRasterHelper info [dict get $payload path]]
            set artifact [datasetPreviewImageArtifact [dict get $payload path] $directory 1]
            set target [file join $directory raster.png]
            if {[dict get $artifact path] ne $target} {file copy -force [dict get $artifact path] $target}
            dict set result images $source [dict create path $target size $sizes sha256 $expected]
            dict set result main_image $source;dict set result original_image $source
        } message]} {dict set result image_message $message}
    } elseif {$source ne {}} {
        dict set result image_message [dict get $verification reason]
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
            if {[catch {
            if {$candidate ni [dict get $result processed_candidates] || [dict get $processedSelection identity] ne [curveSourceDatasetIdentity $::GX::currentSession $candidate]} {error {Processed image selection changed or no longer preserves source geometry}}
            set payload [sessionInspectionDatasetPayload $candidate $::GX::currentSession]
            set artifact [datasetPreviewImageArtifact [dict get $payload path] $directory 1]
            set target [file join $directory processed-raster.png]
            file copy -force [dict get $artifact path] $target
            dict set result images $candidate [dict create path $target size [_native2DRasterHelper info [dict get $payload path]] sha256 [dict get $payload sha256]]
            dict set result main_image $candidate
            } message]} {
                # Retain the verified original and public chooser for explicit
                # recovery. Do not silently substitute it for a selected image.
                dict unset result main_image
                dict set result unavailable_selection $candidate
                dict set result image_message "$message. Select Original source image to render the verified original."
            }
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
    set collected {}
    # Reuse the actual native common-owner result only when all of this
    # publication's semantic roles and predicates still match. Image/source
    # verification above remains the sole authority for aligned presentation.
    if {$nativeOverlay ne {} && ![catch {
        if {[dict get $nativeOverlay dataset_id] ne $id || [dict get $nativeOverlay columns] ne $columns ||
            [dict get $nativeOverlay raster]!=$raster || [dict get $nativeOverlay filters] ne $filters ||
            ![datasetPreviewNativeReceiptCurrent $id [dict get $nativeOverlay native_provider]]} {error {Native overlay identity changed}}
        set collected [dict get $nativeOverlay result]
        dict get $collected curves;dict get $collected unique_point_count
    }]} {dict set result overlay_preparation native} else {
        set collected [_datasetDigitizerPreviewCollect $::GX::currentSession $id $ids $columns $raster $filters]
        dict set result overlay_preparation core
    }
    set curves [dict get $collected curves];set count [dict get $collected unique_point_count]
    dict set result curves $curves;dict set result unique_point_count $count
    modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_QUALITY_API_v2
    if {[::GX::CurveDigitizerQuality::hasReport $id]} {
        set quality [::GX::CurveDigitizerQuality::read $id];dict set result quality $quality
        if {![catch {exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python dataset_digitizer_quality_summary_v1.py] --table << [dict get $quality report_json]} presentation]} {
            dict set result quality_rows [dict get $presentation rows]
            dict set result quality_summary [dict get $presentation summary]
        } else {dict set result quality_presentation_message $presentation}
    }
    return $result
}
proc ::GX::datasetDigitizerPreviewRender {w id {prepared {}}} {
    variable ::GX::DigitizerPreview::state;variable ::GX::DigitizerPreview::serial
    if {$prepared eq {}} {return 0}
    set visibilityValid [expr {![catch {
        set hidden [_datasetDigitizerPreviewVisibilityRead [datasetPreviewConfigurationRead $id] [dict get $prepared curve_variable]]
    }]}]
    if {!$visibilityValid} {set hidden {}}
    set token digitizer-preview-[incr serial]
    set source [datasetPublicationV2DictDefault $prepared prepared_source {}]
    set record [dict merge $prepared [dict create dataset_id $id session_token [interactiveDocumentSessionToken] photos {} widgets {} text_widget $w text_widget_xid [winfo id $w] prepared_source $source visibility_valid $visibilityValid hidden_filters $hidden visibility_identity [list $source $::GX::ui(previewMap,filters)]]]
    dict set state $token $record
    try {
    $w insert end "Curve Digitalizer publication — canonical source identities\n"
    if {![dict get $record raster_available]} {$w insert end "Original raster point coordinates are unavailable in this historical publication. No aligned markers are inferred.\n"}
    if {[dict exists $record original_image]} {
        set selector $w.processed$serial
        set choices [linsert [dict get $record processed_candidates] 0 {Original source image}]
        if {[dict exists $record unavailable_selection]} {lappend choices "Unavailable: [dict get $record unavailable_selection]"}
        ttk::combobox $selector -state readonly -values $choices
        set selectedRecord [dict get $state $token];dict lappend selectedRecord widgets $selector;dict set state $token $selectedRecord
        if {[dict exists $record unavailable_selection]} {$selector set "Unavailable: [dict get $record unavailable_selection]"
        } else {$selector set [expr {[dict get $record main_image] eq [dict get $record original_image]?"Original source image":[dict get $record main_image]}]}
        uiFieldSelectorWithinViewer $selector [winfo toplevel $selector]
        bind $selector <<ComboboxSelected>> [list ::GX::datasetDigitizerPreviewProcessedSelect $token $selector]
        $w insert end "Geometry-preserving source image: ";$w window create end -window $selector;$w insert end "\n"
    }
    if {[dict exists $record main_image]} {datasetDigitizerPreviewImage $w [dict get $record main_image] {Verified source image} $token [dict get $record raster_available]}
    if {[dict exists $record image_message]} {$w insert end "Source image: [dict get $record image_message]\n"}
    set table $w.digitizerCurves$serial;ttk::labelframe $table -text {Retained curve visibility}
    set record [dict get $state $token];dict lappend record widgets $table
    dict set state $token $record
    set palette {#0876bd #c84427 #238b45 #8849a3 #a67513 #008b8b #ba3377};set i 0
    dict for {curve data} [dict get $record curves] {
        set show 1;foreach filter $hidden {if {[dict get $filter value] eq $curve} {set show 0}}
        set ::GX::DigitizerPreview::visible($token,$curve) $show
        dict set record visibility_applied $curve $show
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
    datasetDigitizerPreviewFinish $w $id
    return 1
    } on error {message options} {
        datasetDigitizerPreviewRelease $token
        return -options $options $message
    }
}
proc ::GX::datasetDigitizerPreviewQualifyPrevious {id} {
    variable ::GX::DigitizerPreview::state
    dict for {token record} $state {
        if {[dict get $record dataset_id] ne $id || [dict get $record session_token] ne [interactiveDocumentSessionToken]} continue
        set w [dict get $record text_widget]
        if {![winfo exists $w]} continue
        set previousState [$w cget -state];$w configure -state normal
        foreach tag [datasetPublicationV2DictDefault $record image_label_tags {}] {
            set range [$w tag ranges $tag]
            if {[llength $range]!=2} continue
            set start [lindex $range 0];$w delete {*}$range
            $w insert $start {Previous-render image (source changed; Render to refresh): } $tag
        }
        $w configure -state $previousState
    }
}
proc ::GX::datasetDigitizerQualityInspect {json} {
    set w .gxDigitizerQuality;catch {destroy $w};toplevel $w;wm title $w {Published Quality v2 report — read-only}
    text $w.value -width 100 -height 25 -wrap word -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.value yview]
    pack $w.scroll -side right -fill y;pack $w.value -fill both -expand 1
    $w.value insert 1.0 $json;$w.value configure -state disabled
    ttk::button $w.copy -text {Copy full report} -command [list ::GX::datasetMetadataCopyValue $json];pack $w.copy -anchor e
}
