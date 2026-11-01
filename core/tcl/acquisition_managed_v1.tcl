# SPDX-License-Identifier: GPL-3.0-or-later
# Additive auxiliary execution under Acquisition, existing ScriptJobAsync and
# DatasetAuthority. No new scheduler, Registry, numeric writer or recovery owner.
namespace eval ::GX::AcquisitionManaged {variable requests {};variable worker {};variable uiRequest {}}
proc ::GX::acquisitionHandlerAuthorityBusy {session} {
    variable ::GX::AcquisitionManaged::requests
    dict for {token context} $requests {if {[dict get $context session] eq $session && [dict get $context phase] ne {finished}} {return 1}}
    return 0
}
proc ::GX::_acquisitionManagedAtomic {path value} {
    set temporary "$path.[pid].tmp"
    set ch [open $temporary {WRONLY CREAT EXCL}]
    catch {file attributes $temporary -permissions 0600}
    fconfigure $ch -encoding utf-8 -translation lf
    try {puts -nonewline $ch $value} finally {close $ch}
    file rename -force -- $temporary $path
}
proc ::GX::_acquisitionManagedRead {path} {
    if {![file isfile $path]} {return {}}
    if {[file type $path] eq {link} || [file size $path]>65536} {error {Invalid bounded Acquisition control record}}
    set ch [open $path r];fconfigure $ch -encoding utf-8
    try {set value [read $ch]} finally {close $ch}
    if {[catch {dict size $value}]} {error {Invalid Acquisition control dictionary}}
    return $value
}
proc ::GX::_acquisitionManagedWorkerProgress {module event} {
    variable ::GX::AcquisitionManaged::worker
    if {$worker eq {}} {return [acquisitionHandlerProgressCallback $module $event]}
    dict set event module_id $module
    dict set event operation_id [dict get $worker operation_id]
    dict set event owner_pid [pid]
    dict set event staging [datasetPublicationV2DictDefault $worker staging {}]
    dict set event publication_resources [datasetPublicationV2DictDefault $worker publication_resources {}]
    dict set event raw_directory_existed [datasetPublicationV2DictDefault $worker raw_directory_existed 1]
    dict set event updated_ms [clock milliseconds]
    _acquisitionManagedAtomic [dict get $worker progress] $event
    return $event
}
proc ::GX::_acquisitionManagedResourceTrack {allocation} {
    variable ::GX::AcquisitionManaged::worker
    if {$worker eq {}} return
    dict lappend worker publication_resources [dict create id [dict get $allocation id] path [file normalize [dict get $allocation path]]]
    _acquisitionManagedWorkerProgress [dict get $worker module] [dict create phase publication mode indeterminate message {Preparing owned channel publication workspace}]
}
proc ::GX::_acquisitionManagedStageTrack {path} {
    variable ::GX::AcquisitionManaged::worker
    if {$worker eq {}} return
    dict set worker raw_directory_existed [file exists [file join [dict get $worker session] raw [sanitize [dict get $worker module]] [sanitize [dict get $worker dataset_id]]]]
    dict lappend worker staging [file normalize $path]
    _acquisitionManagedWorkerProgress [dict get $worker module] [dict create phase raw mode indeterminate message {Copying and verifying immutable RAW source}]
}
proc ::GX::_acquisitionManagedWorkerCancel {} {
    variable ::GX::AcquisitionManaged::worker
    if {$worker eq {}} {return [acquisitionHandlerCancelRequested]}
    set control [_acquisitionManagedRead [dict get $worker lease]]
    return [expr {$control eq {} || [datasetPublicationV2DictDefault $control cancelled 1] || [datasetPublicationV2DictDefault $control session_token {}] ne [dict get $worker session_token]}]
}
proc ::GX::_acquisitionManagedCheck {} {if {[_acquisitionManagedWorkerCancel]} {error {Acquisition cancelled or Session changed before commit}}}
proc ::GX::_acquisitionManagedWorkerLog {module text} {
    _acquisitionManagedWorkerProgress $module [dict create phase diagnostic mode indeterminate message [string range $text 0 1023]]
}
proc ::GX::_acquisitionManagedExecute {request} {
    set module [dict get $request module];set session [dict get $request session]
    _acquisitionManagedCheck
    set current {}
    foreach source [dict get $request sources] reviewed [dict get $request source_review] {
        if {![file isfile $source] || [list [file size $source] [file mtime $source]] ne $reviewed} {error {Acquisition source changed since review; reopen import}}
    }
    set sourceHashes [lmap source [dict get $request sources] {sha256File $source}]
    set ids [acquisitionHandlerImportSourcesToSession $module $session [dict get $request sources] [dict get $request dataset_id] [dict get $request contract] [dict get $request variables] [dict get $request options]]
    _acquisitionManagedCheck
    foreach source [dict get $request sources] expected $sourceHashes {
        if {![file isfile $source] || [sha256File $source] ne $expected} {error {Acquisition source changed during import; no outputs were committed}}
    }
    set result [dict create operation_id [dict get $request operation_id] status completed session $session module_id $module dataset_ids $ids]
    set receipt [dict get $request receipt]
    file mkdir [file dirname $receipt]
    datasetAuthorityEnlist $receipt
    _acquisitionManagedAtomic $receipt $result
    _acquisitionManagedWorkerProgress $module [dict create phase commit mode indeterminate message {Committing complete Acquisition transaction}]
    return $result
}
proc ::GX::_acquisitionManagedCompletion {request} {
    set receipt [_acquisitionManagedRead [dict get $request receipt]]
    if {$receipt ne {}} {
        foreach key {operation_id session} {if {[dict get $receipt $key] ne [dict get $request $key]} {error {Acquisition completion identity differs}}}
        return $receipt
    }
    return [dict create operation_id [dict get $request operation_id] status cancelled session [dict get $request session] module_id [dict get $request module] dataset_ids {}]
}
proc ::GX::_acquisitionManagedRecoverStages {request} {
    set progress [_acquisitionManagedRead [dict get $request progress]]
    if {$progress eq {}} return
    if {[dict get $progress operation_id] ne [dict get $request operation_id]} {error {Acquisition staging ownership differs}}
    set owner [dict get $progress owner_pid]
    if {![string is integer -strict $owner] || $owner<=1} {error {Invalid Acquisition staging owner}}
    set root [file normalize [file join [dict get $request session] .acquisition-txn]]
    set prefix "[sanitize [dict get $request dataset_id]]-$owner-"
    foreach path [datasetPublicationV2DictDefault $progress staging {}] {
        set path [file normalize $path]
        if {[file dirname $path] ne $root || ![string match "$prefix*" [file tail $path]]} {error {Acquisition staging cleanup identity differs}}
        if {[file exists $path]} {if {[file type $path] eq {link}} {error {Unsafe Acquisition staging link}};file delete -force -- $path}
    }
    foreach allocation [datasetPublicationV2DictDefault $progress publication_resources {}] {
        set id [dict get $allocation id]
        if {![regexp {^resource-[a-f0-9]{32}$} $id]} {error {Invalid Acquisition workspace resource identity}}
        set record [resourceManagementInspect $id]
        if {[dict get $record owner_pid]!=$owner || [dict get $record subsystem] ne {acquisition_publication} || [dict get $record session] ne [dict get $request session] || ![dict get $record managed] || [dict get $record recovery_required] || [file normalize [dict get $record path]] ne [dict get $allocation path]} {error {Acquisition workspace ownership differs during recovery}}
        if {![dict get $record removed]} {
            resourceManagementRelease $id
            resourceManagementCleanup [list $id]
            if {![dict get [resourceManagementInspect $id] removed]} {error {Owned Acquisition workspace cleanup was refused}}
        }
    }
    _acquisitionManagedRecoverEmptyRaw $request $progress
}
proc ::GX::_acquisitionManagedRecoverEmptyRaw {request progress} {
    if {[dict get $request source_storage] ne {copy} || [file exists [dict get $request receipt]] || [datasetPublicationV2DictDefault $progress raw_directory_existed 1]} return
    set directory [file join [dict get $request session] raw [sanitize [dict get $request module]] [sanitize [dict get $request dataset_id]]]
    if {![file exists $directory]} return
    if {[file type $directory] ne {directory}} {error {Acquisition RAW cleanup found an unexpected object}}
    set names [glob -nocomplain -tails -directory $directory * .*]
    foreach name $names {if {$name ni {. ..}} {return}}
    # Non-force removal cannot delete a concurrently added file. Never prune
    # shared module/root directories or pre-existing request directories.
    file delete -- $directory
}
proc ::GX::_acquisitionManagedParserPoll {marker id request progress} {
    variable ::GX::AcquisitionManaged::parserResults
    if {![dict exists $::GX::AcquisitionManaged::parserActive $marker] || [dict exists $parserResults $marker]} return
    if {[_acquisitionManagedWorkerCancel]} {scriptJobRequestCancel $id}
    if {[file isfile $progress]} {
        set value [_acquisitionManagedRead $progress]
        if {$value ne {}} {acquisitionHandlerInvokeCallback [dict get $request progress_callback] $value}
    }
    after 50 [list ::GX::_acquisitionManagedParserPoll $marker $id $request $progress]
}
proc ::GX::_acquisitionManagedParserDone {marker response} {dict set ::GX::AcquisitionManaged::parserResults $marker $response;set ::GX::AcquisitionManaged::parserWake [clock clicks]}
proc ::GX::acquisitionHandlerExecuteWorker {command request} {
    variable ::GX::AcquisitionManaged::worker
    if {$worker eq {}} {return [exec {*}$command 2>@1]}
    variable ::GX::AcquisitionManaged::parserResults
    if {![info exists parserResults]} {set parserResults {}}
    set marker parser-[pid]-[clock clicks]
    dict set ::GX::AcquisitionManaged::parserActive $marker 1
    set progress [file join [dict get $request output_dir] .parser-progress]
    acquisitionHandlerInvokeCallback [dict get $request progress_callback] [dict create phase parser mode determinate current 0 total 100 message {Starting source parser}]
    set wrapped [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python acquisition_worker_envelope.py] parser --progress $progress -- {*}$command]
    set id [scriptJobAsync $wrapped {} [list ::GX::_acquisitionManagedParserDone $marker] {timeout_ms 0 max_bytes 1048576 process_group 0 label {Acquisition parser}}]
    _acquisitionManagedParserPoll $marker $id $request $progress
    while {![dict exists $parserResults $marker]} {vwait ::GX::AcquisitionManaged::parserWake}
    dict unset ::GX::AcquisitionManaged::parserActive $marker
    set response [dict get $parserResults $marker];dict unset parserResults $marker
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result diagnostic_tail]
}

proc ::GX::acquisitionHandlerImportSourcesAsync {module session sources datasetId contract variables {options {}} {callback {}}} {
    variable ::GX::AcquisitionManaged::requests
    if {[datasetAuthorityActive]} {error {Managed Acquisition must start outside a Dataset transaction}}
    if {$session eq {} || $::GX::currentSession eq {} || [file normalize $session] ne [file normalize $::GX::currentSession]} {error {Managed Acquisition requires the reviewed selected Session}}
    set session [file normalize $session]
    if {![file isdirectory $session] || [acquisitionHandlerAuthorityBusy $session]} {error {The selected Session is unavailable or already importing}}
    acquisitionHandlerLoadModule $module
    acquisitionHandlerValidateDatasetId $datasetId
    if {![llength $sources] || [llength $sources]>64 || [string bytelength $variables]>262144 || [string bytelength $options]>65536} {error {Managed Acquisition requires bounded sources, schema and options}}
    set review {};set normalized {}
    foreach source $sources {
        set source [file normalize $source]
        if {![file isfile $source]} {error {Managed Acquisition source is unavailable}}
        lappend normalized $source;lappend review [list [file size $source] [file mtime $source]]
    }
    set token [interactiveDocumentSessionToken]
    set operation "acq-[pid]-[clock clicks]"
    set allocation [resourceManagementAllocate acquisition_request [dict create kind directory session $session lifetime computation]]
    set directory [dict get $allocation path]
    set config {};foreach key [moduleConfigKeys $module] {if {[info exists ::GX::moduleCfg($module,$key)]} {dict set config $module,$key $::GX::moduleCfg($module,$key)}}
    set tools {};foreach tool {python octave} {set executable [runtimeToolResolve $tool];if {$executable ne {}} {dict set tools $tool $executable}}
    set request [dict create operation import operation_id $operation session $session session_token $token module $module sources $normalized source_review $review dataset_id $datasetId contract $contract variables $variables options $options config $config source_storage [acquisitionHandlerSourceStoragePolicy $module] tools $tools workers [configurationGet computation.default_workers] parallel_policy [dict get [parallelExecutionApiInfo] policy] parallel_depth [parallelExecutionContextDepth] module_sha256 [sha256File [moduleField $module descriptor {}]] progress [file join $directory progress.tcldict] lease [file join $directory lease.tcldict] receipt [file join $session logs acquisition "${operation}.tcldict"]]
    set requestPath [file join $directory request.tcldict]
    _acquisitionManagedAtomic [dict get $request lease] [dict create cancelled 0 session_token $token]
    _acquisitionManagedAtomic $requestPath $request
    set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python acquisition_worker_envelope.py] bootstrap --framework $::GX::scriptDir --request $requestPath]
    set context [dict create session $session request $request callback $callback allocation $allocation phase preparing cancel_reason {} timer {} started [clock milliseconds] progress_stamp {}]
    dict set requests $operation $context
    if {[catch {set id [scriptJobAsync $command {} [list ::GX::_acquisitionManagedDone $operation] {timeout_ms 3600000 max_bytes 1048576 process_group 1 ui_lifetime 1 label {Managed Acquisition}}]} reason options]} {
        dict unset requests $operation
        resourceManagementRelease [dict get $allocation id];resourceManagementCleanup [list [dict get $allocation id]]
        return -options $options $reason
    }
    dict set requests $operation request_id $id
    dict set requests $operation phase running
    _acquisitionManagedTick $operation
    return [dict create operation_id $operation request_id $id session $session state preparing]
}
proc ::GX::acquisitionHandlerCancelAsync {operation {reason {Cancelled by user}}} {
    variable ::GX::AcquisitionManaged::requests
    if {![dict exists $requests $operation] || [dict get $requests $operation phase] in {recovering finished recovery_failed}} {return 0}
    if {[dict get $requests $operation cancel_reason] ne {}} {return 1}
    dict set requests $operation cancel_reason $reason
    set context [dict get $requests $operation]
    _acquisitionManagedAtomic [dict get $context request lease] [dict create cancelled 1 session_token [dict get $context request session_token]]
    scriptJobRequestCancel [dict get $context request_id]
    return 1
}
proc ::GX::_acquisitionManagedTick {operation} {
    variable ::GX::AcquisitionManaged::requests
    variable ::GX::AcquisitionManaged::uiRequest
    if {![dict exists $requests $operation] || [dict get $requests $operation phase] ne {running}} return
    set context [dict get $requests $operation];set request [dict get $context request]
    set actualToken [expr {$::GX::currentSession eq {} ? {} : [interactiveDocumentSessionToken]}]
    if {$actualToken ne [dict get $request session_token]} {acquisitionHandlerCancelAsync $operation {Session changed; original import cancelled}}
    if {$uiRequest eq $operation && $::GX::acquisitionHandlerCancelFlag} {acquisitionHandlerCancelAsync $operation}
    if {![catch {_acquisitionManagedRead [dict get $request progress]} event] && $event ne {}} {
        set stamp [datasetPublicationV2DictDefault $event updated_ms {}]
        if {$stamp ne [dict get $context progress_stamp]} {
            dict set requests $operation progress_stamp $stamp
            set visible [dict create state running module_id [dict get $request module]]
            foreach key {phase mode current total rows prepared_channels message} {if {[dict exists $event $key]} {dict set visible $key [dict get $event $key]}}
            if {[dict get $requests $operation cancel_reason] ne {}} {dict set visible mode indeterminate;dict set visible message {Cancelling Acquisition and recovering owned resources}}
            acquisitionHandlerProgressCallback [dict get $request module] $visible
            if {$uiRequest eq $operation} {_acquisitionManagedUiProgress $visible}
        }
    }
    dict set requests $operation timer [after 50 [list ::GX::_acquisitionManagedTick $operation]]
}
proc ::GX::_acquisitionManagedDone {operation response} {
    variable ::GX::AcquisitionManaged::requests
    if {![dict exists $requests $operation]} return
    set context [dict get $requests $operation]
    if {[dict get $context timer] ne {}} {after cancel [dict get $context timer]}
    dict set requests $operation response $response
    dict set requests $operation phase recovering
    set request [dict get $context request]
    dict set request operation recover
    set path [file join [dict get [dict get $context allocation] path] recover.tcldict]
    _acquisitionManagedAtomic $path $request
    set progress [dict create state running phase recovery mode indeterminate message {Reconciling Acquisition transaction and owned resources}]
    acquisitionHandlerProgressCallback [dict get $request module] $progress
    if {$::GX::AcquisitionManaged::uiRequest eq $operation} {_acquisitionManagedUiProgress $progress}
    set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python acquisition_worker_envelope.py] bootstrap --framework $::GX::scriptDir --request $path]
    if {[catch {scriptJobAsync $command {} [list ::GX::_acquisitionManagedRecovered $operation] {timeout_ms 120000 max_bytes 1048576 process_group 1 ui_lifetime 0 label {Acquisition recovery}}} reason]} {_acquisitionManagedRecovered $operation [dict create ok 0 error $reason]}
}
proc ::GX::_acquisitionManagedRecovered {operation response} {
    variable ::GX::AcquisitionManaged::requests
    if {![dict exists $requests $operation]} return
    set context [dict get $requests $operation];set request [dict get $context request]
    if {![dict get $response ok]} {
        dict set requests $operation phase recovery_failed
        dict set response recovery_required 1
        acquisitionHandlerProgressCallback [dict get $request module] [dict create state failed phase recovery message {Acquisition recovery requires review; Session remains protected}]
    } else {
        set result [dict get $response result]
        dict set requests $operation phase finished
        if {[dict get $result status] eq {completed}} {
            dict set result request_id [dict get $context request_id]
            if {[dict get $context cancel_reason] ne {}} {dict set result diagnostic {The transaction completed before cancellation took effect}}
            set response [dict create ok 1 result $result]
        } elseif {[dict get $context cancel_reason] ne {}} {
            set response [dict create ok 1 result [dict replace $result diagnostic [dict get $context cancel_reason]]]
        } else {
            set original [dict get $context response]
            set error [datasetPublicationV2DictDefault $original error {Acquisition ended without an authoritative committed receipt}]
            set response [dict create ok 0 error $error recovered 1]
        }
        set selected [expr {$::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [dict get $request session] && [interactiveDocumentSessionToken] eq [dict get $request session_token]}]
        if {$selected && [dict get $response ok] && [dict get $response result status] eq {completed}} {loadDatasetRegistry [dict get $request session]}
        # The live host remains the control allocation's Resource owner. Keep
        # its release/cleanup on that public asynchronous owner, off Tk's stack.
        set resource [dict get $context allocation id]
        resourceManagementAsync release [list resource_id $resource state verified_orphan] [list ::GX::_acquisitionManagedResourceReleased $resource]
        dict unset requests $operation
    }
    if {[dict get $context callback] ne {}} {uplevel #0 [list {*}[dict get $context callback] $response]}
}
proc ::GX::_acquisitionManagedResourceReleased {resource code output} {
    if {$code} {guiLog {Acquisition temporary resource release remains available in Resource Management};return}
    resourceManagementAsync cleanup [list $resource] ::GX::_acquisitionManagedResourceCleaned
}
proc ::GX::_acquisitionManagedResourceCleaned {code output} {if {$code} {guiLog {Acquisition temporary resource cleanup remains available in Resource Management}}}

proc ::GX::_acquisitionManagedUiBusy {busy} {
    variable ui
    variable ::GX::AcquisitionManaged::disabled
    if {![llength [info commands winfo]]} return
    if {$busy} {
        set heading .top.nb.acq.heading
        if {[winfo exists $heading] && ![winfo exists $heading.managed]} {
            ttk::frame $heading.managed -padding {0 4}
            ttk::label $heading.managed.label -textvariable ::GX::AcquisitionManaged::uiMessage -wraplength 850
            ttk::progressbar $heading.managed.progress -mode indeterminate
            ttk::button $heading.managed.cancel -text {Cancel import} -command ::GX::stopCurrent
            grid $heading.managed.label -row 0 -column 0 -columnspan 2 -sticky ew
            grid $heading.managed.progress -row 1 -column 0 -sticky ew -padx {0 6}
            grid $heading.managed.cancel -row 1 -column 1 -sticky e
            grid columnconfigure $heading.managed 0 -weight 1
            pack $heading.managed -fill x
            bind $heading.managed <Configure> {%W.label configure -wraplength [expr {max(200,%w-12)}]}
        }
        set ::GX::AcquisitionManaged::uiMessage {Preparing Acquisition…}
        set disabled {}
        set queue {}
        if {[winfo exists .top.nb.acq]} {lappend queue .top.nb.acq}
        foreach key {startButton analysisStart runAllButton} {if {[info exists ui($key)] && [winfo exists $ui($key)]} {lappend queue $ui($key)}}
        while {[llength $queue]} {
            set widget [lindex $queue 0];set queue [lrange $queue 1 end]
            lappend queue {*}[winfo children $widget]
            if {[winfo class $widget] in {TButton TEntry TCombobox TCheckbutton TSpinbox}} {dict set disabled $widget [$widget state];$widget state disabled}
        }
    } elseif {[info exists disabled]} {
        dict for {widget state} $disabled {if {[winfo exists $widget]} {$widget state !disabled;if {{disabled} in $state} {$widget state disabled}}}
        set disabled {}
    }
    set panel .top.nb.acq.heading.managed
    if {[winfo exists $panel]} {
        $panel.cancel state [expr {$busy?{!disabled}:{disabled}}]
        if {$busy} {
            grid $panel.progress;grid $panel.cancel
            $panel.progress configure -mode indeterminate;$panel.progress start 80
        } else {
            # Completion/cleanup already ended before this UI-only branch.
            # Keep the final message and row diagnostics, release idle chrome.
            $panel.progress stop;grid remove $panel.progress;grid remove $panel.cancel
        }
    }
    if {[info exists ui(stopButton)] && [winfo exists $ui(stopButton)]} {$ui(stopButton) configure -state [expr {$busy?{normal}:{disabled}}]}
}
proc ::GX::_acquisitionManagedUiProgress {event} {
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.acq.heading.managed]} return
    set panel .top.nb.acq.heading.managed
    set ::GX::AcquisitionManaged::uiMessage [dict get $event message]
    $panel.progress stop
    if {[datasetPublicationV2DictDefault $event mode indeterminate] eq {determinate} && [dict exists $event total] && [dict get $event total]>0} {
        $panel.progress configure -mode determinate -maximum [dict get $event total] -value [dict get $event current]
    } else {$panel.progress configure -mode indeterminate;$panel.progress start 80}
}
proc ::GX::_acquisitionManagedGuiSessionValid {} {
    variable ::GX::AcquisitionManaged::queueState
    expr {$::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [dict get $queueState session] && [interactiveDocumentSessionToken] eq [dict get $queueState session_token]}
}
proc ::GX::_acquisitionManagedGuiNext {} {
    variable ::GX::AcquisitionManaged::queueState
    variable ::GX::AcquisitionManaged::uiRequest
    if {![_acquisitionManagedGuiSessionValid] || $::GX::acquisitionHandlerCancelFlag || ![llength [dict get $queueState pending]]} {
        _acquisitionManagedGuiFinish
        return
    }
    set plan [lindex [dict get $queueState pending] 0]
    dict set queueState pending [lrange [dict get $queueState pending] 1 end]
    dict set queueState current $plan
    set module [dict get $queueState module]
    if {[catch {
        set started [acquisitionHandlerImportSourcesAsync $module [dict get $queueState session] [dict get $plan sources] [dict get $plan dataset_id] [dict get $plan contract] [dict get $plan variables] {} ::GX::_acquisitionManagedGuiDone]
        set uiRequest [dict get $started operation_id]
    } reason]} {
        _acquisitionManagedGuiDone [dict create ok 0 error $reason]
    }
}
proc ::GX::_acquisitionManagedGuiDone {response} {
    variable ::GX::AcquisitionManaged::queueState
    variable ::GX::AcquisitionManaged::uiRequest
    set plan [dict get $queueState current]
    set valid [_acquisitionManagedGuiSessionValid]
    set state [expr {[dict get $response ok] ? [dict get $response result status] : {failed}}]
    if {$state eq {completed}} {
        set ids [dict get $response result dataset_ids]
        set message "Imported Dataset(s): [join $ids {, }]"
        dict incr queueState completed
    } else {
        set message [expr {[dict get $response ok] ? [datasetPublicationV2DictDefault [dict get $response result] diagnostic {Cancelled}] : [dict get $response error]}]
        if {$state eq {cancelled}} {set ::GX::acquisitionHandlerCancelFlag 1} else {dict incr queueState failed}
    }
    dict lappend queueState results [dict create row [dict get $plan row] status $state message $message]
    if {$valid && [dict get $plan row]>0} {
        set row [dict get $plan row]
        if {[info exists ::GX::genericCsvBatch($row,path)] && [info exists ::GX::genericCsvBatch($row,dataset_id)] && [file normalize $::GX::genericCsvBatch($row,path)] eq [dict get $plan source] && $::GX::genericCsvBatch($row,dataset_id) eq [dict get $plan dataset_id]} {
            genericCsvBatchRecord $row [expr {$state eq {completed}?{Imported}:($state eq {cancelled}?{Cancelled}:{Failed})}] $message
        }
    }
    if {[dict exists $response recovery_required] && [dict get $response recovery_required]} {
        dict set queueState pending {}
        dict set queueState recovery_required 1
    }
    set uiRequest {}
    after 1 ::GX::_acquisitionManagedGuiNext
}
proc ::GX::_acquisitionManagedGuiFinish {} {
    variable ::GX::AcquisitionManaged::queueState
    variable ::GX::AcquisitionManaged::uiRequest
    set valid [_acquisitionManagedGuiSessionValid]
    set cancelled $::GX::acquisitionHandlerCancelFlag
    set success [expr {!$cancelled && ![dict get $queueState failed]}]
    set module [dict get $queueState module]
    set completed [dict get $queueState completed]
    set failed [dict get $queueState failed]
    set ::GX::acquisitionHandlerBatchLastReport [dict create summary [dict create imported $completed failed $failed skipped [llength [dict get $queueState pending]]] rows [dict get $queueState results] session [dict get $queueState session]]
    set uiRequest {};set ::GX::acquisitionHandlerAsyncActive 0;set ::GX::acquisitionHandlerCancelFlag 0
    _acquisitionManagedUiBusy 0
    if {$valid} {
        if {[dict get $queueState batch] && [info exists ::GX::interactiveImportQueue] && $::GX::interactiveImportQueue} {importQueuePruneSuccessful}
        set refresh {genericCsvBatchRender refreshResults refreshAnalysisStatus refreshGraphs refreshNativeVariablesGui refreshDatasetInspectionChoices refreshAnalysisSourceWidgets updateSessionUi refreshCsvPreview refreshManifestPreview}
        if {$completed>0} {set refresh [linsert $refresh 0 _acquisitionManagedPersistCurrentManifest]}
        after 1 [list ::GX::_acquisitionManagedUiRefresh [dict get $queueState session] [dict get $queueState session_token] $refresh]
    }
    set state [expr {$cancelled?{cancelled}:($success?{completed}:{failed})}]
    acquisitionHandlerProgressCallback $module [dict create state $state mode determinate current 1 total 1 message "Acquisition $state — $completed imported, $failed failed"]
    _acquisitionManagedUiProgress [dict create state $state mode determinate current 1 total 1 message "Acquisition $state — $completed imported, $failed failed"]
    if {[info exists ::GX::runAllPending] && $::GX::runAllPending} {
        set ::GX::runAllPending 0
        if {$success && $valid} {after 100 ::GX::startAnalysis}
    }
}
# No Dataset lock is held here: the owned request and recovery have ended.
# Yield between existing normal projection owners rather than making one long
# completion callback. Each step retains the reviewed Session identity guard.
proc ::GX::_acquisitionManagedPersistCurrentManifest {} {writeManifest [file join $::GX::currentSession metadata manifest.ini]}
proc ::GX::_acquisitionManagedUiRefresh {session token commands} {
    if {$::GX::currentSession eq {} || [file normalize $::GX::currentSession] ne $session || [interactiveDocumentSessionToken] ne $token || [acquisitionHandlerAuthorityBusy $session] || ![llength $commands]} return
    if {[catch {::GX::[lindex $commands 0]} reason]} {guiLog "Acquisition view update [lindex $commands 0]: [string range $reason 0 511]"}
    if {[llength $commands]>1} {after 1 [list ::GX::_acquisitionManagedUiRefresh $session $token [lrange $commands 1 end]]}
}
proc ::GX::acquisitionHandlerStartManaged {module {currentOnly 0}} {
    variable cfg
    variable currentSession
    variable ::GX::AcquisitionManaged::queueState
    if {$::GX::acquisitionHandlerAsyncActive} {error {An Acquisition request is already active}}
    set batch [expr {[info exists ::GX::genericCsvBatchEnabled] && $::GX::genericCsvBatchEnabled && [acquisitionHandlerModuleSupportsBatch $module]}]
    if {$currentOnly} {
        if {$currentSession eq {} || ![file isdirectory $currentSession]} {error {Create or open the intended Session before importing}}
        set session [file normalize $currentSession]
    } else {
        set cfg(session_mode) [expr {$batch?{analysis_only}:{measurement}}]
        set session [makeSession]
    }
    set plans {}
    if {$batch} {
        set rows [expr {$currentOnly ? [genericCsvBatchPendingEnabledRows] : [genericCsvBatchEnabledRows]}]
        if {![llength $rows]} {return $session}
        genericCsvBatchPreflightRows $rows $session
        foreach row $rows {
            set source [file normalize $::GX::genericCsvBatch($row,path)]
            set sources [expr {[info exists ::GX::genericCsvBatch($row,source_paths)] && [llength $::GX::genericCsvBatch($row,source_paths)] ? $::GX::genericCsvBatch($row,source_paths) : [list $source]}]
            lappend plans [dict create row $row source $source sources $sources dataset_id $::GX::genericCsvBatch($row,dataset_id) contract [genericCsvBatchResolvedContract $row] variables [acquisitionHandlerBatchVariableMap $row]]
        }
    } else {
        if {$cfg(input_csv) eq {} || ![file isfile $cfg(input_csv)]} {error {Select an acquisition source}}
        set inspection [acquisitionHandlerInspect $module $cfg(input_csv)]
        if {$::GX::sourceVarCount==0} {acquisitionHandlerSeedVariables $inspection}
        lappend plans [dict create row 0 source [file normalize $cfg(input_csv)] sources [list [file normalize $cfg(input_csv)]] dataset_id [acquisitionHandlerDefaultDatasetId $module] contract [acquisitionHandlerDefaultContract $module] variables [acquisitionHandlerVariableMap]]
    }
    set queueState [dict create module $module session $session session_token [interactiveDocumentSessionToken] pending $plans batch $batch completed 0 failed 0 results {}]
    set ::GX::acquisitionHandlerAsyncActive 1;set ::GX::acquisitionHandlerCancelFlag 0
    _acquisitionManagedUiBusy 1
    _acquisitionManagedGuiNext
    return $session
}
# Only GUI-facing wrappers opt into managed requests. Public Sync operations
# and existing cooperative handlers keep their accepted return/dispatch paths.
rename ::GX::acquisitionHandlerStartPlugin ::GX::acquisitionHandlerStartPlugin_before_managed_request
proc ::GX::acquisitionHandlerStartPlugin {module} {
    set hid [acquisitionHandlerLoadModule $module]
    if {[acquisitionHandlerHasCapability $hid managed_request]} {
        if {[catch {acquisitionHandlerStartManaged $module} reason]} {tk_messageBox -icon error -title {Acquisition} -message $reason}
        return
    }
    tailcall ::GX::acquisitionHandlerStartPlugin_before_managed_request $module
}
rename ::GX::genericCsvBatchImportIntoCurrentSession ::GX::genericCsvBatchImportIntoCurrentSession_before_managed_request
proc ::GX::genericCsvBatchImportIntoCurrentSession {} {
    if {[acquisitionHandlerCurrentModuleIsPlugin] && [acquisitionHandlerHasCapability [acquisitionHandlerLoadModule $::GX::cfg(acquisition_module)] managed_request]} {
        if {[catch {acquisitionHandlerStartManaged $::GX::cfg(acquisition_module) 1} reason]} {tk_messageBox -icon error -title {Import Datasets} -message $reason}
        return
    }
    tailcall ::GX::genericCsvBatchImportIntoCurrentSession_before_managed_request
}
