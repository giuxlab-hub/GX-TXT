# SPDX-License-Identifier: GPL-3.0-or-later
# Tk clipping follows actual ancestors, not pack -in geometry alone.
proc ::GX::DatasetCurveFit::_widget {w logical} {
    set paths {source source.body workspace sources.body filter filters.controls filters filters.list settings settings.body parameters settings.parameters selection selection.body accepted accepted.actions fits accepted.list samples samples.body presentation presentation.body}
    if {[dict exists $paths $logical]} {return $w.left.viewport.content.[dict get $paths $logical]}
    if {$logical eq "workspace.actions"} {return $w.left.viewport.content.sources.body.actions}
    if {$logical eq "residualPager"} {return $w.right.residuals.pager}
    return $w.$logical
}
proc ::GX::DatasetCurveFit::_layoutPrepare {w} {
    ttk::frame $w.footer
    ttk::panedwindow $w.main -orient horizontal
    ttk::frame $w.left -width 370;ttk::frame $w.right
    $w.main add $w.left -weight 0;$w.main add $w.right -weight 1
    canvas $w.left.viewport -width 350 -highlightthickness 0 -yscrollcommand [list $w.left.scroll set]
    ttk::scrollbar $w.left.scroll -command [list $w.left.viewport yview]
    ttk::frame $w.left.viewport.content -padding 4
    $w.left.viewport create window 0 0 -window $w.left.viewport.content -anchor nw -tags content
    bind $w.left.viewport <Configure> [list $w.left.viewport itemconfigure content -width %w]
    bind $w.left.viewport.content <Configure> [list $w.left.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $w.left.scroll -side right -fill y;pack $w.left.viewport -fill both -expand 1
    dict for {group field} [_panelFields] {ttk::labelframe $w.left.viewport.content.$group -text [dict get $field label] -padding 4}
    ttk::frame $w.right.plot;ttk::frame $w.right.residuals;canvas $w.right.report -height 200 -width 1 -highlightthickness 0
    _reportViewportCreate $w
    pack $w.right.residuals -side bottom -fill x
    pack $w.right.plot -fill both -expand 1
}
proc ::GX::DatasetCurveFit::_menuStates {w menu widgets} {
    set i 0
    foreach widget $widgets {
        set enabled [expr {[$widget cget -state] ne "disabled" && ([_historyEditable $w] || [string match *.cancel $widget])}]
        $menu entryconfigure $i -state [expr {$enabled ? "normal" : "disabled"}];incr i
    }
    ::GX::viewerCommandMenusRefresh $w
}
proc ::GX::DatasetCurveFit::_layout {w} {
    variable state
    foreach child [winfo children $w] {pack forget $child}
    ttk::frame $w.menus -padding 4;pack $w.menus -side top -fill x
    _commandsAttach $w
    foreach {category names} {Sources {samples.load samples.publish filter.load filter.cancel workspace.actions.show workspace.actions.hide workspace.actions.style workspace.actions.remove workspace.actions.reload workspace.actions.reverse workspace.actions.span} Fit {actions.preview actions.accept settings.parametric settings.polar workspace.actions.preview workspace.actions.accept} Selection {actions.clear selection.remove} Results {actions.publish actions.export accepted.visibility accepted.delete accepted.publish} View {selection.zoomin selection.zoomout selection.reset presentation.settings}} {
        set button $w.menus.[string tolower $category];set menu $button.menu
        ttk::menubutton $button -text $category -menu $menu
        menu $menu -tearoff 0
        set widgets {}
        foreach name $names {
            set parts [split $name .];set widget [_widget $w [lindex $parts 0]]
            if {[llength $parts]>1} {append widget .[join [lrange $parts 1 end] .]}
            lappend widgets $widget
            set id [string map {. _} $name]
            if {$name in {actions.preview actions.accept}} {set id [lindex $parts 1]}
            ::GX::viewerCommandMenuAdd $w $menu $id
        }
        $menu configure -postcommand [list ::GX::DatasetCurveFit::_menuStates $w $menu $widgets]
        pack $button -side left -padx 3
    }
    $w.menus.fit.menu add separator
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu model_card
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu translation
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu statistics_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu bootstrap_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu profile_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu solver_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu smoothing_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu component_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu formula_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu knot_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu rational_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu implicit_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu complex_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu surface_workflow
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu parameter_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu region_settings
    foreach command {registered_settings registered_declare registered_cancel} {::GX::viewerCommandMenuAdd $w $w.menus.fit.menu $command}
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu covariance_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu model_suggestions
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu baseline_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu smooth_source
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu log_settings
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu log_publish
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu log_details
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu family_sources
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu global_family
    ::GX::viewerCommandMenuAdd $w $w.menus.fit.menu template_apply
    $w.menus.results.menu add separator
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu parameter_dataset
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu global_family_results
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu parameter_correlation
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu solver_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu prediction_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu scientific_report
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu smoothing_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu covariance_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu measurement_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu model_comparison
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu residual_source
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu residual_predicted
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu residual_sequence
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu influence_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu bootstrap_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu profile_details
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu retained_query
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu physical_plausibility
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu derived_properties
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu model_workbench
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu model_export
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu recipe_python
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu recipe_octave
    ::GX::viewerCommandMenuAdd $w $w.menus.results.menu template_save
    $w.menus.view.menu add separator
    ::GX::viewerCommandMenuAdd $w $w.menus.view.menu configuration
    ::GX::viewerCommandMenuAdd $w $w.menus.view.menu panels_reset
    ::GX::viewerCommandMenuAdd $w $w.menus.view.menu strip
    ::GX::viewerCommandMenuAdd $w $w.menus.view.menu history_details
    ttk::menubutton $w.menus.history -text History -menu $w.menus.history.menu
    menu $w.menus.history.menu -tearoff 0 -postcommand [list ::GX::viewerCommandMenusRefresh $w]
    foreach id {undo redo previous next latest branch timeline} {::GX::viewerCommandMenuAdd $w $w.menus.history.menu $id}
    pack $w.menus.history -side left -padx 3
    ttk::menubutton $w.menus.workspace -text Workspace -menu $w.menus.workspace.menu
    menu $w.menus.workspace.menu -tearoff 0
    ::GX::sessionWorkspaceViewerMenu $w.menus.workspace.menu dataset_curve_fit [::GX::DatasetCurveFit::_workspaceCallbacks $w] $w
    $w.menus.workspace.menu add separator
    set index 0
    foreach id {workspace_new workspace_open save workspace_duplicate workspace_rename workspace_manager workspace_close workspace_delete} {::GX::viewerCommandMenuTrack $w $w.menus.workspace.menu $index $id;incr index}
    ::GX::viewerCommandMenuAdd $w $w.menus.workspace.menu workspace_clear_history
    $w.menus.workspace.menu configure -postcommand "[list ::GX::viewerCommandMenusRefresh $w];[list ::GX::sessionWorkspaceViewerMenuRefresh $w.menus.workspace.menu]"
    pack $w.menus.workspace -side left -padx 3
    ::GX::uiMenuRowAttach $w.menus [pack slaves $w.menus]
    pack $w.footer -side bottom -fill x
    pack $w.main -fill both -expand 1
    set p $w.left.viewport.content
    foreach {column width} {id 90 kind 90 identity 160 variables 150 rows 95 visible 120} {$p.sources.body.sources column $column -width $width -stretch 0}
    pack forget $p.sources.body.actions $p.accepted.actions
    foreach widget {add remove load title} {pack forget $p.filters.controls.$widget}
    pack $p.filters.controls.load -side bottom -fill x
    pack $p.filters.controls.add $p.filters.controls.remove -side bottom -fill x
    foreach widget {remove zoomin zoomout reset help} {pack forget $p.selection.body.$widget}
    foreach widget {settings coordinates} {pack forget $p.presentation.body.$widget}
    bind $w.right.report <Configure> [list ::GX::DatasetCurveFit::_reportWidth $w %w]
    ttk::label $w.footer.coordinateReadout -textvariable ::GX::DatasetCurveFit::state($w,coordinates)
    pack $w.footer.coordinateReadout -fill x
    $w.footer.status configure -wraplength 950;$w.right.report.result configure -wraplength 650
    foreach frame {source samples filter settings parameters selection presentation} {
        foreach child [winfo children [_widget $w $frame]] {bind $child <FocusIn> +[list ::GX::uiFieldScrollSee $w.left.viewport $p $child]}
    }
    foreach {frame children} {filter {variable operator value add remove load cancel} selection {l_mode mode} presentation {residuals split}} {
        set parent [_widget $w $frame];set widgets [lmap child $children {format %s.%s $parent $child}]
        foreach widget [winfo children $parent] {pack forget $widget;grid forget $widget}
        bind $parent <Configure> [list ::GX::native2DToolbarLayout $parent %w $widgets]
    }
    foreach area {body parameters} {bind $w.left.viewport.content.settings.$area <Configure> [list ::GX::DatasetCurveFit::_settingsControlsLayout $w $area %w]}
    _reportScrollBindings $w
    _residualPanelLayout $w
    foreach child [::GX::_viewerCommandsDescendants $w.left] {
        bind $child <Button-4> +[list $w.left.viewport yview scroll -3 units]
        bind $child <Button-5> +[list $w.left.viewport yview scroll 3 units]
    }
    bind $w.main <Map> [list after idle [list ::GX::DatasetCurveFit::_layoutSash $w]]
    set state($w,configurationSubscription) [::GX::configurationSubscribe [list ::GX::DatasetCurveFit::_panelsChanged $w]]
    _panelsChanged $w {}
    after idle [list ::GX::DatasetCurveFit::_layoutSash $w]
}
proc ::GX::DatasetCurveFit::_panelsChanged {w id} {
    if {![winfo exists $w] || $id ni {{} modules.dataset_curve_fit.panels}} return
    set values [_panelValidate [dict get [::GX::configurationResolve modules.dataset_curve_fit.panels] effective]]
    set p $w.left.viewport.content
    dict for {group field} [_panelFields] {
        pack forget $p.$group
        foreach child [winfo children $p.$group] {pack forget $child}
        set mode [dict get $values $group]
        if {$mode eq "hidden"} continue
        pack $p.$group -fill x -pady 4
        if {$mode eq "visible"} {
            foreach child [winfo children $p.$group] {
                if {$child eq "$p.accepted.actions"} continue
                pack $child -fill x
            }
        }
    }
    after idle [list $w.left.viewport yview moveto 0]
}
proc ::GX::DatasetCurveFit::_panelsReset {w} {
    set scope [expr {$::GX::currentSession eq {} ? "user" : "session"}]
    ::GX::configurationCommit [list [dict create id modules.dataset_curve_fit.panels scope $scope value {} clear 1 session_token [::GX::_configurationSessionToken]]]
}
proc ::GX::DatasetCurveFit::_layoutSash {w} {
    if {[winfo exists $w.main]} {$w.main sashpos 0 [expr {min(390,max(300,[winfo width $w]/3))}]}
}
proc ::GX::DatasetCurveFit::_residualPanelLayout {w} {
    variable state
    if {![winfo exists $w.right.residuals]} return
    if {$state($w,showResiduals)} {
        pack $w.right.residuals.pager -side bottom -fill x
        pack $w.right.residuals.table -fill x
    } else {pack forget $w.right.residuals.table $w.right.residuals.pager}
}
