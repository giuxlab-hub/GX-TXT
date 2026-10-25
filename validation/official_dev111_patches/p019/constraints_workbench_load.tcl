lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p019_constraints_workbench_load__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
::GX::createNewSession p019_load {} 0
package require Tk;wm withdraw .
set errors {}
proc bgerror {message} {lappend ::errors $message;puts stderr "BG: $message"}
set code 0
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 component load}}]
 set host [::GX::CurveWorkbench::_cadCanvas $w];set a [$host advanced]
 if {[lsearch -exact [info object methods $a -all] constraint]<0} {error {Missing constraint controller}}
 if {[::GX::CurveWorkbench::_constraintOptions $w] ne {}} {error {Empty drawing should have no constraint choices}}
 ::GX::CurveWorkbench::_draw $w
 set ::wait 1;after 150 {set ::wait 0};vwait ::wait
 if {$errors ne {}} {error "Background errors: $errors"}
 puts {PASS normal Workbench activation/shared component load only}
} on error {message options} {puts stderr "$message\n[dict get $options -errorinfo]";set code 1} finally {
 set f [open [file join $output RESULT.txt] w];puts $f [expr {$code?{FAIL}:{PASS load only}}];close $f
 catch {destroy .}
}
exit $code
