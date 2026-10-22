# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Workbench3D {variable extensionTransactions {};variable extensionSerial 0}
proc ::GX::Workbench3D::extensionContext {} {
    variable document;variable model;variable selection
    cancelPreview
    return [dict create workbench_id viewer.3d_workbench workbench_version [::GX::moduleField viewer.3d_workbench version {}] document_id $document revision [dict get [::GX::interactiveDocumentRead $document] revision] selection [dict create kind object ids $selection point_indices {}] active_object [lindex $selection 0] active_group {} working_plane {} units [dict create working_unit [dict get $model working_unit]] parameters {}]
}
proc ::GX::Workbench3D::extensionBegin {context} {
    variable document;variable model;variable scene;variable tokens;variable profileTokens;variable groupTokens;variable undo;variable redo;variable busy;variable selection;variable extensionTransactions;variable extensionSerial;variable module;variable provider
    if {$busy||[dict get $context document_id] ne $document} {error "Workbench owner is busy or changed"}
    set id "extension3d-[pid]-[incr extensionSerial]"
    set before [dict create context $context model $model scene $scene tokens $tokens profiles $profileTokens groups $groupTokens undo $undo redo $redo selection $selection view [::GX::viewerSceneGet $module $provider] created {} modified {} deleted {}]
    dict set extensionTransactions $id $before;set busy 1
    try {restoreStage} on error {message options} {extensionRollback $id;return -options $options $message}
    return $id
}
proc ::GX::Workbench3D::extensionRequire {id} {
    variable extensionTransactions;variable document
    if {![dict exists $extensionTransactions $id]} {error "Closed 3D extension transaction"}
    set value [dict get $extensionTransactions $id];set owner [::GX::interactiveDocumentRead $document]
    if {[dict get $owner revision]!=[dict get $value context revision]} {error "3D extension document revision changed"}
    ::GX::native3DGeometrySceneInfo $::GX::Workbench3D::scene
    return $value
}
proc ::GX::Workbench3D::extensionTrack {id kind object} {variable extensionTransactions;set value [dict get $extensionTransactions $id];dict lappend value $kind $object;dict set extensionTransactions $id $value}
proc ::GX::Workbench3D::extensionApply {id result} {
    variable model;variable tokens;variable scene;variable extensionTransactions
    extensionRequire $id;set operations [dict get $result operations]
    if {[llength $operations]>256} {error "3D extension limit is 256 semantic operations"}
    foreach operation $operations {
        set action [dict get $operation operation]
        if {$action eq "replay_recipe"} {
            set encoded [dict get $operation encoded];::GX::scientificRecipeValidate $encoded;set recipe [::GX::scientificRecipeDecode $encoded]
            if {[dict get $recipe workbench_id] ne "viewer.3d_workbench"} {error "Recipe belongs to a different Workbench"}
            set old [dict keys [dict get $model objects]];set next [dict get $recipe base]
            foreach step [dict get $recipe steps] {set next [::GX::scientificRecipeApplyPatch $next [dict get $step patch]]}
            set model [dict merge [defaultModel] $next];set previousScene $scene
            restoreStage;::GX::native3DGeometryClose $previousScene
            foreach object [dict keys [dict get $model objects]] {extensionTrack $id [expr {$object in $old ? "modified" : "created"}] $object}
            foreach object $old {if {![dict exists $model objects $object]} {extensionTrack $id deleted $object}}
            continue
        }
        if {$action in {box cylinder}} {
            set request [dict get $operation parameters]
            set receipt [call $action $request];set object [installObject $receipt [dict get $operation name]]
            extensionTrack $id created $object;continue
        }
        if {$action ni {translate rotate scale identity delete}} {error "Unsupported 3D extension operation $action"}
        foreach object [dict get $operation target_ids] {
            if {![dict exists $model objects $object]||[dict get $model objects $object locked]} {error "3D extension target is missing or locked: $object"}
            if {[dict get $model objects $object group] ne {}} {error "Edit grouped geometry through its group before invoking this extension"}
            if {$action eq "identity"} {
                if {[dict exists $operation name]} {dict set model objects $object name [dict get $operation name]}
                if {[dict exists $operation attributes]} {dict set model objects $object attrs [dict merge [dict get $model objects $object attrs] [dict get $operation attributes]]}
            } elseif {$action eq "delete"} {call delete [dict create object_token [dict get $tokens $object]];dict unset tokens $object;dict unset model objects $object;extensionTrack $id deleted $object;continue} else {
                set request [dict merge [dict get $operation parameters] [dict create object_token [dict get $tokens $object]]]
                set predecessor [dict get $tokens $object]
                set receipt [call $action $request]
                installPreparedObject $receipt [snapshotObject $receipt] [dict get $model objects $object name] $object
                call delete [dict create object_token $predecessor]
            }
            extensionTrack $id modified $object
        }
    }
    dict set extensionTransactions $id provenance [::GX::datasetPublicationV2DictDefault $result provenance {}]
    set receipt [dict get $extensionTransactions $id]
    return [dict create created_ids [lsort -unique [dict get $receipt created]] modified_ids [lsort -unique [dict get $receipt modified]] deleted_ids [lsort -unique [dict get $receipt deleted]] operations $operations]
}
proc ::GX::Workbench3D::extensionCommit {id applied} {
    variable extensionTransactions;variable model;variable busy;variable document;variable cleanupNotice
    set before [extensionRequire $id]
    # A logical replay restores complete scientific object records, including
    # their producer/source chain. Its invocation belongs to the transaction
    # History below, not in place of the restored object's derivation.
    set replay 0
    foreach operation [dict get $applied operations] {if {[dict get $operation operation] eq {replay_recipe}} {set replay 1}}
    set invocation [dict get $before provenance]
    if {!$replay && $invocation ne {}} {
        foreach object [concat [dict get $applied created_ids] [dict get $applied modified_ids]] {if {[dict exists $model objects $object]} {dict set model objects $object provenance $invocation}}
    }
    commit [dict get $before model] extension_transaction [dict create operations [dict get $applied operations] provenance [dict get $before provenance]] [dict get $before context selection ids] [dict get $applied created_ids]
    set warnings {};if {[catch {::GX::native3DGeometryClose [dict get $before scene]} message]} {lappend warnings "Extension committed; predecessor scene cleanup failed: $message"}
    dict unset extensionTransactions $id;set busy 0
    return [dict create revision [dict get [::GX::interactiveDocumentRead $document] revision] warnings $warnings]
}
proc ::GX::Workbench3D::extensionRollback {id} {
    variable extensionTransactions;variable model;variable scene;variable tokens;variable profileTokens;variable groupTokens;variable undo;variable redo;variable busy;variable selection;variable module;variable provider
    if {![dict exists $extensionTransactions $id]} return
    set before [dict get $extensionTransactions $id]
    try {
        if {$scene ne [dict get $before scene]} {::GX::native3DGeometryClose $scene}
    } finally {
        set scene [dict get $before scene];set model [dict get $before model];set tokens [dict get $before tokens];set profileTokens [dict get $before profiles];set groupTokens [dict get $before groups];set undo [dict get $before undo];set redo [dict get $before redo];set selection [dict get $before selection];set busy 0;dict unset extensionTransactions $id
        ::GX::viewerSceneSet $module $provider [dict get $before view];refresh
    }
}
proc ::GX::Workbench3D::recipeState {value} {return [dict remove $value recipe scientific_recipe]}
proc ::GX::Workbench3D::recipeCapture {context} {
    variable model;variable document
    if {[dict get $context document_id] ne $document} {error "Recipe document changed"}
    set state [recipeState $model];set record [::GX::datasetPublicationV2DictDefault $model scientific_recipe [dict create base $state steps {}]]
    set current [dict get $record base];foreach step [dict get $record steps] {set current [::GX::scientificRecipeApplyPatch $current [dict get $step patch]]}
    set record [::GX::scientificRecipeAppend $record $current $state [dict create api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1 operation checkpoint_current parameters {} targets [dict keys [dict get $state objects]] result_ids [dict keys [dict get $state objects]] working_unit [dict get $state working_unit]]]
    set sources {}
    foreach value [concat [list [dict get $record base]] [lmap step [dict get $record steps] {dict get $step patch}]] {
        foreach collection {objects profiles} {if {![dict exists $value $collection]} continue;dict for {object info} [dict get $value $collection] {
            foreach binding [::GX::datasetPublicationV2DictDefault $info source_bindings {}] {
                if {[dict exists $binding source_descriptor request]&&[dict exists $binding source_descriptor source_id]} {set item [dict create request [dict get $binding source_descriptor request] fingerprint [dict get $binding source_descriptor source_id]]} elseif {[dict exists $binding source_dataset_id]&&[dict exists $binding source_sha256]} {set item [dict create source_kind geometry_dataset dataset_id [dict get $binding source_dataset_id] fingerprint [dict get $binding source_sha256]]} else continue
                if {$item ni $sources} {lappend sources $item}
            }
        }}
    }
    return [dict merge $record [dict create format gxtxt.scientific_recipe.v1 workbench_id viewer.3d_workbench document_id $document required_apis {NATIVE_3D_GEOMETRY_API_v1 CURVE_SOURCE_API_v1 SCIENTIFIC_RECIPE_API_v1} plugin_versions [dict create viewer.3d_workbench [::GX::moduleField viewer.3d_workbench version {}]] sources $sources]]
}
proc ::GX::Workbench3D::recipeValidate {recipe} {
    set state [dict get $recipe base];set scene [::GX::native3DGeometryOpen [dict get $recipe document_id]]
    try {
        foreach patch [concat [list $state] [lmap step [dict get $recipe steps] {dict get $step patch}]] {
            set state [::GX::scientificRecipeApplyPatch $state $patch]
            ::GX::unitRegistryConversionPlan [dict get $state working_unit] mm
            foreach collection {objects profiles} {
                if {![dict exists $patch $collection]} continue
                dict for {id record} [dict get $patch $collection] {
                    if {$collection eq "objects"} {
                        ::GX::interactiveDocumentResourceInfo [dict get $record geometry]
                        set loaded [::GX::native3DGeometryCall $scene [expr {[dict get $record kind] eq "brep" ? "load_step" : "load_mesh"}] [dict create resource [dict get $record geometry]]]
                        ::GX::native3DGeometryCall $scene delete [dict create object_token [dict get $loaded object_token]]
                    } else {
                        set loaded [::GX::native3DGeometryCall $scene profile [dict create contours [dict get $record contours] plane [dict get $record plane] tolerance [dict get $record tolerance]]]
                        ::GX::native3DGeometryCall $scene profile_delete [dict create profile_token [dict get $loaded profile_token]]
                    }
                }
            }
        }
        dict for {group info} [dict get $state groups] {foreach id [dict get $info members] {if {![dict exists $state objects $id]} {error "Recipe group $group has missing object $id"}}}
    } finally {::GX::native3DGeometryClose $scene}
}
proc ::GX::Workbench3D::recipeReplay {context recipe} {
    set transaction [extensionBegin $context]
    try {set applied [extensionApply $transaction [dict create status ok operations [list [dict create operation replay_recipe encoded [::GX::scientificRecipeEncode $recipe]]] provenance [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 replay_policy validated_logical_geometry_operations]]];set receipt [extensionCommit $transaction $applied];set transaction {};return $receipt} finally {if {$transaction ne {}} {extensionRollback $transaction}}
}
rename ::GX::Workbench3D::commit ::GX::Workbench3D::commit_recipe_base
proc ::GX::Workbench3D::commit {before operation parameters targets results} {
    variable model
    set first [recipeState $before];set last [recipeState $model]
    set record [::GX::datasetPublicationV2DictDefault $before scientific_recipe {}]
    set notice {}
    if {[catch {set next [::GX::scientificRecipeAppend $record $first $last [dict create api_id SCIENTIFIC_RECIPE_API_v1 geometry_api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1 operation geometry_state semantic_operation $operation parameters $parameters targets $targets result_ids $results working_unit [dict get $model working_unit]]]} reason]} {set notice "Edit committed; recipe recording needs attention: $reason"} else {dict set model scientific_recipe $next}
    set receipt [commit_recipe_base $before $operation $parameters $targets $results]
    if {$notice ne {}} {set ::GX::Workbench3D::status $notice}
    return $receipt
}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_recipe_base
proc ::GX::Workbench3D::buildPanel {window} {
    variable panel;buildPanel_recipe_base $window
    foreach {key label command} [list recipe {Scientific Recipe Recorder…} [list ::GX::scientificRecipeDialog $window.recipe viewer.3d_workbench ::GX::Workbench3D::extensionContext $window] extensions {Extensions…} [list ::GX::workbenchExtensionActionDialog $window.extensions ::GX::Workbench3D::extensionContext $window]] {ttk::button $panel.$key -text $label -command [list ::GX::Workbench3D::safe $command];pack $panel.$key -fill x -before $panel.status}
}
::GX::scientificRecipeHostRegister viewer.3d_workbench [dict create capture ::GX::Workbench3D::recipeCapture validate ::GX::Workbench3D::recipeValidate replay ::GX::Workbench3D::recipeReplay]
::GX::workbenchExtensionHostRegister viewer.3d_workbench [dict create begin ::GX::Workbench3D::extensionBegin apply ::GX::Workbench3D::extensionApply commit ::GX::Workbench3D::extensionCommit rollback ::GX::Workbench3D::extensionRollback]
