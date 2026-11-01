# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative composition adapter. Exact geometry, interaction and History stay
# in the shared Sketch component; authored native Viewers only send action IDs.
proc ::GX::_viewerGuiCadSketchMount {window id parent properties saved} {
    set options [dict remove $properties title]
    if {[dict exists $saved domain_state cad_sketches $id document_id]} {
        dict set options document_id [dict get $saved domain_state cad_sketches $id document_id]
    }
    dict set options changed_command [list ::GX::_viewerGuiCadSketchChanged $window $id]
    set sketch [nativeCadSketchCreate $parent $options]
    pack [$sketch widget] -fill both -expand 1
    dict set ::GX::ViewerGui::instances $window cad_sketches $id $sketch
    if {[datasetPublicationV2DictDefault $properties presentation canvas] eq {canvas}} {
        $sketch canvasControls
    }
    _viewerGuiCadSketchChanged $window $id [$sketch state]
    return $sketch
}
proc ::GX::_viewerGuiCadSketchChanged {window id state} {
    if {![dict exists $::GX::ViewerGui::instances $window]} return
    set domain [viewerGuiDesignContextGet $window]
    # A Workspace references the exact Interactive Document; never serialize a
    # display sample or create a second geometry/History store in Viewer state.
    dict set domain cad_sketches $id [dict create document_id [dict get $state document_id]]
    viewerGuiDesignContextSet $window $domain
    # All predicates belonging to each declared Sketch share one synchronous
    # read. A surrounding component refresh reuses that same scoped snapshot.
    set refresh [list ::GX::viewerGuiActionsRefresh $window]
    dict for {component sketch} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] cad_sketches {}] {
        if {[nativeCadSketchIsManaged $sketch]} {set refresh [list ::GX::_native2DCadWithActionStates $sketch $refresh]}
    }
    return [uplevel #0 $refresh]
}
proc ::GX::_viewerGuiCadSketch {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Sketch Viewer lifetime ended}}
    if {[dict get [viewerGuiDesignComponent $window $component] type] ne {cad_sketch}} {error {Select a declared CAD Sketch component}}
    set sketch [dict get $::GX::ViewerGui::instances $window cad_sketches $component]
    if {![nativeCadSketchIsManaged $sketch]} {error {Sketch has closed}}
    return $sketch
}
proc ::GX::viewerGuiDesignCadCommand {window component action} {
    return [[_viewerGuiCadSketch $window $component] command $action]
}
proc ::GX::viewerGuiDesignCadState {window component {action {}}} {
    set sketch [_viewerGuiCadSketch $window $component]
    if {$action eq {}} {return [$sketch state]}
    return [$sketch actionState $action]
}
proc ::GX::_viewerGuiCadSave {window} {
    dict for {id sketch} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] cad_sketches {}] {$sketch save}
}
proc ::GX::_viewerGuiCadDirty {window} {
    dict for {id sketch} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] cad_sketches {}] {
        if {[nativeCadSketchIsManaged $sketch] && ([$sketch dirty] || [$sketch pending])} {return 1}
    }
    return 0
}
proc ::GX::_viewerGuiCadDispose {window} {
    dict for {id sketch} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] cad_sketches {}] {
        if {[nativeCadSketchIsManaged $sketch]} {$sketch destroy}
    }
}
proc ::GX::_viewerGuiCadBindingState {window pair key} {
    if {[llength $pair]!=2} {return 0}
    lassign $pair component action
    if {[catch {viewerGuiDesignCadState $window $component $action} state]} {return 0}
    return [dict get $state $key]
}
proc ::GX::_viewerGuiCadContextsMount {window} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    foreach definition [dict get $instance design components] {
        if {[dict get $definition type] ne {context_menu} || ![dict exists $definition properties cad_context]} continue
        set target [dict get $definition properties cad_context]
        if {![dict exists $instance cad_sketches $target]} continue
        set sketch [dict get $instance cad_sketches $target]
        # The Viewer chooses these declared commands, including its own domain
        # actions. Canvas-owned panel menus remain available when combined.
        viewerGuiContextMount $window [[$sketch get host] canvas]
    }
}
