# SPDX-License-Identifier: GPL-3.0-or-later
# available as hover help without changing button commands.
proc ::GX::plotsToolbarTipHide {} {
    variable plotsToolbarTipAfter
    if {[info exists plotsToolbarTipAfter] && $plotsToolbarTipAfter ne ""} {
        after cancel $plotsToolbarTipAfter
        set plotsToolbarTipAfter ""
    }
    catch {destroy .plotsToolbarTip}
    native2DViewportTooltipHide
}
proc ::GX::plotsToolbarTipShow {widget message} {
    variable plotsToolbarTipAfter
    set plotsToolbarTipAfter ""
    native2DViewportTooltipShow $widget $message
}
proc ::GX::plotsToolbarTipSchedule {widget message} {
    plotsToolbarTipHide
    set ::GX::plotsToolbarTipAfter [after 550 [list ::GX::plotsToolbarTipShow $widget $message]]
}
proc ::GX::plotsToolbarInstallTips {} {
    set b .top.nb.graphs.buttons
    set a .top.nb.graphs.actions
    foreach {widget message} [list         $b.refresh {Refresh plots from the session.}         $b.all {Select all plots.}         $b.none {Clear all plot selections.}         $b.toggle {Toggle the current plot selection.}         $b.up {Move the selected plot up.}         $b.down {Move the selected plot down.}         $b.export {Export selected plots.}         $a.one {Rerender current plot from valid render cache.}         $a.sel {Rerender selected plots.}         $a.mod {Rerender the entire module.}         $a.legend {Configure the selected plot legend.}         $a.pick {Place legend center by clicking the preview.}         $a.axes {Configure axes, grid, ranges and level scales.}         $a.globalgfx {Configure global graphics.}         $a.annotate {Annotate the current plot.}         $a.exportann {Export annotated plots.}         $a.clone {Clone the current plot.}         $a.editclone {Edit the selected clone.}         $a.selectdata {Select plotted source points or areas and publish a keep/exclude Dataset.}         $a.region {Select an area of the current plot.}         $a.clearregion {Clear the selected plot area.}         $a.openfull {Open server PNG at one-to-one pixel size.}         $a.variants {Manage persistent plot variants.}] {
        if {![winfo exists $widget]} continue
        bind $widget <Enter> [list ::GX::plotsToolbarTipSchedule $widget $message]
        bind $widget <Leave> ::GX::plotsToolbarTipHide
        bind $widget <ButtonPress> ::GX::plotsToolbarTipHide
    }
}
proc ::GX::launchGui_before_dataset_page_actions {} {
    ::GX::launchGui_before_toolbar_tips
    plotsToolbarInstallTips
}

# Menus invoke the established widgets: callback identity, shortcuts and all
# existing capability/state updates remain owned by those action widgets.
proc ::GX::plotsToolbarMenuSync {menu widgets} {
    set index 0
    foreach widget $widgets {
        $menu entryconfigure $index -state [expr {[$widget instate disabled] ? "disabled" : "normal"}]
        incr index
    }
}
proc ::GX::plotsToolbarPrimaryLayout {frame controls} {
    if {[winfo exists $frame]} {uiFieldControlsLayout $frame [winfo width $frame] $controls}
}
proc ::GX::plotsToolbarHelp {} {
    tk_messageBox -parent . -title {Plot controls help} -icon info -message [.top.nb.graphs.actionNote cget -text]
}
proc ::GX::plotsPreviewStatusUpdate {args} {
    set label .top.nb.graphs.preview.info
    if {[winfo exists $label] && [info exists ::GX::ui(graphInfo)]} {
        # A view projection only: the full live status remains in its existing
        # owner variable and tooltip, including diagnostics and artifact identity.
        $label configure -text [string map [list \n { · }] $::GX::ui(graphInfo)]
        native2DViewportTooltip $label $::GX::ui(graphInfo)
    }
}
proc ::GX::plotsBrowserStyle {} {
    # Stock themes retain a fixed 20-pixel row even when the configured font is
    # taller. Size only this existing browser's rows; keep column preferences,
    # item identities, selection and the scientific Preview's owners unchanged.
    _uiFieldTreeFontRows .top.nb.graphs.tree GXPlots.Treeview
}
proc ::GX::plotsToolbarOrganize {} {
    set b .top.nb.graphs.buttons
    set a .top.nb.graphs.actions
    set grouped {}
    foreach {key label widgets} [list \
        selection Selection [list $b.all $b.none $b.toggle $b.up $b.down] \
        render Render [list $a.one $a.sel $a.mod] \
        presentation Presentation [list $a.legend $a.pick $a.axes $a.labels $a.globalgfx $a.annotate] \
        data {Data / Variants} [list $a.variants $a.selectdata $a.region $a.clearregion] \
        graph Graph [list $a.openfull $a.clone $a.editclone $a.delete $a.info $a.notes] \
        transport {Import / Export} [list $b.export $a.exportann $a.exportzip $a.importzip]] {
        set found {}
        ttk::menubutton $b.$key -text $label -menu $b.$key.menu
        menu $b.$key.menu -tearoff 0
        foreach widget $widgets {
            if {![winfo exists $widget]} continue
            lappend found $widget
            $b.$key.menu add command -label [$widget cget -text] -command [list $widget invoke]
            pack forget $widget
        }
        $b.$key.menu configure -postcommand [list ::GX::plotsToolbarMenuSync $b.$key.menu $found]
        pack $b.$key -side left -padx 3
        lappend grouped {*}$found
    }
    # Every general command is reachable through the primary groups. Keep the
    # underlying action widgets for their established callbacks/state owners,
    # without a duplicate row consuming the scientific Preview's height.
    foreach separator {sep sep2} {if {[winfo exists $a.$separator]} {pack forget $a.$separator}}
    place forget $a
    grid remove .top.nb.graphs.actionViewport .top.nb.graphs.actionScroll
    grid remove $a .top.nb.graphs.actionNote
    set help [.top.nb.graphs.actionNote cget -text]
    foreach heading {render presentation graph} {native2DViewportTooltip $b.$heading $help}
    $b.graph.menu add separator
    $b.graph.menu add command -label {Plot controls help...} -command ::GX::plotsToolbarHelp
    .top.nb.graphs.preview.info configure -textvariable {} -wraplength 0 -width 1 -anchor w
    pack configure .top.nb.graphs.preview.info -before .top.nb.graphs.preview.img -pady 0
    if {{write ::GX::plotsPreviewStatusUpdate} ni [trace info variable ::GX::ui(graphInfo)]} {trace add variable ::GX::ui(graphInfo) write ::GX::plotsPreviewStatusUpdate}
    plotsPreviewStatusUpdate
    # Honor the page's existing 1:2 browser/Preview weights independently of
    # requested text widths. Long paths must not squeeze the scientific image.
    grid columnconfigure .top.nb.graphs 0 -uniform plotsColumns
    grid columnconfigure .top.nb.graphs 1 -uniform plotsColumns
    ttk::scrollbar .top.nb.graphs.sx -orient horizontal -takefocus 1 -command [list .top.nb.graphs.tree xview]
    foreach event {<<PrevChar>> <<NextChar>> <<PrevWord>> <<NextWord>> <<LineStart>> <<LineEnd>> <Prior> <Next>} {bind .top.nb.graphs.sx $event [bind Scrollbar $event]}
    .top.nb.graphs.tree configure -xscrollcommand [list .top.nb.graphs.sx set]
    plotsBrowserStyle
    bind .top.nb.graphs.tree <<ThemeChanged>> +::GX::plotsBrowserStyle
    .top.nb.graphs.tree heading file -anchor w
    grid .top.nb.graphs.sx -row 5 -column 0 -sticky ew -padx 5
    grid configure .top.nb.graphs.preview -rowspan 2
    # Keep all six established primary groups in this same region at large
    # fonts/narrow sizes. The shared UI Field owner wraps their existing widgets.
    set primary [list $b.refresh $b.selection $b.render $b.presentation $b.data $b.graph $b.transport]
    grid configure $b -sticky ew
    bind $b <Configure> +[list ::GX::plotsToolbarPrimaryLayout $b $primary]
    after idle [list ::GX::plotsToolbarPrimaryLayout $b $primary]
}
