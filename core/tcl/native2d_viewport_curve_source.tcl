# SPDX-License-Identifier: GPL-3.0-or-later
# Curve Source + existing Native2D Viewport composition. No new data store,
# plotting model, scientific selection engine, renderer or worker is introduced.
proc ::GX::native2DViewportCurveCreate {parent session request {options {}}} {
    variable ::GX::ViewportHost::hosts
    foreach key [dict keys $options] {if {$key ni {selected completed progress color title}} {error "Unknown embedded curve option '$key'"}}
    if {[file normalize $session] ne [file normalize $::GX::currentSession]} {error {Embedded curve requires the current scientific Session}}
    set canvas [expr {$parent eq "." ? ".curve" : "$parent.curve"}]
    if {![winfo exists $parent]||[winfo exists $canvas]} {error {Embedded curve parent is unavailable or its curve child already exists}}
    set token [curveSourceOpen $session $request];set scene {};set attached 0
    try {
        set descriptor [curveSourceDescribe $token]
        native2DEnsure;set scene [::GX::Native2D::core scene]
        ::GX::Native2D::core aspect $scene auto
        canvas $canvas -highlightthickness 0 -background white -width 640 -height 420
        native2DViewportHostCreate $parent $canvas $scene [list ::GX::_native2DViewportCurveSchedule $canvas]
        set attached 1
        dict set hosts $canvas curve [dict create token $token scene $scene descriptor $descriptor options $options status loading job {} object {} pending {} pan {} closing 0]
        bind $canvas <Configure> +[list ::GX::_native2DViewportCurveSchedule $canvas]
        bind $canvas <Button-1> [list ::GX::native2DViewportCurveHit $canvas %x %y 1]
        bind $canvas <Button-4> [list ::GX::native2DViewportCurveNavigate $canvas zoom 1.2 %x %y]
        bind $canvas <Button-5> [list ::GX::native2DViewportCurveNavigate $canvas zoom [expr {1/1.2}] %x %y]
        bind $canvas <MouseWheel> [list ::GX::_native2DViewportCurveWheel $canvas %D %x %y]
        bind $canvas <ButtonPress-2> [list ::GX::native2DViewportCurveNavigate $canvas pan_begin %x %y]
        bind $canvas <B2-Motion> [list ::GX::native2DViewportCurveNavigate $canvas pan %x %y]
        bind $canvas <ButtonRelease-2> [list ::GX::native2DViewportCurveNavigate $canvas pan_end]
        bind $canvas <Double-Button-1> [list ::GX::native2DViewportCurveNavigate $canvas fit]
        set progress [datasetPublicationV2DictDefault $options progress {}]
        dict set hosts $canvas curve job [curveSourceDisplayAsync $token [list ::GX::_native2DViewportCurveDone $canvas $token] $progress]
        return $canvas
    } on error {message opts} {
        if {$attached} {catch {destroy $canvas}} else {if {$scene ne {}} {catch {::GX::Native2D::core destroy $scene}};catch {curveSourceClose $token}}
        return -options $opts $message
    }
}
proc ::GX::_native2DViewportCurveRequire {canvas} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $canvas curve]||![winfo exists $canvas]} {error {Embedded curve is closed}}
    set record [dict get $hosts $canvas curve]
    if {[dict get $record closing]} {error {Embedded curve is closing}}
    curveSourceDescribe [dict get $record token]
    return $record
}
proc ::GX::native2DViewportCurveDescribe {canvas} {
    set record [_native2DViewportCurveRequire $canvas]
    set result [dict create api_id NATIVE2D_VIEWPORT_HOST_v1 host_kind curve_source source [dict get $record descriptor] status [dict get $record status] display_is_scientific_data 0]
    if {[dict exists $record display]} {dict set result display [dict get $record display];dict set result view [::GX::Native2D::core view [dict get $record scene]]}
    return $result
}
proc ::GX::_native2DViewportCurveDone {canvas token result} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $canvas curve]||[dict get $hosts $canvas curve closing]||[dict get $hosts $canvas curve token] ne $token} return
    dict set hosts $canvas curve job {}
    if {[catch {
        set record [_native2DViewportCurveRequire $canvas]
        if {[dict get $result status] ne "ok"} {error [datasetPublicationV2DictDefault $result message {Embedded source loading cancelled}]}
        set display [dict get $result display];set scene [dict get $record scene]
        set object [::GX::Native2D::core add $scene [dict get $display points]]
        if {[dict get $display breaks] ne {}} {::GX::Native2D::core set_breaks $scene $object [dict get $display breaks]}
        set color [uiFieldColorToRGBA [datasetPublicationV2DictDefault [dict get $record options] color #245caa]]
        ::GX::Native2D::core object_style $scene $object [dict create color $color line_width 1.5 visible 1 locked 1]
        dict set hosts $canvas curve object $object;dict set hosts $canvas curve display $display;dict set hosts $canvas curve status ready
        dict set hosts $canvas curve subscription [datasetCatalogSubscribe [list ::GX::_native2DViewportCurveCatalog $canvas]]
        native2DViewportCurveNavigate $canvas fit
    } message opts]} {
        dict set hosts $canvas curve status unavailable
        $canvas delete all;$canvas create text 12 12 -anchor nw -width 500 -text "Curve source unavailable: $message" -tags source_status
        set result [dict create status error message $message]
    }
    set callback [datasetPublicationV2DictDefault [dict get $hosts $canvas curve options] completed {}]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $canvas $result]}
}
proc ::GX::_native2DViewportCurveCatalog {canvas receipt} {
    if {[catch {_native2DViewportCurveRequire $canvas} message]} {
        if {[winfo exists $canvas]} {$canvas delete all;$canvas create text 12 12 -anchor nw -width 500 -text "Curve source unavailable: $message" -tags source_status}
        return
    }
}
proc ::GX::_native2DViewportCurveSchedule {canvas} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $canvas curve]||[dict get $hosts $canvas curve pending] ne {}} return
    dict set hosts $canvas curve pending [after idle [list ::GX::_native2DViewportCurveDraw $canvas]]
}
proc ::GX::_native2DViewportCurveDraw {canvas} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $canvas curve]||![winfo exists $canvas]} return
    dict set hosts $canvas curve pending {}
    if {[catch {set record [_native2DViewportCurveRequire $canvas]} message]} {_native2DViewportCurveCatalog $canvas {};return}
    if {[dict get $record status] ne "ready"||[winfo width $canvas]<160||[winfo height $canvas]<120} return
    set scene [dict get $record scene];set view [::GX::Native2D::core view_requested $scene]
    lset view 0 [winfo width $canvas];lset view 1 [winfo height $canvas];set view [lreplace $view 2 5 85 32 28 58]
    ::GX::Native2D::core view $scene $view
    set axes [dict get [dict get $record descriptor] variables];set labels {}
    foreach axis {x y} spec $axes {
        set label [datasetPublicationV2DictDefault $spec display_label [dict get $spec variable_id]]
        if {[dict get $spec unit] ne {}} {append label " ([dict get $spec unit])"}
        dict set labels ${axis}_label $label
    }
    native2DCanvasSnapshot $canvas [native2DPresentationSnapshot $scene [dict merge $labels [dict create title [datasetPublicationV2DictDefault [dict get $record options] title {}] point_budget 65536]]]
}
proc ::GX::_native2DViewportCurveWheel {canvas delta x y} {native2DViewportCurveNavigate $canvas zoom [expr {pow(1.2,$delta/120.)}] $x $y}
proc ::GX::native2DViewportCurveNavigate {canvas action args} {
    variable ::GX::ViewportHost::hosts
    set record [_native2DViewportCurveRequire $canvas]
    if {[dict get $record status] ne "ready"} return
    set scene [dict get $record scene]
    switch $action {
        fit {::GX::Native2D::core fit_bounds $scene [dict get $record display full_bounds]}
        zoom {lassign $args factor x y;::GX::Native2D::core zoom $scene $factor [list $x $y]}
        pan_begin {dict set hosts $canvas curve pan $args;return}
        pan {if {[dict get $record pan] eq {}} return;lassign [dict get $record pan] oldX oldY;lassign $args x y;::GX::Native2D::core pan $scene [expr {$x-$oldX}] [expr {$y-$oldY}];dict set hosts $canvas curve pan $args}
        pan_end {dict set hosts $canvas curve pan {};return}
        default {error {Unknown embedded curve navigation action}}
    }
    _native2DViewportCurveSchedule $canvas
}
proc ::GX::native2DViewportCurveHit {canvas x y {notify 0}} {
    set record [_native2DViewportCurveRequire $canvas]
    if {[dict get $record status] ne "ready"} {return {hit 0}}
    set hit [::GX::Native2D::core hit_point_device [dict get $record scene] [dict get $record object] [list $x $y] 8]
    if {$hit eq {}} {return {hit 0}}
    set index [dict get $hit index];set row [lindex [dict get $record display source_rows] $index]
    set result [dict create hit 1 source_id [dict get $record descriptor source_id] source_row_ordinal $row row_identity_kind [dict get $record descriptor row_identity_kind] xy [lindex [dict get $record display points] $index] variables [dict get $record descriptor variables] display_is_scientific_data 0]
    set callback [datasetPublicationV2DictDefault [dict get $record options] selected {}]
    if {$notify && $callback ne {}} {uplevel #0 [list {*}$callback $canvas $result]}
    return $result
}
proc ::GX::_native2DViewportCurveDispose {canvas} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $canvas curve]} return
    set record [dict get $hosts $canvas curve];dict set hosts $canvas curve closing 1
    if {[dict get $record pending] ne {}} {after cancel [dict get $record pending]}
    if {[dict exists $record subscription]} {datasetCatalogUnsubscribe [dict get $record subscription]}
    if {[dict get $record job] ne {}} {curveSourceCancel [dict get $record job]}
    curveSourceClose [dict get $record token]
    ::GX::Native2D::core destroy [dict get $record scene]
    dict unset hosts $canvas curve
}
proc ::GX::native2DViewportCurveDestroy {canvas} {if {[winfo exists $canvas]} {destroy $canvas}}
