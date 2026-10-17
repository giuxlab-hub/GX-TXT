# Compact parameterless statistical tables; numerical facts remain Numeric-owned.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_tableProfiles {} {
    return {survival foundation_correlation multiplicity location_estimate summary hypothesis anova resampling pca comparison power_level local_cloud replicate_profile signal_summary signal_snr signal_spectrum_quality fft_spectrum_quality harmonic_peak_quality harmonic_components event_timing signal_correlation window_metrics signal_spectral}
}
proc ::GX::StatisticsV1::_tableRowId {id seen} {
    if {$id eq {}||[string length $id]>256||[regexp {[[:cntrl:]]} $id]||[dict exists $seen $id]} {_error {Statistical table row IDs must be unique nonempty printable identifiers}}
}
proc ::GX::StatisticsV1::_buildTable {modelId operation rows context provenance inputKind} {
    if {[llength $rows]<1||[llength $rows]>8192} {_error {Statistical tables require one to 8192 rows}}
    set ids {};set seen {};set index 0;set factKeys {}
    array set facts {}
    array set definitions {};array set states {};array set stateIds {};array set values {};array set hasValues {}
    foreach row $rows {
        _keys $row [expr {$inputKind eq "numeric" ? {id raw} : {id numerical}}] {statistical table row}
        set id [_get $row id {}];_tableRowId $id $seen;dict set seen $id 1;lappend ids $id
        set rowProvenance [dict merge $provenance [dict create table_row_id $id]]
        if {$inputKind eq "numeric"} {
            if {![dict exists $row raw]} {_error {Numeric table row requires its raw public result}}
            set result [fromNumeric $modelId $operation [dict get $row raw] $context {} $rowProvenance]
        } else {
            set result [interpret [dict create model_id $modelId context $context numerical [dict get $row numerical] provenance $rowProvenance]]
        }
        set actualProvenance [dict get $result provenance];dict unset actualProvenance table_row_id
        if {$index==0} {
            set descriptor [dict get $result model];set commonContext [dict get $result context];set commonProvenance $actualProvenance
            if {[dict get $descriptor profile] ni [_tableProfiles]||[llength [dict get $result parameters]]} {_error {Statistical tables require a parameterless analysis profile}}
        } elseif {[dict get $result model] ne $descriptor||[dict get $result context] ne $commonContext||$actualProvenance ne $commonProvenance} {_error {Rows with different models, contexts or provenance require separate statistical tables}}
        set numerical [dict get $result request numerical]
        if {$index==0} {set factKeys [dict keys $numerical];foreach key $factKeys {set facts($key) {}}} elseif {[lsort [dict keys $numerical]] ne [lsort $factKeys]} {_error {Statistical table rows require the same numerical fact columns}}
        dict for {key value} $numerical {
            if {![string is double -strict $value]} {_error {Statistical table v1 accepts scalar numerical facts only}}
            lappend facts($key) [_tableNumber $value]
        }
        dict for {quantity item} [dict get $result quantities] {
            set definition [dict remove $item status reason value]
            set state [dict create status [dict get $item status] reason [dict get $item reason]]
            if {$index==0} {set definitions($quantity) $definition;set states($quantity) {};set stateIds($quantity) {};set values($quantity) {};set hasValues($quantity) 0}
            if {$definitions($quantity) ne $definition} {_error {Statistical quantity definitions differ across table rows}}
            set stateId [lsearch -exact $states($quantity) $state]
            if {$stateId<0} {set stateId [llength $states($quantity)];lappend states($quantity) $state}
            lappend stateIds($quantity) $stateId
            set value nan
            if {[dict get $item status] eq "value"} {
                if {[dict get $item kind] ne "scalar"} {_error {Statistical table v1 cannot flatten vector or matrix identities}}
                set value [_tableNumber [dict get $item value]];set hasValues($quantity) 1
            }
            lappend values($quantity) $value
        }
        incr index
    }
    set columns {}
    # Stable catalog order; each column buffer above has one mutable owner.
    foreach quantity [dict keys [dict get $result quantities]] {
        set column [dict create definition $definitions($quantity) states $states($quantity)]
        if {[llength $states($quantity)]==1} {dict set column state 0} else {dict set column state_ids $stateIds($quantity)}
        if {$hasValues($quantity)} {dict set column values $values($quantity)}
        dict set columns $quantity $column
    }
    set numericalColumns {};foreach key $factKeys {dict set numericalColumns $key $facts($key)}
    set request [dict create model_id $modelId context $commonContext provenance $commonProvenance row_ids $ids numerical_columns $numericalColumns]
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.statistical_result.table.v1 \
        model $descriptor context $commonContext provenance $commonProvenance row_ids $ids row_count [llength $ids] columns $columns request $request]
}
proc ::GX::StatisticsV1::fromNumericTable {modelId operation rows context {provenance {}}} {
    return [_buildTable $modelId $operation $rows $context $provenance numeric]
}
proc ::GX::StatisticsV1::fromNumericColumns {modelId operation rowIds rawColumns commonRaw context {provenance {}}} {
    if {[llength $rowIds]<1||[llength $rowIds]>8192} {_error {Statistical tables require one to 8192 rows}}
    dict for {key values} $rawColumns {
        if {[dict exists $commonRaw $key]||[llength $values]!=[llength $rowIds]} {_error {Raw numerical columns must match row identities and not shadow common facts}}
        foreach value $values {if {![string is double -strict $value]} {_error {Raw statistical columns require scalar numerical facts}}}
    }
    if {[dict size $rawColumns]*[llength $rowIds]>1000000} {_error {Statistical table exceeds one million numerical facts}}
    set rows {};set i 0
    foreach id $rowIds {
        set raw $commonRaw;dict for {key values} $rawColumns {dict set raw $key [lindex $values $i]}
        lappend rows [dict create id $id raw $raw];incr i
    }
    return [_buildTable $modelId $operation $rows $context $provenance numeric]
}
proc ::GX::StatisticsV1::_tableNumber {value} {
    if {[_finite $value]} {set text [format %.17g $value];if {$text eq "-0"} {return -0.0};return $text}
    if {[_infinite $value 1]} {return inf}
    if {[_infinite $value -1]} {return -inf}
    return nan
}
proc ::GX::StatisticsV1::interpretTable {request} {
    _keys $request {model_id context provenance row_ids numerical_columns} {statistical table request}
    set ids [dict get $request row_ids];set columns [dict get $request numerical_columns]
    if {[llength $ids]<1||[llength $ids]>8192||[dict size $columns]*[llength $ids]>1000000} {_error {Statistical table exceeds its row or numerical fact limit}}
    dict for {key values} $columns {if {[llength $values]!=[llength $ids]} {_error {Numerical table fact column differs from row identity count}}}
    set rows {};set i 0
    foreach id $ids {
        set numerical {};dict for {key values} $columns {dict set numerical $key [lindex $values $i]}
        lappend rows [dict create id $id numerical $numerical];incr i
    }
    return [_buildTable [dict get $request model_id] {} $rows [dict get $request context] [dict get $request provenance] canonical]
}
proc ::GX::StatisticsV1::_tableColumnValue {column index} {
    set stateId [_get $column state {}]
    if {$stateId eq {}} {set stateId [lindex [dict get $column state_ids] $index]}
    set state [lindex [dict get $column states] $stateId]
    set result [dict merge [dict get $column definition] $state]
    if {[dict get $state status] eq "value"} {dict set result value [lindex [dict get $column values] $index]}
    return $result
}
proc ::GX::StatisticsV1::tableSelect {result rowIds} {
    validate $result
    if {[_get $result schema {}] ne "gxtxt.statistical_result.table.v1"||![llength $rowIds]} {_error {tableSelect requires a statistical table and nonempty row selection}}
    set lookup {};set i 0;foreach id [dict get $result row_ids] {dict set lookup $id $i;incr i}
    set seen {};set indices {}
    foreach id $rowIds {
        _tableRowId $id $seen;dict set seen $id 1
        if {![dict exists $lookup $id]} {_error "Unknown statistical row '$id'"}
        lappend indices [dict get $lookup $id]
    }
    set request [dict get $result request];dict set request row_ids $rowIds
    dict for {key values} [dict get $request numerical_columns] {
        set selected {};foreach i $indices {lappend selected [lindex $values $i]}
        dict set request numerical_columns $key $selected
    }
    return [interpretTable $request]
}
proc ::GX::StatisticsV1::tableValues {result quantities} {
    validate $result
    if {[_get $result schema {}] ne "gxtxt.statistical_result.table.v1"} {_error {tableValues requires a statistical table}}
    set output {}
    foreach quantity $quantities {
        if {![dict exists $result columns $quantity]} {_error "Unknown table quantity '$quantity'"}
        set column [dict get $result columns $quantity]
        if {[dict get $column definition kind] ne "scalar"} {_error {Table value access requires scalar quantities}}
        set values {}
        for {set i 0} {$i<[dict get $result row_count]} {incr i} {
            set item [_tableColumnValue $column $i]
            lappend values [_get $item value NaN]
        }
        dict set output $quantity $values
    }
    return $output
}
proc ::GX::StatisticsV1::tableReport {result rowIds quantities} {
    validate $result
    if {[_get $result schema {}] ne "gxtxt.statistical_result.table.v1"} {_error {tableReport requires a statistical table}}
    set ids [dict get $result row_ids];if {![llength $rowIds]} {set rowIds $ids}
    set lines {}
    foreach id $rowIds {
        set index [lsearch -exact $ids $id];if {$index<0} {_error "Unknown statistical row '$id'"}
        lappend lines "Row: $id"
        foreach quantity $quantities {
            if {![dict exists $result columns $quantity]} {_error "Unknown table quantity '$quantity'"}
            set item [_tableColumnValue [dict get $result columns $quantity] $index]
            if {[dict get $item status] eq "value"} {lappend lines "[dict get $item label]: [format %.9g [dict get $item value]] ([dict get $item unit])"} else {
                lappend lines "[dict get $item label]: [dict get $item status] — [dict get $item reason]"
            }
        }
    }
    if {[dict get $result model profile] in {survival foundation_correlation multiplicity}} {
        foreach assumption [dict get $result context assumptions] {lappend lines $assumption}
    }
    return [join $lines \n]
}
proc ::GX::StatisticsV1::tableRows {result mapping {rowIds {}}} {
    validate $result
    if {[_get $result schema {}] ne "gxtxt.statistical_result.table.v1"} {_error {tableRows requires a statistical table}}
    set ids [dict get $result row_ids];if {![llength $rowIds]} {set rowIds $ids}
    dict for {alias quantity} $mapping {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $alias]||![dict exists $result columns $quantity]} {_error {Table aliases and quantities must be valid identifiers}}
        if {[dict get $result columns $quantity definition kind] ne "scalar"} {_error {Table rows cannot flatten vector/matrix identities}}
    }
    set rows {};set seen {}
    foreach id $rowIds {
        _tableRowId $id $seen;dict set seen $id 1
        set index [lsearch -exact $ids $id];if {$index<0} {_error "Unknown statistical row '$id'"}
        set cells {}
        dict for {alias quantity} $mapping {
            set item [_tableColumnValue [dict get $result columns $quantity] $index]
            set unit [dict get $item unit];set display $unit
            if {$unit in {count dimensionless}} {set display 1} elseif {[llength $unit]==3&&[lindex $unit 0] eq "power"} {set display "[lindex $unit 1]^[lindex $unit 2]"}
            dict set cells $alias [dict merge $item [dict create id $alias quantity $quantity unit_text $display value [_get $item value NaN]]]
        }
        lappend rows [dict create row_id $id cells $cells]
    }
    return $rows
}
proc ::GX::StatisticsV1::tableCsvRows {result mapping {rowIds {}}} {
    if {![dict size $mapping]} {_error {CSV statistical rows require at least one quantity}}
    set records {};set ids {}
    foreach row [tableRows $result $mapping $rowIds] {
        lappend ids [dict get $row row_id];set fields {}
        dict for {alias item} [dict get $row cells] {
            if {[dict get $item status] eq "value"} {lappend fields [_tableNumber [dict get $item value]]} else {lappend fields {}}
        }
        lappend records [join $fields ,]
    }
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.statistical_csv_rows.v1 columns [dict keys $mapping] row_ids $ids records $records]
}
