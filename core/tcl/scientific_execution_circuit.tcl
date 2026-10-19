# SPDX-License-Identifier: GPL-3.0-or-later
# Circuit specialization of the existing provider/document/Job contract.
proc ::GX::scientificExecutionCircuitInspect {document {parameters {}}} {
    set owner [native2DGeometryDiagramRead $document]
    native2DGeometryDiagramValidate [dict get $owner payload]
    set parameters [_scientificExecutionParameters [dict get $::GX::ScientificExecution::providers core.ngspice.circuit parameters] $parameters]
    set payload [dict create payload [dict get $owner payload] parameters $parameters]
    set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_scientific_circuit_provider.py] --inspect]
    if {[catch {exec {*}$command << $payload} response] || [catch {dict get $response ok} ok] || !$ok} {
        if {![catch {dict get $response error} message]} {error $message}
        error {Circuit inspection failed; no scientific Job was submitted}
    }
    return [dict merge [dict get $response result] [dict create document [dict remove $owner payload] provider_id core.ngspice.circuit provider_version 1.0.0 analyses {op tran ac dc} parameters $parameters]]
}
proc ::GX::scientificExecutionCircuitPrepare {document parameters {options {}}} {
    foreach key [dict keys $options] {if {$key ni {node_id remote_session_id expected_generation expected_revision expected_sha256}} {error {Unknown circuit preparation option}}}
    set inspection [scientificExecutionCircuitInspect $document $parameters]
    set owner [dict get $inspection document]
    foreach {option field} {expected_generation generation expected_revision revision expected_sha256 sha256} {
        if {[dict exists $options $option] && [dict get $options $option] ne [dict get $owner $field]} {return -code error -errorcode {GX SCIENTIFIC STALE_SOURCE} {Circuit snapshot changed before preparation}}
    }
    # A resource belongs to the actual source Document; no second circuit store.
    set current [native2DGeometryDiagramRead $document]
    if {[dict remove $current payload] ne $owner} {error {Circuit changed during inspection}}
    set resource [managedResourceWrite $document [dict create format gxtxt.native2d.diagram.v1 origin canonical_circuit source_sha256 [dict get $inspection source_sha256]] [encoding convertto utf-8 [dict get $current payload]]]
    set prepareOptions [dict remove $options expected_generation expected_revision expected_sha256]
    dict set prepareOptions document_id $document
    dict set prepareOptions expected_revision [dict get $owner revision]
    set token [scientificExecutionPrepare core.ngspice.circuit $parameters [dict create circuit $resource] $prepareOptions]
    return [dict merge $inspection [dict create preparation $token source_resource $resource]]
}
proc ::GX::scientificExecutionCircuitSweepPrepare {document parameters items {options {}}} {
    # A bounded collection of existing preparations, never another queue/store.
    if {[llength $items]<1 || [llength $items]>16} {error {A circuit sweep requires1..16 explicit parameter cases}}
    foreach key [dict keys $options] {if {$key ni {node_id remote_session_id expected_generation expected_revision expected_sha256}} {error {Unknown circuit sweep preparation option}}}
    set owner [native2DGeometryDiagramRead $document]
    set guard [dict create document_id $document generation [dict get $owner generation] revision [dict get $owner revision] sha256 [dict get $owner sha256]]
    foreach {option field} {expected_generation generation expected_revision revision expected_sha256 sha256} {
        if {[dict exists $options $option] && [dict get $options $option] ne [dict get $owner $field]} {error {Circuit sweep source changed before preparation}}
    }
    set seen {};set normalized {}
    foreach item $items {
        if {[lsort [dict keys $item]] ne {id parameters} || ![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$} [dict get $item id]] || [dict get $item id] in $seen} {error {Circuit sweep cases require unique bounded IDs and typed parameter dictionaries}}
        lappend seen [dict get $item id]
        set inspection [scientificExecutionCircuitInspect $document [dict merge $parameters [dict get $item parameters]]]
        _scientificExecutionPublicationGuard $guard
        lappend normalized [dict create id [dict get $item id] parameters [dict get $inspection parameters] component_values [dict get $inspection component_values]]
    }
    set resource [managedResourceWrite $document [dict create format gxtxt.native2d.diagram.v1 origin canonical_circuit source_sha256 [dict get $owner sha256]] [encoding convertto utf-8 [dict get $owner payload]]]
    set prepareOptions [dict remove $options expected_generation expected_revision expected_sha256]
    dict set prepareOptions document_id $document;dict set prepareOptions expected_revision [dict get $owner revision]
    set preparedItems {}
    try {
        foreach item $normalized {
            _scientificExecutionPublicationGuard $guard
            set token [scientificExecutionPrepare core.ngspice.circuit [dict get $item parameters] [dict create circuit $resource] $prepareOptions]
            dict set item preparation $token
            lappend preparedItems $item
        }
    } on error {message errorOptions} {
        foreach item $preparedItems {catch {scientificExecutionDiscard [dict get $item preparation]}}
        return -options $errorOptions $message
    }
    return [dict create api_id SCIENTIFIC_EXECUTION_API_v1 operation circuit_sweep_prepare provider_id core.ngspice.circuit provider_version 1.0.0 source_guard $guard source_resource $resource items $preparedItems destination [datasetPublicationV2DictDefault $options node_id [scientificExecutionDestination]]]
}
proc ::GX::_scientificExecutionCircuitSubmitItem {guard item context} {
    _scientificExecutionPublicationGuard $guard
    set receipt [scientificExecutionSubmit [dict get $item preparation]]
    return [dict create item_id [dict get $item id] parameters [dict get $item parameters] component_values [dict get $item component_values] source_guard $guard submitted $receipt coordination $context]
}
proc ::GX::scientificExecutionCircuitSweepSubmit {preparation {options {}}} {
    if {[dict get $preparation api_id] ne {SCIENTIFIC_EXECUTION_API_v1} || [dict get $preparation operation] ne {circuit_sweep_prepare}} {error {Use an existing circuit sweep preparation receipt}}
    foreach key [dict keys $options] {if {$key ni {workers fail_fast progress_command run_id}} {error {Unknown circuit sweep submission option}}}
    set guard [dict get $preparation source_guard]
    _scientificExecutionPublicationGuard $guard
    set items [dict get $preparation items]
    if {[llength $items]<1 || [llength $items]>16} {error {Invalid bounded circuit preparation collection}}
    set coordination [parallelExecutionExecute $items [dict create kind callback command [list ::GX::_scientificExecutionCircuitSubmitItem $guard]] $options]
    # The coordinator serializes admissions. Actual scientific processes are
    # admitted/scheduled exclusively by the existing durable Job Supervisor.
    return [dict create api_id SCIENTIFIC_EXECUTION_API_v1 operation circuit_sweep_submit state ADMISSION_FINISHED source_guard $guard provider_id [dict get $preparation provider_id] provider_version [dict get $preparation provider_version] destination [dict get $preparation destination] coordination $coordination completion_policy {Admission success is not simulation completion; inspect every canonical child Job. Retain preparations for uncertain remote admission retry; discard only known submitted or explicitly abandoned items.} execution_authority SCRIPT_JOB_API_v1]
}
::GX::scientificExecutionRegister core.ngspice.circuit [dict create module_id core.scientific_execution version 1.0.0 worker core/python/gxtxt_scientific_circuit_provider.py tools {spice} parameters [dict create \
    analysis {type choice default op values {op tran ac dc}} \
    step_seconds {type number default 1e-5 min 1e-12 max 1} \
    stop_seconds {type number default .005 min 1e-12 max 100} \
    ac_grid {type choice default dec values {dec lin oct}} \
    points {type integer default 30 min 1 max 10000} \
    start_hz {type number default 1 min 1e-12 max 1e12} \
    stop_hz {type number default 100000 min 1e-12 max 1e12} \
    source {type string default {}} \
    dc_start {type number default 0 min -1e9 max 1e9} \
    dc_stop {type number default 5 min -1e9 max 1e9} \
    dc_step {type number default .1 min -1e9 max 1e9} \
    override_component {type string default {}} \
    override_value {type number default 0 min -1e12 max 1e12} \
    component_values {type string default {}}]]
