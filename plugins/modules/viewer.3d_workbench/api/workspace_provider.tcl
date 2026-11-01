# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] workspace_native.tcl]
namespace eval ::GX::Workbench3D {variable workspacePresentation {};variable workspaceDiscard 0;variable workspaceClosing 0}
proc ::GX::Workbench3D::workspaceOpen {id} {
    ::GX::sessionWorkspaceValidate $id
    ::GX::modulePublicApiActivate viewer.3d_workbench WORKBENCH_3D_API_v1
    return [::GX::viewerOpen viewer.3d_workbench workbench_3d [dict create workspace_id $id]]
}
proc ::GX::Workbench3D::workspacePresentationCapture {} {
    set result {};foreach key {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool} {dict set result $key [set ::GX::Workbench3D::$key]}
    dict set result view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    return $result
}
proc ::GX::Workbench3D::workspaceDirty {} {
    variable scene;variable historyContext;variable workspacePresentation
    if {$scene eq {}} {return 0}
    if {$historyContext ne {} && [dict exists $::GX::ScientificHistory::viewers $historyContext] && [dict get $::GX::ScientificHistory::viewers $historyContext dirty]} {return 1}
    return [expr {[workspacePresentationCapture] ne $workspacePresentation}]
}
proc ::GX::Workbench3D::workspacePrepare {action} {
    variable scene;variable busy;variable preview;variable historyContext
    if {$scene eq {}} {return}
    ::GX::native3DGeometrySceneInfo $scene
    if {$busy || $::GX::Engine3D::workerBusy || $preview ne {}} {error {Finish or cancel the current 3D operation or preview before changing Workspace}}
    if {$action ne {query} && [dict get $::GX::ScientificHistory::viewers $historyContext browsing]} {error {Return History to Latest before changing Workspace}}
}
proc ::GX::Workbench3D::workspaceCloseHost {} {
    variable workspaceDiscard;variable workspaceClosing
    set workspaceDiscard 1;set workspaceClosing 1
    try {::GX::Engine3D::close} finally {set workspaceClosing 0;set workspaceDiscard 0}
}
proc ::GX::Workbench3D::workspaceCallbacks {} {return [dict create current {set ::GX::Workbench3D::document} save ::GX::Workbench3D::checkpoint open ::GX::Workbench3D::workspaceOpenAction close ::GX::Workbench3D::close discard ::GX::Workbench3D::workspaceCloseHost dirty ::GX::Workbench3D::workspaceDirty prepare ::GX::Workbench3D::workspacePrepare]}
proc ::GX::Workbench3D::workspaceOpenAction {context} {
    set id [dict get $context workspace_id]
    if {$id eq {new}} {return [::GX::viewerOpen viewer.3d_workbench workbench_3d $context]}
    return [workspaceOpen $id]
}
proc ::GX::Workbench3D::workspaceMenuAttach {parent} {
    if {![winfo exists $parent] || [winfo exists $parent.nativeWorkspace]} {return}
    set top [winfo toplevel $parent]
    set bar [$top cget -menu]
    if {$bar eq {}} {set bar $top.workspaceBar;menu $bar -tearoff 0;$top configure -menu $bar}
    menu $parent.nativeWorkspace -tearoff 0
    $bar add cascade -label {3D Workspace} -menu $parent.nativeWorkspace
    ::GX::sessionWorkspaceViewerMenu $parent.nativeWorkspace workbench_3d [workspaceCallbacks] $parent
}
