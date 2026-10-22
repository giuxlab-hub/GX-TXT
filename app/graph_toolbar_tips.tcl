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
proc ::GX::plotsToolbarOrganize {} {
    set b .top.nb.graphs.buttons
    set a .top.nb.graphs.actions
    set grouped {}
    foreach {key label widgets} [list \
        selection Selection [list $b.all $b.none $b.toggle $b.up $b.down] \
        render Render [list $a.sel $a.mod] \
        presentation Presentation [list $a.legend $a.pick $a.axes $a.labels $a.globalgfx $a.annotate] \
        data {Data / Variants} [list $a.variants $a.selectdata $a.region $a.clearregion] \
        graph Graph [list $a.clone $a.editclone $a.delete $a.info $a.notes] \
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
    # Frequent operations remain directly accessible on the second compact row.
    foreach separator {sep sep2} {if {[winfo exists $a.$separator]} {pack forget $a.$separator}}
    place forget $a
    grid remove .top.nb.graphs.actionViewport .top.nb.graphs.actionScroll
    grid $a -row 1 -column 0 -columnspan 2 -sticky w -padx 5 -pady 3
    .top.nb.graphs.actionNote configure -wraplength 880
}
