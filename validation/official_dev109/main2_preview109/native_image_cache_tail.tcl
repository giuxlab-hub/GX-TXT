try {
    set cases {}
    foreach id {SYNTHETIC_RGB SYNTHETIC_GRAY16} {
        set key [::GX::datasetPreviewCacheKey $id]
        set cached [::GX::datasetPreviewCacheRead $id $key]
        set directory [::GX::datasetPreviewCachePath $::GX::currentSession $key]
        dict set cases $id [dict create key $key directory $directory representation_sha256 [::GX::sha256File [file join $directory representation.tcldict]] source [dict get $cached source] artifacts [dict get $cached artifacts] outcome [::GX::datasetPreviewCacheStatus $key] payload [::GX::sessionInspectionDatasetPayload $id] metadata [::GX::datasetMetadataRead $::GX::currentSession $id]]
    }
    set misses $::GX::PreviewCache::misses
    nativeDataset SYNTHETIC_GRAY16;imageReady SYNTHETIC_GRAY16
    nativeDataset SYNTHETIC_RGB;imageReady SYNTHETIC_RGB
    check revisit_no_extra_managed_job {$::GX::PreviewCache::misses==$misses && ![dict size $::GX::PreviewCache::tasks]}
    record image_cache_verified [dict create status PASS cases $cases misses_before $misses misses_after $::GX::PreviewCache::misses hits $::GX::PreviewCache::hits script_job_root [::GX::scriptJobRoot] native_geometry [winfo geometry .] copy_status {UNVERIFIED: embedded table row selects but Tk focus remains empty after WM resize; all keyboard-copy failures preserved. No source workaround.} pid [pid]]
} on error {m o} {record cache_tail_failure [dict create message $m options $o];capture . cache_tail_failure_[clock microseconds];return -options $o $m}
