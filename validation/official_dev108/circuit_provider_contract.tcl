# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out nodeOut
set out [file normalize $out]
if {![string match */_private_dev108/circuit-provider* $out] || [file exists $out]} {error {Fresh private circuit-provider output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_circuit_provider_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
set session [::GX::createNewSession circuit_provider_contract]
set destination local
if {$nodeOut ne {}} {
    set f [open [file join $nodeOut descriptor.tcldict] r];try {set descriptor [read $f]} finally {close $f}
    ::GX::scientificExecutionNodeRegister dev108-loopback $descriptor
    set destination dev108-loopback
    set capability [::GX::scientificExecutionNodeInspect $destination]
    set f [open [file join $out remote_capabilities.tcldict] w];puts $f $capability;close $f
    set available 0
    foreach provider [dict get $capability providers] {if {[dict get $provider provider_id] eq {core.ngspice.circuit} && [dict get $provider available]} {set available 1}}
    if {!$available} {error {Actual node does not advertise the required circuit provider}}
}
proc receipt {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set id [dict get [::GX::native2DGeometryDiagramCreate viewer.development_workspace development_workspace electrical.basic] id]
proc edit {op request} {return [::GX::native2DGeometryDiagramEdit $::id [::GX::native2DGeometryDiagramRead $::id] $op $request]}
set v [dict get [edit place {kind voltage name V1 position {-80 0} attributes {waveform pulse}}] object_id]
check {[catch {::GX::scientificExecutionCircuitInspect $id} denied]} {Open/no-ground circuit admitted}
receipt open_circuit_rejected $denied
set r [dict get [edit place {kind resistor name R1 position {0 0}}] object_id]
set c [dict get [edit place {kind capacitor name C1 position {80 0}}] object_id]
set g [dict get [edit place {kind ground name G1 position {0 -100}}] object_id]
foreach {a ap b bp} [list $v p $r p $r n $c p $c n $g g $v n $g g] {edit wire [dict create start [list $a $ap] end [list $b $bp]]}
edit label [dict create endpoint [list $v p] text input]
edit label [dict create endpoint [list $c p] text output]
receipt inspection [::GX::scientificExecutionCircuitInspect $id]
set original [::GX::native2DGeometryDiagramRead $id]
edit properties [dict create id $r name {R1.bad}]
check {[catch {::GX::scientificExecutionCircuitInspect $id} denied]} {Unsafe SPICE name admitted}
receipt unsafe_name_rejected $denied
edit restore [dict create payload [dict get $original payload]]
set stale [::GX::scientificExecutionCircuitPrepare $id {analysis op} [dict create node_id $destination]]
edit properties [dict create id $r attributes {value 2000}]
check {[catch {::GX::scientificExecutionSubmit [dict get $stale preparation]} denied]} {Stale prepared source submitted}
receipt stale_rejected $denied
::GX::scientificExecutionDiscard [dict get $stale preparation]
edit restore [dict create payload [dict get $original payload]]
proc waitJob {job} {
    set deadline [expr {[clock seconds]+120}]
    while {[clock seconds]<$deadline} {
        set status [::GX::scientificExecutionStatus $job]
        if {[dict get $status state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} {return $status}
        after 100;update
    }
    error {Scientific circuit Job timed out}
}
set runs {}
foreach analysis {op tran ac dc} {
    puts "Submitting real $analysis";flush stdout
    set prepared [::GX::scientificExecutionCircuitPrepare $id [dict create analysis $analysis source V1] [dict create node_id $destination]]
    set submitted [::GX::scientificExecutionSubmit [dict get $prepared preparation]]
    set job [dict get $submitted job_id];set terminal [waitJob $job]
    receipt ${analysis}_status $terminal
    receipt ${analysis}_log [::GX::scientificExecutionLog $job]
    check {[dict get $terminal state] eq {COMPLETED}} "$analysis real circuit Job failed"
    set outputs [::GX::scientificExecutionOutputs $job];receipt ${analysis}_outputs $outputs
    set token {}
    foreach output [dict get $outputs outputs] {if {[dict get $output role] eq {waveform}} {set token [dict get $output token]}}
    check {$token ne {}} {Missing actual solver observation table}
    set records [::GX::scientificExecutionReadRecords $job $token 0 1048576]
    receipt ${analysis}_records $records
    dict set runs $analysis [dict create job $job token $token records $records]
}
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
set operations [::GX::NumericAPIv1::listOperations]
receipt numeric_operation_catalog $operations
set times {};set voltages {}
set records [dict get $runs tran records]
set columns [lmap column [dict get $records columns] {dict get $column id}]
set tx [lsearch -exact $columns time];set vy [lsearch -exact $columns v_output]
foreach row [dict get $records records] {lappend times [lindex $row $tx];lappend voltages [lindex $row $vy]}
proc scalar {value} {dict create kind scalar value $value}
proc vector {value} {dict create kind vector value $value}
proc numericBinary {operation left right} {dict get [::GX::NumericAPIv1::arrayBinary $operation $left $right] values}
set query {.0005 .001 .002 .003 .004}
set tau [numericBinary multiply [scalar 1000] [scalar 1e-6]]
set minus_t [numericBinary multiply [vector $query] [scalar -1]]
set exponent [numericBinary divide [vector $minus_t] [scalar $tau]]
set decay [dict get [::GX::NumericAPIv1::arrayUnary exp [vector $exponent]] values]
set expected [numericBinary subtract [scalar 1] [vector $decay]]
set observed [dict get [::GX::NumericAPIv1::interpolate $times $voltages $query {method linear extrapolation error}] yq]
set residual [numericBinary subtract [vector $observed] [vector $expected]]
set absolute [dict get [::GX::NumericAPIv1::arrayUnary abs [vector $residual]] values]
set maximum [dict get [::GX::NumericAPIv1::arrayReduce maximum [vector $absolute]] values]
set rms [dict get [::GX::NumericAPIv1::arrayReduce rms [vector $residual]] values]
set within [::GX::NumericAPIv1::arrayCompare less_than [scalar $maximum] [scalar .0001]]
receipt numeric_rc_validation [dict create api NUMERIC_API_v1 tau_seconds $tau query_seconds $query observed_V $observed expected_V $expected max_abs_error_V $maximum rms_error_V $rms tolerance_V .0001 comparison $within]
check {[dict get $within values] eq {1}} {Actual RC transient disagrees with public Numeric analytical reference}
proc imported {response} {set ::imported $response}
set owner [::GX::native2DGeometryDiagramRead $id]
set guard [dict create document_id $id generation [dict get $owner generation] revision [dict get $owner revision] sha256 [dict get $owner sha256]]
::GX::scientificExecutionImportTable [dict get $runs tran job] [dict get $runs tran token] core.scientific_execution [dict create dataset_id dev108_circuit_rc contract table.generic storage csv provenance "Actual bounded circuit provider; Job [dict get $runs tran job]; circuit [dict get $owner sha256]"] imported $guard
vwait ::imported
receipt dataset $::imported
check {[dict get $::imported ok]} {Canonical Dataset publication failed}
edit properties [dict create id $r attributes {value 1500}]
check {[catch {::GX::scientificExecutionImportTable [dict get $runs tran job] [dict get $runs tran token] core.scientific_execution [dict create dataset_id stale_result contract table.generic storage csv] imported $guard} denied]} {Stale output publication was admitted}
receipt stale_publication_rejected $denied
receipt result [dict create result PASS_SCOPE_ONLY analyses {op tran ac dc} solver ngspice source_document $id runs $runs scientific_reference public_NUMERIC_API_v1 destination $destination authored_viewer NOT_TESTED_BY_THIS_SCRIPT]
puts {PASS actual circuit provider four analyses, stale/unsafe/open rejection, public Numeric RC reference and canonical Dataset}
