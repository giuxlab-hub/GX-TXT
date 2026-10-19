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
    dict set ::GX::Native2DDiagram::viewports $widget [dict create document $document session_token [interactiveDocumentSessionToken] callback $callback projection {} tool select selected {} start {} route {} cursor {} drag {} pending {}]
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
        set options [dict create point_budget 4096 legend 0 axes_visible 0 include_construction_reference 1 font_size 13 annotations [dict get $projection annotations]]
        set ghost {}
        try {
            if {[dict get $r start] ne {} && [dict get $r cursor] ne {}} {
                set owner [native2DGeometryDiagramRead [dict get $r document]]
                set start [native2DGeometryDiagramEndpoint [dict get $owner payload] [dict get $r start]]
                set points [list $start {*}[dict get $r route] [dict get $r cursor]]
                set ghost [dict get [native2DGeometryCall [dict get $projection scene_token] curve [dict create points $points]] object_token]
                native2DGeometryCall [dict get $projection scene_token] style [dict create object_token $ghost properties {color {0.85 0.4 0.05 1} line_width 2 marker 0}]
            }
            native2DCanvasSnapshot $w.canvas [native2DPresentationSnapshot $native $options]
        } finally {if {$ghost ne {}} {native2DGeometryCall [dict get $projection scene_token] delete [dict create object_token $ghost]}}
        set hint [expr {[dict get $r start] ne {} ? {Click grid for bends; finish on pin/junction; Backspace removes bend; Esc cancels} : {Esc select · W wire · R rotate · Del delete · Double-click properties}}]
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
    native2DGeometryDiagramEdit [dict get $r document] [dict get $r projection document] $operation $request preview
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
            dict set ::GX::Native2DDiagram::viewports $w drag {}
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
proc ::GX::_native2DDiagramViewportTerminal {w x y} {
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
    return $best
}
proc ::GX::_native2DDiagramViewportPress {w x y} {
    focus $w.canvas
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set tool [dict get $r tool];set point [_native2DDiagramViewportPoint $w $x $y]
        set owner [native2DGeometryDiagramRead [dict get $r document]]
        if {$tool eq {pan}} {dict set ::GX::Native2DDiagram::viewports $w drag [dict create kind pan device [list $x $y]]
        } elseif {$tool eq {junction}} {native2DGeometryDiagramViewportEdit $w junction [dict create position $point]
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
                error {Select an existing pin or explicit junction; geometric crossings do not connect}
            }
            if {$tool eq {wire}} {
                if {[dict get $r start] eq {}} {dict set ::GX::Native2DDiagram::viewports $w start $endpoint
                } else {native2DGeometryDiagramViewportEdit $w wire [dict create start [dict get $r start] end $endpoint route [dict get $r route]];dict set ::GX::Native2DDiagram::viewports $w start {};dict set ::GX::Native2DDiagram::viewports $w route {};dict set ::GX::Native2DDiagram::viewports $w cursor {}}
            } elseif {$tool eq {probe}} {_native2DDiagramViewportEmit $w probe [dict create endpoint $endpoint]
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
    } reason]==1} {$w.status configure -text $reason;return}
    _native2DDiagramViewportSchedule $w
}
proc ::GX::_native2DDiagramViewportCursor {w x y} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w]
        if {[dict get $r tool] eq {wire} && [dict get $r start] ne {}} {
            dict set ::GX::Native2DDiagram::viewports $w cursor [_native2DDiagramViewportPoint $w $x $y]
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
        }
    } reason]==1} {$w.status configure -text $reason}
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
    } reason]==1} {$w.status configure -text $reason}
}
proc ::GX::_native2DDiagramViewportProperties {w id} {
    set r [_native2DDiagramViewportRecord $w];set owner [native2DGeometryDiagramRead [dict get $r document]]
    if {[winfo exists $w.properties]} {raise $w.properties;return}
    if {[dict exists $owner payload wires $id]} {return [_native2DDiagramWireProperties $w $id $owner]}
    set ::GX::Native2DDiagram::field($w,properties_kind) symbol_or_label
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
    ttk::frame $d.buttons;pack $d.buttons -fill x -padx 12 -pady 8
    ttk::button $d.buttons.apply -text Apply -command [list ::GX::_native2DDiagramViewportPropertiesApply $w $id $fields]
    ttk::button $d.buttons.close -text Close -command [list destroy $d]
    pack $d.buttons.apply $d.buttons.close -side left -padx 4
}
proc ::GX::_native2DDiagramViewportPropertiesApply {w id fields} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set owner [native2DGeometryDiagramRead [dict get $r document]]
        if {[dict exists $owner payload labels $id]} {
            set offset {};foreach key {offset_x offset_y} {lappend offset [uiFieldNormalize [dict get $fields $key] $::GX::Native2DDiagram::field($w,$key)]}
            native2DGeometryDiagramViewportEdit $w label [dict create id $id text $::GX::Native2DDiagram::field($w,name) offset $offset]
        } else {
            set attributes {}
            dict for {key field} $fields {if {$key ne {name}} {dict set attributes $key [uiFieldNormalize $field $::GX::Native2DDiagram::field($w,$key)]}}
            native2DGeometryDiagramViewportEdit $w properties [dict create id $id name $::GX::Native2DDiagram::field($w,name) attributes $attributes]
        }
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
