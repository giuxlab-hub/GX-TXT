# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_COUNTER_PROFILE__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::native2DEnsure
source [file join [file dirname [info script]] counter.tcl]
set scene [::GX::Native2D::core scene];::GX::Native2D::core view $scene {800 600 0 0 0 0 {0 0 100 100}}
set result {}
foreach mode {off count span both} {
 set samples {}
 for {set j 0} {$j<3} {incr j} {
  ::EXP01Counter::start $mode
  set begin [clock microseconds]
  for {set i 0} {$i<20000} {incr i} {set xy [::GX::Native2D::core world $scene {400 300}]}
  set elapsed [expr {[clock microseconds]-$begin}];set receipt [::EXP01Counter::stop]
  if {$mode in {count both} && [dict get $receipt calls]!=20000} {error {Counter truncated}}
  lappend samples [dict create total_us $elapsed per_call_us [expr {$elapsed/20000.0}] count [dict get $receipt calls] point $xy]
 }
 dict set result $mode $samples
}
::GX::Native2D::core destroy $scene
set f [open [file join $output RESULT.tcldict] w];puts $f $result;close $f
puts $result
