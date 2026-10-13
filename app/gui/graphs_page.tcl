# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildGraphsPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Graphs tab
    set f .top.nb.graphs
    grid columnconfigure $f 0 -weight 1
    grid columnconfigure $f 1 -weight 2
    grid rowconfigure $f 4 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.refresh -text "Refresh" -command ::GX::refreshGraphs
    ttk::button $f.buttons.all -text "All" -command [list ::GX::setAllGraphs 1]
    ttk::button $f.buttons.none -text "None" -command [list ::GX::setAllGraphs 0]
    ttk::button $f.buttons.toggle -text "Toggle" -command ::GX::toggleGraph
    ttk::button $f.buttons.up -text "Up" -command [list ::GX::moveGraph -1]
    ttk::button $f.buttons.down -text "Down" -command [list ::GX::moveGraph 1]
    ttk::button $f.buttons.export -text "Export..." -command ::GX::exportSelectedGraphs
    pack $f.buttons.refresh $f.buttons.all $f.buttons.none $f.buttons.toggle $f.buttons.up $f.buttons.down $f.buttons.export -side left -padx 3
    grid $f.buttons -row 0 -column 0 -columnspan 2 -sticky w -padx 5 -pady 5
    ttk::frame $f.actions
    ttk::button $f.actions.one -text "Rerender" -command ::GX::rerenderCurrentGraph
    ttk::button $f.actions.sel -text "Rerender selected" -command ::GX::rerenderSelectedGraphs
    ttk::button $f.actions.mod -text "Rerender module" -command ::GX::rerenderCurrentModule
    ttk::separator $f.actions.sep -orient vertical
    ttk::button $f.actions.legend -text "Legend..." -command ::GX::legendConfigDialog
    ttk::button $f.actions.pick -text "Place legend" -command ::GX::beginLegendPick
    ttk::button $f.actions.axes -text "Axes..." -command ::GX::axisConfigDialog
    ttk::button $f.actions.labels -text "Title and labels..." -command ::GX::graphPresentationDialog
    ttk::button $f.actions.info -text "Graph info..." -command ::GX::graphInfoDialog
    ttk::button $f.actions.notes -text "Notes..." -command ::GX::graphNotesOpenCurrent
    ttk::button $f.actions.exportzip -text "Export Graph ZIP..." -command ::GX::portableResourceGuiExportGraph
    ttk::button $f.actions.importzip -text "Import Graph ZIP..." -command [list ::GX::portableResourceGuiImport graph]
    ttk::button $f.actions.globalgfx -text "Graphics..." -command ::GX::globalGraphicsDialog
    ttk::button $f.actions.clone -text "Clone..." -command ::GX::cloneCurrentPlot
    ttk::button $f.actions.editclone -text "Edit clone..." -command ::GX::editCurrentClonedPlot
    ttk::button $f.actions.delete -text "Delete..." -command ::GX::deleteCurrentGraph
    ttk::separator $f.actions.sep2 -orient vertical
    ttk::button $f.actions.openfull -text "Open PNG 1:1" -command ::GX::openCurrentGraphWindow
    pack $f.actions.one $f.actions.sel $f.actions.mod $f.actions.sep $f.actions.legend $f.actions.pick $f.actions.axes $f.actions.labels $f.actions.info $f.actions.notes $f.actions.globalgfx $f.actions.clone $f.actions.editclone $f.actions.delete $f.actions.sep2 $f.actions.openfull $f.actions.exportzip $f.actions.importzip -side left -padx 3
    # Other graph extensions append actions to this frame. At ordinary screen
    # widths the combined toolbar is wider than the window, so keep the full
    # set reachable with a horizontal viewport.
    canvas $f.actionViewport -height 36 -highlightthickness 0
    ttk::scrollbar $f.actionScroll -orient horizontal -command [list ::GX::graphsActionScroll $f]
    $f.actionViewport configure -xscrollcommand [list $f.actionScroll set]
    place $f.actions -in $f.actionViewport -x 0 -y 0
    bind $f.actions <Configure> [list $f.actionViewport configure -scrollregion [list 0 0 %w %h]]
    grid $f.actionViewport -row 1 -column 0 -columnspan 2 -sticky ew -padx 5
    grid $f.actionScroll -row 2 -column 0 -columnspan 2 -sticky ew -padx 5
    raise $f.actions $f.actionViewport
    ttk::label $f.actionNote -text "Rerender uses valid render caches where available. Axes... controls units, grid and panel axes. Clone... preserves the selected graph in Session-owned storage. Rendered-only Clones can be exported; presentation editing requires a scientific Clone."
    grid $f.actionNote -row 3 -column 0 -columnspan 2 -sticky w -padx 8 -pady {0 3}
    ttk::treeview $f.tree -columns {use module file} -show headings -selectmode browse
    $f.tree heading use -text "Use"; $f.tree column use -width 50 -anchor center -stretch 0
    $f.tree heading module -text "Module"; $f.tree column module -width 150 -stretch 0
    $f.tree heading file -text "Plot"; $f.tree column file -width 430
    ttk::scrollbar $f.sy -orient vertical -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.sy set]
    grid $f.tree -row 4 -column 0 -sticky nsew -padx {5 0} -pady 5
    grid $f.sy -row 4 -column 0 -sticky nse -pady 5
    ttk::frame $f.preview
    canvas $f.preview.img -highlightthickness 0 -background #d9d9d9
    ttk::button $f.preview.img.interactive -text {3D} -width 3 -command ::GX::native3DPreviewPlotActivate
    ::GX::native2DViewportTooltip $f.preview.img.interactive {Open interactive scientific 3D preview}
    set ui(graphInfo) "Select a plot."
    ttk::label $f.preview.info -textvariable ::GX::ui(graphInfo) -wraplength 700 -justify left
    pack $f.preview.img -side top -fill both -expand 1
    pack $f.preview.info -side bottom -fill x -pady 4
    grid $f.preview -row 4 -column 1 -sticky nsew -padx 5 -pady 5
    set ui(graphTree) $f.tree
    set ui(graphPreview) $f.preview.img
    bind $f.tree <<TreeviewSelect>> {::GX::previewGraph}
    bind $f.tree <Double-1> {::GX::toggleGraph}
    bind $f.preview.img <Configure> {::GX::onGraphPreviewConfigure %w %h}
    bind $f.preview.img <Double-1> {::GX::openCurrentGraphWindow}

}

proc ::GX::graphsActionScroll {f args} {
    $f.actionViewport xview {*}$args
    place configure $f.actions -x [expr {-round([$f.actionViewport canvasx 0])}]
}
