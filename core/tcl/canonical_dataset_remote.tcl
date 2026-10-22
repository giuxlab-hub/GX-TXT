# SPDX-License-Identifier: GPL-3.0-or-later
# Remote location is an adapter on the ordinary canonical registry and handles.
namespace eval ::GX {variable datasetRemoteHandles {};variable datasetRemoteSerial 0}
proc ::GX::datasetRemoteSessions {node} {
    set descriptor [dict get [scientificExecutionNodes] $node]
    return [scientificExecutionRemoteCall $node [dict get $descriptor session_id] sessions]
}
proc ::GX::datasetRemoteAttach {session node remoteSession} {
    set entries [scientificExecutionRemoteCall $node $remoteSession dataset.catalog]
    loadDatasetRegistry $session
    foreach item $entries {
        set id [dict get $item dataset_id]
        if {[datasetField $id id {}] ne {} && ([datasetField $id remote_node_id {}] ne $node || [datasetField $id remote_session_id {}] ne $remoteSession)} {error "Dataset identity '$id' already belongs to another authority; use a distinct Session projection"}
    }
    datasetAuthorityTransaction $session ::GX::_datasetRemoteAttachCommit $session $node $remoteSession $entries
    return [dict create node_id $node remote_session_id $remoteSession dataset_ids [lmap item $entries {dict get $item dataset_id}]]
}
proc ::GX::_datasetRemoteAttachCommit {session node remoteSession entries} {
    foreach item $entries {
        set id [dict get $item dataset_id];set fields [dict get $item fields]
        dict set fields remote_storage_provider [datasetPublicationV2DictDefault $fields storage_provider {}]
        dict set fields storage_provider remote;dict set fields path {}
        dict set fields remote_node_id $node;dict set fields remote_session_id $remoteSession
        dict set fields remote_revision [dict get $item revision]
        dict set fields remote_metadata [dict get $item metadata]
        dict set fields remote_metadata_values [dict get $item metadata_values]
        dict set fields remote_coordinate_context [dict get $item coordinate_context]
        datasetRegister $id $fields
    }
    saveDatasetRegistry $session
}
proc ::GX::datasetRemoteVerify {id} {
    if {[datasetField $id storage_provider {}] ne "remote"} {error {Dataset does not have a remote locator}}
    set record {};foreach field {remote_node_id remote_session_id remote_revision canonical_sha256} {dict set record $field [datasetField $id $field]}
    return [_datasetRemoteVerifyRecord $id $record]
}
proc ::GX::_datasetRemoteVerifyRecord {id record} {
    # The Session Inspection owner can resolve an explicitly named Session
    # without replacing the active GUI's canonical registry projection.
    scientificExecutionRemoteCall [dict get $record remote_node_id] [dict get $record remote_session_id] dataset.metadata $id [dict get $record remote_revision]
    return [dict create node_id [dict get $record remote_node_id] remote_session_id [dict get $record remote_session_id] dataset_id $id revision [dict get $record remote_revision] sha256 [dict get $record canonical_sha256]]
}
proc ::GX::datasetRemoteImport {session id newId} {
    loadDatasetRegistry $session
    set origin [datasetRemoteVerify $id]
    set handle [datasetAccessOpen $session $id];set writer {}
    try {
        set metadata [datasetAccessMetadata $handle]
        set plan [datasetPublicationV2Prepare $session core.scientific_execution [dict create dataset_id $newId contract [datasetField $id contract [datasetField $id kind]] storage hdf5 structured_metadata [dict create remote.source $origin]]]
        set writer [datasetPublicationV2OpenWriter $plan];set dimensions {}
        foreach variable [dict get $metadata variables] {
            foreach dim [datasetSchemaV3SplitIds [dict get $variable dimension_ids]] size [datasetSchemaV3SplitIds [dict get $variable shape]] {
                if {![dict exists $dimensions $dim]} {datasetPublicationV2DeclareDimension $writer $dim $size;dict set dimensions $dim $size} elseif {[dict get $dimensions $dim]!=$size} {error {Inconsistent remote dimension identity}}
            }
            datasetPublicationV2DeclareVariable $writer [dict get $variable variable_id] [datasetStorageVariableSpec $variable]
        }
        foreach variable [dict get $metadata variables] {
            set vid [dict get $variable variable_id];set shape [datasetSchemaV3SplitIds [dict get $variable shape]]
            set tail 1;foreach size [lrange $shape 1 end] {set tail [expr {$tail*$size}]}
            if {$tail>65536} {error {Explicit import requires a bounded first-dimension slice; use smaller hyperslabs for this shape}}
            set chunk [expr {max(1,65536/max(1,$tail))}]
            for {set start 0} {$start<[lindex $shape 0]} {incr start $chunk} {
                set count [expr {min($chunk,[lindex $shape 0]-$start)}]
                if {[llength $shape]==1} {set item [dict get [datasetAccessReadRange $handle [list $vid] $start $count] $vid];datasetPublicationV2WriteRange $writer $vid $start [dict get $item values]} else {
                    set starts [lrepeat [llength $shape] 0];lset starts 0 $start;set counts $shape;lset counts 0 $count
                    set item [datasetAccessReadHyperslab $handle $vid $starts $counts]
                    datasetPublicationV2WriteHyperslab $writer $vid $starts $counts [dict get $item values]
                }
            }
        }
        datasetRemoteVerify $id
        set result [datasetPublicationV2Finalize $writer];set writer {};return $result
    } finally {datasetAccessClose $handle;if {$writer ne {}} {datasetPublicationV2Abort $writer}}
}
proc ::GX::datasetRemoteAccessOpen {session id {descriptor {}}} {
    variable datasetAccessCounter;variable datasetAccessHandle;variable datasetRemoteHandles;variable datasetRemoteSerial
    set session [file normalize $session]
    if {$descriptor eq {}} {set descriptor [_datasetAccessDescriptor $session $id]}
    if {[dict get $descriptor session] ne $session || [dict get $descriptor dataset_id] ne $id || [dict get $descriptor provider] ne {remote}} {
        error {Remote Dataset descriptor does not match the requested Session and Dataset}
    }
    set record [dict get $descriptor record]
    set node [dict get $record remote_node_id];set remote [dict get $record remote_session_id];set revision [dict get $record remote_revision]
    set metadata [scientificExecutionRemoteCall $node $remote dataset.metadata $id $revision]
    dict set metadata source_storage_provider [dict get $metadata storage_provider]
    dict set metadata storage_provider remote
    foreach {key value} {read_full 0 typed_binary_read 1 managed_binary_read 0} {dict set metadata capabilities $key $value}
    set providerToken remote-dataset#[incr datasetRemoteSerial]
    dict set datasetRemoteHandles $providerToken [dict create node $node session $remote dataset_id $id revision $revision metadata $metadata]
    set handle dataset#[incr datasetAccessCounter]
    foreach {key value} [list dataset_id $id session $session provider remote provider_token $providerToken metadata $metadata descriptor $descriptor] {set datasetAccessHandle($handle,$key) $value}
    return $handle
}
proc ::GX::datasetRemoteProvider {operation token args} {
    variable datasetRemoteHandles
    if {![dict exists $datasetRemoteHandles $token]} {error {Remote canonical handle has closed}}
    set record [dict get $datasetRemoteHandles $token]
    switch -- $operation {
        metadata {return [dict get $record metadata]}
        close {dict unset datasetRemoteHandles $token;return}
        read_range - read_range_binary {set method dataset.range}
        read_hyperslab - read_hyperslab_binary {set method dataset.hyperslab}
        default {error "Unsupported remote canonical operation '$operation'"}
    }
    set result [scientificExecutionRemoteCall [dict get $record node] [dict get $record session] $method [dict get $record dataset_id] [dict get $record revision] {*}$args]
    if {$method eq "dataset.hyperslab"} {return [dict get $result [lindex $args 0]]}
    return $result
}
::GX::datasetStorageProviderRegister remote ::GX::datasetRemoteProvider {read_full 0 read_selected_variables 1 row_range_read 1 random_access 1 chunk_read 1 hyperslab_read 1 multidimensional 1 groups 1 implicit_axis 1 typed_binary_read 1 managed_binary_read 0}
