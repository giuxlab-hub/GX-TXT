# SPDX-License-Identifier: GPL-3.0-or-later
# Only authorized Session transport changes physical History ownership. The
# native engine verifies and serializes all records; this code never edits frames.
proc ::GX::scientificHistoryPortableDrain {session} {
    set session [file normalize $session];set owned {};set revisions {}
    if {[info exists ::GX::ScientificHistory::viewers]} {
        dict for {context adapter} $::GX::ScientificHistory::viewers {
            if {[dict get $adapter session] ne $session} continue
            set status [scientificHistoryViewerFlush $context 30000 0]
            lappend owned [dict get $adapter path]
            dict set revisions [dict get $adapter path] [dict create accepted_revision [dict get $status accepted_revision] durable_revision [dict get $status durable_revision]]
        }
    }
    return [dict create owned [lsort -unique $owned] revisions $revisions]
}
proc ::GX::_historyPortableHeader {family} {
    set path [expr {[file isfile "$family.checkpoint"] ? "$family.checkpoint" : $family}]
    if {![file isfile $path] || [file type $path] ne {file}} {error {History transport requires a regular journal/checkpoint}}
    set f [open $path rb]
    try {
        set prefix [read $f 12]
        if {[string length $prefix]!=12 || [string range $prefix 0 7] ne "GXH17\x00\x02\n"} {error {Unsupported native History transport header}}
        binary scan [string range $prefix 8 11] cu4 bytes
        set count [expr {[lindex $bytes 0] | ([lindex $bytes 1]<<8) | ([lindex $bytes 2]<<16) | ([lindex $bytes 3]<<24)}]
        if {$count<1 || $count>65536} {error {History transport identity exceeds its bound}}
        set encoded [read $f $count]
        if {[string length $encoded]!=$count || [string length [read $f 32]]!=32} {error {Incomplete native History transport header}}
    } finally {close $f}
    set identity [encoding convertfrom utf-8 $encoded]
    if {[catch {llength $identity}] || [string first \x00 $identity]>=0 || [llength $identity]<4} {error {Malformed inert History ownership identity}}
    if {[file pathtype [lindex $identity 0]] ne {absolute} || ![string is entier -strict [lindex $identity 1]] || ![string is entier -strict [lindex $identity 2]]} {error {Malformed physical History identity}}
    return $identity
}
proc ::GX::_historyPortableFamilies {session {documents all}} {
    set directory [file join $session metadata history];set result {}
    foreach root [expr {$documents eq {all} ? [list $directory [file join $directory drafts]] : [list $directory]}] {
        if {![file exists $root]} continue
        if {[file type $root] ne {directory}} {error {History transport directory is unsafe}}
        foreach path [glob -nocomplain -directory $root *.gxh *.gxh.checkpoint] {
            if {[string match *.checkpoint $path]} {set path [string range $path 0 end-11]}
            set name [file tail $path]
            if {[file tail $root] eq {drafts}} {
                if {![regexp {^[0-9]+-[0-9]+-[0-9]+\.gxh$} $name]} {error {Invalid native draft filename}}
            } else {
                if {![regexp {^(idoc_[0-9]{4,})(?:\.([A-Za-z][A-Za-z0-9_]{0,63}))?\.gxh$} $name -> id channel]} {error {Invalid native Document History filename}}
                if {$documents ne {all} && $id ni $documents} continue
            }
            lappend result $path
        }
    }
    return [lsort -unique $result]
}
proc ::GX::_historyPortableVerify {session family registry} {
    _historyNativeRequire
    set identity [_historyPortableHeader $family];set owner [lindex $identity 3]
    _interactiveDocumentValidateOwner $owner history_transport
    set tail [file tail $family];set draft [expr {[file tail [file dirname $family]] eq {drafts}}]
    set channel {}
    if {$draft} {
        set fields [lrange $identity 4 end]
        if {[llength $fields]==4 && [lindex $fields 0] eq {channel}} {set channel [lindex $fields 1];set fields [lrange $fields 2 end]}
        if {$fields ne [list draft $tail]} {error {History draft ownership does not match its transport family}}
    } else {
        regexp {^(idoc_[0-9]{4,})(?:\.([A-Za-z][A-Za-z0-9_]{0,63}))?\.gxh$} $tail -> document channel
        if {![dict exists $registry $document]} {error {History transport references an absent Document owner}}
        set item [dict get $registry $document]
        set fields [list [dict get $item module_id] $document [dict get $item generation] [dict get $item provider_id]]
        if {$channel ne {}} {lappend fields channel $channel}
        if {[lrange $identity 3 end] ne $fields} {error {History transport Document/module/generation/provider/channel ownership mismatch}}
    }
    if {$channel ne {} && ![regexp {^[A-Za-z][A-Za-z0-9_]{0,63}$} $channel]} {error {Invalid native History transport channel}}
    # The bounded header is inert input, never authorization by itself. Native
    # recovery verifies its hash, every complete frame and the record contract.
    set recovered [historyNative recover $family $identity]
    set record [dict get $recovered record]
    if {[dict get $record workbench_id] ne $owner} {error {History scientific owner differs from its verified transport identity}}
    return [dict create identity $identity owner $owner recovered $recovered]
}
proc ::GX::_historyPortableSnapshot {source destination documents owned} {
    set helper [file join $::GX::scriptDir core python scientific_history_portable_copy.py]
    set command [list [runtimeToolRequired python] $helper $source $destination]
    if {$documents ne {all}} {foreach id $documents {lappend command --document $id}}
    foreach path $owned {lappend command --owned $path}
    exec {*}$command 2>@1
}
proc ::GX::scientificHistoryPortableVerifySession {session owned} {
    set f [file tempfile temporary];close $f;file delete -- $temporary
    try {
        _historyPortableSnapshot $session $temporary all $owned
        set registry [_interactiveDocumentRegistryRead $session]
        foreach family [_historyPortableFamilies $temporary] {_historyPortableVerify $temporary $family $registry}
    } finally {if {[file exists $temporary]} {file delete -force -- $temporary}}
}
proc ::GX::scientificHistoryPortableRecords {session document {owned {}}} {
    set f [file tempfile temporary];close $f;file delete -- $temporary
    try {
        _historyPortableSnapshot $session $temporary [list $document] $owned
        set registry [_interactiveDocumentRegistryRead $session];set result {}
        foreach family [_historyPortableFamilies $temporary [list $document]] {lappend result [dict get [_historyPortableVerify $temporary $family $registry] recovered record]}
        return $result
    } finally {if {[file exists $temporary]} {file delete -force -- $temporary}}
}
proc ::GX::scientificHistoryPortableRescope {stage logicalDestination {documents all}} {
    set stage [file normalize $stage];set logicalDestination [file normalize $logicalDestination]
    set registry [_interactiveDocumentRegistryRead $stage];file stat $stage stat
    set receipts {}
    # The caller owns an unpublished import/clone transaction. Process one
    # bounded native record at a time; any later error aborts that whole stage
    # before its final Session rename, preserving source/archive bytes.
    foreach family [_historyPortableFamilies $stage $documents] {
        set value [_historyPortableVerify $stage $family $registry]
        set identity [dict get $value identity]
        set next [lreplace $identity 0 2 $logicalDestination $stat(dev) $stat(ino)]
        set recovered [dict get $value recovered];set record [dict get $recovered record]
        # Auxiliary presentation state is native-owned but intentionally absent
        # from the scientific recipe. Preserve it through the same new owner.
        set auxiliary [datasetPublicationV2DictDefault $recovered auxiliary {}]
        set relative [string range $family [expr {[string length [file join $stage metadata history]]+1}] end]
        set archive [file join $stage metadata history transport_archives "[clock microseconds]-[pid]" $relative]
        file mkdir [file dirname $archive]
        set rawHashes {}
        foreach suffix {{} .checkpoint} {if {[file isfile "$family$suffix"]} {dict set rawHashes $suffix [sha256File "$family$suffix"]}}
        foreach suffix {{} .checkpoint} {if {[file exists "$family$suffix"]} {file rename -- "$family$suffix" "$archive$suffix"}}
        set h [historyNative open [dict get $value owner] $record $family $next $auxiliary]
        try {
            set status [historyNative flush $h 30000]
            set rewritten [historyNative record $h]
            if {[dict get $rewritten steps] ne [dict get $record steps] || [dict get $rewritten cursor] ne [dict get $record cursor] || [dict get $rewritten base] ne [dict get $record base]} {error {Native History transport changed scientific state}}
            if {[historyNative auxiliary $h] ne $auxiliary} {error {Native History transport changed auxiliary presentation state}}
        } finally {historyNative close $h}
        set receipt [dict create family $relative source_identity $identity destination_identity $next source_accepted_revision [dict get $recovered revision] source_durable_revision [dict get $recovered durable_revision] raw_sha256 $rawHashes destination_durable_revision [dict get $status durable_revision] torn_tail [dict get $recovered torn_tail] policy authorized_new_session_revision_epoch scientific_steps_changed 0 auxiliary_preserved 1]
        set f [open "$archive.receipt.tcldict" {WRONLY CREAT EXCL}];try {fconfigure $f -encoding utf-8;puts $f $receipt} finally {close $f}
        lappend receipts $receipt
    }
    return $receipts
}
proc ::GX::scientificHistoryPortableCopyDocuments {source stage documents owned logicalDestination} {
    if {$documents eq {}} {return {}}
    set f [file tempfile temporary];close $f;file delete -- $temporary
    try {
        _historyPortableSnapshot $source $temporary $documents $owned
        set directory [file join $temporary metadata history]
        if {![file isdirectory $directory]} {return {}}
        file mkdir [file join $stage metadata]
        if {[file exists [file join $stage metadata history]]} {error {Clone History authority was already copied by another path}}
        file copy -- $directory [file join $stage metadata history]
        return [scientificHistoryPortableRescope $stage $logicalDestination $documents]
    } finally {if {[file exists $temporary]} {file delete -force -- $temporary}}
}
