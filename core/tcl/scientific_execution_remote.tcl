# SPDX-License-Identifier: GPL-3.0-or-later
# Remote dispatch is a Configuration-backed reference, never another executor.
namespace eval ::GX::ScientificExecution {variable remoteMetrics {};variable remotePrepared {};variable remoteSerial 0}
proc ::GX::scientificExecutionNodesInit {} {
    foreach {id label default} {execution.nodes {Compute nodes} {} execution.destination {Execution destination} local} {
        if {![dict exists [configurationFields] $id]} {configurationRegister $id [dict create group Execution label $label type string default $default scope user]}
    }
}
proc ::GX::scientificExecutionNodeRegister {id descriptor} {
    scientificExecutionNodesInit
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id]} {error {Invalid compute node ID}}
    foreach field {endpoint ca_file client_cert client_key session_id} {if {![dict exists $descriptor $field] || [dict get $descriptor $field] eq {}} {error "Compute node requires '$field'"}}
    if {![regexp {^https://[^/@?#[:space:]]+(/[^?#[:space:]]*)?$} [dict get $descriptor endpoint]]} {error {Compute nodes require authenticated HTTPS}}
    if {![regexp {^[A-Za-z0-9_.-]+$} [dict get $descriptor session_id]]} {error {Invalid logical remote Session ID}}
    dict set descriptor node_id $id
    if {![dict exists $descriptor enabled]} {dict set descriptor enabled 1}
    set nodes [configurationGet execution.nodes];dict set nodes $id $descriptor
    configurationSet execution.nodes $nodes;configurationSave
    return $id
}
proc ::GX::scientificExecutionNodes {} {scientificExecutionNodesInit;return [configurationGet execution.nodes]}
proc ::GX::scientificExecutionNodeList {} {
    set result {}
    dict for {id node} [scientificExecutionNodes] {lappend result [dict create node_id $id endpoint [dict get $node endpoint] session_id [dict get $node session_id] enabled [dict get $node enabled]]}
    return $result
}
proc ::GX::scientificExecutionDestination {{destination {}}} {
    scientificExecutionNodesInit
    if {$destination ne {}} {
        if {$destination ni {local auto} && ![dict exists [scientificExecutionNodes] $destination]} {error {Unknown execution destination}}
        configurationSet execution.destination $destination;configurationSave
    }
    return [configurationGet execution.destination]
}
proc ::GX::_scientificExecutionRemoteRequest {node session operation args} {
    set nodes [scientificExecutionNodes]
    if {![dict exists $nodes $node] || ![dict get $nodes $node enabled]} {error {Compute node is unknown or disabled}}
    set request [dict create node [dict get $nodes $node] session_id $session operation $operation arguments $args]
    if {$operation eq "scientific.submit"} {dict set request nonce [lindex $args 1];dict set request arguments [list [lindex $args 0]]}
    if {$operation eq "resource.append"} {dict set request payload_base64 [lindex $args 2];dict set request arguments [lrange $args 0 1]}
    if {$operation eq "dataset.preview"} {dict set request artifact_directory [lindex $args 3];dict set request arguments [lrange $args 0 2]}
    return $request
}
proc ::GX::_scientificExecutionRemoteCommand {} {
    return [list [runtimeToolResolve python] -B [file join $::GX::scriptDir core python gxtxt_remote_transport.py]]
}
proc ::GX::scientificExecutionRemoteCall {node session operation args} {
    variable ::GX::ScientificExecution::remoteMetrics
    set request [_scientificExecutionRemoteRequest $node $session $operation {*}$args]
    set command [_scientificExecutionRemoteCommand]
    if {[catch {exec {*}$command << $request} response] || [catch {dict get $response ok} ok]} {return -code error -errorcode {GX REMOTE UNAVAILABLE} {Compute node transport is unavailable}}
    if {!$ok} {return -code error -errorcode [dict get $response error_code] [dict get $response error]}
    set remoteMetrics [dict get $response metrics]
    return [dict get $response result]
}
# The same authenticated transport, managed by the existing auxiliary request
# owner. Cancelling this client request never cancels the durable remote Job.
proc ::GX::scientificExecutionRemoteCallAsync {node session operation arguments callback} {
    set request [_scientificExecutionRemoteRequest $node $session $operation {*}$arguments]
    return [scriptJobAsync [_scientificExecutionRemoteCommand] $request \
        [list ::GX::_scientificExecutionRemoteAsyncReady $callback] \
        {timeout_ms 20000 max_bytes 67108864 ui_lifetime 1 label {Compute node request}}]
}
proc ::GX::_scientificExecutionRemoteAsyncReady {callback response} {
    if {[dict get $response ok] && [dict exists $response metrics]} {
        set ::GX::ScientificExecution::remoteMetrics [dict get $response metrics]
    }
    if {$callback ne {}} {uplevel #0 [list {*}$callback $response]}
}
proc ::GX::_scientificExecutionRemoteHostContracts {} {
    set parameters {}
    foreach {name type description} {
        node NodeID {Existing enabled Execution Configuration node ID; no implicit fallback.}
        session RemoteSessionID {Exact logical remote Session identity from the original receipt.}
        operation RemoteOperation {An operation already implemented by the authenticated compute-node protocol.}
        arguments ArgumentList {One inert Tcl list of operation arguments, not executable source or variadic parameters.}
        callback CommandPrefix {Prefix receiving the existing ok/result/metrics or ok/error response dictionary.}
    } {dict set parameters $name [dict create type $type description $description]}
    return [dict create scientificExecutionRemoteCallAsync [dict create \
        command ::GX::scientificExecutionRemoteCallAsync \
        arguments {node session operation arguments callback} parameters $parameters \
        result [dict create type AuxiliaryRequestID description {Existing Script Job client token, bounded to 20 seconds and 64 MiB. Node validation or startup errors raise before a token exists. Cancelling the client does not cancel the durable Job.}] \
        context {Trusted Tcl host only. Uses existing configured authenticated transport. No Script Bridge or C++ SDK grant is implied.}]]
}
proc ::GX::scientificExecutionNodeInspect {node} {
    set nodes [scientificExecutionNodes]
    if {![dict exists $nodes $node]} {error {Unknown compute node}}
    return [scientificExecutionRemoteCall $node [dict get $nodes $node session_id] capabilities]
}
proc ::GX::scientificExecutionRemoteId {id} {return [regexp {^remote/([A-Za-z][A-Za-z0-9_.-]*)/([A-Za-z0-9_.-]+)/([^/]+)$} $id]}
proc ::GX::_scientificRemoteRoute {id} {
    if {![regexp {^remote/([A-Za-z][A-Za-z0-9_.-]*)/([A-Za-z0-9_.-]+)/([^/]+)$} $id -> node session job]} {error {Invalid remote Job identity}}
    return [list $node $session $job]
}
proc ::GX::scientificExecutionRemoteJob {id operation args} {
    lassign [_scientificRemoteRoute $id] node session job
    set result [scientificExecutionRemoteCall $node $session scientific.$operation $job {*}$args]
    if {$operation in {status cancel}} {dict set result job_id $id;dict set result node_id $node;dict set result remote_session_id $session}
    return $result
}
proc ::GX::scientificExecutionRemoteJobRecord {id operation args} {
    lassign [_scientificRemoteRoute $id] node session job
    set result [scientificExecutionRemoteCall $node $session job.$operation $job {*}$args]
    if {$operation eq "describe"} {dict set result id $id;dict set result backend remote;dict set result node_id $node;dict set result remote_session_id $session}
    return $result
}
proc ::GX::scientificExecutionRemotePrepare {node provider parameters resources options} {
    variable ::GX::ScientificExecution::remotePrepared;variable ::GX::ScientificExecution::remoteSerial
    set nodes [scientificExecutionNodes];set descriptor [dict get $nodes $node]
    set session [datasetPublicationV2DictDefault $options remote_session_id [dict get $descriptor session_id]]
    set localDocument {}
    if {[dict exists $options document_id]} {
        set localDocument [dict remove [interactiveDocumentRead [dict get $options document_id]] payload]
        if {[dict exists $options expected_revision] && [dict get $options expected_revision] ne [dict get $localDocument revision]} {error {Scientific Workspace revision changed}}
    }
    set options [dict remove $options node_id remote_session_id backend document_id expected_revision]
    set staged {}
    dict for {alias reference} $resources {dict set staged $alias [scientificExecutionStageResource $node $session $reference]}
    set token [scientificExecutionRemoteCall $node $session scientific.prepare $provider $parameters $staged $options]
    set handle remote-prepare#[pid]-[incr remoteSerial]
    set nonce [format %s-%s-%s [installationIdentityCurrent] [pid] [clock clicks]]
    dict set remotePrepared $handle [dict create node $node session $session token $token nonce $nonce provider_id $provider resources $resources local_document $localDocument session_token [interactiveDocumentSessionToken]]
    return $handle
}
proc ::GX::scientificExecutionRemoteSubmit {token} {
    variable ::GX::ScientificExecution::remotePrepared
    if {![dict exists $remotePrepared $token]} {error {Unknown remote preparation}}
    set p [dict get $remotePrepared $token]
    if {[dict get $p session_token] ne [interactiveDocumentSessionToken]} {error {Remote preparation belongs to a previous Session lifetime}}
    if {[dict get $p local_document] ne {}} {
        set previous [dict get $p local_document];set current [interactiveDocumentRead [dict get $previous id]]
        if {[dict get $previous revision] ne [dict get $current revision] || [dict get $previous sha256] ne [dict get $current sha256]} {error {Scientific Workspace changed after preparation}}
    }
    dict for {alias reference} [dict get $p resources] {interactiveDocumentResourceInfo $reference}
    set result [scientificExecutionRemoteCall [dict get $p node] [dict get $p session] scientific.submit [dict get $p token] [dict get $p nonce]]
    dict set result job_id remote/[dict get $p node]/[dict get $p session]/[dict get $result job_id]
    dict set result backend remote;dict set result node_id [dict get $p node]
    # Retain the nonce receipt until explicit discard: a transport retry must
    # return the same durable supervisor Job, never repeat an admission.
    dict set remotePrepared $token receipt $result
    return $result
}
proc ::GX::scientificExecutionStageResource {node session reference} {
    interactiveDocumentResourceInfo $reference
    set size [dict get $reference size_bytes]
    if {$size>8388608} {error {Remote managed input exceeds 8 MiB}}
    set metadata [dict create format gxtxt.remote.staged_input.v1 source_sha256 [dict get $reference sha256] source_document [dict get $reference document_id] source_generation [dict get [interactiveDocumentRead [dict get $reference document_id]] generation] source_origin [sessionOriginRead $::GX::currentSession] source_installation [installationIdentityCurrent] staged_input 1]
    set existing [scientificExecutionRemoteCall $node $session resource.lookup $metadata [dict get $reference sha256] $size]
    if {$existing ne {}} {return $existing}
    set token [scientificExecutionRemoteCall $node $session resource.open $metadata [dict get $reference sha256] $size]
    try {
        for {set offset 0} {$offset<$size} {incr offset 1048576} {
            set bytes [interactiveDocumentResourceReadChunk $reference $offset [expr {min(1048576,$size-$offset)}]]
            scientificExecutionRemoteCall $node $session resource.append $token $offset [binary encode base64 -maxlen 0 $bytes]
        }
        return [scientificExecutionRemoteCall $node $session resource.finalize $token]
    } on error {message options} {
        catch {scientificExecutionRemoteCall $node $session resource.abort $token}
        return -options $options $message
    }
}
