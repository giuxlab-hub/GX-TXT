# Fresh headless process reads the same isolated XDG Configuration as desktop.
set root [lindex $argv 0];set argv0 __dev103_catalog_persist__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
if {[::GX::viewerProviderEnabled viewer.replicate_curve_analysis replicate_consensus]} {error {Disabled presentation did not persist}}
if {![::GX::moduleIsEnabled math.numeric]} {error {Essential numeric service was disabled}}
puts {PASS persisted Viewer disablement and preserved essential scientific service}
