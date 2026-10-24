# SPDX-License-Identifier: GPL-3.0-or-later
# Hydrate structural candidates before the authoritative document commit.
proc ::GX::Workbench3D::structuralCommit {before operation parameters targets results {rollbackTokens {}}} {
    variable scene;variable tokens;variable profileTokens;variable groupTokens;variable model;variable selection;variable module;variable provider;variable cleanupNotice
    set scope [::GX::native3DGeometrySceneInfo $scene]
    set oldScene $scene;set oldTokens $tokens;if {$rollbackTokens ne {}} {set oldTokens $rollbackTokens}
    set oldProfiles $profileTokens;set oldGroups $groupTokens;set oldSelection $selection;set oldView [::GX::viewerSceneGet $module $provider]
    try {
        restoreStage
        set receipt [commit $before $operation $parameters $targets $results]
    } on error {message options} {
        if {$scene ne $oldScene&&$scene ne {}&&[catch {::GX::native3DGeometryClose $scene} cleanup]} {append message "; structural candidate cleanup failed: $cleanup"}
        set scene $oldScene;set tokens $oldTokens;set profileTokens $oldProfiles;set groupTokens $oldGroups
        set model $before;set selection $oldSelection
        if {[dict get $scope session_token] eq [::GX::interactiveDocumentSessionToken]&&![catch {::GX::interactiveDocumentMetadata [dict get $scope document_id]} owner]&&[dict get $owner generation] eq [dict get $scope generation]} {
            ::GX::viewerSceneSet $module $provider $oldView
            if {[catch {refresh} rollback]} {append message "; structural presentation rollback failed: $rollback"}
        }
        return -options $options $message
    }
    if {[catch {::GX::native3DGeometryClose $oldScene} cleanup]} {set cleanupNotice "structural action committed; previous scene cleanup failed: $cleanup"}
    return $receipt
}

proc ::GX::Workbench3D::committedCleanupDelete {ownedTokens} {
    variable cleanupNotice
    foreach token $ownedTokens {if {[catch {call delete [dict create object_token $token]} message]} {append cleanupNotice "Action committed; predecessor geometry cleanup failed: $message; "}}
}
