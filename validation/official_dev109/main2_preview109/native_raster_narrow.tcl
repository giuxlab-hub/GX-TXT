source [file join $::root validation main2_preview109 native_common.tcl]
try {
    set f [open [file join $::out raster_large_fit_complete.tcldict] r];try {set prior [read $f]} finally {close $f}
    set w .top.nb.preview.txt;set tools .top.nb.preview.imageTools
    set id SYNTHETIC_GUI_SCREENSHOT_B130metadata_native
    set misses $::GX::PreviewCache::misses
    exec xdotool mousemove [expr {[winfo rootx .]+[winfo width .]-3}] [expr {[winfo rooty .]+[winfo height .]-3}]
    exec xdotool key --clearmodifiers alt+F8
    pause 100
    exec xdotool mousemove --sync [expr {[winfo rootx .]+850}] [expr {[winfo rooty .]+580}] click 1
    pause 400
    check new_controls_actual_narrow {[winfo width .]<1000 && [winfo height .]<750}
    foreach name {out actual in fit scale} {
        check new_control_visible_$name {[winfo ismapped $tools.$name] && [winfo rootx $tools.$name]+[winfo width $tools.$name]<=[winfo rootx $w]+[winfo width $w]}
    }
    click $tools.fit
    set photo [$w image cget [lindex [$w image names] 0] -image]
    set fitted [list [image width $photo] [image height $photo]]
    check narrow_fit_image {[lindex $fitted 0]<=[winfo width $w]-16 && [lindex $fitted 1]<=[winfo height $w]-24}
    set directory [::GX::datasetPreviewCachePath $::GX::currentSession [dict get $prior key]]
    set cache [::GX::datasetPreviewCacheRead $id [dict get $prior key]]
    set artifact [file join $directory [file tail [dict get $cache media_artifact path]]]
    check narrow_zoom_cache_exact {[dict get $prior cache_artifact_pins] eq [list [::GX::sha256File $artifact] [::GX::sha256File [file join $directory representation.tcldict]]]}
    check narrow_zoom_source_exact {[dict get $prior source_before] eq [list [::GX::sessionInspectionDatasetPayload $id] [::GX::datasetMetadataRead $::GX::currentSession $id] [::GX::datasetViewerScientificIdentity $id]]}
    check narrow_zoom_no_preparation {$::GX::PreviewCache::misses==$misses && ![dict size $::GX::PreviewCache::tasks]}
    record raster_narrow_complete [dict create status NATIVE_RASTER_ZOOM_NARROW_PASS geometry [winfo geometry .] fitted $fitted viewport [list [winfo width $w] [winfo height $w]] scale_label [$tools.scale cget -text] misses_before $misses source_sha256 [::GX::sha256File [file join $::root core tcl dataset_preview_api_v1.tcl]]]
    capture . raster_zoom_narrow
} on error {m o} {record raster_narrow_failure_[clock microseconds] [dict create message $m options $o];capture . raster_narrow_failure_[clock microseconds];return -options $o $m}
