# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output kind mode expectedRetry
if {[file exists $output] || $kind ni {component legacy} || $mode ni {Auto Software}} {error {Use a new private output and a supported launch case}}
set root [file normalize $root];file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __P021_GRAPHICS_STARTUP__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
proc write {name value} {set f [open [file join $::output $name] w];puts $f $value;close $f}
proc pause {} {set ::waiting 1;after 50 {set ::waiting 0};vwait ::waiting}
set errors {};set ::h {};set code 0
proc bgerror {message} {lappend ::errors [dict create message $message info $::errorInfo]}
::GX::configurationSet viewers.native3d.preset High
::GX::configurationSet viewers.native3d.execution $mode
set requested [::GX::native3dGraphicsPolicy]
write requested.tcldict $requested
try {
    if {$kind eq {legacy}} {
        ::GX::configurationSet viewers.native3d.msaa Off
        set ::env(__GLX_VENDOR_LIBRARY_NAME) nvidia
        set before {};foreach key {LIBGL_ALWAYS_SOFTWARE LIBGL_ALWAYS_INDIRECT MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER __GLX_VENDOR_LIBRARY_NAME} {dict set before $key [expr {[info exists ::env($key)] ? [list 1 $::env($key)] : [list 0 {}]}]}
        set result [::GX::Engine3D::graphicsCheck]
        set after {};foreach key [dict keys $before] {dict set after $key [expr {[info exists ::env($key)] ? [list 1 $::env($key)] : [list 0 {}]}]}
        if {$before ne $after} {error {Legacy worker leaked graphics environment into parent}}
        if {[dict get $result execution] ne {Software} || ![string match -nocase {*llvmpipe*} [dict get $result device]]} {error {Legacy Software worker did not actually select llvmpipe}}
        write result.tcldict $result;write environment-restored.tcldict [dict create restored 1 before $before after $after]
    } else {
        package require Tk
        wm title . {P021 private startup recovery check};wm geometry . 800x620+60+60
        set h [::GX::native3DViewportCreate .v]
        pack .v -fill both -expand 1
        update idletasks
        pause
        ::GX::native3DViewportBind $h {kind demo}
        set deadline [expr {[clock milliseconds]+45000}]
        set stable 0
        while {[clock milliseconds]<$deadline} {
            set result [::GX::native3DViewportInspect $h]
            if {[dict get $result status] in {error stale_source}} break
            set record [::GX::_native3DViewportRecord $h]
            if {[dict get $result status] eq {ready} && [dict get $result pending]==0 && [dict get $record resize] eq {}} {incr stable} else {set stable 0}
            if {$stable>=5} break
            pause
        }
        write result.tcldict $result
        set record [::GX::_native3DViewportRecord $h]
        foreach name {worker.log worker.software.log} {set path [file join [dict get $record directory] $name];if {[file exists $path]} {file copy $path [file join $output $name]}}
        if {[dict get $result status] ne {ready}} {error "Native startup not ready: [dict get $result error]"}
        if {[dict get $result software_retry]!=$expectedRetry} {error {Unexpected Auto retry count}}
        if {[::GX::native3dGraphicsPolicy] ne $requested} {error {Startup changed requested graphics quality}}
        if {$expectedRetry && ([dict get $result hardware_error] eq {} || [dict get $result result execution] ne {Software} || ![string match -nocase {*llvmpipe*} [dict get $result result device]])} {error {Fallback did not preserve the actual hardware failure and Mesa identity}}
        [dict get $record photo] write [file join $output canvas-photo.png] -format png
        file copy [file join [dict get $record directory] frame.png] [file join $output native-frame.png]
    }
    write RESULT.txt {PASS actual native startup/policy checks; this is not mouse/GUI acceptance}
} on error {message options} {write FAILURE.tcldict [dict create message $message options $options];puts stderr [dict get $options -errorinfo];set code 1} finally {
    if {$h ne {}} {catch {::GX::native3DViewportRelease $h}}
    catch {::GX::Engine3D::stopWorker}
    set deadline [expr {[clock milliseconds]+2500}]
    while {[dict size $::GX::Native3DCanvas::retiring] && [clock milliseconds]<$deadline} {pause}
    write CLEANUP.tcldict [dict create instances [dict size $::GX::Native3DCanvas::instances] retiring [dict size $::GX::Native3DCanvas::retiring] legacy_worker $::GX::Engine3D::worker errors $errors]
    catch {destroy .}
}
if {[llength $errors]} {set code 1}
exit $code
