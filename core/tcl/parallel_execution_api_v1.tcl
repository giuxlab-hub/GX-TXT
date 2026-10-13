# GX-TXT Parallel Execution API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public CORE coordinator for independent work items. The API owns scheduling,
# deterministic association, progress, cancellation and worker-count policy;
# scientific consumers continue to own Dataset/Publication semantics.

namespace eval ::GX {}
proc ::GX::parallelExecutionHardwareThreads {} {
    if {[info exists ::env(NUMBER_OF_PROCESSORS)] &&
        [string is integer -strict $::env(NUMBER_OF_PROCESSORS)] && $::env(NUMBER_OF_PROCESSORS) > 0} {
        return $::env(NUMBER_OF_PROCESSORS)
    }
    foreach command {{nproc} {getconf _NPROCESSORS_ONLN} {sysctl -n hw.ncpu}} {
        if {![catch {set count [string trim [exec {*}$command]]}] &&
            [string is integer -strict $count] && $count > 0} {
            return $count
        }
    }
    return 1
}

namespace eval ::GX {
    variable parallelExecutionApiVersion 1
    variable parallelExecutionCounter 0
    variable parallelExecutionActiveDepth 0
    variable parallelExecutionRun
    variable parallelExecutionProcessHelper [file normalize [file join [file dirname [info script]] .. python parallel_process_exec_v1.py]]
    variable parallelExecutionDetectedThreads [parallelExecutionHardwareThreads]
    variable parallelExecutionPolicy [dict create \
        enabled 1 \
        default_workers [expr {max(1, int(ceil($parallelExecutionDetectedThreads * 0.8)))}] \
        max_workers $parallelExecutionDetectedThreads \
        recommended_internal_threads 1]
}

proc ::GX::parallelExecutionApiInfo {} {
    variable parallelExecutionApiVersion
    variable parallelExecutionPolicy
    return [dict create \
        api_name {Parallel Execution API} \
        api_version $parallelExecutionApiVersion \
        work_item_identity id \
        operation_kinds {callback process} \
        policy $parallelExecutionPolicy \
        nested_policy serial \
        result_order input \
        runtime_state persistent_no]
}

proc ::GX::parallelExecutionBool {value field} {
    if {![string is boolean -strict $value]} {
        error "$field must be a boolean value."
    }
    return [expr {$value ? 1 : 0}]
}

proc ::GX::parallelExecutionPositiveInt {value field} {
    if {![string is integer -strict $value] || $value < 1} {
        error "$field must be an integer >= 1."
    }
    return $value
}

proc ::GX::parallelExecutionConfigure {{changes {}}} {
    variable parallelExecutionPolicy
    if {[catch {dict size $changes}]} {
        error "Parallel execution configuration must be a dictionary."
    }
    set candidate $parallelExecutionPolicy
    set allowed {enabled default_workers max_workers recommended_internal_threads}
    dict for {key value} $changes {
        if {$key ni $allowed} { error "Unknown Parallel Execution policy field '$key'." }
        switch -- $key {
            enabled { set value [parallelExecutionBool $value $key] }
            default_workers - max_workers - recommended_internal_threads {
                set value [parallelExecutionPositiveInt $value $key]
            }
        }
        dict set candidate $key $value
    }
    if {[dict get $candidate default_workers] > [dict get $candidate max_workers]} {
        error "default_workers must not exceed max_workers."
    }
    # Validate the complete candidate before changing the central policy so a
    # rejected configuration can never leave CORE in a partially updated state.
    # A supervised script already occupies a central scheduler CPU slot.
    # Nested public resource consumers receive the same bounded policy.
    if {[info exists ::env(GXTXT_JOB_THREADS)]} {
        set budget [parallelExecutionPositiveInt $::env(GXTXT_JOB_THREADS) GXTXT_JOB_THREADS]
        dict set candidate max_workers $budget
        dict set candidate default_workers [expr {min($budget,[dict get $candidate default_workers])}]
        dict set candidate recommended_internal_threads 1
    }
    set parallelExecutionPolicy $candidate
    return $parallelExecutionPolicy
}

proc ::GX::parallelExecutionNewRunId {{label core.parallel}} {
    variable parallelExecutionCounter
    incr parallelExecutionCounter
    set safe [string map {" " _ "/" _ "\\" _ ":" _} $label]
    return [format "%s-%d-%d-%d" $safe [clock milliseconds] [pid] $parallelExecutionCounter]
}

proc ::GX::parallelExecutionEnvDepth {} {
    if {![info exists ::env(GXTXT_PARALLEL_DEPTH)]} { return 0 }
    set value [string trim $::env(GXTXT_PARALLEL_DEPTH)]
    if {![string is integer -strict $value] || $value < 0} { return 0 }
    return $value
}

proc ::GX::parallelExecutionContextDepth {} {
    variable parallelExecutionActiveDepth
    set envDepth [parallelExecutionEnvDepth]
    return [expr {$parallelExecutionActiveDepth > $envDepth ? $parallelExecutionActiveDepth : $envDepth}]
}

proc ::GX::parallelExecutionNormalizeItems {items} {
    set out {}
    set seen [dict create]
    set index 0
    foreach item $items {
        if {[catch {dict size $item}]} {
            error "Parallel work item at index $index must be a dictionary."
        }
        if {![dict exists $item id] || [string trim [dict get $item id]] eq ""} {
            error "Parallel work item at index $index is missing a non-empty id."
        }
        set id [dict get $item id]
        if {[dict exists $seen $id]} { error "Duplicate parallel work-item id '$id'." }
        dict set seen $id 1
        lappend out $item
        incr index
    }
    return $out
}

proc ::GX::parallelExecutionNormalizeOperation {operation} {
    if {[catch {dict size $operation}]} {
        error "Parallel operation must be a dictionary."
    }
    if {![dict exists $operation kind]} { error "Parallel operation requires kind=callback or kind=process." }
    set kind [string tolower [string trim [dict get $operation kind]]]
    if {$kind ni {callback process}} { error "Unsupported parallel operation kind '$kind'." }
    if {$kind eq "callback"} {
        if {![dict exists $operation command] || [llength [dict get $operation command]] == 0} {
            error "Callback operations require a command prefix."
        }
    } else {
        if {![dict exists $operation command_builder] || [llength [dict get $operation command_builder]] == 0} {
            error "Process operations require a command_builder prefix."
        }
    }
    foreach field {environment} {
        if {[dict exists $operation $field] && [catch {dict size [dict get $operation $field]}]} {
            error "Parallel operation field '$field' must be a dictionary."
        }
    }
    dict set operation kind $kind
    if {![dict exists $operation environment]} { dict set operation environment [dict create] }
    if {![dict exists $operation result_parser]} { dict set operation result_parser {} }
    if {![dict exists $operation process_group]} { dict set operation process_group 1 }
    dict set operation process_group [parallelExecutionBool [dict get $operation process_group] process_group]
    return $operation
}

proc ::GX::parallelExecutionNormalizeOptions {options} {
    if {[catch {dict size $options}]} {
        error "Parallel execution options must be a dictionary."
    }
    set defaults [dict create \
        workers auto \
        fail_fast 0 \
        progress_command {} \
        run_id {} \
        environment [dict create]]
    set allowed [dict keys $defaults]
    dict for {key value} $options {
        if {$key ni $allowed} { error "Unknown Parallel Execution option '$key'." }
        dict set defaults $key $value
    }
    dict set defaults fail_fast [parallelExecutionBool [dict get $defaults fail_fast] fail_fast]
    if {[catch {dict size [dict get $defaults environment]}]} {
        error "Parallel Execution option environment must be a dictionary."
    }
    set workers [dict get $defaults workers]
    if {$workers eq "serial"} { set workers 1 }
    if {$workers ne "auto"} { set workers [parallelExecutionPositiveInt $workers workers] }
    dict set defaults workers $workers
    return $defaults
}

proc ::GX::parallelExecutionResolveWorkers {itemCount operation options} {
    variable parallelExecutionPolicy
    set requested [dict get $options workers]
    set maxWorkers [dict get $parallelExecutionPolicy max_workers]
    if {$requested ne "auto" && $requested > $maxWorkers} {
        error "Requested worker count $requested exceeds CORE max_workers=$maxWorkers."
    }
    if {$itemCount == 0} {
        return [dict create requested $requested resolved 0 fallback_reason {}]
    }
    set desired [expr {$requested eq "auto" ? [dict get $parallelExecutionPolicy default_workers] : $requested}]
    if {$desired > $itemCount} { set desired $itemCount }
    set fallback ""
    set nestedDepth [parallelExecutionContextDepth]
    if {$nestedDepth > 0 && $desired > 1} {
        set desired 1
        set fallback nested_parallelism
    } elseif {![dict get $parallelExecutionPolicy enabled] && $desired > 1} {
        set desired 1
        set fallback parallel_disabled
    } elseif {[dict get $operation kind] eq "callback" && $desired > 1} {
        # In-process Tcl callbacks are deliberately serial. True concurrency is
        # provided by the process operation so arbitrary Tcl state is never
        # shared unsafely between pseudo-workers.
        set desired 1
        set fallback callback_in_process
    }
    if {$desired < 1} { set desired 1 }
    return [dict create requested $requested resolved $desired fallback_reason $fallback]
}

proc ::GX::parallelExecutionValidateEnvironment {envDict} {
    dict for {key value} $envDict {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $key]} {
            error "Invalid worker environment variable name '$key'."
        }
    }
    return $envDict
}

proc ::GX::parallelExecutionTempDirectory {runId} {
    set base [expr {[info exists ::env(TMPDIR)] && [string trim $::env(TMPDIR)] ne "" ? $::env(TMPDIR) : "/tmp"}]
    if {[llength [info commands ::GX::configurationTempDirectory]] &&
        [info exists ::GX::configurationLoaded] && $::GX::configurationLoaded} {
        set base [configurationTempDirectory]
    }
    set safe [string map {"/" _ "\\" _ ":" _ " " _} $runId]
    set path [file join $base "gxtxt-parallel-$safe-[pid]-[clock clicks]"]
    file mkdir $path
    return [file normalize $path]
}

proc ::GX::parallelExecutionRunExists {runId} {
    variable parallelExecutionRun
    return [info exists parallelExecutionRun($runId,state)]
}

proc ::GX::parallelExecutionStatus {runId} {
    variable parallelExecutionRun
    if {![parallelExecutionRunExists $runId]} { error "Unknown Parallel Execution run '$runId'." }
    set out [dict create]
    foreach field {state cancel_requested requested_workers worker_count total completed success_count error_count cancelled_count not_executed_count fallback_reason started_at finished_at completion_order} {
        if {[info exists parallelExecutionRun($runId,$field)]} {
            dict set out $field $parallelExecutionRun($runId,$field)
        }
    }
    dict set out run_id $runId
    dict set out api_version 1
    return $out
}

proc ::GX::parallelExecutionCancel {runId} {
    variable parallelExecutionRun
    if {![parallelExecutionRunExists $runId]} { error "Unknown Parallel Execution run '$runId'." }
    if {$parallelExecutionRun($runId,state) in {completed failed cancelled}} { return 0 }
    set parallelExecutionRun($runId,cancel_requested) 1
    # Wake the coordinator from vwait. The coordinator owns termination so one
    # place remains responsible for channel/process cleanup and result states.
    incr parallelExecutionRun($runId,wakeup)
    return 1
}

proc ::GX::parallelExecutionRelease {runId} {
    variable parallelExecutionRun
    if {![parallelExecutionRunExists $runId]} { return 0 }
    if {$parallelExecutionRun($runId,state) ni {completed failed cancelled}} {
        error "Cannot release active Parallel Execution run '$runId'."
    }
    foreach key [array names parallelExecutionRun "$runId,*"] { unset parallelExecutionRun($key) }
    return 1
}

proc ::GX::parallelExecutionInvokePrefix {prefix args} {
    return [uplevel #0 [list {*}$prefix {*}$args]]
}

proc ::GX::parallelExecutionItemContext {runId index item} {
    variable parallelExecutionRun
    variable parallelExecutionPolicy
    return [dict create \
        api_version 1 \
        run_id $runId \
        item_id [dict get $item id] \
        index $index \
        worker_count $parallelExecutionRun($runId,worker_count) \
        parallel_depth [parallelExecutionContextDepth] \
        recommended_internal_threads [dict get $parallelExecutionPolicy recommended_internal_threads]]
}

proc ::GX::parallelExecutionProgress {runId state {itemId ""} {message ""}} {
    variable parallelExecutionRun
    if {![info exists parallelExecutionRun($runId,options)]} { return }
    set command [dict get $parallelExecutionRun($runId,options) progress_command]
    if {[llength $command] == 0} { return }
    set event [dict create \
        api_version 1 \
        state $state \
        mode determinate \
        stage parallel_execution \
        message $message \
        current $parallelExecutionRun($runId,completed) \
        total $parallelExecutionRun($runId,total) \
        module_id core.parallel \
        run_id $runId \
        item_id $itemId]
    # Progress is advisory. A UI/reporting callback must never corrupt the
    # scientific result association or worker lifecycle.
    catch {parallelExecutionInvokePrefix $command $event}
}

proc ::GX::parallelExecutionResult {index id state args} {
    set out [dict create index $index id $id state $state]
    foreach {key value} $args { dict set out $key $value }
    return $out
}

proc ::GX::parallelExecutionStoreResult {runId index result} {
    variable parallelExecutionRun
    set results $parallelExecutionRun($runId,results)
    lset results $index $result
    set parallelExecutionRun($runId,results) $results
    set state [dict get $result state]
    switch -- $state {
        success { incr parallelExecutionRun($runId,success_count); incr parallelExecutionRun($runId,completed) }
        error { incr parallelExecutionRun($runId,error_count); incr parallelExecutionRun($runId,completed) }
        cancelled { incr parallelExecutionRun($runId,cancelled_count); incr parallelExecutionRun($runId,completed) }
        not_executed { incr parallelExecutionRun($runId,not_executed_count) }
    }
    # completion_order describes work that actually entered execution. Pending
    # items deliberately not scheduled by cancellation/fail-fast are tracked
    # separately and must not masquerade as completed work.
    if {$state ne "not_executed"} {
        lappend parallelExecutionRun($runId,completion_order) [dict get $result id]
    }
    set msg [expr {$state eq "success" ? "Completed [dict get $result id]" : "[string totitle [string map {_ { }} $state]] [dict get $result id]"}]
    parallelExecutionProgress $runId running [dict get $result id] $msg
}

proc ::GX::parallelExecutionErrorCode {options} {
    if {[dict exists $options -errorcode]} { return [dict get $options -errorcode] }
    return {}
}

proc ::GX::parallelExecutionRunCallback {runId index item operation} {
    set id [dict get $item id]
    set context [parallelExecutionItemContext $runId $index $item]
    if {[catch {set value [parallelExecutionInvokePrefix [dict get $operation command] $item $context]} message options]} {
        return [parallelExecutionResult $index $id error error $message error_code [parallelExecutionErrorCode $options]]
    }
    return [parallelExecutionResult $index $id success value $value]
}

proc ::GX::parallelExecutionB64 {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::GX::parallelExecutionWriteProcessRequest {runId index argv workerEnv processGroup} {
    variable parallelExecutionRun
    set path [file join $parallelExecutionRun($runId,temp_dir) [format "request-%06d.txt" $index]]
    set fd [open $path w]
    fconfigure $fd -encoding ascii -translation lf
    puts $fd "GXTXT_PARALLEL_EXEC_V1"
    puts $fd "GROUP\t[expr {$processGroup ? 1 : 0}]"
    foreach arg $argv { puts $fd "ARG\t[parallelExecutionB64 $arg]" }
    dict for {key value} $workerEnv {
        puts $fd "ENV\t[parallelExecutionB64 $key]\t[parallelExecutionB64 $value]"
    }
    close $fd
    return $path
}

proc ::GX::parallelExecutionBuildProcessArgv {runId index item operation options} {
    variable parallelExecutionPolicy
    variable parallelExecutionProcessHelper
    set context [parallelExecutionItemContext $runId $index $item]
    set argv [parallelExecutionInvokePrefix [dict get $operation command_builder] $item $context]
    if {[llength $argv] == 0} { error "Process command_builder returned an empty argv list." }

    set workerEnv [dict merge [dict get $operation environment] [dict get $options environment]]
    set workerEnv [parallelExecutionValidateEnvironment $workerEnv]
    # These CORE-owned values communicate nesting/thread policy without
    # hard-coding BLAS, FFTW, Octave or another backend into the public API.
    dict set workerEnv GXTXT_PARALLEL_DEPTH [dict get $context parallel_depth]
    dict set workerEnv GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS [dict get $context recommended_internal_threads]

    set python [runtimeToolRequired python]
    if {![file isfile $parallelExecutionProcessHelper]} {
        error "Parallel Execution process launcher is missing: $parallelExecutionProcessHelper"
    }
    set processGroup [dict get $operation process_group]
    set requestPath [parallelExecutionWriteProcessRequest $runId $index $argv $workerEnv $processGroup]
    # Only framework-generated paths reach Tcl's pipeline parser. The requested
    # worker argv is decoded by the Python launcher and executed with execvpe(),
    # so user-derived arguments cannot become Tcl/shell redirection syntax.
    return [dict create \
        argv [list $python $parallelExecutionProcessHelper $requestPath] \
        process_group $processGroup \
        request_path $requestPath]
}

proc ::GX::parallelExecutionReadFile {path} {
    if {![file isfile $path]} { return "" }
    set fd [open $path r]
    fconfigure $fd -translation binary -encoding binary
    set data [read $fd]
    close $fd
    return $data
}

proc ::GX::parallelExecutionStartProcess {runId index} {
    variable parallelExecutionRun
    set item [lindex $parallelExecutionRun($runId,items) $index]
    set id [dict get $item id]
    set operation $parallelExecutionRun($runId,operation)
    set options $parallelExecutionRun($runId,options)
    if {[catch {set launch [parallelExecutionBuildProcessArgv $runId $index $item $operation $options]} message buildOptions]} {
        parallelExecutionStoreResult $runId $index [parallelExecutionResult $index $id error error $message error_code [parallelExecutionErrorCode $buildOptions]]
        return 0
    }
    set stderrPath [file join $parallelExecutionRun($runId,temp_dir) [format "stderr-%06d.log" $index]]
    set pipeline [concat [list |] [dict get $launch argv] [list 2>$stderrPath]]
    if {[catch {set channel [open $pipeline r]} message openOptions]} {
        catch {file delete -force -- $stderrPath}
        parallelExecutionStoreResult $runId $index [parallelExecutionResult $index $id error error $message error_code [parallelExecutionErrorCode $openOptions]]
        return 0
    }
    fconfigure $channel -blocking 0 -buffering none -translation binary -encoding binary
    set pids [pid $channel]
    set parallelExecutionRun($runId,item,$index,channel) $channel
    set parallelExecutionRun($runId,item,$index,pids) $pids
    set parallelExecutionRun($runId,item,$index,process_group) [dict get $launch process_group]
    set parallelExecutionRun($runId,item,$index,stderr_path) $stderrPath
    set parallelExecutionRun($runId,item,$index,request_path) [dict get $launch request_path]
    set parallelExecutionRun($runId,item,$index,stdout) ""
    lappend parallelExecutionRun($runId,active_indices) $index
    fileevent $channel readable [list ::GX::parallelExecutionProcessReadable $runId $index $channel]
    return 1
}

proc ::GX::parallelExecutionRemoveActiveIndex {runId index} {
    variable parallelExecutionRun
    set kept {}
    foreach value $parallelExecutionRun($runId,active_indices) {
        if {$value != $index} { lappend kept $value }
    }
    set parallelExecutionRun($runId,active_indices) $kept
}

proc ::GX::parallelExecutionProcessReadable {runId index channel} {
    variable parallelExecutionRun
    if {![parallelExecutionRunExists $runId]} { catch {fileevent $channel readable {}}; return }
    if {![info exists parallelExecutionRun($runId,item,$index,channel)] || $parallelExecutionRun($runId,item,$index,channel) ne $channel} {
        catch {fileevent $channel readable {}}
        return
    }
    if {[catch {set chunk [read $channel]} readError readOptions]} {
        set chunk ""
        set parallelExecutionRun($runId,item,$index,read_error) $readError
        set parallelExecutionRun($runId,item,$index,read_error_code) [parallelExecutionErrorCode $readOptions]
    }
    if {$chunk ne ""} { append parallelExecutionRun($runId,item,$index,stdout) $chunk }
    if {![eof $channel]} { return }
    parallelExecutionFinalizeProcess $runId $index 0
}

proc ::GX::parallelExecutionFinalizeProcess {runId index cancelled} {
    variable parallelExecutionRun
    if {![info exists parallelExecutionRun($runId,item,$index,channel)]} { return }
    set item [lindex $parallelExecutionRun($runId,items) $index]
    set id [dict get $item id]
    set channel $parallelExecutionRun($runId,item,$index,channel)
    catch {fileevent $channel readable {}}
    catch {append parallelExecutionRun($runId,item,$index,stdout) [read $channel]}
    catch {fconfigure $channel -blocking 1}
    set closeRc [catch {close $channel} closeMessage closeOptions]
    set stdout $parallelExecutionRun($runId,item,$index,stdout)
    set stderrPath $parallelExecutionRun($runId,item,$index,stderr_path)
    set requestPath $parallelExecutionRun($runId,item,$index,request_path)
    set stderr [parallelExecutionReadFile $stderrPath]
    catch {file delete -force -- $stderrPath}
    catch {file delete -force -- $requestPath}
    set readError [expr {[info exists parallelExecutionRun($runId,item,$index,read_error)] ? $parallelExecutionRun($runId,item,$index,read_error) : ""}]
    set readCode [expr {[info exists parallelExecutionRun($runId,item,$index,read_error_code)] ? $parallelExecutionRun($runId,item,$index,read_error_code) : {}}]
    foreach key [array names parallelExecutionRun "$runId,item,$index,*"] { unset parallelExecutionRun($key) }
    parallelExecutionRemoveActiveIndex $runId $index

    if {$cancelled || $parallelExecutionRun($runId,cancel_requested)} {
        set result [parallelExecutionResult $index $id cancelled stdout $stdout stderr $stderr]
    } elseif {$readError ne ""} {
        set result [parallelExecutionResult $index $id error error $readError error_code $readCode stdout $stdout stderr $stderr]
    } elseif {$closeRc} {
        set result [parallelExecutionResult $index $id error error $closeMessage error_code [parallelExecutionErrorCode $closeOptions] stdout $stdout stderr $stderr]
    } else {
        set parser [dict get $parallelExecutionRun($runId,operation) result_parser]
        if {[llength $parser]} {
            set context [parallelExecutionItemContext $runId $index $item]
            if {[catch {set value [parallelExecutionInvokePrefix $parser $stdout $item $context]} parseError parseOptions]} {
                set result [parallelExecutionResult $index $id error error $parseError error_code [parallelExecutionErrorCode $parseOptions] stdout $stdout stderr $stderr]
            } else {
                set result [parallelExecutionResult $index $id success value $value stderr $stderr]
            }
        } else {
            set result [parallelExecutionResult $index $id success value $stdout stderr $stderr]
        }
    }
    parallelExecutionStoreResult $runId $index $result
    incr parallelExecutionRun($runId,wakeup)
}

proc ::GX::parallelExecutionSignalPid {pid signal group} {
    if {$::tcl_platform(platform) eq "windows"} {
        set taskkill [auto_execok taskkill]
        if {$taskkill eq "" || $pid eq ""} { return 0 }
        # Windows has no POSIX process group for the Python launcher. /T
        # includes its worker child so cancellation cannot orphan Octave.
        return [expr {![catch {exec {*}$taskkill /PID $pid /T /F}]}]
    }
    set kill [auto_execok kill]
    if {$kill eq "" || $pid eq ""} { return 0 }
    if {$group} {
        if {![catch {exec $kill -$signal -- -$pid}]} { return 1 }
    }
    return [expr {![catch {exec $kill -$signal -- $pid}]}]
}

proc ::GX::parallelExecutionPidAlive {pid} {
    set kill [auto_execok kill]
    if {$kill eq "" || $pid eq ""} { return 0 }
    return [expr {![catch {exec $kill -0 -- $pid}]}]
}

proc ::GX::parallelExecutionTerminateActive {runId} {
    variable parallelExecutionRun
    set indices $parallelExecutionRun($runId,active_indices)
    foreach index $indices {
        if {![info exists parallelExecutionRun($runId,item,$index,channel)]} continue
        set channel $parallelExecutionRun($runId,item,$index,channel)
        catch {fileevent $channel readable {}}
        set group $parallelExecutionRun($runId,item,$index,process_group)
        foreach pid $parallelExecutionRun($runId,item,$index,pids) {
            parallelExecutionSignalPid $pid TERM $group
        }
    }
    # Give cooperative workers a short chance to exit, then guarantee cleanup.
    after 75
    foreach index $indices {
        if {![info exists parallelExecutionRun($runId,item,$index,pids)]} continue
        set group $parallelExecutionRun($runId,item,$index,process_group)
        foreach pid $parallelExecutionRun($runId,item,$index,pids) {
            if {[parallelExecutionPidAlive $pid]} { parallelExecutionSignalPid $pid KILL $group }
        }
    }
    foreach index $indices {
        if {[info exists parallelExecutionRun($runId,item,$index,channel)]} {
            parallelExecutionFinalizeProcess $runId $index 1
        }
    }
}

proc ::GX::parallelExecutionMarkNotExecuted {runId fromIndex reason} {
    variable parallelExecutionRun
    for {set index $fromIndex} {$index < $parallelExecutionRun($runId,total)} {incr index} {
        set current [lindex $parallelExecutionRun($runId,results) $index]
        if {$current ne ""} continue
        set item [lindex $parallelExecutionRun($runId,items) $index]
        parallelExecutionStoreResult $runId $index [parallelExecutionResult $index [dict get $item id] not_executed reason $reason]
    }
    set parallelExecutionRun($runId,next_index) $parallelExecutionRun($runId,total)
}

proc ::GX::parallelExecutionExecuteCallbacks {runId} {
    variable parallelExecutionRun
    set total $parallelExecutionRun($runId,total)
    for {set index 0} {$index < $total} {incr index} {
        # Process pending event-loop callbacks between items so cancellation is
        # observable even on the deterministic in-process serial path.
        catch {update}
        if {$parallelExecutionRun($runId,cancel_requested)} {
            parallelExecutionMarkNotExecuted $runId $index cancellation_requested
            break
        }
        set item [lindex $parallelExecutionRun($runId,items) $index]
        set result [parallelExecutionRunCallback $runId $index $item $parallelExecutionRun($runId,operation)]
        parallelExecutionStoreResult $runId $index $result
        set parallelExecutionRun($runId,next_index) [expr {$index + 1}]
        if {[dict get $result state] eq "error" && [dict get $parallelExecutionRun($runId,options) fail_fast]} {
            parallelExecutionMarkNotExecuted $runId [expr {$index + 1}] fail_fast
            break
        }
    }
}

proc ::GX::parallelExecutionExecuteProcesses {runId} {
    variable parallelExecutionRun
    while {1} {
        if {$parallelExecutionRun($runId,cancel_requested)} {
            set next $parallelExecutionRun($runId,next_index)
            if {$next < $parallelExecutionRun($runId,total)} {
                parallelExecutionMarkNotExecuted $runId $next cancellation_requested
            }
            parallelExecutionTerminateActive $runId
            break
        }
        set stopScheduling [expr {[dict get $parallelExecutionRun($runId,options) fail_fast] && $parallelExecutionRun($runId,error_count) > 0}]
        if {$stopScheduling && $parallelExecutionRun($runId,next_index) < $parallelExecutionRun($runId,total)} {
            parallelExecutionMarkNotExecuted $runId $parallelExecutionRun($runId,next_index) fail_fast
        }
        while {!$stopScheduling && !$parallelExecutionRun($runId,cancel_requested) && \
                [llength $parallelExecutionRun($runId,active_indices)] < $parallelExecutionRun($runId,worker_count) && \
                $parallelExecutionRun($runId,next_index) < $parallelExecutionRun($runId,total)} {
            set index $parallelExecutionRun($runId,next_index)
            incr parallelExecutionRun($runId,next_index)
            parallelExecutionStartProcess $runId $index
            if {[dict get $parallelExecutionRun($runId,options) fail_fast] && $parallelExecutionRun($runId,error_count) > 0} {
                set stopScheduling 1
                break
            }
        }
        if {[llength $parallelExecutionRun($runId,active_indices)] == 0} {
            if {$parallelExecutionRun($runId,next_index) >= $parallelExecutionRun($runId,total)} { break }
            continue
        }
        set before $parallelExecutionRun($runId,wakeup)
        vwait ::GX::parallelExecutionRun($runId,wakeup)
        # vwait returns for process completion or cancellation. The value itself
        # is only a wakeup generation and carries no scientific semantics.
        if {$parallelExecutionRun($runId,wakeup) == $before} { continue }
    }
}

proc ::GX::parallelExecutionCleanupRuntime {runId} {
    variable parallelExecutionRun
    if {[info exists parallelExecutionRun($runId,temp_dir)] && $parallelExecutionRun($runId,temp_dir) ne ""} {
        catch {file delete -force -- $parallelExecutionRun($runId,temp_dir)}
    }
    foreach key [array names parallelExecutionRun "$runId,item,*"] { unset parallelExecutionRun($key) }
    foreach field {items operation options temp_dir active_indices wakeup next_index results} {
        catch {unset parallelExecutionRun($runId,$field)}
    }
}

proc ::GX::parallelExecutionFinalizeRun {runId results} {
    variable parallelExecutionRun
    if {$parallelExecutionRun($runId,cancel_requested)} {
        set state cancelled
    } elseif {$parallelExecutionRun($runId,error_count) > 0} {
        set state failed
    } else {
        set state completed
    }
    set parallelExecutionRun($runId,state) $state
    set parallelExecutionRun($runId,finished_at) [clock milliseconds]
    parallelExecutionProgress $runId $state "" [string totitle $state]
    set summary [parallelExecutionStatus $runId]
    dict set summary results $results
    return $summary
}

proc ::GX::parallelExecutionExecute {items operation {options {}}} {
    variable parallelExecutionRun
    variable parallelExecutionActiveDepth
    set items [parallelExecutionNormalizeItems $items]
    set operation [parallelExecutionNormalizeOperation $operation]
    set options [parallelExecutionNormalizeOptions $options]
    set runId [string trim [dict get $options run_id]]
    if {$runId eq ""} { set runId [parallelExecutionNewRunId] }
    if {[parallelExecutionRunExists $runId]} { error "Parallel Execution run '$runId' already exists." }

    set workerInfo [parallelExecutionResolveWorkers [llength $items] $operation $options]
    foreach {field value} [list \
        state pending cancel_requested 0 \
        requested_workers [dict get $workerInfo requested] \
        worker_count [dict get $workerInfo resolved] \
        fallback_reason [dict get $workerInfo fallback_reason] \
        total [llength $items] completed 0 success_count 0 error_count 0 cancelled_count 0 not_executed_count 0 \
        started_at [clock milliseconds] finished_at {} completion_order {} \
        wakeup 0 next_index 0 active_indices {} \
        items $items operation $operation options $options] {
        set parallelExecutionRun($runId,$field) $value
    }
    set parallelExecutionRun($runId,results) [lrepeat [llength $items] ""]

    if {[llength $items] == 0} {
        set parallelExecutionRun($runId,state) running
        parallelExecutionProgress $runId running "" "No work items"
        set result [parallelExecutionFinalizeRun $runId {}]
        parallelExecutionCleanupRuntime $runId
        return $result
    }

    set parallelExecutionRun($runId,state) running
    if {[dict get $operation kind] eq "process"} {
        set parallelExecutionRun($runId,temp_dir) [parallelExecutionTempDirectory $runId]
    } else {
        set parallelExecutionRun($runId,temp_dir) ""
    }
    parallelExecutionProgress $runId running "" "Started"
    incr parallelExecutionActiveDepth
    set code [catch {
        if {[dict get $operation kind] eq "callback"} {
            parallelExecutionExecuteCallbacks $runId
        } else {
            parallelExecutionExecuteProcesses $runId
        }
    } message caughtOptions]
    incr parallelExecutionActiveDepth -1

    if {$code} {
        # An internal coordinator failure is distinct from a per-item failure.
        # Active workers are terminated before the exception is propagated.
        catch {set parallelExecutionRun($runId,cancel_requested) 1; parallelExecutionTerminateActive $runId}
        set parallelExecutionRun($runId,state) failed
        set parallelExecutionRun($runId,finished_at) [clock milliseconds]
        parallelExecutionCleanupRuntime $runId
        return -options $caughtOptions $message
    }

    set results $parallelExecutionRun($runId,results)
    set result [parallelExecutionFinalizeRun $runId $results]
    parallelExecutionCleanupRuntime $runId
    return $result
}
