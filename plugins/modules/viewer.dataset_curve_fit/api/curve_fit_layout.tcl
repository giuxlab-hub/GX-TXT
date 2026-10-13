# SPDX-License-Identifier: GPL-3.0-or-later
# Layout only: existing widgets, commands, Native canvas and numerical state.
proc ::GX::DatasetCurveFit::_menuWidget {menu widget} {
    $menu add command -label [$widget cget -text] -command [$widget cget -command]
}
proc ::GX::DatasetCurveFit::_menuStates {menu widgets} {
    set i 0
    foreach widget $widgets {
        set state [expr {[$widget cget -state] eq "disabled" ? "disabled" : "normal"}]
        $menu entryconfigure $i -state $state
        incr i
    }
}
proc ::GX::DatasetCurveFit::_layout {w} {
    variable state
    foreach child [winfo children $w] {pack forget $child}
    ttk::frame $w.menus -padding 4;pack $w.menus -side top -fill x
    foreach {category widgets} [list \
        Sources [list $w.samples.load $w.samples.publish $w.filter.load $w.filter.cancel $w.workspace.actions.show $w.workspace.actions.hide $w.workspace.actions.style $w.workspace.actions.remove $w.workspace.actions.reload $w.workspace.actions.reverse $w.workspace.actions.span] \
        Fit [list $w.actions.preview $w.actions.accept $w.settings.parametric $w.settings.polar $w.workspace.actions.preview $w.workspace.actions.accept] \
        Selection [list $w.actions.clear $w.selection.remove] \
        Results [list $w.actions.publish $w.actions.export $w.accepted.visibility $w.accepted.delete $w.accepted.publish] \
        View [list $w.selection.zoomin $w.selection.zoomout $w.selection.reset $w.presentation.settings]] {
        set name [string tolower $category]
        ttk::menubutton $w.menus.$name -text $category -menu $w.menus.$name.menu
        menu $w.menus.$name.menu -tearoff 0 -postcommand [list ::GX::DatasetCurveFit::_menuStates $w.menus.$name.menu $widgets]
        foreach widget $widgets {_menuWidget $w.menus.$name.menu $widget}
        pack $w.menus.$name -side left -padx 3
    }
    ttk::menubutton $w.menus.workspace -text Workspace -menu $w.menus.workspace.menu
    menu $w.menus.workspace.menu -tearoff 0
    ::GX::sessionWorkspaceViewerMenu $w.menus.workspace.menu dataset_curve_fit [dict create current [list ::GX::DatasetCurveFit::_currentWorkspace $w] save [list ::GX::DatasetCurveFit::_saveState $w] close [list ::GX::DatasetCurveFit::_closeWindow $w] open ::GX::DatasetCurveFit::open] $w
    pack $w.menus.workspace -side left -padx 3
    pack $w.actions -side top -fill x
    foreach child [winfo children $w.actions] {pack forget $child}
    $w.actions.accept configure -text Accept
    foreach child {preview accept} {pack $w.actions.$child -side left -padx 4}
    bind $w.actions <Configure> [list ::GX::native2DToolbarLayout $w.actions %w [list $w.actions.preview $w.actions.accept]]
    ttk::panedwindow $w.main -orient horizontal;pack $w.main -fill both -expand 1
    ttk::frame $w.left -width 370
    ttk::frame $w.right
    $w.main add $w.left -weight 0;$w.main add $w.right -weight 1
    ttk::scrollbar $w.left.scroll -command [list $w.left.viewport yview]
    canvas $w.left.viewport -width 350 -highlightthickness 0
    $w.left.viewport configure -yscrollcommand [list $w.left.scroll set]
    ttk::frame $w.left.viewport.content -padding 4
    $w.left.viewport create window 0 0 -window $w.left.viewport.content -anchor nw -tags content
    bind $w.left.viewport <Configure> [list $w.left.viewport itemconfigure content -width %w]
    bind $w.left.viewport.content <Configure> [list $w.left.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $w.left.scroll -side right -fill y;pack $w.left.viewport -fill both -expand 1
    set p $w.left.viewport.content
    foreach {group label widgets} [list source {Dataset and variables} [list $w.source] \
        sources {Source curves} [list $w.workspace] filters {Filters (AND)} [list $w.filter $w.filters] \
        settings {Fit model and configuration} [list $w.settings $w.parameters] \
        selection {Point selection} [list $w.selection] accepted {Accepted fits} [list $w.accepted $w.fits] \
        samples {Built-in samples} [list $w.samples] presentation {View and residuals} [list $w.presentation]] {
        ttk::labelframe $p.$group -text $label -padding 4;pack $p.$group -fill x -pady 4
        foreach widget $widgets {pack $widget -in $p.$group -fill x;raise $widget}
    }
    foreach {column width} {id 90 kind 90 identity 160 variables 150 rows 95 visible 120} {$w.workspace.sources column $column -width $width -stretch 0}
    # Infrequent actions stay in their existing widgets, invoked by grouped menus.
    foreach frame {workspace.actions accepted} {pack forget $w.$frame}
    foreach widget {add remove load title} {pack forget $w.filter.$widget}
    pack $w.filter.load -side bottom -fill x
    pack $w.filter.add $w.filter.remove -side bottom -fill x
    foreach widget {remove zoomin zoomout reset help} {pack forget $w.selection.$widget}
    foreach widget {settings coordinates split} {pack forget $w.presentation.$widget}
    ttk::frame $w.right.plot;pack $w.right.plot -fill both -expand 1
    pack $w.canvas -in $w.right.plot -fill both -expand 1 -padx 4 -pady 4;raise $w.canvas
    ttk::frame $w.right.residuals;pack $w.right.residuals -side bottom -fill x
    ttk::frame $w.right.report;pack $w.right.report -side bottom -fill x
    pack $w.result -in $w.right.report -fill x -padx 5;raise $w.result
    bind $w.right.report <Configure> [list $w.result configure -wraplength %w]
    ttk::frame $w.footer;pack $w.footer -side bottom -fill x -before $w.main
    pack $w.status -in $w.footer -fill x;raise $w.status
    ttk::label $w.coordinateReadout -textvariable ::GX::DatasetCurveFit::state($w,coordinates)
    pack $w.coordinateReadout -in $w.footer -fill x
    $w.status configure -wraplength 950
    $w.result configure -wraplength 650
    foreach f {source samples filter settings parameters selection presentation} {
        foreach child [winfo children $w.$f] {bind $child <FocusIn> +[list ::GX::uiFieldScrollSee $w.left.viewport $p $child]}
    }
    foreach {frame children} {filter {variable operator value add remove load cancel} selection {l_mode mode} presentation {residuals split}} {
        set widgets [lmap child $children {format %s.%s.%s $w $frame $child}]
        foreach widget [winfo children $w.$frame] {pack forget $widget;grid forget $widget}
        bind $w.$frame <Configure> [list ::GX::native2DToolbarLayout $w.$frame %w $widgets]
    }
    _residualPanelLayout $w
    bind $w.left.viewport <Button-4> [list $w.left.viewport yview scroll -3 units]
    bind $w.left.viewport <Button-5> [list $w.left.viewport yview scroll 3 units]
    bind $w <Control-s> [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_saveState $w]]
    bind $w.main <Map> [list after idle [list ::GX::DatasetCurveFit::_layoutSash $w]]
    after idle [list ::GX::DatasetCurveFit::_layoutSash $w]
}
proc ::GX::DatasetCurveFit::_layoutSash {w} {
    if {[winfo exists $w.main]} {$w.main sashpos 0 [expr {min(390,max(300,[winfo width $w]/3))}]}
}
proc ::GX::DatasetCurveFit::_residualPanelLayout {w} {
    variable state
    if {![winfo exists $w.right.residuals]} return
    if {$state($w,showResiduals)} {
        pack $w.residualPager -in $w.right.residuals -side bottom -fill x
        pack $w.residuals -in $w.right.residuals -fill x;raise $w.residuals;raise $w.residualPager
    } else {pack forget $w.residuals $w.residualPager}
}
