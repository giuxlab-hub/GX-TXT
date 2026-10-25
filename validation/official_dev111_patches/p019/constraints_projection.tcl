lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p019_constraints_projection__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
::GX::createNewSession p019_projection {} 0
package require Tk;wm geometry . 1000x700+10+10
set errors {};set inputs {};set result {};set code 0
proc write {name value} {set f [open [file join $::output $name] w];puts $f $value;close $f}
proc bgerror {message} {lappend ::errors $message}
proc pause {{ms 120}} {set ::wait 1;after $ms {set ::wait 0};vwait ::wait}
proc xt {args} {lappend ::inputs [list [clock microseconds] {*}$args];exec xdotool {*}$args}
proc at {device} {xt mousemove [expr {[winfo rootx $::canvas]+int([lindex $device 0])}] [expr {[winfo rooty $::canvas]+int([lindex $device 1])}]}
proc label {} {foreach item [$::canvas find withtag cad_relation_preview] {if {[$::canvas type $item] eq {text}} {return [$::canvas coords $item]}};return {}}
try {
 ::GX::native2DEnsure;set scene [::GX::Native2D::core scene]
 set id [::GX::Native2D::core sketch_create $scene {family line controls {{0 0} {4 0}}} 128]
 ::GX::Native2D::core object_style $scene $id {color {0.1 0.3 0.7 1} line_width 2}
 frame .embed;pack .embed -fill both -expand 1
 set host [::GX::native2DCadCanvasCreate .embed $scene];set canvas [$host canvas];pack $canvas -fill both -expand 1
 set a [$host advanced];set cad [$host context];$host fit;pause 200
 set before [$cad object definition $id]
 at [::GX::Native2D::core device $scene {1 -0.4}];xt click 1;pause 80
 $a dimension start distance [list [$cad selection reference $id object 0]]
 at [::GX::Native2D::core device $scene {1.5 -0.5}];pause 180
 set staged [$a dimension state];set drawnBefore [label];set viewBefore [::GX::Native2D::core view $scene]
 if {$drawnBefore eq {}} {error {Pointer hover did not render staged dimension}}
 xt click 4;pause 220
 set fresh [$cad relationship dimension_preview [dict get $staged specification] [dict get $staged annotation]]
 set expected [dict get $fresh label];set actual [label]
 set matches [expr {[llength $actual]==2 && abs([lindex $actual 0]-[lindex $expected 0])<1e-8 && abs([lindex $actual 1]-[lindex $expected 1])<1e-8}]
 set actualLines {};foreach item [$canvas find withtag cad_relation_preview] {if {[$canvas type $item] eq {line}} {lappend actualLines [$canvas coords $item]}}
 set expectedLines {};foreach line [dict get $fresh lines] {lappend expectedLines [concat {*}$line]}
 set linesMatch [expr {[llength $actualLines]==[llength $expectedLines]}]
 foreach actualLine $actualLines expectedLine $expectedLines {foreach actualValue $actualLine expectedValue $expectedLine {if {abs($actualValue-$expectedValue)>1e-8} {set linesMatch 0}}}
 set result [dict create before_view $viewBefore after_view [::GX::Native2D::core view $scene] before_label $drawnBefore actual_label $actual native_expected_label $expected projection_matches $matches actual_lines $actualLines native_expected_lines $expectedLines line_projection_matches $linesMatch]
 exec import -silent -window root [file join $output staged-wheel.png]
 xt key Escape;pause 120
 dict set result cancel_clean [expr {[$canvas find withtag cad_relation_preview] eq {} && [$cad object definition $id] eq $before && [$cad relationship list] eq {}}]
 dict set result background_errors $errors
 if {!$matches || !$linesMatch || ![dict get $result cancel_clean] || $errors ne {}} {error {Staged projection or cancellation failed}}
 puts {PASS actual hover-wheel native projection and Escape integrity}
} on error {message options} {set code 1;dict set result failure $message;dict set result errorinfo [dict get $options -errorinfo];puts stderr $message} finally {
 write receipt.tcldict $result;write input.tcllist $inputs;write RESULT.txt [expr {$code?{FAIL}:{PASS}}]
 catch {$host dispose};catch {destroy .}
}
exit $code
