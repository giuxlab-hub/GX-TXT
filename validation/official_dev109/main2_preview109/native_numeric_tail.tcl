# Continue the already-open numeric native journey; do not repeat completed input.
try {
    set fd [open [file join $::out numeric_initial.tcldict] r];set prior [read $fd];close $fd
    set before [dict get $prior source]
    set key [dict get $::GX::PreviewLive::active rendered_key]
    record numeric_first_render_qualification [dict create initial_options [dict get $prior active rendered_options] explicit_options [dict get $::GX::PreviewLive::active rendered_options] initial_key [dict get $prior active rendered_key] explicit_key $key cache [::GX::datasetPreviewCacheStatus $key] original_failed_assumption valid_cached_render_no_prepare_miss]
    check first_render_options_really_differ {[dict get $prior active rendered_options] ne [dict get $::GX::PreviewLive::active rendered_options]}
    set path [numericReady SYNTHETIC_NUMERIC_A]
    set rendered [::GX::PlotDatasetAPIv4::widgetReceipt $path]
    set x [expr {[winfo rootx $path]+[winfo width $path]/2}]
    set y [expr {[winfo rooty $path]+[winfo height $path]/2}]
    exec xdotool mousemove $x $y click 4;pause 250
    set zoomed [::GX::PlotDatasetAPIv4::widgetReceipt $path]
    check native_wheel_changes_view {[dict get $zoomed axes] ne [dict get $rendered axes]}
    click .top.nb.preview.live.actions.fit;pause 250
    set fitted [::GX::PlotDatasetAPIv4::widgetReceipt $path]
    check native_fit_restores_axes {[dict get $fitted axes] eq [dict get $rendered axes]}
    record numeric_refreshed [dict create receipt $rendered zoomed $zoomed fitted $fitted native_id [winfo id $path] misses $::GX::PreviewCache::misses]
    capture . numeric_refreshed
    nativeDataset SYNTHETIC_NUMERIC_B;numericReady SYNTHETIC_NUMERIC_B;pause 200
    record numeric_b [dict create active $::GX::PreviewLive::active receipt [::GX::PlotDatasetAPIv4::widgetReceipt $path]]
    capture . numeric_b
    set misses $::GX::PreviewCache::misses
    nativeDataset SYNTHETIC_NUMERIC_A;numericReady SYNTHETIC_NUMERIC_A;pause 200
    check numeric_a_return_uses_cache {$::GX::PreviewCache::misses==$misses}
    foreach id {SYNTHETIC_NUMERIC_A SYNTHETIC_NUMERIC_B} {check unchanged_science_$id {[dict get $before $id] eq [numericSource $id]}}
    record numeric_complete [dict create status POSITIVE_NATIVE_NUMERIC_REFRESH_PASS source $before receipt [::GX::PlotDatasetAPIv4::widgetReceipt $path] cache [::GX::datasetPreviewCacheStatus [dict get $::GX::PreviewLive::active key]] note {Initial failed zero-miss assumption qualified by different actual options. Late rejection owner-tested separately; no original thermal or digitizer claim}]
    capture . numeric_a_return
} on error {m o} {record numeric_tail_failure [dict create message $m options $o];capture . numeric_tail_failure_[clock microseconds];return -options $o $m}
