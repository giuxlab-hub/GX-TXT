# SPDX-License-Identifier: GPL-3.0-or-later
# Session-free presentation adapter for the existing public Plot v4 native owner.
namespace eval ::GX::NativePlotDisplay {variable widgets {}}
proc ::GX::nativePlotDisplayApiInfo {} {return [dict create api_id NATIVE_PLOT_DISPLAY_API_v1 api_version 1 owner PLOT_DATASET_API_v4 renderer Native2D.C++.Cairo operations {create view inspect hit destroy} provenance display_only_RAM publication 0]}
proc ::GX::nativePlotDisplayCreate {path model {callback {}}} {
    if {[dict size $::GX::NativePlotDisplay::widgets]>=8} {error {Temporary Plot display limit reached}}
    if {[string bytelength $model]>1048576} {error {Temporary Plot model exceeds 1 MiB}}
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    # The public Plot owner prepares the model; it never acquires scientific sources.
    set model [::GX::PlotDatasetAPIv4::modelFromSpec $model {prepared_model 1}]
    if {[llength [dict get $model panels]]>4} {error {Temporary Plot supports at most four panels}}
    foreach panel [dict get $model panels] {
        if {[llength [dict get $panel series]]>8} {error {Temporary Plot supports at most eight series per panel}}
        foreach series [dict get $panel series] {
            foreach key {dataset_id source_descriptor source_descriptors cell_field_binding} {if {[dict exists $series $key]} {error {Temporary Plot cannot bind scientific identities}}}
            if {[dict get $series kind] ni {line line_marker scatter}||[llength [dict get $series points]]>4096} {error {Temporary Plot requires bounded RAM line/marker/scatter points}}
        }
    }
    set token [::gx::native2d::plot_v4 create $model]
    try {::gx::native2d::surface $path} on error {message opts} {::gx::native2d::plot_v4 destroy $token;return -options $opts $message}
    dict set ::GX::NativePlotDisplay::widgets $path [dict create token $token callback $callback pending {} receipt {} drag {}]
    bind $path <Configure> [list ::GX::_nativePlotDisplaySchedule $path]
    bind $path <Destroy> [list ::GX::_nativePlotDisplayDispose $path %W]
    bind $path <Button-4> [list ::GX::nativePlotDisplayView $path zoom 1.25]
    bind $path <Button-5> [list ::GX::nativePlotDisplayView $path zoom 0.8]
    bind $path <Double-Button-1> [list ::GX::nativePlotDisplayView $path fit]
    bind $path <Button-1> [list ::GX::nativePlotDisplayHit $path %x %y]
    bind $path <ButtonPress-2> [list ::GX::_nativePlotDisplayPan $path start %x %y]
    bind $path <B2-Motion> [list ::GX::_nativePlotDisplayPan $path update %x %y]
    bind $path <ButtonRelease-2> [list ::GX::_nativePlotDisplayPan $path end %x %y]
    _nativePlotDisplaySchedule $path
    return $path
}
proc ::GX::_nativePlotDisplaySchedule {path} {
    if {![dict exists $::GX::NativePlotDisplay::widgets $path]||[dict get $::GX::NativePlotDisplay::widgets $path pending] ne {}} return
    dict set ::GX::NativePlotDisplay::widgets $path pending [after idle [list ::GX::_nativePlotDisplayDraw $path]]
}
proc ::GX::_nativePlotDisplayDraw {path} {
    if {![dict exists $::GX::NativePlotDisplay::widgets $path]||![winfo exists $path]} return
    dict set ::GX::NativePlotDisplay::widgets $path pending {}
    if {[winfo width $path]<160||[winfo height $path]<120} return
    set result [::gx::native2d::plot_v4 draw [dict get $::GX::NativePlotDisplay::widgets $path token] [winfo width $path] [winfo height $path]]
    $path draw [dict get $result primitives]
    dict set ::GX::NativePlotDisplay::widgets $path receipt [dict get $result receipt]
}
proc ::GX::nativePlotDisplayView {path operation {factor 1}} {
    set token [dict get $::GX::NativePlotDisplay::widgets $path token]
    if {$operation eq {fit}} {::gx::native2d::plot_v4 fit $token} elseif {$operation eq {zoom}} {
        if {![string is double -strict $factor]||$factor<0.1||$factor>10} {error {Temporary Plot zoom is outside bounds}}
        foreach axis [dict get [::gx::native2d::plot_v4 receipt $token] axes] {if {[dict get $axis axis] eq {x}} {::gx::native2d::plot_v4 view $token [dict get $axis panel_id] zoom $factor .5 .5}}
    } else {error {Temporary Plot supports fit and zoom}}
    _nativePlotDisplayEmit $path view_changed [dict create operation $operation];_nativePlotDisplaySchedule $path
}
proc ::GX::_nativePlotDisplayPan {path phase x y} {
    set r [dict get $::GX::NativePlotDisplay::widgets $path]
    if {$phase eq {start}} {dict set ::GX::NativePlotDisplay::widgets $path drag [list $x $y];return}
    if {$phase eq {end}} {dict set ::GX::NativePlotDisplay::widgets $path drag {};return}
    if {[dict get $r drag] eq {}} return
    lassign [dict get $r drag] px py;set token [dict get $r token]
    foreach axis [dict get [::gx::native2d::plot_v4 receipt $token] axes] {
        if {[dict get $axis axis] ne {x}} continue
        lassign [dict get $axis plot_rect] left top right bottom
        ::gx::native2d::plot_v4 view $token [dict get $axis panel_id] pan [expr {($px-$x)/double($right-$left)}] [expr {($y-$py)/double($bottom-$top)}]
    }
    dict set ::GX::NativePlotDisplay::widgets $path drag [list $x $y]
    _nativePlotDisplayEmit $path view_changed {operation pan};_nativePlotDisplaySchedule $path
}
proc ::GX::nativePlotDisplayHit {path x y} {
    set hit [::gx::native2d::plot_v4 hit [dict get $::GX::NativePlotDisplay::widgets $path token] $x $y]
    _nativePlotDisplayEmit $path selection [dict create native_hit $hit source_identity {}]
    return $hit
}
proc ::GX::_nativePlotDisplayEmit {path event detail} {
    set callback [dict get $::GX::NativePlotDisplay::widgets $path callback]
    if {$callback ne {}} {catch {{*}$callback $path [dict create author demo_fixture provenance display_only_RAM event $event detail $detail]}}
}
proc ::GX::nativePlotDisplayInspect {path} {return [dict create api_id NATIVE_PLOT_DISPLAY_API_v1 owner PLOT_DATASET_API_v4 renderer Native2D.C++.Cairo source_identity {} provenance display_only_RAM publication 0 receipt [dict get $::GX::NativePlotDisplay::widgets $path receipt]]}
proc ::GX::_nativePlotDisplayDispose {path actual} {
    if {$actual ne $path||![dict exists $::GX::NativePlotDisplay::widgets $path]} return
    set r [dict get $::GX::NativePlotDisplay::widgets $path]
    if {[dict get $r pending] ne {}} {after cancel [dict get $r pending]}
    ::gx::native2d::plot_v4 destroy [dict get $r token]
    dict unset ::GX::NativePlotDisplay::widgets $path
}
proc ::GX::nativePlotDisplayDestroy {path} {if {[winfo exists $path]} {destroy $path}}
