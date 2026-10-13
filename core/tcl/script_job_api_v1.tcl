# SPDX-License-Identifier: GPL-3.0-or-later
# CORE local durable Job API. UI callbacks use nonblocking fileevents only.
namespace eval ::GX {variable scriptJobRequests {};variable scriptJobCounter 0}
proc ::GX::scriptJobApiInfo {} {
    return [dict create api_name SCRIPT_JOB_API_v1 api_version 1 scope local authority core operations {submit list describe inspect log_read inspect_run run_log_read run_summaries cancel recover configure} persistence durable gui_lifetime independent]
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
proc ::GX::scriptJobAsync {command payload callback} {
    variable scriptJobRequests;variable scriptJobCounter
    set request job-request-[incr scriptJobCounter]
    set pipe [open [list | {*}$command 2>@1] r+]
    fconfigure $pipe -blocking 0 -buffering none -encoding utf-8 -translation lf
    puts -nonewline $pipe $payload
    chan close $pipe write
    dict set scriptJobRequests $request [dict create pipe $pipe callback $callback data {}]
    fileevent $pipe readable [list ::GX::scriptJobReadable $request]
    return $request
}
proc ::GX::scriptJobReadable {request} {
    variable scriptJobRequests
    if {![dict exists $scriptJobRequests $request]} return
    set entry [dict get $scriptJobRequests $request];set pipe [dict get $entry pipe]
    dict append entry data [read $pipe]
    dict set scriptJobRequests $request $entry
    if {![eof $pipe]} return
    fileevent $pipe readable {};catch {close $pipe}
    dict unset scriptJobRequests $request
    set response [string trim [dict get $entry data]]
    if {[catch {dict get $response ok}]} {set response [dict create ok 0 error $response]}
    uplevel #0 [list {*}[dict get $entry callback] $response]
}
proc ::GX::scriptJobSubmit {reference parameters {options {}} {callback {}}} {
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
proc ::GX::scriptJobDescribe {id} {scriptJobCall describe $id}
proc ::GX::scriptJobInspect {id} {scriptJobCall inspect $id}
proc ::GX::scriptJobLogRead {id {offset 0} {count 65536} {tail 0}} {scriptJobCall log_read $id $offset $count $tail}
proc ::GX::scriptExecutionInspectRun {session runId} {scriptJobCall inspect_run $session $runId}
proc ::GX::scriptExecutionRunSummaries {session} {scriptJobCall run_summaries $session}
proc ::GX::scriptJobCancel {id} {scriptJobCall cancel $id}
proc ::GX::scriptJobRecover {} {scriptJobCall recover}
# FUTURE WINDOWS PORTING REQUIREMENT: GUI close only detaches this client.
# Use the same LOCAL CORE Job API with an independent Windows supervisor/tray:
# reopen GUI, inspect jobs, cancel selected/all (confirm all), safe supervisor exit.
# No remote dispatch or mandatory service; native Job Objects own child lifetime.
