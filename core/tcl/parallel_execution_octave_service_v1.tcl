# GX-TXT Parallel Execution API v1 - standard_octave binding service
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This adapter exposes the already-loaded CORE Parallel Execution coordinator to
# standard_octave subprocesses through a loopback-only authenticated endpoint.
# It does not create another scheduler. All worker policy, process execution,
# cancellation, nesting and cleanup remain owned by Parallel Execution API v1.

namespace eval ::GX {
    variable parallelOctaveService
    variable parallelOctaveConnection
    variable parallelOctaveServiceCounter 0
}

proc ::GX::parallelOctaveB64Encode {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::GX::parallelOctaveB64Decode {value} {
    if {$value eq ""} { return "" }
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}

proc ::GX::parallelOctaveRandomToken {} {
    if {![catch {
        set fd [open /dev/urandom rb]
        fconfigure $fd -translation binary -encoding binary
        set bytes [read $fd 32]
        close $fd
        if {[string length $bytes] != 32} { error "short random read" }
        set token [binary encode hex $bytes]
    }]} {
        return $token
    }
    variable parallelOctaveServiceCounter
    incr parallelOctaveServiceCounter
    # Fallback remains local-only and combines process/time/counter entropy.
    return [format "%x%x%x%x" [pid] [clock milliseconds] [clock clicks] $parallelOctaveServiceCounter]
}

proc ::GX::parallelOctaveServiceExists {analysisRunId} {
    variable parallelOctaveService
    return [info exists parallelOctaveService($analysisRunId,server)]
}

proc ::GX::parallelOctaveServiceStart {analysisRunId moduleId} {
    variable parallelOctaveService
    if {$analysisRunId eq ""} { error "standard_octave Parallel Execution service requires an analysis run ID." }
    if {[parallelOctaveServiceExists $analysisRunId]} {
        return [parallelOctaveServiceEnvironment $analysisRunId]
    }
    set token [parallelOctaveRandomToken]
    set server [socket -server [list ::GX::parallelOctaveAccept $analysisRunId] -myaddr 127.0.0.1 0]
    set sockname [fconfigure $server -sockname]
    set port [lindex $sockname end]
    set parallelOctaveService($analysisRunId,server) $server
    set parallelOctaveService($analysisRunId,host) 127.0.0.1
    set parallelOctaveService($analysisRunId,port) $port
    set parallelOctaveService($analysisRunId,token) $token
    set parallelOctaveService($analysisRunId,module_id) $moduleId
    set parallelOctaveService($analysisRunId,channels) {}
    set parallelOctaveService($analysisRunId,active_runs) {}
    return [parallelOctaveServiceEnvironment $analysisRunId]
}

proc ::GX::parallelOctaveServiceEnvironment {analysisRunId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { error "Unknown standard_octave Parallel Execution service '$analysisRunId'." }
    return [list \
        GXTXT_PARALLEL_BINDING_HOST=$parallelOctaveService($analysisRunId,host) \
        GXTXT_PARALLEL_BINDING_PORT=$parallelOctaveService($analysisRunId,port) \
        GXTXT_PARALLEL_BINDING_TOKEN=$parallelOctaveService($analysisRunId,token) \
        GXTXT_PARALLEL_BINDING_ANALYSIS_RUN_ID=$analysisRunId]
}

proc ::GX::parallelOctaveServiceEnvironmentDict {analysisRunId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { error "Unknown standard_octave Parallel Execution service '$analysisRunId'." }
    return [dict create \
        GXTXT_PARALLEL_BINDING_HOST $parallelOctaveService($analysisRunId,host) \
        GXTXT_PARALLEL_BINDING_PORT $parallelOctaveService($analysisRunId,port) \
        GXTXT_PARALLEL_BINDING_TOKEN $parallelOctaveService($analysisRunId,token) \
        GXTXT_PARALLEL_BINDING_ANALYSIS_RUN_ID $analysisRunId]
}

proc ::GX::parallelOctaveAccept {analysisRunId channel address port} {
    variable parallelOctaveService
    variable parallelOctaveConnection
    if {![parallelOctaveServiceExists $analysisRunId] || $address ni {127.0.0.1 ::1}} {
        catch {close $channel}
        return
    }
    fconfigure $channel -blocking 0 -buffering line -encoding utf-8 -translation lf
    lappend parallelOctaveService($analysisRunId,channels) $channel
    set parallelOctaveConnection($channel,analysis_run_id) $analysisRunId
    set parallelOctaveConnection($channel,authenticated) 0
    set parallelOctaveConnection($channel,request_lines) {}
    set parallelOctaveConnection($channel,active_run_id) ""
    fileevent $channel readable [list ::GX::parallelOctaveReadable $channel]
}

proc ::GX::parallelOctaveWrite {channel fields} {
    if {[catch {puts $channel [join $fields "\t"]; flush $channel}]} { return 0 }
    return 1
}

proc ::GX::parallelOctaveError {channel message} {
    parallelOctaveWrite $channel [list ERROR [parallelOctaveB64Encode $message]]
}

proc ::GX::parallelOctaveReady {channel analysisRunId} {
    variable parallelExecutionPolicy
    set api [parallelExecutionApiInfo]
    return [parallelOctaveWrite $channel [list READY \
        [dict get $api api_version] \
        [dict get $parallelExecutionPolicy enabled] \
        [dict get $parallelExecutionPolicy default_workers] \
        [dict get $parallelExecutionPolicy max_workers] \
        [dict get $parallelExecutionPolicy recommended_internal_threads] \
        [parallelOctaveB64Encode [dict get $api nested_policy]] \
        [parallelOctaveB64Encode $analysisRunId]]]
}

proc ::GX::parallelOctaveRemoveChannel {analysisRunId channel} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { return }
    set kept {}
    foreach ch $parallelOctaveService($analysisRunId,channels) {
        if {$ch ne $channel} { lappend kept $ch }
    }
    set parallelOctaveService($analysisRunId,channels) $kept
}

proc ::GX::parallelOctaveConnectionClose {channel {cancelActive 1}} {
    variable parallelOctaveConnection
    set analysisRunId [expr {[info exists parallelOctaveConnection($channel,analysis_run_id)] ? $parallelOctaveConnection($channel,analysis_run_id) : ""}]
    set active [expr {[info exists parallelOctaveConnection($channel,active_run_id)] ? $parallelOctaveConnection($channel,active_run_id) : ""}]
    catch {fileevent $channel readable {}}
    if {$cancelActive && $active ne "" && [parallelExecutionRunExists $active]} {
        catch {parallelExecutionCancel $active}
    }
    catch {close $channel}
    foreach key [array names parallelOctaveConnection "$channel,*"] { unset parallelOctaveConnection($key) }
    if {$analysisRunId ne ""} { parallelOctaveRemoveChannel $analysisRunId $channel }
}

proc ::GX::parallelOctaveServiceAddActiveRun {analysisRunId runId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { return }
    if {$runId ni $parallelOctaveService($analysisRunId,active_runs)} {
        lappend parallelOctaveService($analysisRunId,active_runs) $runId
    }
}

proc ::GX::parallelOctaveServiceRemoveActiveRun {analysisRunId runId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { return }
    set kept {}
    foreach current $parallelOctaveService($analysisRunId,active_runs) {
        if {$current ne $runId} { lappend kept $current }
    }
    set parallelOctaveService($analysisRunId,active_runs) $kept
}

proc ::GX::parallelOctaveServiceCancel {analysisRunId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { return 0 }
    set count 0
    foreach runId $parallelOctaveService($analysisRunId,active_runs) {
        if {[parallelExecutionRunExists $runId]} {
            if {![catch {parallelExecutionCancel $runId} changed] && $changed} { incr count }
        }
    }
    return $count
}

proc ::GX::parallelOctaveServiceStop {analysisRunId} {
    variable parallelOctaveService
    if {![parallelOctaveServiceExists $analysisRunId]} { return 0 }
    parallelOctaveServiceCancel $analysisRunId
    foreach channel [list {*}$parallelOctaveService($analysisRunId,channels)] {
        parallelOctaveConnectionClose $channel 1
    }
    catch {close $parallelOctaveService($analysisRunId,server)}
    foreach key [array names parallelOctaveService "$analysisRunId,*"] { unset parallelOctaveService($key) }
    return 1
}

proc ::GX::parallelOctaveServiceStopAll {} {
    variable parallelOctaveService
    set ids {}
    foreach key [array names parallelOctaveService "*,server"] {
        set id [string range $key 0 end-[string length ",server"]]
        lappend ids $id
    }
    foreach id [lsort -unique $ids] { catch {parallelOctaveServiceStop $id} }
}

proc ::GX::parallelOctaveReadEnvironment {lines index countVar} {
    upvar 1 $countVar indexRef
    set out [dict create]
    for {set n 0} {$n < $index} {incr n} {
        if {$indexRef >= [llength $lines]} { error "Unexpected end of Parallel Execution environment." }
        set parts [split [lindex $lines $indexRef] "\t"]
        incr indexRef
        if {[llength $parts] != 3 || [lindex $parts 0] ne "ENV"} { error "Invalid Parallel Execution ENV record." }
        dict set out [parallelOctaveB64Decode [lindex $parts 1]] [parallelOctaveB64Decode [lindex $parts 2]]
    }
    return $out
}

proc ::GX::parallelOctaveParseRequest {lines} {
    if {[llength $lines] < 2 || [lindex $lines end] ne "EXEC"} { error "Incomplete Parallel Execution request." }
    set index 0
    set begin [split [lindex $lines $index] "\t"]; incr index
    if {[llength $begin] != 6 || [lindex $begin 0] ne "BEGIN"} { error "Invalid Parallel Execution BEGIN record." }
    set workers [lindex $begin 1]
    set failFast [lindex $begin 2]
    set runId [parallelOctaveB64Decode [lindex $begin 3]]
    set itemCount [lindex $begin 4]
    set envCount [lindex $begin 5]
    if {![string is integer -strict $itemCount] || $itemCount < 0} { error "Parallel Execution item count must be >= 0." }
    if {![string is integer -strict $envCount] || $envCount < 0} { error "Parallel Execution environment count must be >= 0." }
    set globalEnv [parallelOctaveReadEnvironment $lines $envCount index]
    set items {}
    for {set itemIndex 0} {$itemIndex < $itemCount} {incr itemIndex} {
        if {$index >= [llength $lines]} { error "Unexpected end of Parallel Execution work items." }
        set head [split [lindex $lines $index] "\t"]; incr index
        if {[llength $head] != 3 || [lindex $head 0] ne "ITEM"} { error "Invalid Parallel Execution ITEM record." }
        set id [parallelOctaveB64Decode [lindex $head 1]]
        set argc [lindex $head 2]
        if {![string is integer -strict $argc] || $argc < 1} { error "Parallel Execution argv count must be >= 1." }
        set argv {}
        for {set argIndex 0} {$argIndex < $argc} {incr argIndex} {
            if {$index >= [llength $lines]} { error "Unexpected end of Parallel Execution argv." }
            set argLine [split [lindex $lines $index] "\t"]; incr index
            if {[llength $argLine] != 2 || [lindex $argLine 0] ne "ARG"} { error "Invalid Parallel Execution ARG record." }
            lappend argv [parallelOctaveB64Decode [lindex $argLine 1]]
        }
        if {$index >= [llength $lines] || [lindex $lines $index] ne "ENDITEM"} { error "Invalid Parallel Execution ENDITEM record." }
        incr index
        lappend items [dict create id $id argv $argv]
    }
    if {$index != [expr {[llength $lines] - 1}]} { error "Unexpected Parallel Execution request records." }
    return [dict create items $items options [dict create workers $workers fail_fast $failFast run_id $runId environment $globalEnv]]
}

proc ::GX::parallelOctaveCommandBuilder {item context} {
    if {![dict exists $item argv] || [llength [dict get $item argv]] == 0} { error "Parallel Execution work item '[dict get $item id]' has no argv." }
    return [dict get $item argv]
}

proc ::GX::parallelOctaveProgress {channel analysisRunId moduleId event} {
    set state [dict get $event state]
    set current [dict get $event current]
    set total [dict get $event total]
    set itemId [expr {[dict exists $event item_id] ? [dict get $event item_id] : ""}]
    set message [expr {[dict exists $event message] ? [dict get $event message] : ""}]
    catch {parallelOctaveWrite $channel [list PROGRESS \
        [parallelOctaveB64Encode $state] $current $total \
        [parallelOctaveB64Encode $itemId] [parallelOctaveB64Encode $message] \
        [parallelOctaveB64Encode $analysisRunId] [parallelOctaveB64Encode $moduleId]]}
}

proc ::GX::parallelOctaveExitStatus {result} {
    if {[dict get $result state] eq "success"} { return 0 }
    if {![dict exists $result error_code]} { return "" }
    set code [dict get $result error_code]
    if {[llength $code] >= 3 && [lindex $code 0] eq "CHILDSTATUS" && [string is integer -strict [lindex $code 2]]} { return [lindex $code 2] }
    return ""
}

proc ::GX::parallelOctaveEmitSummary {channel summary} {
    set completion [expr {[dict exists $summary completion_order] ? [dict get $summary completion_order] : {}}]
    if {![parallelOctaveWrite $channel [list SUMMARY \
        [parallelOctaveB64Encode [dict get $summary run_id]] \
        [parallelOctaveB64Encode [dict get $summary state]] \
        [parallelOctaveB64Encode [dict get $summary requested_workers]] \
        [dict get $summary worker_count] [dict get $summary total] [dict get $summary completed] \
        [dict get $summary success_count] [dict get $summary error_count] \
        [dict get $summary cancelled_count] [dict get $summary not_executed_count] \
        [parallelOctaveB64Encode [dict get $summary fallback_reason]] \
        [dict get $summary started_at] [dict get $summary finished_at] [llength $completion]]]} { return 0 }
    foreach id $completion {
        if {![parallelOctaveWrite $channel [list COMPLETEID [parallelOctaveB64Encode $id]]]} { return 0 }
    }
    foreach result [dict get $summary results] {
        set value [expr {[dict exists $result value] ? [dict get $result value] : ""}]
        set stdout [expr {[dict exists $result stdout] ? [dict get $result stdout] : $value}]
        set stderr [expr {[dict exists $result stderr] ? [dict get $result stderr] : ""}]
        set err [expr {[dict exists $result error] ? [dict get $result error] : ""}]
        set errorCode [expr {[dict exists $result error_code] ? [dict get $result error_code] : ""}]
        set reason [expr {[dict exists $result reason] ? [dict get $result reason] : ""}]
        if {![parallelOctaveWrite $channel [list ITEMRESULT \
            [dict get $result index] \
            [parallelOctaveB64Encode [dict get $result id]] \
            [parallelOctaveB64Encode [dict get $result state]] \
            [parallelOctaveB64Encode $value] [parallelOctaveB64Encode $stdout] [parallelOctaveB64Encode $stderr] \
            [parallelOctaveB64Encode $err] [parallelOctaveB64Encode $errorCode] [parallelOctaveB64Encode $reason] \
            [parallelOctaveExitStatus $result]]]} { return 0 }
    }
    return [parallelOctaveWrite $channel [list END]]
}

proc ::GX::parallelOctaveHandleCancel {channel parts} {
    if {[llength $parts] != 2} { error "CANCEL requires one run ID." }
    set runId [parallelOctaveB64Decode [lindex $parts 1]]
    set changed [parallelExecutionCancel $runId]
    parallelOctaveWrite $channel [list CANCELRESULT [parallelOctaveB64Encode $runId] $changed]
}

proc ::GX::parallelOctaveExecuteRequest {channel} {
    variable parallelOctaveConnection
    set analysisRunId $parallelOctaveConnection($channel,analysis_run_id)
    variable parallelOctaveService
    set moduleId $parallelOctaveService($analysisRunId,module_id)
    set request [parallelOctaveParseRequest $parallelOctaveConnection($channel,request_lines)]
    set options [dict get $request options]
    set requestedRun [string trim [dict get $options run_id]]
    if {$requestedRun eq ""} {
        set requestedRun [parallelExecutionNewRunId standard_octave]
        dict set options run_id $requestedRun
    }
    dict set options progress_command [list ::GX::parallelOctaveProgress $channel $analysisRunId $moduleId]
    # Nested standard_octave workers inherit the same authenticated endpoint.
    # Caller environment remains supported, but binding endpoint identity is
    # CORE-owned and cannot be redirected by a work-item request.
    set workerEnv [dict merge [dict get $options environment] [parallelOctaveServiceEnvironmentDict $analysisRunId]]
    dict set options environment $workerEnv
    set parallelOctaveConnection($channel,active_run_id) $requestedRun
    parallelOctaveServiceAddActiveRun $analysisRunId $requestedRun
    set operation [dict create kind process command_builder ::GX::parallelOctaveCommandBuilder]
    set code [catch {set summary [parallelExecutionExecute [dict get $request items] $operation $options]} message caught]
    parallelOctaveServiceRemoveActiveRun $analysisRunId $requestedRun
    if {[info exists parallelOctaveConnection($channel,active_run_id)]} { set parallelOctaveConnection($channel,active_run_id) "" }
    if {$code} {
        catch {parallelOctaveError $channel $message}
    } else {
        catch {parallelOctaveEmitSummary $channel $summary}
    }
    if {[info exists parallelOctaveConnection($channel,request_lines)]} { set parallelOctaveConnection($channel,request_lines) {} }
}

proc ::GX::parallelOctaveReadable {channel} {
    variable parallelOctaveConnection
    variable parallelOctaveService
    if {![info exists parallelOctaveConnection($channel,analysis_run_id)]} { catch {close $channel}; return }
    set analysisRunId $parallelOctaveConnection($channel,analysis_run_id)
    if {[eof $channel]} { parallelOctaveConnectionClose $channel 1; return }
    while {[gets $channel line] >= 0} {
        if {!$parallelOctaveConnection($channel,authenticated)} {
            set parts [split $line "\t"]
            if {[llength $parts] != 2 || [lindex $parts 0] ne "AUTH" || [lindex $parts 1] ne $parallelOctaveService($analysisRunId,token)} {
                parallelOctaveError $channel "Parallel Execution binding authentication failed."
                parallelOctaveConnectionClose $channel 0
                return
            }
            set parallelOctaveConnection($channel,authenticated) 1
            if {![parallelOctaveReady $channel $analysisRunId]} { parallelOctaveConnectionClose $channel 0; return }
            continue
        }
        set parts [split $line "\t"]
        if {[lindex $parts 0] eq "CANCEL"} {
            if {[catch {parallelOctaveHandleCancel $channel $parts} message]} { parallelOctaveError $channel $message }
            return
        }
        lappend parallelOctaveConnection($channel,request_lines) $line
        if {$line eq "EXEC"} {
            if {[catch {parallelOctaveExecuteRequest $channel} message]} { catch {parallelOctaveError $channel $message} }
            # parallelExecutionExecute enters a nested event loop. The client may
            # have disconnected while work was active, so never continue using
            # this channel from the older readable callback frame.
            return
        }
    }
    if {[lsearch -exact [chan names] $channel] >= 0 && [eof $channel]} { parallelOctaveConnectionClose $channel 1 }
}

proc ::GX::parallelOctaveRuntimeAppend {path} {
    variable parallelExecutionPolicy
    if {![file isfile $path]} { return $path }
    set fd [open $path a]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[parallel_execution_api\]"
    putKV $fd api_version 1
    putKV $fd standard_octave_binding 1
    putKV $fd helper gxtxt_parallel_execute_v1
    putKV $fd cancel_helper gxtxt_parallel_cancel_v1
    putKV $fd discovery_helper gxtxt_parallel_execution_info_v1
    putKV $fd workers {auto;serial;positive_integer}
    putKV $fd result_order input
    putKV $fd nested_policy serial
    putKV $fd default_workers [dict get $parallelExecutionPolicy default_workers]
    putKV $fd max_workers [dict get $parallelExecutionPolicy max_workers]
    putKV $fd recommended_internal_threads [dict get $parallelExecutionPolicy recommended_internal_threads]
    close $fd
    return $path
}

# The final runtime writer delegates to the named temporal-set predecessor.
# Re-sourcing this file replaces only this entry point, without stacking wrappers.
if {[llength [info commands ::GX::writeStandardRuntimeConfig_before_parallel_octave_binding_v1]]} {
    proc ::GX::writeStandardRuntimeConfig {moduleId} {
        set path [::GX::writeStandardRuntimeConfig_before_parallel_octave_binding_v1 $moduleId]
        return [parallelOctaveRuntimeAppend $path]
    }
}

proc ::GX::parallelOctaveCommandUsesStandardOctave {cmd} {
    foreach word $cmd {
        if {[file tail $word] eq "standard_octave_exec.tcl"} { return 1 }
    }
    return 0
}

# Start one loopback service for the standard_octave module that is about to run
# and inject only endpoint/authentication values into its environment.
# The service decorator is a fixed predecessor of documentation snapshotting.
# Re-sourcing replaces this named layer without stacking another wrapper.
if {[llength [info commands ::GX::runNextAnalysis_before_parallel_octave_binding_v1]]} {
    proc ::GX::runNextAnalysis_before_documentation_snapshot {} {
        variable analysisQueue
        if {[llength $analysisQueue] > 0} {
            set item [lindex $analysisQueue 0]
            if {[llength $item] >= 4} {
                set cmd [lindex $item 1]
                if {[parallelOctaveCommandUsesStandardOctave $cmd]} {
                    set moduleId [lindex $item 2]
                    set runId [lindex $item 3]
                    set env [parallelOctaveServiceStart $runId $moduleId]
                    if {[llength $cmd] > 0 && [lindex $cmd 0] eq "env"} {
                        set cmd [linsert $cmd 1 {*}$env]
                    } else {
                        set cmd [concat [list env] $env $cmd]
                    }
                    set item [lreplace $item 1 1 $cmd]
                    set analysisQueue [lreplace $analysisQueue 0 0 $item]
                }
            }
        }
        tailcall ::GX::runNextAnalysis_before_parallel_octave_binding_v1
    }
}

# Release the service associated with a module once its analysis pipe has ended.
if {[llength [info commands ::GX::onAnalysisReadable_before_parallel_octave_binding_v1]]} {
    proc ::GX::onAnalysisReadable_before_plan_status {p} {
        variable analysisPipe
        variable ui
        set runId [expr {[info exists ui(analysisCurrentRunId)] ? $ui(analysisCurrentRunId) : ""}]
        set code [catch {::GX::onAnalysisReadable_before_parallel_octave_binding_v1 $p} result options]
        if {$runId ne "" && ($analysisPipe eq "" || $analysisPipe ne $p)} { catch {parallelOctaveServiceStop $runId} }
        if {$code} { return -options $options $result }
        return $result
    }
}

# Cancellation first reaches the shared CORE coordinator. The existing analysis
# stop path may then terminate the standard_octave process without orphaning its
# worker processes or temporary Parallel Execution state.
if {[llength [info commands ::GX::stopAnalysis_before_parallel_octave_binding_v1]]} {
    proc ::GX::stopAnalysis_before_plan_status {{message 1}} {
        variable ui
        set runId [expr {[info exists ui(analysisCurrentRunId)] ? $ui(analysisCurrentRunId) : ""}]
        if {$runId ne ""} { catch {parallelOctaveServiceCancel $runId} }
        set result [::GX::stopAnalysis_before_parallel_octave_binding_v1 $message]
        if {$runId ne ""} { after 100 [list catch [list ::GX::parallelOctaveServiceStop $runId]] }
        return $result
    }
}
