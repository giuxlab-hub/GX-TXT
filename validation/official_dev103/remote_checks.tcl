# Actual TLS client to an isolated localhost node using the public CORE owners.
lassign $argv root out descriptor phase
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out client $key]}
set argv0 __dev103_remote_client__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set checks {}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label";flush stdout}
proc save {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
if {$phase eq "initial"} {
    set ::GX::cfg(output_root) [file join $out client_sessions]
    set session [::GX::createNewSession remote_projection]
    ::GX::scientificExecutionNodeRegister localhost $descriptor
    save client_session $session
} else {
    set f [open [file join $out client_session.tcldict] r];set session [string trim [read $f]];close $f
    ::GX::openSessionPath $session
}
if {$phase ne "offline"} {
    set health [::GX::scientificExecutionNodeInspect localhost];save capabilities_$phase $health
    check {[dict get $health node_id] eq "localhost" && [dict get $health os] eq "Linux"} {Authenticated node reports its real Linux capabilities}
}
if {$phase eq "initial"} {
    set attached [::GX::datasetRemoteAttach $session localhost node-science];save attached $attached
    set handle [::GX::datasetAccessOpen $session remote_big]
    set page [::GX::datasetAccessReadRange $handle exact 999980 7]
    check {[dict get $page exact values] eq {9007199255740973 9007199255740974 9007199255740975 9007199255740976 9007199255740977 9007199255740978 9007199255740979}} {Bounded remote uint64 range preserves exact values above 2^53}
    save range $page;save transfer_metrics $::GX::ScientificExecution::remoteMetrics
    check {[dict get $::GX::ScientificExecution::remoteMetrics received_bytes]<8192} {Consultation transfers a bounded slice rather than the million-row source}
    ::GX::datasetAccessClose $handle
    set stream [::GX::tableStreamOpenDataset $session remote_big exact 3 {start 12 count 7}]
    set rows 0;while 1 {set page [::GX::tableStreamNext $stream];incr rows [dict get $page row_count];if {[dict get $page eof]} break}
    ::GX::tableStreamClose $stream
    check {$rows==7} {Existing Table Stream reads the remote provider in bounded chunks}
    set handle [::GX::datasetAccessOpen $session remote_matrix]
    set slab [::GX::datasetAccessReadHyperslab $handle matrix {1 1} {2 2}];save hyperslab $slab
    check {[dict get $slab values] eq {-9007199254740994 -9007199254740995 1 2}} {Remote multidimensional hyperslab preserves int64 values, order and shape}
    check {[catch {::GX::datasetAccessReadHyperslab $handle matrix {1 1} {100 100}}]} {Invalid remote hyperslab is rejected}
    ::GX::datasetAccessClose $handle
    set handle [::GX::datasetAccessOpen $session remote_typed]
    set typed [::GX::datasetAccessReadRange $handle {label flag reading} 0 4];save typed $typed
    check {[dict get $typed label values] eq {µV commas,a {} {two words}}} {Remote UTF-8 strings preserve commas, blanks and whitespace}
    check {[dict get $typed flag values] eq {1 0 1 0}} {Remote boolean transport retains exact typed values}
    check {[lindex [dict get $typed reading values] 0]==1.25 && [lindex [dict get $typed reading values] 1] eq {} && [string equal -nocase [lindex [dict get $typed reading values] 2] NaN]} {Remote floating transport distinguishes missing cells from explicit NaN}
    ::GX::datasetAccessClose $handle
    set document [::GX::interactiveDocumentCreate core.scientific_execution managed_netlist text 1 {RC input}]
    set resource [::GX::managedResourceWrite [dict get $document id] {format spice.netlist media_type text/plain} [encoding convertto utf-8 {GX-TXT managed RC transient
V1 input 0 PULSE(0 1 0 1n 1n 10m 20m)
R1 input output 1000
C1 output 0 1u IC=0
.end
}]]
    set localDocument [::GX::interactiveDocumentRead [dict get $document id]]
    set guarded [::GX::scientificExecutionPrepare core.ngspice.rc_transient {} [dict create netlist $resource] [dict create node_id localhost document_id [dict get $document id] expected_revision [dict get $localDocument revision]]]
    ::GX::interactiveDocumentUpdate [dict get $document id] {Changed local scientific recipe}
    check {[catch {::GX::scientificExecutionSubmit $guarded} reason] && [string match {*Workspace changed*} $reason]} {Remote admission rechecks the original local scientific Document revision}
    ::GX::scientificExecutionDiscard $guarded
    set stagedA [::GX::scientificExecutionStageResource localhost node-science $resource]
    set stagedB [::GX::scientificExecutionStageResource localhost node-science $resource]
    check {$stagedA eq $stagedB} {Repeated exact input staging reuses a verified managed resource}
    ::GX::scientificExecutionDestination localhost
    set prepared [::GX::scientificExecutionPrepare core.ngspice.rc_transient {} [dict create netlist $resource]]
    set job [::GX::scientificExecutionSubmit $prepared];set id [dict get $job job_id];save remote_job_id $id
    check {[::GX::scientificExecutionRemoteId $id]} {Public scientific submission routes transparently to the node-local Supervisor}
    check {[dict get [::GX::scientificExecutionSubmit $prepared] job_id] eq $id} {Repeated submission nonce returns the same durable scientific Job}
    set deadline [expr {[clock milliseconds]+90000}]
    while {[clock milliseconds]<$deadline} {set status [::GX::scientificExecutionStatus $id];if {[dict get $status state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} break;after 150}
    save solver_status $status
    check {[dict get $status state] eq "COMPLETED"} {Actual registered ngspice solver completes on the compute node}
    check {[dict get [::GX::scriptJobDescribe $id] backend] eq "remote"} {Generic Script Job API describes remote Jobs through the same public identity}
    check {[dict get [::GX::scriptJobWait $id] state] eq "COMPLETED"} {Generic Script Job wait observes the remote Supervisor without a local lease}
    save generic_inspection [::GX::scriptJobInspect $id]
    set outputs [::GX::scientificExecutionOutputs $id];save outputs $outputs
    set outputToken [dict get [lindex [dict get $outputs outputs] 0] token]
    set frozen [::GX::scientificExecutionFreezeResource $id $outputToken [dict get $document id]]
    check {[dict get $frozen size_bytes]>100 && [dict get $frozen sha256] ne {}} {Remote terminal output freezes into an explicitly selected local managed Document}
    save frozen_output $frozen
    set page [::GX::scientificExecutionReadOutput $id $outputToken 0 1048576]
    set maximum 0.;set count 0
    foreach line [lrange [split [string trim [encoding convertfrom utf-8 [binary decode base64 [dict get $page bytes_base64]]]] \n] 1 end] {lassign [split $line ,] t v;set maximum [expr {max($maximum,abs($v-(1.-exp(-$t/.001))))}];incr count}
    check {$count>100 && $maximum<.002} {Remote waveform agrees with the independent 1 ms RC analytic solution}
    save numerical_gold [dict create rows $count maximum_voltage_error $maximum]
    save logs [::GX::scientificExecutionLog $id]
    set publication [::GX::scientificExecutionImportResults $id $outputToken {dataset_id remote_rc_waveform}];save node_publication $publication
    check {[dict get $publication dataset_id] eq "remote_rc_waveform"} {Validated result is published by the server-side canonical Publication authority}
    ::GX::datasetRemoteAttach $session localhost node-science
    set imported [::GX::datasetRemoteImport $session remote_matrix explicit_local_matrix]
    set importedHandle [::GX::datasetAccessOpen $session explicit_local_matrix]
    check {[dict get [::GX::datasetAccessReadHyperslab $importedHandle matrix {1 1} {2 2}] values] eq {-9007199254740994 -9007199254740995 1 2}} {Explicit local import preserves canonical multidimensional exact integers}
    ::GX::datasetAccessClose $importedHandle
    set preview [::GX::datasetPreviewCacheGenerate remote_rc_waveform {}]
    check {[dict get $preview kind] eq "native2d" && [dict get $preview row_count]>100} {Authoritative node prepares a bounded remote native Preview through its existing managed Job}
    save remote_preview $preview
    set cached [::GX::datasetPreviewCacheRead remote_rc_waveform [dict get $preview key]]
    check {$cached ne {}} {Remote prepared Preview is reusable from the local disposable Session cache}
    ::GX::scientificExecutionDestination local
    set local [::GX::scientificExecutionPrepare core.ngspice.rc_transient {} [dict create netlist $resource] {node_id local}]
    set localId [dict get [::GX::scientificExecutionSubmit $local] job_id]
    check {![::GX::scientificExecutionRemoteId $localId] && [dict get [::GX::scriptJobWait $localId 60] state] eq "COMPLETED"} {Explicit local override preserves real local registered-solver execution}
    set slow [::GX::scientificExecutionPrepare core.verification.cpu {seconds 25} {} {node_id localhost}]
    set slowId [dict get [::GX::scientificExecutionSubmit $slow] job_id]
    after 800
    ::GX::scientificExecutionCancel $slowId
    set deadline [expr {[clock milliseconds]+30000}]
    while {[clock milliseconds]<$deadline} {set status [::GX::scientificExecutionStatus $slowId];if {[dict get $status state] in {CANCELLED FAILED INTERRUPTED}} break;after 100}
    save cancelled $status
    check {[dict get $status state] eq "CANCELLED"} {Remote cancellation uses node-local Supervisor process-tree cleanup}
    set reconnect [::GX::scientificExecutionPrepare core.verification.cpu {seconds 8 seed 103} {} {node_id localhost}]
    save reconnect_job [dict get [::GX::scientificExecutionSubmit $reconnect] job_id]
    save result_initial [dict create status PASS checks $checks session $session]
} elseif {$phase eq "offline"} {
    set f [open [file join $out remote_job_id.tcldict] r];set id [string trim [read $f]];close $f
    check {[catch {::GX::scientificExecutionStatus $id} message options] && [dict get $options -errorcode] eq {GX REMOTE UNAVAILABLE}} {Disconnection reports transport unavailable without inventing a scientific terminal state}
    check {[catch {::GX::datasetAccessOpen $session remote_big}]} {Disconnected remote Dataset refuses a read without a false local fallback}
    check {[::GX::datasetField remote_big id] eq "remote_big"} {Offline Dataset retains its canonical identity in the ordinary catalog}
    save result_offline [dict create status PASS checks $checks]
} elseif {$phase eq "invalidation"} {
    check {[catch {::GX::datasetAccessOpen $session remote_big} message options] && [dict get $options -errorcode] eq {GX REMOTE STALE_SOURCE}} {A genuine authoritative metadata revision invalidates the old remote handle}
    ::GX::datasetRemoteAttach $session localhost node-science
    set h [::GX::datasetAccessOpen $session remote_big]
    check {[lindex [dict get [::GX::datasetAccessReadRange $h exact 0 1] exact values] 0] eq "9007199254740993"} {Catalog refresh rebinds current revision without altering exact source values}
    ::GX::datasetAccessClose $h
    save result_invalidation [dict create status PASS checks $checks]
} else {
    set f [open [file join $out reconnect_job.tcldict] r];set id [string trim [read $f]];close $f
    set deadline [expr {[clock milliseconds]+30000}]
    while {[clock milliseconds]<$deadline} {set status [::GX::scientificExecutionReconnect $id];if {[dict get $status state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} break;after 100}
    check {[dict get $status state] eq "COMPLETED"} {Supervisor Job survives an agent restart and reconnects by its durable public identity}
    save reconnected $status
    ::GX::datasetRemoteAttach $session localhost node-science
    check {[::GX::datasetField remote_rc_waveform id] eq "remote_rc_waveform"} {Reconnected catalog discovers authoritative remote solver publication}
    set handle [::GX::datasetAccessOpen $session remote_big]
    check {[lindex [dict get [::GX::datasetAccessReadRange $handle exact 0 1] exact values] 0] eq "9007199254740993"} {Remote Dataset reopens after node-agent reconnection}
    ::GX::datasetAccessClose $handle
    save result_reconnect [dict create status PASS checks $checks]
}
