# SPDX-License-Identifier: GPL-3.0-or-later
# Scientific hooks only. CORE owns the active timeline and persistence workers.
proc ::GX::Workbench3D::historyDifference {before after} {
    set patch {}
    dict for {key value} $after {if {![dict exists $before $key] || [dict get $before $key] ne $value} {dict set patch $key $value}}
    foreach key [dict keys $before] {if {![dict exists $after $key]} {dict set patch $key @gxtxt.recipe.delete}}
    return $patch
}
proc ::GX::Workbench3D::historyCapture {} {
    variable model;variable module;variable provider
    foreach key {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool} {dict set model tool_settings $key [set ::GX::Workbench3D::$key]}
    dict set model view [::GX::viewerSceneGet $module $provider]
    return [recipeState $model]
}
proc ::GX::Workbench3D::historyValidate {record} {
    # Exported scientific recipes retain their full scientific admission hook.
    # Import/open validates inert History structure once; each actual geometry
    # hydration still validates its owned resources through Native3D.
    if {[dict exists $record document_id]} {return [recipeValidate $record]}
    set state [dict get $record base]
    foreach key {format working_unit objects profiles} {if {![dict exists $state $key]} {error "3D History checkpoint requires $key"}}
    if {[dict get $state format] ne {workbench3d.document.v1}} {error {Unsupported 3D History scientific state}}
    return 1
}
proc ::GX::Workbench3D::historyGuard {} {
    variable scene
    if {$scene eq {}} {return 0}
    ::GX::native3DGeometrySceneInfo $scene
    return 1
}
proc ::GX::Workbench3D::historyError {receipt} {
    variable recoveryNotice
    set recoveryNotice "History accepted in RAM; persistence failed: [dict get $receipt error]. Save/export retained RAM state before closing."
}
proc ::GX::Workbench3D::historyProject {record} {
    variable scene;variable model;variable allocationCounters
    set result [::GX::native3DGeometryCheckpoint $scene [payload $record]]
    set allocationCounters [allocationMerge $allocationCounters $model]
    return $result
}
proc ::GX::Workbench3D::historyRestore {snapshot} {
    variable model;variable scene;variable module;variable provider
    variable tokens;variable profileTokens;variable groupTokens;variable selection;variable cleanupNotice
    set scope [::GX::native3DGeometrySceneInfo $scene]
    set before $model;set oldScene $scene;set oldTokens $tokens;set oldProfiles $profileTokens;set oldGroups $groupTokens;set oldSelection $selection
    set oldView [::GX::viewerSceneGet $module $provider];set settings {}
    foreach key {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool requestedUnit} {dict set settings $key [set ::GX::Workbench3D::$key]}
    set model [dict merge [defaultModel] $snapshot]
    try {
        if {[dict exists $model tool_settings]} {dict for {key value} [dict get $model tool_settings] {if {[dict exists $settings $key]} {set ::GX::Workbench3D::$key $value}}}
        set ::GX::Workbench3D::requestedUnit [dict get $model working_unit]
        # Keep the old retained scene until complete hydration succeeds. CORE
        # moves its cursor only after this owning-thread hook returns.
        restoreStage
    } on error {message options} {
        if {$scene ne $oldScene && $scene ne {}} {catch {::GX::native3DGeometryClose $scene}}
        set scene $oldScene;set tokens $oldTokens;set profileTokens $oldProfiles;set groupTokens $oldGroups;set model $before;set selection $oldSelection
        dict for {key value} $settings {set ::GX::Workbench3D::$key $value}
        if {[dict get $scope session_token] eq [::GX::interactiveDocumentSessionToken]} {::GX::viewerSceneSet $module $provider $oldView;catch {refresh}}
        return -options $options $message
    }
    if {[catch {::GX::native3DGeometryClose $oldScene} message]} {set cleanupNotice "History restored; previous scene cleanup failed: $message"}
    catch {guiPresentationChanged}
}
proc ::GX::Workbench3D::historyArchiveLegacy {payload} {
    variable document;variable legacyHistoryArchive
    if {$legacyHistoryArchive ne {}} return
    # Preserve the exact former private payload and all branch/provenance data
    # through the existing CORE Resource owner before an explicit Save replaces
    # its old fields. This is one-time import, never ordinary operation work.
    set metadata [dict create format gxtxt.workbench3d.legacy_history.v1 dependencies [::GX::interactiveDocumentResourceReferences $payload] scientific_authority 1]
    set writer [::GX::interactiveDocumentResourceOpenWriter $document $metadata]
    try {
        set bytes [encoding convertto utf-8 $payload]
        for {set offset 0} {$offset<[string length $bytes]} {incr offset 1048576} {::GX::interactiveDocumentResourceAppend $writer [string range $bytes $offset [expr {$offset+1048575}]]}
        set legacyHistoryArchive [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
}
proc ::GX::Workbench3D::historyImport {payload} {
    variable legacyHistoryArchive
    if {[dict exists $payload scientific_history]} {return [dict get $payload scientific_history]}
    set current [recipeState [dict get $payload model]]
    set past [lmap snapshot [::GX::datasetPublicationV2DictDefault $payload undo {}] {recipeState $snapshot}]
    set future [lmap snapshot [lreverse [::GX::datasetPublicationV2DictDefault $payload redo {}]] {recipeState $snapshot}]
    set prior [::GX::datasetPublicationV2DictDefault [dict get $payload model] scientific_recipe {}]
    if {$prior ne {} || $past ne {} || $future ne {}} {historyArchiveLegacy $payload}
    set record [::GX::scientificHistoryCreate viewer.3d_workbench [expr {$past eq {} ? $current : [lindex $past 0]}]]
    if {$legacyHistoryArchive ne {}} {dict set record legacy_history_archive $legacyHistoryArchive}
    set matched 0
    if {$prior ne {}} {
        # Preserve every retained semantic step and unknown receipt field.
        set record [dict merge $record $prior [dict create workbench_id viewer.3d_workbench retention complete legacy_import 1 cursor [llength [dict get $prior steps]]]]
        set count [dict get $record cursor]
        set matched [expr {[::GX::scientificHistoryState $record] eq $current && $count>=[llength $past]}]
        if {$matched} {
            set index [expr {$count-[llength $past]}]
            foreach state $past {if {[::GX::scientificHistoryState $record $index] ne $state} {set matched 0;break};incr index}
        }
    }
    if {!$matched} {
        foreach state [concat $past [list $current]] {set record [::GX::scientificHistoryAppend viewer.3d_workbench $record $state {Imported legacy Undo checkpoint}]}
    }
    set cursor [dict get $record cursor]
    foreach state $future {set record [::GX::scientificHistoryAppend viewer.3d_workbench $record $state {Imported legacy Redo checkpoint}]}
    dict set record cursor $cursor
    return $record
}
