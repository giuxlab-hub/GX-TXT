# SPDX-License-Identifier: GPL-3.0-or-later
# Reentrant local transaction extension of the canonical Dataset Catalog.
# Existing Dataset resources remain authoritative; the journal contains undo
# preimages only and must never be treated as reusable cache or age-deleted.
namespace eval ::GX {
    variable datasetAuthorityChannel {}
    variable datasetAuthoritySession {}
    variable datasetAuthorityBaseline {}
    variable datasetAuthorityLoadedSession {}
    variable datasetAuthorityNotification {}
    variable datasetAuthorityFailure {}
    variable datasetAuthorityReadSnapshot {}
}
proc ::GX::datasetAuthorityActive {{session {}}} {
    variable datasetAuthorityChannel;variable datasetAuthoritySession
    expr {$datasetAuthorityChannel ne {} && ($session eq {} || [file normalize $session] eq $datasetAuthoritySession)}
}
proc ::GX::datasetAuthorityRequest {command {argument {}}} {
    variable datasetAuthorityChannel
    puts $datasetAuthorityChannel "$command\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $argument]]"
    flush $datasetAuthorityChannel
    if {[gets $datasetAuthorityChannel response]<0} {error {Dataset transaction worker exited unexpectedly; reopen Session to recover}}
    if {$response ne "OK"} {error [encoding convertfrom utf-8 [binary decode base64 [lindex [split $response \t] 1]]]}
}
proc ::GX::datasetAuthorityEnlist {path} {
    if {![datasetAuthorityActive]} {error {Dataset mutation requires the CORE transaction authority}}
    datasetAuthorityRequest ENLIST [file normalize $path]
}
proc ::GX::datasetAuthorityRecord {} {
    set records {}
    foreach id [datasetRegistryIds] {
        set fields {}
        foreach key [lsort [array names ::GX::datasetRegistry "$id,*"]] {dict set fields $key $::GX::datasetRegistry($key)}
        dict set records $id $fields
    }
    return $records
}
proc ::GX::datasetAuthorityLoaded {session} {
    variable datasetAuthorityBaseline;variable datasetAuthorityLoadedSession
    variable datasetAuthorityReadSnapshot
    set datasetAuthorityLoadedSession [file normalize $session]
    set datasetAuthorityBaseline [datasetAuthorityRecord]
    # One bounded read hint, never another persistence or recovery authority.
    # Exact registry bytes distinguish same-size edits within one timestamp tick.
    set datasetAuthorityReadSnapshot {}
    set path [datasetRegistryPath $session]
    if {[file isfile $path] && [file type $path] eq "file" && [file size $path]<=4194304} {
        set fd [open $path rb]
        try {set bytes [read $fd 4194305]} finally {close $fd}
        if {[string length $bytes]<=4194304} {
            set datasetAuthorityReadSnapshot [list $datasetAuthorityLoadedSession $bytes]
        }
    }
}
proc ::GX::datasetAuthorityReadUnchanged {session} {
    variable datasetAuthorityBaseline;variable datasetAuthorityLoadedSession
    variable datasetAuthorityReadSnapshot
    set session [file normalize $session]
    if {$datasetAuthorityReadSnapshot eq {} || $session ne $datasetAuthorityLoadedSession ||
        $session ne [lindex $datasetAuthorityReadSnapshot 0] ||
        [datasetAuthorityRecord] ne $datasetAuthorityBaseline} {return 0}
    set journal [file join $session metadata .dataset_transactions]
    # Recovery/staging always goes through the existing locked authority. Check
    # both sides of the read so an in-progress multi-file commit is never reused.
    if {[glob -nocomplain -directory $journal txn-* stage-*] ne {}} {return 0}
    set path [datasetRegistryPath $session]
    if {![file isfile $path] || [file type $path] ne "file" || [file size $path]>4194304} {return 0}
    set fd [open $path rb]
    try {set bytes [read $fd 4194305]} finally {close $fd}
    if {$bytes ne [lindex $datasetAuthorityReadSnapshot 1]} {return 0}
    if {[glob -nocomplain -directory $journal txn-* stage-*] ne {}} {return 0}
    return 1
}
proc ::GX::datasetAuthorityTransaction {session command args} {
    variable datasetAuthorityChannel;variable datasetAuthoritySession
    variable datasetAuthorityBaseline;variable datasetAuthorityLoadedSession
    variable datasetRegistry;variable scriptDir;variable datasetAuthorityNotification;variable datasetAuthorityFailure
    set session [file normalize $session]
    if {[datasetAuthorityActive $session]} {return [uplevel 1 [list $command {*}$args]]}
    if {[datasetAuthorityActive]} {error {A Dataset transaction cannot switch Sessions}}
    set pending [datasetAuthorityRecord];set baseline $datasetAuthorityBaseline
    set hasBaseline [expr {$datasetAuthorityLoadedSession eq $session}]
    set python [runtimeToolRequired python]
    set channel [open [list | $python -u [file join $scriptDir core python dataset_authority.py] $session] r+]
    fconfigure $channel -encoding utf-8 -translation lf -buffering line
    if {[gets $channel ready]<0 || $ready ne "OK"} {catch {close $channel};error {Cannot acquire/recover the Dataset authority}}
    set datasetAuthorityChannel $channel;set datasetAuthoritySession $session
    if {[info commands ::GX::resourceManagementObserve] ne {}} {
        catch {resourceManagementObserve [file join $session metadata .dataset_transactions] dataset_publication [dict create category protected_authoritative session $session recovery_required 1 lifetime recovery owner_pid [pid]]}
    }
    set datasetAuthorityNotification {};set datasetAuthorityFailure {};set committed 0
    try {
        loadDatasetRegistry_before_catalog $session
        set disk [datasetAuthorityRecord]
        # Legacy callers intentionally edit the in-memory registry before Save.
        # Merge only their changed records, and CAS against their last disk read.
        if {$hasBaseline} {
            foreach id [lsort -unique [concat [dict keys $baseline] [dict keys $pending]]] {
                set before [expr {[dict exists $baseline $id] ? [dict get $baseline $id] : {}}]
                set after [expr {[dict exists $pending $id] ? [dict get $pending $id] : {}}]
                if {$before eq $after} continue
                set current [expr {[dict exists $disk $id] ? [dict get $disk $id] : {}}]
                if {$current ne $before} {error "Dataset '$id' changed concurrently; reload before saving"}
                foreach key [array names datasetRegistry "$id,*"] {unset datasetRegistry($key)}
                array set datasetRegistry $after
            }
        }
        set result [uplevel 1 [list $command {*}$args]]
        if {$datasetAuthorityFailure ne {}} {error "Dataset transaction aborted after a nested failure: $datasetAuthorityFailure"}
        # Lazy read adapters may add projection-only fields to memory. The CAS
        # baseline must describe the actual registry as the acquisition loader
        # sees it, not those unsaved fields. Preserve the caller's pending view
        # while refreshing the baseline under the same lock. Do this before the
        # durable marker so a loader failure can still abort the transaction.
        set pendingAfter [array get datasetRegistry]
        try {
            loadDatasetRegistry_before_catalog $session
        } finally {
            array unset datasetRegistry *
            array set datasetRegistry $pendingAfter
        }
        datasetAuthorityRequest COMMIT
        set committed 1
        return $result
    } on error {message options} {
        if {[catch {datasetAuthorityRequest ABORT} rollback]} {
            return -options $options "$message; Dataset recovery remains pending: $rollback"
        }
        catch {loadDatasetRegistry_before_catalog $session}
        return -options $options $message
    } finally {
        catch {datasetAuthorityRequest QUIT};catch {close $channel}
        set notification $datasetAuthorityNotification;set datasetAuthorityNotification {}
        set datasetAuthorityChannel {};set datasetAuthoritySession {}
        if {$committed && $notification ne {}} {datasetCatalogObserve {*}$notification}
    }
}
proc ::GX::datasetRevisionToken {datasetId {session {}}} {
    variable currentSession
    if {$session eq {}} {set session $currentSession}
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetRevisionToken $datasetId $session]}
    variable datasetRegistry
    # Read the persisted canonical descriptor, not its mutable lazy projection.
    # The v2/v3 access adapters can enrich in-memory schema during a read; those
    # derived defaults are not a new scientific Dataset revision. Reuse CORE's
    # raw registry loader and restore the caller's pending state unconditionally.
    set pending [array get datasetRegistry]
    try {
        loadDatasetRegistry_v1_before_schema $session
        if {[datasetField $datasetId id {}] eq {}} {error "Unknown Dataset '$datasetId'"}
        set record [dict get [datasetAuthorityRecord] $datasetId]
        lassign [_datasetMetadataPath $session $datasetId] rel path
        set hash [expr {[file isfile $path] ? [sha256File $path] : {}}]
    } finally {
        array unset datasetRegistry *
        array set datasetRegistry $pending
    }
    # Persisted namespace/schema-only changes still invalidate a binding even
    # when payload SHA-256 stays unchanged.
    return [list dataset-revision-v1 [file normalize $session] $datasetId $record $hash]
}
proc ::GX::datasetAuthorityFault {point} {
    # Fault injection is an explicit process-local validation hook, never set
    # by runtime/script requests or persisted configuration.
    if {[info exists ::GX::datasetAuthorityTestFault] && $::GX::datasetAuthorityTestFault eq $point} {
        # Kill the lock/journal helper too, proving restart recovery rather than
        # relying on its graceful parent-EOF rollback.
        catch {exec kill -KILL {*}[pid $::GX::datasetAuthorityChannel]}
        exec kill -KILL [pid]
    }
}

# Explicit idempotent recovery for supervisor cancellation/restart reconciliation.
# The same lock excludes live commits; no filename-age or arbitrary cleanup.
proc ::GX::datasetPublicationRecover {session} {
    return [datasetAuthorityTransaction $session ::GX::_datasetPublicationRecovered $session]
}
proc ::GX::_datasetPublicationRecovered {session} {
    loadDatasetRegistry $session
    return [dict create session [file normalize $session] recovered 1 dataset_ids [datasetRegistryIds]]
}

proc ::GX::datasetPublicationStageTrack {session path {worker {}} {remove 0}} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetPublicationStageTrack $session $path $worker $remove]}
    datasetAuthorityRequest [expr {$remove ? "UNSTAGE" : "STAGE"}] "$path\t$worker"
}
