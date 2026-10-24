# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D semantic document bindings share the existing Viewer state/history.
proc ::GX::viewerGuiDesignDiagramToolBindings {design} {
    set definitions {};set result {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {![dict exists $p diagram_tool]} continue
        if {[dict get $c type] ne {action} || [llength [dict get $p diagram_tool]]!=2} {error {Diagram tool binding requires an action and a component/tool pair}}
        lassign [dict get $p diagram_tool] target tool
        if {![dict exists $definitions $target] || [dict get $definitions $target type] ne {native2d}} {error {Diagram tool binding must target a Native2D component in this design}}
        set catalog [datasetPublicationV2DictDefault [dict get $definitions $target properties] diagram_catalog {}]
        if {$catalog eq {}} {error {Diagram tool binding requires a declared diagram catalog}}
        set symbols [dict get [native2DGeometryDiagramCatalog $catalog] symbols]
        if {$tool ni {select wire junction label pan probe} && ![dict exists $symbols $tool]} {error {Tool binding is outside the declared diagram catalog}}
        set action [dict get $p action];set pair [list $target $tool]
        if {[dict exists $result $action] && [dict get $result $action] ne $pair} {error {One action cannot represent conflicting diagram tools}}
        if {[dict exists $p component_visibility]} {error {A diagram tool action cannot also toggle component visibility}}
        dict set result $action $pair
    }
    return $result
}
proc ::GX::viewerGuiDesignDiagramToolChecked {window component tool} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window widgets $component]} {return 0}
    set viewport [dict get $::GX::ViewerGui::instances $window widgets $component].diagram
    if {![winfo exists $viewport]} {return 0}
    return [expr {[dict get [native2DGeometryDiagramViewportDescribe $viewport 0] tool] eq $tool}]
}
proc ::GX::viewerGuiDesignDiagramSet {window component {document {}} {snapshot {}} {viewState {}}} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer belongs to a previous Session lifetime}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $definition properties] diagram_catalog {}] eq {}} {error {Declare a Native2D diagram_catalog in Interface Builder}}
    set catalog [dict get $definition properties diagram_catalog]
    set instance [dict get $::GX::ViewerGui::instances $window]
    set created [expr {$document eq {}}]
    if {$created} {set owner [native2DGeometryDiagramCreate [dict get $instance module] [dict get $instance provider] $catalog];set document [dict get $owner id]}
    set owner [native2DGeometryDiagramRead $document]
    if {[dict get $owner payload catalog] ne $catalog || [dict get $owner module_id] ne [dict get $instance module]} {error {Diagram catalog or module ownership differs from this Viewer}}
    if {$snapshot ne {} && [dict get $owner payload] ne $snapshot} {
        if {![dict exists $instance bindings $component document_receipt]} {error {Saved diagram differs from current authority; reopen its current document explicitly}}
        set expected [dict get $instance bindings $component document_receipt]
        native2DGeometryDiagramEdit $document $expected restore [dict create payload $snapshot]
        set owner [native2DGeometryDiagramRead $document]
    }
    set widget [dict get $instance widgets $component]
    foreach child [winfo children $widget] {destroy $child}
    native2DGeometryDiagramViewportCreate $widget.diagram $document [list ::GX::_viewerGuiDiagramEvent $window $component]
    pack $widget.diagram -fill both -expand 1
    if {$viewState ne {}} {
        set token [dict get $::GX::Native2DDiagram::viewports $widget.diagram projection scene_token]
        native2DGeometryCall $token view_state [dict create view_state $viewState]
    }
    dict set ::GX::ViewerGui::instances $window bindings $component [dict create kind diagram document_id $document document_receipt [dict remove $owner payload] payload [dict get $owner payload]]
    viewerGuiActionsRefresh $window
    if {$created && ![dict get $instance restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {New diagram}}
    return $widget.diagram
}
proc ::GX::viewerGuiDesignDiagramCommand {window component operation args} {
    if {![viewerGuiDesignGuard $window]} {error {Viewer belongs to a previous Session lifetime}}
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component]} {viewerGuiDesignDiagramSet $window $component}
    if {[dict get $::GX::ViewerGui::instances $window bindings $component kind] ne {diagram}} {error {Component is bound to another scientific source}}
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component].diagram
    return [native2DGeometryDiagramViewportCommand $widget $operation {*}$args]
}
proc ::GX::_viewerGuiDiagramEvent {window component widget event} {
    if {![viewerGuiDesignGuard $window]} return
    if {[dict get $event event] eq {before_edit}} {
        if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {return -code error -errorcode {GX HISTORY EDIT_CANCELLED} {Diagram edit cancelled before changing the document}}
        return
    }
    set owner [native2DGeometryDiagramRead [dict get $event document id]]
    dict set ::GX::ViewerGui::instances $window bindings $component document_receipt [dict remove $owner payload]
    dict set ::GX::ViewerGui::instances $window bindings $component payload [dict get $owner payload]
    set kind [dict get $event event]
    if {$kind eq {probe}} {
        foreach definition [dict get $::GX::ViewerGui::instances $window design components] {
            set p [dict get $definition properties]
            if {[dict get $definition type] eq {section} && [datasetPublicationV2DictDefault $p scientific_probe_diagram {}] eq $component} {
                viewerGuiDesignScientificProbe $window [dict get $definition id] [dict get $event detail endpoint] [dict get $event detail]
            }
        }
    }
    viewerGuiTraceEmit $window $component $kind [dict create status accepted document_id [dict get $owner id] revision [dict get $owner revision] detail [dict get $event detail]]
    if {$kind eq {committed} && ![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window "Diagram [dict get $event detail operation]"}
    viewerGuiActionsRefresh $window
}
