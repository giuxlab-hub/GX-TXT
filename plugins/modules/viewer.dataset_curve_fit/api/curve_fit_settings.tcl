# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::DatasetCurveFit {}
proc ::GX::DatasetCurveFit::_panelFields {} {
    set result {}
    foreach {id label} {source {Dataset and variables} sources {Source curves} filters Filters settings {Fit model and configuration} selection {Point selection} accepted {Accepted fits} samples {Built-in samples} presentation {View and residuals}} {
        dict set result $id [dict create type choice label $label values {visible collapsed hidden} default visible]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_panelValidate {values} {
    if {[catch {dict size $values}]} {error {Panels must be a dictionary}}
    set result {}
    dict for {id field} [_panelFields] {dict set result $id [::GX::datasetPublicationV2DictDefault $values $id visible]}
    dict for {id value} $values {if {![dict exists $result $id] || $value ni {visible collapsed hidden}} {error {Choose visible, collapsed or hidden for a registered panel}}}
    return $result
}
proc ::GX::DatasetCurveFit::_shortcutValidate {values} {::GX::viewerShortcutsValidate viewer.dataset_curve_fit $values}
proc ::GX::DatasetCurveFit::_shortcutFields {} {::GX::viewerShortcutFields viewer.dataset_curve_fit}
proc ::GX::DatasetCurveFit::_commandWidgets {} {
    return {samples.load {Open built-in sample} samples.publish {Publish built-in sample…} filter.load {Add Dataset curve} filter.cancel {Cancel operation} filter.add {Add filter} filter.remove {Remove filter} workspace.actions.show {Show sources} workspace.actions.hide {Hide sources} workspace.actions.style {Style sources…} workspace.actions.remove {Remove sources} workspace.actions.reload {Reload active source} workspace.actions.reverse {Reverse whole to new source} workspace.actions.span {Reverse span to new source} settings.parametric {Parametric settings…} settings.polar {Radial settings…} workspace.actions.preview {Fit selected sources} workspace.actions.accept {Accept selected previews} actions.clear {Clear point selection} selection.remove {Remove last rectangle} actions.publish {Publish Preview Dataset…} actions.export {Export accepted CSV…} accepted.visibility {Show / hide accepted fit} accepted.delete {Delete accepted fit} accepted.publish {Publish accepted Dataset…} selection.zoomin {Zoom in} selection.zoomout {Zoom out} selection.reset {Fit view} presentation.settings {View settings…} residualPager.previous {Previous residual page} residualPager.next {Next residual page} residualPager.first {First residual page} residualPager.last {Last residual page}}
}
set ::GX::DatasetCurveFit::commandCatalog [dict create preview [dict create label {Preview fit} default F5] accept [dict create label {Accept fit} default F6] undo [dict create label Undo default Ctrl+z] redo [dict create label Redo default Ctrl+Shift+z] save [dict create label {Save Workspace} default Ctrl+s] previous [dict create label {Previous History step} default {}] next [dict create label {Next History step} default {}] latest [dict create label {Return to latest} default {}] branch [dict create label {Restart here…} default {}]]
dict for {widget label} [::GX::DatasetCurveFit::_commandWidgets] {dict set ::GX::DatasetCurveFit::commandCatalog [string map {. _} $widget] [dict create label $label default {}]}
foreach {id label} {translation {Input translation / shift positive…} configuration {Panels / Configuration…} panels_reset {Restore default panel layout} timeline {Show History timeline} strip {Show Description / History strip} workspace_new {New Workspace…} workspace_open {Open Workspace…} workspace_duplicate {Save as / Duplicate…} workspace_rename {Rename Workspace…} workspace_manager {Session Workspaces…} workspace_close {Close Workspace} workspace_delete {Delete Workspace…} workspace_clear_history {Clear History…} selection_replace {Rectangle Replace mode} selection_add {Rectangle Add mode} selection_subtract {Rectangle Subtract mode} source_activate {Activate selected source}} {dict set ::GX::DatasetCurveFit::commandCatalog $id [dict create label $label default {}]}
dict set ::GX::DatasetCurveFit::commandCatalog history_details [dict create label {Description / History details…} default {}]
::GX::viewerCommandCatalogRegister viewer.dataset_curve_fit $::GX::DatasetCurveFit::commandCatalog modules.dataset_curve_fit.shortcuts

proc ::GX::DatasetCurveFit::_translationMetadata {key result} {
    variable state
    set axes [dict get [_sourceProvenance $key] source_axes]
    set orientation [dict get $result orientation]
    set physical {x y};if {$orientation eq "x_of_y"} {set physical {y x}}
    set mapping [dict create version 1 algorithm [dict get $result translation_algorithm] inverse_applied 1 \
        orientation $orientation coefficient_space translated_fit \
        forward {u_fit=u+delta_u; v_fit=v+delta_v} inverse {u=u_fit-delta_u; v=v_fit-delta_v} \
        residual_space original_physical source_dataset_id $state($key,dataset)]
    foreach axis {u v} physicalAxis $physical {
        set spec [dict get $axes $physicalAxis]
        set variable [::GX::datasetPublicationV2DictDefault $spec variable_id $physicalAxis]
        set unit [dict get $spec unit]
        if {$orientation eq "r_of_theta"} {
            if {$axis eq "u"} {set variable theta;set unit [dict get $result angle_unit]} else {set variable radius}
        }
        set entry [dict create physical_axis $physicalAxis variable_id $variable unit $unit]
        foreach field {mode delta margin original_bounds transformed_bounds} {dict set entry $field [dict get $result translation_${axis}_$field]}
        dict set mapping $axis $entry
    }
    return $mapping
}
proc ::GX::DatasetCurveFit::_translationSettings {w} {
    variable state
    set fields {}
    foreach axis {U V} label {{Independent axis (geometric X)} {Dependent axis (geometric Y)}} {
        dict set fields translation${axis}Mode [dict create type choice label "$label — mode" values {auto manual off}]
        dict set fields translation${axis}Delta [dict create type number label "$label — manual constant in original units" required 1]
    }
    set values {}
    foreach axis {U V} {foreach field {Mode Delta} {set key translation${axis}$field;dict set values $key $state($w,$key)}}
    ::GX::uiFieldFormCreate $w.translation {Reversible input translation — AUTO by default} $fields $values [list ::GX::DatasetCurveFit::_translationApply $w $state($w,activeSource)] $w
    ttk::label $w.translation.rule -text {AUTO resolves each constant over training, complete residual source and output bounds. Physical output: u=u_fit−delta_u; v=f(u+delta_u)−delta_v. Geometric parameter t is unchanged.} -wraplength 520
    pack $w.translation.rule -fill x
}
proc ::GX::DatasetCurveFit::_translationApply {w owner values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error {Active source changed; reopen translation settings}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    dict for {field value} $values {set state($w,$field) $value}
    _invalidateSettings $w
    _workspaceCapture $w;_saveState $w
    set state($w,status) {Translation changed. Preview again to resolve constants and show the physical-space formula.}
}
proc ::GX::DatasetCurveFit::_invalidateSelectionPreview {w} {
    variable state
    if {$state($w,preview) ne {} && [dict get $state($w,preview) scope] eq "selected" && ![_selectionUnchanged $w $state($w,preview)]} {
        _invalidateSettings $w
    }
}
proc ::GX::DatasetCurveFit::_invalidateSettings {w} {
    variable state
    # Persist invalidation in scientific working state as well as button state;
    # otherwise reopening or restoring History could re-enable a stale Preview.
    _disposePreview $w
    set state($w,preview) {};set state($w,previewAccepted) 0;set state($w,previewFitId) {}
    set state($w,report) {}
    if {[winfo exists $w.right.residuals.table]} {$w.right.residuals.table delete [$w.right.residuals.table children {}]}
    if {[winfo exists $w.actions.accept]} {$w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled}
    if {[winfo exists $w.right.plot.canvas]} {redraw $w}
}
proc ::GX::DatasetCurveFit::_uiBoundSetting {w field} {
    variable state
    if {![winfo exists $w] || [info exists state($w,restoringWorkspace)]} return
    set proposed $state($w,$field)
    # Tk updates a bound variable before delivering its selection/focus event.
    # Recover the displayed checkpoint through CORE before asking to branch;
    # cancellation must leave both scientific state and the form unchanged.
    if {[dict exists $::GX::ScientificHistory::viewers $w]} {
        set payload [::GX::scientificHistoryViewerState $w]
        set restored 0
        foreach entry [dict get $payload workspace_sources] {
            if {[dict get $entry id] ne [dict get $payload active_source]} continue
            set saved [dict get $entry state]
            if {$field eq "orientationLabel"} {
                set state($w,orientation) [dict get $saved orientation]
                _orientationLabels $w
            } elseif {[dict exists $saved $field]} {set state($w,$field) [dict get $saved $field]}
            set restored 1
            break
        }
        if {$restored && $proposed eq $state($w,$field)} return
    }
    _uiSafe $w [list ::GX::DatasetCurveFit::_uiApplySetting $w $field $proposed]
}
proc ::GX::DatasetCurveFit::_uiApplySetting {w field value} {
    variable state
    set state($w,$field) $value
    switch $field {
        model {_uiModel $w}
        orientationLabel {_uiOrientation $w}
        default {_uiDomainFields $w;_invalidateSettings $w;_workspaceCapture $w;_saveState $w}
    }
}
proc ::GX::DatasetCurveFit::_commitFocusedSetting {w} {
    variable state
    set widget [focus]
    foreach field {degree initial period smoothing min max samples} {
        if {$widget ne "$w.left.viewport.content.settings.parameters.$field"} continue
        set proposed $state($w,$field)
        _uiBoundSetting $w $field
        return [expr {$state($w,$field) eq $proposed}]
    }
    return 1
}
