# SPDX-License-Identifier: GPL-3.0-or-later
# Existing Native2D Viewport Host projected from canonical Interactive Documents.
namespace eval ::GX::Native2DDiagram {variable viewports {};variable field}
source [file join [file dirname [info script]] native2d_diagram_wire_properties_v1.tcl]
proc ::GX::native2DGeometryDiagramViewportCreate {widget document {callback {}}} {
    native2DGeometryDiagramRead $document
    ttk::frame $widget
    canvas $widget.canvas -width 640 -height 420 -highlightthickness 0 -takefocus 1
    ttk::label $widget.status -anchor w -wraplength 800
    pack $widget.status -side bottom -fill x
    pack $widget.canvas -fill both -expand 1
    dict set ::GX::Native2DDiagram::viewports $widget [dict create document $document session_token [interactiveDocumentSessionToken] callback $callback projection {} tool select selected {} start {} route {} cursor {} hover_terminal {} drag {} pending {} last_notice {}]
    bind $widget <Destroy> [list ::GX::_native2DDiagramViewportDispose $widget %W]
    bind $widget.canvas <Configure> [list ::GX::_native2DDiagramViewportSchedule $widget]
    bind $widget.canvas <ButtonPress-1> [list ::GX::_native2DDiagramViewportPress $widget %x %y]
    bind $widget.canvas <B1-Motion> [list ::GX::_native2DDiagramViewportMotion $widget %x %y]
    bind $widget.canvas <Motion> [list ::GX::_native2DDiagramViewportCursor $widget %x %y]
    bind $widget.canvas <BackSpace> [list ::GX::native2DGeometryDiagramViewportCommand $widget wire_back]
    bind $widget.canvas <ButtonRelease-1> [list ::GX::_native2DDiagramViewportRelease $widget %x %y]
    bind $widget.canvas <Double-Button-1> [list ::GX::_native2DDiagramViewportDoublePress $widget %x %y]
    bind $widget.canvas <Escape> [list ::GX::native2DGeometryDiagramViewportCommand $widget tool select]
    bind $widget.canvas <Delete> [list ::GX::native2DGeometryDiagramViewportCommand $widget delete]
    bind $widget.canvas <Key-r> [list ::GX::native2DGeometryDiagramViewportCommand $widget rotate]
    bind $widget.canvas <Key-w> [list ::GX::native2DGeometryDiagramViewportCommand $widget tool wire]
    bind $widget.canvas <Key-j> [list ::GX::native2DGeometryDiagramViewportCommand $widget tool junction]
    bind $widget.canvas <Key-p> [list ::GX::native2DGeometryDiagramViewportCommand $widget tool pan]
    bind $widget.canvas <Key-f> [list ::GX::native2DGeometryDiagramViewportCommand $widget fit]
    bind $widget.canvas <Button-4> [list ::GX::native2DGeometryDiagramViewportCommand $widget zoom 1.2 %x %y]
    bind $widget.canvas <Button-5> [list ::GX::native2DGeometryDiagramViewportCommand $widget zoom 0.833333333333 %x %y]
    _native2DDiagramViewportProject $widget
    return $widget
}
proc ::GX::_native2DDiagramViewportRecord {w} {
    set r [dict get $::GX::Native2DDiagram::viewports $w]
    if {[dict get $r session_token] ne [interactiveDocumentSessionToken]} {error {Diagram belongs to a previous Session lifetime}}
    return $r
}
proc ::GX::native2DGeometryDiagramViewportDescribe {w {includeSource 1}} {
    set r [_native2DDiagramViewportRecord $w]
    set result [dict create document_id [dict get $r document] tool [dict get $r tool] selected [dict get $r selected] routing_active [expr {[dict get $r start] ne {}}] last_notice [dict get $r last_notice]]
    # Local chrome needs the current authoritative interaction state, not a
    # scientific payload receipt for every individual toolbar control. The
    # default full description and all edit/tool commands keep source checks.
    if {$includeSource} {dict set result source [dict remove [native2DGeometryDiagramRead [dict get $r document]] payload]}
    return $result
}
proc ::GX::_native2DDiagramViewportNotice {w message} {
    # Interaction errors remain readable through release, hover and repaint.
    # Only the next deliberate press or command clears this presentation state.
    dict set ::GX::Native2DDiagram::viewports $w last_notice $message
    $w.status configure -text $message
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportDoublePress {w x y} {
    # Tk selects the double-click binding instead of the second ordinary press.
    # A rapid wire end/start must therefore reach the same routing transaction.
    if {[dict get [_native2DDiagramViewportRecord $w] tool] eq {select}} {
        return [native2DGeometryDiagramViewportCommand $w properties]
    }
    return [_native2DDiagramViewportPress $w $x $y]
}
proc ::GX::_native2DDiagramViewportProject {w} {
    set r [_native2DDiagramViewportRecord $w]
    set view {}
    if {[dict get $r projection] ne {}} {
        set prior [dict get $r projection scene_token]
        # A canonical edit makes the old geometry token stale. Its display view
        # is still a host-owned presentation value, never a scientific source.
        if {[dict exists $::GX::Native2DGeometry::scenes $prior]} {set native [dict get $::GX::Native2DGeometry::scenes $prior native];set view [::GX::Native2D::core view $native]}
        native2DGeometryClose $prior
    }
    set projected [native2DGeometryDiagramProject [dict get $r document]]
    dict set r projection $projected
    dict set ::GX::Native2DDiagram::viewports $w $r
    set native [dict get [_native2DGeometryRequire [dict get $projected scene_token]] native]
    ::GX::Native2D::core aspect $native xy_equal
    ::GX::Native2D::core grid $native {enabled 1 visible 1 snap_enabled 1 spacing_x 10 spacing_y 10 axes_visible 0}
    if {$view ne {}} {::GX::Native2D::core view $native $view}
    if {[dict exists $::GX::ViewportHost::hosts $w.canvas]} {
        dict set ::GX::ViewportHost::hosts $w.canvas scene $native
    } else {native2DViewportHostCreate $w $w.canvas $native [list ::GX::_native2DDiagramViewportSchedule $w]}
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportSchedule {w} {
    if {![dict exists $::GX::Native2DDiagram::viewports $w] || ![winfo exists $w.canvas]} return
    if {[dict get $::GX::Native2DDiagram::viewports $w pending] eq {}} {dict set ::GX::Native2DDiagram::viewports $w pending [after idle [list ::GX::_native2DDiagramViewportDraw $w]]}
}
proc ::GX::_native2DDiagramViewportDraw {w} {
    if {![dict exists $::GX::Native2DDiagram::viewports $w] || ![winfo exists $w.canvas]} return
    dict set ::GX::Native2DDiagram::viewports $w pending {}
    if {[winfo width $w.canvas]<64 || [winfo height $w.canvas]<64} return
    if {[catch {
        set r [_native2DDiagramViewportRecord $w]
        set projection [dict get $r projection];set scene [_native2DGeometryRequire [dict get $projection scene_token]]
        set native [dict get $scene native]
        set view [::GX::Native2D::core view_requested $native]
        lset view 0 [winfo width $w.canvas];lset view 1 [winfo height $w.canvas];set view [lreplace $view 2 5 16 16 16 16]
        ::GX::Native2D::core view $native $view
        set ghost {};set transient {}
        try {
            set payload [dict get [native2DGeometryDiagramRead [dict get $r document]] payload]
            set drag [dict get $r drag]
            if {$drag ne {} && [dict exists $drag request]} {
                set operation [expr {[dict get $drag kind] eq {move}?{transform}:{label}}]
                set candidate [native2DGeometryDiagramEdit [dict get $r document] [dict get $projection document] $operation [dict get $drag request] preview]
                set transient [native2DGeometryDiagramProject [dict get $r document] $candidate]
                set projection $transient
                set payload [dict get $candidate proposed_payload]
                set scene [_native2DGeometryRequire [dict get $projection scene_token]]
                set native [dict get $scene native]
                ::GX::Native2D::core view $native $view
                ::GX::Native2D::core grid $native {enabled 1 visible 1 snap_enabled 1 spacing_x 10 spacing_y 10 axes_visible 0}
            }
            set options [dict create point_budget 4096 legend 0 axes_visible 0 include_construction_reference 1 font_size 13 annotations [dict get $projection annotations]]
            if {[dict get $r start] ne {} && [dict get $r cursor] ne {}} {
                set owner [native2DGeometryDiagramRead [dict get $r document]]
                set start [_native2DDiagramTargetPoint [dict get $owner payload] [dict get $r start]]
                set points [list $start {*}[dict get $r route] [dict get $r cursor]]
                set ghost [dict get [native2DGeometryCall [dict get $projection scene_token] curve [dict create points $points]] object_token]
                native2DGeometryCall [dict get $projection scene_token] style [dict create object_token $ghost properties {color {0.85 0.4 0.05 1} line_width 2 marker 0}]
            }
            set snapshot [native2DPresentationSnapshot $native $options]
            set selectedIds {}
            foreach object [datasetPublicationV2DictDefault [dict get $projection object_tokens] [dict get $r selected] {}] {lappend selectedIds [_native2DGeometryObject $scene $object]}
            set objects {}
            foreach object [dict get $snapshot objects] {
                if {[dict get $object id] in $selectedIds} {dict set object style color {0.72 0.12 0.12 1};dict set object style line_width 3}
                lappend objects $object
            }
            dict set snapshot objects $objects
            native2DCanvasSnapshot $w.canvas $snapshot
            set bounds {}
            foreach id $selectedIds {
                set box [$w.canvas bbox object_$id]
                if {$box eq {}} continue
                if {$bounds eq {}} {set bounds $box} else {
                    lassign $bounds a b c d;lassign $box x y z t
                    set bounds [list [expr {min($a,$x)}] [expr {min($b,$y)}] [expr {max($c,$z)}] [expr {max($d,$t)}]]
                }
            }
            if {$bounds ne {}} {
                lassign $bounds a b c d
                $w.canvas create rectangle [expr {$a-5}] [expr {$b-5}] [expr {$c+5}] [expr {$d+5}] -outline #a72828 -dash {4 3} -width 1 -tags diagram_selection
            }
            if {[dict get $r tool] in {wire junction label probe}} {_native2DDiagramViewportPins $w $native $payload [datasetPublicationV2DictDefault $r hover_terminal {}]}
        } finally {
            if {$ghost ne {}} {catch {native2DGeometryCall [dict get $projection scene_token] delete [dict create object_token $ghost]}}
            if {$transient ne {}} {native2DGeometryClose [dict get $transient scene_token]}
        }
        set hint [expr {[dict get $r start] ne {} ? {Click grid for bends; finish on pin, junction or wire; Backspace removes bend; Esc cancels} : {Esc select · W wire · R rotate · Del delete · Double-click properties}}]
        if {[dict get $r last_notice] ne {}} {set hint [dict get $r last_notice]}
        $w.status configure -wraplength [expr {max(200,[winfo width $w.canvas])}] -text "[dict get $r document] · Tool: [dict get $r tool] · Selected: [dict get $r selected] · $hint"
    } reason]} {$w.status configure -text "Diagram unavailable: $reason"}
}
proc ::GX::_native2DDiagramViewportEmit {w event detail} {
    set r [_native2DDiagramViewportRecord $w]
    if {[dict get $r callback] ne {}} {{*}[dict get $r callback] $w [dict create event $event detail $detail document [dict remove [native2DGeometryDiagramRead [dict get $r document]] payload]]}
}
proc ::GX::native2DGeometryDiagramViewportEdit {w operation request} {
    # Reject malformed/semantically invalid candidates before asking History
    # to discard a redo tail. The ordinary commit below repeats source and
    # candidate validation after any native confirmation/Session transition.
    set r [_native2DDiagramViewportRecord $w]
    set candidate [native2DGeometryDiagramEdit [dict get $r document] [dict get $r projection document] $operation $request preview]
    set owner [native2DGeometryDiagramRead [dict get $r document]]
    if {[dict get $candidate proposed_payload] eq [dict get $owner payload]} {
        # An unchanged action must not prepare a History branch, discard its
        # redo tail or publish an edit notification. Keep the normal receipt.
        return [dict create document [dict remove $owner payload] object_id [dict get $candidate object_id] operation $operation payload [dict get $owner payload]]
    }
    # The owning Viewer can prepare its existing History transaction before
    # any canonical mutation. A cancelled branch must leave source untouched.
    _native2DDiagramViewportEmit $w before_edit [dict create operation $operation]
    set r [_native2DDiagramViewportRecord $w]
    set expected [dict get $r projection document]
    set receipt [native2DGeometryDiagramEdit [dict get $r document] $expected $operation $request]
    _native2DDiagramViewportProject $w
    _native2DDiagramViewportEmit $w committed [dict create operation $operation object_id [dict get $receipt object_id]]
    return $receipt
}
proc ::GX::native2DGeometryDiagramViewportCommand {w operation args} {
    set r [_native2DDiagramViewportRecord $w]
    dict set ::GX::Native2DDiagram::viewports $w last_notice {}
    set token [dict get $r projection scene_token]
    try {
    switch $operation {
        tool {
            set tool [lindex $args 0]
            set owner [native2DGeometryDiagramRead [dict get $r document]]
            set symbols [dict get [native2DGeometryDiagramCatalog [dict get $owner payload catalog]] symbols]
            if {$tool ni {select wire junction label pan probe} && ![dict exists $symbols $tool]} {error {Unsupported diagram tool or symbol}}
            dict set ::GX::Native2DDiagram::viewports $w tool $tool
            dict set ::GX::Native2DDiagram::viewports $w start {}
            dict set ::GX::Native2DDiagram::viewports $w route {}
            dict set ::GX::Native2DDiagram::viewports $w cursor {}
            dict set ::GX::Native2DDiagram::viewports $w hover_terminal {}
            dict set ::GX::Native2DDiagram::viewports $w drag {}
            _native2DDiagramViewportEmit $w tool_changed [dict create tool $tool]
        }
        fit {if {[dict size [dict get $r projection object_tokens]]} {_native2DDiagramFit $w}}
        zoom {lassign $args factor x y;uiFieldNormalize {type number min 0.1 max 10} $factor;native2DGeometryCall $token zoom [dict create factor $factor point [list $x $y]]}
        delete {if {[dict get $r selected] ne {}} {native2DGeometryDiagramViewportEdit $w remove [dict create id [dict get $r selected]];dict set ::GX::Native2DDiagram::viewports $w selected {}}}
        rotate {
            set owner [native2DGeometryDiagramRead [dict get $r document]];set id [dict get $r selected]
            if {[dict exists $owner payload components $id]} {set angle [dict get $owner payload components $id rotation];native2DGeometryDiagramViewportEdit $w transform [dict create id $id rotation [expr {($angle+90)%360}]]}
        }
        properties {if {[dict get $r selected] ne {}} {_native2DDiagramViewportProperties $w [dict get $r selected]}}
        wire_back {if {[dict get $r tool] eq {wire}} {dict set ::GX::Native2DDiagram::viewports $w route [lrange [dict get $r route] 0 end-1]}}
        default {error {Unsupported diagram viewport command}}
    }
    } trap {GX HISTORY EDIT_CANCELLED} {message options} {
        # Expected native confirmation cancellation unwinds before any mutation
        # or command-local selection cleanup. It is not a Tk background error.
        _native2DDiagramViewportSchedule $w
        return [dict create status cancelled operation $operation reason $message]
    }
    _native2DDiagramViewportSchedule $w
    return [dict create status accepted operation $operation]
}
proc ::GX::_native2DDiagramViewportPoint {w x y} {
    set r [_native2DDiagramViewportRecord $w]
    set native [dict get [_native2DGeometryRequire [dict get $r projection scene_token]] native]
    return [::GX::Native2D::core grid_snap $native [::GX::Native2D::core world $native [list $x $y]] 3]
}
proc ::GX::native2DGeometryDiagramViewportHitTest {w x y} {
    set r [_native2DDiagramViewportRecord $w]
    set owner [native2DGeometryDiagramRead [dict get $r document]];set payload [dict get $owner payload]
    set token [dict get $r projection scene_token];set best {};set distance 101
    set endpoints {}
    dict for {id item} [dict get $payload components] {dict for {pin point} [dict get [native2DGeometryDiagramCatalog [dict get $payload catalog]] symbols [dict get $item kind] pins] {lappend endpoints [list $id $pin]}}
    lappend endpoints {*}[dict keys [dict get $payload junctions]]
    foreach endpoint $endpoints {
        lassign [dict get [native2DGeometryCall $token world_to_device [dict create point [native2DGeometryDiagramEndpoint $payload $endpoint]]] point] px py
        set d [expr {($x-$px)*($x-$px)+($y-$py)*($y-$py)}]
        if {$d<$distance} {set distance $d;set best $endpoint}
    }
    if {$best ne {}} {return [dict create kind terminal endpoint $best point [native2DGeometryDiagramEndpoint $payload $best]]}
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    set query [::GX::Native2D::core world $native [list $x $y]]
    set scope {};set owners {}
    dict for {id wire} [dict get $payload wires] {
        foreach object [dict get $r projection object_tokens $id] {lappend scope $object;dict set owners $object $id}
    }
    if {![llength $scope]} {return {}}
    set picked [native2DGeometryCall $token selection_pick [dict create object_tokens $scope device [list $x $y] tolerance 10 target object]]
    if {![dict get $picked hit]} {return {}}
    set object [dict get $picked member object_token]
    set hit [::GX::Native2D::core nearest_segment $native [_native2DGeometryObject $scene $object] $query]
    # Snap along the selected wire using the same native grid and projection.
    # Never connect another coincident/crossing wire merely by its coordinates.
    set snapped [::GX::Native2D::core grid_snap $native $query 3]
    set candidate [::GX::Native2D::core nearest_segment $native [_native2DGeometryObject $scene $object] $snapped]
    lassign [::GX::Native2D::core device $native [dict get $candidate point]] px py
    if {($x-$px)*($x-$px)+($y-$py)*($y-$py)<=101} {set hit $candidate}
    return [dict create kind wire wire_id [dict get $owners $object] point [dict get $hit point]]
}
proc ::GX::_native2DDiagramViewportTerminal {w x y} {
    set hit [native2DGeometryDiagramViewportHitTest $w $x $y]
    if {$hit eq {}} {return {}}
    if {[dict get $hit kind] eq {terminal}} {return [dict get $hit endpoint]}
    return $hit
}
proc ::GX::_native2DDiagramViewportJunctionTargets {w x y} {
    set hit [native2DGeometryDiagramViewportHitTest $w $x $y]
    if {$hit eq {}} {return {}}
    set r [_native2DDiagramViewportRecord $w];set scene [_native2DGeometryRequire [dict get $r projection scene_token]]
    set native [dict get $scene native];set point [dict get $hit point];set targets {}
    if {[dict get $hit kind] eq {terminal}} {lappend targets [dict get $hit endpoint]}
    set payload [dict get [native2DGeometryDiagramRead [dict get $r document]] payload]
    dict for {id wire} [dict get $payload wires] {
        set object [lindex [dict get $r projection object_tokens $id] 0]
        set nearest [::GX::Native2D::core nearest_segment $native [_native2DGeometryObject $scene $object] $point]
        if {[dict get $nearest distance]<=1e-7} {lappend targets [dict create kind wire wire_id $id point $point]}
    }
    return $targets
}
proc ::GX::_native2DDiagramViewportPins {w native payload hover} {
    set endpoints {}
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    dict for {id item} [dict get $payload components] {foreach pin [dict keys [dict get $catalog symbols [dict get $item kind] pins]] {lappend endpoints [list $id $pin]}}
    lappend endpoints {*}[dict keys [dict get $payload junctions]]
    lassign [::GX::Native2D::core view $native] width height left top right bottom
    foreach endpoint $endpoints {
        lassign [::GX::Native2D::core device $native [native2DGeometryDiagramEndpoint $payload $endpoint]] x y
        if {$x<$left || $x>$width-$right || $y<$top || $y>$height-$bottom} continue
        set active [expr {$endpoint eq $hover}];set radius [expr {$active?6:3}]
        $w.canvas create oval [expr {$x-$radius}] [expr {$y-$radius}] [expr {$x+$radius}] [expr {$y+$radius}] -outline [expr {$active?{#a65b00}:{#195c45}}] -fill [expr {$active?{#ffe39b}:{#ffffff}}] -width [expr {$active?2:1}] -tags diagram_terminal
        if {$active} {$w.canvas create line [expr {$x-9}] $y [expr {$x+9}] $y -fill #a65b00 -tags diagram_terminal;$w.canvas create line $x [expr {$y-9}] $x [expr {$y+9}] -fill #a65b00 -tags diagram_terminal}
    }
    if {[_native2DDiagramIsWireTarget $hover]} {
        lassign [::GX::Native2D::core device $native [dict get $hover point]] x y
        $w.canvas create oval [expr {$x-6}] [expr {$y-6}] [expr {$x+6}] [expr {$y+6}] -outline #a65b00 -fill #ffe39b -width 2 -tags diagram_terminal
        $w.canvas create line [expr {$x-10}] $y [expr {$x+10}] $y -fill #a65b00 -tags diagram_terminal
        $w.canvas create line $x [expr {$y-10}] $x [expr {$y+10}] -fill #a65b00 -tags diagram_terminal
    }
}
proc ::GX::_native2DDiagramViewportPress {w x y} {
    focus $w.canvas
    dict set ::GX::Native2DDiagram::viewports $w last_notice {}
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set tool [dict get $r tool];set point [_native2DDiagramViewportPoint $w $x $y]
        set owner [native2DGeometryDiagramRead [dict get $r document]]
        if {$tool eq {pan}} {dict set ::GX::Native2DDiagram::viewports $w drag [dict create kind pan device [list $x $y]]
        } elseif {$tool eq {junction}} {
            set targets [_native2DDiagramViewportJunctionTargets $w $x $y]
            if {[llength $targets]>1 || ([llength $targets]==1 && [_native2DDiagramIsWireTarget [lindex $targets 0]])} {native2DGeometryDiagramViewportEdit $w junction [dict create targets $targets]
            } elseif {$targets eq {}} {native2DGeometryDiagramViewportEdit $w junction [dict create position $point]
            } else {dict set ::GX::Native2DDiagram::viewports $w selected [lindex [lindex $targets 0] 0]}
        } elseif {$tool in {wire label probe}} {
            set endpoint [_native2DDiagramViewportTerminal $w $x $y]
            if {$endpoint eq {}} {
                if {$tool eq {wire} && [dict get $r start] ne {}} {
                    if {[llength [dict get $r route]]>=64} {error {Wire route is limited to64 bends}}
                    dict lappend r route $point
                    dict set r cursor $point
                    dict set ::GX::Native2DDiagram::viewports $w $r
                    _native2DDiagramViewportSchedule $w
                    return
                }
                error {Select a component pin, explicit junction or wire segment; geometric crossings alone do not connect}
            }
            if {$tool eq {wire}} {
                if {[dict get $r start] eq {}} {dict set ::GX::Native2DDiagram::viewports $w start $endpoint
                } else {native2DGeometryDiagramViewportEdit $w wire [dict create start [dict get $r start] end $endpoint route [dict get $r route]];dict set ::GX::Native2DDiagram::viewports $w start {};dict set ::GX::Native2DDiagram::viewports $w route {};dict set ::GX::Native2DDiagram::viewports $w cursor {}}
            } elseif {$tool eq {probe}} {
                set detail [dict create endpoint $endpoint hit_kind terminal]
                if {[_native2DDiagramIsWireTarget $endpoint]} {
                    set wireId [dict get $endpoint wire_id]
                    set detail [dict create endpoint [dict get $owner payload wires $wireId start] hit_kind wire wire_id $wireId point [dict get $endpoint point]]
                }
                _native2DDiagramViewportEmit $w probe $detail
            } else {_native2DDiagramViewportLabel $w $endpoint}
        } elseif {$tool ne {select}} {native2DGeometryDiagramViewportEdit $w place [dict create kind $tool position $point]
        } else {
            set selected {};set scope {};set owners {}
            set annotationHit [native2DAnnotationHit $w.canvas $x $y]
            if {[dict get $annotationHit hit]} {set selected [dict get $annotationHit annotation_id]}
            # The kernel resolves exact equal-distance ties in caller scope
            # order. Explicit junction dots precede coincident wire endpoints;
            # all candidates still use the same owned geometric picker.
            set scoped {}
            foreach id [concat [dict keys [dict get $owner payload junctions]] [dict keys [dict get $r projection object_tokens]]] {
                if {[dict exists $scoped $id]} continue
                dict set scoped $id 1
                set tokens [dict get $r projection object_tokens $id]
                foreach token $tokens {lappend scope $token;dict set owners $token $id}
            }
            # Diagram selection addresses visible symbol/wire strokes. Exact
            # vertex picking is reserved for pin endpoints, not whole objects.
            if {$selected eq {} && [llength $scope]} {
                set hit [native2DGeometryCall [dict get $r projection scene_token] selection_pick [dict create object_tokens $scope device [list $x $y] tolerance 12 target object]]
                if {[dict get $hit hit]} {set selected [dict get $owners [dict get $hit member object_token]]}
            }
            dict set ::GX::Native2DDiagram::viewports $w selected $selected
            if {[dict exists $owner payload components $selected]} {dict set ::GX::Native2DDiagram::viewports $w drag [dict create kind move selected $selected start $point position [dict get $owner payload components $selected position]]}
            if {[dict exists $owner payload labels $selected]} {dict set ::GX::Native2DDiagram::viewports $w drag [dict create kind label selected $selected start $point offset [datasetPublicationV2DictDefault [dict get $owner payload labels $selected] offset {0 0}]]}
            _native2DDiagramViewportEmit $w selection [dict create object_id $selected]
        }
    } reason]==1} {_native2DDiagramViewportNotice $w $reason;return}
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportCursor {w x y} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w]
        if {[dict get $r tool] in {wire junction label probe}} {
            set endpoint [_native2DDiagramViewportTerminal $w $x $y]
            dict set ::GX::Native2DDiagram::viewports $w hover_terminal $endpoint
            if {[dict get $r tool] eq {wire} && [dict get $r start] ne {}} {
                set point [_native2DDiagramViewportPoint $w $x $y]
                if {$endpoint ne {}} {set point [_native2DDiagramTargetPoint [dict get [native2DGeometryDiagramRead [dict get $r document]] payload] $endpoint]}
                dict set ::GX::Native2DDiagram::viewports $w cursor $point
            }
            _native2DDiagramViewportSchedule $w
        }
    }]} return
}
proc ::GX::_native2DDiagramViewportMotion {w x y} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set drag [dict get $r drag]
        if {$drag eq {}} return
        if {[dict get $drag kind] eq {pan}} {
            lassign [dict get $drag device] px py
            native2DGeometryCall [dict get $r projection scene_token] pan [dict create delta [list [expr {$x-$px}] [expr {$y-$py}]]]
            dict set ::GX::Native2DDiagram::viewports $w drag device [list $x $y]
            _native2DDiagramViewportSchedule $w
        } elseif {[dict get $drag kind] in {move label}} {
            lassign [dict get $drag start] sx sy;lassign [_native2DDiagramViewportPoint $w $x $y] ex ey
            if {[dict get $drag kind] eq {move}} {set field position} else {set field offset}
            lassign [dict get $drag $field] px py
            dict set drag request [dict create id [dict get $drag selected] $field [list [expr {$px+$ex-$sx}] [expr {$py+$ey-$sy}]]]
            dict set ::GX::Native2DDiagram::viewports $w drag $drag
            _native2DDiagramViewportSchedule $w
        }
    } reason]==1} {_native2DDiagramViewportNotice $w $reason}
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportRelease {w x y} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set drag [dict get $r drag]
        dict set ::GX::Native2DDiagram::viewports $w drag {}
        if {$drag eq {}} return
        if {[dict get $drag kind] eq {move}} {
            lassign [dict get $drag position] px py;lassign [dict get $drag start] sx sy;lassign [_native2DDiagramViewportPoint $w $x $y] ex ey
            set position [list [expr {$px+$ex-$sx}] [expr {$py+$ey-$sy}]]
            if {$ex!=$sx || $ey!=$sy} {native2DGeometryDiagramViewportEdit $w transform [dict create id [dict get $drag selected] position $position]}
        } elseif {[dict get $drag kind] eq {label}} {
            lassign [dict get $drag offset] dx dy;lassign [dict get $drag start] sx sy;lassign [_native2DDiagramViewportPoint $w $x $y] ex ey
            set offset [list [expr {$dx+$ex-$sx}] [expr {$dy+$ey-$sy}]]
            if {$ex!=$sx || $ey!=$sy} {native2DGeometryDiagramViewportEdit $w label [dict create id [dict get $drag selected] offset $offset]}
        } else {_native2DDiagramViewportEmit $w view_changed [native2DGeometryCall [dict get $r projection scene_token] view_state {}]}
    } reason]==1} {_native2DDiagramViewportNotice $w $reason}
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportProperties {w id} {
    set r [_native2DDiagramViewportRecord $w];set owner [native2DGeometryDiagramRead [dict get $r document]]
    if {[winfo exists $w.properties]} {raise $w.properties;return}
    if {[dict exists $owner payload wires $id]} {return [_native2DDiagramWireProperties $w $id $owner]}
    set ::GX::Native2DDiagram::field($w,properties_kind) symbol_or_label
    set ::GX::Native2DDiagram::field($w,properties_source) [dict remove $owner payload]
    set ::GX::Native2DDiagram::field($w,properties_fields) $w.properties.fields
    if {[dict exists $owner payload labels $id]} {
        set item [dict get $owner payload labels $id]
        lassign [datasetPublicationV2DictDefault $item offset {0 0}] dx dy
        set fields [dict create name {type string default {} label {Net name}} offset_x {type number default 0 label {Display offset X}} offset_y {type number default 0 label {Display offset Y}}]
        set values [dict create name [dict get $item text] offset_x $dx offset_y $dy]
        set title "[dict get $item text] · Net label properties"
    } elseif {[dict exists $owner payload components $id]} {
        set item [dict get $owner payload components $id]
        set symbol [dict get [native2DGeometryDiagramCatalog [dict get $owner payload catalog]] symbols [dict get $item kind]]
        set fields [dict merge [dict create name {type string default {} label Name}] [dict get $symbol attributes]]
        set values [dict merge [dict get $item attributes] [dict create name [dict get $item name]]]
        set title "[dict get $item name] · Symbol properties"
    } else {error {Select a symbol or net label to edit properties}}
    set d $w.properties
    if {[winfo exists $d]} {raise $d;return}
    toplevel $d;wm title $d $title;wm transient $d [winfo toplevel $w]
    ttk::frame $d.fields -padding 12;pack $d.fields -fill both -expand 1
    set row 0
    dict for {key field} $fields {
        set ::GX::Native2DDiagram::field($w,$key) [dict get $values $key]
        if {[datasetPublicationV2DictDefault $field notation {}] eq {electrical_engineering}} {
            set ::GX::Native2DDiagram::field($w,$key) [_native2DDiagramElectricalDisplay [dict get $values $key]]
            # Electrical suffix parsing belongs to the catalog attribute owner,
            # not generic Numeric fields or a Viewer-specific parser.
            dict set field type string
            dict set field default [_native2DDiagramElectricalDisplay [dict get $field default]]
            foreach bound {min max notation} {if {[dict exists $field $bound]} {dict unset field $bound}}
        }
        set label [datasetPublicationV2DictDefault $field label $key]
        if {[dict exists $field unit]} {append label " ([dict get $field unit])"}
        ttk::label $d.fields.l$key -text $label
        if {[dict get $field type] eq {choice}} {dict set field values [dict get $field values]}
        uiFieldCreate $d.fields.f$key [dict merge $field [dict create label {}]] ::GX::Native2DDiagram::field($w,$key)
        grid $d.fields.l$key -row $row -column 0 -sticky e -padx 5 -pady 4
        grid $d.fields.f$key -row $row -column 1 -sticky ew -padx 5 -pady 4
        incr row
    }
    grid columnconfigure $d.fields 1 -weight 1
    ttk::label $d.error -wraplength 440;pack $d.error -fill x -padx 12
    bind $d.error <Configure> +[list ::GX::_uiFieldComponentTextWrap $d.error 440 %W %w]
    bind $d.error <Configure> +[list ::GX::_native2DDiagramPropertiesMinimum $d]
    ttk::frame $d.buttons;pack $d.buttons -fill x -padx 12 -pady 8
    ttk::button $d.buttons.apply -text Apply -command [list ::GX::_native2DDiagramViewportPropertiesApply $w $id $fields]
    ttk::button $d.buttons.close -text Close -command [list destroy $d]
    pack $d.buttons.apply $d.buttons.close -side left -padx 4
}
proc ::GX::_native2DDiagramPropertiesMinimum {d} {
    if {![winfo exists $d.buttons]} return
    # Wrapped diagnostics can increase the form's natural height after opening.
    # Keep every field and normal action visible instead of clipping the last
    # packed row inside the previously allocated window.
    wm minsize $d [winfo reqwidth $d.fields] [winfo reqheight $d]
}
proc ::GX::_native2DDiagramViewportPropertiesApply {w id fields} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set owner [native2DGeometryDiagramRead [dict get $r document]]
        # The nonmodal form is a draft of the revision shown when opened.
        # Reject stale drafts before validation or History branch preparation.
        foreach key {id generation revision sha256} {
            if {[dict get $owner $key] ne [dict get $::GX::Native2DDiagram::field($w,properties_source) $key]} {
                return -code error -errorcode {GX NATIVE2D STALE_SOURCE} {Diagram changed while Properties was open; close and reopen the editor}
            }
        }
        if {[dict exists $owner payload labels $id]} {
            set offset {};foreach key {offset_x offset_y} {lappend offset [uiFieldNormalize [dict get $fields $key] $::GX::Native2DDiagram::field($w,$key)]}
            native2DGeometryDiagramViewportEdit $w label [dict create id $id text $::GX::Native2DDiagram::field($w,name) offset $offset]
        } else {
            set attributes {}
            dict for {key field} $fields {if {$key ne {name}} {dict set attributes $key [_native2DDiagramAttributeNormalize $field $::GX::Native2DDiagram::field($w,$key)]}}
            native2DGeometryDiagramViewportEdit $w properties [dict create id $id name $::GX::Native2DDiagram::field($w,name) attributes $attributes]
        }
        set ::GX::Native2DDiagram::field($w,properties_source) [dict remove [native2DGeometryDiagramRead [dict get $r document]] payload]
    } reason]} {if {[winfo exists $w.properties.error]} {$w.properties.error configure -text $reason};return}
    if {[winfo exists $w.properties.error]} {$w.properties.error configure -text {Properties committed to the canonical document.}}
}
proc ::GX::_native2DDiagramViewportLabel {w endpoint} {
    set d $w.netlabel
    if {[winfo exists $d]} {destroy $d}
    toplevel $d;wm title $d {Explicit net label};wm transient $d [winfo toplevel $w]
    ttk::label $d.caption -text {Net name (letters, digits and underscore)}
    ttk::entry $d.value
    ttk::button $d.apply -text Apply -command [list ::GX::_native2DDiagramViewportLabelApply $w $endpoint]
    ttk::button $d.cancel -text Cancel -command [list destroy $d]
    ttk::label $d.status -wraplength 400
    pack $d.caption $d.value $d.apply $d.cancel $d.status -padx 12 -pady 6 -fill x
    focus $d.value
}
proc ::GX::_native2DDiagramViewportLabelApply {w endpoint} {
    if {[catch {native2DGeometryDiagramViewportEdit $w label [dict create endpoint $endpoint text [$w.netlabel.value get]]} reason]} {$w.netlabel.status configure -text $reason;return}
    destroy $w.netlabel
}
proc ::GX::_native2DDiagramFit {w} {
    set projection [dict get $::GX::Native2DDiagram::viewports $w projection]
    set token [dict get $projection scene_token]
    lassign [dict get [native2DGeometryCall $token scene_bounds {}] bounds] x0 y0 x1 y1
    set annotations [dict get $projection annotations]
    # Scientific geometry stays untouched. Fit includes presentation anchors
    # and the same actual pixel-font extents used by the shared snapshot painter.
    foreach annotation $annotations {
        lassign [dict get $annotation point] x y
        set x0 [expr {min($x0,$x)}];set y0 [expr {min($y0,$y)}]
        set x1 [expr {max($x1,$x)}];set y1 [expr {max($y1,$y)}]
    }
    native2DGeometryCall $token fit_bounds [dict create bounds [list $x0 $y0 $x1 $y1]]
    set font {Sans -13}
    for {set pass 0} {$pass<2} {incr pass} {
        foreach annotation $annotations {
            lassign [dict get [native2DGeometryCall $token world_to_device [dict create point [dict get $annotation point]]] point] x y
            set width [expr {[font measure $font [dict get $annotation text]]+4}]
            set height [expr {[font metrics $font -linespace]+4}]
            set anchor [datasetPublicationV2DictDefault $annotation anchor sw]
            set left [expr {$x-$width*($anchor in {e ne se}?1.0:($anchor in {w nw sw}?0.0:0.5))}]
            set top [expr {$y-$height*($anchor in {s se sw}?1.0:($anchor in {n ne nw}?0.0:0.5))}]
            foreach device [list [list $left $top] [list [expr {$left+$width}] [expr {$top+$height}]]] {
                lassign [dict get [native2DGeometryCall $token device_to_world [dict create point $device]] point] wx wy
                set x0 [expr {min($x0,$wx)}];set y0 [expr {min($y0,$wy)}]
                set x1 [expr {max($x1,$wx)}];set y1 [expr {max($y1,$wy)}]
            }
        }
        native2DGeometryCall $token fit_bounds [dict create bounds [list $x0 $y0 $x1 $y1]]
    }
    return [dict create bounds [list $x0 $y0 $x1 $y1] annotations [llength $annotations] font $font]
}
proc ::GX::_native2DDiagramViewportDispose {w actual} {
    if {$actual ne $w || ![dict exists $::GX::Native2DDiagram::viewports $w]} return
    set r [dict get $::GX::Native2DDiagram::viewports $w]
    if {[dict get $r pending] ne {}} {after cancel [dict get $r pending]}
    if {[dict get $r projection] ne {}} {catch {native2DGeometryClose [dict get $r projection scene_token]}}
    dict unset ::GX::Native2DDiagram::viewports $w
    array unset ::GX::Native2DDiagram::field $w,*
}
