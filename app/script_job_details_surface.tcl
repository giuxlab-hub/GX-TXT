# SPDX-License-Identifier: GPL-3.0-or-later
# Host presentation only: provenance/log reads remain in Script Execution/Job CORE.
namespace eval ::GX {variable scriptJobDetail;variable scriptJobDetailSerial 0}
proc ::GX::scriptJobField {record field {fallback {not recorded}}} {
    if {[dict exists $record $field] && [dict get $record $field] ne {}} {return [dict get $record $field]}
    return $fallback
}
proc ::GX::scriptJobTime {value} {
    if {![scriptJobTimestampValid $value] || [catch {clock format [expr {int($value)}] -format {%Y-%m-%d %H:%M:%S}} formatted]} {return {not recorded}}
    return $formatted
}
proc ::GX::scriptJobTimestampValid {value} {
    return [expr {[string is double -strict $value] && ![catch {expr {abs($value)<1e12}} finite] && $finite}]
}
proc ::GX::scriptJobDuration {job} {
    set start [scriptJobStart $job];set end [scriptJobField $job finished {}]
    if {![scriptJobTimestampValid $start]} {
        if {[dict exists $job started] && [dict get $job started] eq {} && ![scriptJobField $job archived 0]} {return {not started}}
        return {not recorded}
    }
    if {![scriptJobTimestampValid $end]} {
        if {[scriptJobField $job state] ni {QUEUED PREPARING RUNNING FINALIZING}} {return {end not recorded}}
        return "[format %.1f [expr {max(0,[clock seconds]-$start)}]] s (ongoing)"
    }
    return "[format %.1f [expr {max(0,$end-$start)}]] s"
}
proc ::GX::scriptJobStart {job} {
    if {[dict exists $job launched_at]} {return [dict get $job launched_at]}
    if {[dict exists $job worker_pid] || [dict exists $job execution_report started_at]} {return [scriptJobField $job started {}]}
    return {}
}
proc ::GX::scriptJobSessionName {job} {
    set name [scriptJobField $job session_name {}]
    if {$name eq {}} {set name [file tail [scriptJobField $job session {}]]}
    return $name
}
proc ::GX::scriptJobDetailsFormat {job} {
    set text "Script: [scriptJobField $job script_name]\nRegistered Script ID: [scriptJobField $job reference]\nLanguage: [scriptJobField $job language]\nVersion: [scriptJobField $job script_version]   Revision: [scriptJobField $job script_revision]\nSHA-256 (submitted source): [scriptJobField $job source_sha256]\nSnapshot validation: [scriptJobField $job snapshot_validation {Open details to verify}]\nJob ID: [scriptJobField $job id]\nSession: [scriptJobSessionName $job]\nSession ID: [scriptJobField $job session_id]\nSession path: [scriptJobField $job session]\nState: [scriptJobField $job state]\nAdmission: [scriptJobTime [scriptJobField $job created {}]]\nStart (supervisor preparation): [scriptJobTime [scriptJobField $job started {}]]\nFinish: [scriptJobTime [scriptJobField $job finished {}]]\nElapsed: [scriptJobDuration $job]\nProcess exit code: [scriptJobField $job exit_code N/A]\nError / final result: [scriptJobField $job error {No error recorded}]\n"
    append text "Process launch: [scriptJobTime [scriptJobStart $job]]\n"
    foreach {key title} {inputs {Frozen semantic input aliases / Dataset IDs / revisions} analysis_sources {Analysis Source bindings at execution} parameters {Execution parameters} output {Requested output (separate from committed publications)} published_datasets {Committed published Dataset IDs} command {Runtime command} runtime_metadata {Actual runtime metadata} policy {Effective resource policy} usage {Sampled resource usage} peak_rss_bytes {Peak RSS (bytes)} snapshot {Immutable source path} output_dir {Run directory} log_path {Exact execution log path} log_streams {Log streams} diagnostics {Inspection diagnostics} execution_report {Retained execution report}} {
        if {[dict exists $job $key]} {
            append text "\n$title:\n"
            if {$key in {inputs analysis_sources parameters output runtime_metadata policy usage execution_report} && ![catch {dict size [dict get $job $key]}]} {
                dict for {name value} [dict get $job $key] {append text "  $name: $value\n"}
            } else {append text "[dict get $job $key]\n"}
        }
    }
    return $text
}
proc ::GX::scriptJobClipboard {text} {clipboard clear;clipboard append -- $text}
proc ::GX::scriptJobTextCopy {widget} {
    set ranges [$widget tag ranges sel]
    if {[llength $ranges]} {scriptJobClipboard [$widget get sel.first sel.last]} else {scriptJobClipboard [$widget get 1.0 end-1c]}
}
proc ::GX::scriptJobTextCopyAll {widget} {scriptJobClipboard [$widget get 1.0 end-1c]}
proc ::GX::scriptJobTextSelectAll {widget} {$widget tag add sel 1.0 end-1c;focus $widget}
proc ::GX::scriptJobTextCreate {widget parent {owner {}}} {
    grid rowconfigure $parent 0 -weight 1;grid columnconfigure $parent 0 -weight 1
    text $widget -height 8 -wrap none -font TkFixedFont -state disabled -exportselection 0 -undo 0
    ttk::scrollbar $parent.sy -command [list $widget yview];ttk::scrollbar $parent.sx -orient horizontal -command [list $widget xview]
    $widget configure -yscrollcommand [list $parent.sy set] -xscrollcommand [list $parent.sx set]
    grid $widget -in $parent -row 0 -column 0 -sticky nsew;grid $parent.sy -row 0 -column 1 -sticky ns;grid $parent.sx -row 1 -column 0 -sticky ew
    bind $widget <Control-c> [list ::GX::scriptJobTextCopy $widget]
    bind $widget <Control-a> [list ::GX::scriptJobTextSelectAll $widget]
    # Tk's disabled Text class may select without acquiring keyboard focus.
    # Acquire it only for an explicit user click, never from polling callbacks.
    bind $widget <ButtonPress-1> {focus -force %W}
    menu $widget.copyMenu -tearoff 0
    $widget.copyMenu add command -label {Copy selection / text} -command [list ::GX::scriptJobTextCopy $widget]
    $widget.copyMenu add command -label {Select all} -command [list ::GX::scriptJobTextSelectAll $widget]
    bind $widget <Button-3> [list tk_popup $widget.copyMenu %X %Y]
    if {$owner ne {}} {
        foreach event {<ButtonPress-1> <B1-Motion> <Button-4> <Button-5> <MouseWheel> <KeyPress-Prior> <KeyPress-Next> <KeyPress-Up> <KeyPress-Down> <Control-a>} {bind $widget $event +[list ::GX::scriptJobDetailSuspend $owner]}
        foreach scrollbar [list $parent.sy $parent.sx] {bind $scrollbar <ButtonPress-1> [list ::GX::scriptJobDetailSuspend $owner]}
    }
}
proc ::GX::scriptJobTextReplace {widget text {reset 0}} {
    if {![winfo exists $widget]} return
    set old [$widget get 1.0 end-1c]
    if {$old eq $text} return
    set y [$widget yview];set x [$widget xview]
    $widget configure -state normal
    if {$reset} {$widget delete 1.0 end;$widget insert 1.0 $text;$widget tag remove sel 1.0 end} else {
        # Replace only changed text. Tk maintains selection/caret marks on the
        # unchanged log suffix when state fields above it change.
        set prefix 0;set limit [expr {min([string length $old],[string length $text])}]
        while {$prefix<$limit && [string index $old $prefix] eq [string index $text $prefix]} {incr prefix}
        set suffix 0
        while {$suffix<$limit-$prefix && [string index $old end-$suffix] eq [string index $text end-$suffix]} {incr suffix}
        $widget delete "1.0 + $prefix chars" "1.0 + [expr {[string length $old]-$suffix}] chars"
        $widget insert "1.0 + $prefix chars" [string range $text $prefix [expr {[string length $text]-$suffix-1}]]
    }
    $widget configure -state disabled
    if {$reset} {$widget yview moveto 0;$widget xview moveto 0} else {$widget yview moveto [lindex $y 0];$widget xview moveto [lindex $x 0]}
}
proc ::GX::scriptJobDetailsWindow {id {session {}}} {
    variable scriptJobDetail;variable scriptJobDetailSerial
    foreach key [array names scriptJobDetail *,id] {
        set existing [string range $key 0 end-3]
        if {$scriptJobDetail($key) eq $id && $scriptJobDetail($existing,session) eq $session && [winfo exists $existing]} {raise $existing;focus $existing;return $existing}
    }
    set w .scriptJobDetail[incr scriptJobDetailSerial]
    set scriptJobDetail($w,id) $id;set scriptJobDetail($w,session) $session
    set scriptJobDetail($w,remote) [scientificExecutionRemoteId $id]
    set scriptJobDetail($w,requests) {};set scriptJobDetail($w,requestSerial) 0
    set scriptJobDetail($w,generation) 0;set scriptJobDetail($w,pageGeneration) 0
    set scriptJobDetail($w,follow) 0;set scriptJobDetail($w,offset) 0;set scriptJobDetail($w,next) 0
    set scriptJobDetail($w,stream) legacy;set scriptJobDetail($w,streamLabel) {Legacy combined stream};set scriptJobDetail($w,record) {};set scriptJobDetail($w,status) {Loading exact execution…}
    toplevel $w;wm title $w "Execution details — $id";wm geometry $w 1100x780;wm minsize $w 680 480
    wm protocol $w WM_DELETE_WINDOW [list ::GX::scriptJobDetailClose $w]
    ttk::frame $w.actions;pack $w.actions -fill x
    ttk::button $w.actions.reconnect -text Reconnect -command [list ::GX::scriptJobDetailReconnect $w]
    ttk::button $w.actions.cancel -text {Cancel Job…} -command [list ::GX::scriptJobDetailCancel $w] -state disabled
    pack $w.actions.reconnect $w.actions.cancel -side left -padx 3 -pady 3
    foreach {name label command} {script {Copy Script ID} scriptJobDetailCopyScript id {Copy Job ID} scriptJobDetailCopyId details {Copy details} scriptJobDetailCopyDetails copy {Copy selection} scriptJobDetailCopySelection all {Select visible page} scriptJobDetailSelectLog full {Copy entire source} scriptJobDetailCopyFull save {Save source to file…} scriptJobDetailSaveLog} {
        ttk::button $w.actions.$name -text $label -command [list ::GX::$command $w];pack $w.actions.$name -side left -padx 3 -pady 3
    }
    ttk::combobox $w.actions.source -state readonly -values {{Program output} {Program stderr} {Diagnostic log} {Legacy combined stream}} -textvariable ::GX::scriptJobDetail($w,streamLabel) -width 24
    pack $w.actions.source -side left -padx 3
    bind $w.actions.source <<ComboboxSelected>> [list ::GX::scriptJobDetailSourceChanged $w]
    ttk::button $w.actions.publish -text {Publish source as Dataset…} -command [list ::GX::scriptJobDetailPublish $w]
    pack $w.actions.publish -side left -padx 3
    if {$scriptJobDetail($w,remote)} {
        $w.actions.source configure -values {{Legacy combined stream}} -state disabled
        $w.actions.publish state disabled
    }
    bind $w.actions <Configure> {::GX::uiFieldControlsLayout %W %w}
    ttk::panedwindow $w.split -orient vertical;pack $w.split -fill both -expand 1 -padx 5
    ttk::frame $w.split.info;ttk::frame $w.split.log
    $w.split add $w.split.info -weight 1;$w.split add $w.split.log -weight 2
    scriptJobTextCreate $w.info $w.split.info
    ttk::frame $w.split.log.bar;pack $w.split.log.bar -fill x
    foreach {name label command} {first {First page} first previous {Previous page} previous next {Next page} next latest {Latest page} latest} {
        ttk::button $w.split.log.bar.$name -text $label -command [list ::GX::scriptJobDetailPage $w $command];pack $w.split.log.bar.$name -side left -padx 4
    }
    ttk::checkbutton $w.split.log.bar.follow -text {Follow latest output} -variable ::GX::scriptJobDetail($w,follow) -command [list ::GX::scriptJobDetailFollow $w]
    pack $w.split.log.bar.follow -side left -padx 6
    ttk::frame $w.split.log.text;pack $w.split.log.text -fill both -expand 1
    scriptJobTextCreate $w.log $w.split.log.text $w
    ttk::label $w.status -textvariable ::GX::scriptJobDetail($w,status) -wraplength 1000;pack $w.status -fill x -padx 5 -pady 4
    scriptJobDetailRefresh $w
    scriptJobDetailPage $w first
    return $w
}
proc ::GX::scriptJobDetailCommand {w operation args} {
    variable scriptJobDetail
    if {$scriptJobDetail($w,remote)} {error {Remote Job requests use the configured Scientific Execution transport}}
    if {$operation eq {cancel} && $scriptJobDetail($w,session) ne {}} {error {Archived run details cannot cancel a live Job}}
    if {$operation eq {log_read}} {set args [linsert $args 0 $scriptJobDetail($w,stream)];set operation stream_read}
    if {$scriptJobDetail($w,session) eq {}} {return [scriptJobCommand $operation $scriptJobDetail($w,id) {*}$args]}
    set op [expr {$operation eq "inspect" ? "inspect_run" : "run_stream_read"}]
    return [scriptJobCommand $op $scriptJobDetail($w,session) $scriptJobDetail($w,id) {*}$args]
}
proc ::GX::scriptJobDetailRequest {w operation arguments callback} {
    variable scriptJobDetail
    set serial [incr scriptJobDetail($w,requestSerial)]
    set done [list ::GX::scriptJobDetailRequestDone $w $serial $callback]
    if {[catch {
        if {$scriptJobDetail($w,remote)} {
            lassign [_scientificRemoteRoute $scriptJobDetail($w,id)] node session job
            switch -- $operation {
                inspect {set op job.inspect}
                log_read {set op job.log_read}
                cancel {set op scientific.cancel}
                default {error {Unsupported remote Job detail operation}}
            }
            set token [scientificExecutionRemoteCallAsync $node $session $op [linsert $arguments 0 $job] $done]
        } else {
            set token [scriptJobAsync [scriptJobDetailCommand $w $operation {*}$arguments] {} $done]
        }
    } reason options]} {
        set response [dict create ok 0 error $reason]
        if {[dict exists $options -errorcode]} {dict set response error_code [dict get $options -errorcode]}
        after idle [list {*}$done $response]
        return {}
    }
    dict set scriptJobDetail($w,requests) $serial $token
    return $token
}
proc ::GX::scriptJobDetailRequestDone {w serial callback response} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)]} return
    if {[dict exists $scriptJobDetail($w,requests) $serial]} {dict unset scriptJobDetail($w,requests) $serial}
    uplevel #0 [list {*}$callback $response]
}
proc ::GX::scriptJobDetailReconnect {w} {
    scriptJobDetailRefresh $w
    scriptJobDetailPage $w latest
}
proc ::GX::scriptJobDetailCancel {w} {
    variable scriptJobDetail
    if {$scriptJobDetail($w,session) ne {} || [scriptJobField $scriptJobDetail($w,record) state] ni {QUEUED PREPARING RUNNING FINALIZING}} return
    set id $scriptJobDetail($w,id)
    if {[tk_messageBox -parent $w -icon question -type yesno -default no -title {Cancel the existing Job?} -message "Request cancellation of $id through its existing execution owner? Closing this window alone never cancels the Job."] ne {yes}} return
    $w.actions.cancel state disabled
    scriptJobDetailRequest $w cancel {} [list ::GX::scriptJobDetailCancelReady $w $id]
}
proc ::GX::scriptJobDetailCancelReady {w id response} {
    if {![info exists ::GX::scriptJobDetail($w,id)] || $::GX::scriptJobDetail($w,id) ne $id} return
    if {![dict get $response ok]} {set ::GX::scriptJobDetail($w,status) "Cancellation unavailable: [dict get $response error]";return}
    set ::GX::scriptJobDetail($w,status) {Cancellation requested; reconnecting to the authoritative state.}
    scriptJobDetailRefresh $w
}
proc ::GX::scriptJobDetailRefresh {w} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)]} return
    if {[info exists scriptJobDetail($w,timer)]} {after cancel $scriptJobDetail($w,timer);unset scriptJobDetail($w,timer)}
    set gen [incr scriptJobDetail($w,generation)]
    scriptJobDetailRequest $w inspect {} [list ::GX::scriptJobDetailReady $w $scriptJobDetail($w,id) $gen]
}
proc ::GX::scriptJobDetailReady {w id gen response} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)] || $id ne $scriptJobDetail($w,id) || $gen!=$scriptJobDetail($w,generation)} return
    if {![dict get $response ok]} {
        $w.actions.cancel state disabled
        set scriptJobDetail($w,status) "Execution unavailable: [dict get $response error]"
        scriptJobTextReplace $w.info "Job ID: $id\n$scriptJobDetail($w,status)"
        return
    }
    set job [dict get $response result];set scriptJobDetail($w,record) $job
    if {$scriptJobDetail($w,remote)} {
        lassign [_scientificRemoteRoute $id] node remoteSession localJob
        dict set job node_local_job_id [scriptJobField $job id $localJob]
        dict set job id $id;dict set job node_id $node;dict set job remote_session_id $remoteSession
        set scriptJobDetail($w,record) $job
    }
    $w.actions.cancel state [expr {$scriptJobDetail($w,session) eq {} && [scriptJobField $job state] in {QUEUED PREPARING RUNNING FINALIZING} ? {!disabled} : {disabled}}]
    if {[dict exists $job origin] && [dict get $job origin] eq {core_service}} {set scriptJobDetail($w,status) {Private CORE service: engineering inspection only. Ordinary user stream actions are unavailable.};$w.actions.publish state disabled}
    if {!$scriptJobDetail($w,remote) && $scriptJobDetail($w,stream) eq {legacy} && [string match {Separate*} [scriptJobField $job log_streams {}]]} {set scriptJobDetail($w,streamLabel) {Program output};scriptJobDetailSourceChanged $w}
    wm title $w "[scriptJobField $job script_name] — [scriptJobField $job state] — $id"
    scriptJobTextReplace $w.info [scriptJobDetailsFormat $job]
    if {$scriptJobDetail($w,remote)} {
        scriptJobTextReplace $w.info "[$w.info get 1.0 end-1c]\nRemote node: $node\nLogical remote Session: $remoteSession\nNode-local Job ID: [dict get $job node_local_job_id]\nThis transport exposes the retained combined log only. Separate-stream selection and local Dataset publication are unavailable here; no remote output has been imported."
    }
    if {[scriptJobField $job state] in {QUEUED PREPARING RUNNING FINALIZING}} {
        if {$scriptJobDetail($w,follow)} {scriptJobDetailPage $w latest}
        set scriptJobDetail($w,timer) [after 1000 [list ::GX::scriptJobDetailRefresh $w]]
        $w.split.log.bar.follow state !disabled
    } else {set scriptJobDetail($w,follow) 0;$w.split.log.bar.follow state disabled}
}
proc ::GX::scriptJobDetailPage {w action} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)]} return
    set offset $scriptJobDetail($w,offset);set tail 0
    switch $action {
        first {set offset 0}
        previous {set offset [expr {max(0,$offset-65536)}]}
        next {set offset $scriptJobDetail($w,next)}
        latest {set offset 0;set tail 1}
    }
    if {!$tail} {scriptJobDetailSuspend $w}
    set gen [incr scriptJobDetail($w,pageGeneration)]
    scriptJobDetailRequest $w log_read [list $offset 65536 $tail] [list ::GX::scriptJobDetailLogReady $w $scriptJobDetail($w,id) $gen $action]
}
proc ::GX::scriptJobDetailLogReady {w id gen action response} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)] || $id ne $scriptJobDetail($w,id) || $gen!=$scriptJobDetail($w,pageGeneration)} return
    if {![dict get $response ok]} {set scriptJobDetail($w,status) "Log unavailable: [dict get $response error]";scriptJobTextReplace $w.log $scriptJobDetail($w,status);return}
    set page [dict get $response result]
    set scriptJobDetail($w,offset) [dict get $page offset];set scriptJobDetail($w,next) [dict get $page next_offset]
    set scriptJobDetail($w,status) "$scriptJobDetail($w,streamLabel) in 64 KiB pages — bytes [dict get $page offset] .. [dict get $page next_offset] / [dict get $page size]. [dict get $page diagnostic]"
    set text [dict get $page content]
    if {![dict get $page available]} {set text [dict get $page diagnostic]}
    scriptJobTextReplace $w.log $text [expr {!$scriptJobDetail($w,follow)}]
    if {$scriptJobDetail($w,follow) && ![llength [$w.log tag ranges sel]]} {$w.log see end}
    $w.split.log.bar.next state [expr {[dict get $page eof] ? "disabled" : "!disabled"}]
    $w.split.log.bar.previous state [expr {[dict get $page offset]==0 ? "disabled" : "!disabled"}]
}
proc ::GX::scriptJobDetailSuspend {w} {
    if {[info exists ::GX::scriptJobDetail($w,follow)] && $::GX::scriptJobDetail($w,follow)} {
        set ::GX::scriptJobDetail($w,follow) 0
        incr ::GX::scriptJobDetail($w,pageGeneration)
    }
}
proc ::GX::scriptJobDetailFollow {w} {if {$::GX::scriptJobDetail($w,follow)} {scriptJobDetailPage $w latest}}
proc ::GX::scriptJobDetailCopyScript {w} {scriptJobClipboard [scriptJobField $::GX::scriptJobDetail($w,record) reference]}
proc ::GX::scriptJobDetailCopyId {w} {scriptJobClipboard $::GX::scriptJobDetail($w,id)}
proc ::GX::scriptJobDetailCopyDetails {w} {scriptJobClipboard [$w.info get 1.0 end-1c]}
proc ::GX::scriptJobDetailCopySelection {w} {
    if {[focus -displayof $w] eq "$w.info"} {scriptJobTextCopy $w.info} else {scriptJobTextCopy $w.log}
}
proc ::GX::scriptJobDetailSelectLog {w} {scriptJobTextSelectAll $w.log;scriptJobDetailSuspend $w}
proc ::GX::scriptJobDetailCopyFull {w} {scriptJobDetailTransfer $w clipboard}
proc ::GX::scriptJobDetailSaveLog {w} {
    set path [tk_getSaveFile -parent $w -title "Save $::GX::scriptJobDetail($w,streamLabel)" -initialfile "[string map {/ _} $::GX::scriptJobDetail($w,id)].log"]
    if {$path ne {}} {scriptJobDetailTransfer $w $path}
}
proc ::GX::scriptJobDetailTransfer {w destination} {
    variable scriptJobDetail
    if {[info exists scriptJobDetail($w,transfer)]} {set scriptJobDetail($w,status) {A source transfer is already running};return}
    set scriptJobDetail($w,transfer) $destination;set scriptJobDetail($w,transferBytes) 0;set scriptJobDetail($w,transferPending) {}
    unset -nocomplain scriptJobDetail($w,transferSize) scriptJobDetail($w,transferIdentity)
    if {$destination eq "clipboard"} {clipboard clear} else {
        set normalized [file normalize $destination]
        set origin [expr {$scriptJobDetail($w,remote) ? $::GX::currentSession : [scriptJobField $scriptJobDetail($w,record) session $scriptJobDetail($w,session)]}]
        if {$origin ne {} && [string first "[file normalize $origin]/" "$normalized/"]==0} {
            unset scriptJobDetail($w,transfer);set scriptJobDetail($w,status) {Choose a destination outside the origin scientific Session; execution files are preserved.};return
        }
        if {[file exists $destination]} {
            file lstat $destination st
            if {$st(type) ne "file" || $st(nlink)!=1} {unset scriptJobDetail($w,transfer);set scriptJobDetail($w,status) {Save requires a regular destination without links.};return}
        }
        set scriptJobDetail($w,exportDestination) $destination
        set scriptJobDetail($w,exportPolicy) [expr {[file exists $destination]?{replace}:{create_only}}]
        if {[catch {set ch [file tempfile temporary [file join [file dirname $destination] .gxtxt-stream-export-]];set scriptJobDetail($w,exportTemporary) $temporary} reason]} {unset scriptJobDetail($w,transfer);set scriptJobDetail($w,status) $reason;return}
        fconfigure $ch -encoding binary -translation binary;set scriptJobDetail($w,transferChannel) $ch
    }
    scriptJobDetailRequest $w log_read {0 65536 0} [list ::GX::scriptJobDetailTransferReady $w $scriptJobDetail($w,id)]
}
proc ::GX::scriptJobDetailTransferReady {w id response} {
    variable scriptJobDetail
    if {![info exists scriptJobDetail($w,id)] || $id ne $scriptJobDetail($w,id) || ![info exists scriptJobDetail($w,transfer)]} return
    set error {}
    if {![dict get $response ok]} {set error [dict get $response error]} else {
        set page [dict get $response result]
        if {![dict get $page available]} {set error [dict get $page diagnostic]}
        if {$scriptJobDetail($w,transfer) eq "clipboard" && [dict get $page size]>33554432} {set error {Clipboard limit is 32 MiB. Use Save full log for this complete log; pages remain available.}}
        if {[dict get $page available]} {
            set identity [lrange [split [dict get $page receipt] :] 0 1]
            if {![info exists scriptJobDetail($w,transferSize)]} {
                set scriptJobDetail($w,transferSize) [dict get $page size]
                set scriptJobDetail($w,transferIdentity) $identity
            } elseif {$identity ne $scriptJobDetail($w,transferIdentity) || [dict get $page size]<$scriptJobDetail($w,transferSize)} {set error {Retained log was replaced or shrank during transfer; retry the exact run.}}
        }
    }
    if {$error ne {}} {
        if {[info exists scriptJobDetail($w,transferChannel)]} {close $scriptJobDetail($w,transferChannel);unset scriptJobDetail($w,transferChannel);catch {file delete -- $scriptJobDetail($w,exportTemporary)}}
        unset scriptJobDetail($w,transfer);set scriptJobDetail($w,status) "Source transfer stopped: $error";return
    }
    set take [expr {min([dict get $page next_offset]-[dict get $page offset],$scriptJobDetail($w,transferSize)-[dict get $page offset])}]
    set raw [binary decode base64 [dict get $page content_base64]]
    if {$take<[string length $raw]} {set raw [string range $raw 0 [expr {$take-1}]]}
    if {$scriptJobDetail($w,transfer) eq "clipboard"} {set bytes $scriptJobDetail($w,transferPending)$raw;set split [scriptJobUtf8CompleteLength $bytes];clipboard append -- [encoding convertfrom utf-8 [string range $bytes 0 [expr {$split-1}]]];set scriptJobDetail($w,transferPending) [string range $bytes $split end]} else {puts -nonewline $scriptJobDetail($w,transferChannel) $raw}
    incr scriptJobDetail($w,transferBytes) $take
    set scriptJobDetail($w,status) "Transferring complete retained source snapshot: $scriptJobDetail($w,transferBytes) / $scriptJobDetail($w,transferSize) bytes"
    if {[dict get $page eof] || $scriptJobDetail($w,transferBytes)>=$scriptJobDetail($w,transferSize)} {
        if {$scriptJobDetail($w,transfer) eq {clipboard} && $scriptJobDetail($w,transferPending) ne {}} {clipboard append -- [encoding convertfrom utf-8 $scriptJobDetail($w,transferPending)]}
        if {[info exists scriptJobDetail($w,transferChannel)]} {
            close $scriptJobDetail($w,transferChannel);unset scriptJobDetail($w,transferChannel)
            set temporary $scriptJobDetail($w,exportTemporary)
            if {[catch {filePublicationCopy $temporary $scriptJobDetail($w,exportDestination) [sha256File $temporary] $scriptJobDetail($w,exportPolicy)} reason]} {set scriptJobDetail($w,status) "Atomic source export failed: $reason";catch {file delete -- $temporary};unset scriptJobDetail($w,transfer);return}
            file delete -- $temporary
        }
        unset scriptJobDetail($w,transfer);append scriptJobDetail($w,status) { — complete};return
    }
    scriptJobDetailRequest $w log_read [list [dict get $page next_offset] 65536 0] [list ::GX::scriptJobDetailTransferReady $w $id]
}
proc ::GX::scriptJobDetailClose {w} {
    variable scriptJobDetail
    if {[info exists scriptJobDetail($w,timer)]} {after cancel $scriptJobDetail($w,timer)}
    if {[info exists scriptJobDetail($w,requests)]} {dict for {serial token} $scriptJobDetail($w,requests) {catch {scriptJobRequestCancel $token}}}
    if {[info exists scriptJobDetail($w,transferChannel)]} {close $scriptJobDetail($w,transferChannel);catch {file delete -- $scriptJobDetail($w,exportTemporary)}}
    catch {destroy $w};array unset scriptJobDetail $w,*
}

proc ::GX::scriptJobDetailSourceChanged {w} {
    variable scriptJobDetail
    if {$scriptJobDetail($w,remote)} {set scriptJobDetail($w,streamLabel) {Legacy combined stream};return}
    if {[info exists scriptJobDetail($w,transfer)]} {set scriptJobDetail($w,streamLabel) [dict get {stdout {Program output} stderr {Program stderr} diagnostics {Diagnostic log} legacy {Legacy combined stream}} $scriptJobDetail($w,stream)];set scriptJobDetail($w,status) {Finish the current source transfer before switching streams};return}
    set mapping [dict create {Program output} stdout {Program stderr} stderr {Diagnostic log} diagnostics {Legacy combined stream} legacy]
    set scriptJobDetail($w,stream) [dict get $mapping $scriptJobDetail($w,streamLabel)]
    set scriptJobDetail($w,offset) 0;set scriptJobDetail($w,next) 0
    scriptJobDetailPage $w first
}
proc ::GX::scriptJobDetailPublish {w} {
    if {$::GX::scriptJobDetail($w,remote)} {set ::GX::scriptJobDetail($w,status) {Remote combined logs are inspectable here; local Dataset publication requires an existing supported import workflow.};return}
    set d $w.publish
    uiFieldDialogCreate $d $w {Publish the selected execution source}
    set ::GX::scriptJobDetail($w,publishId) "[string map {- _} $::GX::scriptJobDetail($w,id)]_$::GX::scriptJobDetail($w,stream)"
    ttk::label $d.label -text "New Dataset ID for $::GX::scriptJobDetail($w,streamLabel):"
    ttk::entry $d.id -textvariable ::GX::scriptJobDetail($w,publishId) -width 52
    ttk::button $d.apply -text {Publish as canonical text Dataset} -command [list ::GX::scriptJobDetailPublishCommit $w]
    pack $d.label $d.id $d.apply -fill x -padx 8 -pady 5
    uiFieldDialogPresent $d $d.id 0
}
proc ::GX::scriptJobDetailPublishCommit {w} {
    variable scriptJobDetail
    if {[catch {set receipt [scriptJobStreamPublish $scriptJobDetail($w,id) $scriptJobDetail($w,stream) $scriptJobDetail($w,publishId) $scriptJobDetail($w,session)]} reason]} {set scriptJobDetail($w,status) "Publication failed: $reason";return}
    set scriptJobDetail($w,status) "Published [dict get $receipt dataset_id] from $scriptJobDetail($w,streamLabel)"
    uiFieldDialogClose $w.publish;refreshResults
}

# Byte pages may split a UTF-8 scalar; retain only the incomplete suffix.
proc ::GX::scriptJobUtf8CompleteLength {bytes} {
    set length [string length $bytes];if {!$length} {return 0}
    set i [expr {$length-1}]
    while {$i>=0 && $i>=$length-4} {binary scan [string index $bytes $i] cu byte;if {($byte&192)!=128} break;incr i -1}
    if {$i<0 || $i<$length-4} {return $length}
    set need [expr {$byte<128?1:($byte&224)==192?2:($byte&240)==224?3:($byte&248)==240?4:1}]
    return [expr {$length-$i<$need?$i:$length}]
}
