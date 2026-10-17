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
dict set ::GX::DatasetCurveFit::commandCatalog statistics_settings [dict create label {Statistical assumptions and intervals…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog covariance_settings [dict create label {Correlated observation covariance…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog covariance_details [dict create label {Full covariance fit details…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog measurement_details [dict create label {Training measurement details…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog model_comparison [dict create label {Compare accepted models…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog parameter_correlation [dict create label {Parameter correlation…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog solver_details [dict create label {Solver diagnostics…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog profile_settings [dict create label {Profile likelihood settings…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog profile_details [dict create label {Profile likelihood…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog bootstrap_settings [dict create label {Parameter bootstrap settings…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog bootstrap_details [dict create label {Parameter bootstrap…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog residual_source [dict create label {Residuals vs source coordinate} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog residual_predicted [dict create label {Residuals vs predicted response} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog residual_sequence [dict create label {Residual sequence diagnostics…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog influence_details [dict create label {Linear influence…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog prediction_details [dict create label {Response interval details…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog solver_settings [dict create label {Solver settings…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog component_settings [dict create label {Model components…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog complex_settings [dict create label {Joint complex responses…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog surface_workflow [dict create label {Physical surface fit…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog knot_settings [dict create label {Knots / boundaries…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog rational_settings [dict create label {Rational / Padé model…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog implicit_settings [dict create label {Implicit equation and branch…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog formula_settings [dict create label {Safe formula…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog parameter_settings [dict create label {Initial parameters and manual curve…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog region_settings [dict create label {Joint regions…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog baseline_settings [dict create label {Baseline correction…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog recipe_python [dict create label {Export selected fit rerun (Python)…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog recipe_octave [dict create label {Export selected fit rerun (Octave)…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog template_save [dict create label {Save selected fit as template…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog template_apply [dict create label {Apply fit template…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog retained_query [dict create label {Query selected model and derivatives…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog model_export [dict create label {Export selected model (Python, Octave, LaTeX)…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog registered_settings [dict create label {Registered Python/Octave model…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog registered_declare [dict create label {Declare Script Library model…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog registered_cancel [dict create label {Cancel registered model Job} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog smoothing_settings [dict create label {Smoothing selection…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog smoothing_details [dict create label {Smoothing diagnostics…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog log_settings [dict create label {Logarithmic fitting…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog log_publish [dict create label {Publish physical log-response result…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog log_details [dict create label {Log-response interpretation…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog parameter_dataset [dict create label {Publish accepted parameter Dataset…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog family_sources [dict create label {Independent family sources…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog global_family [dict create label {Global family fit…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog global_family_results [dict create label {Global family results…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog smooth_source [dict create label {Smooth into a separate Dataset…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog scientific_report [dict create label {Scientific report…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog model_card [dict create label {Model documentation…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog physical_plausibility [dict create label {Physical plausibility review…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog derived_properties [dict create label {Derived physical properties…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog model_workbench [dict create label {Transfer selected model to Workbench…} default {}]
dict set ::GX::DatasetCurveFit::commandCatalog model_suggestions [dict create label {Model suggestions…} default {}]
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
    _parameterClear $w
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
