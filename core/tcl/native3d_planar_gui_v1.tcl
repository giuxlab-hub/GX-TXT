# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::PlanarGUI {variable document {};variable unit m;variable tolerance 0.000001;variable mode section}
proc ::GX::native3DPlanarDialog {} {
    set w .native3d_planar
    if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w {Working plane — 2D ↔ 3D}
    ttk::label $w.help -text {Select a source layer in the modern Viewer. Its working-plane fields define the physical section and projection.} -wraplength 570
    pack $w.help -fill x -padx 8 -pady 5
    foreach {key label} {unit {Source coordinate unit} tolerance {Section/join tolerance in that unit}} {
        ttk::label $w.${key}Label -text $label;ttk::entry $w.$key -textvariable ::GX::PlanarGUI::$key
        pack $w.${key}Label $w.$key -fill x -padx 8
    }
    ttk::button $w.create -text {Create from selected source and working plane} -command [list ::GX::Engine3D::showError ::GX::PlanarGUI::create]
    pack $w.create -fill x -padx 8 -pady 5
    ttk::label $w.savedLabel -text {Saved scientific workflow}
    ttk::combobox $w.saved -state readonly -textvariable ::GX::PlanarGUI::document
    pack $w.savedLabel $w.saved -fill x -padx 8
    ttk::frame $w.views;pack $w.views -fill x -padx 8 -pady 5
    foreach {mode label} {source Source all {Plane + results} section Section projection Projection reference {Plane-normal view} accepted {Accepted result}} {
        ttk::button $w.views.$mode -text $label -command [list ::GX::Engine3D::showError [list ::GX::PlanarGUI::show $mode]]
        pack $w.views.$mode -side left -padx 2
    }
    ttk::frame $w.edit;pack $w.edit -fill x -padx 8 -pady 5
    foreach mode {section projection} {
        ttk::button $w.edit.$mode -text "Edit $mode in Curve Workbench" -command [list ::GX::Engine3D::showError [list ::GX::PlanarGUI::edit $mode]]
        pack $w.edit.$mode -side left -padx 2
    }
    ::GX::PlanarGUI::refresh
    return $w
}
proc ::GX::PlanarGUI::refresh {} {
    variable document
    set ids {};foreach item [::GX::native3DPlanarList] {lappend ids [dict get $item id]}
    .native3d_planar.saved configure -values $ids
    if {$document ni $ids} {set document [lindex $ids end]}
}
proc ::GX::PlanarGUI::create {} {
    variable document;variable unit;variable tolerance
    set id $::GX::Engine3D::selectedLayer
    if {$id eq {}} {error {Select a source geometry layer in the modern Viewer}}
    set layer [::GX::viewerLayerGet viewer.engine_3d engine_3d $id]
    if {[dict get $layer source_mode] ne "artifact"} {error {Import the complete scientific geometry as an artifact before plane extraction}}
    set source [::GX::viewerArtifactResolve [dict get $layer resource_path] [dict get $layer sha256]]
    set plane [dict create origin [split $::GX::Engine3D::planeOrigin {;}] normal [split $::GX::Engine3D::planeNormal {;}] u_axis [split $::GX::Engine3D::planeU {;}]]
    set document [::GX::native3DPlanarCreate $source $unit $plane $tolerance [dict create color_array [dict get $layer color_array]]]
    refresh
}
proc ::GX::PlanarGUI::show {mode} {
    variable document
    if {$document eq {}} {error {Choose a saved scientific workflow}}
    ::GX::native3DPlanarShow $document $mode
}
proc ::GX::PlanarGUI::edit {mode} {
    variable document
    if {$document eq {}} {error {Choose a saved scientific workflow}}
    return [::GX::viewerOpen viewer.curve_workbench curve_workbench [dict create workspace_id new workspace_name "3D $document $mode" planar_document $document planar_mode $mode]]
}

proc ::GX::native3DPlanarGuiSelection {document pick} {
    if {[llength [info commands ::GX::CurveWorkbench::planarSelectFrom3D]]} {::GX::CurveWorkbench::planarSelectFrom3D $document $pick}
}
proc ::GX::native3DPlanarFocus {document mode contour} {
    if {$mode ni {section projection accepted}} {error {Unknown planar feature collection}}
    set owner [::GX::_native3DPlanarOwner $document]
    if {[::GX::Engine3D::ownerModule] ne "viewer.engine_3d"} {error {Modern Viewer is not the active host}}
    set layer ${document}_$mode
    if {![dict get [viewerLayerGet viewer.engine_3d engine_3d $layer] visible]} {error {Related 3D layer is hidden}}
    set path [::GX::Engine3D::tempPng]
    set receipt [::GX::Engine3D::rpc [list focus_logical [dict create layer_id $layer association cell logical_id $contour] $path]]
    ::GX::Engine3D::displayNativePng $path
    return $receipt
}
