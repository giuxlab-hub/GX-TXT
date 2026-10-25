lassign $argv framework out
if {[file exists $out]} {error {New output required}}
file mkdir $out;set out [file normalize $out]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $out $dir];file mkdir $::env($key)}
set argv0 __p019_probe__;source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
::GX::configurationSet storage.session_root [file join $out Sessions];::GX::configurationSet storage.temp_dir [file join $out tmp];::GX::configurationSave {storage.session_root storage.temp_dir}
::GX::createNewSession p019probe {} 0
package require Tk
::GX::native2DEnsure
set scene [::GX::Native2D::core scene];frame .embedded;pack .embedded -fill both -expand 1
set host [::GX::native2DCadCanvasCreate .embedded $scene];pack [$host canvas] -fill both -expand 1
set tools [$host advanced]
$tools construction start line {auto_commit 0}
$tools construction adopt {{point {0 0}} {point {2 0}}}
set first [$tools construction commit]
$tools construction adopt {{point {2 0}} {point {4 0}}}
set second [$tools construction commit]
set join [$tools topology apply join_path [list [dict get $first id] [dict get $second id]] {tolerance 1e-9}]
set copies [$tools topology apply separate [list $join]]
if {[llength $copies]!=2} {error {Separate did not preserve exact constituents}}
puts [dict create first $first second $second joined $join separated $copies state [$tools state]]
$host dispose
::GX::Native2D::core destroy $scene
set f [open [file join $out RESULT.txt] w];puts $f {PASS supplementary API smoke only};close $f
exit 0
