# SPDX-License-Identifier: GPL-3.0-or-later
# Typed selection of the existing Native2D component's semantic edit profile.
namespace eval ::GX::InterfaceBuilder {variable diagram;array set diagram {catalog {} slot {} component {}}}
proc ::GX::InterfaceBuilder::diagramProfile {} {
    variable s;variable diagram
    set selected {}
    foreach item [dict get [design] components] {if {[dict get $item id] eq $s(selected)} {set selected $item;break}}
    if {$selected eq {} || [dict get $selected type] ne {native2d}} {error {Select a Native2D viewport component first}}
    set diagram(component) $s(selected)
    set diagram(catalog) [::GX::datasetPublicationV2DictDefault [dict get $selected properties] diagram_catalog {}]
    set diagram(slot) [::GX::datasetPublicationV2DictDefault [dict get $selected properties] document_slot $s(selected)]
    set w .gxInterfaceDiagramProfile
    if {[winfo exists $w]} {destroy $w}
    toplevel $w;wm title $w {Native2D diagram profile};wm transient $w .gxInterfaceDesigner
    ttk::frame $w.fields -padding 12;pack $w.fields -fill both -expand 1
    ttk::label $w.fields.label -text {Shared symbol catalog}
    ttk::combobox $w.fields.catalog -state readonly -values [concat [list {}] [dict keys [::GX::native2DGeometryDiagramCatalog]]] -textvariable ::GX::InterfaceBuilder::diagram(catalog)
    ttk::label $w.fields.slotlabel -text {Document slot identity}
    ttk::entry $w.fields.slot -textvariable ::GX::InterfaceBuilder::diagram(slot)
    grid $w.fields.label $w.fields.catalog -sticky ew -padx 4 -pady 5
    grid $w.fields.slotlabel $w.fields.slot -sticky ew -padx 4 -pady 5
    grid columnconfigure $w.fields 1 -weight 1
    ttk::label $w.info -text {The current Native2D component edits a canonical Interactive Document. Pins and junctions connect explicitly; crossing geometry alone does not connect. Add Workspace and History components for their standard save/reopen and Undo/Redo controls. A Session is required to open an actual diagram.} -wraplength 490 -justify left
    pack $w.info -fill x -padx 16 -pady 8
    ttk::frame $w.actions;pack $w.actions -fill x -padx 12 -pady 8
    ttk::button $w.actions.apply -text {Apply profile} -command {::GX::InterfaceBuilder::safe diagramProfileApply}
    ttk::button $w.actions.preview -text {Open diagram in Preview} -command {::GX::InterfaceBuilder::safe diagramProfilePreview}
    ttk::button $w.actions.close -text Close -command [list destroy $w]
    pack $w.actions.apply $w.actions.preview $w.actions.close -side left -padx 4
    return $w
}
proc ::GX::InterfaceBuilder::diagramProfileApply {} {
    variable diagram
    apply properties $diagram(component) [dict create diagram_catalog $diagram(catalog) document_slot $diagram(slot)]
}
proc ::GX::InterfaceBuilder::diagramProfilePreview {} {
    variable diagram
    diagramProfileApply
    ::GX::viewerGuiDesignDiagramSet .gxInterfacePreview $diagram(component)
    raise .gxInterfacePreview
}
