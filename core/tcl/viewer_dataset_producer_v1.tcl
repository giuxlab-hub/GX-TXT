# SPDX-License-Identifier: GPL-3.0-or-later
# Owning-thread adapter to the existing producer/Publication owners. Receipts are
# transient event context, never authored Workspace state or a second registry.
proc ::GX::_viewerDatasetProducerTextObject {record} {
    set fields {};dict for {key value} $record {dict set fields $key [list text $value]}
    return [list object $fields]
}
proc ::GX::_viewerDatasetProducerReviewTyped {review} {
    set fields {};foreach key {schema session_token producer_module} {dict set fields $key [list text [dict get $review $key]]}
    set revisions {};dict for {id token} [dict get $review dataset_revisions] {dict set revisions $id [list text $token]}
    dict set fields dataset_revisions [list object $revisions]
    return [list object $fields]
}
proc ::GX::_viewerDatasetProducerGroupTyped {group} {
    set fields {}
    dict for {key value} $group {
        switch -- $key {
            revision - created_at {dict set fields $key [list int $value]}
            members {
                set rows {}
                foreach member $value {
                    set row {};dict for {name item} $member {dict set row $name [list [expr {$name eq {required}?{bool}:{text}}] $item]}
                    lappend rows [list object $row]
                }
                dict set fields $key [list array $rows]
            }
            source {set sources {};dict for {id record} $value {dict set sources $id [_viewerDatasetProducerTextObject $record]};dict set fields $key [list object $sources]}
            history {
                set rows {}
                foreach event $value {lappend rows [list object [dict create action [list text [dict get $event action]] at [list int [dict get $event at]] revision [list int [dict get $event revision]] details [_viewerDatasetProducerTextObject [dict get $event details]]]]}
                dict set fields $key [list array $rows]
            }
            issues {
                set rows {};foreach issue $value {set row {};dict for {name item} $issue {dict set row $name [list [expr {$name eq {required}?{bool}:{text}}] $item]};lappend rows [list object $row]};dict set fields $key [list array $rows]
            }
            default {dict set fields $key [list text $value]}
        }
    }
    return [list object $fields]
}
proc ::GX::_viewerDatasetProducerBatchTyped {batch} {
    set ids {};foreach id [dict get $batch dataset_ids] {lappend ids [list text $id]}
    set rows {}
    foreach dataset [dict get $batch datasets] {
        set fields {};foreach key {dataset_id storage_provider sha256} {dict set fields $key [list text [dict get $dataset $key]]}
        if {[dict exists $dataset integrity_seconds]} {dict set fields integrity_seconds [list real [dict get $dataset integrity_seconds]]}
        lappend rows [list object $fields]
    }
    set fields [dict create atomic [list bool [dict get $batch atomic]] output_count [list int [dict get $batch output_count]] dataset_ids [list array $ids] datasets [list array $rows]]
    if {[dict exists $batch dataset_group]} {dict set fields dataset_group [_viewerDatasetProducerGroupTyped [dict get $batch dataset_group]]}
    return [list object $fields]
}
proc ::GX::_viewerDatasetProducerScope {window scope} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerDevelopment::windows $window]} {error {Dataset producer Viewer lifetime ended}}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {$scope eq {} || [winfo id $window] ne [dict get $scope incarnation] || [dict get $record lifetime] ne [dict get $scope lifetime] ||
        [interactiveDocumentSessionToken] ne [dict get $scope session_token] || [dict get $record module] ne [dict get $scope module] ||
        [dict get $record generation] ne [dict get $scope generation]} {error {Dataset producer Session or window changed during the native event}}
    set module [dict get $record module]
    if {[datasetPublicationV2DictDefault $record dataset_producer_module {}] ne $module || [dict get $::GX::ViewerGui::instances $window module] ne $module ||
        [moduleField $module descriptor {}] eq {} || ![moduleIsEnabled $module] || [viewerProviderDefinition $module [dict get $record provider]] eq {} ||
        {RESTRICTED_VIEWER_CLIENT_API_v1} ni [modulePublicApiIds $module]} {error {Dataset producer must be the actual registered admitted native module}}
    if {![dict exists $record runtime_module_root] || [file normalize [file dirname [moduleField $module descriptor]]] ne [file normalize [dict get $record runtime_module_root]]} {error {Install the native producer normally before canonical publication}}
    return $module
}
proc ::GX::_viewerDatasetProducerApply {window scope request} {
    set module [_viewerDatasetProducerScope $window $scope]
    set command [dict get $request command]
    set grants [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] dataset_producer_grants {}]
    switch -- $command {
        review {set api DATASET_GROUP_API_v1;set operation datasetGroupProducerReviewV1}
        create {set api DATASET_GROUP_API_v1;set operation datasetGroupProducerCreateV1}
        publish_batch {set api DATASET_PUBLICATION_API_v2;set operation datasetProducerPublishBatchV1}
        default {error {Unknown finite Dataset producer operation}}
    }
    if {$operation ni [datasetPublicationV2DictDefault $grants $api {}]} {error {Dataset producer operation lacks its explicit admitted capability}}
    set typed [_viewerWorkspaceSdkValue [dict get $request value]]
    set value [nativeWorkspaceDecode $typed]
    set capability [dict get [_datasetPrivateModuleContext $module] capability]
    switch -- $command {
        review {
            if {[lindex $typed 0] ne {array} || [llength $value]>64} {error {Review requires 0..64 canonical Dataset IDs}}
            set result [_viewerDatasetProducerReviewTyped [datasetGroupProducerReviewV1 $capability $::GX::currentSession $value]]
        }
        create {
            if {[lindex $typed 0] ne {object} || [lsort [dict keys $value]] ne {definition review}} {error {Create requires definition and opaque full review}}
            set result [_viewerDatasetProducerGroupTyped [datasetGroupProducerCreateV1 $capability $::GX::currentSession [dict get $value definition] [dict get $value review]]]
        }
        publish_batch {
            if {[lindex $typed 0] ne {object}} {error {Publication batch requires a typed object}}
            if {[dict exists $value dataset_group] && {datasetGroupProducerCreateV1} ni [datasetPublicationV2DictDefault $grants DATASET_GROUP_API_v1 {}]} {error {Optional Dataset Group requires its explicit Create capability}}
            set result [_viewerDatasetProducerBatchTyped [datasetProducerPublishBatchV1 $capability $::GX::currentSession $value]]
        }
    }
    _viewerDatasetProducerScope $window $scope
    set receipt [list object [dict create operation [list text $command] status {text completed} result $result \
        sequence [list int [dict get $scope sequence]] event_generation [list int [dict get $scope generation]]]]
    if {[string bytelength [_viewerWorkspaceTypedJson $receipt]]>1048576} {error {Producer receipt exceeds 1 MiB; full revision strings cannot be truncated}}
    return $receipt
}
proc ::GX::_viewerDatasetProducerCommand {window scope request} {
    try {
        _viewerDatasetProducerScope $window $scope
        set serial [expr {[datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] dataset_producer_sequence 0]+1}]
        dict set ::GX::ViewerDevelopment::windows $window dataset_producer_sequence $serial
        dict set scope sequence $serial
        # The checked continuation remains inside the existing authority. A
        # Session/incarnation change during a yielding writer aborts that scope.
        set receipt [datasetCatalogTransaction ::GX::_viewerDatasetProducerApply $window $scope $request]
        dict set ::GX::ViewerDevelopment::windows $window dataset_producer_result $receipt
    } on error {message options} {
        if {$scope ne {} && ![catch {_viewerDatasetProducerScope $window $scope}]} {
            set serial [datasetPublicationV2DictDefault $scope sequence 0]
            dict set ::GX::ViewerDevelopment::windows $window dataset_producer_result [list object [dict create \
                operation [list text [dict get $request command]] status {text failed} error [list text [string range $message 0 2047]] \
                result {null {}} sequence [list int $serial] event_generation [list int [dict get $scope generation]]]]
        }
        return -options $options $message
    }
}
proc ::GX::_viewerDatasetProducerSnapshot {window} {
    set typed [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] dataset_producer_result {null {}}]
    set json [_viewerWorkspaceTypedJson $typed]
    if {[string bytelength $json]>1048576} {error {Producer context exceeds 1 MiB; full revision strings cannot be truncated}}
    return $json
}
proc ::GX::_viewerDatasetProducerEventFailed {window scope response} {
    if {$scope eq {} || [catch {_viewerDatasetProducerScope $window $scope}]} return
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    set previous [datasetPublicationV2DictDefault $record dataset_producer_result {null {}}]
    if {[lindex $previous 0] eq {object}} {
        set fields [lindex $previous 1]
        if {[dict exists $fields status] && [lindex [dict get $fields status] 1] eq {failed} &&
            [dict exists $fields event_generation] && [lindex [dict get $fields event_generation] 1] == [dict get $scope generation]} return
    }
    set message {Native producer event failed};set command native_event
    if {[dict exists $response result errors]} {set message [join [dict get $response result errors] {; }]}
    foreach candidate {review create publish_batch} {if {[string first dataset_producer.$candidate: $message]>=0} {set command $candidate;break}}
    foreach key {host_error error} {if {[dict exists $response $key]} {set message [dict get $response $key]}}
    set serial [expr {[datasetPublicationV2DictDefault $record dataset_producer_sequence 0]+1}]
    dict set ::GX::ViewerDevelopment::windows $window dataset_producer_sequence $serial
    dict set ::GX::ViewerDevelopment::windows $window dataset_producer_result [list object [dict create operation [list text $command] \
        status {text failed} error [list text [string range $message 0 2047]] result {null {}} sequence [list int $serial] event_generation [list int [dict get $scope generation]]]]
}
