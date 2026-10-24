# SPDX-License-Identifier: GPL-3.0-or-later
# Host-owned recovery checkpoints. Only inert, bounded document data is stored;
# geometry remains in content-addressed Document resources, never copied here.
namespace eval ::GX::WorkbenchRecovery {variable maximumBytes 16777216;variable maximumReceipts 128;variable choices;variable serial 0}
proc ::GX::workbenchRecoveryApiInfo {} {
    return [dict create api_id WORKBENCH_RECOVERY_API_v1 api_version 1 provider workbench_recovery host_only 1 maximum_bytes 16777216 journal_encodings {utf8_v1 zlib_utf8_v1} maximum_receipts 128 operations {begin checkpoint inspect resolve mark_saved close forget} implicit_recovery 0]
}
proc ::GX::_workbenchRecoveryPath {document} {
    if {![interactiveDocumentIdValid $document]} {error "Invalid recovery Document ID"}
    set root [_interactiveDocumentRequireSession]
    foreach part [list metadata workbench_recovery "$document.gxr"] {
        set root [file join $root $part]
        if {![catch {file lstat $root state}]&&$state(type) eq "link"} {error "Recovery symlinks are forbidden"}
    }
    return $root
}
proc ::GX::_workbenchRecoveryDigest {bytes} {
    set f [file tempfile path]
    try {fconfigure $f -translation binary -encoding binary;puts -nonewline $f $bytes;close $f;set f {};return [sha256File $path]} finally {if {$f ne {}} {close $f};file delete -- $path}
}
proc ::GX::_workbenchRecoveryRead {document} {
    variable ::GX::WorkbenchRecovery::maximumBytes
    set path [_workbenchRecoveryPath $document]
    if {![file exists $path]} {return {}}
    if {![file isfile $path]||[file size $path]>$maximumBytes} {error "Recovery checkpoint exceeds its size limit or is not a regular file"}
    set f [open $path rb];try {set bytes [read $f [expr {$maximumBytes+1}]]} finally {close $f}
    set first [string first \n $bytes];set second [string first \n $bytes [expr {$first+1}]]
    set header [string range $bytes 0 [expr {$first-1}]]
    if {$first<0||$second<0||$header ni {GXTXT_RECOVERY_V1 GXTXT_RECOVERY_ZLIB_V1}} {error "Recovery checkpoint header is corrupt"}
    set sha [string range $bytes [expr {$first+1}] [expr {$second-1}]];set data [string range $bytes [expr {$second+1}] end]
    # Hash the exact stored envelope bytes, including compressed stream
    # boundaries. A permissive decoder must not hide appended corruption.
    if {![regexp {^[a-f0-9]{64}$} $sha]||[_workbenchRecoveryDigest $data] ne $sha} {error "Recovery checkpoint SHA-256 mismatch"}
    if {$header eq {GXTXT_RECOVERY_ZLIB_V1}} {
        if {[catch {set data [zlib decompress $data]} message]} {error "Recovery checkpoint compressed data is corrupt: $message"}
    }
    set state [encoding convertfrom utf-8 $data]
    if {[catch {dict size $state}]} {error "Recovery checkpoint data is corrupt"}
    foreach field {api_version document_id generation module_id provider_id clean saved latest receipts} {if {![dict exists $state $field]} {error "Recovery checkpoint is missing $field"}}
    if {[dict get $state api_version]!=1||[dict get $state document_id] ne $document||[dict get $state clean] ni {0 1}||[llength [dict get $state receipts]]>128} {error "Unsupported or malformed recovery checkpoint"}
    set owner [interactiveDocumentRead $document]
    foreach field {generation module_id provider_id} {if {[dict get $state $field] ne [dict get $owner $field]} {error "Recovery checkpoint belongs to a replaced Document owner"}}
    foreach which {saved latest} {
        set snapshot [dict get $state $which]
        foreach field {payload revision sha256 format format_version} {if {![dict exists $snapshot $field]} {error "Recovery $which snapshot is missing $field"}}
        if {[_workbenchRecoveryDigest [encoding convertto utf-8 [dict get $snapshot payload]]] ne [dict get $snapshot sha256]} {error "Recovery $which payload hash mismatch"}
    }
    return $state
}
proc ::GX::_workbenchRecoveryWrite {document state} {
    variable ::GX::WorkbenchRecovery::maximumBytes
    set path [_workbenchRecoveryPath $document];file mkdir [file dirname $path]
    set data [encoding convertto utf-8 $state]
    set header GXTXT_RECOVERY_V1;set encoded $data
    # saved/latest retain complete semantic History, often with repeated text.
    # Compress only the existing journal envelope; never omit either snapshot
    # or relocate scientific geometry out of its normal Document resources.
    if {[string length $encoded]+100>$maximumBytes} {
        set encoded [zlib compress $data];set header GXTXT_RECOVERY_ZLIB_V1
    }
    if {[string length $encoded]+100>$maximumBytes} {error "Recovery checkpoint exceeds the 16 MiB stored journal limit after lossless compression; retain bulk geometry in owned resources"}
    set bytes "$header\n[_workbenchRecoveryDigest $encoded]\n$encoded"
    set f [file tempfile temporary [file join [file dirname $path] .pending-]]
    try {
        fconfigure $f -translation binary -encoding binary;puts -nonewline $f $bytes;close $f;set f {}
        _workbenchRecoveryPath $document
        file rename -force -- $temporary $path;set temporary {}
    } finally {if {$f ne {}} {close $f};if {$temporary ne {}} {file delete -- $temporary}}
    return [dict create status committed document_id $document checkpoint_revision [dict get $state latest revision] clean [dict get $state clean]]
}
proc ::GX::_workbenchRecoverySnapshot {document} {
    return [dict remove [interactiveDocumentRead $document] id module_id provider_id generation created_at updated_at]
}
proc ::GX::workbenchRecoveryBegin {document} {
    set state [_workbenchRecoveryRead $document]
    if {$state eq {}} {
        set owner [interactiveDocumentRead $document];set snapshot [_workbenchRecoverySnapshot $document]
        set state [dict create api_version 1 document_id $document generation [dict get $owner generation] module_id [dict get $owner module_id] provider_id [dict get $owner provider_id] clean 0 saved $snapshot latest $snapshot receipts {}]
    } else {dict set state clean 0}
    return [_workbenchRecoveryWrite $document $state]
}
proc ::GX::workbenchRecoveryCheckpoint {document {receipt {}}} {
    variable ::GX::WorkbenchRecovery::maximumReceipts
    set state [_workbenchRecoveryRead $document]
    if {$state eq {}} {workbenchRecoveryBegin $document;set state [_workbenchRecoveryRead $document]}
    set snapshot [_workbenchRecoverySnapshot $document]
    if {[dict get $snapshot sha256] eq [dict get $state latest sha256]} {return [dict create status unchanged document_id $document checkpoint_revision [dict get $snapshot revision]]}
    dict set state latest $snapshot;dict set state clean 0
    dict lappend state receipts [dict create revision [dict get $snapshot revision] payload_sha256 [dict get $snapshot sha256] timestamp [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}] receipt $receipt]
    dict set state receipts [lrange [dict get $state receipts] end-[expr {$maximumReceipts-1}] end]
    return [_workbenchRecoveryWrite $document $state]
}
proc ::GX::workbenchRecoveryInspect {document} {
    if {[catch {set state [_workbenchRecoveryRead $document]} message]} {return [dict create status corrupt document_id $document reason $message recoverable 0]}
    if {$state eq {}} {return [dict create status absent document_id $document recoverable 0]}
    return [dict create status [expr {[dict get $state clean] ? "clean" : "unclean"}] document_id $document recoverable [expr {![dict get $state clean]}] saved_revision [dict get $state saved revision] checkpoint_revision [dict get $state latest revision] saved_sha256 [dict get $state saved sha256] checkpoint_sha256 [dict get $state latest sha256] receipts [dict get $state receipts] module_id [dict get $state module_id] provider_id [dict get $state provider_id]]
}
proc ::GX::workbenchRecoveryResolve {document choice} {
    if {$choice ni {recover saved}} {error "Choose recover or saved explicitly"}
    set state [_workbenchRecoveryRead $document]
    if {$state eq {}} {error "No recovery checkpoint exists"}
    set snapshot [dict get $state [expr {$choice eq "recover" ? "latest" : "saved"}]]
    # No automatic write on inspect/open. Only an explicit user resolution
    # restores the canonical Interactive Document through its normal API.
    set result [interactiveDocumentUpdate $document [dict get $snapshot payload] [dict get $snapshot format] [dict get $snapshot format_version]]
    return [dict merge $result [dict create status resolved recovery_choice $choice]]
}
proc ::GX::workbenchRecoveryMarkSaved {document} {
    if {[catch {set state [_workbenchRecoveryRead $document]} message]} {return [dict create status corrupt reason $message]}
    set snapshot [_workbenchRecoverySnapshot $document]
    if {$state eq {}} {
        set owner [interactiveDocumentRead $document]
        set state [dict create api_version 1 document_id $document generation [dict get $owner generation] module_id [dict get $owner module_id] provider_id [dict get $owner provider_id] receipts {}]
    }
    dict set state saved $snapshot;dict set state latest $snapshot;dict set state receipts {};dict set state clean 1
    return [_workbenchRecoveryWrite $document $state]
}
proc ::GX::workbenchRecoveryClose {document} {workbenchRecoveryMarkSaved $document}
proc ::GX::workbenchRecoveryForget {document} {
    set path [_workbenchRecoveryPath $document];if {[file exists $path]} {file delete -- $path};return $document
}
proc ::GX::_workbenchRecoveryResourceReferences {document {excludeOwner 0}} {
    set result {}
    if {[llength [info commands _historyResourceReferences]]} {lappend result {*}[ _historyResourceReferences]}
    foreach owner [interactiveDocumentList] {
        if {$excludeOwner&&[dict get $owner id] eq $document} continue
        # Corruption is already visible via Inspect; an unusable checkpoint
        # cannot prevent normal Session open or ordinary resource collection.
        if {[catch {set state [_workbenchRecoveryRead [dict get $owner id]]}]} continue
        if {$state ne {}} {lappend result [dict get $state saved payload] [dict get $state latest payload]}
    }
    return $result
}
proc ::GX::workbenchRecoveryPrompt {document {parent .}} {
    variable ::GX::WorkbenchRecovery::serial;variable ::GX::WorkbenchRecovery::choices
    set info [workbenchRecoveryInspect $document]
    if {![dict get $info recoverable]} {return $info}
    set w .workbenchRecovery[incr serial]
    toplevel $w;wm title $w "Recover Workbench state";wm geometry $w 680x460
    if {[winfo exists $parent]&&[winfo viewable $parent]} {wm transient $w $parent}
    ttk::label $w.message -text "This Workbench did not close cleanly. Choose the last consistent checkpoint or the last explicitly saved state." -wraplength 640
    pack $w.message -fill x -padx 16 -pady 16
    ttk::frame $w.inspection;pack $w.inspection -fill both -expand 1 -padx 16
    text $w.details -height 12 -wrap word
    ttk::scrollbar $w.scroll -orient vertical -command [list $w.details yview]
    $w.details configure -yscrollcommand [list $w.scroll set]
    $w.details insert end "Document: $document\nWorkbench: [dict get $info module_id]\nLast saved revision: [dict get $info saved_revision]\nLast committed checkpoint: [dict get $info checkpoint_revision]\nRecent operations: [llength [dict get $info receipts]]\n"
    foreach item [dict get $info receipts] {
        set receipt [dict get $item receipt];set operation [datasetPublicationV2DictDefault $receipt operation edit]
        if {![catch {dict get $operation operation} name]} {set operation $name}
        $w.details insert end "\nRevision [dict get $item revision] — $operation — [dict get $item timestamp]\n"
        if {[dict exists $receipt module_version]} {$w.details insert end "Plugin version: [dict get $receipt module_version]\n"}
        if {[dict exists $receipt operation result_ids]} {$w.details insert end "Results: [join [dict get $receipt operation result_ids] {, }]\n"}
        if {[dict exists $receipt operation working_unit]} {$w.details insert end "Working unit: [dict get $receipt operation working_unit]\n"}
        $w.details insert end "Checkpoint fingerprint: [string range [dict get $item payload_sha256] 0 15]…\n"
    }
    $w.details configure -state disabled
    pack $w.scroll -in $w.inspection -side right -fill y
    pack $w.details -in $w.inspection -side left -fill both -expand 1
    ttk::frame $w.actions;pack $w.actions -fill x -padx 16 -pady 16
    set choices($w) {}
    foreach {key text choice} {recover Recover recover saved {Open last saved state} saved cancel Cancel cancel} {
        ttk::button $w.actions.$key -text $text -command [list set ::GX::WorkbenchRecovery::choices($w) $choice];pack $w.actions.$key -side left -padx 4
    }
    wm protocol $w WM_DELETE_WINDOW [list set ::GX::WorkbenchRecovery::choices($w) cancel]
    bind $w <Escape> [list set ::GX::WorkbenchRecovery::choices($w) cancel]
    update idletasks
    if {[winfo exists $parent]&&[winfo viewable $parent]} {wm transient $w $parent}
    raise $w;grab set $w
    focus $w.actions.recover
    try {tkwait variable ::GX::WorkbenchRecovery::choices($w);set choice $choices($w)} finally {grab release $w;destroy $w;unset choices($w)}
    if {$choice eq "cancel"} {return -code error -errorcode {GX WORKBENCH RECOVERY_CANCELLED} "Workbench recovery was cancelled; saved Session state was not changed"}
    return [workbenchRecoveryResolve $document $choice]
}
rename ::GX::saveCurrentSessionConfig ::GX::saveCurrentSessionConfig_before_workbench_recovery
proc ::GX::saveCurrentSessionConfig {} {
    if {[llength [info commands scientificHistoryFlushAll]]} {scientificHistoryFlushAll}
    set result [saveCurrentSessionConfig_before_workbench_recovery]
    if {$::GX::currentSession eq ""||![file isdirectory $::GX::currentSession]} {return $result}
    foreach owner [interactiveDocumentList] {
        set id [dict get $owner id]
        if {[dict get [workbenchRecoveryInspect $id] status] ni {absent corrupt}&&[catch {workbenchRecoveryMarkSaved $id} message options]} {return -options $options "Session saved; recovery journal for $id could not be marked clean: $message"}
    }
    return $result
}
