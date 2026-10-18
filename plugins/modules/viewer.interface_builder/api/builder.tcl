# SPDX-License-Identifier: GPL-3.0-or-later
# Editing client only. Public CORE composes Preview and generated Viewers.
namespace eval ::GX::InterfaceBuilder {variable s;variable serial 0}
proc ::GX::InterfaceBuilder::safe {method args} {
    variable s
    if {[catch {[namespace current]::$method {*}$args} result options]} {
        set s(status) $result
        if {[winfo exists .gxInterfaceDesigner.body.right.diagnostics.text]} {.gxInterfaceDesigner.body.right.diagnostics.text insert end "$result\n"}
        return [dict create status failed message $result]
    }
    return $result
}
proc ::GX::InterfaceBuilder::design {} {return [dict get $::GX::InterfaceBuilder::s(model) design]}
proc ::GX::InterfaceBuilder::dirty {} {variable s;return [expr {[dict get $s(model) design] ne [dict get $s(model) saved]}]}
proc ::GX::InterfaceBuilder::prepare {} {
    if {![dirty]} {return 1}
    set answer [tk_messageBox -parent .gxInterfaceDesigner -title {Viewer design changes} -type yesnocancel -default cancel -icon question -message {Save the Viewer design before continuing?}]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {save;if {[dirty]} {return 0}}
    return 1
}
proc ::GX::InterfaceBuilder::new {} {variable s;if {![prepare]} return;set s(previewMode) preview;set s(previewHandlers) {};set s(model) [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignNew]];set s(path) {};set s(selected) canvas;refresh}
proc ::GX::InterfaceBuilder::openFile {} {
    variable s;if {![prepare]} return
    set path [::GX::workspaceOpenFile manifest_dir -parent .gxInterfaceDesigner -title {Open Viewer design} -filetypes {{{GX-TXT Viewer design} {.gxtxt-viewer}} {{All files} *}}]
    if {$path eq {}} return
    set s(previewMode) preview;set s(previewHandlers) {};set s(model) [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignRead $path]];set s(path) $path;set s(selected) canvas;refresh
}
proc ::GX::InterfaceBuilder::save {{as 0}} {
    variable s
    set path $s(path)
    if {$as || $path eq {}} {set path [::GX::workspaceSaveFile manifest_dir -parent .gxInterfaceDesigner -title {Save Viewer design} -initialfile [dict get [design] provider_id].gxtxt-viewer -defaultextension .gxtxt-viewer -filetypes {{{GX-TXT Viewer design} {.gxtxt-viewer}}}]}
    if {$path eq {}} return
    ::GX::viewerGuiDesignSave $path [design];set s(path) $path;dict set s(model) saved [design];set s(status) "Saved [file tail $path]"
}
proc ::GX::InterfaceBuilder::apply {operation args} {variable s;set s(model) [::GX::viewerGuiDesignModelEdit $s(model) $operation {*}$args];refresh}
proc ::GX::InterfaceBuilder::navigate {direction} {variable s;set s(model) [::GX::viewerGuiDesignModelNavigate $s(model) $direction];refresh}
proc ::GX::InterfaceBuilder::add {} {
    variable s;variable serial
    set palette .gxInterfaceDesigner.body.left.palette
    set type [lindex [$palette selection] 0]
    set caps [::GX::viewerGuiComponentCapabilities]
    if {$type eq {} || ![dict exists $caps $type]} {error {Choose a CORE component from the palette.}}
    if {[dict get $caps $type status] ne {AVAILABLE}} {error [dict get $caps $type reason]}
    if {$type in {history workspace} && $::GX::currentSession eq {}} {error {Open a Session before placing its Workspace or History controls.}}
    set id ${type}_[incr serial];set parent $s(selected)
    if {$parent ni {toolbar inspector canvas footer menubar}} {
        set found 0;foreach item [dict get [design] components] {if {[dict get $item id] eq $parent && [dict get $item type] in {panel section splitter tabs tab}} {set found 1}}
        if {!$found} {set parent inspector}
    }
    set p {}
    switch $type {
        panel - section - tab {set p [dict create title [string totitle $type]]}
        splitter {set p {orientation horizontal}}
        label - status {set p [dict create text [string totitle $type]]}
        field {set p {label Value datatype string default {}}}
        entry {set p {default {}}}
        combobox {set p {choices {First Second} default First}}
        checkbutton {set p {label Toggle default 0}}
        list {set p {items {} height 6 selectmode browse}}
        action {set p [dict create label Action action action_$serial];if {$parent eq {canvas}} {set parent toolbar}}
        toggle {set p {label Toggle default 0}}
        choice {set p {label Choice choices {First Second} default First}}
        dataset_selector {set p {label Dataset}}
        native2d - plot {set p [dict create title {Scientific view}];set parent canvas}
        native3d {set p {title Native3D width 560 height 360 projection perspective axes_world 1 navigation_cube_visible 1 demo 1};set parent canvas}
        progress {set p {maximum 100}}
        log {set p {text {}};set parent footer}
        table {set p {columns {Name Value Unit}}}
        command_toolbar {set p {actions {}};set parent toolbar}
        context_menu {set p {actions {}};set parent canvas}
        menu {set p {label Menu actions {}};set parent menubar}
        help - workspace - history {set parent footer}
    }
    set row 0;set col 0
    foreach item [dict get [design] components] {
        if {[dict get $item parent] ne $parent || [dict get $item type] in {menu context_menu command_toolbar help workspace history}} continue
        set layout [dict get $item layout]
        set row [expr {max($row,[::GX::datasetPublicationV2DictDefault $layout row 0]+[::GX::datasetPublicationV2DictDefault $layout rowspan 1])}]
        set col [expr {max($col,[::GX::datasetPublicationV2DictDefault $layout column 0]+[::GX::datasetPublicationV2DictDefault $layout columnspan 1])}]
    }
    if {$parent eq {toolbar}} {set row 0} else {set col 0}
    set item [dict create id $id type $type parent $parent properties $p layout [dict create row $row column $col weight [expr {$parent eq {canvas} ? 1 : 0}] sticky nsew]]
    foreach sibling [dict get [design] components] {if {[dict get $sibling parent] eq $parent && [::GX::datasetPublicationV2DictDefault [dict get $sibling layout] manager grid] eq {pack}} {dict set item layout {manager pack fill x pady 3};break}}
    set s(model) [::GX::viewerGuiDesignModelEdit $s(model) add $item];set s(selected) $id;refresh
}
proc ::GX::InterfaceBuilder::select {} {
    variable s
    set node [lindex [.gxInterfaceDesigner.body.left.tree selection] 0]
    if {$node eq {}} return
    set s(selected) $node;properties;draw
}
proc ::GX::InterfaceBuilder::properties {} {
    variable s
    set selected $s(selected);set item {}
    foreach c [dict get [design] components] {if {[dict get $c id] eq $selected} {set item $c;break}}
    if {$item eq {}} {
        set fields {project.title project.module_id project.provider_id project.version project.geometry project.inspector_width};set api {Viewer project; public CORE design schema gxtxt.viewer_design.v1}
    } else {
        set cap [dict get [::GX::viewerGuiComponentCapabilities] [dict get $item type]]
        set fields {};foreach key [dict keys [dict get $cap properties]] {lappend fields property.$key}
        lappend fields parent layout.row layout.column layout.rowspan layout.columnspan layout.weight layout.padding layout.sticky layout.minimum_width layout.minimum_height layout.manager layout.side layout.fill layout.expand layout.anchor layout.padx layout.pady
        set s(apiId) [dict get $cap api_id]
        set api [dict create component $selected contract $cap events [dict get $cap events] preview_widget [expr {[dict exists $::GX::ViewerGui::instances .gxInterfacePreview widgets $selected] ? [dict get $::GX::ViewerGui::instances .gxInterfacePreview widgets $selected] : {not mounted}}]]
        if {[dict exists $::GX::ViewerGui::instances .gxInterfacePreview widgets $selected]} {
            set widget [dict get $::GX::ViewerGui::instances .gxInterfacePreview widgets $selected]
            if {![catch {::GX::uiFieldComponentRead $widget [dict get $item type]} actual]} {dict set api selected_current_value $actual}
        }
    }
    .gxInterfaceDesigner.body.right.properties.selected configure -text "Selected: $selected"
    .gxInterfaceDesigner.body.right.properties.key configure -values $fields
    if {$s(propertyKey) ni $fields} {set s(propertyKey) [lindex $fields 0]}
    propertyValue
    set text .gxInterfaceDesigner.body.right.api.text;$text configure -state normal;$text delete 1.0 end;$text insert end $api;$text configure -state disabled
}
proc ::GX::InterfaceBuilder::propertyValue {} {
    variable s;set key $s(propertyKey);set s(propertyValue) {}
    if {$key eq {project.inspector_width}} {set s(propertyValue) [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault [design] shell {}] inspector_width 320];return}
    if {[string match project.* $key]} {set s(propertyValue) [dict get [design] [string range $key 8 end]];return}
    foreach item [dict get [design] components] {
        if {[dict get $item id] ne $s(selected)} continue
        if {$key eq {parent}} {set s(propertyValue) [dict get $item parent]} else {
            lassign [split $key .] section name;set section [expr {$section eq {property} ? {properties} : $section}]
            set s(propertyValue) [::GX::datasetPublicationV2DictDefault [dict get $item $section] $name [expr {$section eq {layout} ? ($name eq {sticky} ? {ew} : ($name in {rowspan columnspan} ? 1 : 0)) : {}}]]
        }
    }
}
proc ::GX::InterfaceBuilder::propertyApply {} {
    variable s;set key $s(propertyKey)
    if {[string match project.* $key]} {apply metadata [string range $key 8 end] $s(propertyValue)} elseif {$key eq {parent}} {apply reparent $s(selected) $s(propertyValue)} else {lassign [split $key .] operation field;apply $operation $s(selected) $field $s(propertyValue)}
}
proc ::GX::InterfaceBuilder::preview {} {
    variable s
    set editorFocus [focus]
    set geometry 880x720+20+70
    set retained {}
    if {[winfo exists .gxInterfacePreview]} {
        set geometry [wm geometry .gxInterfacePreview]
        if {[::GX::viewerGuiDesignGuard .gxInterfacePreview]} {
            set retained [::GX::viewerGuiDesignCapture .gxInterfacePreview]
            set old [dict get $::GX::ViewerGui::instances .gxInterfacePreview design]
            set keepValues {};set keepBindings {}
            foreach item [dict get [design] components] {
                set id [dict get $item id]
                foreach previous [dict get $old components] {
                    if {[dict get $previous id] ne $id || [dict get $previous type] ne [dict get $item type]} continue
                    if {[dict exists $retained values $id] && [::GX::datasetPublicationV2DictDefault [dict get $previous properties] default {}] eq [::GX::datasetPublicationV2DictDefault [dict get $item properties] default {}]} {dict set keepValues $id [dict get $retained values $id]}
                    if {[dict exists $retained bindings $id]} {dict set keepBindings $id [dict get $retained bindings $id]}
                }
            }
            dict set retained values $keepValues;dict set retained bindings $keepBindings
        }
        destroy .gxInterfacePreview
    }
    if {![info exists s(previewMode)]} {set s(previewMode) preview;set s(previewHandlers) {}}
    ::GX::viewerGuiDesignCompose [design] .gxInterfacePreview viewer.interface_builder interface_builder $s(previewMode) $s(previewHandlers)
    if {[info exists s(importState)]} {set retained $s(importState);unset s(importState)}
    if {$retained ne {}} {::GX::viewerGuiDesignRestore .gxInterfacePreview $retained}
    wm title .gxInterfacePreview "[expr {$s(previewMode) eq {runtime} ? {Private test} : {Preview}}] — [dict get [design] title]";wm geometry .gxInterfacePreview $geometry
    set s(observer) [::GX::viewerGuiTraceSubscribe .gxInterfacePreview ::GX::InterfaceBuilder::event]
    bind .gxInterfacePreview <Configure> +[list ::GX::InterfaceBuilder::scheduleDraw %W]
    wm protocol .gxInterfacePreview WM_DELETE_WINDOW {::GX::InterfaceBuilder::previewClose}
    if {$editorFocus ne {} && [winfo exists $editorFocus] && [winfo toplevel $editorFocus] eq {.gxInterfaceDesigner}} {
        set s(returnFocus) $editorFocus
        bind .gxInterfacePreview <FocusIn> +[list ::GX::InterfaceBuilder::returnEditorFocus %W]
        if {[info exists s(focusTimer)]} {after cancel $s(focusTimer)}
        set s(focusTimer) [after 200 {unset -nocomplain ::GX::InterfaceBuilder::s(returnFocus)}]
    }
    after idle [list ::GX::InterfaceBuilder::draw]
}
proc ::GX::InterfaceBuilder::returnEditorFocus {actual} {
    variable s
    if {![info exists s(returnFocus)] || $actual ne {.gxInterfacePreview}} return
    set target $s(returnFocus);unset s(returnFocus)
    if {[winfo exists $target]} {focus -force $target}
}
proc ::GX::InterfaceBuilder::previewClose {} {destroy .gxInterfacePreview;set ::GX::InterfaceBuilder::s(status) {Preview closed. Choose Reopen Preview to continue.}}
proc ::GX::InterfaceBuilder::scheduleDraw {window} {
    variable s;if {$window ne {.gxInterfacePreview}} return
    if {[info exists s(drawTimer)]} {after cancel $s(drawTimer)}
    set s(drawTimer) [after 80 ::GX::InterfaceBuilder::draw]
}
proc ::GX::InterfaceBuilder::draw {args} {
    variable s
    set map .gxInterfaceDesigner.body.center.map
    if {![winfo exists $map] || ![winfo exists .gxInterfacePreview]} return
    $map delete all;set zoom $s(zoom)
    set report [::GX::viewerGuiRuntimeInspect .gxInterfacePreview]
    $map configure -scrollregion [list 0 0 [expr {[winfo width .gxInterfacePreview]*$zoom+20}] [expr {[winfo height .gxInterfacePreview]*$zoom+20}]]
    dict for {id row} [dict get $report components] {
        if {![dict exists $row rectangle] || [dict get $row type] in {help workspace menu}} continue
        lassign [dict get $row rectangle] x y width height
        set color [expr {$id eq $s(selected) ? {#d8e8ff} : {#edf2f5}}]
        $map create rectangle [expr {$x*$zoom+8}] [expr {$y*$zoom+8}] [expr {($x+$width)*$zoom+8}] [expr {($y+$height)*$zoom+8}] -fill $color -outline #70869b -tags [list component component_$id]
        $map create text [expr {$x*$zoom+12}] [expr {$y*$zoom+12}] -anchor nw -text "$id · [dict get $row type]" -tags [list component component_$id]
    }
}
proc ::GX::InterfaceBuilder::mapSelect {x y} {
    variable s;set c .gxInterfaceDesigner.body.center.map
    foreach item [$c find overlapping [$c canvasx $x] [$c canvasy $y] [$c canvasx $x] [$c canvasy $y]] {foreach tag [$c gettags $item] {if {[string match component_* $tag]} {set s(selected) [string range $tag 10 end];.gxInterfaceDesigner.body.left.tree selection set $s(selected);properties;draw;return}}}
}
proc ::GX::InterfaceBuilder::mapPress {x y} {
    variable s;mapSelect $x $y
    set report [::GX::viewerGuiRuntimeInspect .gxInterfacePreview]
    if {![dict exists $report components $s(selected) rectangle]} return
    set rectangle [dict get $report components $s(selected) rectangle]
    lassign $rectangle rx ry width height
    set c .gxInterfaceDesigner.body.center.map
    set px [$c canvasx $x];set py [$c canvasy $y]
    set resize [expr {abs($px-(($rx+$width)*$s(zoom)+8))<15 && abs($py-(($ry+$height)*$s(zoom)+8))<15}]
    set s(mapDrag) [dict create id $s(selected) x $px y $py rectangle $rectangle resize $resize]
}
proc ::GX::InterfaceBuilder::mapMotion {x y} {
    variable s;if {![info exists s(mapDrag)]} return
    set c .gxInterfaceDesigner.body.center.map
    set dx [expr {[$c canvasx $x]-[dict get $s(mapDrag) x]}];set dy [expr {[$c canvasy $y]-[dict get $s(mapDrag) y]}]
    lassign [dict get $s(mapDrag) rectangle] rx ry width height
    set left [expr {$rx*$s(zoom)+8}];set top [expr {$ry*$s(zoom)+8}]
    if {[dict get $s(mapDrag) resize]} {set right [expr {$left+$width*$s(zoom)+$dx}];set bottom [expr {$top+$height*$s(zoom)+$dy}]} else {set left [expr {$left+$dx}];set top [expr {$top+$dy}];set right [expr {$left+$width*$s(zoom)}];set bottom [expr {$top+$height*$s(zoom)}]}
    $c delete dragGhost;$c create rectangle $left $top $right $bottom -outline #145da0 -dash {4 3} -width 2 -tags dragGhost
    set s(status) {Drag onto a sibling to swap grid cells or onto a container to nest. Corner drag edits responsive minimum dimensions with a 16 px snap.}
}
proc ::GX::InterfaceBuilder::mapRelease {x y} {
    variable s;if {![info exists s(mapDrag)]} return
    set drag $s(mapDrag);unset s(mapDrag)
    set c .gxInterfaceDesigner.body.center.map;$c delete dragGhost
    set dx [expr {([$c canvasx $x]-[dict get $drag x])/$s(zoom)}];set dy [expr {([$c canvasy $y]-[dict get $drag y])/$s(zoom)}]
    if {abs($dx)+abs($dy)<8} return
    set id [dict get $drag id]
    if {[dict get $drag resize]} {
        lassign [dict get $drag rectangle] rx ry width height
        safe apply constraints $id [dict create minimum_width [expr {max(16,min(2000,16*round(($width+$dx)/16.0)))}] minimum_height [expr {max(16,min(2000,16*round(($height+$dy)/16.0)))}]]
        return
    }
    set target {}
    foreach item [$c find overlapping [$c canvasx $x] [$c canvasy $y] [$c canvasx $x] [$c canvasy $y]] {foreach tag [$c gettags $item] {if {[string match component_* $tag] && [string range $tag 10 end] ne $id} {set target [string range $tag 10 end]}}}
    if {$target ne {}} {
        set source [::GX::viewerGuiDesignComponent .gxInterfacePreview $id];set destination [::GX::viewerGuiDesignComponent .gxInterfacePreview $target]
        if {[dict get $source parent] eq [dict get $destination parent]} {safe apply swap $id $target} elseif {[dict get $destination type] in {panel section splitter tabs tab}} {safe apply reparent $id $target} else {set s(status) {The target is not a compatible sibling or container.}}
    } else {set s(status) {Choose a declared sibling/container target; precise grid placement is available in Properties.}}
}
proc ::GX::InterfaceBuilder::paletteInfo {} {
    variable s;set type [lindex [.gxInterfaceDesigner.body.left.palette selection] 0]
    if {$type eq {}} return
    set cap [dict get [::GX::viewerGuiComponentCapabilities] $type];set s(apiId) [dict get $cap api_id]
    set text .gxInterfaceDesigner.body.right.api.text;$text configure -state normal;$text delete 1.0 end;$text insert end $cap;$text configure -state disabled
}
proc ::GX::InterfaceBuilder::apiGuide {} {variable s;if {![info exists s(apiId)]} {set s(apiId) VIEWER_GUI_HOST_API_v1};::GX::documentationBrowserOpenApi $s(apiId)}
proc ::GX::InterfaceBuilder::gallery {} {
    variable s;set s(presentationMode) Demo
    set selected [lindex [.gxInterfaceDesigner.body.left.palette selection] 0]
    return [::GX::viewerGuiComponentGalleryOpen $selected]
}
proc ::GX::InterfaceBuilder::presentationMode {} {
    variable s
    switch $s(presentationMode) {
        Design {::GX::viewerGuiComponentGalleryClose;set s(status) {Design mode · project and Undo/Redo retained}}
        Demo {gallery}
        {Runtime Test} {::GX::viewerGuiComponentGalleryClose;connectHandlers}
    }
}
proc ::GX::InterfaceBuilder::clearTrace {} {::GX::viewerGuiTraceClear .gxInterfacePreview;.gxInterfaceDesigner.body.right.events.trace delete 1.0 end}
proc ::GX::InterfaceBuilder::event {record} {
    variable s
    if {[dict get $record event] eq {selected}} {
        set s(selected) [dict get $record component]
        if {[winfo exists .gxInterfaceDesigner.body.left.tree] && [.gxInterfaceDesigner.body.left.tree exists $s(selected)]} {.gxInterfaceDesigner.body.left.tree selection set $s(selected);properties}
    }
    if {$s(traceOn) && [string match $s(recordComponent) [dict get $record component]] && [string match $s(traceEvent) [dict get $record event]] && [winfo exists .gxInterfaceDesigner.body.right.events.trace]} {
        set text .gxInterfaceDesigner.body.right.events.trace;$text insert end "$record\n"
        if {[lindex [split [$text index end] .] 0]>2001} {$text delete 1.0 end-2000lines}
        $text see end
    }
}
proc ::GX::InterfaceBuilder::refresh {} {
    variable s
    set priorFocus [focus]
    set tree .gxInterfaceDesigner.body.left.tree
    $tree delete [$tree children {}]
    foreach region {toolbar inspector canvas footer menubar} {$tree insert {} end -id $region -text [string totitle $region] -open 1}
    foreach item [dict get [design] components] {$tree insert [dict get $item parent] end -id [dict get $item id] -text "[dict get $item id] · [dict get $item type]" -open 1}
    if {[$tree exists $s(selected)]} {$tree selection set $s(selected)} else {set s(selected) canvas;$tree selection set canvas}
    preview;properties;set s(status) "Design revision [dict get $s(model) revision] — [llength [dict get [design] components]] CORE components"
    if {$priorFocus ne {} && [winfo exists $priorFocus] && [winfo toplevel $priorFocus] eq {.gxInterfaceDesigner}} {after idle [list focus $priorFocus]}
}
proc ::GX::InterfaceBuilder::copy {{cut 0}} {
    variable s
    set ids [list $s(selected)];set items {};set contracts {}
    foreach item [dict get [design] components] {
        if {[dict get $item parent] in $ids} {lappend ids [dict get $item id]}
        if {[dict get $item id] in $ids} {lappend items $item}
    }
    if {$items eq {}} {error {Select a component subtree to copy.}}
    set s(clipboard) [dict create items $items handlers [dict get [design] handlers]]
    if {$cut} {apply remove $s(selected)}
    set s(status) {Component subtree copied. Select a container and choose Paste.}
}
proc ::GX::InterfaceBuilder::paste {} {
    variable s
    if {![info exists s(clipboard)]} {error {Copy a component first.}}
    set s(model) [::GX::viewerGuiDesignModelEdit $s(model) paste [dict get $s(clipboard) items] $s(selected) [dict get $s(clipboard) handlers]]
    refresh
}
proc ::GX::InterfaceBuilder::remove {} {apply remove $::GX::InterfaceBuilder::s(selected)}
proc ::GX::InterfaceBuilder::duplicate {} {apply duplicate $::GX::InterfaceBuilder::s(selected)}
proc ::GX::InterfaceBuilder::up {} {apply reorder $::GX::InterfaceBuilder::s(selected) -1}
proc ::GX::InterfaceBuilder::down {} {apply reorder $::GX::InterfaceBuilder::s(selected) 1}
proc ::GX::InterfaceBuilder::align {} {apply layout $::GX::InterfaceBuilder::s(selected) sticky w}
proc ::GX::InterfaceBuilder::validate {} {::GX::viewerGuiDesignValidate [design];set ::GX::InterfaceBuilder::s(status) {Design and public CORE capability contracts are valid.}}
proc ::GX::InterfaceBuilder::analyze {} {
    set result [::GX::viewerGuiRuntimeInspect .gxInterfacePreview]
    set w .gxInterfaceDesigner.body.right.diagnostics.text;$w delete 1.0 end;$w insert end $result
    .gxInterfaceDesigner.body.right select .gxInterfaceDesigner.body.right.diagnostics
    return $result
}
proc ::GX::InterfaceBuilder::measure {} {
    variable s
    if {[info exists s(monitor)] && [dict exists $::GX::ViewerGui::monitors $s(monitor)]} {error {A finite responsiveness measurement is already active.}}
    set s(monitor) [::GX::viewerGuiMonitorStart .gxInterfacePreview 2000 ::GX::InterfaceBuilder::measured]
    set s(status) {Measuring 2 seconds of Viewer responsiveness and process resource counters. Interact with Preview now.}
}
proc ::GX::InterfaceBuilder::measured {report} {
    variable s;unset -nocomplain s(monitor);set s(lastReport) $report
    if {![winfo exists .gxInterfaceDesigner]} return
    set widget .gxInterfaceDesigner.body.right.diagnostics.text;$widget delete 1.0 end;$widget insert end $report
    set s(status) "[dict get $report status]: maximum measured callback interval [format %.1f [dict get $report max_callback_interval_ms]] ms. Process counters are not per-Viewer attribution."
}
proc ::GX::InterfaceBuilder::planTests {} {
    variable s
    set families {};foreach family {structure negative lifecycle scientific} {if {$s(test,$family)} {lappend families $family}}
    set s(testPlan) [::GX::viewerGuiTestPlan .gxInterfacePreview $families]
    set s(testRevision) [dict get $s(model) revision]
    set tree .gxInterfaceDesigner.body.right.tests.cases;$tree delete [$tree children {}]
    foreach row [dict get $s(testPlan) cases] {$tree insert {} end -id [dict get $row id] -text [dict get $row id] -values [list {NOT RUN} [dict get $row label]]}
    set s(testStatus) "Planned [dict get $s(testPlan) count] cases. [dict get $s(testPlan) fixture_requirements]"
}
proc ::GX::InterfaceBuilder::runTests {{selected 0}} {
    variable s
    if {![info exists s(testPlan)] || $s(testRevision)!=[dict get $s(model) revision]} {error {Plan the finite suite for the current design before running it.}}
    if {[info exists s(testRun)] && [dict exists $::GX::ViewerGui::laboratories $s(testRun)] && ![dict exists $::GX::ViewerGui::laboratories $s(testRun) finished]} {error {A bounded GUI run is already active.}}
    set plan $s(testPlan)
    if {$selected} {
        set ids [.gxInterfaceDesigner.body.right.tests.cases selection];set cases {}
        foreach row [dict get $plan cases] {if {[dict get $row id] in $ids} {lappend cases $row}}
        if {$cases eq {}} {error {Select the specific cases to rerun.}}
        dict set plan cases $cases;dict set plan count [llength $cases]
    }
    set s(testRun) [::GX::viewerGuiTestsStart .gxInterfacePreview $plan ::GX::InterfaceBuilder::testsCompleted]
    set s(testStatus) "Running $s(testRun): [dict get $plan count] finite cases."
}
proc ::GX::InterfaceBuilder::testsCompleted {report} {
    variable s;set s(lastReport) $report
    if {![winfo exists .gxInterfaceDesigner]} return
    set tree .gxInterfaceDesigner.body.right.tests.cases
    foreach row [dict get $report cases] {
        set id [dict get $row id]
        if {[$tree exists $id]} {$tree item $id -values [list [dict get $row status] [dict get $row observed]]} else {$tree insert {} end -id $id -text $id -values [list [dict get $row status] [dict get $row observed]]}
    }
    set s(testStatus) "[dict get $report id]: [dict get $report status], [llength [dict get $report cases]] observed cases. Export the receipt to retain this run."
}
proc ::GX::InterfaceBuilder::recordStart {} {
    variable s
    if {[info exists s(recording)]} {error {Stop the current recording first.}}
    set s(recording) [::GX::viewerGuiRecordingStart .gxInterfacePreview [dict create component $s(recordComponent) event *]]
    set s(testStatus) {Recording command/result transitions. Field values and scientific payloads are redacted.}
}
proc ::GX::InterfaceBuilder::recordStop {} {
    variable s
    if {![info exists s(recording)]} {error {Start recording first.}}
    set scenario [::GX::viewerGuiRecordingStop $s(recording)];unset s(recording)
    set text .gxInterfaceDesigner.body.right.tests.scenario;$text delete 1.0 end;$text insert 1.0 $scenario
    set s(testStatus) "Recorded [llength [dict get $scenario actions]] logical command/result actions. Edit the inert scenario below, save or replay."
}
proc ::GX::InterfaceBuilder::scenarioRead {} {return [::GX::viewerGuiScenarioValidate [string trim [.gxInterfaceDesigner.body.right.tests.scenario get 1.0 end]]]}
proc ::GX::InterfaceBuilder::scenarioSave {} {
    set scenario [scenarioRead]
    set path [::GX::workspaceSaveFile manifest_dir -parent .gxInterfaceDesigner -title {Save GUI scenario} -defaultextension .gxtxt-gui-test -filetypes {{{GUI scenario} {.gxtxt-gui-test}}}]
    if {$path ne {}} {::GX::resourceLifecycleWriteBytes $path [encoding convertto utf-8 $scenario]}
}
proc ::GX::InterfaceBuilder::scenarioOpen {} {
    set path [::GX::workspaceOpenFile manifest_dir -parent .gxInterfaceDesigner -title {Open GUI scenario} -filetypes {{{GUI scenario} {.gxtxt-gui-test}}}]
    if {$path eq {}} return
    if {[file size $path]>4194304} {error {GUI scenario exceeds 4 MiB.}}
    set f [open $path r];try {set scenario [::GX::viewerGuiScenarioValidate [read $f]]} finally {close $f}
    set text .gxInterfaceDesigner.body.right.tests.scenario;$text delete 1.0 end;$text insert 1.0 $scenario
}
proc ::GX::InterfaceBuilder::replay {} {
    variable s
    set scenario [scenarioRead]
    set options {}
    if {$s(previewMode) eq {runtime}} {set options [dict create fixture_root $s(testFixtureRoot) permitted_commands [dict keys [dict get [design] handlers]]]}
    set s(testRun) [::GX::viewerGuiReplayStart .gxInterfacePreview $scenario ::GX::InterfaceBuilder::testsCompleted $options]
    set s(testStatus) "Replaying $s(testRun): [llength [dict get $scenario actions]] mapped GUI actions with bounded waits."
}
proc ::GX::InterfaceBuilder::cancelTest {} {variable s;if {[info exists s(testRun)]} {::GX::viewerGuiReplayCancel $s(testRun)}}
proc ::GX::InterfaceBuilder::exportReport {} {
    variable s
    if {![info exists s(lastReport)]} {error {Run a finite suite or replay before exporting its receipt.}}
    set path [::GX::workspaceSaveFile manifest_dir -parent .gxInterfaceDesigner -title {Export new GUI test receipt} -defaultextension .json -initialfile [dict get $s(lastReport) id].json -filetypes {{{JSON report} {.json}}}]
    if {$path eq {}} return
    set s(reportJob) [::GX::viewerGuiDiagnosticExport $s(lastReport) $path ::GX::InterfaceBuilder::reportExported]
}
proc ::GX::InterfaceBuilder::reportExported {response} {
    if {![winfo exists .gxInterfaceDesigner]} return
    if {[dict get $response ok]} {set ::GX::InterfaceBuilder::s(testStatus) "Exported [dict get $response result path]"} else {set ::GX::InterfaceBuilder::s(testStatus) "Report export failed: [dict get $response error]"}
}
proc ::GX::InterfaceBuilder::bindAction {} {
    variable s
    apply bind $s(selected) $s(actionId) $s(actionEffect)
}
proc ::GX::InterfaceBuilder::treePress {x y} {variable s;set s(dragStart) [list $x $y [.gxInterfaceDesigner.body.left.tree identify row $x $y]];set s(dragging) 0}
proc ::GX::InterfaceBuilder::treeMotion {x y} {
    variable s;if {![info exists s(dragStart)]} return
    lassign $s(dragStart) sx sy source
    if {abs($x-$sx)+abs($y-$sy)>8} {set s(dragging) 1;set target [.gxInterfaceDesigner.body.left.tree identify row $x $y];set s(status) "Place $source inside $target; CORE validates the container and grid."}
}
proc ::GX::InterfaceBuilder::treeRelease {x y} {
    variable s;if {![info exists s(dragStart)] || !$s(dragging)} return
    set source [lindex $s(dragStart) 2];set target [.gxInterfaceDesigner.body.left.tree identify row $x $y]
    unset s(dragStart);set s(dragging) 0
    if {$source ne {} && $target ne {}} {safe apply reparent $source $target}
}
proc ::GX::InterfaceBuilder::sourceDialog {} {
    variable s
    set type {};foreach item [dict get [design] components] {if {[dict get $item id] eq $s(selected)} {set type [dict get $item type]}}
    if {$type ne {native2d}} {error {Select a Native2D source slot, then Bind Dataset.}}
    if {$::GX::currentSession eq {}} {error {Open a Session with a canonical scientific Dataset first.}}
    if {[::GX::uiFieldDatasetChoices] eq {}} {error {No canonical scientific Datasets are available in this Session.}}
    set w .gxInterfaceSource;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxInterfaceDesigner {Bind scientific XY source} 460x340
    ttk::label $w.about -text {Select a canonical Dataset and exact X/Y Variable IDs. Binding displays a bounded curve through the public source host.} -wraplength 420 -justify left;pack $w.about -fill x -padx 8 -pady 6
    set s(sourceDataset) [lindex [::GX::uiFieldDatasetChoices] 0]
    ttk::combobox $w.dataset -state readonly -textvariable ::GX::InterfaceBuilder::s(sourceDataset)
    ::GX::uiFieldSelectorWithinViewer $w.dataset $w
    ::GX::datasetSelectorAttach $w.dataset ::GX::uiFieldDatasetChoices
    bind $w.dataset <<ComboboxSelected>> ::GX::InterfaceBuilder::sourceVariables
    pack $w.dataset -fill x -padx 8 -pady 6
    ttk::frame $w.variables;pack $w.variables -fill both -expand 1 -padx 8
    ttk::button $w.bind -text {Bind source to Preview} -command {::GX::InterfaceBuilder::safe sourceBind}
    ttk::button $w.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.bind $w.cancel -side left -padx 8 -pady 8
    sourceVariables
    ::GX::uiFieldDialogPresent $w $w.dataset 0
}
proc ::GX::InterfaceBuilder::sourceVariables {} {
    variable s;set w .gxInterfaceSource.variables
    foreach child [winfo children $w] {destroy $child}
    set ids {};set summary {}
    foreach variable [::GX::datasetVariableSchemaV3 $s(sourceDataset)] {
        set id [dict get $variable variable_id];lappend ids $id
        append summary "$id  ([::GX::datasetPublicationV2DictDefault $variable unit {}])\n"
    }
    set s(sourceX) [lindex $ids 0];set s(sourceY) [lindex $ids 1]
    if {$s(sourceY) eq {}} {set s(sourceY) $s(sourceX)}
    foreach name {X Y} {
        ttk::label $w.l$name -text "$name Variable ID";pack $w.l$name -anchor w
        set field $w.[string tolower $name]
        ::GX::uiFieldCreate $field [dict create type choice values $ids default $s(source$name) compact 1] ::GX::InterfaceBuilder::s(source$name)
        ::GX::uiFieldSelectorWithinViewer $field.entry .gxInterfaceSource
        pack $field -fill x -pady 3
    }
    ttk::label $w.units -text $summary -wraplength 420 -justify left;pack $w.units -anchor w
}
proc ::GX::InterfaceBuilder::sourceBind {} {
    variable s
    set request [dict create dataset_id $s(sourceDataset) x_variable_id $s(sourceX) y_variable_id $s(sourceY) display_budget 4096]
    ::GX::viewerGuiDesignSourceSet .gxInterfacePreview $s(selected) $request
    ::GX::uiFieldDialogClose .gxInterfaceSource;set s(status) {Scientific source bound through Native2D / Curve Source.}
}
proc ::GX::InterfaceBuilder::importDialog {} {
    variable s
    set w .gxInterfaceImport;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxInterfaceDesigner {Import Existing Viewer} 650x230
    set s(importChoices) {};set labels {}
    foreach module $::GX::moduleOrder {
        foreach provider [::GX::viewerProviderIds $module] {
            set d [::GX::viewerProviderDefinition $module $provider 1]
            set label "[dict get $d name] — $module / $provider"
            lappend labels $label;dict set s(importChoices) $label [list $module $provider]
        }
    }
    set s(importChoice) [lindex $labels 0]
    ttk::label $w.about -text {Import reads a declared design or a published CORE manifest. Custom, unrepresented interface sections remain explicit coverage boundaries. The original module is preserved.} -wraplength 610 -justify left
    ttk::combobox $w.choice -state readonly -values $labels -textvariable ::GX::InterfaceBuilder::s(importChoice) -width 70
    ::GX::uiFieldSelectorWithinViewer $w.choice $w
    ttk::button $w.original -text {Open original for inspection} -command {::GX::InterfaceBuilder::safe importOriginal}
    ttk::button $w.import -text {Import declared interface} -command {::GX::InterfaceBuilder::safe importApply}
    ttk::button $w.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.about $w.choice -fill x -padx 10 -pady 8;pack $w.original $w.import $w.cancel -side left -padx 8 -pady 10
    ::GX::uiFieldDialogPresent $w $w.choice 0
}
proc ::GX::InterfaceBuilder::importOriginal {} {
    variable s;lassign [dict get $s(importChoices) $s(importChoice)] module provider
    set existing [::GX::viewerGuiPublishedWindows $module $provider]
    if {$existing ne {}} {set s(originalWindow) [lindex $existing 0];wm deiconify $s(originalWindow);raise $s(originalWindow)} else {set s(originalWindow) [::GX::viewerOpen $module $provider]}
    return $s(originalWindow)
}
proc ::GX::InterfaceBuilder::importApply {} {
    variable s;if {![prepare]} return
    lassign [dict get $s(importChoices) $s(importChoice)] module provider
    set report [::GX::viewerGuiDesignImport $module $provider];set s(importReport) $report
    .gxInterfaceDesigner.body.right.diagnostics.text delete 1.0 end;.gxInterfaceDesigner.body.right.diagnostics.text insert end $report
    .gxInterfaceDesigner.body.right select .gxInterfaceDesigner.body.right.diagnostics
    if {![dict exists $report design]} {set s(status) [dict get $report reason];return $report}
    set d [dict get $report design]
    dict set d origin module $module;dict set d origin provider $provider
    if {[dict exists $report state]} {set s(importState) [dict get $report state]}
    set s(previewMode) preview;set s(previewHandlers) {};set s(model) [::GX::viewerGuiDesignModelCreate $d];set s(path) {};set s(selected) canvas;refresh
    set s(status) "Imported [dict get $report status]. Review coverage boundaries before comparison."
    ::GX::uiFieldDialogClose .gxInterfaceImport
    return $report
}
proc ::GX::InterfaceBuilder::compare {} {
    variable s;set origin [dict get [design] origin]
    if {![dict exists $origin module] || ![dict exists $origin provider]} {error {Import an installed Viewer before comparing with its original.}}
    set existing [::GX::viewerGuiPublishedWindows [dict get $origin module] [dict get $origin provider]]
    if {$existing ne {}} {set s(originalWindow) [lindex $existing 0]} else {set s(originalWindow) [::GX::viewerOpen [dict get $origin module] [dict get $origin provider]]}
    if {[llength $s(originalWindow)]!=1 || ![winfo exists $s(originalWindow)]} {error {Original uses an external or structured window host; native side-by-side comparison is unavailable.}}
    set width [expr {max(640,min(900,([winfo screenwidth .]-40)/2))}];set height [expr {min(700,[winfo screenheight .]-140)}]
    set next [expr {$width+25}]
    wm geometry $s(originalWindow) ${width}x${height}+5+60;wm geometry .gxInterfacePreview ${width}x${height}+$next+60
    set s(status) {Matching sizes requested. Comparison follows mapping; only declared components and observed commands can establish parity.}
    if {[info exists s(compareTimer)]} {after cancel $s(compareTimer)}
    set s(compareTimer) [after 250 [list ::GX::InterfaceBuilder::safe compareInspect]]
    return [dict create original $s(originalWindow) preview .gxInterfacePreview import $s(importReport)]
}
proc ::GX::InterfaceBuilder::compareInspect {} {
    variable s
    set report [::GX::viewerGuiCompare $s(originalWindow) .gxInterfacePreview]
    set s(lastReport) $report
    set text .gxInterfaceDesigner.body.right.diagnostics.text;$text delete 1.0 end;$text insert end $report
    .gxInterfaceDesigner.body.right select .gxInterfaceDesigner.body.right.diagnostics
    set s(status) "[dict get $report id]: [dict get $report status]. Review each mismatch and the actual behavior coverage."
    return $report
}
proc ::GX::InterfaceBuilder::generate {} {
    variable s
    if {[info exists s(generateJob)] && [dict exists $::GX::scriptJobRequests $s(generateJob)]} {error {Module generation is running. Cancel it or wait for its result.}}
    set d [design]
    set importedHandlers {}
    if {[dict exists $d origin module] && [dict get $d origin module] eq [dict get $d module_id]} {
        if {[catch {set importedHandlers [::GX::viewerGuiDesignHandlerSource [dict get $d origin module] [dict get $d origin provider]]}]} {error {Choose a separate generated module ID in Project properties before generating this imported Viewer.}}
    }
    if {$s(path) eq {}} {save;if {$s(path) eq {}} return}
    set output [tk_chooseDirectory -parent .gxInterfaceDesigner -title {Viewer module package folder} -initialdir [file dirname $s(path)]]
    if {$output eq {}} return
    set source [file join [file dirname $s(path)] [dict get $d provider_id]_source]
    if {$importedHandlers ne {} && ![file exists [file join $source handlers.tcl]]} {
        file mkdir $source
        ::GX::resourceLifecycleWriteBytes [file join $source handlers.tcl] $importedHandlers
    }
    set temporary [file join [::GX::configurationTempDirectory] viewer-interface-generation [pid]-[clock microseconds]]
    file mkdir $temporary
    set snapshot [file join $temporary project.gxtxt-viewer]
    ::GX::viewerGuiDesignSave $snapshot $d
    set revision [dict get $s(model) revision]
    set s(generateJob) [::GX::viewerGuiDesignGenerate $snapshot $source $output [list ::GX::InterfaceBuilder::generated $revision]]
    set s(status) "Generating Viewer revision $revision; handwritten handlers are preserved."
}
proc ::GX::InterfaceBuilder::generated {revision response} {
    variable s
    unset -nocomplain s(generateJob)
    if {![winfo exists .gxInterfaceDesigner]} return
    if {![dict get $response ok]} {set s(status) "Generation failed: [dict get $response error]";return}
    set s(generated) [dict get $response result]
    set s(status) "Generated revision $revision: [dict get $s(generated) package]"
    .gxInterfaceDesigner.body.right.diagnostics.text delete 1.0 end
    .gxInterfaceDesigner.body.right.diagnostics.text insert end $s(generated)
    .gxInterfaceDesigner.body.right select .gxInterfaceDesigner.body.right.diagnostics
}
proc ::GX::InterfaceBuilder::cancelGenerate {} {variable s;if {[info exists s(generateJob)]} {::GX::scriptJobRequestCancel $s(generateJob)}}
proc ::GX::InterfaceBuilder::connectHandlers {} {
    variable s
    set root [tk_chooseDirectory -parent .gxInterfaceDesigner -title {Explicitly marked private GUI test fixture root}]
    if {$root eq {}} return
    if {![::GX::viewerGuiTestFixtureValidate .gxInterfacePreview [dict create fixture_root $root permitted_commands {}]]} {error {Select a private test root containing .gxtxt-gui-test-fixture and the current Session. Runtime handler connection is restricted to this explicit fixture.}}
    set d [design];set module [dict get $d module_id];set provider [dict get $d provider_id]
    set imported [::GX::viewerGuiDesignImport $module $provider]
    if {![dict exists $imported design] || [dict remove [dict get $imported design] origin] ne [dict remove $d origin]} {error {Install the matching generated Viewer package before connecting its explicit scientific test handlers.}}
    set s(previewHandlers) [::GX::viewerGuiDesignHandlerBindings $module $provider]
    set s(testFixtureRoot) [file normalize $root];set s(previewMode) runtime;refresh
    set s(status) {Private test mode: installed handler contracts are connected. Invoke a declared action explicitly.}
}
proc ::GX::InterfaceBuilder::disconnectHandlers {} {variable s;set s(previewMode) preview;set s(previewHandlers) {};refresh;set s(status) {Safe design mode: custom scientific handlers are disconnected.}}
proc ::GX::InterfaceBuilder::pluginManager {} {::GX::pluginManagerDialog}
proc ::GX::InterfaceBuilder::close {} {
    variable s;if {![prepare]} return
    foreach key {generateJob reportJob} {if {[info exists s($key)]} {::GX::scriptJobRequestCancel $s($key) closed}}
    foreach key {drawTimer focusTimer compareTimer} {if {[info exists s($key)]} {after cancel $s($key)}}
    cancelTest
    if {[info exists s(monitor)]} {::GX::viewerGuiMonitorCancel $s(monitor)}
    if {[info exists s(recording)]} {::GX::viewerGuiRecordingStop $s(recording);unset s(recording)}
    catch {destroy .gxInterfacePreview};destroy .gxInterfaceDesigner
}
proc ::GX::InterfaceBuilder::open {{context {}}} {
    variable s
    if {[winfo exists .gxInterfaceDesigner]} {raise .gxInterfaceDesigner;if {[winfo exists .gxInterfacePreview]} {raise .gxInterfacePreview};return .gxInterfaceDesigner}
    if {![info exists s(model)]} {set s(model) [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignNew]];set s(path) {}}
    array set s {selected canvas propertyKey project.title propertyValue {} actionId analyze actionEffect unbound zoom .7 status {Choose a CORE component and add it to a region.} test,structure 1 test,negative 1 test,lifecycle 1 test,scientific 0 testStatus {Select families, inspect the finite plan, then run.} recordComponent * traceOn 1 traceEvent *}
    set w .gxInterfaceDesigner;toplevel $w;wm title $w {Viewer Interface Designer};wm geometry $w 940x860+950+60;wm minsize $w 800 550
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    set catalog {};set handlers {}
    foreach {id label method keys} {new New new Ctrl+n open Open… openFile Ctrl+o save Save save Ctrl+s save_as {Save As…} {save 1} Ctrl+Shift+s validate Validate validate F5 add {Add component} add {} remove Remove remove Delete duplicate Duplicate duplicate Ctrl+d undo Undo {navigate undo} Ctrl+z redo Redo {navigate redo} Ctrl+y up {Move up} up {} down {Move down} down {} align {Align left} align {} preview {Reopen Preview} preview F6 analyze Analyze analyze F7 close Close close {}} {
        dict set catalog $id [dict create label $label default $keys]
        dict set handlers $id [dict create command [list ::GX::InterfaceBuilder::safe {*}$method]]
    }
    foreach {id label method keys} {copy Copy copy Ctrl+c cut Cut {copy 1} Ctrl+x paste Paste paste Ctrl+v} {dict set catalog $id [dict create label $label default $keys clipboard_operation $id];dict set handlers $id [dict create command [list ::GX::InterfaceBuilder::safe {*}$method]]}
    foreach {id label method} {gallery {Component Gallery / Demo…} gallery import_existing {Import Existing Viewer…} importDialog compare {Compare with Original Viewer} compare bind_source {Bind Dataset…} sourceDialog generate {Generate installable Viewer…} generate cancel_generate {Cancel generation} cancelGenerate plugins {Plugin Manager…} pluginManager connect_handlers {Connect installed test handlers…} connectHandlers disconnect_handlers {Disconnect test handlers} disconnectHandlers} {dict set catalog $id [dict create label $label];dict set handlers $id [dict create command [list ::GX::InterfaceBuilder::safe $method]]}
    ::GX::viewerCommandCatalogRegister viewer.interface_builder.designer $catalog {} designer_shortcuts viewer.interface_builder
    ::GX::viewerCommandsAttach $w viewer.interface_builder.designer $handlers {} {} {session_scoped 0}
    foreach {name label ids} {file File {new open save save_as import_existing - generate cancel_generate plugins - close} edit Edit {undo redo - copy cut paste duplicate remove up down align} design Design {add gallery preview bind_source validate - connect_handlers disconnect_handlers} inspect Inspect {analyze compare}} {
        ::GX::viewerGuiMenuMount $w $w.menus.$name $ids;$w.menus add cascade -label $label -underline 0 -menu $w.menus.$name
    }
    ttk::frame $w.toolbar;pack $w.toolbar -fill x
    ::GX::viewerCommandToolbarCreate $w $w.toolbar {add gallery duplicate remove undo redo preview validate analyze generate plugins}
    ttk::frame $w.modes;pack $w.modes -fill x -padx 5 -pady 3
    ttk::label $w.modes.label -text {Workspace mode:}
    set s(presentationMode) Design
    ttk::combobox $w.modes.choice -state readonly -values {Design Demo {Runtime Test}} -textvariable ::GX::InterfaceBuilder::s(presentationMode) -width 18
    bind $w.modes.choice <<ComboboxSelected>> {::GX::InterfaceBuilder::safe presentationMode}
    pack $w.modes.label $w.modes.choice -side left -padx 3
    ttk::label $w.status -textvariable ::GX::InterfaceBuilder::s(status) -wraplength 900 -anchor w;pack $w.status -side bottom -fill x -padx 6 -pady 5
    ttk::panedwindow $w.body -orient horizontal;pack $w.body -fill both -expand 1
    ttk::frame $w.body.left;ttk::frame $w.body.center;ttk::notebook $w.body.right
    $w.body add $w.body.left -weight 1;$w.body add $w.body.center -weight 3;$w.body add $w.body.right -weight 2
    ttk::label $w.body.left.paletteTitle -text {Public CORE palette} -font TkHeadingFont;pack $w.body.left.paletteTitle -fill x
    ttk::treeview $w.body.left.palette -columns {owner} -show {tree headings} -height 10
    $w.body.left.palette heading #0 -text Component;$w.body.left.palette column #0 -width 160
    $w.body.left.palette heading owner -text API;$w.body.left.palette column owner -width 160
    dict for {type cap} [::GX::viewerGuiComponentCapabilities] {$w.body.left.palette insert {} end -id $type -text $type -values [list "[dict get $cap api_id] @[dict get $cap api_version]"] -tags [dict get $cap status]}
    $w.body.left.palette tag configure CORE_GAP -foreground #777777;pack $w.body.left.palette -fill both -expand 1
    ttk::scrollbar $w.body.left.paletteScroll -orient vertical -command [list $w.body.left.palette yview]
    $w.body.left.palette configure -yscrollcommand [list $w.body.left.paletteScroll set]
    place $w.body.left.paletteScroll -in $w.body.left.palette -relx 1 -x -15 -y 20 -width 15 -relheight 1 -height -20
    ttk::scrollbar $w.body.left.paletteHorizontal -orient horizontal -command [list $w.body.left.palette xview]
    $w.body.left.palette configure -xscrollcommand [list $w.body.left.paletteHorizontal set]
    pack $w.body.left.paletteHorizontal -side bottom -fill x -before $w.body.left.palette
    bind $w.body.left.palette <Double-1> {::GX::InterfaceBuilder::safe add;break}
    bind $w.body.left.palette <<TreeviewSelect>> ::GX::InterfaceBuilder::paletteInfo
    ttk::label $w.body.left.treeTitle -text {Component hierarchy} -font TkHeadingFont;pack $w.body.left.treeTitle -fill x
    ttk::treeview $w.body.left.tree -show tree -height 10;pack $w.body.left.tree -fill both -expand 1
    ttk::scrollbar $w.body.left.treeScroll -orient vertical -command [list $w.body.left.tree yview]
    $w.body.left.tree configure -yscrollcommand [list $w.body.left.treeScroll set]
    place $w.body.left.treeScroll -in $w.body.left.tree -relx 1 -x -15 -y 0 -width 15 -relheight 1
    bind $w.body.left.tree <<TreeviewSelect>> ::GX::InterfaceBuilder::select
    bind $w.body.left.tree <ButtonPress-1> {+::GX::InterfaceBuilder::treePress %x %y}
    bind $w.body.left.tree <B1-Motion> {::GX::InterfaceBuilder::treeMotion %x %y;break}
    bind $w.body.left.tree <ButtonRelease-1> {+::GX::InterfaceBuilder::treeRelease %x %y}
    ttk::label $w.body.center.title -text {Layout map — real widgets are in Preview} -wraplength 300;pack $w.body.center.title -fill x
    ttk::scale $w.body.center.zoom -from .35 -to 1.8 -variable ::GX::InterfaceBuilder::s(zoom) -command {::GX::InterfaceBuilder::draw};pack $w.body.center.zoom -fill x
    canvas $w.body.center.map -background #ffffff -highlightthickness 0 -width 300 -height 400;pack $w.body.center.map -fill both -expand 1
    ttk::scrollbar $w.body.center.vertical -command [list $w.body.center.map yview]
    ttk::scrollbar $w.body.center.horizontal -orient horizontal -command [list $w.body.center.map xview]
    $w.body.center.map configure -yscrollcommand [list $w.body.center.vertical set] -xscrollcommand [list $w.body.center.horizontal set]
    place $w.body.center.vertical -in $w.body.center.map -relx 1 -x -15 -width 15 -relheight 1 -height -15
    place $w.body.center.horizontal -in $w.body.center.map -rely 1 -y -15 -height 15 -relwidth 1 -width -15
    bind $w.body.center.map <ButtonPress-1> {::GX::InterfaceBuilder::mapPress %x %y}
    bind $w.body.center.map <B1-Motion> {::GX::InterfaceBuilder::mapMotion %x %y}
    bind $w.body.center.map <ButtonRelease-1> {::GX::InterfaceBuilder::mapRelease %x %y}
    foreach {id title} {properties Properties api {API / owner} events Events diagnostics Analyzers tests {Automated tests}} {ttk::frame $w.body.right.$id;$w.body.right add $w.body.right.$id -text $title}
    ttk::label $w.body.right.properties.selected -text {};ttk::combobox $w.body.right.properties.key -state readonly -textvariable ::GX::InterfaceBuilder::s(propertyKey)
    ttk::entry $w.body.right.properties.value -textvariable ::GX::InterfaceBuilder::s(propertyValue)
    ::GX::uiFieldSelectorWithinViewer $w.body.right.properties.key $w
    ttk::button $w.body.right.properties.apply -text {Apply property / grid constraint} -command {::GX::InterfaceBuilder::safe propertyApply}
    pack $w.body.right.properties.selected $w.body.right.properties.key $w.body.right.properties.value $w.body.right.properties.apply -fill x -padx 5 -pady 5
    bind $w.body.right.properties.key <<ComboboxSelected>> ::GX::InterfaceBuilder::propertyValue
    bind $w.body.right.properties.value <Return> {::GX::InterfaceBuilder::safe propertyApply}
    ttk::button $w.body.right.api.guide -text {Open public CORE API guide} -command {::GX::InterfaceBuilder::safe apiGuide};pack $w.body.right.api.guide -fill x
    text $w.body.right.api.text -wrap word -width 28 -state disabled;pack $w.body.right.api.text -fill both -expand 1
    ttk::label $w.body.right.events.signature -text {Handler contract: (window, action)};pack $w.body.right.events.signature -fill x
    ttk::entry $w.body.right.events.action -textvariable ::GX::InterfaceBuilder::s(actionId)
    ttk::combobox $w.body.right.events.effect -state readonly -values {unbound presentation mutating} -textvariable ::GX::InterfaceBuilder::s(actionEffect)
    ::GX::uiFieldSelectorWithinViewer $w.body.right.events.effect $w
    ttk::button $w.body.right.events.bind -text {Bind action / change contract} -command {::GX::InterfaceBuilder::safe bindAction}
    pack $w.body.right.events.action $w.body.right.events.effect $w.body.right.events.bind -fill x -padx 5 -pady 3
    ttk::checkbutton $w.body.right.events.capture -text {Capture redacted events} -variable ::GX::InterfaceBuilder::s(traceOn);pack $w.body.right.events.capture -fill x
    ttk::label $w.body.right.events.filterLabel -text {Component / event filters (glob)};pack $w.body.right.events.filterLabel -fill x
    ttk::entry $w.body.right.events.componentFilter -textvariable ::GX::InterfaceBuilder::s(recordComponent);pack $w.body.right.events.componentFilter -fill x
    ttk::entry $w.body.right.events.eventFilter -textvariable ::GX::InterfaceBuilder::s(traceEvent);pack $w.body.right.events.eventFilter -fill x
    ttk::button $w.body.right.events.clear -text {Clear current trace} -command ::GX::InterfaceBuilder::clearTrace;pack $w.body.right.events.clear -fill x
    text $w.body.right.events.trace -wrap word -width 28;pack $w.body.right.events.trace -fill both -expand 1
    ttk::button $w.body.right.diagnostics.measure -text {Measure responsiveness (2 s)} -command {::GX::InterfaceBuilder::safe measure}
    ttk::button $w.body.right.diagnostics.cancelMeasure -text {Cancel measurement} -command {if {[info exists ::GX::InterfaceBuilder::s(monitor)]} {::GX::viewerGuiMonitorCancel $::GX::InterfaceBuilder::s(monitor)}}
    pack $w.body.right.diagnostics.measure $w.body.right.diagnostics.cancelMeasure -fill x
    text $w.body.right.diagnostics.text -wrap word -width 28;pack $w.body.right.diagnostics.text -fill both -expand 1
    ttk::frame $w.body.right.tests.families;pack $w.body.right.tests.families -fill x
    foreach family {structure negative lifecycle scientific} {ttk::checkbutton $w.body.right.tests.families.$family -text [string totitle $family] -variable ::GX::InterfaceBuilder::s(test,$family);pack $w.body.right.tests.families.$family -anchor w}
    ttk::frame $w.body.right.tests.tools;pack $w.body.right.tests.tools -fill x
    foreach {id title method} {plan Plan planTests run {Run plan} runTests selected {Rerun selected} {runTests 1} cancel Cancel cancelTest export {Export JSON…} exportReport} {ttk::button $w.body.right.tests.tools.$id -text $title -command [list ::GX::InterfaceBuilder::safe {*}$method];pack $w.body.right.tests.tools.$id -anchor w -fill x}
    ttk::label $w.body.right.tests.status -textvariable ::GX::InterfaceBuilder::s(testStatus) -wraplength 300 -justify left;pack $w.body.right.tests.status -fill x -padx 3 -pady 4
    ttk::treeview $w.body.right.tests.cases -columns {status result} -show {tree headings} -height 5 -selectmode extended
    $w.body.right.tests.cases heading #0 -text Case;$w.body.right.tests.cases column #0 -width 120
    foreach key {status result} {$w.body.right.tests.cases heading $key -text [string totitle $key];$w.body.right.tests.cases column $key -width 90}
    pack $w.body.right.tests.cases -fill both -expand 1
    ttk::frame $w.body.right.tests.record;pack $w.body.right.tests.record -fill x
    ttk::entry $w.body.right.tests.record.filter -textvariable ::GX::InterfaceBuilder::s(recordComponent) -width 12
    set column 0
    foreach {id title method} {start Record recordStart stop Stop recordStop replay Replay replay save Save… scenarioSave open Open… scenarioOpen} {ttk::button $w.body.right.tests.record.$id -text $title -command [list ::GX::InterfaceBuilder::safe $method];grid $w.body.right.tests.record.$id -row [expr {1+$column/3}] -column [expr {$column%3}] -sticky ew;incr column}
    grid $w.body.right.tests.record.filter -row 0 -column 0 -columnspan 3 -sticky ew
    foreach column {0 1 2} {grid columnconfigure $w.body.right.tests.record $column -weight 1}
    text $w.body.right.tests.scenario -wrap word -height 5 -width 28;pack $w.body.right.tests.scenario -fill both -expand 1
    $w.body.right.tests.scenario insert 1.0 {schema gxtxt.viewer_gui_scenario.v1 actions {{operation checkpoint timeout_ms 1000}}}
    wm protocol $w WM_DELETE_WINDOW {::GX::InterfaceBuilder::safe close}
    ::GX::documentationBrowserAttachViewerHelp viewer.interface_builder interface_builder $w
    refresh;::GX::uiFieldFocusWhenMapped $w $w.body.left.palette 0;raise $w;return $w
}
proc ::GX::InterfaceBuilder::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_interface_builder_tk ::GX::InterfaceBuilder::dispatch
