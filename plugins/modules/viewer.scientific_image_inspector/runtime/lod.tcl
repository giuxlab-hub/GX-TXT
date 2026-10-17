# Full-resolution source-backed viewport LOD for Scientific Image Inspector.
# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D supplies all world/device coordinates; ImageMagick only samples the
# authorized original/processed raster. No Tk image upscale is authoritative.
namespace eval ::GX::SII {variable lodJobs [dict create]}
proc ::GX::SII::lodReset {} {
    variable ui
    foreach which {original processed} {
        if {[info exists ui(lodTimer-$which)]} {catch {after cancel $ui(lodTimer-$which)}}
        unset -nocomplain ui(lodTimer-$which) ui(lodWant-$which) ui(lodReady-$which)
        if {[info exists ui(lodImage-$which)]} {catch {image delete $ui(lodImage-$which)}}
        unset -nocomplain ui(lodImage-$which)
        if {[info exists ui(lodFile-$which)]} {catch {file delete -- $ui(lodFile-$which)}}
        unset -nocomplain ui(lodFile-$which)
    }
    # Running workers will finish in the background and discard stale output.
}
proc ::GX::SII::lodPlan {which} {
    variable ui
    set c $ui(window).layout.main.panes.$which.canvas
    if {![winfo exists $c] || ![info exists ui(preview-$which)]} {return {}}
    set source [expr {$which eq "original" ? $ui(workingFile) : $ui(processedFile)}]
    set info [expr {$which eq "original" ? $ui(workingInfo) : $ui(processedInfo)}]
    set iw [dict get $info width];set ih [dict get $info height]
    if {$iw<1 || $ih<1} {return {}}
    set scene $ui(native-$which)
    set cw [winfo width $c];set ch [winfo height $c]
    if {$cw<20 || $ch<20} {return {}}
    lassign [::GX::Native2D::core world $scene [list 0 0]] ax ay
    lassign [::GX::Native2D::core world $scene [list $cw $ch]] bx by
    set x [expr {max(0,int(floor(min($ax,$bx))))}]
    set y [expr {max(0,int(floor($ih-max($ay,$by))))}]
    set right [expr {min($iw,int(ceil(max($ax,$bx))))}]
    set bottom [expr {min($ih,int(ceil($ih-min($ay,$by))))}]
    if {$right <= $x || $bottom <= $y} {return {}}
    set sw [expr {$right-$x}];set sh [expr {$bottom-$y}]
    lassign [::GX::Native2D::core device $scene [list $x [expr {$ih-$y}]]] dx0 dy0
    lassign [::GX::Native2D::core device $scene [list $right [expr {$ih-$bottom}]]] dx1 dy1
    set dw [expr {int(round(abs($dx1-$dx0)))}]
    set dh [expr {int(round(abs($dy1-$dy0)))}]
    if {$dw<10 || $dh<10 || $dw>4096 || $dh>4096 || wide($dw)*$dh>8500000} {return {}}
    # All fields are internal numeric/source identities, never untrusted argv.
    return [list $source $x $y $sw $sh $dw $dh [expr {int(round($dx0))}] [expr {int(round($dy0))}]]
}
proc ::GX::SII::lodRequest {which} {
    variable ui
    set plan [lodPlan $which]
    if {$plan eq {}} return
    set ui(lodWant-$which) $plan
    if {[info exists ui(lodReady-$which)] && $ui(lodReady-$which) eq $plan && [info exists ui(lodImage-$which)]} {
        lodPlace $which
        return
    }
    if {[info exists ui(lodTimer-$which)]} {after cancel $ui(lodTimer-$which)}
    set ui(lodTimer-$which) [after 160 [list ::GX::SII::lodStart $which]]
}
proc ::GX::SII::lodPlace {which} {
    variable ui
    if {![info exists ui(lodReady-$which)] || ![info exists ui(lodImage-$which)] || \
        ![info exists ui(lodWant-$which)] || $ui(lodReady-$which) ne $ui(lodWant-$which)} return
    set c $ui(window).layout.main.panes.$which.canvas
    if {![winfo exists $c]} return
    lassign $ui(lodReady-$which) source x y sw sh dw dh px py
    $c delete canvas_image
    $c create image $px $py -anchor nw -image $ui(lodImage-$which) -tags canvas_image
    $c lower canvas_image
    # Grid/geometry must remain on top of the LOD tiles.
}
proc ::GX::SII::lodStart {which} {
    variable ui
    variable lodJobs
    unset -nocomplain ui(lodTimer-$which)
    if {![info exists ui(window)] || ![winfo exists $ui(window)] || ![info exists ui(lodWant-$which)]} return
    if {[dict exists $lodJobs $which]} return
    set plan $ui(lodWant-$which)
    if {[info exists ui(lodReady-$which)] && $ui(lodReady-$which) eq $plan} return
    lassign $plan source x y sw sh dw dh px py
    set output [guiTemp .png]
    set argv [list [magickPath] {*}[limits] [frame0 $source] \
        -crop "${sw}x${sh}+${x}+${y}" +repage \
        -filter Lanczos -resize "${dw}x${dh}!" -depth 8 "PNG:$output"]
    if {[catch {
        set channel [open |[list {*}$argv 2>@1] r]
        fconfigure $channel -blocking 0 -encoding utf-8
        set job [dict create channel $channel pids [pid $channel] plan $plan output $output error {}]
        dict set job timeout [after 20000 [list ::GX::SII::lodTimeout $which $channel]]
        dict set lodJobs $which $job
        fileevent $channel readable [list ::GX::SII::lodDone $which $channel]
    } err]} {
        catch {file delete -- $output}
        set ui(status) "Viewport LOD unavailable: $err"
    }
}
proc ::GX::SII::lodTimeout {which channel} {
    variable lodJobs
    if {![dict exists $lodJobs $which] || [dict get $lodJobs $which channel] ne $channel} return
    set job [dict get $lodJobs $which]
    dict set job error {Viewport rendering timed out}
    dict set lodJobs $which $job
    foreach child [dict get $job pids] {
        if {$::tcl_platform(platform) eq "windows"} {catch {exec taskkill /PID $child /T /F}} else {catch {exec kill -TERM -- $child}}
    }
}
proc ::GX::SII::lodDone {which channel} {
    variable ui
    variable lodJobs
    if {![dict exists $lodJobs $which] || [dict get $lodJobs $which channel] ne $channel} return
    set job [dict get $lodJobs $which]
    if {[catch {set output [read $channel]} err]} {dict set job error $err;set output {}}
    if {[string length $output]>10000} {dict set job error {Excessive renderer diagnostic output}}
    dict set lodJobs $which $job
    if {![eof $channel]} return
    fileevent $channel readable {}
    after cancel [dict get $job timeout]
    if {[catch {close $channel} err]} {dict set job error $err}
    dict unset lodJobs $which
    set file [dict get $job output]
    set plan [dict get $job plan]
    if {[dict get $job error] eq {} && [file exists $file] && [file size $file]>0 \
        && [info exists ui(lodWant-$which)] && $ui(lodWant-$which) eq $plan \
        && [info exists ui(window)] && [winfo exists $ui(window)]} {
        if {[catch {set photo [image create photo -file $file]} err]} {
            catch {file delete -- $file}
        } else {
            if {[info exists ui(lodImage-$which)]} {catch {image delete $ui(lodImage-$which)}}
            if {[info exists ui(lodFile-$which)]} {catch {file delete -- $ui(lodFile-$which)}}
            set ui(lodImage-$which) $photo
            set ui(lodFile-$which) $file
            set ui(lodReady-$which) $plan
            lodPlace $which
        }
    } else {catch {file delete -- $file}}
    if {[info exists ui(lodWant-$which)] && $ui(lodWant-$which) ne $plan} {
        set ui(lodTimer-$which) [after 30 [list ::GX::SII::lodStart $which]]
    }
}
