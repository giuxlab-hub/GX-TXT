# SPDX-License-Identifier: GPL-3.0-or-later
# Isolated Tcl/VTK process. Standard output is a one-line Tcl-list protocol.
if {[llength $argv] != 1} {puts stderr "Usage: renderer_worker.tcl <bridge-library>";exit 2}
load [lindex $argv 0] Gx3deviewer
fconfigure stdin -buffering line -encoding utf-8 -translation lf
fconfigure stdout -buffering line -encoding utf-8 -translation lf
puts "GX3DE_VIEWER_WORKER_READY"
while {[gets stdin line] >= 0} {
    if {[catch {
        set command [lindex $line 0]
        set args [lrange $line 1 end]
        switch -- $command {
            cad {if {[llength $args]!=3} {error "cad expects owner scope, action and request"};set result [::GX3DEViewer::cad {*}$args]}
            render {if {[llength $args] != 5} {error "render expects scene, PNG, width, height, stage"};set result [::GX3DEViewer::render {*}$args]}
            graphics_probe {if {[llength $args] != 1} {error "graphics_probe expects policy"};set result [::GX3DEViewer::graphics_probe {*}$args]}
            pick {if {[llength $args] != 2} {error "pick expects x,y"};set result [::GX3DEViewer::pick {*}$args]}
            preset {if {[llength $args] != 5} {error "preset expects preset, layer, PNG, width, height"};set result [::GX3DEViewer::preset {*}$args]}
            navcube_pick {if {[llength $args] != 2} {error "navcube_pick expects x,y"};set result [::GX3DEViewer::navcube_pick {*}$args]}
            navcube_click {if {[llength $args] != 3} {error "navcube_click expects x,y,PNG"};set result [::GX3DEViewer::navcube_click {*}$args]}
            navigate {if {[llength $args] != 4} {error "navigate expects mode, delta x, delta y, PNG"};set result [::GX3DEViewer::navigate {*}$args]}
            gizmo_select {if {[llength $args] != 7} {error "gizmo_select expects layer, space, families, pivot, marker, size, PNG"};set result [::GX3DEViewer::gizmo_select {*}$args]}
            gizmo_pick {if {[llength $args] != 2} {error "gizmo_pick expects x,y"};set result [::GX3DEViewer::gizmo_pick {*}$args]}
            gizmo_begin {if {[llength $args] != 2} {error "gizmo_begin expects x,y"};set result [::GX3DEViewer::gizmo_begin {*}$args]}
            gizmo_update {if {[llength $args] != 3} {error "gizmo_update expects x,y,PNG"};set result [::GX3DEViewer::gizmo_update {*}$args]}
            gizmo_end {if {[llength $args] != 1} {error "gizmo_end expects accept"};set result [::GX3DEViewer::gizmo_end {*}$args]}
            export_png {if {[llength $args] != 3} {error "export_png expects path, width, height"};set result [::GX3DEViewer::export_png {*}$args]}
            timeline {if {[llength $args] != 3} {error "timeline expects action, value, PNG"};set result [::GX3DEViewer::timeline {*}$args]}
            plane_begin {if {[llength $args] != 6} {error "plane_begin expects target, action, handle, slot, x, y"};set result [::GX3DEViewer::plane_begin {*}$args]}
            plane_update {if {[llength $args] != 3} {error "plane_update expects x, y, PNG"};set result [::GX3DEViewer::plane_update {*}$args]}
            plane_end {if {[llength $args] != 1} {error "plane_end expects accept"};set result [::GX3DEViewer::plane_end {*}$args]}
            close {::GX3DEViewer::close;set result closed}
            default {error "Unknown renderer worker command"}
        }
    } error]} {puts [list error $error]} else {puts [list ok $result]}
    flush stdout
    if {$command eq "close"} break
}
