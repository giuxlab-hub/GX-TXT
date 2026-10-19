# SPDX-License-Identifier: GPL-3.0-or-later
# Typed drafts in the existing Native2D Properties owner; Document owns commits.
proc ::GX::_native2DDiagramWireEndpoints {payload} {
    set result {}
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    dict for {id item} [dict get $payload components] {
        dict for {pin point} [dict get $catalog symbols [dict get $item kind] pins] {
            dict set result "[dict get $item name].$pin ($id)" [list $id $pin]
        }
    }
    dict for {id point} [dict get $payload junctions] {dict set result "Junction ($id)" $id}
    return $result
}
proc ::GX::_native2DDiagramWireProperties {w id owner} {
    set d $w.properties;set wire [dict get $owner payload wires $id]
    set endpoints [_native2DDiagramWireEndpoints [dict get $owner payload]]
    foreach side {start end} {
        set found 0
        dict for {label endpoint} $endpoints {
            if {$endpoint eq [dict get $wire $side]} {set ::GX::Native2DDiagram::field($w,$side) $label;set found 1;break}
        }
        if {!$found} {error {Wire endpoint is absent from the canonical diagram}}
    }
    set ::GX::Native2DDiagram::field($w,properties_kind) wire
    set ::GX::Native2DDiagram::field($w,wire_id) $id
    set ::GX::Native2DDiagram::field($w,wire_endpoints) $endpoints
    set ::GX::Native2DDiagram::field($w,wire_route) [dict get $wire route]
    set ::GX::Native2DDiagram::field($w,wire_source) [dict remove $owner payload]
    toplevel $d;wm title $d "$id · Wire properties";wm transient $d [winfo toplevel $w]
    wm geometry $d 600x520;wm minsize $d 480 320
    ttk::frame $d.buttons;pack $d.buttons -side bottom -fill x -padx 12 -pady 8
    ttk::button $d.buttons.apply -text Apply -command [list ::GX::_native2DDiagramWireApply $w]
    ttk::button $d.buttons.close -text Close -command [list destroy $d]
    pack $d.buttons.apply $d.buttons.close -side left -padx 4
    ttk::label $d.error -wraplength 440;pack $d.error -side bottom -fill x -padx 12
    set content [uiFieldScrollableCreate $d.body 560];pack $d.body -fill both -expand 1
    set fields $content.fields;ttk::frame $fields -padding 8;pack $fields -fill x
    set ::GX::Native2DDiagram::field($w,properties_fields) $fields
    grid columnconfigure $fields 1 -weight 1
    set row 0
    foreach side {start end} {
        ttk::label $fields.l$side -text "[string totitle $side] terminal"
        uiFieldCreate $fields.f$side [dict create type choice values [dict keys $endpoints] label {}] ::GX::Native2DDiagram::field($w,$side)
        grid $fields.l$side -row $row -column 0 -sticky w -padx 4 -pady 4
        grid $fields.f$side -row $row -column 1 -sticky ew -padx 4 -pady 4
        incr row
    }
    ttk::label $fields.caption -text {Ordered bend points (display coordinates; up to128). Empty means a direct wire. Draft changes reach the Document only on Apply.} -wraplength 440
    grid $fields.caption -row 2 -column 0 -columnspan 2 -sticky ew -pady 6
    ttk::frame $fields.points
    ttk::treeview $fields.points.tree -columns {order x y} -show headings -height 6 -selectmode browse
    foreach {key title width} {order Bend 65 x X 150 y Y 150} {$fields.points.tree heading $key -text $title;$fields.points.tree column $key -width $width -stretch 1}
    ttk::scrollbar $fields.points.bar -command [list $fields.points.tree yview];$fields.points.tree configure -yscrollcommand [list $fields.points.bar set]
    pack $fields.points.bar -side right -fill y;pack $fields.points.tree -fill both -expand 1
    grid $fields.points -row 3 -column 0 -columnspan 2 -sticky ew -pady 4
    bind $fields.points.tree <<TreeviewSelect>> [list ::GX::_native2DDiagramWireSelect $w]
    foreach {key title row} {point_x {Bend X} 4 point_y {Bend Y} 5} {
        set ::GX::Native2DDiagram::field($w,$key) 0
        ttk::label $fields.l$key -text $title
        uiFieldCreate $fields.f$key {type number min -1000000 max 1000000 label {}} ::GX::Native2DDiagram::field($w,$key)
        grid $fields.l$key -row $row -column 0 -sticky w -padx 4 -pady 4
        grid $fields.f$key -row $row -column 1 -sticky ew -padx 4 -pady 4
    }
    ttk::frame $fields.actions;grid $fields.actions -row 6 -column 0 -columnspan 2 -sticky ew -pady 6
    foreach {operation title} {add {Add bend} replace Replace remove Remove up {Move up} down {Move down}} {
        ttk::button $fields.actions.$operation -text $title -command [list ::GX::_native2DDiagramWireRouteEdit $w $operation]
        uiFieldControlsAppend $fields.actions $fields.actions.$operation
    }
    bind $fields.actions <Configure> [list ::GX::uiFieldControlsLayout $fields.actions %w]
    _native2DDiagramWireRefresh $w
    return $d
}
proc ::GX::_native2DDiagramWireTree {w} {return $::GX::Native2DDiagram::field($w,properties_fields).points.tree}
proc ::GX::_native2DDiagramWireSelect {w} {
    if {![winfo exists $w.properties]} return
    set tree [_native2DDiagramWireTree $w];set selected [$tree selection]
    if {[llength $selected]} {
        set index [lsearch -exact [$tree children {}] [lindex $selected 0]]
        lassign [lindex $::GX::Native2DDiagram::field($w,wire_route) $index] x y
        set ::GX::Native2DDiagram::field($w,point_x) $x;set ::GX::Native2DDiagram::field($w,point_y) $y
    }
    set actions $::GX::Native2DDiagram::field($w,properties_fields).actions
    set count [llength [$tree children {}]];set index [lsearch -exact [$tree children {}] [lindex $selected 0]]
    foreach operation {replace remove up down} {
        set enabled [expr {$index>=0 && ($operation ne {up} || $index>0) && ($operation ne {down} || $index<$count-1)}]
        $actions.$operation configure -state [expr {$enabled ? {normal} : {disabled}}]
    }
    $actions.add configure -state [expr {$count<128 ? {normal} : {disabled}}]
}
proc ::GX::_native2DDiagramWireRefresh {w {selected -1}} {
    set tree [_native2DDiagramWireTree $w]
    $tree delete [$tree children {}]
    set index 0
    foreach point $::GX::Native2DDiagram::field($w,wire_route) {
        $tree insert {} end -id point_$index -values [list [expr {$index+1}] {*}$point]
        incr index
    }
    if {$selected>=0 && $selected<$index} {$tree selection set point_$selected;$tree see point_$selected}
    _native2DDiagramWireSelect $w
}
proc ::GX::_native2DDiagramWireRouteEdit {w operation} {
    if {[catch {
        set tree [_native2DDiagramWireTree $w];set selected [$tree selection]
        set route $::GX::Native2DDiagram::field($w,wire_route);set count [llength $route]
        set index [lsearch -exact [$tree children {}] [lindex $selected 0]]
        if {$operation ne {add} && $index<0} {error {Select a bend point first}}
        switch $operation {
            add - replace {
                set point {}
                foreach key {point_x point_y} {lappend point [uiFieldNormalize {type number min -1000000 max 1000000} $::GX::Native2DDiagram::field($w,$key)]}
                if {$operation eq {add}} {
                    if {$count>=128} {error {Wire route exceeds128 bends}}
                    set index [expr {$index<0 ? $count : $index+1}];set route [linsert $route $index $point]
                } else {lset route $index $point}
            }
            remove {set route [lreplace $route $index $index];set index [expr {min($index,[llength $route]-1)}]}
            up - down {
                set next [expr {$index+($operation eq {up} ? -1 : 1)}]
                if {$next<0 || $next>=$count} {error {Bend point is already at this boundary}}
                set other [lindex $route $next];lset route $next [lindex $route $index];lset route $index $other;set index $next
            }
            default {error {Unknown bend editor action}}
        }
        set ::GX::Native2DDiagram::field($w,wire_route) $route
        _native2DDiagramWireRefresh $w $index
    } message]} {$w.properties.error configure -text $message;return}
    $w.properties.error configure -text {Draft changed. Apply commits through the canonical Document and History.}
}
proc ::GX::_native2DDiagramWireApply {w} {
    if {[catch {
        set r [_native2DDiagramViewportRecord $w];set owner [native2DGeometryDiagramRead [dict get $r document]]
        foreach key {generation revision sha256} {if {[dict get $owner $key] ne [dict get $::GX::Native2DDiagram::field($w,wire_source) $key]} {error {Diagram changed while Wire properties was open; close and reopen the editor}}}
        set endpoints $::GX::Native2DDiagram::field($w,wire_endpoints)
        set request [dict create id $::GX::Native2DDiagram::field($w,wire_id) route $::GX::Native2DDiagram::field($w,wire_route)]
        foreach side {start end} {
            set value [uiFieldNormalize [dict create type choice values [dict keys $endpoints]] $::GX::Native2DDiagram::field($w,$side)]
            dict set request $side [dict get $endpoints $value]
        }
        native2DGeometryDiagramViewportEdit $w route $request
        set ::GX::Native2DDiagram::field($w,wire_source) [dict remove [native2DGeometryDiagramRead [dict get $r document]] payload]
    } message]} {if {[winfo exists $w.properties.error]} {$w.properties.error configure -text $message};return}
    if {[winfo exists $w.properties.error]} {$w.properties.error configure -text {Wire committed with the same stable ID.}}
}
