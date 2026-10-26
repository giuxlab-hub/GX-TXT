# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root request output
set root [file normalize $root];set output [file normalize $output]
if {[file exists $output]} {error {Fresh native contract output required}}
file mkdir $output
load [file join $root core native2d bin gx2dtcl.so] Gx2dtcl
set scene [::GX::Native2D::core scene]
set rows {{0 0} {0.000001 200} {-0.000001 -100} {0.000003 400}}
set checks {}
try {
    foreach aspect {auto xy_equal} {
        ::GX::Native2D::core aspect $scene $aspect
        ::GX::Native2D::core view $scene {640 480 30 20 10 25 {-0.000002 -200 0.000004 600}}
        set device [::GX::Native2D::core device_points $scene $rows]
        set scalar [lmap point $rows {::GX::Native2D::core device $scene $point}]
        if {$device ne $scalar} {error {Batched native device coordinates differ}}
        set world [::GX::Native2D::core world_points $scene $device]
        set scalar [lmap point $device {::GX::Native2D::core world $scene $point}]
        if {$world ne $scalar} {error {Batched native world coordinates differ}}
        dict set checks coordinates/$aspect PASS
    }
    set view [::GX::Native2D::core view $scene]
    foreach bad {{{1 2} {3}} {{1 2} {NaN 4}}} {
        if {![catch {::GX::Native2D::core world_points $scene $bad}]} {error {Malformed coordinate batch accepted}}
    }
    if {$view ne [::GX::Native2D::core view $scene]} {error {Rejected coordinate batch mutated native view}}
} finally {::GX::Native2D::core destroy $scene}
load [file join $root core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
set f [open $request r];set render [string trim [read $f]];close $f
set model [lindex $render 1];dict set model graphics_policy execution Software
set steps {{orbit 14 7} {pan 8 -5} {roll 4 0} {zoom 1 0} {orbit -3 11} {pan -2 6} {zoom -1 0}}
::GX3DEViewer::projection enable 1
foreach mode {perspective orthographic} {
    dict set model view projection $mode
    ::GX3DEViewer::frame_transport png
    ::GX3DEViewer::render $model [file join $output ${mode}-initial.png] 640 480 full
    ::GX3DEViewer::frame_transport fast_png
    foreach step $steps {set sequential [::GX3DEViewer::navigate {*}$step [file join $output ${mode}-sequential.png]]}
    ::GX3DEViewer::render $model [file join $output ${mode}-reset.png] 640 480 full
    set batch [::GX3DEViewer::navigate_batch $steps [file join $output ${mode}-batch.png]]
    foreach key {camera_position camera_target camera_up} {
        foreach x [dict get $sequential $key] y [dict get $batch $key] {
            if {abs($x-$y)>1e-12} {error "Ordered native camera batch differs: $mode $key $x $y"}
        }
    }
    set prior [::GX3DEViewer::projection snapshot]
    if {![catch {::GX3DEViewer::navigate_batch {{orbit 1 2} {unknown 0 0}} [file join $output rejected.png]}]} {error {Malformed camera batch accepted}}
    if {$prior ne [::GX3DEViewer::projection snapshot]} {error {Rejected camera batch changed camera/projection}}
    ::GX3DEViewer::frame_transport png [file join $output ${mode}-standard.png]
    ::GX3DEViewer::frame_transport fast_png [file join $output ${mode}-fast.png]
    dict set checks navigation/$mode [dict create result PASS operation_count [dict get $batch navigation_operations] timings_ms [dict get $batch timings_ms]]
    set pngSamples {}
    foreach transport {png fast_png} {
        set durations {}
        for {set repeat 0} {$repeat<3} {incr repeat} {
            set begin [clock microseconds]
            ::GX3DEViewer::frame_transport $transport [file join $output ${mode}-${transport}-${repeat}.png]
            lappend durations [expr {([clock microseconds]-$begin)/1000.0}]
        }
        dict set pngSamples $transport $durations
    }
    dict set checks same_frame_png/$mode $pngSamples
}
::GX3DEViewer::close
set f [open [file join $output CONTRACT.tcldict] w];puts $f $checks;close $f
puts $checks
