# SPDX-License-Identifier: GPL-3.0-or-later
# Three presentations of one Host.Advanced action surface. ViewerCommands owns
# command binding/menu/button state; the shared stock library owns every icon.
namespace eval ::GX::NativeCadSketch {variable mounts {};variable iconAssets {}}
proc ::GX::native2DCadActions {} {
    set result {}
    foreach {id label icon group} {
        select Select select Edit rectangle_selection {Box selection} selection_box Edit
        translate Move pan Edit rotate Rotate rotate Edit mirror Mirror mirror Edit pan Pan pan View
        point Point add_point Create line Line draw_line Create construction_line {Construction line} draw_line Create
        path Path draw_polyline Create polyline Polyline draw_polyline Create spline Spline draw_polyline Create
        rectangle Rectangle draw_rectangle Create circle Circle draw_circle Create arc Arc draw_circle Create
        ellipse Ellipse draw_circle Create quadratic_bezier {Quadratic Bezier} draw_polyline Create cubic_bezier {Cubic Bezier} draw_polyline Create
        join_points {Join points} junction Topology join_path {Join path} link Topology compound Compound group_rows Topology
        separate Separate duplicate Topology split_path {Split path} cut Topology split_composition {Split composition} cut Topology
        dimension Dimension label Relations horizontal Horizontal draw_line Relations vertical Vertical draw_line Relations
        coincident Coincident junction Relations parallel Parallel draw_line Relations perpendicular Perpendicular draw_line Relations
        tangent Tangent draw_circle Relations equal_length {Equal length} draw_line Relations equal_radius {Equal radius} draw_circle Relations fixed Fixed attach Relations
        finish Finish validate View cancel Cancel stop View fit Fit fit View undo Undo undo View redo Redo redo View save Save save View
    } {dict set result $id [dict create label $label icon $icon group $group default {}]}
    dict set result undo default Ctrl+z
    dict set result redo default Ctrl+y
    dict set result save default Ctrl+s
    return $result
}
# Snapshots exist only during one synchronous presentation refresh. They never
# replace native selection, admission, History or the action invocation guard.
proc ::GX::_native2DCadWithActionStates {sketch callback} {
    variable ::GX::NativeCadSketch::actionScopes
    if {![info exists actionScopes]} {set actionScopes {}}
    set owner [expr {![dict exists $actionScopes $sketch]}]
    if {$owner} {dict set actionScopes $sketch {}}
    try {return [uplevel #0 [list {*}$callback]]} finally {
        if {$owner} {dict unset actionScopes $sketch}
    }
}
proc ::GX::_native2DCadActionStatesInvalidate {sketch} {
    variable ::GX::NativeCadSketch::actionScopes
    if {[info exists actionScopes] && [dict exists $actionScopes $sketch]} {dict set actionScopes $sketch {}}
}
proc ::GX::native2DCadActionStates {sketch} {
    variable ::GX::NativeCadSketch::actionScopes
    if {[info exists actionScopes] && [dict exists $actionScopes $sketch]} {
        set states [dict get $actionScopes $sketch]
        if {$states eq {}} {
            set states [_native2DCadActionStatesCollect $sketch]
            dict set actionScopes $sketch $states
        }
        return $states
    }
    return [_native2DCadActionStatesCollect $sketch]
}
proc ::GX::_native2DCadActionStatesCollect {sketch} {
    set catalog [native2DCadActions]
    set live [expr {![catch {$sketch guard}]}]
    if {$live} {
        set host [$sketch get host]
        set construct [dict get [[$host advanced] state] construction]
        set selection [[$host context] selection snapshot]
        set selected [dict get $selection objects];set selectedCount [llength $selected]
        set refs [dict get $selection references];set currentTool [$host tool]
        set family {};set splitPath 0;set splitComposition 0
        if {$selectedCount==1} {
            set definition [[$host context] object definition [lindex $selected 0]]
            set family [dict get $definition family]
            if {$family eq {path}} {set splitPath [expr {[llength [dict get $definition controls]]>=3}]}
            if {$family eq {composite_path}} {set splitComposition [expr {[llength [dict get $definition parts]]>=2}]}
        }
        set joinPoints [expr {$selectedCount==2 && [llength $refs]==2}]
        foreach ref $refs {if {[dict get $ref entity] ne {control}} {set joinPoints 0}}
        set history [scientificHistoryViewerStatus [$sketch get history_context]]
        set cursor [dict get $history cursor];set count [dict get $history count]
    }
    set result {}
    dict for {action descriptor} $catalog {
        set checked 0;set enabled $live
        if {$live} {
            switch -- $action {
                translate - rotate - mirror {set enabled [expr {$selectedCount>0}]}
                join_path - compound {set enabled [expr {$selectedCount>=2}]}
                join_points {set enabled $joinPoints}
                separate {set enabled [expr {$family in {compound composite_path}}]}
                split_path {set enabled $splitPath}
                split_composition {set enabled $splitComposition}
                undo {set enabled [expr {$cursor>0}]}
                redo {set enabled [expr {$cursor<$count}]}
            }
            if {$action in {select pan translate rotate mirror rectangle_selection}} {
                set checked [expr {$currentTool eq [dict get {select select pan pan translate translate rotate rotate mirror mirror rectangle_selection rectangle} $action] && $construct eq {}}]
            }
            if {$construct ne {} && [dict get $construct family] eq $action} {set checked 1}
        }
        dict set result $action [dict merge $descriptor [dict create id $action enabled $enabled checked $checked]]
    }
    return $result
}
proc ::GX::native2DCadActionState {sketch action} {
    set states [native2DCadActionStates $sketch]
    if {![dict exists $states $action]} {error {Unknown shared CAD action}}
    return [dict get $states $action]
}
proc ::GX::native2DCadActionPredicate {sketch action key} {return [dict get [native2DCadActionState $sketch $action] $key]}
proc ::GX::native2DCadActionInvoke {sketch action} {
    # Widget predicates can share a presentation snapshot; execution must always
    # revalidate the current native/Document state independently of that snapshot.
    _native2DCadActionStatesInvalidate $sketch
    set states [_native2DCadActionStatesCollect $sketch]
    if {![dict exists $states $action]} {error {Unknown shared CAD action}}
    if {![dict get $states $action enabled]} {error {CAD action is unavailable in the current selection or lifetime}}
    set host [$sketch get host];set advanced [$host advanced]
    # Toolbars return interaction to their drawing surface. Modal editors may
    # subsequently claim focus; no global Escape/Return binding is installed.
    focus [$host canvas]
    try {
    switch -- $action {
        select - translate - rotate - mirror - pan {$host tool $action}
        rectangle_selection {$host tool rectangle}
        point - line - construction_line - path - polyline - spline - rectangle - circle - arc - ellipse - quadratic_bezier - cubic_bezier {$host tool select;$advanced construction start $action}
        horizontal - vertical - coincident - parallel - perpendicular - tangent - equal_length - equal_radius - fixed {
            set refs [dict get [[$host context] selection snapshot] references]
            $advanced constraint start $action $refs
            set proposal [$advanced constraint state]
            if {[dict get $proposal status] eq {ready}} {$advanced constraint apply 0 [dict get $proposal specification]}
        }
        dimension {$advanced dimension start {} [dict get [[$host context] selection snapshot] references]}
        join_points - join_path - compound - separate - split_path - split_composition {
            set ids [dict get [[$host context] selection snapshot] objects]
            set options {}
            if {$action in {split_path split_composition}} {dict set options index 1}
            if {$action eq {join_points}} {
                set refs [dict get [[$host context] selection snapshot] references]
                if {[llength $refs]!=2} {error {Select two defining point controls}}
                dict set options index [[$host context] control point_index [lindex $refs 0]]
                dict set options target_index [[$host context] control point_index [lindex $refs 1]]
                dict set options tolerance 1e-8
                set ids [list [dict get [lindex $refs 0] object] [dict get [lindex $refs 1] object]]
            }
            set created [$advanced topology apply $action $ids $options]
            if {$action ne {join_points}} {
                set members {};foreach id $created {lappend members [dict create kind object id $id index 0]}
                $host select $members
            }
        }
        finish {
            # Fixed-size tools remain armed after their automatic commit. Finish
            # explicitly exits that mode; an incomplete proposal still reports
            # its native validation error and remains available for correction.
            set construction [dict get [$advanced state] construction]
            $host event key Return
            set remaining [dict get [$advanced state] construction]
            if {$remaining ne {} && [llength [dict get $remaining places]]} {
                # Host dispatch already reports native validation through the
                # owner's error callback. Do not abandon a rejected proposal.
                return [dict create action $action status rejected reason {Construction is incomplete or invalid; correct it or Cancel} document_id [$sketch get document_id] state [$sketch actionState $action]]
            }
            if {$construction ne {}} {$host tool select}
        }
        cancel {$host cancel explicit_cancel}
        fit {$host fit}
        undo - redo {$host cancel history;scientificHistoryViewerNavigate [$sketch get history_context] $action}
        save {$sketch save}
    }
    $host refresh final
    $sketch changed [dict get [native2DCadActions] $action label]
    return [dict create action $action status completed document_id [$sketch get document_id] state [$sketch actionState $action]]
    } finally {_native2DCadActionStatesInvalidate $sketch}
}
proc ::GX::native2DCadPresentationAttach {sketch window} {
    variable ::GX::NativeCadSketch::mounts
    set module framework.native_cad_sketch
    if {![dict exists $::GX::ViewerCommands::catalogs $module]} {viewerCommandCatalogRegister $module [native2DCadActions] {} shortcuts framework}
    set handlers {}
    dict for {id spec} [native2DCadActions] {
        dict set handlers $id [dict create command [list $sketch invoke $id] enabled [list ::GX::native2DCadActionPredicate $sketch $id enabled] checked [list ::GX::native2DCadActionPredicate $sketch $id checked]]
    }
    viewerCommandsAttach $window $module $handlers [list $sketch guard]
    dict set mounts $window $sketch
    bind $window <Destroy> +[list ::GX::native2DCadPresentationDestroyed $window %W]
    return $window
}
proc ::GX::native2DCadPresentationDestroyed {window actual} {
    variable ::GX::NativeCadSketch::mounts
    if {$window eq $actual} {dict unset mounts $window}
}
proc ::GX::native2DCadMenu {sketch menu} {
    return [_native2DCadWithActionStates $sketch [list ::GX::_native2DCadMenuBuild $sketch $menu]]
}
proc ::GX::_native2DCadMenuBuild {sketch menu} {
    # Profiled cold-open cost was repeated helper startup, not CAD geometry.
    # Warm exact existing resources in one bounded public admission operation.
    variable ::GX::NativeCadSketch::iconAssets
    set missing {}
    dict for {id action} [native2DCadActions] {
        set icon [dict get $action icon]
        if {![dict exists $iconAssets $icon] && $icon ni $missing} {lappend missing $icon}
    }
    if {[llength $missing]} {set iconAssets [dict merge $iconAssets [viewerGuiStockIcons $missing {20 24}]]}
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    set owner [$sketch widget]
    if {![dict exists $::GX::ViewerCommands::windows $owner]} {native2DCadPresentationAttach $sketch $owner}
    viewerCommandMenuBatchBegin $owner
    try {
    foreach group {Create Edit Topology Relations View} {
        set sub $menu.[string tolower $group];menu $sub -tearoff 0
        $menu add cascade -label $group -menu $sub
        dict for {id descriptor} [native2DCadActions] {
            if {[dict get $descriptor group] ne $group} continue
            viewerCommandMenuAdd $owner $sub $id
            set asset [native2DCadStockIcon [dict get $descriptor icon]]
            $sub entryconfigure end -image [viewerGuiIconPhoto $asset 20] -compound left
        }
    }
    } finally {viewerCommandMenuBatchEnd $owner}
    return $menu
}
proc ::GX::native2DCadStockIcon {id} {
    variable ::GX::NativeCadSketch::iconAssets
    if {![dict exists $iconAssets $id]} {
        set record [dict get [viewerGuiIconCatalog] icons $id]
        dict set iconAssets $id [viewerGuiIconImport [dict get $record path] [dict get $record title] [dict get $record category] [dict get $record license]]
    }
    return [dict get $iconAssets $id]
}
proc ::GX::native2DCadPalette {sketch parent} {
    set frame $parent.cadPalette[incr ::GX::NativeCadSketch::serial]
    ttk::notebook $frame
    foreach group {Create Edit Topology Relations View} {
        set tab $frame.[string tolower $group];ttk::frame $tab
        $frame add $tab -text $group
        native2DCadPresentationAttach $sketch $tab
        set ids {};dict for {id spec} [native2DCadActions] {if {[dict get $spec group] eq $group} {lappend ids $id}}
        viewerCommandToolbarCreate $tab $tab.tools $ids
        pack $tab.tools -fill x -expand 1
        dict for {id button} [dict get $::GX::ViewerCommands::windows $tab toolbar buttons] {
            set asset [native2DCadStockIcon [dict get [native2DCadActions] $id icon]]
            uiFieldIconApply $button [dict create presentation icon_text icon_size 20 tooltip [dict get [native2DCadActions] $id label]] $asset
        }
    }
    return $frame
}
proc ::GX::native2DCadCanvasControls {sketch {parent {}}} {
    set host [$sketch get host];set canvas [$host canvas];set owner [$sketch widget]
    if {$parent ne {} && $parent ni [list $owner [winfo parent $canvas]]} {error {Canvas-owned controls use their existing ViewportHost; use palette for external placement}}
    set panel [native2DViewportPanelWidget $canvas cad_tools]
    if {[winfo exists $panel]} {native2DViewportPanelShow $canvas cad_tools 1;return $panel.body}
    set frame [native2DViewportPanelCreate $canvas cad_tools {Sketch tools} top-left {max_width 340 max_height 220 min_width 160 priority 0 close 0}]
    if {![dict exists $::GX::ViewerCommands::windows $owner]} {native2DCadPresentationAttach $sketch $owner}
    viewerCommandToolbarCreate $owner $frame.tools {select line circle dimension finish cancel fit undo redo save}
    pack $frame.tools -fill x
    dict for {id button} [dict get $::GX::ViewerCommands::windows $owner toolbar buttons] {
        set asset [native2DCadStockIcon [dict get [native2DCadActions] $id icon]]
        uiFieldIconApply $button [dict create presentation icon_only icon_size 24 tooltip [dict get [native2DCadActions] $id label]] $asset
    }
    ttk::menubutton $frame.commands -text {All CAD actions…} -menu $frame.commands.menu -takefocus 1
    native2DCadMenu $sketch $frame.commands.menu
    pack $frame.commands -anchor w -padx 3 -pady 2
    ttk::label $frame.navigation -text {Space-drag: orbit · +Shift: pan} -wraplength 180 -font TkSmallCaptionFont
    pack $frame.navigation -anchor w -padx 3
    # Same command catalog and predicates in the embedded popup and the panel;
    # no second controller or independent selected/enabled state is introduced.
    bind $canvas <Button-3> +[list ::GX::uiMenuPopup $frame.commands.menu %X %Y]
    return $frame
}
proc ::GX::native2DCadPresentationRefresh {sketch {callback {}}} {
    return [_native2DCadWithActionStates $sketch [list ::GX::_native2DCadPresentationRefresh $sketch $callback]]
}
proc ::GX::_native2DCadPresentationRefresh {sketch callback} {
    variable ::GX::NativeCadSketch::mounts
    dict for {window owner} $mounts {
        if {$owner eq $sketch && [winfo exists $window]} {viewerCommandMenusRefresh $window}
    }
    # A bound trusted presentation callback can refresh authored Viewer controls
    # in this same scope. It must not run a separate scientific operation.
    if {$callback ne {}} {return [uplevel #0 [list {*}$callback]]}
}

proc ::GX::nativeCadSketchIsManaged {handle} {
    return [expr {[info object isa object $handle] && [info object isa typeof $handle ::GX::NativeCadSketch::Component]}]
}
