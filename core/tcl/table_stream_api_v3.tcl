# GX-TXT Table Stream API v3
# SPDX-License-Identifier: GPL-3.0-or-later
# Table-shaped streaming facade over Canonical Dataset API v2.

namespace eval ::GX {
    variable tableStreamApiVersion 3
    variable tableStreamState
    variable tableStreamCounter 0
    array set tableStreamState {}
}

proc ::GX::tableStreamOption {options name default} {
    return [expr {[dict exists $options $name] ? [dict get $options $name] : $default}]
}

proc ::GX::tableStreamKnownDtypes {} {
    return {float16 float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool string}
}

proc ::GX::tableStreamDtypeCompatible {schemaDtype providerDtype} {
    if {$schemaDtype eq $providerDtype} { return 1 }
    if {$schemaDtype eq "string" && ($providerDtype eq "object" || [string match {*string*} $providerDtype] || [string match {*S[0-9]*} $providerDtype])} { return 1 }
    return 0
}

proc ::GX::tableStreamRequire {stream {allowFailed 0}} {
    variable tableStreamState
    if {![info exists tableStreamState($stream,status)]} { error "Unknown Table Stream handle: $stream" }
    set status $tableStreamState($stream,status)
    if {$status eq "closed"} { error "Table Stream handle is closed: $stream" }
    if {$status eq "failed" && !$allowFailed} { error "Table Stream handle is failed: $stream" }
}

proc ::GX::tableStreamOpenDataset {session datasetId variableIds chunkRows {options {}}} {
    variable currentSession
    variable tableStreamState
    variable tableStreamCounter
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "Table Stream session directory does not exist: $session" }
    if {![string is integer -strict $chunkRows] || $chunkRows < 1} { error "Table Stream chunk_rows must be an integer >= 1" }
    set start [tableStreamOption $options start 0]
    set count [tableStreamOption $options count -1]
    set requireDirect [expr {[tableStreamOption $options require_direct 0] ? 1 : 0}]
    set numericTransport [string tolower [string trim [tableStreamOption $options numeric_transport values]]]
    if {$numericTransport ni {values auto resource}} { error "Table Stream numeric_transport must be values, auto or resource" }
    if {![string is integer -strict $start] || $start < 0} { error "Table Stream start must be an integer >= 0" }
    if {![string is integer -strict $count] || $count < -1} { error "Table Stream count must be -1 or an integer >= 0" }
    set currentSession $session
    set access ""
    try {
        set access [datasetAccessOpen $session $datasetId]
        set metadata [datasetAccessMetadata $access]
        set capabilities [datasetAccessCapabilities $access]
        if {![dict get $capabilities row_range_read]} { error "Dataset provider does not support table row ranges" }
        set allVariables [dict create]
        set allIds {}
        foreach variable [dict get $metadata variables] {
            set variableId [dict get $variable variable_id]
            dict set allVariables $variableId $variable
            lappend allIds $variableId
        }
        if {![llength $variableIds]} { set variableIds $allIds }
        set selected {}; set seen {}
        foreach variableId $variableIds {
            if {$variableId in $seen} { error "Duplicate selected variable_id $variableId" }
            if {![dict exists $allVariables $variableId]} { error "Dataset $datasetId has no variable_id $variableId" }
            lappend seen $variableId
            set variable [dict get $allVariables $variableId]
            if {[dict get $variable dtype] ni [tableStreamKnownDtypes]} { error "Variable $variableId has an unsupported or inconsistent dtype '[dict get $variable dtype]'" }
            if {[dict get $variable rank] != 1} { error "Variable $variableId is not table-shaped; use Canonical Dataset API v2 for n-D access" }
            set dimensions [datasetSchemaV3SplitIds [dict get $variable dimension_ids]]
            if {[llength $dimensions] != 1} { error "Variable $variableId does not declare one table row dimension" }
            lappend selected $variable
        }
        if {![llength $selected]} { error "Table Stream requires at least one selected variable_id" }
        set rowDimension [lindex [datasetSchemaV3SplitIds [dict get [lindex $selected 0] dimension_ids]] 0]
        set knownCounts {}
        foreach variable $selected {
            set variableId [dict get $variable variable_id]
            set dimension [lindex [datasetSchemaV3SplitIds [dict get $variable dimension_ids]] 0]
            if {$dimension ne $rowDimension} { error "Selected variables have inconsistent row dimensions" }
            set shape [datasetSchemaV3SplitIds [dict get $variable shape]]
            if {[llength $shape] == 1 && [string is integer -strict [lindex $shape 0]]} { lappend knownCounts [lindex $shape 0] }
            if {[dict get $variable axis_kind] eq "uniform" && [string is integer -strict [dict get $variable axis_count]]} { lappend knownCounts [dict get $variable axis_count] }
        }
        set knownCounts [lsort -integer -unique $knownCounts]
        if {[llength $knownCounts] > 1} { error "Selected variables have inconsistent row counts" }
        set rowCount [dict get $metadata row_count]
        if {[llength $knownCounts]} {
            set schemaCount [lindex $knownCounts 0]
            if {[string is integer -strict $rowCount] && $rowCount >= 0 && $rowCount != $schemaCount} { error "Dataset row count contradicts selected variable shapes" }
            set rowCount $schemaCount
        }
        if {![string is integer -strict $rowCount] || $rowCount < 0} { set rowCount -1 }
        if {$rowCount >= 0} {
            if {$start > $rowCount} { error "Table Stream range starts outside the dataset" }
            if {$count >= 0 && $start+$count > $rowCount} { error "Table Stream range extends outside the dataset" }
        }
        if {$count < 0 && $rowCount >= 0} { set resolvedCount [expr {$rowCount-$start}] } else { set resolvedCount $count }
        set randomAccess [dict get $capabilities random_access]
        if {$requireDirect && !$randomAccess} { error "Dataset provider does not support direct row-range access" }
        set rangeMode [expr {$randomAccess ? "direct" : "sequential_fallback"}]
        set stream "table-stream#[incr tableStreamCounter]"
        set tableStreamState($stream,status) open
        set tableStreamState($stream,access) $access
        set tableStreamState($stream,session) $session
        set tableStreamState($stream,dataset_id) $datasetId
        set tableStreamState($stream,provider) [dict get $metadata storage_provider]
        set tableStreamState($stream,capabilities) $capabilities
        set tableStreamState($stream,variables) $selected
        set tableStreamState($stream,variable_ids) $seen
        set tableStreamState($stream,row_dimension) $rowDimension
        set tableStreamState($stream,row_count) $rowCount
        set tableStreamState($stream,start) $start
        set tableStreamState($stream,count) $resolvedCount
        set tableStreamState($stream,chunk_rows) $chunkRows
        set tableStreamState($stream,position) 0
        set tableStreamState($stream,eof) [expr {$resolvedCount == 0}]
        set tableStreamState($stream,range_mode) $rangeMode
        set tableStreamState($stream,numeric_transport) $numericTransport
        set tableStreamState($stream,chunks_read) 0
        set tableStreamState($stream,rows_returned) 0
        set tableStreamState($stream,max_chunk_rows) 0
        set tableStreamState($stream,max_chunk_elements) 0
        set tableStreamState($stream,implicit_values_synthesized) 0
        set tableStreamState($stream,binary_columns_returned) 0
        set tableStreamState($stream,binary_bytes_returned) 0
        set tableStreamState($stream,value_columns_returned) 0
        set tableStreamState($stream,resource_columns_returned) 0
        set tableStreamState($stream,resource_bytes_returned) 0
        set access ""
        return $stream
    } finally {
        if {$access ne ""} { catch {datasetAccessClose $access} }
    }
}

proc ::GX::tableStreamOpenSource {runtime sourceId variableIds chunkRows {options {}}} {
    if {[file isfile $runtime]} { set runtime [parseIni $runtime] }
    if {[catch {dict size $runtime}]} { error "Table Stream source runtime must be an INI path or dictionary" }
    set sessionKey runtime.session
    set datasetKey "analysis_source.$sourceId.dataset_id"
    if {![dict exists $runtime $sessionKey] || [string trim [dict get $runtime $sessionKey]] eq ""} { error "Runtime does not provide the session path" }
    if {![dict exists $runtime $datasetKey] || [string trim [dict get $runtime $datasetKey]] eq ""} { error "Runtime has no Analysis Source '$sourceId' Dataset ID" }
    return [tableStreamOpenDataset [dict get $runtime $sessionKey] [dict get $runtime $datasetKey] $variableIds $chunkRows $options]
}

proc ::GX::tableStreamMetadata {stream} {
    variable tableStreamState
    tableStreamRequire $stream
    return [dict create \
        api_version 3 \
        dataset_id $tableStreamState($stream,dataset_id) \
        row_dimension $tableStreamState($stream,row_dimension) \
        row_count $tableStreamState($stream,row_count) \
        selected_variable_ids $tableStreamState($stream,variable_ids) \
        variables $tableStreamState($stream,variables) \
        storage_provider $tableStreamState($stream,provider) \
        capabilities $tableStreamState($stream,capabilities) \
        range_start $tableStreamState($stream,start) \
        range_count $tableStreamState($stream,count) \
        range_mode $tableStreamState($stream,range_mode) \
        numeric_transport $tableStreamState($stream,numeric_transport) \
        chunk_rows $tableStreamState($stream,chunk_rows)]
}

proc ::GX::tableStreamEmptyChunk {stream} {
    variable tableStreamState
    set absolute [expr {$tableStreamState($stream,start)+$tableStreamState($stream,position)}]
    set values [dict create]; set columns {}
    foreach variable $tableStreamState($stream,variables) {
        set variableId [dict get $variable variable_id]
        dict set values $variableId {}
        lappend columns [dict merge $variable [dict create values {} count 0]]
    }
    return [dict create api_version 3 dataset_id $tableStreamState($stream,dataset_id) offset $absolute start $absolute row_count 0 nrows 0 selected_variable_ids $tableStreamState($stream,variable_ids) values $values columns $columns eof 1]
}

proc ::GX::tableStreamNext {stream} {
    variable tableStreamState
    tableStreamRequire $stream
    if {$tableStreamState($stream,eof)} { return [tableStreamEmptyChunk $stream] }
    set requested $tableStreamState($stream,chunk_rows)
    set rangeCount $tableStreamState($stream,count)
    if {$rangeCount >= 0} {
        set remaining [expr {$rangeCount-$tableStreamState($stream,position)}]
        if {$remaining <= 0} { set tableStreamState($stream,eof) 1; return [tableStreamEmptyChunk $stream] }
        if {$requested > $remaining} { set requested $remaining }
    }
    set absolute [expr {$tableStreamState($stream,start)+$tableStreamState($stream,position)}]
    if {[catch {
        if {$tableStreamState($stream,numeric_transport) eq "resource"} {
            set raw [datasetAccessReadRangeResource $tableStreamState($stream,access) $tableStreamState($stream,variable_ids) $absolute $requested]
        } elseif {$tableStreamState($stream,numeric_transport) eq "auto"} {
            set raw [datasetAccessReadRangeTransport $tableStreamState($stream,access) $tableStreamState($stream,variable_ids) $absolute $requested]
        } else {
            set raw [datasetAccessReadRange $tableStreamState($stream,access) $tableStreamState($stream,variable_ids) $absolute $requested]
        }
    } failure options]} {
        set tableStreamState($stream,status) failed
        return -options $options $failure
    }
    set actual -1; set values [dict create]; set columns {}; set implicitCount 0
    foreach variable $tableStreamState($stream,variables) {
        set variableId [dict get $variable variable_id]
        if {![dict exists $raw $variableId]} { set tableStreamState($stream,status) failed; error "Canonical provider omitted selected variable_id $variableId" }
        set item [dict get $raw $variableId]
        set itemCount [dict get $item count]
        if {$actual < 0} { set actual $itemCount } elseif {$itemCount != $actual} { set tableStreamState($stream,status) failed; error "Canonical provider returned inconsistent table column lengths" }
        if {![tableStreamDtypeCompatible [dict get $variable dtype] [dict get $item dtype]]} { set tableStreamState($stream,status) failed; error "Canonical provider dtype does not match Schema v3 for $variableId" }
        if {[dict exists $item binary_resource]} {
            set resource [dict get $item binary_resource]
            datasetBinaryResourceValidate $resource $itemCount
            dict set values $variableId $resource
            lappend columns [dict merge $variable [dict create binary_resource $resource transport managed_binary count $itemCount]]
            incr tableStreamState($stream,resource_columns_returned)
            incr tableStreamState($stream,resource_bytes_returned) [dict get $resource byte_count]
        } elseif {[dict exists $item binary_block]} {
            set block [dict get $item binary_block]
            datasetBinaryValidateBlock $block $itemCount
            dict set values $variableId $block
            lappend columns [dict merge $variable [dict create binary_block $block transport typed_binary count $itemCount]]
            incr tableStreamState($stream,binary_columns_returned)
            incr tableStreamState($stream,binary_bytes_returned) [dict get $block byte_count]
        } else {
            set itemValues [dict get $item values]
            dict set values $variableId $itemValues
            lappend columns [dict merge $variable [dict create values $itemValues transport values count $itemCount]]
            incr tableStreamState($stream,value_columns_returned)
        }
        if {[dict exists $item synthesized] && [dict get $item synthesized]} { incr implicitCount $itemCount }
    }
    if {$actual < 0} { set actual 0 }
    incr tableStreamState($stream,position) $actual
    incr tableStreamState($stream,chunks_read)
    incr tableStreamState($stream,rows_returned) $actual
    incr tableStreamState($stream,implicit_values_synthesized) $implicitCount
    if {$actual > $tableStreamState($stream,max_chunk_rows)} { set tableStreamState($stream,max_chunk_rows) $actual }
    set elements [expr {$actual*[llength $tableStreamState($stream,variable_ids)]}]
    if {$elements > $tableStreamState($stream,max_chunk_elements)} { set tableStreamState($stream,max_chunk_elements) $elements }
    if {$actual < $requested || ($rangeCount >= 0 && $tableStreamState($stream,position) >= $rangeCount)} { set tableStreamState($stream,eof) 1 }
    if {$tableStreamState($stream,row_count) >= 0 && $absolute+$actual >= $tableStreamState($stream,row_count)} { set tableStreamState($stream,eof) 1 }
    return [dict create api_version 3 dataset_id $tableStreamState($stream,dataset_id) offset $absolute start $absolute row_count $actual nrows $actual selected_variable_ids $tableStreamState($stream,variable_ids) values $values columns $columns eof $tableStreamState($stream,eof)]
}

proc ::GX::tableStreamDiagnostics {stream} {
    variable tableStreamState
    tableStreamRequire $stream
    set provider [datasetAccessDiagnostics $tableStreamState($stream,access)]
    return [dict create \
        api_version 3 \
        dataset_id $tableStreamState($stream,dataset_id) \
        storage_provider $tableStreamState($stream,provider) \
        range_mode $tableStreamState($stream,range_mode) \
        selected_variable_count [llength $tableStreamState($stream,variable_ids)] \
        chunks_read $tableStreamState($stream,chunks_read) \
        rows_returned $tableStreamState($stream,rows_returned) \
        max_chunk_rows $tableStreamState($stream,max_chunk_rows) \
        max_chunk_elements $tableStreamState($stream,max_chunk_elements) \
        implicit_values_synthesized $tableStreamState($stream,implicit_values_synthesized) \
        binary_columns_returned $tableStreamState($stream,binary_columns_returned) \
        binary_bytes_returned $tableStreamState($stream,binary_bytes_returned) \
        value_columns_returned $tableStreamState($stream,value_columns_returned) \
        resource_columns_returned $tableStreamState($stream,resource_columns_returned) \
        resource_bytes_returned $tableStreamState($stream,resource_bytes_returned) \
        provider $provider]
}

proc ::GX::tableStreamClose {stream} {
    variable tableStreamState
    if {![info exists tableStreamState($stream,status)]} { error "Unknown Table Stream handle: $stream" }
    if {$tableStreamState($stream,status) eq "closed"} { return $stream }
    if {[info exists tableStreamState($stream,access)] && $tableStreamState($stream,access) ne ""} {
        catch {datasetAccessClose $tableStreamState($stream,access)}
        set tableStreamState($stream,access) ""
    }
    set tableStreamState($stream,status) closed
    return $stream
}

proc ::GX::tableStreamReleaseResource {stream resourceId} {
    variable tableStreamState
    tableStreamRequire $stream
    return [datasetAccessReleaseResource $tableStreamState($stream,access) $resourceId]
}

# Runtime discovery is additive. Existing Table Stream v1/v2 and Analysis
# Source sections remain unchanged.
proc ::GX::tableStreamRuntimeAppend {path} {
    if {![file isfile $path]} { return $path }
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[table_stream_api\]"
    putKV $fd api_version 3
    putKV $fd identity {dataset_id;variable_id}
    putKV $fd table_shape {rank1_shared_dimension}
    putKV $fd canonical_dataset_api_version 2
    putKV $fd numeric_transport {typed_binary_auto_with_values_fallback}
    putKV $fd supported_numeric_transports {values;auto;resource}
    close $fd
    return $path
}

proc ::GX::writeStandardRuntimeConfig_before_dataset_metadata_runtime_v1 {moduleId} {
    set path [::GX::writeStandardRuntimeConfig_before_table_stream_v3 $moduleId]
    return [tableStreamRuntimeAppend $path]
}
