# SPDX-License-Identifier: GPL-3.0-or-later
# A typed provider facade over the existing durable Script Job authority.
namespace eval ::GX::ScientificExecution {variable providers {};variable prepared {};variable serial 0}
proc ::GX::scientificExecutionApiInfo {} {
    return [dict create api_id SCIENTIFIC_EXECUTION_API_v1 api_version 1 authority SCRIPT_JOB_API_v1 backend local operations {discover describe prepare discard submit status log cancel outputs read_output read_records freeze_resource import_results reconnect} security_boundary cooperating_trusted_provider_not_OS_sandbox persistence existing_Job_journal]
}
proc ::GX::scientificExecutionRegister {id descriptor} {
    variable ::GX::ScientificExecution::providers
    if {![regexp {^[a-zA-Z][a-zA-Z0-9_.-]*$} $id]} {error {Invalid scientific provider identity}}
    foreach key {module_id version worker tools parameters} {if {![dict exists $descriptor $key]} {error "Provider requires $key"}}
    set relative [dict get $descriptor worker]
    if {[file pathtype $relative] ne {relative}||{..} in [file split $relative]} {error {Trusted worker must be framework-relative}}
    set worker [file normalize [file join $::GX::scriptDir $relative]]
    if {![string match "$::GX::scriptDir/*" $worker]||![file isfile $worker]||[file type $worker] eq {link}} {error {Trusted worker is unavailable}}
    if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+$} [dict get $descriptor version]]} {error {Invalid scientific provider version}}
    dict for {name field} [dict get $descriptor parameters] {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name]||![dict exists $field type]||[dict get $field type] ni {integer number boolean string choice}} {error {Invalid typed provider parameter}}
    }
    dict set providers $id $descriptor
    return $id
}
proc ::GX::scientificExecutionDiscover {} {
    variable ::GX::ScientificExecution::providers
    return [lsort [dict keys $providers]]
}
proc ::GX::scientificExecutionDescribe {provider} {
    variable ::GX::ScientificExecution::providers
    if {![dict exists $providers $provider]} {error {Unknown registered scientific provider}}
    set description [dict get $providers $provider]
    dict unset description worker
    if {[dict exists $description import_command]} {dict unset description import_command}
    dict set description provider_id $provider
    dict set description backend local
    return $description
}
proc ::GX::_scientificExecutionParameters {schema parameters} {
    dict for {name value} $parameters {if {![dict exists $schema $name]} {error "Unknown scientific parameter '$name'"}}
    set result {}
    dict for {name field} $schema {
        if {[dict exists $parameters $name]} {set value [dict get $parameters $name]} elseif {[dict exists $field default]} {set value [dict get $field default]} elseif {[dict exists $field required]&&[dict get $field required]} {error "Missing scientific parameter '$name'"} else continue
        set type [dict get $field type]
        switch $type {
            integer {if {![string is entier -strict $value]} {error "Parameter '$name' requires an integer"}}
            number {if {![string is double -strict $value]||[catch {expr {abs(double($value))<Inf}} finite]||!$finite} {error "Parameter '$name' requires a finite number"}}
            boolean {if {![string is boolean -strict $value]} {error "Parameter '$name' requires a boolean"};set value [expr {!!$value}]}
            choice {if {![dict exists $field values]||$value ni [dict get $field values]} {error "Parameter '$name' has an invalid choice"}}
            string {if {[string length $value]>8192||[string first \x00 $value]>=0} {error {String parameter exceeds bounds}}}
        }
        if {$type in {integer number}} {foreach {bound relation} {min < max >} {if {[dict exists $field $bound]&&[expr "$value $relation [dict get $field $bound]"]} {error "Parameter '$name' violates $bound"}}}
        dict set result $name $value
    }
    return $result
}
proc ::GX::scientificExecutionPrepare {provider parameters {resources {}} {options {}}} {
    variable ::GX::ScientificExecution::providers;variable ::GX::ScientificExecution::prepared;variable ::GX::ScientificExecution::serial
    scientificExecutionDescribe $provider
    set d [dict get $providers $provider]
    set session [_interactiveDocumentRequireSession]
    dict for {old entry} $prepared {if {[dict get $entry session_token] ne [interactiveDocumentSessionToken]} {dict unset prepared $old}}
    if {[dict size $prepared]>=16} {error {At most16 scientific preparations may be retained; submit or discard one}}
    foreach key [dict keys $options] {if {$key ni {document_id expected_revision}} {error "Unknown scientific execution option '$key'"}}
    set sourceIdentities [dict create session_origin [sessionOriginRead $session]];set inputs {};set total 0
    dict for {alias reference} $resources {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $alias]} {error {Invalid input resource alias}}
        interactiveDocumentResourceInfo $reference
        set size [dict get $reference size_bytes];incr total $size
        if {$total>8388608} {error {Prepared resource snapshot exceeds 8 MiB; use a bounded provider materializer}}
        set bytes {};for {set offset 0} {$offset<$size} {incr offset 1048576} {append bytes [interactiveDocumentResourceReadChunk $reference $offset [expr {min(1048576,$size-$offset)}]]}
        dict set inputs $alias [binary encode base64 -maxlen 0 $bytes]
        dict set sourceIdentities $alias [dict remove $reference metadata]
    }
    if {[dict exists $options document_id]} {
        set document [interactiveDocumentRead [dict get $options document_id]]
        if {[dict exists $options expected_revision]&&[dict get $options expected_revision] ne [dict get $document revision]} {error {Scientific Workspace revision changed}}
        dict set sourceIdentities workspace [dict remove $document payload]
    }
    set tools {};foreach tool [dict get $d tools] {dict set tools $tool [runtimeToolRequired $tool]}
    set worker [file normalize [file join $::GX::scriptDir [dict get $d worker]]]
    set runtimeFiles {}
    foreach relative [datasetPublicationV2DictDefault $d runtime_files {}] {
        set path [scriptModuleSafeRelative $::GX::scriptDir $relative]
        dict set runtimeFiles $relative [sha256File $path]
    }
    if {[dict size $runtimeFiles]>256} {error {Scientific provider runtime inventory exceeds256 files}}
    set adapter [file join $::GX::scriptDir core python gxtxt_scientific_execution.py]
    set request [dict create adapter_sha256 [sha256File $adapter] runtime_files $runtimeFiles provider_id $provider provider_version [dict get $d version] worker $worker worker_sha256 [sha256File $worker] schema [dict get $d parameters] parameters [_scientificExecutionParameters [dict get $d parameters] $parameters] inputs $inputs source_identities $sourceIdentities tools $tools]
    set token "scientific-prepare#[pid]-[incr serial]"
    dict set prepared $token [dict create session $session session_token [interactiveDocumentSessionToken] resources $resources options $options request $request]
    return $token
}
proc ::GX::scientificExecutionDiscard {token} {
    variable ::GX::ScientificExecution::prepared
    if {![dict exists $prepared $token]} {error {Unknown scientific preparation}}
    dict unset prepared $token
    return [dict create discarded 1]
}
proc ::GX::scientificExecutionSubmit {token} {
    variable ::GX::ScientificExecution::prepared
    if {![dict exists $prepared $token]} {error {Unknown or consumed scientific preparation}}
    set p [dict get $prepared $token]
    if {[dict get $p session_token] ne [interactiveDocumentSessionToken]} {error {Scientific preparation belongs to another Session lifetime}}
    dict for {alias reference} [dict get $p resources] {interactiveDocumentResourceInfo $reference}
    set request [dict get $p request]
    if {[dict exists $p options document_id]} {
        set current [interactiveDocumentRead [dict get $p options document_id]]
        if {[dict get $current sha256] ne [dict get $request source_identities workspace sha256]||[dict get $current revision] ne [dict get $request source_identities workspace revision]} {error {Scientific Workspace changed after preparation}}
    }
    if {[sha256File [dict get $request worker]] ne [dict get $request worker_sha256]} {error {Scientific provider changed after preparation}}
    dict for {relative expected} [dict get $request runtime_files] {if {[sha256File [scriptModuleSafeRelative $::GX::scriptDir $relative]] ne $expected} {error {Scientific native/runtime dependency changed after preparation}}}
    if {[sha256File [file join $::GX::scriptDir core python gxtxt_scientific_execution.py]] ne [dict get $request adapter_sha256]} {error {Scientific CORE adapter changed after preparation}}
    set source {from gxtxt_scientific_execution import run
import gxtxt
run(gxtxt.gxtxt_context()['parameters']['request'])
}
    set id gx-core-scientific-execution
    if {[catch {set registered [scriptRegistryRead session $id]}]} {
        scriptRegistrySave session $id {CORE scientific provider driver} $source [dict create language Python version 1.0.0 parameters [dict create request [dict create type string required 1]]] 
    } else {
        set f [open [dict get $registered source_path] r];try {set existing [read $f]} finally {close $f}
        if {$existing ne $source} {error {Reserved CORE scientific driver differs; preserve and inspect the registered source}}
    }
    set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $request]]
    set job [scriptJobSubmit session:$id [dict create request $encoded] [dict create session [dict get $p session]]]
    dict unset prepared $token
    return [dict create job_id [dict get $job id] state [dict get $job state] provider_id [dict get $request provider_id]]
}
proc ::GX::_scientificExecutionJob {id} {
    set job [scriptJobDescribe $id]
    if {[dict get $job session] ne [_interactiveDocumentRequireSession]||[dict get $job reference] ne {session:gx-core-scientific-execution}} {error {Scientific Job does not belong to the current Session}}
    set request [encoding convertfrom utf-8 [binary decode base64 [dict get $job parameters request]]]
    if {[dict exists $request source_identities session_origin]&&[dict get $request source_identities session_origin] ne [sessionOriginRead [_interactiveDocumentRequireSession]]} {error {Scientific Job belongs to a different Session origin}}
    dict set job scientific_request $request
    return $job
}
proc ::GX::scientificExecutionStatus {id} {
    set job [_scientificExecutionJob $id]
    set status [dict create job_id $id provider_id [dict get $job scientific_request provider_id] state [dict get $job state]]
    foreach key {created started finished error cancel cpu_seconds peak_rss_bytes peak_processes peak_threads peak_rss_bytes process_identities temporary_bytes resource_cleanup resource_id policy usage queue_reason pid pid_start} {if {[dict exists $job $key]} {dict set status $key [dict get $job $key]}}
    if {[dict exists $status resource_cleanup]} {
        set cleanup {};foreach entry [dict get $status resource_cleanup] {lappend cleanup [dict remove $entry path]}
        dict set status resource_cleanup $cleanup
    }
    dict set status source_identities [dict get $job scientific_request source_identities]
    return $status
}
proc ::GX::scientificExecutionReconnect {id} {scientificExecutionStatus $id}
proc ::GX::scientificExecutionCancel {id} {_scientificExecutionJob $id;scriptJobCancel $id;return [scientificExecutionStatus $id]}
proc ::GX::scientificExecutionLog {id {offset 0} {count 65536} {previousReceipt {}}} {
    _scientificExecutionJob $id
    if {$previousReceipt ne {}&&![regexp {^[0-9]+:[0-9]+:[0-9]+:[0-9]+$} $previousReceipt]} {error {Invalid prior log generation token}}
    set page [dict remove [scriptJobLogRead $id $offset $count] path]
    set change initial;set reset 0
    if {$previousReceipt ne {}} {
        if {![dict get $page available]&&[string match {*Log shrank*} [dict get $page diagnostic]]} {set page [dict remove [scriptJobLogRead $id 0 $count] path];set reset 1;set change truncated}
        if {[dict exists $page receipt]} {
            lassign [split $previousReceipt :] oldDev oldInode oldModified oldSize
            lassign [split [dict get $page receipt] :] dev inode modified size
            if {$dev ne $oldDev||$inode ne $oldInode} {set reset 1;set change rotated} elseif {$size<$oldSize} {set reset 1;set change truncated} elseif {$modified ne $oldModified&&$size<=$oldSize} {set reset 1;set change rewritten} elseif {$size>$oldSize} {set change append} else {set change unchanged}
            if {$reset&&[dict get $page offset]!=0} {set page [dict remove [scriptJobLogRead $id 0 $count] path]}
        }
    }
    dict set page job_id $id
    dict set page change $change
    dict set page cursor_reset $reset
    if {[dict exists $page receipt]} {dict set page generation [dict get $page receipt]}
    return $page
}
proc ::GX::_scientificExecutionOutput {id operation {token {}} {offset 0} {count 65536} {generation {}}} {
    set job [_scientificExecutionJob $id]
    set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_scientific_execution.py] [dict get $job output_dir] $id $operation $token $offset $count $generation]
    set rc [catch {exec {*}$command} response]
    if {[catch {dict get $response ok} ok]||!$ok} {if {![catch {dict get $response error} message]} {error $message};error $response}
    return [dict get $response result]
}
proc ::GX::scientificExecutionOutputs {id} {_scientificExecutionOutput $id list}
proc ::GX::scientificExecutionReadOutput {id token {offset 0} {count 65536} {generation {}}} {_scientificExecutionOutput $id read $token $offset $count $generation}
proc ::GX::scientificExecutionReadRecords {id token {offset 0} {count 65536} {generation {}}} {_scientificExecutionOutput $id read_records $token $offset $count $generation}
proc ::GX::scientificExecutionFreezeResource {id token document} {
    set job [_scientificExecutionJob $id]
    if {[dict get $job state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {error {Freeze a terminal Job output; live values remain provisional}}
    interactiveDocumentRead $document
    set output [_scientificExecutionOutput $id freeze $token 0 16777216]
    if {![dict exists $output sha256]||![dict get $output complete]} {error {Freeze requires a complete coherent bounded scientific output}}
    return [managedResourceWrite $document [dict create format [dict get $output format] origin scientific_job source_job_id $id source_output_token $token source_generation [dict get $output source_generation] source_sha256 [dict get $output sha256] scientific_authority 1] [binary decode base64 [dict get $output bytes_base64]]]
}
proc ::GX::scientificExecutionImportResults {id token request} {
    variable ::GX::ScientificExecution::providers
    set job [_scientificExecutionJob $id]
    if {[dict get $job state] ne {COMPLETED}} {error {Only a completed scientific Job may be imported}}
    set provider [dict get $job scientific_request provider_id]
    if {![dict exists $providers $provider import_command]} {error {This provider has no registered scientific result importer}}
    set output [_scientificExecutionOutput $id freeze $token 0 16777216]
    if {[dict get $output availability] ne {available}||![dict exists $output sha256]||![dict get $output complete]} {error {Import requires a complete coherent bounded result; use a provider streaming importer for larger results}}
    set bytes [binary decode base64 [dict get $output bytes_base64]]
    return [{*}[dict get $providers $provider import_command] $id $token $bytes $request]
}
proc ::GX::scientificExecutionRegisterBuiltins {} {
    scientificExecutionRegister core.ngspice.rc_transient [dict create module_id core.scientific_execution version 1.0.0 worker core/python/gxtxt_scientific_builtin_providers.py tools {spice} parameters [dict create step_seconds {type number default 0.00001 min 0.00000001 max 0.0001} stop_seconds {type number default 0.005 min 0.001 max 0.1}] import_command ::GX::_scientificRcImport]
    if {[info exists ::env(GXTXT_SCIENTIFIC_TEST_PROVIDERS)]&&$::env(GXTXT_SCIENTIFIC_TEST_PROVIDERS) eq {1}} {
        scientificExecutionRegister core.verification.cpu [dict create module_id core.scientific_execution version 1.0.0 worker core/python/gxtxt_scientific_builtin_providers.py tools {} parameters [dict create seed {type integer default 7 min 0 max 4294967295} rounds {type integer default 10000 min 1 max 1000000} seconds {type number default 1 min 0 max 30} fail {type boolean default 0} live {type boolean default 0}]]
    }
}
proc ::GX::_scientificRcImport {jobId outputToken bytes request} {
    if {[dict keys $request] ne {dataset_id}} {error {RC import requires only a new Dataset ID}}
    set text [encoding convertfrom utf-8 $bytes]
    set lines [split [string trim $text] \n]
    if {[lindex $lines 0] ne {time,voltage}} {error {Unexpected RC waveform schema}}
    set times {};set voltages {};set previous -Inf
    foreach line [lrange $lines 1 end] {
        if {[llength [split $line ,]]!=2} {error {Malformed RC record}}
        lassign [split $line ,] t v
        foreach number [list $t $v] {if {![string is double -strict $number]||[catch {expr {abs(double($number))<Inf}} finite]||!$finite} {error {Nonfinite RC waveform}}}
        if {$t<=$previous} {error {RC time must increase}};set previous $t
        lappend times $t;lappend voltages $v
    }
    if {$times eq {}} {error {Empty RC waveform}}
    set session [_interactiveDocumentRequireSession]
    set definition [dict create dataset_id [dict get $request dataset_id] contract table.generic storage csv provenance "Scientific Job $jobId; output $outputToken; registered ngspice RC parser 1.0.0" structured_metadata [dict create scientific_execution.job_id $jobId scientific_execution.output_token $outputToken scientific_execution.source_generation [dict get [scientificExecutionReadOutput $jobId $outputToken] source_generation]]]
    set plan [datasetPublicationV2Prepare $session core.scientific_execution $definition]
    set writer [datasetPublicationV2OpenWriter $plan]
    try {
        datasetPublicationV2DeclareDimension $writer rows 0 {extendible 1}
        datasetPublicationV2DeclareVariable $writer time {dtype float64 name Time unit s dimension_ids rows}
        datasetPublicationV2DeclareVariable $writer voltage {dtype float64 name Voltage unit V dimension_ids rows}
        datasetPublicationV2Append $writer rows [dict create time $times voltage $voltages]
        return [datasetPublicationV2Finalize $writer]
    } on error {message options} {catch {datasetPublicationV2Abort $writer};return -options $options $message}
}

::GX::scientificExecutionRegisterBuiltins
