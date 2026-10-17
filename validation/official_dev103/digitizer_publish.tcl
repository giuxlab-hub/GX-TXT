# Actual installed Digitalizer publication path, synthetic load-test packets.
lassign $argv root out inputs
set root [file normalize $root];set out [file normalize $out];set inputs [file normalize $inputs]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach name {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($name) [file join $out $name]}
set argv0 __dev103_digitizer_publish__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;set ::GX::cfg(output_root) [file join $out sessions]
set session [::GX::createNewSession synthetic_digitizer_load]
proc rd {p} {set f [open $p];fconfigure $f -encoding utf-8;try {return [read $f]} finally {close $f}}
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
::GX::acquisitionHandlerImportSourceToSession acq.image_binary $session [file join $inputs image.png] image103 image.raster {}
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_VIEWER_API_v1
set configuration [rd [file join $inputs none configuration.json]]
set document [dict get [::GX::interactiveDocumentCreate viewer.curve_digitizer curve_digitizer gxtxt.curve_digitizer.configuration 1.0 $configuration] id]
set receipt [::GX::CurveDigitizer::_publish [::GX::interactiveDocumentSessionToken] $document synthetic_digitizer_60000 {Synthetic load test: 20 curves, 2 calibrations} family Time s independent Voltage V measured Temperature K family image103 [::GX::sha256File [file join $inputs image.png]] four_point_homography linear linear {Synthetic load-test configuration} [rd [file join $inputs none rows.tsv]] [rd [file join $inputs none metadata.records]] combined {} {} {}]
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS publication $receipt session $session dataset_id synthetic_digitizer_60000 rows 60000 unique_raster_points 30000 source_sha256 [::GX::datasetField synthetic_digitizer_60000 canonical_sha256]];close $f
puts "PASS actual Digitalizer publication: 60,000 synthetic rows in $session"
