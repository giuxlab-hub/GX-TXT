# Isolated scientific snapshot worker: canonical Dataset ZIPs are imported only
# into newly owned disposable Session storage, never into the operator Session.
lassign $argv framework directory graph
set argv0 __gxtxt_native_v4_snapshot__
set private [file join $directory .native_render_[pid]_[clock clicks]]
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
    if {$graph eq {plot.dataset.xyz}} {set artifact [::GX::PlotDatasetAPIv4::render3DSpec $spec [file join $directory graph.native.[pid].png]]} else {set artifact [file join $directory graph.native.[pid].png];::GX::PlotDatasetAPIv4::renderModel [::GX::PlotDatasetAPIv4::modelFromSpec $spec] $artifact}
    file rename -force -- $artifact [file join $directory graph.png]
    set geometry [::GX::plotRegionMetadataPath $artifact];if {[file isfile $geometry]} {file rename -force -- $geometry [::GX::plotRegionMetadataPath [file join $directory graph.png]]}
    set xrange [file join [file dirname $geometry] "[file rootname [file tail $artifact]].xrange.ini"];if {[file isfile $xrange]} {file rename -force -- $xrange [file join [file dirname $geometry] graph.xrange.ini]}
} finally {file delete -force -- $private}
