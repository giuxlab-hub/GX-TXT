# GX-TXT optional CORE workspace surfaces.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable coreUiSurfaces [dict create] }

proc ::GX::coreUiSurfaceRegister {id label configId} {
    variable coreUiSurfaces
    if {![regexp {^[a-z][a-z0-9_]*$} $id]} { error "Invalid CORE UI surface ID '$id'." }
    if {![dict exists [configurationFields] $configId]} { error "CORE UI surface '$id' has no Configuration field '$configId'." }
    dict set coreUiSurfaces $id [dict create label $label config_id $configId]
    return $id
}

proc ::GX::coreUiSurfaceVisible {id} {
    variable coreUiSurfaces
    if {![dict exists $coreUiSurfaces $id]} { return 0 }
    return [configurationGet [dict get $coreUiSurfaces $id config_id]]
}

proc ::GX::coreUiSurfaceSet {id visible} {
    variable coreUiSurfaces
    if {![dict exists $coreUiSurfaces $id]} { error "Unknown CORE UI surface '$id'." }
    configurationSet [dict get $coreUiSurfaces $id config_id] $visible
    configurationSave
    catch {rebuildNativeAnalysisGui}
    return [coreUiSurfaceVisible $id]
}

proc ::GX::coreUiSurfaceGuiChanged {id} {
    variable coreUiSurfaces
    set configId [dict get $coreUiSurfaces $id config_id]
    coreUiSurfaceSet $id $::GX::configurationUi($configId)
}

proc ::GX::coreUiSurfaceBuildModulesControls {} {
    variable coreUiSurfaces
    set host .top.nb.modules
    if {![llength [info commands winfo]] || ![winfo exists $host]} return
    catch {destroy $host.surfaces}
    ttk::labelframe $host.surfaces -text "Optional CORE workspace surfaces"
    if {[winfo exists $host.cards]} {
        pack $host.surfaces -before $host.cards -fill x -padx 12 -pady 4
    } else {grid $host.surfaces -row 4 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 4}
    set i 0
    dict for {id info} $coreUiSurfaces {
        ttk::checkbutton $host.surfaces.c$i -text [dict get $info label] \
            -variable ::GX::configurationUi([dict get $info config_id]) \
            -command [list ::GX::coreUiSurfaceGuiChanged $id]
        pack $host.surfaces.c$i -side left -padx 6 -pady 3
        incr i
    }
}

proc ::GX::launchGui_before_toolbar_tips {} {
    ::GX::launchGui_before_core_ui_surfaces
    coreUiSurfaceBuildModulesControls
}

# Final startup initializer; each named predecessor preserves its own state reset.
proc ::GX::defaults {} {
    ::GX::defaults_before_core_ui_surfaces
    set ::GX::cfg(dataset_namespace_current) base
    set ::GX::cfg(dataset_namespace_created) {}
    set ::GX::cfg(dataset_namespace_shared_inputs) {}
    coreUiSurfaceRegister script_workspace {Show Script Workspace} features.script_workspace
}
