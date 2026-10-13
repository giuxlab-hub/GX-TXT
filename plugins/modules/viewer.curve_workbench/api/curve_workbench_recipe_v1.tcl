# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveWorkbench::_recipeWindow {context} {
    variable st
    foreach key [array names st *,document] {if {$st($key) eq [dict get $context document_id]} {set w [string range $key 0 end-9];if {[winfo exists $w]} {return $w}}}
    error "Recipe Workbench is closed"
}
proc ::GX::CurveWorkbench::_recipeState {w} {
    set state [_snapshotIds $w [dict keys $::GX::CurveWorkbench::st($w,curves)]]
    if {$::GX::CurveWorkbench::st($w,document) ne {}} {
        dict set state @cad parameter_definitions [::GX::parameterDefinitions [_parameterBind $w]]
        dict set state @cad session_parameters [::GX::parameterViewSessionDefinitions [_parameterBind $w]]
    }
    return $state
}
proc ::GX::CurveWorkbench::_recipeUnit {state} {
    set units {};dict for {id record} [dict remove $state @cad] {if {$record ne {}} {foreach unit [_coordinateUnits $record] {if {$unit ni $units} {lappend units $unit}}}}
    return [join $units /]
}
proc ::GX::CurveWorkbench::_recipeCapture {context} {
    variable st;set w [_recipeWindow $context]
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)} {error {Return to Latest before recording a recipe.}}
    set after [_recipeState $w];set record $st($w,scientificRecipe)
    if {$record eq {}} {set record [dict create base $after steps {} retention complete]}
    set current [dict get $record base];foreach step [dict get $record steps] {set current [::GX::scientificRecipeApplyPatch $current [dict get $step patch]]}
    set record [::GX::scientificRecipeAppend $record $current $after [dict create api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operation checkpoint_current parameters {} targets [dict keys [dict remove $after @cad]] result_ids [dict keys [dict remove $after @cad]] working_unit [_recipeUnit $after]]]
    set sources {};foreach state [concat [list [dict get $record base]] [lmap step [dict get $record steps] {dict get $step patch}]] {
        dict for {id value} [dict remove $state @cad] {if {$value ne "@gxtxt.recipe.delete"&&[dict exists $value source_descriptor source_id]} {set source [dict create request [dict get $value source_request] fingerprint [dict get $value source_descriptor source_id]];if {$source ni $sources} {lappend sources $source}}}
    }
    return [dict merge $record [dict create format gxtxt.scientific_recipe.v1 workbench_id viewer.curve_workbench document_id $st($w,document) required_apis {NATIVE_2D_GEOMETRY_API_v1 CURVE_SOURCE_API_v1 SCIENTIFIC_RECIPE_API_v1} plugin_versions [dict create viewer.curve_workbench [::GX::moduleField viewer.curve_workbench version {}]] sources $sources]]
}
proc ::GX::CurveWorkbench::_recipeValidate {recipe} {
    ::GX::native2DEnsure;set scene [::GX::Native2D::core scene];set state [dict get $recipe base]
    try {
        foreach patch [concat [list $state] [lmap step [dict get $recipe steps] {dict get $step patch}]] {
            dict for {id record} $patch {
                if {$id eq "@cad"} {dict set state @cad $record;continue}
                if {$record eq "@gxtxt.recipe.delete"} {if {[dict exists $state $id]} {dict unset state $id};continue}
                if {[dict get $record id] ne $id} {error "Recipe logical identity mismatch: $id"}
                if {[dict exists $record working_unit]&&[dict get $record working_unit] ne {}} {::GX::unitRegistryConversionPlan [dict get $record working_unit] [dict get $record working_unit]}
                if {[_bulkRecord $record]} {set object [::GX::interactiveDocumentNative2DRestoreWithGaps [dict get $record geometry_resource] [dict get $record gap_resource] $scene]} elseif {[dict exists $record sketch_definition]} {set object [::GX::Native2D::core sketch_create $scene [dict get $record sketch_definition] [dict get $record sketch_samples]]} else {set object [::GX::Native2D::core [expr {[llength [dict get $record samples]]==1 ? "point" : "add"}] $scene [_xy [dict get $record samples]]]}
                ::GX::Native2D::core delete $scene $object;dict set state $id $record
            }
        }
        if {[dict exists $state @cad]} {dict for {group value} [dict get $state @cad groups] {foreach id [dict get $value members] {if {![dict exists $state $id]} {error "Recipe group $group has missing logical member $id"}}}}
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::CurveWorkbench::_recipeApplyState {w recipe} {
    variable st
    set state [dict get $recipe base];foreach step [dict get $recipe steps] {set state [::GX::scientificRecipeApplyPatch $state [dict get $step patch]]}
    foreach id [dict keys $st($w,curves)] {if {![dict exists $state $id]} {dict set state $id {}}}
    _restoreSnapshot $w $state
    foreach id [dict keys $st($w,curves)] {if {[regexp {^curve([0-9]+)$} $id -> number]} {set st($w,next) [expr {max($st($w,next),$number)}]}}
    return [dict keys $st($w,curves)]
}
proc ::GX::CurveWorkbench::_recipeReplay {context recipe} {
    set transaction [_extensionBegin $context]
    try {
        set receipt [_extensionApply $transaction [dict create status ok operations [list [dict create operation replay_recipe encoded [::GX::scientificRecipeEncode $recipe]]]]]
        set result [_extensionCommit $transaction $receipt];set transaction {};return $result
    } finally {if {$transaction ne {}} {_extensionRollback $transaction}}
}
rename ::GX::CurveWorkbench::_snapshotIds ::GX::CurveWorkbench::_snapshotIds_recipe_base
proc ::GX::CurveWorkbench::_snapshotIds {w ids} {
    set state [_snapshotIds_recipe_base $w $ids]
    dict set state @cad [dict remove [dict get $state @cad] scientific_recipe]
    if {$::GX::CurveWorkbench::st($w,document) ne {}} {
        set token [_parameterBind $w]
        dict set state @cad parameter_definitions [::GX::parameterDefinitions $token]
        dict set state @cad session_parameters [::GX::parameterViewSessionDefinitions $token]
    } else {dict set state @cad parameter_definitions {};dict set state @cad session_parameters [::GX::parameterSessionDefinitions]}
    return $state
}
rename ::GX::CurveWorkbench::_load ::GX::CurveWorkbench::_load_recipe_base
proc ::GX::CurveWorkbench::_load {w} {
    variable st
    _load_recipe_base $w
    if {$st($w,document) ne {}} {
        set payload [dict get [::GX::interactiveDocumentRead $st($w,document)] payload]
        # Version-2 Workspaces predate CAD/recipes. The base loader deliberately
        # accepts an absent CAD block; optional recipe restore must do so too.
        set cad [::GX::datasetPublicationV2DictDefault $payload cad_workspace {}]
        set st($w,scientificRecipe) [::GX::datasetPublicationV2DictDefault $cad scientific_recipe {}]
    }
}
rename ::GX::CurveWorkbench::_history ::GX::CurveWorkbench::_history_recipe_base
proc ::GX::CurveWorkbench::_history {w before ids} {
    variable st
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)} {
        _restoreSnapshot $w $before;_draw $w
        error {History is read-only. Return to Latest or explicitly Restart from this step.}
    }
    set previous $st($w,scientificRecipe);set after [_recipeState $w];set fullBefore $after
    dict for {id record} $before {if {$record eq {}} {if {[dict exists $fullBefore $id]} {dict unset fullBefore $id}} else {dict set fullBefore $id $record}}
    set operations {};foreach id $ids {if {[dict exists $after $id operations]} {dict set operations $id [dict get $after $id operations]}}
    set notice {}
    if {$previous eq {}} {set previous [dict create base $fullBefore steps {} retention complete]} else {dict set previous retention complete}
    if {[catch {set next [::GX::scientificRecipeAppend $previous $fullBefore $after [dict create api_id SCIENTIFIC_RECIPE_API_v1 geometry_api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operation geometry_state semantic_operation update_logical_geometry parameters $operations targets $ids result_ids [dict keys [dict remove $after @cad]] working_unit [_recipeUnit $after]]]} reason]} {_restoreSnapshot $w $before;error "Edit rejected to preserve complete History: $reason"} else {set st($w,scientificRecipe) $next}
    try {_history_recipe_base $w $before $ids} on error {message options} {set st($w,scientificRecipe) $previous;return -options $options $message}
    if {[info commands ::GX::CurveWorkbench::_timelineRender] ne {}} {_timelineRender $w}
    if {$notice ne {}} {set st($w,status) $notice;set st($w,scientificRecipeNotice) $notice}
}
proc ::GX::CurveWorkbench::_buildRecipe {w} {
    variable st
    $w.cad.sketch.menu add command -label "Scientific Recipe Recorder…" -command [list ::GX::scientificRecipeDialog $w.recipe viewer.curve_workbench [list ::GX::CurveWorkbench::_extensionContext $w] $w]
}
::GX::scientificRecipeHostRegister viewer.curve_workbench [dict create capture ::GX::CurveWorkbench::_recipeCapture validate ::GX::CurveWorkbench::_recipeValidate replay ::GX::CurveWorkbench::_recipeReplay]
