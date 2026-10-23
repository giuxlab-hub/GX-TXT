# SOURCE ONLY. Existing public Document/Resource owners; no private PCB/storage reads.
if {$argc!=9} {error {Usage: readback.tcl ROOT OUTPUT SESSION DOCUMENT GUI_GENERATION GUI_REVISION GUI_SHA ORIGINAL_DEADLINE_MS SOURCE_ID}}
namespace eval ::GX210PCBReadback {
    lassign $::argv root output session document guiGeneration guiRevision guiSha deadline sourceId
    variable here [file dirname [file normalize [info script]]]
    variable phase admission;variable status FAIL;variable checks {};variable resources {}
    variable before {};variable after {};variable identitySource {};variable reader {};variable sourceObservation {}
}
proc ::GX210PCBReadback::require {yes} {if {!$yes} {error {PCB public readback refused}}}
proc ::GX210PCBReadback::admit {} {require [expr {[clock milliseconds]<$::GX210PCBReadback::deadline}]}
proc ::GX210PCBReadback::write {path bytes} {
    set f [open $path {WRONLY CREAT EXCL} 0600]
    try {fconfigure $f -encoding binary -translation binary;puts -nonewline $f $bytes} finally {close $f}
}
proc ::GX210PCBReadback::policy {} {
    variable here
    # QA-owned fixed inert policy, never a Session/Resource storage pathname.
    set path [file join $here POLICY.tcldict];file lstat $path s
    require [expr {$s(type) eq {file} && $s(nlink)==1 && [file owned $path] && $s(size)<=16384}]
    set f [open $path rb];try {set data [read $f 16385]} finally {close $f}
    require [expr {[string length $data]<=16384 && ![catch {dict size $data}]}]
    return $data
}
proc ::GX210PCBReadback::listed {module provider id} {
    admit
    set rows [::GX::interactiveDocumentList $module $provider]
    require [expr {[llength $rows]<=128}]
    set found {}
    foreach row $rows {
        if {[dict get $row id] eq $id} {require [expr {$found eq {}}];set found $row}
    }
    require [expr {$found ne {}}]
    return $found
}
proc ::GX210PCBReadback::sameMetadata {listed read} {
    require [expr {[lsort [dict keys $read]] eq [lsort [concat [dict keys $listed] payload]]}]
    dict for {key value} $listed {require [expr {[dict get $read $key] eq $value}]}
}
set ::argv0 __gx210_pcb_public_resource_readback__
namespace eval ::GX210PCBReadback {
try {
    require [expr {[string is wideinteger -strict $deadline] && $deadline<[clock milliseconds]+120000}]
    admit
    set p [policy]
    require [expr {$document eq $sourceId && [regexp {^idoc_[0-9]{4,}$} $document]}]
    set phase global_source
    uplevel #0 [list source [file join $root gxtxt_pipeline.tcl]]
    set phase defaults
    ::GX::defaults
    set phase configuration_load
    ::GX::configurationLoad
    set phase catalog
    ::GX::loadModuleCatalog
    set phase noTk
    require [expr {![llength [info commands winfo]]}]
    set phase reopen_same_owned_session
    # Same headless reopen sequence used by normal Script Job request/server.
    # No GUI refresh/render wrapper or replacement Session is constructed.
    set ::GX::currentSession $session
    ::GX::loadManifest [file join $session metadata manifest.ini]
    set ::GX::currentSession $session
    ::GX::loadDatasetRegistry $session
    require [expr {[::GX::sessionInspectionCurrentSession] eq $session}]
    set token [::GX::interactiveDocumentSessionToken]
    set module [dict get $p module_id];set provider [dict get $p provider_id]
    require [expr {[::GX::moduleField $module version {}] eq {0.1.0}}]
    set phase public_list_read
    set before [listed $module $provider $document]
    require [expr {[dict get $before module_id] eq $module && [dict get $before provider_id] eq $provider &&
        [dict get $before format] eq [dict get $p source_kind] && [dict get $before format_version] eq {1}}]
    set identitySource first_public_owner_observation_not_external_GUI_pin
    set supplied [expr {$guiGeneration ne {} || $guiRevision ne {} || $guiSha ne {}}]
    if {$supplied} {
        require [expr {$guiGeneration ne {} && [string is wideinteger -strict $guiRevision] &&
            [regexp {^[0-9a-f]{64}$} $guiSha] && [dict get $before generation] eq $guiGeneration &&
            [dict get $before revision] eq $guiRevision && [dict get $before sha256] eq $guiSha}]
        set identitySource genuine_GUI_handoff_observation_matched
    }
    set record [::GX::interactiveDocumentRead $document]
    sameMetadata $before $record
    set payload [dict get $record payload]
    require [expr {[string length [encoding convertto utf-8 $payload]]<=262144 &&
        [lsort [dict keys $payload]] eq {artifacts descriptors license originals pair_stamp parser schema state summary worker_sha256}}]
    require [expr {[dict get $payload schema] eq [dict get $p source_kind] && [dict get $payload state] eq {completed} &&
        [dict get $payload parser] eq {gxtxt.eagle_paired_source.v1} &&
        [dict get $payload pair_stamp] eq [dict get $p pair_stamp] &&
        [dict get $payload worker_sha256] eq [dict get $p worker_sha256]}]
    set names [dict get $p names]
    require [expr {[lsort [dict keys [dict get $payload artifacts]]] eq [lsort $names] &&
        [lsort [dict keys [dict get $payload descriptors]]] eq [lsort $names]}]
    set summary [dict get $payload summary]
    require [expr {[dict get $summary resource_count]==10 && [dict get $summary pair_stamp] eq [dict get $p pair_stamp] &&
        [dict get $summary unit_policy] eq [dict get $p unit_policy]}]
    dict for {key value} [dict get $p structural_counts] {require [expr {[dict get $summary structural_counts $key] eq $value}]}
    require [expr {[dict get $summary actual_point_count]==226}]
    foreach role {board schematic} {
        require [expr {[dict get $payload originals $role sha256] eq [dict get $p originals $role sha256] &&
            [dict get $payload originals $role copy] eq [dict get $p originals $role copy]}]
    }
    set license [dict get $payload license]
    dict for {key value} [dict get $p license] {require [expr {[dict get $license $key] eq $value}]}
    set sourceObservation [dict create source_kind [dict get $payload schema] pair_stamp [dict get $payload pair_stamp] worker_sha256 [dict get $payload worker_sha256] originals [dict get $payload originals] summary $summary license $license]
    dict set checks canonical_public_identity 1
    file mkdir [file join $output snapshots];file attributes [file join $output snapshots] -permissions 0700
    set total 0
    foreach name $names {
        set phase public_stream_$name;admit
        set ref [dict get $payload artifacts $name];set descriptor [dict get $payload descriptors $name]
        require [expr {[lsort [dict keys $descriptor]] eq {bytes mode name sha256} &&
            [dict get $descriptor name] eq $name && [dict get $descriptor mode] eq {384} &&
            [regexp {^[0-9a-f]{64}$} [dict get $descriptor sha256]] &&
            [string is wideinteger -strict [dict get $descriptor bytes]] && [dict get $descriptor bytes]>0}]
        set maximum 16777216
        if {$name in {board.original.brd schematic.original.sch}} {set maximum 4194304}
        if {$name eq {SOURCE_LICENSE.md}} {set maximum 65536}
        require [expr {[dict get $descriptor bytes]<=$maximum &&
            [dict get $ref api_id] eq {INTERACTIVE_DOCUMENT_RESOURCE_API_v1} &&
            [dict get $ref document_id] eq $document && [dict get $ref owner_generation] eq [dict get $before generation] &&
            [dict get $ref sha256] eq [dict get $descriptor sha256] && [dict get $ref size_bytes]==[dict get $descriptor bytes]}]
        set metadata [dict get $ref metadata]
        require [expr {[dict get $metadata format] eq {gxtxt.pcb.eagle_pair.artifact.v1} &&
            [dict get $metadata role] eq $name && [dict get $metadata pair_stamp] eq [dict get $p pair_stamp] &&
            [dict get $metadata worker_sha256] eq [dict get $p worker_sha256]}]
        incr total [dict get $ref size_bytes];require [expr {$total<=100663296}]
        require [expr {[::GX::interactiveDocumentResourceInfo $ref] eq $ref}]
        set path [file join $output snapshots $name]
        set f [open $path {WRONLY CREAT EXCL} 0600];fconfigure $f -encoding binary -translation binary
        set received 0;set chunks 0;set eof 0
        try {
            set reader [::GX::interactiveDocumentResourceOpenReader $ref]
            set ri [::GX::interactiveDocumentResourceReaderInfo $reader]
            require [expr {[dict get $ri offset]==0 && [dict get $ri reference] eq $ref}]
            while {!$eof} {
                admit
                set chunk [::GX::interactiveDocumentResourceNext $reader 1048576]
                set bytes [dict get $chunk bytes];set count [dict get $chunk count]
                require [expr {[dict get $chunk offset]==$received && $count==[string length $bytes] && $count<=1048576}]
                puts -nonewline $f $bytes
                incr received $count;incr chunks
                set eof [dict get $chunk eof]
                require [expr {[string is boolean -strict $eof] && $chunks<=16 && $received<=$maximum && ($count>0 || $eof)}]
            }
            set ri [::GX::interactiveDocumentResourceReaderInfo $reader]
            require [expr {$received==[dict get $ref size_bytes] && [dict get $ri offset]==$received && [dict get $ri reference] eq $ref}]
        } finally {
            try {
                if {$reader ne {}} {::GX::interactiveDocumentResourceCloseReader $reader;set reader {}}
            } finally {close $f}
        }
        set digest [::GX::sha256File $path]
        require [expr {$digest eq [dict get $descriptor sha256]}]
        set independence descriptor_stream_owner_consistency_only
        if {[dict exists $p independent_sha256 $name]} {
            require [expr {$digest eq [dict get $p independent_sha256 $name]}]
            set independence independent_preexisting_original_or_license_sha
        }
        dict set resources $name [dict create reference $ref descriptor $descriptor received_bytes $received chunks $chunks checked_eof $eof actual_stream_sha256 $digest evidence_scope $independence]
    }
    set phase post_identity
    set after [listed $module $provider $document]
    set reread [::GX::interactiveDocumentRead $document]
    sameMetadata $after $reread
    require [expr {$after eq $before && [dict get $reread payload] eq $payload &&
        [::GX::sessionInspectionCurrentSession] eq $session && [::GX::interactiveDocumentSessionToken] eq $token && [dict size $resources]==10}]
    dict set checks all_ten_actual_public_streams_through_EOF 1
    dict set checks public_identity_preserved 1
    set phase complete;set status PASS
} on error {message options} {
    set status FAIL
} finally {
    if {$reader ne {}} {catch {::GX::interactiveDocumentResourceCloseReader $reader}}
    set report [dict create schema gxtxt.task210.pcb_canonical_readback.v1 status $status phase $phase session $session document_id $document source_id $sourceId identity_source $identitySource before $before after $after source_observation $sourceObservation checks $checks resources $resources whole_science_accepted 0 GUI_accepted 0 installed_accepted 0]
    write [file join $output READBACK_RESULT.tcldict] [encoding convertto utf-8 $report]
}
exit [expr {$status eq {PASS}?0:1}]
}
