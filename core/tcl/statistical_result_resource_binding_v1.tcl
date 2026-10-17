# Captured numerical columns in canonical Document resources; no estimation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::fromProviderColumns {document operation context provenance transported path} {
    set values [dict get $transported values];set raw [dict get $values sample];set capture [dict get $values capture]
    _keys $capture {fields shapes row_count} {provider column capture}
    set fields [dict get $capture fields];set shapes [dict get $capture shapes];set rows [dict get $capture row_count]
    if {![string is wideinteger -strict $rows]||$rows<0||[llength $fields]!=[llength $shapes]||[llength $fields]>128} {_error {Invalid provider column dimensions}}
    set selector {};if {$operation eq "linear_regression"&&[dict exists $raw has_intercept]} {dict set selector has_intercept [dict get $raw has_intercept]}
    set model [numericModel $operation $selector]
    set prototype [fromNumeric [dict get $model id] $operation $raw $context {} $provenance]
    set out [dict create values $raw types {} captured_statistics $prototype transport [dict get $transported transport]]
    dict for {field type} [dict get $transported types] {
        if {[string match sample.* $field]} {dict set out types [string range $field 7 end] $type}
    }
    if {![llength $fields]} {if {$rows!=0} {_error {Empty column capture has a nonzero row count}};return $out}
    if {$rows<2||[llength [lsort -unique $fields]]!=[llength $fields]} {_error {Invalid provider captured vector identities}}
    set map [numericFieldMap $operation];set binding {};set schema {};set originalShapes {};set index 0
    foreach field $fields {
        if {![dict exists $map $field]} {_error {Provider captured an unregistered fact field}}
        set quantity [dict get $map $field]
        if {[dict exists $binding $quantity]} {_error {Two provider columns claim the same statistical identity}}
        set shape [lindex $shapes $index];incr index
        if {[llength $shape]!=2} {_error {Provider column requires its actual vector shape}}
        lassign $shape n m
        if {![string is wideinteger -strict $n]||![string is wideinteger -strict $m]||$n<1||$m<1||$n*$m!=$rows||($n!=1&&$m!=1)} {_error {Provider shape differs from its captured row count}}
        dict set binding $quantity $field;dict set originalShapes $field $shape
        lappend schema [dict create variable_id $field unit [dict get $prototype quantities $quantity unit] dtype float64 rank 1 shape [list $rows] dimension_ids row]
        # A prototype sample is not a vector result. Actual field reads must use
        # the captured resource, never these first-row example values.
        dict unset out values $field;dict set out types $field captured_column
    }
    bindColumns $prototype $binding $rows
    if {![file isfile $path]||[file type $path] eq "link"||[file size $path]!=8*$rows*[llength $fields]} {_error {Provider captured artifact differs from its declared byte shape}}
    set metadata [dict create format gxtxt.statistical_facts.float64_column_major_le.v1 row_count $rows variable_schema $schema original_field_shapes $originalShapes]
    set resource [::GX::interactiveDocumentResourceImportNumeric $document $path $metadata]
    dict set out captured_statistics [bindResourceColumns $prototype $resource $binding $rows]
    return $out
}
proc ::GX::StatisticsV1::bindResourceColumns {prototype resource columnVariables rowCount {rowStart 0}} {
    set binding [bindColumns $prototype $columnVariables $rowCount $rowStart]
    # The existing resource owner verifies identity, generation, complete size,
    # SHA and Session lifetime. No caller-selected storage path is accepted.
    ::GX::interactiveDocumentResourceInfo $resource
    set metadata [dict get $resource metadata]
    if {[_get $metadata format {}] ne "gxtxt.statistical_facts.float64_column_major_le.v1"} {_error {Statistical resource requires the declared binary64 column-major format}}
    set storedRows [_get $metadata row_count {}];set schema [_get $metadata variable_schema {}]
    if {![string is wideinteger -strict $storedRows]||$storedRows<1||[llength $schema]<1||[llength $schema]>128} {_error {Statistical resource requires its actual positive row count and bounded column schema}}
    if {[dict get $resource size_bytes]!=8*$storedRows*[llength $schema]} {_error {Statistical resource byte length differs from its declared shape}}
    set seen {}
    foreach variable $schema {
        _keys $variable {variable_id unit dtype rank shape dimension_ids} {statistical resource variable}
        set id [_get $variable variable_id {}]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $id]||$id in $seen} {_error {Statistical resource requires unique column identities}}
        lappend seen $id
        if {[_get $variable dtype {}] ne "float64"||[_get $variable rank {}]!=1||[_get $variable shape {}] ne [list $storedRows]||[_get $variable dimension_ids {}] ne "row"} {_error {Statistical resource columns must declare their actual binary64 row shape}}
    }
    _bindingSchema $binding $schema
    dict set binding schema gxtxt.statistical_result.resource_binding.v1
    dict unset binding seal
    dict set binding resource $resource
    return $binding
}
proc ::GX::StatisticsV1::_validateResourceBinding {result} {
    _keys $result {api_id api_version schema prototype column_variables row_count row_start resource} {resource binding}
    set expected [bindResourceColumns [dict get $result prototype] [dict get $result resource] [dict get $result column_variables] [dict get $result row_count] [dict get $result row_start]]
    foreach key [dict keys $expected] {
        if {![dict exists $result $key]||[dict get $result $key] ne [dict get $expected $key]} {_error "Resource binding field '$key' bypasses CORE interpretation"}
    }
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::_resourceBindingRequest {result start count} {
    if {![string is wideinteger -strict $start]||$start<0||![string is integer -strict $count]||$count<1||$count>8192} {_error {Resource binding reads require a nonnegative start and one to 8192 rows}}
    validate $result
    if {[_get $result schema {}] ne "gxtxt.statistical_result.resource_binding.v1"} {_error {Resource table requires its captured resource binding}}
    if {$start+$count>[dict get $result row_count]} {_error {Resource read exceeds its captured row span}}
    set facts [dict get $result prototype request numerical]
    set mapping [dict get $result column_variables]
    if {[dict size $facts]*$count>1000000||8*[dict size $mapping]*$count>1048576} {_error {Resource read exceeds the bounded fact or binary page limit}}
    set resource [dict get $result resource];set metadata [dict get $resource metadata]
    set storedRows [dict get $metadata row_count];set indexes {};set index 0
    foreach variable [dict get $metadata variable_schema] {dict set indexes [dict get $variable variable_id] $index;incr index}
    set physicalStart [expr {[dict get $result row_start]+$start}];set ranges {}
    dict for {quantity variable} $mapping {lappend ranges [list [expr {8*([dict get $indexes $variable]*$storedRows+$physicalStart)}] [expr {8*$count}]]}
    set blocks [::GX::interactiveDocumentResourceReadRanges $resource $ranges]
    set columns {};dict for {quantity value} $facts {dict set columns $quantity [lrepeat $count $value]}
    set index 0
    dict for {quantity variable} $mapping {
        set bytes [lindex $blocks $index];incr index
        if {[string length $bytes]!=8*$count} {_error {Statistical resource returned an incomplete binary column}}
        binary scan $bytes q* values
        dict set columns $quantity $values
    }
    set rows {};for {set i $physicalStart} {$i<$physicalStart+$count} {incr i} {lappend rows row_$i}
    set request [dict get $result prototype request]
    set provenance [dict merge [dict get $request provenance] [dict create binding_resource $resource binding_row_start $physicalStart]]
    return [dict create model_id [dict get $request model_id] context [dict get $request context] provenance $provenance row_ids $rows numerical_columns $columns]
}
proc ::GX::StatisticsV1::resourceBindingTable {result start count} {
    return [interpretTable [_resourceBindingRequest $result $start $count]]
}
proc ::GX::StatisticsV1::resourceBindingFieldElements {result field start count} {
    set request [_resourceBindingRequest $result $start $count]
    set fields [numericFields [dict get $result prototype]]
    if {![dict exists $fields $field]} {_error "Source field '$field' has no statistical interpretation"}
    set template [dict get $fields $field];set quantity [dict get $template quantity]
    if {[dict get $template kind] ne "scalar"} {_error {Resource columns require a scalar field identity}}
    set base [dict create model_id [dict get $request model_id] context [dict get $request context] provenance [dict get $request provenance]]
    set descriptor [dict get $result prototype model]
    set cells {};set index 0
    foreach rowId [dict get $request row_ids] {
        set numerical {};dict for {key values} [dict get $request numerical_columns] {dict set numerical $key [lindex $values $index]}
        dict set base numerical $numerical
        set item [dict get [_interpretRequest $base [list $quantity] $descriptor] quantities $quantity]
        dict set item id $field;dict set item quantity $quantity
        dict set item unit [dict get $template unit_text];dict set item unit_text [dict get $template unit_text]
        dict set item row $index;dict set item column 0;dict set item row_id $rowId
        lappend cells $item;incr index
    }
    return [dict create shape [list $count 1] cells $cells]
}
proc ::GX::StatisticsV1::resourceBindingReport {result} {
    validate $result
    set resource [dict get $result resource]
    set lines [list "Managed-resource statistical columns: [dict get $result row_count] rows starting at [dict get $result row_start]; [dict size [dict get $result column_variables]] captured fact columns." "Resource SHA-256: [dict get $resource sha256]" {Read a bounded resource_binding_table window for actual values and availability; prototype values are examples, not aggregates.}]
    dict for {quantity variable} [dict get $result column_variables] {
        set item [dict get $result prototype quantities $quantity]
        lappend lines "[dict get $item label] ([dict get $item unit]); column $variable: [_get $item definition {Captured numerical quantity; consult row status before use}]"
    }
    foreach assumption [_get [dict get $result prototype context] assumptions {}] {lappend lines $assumption}
    return [join $lines \n]
}
