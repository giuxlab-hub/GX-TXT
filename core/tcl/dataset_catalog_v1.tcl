# Observable catalog extension of CANONICAL_DATASET_API_v2.
# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] dataset_authority_v1.tcl]
namespace eval ::GX {
    variable datasetCatalogState [dict create]
    variable datasetCatalogCounter 0
    variable datasetCatalogSubscribers [dict create]
    variable datasetCatalogSubscriberCounter 0
    variable datasetCatalogDepth 0
    variable datasetCatalogNotifying 0
    variable datasetSelectorState [dict create]
}
proc ::GX::datasetCatalogObserve {session {kind changed} {renames {}}} {
    variable datasetCatalogState; variable datasetCatalogCounter
    variable datasetCatalogSubscribers; variable datasetCatalogNotifying
    variable datasetCatalogDepth
    if {$datasetCatalogDepth || $datasetCatalogNotifying} {return}
    if {[datasetAuthorityActive]} {set ::GX::datasetAuthorityNotification [list $session $kind $renames];return}
    set sessionPath [expr {$session eq "" ? "" : [file normalize $session]}]
    set token "catalog-session#[pid]-[clock clicks]"
    set namespace [datasetNamespaceCurrentGet $session]
    set entries [dict create]
    foreach id [datasetRegistryIds] {
        set fields [dict create]
        foreach key [lsort [array names ::GX::datasetRegistry "$id,*"]] {
            dict set fields [string range $key [expr {[string length $id]+1}] end] $::GX::datasetRegistry($key)
        }
        dict set entries $id $fields
    }
    set previous [dict create]
    set revisionBefore $datasetCatalogCounter
    if {[dict size $datasetCatalogState]} {
        set previous [dict get $datasetCatalogState entries]
        if {$sessionPath eq [dict get $datasetCatalogState session_path]} {
            set token [dict get $datasetCatalogState session_token]
            if {$kind ne "namespace"&&$entries eq $previous&&[dict exists $datasetCatalogState current_namespace]&&$namespace eq [dict get $datasetCatalogState current_namespace]} {return}
        } else {set kind session}
    } else {set kind session}
    set added {}; set deleted {}; set changed {}
    foreach id [dict keys $entries] {
        if {![dict exists $previous $id]} {lappend added $id} elseif {[dict get $previous $id] ne [dict get $entries $id]} {lappend changed $id}
    }
    foreach id [dict keys $previous] {if {![dict exists $entries $id]} {lappend deleted $id}}
    if {$kind eq "namespace"} {set changed [dict keys $entries]}
    set receipt [dict create session_token $token revision_before $revisionBefore revision_after [incr datasetCatalogCounter] change_kind $kind added $added deleted $deleted changed $changed renames $renames dataset_ids [concat $added $deleted $changed]]
    set history {}
    if {[dict exists $datasetCatalogState history]} {set history [dict get $datasetCatalogState history]}
    lappend history $receipt
    set datasetCatalogState [dict create current_namespace $namespace session_path $sessionPath session_token $token revision $datasetCatalogCounter entries $entries history [lrange $history end-127 end]]
    set datasetCatalogNotifying 1
    try {
        dict for {subscription spec} $datasetCatalogSubscribers {
            if {[dict get $spec session_token] ne $token && $kind ne "session"} continue
            # Subscriber failures are advisory and cannot undo a committed Dataset.
            catch {uplevel #0 [list {*}[dict get $spec callback] $receipt]}
        }
    } finally {set datasetCatalogNotifying 0}
}
proc ::GX::datasetCatalogRevision {{session ""}} {
    variable currentSession; variable datasetCatalogCounter
    variable datasetCatalogDepth; variable datasetCatalogNotifying
    if {$session eq ""} {set session $currentSession}
    if {!$datasetCatalogDepth && !$datasetCatalogNotifying} {
        if {$session ne ""} {::GX::loadDatasetRegistry $session}
        datasetCatalogObserve $session
    }
    return $datasetCatalogCounter
}
proc ::GX::datasetCatalogSnapshot {{session ""}} {
    variable datasetCatalogState
    datasetCatalogRevision $session
    if {![dict size $datasetCatalogState]} {return [dict create session_token "" revision 0 dataset_ids {} datasets {}]}
    set datasets {}
    dict for {id fields} [dict get $datasetCatalogState entries] {
        set item [dict create dataset_id $id]
        foreach key {kind display_name storage_provider storage_kind canonical_sha256 row_count} {
            dict set item $key [expr {[dict exists $fields $key] ? [dict get $fields $key] : ""}]
        }
        if {[dict exists $fields metadata_display_name] && [dict get $fields metadata_display_name] ne ""} {dict set item display_name [dict get $fields metadata_display_name]}
        dict set item namespace [_datasetNamespaceFromMetadata [dict get $datasetCatalogState session_path] [_datasetMetadataReadRegistered [dict get $datasetCatalogState session_path] $id]]
        lappend datasets $item
    }
    return [dict create current_namespace [dict get $datasetCatalogState current_namespace] session_token [dict get $datasetCatalogState session_token] revision [dict get $datasetCatalogState revision] dataset_ids [dict keys [dict get $datasetCatalogState entries]] datasets $datasets]
}
proc ::GX::datasetCatalogChangedSince {revision {session ""}} {
    variable datasetCatalogState
    if {![string is entier -strict $revision] || $revision<0} {error "Catalog revision must be a nonnegative integer"}
    set current [datasetCatalogRevision $session]
    set changes {}
    foreach receipt [dict get $datasetCatalogState history] {if {[dict get $receipt revision_after]>$revision} {lappend changes $receipt}}
    set first [dict get [lindex [dict get $datasetCatalogState history] 0] revision_before]
    return [dict create changed [expr {$current!=$revision}] revision $current reset_required [expr {$revision<$first || $revision>$current}] changes $changes]
}
proc ::GX::datasetCatalogSubscribe {callback {session ""}} {
    variable datasetCatalogSubscribers; variable datasetCatalogSubscriberCounter
    if {![llength $callback]} {error "Catalog subscriber requires a callback"}
    set snapshot [datasetCatalogSnapshot $session]
    set token "catalog-subscription#[incr datasetCatalogSubscriberCounter]"
    dict set datasetCatalogSubscribers $token [dict create callback $callback session_token [dict get $snapshot session_token]]
    return $token
}
proc ::GX::datasetCatalogUnsubscribe {token} {
    variable datasetCatalogSubscribers
    dict unset datasetCatalogSubscribers $token
}
proc ::GX::datasetCatalogTransaction {command args} {
    variable datasetCatalogDepth; variable currentSession
    variable datasetCatalogState
    set authoritySession $currentSession
    switch -glob -- $command {
        *saveDatasetRegistry_before_catalog - *datasetMetadata*_before_catalog -
        *datasetFilePublicationPublish_before_catalog - *datasetDelete_before_catalog -
        *datasetRename_before_catalog - *genericCsvBatchImportRowToSession_before_catalog -
        *_datasetNamespaceMigrateApply - *_datasetPublicationV2BatchExecute {set authoritySession [lindex $args 0]}
        *acquisitionHandlerImport*ToSession_before_catalog {set authoritySession [lindex $args 1]}
    }
    # Streaming finalize validates/closes/hashes outside the authority lock;
    # its commit continuation acquires the same transaction after that work.
    if {![string match *datasetPublicationV2Finalize_before_catalog $command] && $authoritySession ne {} && ![datasetAuthorityActive $authoritySession]} {
        return [datasetAuthorityTransaction $authoritySession ::GX::datasetCatalogTransaction $command {*}$args]
    }
    # saveDatasetRegistry may receive an already modified in-memory registry.
    # Never reload over it. Initialize from committed disk state only if needed.
    if {!$datasetCatalogDepth && ![dict size $datasetCatalogState]} {
        set pending [array get ::GX::datasetRegistry]
        try {datasetCatalogRevision} finally {
            array unset ::GX::datasetRegistry *
            array set ::GX::datasetRegistry $pending
        }
    }
    incr datasetCatalogDepth
    set code [catch {uplevel 1 [list $command {*}$args]} result options]
    incr datasetCatalogDepth -1
    if {$code && [datasetAuthorityActive]} {set ::GX::datasetAuthorityFailure $result}
    if {!$datasetCatalogDepth && !$code} {
        set session $currentSession
        switch -glob -- $command {
            *saveDatasetRegistry_before_catalog -
            *datasetMetadata*_before_catalog -
            *datasetFilePublicationPublish_before_catalog -
            *datasetDelete_before_catalog -
            *datasetRename_before_catalog -
            *genericCsvBatchImportRowToSession_before_catalog {set session [lindex $args 0]}
            *acquisitionHandlerImport*ToSession_before_catalog {set session [lindex $args 1]}
        }
        set renames {}
        if {[string match *datasetRename_before_catalog $command] && [lindex $args 1] ne [lindex $args 2]} {set renames [list [list [lindex $args 1] [lindex $args 2]]]}
        datasetCatalogObserve $session [expr {[llength $renames] ? "rename" : "committed"}] $renames
    }
    return -options $options $result
}
rename ::GX::loadDatasetRegistry ::GX::loadDatasetRegistry_before_catalog
proc ::GX::loadDatasetRegistry {session} {
    if {![datasetAuthorityActive $session]} {
        if {[datasetAuthorityReadUnchanged $session]} {
            datasetCatalogObserve $session
            return [datasetRegistryIds]
        }
        return [datasetAuthorityTransaction $session ::GX::loadDatasetRegistry $session]
    }
    set result [loadDatasetRegistry_before_catalog $session]
    datasetCatalogObserve $session
    return $result
}
# Wrap the final public commit authorities, preserving argument/return contracts.
foreach name {saveDatasetRegistry _datasetMetadataWriteAll datasetVariableSchemaUpdate datasetPublicationV2Finalize datasetFilePublicationPublish datasetPublicationProcessFile datasetDelete datasetRename acquisitionHandlerImportSourcesToSession acquisitionHandlerImportSourceToSession genericCsvBatchImportRowToSession} {
    if {![llength [info commands ::GX::$name]]} continue
    rename ::GX::$name ::GX::${name}_before_catalog
    proc ::GX::$name {args} [format {tailcall ::GX::datasetCatalogTransaction ::GX::%s_before_catalog {*}$args} $name]
}

# Shared JIT selector adapter. Choice callbacks retain existing label/filter models.
proc ::GX::datasetSelectorAttach {widget choices {changed ""}} {
    variable datasetSelectorState
    dict set datasetSelectorState $widget [dict create revision -1 choices $choices changed $changed]
    $widget configure -postcommand [list ::GX::datasetSelectorRefresh $widget]
    bind $widget <Destroy> +[list ::GX::datasetSelectorDetach $widget]
    datasetSelectorRefresh $widget
}
proc ::GX::datasetSelectorDetach {widget} {
    variable datasetSelectorState
    dict unset datasetSelectorState $widget
}
proc ::GX::datasetSelectorRefresh {widget} {
    variable datasetSelectorState
    if {![dict exists $datasetSelectorState $widget] || ![winfo exists $widget]} return
    set state [dict get $datasetSelectorState $widget]
    set revision [datasetCatalogRevision]
    if {$revision==[dict get $state revision]} return
    set value [$widget get]
    set choices [uplevel #0 [dict get $state choices]]
    $widget configure -values $choices
    # A missing current choice stays visible as historical input. Never choose another.
    $widget set $value
    dict set datasetSelectorState $widget revision $revision
    if {[dict get $state changed] ne ""} {uplevel #0 [list {*}[dict get $state changed] [datasetCatalogSnapshot]]}
}
