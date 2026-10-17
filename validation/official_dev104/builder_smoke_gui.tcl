# SPDX-License-Identifier: GPL-3.0-or-later
# Source in the private actual Debian desktop console; all gestures are X11 input.
source validation/official_dev104/p0_workflow.tcl
proc bActivate {w} {
    wm deiconify $w
    update idletasks;p0pause 100
    set id [winfo id $w]
    if {$id eq {0x0}} {error {Native window is not mapped yet}}
    for {set n 0} {$n<6} {incr n} {
        if {![catch {exec xprop -id $id _NET_WM_DESKTOP} prop] && [string match {*CARDINAL*} $prop]} break
        set tree [exec xwininfo -id $id -tree]
        if {![regexp {Parent window id: (0x[0-9a-fA-F]+)} $tree -> id]} {error {Cannot find native window manager client}}
    }
    exec xdotool windowactivate $id
    p0pause 100
    focus -force $w;p0pause 150
}
proc bClick {w} {bActivate [winfo toplevel $w];p0click $w [expr {[winfo width $w]/2}] [expr {[winfo height $w]/2}]}
proc bTree {tree id} {
    bActivate [winfo toplevel $tree];$tree see $id;p0pause
    lassign [$tree bbox $id] x y width height
    if {$height<1} {error "Tree row not visible: $id"}
    p0click $tree [expr {$x+30}] [expr {$y+$height/2}]
    if {$id ni [$tree selection]} {error "Native row selection failed: $id"}
}
proc bButton {text} {
    foreach row [widgets .gxInterfaceDesigner.toolbar] {lassign $row path class label;if {$class eq {TButton} && $label eq $text} {bClick $path;return}}
    error "Missing toolbar action '$text'"
}
proc bChoose {combo value} {
    bClick $combo
    set panel [::GX::_uiFieldSelectorPanel $combo [winfo toplevel $combo]]
    if {![winfo exists $panel.options]} {error {Expected public selector popup}}
    set list $panel.options;set i [lsearch -exact [$list get 0 end] $value]
    if {$i<0} {error "Missing choice '$value'"}
    $list see $i;p0pause 60;lassign [$list bbox $i] x y width height
    p0click $list [expr {$x+20}] [expr {$y+$height/2}]
    if {[$combo get] ne $value} {error "Choice failed: $value"}
}
proc bType {entry value} {bClick $entry;exec xdotool key Home shift+End;exec xdotool type --clearmodifiers --delay 1 -- $value;p0pause 80}
proc bProperty {key value} {bChoose .gxInterfaceDesigner.body.right.properties.key $key;bType .gxInterfaceDesigner.body.right.properties.value $value;bClick .gxInterfaceDesigner.body.right.properties.apply}
proc bShot {w name} {bActivate $w;p0capture $w $name}
proc bSmoke {} {
    set ::GX::cfg(output_root) [file join $::out Sessions]
    if {$::GX::currentSession eq {}} {::GX::createNewSession builder_acceptance}
    ::GX::configurationSet storage.temp_dir [file join $::out temp]
    .top.nb select .top.nb.viewers
    bType .top.nb.viewers.tools.search {Interface Builder};p0pause 250
    set tile {}
    foreach group [winfo children .top.nb.viewers.viewport.content] {foreach button [winfo children $group] {if {[winfo class $button] eq {TButton} && [lrange [$button cget -command] end-1 end] eq {viewer.interface_builder interface_builder}} {set tile $button}}}
    if {$tile eq {}} {error {Missing standard Viewer catalog tile}}
    bActivate .;::GX::uiFieldScrollSee .top.nb.viewers.viewport .top.nb.viewers.viewport.content $tile;p0pause;bClick $tile;p0pause 400
    p0assert {[winfo exists .gxInterfaceDesigner] && [winfo exists .gxInterfacePreview]} builder_two_windows
    set palette .gxInterfaceDesigner.body.left.palette;set tree .gxInterfaceDesigner.body.left.tree
    bShot .gxInterfacePreview blank_preview
    bTree $tree inspector;bTree $palette section;bButton {Add component}
    set section $::GX::InterfaceBuilder::s(selected)
    bProperty property.title {Source settings}
    bTree $palette field;bButton {Add component}
    set field $::GX::InterfaceBuilder::s(selected)
    bProperty property.label {Sample label}
    bProperty property.default {Private fixture}
    set previewWidget [dict get $::GX::ViewerGui::instances .gxInterfacePreview widgets $field]
    p0assert {[set ::GX::ViewerGui::values(.gxInterfacePreview,$field)] eq {Private fixture}} field_default
    p0assert {[dict get [::GX::viewerGuiDesignComponent .gxInterfacePreview $field] parent] eq $section} nested_field
    set count [llength [dict get [::GX::InterfaceBuilder::design] components]]
    bButton Duplicate
    incr count
    p0assert {[llength [dict get [::GX::InterfaceBuilder::design] components]]==$count} duplicate_added
    bActivate .gxInterfaceDesigner;focus -force $tree;exec xdotool key ctrl+z;p0pause
    p0assert {[llength [dict get [::GX::InterfaceBuilder::design] components]]==$count-1} shortcut_undo
    exec xdotool key ctrl+y;p0pause
    p0assert {[llength [dict get [::GX::InterfaceBuilder::design] components]]==$count} shortcut_redo
    bTree $tree canvas;bTree $palette action;bButton {Add component}
    set action $::GX::InterfaceBuilder::s(selected)
    set actionId [dict get [::GX::viewerGuiDesignComponent .gxInterfacePreview $action] properties action]
    set widget [dict get $::GX::ViewerGui::instances .gxInterfacePreview widgets $action]
    set jobs [::GX::scriptJobList];bClick $widget
    set traces [dict get [::GX::viewerGuiRuntimeInspect .gxInterfacePreview] trace]
    set observed {};foreach event $traces {if {[dict get $event component] eq $actionId && [dict get $event event] eq {result}} {set observed [dict get $event detail status]}}
    p0assert {$observed eq {not_connected} && [::GX::scriptJobList] eq $jobs} safe_unbound_action
    set geometry [wm geometry .gxInterfacePreview]
    for {set n 0} {$n<4} {incr n} {bButton {Reopen Preview};p0pause 200}
    p0assert {[wm geometry .gxInterfacePreview] eq $geometry} repeated_preview_geometry
    wm geometry .gxInterfacePreview 700x480+20+70;p0pause 300;bShot .gxInterfacePreview compact_preview
    wm geometry .gxInterfacePreview 880x720+20+70;p0pause 300;bShot .gxInterfacePreview composed_preview
    bShot .gxInterfaceDesigner composed_designer
    record smoke_result [dict create status PASS design [::GX::InterfaceBuilder::design] inspection [::GX::viewerGuiRuntimeInspect .gxInterfacePreview] methods {X11 native pointer and keyboard; public APIs for assertions}]
}
if {![info exists ::bSkipSmoke] || !$::bSkipSmoke} {bSmoke}
