# Read-only native preparation worker, used by the existing shared scientific
# consultation host. It writes only the caller-owned output directory.
lassign $argv framework session reference output
set argv0 __native_plot_v4_prepare__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::currentSession $session
::GX::loadDatasetRegistry $session
::GX::loadManifest [file join $session metadata manifest.ini]
::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
::GX::PlotDatasetAPIv4::prepare3DPreview $reference $output
puts NATIVE3D_PREPARED
