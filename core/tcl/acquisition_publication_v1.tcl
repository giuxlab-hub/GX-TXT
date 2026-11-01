# SPDX-License-Identifier: GPL-3.0-or-later
# Narrow acquisition staging -> existing Publication v2 numeric writer adapter.
# Staged little-endian arrays are standard binary transport, never canonical
# Datasets. Only Publication chooses storage, validates schema and commits SHA.
proc ::GX::_acquisitionPreparedIds {value} {
    # Native typed arrays decode to Tcl lists; canonical Registry IDs use ';'.
    if {[llength $value]>1 && [string first {;} $value]<0 && [string first , $value]<0} {return $value}
    return [datasetSchemaV3SplitIds $value]
}
proc ::GX::acquisitionPreparedPublicationsPreflight {moduleId session outputDir declarations} {
    if {[llength $declarations]<1 || [llength $declarations]>64} {error {Acquisition must prepare 1..64 actual numeric Datasets}}
    set result {};set definitions {};set ids {}
    set declared [splitList [moduleField $moduleId output_datasets {}]]
    foreach item $declarations {
        if {[lsort [dict keys $item]] ni {{definition row_count variables} {definition dimensions row_count variables}}} {error {Prepared Acquisition requires definition, row_count, variables and optional explicit dimensions}}
        set definition [dict get $item definition]
        # Prepared arrays carry exact dtypes. Use the existing storage policy's
        # capability negotiation, including for small known-size outputs.
        dict set definition capabilities_required [lsort -unique [concat typed_numeric [datasetPublicationV2DictDefault $definition capabilities_required {}]]]
        set id [datasetPublicationV2ValidateId dataset [dict get $definition dataset_id]]
        if {$id in $ids} {error {Duplicate prepared Acquisition Dataset ID}}
        lappend ids $id
        if {[dict get $definition contract] ni $declared} {error {Prepared Acquisition output contract is not declared by the producer}}
        if {[dict exists $definition publication_module] && [dict get $definition publication_module] ne $moduleId} {error {Prepared Acquisition cannot change its producer identity}}
        set rows [dict get $item row_count]
        if {![string is wideinteger -strict $rows] || $rows<1} {error {Prepared Acquisition requires a positive exact row count}}
        set explicit [dict exists $item dimensions]
        set dimensions [expr {$explicit?[dict get $item dimensions]:[dict create row $rows]}]
        if {[catch {dict size $dimensions}] || [dict size $dimensions]<1 || [dict size $dimensions]>16} {error {Prepared Acquisition requires 1..16 dimensions}}
        dict for {dim size} $dimensions {
            datasetPublicationV2ValidateId dimension $dim
            if {![string is wideinteger -strict $size] || $size<1 || $size>536870912} {error {Prepared dimensions require positive bounded integer sizes}}
        }
        set variables [dict get $item variables]
        if {[llength $variables]<1 || [llength $variables]>128} {error {Prepared Acquisition requires 1..128 variables}}
        set prepared {};set variableIds {};set usedDimensions {};set actualRows 0;set totalBytes 0
        foreach variable $variables {
            if {[lsort [dict keys $variable]] ni {{path schema variable_id} {path schema sha256 variable_id}}} {error {Prepared Acquisition variable requires path, schema, variable_id and an optional integrity SHA}}
            set vid [datasetPublicationV2ValidateId variable [dict get $variable variable_id]]
            if {$vid in $variableIds} {error {Prepared Acquisition variable IDs must be unique}}
            lappend variableIds $vid
            set schema [dict get $variable schema]
            set dtype [datasetPublicationV2DictDefault $schema dtype {}]
            if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool}} {error {Prepared Acquisition requires a supported typed numeric dtype}}
            set width [datasetBinaryTransportWidth $dtype]
            if {$explicit} {
                set dimIds [_acquisitionPreparedIds [datasetPublicationV2DictDefault $schema dimension_ids {}]]
                if {[llength $dimIds]<1 || [llength $dimIds]>16 || [llength [lsort -unique $dimIds]]!=[llength $dimIds]} {error {Prepared Variable requires 1..16 unique dimension IDs}}
                set shape {}
                foreach dim $dimIds {
                    if {![dict exists $dimensions $dim]} {error {Prepared Variable references an undeclared dimension}}
                    lappend shape [dict get $dimensions $dim]
                }
            } else {set dimIds row;set shape [list $rows]}
            set count [datasetPublicationV2ElementCount $shape]
            set expected [expr {$count*$width}]
            if {$expected>536870912} {error {Prepared numeric variable exceeds the existing 512 MiB resource bound}}
            lassign [acquisitionHandlerSafeDatasetPath $session $outputDir [dict get $variable path]] path unused
            if {[file size $path]!=$expected} {error {Prepared Acquisition array byte length does not match its typed shape}}
            foreach {key expectedValue} [list variable_id $vid rank [llength $shape] dimension_ids $dimIds shape $shape] {
                if {[dict exists $schema $key]} {
                    set supplied [dict get $schema $key]
                    if {$key eq {shape}} {set supplied [datasetPublicationV2Shape $supplied]}
                    if {$key eq {dimension_ids}} {set supplied [_acquisitionPreparedIds $supplied]}
                    if {$supplied ne $expectedValue} {error "Prepared numeric schema contradicts '$key'"}
                }
                dict set schema $key $expectedValue
            }
            foreach key {dimension_ids coordinate_variable_ids component_ids} {
                if {[dict exists $schema $key]} {dict set schema $key [join [_acquisitionPreparedIds [dict get $schema $key]] {;}]}
            }
            if {[datasetPublicationV2DictDefault $schema order F] ne {F} || [datasetPublicationV2DictDefault $schema endian little] ne {little}} {error {Prepared numeric arrays require little-endian column-major values}}
            foreach dim $dimIds {if {$dim ni $usedDimensions} {lappend usedDimensions $dim}}
            set actualRows [expr {max($actualRows,[lindex $shape 0])}]
            incr totalBytes $expected
            if {[llength $shape]>1} {dict set definition capabilities_required [lsort -unique [concat multidimensional [dict get $definition capabilities_required]]]}
            set pin [datasetPublicationV2DictDefault $variable sha256 {}]
            if {$pin ne {} && (![regexp {^[0-9a-f]{64}$} $pin] || [sha256File $path] ne $pin)} {error {Prepared Acquisition array SHA differs from the sealed output}}
            lappend prepared [dict create variable_id $vid schema $schema path $path dtype $dtype width $width shape $shape count $count byte_count $expected sha256 $pin]
        }
        if {[lsort $usedDimensions] ne [lsort [dict keys $dimensions]] || $rows!=$actualRows} {error {Prepared dimensions/row summary do not match the actual Variables}}
        if {[dict get $definition contract] eq {spectrum.scientific}} {
            set qualified [_acquisitionPreparedSpectrumValidate $definition $prepared]
            set definition [dict get $qualified definition];set prepared [dict get $qualified variables]
        }
        dict set definition expected_rows $rows
        dict set definition estimated_numeric_bytes $totalBytes
        lappend definitions $definition
        lappend result [dict create definition $definition row_count $rows dimensions $dimensions variables $prepared]
    }
    datasetPublicationV2BatchPreflight $session $moduleId $definitions
    return $result
}
proc ::GX::_acquisitionPreparedConsumables {session plans callbacks} {
    set root [datasetPublicationV2DictDefault $callbacks prepared_consumable_root {}]
    if {$root eq {}} {return {}}
    set root [file normalize $root]
    set transactionRoot [file normalize [file join $session .acquisition-txn]]
    if {[file tail $root] ne {datasets} || [file dirname [file dirname $root]] ne $transactionRoot || ![regexp {^[A-Za-z0-9_.-]+-[0-9]+-[0-9]+$} [file tail [file dirname $root]]]} {error {Consumable buffers require CORE's owned Acquisition staging root}}
    set state {}
    foreach plan $plans {
        foreach variable [dict get $plan variables] {
            set path [file normalize [dict get $variable path]]
            if {[string first "$root/" "$path/"]!=0 || ![file isfile $path] || [file type $path] ne {file}} {error {Consumable prepared buffer escaped its admitted staging root}}
            if {[dict exists $state $path]} {dict incr state $path 1} else {dict set state $path 1}
        }
    }
    return $state
}
proc ::GX::_acquisitionPreparedConsumed {stateName path} {
    upvar 1 $stateName state
    if {$state eq {}} return
    set path [file normalize $path]
    if {![dict exists $state $path] || [dict get $state $path]<1} {error {Unknown or already consumed prepared buffer}}
    dict incr state $path -1
    if {[dict get $state $path]==0} {
        if {![file isfile $path] || [file type $path] ne {file}} {error {Consumable buffer changed before its final acknowledgement}}
        file delete -- $path
    }
}
proc ::GX::acquisitionPublishPreparedSerial {moduleId session plans sourceProvenance {callbacks {}}} {
    if {![datasetAuthorityActive $session]} {error {Prepared Acquisition publication requires the existing outer Dataset authority transaction}}
    set consumables [_acquisitionPreparedConsumables $session $plans $callbacks]
    set ids {}
    set channel 0
    set totalVariables 0;foreach plan $plans {incr totalVariables [llength [dict get $plan variables]]}
    set completedVariables 0
    set allocation [resourceManagementAllocate acquisition_publication [dict create kind directory session $session lifetime computation]]
    set groupWorkspace [dict get $allocation path]
    set hadScope [info exists ::env(GXTXT_BRIDGE_WORKSPACE)]
    if {$hadScope} {set previousScope $::env(GXTXT_BRIDGE_WORKSPACE)}
    set writer {}
    try {
    if {[llength [info commands ::GX::_acquisitionManagedResourceTrack]]} {_acquisitionManagedResourceTrack $allocation}
    foreach plan $plans {
        incr channel
        set progress [datasetPublicationV2DictDefault $callbacks progress_callback {}]
        set cancel [datasetPublicationV2DictDefault $callbacks cancel_callback {}]
        if {$cancel ne {} && [acquisitionHandlerInvokeCallback $cancel]} {error {Acquisition cancelled before numeric publication}}
        set definition [dict get $plan definition]
        acquisitionHandlerInvokeCallback $progress [dict create phase publication mode determinate current $completedVariables total $totalVariables prepared_channels [expr {$channel-1}] message "Publishing channel $channel / [llength $plans]"]
        set metadata [datasetPublicationV2DictDefault $definition structured_metadata {}]
        dict for {key value} $sourceProvenance {
            if {[dict exists $metadata $key] && [dict get $metadata $key] ne $value} {error "Conflicting pinned Library source field '$key'"}
            dict set metadata $key $value
        }
        dict set definition structured_metadata $metadata
        set publication [datasetPublicationV2Prepare $session $moduleId $definition]
        set workspace [file join $groupWorkspace [format channel-%04d $channel]]
        file mkdir $workspace
        try {
            # Reuse the already public managed binary lane. No numeric values
            # cross the Tcl/Base64 control channel and no HDF5 writer is cloned.
            set ::env(GXTXT_BRIDGE_WORKSPACE) $workspace
            set writer [datasetPublicationV2OpenWriter $publication]
            if {![datasetPublicationV2DictDefault [datasetPublicationV2WriterCapabilities $writer] managed_binary_write 0]} {error {Prepared numeric Acquisition requires a CORE managed-binary writer; choose HDF5}}
            dict for {dim size} [dict get $plan dimensions] {datasetPublicationV2DeclareDimension $writer $dim $size}
            foreach variable [dict get $plan variables] {
                if {$cancel ne {} && [acquisitionHandlerInvokeCallback $cancel]} {error {Acquisition cancelled during numeric publication}}
                datasetPublicationV2DeclareVariable $writer [dict get $variable variable_id] [dict get $variable schema]
            }
            set serial 0
            foreach variable [dict get $plan variables] {
                if {$cancel ne {} && [acquisitionHandlerInvokeCallback $cancel]} {error {Acquisition cancelled during numeric payload transfer}}
                set name [format %032x.bin [incr serial]]
                set path [file join $workspace $name]
                set pin [datasetPublicationV2DictDefault $variable sha256 {}]
                if {$pin ne {} && [sha256File [dict get $variable path]] ne $pin} {error {Prepared numeric array changed after admission}}
                file copy -- [dict get $variable path] $path
                set expected [dict get $variable byte_count]
                if {[file size $path]!=$expected} {error {Prepared numeric array changed during publication}}
                if {$pin ne {} && ([sha256File $path] ne $pin || [sha256File [dict get $variable path]] ne $pin)} {error {Prepared numeric array SHA changed during publication}}
                set shape [dict get $variable shape]
                set resource [dict create version 2 dtype [dict get $variable dtype] endian little order F shape [join $shape {;}] count [dict get $variable count] byte_count $expected resource_id $name resource_root $workspace]
                datasetPublicationV2WriteVariable $writer [dict get $variable variable_id] \
                    [dict create __gxtxt_binary_resource 1 shape $shape resource $resource] $shape
                _acquisitionPreparedConsumed consumables [dict get $variable path]
                incr completedVariables
                acquisitionHandlerInvokeCallback $progress [dict create phase publication mode determinate current $completedVariables total $totalVariables message "Publishing channel $channel / [llength $plans]: [dict get $variable variable_id]"]
                file delete -- $path
            }
            acquisitionHandlerInvokeCallback $progress [dict create phase finalization mode indeterminate message "Validating and finalizing channel $channel / [llength $plans]"]
            if {$cancel ne {} && [acquisitionHandlerInvokeCallback $cancel]} {error {Acquisition cancelled before finalization}}
            set result [datasetPublicationV2Finalize $writer];set writer {}
            lappend ids [dict get $result dataset_id]
            acquisitionHandlerInvokeCallback $progress [dict create phase publication mode determinate current $completedVariables total $totalVariables prepared_channels $channel message "Validated channel $channel / [llength $plans]; Group commit pending"]
        } finally {
            if {$writer ne {}} {catch {datasetPublicationV2Abort $writer};set writer {}}
        }
    }
    } finally {
        if {$hadScope} {set ::env(GXTXT_BRIDGE_WORKSPACE) $previousScope} else {unset -nocomplain ::env(GXTXT_BRIDGE_WORKSPACE)}
        resourceManagementRelease [dict get $allocation id]
        resourceManagementCleanup [list [dict get $allocation id]]
    }
    return $ids
}
proc ::GX::acquisitionHandlerDispatchApiInfo {} {
    set nativeContracts [dict create \
        source_info [dict create arguments {source_index:uint32} result {request-scoped immutable source descriptor}] \
        source_read [dict create arguments {source_index:uint32 offset:uint64 count:uint32:1..65536} result {bounded raw slice bytes_base64 with exact offset/count/EOF}] \
        cancelled [dict create arguments {} result {live request cancellation state}] \
        progress [dict create arguments {phase message current?:uint64 total?:uint64} result {owned progress acknowledgement}] \
        prepare_output [dict create arguments {definition (row_count|dimensions:{id:positive-size}) variables:{variable_id,schema}} result {opaque output and typed variable byte counts; dimensions form preserves explicit rank/shape/coordinate IDs}] \
        output_write [dict create arguments {output_id variable_id offset byte_count chunk_sha256?} result {bounded sequential write authorization; bytes remain in trusted worker}] \
        output_finish [dict create arguments {output_id variables:{variable_id,byte_count,sha256}} result {provisional output reference; normal actor closure and CORE SHA checks required}] \
        helper_call [dict create arguments {helper_id args} result {explicitly admitted managed helper typed result; unavailable capability refuses}] \
        scientific_spectrum_parse [dict create arguments {source_index:uint32 format:csv|jcamp options:documented-text-fields} result {request-local parse_token row_count source_index source_sha256 parser_sha256 fields metadata provenance; existing source phase budget applies}] \
        scientific_spectrum_read [dict create arguments {parse_token offset:uint64 count:uint32:1..2048} result {offset row_count total_rows eof x y; bounded source-data vectors only}]]
    return [dict create api_id ACQUISITION_HANDLER_PLUGIN_API_v1 api_version 1 \
        source_dispatch_options {source_provenance destination_namespace} prepared_publication_api 1 dataset_group_api 1 \
        prepared_schema gxtxt.acquisition_prepared_numeric.v1 publication_owner DATASET_PUBLICATION_API_v2 \
        native_protocol gxtxt.native_acquisition_request.v1 native_protocol_version 1 \
        native_operation_contracts $nativeContracts operations [dict keys $nativeContracts] \
        native_runtime_available [expr {[llength [info commands ::GX::acquisitionHandlerNativeInvoke]]>0}] \
        native_context {CORE-admitted module/profile/request/phase capability; catalog presence grants no execution} \
        native_helper_runtime_available [expr {[llength [info commands ::GX::acquisitionHandlerNativeHelperAvailable]]>0 && [acquisitionHandlerNativeHelperAvailable]}] native_prepared_sha256 1 native_replacement_available 0 \
        native_scientific_source_limits {source_bytes 33554432 samples_per_request 1000000 parses_per_request 4 page_rows 2048 metadata_bytes 49152} \
        native_limits {slice_bytes 65536 control_frame_bytes 262144 datasets 64 variables_per_dataset 128 variable_bytes 536870912 rank 16 dimensions 16}]
}

# Selected normal strategy: measurements found no reliable end-to-end benefit
# from more provider processes; the additive API remains available to callers.
proc ::GX::acquisitionPublishPrepared {moduleId session plans sourceProvenance {callbacks {}}} {
    return [acquisitionPublishPreparedSerial $moduleId $session $plans $sourceProvenance $callbacks]
}
source [file join [file dirname [info script]] acquisition_spectrum_validation_v1.tcl]
