# SPDX-License-Identifier: GPL-3.0-or-later
# Workbench maps logical dimensions to CORE bindings and presents the shared UI.
namespace eval ::GX::CurveWorkbench {variable parameterCapability [::GX::parameterModuleRegister {}]}
proc ::GX::CurveWorkbench::_parameterBind {w} {
    variable st;variable parameterCapability
    if {$st($w,document) eq {}} return
    if {[info exists st($w,parameterContext)]&&![catch {set info [::GX::parameterContextInfo $st($w,parameterContext)]}]&&[dict get $info workspace] eq $st($w,document)} {return $st($w,parameterContext)}
    set st($w,parameterContext) [::GX::parameterContext $parameterCapability $st($w,document)]
    set st($w,previousParameters) [::GX::parameterDefinitions $st($w,parameterContext)]
    ::GX::parameterSubscribe $st($w,parameterContext) [list ::GX::CurveWorkbench::_parameterRecalculate $w]
    return $st($w,parameterContext)
}
proc ::GX::CurveWorkbench::_parameterRecalculate {w token} {
    variable st
    if {![winfo exists $w]||![info exists st($w,parameterContext)]||$st($w,parameterContext) ne $token} {::GX::parameterUnsubscribe $token;return {}}
    set before [_snapshotIds $w [dict keys $st($w,curves)]];set expressions {}
    dict set before @cad parameter_definitions $st($w,previousParameters)
    dict for {id record} $st($w,constraints) {
        if {[dict exists $record expression]&&![::GX::datasetPublicationV2DictDefault [dict get $record definition] driven 0]} {dict set expressions [dict get $record native] [dict get $record expression]}
    }
    try {
        ::GX::parameterApplyDimensions $token $st($w,scene) $expressions
        foreach id [dict keys $st($w,curves)] {if {[dict exists [_record $w $id] sketch_definition]} {_syncSamples $w $id}}
        _constraintCapture $w;_selectionScene $w
        if {![info exists st($w,importTransaction)]&&![info exists st($w,historyRestoring)]} {
            if {$st($w,scientificRecipe) ne {}} {
                set previous [dict get $st($w,scientificRecipe) base]
                foreach step [dict get $st($w,scientificRecipe) steps] {set previous [::GX::scientificRecipeApplyPatch $previous [dict get $step patch]]}
                if {[dict exists $previous @cad parameter_definitions]} {dict set before @cad parameter_definitions [dict get $previous @cad parameter_definitions]}
            }
            _history $w $before [dict keys $st($w,curves)]
        } else {_changed $w}
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,previousParameters) [::GX::parameterDefinitions $token]
    return [list ::GX::CurveWorkbench::_restoreSnapshot $w $before]
}
proc ::GX::CurveWorkbench::_parametersOpen {w} {
    variable st;_save $w
    ::GX::sessionWorkspaceActionInvoke $st($w,document) parameters
}
proc ::GX::CurveWorkbench::parametersAction {workspace context} {
    set w [open [dict create workspace_id $workspace]]
    variable st
    # Existing window state owns one live subscription; action context was
    # already checked by CORE, while this handle follows the actual open view.
    set token [_parameterBind $w]
    return [::GX::parameterEditorOpen $token $w]
}

proc ::GX::CurveWorkbench::_parameterPersistBindings {w} {
    variable st;set bindings {}
    dict for {id record} $st($w,constraints) {
        if {[dict exists $record expression] && ![::GX::datasetPublicationV2DictDefault [dict get $record definition] driven 0]} {dict set bindings $id [dict get $record expression]}
    }
    ::GX::parameterBindingsSet [_parameterBind $w] $bindings
}
