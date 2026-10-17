# Worksheet projections of captured CORE scientific resources; no estimation.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificWorksheet {
    variable evaluationDocument {}
    variable statisticalFieldCache {}
    variable statisticalItemCache {}
}
proc ::GX::ScientificWorksheet::_predictionSource {operands} {
    set sources {}
    foreach operand $operands {
        foreach source [_statisticalSources $operand] {
            if {[dict get $source schema] eq "gxtxt.statistical_result.v1"&&[dict get $source model profile] in {regression nonlinear_regression}&&$source ni $sources} {lappend sources $source}
        }
    }
    if {[llength $sources]!=1} {error {Prediction intervals require exactly one captured fitted statistical source in their operand lineage}}
    ::GX::StatisticsV1::validate [lindex $sources 0]
    return [lindex $sources 0]
}
proc ::GX::ScientificWorksheet::_statisticalDataFieldItem {statistics field values {window {}} {selected 0} {companions {}}} {
    # Public CORE contracts describe original Numeric data without copying its
    # potentially large arrays into the statistical interpretation record.
    set contract [dict get [::GX::StatisticsV1::numericDataFields $statistics] fields $field]
    lassign [dict get $contract shape] total columns
    if {$columns!=1||[dict get $contract kind] ne "vector"} {error {Unsupported captured data field shape}}
    set start 0;set count $total
    if {$window ne {}} {lassign [_statisticalWindowBounds $window $total] start count}
    if {$count>20000} {error {Choose a captured data row window of at most 20000 cells}}
    if {$selected} {
        if {[llength $values]!=$count} {error {Saved data values differ from their captured row selection}}
    } else {
        if {[llength $values]!=$total} {error {Numeric data shape differs from its CORE contract}}
        set values [lrange $values $start [expr {$start+$count-1}]]
    }
    set captured {};set availability [lrepeat $count 1]
    if {[dict exists $contract availability_field]} {
        set maskField [dict get $contract availability_field]
        if {![dict exists $companions $maskField]} {error {Captured data requires its original availability mask}}
        set mask [dict get $companions $maskField]
        if {[llength $mask]!=($selected?$count:$total)} {error {Availability mask differs from its captured data shape}}
        if {!$selected} {set mask [lrange $mask $start [expr {$start+$count-1}]]}
        foreach v $mask {if {![string is double -strict $v]||[string match -nocase *nan* $v]||($v!=0&&$v!=1)} {error {Availability mask requires zero or one}}}
        set availability $mask;dict set captured $maskField $mask
    }
    set normalized {};set statuses {};set reasons {}
    foreach v $values available $availability {
        if {![string is double -strict $v]} {error {Numeric data value differs from its CORE contract}}
        set finite [expr {![string match -nocase *nan* $v]&&abs($v)!=Inf}]
        if {[dict exists $contract availability_field]&&!!$available!=$finite} {error {Captured interval bounds disagree with their availability mask}}
        if {!$finite} {
            if {![dict exists $contract nonfinite_status]} {error {Numeric data value differs from its CORE contract}}
            lappend normalized NaN;lappend statuses [dict get $contract nonfinite_status]
            lappend reasons [dict get $contract [expr {$available?"nonfinite_reason":"unavailable_reason"}]]
            continue
        }
        if {([dict exists $contract minimum]&&$v<[dict get $contract minimum])||([dict exists $contract maximum]&&$v>[dict get $contract maximum])||([dict get $contract value_kind] eq "integer"&&$v!=floor($v))} {error {Numeric data value differs from its CORE contract}}
        lappend normalized $v;lappend statuses value;lappend reasons {}
    }
    set item [_value $normalized [dict get $contract unit] [expr {$count==1?"scalar":"vector"}]]
    dict set item shape [list $count 1];dict set item element_units [lrepeat $count [dict get $contract unit]]
    dict set item statistical_result $statistics;dict set item statistical_field $field;dict set item statistical_data_field 1
    dict set item statistical_data_companions $captured
    dict set item statistical_data_statuses $statuses;dict set item statistical_data_reasons $reasons
    if {$window ne {}} {dict set item statistical_window $window}
    return $item
}
proc ::GX::ScientificWorksheet::_statisticalProjection {statistics field {window {}}} {
    set schema [dict get $statistics schema]
    if {$schema eq "gxtxt.statistical_result.resource_binding.v1"} {
        set prototype [dict get $statistics prototype]
        set fields [::GX::StatisticsV1::numericFields $prototype]
        if {![dict exists $fields $field]} {error {Unknown captured statistical field}}
        set quantity [dict get $fields $field quantity]
        if {![dict exists $statistics column_variables $quantity]} {
            ::GX::StatisticsV1::validate $statistics
            set projection [::GX::StatisticsV1::numericFieldElements $prototype $field]
            return [_statisticalWindow $projection $window]
        }
        set rows [dict get $statistics row_count];set start 0;set count $rows
        if {$window ne {}} {lassign [_statisticalWindowBounds $window $rows] start count}
        if {$count>20000} {error "Result has $rows rows. Choose a result row window of at most 20000 cells."}
        set key [list [::GX::interactiveDocumentSessionToken] $statistics $field $start $count]
        variable statisticalFieldCache
        if {[dict exists $statisticalFieldCache $key]} {return [dict get $statisticalFieldCache $key]}
        set maximum [expr {min(8192,1048576/(8*[dict size [dict get $statistics column_variables]]),1000000/[dict size [dict get $prototype request numerical]])}]
        set cells {};set offset 0
        while {$offset<$count} {
            set take [expr {min($maximum,$count-$offset)}]
            set page [::GX::StatisticsV1::resourceBindingFieldElements $statistics $field [expr {$start+$offset}] $take]
            foreach cell [dict get $page cells] {dict set cell row [expr {$offset+[dict get $cell row]}];lappend cells $cell}
            incr offset $take
        }
        set shape [list $count 1]
        if {$window eq {}&&[dict exists $statistics resource metadata original_field_shapes $field]} {
            set original [dict get $statistics resource metadata original_field_shapes $field]
            if {[lindex $original 0]==1} {
                set shape [list 1 $count];set revised {};set index 0
                foreach cell $cells {dict set cell row 0;dict set cell column $index;lappend revised $cell;incr index};set cells $revised
            }
        }
        set projection [dict create shape $shape cells $cells]
        dict set statisticalFieldCache $key $projection
        if {[dict size $statisticalFieldCache]>8} {dict unset statisticalFieldCache [lindex [dict keys $statisticalFieldCache] 0]}
        return $projection
    }
    set projection [::GX::StatisticsV1::numericFieldElements $statistics $field]
    if {[dict exists $statistics provenance worksheet_field_shapes $field]&&[dict get $statistics provenance worksheet_field_shapes $field] eq {1 1}} {
        set cells [dict get $projection cells];set first [lindex $cells 0]
        set comparable [dict remove $first row column row_id]
        foreach cell $cells {if {[dict remove $cell row column row_id] ne $comparable} {error {A shared scalar field cannot collapse unequal captured facts}}}
        dict set first row 0;dict set first column 0
        set projection [dict create shape {1 1} cells [list $first]]
    }
    return [_statisticalWindow $projection $window]
}
proc ::GX::ScientificWorksheet::_uiResultWindow {w} {
    variable ui
    if {![info exists ui($w,apply_row_count)]||$ui($w,apply_row_count) eq {}} {
        if {[info exists ui($w,apply_first_row)]&&$ui($w,apply_first_row) ne "1"} {error {Specify the number of result rows when selecting a later first row}}
        return {}
    }
    set first $ui($w,apply_first_row);set count $ui($w,apply_row_count)
    if {![string is wideinteger -strict $first]||$first<1||![string is integer -strict $count]||$count<1||$count>20000} {error {Choose a positive first result row and one to 20000 rows}}
    return [dict create start [expr {$first-1}] count $count]
}
proc ::GX::ScientificWorksheet::_statisticalWindowBounds {window total} {
    if {[catch {dict size $window}]||[lsort [dict keys $window]] ne {count start}} {error {Result row window requires start and count}}
    set start [dict get $window start];set count [dict get $window count]
    if {![string is wideinteger -strict $start]||![string is integer -strict $count]||$start<0||$count<1||$count>20000||$start+$count>$total} {error {Result row window is outside the actual result or exceeds 20000 cells}}
    return [list $start $count]
}
proc ::GX::ScientificWorksheet::_statisticalWindow {projection window} {
    if {$window eq {}} {return $projection}
    lassign [dict get $projection shape] rows columns
    if {$columns!=1&&$rows!=1} {error {A result row window requires a vector field}}
    lassign [_statisticalWindowBounds $window [expr {$rows*$columns}]] start count
    set cells {};set index 0
    foreach cell [lrange [dict get $projection cells] $start [expr {$start+$count-1}]] {
        dict set cell row $index;dict set cell column 0;lappend cells $cell;incr index
    }
    return [dict create shape [list $count 1] cells $cells]
}
proc ::GX::ScientificWorksheet::_capturedSignalCall {document spec args options} {
    set typed [lmap item $args {_typed $item}]
    while {[llength $typed]<3} {lappend typed [::GX::ScientificTransportv1::empty]}
    if {[llength $typed]!=3} {error {Signal calculation requires at most three operands}}
    return [::GX::SignalAPIv1::callCaptured $document [dict get $spec operation] {*}$typed [dict get $spec context] $options [dict get $spec provenance]]
}
proc ::GX::ScientificWorksheet::_foundationCaptureApplies {meta} {
    expr {[dict get $meta id] in {statistics.multiple_testing statistics.survival_kaplan_meier}}
}
proc ::GX::ScientificWorksheet::_capturedFoundationCall {document meta args options} {
    set typed [_numericTypedArguments $meta $args]
    while {[llength $typed]<3} {lappend typed [::GX::ScientificTransportv1::empty]}
    if {[llength $typed]!=3} {error {Foundation calculation requires at most three operands}}
    set lineage {}
    foreach item $args {
        if {[dict exists $item mixed_units]&&[dict get $item mixed_units]} {error {Statistical input contains mixed units; convert explicitly before calculation}}
        foreach source [_sourceLineage $item] {dict set lineage $source 1}
    }
    set provenance [dict create producer viewer.scientific_worksheet]
    if {[dict size $lineage]} {dict set provenance source_variables [dict keys $lineage]}
    set context {}
    if {[dict get $meta id] eq "statistics.survival_kaplan_meier"} {dict set context x_unit [dict get [lindex $args 0] unit]}
    return [::GX::NumericAPIv1::foundationCaptured $document [dict get $meta family] [dict get $meta action] {*}$typed $context $options $provenance]
}
proc ::GX::ScientificWorksheet::_formulaResourceReferences {book} {
    # Formula values keep their established recalculation behavior. Save their
    # last captured scientific resources as provenance, while guided operations
    # already retain complete bindings in their saved operation definitions.
    _ensureCalculationSnapshot $book
    variable cache
    set retained [expr {[dict exists $book captured_formula_resources]?[dict get $book captured_formula_resources]:{}}]
    set flushed [_flush $book]
    foreach sheet [dict keys $retained] {if {$sheet ni [dict get $flushed sheet_order]} {dict unset retained $sheet}}
    foreach sheet [dict get $flushed sheet_order] {
        set active [_activate $flushed $sheet];set key [_key $active]
        if {[dict exists $retained $sheet]} {
            foreach address [dict keys [dict get $retained $sheet]] {
                if {![dict exists $active cells $address]||[dict get $active cells $address kind] ne "formula"} {dict unset retained $sheet $address}
            }
        }
        if {![dict exists $cache $key]} continue
        dict for {address item} [dict get $cache $key] {
            if {![dict exists $active cells $address]||[dict get $active cells $address kind] ne "formula"} continue
            set references {}
            foreach result [_statisticalSources $item] {
                if {[dict get $result schema] eq "gxtxt.statistical_result.resource_binding.v1"} {
                    set reference [dict get $result resource]
                    if {$reference ni $references} {lappend references $reference}
                }
            }
            if {[llength $references]} {dict set retained $sheet $address $references} elseif {[dict exists $retained $sheet $address]} {dict unset retained $sheet $address}
        }
    }
    dict set book captured_formula_resources $retained
    return $book
}
