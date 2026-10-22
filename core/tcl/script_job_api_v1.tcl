# SPDX-License-Identifier: GPL-3.0-or-later
# CORE local durable Job API. UI callbacks use nonblocking fileevents only.
namespace eval ::GX {variable scriptJobRequests {};variable scriptJobCounter 0;variable scriptJobShutdownHook 0}
proc ::GX::scriptJobApiInfo {} {
    return [dict create api_name SCRIPT_JOB_API_v1 api_version 1 scope {local remote_references} authority core operations {submit wait list describe inspect log_read inspect_run run_log_read run_summaries cancel recover configure debug_submit debug_read debug_control debug_capabilities stream_read stream_publish view_list history_hide history_restore history_candidates workspace_save workspace_open workspace_rename workspace_delete view_remember} persistence durable gui_lifetime independent presentation_scope user_configuration auxiliary_operations {scriptJobAsync scriptJobRequestCancel scriptJobRequestExchange} auxiliary_limits {timeout_ms max_bytes process_group ui_lifetime label duplex} auxiliary_exchange_timeout_ms {default 12000 min 1 max 120000}]
}
proc ::GX::scriptJobRoot {} {
    if {[info exists ::env(GXTXT_JOB_ROOT)]} {return [file normalize $::env(GXTXT_JOB_ROOT)]}
    return [file join [file dirname [configurationPath]] script-jobs-v1]
}
proc ::GX::scriptJobCommand {operation args} {
    return [list [runtimeToolResolve python] -B [file join $::GX::scriptDir core python gxtxt_job_supervisor.py] --root [scriptJobRoot] $operation {*}$args]
}
proc ::GX::scriptJobCall {operation args} {
    set rc [catch {exec {*}[scriptJobCommand $operation {*}$args]} response]
    if {[catch {dict get $response ok} ok]} {error $response}
    if {!$ok} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::scriptJobAsync {command payload callback {options {}}} {
    variable scriptJobRequests;variable scriptJobCounter
    foreach key [dict keys $options] {if {$key ni {timeout_ms max_bytes process_group ui_lifetime label duplex}} {error {Unknown managed request option.}}}
    set options [dict merge {timeout_ms 0 max_bytes 0 process_group 0 ui_lifetime 0 label {Managed request} duplex 0} $options]
    foreach key {timeout_ms max_bytes} {if {![string is integer -strict [dict get $options $key]] || [dict get $options $key]<0} {error {Managed request limits must be nonnegative integers.}}}
    foreach key {process_group ui_lifetime duplex} {if {![string is boolean -strict [dict get $options $key]]} {error {Managed request lifetime options must be boolean.}}}
    if {[dict get $options process_group] && [auto_execok kill] eq {}} {error {Owned process-group cancellation is unavailable on this host.}}
    set request job-request-[incr scriptJobCounter]
    set pipe [open [list | {*}$command 2>@1] r+]
    try {
        fconfigure $pipe -blocking 0 -buffering none -encoding utf-8 -translation lf
        puts -nonewline $pipe $payload
        if {![dict get $options duplex]} {chan close $pipe write}
    } on error {message context} {catch {close $pipe};return -options $context $message}
    dict set scriptJobRequests $request [dict create pipe $pipe callback $callback data {} options $options pids [pid $pipe] started_ms [clock milliseconds] timer {} kill_timer {} cancelled {}]
    set timeout [dict get $options timeout_ms]
    if {$timeout>0} {dict set scriptJobRequests $request timer [after $timeout [list ::GX::scriptJobRequestCancel $request timeout]]}
    if {[dict get $options ui_lifetime] && !$::GX::scriptJobShutdownHook && [llength [info commands winfo]] && [winfo exists .]} {
        bind . <Destroy> +[list ::GX::scriptJobRequestsShutdown %W]
        set ::GX::scriptJobShutdownHook 1
    }
    fileevent $pipe readable [list ::GX::scriptJobReadable $request]
    return $request
}
proc ::GX::scriptJobReadable {request} {
    variable scriptJobRequests
    if {![dict exists $scriptJobRequests $request]} return
    set entry [dict get $scriptJobRequests $request];set pipe [dict get $entry pipe]
    dict append entry data [read $pipe 65536]
    set maximum [dict get $entry options max_bytes]
    if {[dict get $entry options duplex]} {
        if {[dict get $entry cancelled] ne {}} {
            # Drain the owned channel during normal cancellation without
            # retaining additional unsolicited native output.
            dict set entry data {}
        } else {
        set data [dict get $entry data]
        while {[set newline [string first \n $data]]>=0} {
            set line [string range $data 0 [expr {$newline-1}]]
            set data [string range $data [expr {$newline+1}] end]
            if {$maximum>0 && [string bytelength $line]>$maximum} {dict set scriptJobRequests $request $entry;scriptJobRequestCancel $request output_limit;return}
            if {[llength [datasetPublicationV2DictDefault $entry messages {}]]>=16} {
                dict set entry data {};dict set scriptJobRequests $request $entry
                scriptJobRequestCancel $request output_limit;return
            }
            dict lappend entry messages $line
        }
        dict set entry data $data
        }
    }
    if {$maximum>0 && [string bytelength [dict get $entry data]]>$maximum} {
        dict set entry data [string range [dict get $entry data] 0 [expr {max(0,$maximum/8-1)}]]
        dict set scriptJobRequests $request $entry
        scriptJobRequestCancel $request output_limit
        set entry [dict get $scriptJobRequests $request]
    }
    dict set scriptJobRequests $request $entry
    if {![eof $pipe]} return
    if {[dict get $entry options duplex] && [dict get $entry cancelled] eq {}} {
        # A persistent native leader can crash after fork while a descendant
        # redirects stdout. Retain ownership until the whole group is reaped.
        scriptJobRequestCancel $request closed
        set entry [dict get $scriptJobRequests $request]
    }
    # A worker can exit before a descendant that redirected its stdout. Keep
    # the group identity until the escalation has run, even after pipe EOF.
    if {[dict get $entry cancelled] ne {} && ![dict exists $entry escalated]} {
        fileevent $pipe readable {}
        dict set scriptJobRequests $request eof 1
        return
    }
    fileevent $pipe readable {};catch {close $pipe}
    foreach key {timer kill_timer} {if {[dict get $entry $key] ne {}} {after cancel [dict get $entry $key]}}
    dict unset scriptJobRequests $request
    set response [string trim [dict get $entry data]]
    if {[dict get $entry cancelled] ne {}} {set response [dict create ok 0 error "[dict get $entry options label]: [dict get $entry cancelled]" error_type [dict get $entry cancelled]]}
    if {[catch {dict get $response ok}]} {set response [dict create ok 0 error $response]}
    if {[dict get $entry callback] ne {}} {uplevel #0 [list {*}[dict get $entry callback] $response]}
}
proc ::GX::scriptJobRequestExchange {request payload {timeout_ms 12000}} {
    # Short native RPCs share the existing managed request/pipe/process-group
    # owner. Do not enter a nested Tk event loop: queued Canvas input must see
    # the completed local tool selection, never the previous tool.
    if {![string is integer -strict $timeout_ms] || $timeout_ms<1 || $timeout_ms>120000} {error {Managed exchange timeout is outside1..120000ms}}
    if {![dict exists $::GX::scriptJobRequests $request] || ![dict get $::GX::scriptJobRequests $request options duplex]} {error {Managed duplex request is no longer active}}
    set pipe [dict get $::GX::scriptJobRequests $request pipe]
    if {$payload ne {}} {puts $pipe $payload;flush $pipe}
    set deadline [expr {[clock milliseconds]+$timeout_ms}]
    while {[dict exists $::GX::scriptJobRequests $request]} {
        scriptJobReadable $request
        if {![dict exists $::GX::scriptJobRequests $request]} break
        set entry [dict get $::GX::scriptJobRequests $request]
        if {[dict get $entry cancelled] ne {}} {error {Managed compiled request was cancelled}}
        set messages [datasetPublicationV2DictDefault $entry messages {}]
        if {[llength $messages]} {dict set ::GX::scriptJobRequests $request messages [lrange $messages 1 end];return [lindex $messages 0]}
        if {[clock milliseconds]>=$deadline} {scriptJobRequestCancel $request timeout;error {Compiled local event exceeded its bounded response time}}
        after 1
    }
    error {Compiled Viewer worker ended before responding}
}
proc ::GX::_scriptJobRequestSignal {request signal} {
    if {![dict exists $::GX::scriptJobRequests $request]} return
    set entry [dict get $::GX::scriptJobRequests $request]
    set kill [auto_execok kill];if {$kill eq {}} return
    foreach child [dict get $entry pids] {
        if {![string is integer -strict $child] || $child<=1} continue
        set delivered 0
        if {[dict get $entry options process_group]} {set delivered [expr {![catch {exec {*}$kill -$signal -- -$child 2>/dev/null}]}]}
        # A successful group signal already includes its leader. Sending it
        # again to that PID can interrupt the worker's terminal cleanup handler.
        if {!$delivered} {catch {exec {*}$kill -$signal -- $child 2>/dev/null}}
    }
}
proc ::GX::scriptJobRequestCancel {request {reason cancelled}} {
    variable scriptJobRequests
    if {$reason ni {cancelled timeout output_limit closed}} {error {Unknown managed request cancellation reason.}}
    if {![dict exists $scriptJobRequests $request] || [dict get $scriptJobRequests $request cancelled] ne {}} {return 0}
    dict set scriptJobRequests $request cancelled $reason
    _scriptJobRequestSignal $request TERM
    dict set scriptJobRequests $request kill_timer [after 500 [list ::GX::_scriptJobRequestEscalate $request]]
    return 1
}
proc ::GX::_scriptJobRequestEscalate {request} {
    if {![dict exists $::GX::scriptJobRequests $request]} return
    _scriptJobRequestSignal $request KILL
    dict set ::GX::scriptJobRequests $request escalated 1
    if {[dict exists $::GX::scriptJobRequests $request eof]} {scriptJobReadable $request}
}
proc ::GX::scriptJobRequestsShutdown {actual} {
    if {$actual ne {.}} return
    dict for {request entry} $::GX::scriptJobRequests {if {[dict get $entry options ui_lifetime]} {_scriptJobRequestSignal $request KILL}}
}
proc ::GX::scriptJobSubmit {reference parameters {options {}} {callback {}}} {
    if {[string match core-service:* $reference] || [dict exists $options core_service]} {error {Private CORE services cannot be submitted through user Script Job APIs}}
    tailcall ::GX::_scriptJobSubmit $reference $parameters $options $callback
}
proc ::GX::_scriptJobSubmitCore {service parameters {options {}} {callback {}}} {
    _scriptCoreServiceMetadata $service
    dict set options core_service $service
    tailcall ::GX::_scriptJobSubmit core-service:$service $parameters $options $callback
}
proc ::GX::_scriptJobSubmit {reference parameters options callback} {
    set session [dict get [dict merge [dict create session $::GX::currentSession] $options] session]
    if {$session eq {} || ![file isdirectory $session]} {error {Open a Session before submitting a script.}}
    set moduleConfig {}
    if {$::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [file normalize $session]} {
        foreach module {analysis.python_script analysis.octave_script} {
            foreach key [array names ::GX::moduleCfg "$module,*"] {dict set moduleConfig $key $::GX::moduleCfg($key)}
        }
    }
    set request [dict merge [dict create module_config $moduleConfig inputs {} output {} runtime_template {} module_output {}] $options [dict create session [file normalize $session] reference $reference parameters $parameters root [scriptJobRoot]]]
    # The GUI may run under wish: its executable would keep a hidden Tk event
    # loop alive after preparation, preventing the asynchronous pipe from EOF.
    set interpreter [auto_execok tclsh]
    if {$interpreter eq {}} {error {A local Tcl interpreter is required for job preparation.}}
    set command [list {*}$interpreter [file join $::GX::scriptDir core tcl script_job_request.tcl] $::GX::scriptDir]
    if {$callback ne {}} {return [scriptJobAsync $command $request $callback]}
    set response [exec {*}$command << $request]
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::scriptJobList {} {scriptJobCall list}
proc ::GX::scriptJobDescribe {id} {if {[scientificExecutionRemoteId $id]} {return [scientificExecutionRemoteJobRecord $id describe]};scriptJobCall describe $id}
proc ::GX::scriptJobInspect {id} {if {[scientificExecutionRemoteId $id]} {return [scientificExecutionRemoteJobRecord $id inspect]};scriptJobCall inspect $id}
proc ::GX::scriptJobLogRead {id {offset 0} {count 65536} {tail 0}} {if {[scientificExecutionRemoteId $id]} {return [scientificExecutionRemoteJobRecord $id log_read $offset $count $tail]};scriptJobCall log_read $id $offset $count $tail}
proc ::GX::scriptExecutionInspectRun {session runId} {scriptJobCall inspect_run $session $runId}
proc ::GX::scriptExecutionRunSummaries {session} {scriptJobCall run_summaries $session}
proc ::GX::scriptJobCancel {id} {if {[scientificExecutionRemoteId $id]} {return [scientificExecutionRemoteJob $id cancel]};scriptJobCall cancel $id}
proc ::GX::scriptJobWait {id {timeoutSeconds 60} {cancelCommand {}}} {
    if {![string is integer -strict $timeoutSeconds]||$timeoutSeconds<1||$timeoutSeconds>86400} {error {Job wait timeout must be an integer from 1 to 86400 seconds}}
    set lease {};if {![scientificExecutionRemoteId $id]} {set lease [scriptJobCall wait_begin $id]};set started [clock milliseconds];set cancelled 0
    try {
        while {1} {
            set info [scriptJobDescribe $id]
            if {[dict get $info state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} break
            set requested [expr {[clock milliseconds]-$started>=1000*$timeoutSeconds}]
            if {$cancelCommand ne {}&&[{*}$cancelCommand]} {set requested 1}
            if {$requested&&!$cancelled} {scriptJobCancel $id;set cancelled 1}
            # Keep host events/cancellation responsive while CORE alone owns
            # admission, descendant lifetimes and terminal resource recovery.
            after 100;update
        }
        dict set info wait_cancel_requested $cancelled
        return $info
    } on error {message options} {
        catch {scriptJobCancel $id}
        return -options $options $message
    } finally {
        # On process/transport failure the supervisor reaps the caller lease,
        # cancels the owned child and restores capacity without caller cleanup.
        if {$lease ne {}} {catch {scriptJobCall wait_end [dict get $lease token]}}
    }
}
proc ::GX::scriptJobRecover {} {scriptJobCall recover}
source [file join [file dirname [info script]] script_job_presentation_v1.tcl]
# FUTURE WINDOWS PORTING REQUIREMENT: GUI close only detaches this client.
# Use the same LOCAL CORE Job API with an independent Windows supervisor/tray:
# reopen GUI, inspect jobs, cancel selected/all (confirm all), safe supervisor exit.
# No remote dispatch or mandatory service; native Job Objects own child lifetime.

proc ::GX::scriptJobStreamRead {id role {offset 0} {count 65536} {tail 0}} {scriptJobCall stream_read $id $role $offset $count $tail}
proc ::GX::scriptJobStreamPublish {id role datasetId {session {}}} {
    if {$session eq {}} {set record [scriptJobInspect $id]} else {set record [scriptExecutionInspectRun $session $id]}
    if {[dict get $record origin] eq {core_service}} {error {Private CORE service streams cannot be published as user results}}
    if {$::GX::currentSession eq {} || [file normalize [dict get $record session]] ne [file normalize $::GX::currentSession]} {error {Activate the source Job Session before publication}}
    set page [expr {$session eq {} ? [scriptJobStreamRead $id $role 0 65536 0] : [scriptJobCall run_stream_read $session $id $role 0 65536 0]}]
    if {![dict get $page available]} {error [dict get $page diagnostic]}
    if {![dict get $page complete]} {error {Wait for a terminal Job before publishing an immutable complete stream}}
    set path [dict get $page path];set before [sha256File $path]
    set producer [scriptAnalysisModule [dict get $record language]]
    set request [dict create dataset_id $datasetId contract document.text format txt source_file $path storage_kind text media_type text/plain provenance "Script Job $id; stream $role; source SHA [dict get $record source_sha256]" structured_metadata [dict create script.job_id $id script.stream_role $role script.source_sha256 [dict get $record source_sha256] script.stream_sha256 $before script.complete 1 text.encoding UTF-8]]
    set receipt [datasetFilePublicationPublish $::GX::currentSession $producer $request]
    if {[sha256File $path] ne $before} {error {Retained stream changed unexpectedly during publication}}
    return $receipt
}

proc ::GX::scriptJobDebugSubmit {reference parameters {options {}} {callback {}}} {dict set options debug 1;tailcall ::GX::scriptJobSubmit $reference $parameters $options $callback}
proc ::GX::scriptJobDebugRead {id} {scriptJobCall debug_read $id}
proc ::GX::scriptJobDebugCapabilities {language} {scriptJobCall debug_capabilities $language}
proc ::GX::scriptJobDebugControl {id operation sourceSha {frame 0}} {
    if {$operation eq {stop}} {return [scriptJobCancel $id]}
    scriptJobCall debug_control $id $operation $sourceSha $frame
}
