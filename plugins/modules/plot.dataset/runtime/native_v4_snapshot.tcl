# Isolated scientific snapshot worker: canonical Dataset ZIPs are imported only
# into newly owned disposable Session storage, never into the operator Session.
lassign $argv framework directory graph work
set argv0 __gxtxt_native_v4_snapshot__
if {[llength $argv]!=4 || ![file isdirectory $work] || [file type $work] ne {directory}} {error {Native snapshot worker requires its parent-owned operation directory}}
set private [file join [file normalize $work] native_snapshot]
if {[file exists $private]} {error {Native snapshot work directory is already in use}}
file mkdir [file join $private metadata]
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $private config $key]}
try {
    source [file join $framework gxtxt_pipeline.tcl]
    ::GX::defaults;::GX::loadModuleCatalog
    set ::GX::cfg(output_root) [file join $private sessions]
    ::GX::createNewSession native_scientific_snapshot
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set manifest [::GX::PlotDatasetAPIv4::snapshotValidate $directory $graph]
    dict for {id resource} [dict get $manifest datasets] {::GX::portableResourceImport [file join $directory [dict get $resource archive]] [dict create dataset_id $id]}
    set spec [dict get $manifest spec];::GX::PlotDatasetAPIv4::validateSpec $spec
    if {$graph eq {plot.dataset.xyz}} {set artifact [::GX::PlotDatasetAPIv4::render3DSpec $spec [file join $directory graph.native.[pid].png]]} else {set artifact [file join $directory graph.native.[pid].png];set model [::GX::PlotDatasetAPIv4::modelFromSpec $spec];set graphics [::GX::PlotDatasetAPIv4::_get [::GX::PlotDatasetAPIv4::_get $model native_presentation {}] graphics {}];::GX::PlotDatasetAPIv4::renderModel $model $artifact [::GX::PlotDatasetAPIv4::_get $graphics width_px 1000] [::GX::PlotDatasetAPIv4::_get $graphics height_px 720]}
    file rename -force -- $artifact [file join $directory graph.png]
    set geometry [::GX::plotRegionMetadataPath $artifact];if {[file isfile $geometry]} {file rename -force -- $geometry [::GX::plotRegionMetadataPath [file join $directory graph.png]]}
    set xrange [file join [file dirname $geometry] "[file rootname [file tail $artifact]].xrange.ini"];if {[file isfile $xrange]} {file rename -force -- $xrange [file join [file dirname $geometry] graph.xrange.ini]}
} finally {
    # Canonical import can start this interpreter's ordinary cache/metadata
    # requests. Close their existing owners and wait for terminal EOF before
    # deleting the private profile; no parent/session requests are visible here.
    if {[llength [info commands ::GX::apiCatalogClose]]} {::GX::apiCatalogClose}
    if {[info exists ::GX::PreviewCache::tasks]} {foreach key [dict keys $::GX::PreviewCache::tasks] {::GX::datasetPreviewCacheCancel $key}}
    if {[info exists ::GX::scriptJobRequests]} {
        foreach request [dict keys $::GX::scriptJobRequests] {::GX::scriptJobRequestCancel $request closed}
        set deadline [expr {[clock milliseconds]+4000}]
        while {[dict size $::GX::scriptJobRequests] && [clock milliseconds]<$deadline} {
            after 10 {set ::nativeSnapshotShutdownTick 1};vwait ::nativeSnapshotShutdownTick
        }
        if {[dict size $::GX::scriptJobRequests]} {error {Native snapshot owned descendants did not reach terminal EOF; operation allocation remains protected}}
    }
    file delete -force -- $private
}
