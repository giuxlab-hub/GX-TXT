# Dataset-local references to captured numerical facts; no statistical arithmetic.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::bindColumns {prototype columnVariables rowCount {rowStart 0}} {
    if {[_get $prototype schema {}] ne "gxtxt.statistical_result.v1"} {_error {Column binding requires a scalar prototype}}
    validate $prototype
    if {[llength [dict get $prototype parameters]]||[dict get $prototype model profile] ni [_tableProfiles]} {_error {Column binding requires a parameterless table-compatible profile}}
    if {![string is wideinteger -strict $rowCount]||$rowCount<1} {_error {Column binding requires a positive row count}}
    if {![string is wideinteger -strict $rowStart]||$rowStart<0} {_error {Column binding requires a nonnegative physical row start}}
    set facts [dict get $prototype request numerical]
    if {[string bytelength $prototype]>1048576||[dict size $facts]>128||![dict size $columnVariables]} {_error {Column binding exceeds its bounded definition or lacks columns}}
    dict for {key value} $facts {if {![string is double -strict $value]} {_error {Column binding requires scalar numerical facts}}}
    set columns {};set used {}
    foreach quantity [lsort [dict keys $columnVariables]] {
        set variable [dict get $columnVariables $quantity]
        if {![dict exists $facts $quantity]||![dict exists $prototype quantities $quantity]||[dict get $prototype quantities $quantity kind] ne "scalar"} {_error "Binding quantity '$quantity' must be a captured scalar fact"}
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $variable]||$variable in $used} {_error {Column binding requires unique canonical Variable IDs}}
        lappend used $variable;dict set columns $quantity $variable
    }
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.statistical_result.column_binding.v1 prototype $prototype column_variables $columns row_count $rowCount row_start $rowStart seal {}]
}
proc ::GX::StatisticsV1::_validateColumnBinding {result} {
    _keys $result {api_id api_version schema prototype column_variables row_count row_start seal} {column binding}
    set expected [bindColumns [dict get $result prototype] [dict get $result column_variables] [dict get $result row_count] [dict get $result row_start]]
    foreach key [dict keys $expected] {if {$key ne "seal"&&[dict get $result $key] ne [dict get $expected $key]} {_error "Column binding field '$key' bypasses CORE interpretation"}}
    set seal [dict get $result seal]
    if {$seal ne {}} {
        _keys $seal {payload_sha256 variable_schema} {column binding seal}
        if {![regexp {^[0-9a-f]{64}$} [dict get $seal payload_sha256]]} {_error {Column binding lacks a canonical payload SHA256}}
        set checked [_bindingSchema $result [dict get $seal variable_schema]]
        if {$checked ne [dict get $seal variable_schema]} {_error {Column binding schema seal is not canonical}}
    }
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::_bindingUnit {unit} {
    if {$unit in {{} unspecified}} {return {}}
    if {$unit in {count dimensionless}} {return 1}
    if {[llength $unit]==3&&[lindex $unit 0] eq "power"} {return "[lindex $unit 1]^[lindex $unit 2]"}
    return $unit
}
proc ::GX::StatisticsV1::_bindingSchema {binding schema} {
    set variables {};foreach v $schema {dict set variables [dict get $v variable_id] $v}
    set out {};set dimension {};set shape {}
    dict for {quantity id} [dict get $binding column_variables] {
        if {![dict exists $variables $id]} {_error "Statistical binding references missing Variable ID '$id'"}
        set v [dict get $variables $id];set item [dict create variable_id $id]
        foreach key {unit dtype rank shape dimension_ids} {dict set item $key [dict get $v $key]}
        dict set item shape [::GX::datasetPublicationV2Shape [dict get $item shape]]
        dict set item dimension_ids [::GX::datasetSchemaV3SplitIds [dict get $item dimension_ids]]
        if {[dict get $item rank]!=1||[llength [dict get $item shape]]!=1||[lindex [dict get $item shape] 0]<[dict get $binding row_start]+[dict get $binding row_count]||[llength [dict get $item dimension_ids]]!=1} {_error {Statistical binding requires scalar row columns covering its declared row span}}
        if {[dict get $item dtype] ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64}} {_error {Statistical binding requires real numerical columns}}
        if {$dimension ne {}&&($dimension ne [dict get $item dimension_ids]||$shape ne [dict get $item shape])} {_error {Statistical columns must share one row dimension and length}}
        set dimension [dict get $item dimension_ids];set shape [dict get $item shape]
        if {[_bindingUnit [dict get $item unit]] ne [_bindingUnit [dict get $binding prototype quantities $quantity unit]]} {_error "Statistical binding unit mismatch for '$id'"}
        lappend out $item
    }
    return $out
}
proc ::GX::StatisticsV1::sealPublicationBindings {metadata schema sha} {
    # Called inside the canonical publication transaction, after provider finalize.
    dict for {key value} $metadata {
        if {[lindex [split $key .] end] eq "statistical_results"} {
            dict for {name result} $value {
                if {[_get $result schema {}] ne "gxtxt.statistical_result.column_binding.v1"} {continue}
                validate $result
                dict set result seal [dict create payload_sha256 $sha variable_schema [_bindingSchema $result $schema]]
                dict set metadata $key $name $result
            }
        } elseif {[_get $value schema {}] eq "gxtxt.statistical_result.column_binding.v1"} {
            validate $value
            dict set value seal [dict create payload_sha256 $sha variable_schema [_bindingSchema $value $schema]]
            dict set metadata $key $value
        }
    }
    return $metadata
}
proc ::GX::StatisticsV1::bindingTable {session datasetId recordName start count} {
    if {![string is wideinteger -strict $start]||$start<0||![string is integer -strict $count]||$count<1||$count>8192} {_error {Binding reads require a nonnegative start and one to 8192 rows}}
    set previous $::GX::currentSession
    try {
        set ::GX::currentSession $session;::GX::loadDatasetRegistry $session
        set metadata [::GX::datasetMetadataRead $session $datasetId]
        set result [dict get $metadata analysis.statistical_results $recordName]
        if {[_get $result schema {}] ne "gxtxt.statistical_result.column_binding.v1"} {_error {Requested record is not a statistical column binding}}
        validate $result
        if {[dict get $result seal] eq {}} {_error {Statistical column binding has not been sealed by publication}}
        if {$start+$count>[dict get $result row_count]} {_error {Binding read exceeds its captured row count}}
        set facts [dict get $result prototype request numerical]
        if {[dict size $facts]*$count>1000000} {_error {Binding read exceeds the bounded numerical fact limit}}
        set payload [::GX::sessionInspectionDatasetPayload $datasetId $session]
        if {[dict get $payload sha256] ne [dict get $result seal payload_sha256]} {_error {Statistical column binding payload has changed}}
        if {[_bindingSchema $result [::GX::datasetVariableSchemaV3 $datasetId]] ne [dict get $result seal variable_schema]} {_error {Statistical column binding schema has changed}}
        set ids [dict values [dict get $result column_variables]]
        set physicalStart [expr {[dict get $result row_start]+$start}]
        set stream [::GX::tableStreamOpenDataset $session $datasetId $ids $count [dict create start $physicalStart count $count numeric_transport values]]
        try {set chunk [::GX::tableStreamNext $stream]} finally {::GX::tableStreamClose $stream}
        if {[dict get $chunk row_count]!=$count} {_error {Statistical binding read returned incomplete rows}}
        if {[dict get [::GX::sessionInspectionDatasetPayload $datasetId $session] sha256] ne [dict get $payload sha256]} {_error {Dataset changed during statistical binding read}}
        set columns {};dict for {key value} $facts {dict set columns $key [lrepeat $count $value]}
        dict for {quantity variable} [dict get $result column_variables] {dict set columns $quantity [dict get $chunk values $variable]}
        set rows {};for {set i $physicalStart} {$i<$physicalStart+$count} {incr i} {lappend rows row_$i}
        set request [dict get $result prototype request]
        set provenance [dict merge [dict get $request provenance] [dict create binding_dataset_id $datasetId binding_record $recordName binding_payload_sha256 [dict get $payload sha256] binding_row_start $physicalStart]]
        return [interpretTable [dict create model_id [dict get $request model_id] context [dict get $request context] provenance $provenance row_ids $rows numerical_columns $columns]]
    } finally {set ::GX::currentSession $previous;::GX::loadDatasetRegistry $previous}
}
proc ::GX::StatisticsV1::bindingReport {result} {
    validate $result
    set lines [list "Dataset-local statistical column binding: [dict get $result row_count] rows starting at physical row [dict get $result row_start]; [dict size [dict get $result column_variables]] fact columns. Values and row applicability require a bounded binding_table read. The prototype supplies definitions and common facts; its example values are not aggregate results."]
    dict for {quantity variable} [dict get $result column_variables] {
        set item [dict get $result prototype quantities $quantity]
        lappend lines "[dict get $item label] ([dict get $item unit]); column $variable: [_get $item definition {Captured numerical quantity; consult row status before use}]"
    }
    foreach assumption [_get [dict get $result prototype context] assumptions {}] {lappend lines $assumption}
    return [join $lines \n]
}
