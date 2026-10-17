# GX-TXT Scientific Worksheet API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificWorksheet {
    variable version 1.2.0
    variable cache [dict create]
    variable dirty [dict create]
    variable evaluating [dict create]
    variable ui
}
proc ::GX::ScientificWorksheet::_requireSession {} {return [::GX::sessionInspectionCurrentSession]}
proc ::GX::ScientificWorksheet::_cell {cell} {
    set cell [string toupper [string trim $cell]]
    if {![regexp {^([A-Z]{1,3})([1-9][0-9]*)$} $cell unused column row]} {error "Invalid cell address '$cell'."}
    if {$row > 1000000} {error "Worksheet row limit is 1000000."}
    return $cell
}
proc ::GX::ScientificWorksheet::_columnNumber {letters} {
    set result 0
    foreach character [split $letters {}] {set result [expr {$result*26+[scan $character %c]-64}]}
    return $result
}
proc ::GX::ScientificWorksheet::_columnName {number} {
    if {$number < 1 || $number > 702} {error "Worksheet column limit is ZZ."}
    set out ""
    while {$number} {set remainder [expr {($number-1)%26}]; set out "[format %c [expr {65+$remainder}]]$out"; set number [expr {($number-1)/26}]}
    return $out
}
proc ::GX::ScientificWorksheet::_parts {cell} {_cell $cell; regexp {^([A-Z]+)([0-9]+)$} [string toupper $cell] unused col row; return [list [_columnNumber $col] $row]}
proc ::GX::ScientificWorksheet::rangeCells {from to} {
    lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
    if {$c2 < $c1 || $r2 < $r1} {error "Range end must follow its start."}
    if {($c2-$c1+1)*($r2-$r1+1) > 20000} {error "Formula range exceeds 20000 cells."}
    set cells {}
    for {set row $r1} {$row <= $r2} {incr row} {for {set col $c1} {$col <= $c2} {incr col} {lappend cells "[_columnName $col]$row"}}
    return $cells
}
proc ::GX::ScientificWorksheet::new {{name "Untitled Worksheet"}} {
    if {[string trim $name] eq ""} {error "Worksheet name is required."}
    return [dict create format scientific_worksheet.v1 document_id "" name $name revision 0 cells [dict create] columns [dict create] ranges [dict create] bindings [dict create] options [dict create display_digits 8] presentation [dict create visible_rows 200 first_row 1]]
}
proc ::GX::ScientificWorksheet::_key {book} {
    if {[dict get $book document_id] ne ""} {return [dict get $book document_id]}
    return "new:[dict get $book name]"
}
proc ::GX::ScientificWorksheet::_tokenize {formula} {
    set remaining [string trim $formula]
    if {[string index $remaining 0] eq "="} {set remaining [string range $remaining 1 end]}
    if {[string length $remaining] > 8192} {error "Formula exceeds 8192 characters."}
    set tokens {}
    while {[string trim $remaining] ne ""} {
        set remaining [string trimleft $remaining]
        if {[regexp {^([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?} $remaining match]} {
            lappend tokens [list number $match]; set remaining [string range $remaining [string length $match] end]; continue
        }
        if {[regexp {^"([^"\\]|\\.)*"} $remaining match]} {
            set text [string range $match 1 end-1]
            set text [string map [list {\"} {"}] $text]
            lappend tokens [list string $text]; set remaining [string range $remaining [string length $match] end]; continue
        }
        if {[regexp {^[A-Za-z_][A-Za-z0-9_.]*} $remaining match]} {
            lappend tokens [list identifier $match]; set remaining [string range $remaining [string length $match] end]; continue
        }
        if {[regexp {^(<=|>=|==|!=|[+*/^(),:\[\]<>-])} $remaining match]} {
            lappend tokens [list symbol $match]; set remaining [string range $remaining [string length $match] end]; continue
        }
        error "Invalid formula character near '[string range $remaining 0 15]'."
    }
    lappend tokens [list eof ""]
    return $tokens
}
proc ::GX::ScientificWorksheet::_dependencies {book formula} {
    set tokens [_tokenize $formula]; set deps [dict create]
    for {set i 0} {$i < [llength $tokens]-1} {incr i} {
        lassign [lindex $tokens $i] kind value
        if {$kind ne "identifier"} continue
        if {[regexp -nocase {^[A-Z]{1,3}[1-9][0-9]*$} $value]} {
            set first [_cell $value]
            if {[lindex [lindex $tokens [expr {$i+1}]] 1] eq ":"} {
                set last [lindex [lindex $tokens [expr {$i+2}]] 1]
                foreach address [rangeCells $first $last] {dict set deps $address 1}
            } else {dict set deps $first 1}
        } elseif {[dict exists $book ranges $value]} {
            foreach address [dict get $book ranges $value] {dict set deps $address 1}
        } elseif {[dict exists $book columns $value] && [lindex [lindex $tokens [expr {$i+1}]] 1] eq "\["} {
            set row [lindex [lindex $tokens [expr {$i+2}]] 1]
            if {![string is integer -strict $row] || $row < 1} {error "Named column row must be a positive integer."}
            dict set deps "[dict get $book columns $value]$row" 1
        }
    }
    return [dict keys $deps]
}
proc ::GX::ScientificWorksheet::_invalidate {book changed} {
    variable cache; variable dirty
    set key [_key $book]
    set queue [list $changed]; set touched [dict create]
    while {[llength $queue]} {
        set current [lindex $queue 0]; set queue [lrange $queue 1 end]
        if {[dict exists $touched $current]} continue
        dict set touched $current 1
        if {[dict exists $cache $key $current]} {dict unset cache $key $current}
        dict set dirty $key $current 1
        dict for {address data} [dict get $book cells] {
            if {[dict exists $data dependencies] && $current in [dict get $data dependencies]} {lappend queue $address}
        }
    }
}
proc ::GX::ScientificWorksheet::setCell {book address source} {
    set address [_cell $address]
    if {[string length $source] > 8192} {error "Cell source exceeds 8192 characters."}
    if {$source eq ""} {dict unset book cells $address} else {
        lassign [_parts $address] columnNumber unused
        set column [_columnName $columnNumber]
        set unit [expr {[dict exists $book column_metadata $column unit] ? [dict get $book column_metadata $column unit] : ""}]
        set data [dict create source $source kind manual unit $unit lineage [dict create]]
        if {[string index $source 0] eq "="} {
            set deps [_dependencies $book $source]
            dict set data kind formula; dict set data dependencies $deps
        } elseif {![string is double -strict $source]} {
            dict set data kind text
        } elseif {[expr {abs(double($source)) == Inf || double($source) != double($source)}]} {
            error "Cell numeric input must be finite."
        }
        dict set book cells $address $data
    }
    dict incr book revision
    _invalidate $book $address
    return $book
}
proc ::GX::ScientificWorksheet::setColumn {book column name {unit ""}} {
    set column [string toupper $column]
    _columnNumber $column
    if {$name ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name]} {error "Column name must be an identifier."}
    if {$name ne ""} {
        if {[dict exists $book columns $name] && [dict get $book columns $name] ne $column} {error "Column name '$name' already has a stable binding."}
        dict set book columns $name $column
    }
    if {$unit eq "" && [dict exists $book column_metadata $column unit]} {set unit [dict get $book column_metadata $column unit]}
    dict for {cell data} [dict get $book cells] {
        if {![string match "$column*" $cell]} continue
        if {[dict get $data kind] eq "dataset" && [dict get $data unit] ne $unit} {error "Dataset-bound column $column has source unit '[dict get $data unit]'. Convert explicitly before assigning another unit."}
        if {[dict get $data kind] in {manual text}} {dict set book cells $cell unit $unit}
    }
    dict set book column_metadata $column [dict create name $name unit $unit]
    dict for {cell data} [dict get $book cells] {
        if {[dict get $data kind] eq "formula"} {dict set book cells $cell dependencies [_dependencies $book [dict get $data source]]}
    }
    variable cache
    set key [_key $book]
    if {[dict exists $cache $key]} {dict unset cache $key}
    dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::defineRange {book name start end} {
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name]} {error "Range name must be an identifier."}
    set addresses [rangeCells $start $end]
    if {[dict exists $book ranges $name] && [dict get $book ranges $name] ne $addresses} {error "Range name '$name' already has a stable binding."}
    dict set book ranges $name $addresses
    dict for {cell data} [dict get $book cells] {
        if {[dict get $data kind] eq "formula"} {
            dict set book cells $cell dependencies [_dependencies $book [dict get $data source]]
        }
    }
    variable cache
    set key [_key $book]
    if {[dict exists $cache $key]} {dict unset cache $key}
    dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::_peek {tokens index} {return [lindex [lindex $tokens $index] 1]}
proc ::GX::ScientificWorksheet::_take {tokens indexVar expected} {
    upvar 1 $indexVar index
    set actual [_peek $tokens $index]
    if {$actual ne $expected} {error "Expected '$expected' in formula, got '$actual'."}
    incr index
}
proc ::GX::ScientificWorksheet::_value {value {unit ""} {kind scalar}} {return [dict create value $value unit $unit kind $kind]}
proc ::GX::ScientificWorksheet::_statisticalSources {item} {
    set results [expr {[dict exists $item statistical_sources]?[dict get $item statistical_sources]:{}}]
    if {[dict exists $item statistical_result]&&[lsearch -exact $results [dict get $item statistical_result]]<0} {lappend results [dict get $item statistical_result]}
    return $results
}
proc ::GX::ScientificWorksheet::_sourceLineage {item} {
    set records [expr {[dict exists $item source_lineage]?[dict get $item source_lineage]:{}}]
    if {[dict exists $item lineage dataset_id]&&[dict exists $item lineage variable_id]} {
        set record [dict create dataset_id [dict get $item lineage dataset_id] variable_id [dict get $item lineage variable_id]]
        if {$record ni $records} {lappend records $record}
    }
    return $records
}
proc ::GX::ScientificWorksheet::_carryStatistics {item inputs} {
    set results [_statisticalSources $item]
    set lineage {};foreach record [_sourceLineage $item] {dict set lineage $record 1}
    foreach input $inputs {
        foreach result [_statisticalSources $input] {if {[lsearch -exact $results $result]<0} {lappend results $result}}
        foreach record [_sourceLineage $input] {dict set lineage $record 1}
        if {[dict exists $input mixed_units]&&[dict get $input mixed_units]} {dict set item mixed_units 1}
    }
    if {[llength $results]} {dict set item statistical_sources $results}
    if {[dict size $lineage]} {dict set item source_lineage [dict keys $lineage]}
    return $item
}
proc ::GX::ScientificWorksheet::_evalCell {book address stack} {
    variable cache; variable evaluating
    set address [_cell $address]; set key [_key $book]
    if {$address in $stack} {error "Circular reference: [join [concat $stack $address] { -> }]."}
    if {[dict exists $cache $key $address]} {return [dict get $cache $key $address]}
    if {![dict exists $book cells $address]} {error "Referenced cell $address is empty."}
    set data [dict get $book cells $address]; set source [dict get $data source]
    if {[dict get $data kind] eq "formula"} {
        set tokens [_tokenize $source]; set index 0
        set result [_parseComparison $book $tokens index [concat $stack $address]]
        if {[_peek $tokens $index] ne ""} {error "Unexpected formula token '[_peek $tokens $index]'."}
    } elseif {[dict get $data kind] eq "text"} {set result [_value $source "" text]} else {
        set unit [expr {[dict exists $data unit] ? [dict get $data unit] : ""}]
        set result [_value $source $unit]
    }
    dict set result origin [dict get $data kind]
    if {[dict exists $data lineage]} {dict set result lineage [dict get $data lineage]}
    dict set cache $key $address $result
    return $result
}
proc ::GX::ScientificWorksheet::value {book address} {return [_evalCell $book $address {}]}
proc ::GX::ScientificWorksheet::recalculate {book {all 0}} {
    variable cache; variable dirty
    set key [_key $book]
    if {$all} {if {[dict exists $cache $key]} {dict unset cache $key}; set targets [dict keys [dict get $book cells]]} else {
        set targets [expr {[dict exists $dirty $key] ? [dict keys [dict get $dirty $key]] : [dict keys [dict get $book cells]]}]
    }
    set result [dict create]
    foreach address $targets {
        if {[catch {set item [value $book $address]} message]} {dict set result $address [dict create error $message]} else {dict set result $address $item}
    }
    if {[dict exists $dirty $key]} {dict unset dirty $key}
    return $result
}
proc ::GX::ScientificWorksheet::_numericOperand {item} {
    if {[dict get $item kind] eq "text"} {error "Numeric function requires a number or vector."}
    return [dict create kind [dict get $item kind] value [dict get $item value]]
}
proc ::GX::ScientificWorksheet::_binary {operator left right} {
    if {[dict get $left kind] ne "scalar" || [dict get $right kind] ne "scalar"} {error "Arithmetic with vectors requires a public numeric function."}
    set a [dict get $left value]; set b [dict get $right value]
    if {![string is double -strict $a] || ![string is double -strict $b]} {error "Arithmetic requires numeric values."}
    set u [dict get $left unit]; set v [dict get $right unit]
    if {$operator in {+ - < > <= >= == !=} && $u ne $v} {error "Units '$u' and '$v' differ. Convert explicitly with Unit Registry first."}
    switch -- $operator {
        + {set result [expr {$a+$b}]; set unit $u}
        - {set result [expr {$a-$b}]; set unit $u}
        * {set result [expr {$a*$b}]; set unit ""}
        / {if {$b == 0} {error "Division by zero."}; set result [expr {double($a)/$b}]; set unit ""}
        ^ {set result [expr {pow($a,$b)}]; set unit ""}
        < {set result [expr {$a<$b}]; set unit ""}
        > {set result [expr {$a>$b}]; set unit ""}
        <= {set result [expr {$a<=$b}]; set unit ""}
        >= {set result [expr {$a>=$b}]; set unit ""}
        == {set result [expr {$a==$b}]; set unit ""}
        != {set result [expr {$a!=$b}]; set unit ""}
    }
    if {![string is double -strict $result] || [expr {abs(double($result)) == Inf || double($result) != double($result)}]} {error "Nonfinite formula result."}
    return [_carryStatistics [_value $result $unit] [list $left $right]]
}
proc ::GX::ScientificWorksheet::_parseComparison {book tokens indexVar stack} {
    upvar 1 $indexVar index
    set left [_parseSum $book $tokens index $stack]
    while {[_peek $tokens $index] in {< > <= >= == !=}} {set op [_peek $tokens $index]; incr index; set right [_parseSum $book $tokens index $stack]; set left [_binary $op $left $right]}
    return $left
}
proc ::GX::ScientificWorksheet::_parseSum {book tokens indexVar stack} {
    upvar 1 $indexVar index
    set left [_parseProduct $book $tokens index $stack]
    while {[_peek $tokens $index] in {+ -}} {set op [_peek $tokens $index]; incr index; set right [_parseProduct $book $tokens index $stack]; set left [_binary $op $left $right]}
    return $left
}
proc ::GX::ScientificWorksheet::_parseProduct {book tokens indexVar stack} {
    upvar 1 $indexVar index
    set left [_parsePower $book $tokens index $stack]
    while {[_peek $tokens $index] in {* /}} {set op [_peek $tokens $index]; incr index; set right [_parsePower $book $tokens index $stack]; set left [_binary $op $left $right]}
    return $left
}
proc ::GX::ScientificWorksheet::_parsePower {book tokens indexVar stack} {
    upvar 1 $indexVar index
    set left [_parsePrimary $book $tokens index $stack]
    if {[_peek $tokens $index] eq "^"} {incr index; set right [_parsePower $book $tokens index $stack]; set left [_binary ^ $left $right]}
    return $left
}
proc ::GX::ScientificWorksheet::_parsePrimary {book tokens indexVar stack} {
    upvar 1 $indexVar index
    lassign [lindex $tokens $index] kind value
    if {$value eq "-"} {incr index; return [_binary * [_value -1] [_parsePrimary $book $tokens index $stack]]}
    if {$value eq "+"} {incr index; return [_parsePrimary $book $tokens index $stack]}
    if {$value eq "("} {incr index; set out [_parseComparison $book $tokens index $stack]; _take $tokens index ")"; return $out}
    if {$kind eq "number"} {incr index; return [_value $value]}
    if {$kind eq "string"} {incr index; return [_value $value "" text]}
    if {$kind ne "identifier"} {error "Expected value in formula, got '$value'."}
    incr index
    if {[_peek $tokens $index] eq "("} {
        incr index; set args {}
        if {[_peek $tokens $index] ne ")"} {
            while {1} {lappend args [_parseComparison $book $tokens index $stack]; if {[_peek $tokens $index] ne ","} break; incr index}
        }
        _take $tokens index ")"
        return [_call $value {*}$args]
    }
    if {[regexp -nocase {^[A-Z]{1,3}[1-9][0-9]*$} $value]} {
        set first [_cell $value]
        if {[_peek $tokens $index] eq ":"} {
            incr index; set last [_peek $tokens $index]; incr index
            set addresses [rangeCells $first $last]; set out {}; set unit "";set inputs {}
            foreach address $addresses {set item [_evalCell $book $address $stack]; if {![llength $inputs]} {set unit [dict get $item unit]} elseif {[dict get $item unit] ne $unit} {error "Range units differ."};lappend inputs $item; lappend out [dict get $item value]}
            return [_carryStatistics [_value $out $unit vector] $inputs]
        }
        return [_evalCell $book $first $stack]
    }
    if {[dict exists $book ranges $value]} {
        set out {}; set unit "";set inputs {}
        foreach address [dict get $book ranges $value] {set item [_evalCell $book $address $stack]; if {![llength $inputs]} {set unit [dict get $item unit]} elseif {[dict get $item unit] ne $unit} {error "Range units differ."};lappend inputs $item; lappend out [dict get $item value]}
        return [_carryStatistics [_value $out $unit vector] $inputs]
    }
    if {[dict exists $book columns $value] && [_peek $tokens $index] eq "\["} {
        incr index; set row [_peek $tokens $index]; incr index; _take $tokens index "]"
        if {![string is integer -strict $row] || $row < 1} {error "Named column requires a positive integer row."}
        return [_evalCell $book "[dict get $book columns $value]$row" $stack]
    }
    error "Unknown formula name '$value'."
}
proc ::GX::ScientificWorksheet::functionCatalog {{query ""}} {
    set out [dict create]
    foreach {provider api namespace prefix} {
        math.numeric NUMERIC_API_v1 NumericAPIv1 numeric
        math.signal SIGNAL_API_v1 SignalAPIv1 signal
        math.rf_network RF_NETWORK_API_v1 RFNetworkAPIv1 rf
        math.magnetics MAGNETICS_API_v1 MagneticsAPIv1 magnetics
    } {
        ::GX::modulePublicApiActivate $provider $api
        foreach id [::GX::${namespace}::listOperations] {
            set meta [::GX::${namespace}::operationMetadata $id]
            if {$prefix eq "numeric"} {
                if {[lsearch -exact [dict get $meta flags] expression] < 0 || [dict get $meta expression_name] eq ""} continue
                if {[lindex [split $id .] 0] ni {array_unary array_binary array_compare array_reduce array_mask array_select array_where interpolate resample integrate cumulative_integrate differentiate rank correlation covariance mad}} continue
                set name "$prefix.[dict get $meta expression_name]"
                if {[dict exists $out $name]} continue
            } else {set name "$prefix.$id"}
            if {$query ne "" && ![string match -nocase "*$query*" "$name [dict get $meta summary]"]} continue
            dict set meta worksheet_name $name
            dict set meta provider_id $provider
            dict set out $name $meta
        }
    }
    foreach {name summary arguments} {
        vector {Build a numeric vector from scalar values} {value...}
        matrix {Give a numeric range its row and column shape} {values rows columns}
        complex {Combine matching real and imaginary arrays for a public API} {real imaginary}
        record {Build data-only public API options from name/value pairs} {name value...}
        empty {Supply an empty optional scientific API operand} {}
        field {Select one named public API result field} {result field_name}
    } {
        if {$query ne "" && ![string match -nocase "*$query*" "$name $summary"]} continue
        dict set out $name [dict create id $name worksheet_name $name provider_id viewer.scientific_worksheet api_id SCIENTIFIC_WORKSHEET_API_v1 summary $summary arguments $arguments shape_semantics data_only unit_behavior caller_owned]
    }
    return $out
}
proc ::GX::ScientificWorksheet::_numericResult {id meta args} {
    set count [llength $args]
    if {$count < [dict get $meta arity_min] || $count > [dict get $meta arity_max]} {error "Function requires [dict get $meta arity_min]–[dict get $meta arity_max] arguments."}
    set unmapped [catch {set mapping [::GX::StatisticsV1::numericFieldMap $id]} reason mappingOptions]
    if {$unmapped&&[dict get $mappingOptions -errorcode] ne {GXTXT STATISTICS UNKNOWN_NUMERIC_OPERATION}} {return -options $mappingOptions $reason}
    if {!$unmapped} {
        foreach item $args {if {[dict exists $item mixed_units]&&[dict get $item mixed_units]} {error {Statistical input contains mixed units; convert values explicitly before aggregation}}}
    }
    set parts [split $id .]; set family [lindex $parts 0]; set action [lindex $parts 1]
    switch -- $family {
        array_unary {set raw [::GX::NumericAPIv1::arrayUnary $action [_numericOperand [lindex $args 0]]]}
        array_binary {set raw [::GX::NumericAPIv1::arrayBinary $action [_numericOperand [lindex $args 0]] [_numericOperand [lindex $args 1]]]}
        array_compare {set raw [::GX::NumericAPIv1::arrayCompare $action [_numericOperand [lindex $args 0]] [_numericOperand [lindex $args 1]]]}
        array_mask {
            if {$count > 1} {set second [_numericOperand [lindex $args 1]]} else {set second {}}
            set raw [::GX::NumericAPIv1::arrayMask $action [_numericOperand [lindex $args 0]] $second]
        }
        array_select {set raw [::GX::NumericAPIv1::arraySelect [_numericOperand [lindex $args 0]] [_numericOperand [lindex $args 1]]]}
        array_where {set raw [::GX::NumericAPIv1::arrayWhere [_numericOperand [lindex $args 0]] [_numericOperand [lindex $args 1]] [_numericOperand [lindex $args 2]]]}
        array_reduce {
            set options [dict create]
            if {$action eq "quantile" && $count == 2} {dict set options probability [dict get [lindex $args 1] value]}
            set raw [::GX::NumericAPIv1::arrayReduce $action [_numericOperand [lindex $args 0]] $options]
        }
        interpolate - resample {set command [expr {$family eq "interpolate" ? "interpolate" : "resample"}]; set raw [::GX::NumericAPIv1::$command {*}[lmap item $args {dict get $item value}]]}
        integrate {set raw [::GX::NumericAPIv1::integrate [dict get [lindex $args 0] value] [dict get [lindex $args 1] value]]}
        cumulative_integrate {set raw [::GX::NumericAPIv1::cumulativeIntegrate [dict get [lindex $args 0] value] [dict get [lindex $args 1] value]]}
        differentiate {set raw [::GX::NumericAPIv1::differentiate [dict get [lindex $args 0] value] [dict get [lindex $args 1] value]]}
        rank {set raw [::GX::NumericAPIv1::rank [dict get [lindex $args 0] value]]}
        correlation {set raw [::GX::NumericAPIv1::correlation [dict get [lindex $args 0] value] [dict get [lindex $args 1] value]]}
        covariance {set raw [::GX::NumericAPIv1::covariance [dict get [lindex $args 0] value] [dict get [lindex $args 1] value]]}
        mad {set raw [::GX::NumericAPIv1::mad [dict get [lindex $args 0] value]]}
        default {error "Operation $id is listed by NUMERIC_API but is unavailable in safe formulas."}
    }
    set field [dict get $meta expression_result_field]
    if {![dict exists $raw $field]} {error "NUMERIC_API result field '$field' is unavailable; inspect operation metadata."}
    # Safe-formula statistical operations all produce descriptive summaries.
    # CORE owns source-field applicability and units; an unknown field mapping
    # means this is an ordinary nonstatistical mathematical operation.
    if {!$unmapped&&[dict exists $mapping $field]} {
        set context [dict create y_unit [dict get [lindex $args 0] unit]]
        foreach argument [dict get $meta arguments] item $args {
            if {$argument in {x y}&&$item ne {}} {dict set context ${argument}_unit [dict get $item unit]}
        }
        set provenance [dict create producer viewer.scientific_worksheet]
        set lineage {};foreach item $args {foreach record [_sourceLineage $item] {dict set lineage $record 1}}
        if {[dict size $lineage]} {dict set provenance source_variables [dict keys $lineage]}
        set statistics [::GX::StatisticsV1::fromNumeric math.numeric.summary $id $raw $context {} $provenance]
        set item [dict get [::GX::StatisticsV1::numericFields $statistics] $field]
        set value NaN
        if {[dict get $item status] eq "value"} {set value [dict get $item value]}
        set kind [expr {[llength $value]>1?"vector":"scalar"}]
        return [dict merge [_value $value [dict get $item unit_text] $kind] [dict create statistical_result $statistics statistical_field $field]]
    }
    set value [dict get $raw $field]
    set kind [expr {[llength $value] > 1 ? "vector" : "scalar"}]
    set unitBehavior [dict get $meta unit_behavior]
    set unit ""
    if {$unitBehavior in {preserve preserve_y}} {set unit [dict get [lindex $args end] unit]}
    if {$unitBehavior eq "compatible"} {
        set unit [dict get [lindex $args 0] unit]
        if {[dict get [lindex $args 1] unit] ne $unit} {error "Function operands have incompatible units."}
    }
    return [_value $value $unit $kind]
}
proc ::GX::ScientificWorksheet::_columnMajor {values shape} {
    # Workbook cells and spills are row-major; public provider arrays are
    # column-major. Convert at this one producer/consumer boundary only.
    if {[llength $shape]!=2} {error {Worksheet matrix shape requires two dimensions}}
    lassign $shape rows cols
    foreach size $shape {if {![string is integer -strict $size]||$size<1} {error {Worksheet matrix dimensions must be positive integers}}}
    if {[llength $values]!=$rows*$cols} {error {Worksheet matrix shape differs from its cell count}}
    if {$rows==1||$cols==1} {return $values}
    set result {}
    for {set col 0} {$col<$cols} {incr col} {for {set row 0} {$row<$rows} {incr row} {lappend result [lindex $values [expr {$row*$cols+$col}]]}}
    return $result
}
proc ::GX::ScientificWorksheet::_typed {item} {
    set kind [dict get $item kind]; set value [dict get $item value]
    if {$kind eq "text"} {return [::GX::ScientificTransportv1::text $value]}
    if {$kind eq "scalar"} {return [::GX::ScientificTransportv1::array {1 1} [list $value]]}
    if {$kind eq "vector"} {return [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]}
    if {$kind eq "matrix"} {return [::GX::ScientificTransportv1::array [dict get $item shape] [_columnMajor $value [dict get $item shape]]]}
    if {$kind eq "complex"} {
        set data [dict get $item value]
        return [::GX::ScientificTransportv1::array [dict get $data shape] [_columnMajor [dict get $data real] [dict get $data shape]] [_columnMajor [dict get $data imaginary] [dict get $data shape]]]
    }
    if {$kind eq "empty"} {return [::GX::ScientificTransportv1::empty]}
    if {$kind eq "record"} {
        set fields [dict create]
        dict for {key nested} $value {dict set fields $key [_typed $nested]}
        return [::GX::ScientificTransportv1::struct $fields]
    }
    error "Scientific API argument must be a scalar, vector or string."
}
proc ::GX::ScientificWorksheet::_call {name args} {
    if {$name eq "empty"} {if {[llength $args]} {error "empty() takes no arguments."}; return [_value "" "" empty]}
    if {$name eq "record"} {
        if {[llength $args] % 2} {error "record requires name/value argument pairs."}
        set fields [dict create]
        foreach {key value} $args {
            if {[dict get $key kind] ne "text" || ![regexp {^[A-Za-z][A-Za-z0-9_]*$} [dict get $key value]]} {error "Record field names must be strings with identifier names."}
            dict set fields [dict get $key value] $value
        }
        return [_value $fields "" record]
    }
    if {$name eq "vector"} {
        set values {};set units {}
        foreach item $args {
            if {[dict get $item kind] ne "scalar"} {error "vector requires scalar arguments."}
            lappend values [dict get $item value]
            set unit [dict get $item unit];if {$unit ni $units} {lappend units $unit}
        }
        set item [_value $values [expr {[llength $units]==1?[lindex $units 0]:{}}] vector]
        if {[llength $units]>1} {dict set item mixed_units 1}
        return $item
    }
    if {$name eq "matrix"} {
        if {[llength $args] != 3} {error "matrix(values, rows, columns) requires three arguments."}
        lassign $args source rows columns
        set rows [dict get $rows value]; set columns [dict get $columns value]
        if {![string is integer -strict $rows] || ![string is integer -strict $columns] || $rows < 1 || $columns < 1 || $rows*$columns != [llength [dict get $source value]]} {error "Matrix dimensions do not match the range length."}
        set result [_value [dict get $source value] [dict get $source unit] matrix]
        dict set result shape [list $rows $columns]
        if {[dict exists $source mixed_units]} {dict set result mixed_units [dict get $source mixed_units]}
        return $result
    }
    if {$name eq "complex"} {
        if {[llength $args] != 2} {error "complex(real, imaginary) requires two arguments."}
        lassign $args real imaginary
        if {[dict get $real kind] ne [dict get $imaginary kind] || [dict get $real kind] ni {scalar vector matrix}} {error "Complex real and imaginary parts must have matching numeric shape."}
        if {[dict get $real unit] ne [dict get $imaginary unit]||([dict exists $real mixed_units]&&[dict get $real mixed_units])||([dict exists $imaginary mixed_units]&&[dict get $imaginary mixed_units])} {error {Complex real and imaginary parts must have matching physical units; convert explicitly first.}}
        if {[dict get $real kind] eq "matrix"} {
            if {[dict get $real shape] ne [dict get $imaginary shape]} {error "Complex matrix dimensions differ."}
            set shape [dict get $real shape]
        } elseif {[dict get $real kind] eq "vector"} {
            if {[llength [dict get $real value]] != [llength [dict get $imaginary value]]} {error "Complex vector lengths differ."}
            set shape [list [llength [dict get $real value]] 1]
        } else {set shape {1 1}}
        return [_value [dict create shape $shape real [dict get $real value] imaginary [dict get $imaginary value]] [dict get $real unit] complex]
    }
    if {$name eq "field"} {
        if {[llength $args] != 2 || [dict get [lindex $args 0] kind] ne "struct" || [dict get [lindex $args 1] kind] ne "text"} {error "field(result, \"field_name\") requires a public API result and field name."}
        set field [dict get [lindex $args 1] value]; set fields [dict get [lindex $args 0] value]
        if {![dict exists $fields $field]} {error "Result field '$field' is unavailable; fields: [join [dict keys $fields] {, }]."}
        set value [dict get $fields $field]
        return [_value $value "" [expr {[llength $value] > 1 ? "vector" : "scalar"}]]
    }
    set catalog [functionCatalog $name]
    if {![dict exists $catalog $name]} {error "Unknown or unsafe function '$name'. Browse Worksheet functions for supported operations."}
    set meta [dict get $catalog $name]; set id [dict get $meta id]; set provider [dict get $meta provider_id]
    if {[dict exists $meta operation_kind]&&[dict get $meta operation_kind] eq "metadata"} {error {This operation describes API result contracts and does not calculate Worksheet cell values.}}
    if {$provider eq "math.numeric"} {return [_numericResult $id $meta {*}$args]}
    if {[llength $args] > 4} {error "Scientific API operation accepts at most three data arguments and one options record."}
    set options [::GX::ScientificTransportv1::struct [dict create]]
    if {[llength $args] == 4} {
        if {[dict get [lindex $args end] kind] ne "record"} {error "Fourth scientific API argument must be a record of options."}
        set options [_typed [lindex $args end]]
        set args [lrange $args 0 2]
    }
    set typed [lmap item $args {_typed $item}]
    while {[llength $typed] < 3} {lappend typed [::GX::ScientificTransportv1::empty]}
    lassign [split $id .] family action
    switch -- $provider {
        math.signal {set namespace SignalAPIv1}
        math.rf_network {set namespace RFNetworkAPIv1}
        math.magnetics {set namespace MagneticsAPIv1}
        default {error "Unsupported scientific provider."}
    }
    set raw [::GX::${namespace}::call $family $action {*}$typed $options]
    return [_value $raw "" struct]
}
proc ::GX::ScientificWorksheet::functionHelp {name} {
    set catalog [functionCatalog $name]
    if {![dict exists $catalog $name]} {error "Unknown Worksheet function '$name'."}
    set meta [dict get $catalog $name]
    set out "$name — [dict get $meta api_id]\n[dict get $meta summary]\n"
    if {[dict exists $meta arguments]} {append out "Arguments: [join [dict get $meta arguments] {, }]\nShape: [dict get $meta shape_semantics]\nUnits: [dict get $meta unit_behavior]\n"} else {append out "Operands: [dict get $meta operands]\nShapes: [dict get $meta input_shapes]\nUnits: [dict get $meta units]\n"}
    return $out
}
proc ::GX::ScientificWorksheet::bindDataset {book datasetId mappings {firstRow 1} {limit 20000} {selectionId ""}} {
    set session [_requireSession]
    if {![string is integer -strict $firstRow] || $firstRow < 1 || ![string is integer -strict $limit] || $limit < 1 || $limit > 20000} {error "Import range must start at row 1 or later and contain at most 20000 rows."}
    set ids [dict values $mappings]
    if {![llength $ids] || [llength $ids] > 26} {error "Choose 1–26 source variables."}
    set schema [dict create]
    foreach v [::GX::datasetVariableSchema $datasetId] {dict set schema [dict get $v variable_id] $v}
    dict for {col id} $mappings {
        if {![regexp {^[A-Z]{1,2}$} $col] || ![dict exists $schema $id]} {error "Invalid column '$col' or Dataset variable '$id'."}
        if {[dict get [dict get $schema $id] value_kind] ne "number"} {error "Worksheet import requires numeric variables."}
    }
    set selected [dict create]
    if {$selectionId ne ""} {
        set selection [::GX::sessionInspectionSelection $selectionId $session]
        if {[dict get $selection source_dataset_id] ne $datasetId} {error "Selection belongs to another Dataset."}
        set xId [dict get $selection x_variable_id]
        if {![dict exists $schema $xId]} {error "Selection X variable is unavailable."}
        set ids [lsort -unique [concat $ids [list $xId]]]
        if {[dict get $selection type] eq "rectangle"} {set yId [dict get $selection y_variable_id]; lappend ids $yId} else {set yId ""}
        if {[dict get $selection type] ni {x_range rectangle}} {error "Only X range and rectangle Selections can bind into Worksheet."}
    }
    set stream [::GX::tableStreamOpenDataset $session $datasetId $ids 4096]
    set imported 0
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]; set values [dict get $chunk values]
            for {set i 0} {$i < [dict get $chunk nrows]} {incr i} {
                set sourceRow [expr {[dict get $chunk offset]+$i}]
                if {$selectionId ne ""} {
                    set x [lindex [dict get $values $xId] $i]
                    if {![string is double -strict $x] || $x < [dict get $selection x_min] || $x > [dict get $selection x_max]} continue
                    if {$yId ne ""} {set y [lindex [dict get $values $yId] $i]; if {![string is double -strict $y] || $y < [dict get $selection y_min] || $y > [dict get $selection y_max]} continue}
                }
                if {$imported >= $limit} {break}
                set targetRow [expr {$firstRow+$imported}]
                dict for {col id} $mappings {
                    set raw [lindex [dict get $values $id] $i]
                    if {![string is double -strict $raw]} continue
                    set address "${col}$targetRow"; set variable [dict get $schema $id]
                    set lineage [dict create dataset_id $datasetId variable_id $id source_row $sourceRow selection_id $selectionId]
                    dict set book cells $address [dict create source $raw kind dataset unit [dict get $variable unit] lineage $lineage]
                    dict set book bindings $col [dict create dataset_id $datasetId variable_id $id unit [dict get $variable unit] selection_id $selectionId first_row $firstRow row_count [expr {$imported+1}]]
                    dict set book column_metadata $col [dict create name $id unit [dict get $variable unit]]
                    if {![dict exists $book columns $id]} {dict set book columns $id $col}
                }
                incr imported
            }
            if {$imported >= $limit || [dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    dict incr book revision
    variable cache; variable dirty
    set key [_key $book]
    if {[dict exists $cache $key]} {dict unset cache $key}
    if {[dict exists $dirty $key]} {dict unset dirty $key}
    return [list $book $imported]
}
proc ::GX::ScientificWorksheet::save {book} {
    _requireSession
    set id [dict get $book document_id]
    if {$id eq ""} {
        set meta [::GX::interactiveDocumentCreate viewer.scientific_worksheet scientific_worksheet scientific_worksheet.v1 1 $book]
        dict set book document_id [dict get $meta id]
        ::GX::interactiveDocumentUpdate [dict get $meta id] $book
    } else {::GX::interactiveDocumentUpdate $id $book}
    return $book
}
proc ::GX::ScientificWorksheet::listDocuments {} {return [::GX::interactiveDocumentList viewer.scientific_worksheet scientific_worksheet]}
proc ::GX::ScientificWorksheet::load {id} {
    set record [::GX::interactiveDocumentRead $id]
    if {[dict get $record format] ne "scientific_worksheet.v1"} {error "Unsupported Worksheet document format."}
    set book [dict get $record payload]
    if {[catch {dict get $book format} format] || $format ne "scientific_worksheet.v1"} {error "Invalid Worksheet document payload."}
    dict set book document_id $id
    set key [_key $book]
    variable cache; variable dirty
    if {[dict exists $cache $key]} {dict unset cache $key}
    if {[dict exists $dirty $key]} {dict unset dirty $key}
    return $book
}
proc ::GX::ScientificWorksheet::columnValues {book column first last} {
    set column [string toupper $column]; _columnNumber $column
    if {![string is integer -strict $first] || ![string is integer -strict $last] || $first < 1 || $last < $first || $last-$first >= 20000} {error "Select a valid range of at most 20000 rows."}
    set values {}; set unit ""; set sources {}; set formulas {};set statistics {}
    for {set row $first} {$row <= $last} {incr row} {
        set address "$column$row"
        set item [value $book $address]
        if {[dict get $item kind] eq "blank"} {error "Selected column has an empty cell at $address."}
        if {[dict get $item kind] ne "scalar" || ![string is double -strict [dict get $item value]]} {error "Selected column requires scalar numeric cells: $address."}
        if {$row == $first} {set unit [dict get $item unit]} elseif {[dict get $item unit] ne $unit} {error "Selected column contains incompatible units at $address."}
        lappend values [dict get $item value]
        if {[llength [_statisticalSources $item]]} {dict set statistics $address [_statisticalSources $item]}
        foreach record [_sourceLineage $item] {if {$record ni $sources} {lappend sources $record}}
        if {[dict exists $book cells $address]} {
            set cell [dict get $book cells $address]
            if {[dict get $cell kind] eq "formula"} {lappend formulas "$address=[dict get $cell source]"}
        } elseif {[dict exists $item anchor]} {lappend formulas "$address=spill([dict get $item anchor])"}
    }
    return [dict create values $values unit $unit sources $sources formulas $formulas statistical_sources $statistics]
}
proc ::GX::ScientificWorksheet::publish {book mappings first last datasetId {displayName ""}} {
    set session [_requireSession]
    if {[dict get $book document_id] eq ""} {error "Save the Worksheet before publication so its identity is retained."}
    set datasetId [::GX::datasetPublicationV2ValidateId dataset $datasetId]
    if {![llength $mappings]} {error "Select at least one column."}
    set values [dict create]; set units [dict create]; set sources [dict create]; set bindings [dict create]; set formulaText {};set statisticalResults {};set statisticalLinks {};set distinctStatistics {}
    dict for {outputId col} $mappings {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $outputId]} {error "Invalid output variable ID '$outputId'."}
        set selected [columnValues $book $col $first $last]
        dict set values $outputId [dict get $selected values]
        dict set units $outputId [dict get $selected unit]
        foreach lineage [dict get $selected sources] {dict set sources [dict get $lineage dataset_id] 1; dict set bindings "[dict get $lineage dataset_id]:[dict get $lineage variable_id]" 1}
        set formulaText [concat $formulaText [dict get $selected formulas]]
        dict for {address results} [dict get $selected statistical_sources] {
            foreach result $results {
                set index [lsearch -exact $distinctStatistics $result]
                if {$index<0} {set index [llength $distinctStatistics];lappend distinctStatistics $result}
                set name worksheet_stat_$index
                dict set statisticalResults $name $result
                if {![dict exists $statisticalLinks $address]||$name ni [dict get $statisticalLinks $address]} {dict lappend statisticalLinks $address $name}
            }
        }
    }
    set provenance "Scientific Worksheet [dict get $book document_id] revision [dict get $book revision]; rows $first:$last; columns $mappings; formulas [join $formulaText {; }]"
    set definition [dict create dataset_id $datasetId contract table.generic storage csv producer_version [::GX::moduleField viewer.scientific_worksheet version {}] source "Scientific Worksheet" provenance $provenance notes $displayName source_dataset_ids [dict keys $sources] source_variable_ids [dict keys $bindings]]
    set statisticalMetadata {}
    if {[dict size $statisticalResults]} {
        set statisticalMetadata [::GX::StatisticsV1::publicationMetadata $statisticalResults]
        dict set statisticalMetadata worksheet.statistical_contributions $statisticalLinks
        dict set definition structured_metadata $statisticalMetadata
    }
    set plan [::GX::datasetPublicationV2Prepare $session viewer.scientific_worksheet $definition]
    set writer ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        set index 0
        dict for {outputId col} $mappings {
            set role [expr {$index == 0 ? "coordinate" : "data"}]
            ::GX::datasetPublicationV2DeclareVariable $writer $outputId [dict create name $outputId unit [dict get $units $outputId] semantic_role "" dtype float64 rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
            incr index
        }
        ::GX::datasetPublicationV2Append $writer row $values
        set result [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}; return -options $options $message}
    ::GX::datasetMetadataWrite $session $datasetId [dict merge $statisticalMetadata [dict create dataset.display_name $displayName worksheet.document_id [dict get $book document_id] worksheet.revision [dict get $book revision] worksheet.source_rows "$first:$last" worksheet.columns $mappings worksheet.formulas [join $formulaText {; }] worksheet.source_dataset_ids [join [dict keys $sources] {;}] worksheet.source_variable_ids [join [dict keys $bindings] {;}]]]
    return $result
}
proc ::GX::ScientificWorksheet::preview {book xColumn yColumns first last destinationDir {zColumn ""}} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    file mkdir $destinationDir
    set x [dict get [columnValues $book $xColumn $first $last] values]
    if {$zColumn ne ""} {
        if {[llength $yColumns] != 1} {error "3-D preview requires one Y column."}
        set y [dict get [columnValues $book [lindex $yColumns 0] $first $last] values]
        set z [dict get [columnValues $book $zColumn $first $last] values]
        return [::GX::PlotDatasetAPIv3::renderTransientCurve3D $x $y $z "Worksheet 3-D preview" $destinationDir]
    }
    set series {}
    foreach yColumn $yColumns {
        set item [columnValues $book $yColumn $first $last]
        lappend series [dict create label "Worksheet $yColumn" values [dict get $item values] unit [dict get $item unit]]
    }
    if {![llength $series]} {error "Choose at least one Y column."}
    set xUnit [dict get [columnValues $book $xColumn $first $last] unit]
    return [::GX::PlotDatasetAPIv3::renderTransientCurves2D $x $series "Scientific Worksheet preview" $destinationDir $xUnit]
}
proc ::GX::ScientificWorksheet::previewOnArtifact {book artifact xColumn yColumns first last destinationDir} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    file mkdir $destinationDir
    set x [dict get [columnValues $book $xColumn $first $last] values]
    set results {}; set index 0
    foreach yColumn $yColumns {
        set y [dict get [columnValues $book $yColumn $first $last] values]
        set path [file join $destinationDir "y[incr index]"]
        lappend results [::GX::PlotDatasetAPIv3::renderTransientOverlay $artifact $x $y "Worksheet $yColumn" $path]
    }
    return $results
}
proc ::GX::ScientificWorksheet::retainPlot {book mappings first last datasetId xId yIds {zId ""}} {
    publish $book $mappings $first $last $datasetId "Worksheet plot source"
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    if {$zId ne ""} {
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_3d graph_id plot.dataset.xyz dataset_id $datasetId x_variable_id $xId y_variable_id [lindex $yIds 0] z_variable_id $zId title "Worksheet 3-D plot" config [dict create plot_type line3]]
    } else {
        set series {}; set index 0
        foreach yId $yIds {lappend series [dict create id "y[incr index]" dataset_id $datasetId x_variable_id $xId y_variable_id $yId axis left kind line label $yId style [dict create line_width 2.0]]}
        set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy title "Worksheet plot" defaults [dict create style [dict create]] panels [list [dict create id main title "Worksheet" axes [dict create x [dict create label $xId scale linear] y_left [dict create label Y scale linear]] series $series annotations {}]] output [dict create]]
    }
    set ref [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
    ::GX::PlotDatasetAPIv3::render $ref
    return $ref
}
proc ::GX::ScientificWorksheet::_uiError {w message} {
    variable ui
    set ui($w,status) $message
    tk_messageBox -icon error -type ok -title "Scientific Worksheet" -message $message -parent $w
}
proc ::GX::ScientificWorksheet::_uiSelectAt {w x y} {
    variable ui
    set table $w.grid.table
    set row [$table identify row $y]
    set column [$table identify column $x]
    if {$row eq "" || $column eq ""} return
    set index [string range $column 1 end]
    if {$index < 1} return
    set letters [lindex [dict get $ui($w,book) presentation display_columns] [expr {$index-2}]]
    set ui($w,active) "$letters$row"
    _uiSelect $w
}
proc ::GX::ScientificWorksheet::_uiSelect {w} {
    variable ui
    set address $ui($w,active)
    if {[dict exists $ui($w,book) cells $address]} {
        set ui($w,formula) [dict get $ui($w,book) cells $address source]
    } else {
        set ui($w,formula) ""
    }
    set ui($w,status) "Active cell $address"
    if {[dict exists $ui($w,book) cells $address lineage]} {append ui($w,status) " — [dict get $ui($w,book) cells $address lineage]"}
}
proc ::GX::ScientificWorksheet::_uiSelectRow {w} {
    variable ui
    set selected [$w.grid.table selection]
    if {![llength $selected]} return
    regexp {^([A-Z]+)} $ui($w,active) unused column
    set ui($w,active) "$column[lindex $selected 0]"
    _uiSelect $w
}
proc ::GX::ScientificWorksheet::_uiCommit {w} {
    variable ui
    if {$ui($w,active) eq ""} return
    if {[catch {set ui($w,book) [setCell $ui($w,book) $ui($w,active) $ui($w,formula)]; recalculate $ui($w,book); _uiRefresh $w} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiRefresh {w} {
    variable ui
    set table $w.grid.table
    $table delete [$table children {}]
    set first $ui($w,first_row); set last [expr {$first+199}]
    set displayedColumns [dict get $ui($w,book) presentation display_columns]
    foreach col $displayedColumns {
        set heading $col
        if {[dict exists $ui($w,book) column_metadata $col]} {
            set meta [dict get $ui($w,book) column_metadata $col]
            if {[dict get $meta name] ne ""} {append heading " — [dict get $meta name]"}
            if {[dict get $meta unit] ne ""} {append heading " \[[dict get $meta unit]\]"}
        }
        $table heading $col -text $heading
    }
    for {set row $first} {$row <= $last} {incr row} {
        set values [list $row]
        foreach col $displayedColumns {
            set address "$col$row"; set display ""
            if {[dict exists $ui($w,book) cells $address]} {
                if {[catch {set item [value $ui($w,book) $address]} message]} {set display "#ERROR"} else {
                    set raw [dict get $item value]
                    if {[dict get $item kind] eq "missing"} {
                        set display "Missing"
                    } elseif {[dict get $item kind] eq "scalar" && [string is double -strict $raw] &&
                        ![catch {format %.8g $raw} formatted]} {
                        set display $formatted
                    } else {set display [string range $raw 0 40]}
                }
            }
            lappend values $display
        }
        $table insert {} end -id $row -values $values
    }
    set ui($w,status) "Worksheet [dict get $ui($w,book) name], revision [dict get $ui($w,book) revision]. Visible rows $first–$last."
}
proc ::GX::ScientificWorksheet::_uiPage {w delta} {
    variable ui
    set ui($w,first_row) [expr {max(1,$ui($w,first_row)+$delta)}]
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiMove {w rowDelta colDelta} {
    variable ui
    lassign [_parts $ui($w,active)] col row
    set col [expr {max(1,min(12,$col+$colDelta))}]
    set row [expr {max(1,$row+$rowDelta)}]
    set ui($w,active) "[_columnName $col]$row"
    if {$row < $ui($w,first_row) || $row >= $ui($w,first_row)+200} {
        set ui($w,first_row) [expr {(($row-1)/200)*200+1}]
        _uiRefresh $w
    }
    $w.grid.table selection set $row
    $w.grid.table see $row
    _uiSelect $w
}
proc ::GX::ScientificWorksheet::_uiNamesDialog {w} {
    variable ui
    set d $w.names; catch {destroy $d}; toplevel $d; wm title $d "Worksheet columns and ranges"
    foreach {key label default} {column {Column coordinate} A name {Column name} {} unit {Column unit (explicit assignment)} {} range_name {Range name} {} range_start {First cell} A1 range_end {Last cell} A2} {
        set ui($w,names_$key) $default
        ttk::label $d.l_$key -text $label; ttk::entry $d.e_$key -textvariable ::GX::ScientificWorksheet::ui($w,names_$key)
        pack $d.l_$key $d.e_$key -anchor w -fill x
    }
    ttk::button $d.column -text "Apply column name/unit" -command [list ::GX::ScientificWorksheet::_uiSetColumn $w]
    ttk::button $d.range -text "Define range" -command [list ::GX::ScientificWorksheet::_uiDefineRange $w]
    pack $d.column $d.range -side left -padx 4 -pady 5
}
proc ::GX::ScientificWorksheet::_uiSetColumn {w} {
    variable ui
    if {[catch {set ui($w,book) [setColumn $ui($w,book) $ui($w,names_column) $ui($w,names_name) $ui($w,names_unit)]; _uiRefresh $w} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiDefineRange {w} {
    variable ui
    if {[catch {set ui($w,book) [defineRange $ui($w,book) $ui($w,names_range_name) $ui($w,names_range_start) $ui($w,names_range_end)]; _uiRefresh $w} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiCopy {w} {
    variable ui
    set selected [$w.grid.table selection]
    if {![llength $selected]} return
    set text ""
    foreach row $selected {
        set line {}
        foreach col [dict get $ui($w,book) presentation display_columns] {
            set address "$col$row"
            lappend line [expr {[dict exists $ui($w,book) cells $address] ? [dict get $ui($w,book) cells $address source] : ""}]
        }
        append text "[join $line \t]\n"
    }
    clipboard clear -displayof $w; clipboard append -displayof $w $text
}
proc ::GX::ScientificWorksheet::_uiPaste {w} {
    variable ui
    if {$ui($w,active) eq ""} return
    if {[catch {set text [clipboard get -displayof $w]} message]} {_uiError $w $message; return}
    if {[string length $text] > 2000000} {_uiError $w "Paste exceeds 2 MB."; return}
    lassign [_parts $ui($w,active)] c0 r0
    set book $ui($w,book); set r $r0
    foreach line [split [string trimright $text "\r\n"] "\n"] {
        set c $c0
        foreach cell [split [string trimright $line "\r"] "\t"] {
            if {$c > 702} {error "Paste exceeds ZZ column."}
            set book [setCell $book "[_columnName $c]$r" $cell]
            incr c
        }
        incr r
    }
    set ui($w,book) $book
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiSave {w} {
    variable ui
    if {[catch {set ui($w,book) [save $ui($w,book)]; set ui($w,status) "Saved document [dict get $ui($w,book) document_id]."} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiLoad {w} {
    variable ui
    set ids [lmap item [listDocuments] {dict get $item id}]
    if {![llength $ids]} {_uiError $w "This Session has no saved Worksheets."; return}
    set dialog $w.load; catch {destroy $dialog}; toplevel $dialog; wm title $dialog "Open Worksheet"
    listbox $dialog.list -listvariable ::GX::ScientificWorksheet::ui($w,documents)
    set ui($w,documents) $ids
    pack $dialog.list -fill both -expand 1
    ttk::button $dialog.open -text Open -command [list ::GX::ScientificWorksheet::_uiLoadSelected $w $dialog]
    pack $dialog.open
}
proc ::GX::ScientificWorksheet::_uiLoadSelected {w dialog} {
    variable ui
    set index [lindex [$dialog.list curselection] 0]
    if {$index eq ""} return
    if {[catch {set ui($w,book) [load [lindex $ui($w,documents) $index]]; _uiRefresh $w; destroy $dialog} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiRecalculate {w all} {
    variable ui
    set results [recalculate $ui($w,book) $all]
    set errors 0
    dict for {address item} $results {if {[dict exists $item error]} {incr errors}}
    _uiRefresh $w
    set ui($w,status) "Recalculated [dict size $results] cells; $errors errors. Select a cell to inspect its error."
}
proc ::GX::ScientificWorksheet::_cellInspectionText {book address} {
    set result [value $book $address]
    set display [dict get $result value]
    if {[string length $display]>2000} {set display "[string range $display 0 1999]… (display shortened)"}
    set unit [dict get $result unit];if {$unit eq ""} {set unit {undeclared}}
    set detail "$address\nValue: $display\nUnit: $unit"
    if {[dict exists $result statistical_result]} {
        set statistics [dict get $result statistical_result]
        set field [dict get $result statistical_field]
        set window [expr {[dict exists $result statistical_window]?[dict get $result statistical_window]:{}}]
        if {[dict exists $result statistical_data_field]} {
            set contract [dict get [::GX::StatisticsV1::numericDataFields $statistics] fields $field]
            append detail "\n\n[dict get $contract label]\n[dict get $contract definition]"
            if {[dict get $result kind] eq "scalar"} {
                set index [expr {[dict exists $result statistical_element]?[dict get $result statistical_element]:0}]
                set start [expr {$window eq {}?0:[dict get $window start]}]
                append detail "\nObservation row: [expr {$start+$index+1}]"
                if {[dict exists $result statistical_data_statuses]&&[lindex [dict get $result statistical_data_statuses] $index] ne "value"} {
                    append detail "\n[lindex [dict get $result statistical_data_statuses] $index] — [lindex [dict get $result statistical_data_reasons] $index]"
                }
                if {[dict exists $contract identity_ids]} {append detail "\nIdentity: [lindex [dict get $contract identity_ids] [expr {int([dict get $result value])-1}]]"}
            }
        } elseif {[dict exists $result statistical_element]} {
            set cells [dict get [_statisticalProjection $statistics $field $window] cells]
            set cell [lindex $cells [dict get $result statistical_element]]
            append detail "\n\n[dict get $cell label]: "
            if {[dict get $cell status] eq "value"} {append detail "[format %.9g [dict get $cell value]] ([dict get $cell unit_text])"} else {append detail "[dict get $cell status] — [dict get $cell reason]"}
            foreach key {element_id row_id column_id probability} {if {[dict exists $cell $key]} {append detail "\n[string totitle [string map {_ { }} $key]]: [dict get $cell $key]"}}
            if {[dict exists $cell definition]} {append detail "\n[dict get $cell definition]"}
        } elseif {[dict get $statistics schema] eq "gxtxt.statistical_result.resource_binding.v1"} {
            set cells [dict get [_statisticalProjection $statistics $field $window] cells]
            foreach cell [lrange $cells 0 19] {
                append detail "\n\n[dict get $cell label]"
                if {[dict exists $cell row_id]} {append detail " · [dict get $cell row_id]"}
                if {[dict get $cell status] eq "value"} {append detail ": [format %.9g [dict get $cell value]] ([dict get $cell unit_text])"} else {append detail ": [dict get $cell status] — [dict get $cell reason]"}
            }
            if {[llength $cells]>20} {append detail "\nShowing the first 20 selected result rows."}
        } elseif {[dict get $statistics schema] eq "gxtxt.statistical_result.table.v1"} {
            set quantity [dict get [::GX::StatisticsV1::numericFieldMap [dict get $statistics provenance operation]] $field]
            append detail "\n\n[::GX::StatisticsV1::tableReport $statistics [lrange [dict get $statistics row_ids] 0 19] [list $quantity]]"
            if {[dict get $statistics row_count]>20} {append detail "\nShowing the first 20 statistical rows."}
        } else {
            set quantity [dict get [::GX::StatisticsV1::numericFields $statistics] $field quantity]
            append detail "\n\n[::GX::StatisticsV1::report $statistics [list $quantity]]"
        }
    }
    set contributors [_statisticalSources $result]
    if {[dict exists $result statistical_result]} {
        set at [lsearch -exact $contributors [dict get $result statistical_result]]
        if {$at>=0} {set contributors [lreplace $contributors $at $at]}
    }
    if {[llength $contributors]} {
        append detail "\n\nStatistical inputs used by this cell:"
        foreach statistics $contributors {
            if {[dict get $statistics schema] eq "gxtxt.statistical_result.resource_binding.v1"} {append detail "\n\n[::GX::StatisticsV1::report $statistics]";continue}
            if {[dict get $statistics schema] eq "gxtxt.statistical_result.table.v1"} {
                set requested [lsort -unique [dict values [::GX::StatisticsV1::numericFieldMap [dict get $statistics provenance operation]]]]
                set report [::GX::StatisticsV1::tableReport $statistics [lrange [dict get $statistics row_ids] 0 4] $requested]
                if {[dict get $statistics row_count]>5} {append report "\nShowing the first 5 contributing rows."}
                if {[string length $report]>4000} {set report "[string range $report 0 3999]… (display shortened)"}
                append detail "\n\n$report";continue
            }
            set requested {}
            dict for {field item} [::GX::StatisticsV1::numericFields $statistics] {
                if {[dict get $item status] in {value undefined error}} {lappend requested [dict get $item quantity]}
            }
            set report [::GX::StatisticsV1::report $statistics [lsort -unique $requested]]
            if {[string length $report]>4000} {set report "[string range $report 0 3999]… (display shortened)"}
            append detail "\n\n$report"
        }
    }
    foreach source [_sourceLineage $result] {
        append detail "\nSource Dataset: [dict get $source dataset_id]; Variable: [dict get $source variable_id]"
    }
    if {[dict exists $result lineage source_row]} {append detail "\nSource row: [dict get $result lineage source_row]"}
    return $detail
}
proc ::GX::ScientificWorksheet::_uiInspect {w} {
    variable ui
    if {$ui($w,active) eq ""} return
    set address $ui($w,active)
    if {[catch {set detail [_cellInspectionText $ui($w,book) $address]} message]} {set detail "Error in $address: $message"}
    set d $w.inspect;catch {destroy $d};toplevel $d
    wm title $d "Worksheet cell $address";wm transient $d $w
    text $d.detail -wrap word -width 76 -height 18 -padx 12 -pady 12 -yscrollcommand [list $d.scroll set]
    ttk::scrollbar $d.scroll -orient vertical -command [list $d.detail yview]
    ttk::button $d.close -text Close -command [list destroy $d]
    $d.detail insert 1.0 $detail;$d.detail configure -state disabled
    grid $d.detail $d.scroll -sticky nsew;grid $d.close -columnspan 2 -sticky e -padx 12 -pady 8
    grid rowconfigure $d 0 -weight 1;grid columnconfigure $d 0 -weight 1
}
proc ::GX::ScientificWorksheet::_uiFunctionBrowser {w} {
    variable ui
    set d $w.functions; catch {destroy $d}; toplevel $d; wm title $d "Worksheet functions"
    ttk::entry $d.search -textvariable ::GX::ScientificWorksheet::ui($w,function_query)
    ttk::treeview $d.tree -columns {api summary} -show {tree headings} -height 18
    $d.tree heading #0 -text Function; $d.tree heading api -text {Public API}; $d.tree heading summary -text Description
    $d.tree column #0 -width 260; $d.tree column api -width 180; $d.tree column summary -width 400
    text $d.help -wrap word -height 7 -state disabled
    ttk::button $d.insert -text "Insert into formula" -command [list ::GX::ScientificWorksheet::_uiInsertFunction $w $d]
    pack $d.search -fill x; pack $d.tree -fill both -expand 1; pack $d.help -fill x; pack $d.insert -anchor e
    bind $d.search <KeyRelease> [list ::GX::ScientificWorksheet::_uiFunctionSearch $w $d]
    bind $d.tree <<TreeviewSelect>> [list ::GX::ScientificWorksheet::_uiFunctionHelp $w $d]
    _uiFunctionSearch $w $d
}
proc ::GX::ScientificWorksheet::_uiFunctionSearch {w d} {
    variable ui
    $d.tree delete [$d.tree children {}]
    dict for {name meta} [functionCatalog $ui($w,function_query)] {$d.tree insert {} end -id $name -text $name -values [list [dict get $meta api_id] [dict get $meta summary]]}
}
proc ::GX::ScientificWorksheet::_uiFunctionHelp {w d} {
    set selected [$d.tree selection]
    if {![llength $selected]} return
    $d.help configure -state normal; $d.help delete 1.0 end; $d.help insert 1.0 [functionHelp [lindex $selected 0]]; $d.help configure -state disabled
}
proc ::GX::ScientificWorksheet::_uiInsertFunction {w d} {
    variable ui
    set selected [$d.tree selection]; if {![llength $selected]} return
    append ui($w,formula) "[lindex $selected 0]("
    focus $w.formula.entry
}
proc ::GX::ScientificWorksheet::_uiAutocomplete {w} {
    variable ui
    set text $ui($w,formula)
    if {![regexp {([A-Za-z_][A-Za-z0-9_.]*)$} $text unused prefix]} return
    set matches [dict keys [functionCatalog $prefix]]
    if {[llength $matches] == 1} {set ui($w,formula) "[string range $text 0 end-[string length $prefix]][lindex $matches 0]("}
}
proc ::GX::ScientificWorksheet::_uiImportDialog {w} {
    variable ui
    set d $w.import; catch {destroy $d}; toplevel $d; wm title $d "Import canonical Dataset columns"
    foreach {key label} {dataset Dataset mappings {Column=variable pairs, e.g. A=v_time B=v_signal} first {First Worksheet row} limit {Maximum rows (≤20000)} selection {Dataset Selection ID (optional)}} {
        ttk::label $d.l_$key -text $label; ttk::entry $d.e_$key -textvariable ::GX::ScientificWorksheet::ui($w,import_$key) -width 45; pack $d.l_$key $d.e_$key -anchor w -fill x
    }
    set ui($w,import_first) 1; set ui($w,import_limit) 2000; set ui($w,import_selection) ""
    ttk::combobox $d.datasets -values [::GX::sessionInspectionDatasetIds] -textvariable ::GX::ScientificWorksheet::ui($w,import_dataset) -state readonly
    pack $d.datasets -fill x
    ttk::button $d.go -text "Bind values" -command [list ::GX::ScientificWorksheet::_uiImport $w $d]
    pack $d.go
}
proc ::GX::ScientificWorksheet::_uiImport {w d} {
    variable ui
    if {[catch {
        set mappings [dict create]
        foreach pair [split $ui($w,import_mappings) " "] {
            if {$pair eq ""} continue
            if {![regexp {^([A-Z]{1,2})=([A-Za-z][A-Za-z0-9_.-]*)$} $pair unused col id]} {error "Use mappings like A=v_time B=v_signal."}
            dict set mappings $col $id
        }
        lassign [bindDataset $ui($w,book) $ui($w,import_dataset) $mappings $ui($w,import_first) $ui($w,import_limit) $ui($w,import_selection)] book count
        set ui($w,book) $book; _uiRefresh $w; set ui($w,status) "Imported $count canonical rows. Save to keep the Worksheet document."; destroy $d
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiPlotDialog {w mode} {
    variable ui
    set d $w.plot; catch {destroy $d}; toplevel $d; wm title $d "Worksheet plot and publication"
    foreach {key label default} {x {X column} A y {Y columns (space separated)} B z {Z column (3-D only)} {} first {First row} 1 last {Last row} 20 dataset {Output Dataset ID for publication} worksheet_result} {
        set ui($w,plot_$key) $default
        ttk::label $d.l_$key -text $label; ttk::entry $d.e_$key -textvariable ::GX::ScientificWorksheet::ui($w,plot_$key); pack $d.l_$key $d.e_$key -anchor w -fill x
    }
    ttk::button $d.preview -text "Transient preview" -command [list ::GX::ScientificWorksheet::_uiPlotAction $w preview]
    ttk::button $d.publish -text "Publish as Dataset" -command [list ::GX::ScientificWorksheet::_uiPlotAction $w publish]
    ttk::button $d.retain -text "Publish and retain plot" -command [list ::GX::ScientificWorksheet::_uiPlotAction $w retain]
    pack $d.preview $d.publish $d.retain -side left
}
proc ::GX::ScientificWorksheet::_uiPlotAction {w action} {
    variable ui
    if {[catch {
        set book $ui($w,book); set x $ui($w,plot_x); set ys [split [string trim $ui($w,plot_y)]]; set z $ui($w,plot_z)
        set first $ui($w,plot_first); set last $ui($w,plot_last)
        if {$action eq "preview"} {
            set channel [file tempfile dest]; close $channel; file delete -- $dest; file mkdir $dest
            set result [preview $book $x $ys $first $last $dest $z]
            set ui($w,status) "Transient Plot Dataset preview: [dict get $result artifact]"
            _uiShowPreview $w [dict get $result artifact]
        } else {
            set mappings [dict create x $x]; set yIds {}; set index 0
            foreach y $ys {set id "y[incr index]"; dict set mappings $id $y; lappend yIds $id}
            if {$z ne ""} {dict set mappings z $z}
            if {$action eq "retain"} {
                set result [retainPlot $book $mappings $first $last $ui($w,plot_dataset) x $yIds [expr {$z eq "" ? "" : "z"}]]
                if {$z ne ""} {::GX::PlotDatasetAPIv3::openInteractive $result} else {
                    set rendered [::GX::PlotDatasetAPIv3::render $result]
                    _uiShowPreview $w [dict get [dict get $rendered artifacts] graph_artifact]
                }
            } else {set result [publish $book $mappings $first $last $ui($w,plot_dataset)]}
            set ui($w,status) "Published Worksheet Dataset $ui($w,plot_dataset): $result"
        }
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiShowPreview {w artifact} {
    variable ui
    set d $w.preview
    catch {destroy $d}
    toplevel $d
    wm title $d "Scientific Worksheet — Plot Dataset transient preview"
    set ui($w,preview_photo) [image create photo -file $artifact]
    ttk::label $d.image -image $ui($w,preview_photo)
    pack $d.image -fill both -expand 1
}
proc ::GX::ScientificWorksheet::open {{context {}}} {
    variable ui
    package require Tk
    _requireSession
    set w .scientific_worksheet
    if {[winfo exists $w]} {raise $w; return $w}
    toplevel $w; wm title $w "Scientific Worksheet"; wm minsize $w 900 580
    set ui($w,book) [new]
    dict set ui($w,book) presentation display_columns {A B C D E F G H I J K L}
    set ui($w,first_row) 1; set ui($w,active) A1; set ui($w,formula) ""; set ui($w,status) "Enter a value or formula starting with =."; set ui($w,function_query) ""
    if {[dict exists $context document_id]} {set ui($w,book) [load [dict get $context document_id]]}
    ttk::frame $w.toolbar -padding 6; pack $w.toolbar -fill x
    foreach {key label command} {save Save _uiSave load Open _uiLoad recalc Recalculate _uiRecalculate all {Recalculate All} _uiRecalculate import {Bind Dataset} _uiImportDialog names {Columns / Ranges} _uiNamesDialog functions Functions _uiFunctionBrowser plot Plot/Publish _uiPlotDialog inspect {Inspect cell} _uiInspect} {
        if {$key eq "recalc"} {set script [list ::GX::ScientificWorksheet::$command $w 0]} elseif {$key eq "all"} {set script [list ::GX::ScientificWorksheet::$command $w 1]} elseif {$key eq "plot"} {set script [list ::GX::ScientificWorksheet::$command $w plot]} else {set script [list ::GX::ScientificWorksheet::$command $w]}
        ttk::button $w.toolbar.$key -text $label -command $script; pack $w.toolbar.$key -side left -padx 2
    }
    ttk::frame $w.formula -padding 6; pack $w.formula -fill x
    ttk::label $w.formula.active -textvariable ::GX::ScientificWorksheet::ui($w,active) -width 8
    ttk::entry $w.formula.entry -textvariable ::GX::ScientificWorksheet::ui($w,formula)
    ttk::button $w.formula.apply -text Apply -command [list ::GX::ScientificWorksheet::_uiCommit $w]
    pack $w.formula.active -side left; pack $w.formula.entry -side left -fill x -expand 1; pack $w.formula.apply -side left
    bind $w.formula.entry <Return> [list ::GX::ScientificWorksheet::_uiCommit $w]
    bind $w.formula.entry <Control-space> [list ::GX::ScientificWorksheet::_uiAutocomplete $w]
    ttk::frame $w.grid -padding 6; pack $w.grid -fill both -expand 1
    set columns {row A B C D E F G H I J K L}
    ttk::treeview $w.grid.table -columns $columns -show headings -selectmode extended
    foreach col $columns {$w.grid.table heading $col -text $col; $w.grid.table column $col -width [expr {$col eq "row" ? 54 : 90}] -stretch 1}
    ttk::scrollbar $w.grid.sy -orient vertical -command [list $w.grid.table yview]
    ttk::scrollbar $w.grid.sx -orient horizontal -command [list $w.grid.table xview]
    $w.grid.table configure -yscrollcommand [list $w.grid.sy set] -xscrollcommand [list $w.grid.sx set]
    grid $w.grid.table -row 0 -column 0 -sticky nsew; grid $w.grid.sy -row 0 -column 1 -sticky ns; grid $w.grid.sx -row 1 -column 0 -sticky ew
    grid rowconfigure $w.grid 0 -weight 1; grid columnconfigure $w.grid 0 -weight 1
    bind $w.grid.table <ButtonRelease-1> [list ::GX::ScientificWorksheet::_uiSelectAt $w %x %y]
    bind $w.grid.table <<TreeviewSelect>> [list ::GX::ScientificWorksheet::_uiSelectRow $w]
    bind $w.grid.table <Control-c> [list ::GX::ScientificWorksheet::_uiCopy $w]
    bind $w.grid.table <Control-v> [list ::GX::ScientificWorksheet::_uiPaste $w]
    foreach {event dr dc} {<Up> -1 0 <Down> 1 0 <Left> 0 -1 <Right> 0 1 <Tab> 0 1 <Shift-Tab> 0 -1} {
        bind $w.grid.table $event "[list ::GX::ScientificWorksheet::_uiMove $w $dr $dc]; break"
    }
    ttk::frame $w.footer -padding 4; pack $w.footer -fill x
    ttk::button $w.footer.previous -text "Previous 200 rows" -command [list ::GX::ScientificWorksheet::_uiPage $w -200]
    ttk::button $w.footer.next -text "Next 200 rows" -command [list ::GX::ScientificWorksheet::_uiPage $w 200]
    ttk::label $w.footer.status -textvariable ::GX::ScientificWorksheet::ui($w,status)
    pack $w.footer.previous $w.footer.next -side left -padx 2; pack $w.footer.status -side left -padx 12
    _uiRefresh $w
    return $w
}
proc ::GX::ScientificWorksheet::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Worksheet viewer action '$action'."}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
::GX::viewerBackendRegister scientific_worksheet_tk ::GX::ScientificWorksheet::viewerDispatch
source [file join [file dirname [info script]] scientific_worksheet_workbook_v2.tcl]
source [file join [file dirname [info script]] .. ui worksheet_ux_v3.tcl]
