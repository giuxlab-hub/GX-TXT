# SPDX-License-Identifier: GPL-3.0-or-later
# Session-local aggregates of canonical Dataset identities. All mutations enlist
# in the existing Dataset authority journal; this is not another Dataset store.
proc ::GX::datasetGroupApiInfo {} {
    return [dict create api_id DATASET_GROUP_API_v1 api_version 1 schema gxtxt.dataset_groups.v1 \
        operations {datasetGroupList datasetGroupGet datasetGroupForDataset datasetGroupCreate datasetGroupMove datasetGroupDetach datasetGroupUngroup datasetGroupProducerReviewV1 datasetGroupProducerCreateV1 datasetGroupHostReviewV1 datasetGroupHostCreateV1} \
        authority Dataset_Authority persistence metadata/dataset_groups.tcldict script_mutation 0 producer_scoped_mutation 1 producer_api DATASET_GROUP_PRODUCER_API_v1]
}
proc ::GX::_datasetGroupHistoryValidate {events} {
    if {[llength $events]>128} {error {Dataset Group history exceeds 128 events}}
    foreach event $events {
        if {[catch {dict size $event}] || [lsort [dict keys $event]] ne {action at details revision}} {error {Invalid Dataset Group history event}}
        foreach field {at revision} {if {![string is wideinteger -strict [dict get $event $field]] || [dict get $event $field]<0} {error {Invalid Dataset Group history counter}}}
        if {![regexp {^[a-z][a-z0-9_.-]{0,63}$} [dict get $event action]] || [catch {dict size [dict get $event details]} size] || $size>16} {error {Invalid Dataset Group history action/details}}
        dict for {key value} [dict get $event details] {
            if {[string length $key]>64 || [string length $value]>512 || [string first \x00 $key]>=0 || [string first \x00 $value]>=0} {error {Invalid Dataset Group history detail}}
        }
    }
    return $events
}
proc ::GX::_datasetGroupHistoryAppend {storeName groupId action details} {
    upvar 1 $storeName store
    set events [datasetPublicationV2DictDefault [dict get $store groups $groupId] history {}]
    lappend events [dict create action $action at [clock seconds] revision [dict get $store groups $groupId revision] details $details]
    dict set store groups $groupId history [_datasetGroupHistoryValidate [lrange $events end-127 end]]
}
proc ::GX::_datasetGroupPath {session} {
    set session [file normalize $session]
    set path [file join $session metadata dataset_groups.tcldict]
    foreach item [list [file join $session metadata] $path] {
        if {![catch {file type $item} kind] && $kind eq {link}} {error {Dataset Group storage must not contain symlinks}}
    }
    return $path
}
proc ::GX::_datasetGroupStoreRead {session} {
    set empty [dict create schema gxtxt.dataset_groups.v1 groups {}]
    if {$session eq {}} {return $empty}
    set path [_datasetGroupPath $session]
    if {![file exists $path]} {return $empty}
    if {![file isfile $path] || [file size $path]>1048576} {error {Invalid or oversized Dataset Group descriptor}}
    set fd [open $path rb]
    try {set value [encoding convertfrom utf-8 [read $fd 1048577]]} finally {close $fd}
    if {[catch {dict size $value}] || ![dict exists $value schema] ||
        [dict get $value schema] ne {gxtxt.dataset_groups.v1} || ![dict exists $value groups] ||
        [catch {dict size [dict get $value groups]} size] || $size>1000} {error {Invalid Dataset Group schema}}
    dict for {id group} [dict get $value groups] {
        acquisitionHandlerValidateDatasetId $id {Dataset Group ID}
        foreach field {group_id display_name group_contract revision namespace primary_dataset_id members source} {
            if {![dict exists $group $field]} {error "Dataset Group '$id' is missing '$field'"}
        }
        if {[dict get $group group_id] ne $id || ![string is integer -strict [dict get $group revision]] ||
            [dict get $group revision]<1 || [llength [dict get $group members]]<1 || [llength [dict get $group members]]>1000} {error {Invalid Dataset Group identity or membership}}
        datasetNamespaceNormalize [dict get $group namespace]
        set seen {}
        foreach member [dict get $group members] {
            foreach field {dataset_id role required contract canonical_sha256} {if {![dict exists $member $field]} {error {Invalid Dataset Group member}}}
            set memberId [acquisitionHandlerValidateDatasetId [dict get $member dataset_id] {Dataset Group member}]
            if {$memberId in $seen || ![string is boolean -strict [dict get $member required]]} {error {Duplicate or invalid Dataset Group member}}
            lappend seen $memberId
        }
        if {[dict get $group primary_dataset_id] ni $seen} {error {Dataset Group primary must be a member}}
        if {[dict exists $group history]} {_datasetGroupHistoryValidate [dict get $group history]}
    }
    return $value
}
proc ::GX::_datasetGroupStoreWrite {session store} {
    if {![datasetAuthorityActive $session]} {error {Dataset Group mutation requires the Dataset authority}}
    set bytes [encoding convertto utf-8 $store]
    if {[string length $bytes]>1048576 || [dict size [dict get $store groups]]>1000} {error {Dataset Group descriptor exceeds its bound}}
    set path [_datasetGroupPath $session]
    datasetAuthorityEnlist $path
    resourceLifecycleWriteBytes $path $bytes
    datasetCatalogObserve $session groups
}
proc ::GX::_datasetGroupRequireAdmin {session} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Dataset Group changes require user/admin authority}}
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the selected Session before changing Dataset Groups}}
    return $session
}
proc ::GX::datasetGroupList {session} {
    set session [_sessionInspectionRequire $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupList $session]}
    return [dict values [dict get [_datasetGroupStoreRead $session] groups]]
}
proc ::GX::datasetGroupGet {session groupId} {
    set session [_sessionInspectionRequire $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupGet $session $groupId]}
    set store [_datasetGroupStoreRead $session]
    if {![dict exists $store groups $groupId]} {error "Unknown Dataset Group '$groupId'"}
    set group [dict get $store groups $groupId]
    set issues {}
    foreach member [dict get $group members] {
        set id [dict get $member dataset_id]
        if {[datasetField $id id {}] eq {}} {
            lappend issues [dict create dataset_id $id reason missing required [dict get $member required]]
        } elseif {[datasetField $id canonical_sha256 [datasetField $id sha256 {}]] ne [dict get $member canonical_sha256] ||
            [datasetField $id contract [datasetField $id kind {}]] ne [dict get $member contract]} {
            lappend issues [dict create dataset_id $id reason changed required [dict get $member required]]
        } elseif {[datasetNamespaceGet $session $id] ne [dict get $group namespace]} {
            lappend issues [dict create dataset_id $id reason namespace_mismatch required [dict get $member required]]
        } elseif {![dict exists $group source $id]} {
            lappend issues [dict create dataset_id $id reason missing_source_identity required [dict get $member required]]
        } else {
            foreach field {source_module source_sha256 source_raw} {
                if {![dict exists $group source $id $field] || [datasetField $id $field {}] ne [dict get $group source $id $field]} {
                    lappend issues [dict create dataset_id $id reason source_changed field $field required [dict get $member required]]
                }
            }
        }
    }
    dict set group status [expr {[llength $issues] ? "DEGRADED" : "COMPLETE"}]
    dict set group issues $issues
    return $group
}
proc ::GX::datasetGroupForDataset {session datasetId} {
    set session [_sessionInspectionRequire $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupForDataset $session $datasetId]}
    foreach group [datasetGroupList $session] {
        foreach member [dict get $group members] {if {[dict get $member dataset_id] eq $datasetId} {return [dict get $group group_id]}}
    }
    return {}
}
proc ::GX::datasetGroupCreate {session definition} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupCreate $session $definition]}
    return [_datasetGroupCreate $session $definition]
}
# One validated storage/lifecycle implementation, called only after host or
# producer authorization inside the same Dataset Authority transaction.
proc ::GX::_datasetGroupCreate {session definition {producer {}}} {
    if {![datasetAuthorityActive $session]} {error {Dataset Group creation requires the Dataset authority}}
    foreach field {group_id display_name group_contract primary_dataset_id members} {
        if {![dict exists $definition $field]} {error "Dataset Group declaration requires '$field'"}
    }
    set groupId [acquisitionHandlerValidateDatasetId [dict get $definition group_id] {Dataset Group ID}]
    set store [_datasetGroupStoreRead $session]
    if {[dict exists $store groups $groupId]} {error "Dataset Group '$groupId' already exists"}
    set contract [dict get $definition group_contract]
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $contract] || [string length $contract]>128} {error {Invalid qualified Dataset Group contract}}
    set label [dict get $definition display_name]
    if {[string length $label]>512 || [regexp {[\x00\r\n]} $label]} {error {Invalid Dataset Group display name}}
    set members {};set ids {};set namespace {};set sources {}
    if {[llength [dict get $definition members]]<1 || [llength [dict get $definition members]]>1000} {error {A Dataset Group requires 1–1000 members}}
    foreach item [dict get $definition members] {
        foreach field {dataset_id role required} {if {![dict exists $item $field]} {error "Dataset Group member requires '$field'"}}
        set id [acquisitionHandlerValidateDatasetId [dict get $item dataset_id] {Dataset Group member}]
        if {$id in $ids || [datasetField $id id {}] eq {}} {error "Duplicate or missing canonical Dataset '$id'"}
        if {[datasetGroupForDataset $session $id] ne {}} {error "Dataset '$id' already belongs to a group"}
        set role [dict get $item role]
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $role] || [string length $role]>128 || ![string is boolean -strict [dict get $item required]]} {error {Invalid Dataset Group role or required flag}}
        set placement [datasetNamespaceGet $session $id]
        if {$namespace eq {}} {set namespace $placement} elseif {$namespace ne $placement} {error {All Dataset Group members must share one namespace}}
        set sha [datasetField $id canonical_sha256 [datasetField $id sha256 {}]]
        if {![regexp {^[a-fA-F0-9]{64}$} $sha]} {error "Dataset '$id' has no canonical content fingerprint"}
        if {[dict exists $item contract] && [dict get $item contract] ne [datasetField $id contract [datasetField $id kind {}]]} {error "Dataset '$id' contract differs from the declared member contract"}
        if {[dict exists $item canonical_sha256] && ![string equal -nocase [dict get $item canonical_sha256] $sha]} {error "Dataset '$id' fingerprint differs from the declared member fingerprint"}
        lappend ids $id
        lappend members [dict create dataset_id $id role $role required [expr {!![dict get $item required]}] \
            contract [datasetField $id contract [datasetField $id kind {}]] canonical_sha256 $sha]
        dict set sources $id [dict create source_module [datasetField $id source_module {}] source_sha256 [datasetField $id source_sha256 {}] source_raw [datasetField $id source_raw {}] source_name [file tail [datasetField $id source_raw {}]]]
    }
    if {[dict exists $definition namespace] && [datasetNamespaceNormalize [dict get $definition namespace]] ne $namespace} {error {Dataset Group namespace conflicts with its actual members}}
    set primary [dict get $definition primary_dataset_id]
    if {$primary ni $ids} {error {Dataset Group primary must be an actual member}}
    set group [dict create group_id $groupId display_name $label group_contract $contract revision 1 \
        namespace $namespace primary_dataset_id $primary members $members source $sources created_at [clock seconds]]
    if {$producer ne {}} {dict set group producer_module $producer;dict set group producer_api DATASET_GROUP_PRODUCER_API_v1}
    dict set store groups $groupId $group
    _datasetGroupHistoryAppend store $groupId create [dict create namespace $namespace]
    _datasetGroupStoreWrite $session $store
    return [datasetGroupGet $session $groupId]
}
proc ::GX::datasetGroupProducerApiInfoV1 {} {
    return [dict create api_id DATASET_GROUP_PRODUCER_API_v1 api_version 1 \
        operations {datasetGroupProducerReviewV1 datasetGroupProducerCreateV1 datasetProducerPublishBatchV1} \
        authority CORE_issued_producer_capability member_authority exact_producer_and_namespace \
        grouping opt_in publication_engine DATASET_PUBLICATION_API_v2 revision opaque_full_dataset_revision \
        source_file_association SOURCE_NOTE_API_v1]
}
proc ::GX::_datasetGroupProducer {capability session} {
    variable ::GX::DatasetPrivate::owners
    variable ::GX::DatasetPrivate::activeContext
    if {![dict exists $owners $capability]} {error {Invalid Dataset producer capability}}
    set producer [dict get $owners $capability]
    if {[moduleField $producer descriptor {}] eq {}} {error {Dataset producer is no longer registered}}
    if {$activeContext ne {} && [dict get $activeContext capability] ne $capability} {error {Dataset producer capability does not match the active module}}
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Dataset producer operation requires its current open Session}}
    return $producer
}
proc ::GX::_datasetGroupProducerMember {session producer id} {
    if {[acquisitionHandlerValidateDatasetId $id] ne $id || [string length $id]>256 || [datasetField $id id {}] ne $id} {error {Invalid or missing canonical Dataset identity}}
    if {[datasetField $id producer_module [datasetField $id source_module {}]] ne $producer} {error "Producer may group only its own canonical outputs: $id"}
    set namespace [datasetNamespaceGet $session $id]
    set assigned [datasetNamespaceForModule $producer]
    if {$namespace ne $assigned && [string first "$assigned/" $namespace]!=0} {
        set grants [datasetNamespaceSharedInputs $session]
        if {![dict exists $grants $namespace] || $producer ni [dict get $grants $namespace]} {error {Producer is not authorized for the member Dataset namespace}}
    }
    # Validate the actual canonical payload against its registered fingerprint;
    # no writer, replacement, copying or republishing is involved.
    sessionInspectionDatasetPayload $id $session
}
proc ::GX::_datasetGroupDefinitionIds {definition} {
    if {[catch {dict size $definition}]} {error {Dataset Group requires a declaration dictionary}}
    foreach key [dict keys $definition] {
        if {$key ni {group_id display_name group_contract primary_dataset_id members namespace}} {error "Unsupported Dataset Group declaration field '$key'"}
    }
    foreach key {group_id display_name group_contract primary_dataset_id members} {if {![dict exists $definition $key]} {error "Dataset Group declaration requires '$key'"}}
    set groupId [dict get $definition group_id]
    if {[acquisitionHandlerValidateDatasetId $groupId] ne $groupId || [string length $groupId]>256} {error {Malformed Dataset Group identity}}
    set ids {}
    foreach item [dict get $definition members] {
        foreach key [dict keys $item] {if {$key ni {dataset_id role required contract canonical_sha256}} {error "Unsupported Dataset Group member field '$key'"}}
        foreach key {dataset_id role required} {if {![dict exists $item $key]} {error "Dataset Group member requires '$key'"}}
        set id [dict get $item dataset_id]
        if {[acquisitionHandlerValidateDatasetId $id] ne $id || [string length $id]>256 || $id in $ids} {error {Malformed or duplicate Dataset Group member identity}}
        lappend ids $id
    }
    if {[llength $ids]<1 || [llength $ids]>64} {error {Producer/reviewed Dataset Groups require 1..64 members}}
    return $ids
}
proc ::GX::datasetGroupProducerReviewV1 {capability session datasetIds} {
    set producer [_datasetGroupProducer $capability $session]
    set session [file normalize $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupProducerReviewV1 $capability $session $datasetIds]}
    if {[llength $datasetIds]>64} {error {Review at most 64 Dataset Group members}}
    set revisions {}
    foreach id $datasetIds {
        if {[dict exists $revisions $id]} {error {Duplicate Dataset Group review member}}
        _datasetGroupProducerMember $session $producer $id
        dict set revisions $id [datasetRevisionToken $id $session]
    }
    return [dict create schema gxtxt.dataset_group_review.v1 session_token [interactiveDocumentSessionToken] producer_module $producer dataset_revisions $revisions]
}
proc ::GX::_datasetGroupReviewCheck {session definition review {producer {}}} {
    if {[catch {dict size $review}] || ![dict exists $review schema] || [dict get $review schema] ne {gxtxt.dataset_group_review.v1}} {error {Invalid Dataset Group review}}
    foreach key {session_token producer_module dataset_revisions} {if {![dict exists $review $key]} {error "Dataset Group review requires '$key'"}}
    if {[dict get $review session_token] ne [interactiveDocumentSessionToken] || [dict get $review producer_module] ne $producer} {error {Session or producer changed since Dataset Group review}}
    set ids [_datasetGroupDefinitionIds $definition]
    if {[lsort $ids] ne [lsort [dict keys [dict get $review dataset_revisions]]]} {error {Dataset Group members differ from the reviewed outputs}}
    foreach id $ids {
        if {$producer ne {}} {_datasetGroupProducerMember $session $producer $id} else {sessionInspectionDatasetPayload $id $session}
        if {[datasetRevisionToken $id $session] ne [dict get $review dataset_revisions $id]} {error "Dataset '$id' changed since Group review"}
    }
}
proc ::GX::datasetGroupProducerCreateV1 {capability session definition review} {
    set producer [_datasetGroupProducer $capability $session]
    set session [file normalize $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupProducerCreateV1 $capability $session $definition $review]}
    return [datasetCatalogTransaction ::GX::_datasetGroupProducerCreateV1 $capability $session $definition $review]
}
proc ::GX::_datasetGroupProducerCreateV1 {capability session definition review} {
    set producer [_datasetGroupProducer $capability $session]
    _datasetGroupReviewCheck $session $definition $review $producer
    return [_datasetGroupCreate $session $definition $producer]
}
# Host review is deliberately separate from producer authority: the GUI obtains
# this snapshot before explicit user confirmation of independently owned inputs.
proc ::GX::datasetGroupHostReviewV1 {session datasetIds} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupHostReviewV1 $session $datasetIds]}
    if {[llength $datasetIds]<1 || [llength $datasetIds]>64} {error {Review 1..64 Dataset Group members}}
    set revisions {}
    foreach id $datasetIds {
        if {[acquisitionHandlerValidateDatasetId $id] ne $id || [dict exists $revisions $id]} {error {Malformed or duplicate Dataset Group member}}
        sessionInspectionDatasetPayload $id $session
        dict set revisions $id [datasetRevisionToken $id $session]
    }
    return [dict create schema gxtxt.dataset_group_review.v1 session_token [interactiveDocumentSessionToken] producer_module {} dataset_revisions $revisions]
}
proc ::GX::datasetGroupHostCreateV1 {session definition review} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupHostCreateV1 $session $definition $review]}
    return [datasetCatalogTransaction ::GX::_datasetGroupHostCreateV1 $session $definition $review]
}
proc ::GX::_datasetGroupHostCreateV1 {session definition review} {
    _datasetGroupReviewCheck $session $definition $review
    return [_datasetGroupCreate $session $definition]
}
proc ::GX::_datasetGroupRequireRevision {group expected} {
    if {![string is integer -strict $expected] || $expected != [dict get $group revision]} {error {Dataset Group changed; reload before modifying it}}
}
proc ::GX::datasetGroupMove {session groupId namespace expectedRevision} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupMove $session $groupId $namespace $expectedRevision]}
    set group [datasetGroupGet $session $groupId]
    _datasetGroupRequireRevision $group $expectedRevision
    if {[dict get $group status] ne {COMPLETE}} {error {Cannot move a degraded Dataset Group; inspect its members}}
    set namespace [datasetNamespaceNormalize $namespace]
    if {[lindex [split $namespace /] 0] eq {pending}} {error {Pending is reserved for unimported sources}}
    foreach member [dict get $group members] {
        # Use the existing placement owner after explicitly authorizing this
        # whole-group operation; the outer journal rolls back every sidecar.
        _datasetNamespaceSetUngrouped $session [dict get $member dataset_id] $namespace
    }
    set store [_datasetGroupStoreRead $session]
    dict set store groups $groupId namespace $namespace
    dict incr group revision
    dict set store groups $groupId revision [dict get $group revision]
    _datasetGroupHistoryAppend store $groupId move [dict create from_namespace [dict get $group namespace] to_namespace $namespace]
    _datasetGroupStoreWrite $session $store
    return [datasetGroupGet $session $groupId]
}
proc ::GX::datasetGroupDetach {session groupId datasetId expectedRevision} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupDetach $session $groupId $datasetId $expectedRevision]}
    set group [datasetGroupGet $session $groupId]
    _datasetGroupRequireRevision $group $expectedRevision
    set remaining {};set found 0
    foreach member [dict get $group members] {
        if {[dict get $member dataset_id] eq $datasetId} {set found 1} else {lappend remaining $member}
    }
    if {!$found} {error {Dataset is not a member of this group}}
    set store [_datasetGroupStoreRead $session]
    if {$remaining eq {}} {
        dict unset store groups $groupId
    } else {
        dict set store groups $groupId members $remaining
        dict unset store groups $groupId source $datasetId
        if {[dict get $group primary_dataset_id] eq $datasetId} {dict set store groups $groupId primary_dataset_id [dict get [lindex $remaining 0] dataset_id]}
        dict set store groups $groupId revision [expr {[dict get $group revision]+1}]
        _datasetGroupHistoryAppend store $groupId detach [dict create dataset_id $datasetId]
    }
    _datasetGroupStoreWrite $session $store
    return [dict create detached_dataset_id $datasetId group_id $groupId remaining_count [llength $remaining]]
}
proc ::GX::datasetGroupUngroup {session groupId expectedRevision} {
    set session [_datasetGroupRequireAdmin $session]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetGroupUngroup $session $groupId $expectedRevision]}
    set group [datasetGroupGet $session $groupId]
    _datasetGroupRequireRevision $group $expectedRevision
    set store [_datasetGroupStoreRead $session]
    dict unset store groups $groupId
    _datasetGroupStoreWrite $session $store
    return [dict create group_id $groupId ungrouped 1 datasets_preserved 1]
}
proc ::GX::_datasetGroupDatasetRenamed {session oldId newId} {
    if {![datasetAuthorityActive $session]} {error {Grouped Dataset rename requires the Dataset authority}}
    set groupId [datasetGroupForDataset $session $oldId]
    if {$groupId eq {}} {return}
    set store [_datasetGroupStoreRead $session]
    set members {}
    foreach member [dict get $store groups $groupId members] {
        if {[dict get $member dataset_id] eq $oldId} {dict set member dataset_id $newId}
        lappend members $member
    }
    dict set store groups $groupId members $members
    if {[dict get $store groups $groupId primary_dataset_id] eq $oldId} {dict set store groups $groupId primary_dataset_id $newId}
    set source [dict get $store groups $groupId source $oldId]
    dict unset store groups $groupId source $oldId
    dict set store groups $groupId source $newId $source
    dict set store groups $groupId revision [expr {[dict get $store groups $groupId revision]+1}]
    _datasetGroupHistoryAppend store $groupId rename_member [dict create old_dataset_id $oldId new_dataset_id $newId]
    _datasetGroupStoreWrite $session $store
}
