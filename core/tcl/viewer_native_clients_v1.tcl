# SPDX-License-Identifier: GPL-3.0-or-later
# Owning-thread native clients. Model declarations and typed receipts are inert;
# current installed admission and the actual event remain separate authority.
proc ::GX::scriptLibraryApiInfo {} {
    return [dict create api_id SCRIPT_LIBRARY_API_v1 api_version 1 host_only 1 operations {script_library_command} native_client_operations {script_library_command} host_operations {viewerGuiScriptLibraryCommand viewerGuiScriptLibrarySnapshot scriptLibraryOpen} features {project_source_read_admission_v1 restored_owner_review_v1} request_bytes_max 49152 result_bytes_max 49152 registry_owner SCRIPT_EXECUTION_API_v1 source_owner SOURCE_SURFACE_API_v1]
}
proc ::GX::_viewerNativeClientSessionToken {} {
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq {}} {return {}}
    return [interactiveDocumentSessionToken]
}
proc ::GX::_viewerNativeClientPackageSnapshot {root} {
    return [dict create descriptor [sha256File [file join $root module.ini]] binary [sha256File [file join $root native viewer.so]] design [sha256File [file join $root gui design.tcldict]] source [_viewerDevelopmentSnapshot [file join $root source]]]
}
proc ::GX::_viewerNativeClientBase {window} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerDevelopment::windows $window]} {error {Native client window or Session lifetime ended}}
    set r [dict get $::GX::ViewerDevelopment::windows $window];set module [dict get $r module]
    if {[datasetPublicationV2DictDefault $r native_client_module {}] ne $module || [dict get $::GX::ViewerGui::instances $window module] ne $module ||
        [moduleField $module descriptor {}] eq {} || ![moduleIsEnabled $module] || [viewerProviderDefinition $module [dict get $r provider]] eq {} ||
        {RESTRICTED_VIEWER_CLIENT_API_v1} ni [modulePublicApiIds $module]} {error {Native client requires its actual registered admitted module}}
    if {![dict exists $r runtime_module_root] || [file normalize [file dirname [moduleField $module descriptor]]] ne [file normalize [dict get $r runtime_module_root]]} {error {Install the native client normally before using registered resources}}
    if {![dict exists $r validated_snapshot]} {error {Native client lacks its current source admission}}
    return $r
}
proc ::GX::_viewerNativeClientScope {window} {
    set r [_viewerNativeClientBase $window]
    set scope [datasetPublicationV2DictDefault $r native_client_event_scope {}]
    if {$scope eq {} || [winfo id $window] ne [dict get $scope incarnation] || [dict get $r lifetime] ne [dict get $scope lifetime] ||
        [dict get $r module] ne [dict get $scope module] || [dict get $r generation] ne [dict get $scope generation] ||
        [_viewerNativeClientSessionToken] ne [dict get $scope session_token]} {error {Native client Session/window changed during its event}}
    if {[_viewerDevelopmentSnapshot [dict get $r project]] ne [dict get $r validated_snapshot] || ![dict exists $r native_client_package_snapshot] ||
        [_viewerNativeClientPackageSnapshot [dict get $r runtime_module_root]] ne [dict get $r native_client_package_snapshot]} {error {Native client source/package changed after admission; reopen the updated module}}
    return $scope
}
proc ::GX::_viewerGuiScriptLibraryGuard {window form operation} {
    set r [_viewerNativeClientBase $window]
    if {{script_library_command} ni [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $r native_client_grants {}] SCRIPT_LIBRARY_API_v1 {}]} {error {Script Library operation lacks its explicit admitted native capability}}
    set design [dict get $::GX::ViewerGui::instances $window design]
    if {[datasetPublicationV2DictDefault $design target viewer] ne {viewer}} {error {Script Library requires an actual Viewer}}
    set maps [_viewerGuiClientRoleMapsValidate $design]
    if {![dict exists $maps $form script_library_components]} {error {Script Library requires its complete actual component role map}}
    set lifecycle {snapshot dispose capture restore review id_review draft_changed source_notification}
    set commands {list select new_script new_project source_select save copy_record assign_session open_workspace run_review import_script import_project export delete jobs refresh close undo redo find replace cut copy_text paste select_all}
    if {$operation ni [concat $lifecycle $commands]} {error {Unknown Script Library operation}}
    if {$operation in $commands && ![scientificHistoryViewerEditable $window] && $operation ni {copy_text select_all find jobs close}} {
        if {$operation ne {source_select} || ![dict exists $::GX::ScientificHistory::viewers $window] || ![dict get $::GX::ScientificHistory::viewers $window browsing] || [dict get $::GX::ScientificHistory::viewers $window restoring]} {error {History browsing is read-only. Return to latest before changing Script Library state}}
    }
    set userAction 0
    if {$operation ni $lifecycle} {
        set scope [_viewerNativeClientScope $window];set userAction [dict get $scope user_action]
        if {!$userAction && $operation ni {list refresh}} {error {Script Library operation requires an explicit declared user action}}
        if {$operation in {select new_script new_project save copy_record assign_session import_script import_project delete close} && [dict get $scope effect] ne {mutating}} {error {Script Library write/review requires an explicit mutating handler}}
    }
    set ids [dict get $maps $form script_library_components];set widgets {}
    dict for {role id} $ids {
        if {![dict exists $::GX::ViewerGui::instances $window widgets $id]} {error {Declared Script Library component has closed}}
        set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
        if {![winfo exists $widget]} {error {Declared Script Library component has closed}}
        dict set widgets $role $widget
    }
    return [dict create module_id [dict get $r module] session_token [_viewerNativeClientSessionToken] components $widgets component_ids $ids user_action $userAction]
}
proc ::GX::_viewerNativeClientLibraryViewTyped {view} {
    if {[dict exists $view conflict_message]} {dict set view conflict_message [_viewerNativeClientPublicMessage [dict get $view conflict_message]]}
    if {[dict exists $view source_read_error]} {dict set view source_read_error [_viewerNativeClientPublicMessage [dict get $view source_read_error]]}
    set selected {record {reference text revision int sha256 text draft_token text}}
    set item {record {reference text scope text language text kind text id text name text version text revision int sha256 text}}
    set inventory [list record [dict create offset int limit int total int records [list array $item]]]
    set typed [nativeWorkspaceEncode [list record [dict create selected $selected inventory $inventory draft {record {scope text language text dirty bool}} selected_row_reference text selected_relative_file text selection_valid bool conflict_message text source_read_valid bool source_read_error text]] $view]
    foreach optional {selected draft} {if {[datasetPublicationV2DictDefault $view $optional {}] eq {}} {lset typed 1 [dict replace [lindex $typed 1] $optional {null {}}]}}
    return $typed
}
proc ::GX::_viewerNativeClientPublicMessage {message} {
    set message [string map [list \x00 {}] [string range $message 0 2047]]
    # The host retains diagnostics. A worker receives no local absolute path.
    regsub -all {/[^\s"'<>]+} $message {[host path]} message
    regsub -all {[A-Za-z]:\\[^\s"'<>]+} $message {[host path]} message
    return $message
}
proc ::GX::_viewerNativeClientEnvelope {operation status error result view sequence generation} {
    set value [list object [dict create operation [list text $operation] status [list text $status] error [list text [_viewerNativeClientPublicMessage $error]] result $result view $view sequence [list int $sequence] event_generation [list int $generation]]]
    if {[string length [encoding convertto utf-8 [_viewerWorkspaceTypedJson $value]]]>49152} {error {Native client receipt exceeds 48 KiB; complete identities are never truncated}}
    return $value
}
proc ::GX::_viewerNativeClientLibrarySnapshot {window} {
    set r [_viewerNativeClientBase $window];set views {}
    set maps [_viewerGuiClientRoleMapsValidate [dict get $::GX::ViewerGui::instances $window design]]
    dict for {form properties} $maps {
        if {![dict exists $properties script_library_components]} continue
        lappend views [_viewerNativeClientLibraryViewTyped [viewerGuiScriptLibrarySnapshot $window $form]]
    }
    if {[llength $views]!=1} {error {Script Library native context requires exactly one controller form}}
    set view [lindex $views 0]
    set receipt [datasetPublicationV2DictDefault $r script_library_result [_viewerNativeClientEnvelope snapshot completed {} {null {}} $view 0 0]]
    # Typed values are two-element Tcl lists, not dictionaries.
    set fields [lindex $receipt 1];dict set fields view $view;set receipt [list object $fields]
    set json [_viewerWorkspaceTypedJson $receipt]
    if {[string length [encoding convertto utf-8 $json]]>49152} {error {Script Library receipt exceeds 48 KiB; narrow the inventory page}}
    return $json
}
proc ::GX::_viewerNativeClientLibraryCommand {window form intent} {
    set scope [_viewerNativeClientScope $window]
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    set sequence [expr {[datasetPublicationV2DictDefault $r script_library_sequence 0]+1}]
    dict set ::GX::ViewerDevelopment::windows $window script_library_sequence $sequence
    set operation [dict get $intent command]
    try {
        _viewerGuiScriptLibraryGuard $window $form $operation
        set typedRequest [_viewerWorkspaceSdkValue [dict get $intent request]]
        if {$operation eq {select} && [lindex $typedRequest 0] eq {object} && [dict exists [lindex $typedRequest 1] review_owner] && [lindex [dict get [lindex $typedRequest 1] review_owner] 0] ne {bool}} {error {Native owner review requires a typed Boolean flag}}
        set request [nativeWorkspaceDecode $typedRequest]
        set outcome [viewerGuiScriptLibraryCommand $window $form $operation $request]
        if {![winfo exists $window] || ![dict exists $::GX::ViewerDevelopment::windows $window]} return
        _viewerNativeClientScope $window
        set status [dict get $outcome status]
        if {$status ni {completed cancelled pending}} {error {Script Library returned an unknown command status}}
        set view [_viewerNativeClientLibraryViewTyped [viewerGuiScriptLibrarySnapshot $window $form]]
        set result [expr {$status eq {cancelled}?{null {}}:{object {}}}]
        set receipt [_viewerNativeClientEnvelope $operation $status [dict get $outcome message] $result $view $sequence [dict get $scope generation]]
        dict set ::GX::ViewerDevelopment::windows $window script_library_result $receipt
    } on error {message options} {
        if {[dict exists $::GX::ViewerDevelopment::windows $window] && [winfo exists $window] && [winfo id $window] eq [dict get $scope incarnation]} {
            set view {object {}}
            catch {set view [_viewerNativeClientLibraryViewTyped [viewerGuiScriptLibrarySnapshot $window $form]]}
            dict set ::GX::ViewerDevelopment::windows $window script_library_result [_viewerNativeClientEnvelope $operation failed [string range $message 0 2047] {null {}} $view $sequence [dict get $scope generation]]
        }
        return -options $options $message
    }
}
proc ::GX::_viewerNativeClientEventFailed {window response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]} return
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    if {![datasetPublicationV2DictDefault $r script_library_input 0]} return
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {if {[lindex $key 0] eq $window} {_scriptLibraryHostFileHighlight $key}}
    set old [datasetPublicationV2DictDefault $r script_library_result {object {}}]
    set fields [lindex $old 1]
    if {[dict exists $fields status] && [lindex [dict get $fields status] 1] eq {failed} && [dict exists $fields event_generation] && [lindex [dict get $fields event_generation] 1]==[dict get $r generation]} return
    set message {Native Script Library event failed}
    foreach key {host_error error} {if {[dict exists $response $key]} {set message [dict get $response $key]}}
    if {[dict exists $response result errors]} {set message [join [dict get $response result errors] {; }]}
    set sequence [expr {[datasetPublicationV2DictDefault $r script_library_sequence 0]+1}]
    dict set ::GX::ViewerDevelopment::windows $window script_library_sequence $sequence
    dict set ::GX::ViewerDevelopment::windows $window script_library_result [_viewerNativeClientEnvelope native_event failed [string range $message 0 2047] {null {}} {object {}} $sequence [dict get $r generation]]
}
proc ::GX::_viewerGuiScriptLibrarySourceEvent {window form actual} {
    set context [_viewerGuiScriptLibraryGuard $window $form snapshot]
    if {$actual ne [dict get $context component_ids source_files]} {error {Script Library source event belongs to another declared component}}
    if {![winfo ismapped [dict get $context components source_files]]} return
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict get $r status] eq {RUNNING} || [dict get $r busy] ne {}} return
    dict set ::GX::ViewerDevelopment::windows $window script_library_source_event $actual
    viewerDevelopmentInvoke $window __script_library_source_select__
}
proc ::GX::_viewerGuiScriptLibraryDraftChanged {window form} {
    _viewerGuiScriptLibraryGuard $window $form draft_changed
    # Source buffers use the existing typed Workspace/resource capture, never
    # a native event or the bounded48KiB control receipt.
    _viewerGuiScriptLibraryHistorySchedule $window
    viewerGuiTraceEmit $window $form changed [dict create status local_draft owner SCRIPT_EXECUTION_API_v1]
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerNativeClientDisposed {window} {
    _viewerGuiScriptLibraryHistoryCancel $window
    # Tk owns destruction of dynamic children. Retire only this closed host's
    # disposable controller records, never Registry/source data.
    foreach key [dict keys $::GX::ScriptLibraryHost::bindings] {
        if {[lindex $key 0] eq $window} {dict unset ::GX::ScriptLibraryHost::bindings $key}
    }
}
source [file join $::GX::scriptDir core tcl viewer_script_library_workspace_v1.tcl]
