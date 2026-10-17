# Scientific Worksheet workbook and direct-edit extensions.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificWorksheet {
    variable spill [dict create]
    variable undo
    variable redo
    variable automaticCacheSnapshots [dict create]
}

foreach method {new save load setCell setColumn defineRange _tokenize _parsePrimary _dependencies _evalCell value recalculate bindDataset} {
    rename ::GX::ScientificWorksheet::$method ::GX::ScientificWorksheet::_v1_$method
}

proc ::GX::ScientificWorksheet::_sheetData {book} {
    set data [dict create]
    foreach key {cells columns ranges bindings column_metadata row_identity hidden_rows operations} {
        dict set data $key [expr {[dict exists $book $key] ? [dict get $book $key] : [dict create]}]
    }
    return $data
}
proc ::GX::ScientificWorksheet::_upgrade {book} {
    if {![dict exists $book presentation display_columns]} {dict set book presentation display_columns {A B C D E F G H I J K L}}
    if {![dict exists $book sheets]} {
        dict set book sheets [dict create Sheet1 [_sheetData $book]]
        dict set book sheet_order {Sheet1}
        dict set book active_sheet Sheet1
        dict set book options calculation_mode automatic
    }
    return $book
}
proc ::GX::ScientificWorksheet::_flush {book} {
    set book [_upgrade $book]
    dict set book sheets [dict get $book active_sheet] [_sheetData $book]
    return $book
}
proc ::GX::ScientificWorksheet::_activate {book sheet} {
    set book [_flush $book]
    if {![dict exists $book sheets $sheet]} {error "#REF! Unknown sheet '$sheet'."}
    dict set book active_sheet $sheet
    dict for {key value} [dict get $book sheets $sheet] {dict set book $key $value}
    return $book
}
proc ::GX::ScientificWorksheet::_key {book} {
    set id [dict get $book document_id]
    if {$id eq ""} {set id "new:[dict get $book name]"}
    set sheet [expr {[dict exists $book active_sheet] ? [dict get $book active_sheet] : "Sheet1"}]
    return "$id/$sheet"
}
proc ::GX::ScientificWorksheet::new {{name "Untitled Worksheet"}} {return [_upgrade [_v1_new $name]]}
proc ::GX::ScientificWorksheet::save {book} {return [_v1_save [_flush [_formulaResourceReferences $book]]]}
proc ::GX::ScientificWorksheet::load {id} {variable statisticalFieldCache;set statisticalFieldCache {};variable statisticalItemCache;set statisticalItemCache {};return [_upgrade [_v1_load $id]]}
proc ::GX::ScientificWorksheet::sheetNames {book} {return [dict get [_upgrade $book] sheet_order]}
proc ::GX::ScientificWorksheet::activeSheet {book} {return [dict get [_upgrade $book] active_sheet]}
proc ::GX::ScientificWorksheet::selectSheet {book sheet} {return [_activate $book $sheet]}
proc ::GX::ScientificWorksheet::_validSheetName {name} {
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $name] || [string length $name] > 40} {error "Sheet name must be an identifier of at most 40 characters."}
    return $name
}
proc ::GX::ScientificWorksheet::createSheet {book name} {
    set book [_flush $book]; _validSheetName $name
    if {[dict exists $book sheets $name]} {error "Sheet '$name' already exists."}
    dict set book sheets $name [dict create cells [dict create] columns [dict create] ranges [dict create] bindings [dict create] column_metadata [dict create] row_order [dict create] hidden_rows [dict create]]
    dict lappend book sheet_order $name
    dict incr book revision
    return [_activate $book $name]
}
proc ::GX::ScientificWorksheet::duplicateSheet {book from name} {
    set book [_flush $book]; _validSheetName $name
    if {![dict exists $book sheets $from] || [dict exists $book sheets $name]} {error "Source sheet is missing or destination already exists."}
    dict set book sheets $name [dict get $book sheets $from]
    dict lappend book sheet_order $name
    dict incr book revision
    return [_activate $book $name]
}
proc ::GX::ScientificWorksheet::renameSheet {book old name} {
    set book [_flush $book]; _validSheetName $name
    if {![dict exists $book sheets $old] || [dict exists $book sheets $name]} {error "Source sheet is missing or destination already exists."}
    set data [dict get $book sheets $old]; dict unset book sheets $old; dict set book sheets $name $data
    set order {}; foreach item [dict get $book sheet_order] {lappend order [expr {$item eq $old ? $name : $item}]}; dict set book sheet_order $order
    if {[dict get $book active_sheet] eq $old} {dict set book active_sheet $name}
    dict for {sheet body} [dict get $book sheets] {
        dict for {address cell} [dict get $body cells] {
            if {[dict get $cell kind] ne "formula"} continue
            set src [dict get $cell source]
            set src [regsub -all -- "\\m${old}!" $src "${name}!"]
            dict set book sheets $sheet cells $address source $src
        }
    }
    dict incr book revision
    variable cache; set cache [dict create]
    return [_activate $book [dict get $book active_sheet]]
}
proc ::GX::ScientificWorksheet::deleteSheet {book name} {
    set book [_flush $book]
    if {[llength [dict get $book sheet_order]] < 2} {error "A workbook must have at least one sheet."}
    if {![dict exists $book sheets $name]} {error "Unknown sheet '$name'."}
    dict unset book sheets $name
    set order {}; foreach item [dict get $book sheet_order] {if {$item ne $name} {lappend order $item}}
    dict set book sheet_order $order; dict incr book revision
    variable cache; set cache [dict create]
    return [_activate $book [lindex $order 0]]
}
proc ::GX::ScientificWorksheet::moveSheet {book name offset} {
    set book [_flush $book]; set order [dict get $book sheet_order]; set i [lsearch -exact $order $name]
    if {$i < 0} {error "Unknown sheet '$name'."}
    set j [expr {max(0,min([llength $order]-1,$i+$offset))}]
    set order [lreplace $order $i $i]; set order [linsert $order $j $name]
    dict set book sheet_order $order; dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::setCalculationMode {book mode} {
    if {$mode ni {automatic manual}} {error "Calculation mode must be automatic or manual."}
    dict set book options calculation_mode $mode; dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::setCell {book address source} {
    set book [_upgrade $book]
    variable cache; variable spill
    set mode [dict get $book options calculation_mode]
    if {$mode eq "manual"} {set oldCache $cache; set oldSpill $spill}
    if {[string equal -nocase [string trim $source] "NaN"]} {
        set address [_cell $address]
        lassign [_parts $address] number unused; set column [_columnName $number]
        set unit [expr {[dict exists $book column_metadata $column unit] ? [dict get $book column_metadata $column unit] : ""}]
        dict set book cells $address [dict create source NaN kind missing unit $unit lineage [dict create]]
        dict incr book revision
        set cache [dict create]; set spill [dict create]
        return $book
    }
    set result [_v1_setCell $book $address $source]
    if {[string toupper [string trim $source]] in {TRUE FALSE}} {dict set result cells [_cell $address] kind boolean}
    if {$mode eq "manual"} {
        set cache $oldCache; set spill $oldSpill
        set key [_key $book]
        if {[dict exists $cache $key [_cell $address]]} {dict unset cache $key [_cell $address]}
        if {[dict exists $spill $key]} {
            dict for {spillAddress item} [dict get $spill $key] {
                if {[dict get $item anchor] eq [_cell $address]} {dict unset spill $key $spillAddress}
            }
        }
    } else {set cache [dict create]; set spill [dict create]}
    return $result
}
proc ::GX::ScientificWorksheet::setColumn {book column name {unit ""}} {
    set result [_v1_setColumn [_upgrade $book] $column $name $unit]
    variable cache; set cache [dict create]
    return $result
}
proc ::GX::ScientificWorksheet::defineRange {book name start end} {return [_v1_defineRange [_upgrade $book] $name $start $end]}

proc ::GX::ScientificWorksheet::_reference {token} {
    if {![regexp {^(?:([A-Za-z_][A-Za-z0-9_]*)!)?(\$?)([A-Za-z]{1,3})(\$?)([1-9][0-9]*)$} $token unused sheet absCol letters absRow row]} {return {}}
    set address "[string toupper $letters]$row"
    _cell $address
    return [dict create sheet $sheet address $address absolute_column [expr {$absCol ne ""}] absolute_row [expr {$absRow ne ""}]]
}
proc ::GX::ScientificWorksheet::_tokenize {formula} {
    set remaining [string trim $formula]
    if {[string index $remaining 0] eq "="} {set remaining [string range $remaining 1 end]}
    if {[string length $remaining] > 8192} {error "Formula exceeds 8192 characters."}
    set tokens {}; set position 1
    while {[string trim $remaining] ne ""} {
        set spaces [expr {[string length $remaining]-[string length [string trimleft $remaining]]}]
        incr position $spaces; set remaining [string trimleft $remaining]
        if {[regexp {^([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?} $remaining match]} {set kind number
        } elseif {[regexp {^"([^"\\]|\\.)*"} $remaining match]} {set kind string; set quoted $match; set match [string range $match 1 end-1]; set match [string map [list {\"} {"}] $match]; lappend tokens [list $kind $match $position]; incr position [string length $quoted]; set remaining [string range $remaining [string length $quoted] end]; continue
        } elseif {[regexp {^(?:[A-Za-z_][A-Za-z0-9_]*!)?\$?[A-Za-z]{1,3}\$?[1-9][0-9]*} $remaining match]} {set kind identifier
        } elseif {[regexp {^[A-Za-z_][A-Za-z0-9_.]*} $remaining match]} {set kind identifier
        } elseif {[regexp {^(<=|>=|==|!=|[+*/^(),:\[\]<>-])} $remaining match]} {set kind symbol
        } else {error "#VALUE! Invalid formula character at column $position near '[string range $remaining 0 15]'."}
        lappend tokens [list $kind $match $position]
        incr position [string length $match]; set remaining [string range $remaining [string length $match] end]
    }
    lappend tokens [list eof "" $position]
    return $tokens
}
proc ::GX::ScientificWorksheet::_dependencies {book formula} {
    set deps [dict create]; set tokens [_tokenize $formula]
    for {set i 0} {$i < [llength $tokens]-1} {incr i} {
        set token [lindex [lindex $tokens $i] 1]; set ref [_reference $token]
        if {[dict size $ref]} {
            set sheet [dict get $ref sheet]; set first [dict get $ref address]
            if {[lindex [lindex $tokens [expr {$i+1}]] 1] eq ":"} {
                set endRef [_reference [lindex [lindex $tokens [expr {$i+2}]] 1]]
                if {![dict size $endRef]} {error "#REF! Invalid range endpoint."}
                foreach address [rangeCells $first [dict get $endRef address]] {dict set deps "${sheet}!$address" 1}
            } else {dict set deps "${sheet}!$first" 1}
        } elseif {[dict exists $book ranges $token]} {
            foreach address [dict get $book ranges $token] {dict set deps "![set address]" 1}
        } elseif {[dict exists $book columns $token] && [lindex [lindex $tokens [expr {$i+1}]] 1] eq "\["} {
            set row [lindex [lindex $tokens [expr {$i+2}]] 1]
            if {![string is integer -strict $row] || $row < 1} {error "#REF! Named column row must be positive."}
            dict set deps "![dict get $book columns $token]$row" 1
        }
    }
    return [dict keys $deps]
}
proc ::GX::ScientificWorksheet::_parsePrimary {book tokens indexVar stack} {
    upvar 1 $indexVar index
    lassign [lindex $tokens $index] kind token
    set ref [_reference $token]
    if {![dict size $ref]} {
        variable evaluationDocument
        set previous $evaluationDocument;set evaluationDocument [dict get $book document_id]
        try {return [_v1__parsePrimary $book $tokens index $stack]} finally {set evaluationDocument $previous}
    }
    incr index
    set target $book; set sheet [dict get $ref sheet]
    if {$sheet ne ""} {set target [_activate $book $sheet]}
    set first [dict get $ref address]
    if {[_peek $tokens $index] eq ":"} {
        incr index; set endRef [_reference [_peek $tokens $index]]; incr index
        if {![dict size $endRef]} {error "#REF! Invalid range endpoint."}
        set out {}; set unit "";set inputs {}
        foreach address [rangeCells $first [dict get $endRef address]] {
            set item [_evalCell $target $address $stack]
            if {[dict get $item kind] eq "blank"} continue
            if {![llength $inputs]} {set unit [dict get $item unit]} elseif {[dict get $item unit] ne $unit} {error "#UNIT! Range units differ."}
            lappend inputs $item
            if {[dict get $item kind] in {vector matrix}} {lappend out [lindex [dict get $item value] 0]} else {lappend out [dict get $item value]}
        }
        return [_carryStatistics [_value $out $unit vector] $inputs]
    }
    set item [_evalCell $target $first $stack]
    if {[dict get $item kind] in {vector matrix}} {return [_scalarComponent $item 0]}
    return $item
}
proc ::GX::ScientificWorksheet::_evalCell {book address stack} {
    variable cache; variable spill
    set address [_cell $address]; set key [_key $book]; set identity "$key!$address"
    if {$identity in $stack} {error "#CIRC! [join [concat $stack $identity] { -> }]."}
    if {[dict exists $cache $key $address]} {return [dict get $cache $key $address]}
    if {[dict exists $spill $key $address]} {return [dict get $spill $key $address]}
    if {![dict exists $book cells $address]} {
        lassign [_parts $address] targetCol targetRow
        dict for {candidate candidateData} [dict get $book cells] {
            if {[dict get $candidateData kind] ne "formula"} continue
            lassign [_parts $candidate] candidateCol candidateRow
            if {$candidateCol > $targetCol || $candidateRow > $targetRow || $targetRow-$candidateRow > 20000 || "$key!$candidate" in $stack} continue
            catch {_evalCell $book $candidate $stack}
            if {[dict exists $spill $key $address]} {return [dict get $spill $key $address]}
        }
        return [_value "" "" blank]
    }
    set data [dict get $book cells $address]; set source [dict get $data source]
    if {[dict get $data kind] eq "formula"} {
        set tokens [_tokenize $source]; set index 0
        set result [_parseComparison $book $tokens index [concat $stack $identity]]
        if {[_peek $tokens $index] ne ""} {error "#VALUE! Unexpected token at column [lindex [lindex $tokens $index] 2]: '[_peek $tokens $index]'."}
    } elseif {[dict get $data kind] eq "missing"} {set result [_value NaN [dict get $data unit] missing]
    } elseif {[dict get $data kind] eq "boolean"} {set result [_value [expr {[string toupper $source] eq "TRUE"}] "" boolean]
    } elseif {[dict get $data kind] eq "text"} {
        if {[string toupper $source] in {TRUE FALSE}} {set result [_value [expr {[string toupper $source] eq "TRUE"}] "" boolean]} else {set result [_value $source "" text]}
    } else {
        set unit [expr {[dict exists $data unit] ? [dict get $data unit] : ""}]
        set result [_value $source $unit]
    }
    dict set result origin [dict get $data kind]
    if {[dict exists $data lineage]} {dict set result lineage [dict get $data lineage]}
    if {[dict exists $data lineage operation_destination]} {
        set destination [dict get $data lineage operation_destination]
        if {![dict exists $book operations $destination]} {error {Guided cell is missing its captured operation definition}}
        set definition [dict get $book operations $destination]
        foreach key {statistical_sources source_lineage} {if {[dict exists $definition $key]} {dict set result $key [dict get $definition $key]}}
        if {[dict exists $definition captured_statistics]} {
            set statistics [dict get $definition captured_statistics]
            set field [dict get $definition field];set index [dict get $data lineage output_index]
            set window [expr {[dict exists $definition field_window]?[dict get $definition field_window]:{}}]
            if {[dict exists $definition captured_data_values]} {
                set companions [expr {[dict exists $definition captured_data_companions]?[dict get $definition captured_data_companions]:{}}]
                set projected [_statisticalDataFieldItem $statistics $field [dict get $definition captured_data_values] $window 1 $companions]
            } else {set projected [_statisticalFieldItem $statistics $field $window]}
            set expected [_scalarComponent $projected $index]
            if {[dict get $result value] ne [dict get $expected value]||[dict get $result unit] ne [dict get $expected unit]} {error {Guided cell differs from its captured statistical result; reapply the operation or edit the cell explicitly}}
            set result [_carryStatistics [dict merge $result $expected] [list $result]]
        }
    }
    if {[dict get $result kind] in {vector matrix}} {_registerSpill $book $address $result}
    dict set cache $key $address $result
    return $result
}
proc ::GX::ScientificWorksheet::_scalarComponent {result index} {
    set unit [dict get $result unit]
    if {[dict exists $result element_units]} {set unit [lindex [dict get $result element_units] $index]}
    set item [_carryStatistics [_value [lindex [dict get $result value] $index] $unit] [list $result]]
    if {[dict exists $result element_units]&&[dict exists $item mixed_units]} {dict unset item mixed_units}
    foreach key {statistical_result statistical_field statistical_window statistical_data_field statistical_data_companions statistical_data_statuses statistical_data_reasons} {if {[dict exists $result $key]} {dict set item $key [dict get $result $key]}}
    if {[dict exists $result statistical_result]} {dict set item statistical_element $index}
    return $item
}
proc ::GX::ScientificWorksheet::_registerSpill {book anchor result} {
    variable spill
    set key [_key $book]; lassign [_parts $anchor] c0 r0
    set values [dict get $result value]
    if {[dict get $result kind] eq "matrix"} {lassign [dict get $result shape] rows cols} else {set rows [llength $values]; set cols 1}
    if {$rows*$cols != [llength $values] || $rows*$cols > 20000} {error "#VALUE! Invalid spill shape."}
    set pending [dict create]; set i 0
    for {set r 0} {$r < $rows} {incr r} {
        for {set c 0} {$c < $cols} {incr c} {
            set address "[_columnName [expr {$c0+$c}]][expr {$r0+$r}]"
            if {$address ne $anchor && [dict exists $book cells $address]} {error "#SPILL! $address contains data; clear the destination range."}
            if {$address ne $anchor} {dict set pending $address [dict merge [_scalarComponent $result $i] [dict create origin spill anchor $anchor]]}
            incr i
        }
    }
    dict for {address item} $pending {dict set spill $key $address $item}
}
proc ::GX::ScientificWorksheet::_ensureCalculationSnapshot {book} {
    # Automatic values are a function of the supplied workbook, not the last
    # workbook with the same document/sheet ID. Revision alone is insufficient:
    # two independent value copies can have the same revision and different cells.
    # Manual mode deliberately keeps its existing explicit-recalculation cache.
    if {[dict get $book options calculation_mode] ne "automatic"} return
    variable automaticCacheSnapshots;variable cache;variable spill
    set sheet [dict get $book active_sheet]
    set key [_key $book]
    set prefix [string range $key 0 end-[string length $sheet]]
    if {[dict exists $automaticCacheSnapshots $prefix]&&[dict get $automaticCacheSnapshots $prefix] eq $book} return
    # A change on any sheet can affect formulas on other sheets of this book.
    foreach name {cache spill} {
        upvar 0 $name entries
        foreach existing [dict keys $entries] {
            if {[string first $prefix $existing]==0} {dict unset entries $existing}
        }
    }
    if {[dict exists $automaticCacheSnapshots $prefix]} {dict unset automaticCacheSnapshots $prefix}
    dict set automaticCacheSnapshots $prefix $book
    # Keep a bounded set of immutable references. Eviction drops only the
    # comparison snapshot; a later automatic read invalidates its own cache.
    if {[dict size $automaticCacheSnapshots]>8} {dict unset automaticCacheSnapshots [lindex [dict keys $automaticCacheSnapshots] 0]}
}
proc ::GX::ScientificWorksheet::value {book address} {
    set book [_upgrade $book]
    _ensureCalculationSnapshot $book
    return [_evalCell $book $address {}]
}
proc ::GX::ScientificWorksheet::recalculate {book {all 0}} {
    variable cache; variable spill; variable dirty
    variable statisticalFieldCache;set statisticalFieldCache {}
    variable statisticalItemCache;set statisticalItemCache {}
    set book [_upgrade $book]; set key [_key $book]
    if {$all} {set cache [dict create]; set spill [dict create]; set targets [dict keys [dict get $book cells]]} else {
        set targets [expr {[dict exists $dirty $key] ? [dict keys [dict get $dirty $key]] : [dict keys [dict get $book cells]]}]
    }
    set result [dict create]
    foreach address $targets {
        if {[catch {set item [value $book $address]} message]} {dict set result $address [dict create error $message]} else {dict set result $address $item}
    }
    if {[dict exists $dirty $key]} {dict unset dirty $key}
    return $result
}
proc ::GX::ScientificWorksheet::recalculateSelection {book first last} {
    variable cache
    set book [_upgrade $book]; set key [_key $book]
    set result [dict create]
    foreach address [rangeCells $first $last] {
        if {[dict exists $cache $key $address]} {dict unset cache $key $address}
        if {[catch {set item [value $book $address]} message]} {dict set result $address [dict create error $message]} else {dict set result $address $item}
    }
    return $result
}
proc ::GX::ScientificWorksheet::recalculateWorkbook {book} {
    set book [_flush $book]; set result [dict create]
    foreach name [dict get $book sheet_order] {
        dict set result $name [recalculate [_activate $book $name] 1]
    }
    return $result
}
proc ::GX::ScientificWorksheet::reapplyOperations {book} {
    set book [_upgrade $book]
    if {![dict exists $book operations]} {return $book}
    set definitions [dict get $book operations]
    dict for {destination definition} $definitions {
        lassign [_parts $destination] c0 r0
        for {set r 0} {$r < [dict get $definition rows]} {incr r} {
            for {set c 0} {$c < [dict get $definition columns]} {incr c} {
                set address "[_columnName [expr {$c0+$c}]][expr {$r0+$r}]"
                if {[dict exists $book cells $address lineage operation] && [dict get $book cells $address lineage operation] eq [dict get $definition operation]} {dict unset book cells $address}
            }
        }
        lassign [applyOperation $book [dict get $definition operation] [dict get $definition inputs] [dict get $definition options] $destination [dict get $definition field] [dict get $definition model] [expr {[dict exists $definition field_window]?[dict get $definition field_window]:{}}]] book unused
    }
    return $book
}

proc ::GX::ScientificWorksheet::shiftFormula {formula rowOffset columnOffset} {
    if {[string index $formula 0] ne "="} {return $formula}
    set out "="; set remaining [string range $formula 1 end]
    while {$remaining ne ""} {
        if {[string index $remaining 0] eq "\""} {
            if {[regexp {^"([^"\\]|\\.)*"} $remaining quoted]} {append out $quoted; set remaining [string range $remaining [string length $quoted] end]; continue}
        }
        if {[regexp {^(?:[A-Za-z_][A-Za-z0-9_]*!)?\$?[A-Za-z]{1,3}\$?[1-9][0-9]*} $remaining token]} {
            set ref [_reference $token]
            lassign [_parts [dict get $ref address]] c r
            if {![dict get $ref absolute_column]} {incr c $columnOffset}
            if {![dict get $ref absolute_row]} {incr r $rowOffset}
            if {$c < 1 || $r < 1} {error "#REF! Copy would move a reference outside the sheet."}
            set prefix [expr {[dict get $ref sheet] eq "" ? "" : "[dict get $ref sheet]!"}]
            append out $prefix [expr {[dict get $ref absolute_column] ? "$" : ""}] [_columnName $c] [expr {[dict get $ref absolute_row] ? "$" : ""}] $r
            set remaining [string range $remaining [string length $token] end]
        } else {append out [string index $remaining 0]; set remaining [string range $remaining 1 end]}
    }
    return $out
}
proc ::GX::ScientificWorksheet::fillRange {book source targetEnd} {
    set book [_upgrade $book]; set source [_cell $source]; set targetEnd [_cell $targetEnd]
    if {![dict exists $book cells $source]} {error "Source cell is empty."}
    set formula [dict get $book cells $source source]
    lassign [_parts $source] c0 r0
    foreach address [rangeCells $source $targetEnd] {
        if {$address eq $source} continue
        lassign [_parts $address] c r
        set book [setCell $book $address [shiftFormula $formula [expr {$r-$r0}] [expr {$c-$c0}]]]
    }
    return $book
}
proc ::GX::ScientificWorksheet::copyRange {book first last destination} {
    set book [_upgrade $book]; lassign [_parts $first] c0 r0; lassign [_parts $destination] dc dr
    set snapshot [dict get $book cells]
    foreach address [rangeCells $first $last] {
        lassign [_parts $address] c r
        set target "[_columnName [expr {$dc+$c-$c0}]][expr {$dr+$r-$r0}]"
        set source [expr {[dict exists $snapshot $address] ? [dict get $snapshot $address source] : ""}]
        set book [setCell $book $target [shiftFormula $source [expr {$dr-$r0}] [expr {$dc-$c0}]]]
    }
    return $book
}
proc ::GX::ScientificWorksheet::clearRange {book first last} {
    foreach address [rangeCells $first $last] {set book [setCell $book $address ""]}
    return $book
}
proc ::GX::ScientificWorksheet::bindDataset {book datasetId mappings {firstRow 1} {limit 20000} {selectionId ""}} {
    set book [_upgrade $book]
    if {![string is integer -strict $firstRow] || $firstRow < 1 || ![string is integer -strict $limit] || $limit < 1 || $limit > 20000} {error "Import start and limit must be positive; limit is at most 20000 rows."}
    if {![dict size $mappings] || [dict size $mappings] > 26} {error "Select 1–26 variables."}
    set schema [dict create]
    foreach v [::GX::datasetVariableSchema $datasetId] {dict set schema [dict get $v variable_id] $v}
    dict for {col id} $mappings {
        set col [string toupper $col]; _columnNumber $col
        if {![dict exists $schema $id]} {error "Unknown Dataset variable '$id'."}
    }
    set session [_requireSession]; set ids [dict values $mappings]; set xId ""; set yId ""
    if {$selectionId ne ""} {
        set selection [::GX::sessionInspectionSelection $selectionId $session]
        if {[dict get $selection source_dataset_id] ne $datasetId} {error "Selection belongs to another Dataset."}
        if {[dict get $selection type] ni {x_range rectangle}} {error "Only X range and rectangle Selections can bind."}
        set xId [dict get $selection x_variable_id]; lappend ids $xId
        if {[dict get $selection type] eq "rectangle"} {set yId [dict get $selection y_variable_id]; lappend ids $yId}
    }
    set ids [lsort -unique $ids]
    set stream [::GX::tableStreamOpenDataset $session $datasetId $ids 4096]; set count 0
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]; set values [dict get $chunk values]
            for {set i 0} {$i < [dict get $chunk nrows] && $count < $limit} {incr i} {
                if {$selectionId ne ""} {
                    set x [lindex [dict get $values $xId] $i]
                    if {![string is double -strict $x] || $x < [dict get $selection x_min] || $x > [dict get $selection x_max]} continue
                    if {$yId ne ""} {
                        set y [lindex [dict get $values $yId] $i]
                        if {![string is double -strict $y] || $y < [dict get $selection y_min] || $y > [dict get $selection y_max]} continue
                    }
                }
                dict for {col id} $mappings {
                    set variable [dict get $schema $id]; set address "${col}[expr {$firstRow+$count}]"
                    set raw [lindex [dict get $values $id] $i]
                    if {$raw eq ""} {set kind missing} else {set kind [expr {[dict get $variable value_kind] in {number elapsed_time} ? "dataset" : "text"}]}
                    dict set book cells $address [dict create source $raw kind $kind unit [dict get $variable unit] lineage [dict create dataset_id $datasetId variable_id $id source_row [expr {[dict get $chunk offset]+$i}] selection_id $selectionId]]
                    dict set book bindings $col [dict create dataset_id $datasetId variable_id $id unit [dict get $variable unit] selection_id $selectionId first_row $firstRow row_count [expr {$count+1}]]
                    dict set book column_metadata $col [dict create name $id unit [dict get $variable unit]]
                    if {![dict exists $book columns $id]} {dict set book columns $id $col}
                }
                incr count
            }
            if {$count >= $limit || [dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    dict incr book revision; variable cache; variable spill; set cache [dict create]; set spill [dict create]
    return [list $book $count]
}

proc ::GX::ScientificWorksheet::sortRows {book first last columns directions} {
    set book [_upgrade $book]
    if {![llength $columns] || [llength $columns] != [llength $directions]} {error "Choose matching sort columns and directions."}
    if {$last-$first > 19999 || $first < 1 || $last < $first} {error "Sort range must contain 1–20000 rows."}
    set rows {}; set snapshot [dict get $book cells]
    for {set r $first} {$r <= $last} {incr r} {
        if {![dict exists $book row_identity $r]} {dict set book row_identity $r $r}
        set keys {}
        foreach col $columns {
            set address "[string toupper $col]$r"
            if {[dict exists $snapshot $address]} {
                if {[catch {set item [value $book $address]}]} {set v ""} else {set v [dict get $item value]}
            } else {set v ""}
            lappend keys $v
        }
        lappend rows [list $r $keys]
    }
    set sorted [lsort -command [list ::GX::ScientificWorksheet::_compareRows $directions] $rows]
    set newCells $snapshot; set newIdentity [dict get $book row_identity]
    for {set target $first} {$target <= $last} {incr target} {
        set source [lindex [lindex $sorted [expr {$target-$first}]] 0]
        dict set newIdentity $target [dict get $book row_identity $source]
        for {set c 1} {$c <= 702} {incr c} {
            set col [_columnName $c]; set to "$col$target"; set from "$col$source"
            if {[dict exists $snapshot $from]} {dict set newCells $to [dict get $snapshot $from]} elseif {[dict exists $newCells $to]} {dict unset newCells $to}
        }
    }
    dict set book cells $newCells; dict set book row_identity $newIdentity; dict incr book revision
    variable cache; variable spill; set cache [dict create]; set spill [dict create]
    return $book
}
proc ::GX::ScientificWorksheet::_compareRows {directions a b} {
    set ak [lindex $a 1]; set bk [lindex $b 1]
    for {set i 0} {$i < [llength $directions]} {incr i} {
        set av [lindex $ak $i]; set bv [lindex $bk $i]
        if {[string is double -strict $av] && [string is double -strict $bv]} {set cmp [expr {$av < $bv ? -1 : ($av > $bv ? 1 : 0)}]} else {set cmp [string compare -nocase $av $bv]}
        if {$cmp != 0} {return [expr {[lindex $directions $i] eq "descending" ? -$cmp : $cmp}]}
    }
    return [expr {[lindex $a 0]-[lindex $b 0]}]
}
proc ::GX::ScientificWorksheet::restoreRowOrder {book first last} {
    set book [_upgrade $book]
    if {![dict exists $book row_identity]} {return $book}
    set rows {}; for {set r $first} {$r <= $last} {incr r} {lappend rows [list $r [dict get $book row_identity $r]]}
    set rows [lsort -integer -index 1 $rows]; set snapshot [dict get $book cells]; set cells $snapshot
    for {set target $first} {$target <= $last} {incr target} {
        set source [lindex [lindex $rows [expr {$target-$first}]] 0]
        for {set c 1} {$c <= 702} {incr c} {
            set col [_columnName $c]; set to "$col$target"; set from "$col$source"
            if {[dict exists $snapshot $from]} {dict set cells $to [dict get $snapshot $from]} elseif {[dict exists $cells $to]} {dict unset cells $to}
        }
        dict set book row_identity $target [lindex [lindex $rows [expr {$target-$first}]] 1]
    }
    dict set book cells $cells; dict incr book revision; variable cache; set cache [dict create]
    return $book
}
proc ::GX::ScientificWorksheet::filterRows {book column comparator operand first last} {
    set book [_upgrade $book]
    if {$comparator ni {contains equals greater less}} {error "Choose contains, equals, greater, or less."}
    set hidden [dict create]
    for {set r $first} {$r <= $last} {incr r} {
        set address "[string toupper $column]$r"
        if {[dict exists $book cells $address] && ![catch {set item [value $book $address]}]} {set v [dict get $item value]} else {set v ""}
        switch -- $comparator {
            contains {set keep [expr {[string first [string tolower $operand] [string tolower $v]] >= 0}]}
            equals {set keep [expr {$v eq $operand}]}
            greater - less {
                set keep [expr {[string is double -strict $v] && [string is double -strict $operand]}]
                if {$keep} {set keep [expr {$comparator eq "greater" ? $v > $operand : $v < $operand}]}
            }
        }
        if {!$keep} {dict set hidden $r 1}
    }
    dict set book hidden_rows $hidden; dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::showAllRows {book} {dict set book hidden_rows [dict create]; dict incr book revision; return $book}

proc ::GX::ScientificWorksheet::convertUnit {book first last targetUnit} {
    set book [_upgrade $book]
    if {$targetUnit ni [::GX::unitRegistryList]} {error "#UNIT! Choose a registered destination unit."}
    set first [_cell $first]; set last [_cell $last]
    foreach address [rangeCells $first $last] {
        if {![dict exists $book cells $address]} continue
        set item [value $book $address]; set old [dict get $item unit]
        if {$old eq "" || ![::GX::unitTclCompatible $old $targetUnit]} {error "#UNIT! $address has unit '$old', incompatible with '$targetUnit'."}
        if {[dict get $item kind] ne "scalar" || ![string is double -strict [dict get $item value]]} {error "#TYPE! $address is not a numeric scalar."}
        set source [::GX::unitRegistryDefinition $old]; set target [::GX::unitRegistryDefinition $targetUnit]
        foreach def [list $source $target] {
            if {[dict get $def conversion_kind] in {scale affine identity intrinsic}} continue
            set symbol [dict get $def symbol]
            if {[dict get $def conversion_kind] eq "opaque" && ($symbol eq [dict get $source canonical_unit] || $symbol eq [dict get $target canonical_unit])} continue
            error "#UNIT! Unit Registry has no safe conversion for '$old' to '$targetUnit'."
        }
        if {[dict get $source conversion_kind] eq "intrinsic"} {
            if {[catch {set a [lindex [::GX::unitTclSingle $old] 0]}]} {error "#UNIT! No intrinsic conversion scale is defined for '$old'."}
        } else {set a [expr {[dict get $source scale] eq "" ? 1.0 : [dict get $source scale]}]}
        set b [expr {[dict get $source offset] eq "" ? 0.0 : [dict get $source offset]}]
        if {[dict get $target conversion_kind] eq "intrinsic"} {
            if {[catch {set c [lindex [::GX::unitTclSingle $targetUnit] 0]}]} {error "#UNIT! No intrinsic conversion scale is defined for '$targetUnit'."}
        } else {set c [expr {[dict get $target scale] eq "" ? 1.0 : [dict get $target scale]}]}
        set d [expr {[dict get $target offset] eq "" ? 0.0 : [dict get $target offset]}]
        set converted [expr {(double([dict get $item value])*$a+$b-$d)/$c}]
        set original [dict get $book cells $address]
        dict set book cells $address [dict create source [format %.17g $converted] kind manual unit $targetUnit lineage [dict create conversion_from $old conversion_to $targetUnit source [dict get $original source] source_lineage [expr {[dict exists $original lineage] ? [dict get $original lineage] : [dict create]}]]]
    }
    dict incr book revision; variable cache; set cache [dict create]
    return $book
}

foreach method {open _uiRefresh _uiMove _uiCommit _uiImportDialog _uiImport _uiSave _uiLoadSelected} {
    rename ::GX::ScientificWorksheet::$method ::GX::ScientificWorksheet::_v1_$method
}
proc ::GX::ScientificWorksheet::_uiRemember {w} {
    variable ui; variable undo; variable redo
    lappend undo($w) $ui($w,book)
    if {[llength $undo($w)] > 20} {set undo($w) [lrange $undo($w) end-19 end]}
    set redo($w) {}
}
proc ::GX::ScientificWorksheet::_uiUndo {w} {
    variable ui; variable undo; variable redo
    if {![info exists undo($w)] || ![llength $undo($w)]} return
    lappend redo($w) $ui($w,book)
    set ui($w,book) [lindex $undo($w) end]; set undo($w) [lrange $undo($w) 0 end-1]
    variable cache; variable spill; set cache [dict create]; set spill [dict create]
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiRedo {w} {
    variable ui; variable undo; variable redo
    if {![info exists redo($w)] || ![llength $redo($w)]} return
    lappend undo($w) $ui($w,book)
    set ui($w,book) [lindex $redo($w) end]; set redo($w) [lrange $redo($w) 0 end-1]
    variable cache; variable spill; set cache [dict create]; set spill [dict create]
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiCommit {w} {
    variable ui
    if {$ui($w,active) eq ""} return
    _uiRemember $w
    if {[catch {
        set ui($w,book) [setCell $ui($w,book) $ui($w,active) $ui($w,formula)]
        if {[dict get $ui($w,book) options calculation_mode] eq "automatic"} {recalculate $ui($w,book)}
        _uiRefresh $w
    } message]} {_uiError $w $message; return}
    if {[dict get $ui($w,book) options calculation_mode] eq "automatic" && [dict exists $ui($w,book) operations] && [dict size [dict get $ui($w,book) operations]]} {
        if {[catch {set ui($w,book) [reapplyOperations $ui($w,book)]} message]} {set ui($w,status) "Operation refresh: $message"} else {_uiRefresh $w}
    }
    _uiSelect $w
}
proc ::GX::ScientificWorksheet::_uiRefresh {w} {
    variable ui; variable spill
    if {[info exists ui($w,detached)]} {
        foreach row $ui($w,detached) {if {[$w.grid.table exists $row]} {$w.grid.table delete $row}}
        set ui($w,detached) {}
    }
    _v1__uiRefresh $w
    set table $w.grid.table; set book $ui($w,book); set key [_key $book]
    $table column row -width 52 -stretch 0
    foreach col [dict get $book presentation display_columns] {
        set heading [$table heading $col -text]
        set width [expr {max(104,min(215,[string length $heading]*9+22))}]
        $table column $col -width $width -stretch 0
    }
    if {[dict exists $book hidden_rows]} {
        dict for {row unused} [dict get $book hidden_rows] {if {[$table exists $row]} {$table detach $row; lappend ui($w,detached) $row}}
    }
    if {[dict exists $spill $key]} {
        dict for {address item} [dict get $spill $key] {
            lassign [_parts $address] col row
            if {![$table exists $row] || $col > 12} continue
            set display [dict get $item value]
            if {![catch {format %.8g $display} formatted]} {set display $formatted}
            $table set $row [_columnName $col] $display
        }
    }
    foreach row [$table children {}] {
        foreach col [dict get $book presentation display_columns] {
            set address "$col$row"
            if {![dict exists $book cells $address] || ![catch {value $book $address} message]} continue
            set category "#VALUE!"
            if {[string match *Circular* $message] || [string match *#CIRC!* $message]} {set category "#CIRC!"}
            if {[string match *unit* [string tolower $message]] || [string match *#UNIT!* $message]} {set category "#UNIT!"}
            if {[string match *reference* [string tolower $message]] || [string match *#REF!* $message]} {set category "#REF!"}
            if {[string match *#SPILL!* $message]} {set category "#SPILL!"}
            $table set $row $col $category
        }
    }
    _uiTabs $w
    _uiDrawSelection $w
}
proc ::GX::ScientificWorksheet::_uiMove {w rowDelta colDelta} {
    variable ui
    lassign [_parts $ui($w,active)] col row
    set col [expr {max(1,min(12,$col+$colDelta))}]
    set row [expr {max(1,min(1000000,$row+$rowDelta))}]
    set ui($w,active) "[_columnName $col]$row"
    if {$row < $ui($w,first_row)+2 || $row >= $ui($w,first_row)+196} {
        set ui($w,first_row) [expr {max(1,$row-12)}]; _uiRefresh $w
    }
    if {[$w.grid.table exists $row]} {$w.grid.table see $row}
    _uiSelect $w; _uiSetSelection $w $ui($w,active) $ui($w,active) 0
}
proc ::GX::ScientificWorksheet::_uiMoveExtend {w rowDelta colDelta} {
    variable ui
    if {![info exists ui($w,anchor)]} {set ui($w,anchor) $ui($w,active)}
    _uiMove $w $rowDelta $colDelta
    _uiSetSelection $w $ui($w,anchor) $ui($w,active) 0
}
proc ::GX::ScientificWorksheet::_uiScroll {w amount} {
    variable ui
    set ui($w,first_row) [expr {max(1,min(999800,$ui($w,first_row)+$amount))}]
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiScrollbar {w args} {
    variable ui
    if {[lindex $args 0] eq "moveto"} {set row [expr {1+int([lindex $args 1]*999800)}]; set ui($w,first_row) $row
    } elseif {[lindex $args 0] eq "scroll"} {set amount [expr {[lindex $args 1]*([lindex $args 2] eq "pages" ? 25 : 3)}]; set ui($w,first_row) [expr {max(1,$ui($w,first_row)+$amount)}]}
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiCellAt {w x y} {
    set table $w.grid.table; set row [$table identify row $x $y]; set col [$table identify column $x $y]
    if {$row eq "" || $col eq ""} {return ""}
    set number [string range $col 1 end]
    if {$number < 2 || $number > 13} {return ""}
    return "[_columnName [expr {$number-1}]]$row"
}
proc ::GX::ScientificWorksheet::_uiSetSelection {w from to additive} {
    variable ui
    if {!$additive} {set ui($w,selections) {}}
    lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
    set from "[_columnName [expr {min($c1,$c2)}]][expr {min($r1,$r2)}]"
    set to "[_columnName [expr {max($c1,$c2)}]][expr {max($r1,$r2)}]"
    lappend ui($w,selections) [list $from $to]
    _uiDrawSelection $w
    _uiSelectionStatus $w
}
proc ::GX::ScientificWorksheet::_uiMousePress {w x y state} {
    variable ui
    set address [_uiCellAt $w $x $y]; if {$address eq ""} return
    if {[info exists ui($w,pick_reference)] && $ui($w,pick_reference)} {
        set ui($w,anchor) $address; set ui($w,reference_start) $address
        return
    }
    set shift [expr {($state & 0x1) != 0}]; set ctrl [expr {($state & 0x4) != 0}]
    if {!$shift} {set ui($w,anchor) $address}
    set ui($w,active) $address; _uiSelect $w
    _uiSetSelection $w $ui($w,anchor) $address $ctrl
}
proc ::GX::ScientificWorksheet::_uiMouseDrag {w x y} {
    variable ui
    set address [_uiCellAt $w $x $y]; if {$address eq "" || ![info exists ui($w,anchor)]} return
    if {[info exists ui($w,pick_reference)] && $ui($w,pick_reference)} {
        set ui($w,reference_end) $address; _uiSetSelection $w $ui($w,reference_start) $address 0
        return
    }
    set ui($w,active) $address; _uiSelect $w
    _uiSetSelection $w $ui($w,anchor) $address 0
}
proc ::GX::ScientificWorksheet::_uiMouseRelease {w x y} {
    variable ui
    if {![info exists ui($w,pick_reference)] || !$ui($w,pick_reference)} return
    set address [_uiCellAt $w $x $y]
    if {$address eq ""} {set address $ui($w,reference_start)}
    set ref $ui($w,reference_start)
    if {$address ne $ref} {append ref ":$address"}
    append ui($w,formula) $ref
    set ui($w,pick_reference) 0
    focus $w.formula.entry
}
proc ::GX::ScientificWorksheet::_uiPickReference {w} {
    variable ui
    set ui($w,pick_reference) 1
    set ui($w,status) "Drag over a cell or range to insert its reference into the formula bar."
}
proc ::GX::ScientificWorksheet::_uiAutocomplete {w} {
    variable ui
    set text $ui($w,formula)
    if {![regexp {([A-Za-z_][A-Za-z0-9_.!]*)$} $text unused prefix]} return
    set matches [dict keys [functionCatalog $prefix]]
    foreach name [dict keys [dict get $ui($w,book) columns]] {if {[string match -nocase "$prefix*" $name]} {lappend matches $name}}
    foreach name [dict keys [dict get $ui($w,book) ranges]] {if {[string match -nocase "$prefix*" $name]} {lappend matches $name}}
    foreach name [sheetNames $ui($w,book)] {if {[string match -nocase "$prefix*" $name]} {lappend matches "$name!"}}
    set matches [lsort -unique $matches]
    if {[llength $matches] == 1} {
        set found [lindex $matches 0]
        set suffix [expr {[dict exists [functionCatalog $found] $found] ? "(" : ""}]
        set ui($w,formula) "[string range $text 0 end-[string length $prefix]]$found$suffix"
    } else {set ui($w,status) "Completions: [join [lrange $matches 0 12] {, }]"}
}
proc ::GX::ScientificWorksheet::_uiRecalculateMode {w} {
    variable ui
    set mode [expr {[dict get $ui($w,book) options calculation_mode] eq "automatic" ? "manual" : "automatic"}]
    set ui($w,book) [setCalculationMode $ui($w,book) $mode]
    set ui($w,status) "Calculation mode: $mode"
    $w.extra.mode configure -text "Mode: $mode"
}
proc ::GX::ScientificWorksheet::_uiRecalculateScope {w scope} {
    variable ui
    if {[catch {
        set ui($w,book) [reapplyOperations $ui($w,book)]
        switch -- $scope {
            selection {
                if {[info exists ui($w,selections)] && [llength $ui($w,selections)]} {lassign [lindex $ui($w,selections) end] first last} else {set first $ui($w,active); set last $first}
                set result [recalculateSelection $ui($w,book) $first $last]
            }
            sheet {set result [recalculate $ui($w,book) 1]}
            workbook {set result [recalculateWorkbook $ui($w,book)]}
        }
        _uiRefresh $w; set ui($w,status) "Recalculated $scope."
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiDrawSelection {w} {
    variable ui
    if {![winfo exists $w.grid.table]} return
    set table $w.grid.table
    foreach child [winfo children $w.grid] {if {[string match *.outline* $child]} {destroy $child}}
    if {![info exists ui($w,selections)]} return
    set n 0
    foreach range $ui($w,selections) {
        lassign $range from to; lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
        set left [$table bbox $r1 #[expr {$c1+1}]]; set right [$table bbox $r2 #[expr {$c2+1}]]
        if {![llength $left] || ![llength $right]} continue
        lassign $left x1 y1 width height; lassign $right x2 y2 width height
        set color [expr {$n == [llength $ui($w,selections)]-1 ? "#1675b9" : "#719bb4"}]
        foreach {edge x y wid hei} [list top $x1 $y1 [expr {$x2+$width-$x1}] 2 bottom $x1 [expr {$y2+$height-2}] [expr {$x2+$width-$x1}] 2 left $x1 $y1 2 [expr {$y2+$height-$y1}] right [expr {$x2+$width-2}] $y1 2 [expr {$y2+$height-$y1}]] {
            frame $w.grid.outline${n}_$edge -background $color
            place $w.grid.outline${n}_$edge -x [expr {$x+[winfo x $table]}] -y [expr {$y+[winfo y $table]}] -width $wid -height $hei
        }
        incr n
    }
}
proc ::GX::ScientificWorksheet::selectionSummary {book from to {responsive 0}} {
    variable selectionSummaryCache
    lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
    if {$c2<$c1||$r2<$r1} {error {Selection range end must follow its start}}
    set count [expr {($c2-$c1+1)*($r2-$r1+1)}]
    set receipt [dict create from $from to $to cell_count $count numeric_count {} statistics {} status unavailable reason {}]
    if {$count>5000} {dict set receipt reason {Automatic summary is limited to 5000 cells};return $receipt}
    set numbers {};set units {}
    foreach address [rangeCells $from $to] {
        if {![dict exists $book cells $address]||[catch {set item [value $book $address]}]} continue
        if {[dict get $item kind] eq "scalar"&&[string is double -strict [dict get $item value]]&&![catch {expr {abs(double([dict get $item value]))<Inf}} finite]&&$finite} {
            lappend numbers [dict get $item value]
            set unit [dict get $item unit];if {$unit ni $units} {lappend units $unit}
        }
    }
    dict set receipt numeric_count [llength $numbers];dict set receipt units $units
    if {$numbers eq {}} {dict set receipt reason {No finite scalar numbers in the selected cells};return $receipt}
    if {[llength $units]!=1} {dict set receipt reason {Mixed units: convert the selected values to one declared unit before aggregation};return $receipt}
    set key [list $numbers $units $from $to]
    if {[info exists selectionSummaryCache]&&[lindex $selectionSummaryCache 0] eq $key} {return [lindex $selectionSummaryCache 1]}
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set command [expr {$responsive?"statisticsResponsive":"statistics"}]
    set raw [::GX::NumericAPIv1::$command $numbers]
    dict set receipt statistics [::GX::StatisticsV1::fromNumeric math.numeric.summary statistics $raw [dict create y_unit [lindex $units 0]] {} [dict create producer viewer.scientific_worksheet source_selection [list $from $to] finite_scalar_policy omit_nonfinite_text_errors_and_nonscalar]]
    dict set receipt status value
    set selectionSummaryCache [list $key $receipt]
    return $receipt
}
proc ::GX::ScientificWorksheet::_uiSelectionStatus {w} {
    variable ui
    if {![winfo exists $w]||![info exists ui($w,selections)]||![llength $ui($w,selections)]} return
    if {[info exists ui($w,summaryBusy)]&&$ui($w,summaryBusy)} {set ui($w,summaryPending) 1;return}
    lassign [lindex $ui($w,selections) end] from to
    set snapshot $ui($w,book);set token [::GX::interactiveDocumentSessionToken]
    set windowId [winfo id $w]
    set ui($w,summaryBusy) 1;set ui($w,summaryPending) 0
    set ui($w,status) "$from:$to · Computing selection summary…"
    set failed [catch {set receipt [selectionSummary $snapshot $from $to 1]} reason]
    if {![winfo exists $w]||[winfo id $w] ne $windowId||![info exists ui($w,book)]} return
    set ui($w,summaryBusy) 0
    if {$token ne [::GX::interactiveDocumentSessionToken]} return
    if {$ui($w,summaryPending)||$ui($w,book) ne $snapshot||[lindex $ui($w,selections) end] ne [list $from $to]} {
        after idle [list ::GX::ScientificWorksheet::_uiSelectionStatus $w]
        return
    }
    if {$failed} {
        set ui($w,status) "$from:$to · Summary unavailable: $reason"
        unset -nocomplain ui($w,summary)
        return
    }
    set ui($w,summary) $receipt
    set ui($w,status) "$from:$to · [dict get $receipt cell_count] cells"
    if {[dict get $receipt numeric_count] ne {}} {append ui($w,status) " · [dict get $receipt numeric_count] finite numbers"}
    if {[dict get $receipt status] eq "value"} {
        append ui($w,status) " · [::GX::StatisticsV1::report [dict get $receipt statistics] {sum mean}]"
    } else {append ui($w,status) " · [dict get $receipt reason]"}
}
proc ::GX::ScientificWorksheet::_uiBeginEdit {w} {
    variable ui
    set table $w.grid.table; set address $ui($w,active)
    lassign [_parts $address] col row
    if {![$table exists $row]} return
    set box [$table bbox $row #[expr {$col+1}]]; if {![llength $box]} return
    lassign $box x y width height
    catch {destroy $w.grid.editor}
    ttk::entry $w.grid.editor -textvariable ::GX::ScientificWorksheet::ui($w,edit_source)
    set ui($w,edit_source) [expr {[dict exists $ui($w,book) cells $address] ? [dict get $ui($w,book) cells $address source] : ""}]
    place $w.grid.editor -x [expr {$x+[winfo x $table]}] -y [expr {$y+[winfo y $table]}] -width $width -height $height
    focus $w.grid.editor; $w.grid.editor selection range 0 end
    bind $w.grid.editor <Return> [list ::GX::ScientificWorksheet::_uiEndEdit $w 1]
    bind $w.grid.editor <Escape> [list ::GX::ScientificWorksheet::_uiEndEdit $w 0]
}
proc ::GX::ScientificWorksheet::_uiEndEdit {w commit} {
    variable ui
    if {$commit} {set ui($w,formula) $ui($w,edit_source); _uiCommit $w}
    catch {destroy $w.grid.editor}
    focus $w.grid.table
}
proc ::GX::ScientificWorksheet::_uiCopy {w} {
    variable ui
    if {![info exists ui($w,selections)] || ![llength $ui($w,selections)]} {_uiSetSelection $w $ui($w,active) $ui($w,active) 0}
    lassign [lindex $ui($w,selections) end] from to; set ui($w,copy_origin) $from
    lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
    set lines {}; set book $ui($w,book)
    for {set r $r1} {$r <= $r2} {incr r} {
        set fields {}
        for {set c $c1} {$c <= $c2} {incr c} {
            set address "[_columnName $c]$r"
            lappend fields [expr {[dict exists $book cells $address] ? [dict get $book cells $address source] : ""}]
        }
        lappend lines [join $fields "\t"]
    }
    set text [join $lines "\n"]; set ui($w,copy_text) $text
    clipboard clear -displayof $w; clipboard append -displayof $w $text
}
proc ::GX::ScientificWorksheet::_uiPaste {w} {
    variable ui
    if {[catch {set text [clipboard get -displayof $w]}]} return
    if {[string length $text] > 2000000} {_uiError $w "Paste exceeds 2 MB."; return}
    _uiRemember $w
    lassign [_parts $ui($w,active)] c0 r0
    set shift [expr {[info exists ui($w,copy_text)] && $text eq $ui($w,copy_text) && [info exists ui($w,copy_origin)]}]
    if {$shift} {lassign [_parts $ui($w,copy_origin)] sourceC sourceR}
    set book $ui($w,book); set r $r0
    if {[catch {
        foreach line [split [string trimright $text "\r\n"] "\n"] {
            set c $c0
            foreach source [split [string trimright $line "\r"] "\t"] {
                if {$shift} {set source [shiftFormula $source [expr {$r0-$sourceR}] [expr {$c0-$sourceC}]]}
                set book [setCell $book "[_columnName $c]$r" $source]; incr c
            }
            incr r
        }
        set ui($w,book) $book; _uiRefresh $w
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiTabs {w} {
    variable ui
    if {![winfo exists $w.sheets]} return
    foreach child [winfo children $w.sheets] {destroy $child}
    foreach name [sheetNames $ui($w,book)] {
        set label [expr {$name eq [activeSheet $ui($w,book)] ? "● $name" : $name}]
        ttk::button $w.sheets.s_[string map {" " _} $name] -text $label -command [list ::GX::ScientificWorksheet::_uiSwitchSheet $w $name]
        pack $w.sheets.s_[string map {" " _} $name] -side left -padx 2
    }
    ttk::button $w.sheets.add -text + -width 3 -command [list ::GX::ScientificWorksheet::_uiSheetAction $w create]
    pack $w.sheets.add -side left -padx 4
}
proc ::GX::ScientificWorksheet::_uiSwitchSheet {w sheet} {
    variable ui
    set ui($w,book) [selectSheet $ui($w,book) $sheet]
    set ui($w,first_row) 1; set ui($w,active) A1; _uiSelect $w; _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiSheetAction {w action} {
    variable ui
    if {$action eq "delete"} {
        set old [activeSheet $ui($w,book)]
        if {[tk_messageBox -parent $w -type yesno -icon warning -title "Delete sheet" -message "Delete sheet '$old' and its cells? This can be undone until Save."] ne "yes"} return
        _uiRemember $w
        if {[catch {set ui($w,book) [deleteSheet $ui($w,book) $old]} message]} {_uiError $w $message; return}
        _uiRefresh $w; return
    }
    set d $w.sheetdialog; catch {destroy $d}; toplevel $d; wm title $d "[string totitle $action] sheet"
    set ui($w,sheet_name) [expr {$action eq "rename" ? [activeSheet $ui($w,book)] : "Sheet[expr {[llength [sheetNames $ui($w,book)]]+1}]"}]
    ttk::label $d.help -text "Sheet name"; ttk::entry $d.name -textvariable ::GX::ScientificWorksheet::ui($w,sheet_name)
    ttk::button $d.go -text Apply -command [list ::GX::ScientificWorksheet::_uiApplySheetAction $w $action]
    pack $d.help $d.name $d.go -fill x -padx 8 -pady 5; focus $d.name
}
proc ::GX::ScientificWorksheet::_uiApplySheetAction {w action} {
    variable ui
    set book $ui($w,book); set name $ui($w,sheet_name); set old [activeSheet $book]
    _uiRemember $w
    if {[catch {
        switch -- $action {
            create {set book [createSheet $book $name]}
            rename {set book [renameSheet $book $old $name]}
            duplicate {set book [duplicateSheet $book $old $name]}
        }
        set ui($w,book) $book; destroy $w.sheetdialog; _uiRefresh $w
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiSave {w} {variable ui; set ui($w,book) [_flush $ui($w,book)]; _v1__uiSave $w}
proc ::GX::ScientificWorksheet::_uiLoadSelected {w d} {
    _v1__uiLoadSelected $w $d
    variable ui; set ui($w,book) [_upgrade $ui($w,book)]
    _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiFill {w mode} {
    variable ui
    if {![info exists ui($w,selections)] || ![llength $ui($w,selections)]} return
    lassign [lindex $ui($w,selections) end] from to
    lassign [_parts $from] c1 r1; lassign [_parts $to] c2 r2
    _uiRemember $w
    if {[catch {
        set book $ui($w,book)
        if {$mode eq "down"} {
            for {set c $c1} {$c <= $c2} {incr c} {set book [fillRange $book "[_columnName $c]$r1" "[_columnName $c]$r2"]}
        } else {
            for {set r $r1} {$r <= $r2} {incr r} {set book [fillRange $book "[_columnName $c1]$r" "[_columnName $c2]$r"]}
        }
        set ui($w,book) $book; _uiRefresh $w
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiClear {w} {
    variable ui
    if {![info exists ui($w,selections)] || ![llength $ui($w,selections)]} {_uiSetSelection $w $ui($w,active) $ui($w,active) 0}
    lassign [lindex $ui($w,selections) end] first last
    _uiRemember $w; set ui($w,book) [clearRange $ui($w,book) $first $last]; _uiRefresh $w
}
proc ::GX::ScientificWorksheet::_uiImportDialog {w} {
    variable ui
    _v1__uiImportDialog $w
    set d $w.import
    ttk::label $d.choose -text "Select source variables (Ctrl/Shift for multiple). IDs, types, and units are shown below."
    listbox $d.variables -selectmode extended -height 9 -width 65 -exportselection 0
    ttk::label $d.startlabel -text "Destination start column"
    ttk::combobox $d.start -values {A B C D E F G H I J K L} -textvariable ::GX::ScientificWorksheet::ui($w,import_start) -state readonly
    set ui($w,import_start) A
    pack $d.choose $d.variables $d.startlabel $d.start -before $d.go -fill x -padx 6 -pady 3
    ttk::combobox $d.selections -values [::GX::sessionInspectionSelectionIds] -textvariable ::GX::ScientificWorksheet::ui($w,import_selection)
    pack $d.selections -before $d.go -fill x -padx 6
    bind $d.datasets <<ComboboxSelected>> [list ::GX::ScientificWorksheet::_uiImportVariables $w]
    if {[llength [::GX::sessionInspectionDatasetIds]]} {set ui($w,import_dataset) [lindex [::GX::sessionInspectionDatasetIds] 0]; _uiImportVariables $w}
    set ui($w,import_mappings) ""
}
proc ::GX::ScientificWorksheet::_uiImportVariables {w} {
    variable ui; set d $w.import
    $d.variables delete 0 end; set ui($w,import_schema) {}
    if {$ui($w,import_dataset) eq ""} return
    foreach variable [::GX::datasetVariableSchema $ui($w,import_dataset)] {
        set id [dict get $variable variable_id]; lappend ui($w,import_schema) $id
        set name [expr {[dict exists $variable display_name] ? [dict get $variable display_name] : [dict get $variable canonical]}]
        set role [expr {[dict exists $variable coordinate_role] ? [dict get $variable coordinate_role] : ""}]
        $d.variables insert end "$name · $id · [dict get $variable value_kind] · [dict get $variable unit] · $role"
    }
}
proc ::GX::ScientificWorksheet::_uiImport {w d} {
    variable ui
    set chosen [$d.variables curselection]
    if {![llength $chosen]} {_uiRemember $w; _v1__uiImport $w $d; return}
    set c [_columnNumber $ui($w,import_start)]; set mappings [dict create]
    foreach index $chosen {dict set mappings [_columnName $c] [lindex $ui($w,import_schema) $index]; incr c}
    _uiRemember $w
    if {[catch {
        lassign [bindDataset $ui($w,book) $ui($w,import_dataset) $mappings $ui($w,import_first) $ui($w,import_limit) $ui($w,import_selection)] book count
        set ui($w,book) $book; _uiRefresh $w; set ui($w,status) "Imported $count rows from $ui($w,import_dataset). Save to retain the binding snapshot."; destroy $d
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiSortFilter {w} {
    variable ui; set d $w.sort; catch {destroy $d}; toplevel $d; wm title $d "Sort and filter Worksheet rows"
    foreach {key label default} {column {Column (e.g. A)} A second {Second sort column (optional)} {} first {First row} 1 last {Last row} 100 operand {Filter value} {}} {
        set ui($w,sort_$key) $default
        ttk::label $d.l_$key -text $label; ttk::entry $d.e_$key -textvariable ::GX::ScientificWorksheet::ui($w,sort_$key)
        pack $d.l_$key $d.e_$key -fill x -padx 6
    }
    ttk::combobox $d.direction -values {ascending descending} -textvariable ::GX::ScientificWorksheet::ui($w,sort_direction) -state readonly
    set ui($w,sort_direction) ascending
    ttk::combobox $d.comparator -values {contains equals greater less} -textvariable ::GX::ScientificWorksheet::ui($w,sort_comparator) -state readonly
    set ui($w,sort_comparator) contains
    pack $d.direction $d.comparator -fill x -padx 6
    foreach {button label action} {sort Sort sort filter Filter filter show {Show all} show restore {Restore order} restore} {
        ttk::button $d.$button -text $label -command [list ::GX::ScientificWorksheet::_uiApplySortFilter $w $action]; pack $d.$button -side left -padx 4 -pady 6
    }
}
proc ::GX::ScientificWorksheet::_uiApplySortFilter {w action} {
    variable ui
    _uiRemember $w
    if {[catch {
        set book $ui($w,book); set first $ui($w,sort_first); set last $ui($w,sort_last); set col $ui($w,sort_column)
        switch -- $action {
            sort {set columns [list $col]; if {$ui($w,sort_second) ne ""} {lappend columns $ui($w,sort_second)}; set book [sortRows $book $first $last $columns [lrepeat [llength $columns] $ui($w,sort_direction)]]}
            filter {set book [filterRows $book $col $ui($w,sort_comparator) $ui($w,sort_operand) $first $last]}
            show {set book [showAllRows $book]}
            restore {set book [restoreRowOrder $book $first $last]}
        }
        set ui($w,book) $book; _uiRefresh $w
    } message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiConvertDialog {w} {
    variable ui; set d $w.convert; catch {destroy $d}; toplevel $d; wm title $d "Convert selected cells with Unit Registry"
    ttk::label $d.label -text "Destination unit"
    ttk::combobox $d.units -values [::GX::unitRegistryList] -textvariable ::GX::ScientificWorksheet::ui($w,target_unit) -state readonly
    ttk::button $d.apply -text Convert -command [list ::GX::ScientificWorksheet::_uiConvert $w]
    pack $d.label $d.units $d.apply -fill x -padx 8 -pady 5
}
proc ::GX::ScientificWorksheet::_uiConvert {w} {
    variable ui
    if {![info exists ui($w,selections)] || ![llength $ui($w,selections)]} {_uiSetSelection $w $ui($w,active) $ui($w,active) 0}
    lassign [lindex $ui($w,selections) end] first last
    _uiRemember $w
    if {[catch {set ui($w,book) [convertUnit $ui($w,book) $first $last $ui($w,target_unit)]; _uiRefresh $w; destroy $w.convert} message]} {_uiError $w $message}
}
proc ::GX::ScientificWorksheet::_uiGoto {w kind} {
    variable ui
    lassign [_parts $ui($w,active)] col row
    switch -- $kind {
        home {set col 1}
        end {set col 12}
        ctrl_home {set col 1; set row 1}
        ctrl_end {
            set row 1; set col 1
            foreach address [dict keys [dict get $ui($w,book) cells]] {lassign [_parts $address] c r; set col [expr {max($col,$c)}]; set row [expr {max($row,$r)}]}
            set col [expr {min($col,12)}]
        }
    }
    set ui($w,active) "[_columnName $col]$row"
    if {$row < $ui($w,first_row) || $row > $ui($w,first_row)+199} {set ui($w,first_row) [expr {max(1,$row-12)}]; _uiRefresh $w}
    _uiSelect $w; _uiSetSelection $w $ui($w,active) $ui($w,active) 0
}
proc ::GX::ScientificWorksheet::open {{context {}}} {
    variable ui; variable undo; variable redo
    package require Tk
    if {[winfo exists .scientific_worksheet]} {raise .scientific_worksheet;return .scientific_worksheet}
    set ui(.scientific_worksheet,selections) {}
    set ui(.scientific_worksheet,summaryBusy) 0
    set ui(.scientific_worksheet,summaryPending) 0
    unset -nocomplain ui(.scientific_worksheet,summary)
    set w [_v1_open $context]
    set ui($w,book) [_upgrade $ui($w,book)]
    set ui($w,selections) {}; set undo($w) {}; set redo($w) {}
    pack forget $w.footer.previous $w.footer.next
    ttk::frame $w.actions -padding 4
    pack $w.actions -before $w.formula -fill x
    ttk::frame $w.extra -padding 4
    pack $w.extra -before $w.formula -fill x
    ttk::frame $w.sheets -padding 3
    pack $w.sheets -before $w.footer -fill x
    foreach {name label command} {
        undo Undo _uiUndo redo Redo _uiRedo filldown {Fill Down} _uiFill fillright {Fill Right} _uiFill clear Clear _uiClear sort {Sort / Filter} _uiSortFilter convert {Convert Unit} _uiConvertDialog
        rename {Rename Sheet} _uiSheetAction duplicate {Duplicate Sheet} _uiSheetAction delete {Delete Sheet} _uiSheetAction
    } {
        switch -- $name {
            filldown {set script [list ::GX::ScientificWorksheet::$command $w down]}
            fillright {set script [list ::GX::ScientificWorksheet::$command $w right]}
            rename {set script [list ::GX::ScientificWorksheet::$command $w rename]}
            duplicate {set script [list ::GX::ScientificWorksheet::$command $w duplicate]}
            delete {set script [list ::GX::ScientificWorksheet::$command $w delete]}
            default {set script [list ::GX::ScientificWorksheet::$command $w]}
        }
        ttk::button $w.actions.$name -text $label -command $script
        pack $w.actions.$name -side left -padx 1
    }
    bind $w.grid.table <ButtonPress-1> [list ::GX::ScientificWorksheet::_uiMousePress $w %x %y %s]
    bind $w.grid.table <B1-Motion> [list ::GX::ScientificWorksheet::_uiMouseDrag $w %x %y]
    bind $w.grid.table <ButtonRelease-1> [list ::GX::ScientificWorksheet::_uiMouseRelease $w %x %y]
    bind $w.grid.table <<TreeviewSelect>> {}
    bind $w.grid.table <Double-1> [list ::GX::ScientificWorksheet::_uiBeginEdit $w]
    bind $w.grid.table <F2> [list ::GX::ScientificWorksheet::_uiBeginEdit $w]
    bind $w.grid.table <Return> [list ::GX::ScientificWorksheet::_uiBeginEdit $w]
    bind $w.grid.table <Delete> [list ::GX::ScientificWorksheet::_uiClear $w]
    bind $w.grid.table <MouseWheel> [list ::GX::ScientificWorksheet::_uiScroll $w -3]
    bind $w.grid.table <Button-4> [list ::GX::ScientificWorksheet::_uiScroll $w -3]
    bind $w.grid.table <Button-5> [list ::GX::ScientificWorksheet::_uiScroll $w 3]
    bind $w.grid.table <Prior> [list ::GX::ScientificWorksheet::_uiMove $w -25 0]
    bind $w.grid.table <Next> [list ::GX::ScientificWorksheet::_uiMove $w 25 0]
    bind $w.grid.table <Home> [list ::GX::ScientificWorksheet::_uiGoto $w home]
    bind $w.grid.table <End> [list ::GX::ScientificWorksheet::_uiGoto $w end]
    bind $w.grid.table <Control-Home> [list ::GX::ScientificWorksheet::_uiGoto $w ctrl_home]
    bind $w.grid.table <Control-End> [list ::GX::ScientificWorksheet::_uiGoto $w ctrl_end]
    bind $w.grid.table <Control-z> [list ::GX::ScientificWorksheet::_uiUndo $w]
    bind $w.grid.table <Control-y> [list ::GX::ScientificWorksheet::_uiRedo $w]
    ttk::button $w.extra.pick -text "Pick Reference" -command [list ::GX::ScientificWorksheet::_uiPickReference $w]
    pack $w.extra.pick -side left -padx 1
    ttk::button $w.extra.mode -text "Mode: [dict get $ui($w,book) options calculation_mode]" -command [list ::GX::ScientificWorksheet::_uiRecalculateMode $w]
    pack $w.extra.mode -side left -padx 1
    foreach {name label} {selection {Recalc Selection} sheet {Recalc Sheet} workbook {Recalc Workbook}} {
        ttk::button $w.extra.$name -text $label -command [list ::GX::ScientificWorksheet::_uiRecalculateScope $w $name]
        pack $w.extra.$name -side left -padx 1
    }
    foreach {event dr dc} {<Shift-Up> -1 0 <Shift-Down> 1 0 <Shift-Left> 0 -1 <Shift-Right> 0 1} {
        bind $w.grid.table $event "[list ::GX::ScientificWorksheet::_uiMoveExtend $w $dr $dc]; break"
    }
    $w.grid.sy configure -command [list ::GX::ScientificWorksheet::_uiScrollbar $w]
    _uiTabs $w; _uiRefresh $w
    return $w
}

foreach method {functionCatalog functionHelp _call _uiFunctionBrowser _uiFunctionSearch _uiFunctionHelp} {
    rename ::GX::ScientificWorksheet::$method ::GX::ScientificWorksheet::_v1_$method
}
proc ::GX::ScientificWorksheet::functionCatalog {{query ""}} {
    set out [_v1_functionCatalog $query]
    foreach {provider api namespace prefix} {
        math.numeric NUMERIC_API_v1 NumericAPIv1 numeric
        math.signal SIGNAL_API_v1 SignalAPIv1 signal
        math.rf_network RF_NETWORK_API_v1 RFNetworkAPIv1 rf
        math.magnetics MAGNETICS_API_v1 MagneticsAPIv1 magnetics
    } {
        ::GX::modulePublicApiActivate $provider $api
        foreach id [::GX::${namespace}::listOperations] {
            set meta [::GX::${namespace}::operationMetadata $id]
            set name "$prefix.$id"
            if {$query ne "" && ![string match -nocase "*$query*" "$name [dict get $meta summary]"]} continue
            dict set meta worksheet_name $name; dict set meta provider_id $provider
            if {$provider eq "math.numeric"} {
                set family [lindex [split $id .] 0]
                set supported {array_unary array_binary array_compare array_reduce array_mask array_select array_where interpolate resample integrate cumulative_integrate differentiate rank correlation covariance mad}
                set category [expr {[lsearch -exact [dict get $meta flags] expression] >= 0 && [dict get $meta expression_name] ne "" && $family in $supported ? "formula" : "guided"}]
                if {[lsearch -exact [dict get $meta flags] callback] >= 0} {
                    set kinds [::GX::NumericAPIv1::modelKinds $id]
                    set category guided; dict set meta model_kinds $kinds
                    dict set meta worksheet_reason "Choose a provider-owned declarative model: [join $kinds {, }]."
                }
                if {$id eq "configure_fft_threads"} {set category unavailable; dict set meta worksheet_reason "Changes the worker's process configuration, not a Worksheet calculation."}
                if {$id eq "foundation"} {set category unavailable; dict set meta worksheet_reason "Dispatcher group; browse its 115 named foundation actions."}
                dict set meta worksheet_category $category
                if {![dict exists $meta signature]} {dict set meta signature [format {%s(%s)} $name [join [dict get $meta arguments] {, }]]}
                if {![dict exists $meta worksheet_example]} {dict set meta worksheet_example "Use ranges A1:A20 and B1:B20 or scalar cells as indicated by the argument names."}
            } else {dict set meta worksheet_category guided}
            if {[dict exists $meta operation_kind]&&[dict get $meta operation_kind] eq "metadata"} {
                dict set meta worksheet_category unavailable
                dict set meta worksheet_reason {Describes an API result contract; does not calculate Worksheet cell values.}
            }
            dict set out $name $meta
        }
        if {$provider eq "math.numeric"} {
            foreach id [::GX::NumericAPIv1::listFoundationOperations] {
                set meta [::GX::NumericAPIv1::foundationOperationMetadata $id]; set name "numeric.foundation.$id"
                if {$query ne "" && ![string match -nocase "*$query*" "$name [dict get $meta summary]"]} continue
                dict set meta worksheet_name $name; dict set meta provider_id $provider
                if {[lsearch -exact [dict get $meta flags] callback] >= 0} {
                    set kinds [::GX::NumericAPIv1::modelKinds "foundation.$id"]
                    dict set meta model_kinds $kinds
                    dict set meta worksheet_reason "Choose a provider-owned declarative model: [join $kinds {, }]."
                }
                dict set meta worksheet_category guided
                dict set out $name $meta
            }
        }
    }
    return $out
}
proc ::GX::ScientificWorksheet::functionHelp {name} {
    set catalog [functionCatalog $name]
    if {![dict exists $catalog $name]} {error "Unknown Worksheet function '$name'."}
    set meta [dict get $catalog $name]
    set out "$name — [dict get $meta summary]\n"
    foreach key {signature arguments argument_descriptors input_shapes shape_semantics unit_behavior units result_fields result_shape worksheet_example worksheet_reason} {
        if {[dict exists $meta $key]} {append out "[string totitle [string map {_ { }} $key]]: [dict get $meta $key]\n"}
    }
    append out "Worksheet mode: [expr {[dict exists $meta worksheet_category] ? [dict get $meta worksheet_category] : "formula"}]\n"
    append out "Provider: [dict get $meta provider_id] · [dict get $meta api_id]"
    return $out
}
proc ::GX::ScientificWorksheet::_call {name args} {
    if {$name eq "field"&&[llength $args] in {2 4}&&[dict get [lindex $args 0] kind] eq "struct"&&[dict exists [lindex $args 0] captured_statistics]} {
        set source [lindex $args 0];set field [dict get [lindex $args 1] value];set window {}
        if {[llength $args]==4} {
            foreach item [lrange $args 2 3] {if {[dict get $item kind] ne "scalar"||[dict get $item unit] ni {{} 1}||![string is integer -strict [dict get $item value]]} {error {Result row selection requires dimensionless integer first row and count}}}
            set first [dict get [lindex $args 2] value];set count [dict get [lindex $args 3] value]
            set window [dict create start [expr {$first-1}] count $count]
        }
        set statistics [dict get $source captured_statistics]
        if {[dict exists [_capturedStatisticalFieldMap $statistics] $field]} {return [_carryStatistics [_statisticalFieldItem $statistics $field $window] $args]}
        if {[dict exists [::GX::StatisticsV1::numericDataFields $statistics] fields $field]} {
            return [_carryStatistics [_statisticalDataFieldItem $statistics $field [dict get $source value $field] $window 0 [dict get $source value]] $args]
        }
        if {$window ne {}} {error {Result row selection requires a captured statistical field}}
    }
    if {[string match "signal.*" $name]} {
        set catalog [functionCatalog $name]
        if {[dict exists $catalog $name]} {
            set operands $args;set options {}
            if {[llength $args]==4&&[dict get [lindex $args end] kind] eq "record"} {set options [dict get [lindex $args end] value];set operands [lrange $args 0 2]}
            set spec [_signalCaptureSpec [dict get $catalog $name] $operands $options]
            variable evaluationDocument
            if {$spec ne {}&&[dict get $spec profile] eq "signal_spectral"&&$evaluationDocument ne {}} {
                set typedOptions {};dict for {key item} $options {dict set typedOptions $key [_typed $item]}
                set raw [_capturedSignalCall $evaluationDocument $spec $operands [::GX::ScientificTransportv1::struct $typedOptions]]
                set result [_carryStatistics [_value [dict get $raw values] {} struct] $args]
                set statistics [dict get $raw captured_statistics]
                dict set result captured_statistics $statistics;dict lappend result statistical_sources $statistics
                return $result
            }
            set result [_carryStatistics [_v1__call $name {*}$args] $args]
            if {$spec ne {}} {
                set statistics [_signalStatistics $spec [dict get $result value]]
                dict set result captured_statistics $statistics;dict lappend result statistical_sources $statistics
            }
            return $result
        }
    }
    if {![string match "numeric.*" $name]} {return [_carryStatistics [_v1__call $name {*}$args] $args]}
    set catalog [functionCatalog $name]
    if {![dict exists $catalog $name]} {return [_carryStatistics [_v1__call $name {*}$args] $args]}
    set meta [dict get $catalog $name]
    if {![dict exists $meta worksheet_category] || [dict get $meta worksheet_category] eq "formula"} {return [_carryStatistics [_v1__call $name {*}$args] $args]}
    if {[dict get $meta worksheet_category] eq "unavailable"} {error "#VALUE! [dict get $meta worksheet_reason]"}
    if {[dict exists $meta parent_operation] && [dict get $meta parent_operation] eq "foundation"} {
        set options [::GX::ScientificTransportv1::struct [dict create]]
        if {[llength $args]==4&&[dict get [lindex $args end] kind] eq "record"} {set options [_typed [lindex $args end]];set args [lrange $args 0 2]}
        if {[llength $args]>3} {error {Foundation calculation accepts three operands and an optional record}}
        set typed [_numericTypedArguments $meta $args]
        while {[llength $typed] < 3} {lappend typed [::GX::ScientificTransportv1::empty]}
        variable evaluationDocument
        if {$evaluationDocument ne {}&&[_foundationCaptureApplies $meta]} {
            set captured [_capturedFoundationCall $evaluationDocument $meta $args $options]
            set result [_carryStatistics [_value [dict get $captured values] {} struct] $args]
            set statistics [dict get $captured captured_statistics]
            dict set result captured_statistics $statistics;dict lappend result statistical_sources $statistics
            return $result
        }
        set raw [::GX::NumericAPIv1::foundation [dict get $meta family] [dict get $meta action] {*}[lrange $typed 0 2] $options]
    } else {
        set options [::GX::ScientificTransportv1::struct [dict create]]
        if {[llength $args] > [dict get $meta arity_max] && [dict get [lindex $args end] kind] eq "record"} {
            set options [_typed [lindex $args end]]; set args [lrange $args 0 end-1]
        }
        set raw [::GX::NumericAPIv1::callOperation [dict get $meta id] [_numericTypedArguments $meta $args] $options]
    }
    set result [_carryStatistics [_value $raw "" struct] $args]
    set statistics [_numericStatistics $meta $args $raw]
    if {$statistics ne {}} {dict set result captured_statistics $statistics;dict lappend result statistical_sources $statistics}
    return $result
}
proc ::GX::ScientificWorksheet::_uiFunctionBrowser {w} {
    _v1__uiFunctionBrowser $w
    set d $w.functions
    $d.tree heading api -text Mode
    ttk::button $d.apply -text "Apply..." -command [list ::GX::ScientificWorksheet::_uiApplyFunctionDialog $w $d]
    pack $d.apply -side right -padx 4
    _uiFunctionSearch $w $d
}
proc ::GX::ScientificWorksheet::_uiFunctionSearch {w d} {
    variable ui
    $d.tree delete [$d.tree children {}]
    set catalog [functionCatalog $ui($w,function_query)]
    foreach category {{General Numeric} {Linear Algebra} {Calculus} {Interpolation} {Fitting / Optimization} {Differential Equations} Statistics Geometry {Signal Processing} {RF / Network} {Magnetics / Field} Other} {
        $d.tree insert {} end -id "category:$category" -text $category -open 1
    }
    dict for {name meta} $catalog {
        if {[string match "numeric.foundation.*" $name]} {set group [dict get $meta family]} elseif {[dict exists $meta category]} {set group [dict get $meta category]} else {set group [lindex [split [dict get $meta id] .] 0]}
        switch -glob -- "$name/$group" {
            numeric.*/matrix - numeric.*/tensor - numeric.*/linear_matrix {set category "Linear Algebra"}
            numeric.*/calculus - numeric.*/integrat* - numeric.*/differentiat* {set category Calculus}
            numeric.*/interpolat* - numeric.*/resampl* - numeric.*/splin* {set category Interpolation}
            numeric.*/fitting - numeric.*/optimization - numeric.*/least_squares - numeric.*/linear_regression - numeric.*/polynomial_fit {set category "Fitting / Optimization"}
            numeric.*/ode {set category "Differential Equations"}
            numeric.*/statistics - numeric.*/reduction - numeric.*/probability {set category Statistics}
            numeric.*/geometry {set category Geometry}
            signal.*/* - numeric.*/signal {set category "Signal Processing"}
            rf.*/* {set category "RF / Network"}
            magnetics.*/* {set category "Magnetics / Field"}
            numeric.*/* {set category "General Numeric"}
            default {set category Other}
        }
        set mode [expr {[dict exists $meta worksheet_category] ? [dict get $meta worksheet_category] : "formula"}]
        $d.tree insert "category:$category" end -id $name -text $name -values [list $mode [dict get $meta summary]]
    }
}
proc ::GX::ScientificWorksheet::_uiFunctionHelp {w d} {
    set selected [lindex [$d.tree selection] 0]
    if {$selected eq "" || [string match "category:*" $selected]} return
    $d.help configure -state normal; $d.help delete 1.0 end; $d.help insert 1.0 [functionHelp $selected]; $d.help configure -state disabled
}
proc ::GX::ScientificWorksheet::_expressionValue {book source} {
    set book [_upgrade $book]
    _ensureCalculationSnapshot $book
    set source [string trim $source]
    if {$source eq ""} {return [_value "" "" empty]}
    set tokens [_tokenize $source]; set index 0
    set result [_parseComparison $book $tokens index {}]
    if {[_peek $tokens $index] ne ""} {error "#VALUE! Unexpected input near column [lindex [lindex $tokens $index] 2]."}
    return $result
}
proc ::GX::ScientificWorksheet::_numericStatistics {meta args raw} {
    set id [dict get $meta id]
    if {$id eq "prediction_uncertainty"} {return [::GX::StatisticsV1::predictionInterpretation [_predictionSource $args] $raw]}
    if {[dict exists $meta parent_operation]} {set id "[dict get $meta parent_operation].$id"}
    set unmapped [catch {::GX::StatisticsV1::numericFieldMap $id} reason detail]
    if {$unmapped} {
        if {[dict get $detail -errorcode] eq {GXTXT STATISTICS UNKNOWN_NUMERIC_OPERATION}} {return {}}
        return -options $detail $reason
    }
    # The operation's provider owns its default model association. Models that
    # require explicit identities remain on their separately audited path.
    set selector {}
    if {$id eq "linear_regression"&&[dict exists $raw has_intercept]} {dict set selector has_intercept [dict get $raw has_intercept]}
    if {[catch {set model [::GX::StatisticsV1::numericModel $id $selector]} reason detail]} {
        if {[dict get $detail -errorcode] eq {GXTXT STATISTICS NUMERIC_MODEL_REQUIRED}} {return {}}
        return -options $detail $reason
    }
    set context [dict create x_unit {} y_unit {}]
    if {[string match dataset_* $id]} {set context {}}
    if {[llength $args]&&[dict get [lindex $args 0] kind] in {scalar vector matrix}} {dict set context y_unit [dict get [lindex $args 0] unit]}
    set lineage {};set inputUnits {}
    foreach name [dict get $meta arguments] item $args {
        if {$item eq {}} continue
        if {[dict exists $item mixed_units]&&[dict get $item mixed_units]} {error {Statistical input contains mixed units; convert values explicitly before aggregation}}
        set unit [dict get $item unit];dict set inputUnits $name $unit
        if {$name in {x frequency}} {dict set context x_unit $unit}
        if {$name in {values y response observed first_values distribution}} {dict set context y_unit $unit}
        if {$name eq "weights"} {dict set context weight_unit $unit}
        foreach source [_sourceLineage $item] {dict set lineage $source 1}
    }
    foreach {first second} {observed predicted first_values second_values} {
        if {[dict exists $inputUnits $first]&&[dict exists $inputUnits $second]&&[dict get $inputUnits $first] ne [dict get $inputUnits $second]} {
            set secondItem [lindex $args [lsearch -exact [dict get $meta arguments] $second]]
            if {[dict get $secondItem kind] ne "empty"} {error {Statistical samples have incompatible units; convert values explicitly}}
        }
    }
    set provenance [dict create producer viewer.scientific_worksheet]
    if {[dict size $lineage]} {dict set provenance source_variables [dict keys $lineage]}
    if {[dict get $model profile] eq "foundation_regression"&&[llength $args]>=2} {dict set context y_unit [dict get [lindex $args 1] unit]}
    if {$id in {matrix_statistics reduce_summary}&&[dict exists $raw output_shape]} {
        set shape [dict get $raw output_shape];lassign $shape rows columns
        if {[llength $shape]!=2||![string is integer -strict $rows]||![string is integer -strict $columns]||$rows<1||$columns<1} {error {Numeric returned an invalid reduction output shape}}
        if {$rows*$columns>1} {
            set rawColumns {};set common $raw;set ids {}
            set countField [expr {$id eq "matrix_statistics" ? "n" : "count"}]
            dict for {field quantity} [::GX::StatisticsV1::numericFieldMap $id] {
                if {$field eq $countField} continue
                dict set rawColumns $field [dict get $raw $field];dict unset common $field
            }
            for {set row 1} {$row<=$rows} {incr row} {for {set column 1} {$column<=$columns} {incr column} {lappend ids reduction_r${row}_c${column}}}
            dict set provenance worksheet_shape $shape
            dict set provenance worksheet_field_shapes $countField {1 1}
            return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $rawColumns $common $context $provenance]
        }
    }
    if {$id eq "foundation.statistics.survival_kaplan_meier"} {
        set common $raw;set columns {};set ids {};set index 0
        foreach field {time survival at_risk events censored} {dict set columns $field [dict get $raw $field];dict unset common $field}
        foreach value [dict get $raw time] {lappend ids coordinate_[incr index]}
        dict set context x_unit [dict get [lindex $args 0] unit]
        dict set provenance worksheet_field_shapes n {1 1}
        return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $columns $common $context $provenance]
    }
    if {$id eq "foundation.statistics.multiple_testing"} {
        set common $raw;set columns {};set ids {}
        foreach field {adjusted_p original_p hypothesis_index} {dict set columns $field [dict get $raw $field];dict unset common $field}
        foreach index [dict get $raw hypothesis_index] {lappend ids hypothesis_$index}
        dict set provenance worksheet_field_shapes family_size {1 1}
        return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $columns $common $context $provenance]
    }
    if {[dict get $model profile] eq "local_cloud"} {
        if {[dict get $inputUnits query] ne [dict get $inputUnits x]} {error {Local query and source X units differ; convert explicitly}}
        set columns {};set common $raw;set ids {};set i 0
        dict for {field quantity} [::GX::StatisticsV1::numericFieldMap $id] {dict set columns $field [dict get $raw $field];dict unset common $field}
        foreach value [dict get $raw query] {lappend ids query_[incr i]}
        return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $columns $common $context $provenance]
    }
    if {[dict get $model profile] eq "welch_spectrum"} {
        set context [dict create x_unit Hz y_unit [dict get $inputUnits sum_amplitude]]
        set psdUnit [dict get $inputUnits sum_psd];if {$psdUnit eq {}} {set psdUnit unspecified}
        dict set context psd_unit $psdUnit
    }
    if {[dict get $model profile] eq "power_level"} {
        set input [lindex $args 0];set context [dict create power_unit [dict get $input unit]]
        set unit [dict get $context power_unit];if {$unit eq {}} {dict set context power_unit unspecified}
        set shape {1 1}
        if {[dict get $input kind] eq "vector"} {set shape [list [llength [dict get $input value]] 1]}
        if {[dict get $input kind] eq "matrix"} {set shape [dict get $input shape]}
        lassign $shape rows cols
        if {$rows*$cols>1} {
            set columns {};set common $raw;set ids {}
            foreach field {power root_power level_db} {
                set values [dict get $raw $field]
                if {$cols>1&&$rows>1} {set values [concat {*}$values]}
                dict set columns $field $values;dict unset common $field
            }
            for {set row 1} {$row<=$rows} {incr row} {for {set col 1} {$col<=$cols} {incr col} {lappend ids power_r${row}_c${col}}}
            dict set provenance worksheet_shape $shape
            return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $columns $common $context $provenance]
        }
    }
    if {[dict get $model profile] eq "pca"} {
        set columns {};set common $raw;set ids {}
        foreach field {singular_value component_variance explained_ratio cumulative_ratio component_index} {
            dict set columns $field [dict get $raw $field];dict unset common $field
        }
        foreach index [dict get $raw component_index] {lappend ids [format component_%03d $index]}
        return [::GX::StatisticsV1::fromNumericColumns [dict get $model id] $id $ids $columns $common $context $provenance]
    }
    if {[dict get $model profile] eq "propagation"} {
        set count [dict get $raw output_count]
        if {![string is integer -strict $count]||$count<1||$count>256} {error {Propagation interpretation requires one to 256 identified outputs}}
        set ids {};for {set i 1} {$i<=$count} {incr i} {lappend ids output_$i}
        dict set context output_ids $ids
        # A heterogeneous Jacobian does not declare the output measurement units.
        # Preserve explicit unknown units instead of copying its input unit.
        dict set context output_units [lrepeat $count unspecified]
    }
    return [::GX::StatisticsV1::fromNumeric [dict get $model id] $id $raw $context {} $provenance]
}
proc ::GX::ScientificWorksheet::_numericTypedArguments {meta operands} {
    if {[dict get $meta id] eq "prediction_uncertainty"} {_predictionSource $operands}
    set args $operands
    if {[dict get $meta id] in {statistics.logistic_regression statistics.glm}&&[dict exists $meta parent_operation]&&[llength $args]>=2} {
        set response [lindex $args 1]
        if {[dict get $response unit] ni {{} 1}||[dict exists $response mixed_units]&&[dict get $response mixed_units]} {error {Binary and count responses must be dimensionless}}
    }
    if {[dict get $meta id] eq "statistics.survival_kaplan_meier"&&[dict exists $meta parent_operation]&&[llength $args]>=2} {
        set indicators [lindex $args 1]
        if {[dict get $indicators unit] ni {{} 1}||[dict exists $indicators mixed_units]&&[dict get $indicators mixed_units]} {error {Survival event indicators must be dimensionless zero/one values}}
    }
    if {[dict get $meta id] eq "statistics.multiple_testing"&&[dict exists $meta parent_operation]&&[llength $args]} {
        set sample [lindex $args 0]
        if {[dict get $sample unit] ni {{} 1}||[dict exists $sample mixed_units]&&[dict get $sample mixed_units]} {error {Multiple testing requires dimensionless p-values}}
    }
    if {[dict get $meta id] eq "statistics.permutation_test"&&[dict exists $meta parent_operation]&&[llength $args]>=2} {
        lassign $args first second
        if {[dict get $first unit] ne [dict get $second unit]} {error {Permutation samples must have matching physical units; convert explicitly first}}
    }
    if {[dict get $meta id] ne "reduce_accumulate"||[llength $args]!=2} {return [lmap arg $args {_typed $arg}]}
    lassign $args state values
    if {[dict exists $values mixed_units]&&[dict get $values mixed_units]} {error {Accumulated values must have one physical unit}}
    set unit [dict get $values unit]
    if {[dict get $state kind] eq "struct"} {
        if {![dict exists $state captured_statistics]} {error {Accumulation requires a captured scalar reduce_summary or reduce_accumulate result}}
        set statistics [dict get $state captured_statistics]
        set fields [::GX::StatisticsV1::numericFields $statistics]
        if {[dict get $statistics provenance operation] ni {reduce_summary reduce_accumulate}} {error {Accumulation state must retain its public reduction identity}}
        if {[dict get $statistics context y_unit] ne $unit} {error {Accumulation state and new values must have matching physical units; convert the observations before summarizing}}
        set stateFields {}
        foreach key {count sum mean min max} {
            set field [dict get $fields $key]
            if {[dict get $field status] ne "value"||[dict get $field kind] ne "scalar"} {error {Accumulation requires finite scalar summary facts}}
            set value [dict get $field value]
            if {![dict exists $state value $key]||[dict get $state value $key] ne $value} {error {Accumulation state differs from its captured CORE facts}}
            dict set stateFields $key [::GX::ScientificTransportv1::array {1 1} [list $value]]
        }
        set typedState [::GX::ScientificTransportv1::struct $stateFields]
    } else {
        if {[dict get $state kind] eq "record"} {
            foreach key {count sum min max} {
                if {![dict exists $state value $key]} {error {Explicit accumulation state needs count, sum, min and max}}
                set field [dict get $state value $key];set fieldUnit [dict get $field unit]
                if {[dict get $field kind] ne "scalar"||([dict exists $field mixed_units]&&[dict get $field mixed_units])} {error {Explicit accumulation state fields must be scalar}}
                if {($key eq "count"&&$fieldUnit ni {{} 1})||($key ne "count"&&$fieldUnit ne $unit)} {error {Explicit accumulation state fields must retain the units of their observations and a dimensionless count}}
            }
        }
        set typedState [_typed $state]
    }
    return [list $typedState [_typed $values]]
}
proc ::GX::ScientificWorksheet::_signalCaptureSpec {meta args options} {
    set operation [dict get $meta id]
    if {[catch {set contract [::GX::SignalAPIv1::statisticalContract $operation]} reason detail]} {
        if {[dict get $detail -errorcode] eq {GXTXT SCIENTIFIC UnknownOperation}} {return {}}
        return -options $detail $reason
    }
    set lineage {};set units {}
    foreach item $args {
        if {[dict exists $item mixed_units]&&[dict get $item mixed_units]} {error {Signal statistical inputs contain mixed units; convert explicitly first}}
        set unit [dict get $item unit];if {$unit eq {}} {set unit unspecified};lappend units $unit
        foreach source [_sourceLineage $item] {dict set lineage $source 1}
    }
    dict for {key item} $options {
        if {[dict exists $item mixed_units]&&[dict get $item mixed_units]} {error {Signal statistical options contain mixed units; convert explicitly first}}
        foreach source [_sourceLineage $item] {dict set lineage $source 1}
    }
    set first [lindex $units 0];set second [lindex $units 1]
    if {![llength $args]} {error {Signal statistics require their numerical operands}}
    set context [dict create y_unit $first]
    switch -- [dict get $contract profile] {
        signal_spectral {
            if {[llength $args]>=3&&[lindex $units 2] ni {unspecified Hz}} {error {Signal sample rate must be in Hz; convert explicitly first}}
            set context [dict create x_unit $first y_unit $second]
        }
        signal_summary {}
        signal_snr {
            if {$first ne $second} {error {Signal and supplied noise must have matching physical units; convert explicitly first}}
        }
        signal_spectrum_quality {
            if {[llength $args]>=3&&[lindex $units 2] ni {unspecified Hz}} {error {Signal sample rate must be in Hz; convert explicitly first}}
            if {[dict exists $options fundamental_hz]&&[dict get $options fundamental_hz unit] ni {{} Hz}} {error {Fundamental frequency must be in Hz; convert explicitly first}}
        }
        event_timing {
            if {$first ne "s"} {error {Event/pulse time coordinates must declare seconds (s); convert explicitly first}}
            foreach key {threshold hysteresis} {
                if {[dict exists $options $key]&&[dict get $options $key unit] ne {}&&[dict get $options $key unit] ne $second} {error {Event thresholds must use the signal's actual physical unit; convert explicitly first}}
            }
            set context [dict create x_unit s y_unit $second]
        }
        signal_correlation {
            if {[llength $args]<2||[dict get [lindex $args 1] kind] eq "empty"} {set second $first}
            set context [dict create x_unit $first y_unit $second]
            if {[dict exists $options sample_rate]&&[dict get $options sample_rate unit] ni {{} Hz}} {error {Correlation sample rate must be in Hz; convert explicitly first}}
        }
        window_metrics {
            if {$first ni {unspecified 1}} {error {Window coefficients must be dimensionless}}
            if {[llength $args]>=3&&[lindex $units 2] ni {unspecified Hz}} {error {Window sample rate must be in Hz; convert explicitly first}}
            set context [dict create x_unit 1]
        }
        default {error {Unsupported Worksheet statistical contract profile}}
    }
    set provenance [dict create producer viewer.scientific_worksheet signal_operation $operation]
    if {[dict size $lineage]} {dict set provenance source_variables [dict keys $lineage]}
    return [dict create operation $operation context $context provenance $provenance profile [dict get $contract profile]]
}
proc ::GX::ScientificWorksheet::_signalStatistics {spec raw} {
    if {[dict get $spec profile] eq "signal_spectral"} {
        set contract [::GX::SignalAPIv1::statisticalContract [dict get $spec operation]]
        set columns {};set common $raw;set count 0
        foreach field {frequency_hz psd_real psd_imaginary asd value_real value_imaginary} {
            if {[dict exists $raw $field]&&[llength [dict get $raw $field]]>1} {
                dict set columns $field [dict get $raw $field];set count [llength [dict get $raw $field]];dict unset common $field
            }
        }
        if {$count>8192} {error {Save the Worksheet before calculating a large spectral result}}
        if {$count} {
            set rows {};for {set i 0} {$i<$count} {incr i} {lappend rows row_$i}
            set provenance [dict get $spec provenance]
            dict for {field quantity} [::GX::StatisticsV1::numericFieldMap [dict get $contract numerical_operation]] {
                if {[dict exists $common $field]} {dict set provenance worksheet_field_shapes $field {1 1}}
            }
            return [::GX::StatisticsV1::fromNumericColumns [dict get $contract model_id] [dict get $contract numerical_operation] $rows $columns $common [dict get $spec context] $provenance]
        }
    }
    return [::GX::SignalAPIv1::interpretResult [dict get $spec operation] $raw [dict get $spec context] [dict get $spec provenance]]
}
proc ::GX::ScientificWorksheet::_capturedStatisticalFieldMap {statistics} {
    if {[dict get $statistics schema] eq "gxtxt.statistical_result.resource_binding.v1"} {return [::GX::StatisticsV1::numericFields [dict get $statistics prototype]]}
    if {[dict get $statistics schema] eq "gxtxt.statistical_result.table.v1"} {return [::GX::StatisticsV1::numericFieldMap [dict get $statistics provenance operation]]}
    return [::GX::StatisticsV1::numericFields $statistics]
}
proc ::GX::ScientificWorksheet::_statisticalFieldItem {statistics field {window {}}} {
    set itemKey {}
    if {[dict get $statistics schema] eq "gxtxt.statistical_result.resource_binding.v1"} {
        variable statisticalItemCache
        set itemKey [list [::GX::interactiveDocumentSessionToken] $statistics $field $window]
        if {[dict exists $statisticalItemCache $itemKey]} {return [dict get $statisticalItemCache $itemKey]}
    }
    set projection [_statisticalProjection $statistics $field $window]
    set values {};set units {}
    foreach cell [dict get $projection cells] {
        if {[dict exists $cell value]} {lappend values [dict get $cell value]} else {lappend values NaN}
        lappend units [dict get $cell unit_text]
    }
    if {$window eq {}&&([dict exists $statistics provenance worksheet_shape]||[dict exists $statistics provenance worksheet_field_shapes $field])} {
        if {[dict exists $statistics provenance worksheet_field_shapes $field]} {set shape [dict get $statistics provenance worksheet_field_shapes $field]} else {set shape [dict get $statistics provenance worksheet_shape]}
        if {[llength $shape]!=2} {error {Captured Worksheet statistical shape must have two dimensions}}
        foreach size $shape {if {![string is integer -strict $size]||$size<1} {error {Invalid captured Worksheet statistical shape}}}
        lassign $shape rows columns
        if {$rows*$columns==1&&[llength $values]>1} {
            # An explicitly shared captured fact remains one original scalar.
            # Verify the broadcast before projecting it.
            if {[llength [lsort -unique $values]]!=1||[llength [lsort -unique $units]]!=1} {error {A shared reduction count cannot collapse unequal group facts}}
            set values [lrange $values 0 0];set units [lrange $units 0 0]
        }
        if {$rows*$columns!=[llength $values]} {error {Captured Worksheet statistical shape differs from its element identities}}
        dict set projection shape $shape
    }
    lassign [dict get $projection shape] rows columns
    set kind [expr {$rows*$columns==1?"scalar":($columns>1?"matrix":"vector")}]
    if {$kind eq "scalar"} {set values [lindex $values 0]}
    set item [_value $values [lindex $units 0] $kind]
    if {[dict exists $statistics provenance source_variables]} {dict set item source_lineage [dict get $statistics provenance source_variables]}
    if {[dict exists $statistics prototype provenance source_variables]} {dict set item source_lineage [dict get $statistics prototype provenance source_variables]}
    dict set item shape [dict get $projection shape];dict set item element_units $units
    if {[llength [lsort -unique $units]]>1} {dict set item mixed_units 1;dict set item unit {}}
    dict set item statistical_result $statistics;dict set item statistical_field $field
    if {$window ne {}} {dict set item statistical_window $window}
    if {$itemKey ne {}} {
        dict set statisticalItemCache $itemKey $item
        if {[dict size $statisticalItemCache]>8} {dict unset statisticalItemCache [lindex [dict keys $statisticalItemCache] 0]}
    }
    return $item
}
proc ::GX::ScientificWorksheet::_operationRaw {book name inputs options {model {}}} {
    set catalog [functionCatalog $name]
    if {![dict exists $catalog $name]} {error "Unknown operation '$name'."}
    set meta [dict get $catalog $name]
    if {[dict exists $meta worksheet_category] && [dict get $meta worksheet_category] eq "unavailable"} {error [dict get $meta worksheet_reason]}
    set args {}
    foreach input $inputs {
        if {$input eq "@session"} {lappend args [_value [_requireSession] "" text]; continue}
        if {[string match "@text:*" $input]} {lappend args [_value [string range $input 6 end] "" text]; continue}
        lappend args [_expressionValue $book $input]
    }
    set typedOptions [dict create];set optionItems {}
    dict for {key val} $options {set item [_expressionValue $book $val];dict set optionItems $key $item;dict set typedOptions $key [_typed $item]}
    set provider [dict get $meta provider_id]
    set signalSpec {};if {$provider eq "math.signal"} {set signalSpec [_signalCaptureSpec $meta $args $optionItems]}
    if {$provider eq "math.numeric"} {
        if {[dict exists $meta model_kinds]} {
            if {![dict exists $model kind] || [dict get $model kind] ni [dict get $meta model_kinds]} {error "Choose a model kind: [join [dict get $meta model_kinds] {, }]."}
            set fields [dict create kind [::GX::ScientificTransportv1::text [dict get $model kind]]]
            dict for {key expression} $model {
                if {$key eq "kind"} continue
                dict set fields $key [_typed [_expressionValue $book $expression]]
            }
            set modelId [expr {[dict exists $meta parent_operation] ? "foundation.[dict get $meta id]" : [dict get $meta id]}]
            set result [::GX::NumericAPIv1::callModelOperation $modelId [::GX::ScientificTransportv1::struct $fields] [lmap arg $args {_typed $arg}] [::GX::ScientificTransportv1::struct $typedOptions]]
        } elseif {[dict exists $meta parent_operation] && [dict get $meta parent_operation] eq "foundation"} {
            set typed [_numericTypedArguments $meta $args]
            while {[llength $typed] < 3} {lappend typed [::GX::ScientificTransportv1::empty]}
            if {[dict get $book document_id] ne {}&&[_foundationCaptureApplies $meta]} {
                set captured [_capturedFoundationCall [dict get $book document_id] $meta $args [::GX::ScientificTransportv1::struct $typedOptions]]
                dict set captured inputs $args
                return $captured
            }
            set result [::GX::NumericAPIv1::foundation [dict get $meta family] [dict get $meta action] {*}[lrange $typed 0 2] [::GX::ScientificTransportv1::struct $typedOptions]]
        } else {
            set result [::GX::NumericAPIv1::callOperation [dict get $meta id] [_numericTypedArguments $meta $args] [::GX::ScientificTransportv1::struct $typedOptions]]
        }
        set types [::GX::NumericAPIv1::resultTypes]
    } else {
        switch -- $provider {math.signal {set namespace SignalAPIv1} math.rf_network {set namespace RFNetworkAPIv1} math.magnetics {set namespace MagneticsAPIv1} default {error "Unsupported provider."}}
        set typed [lmap arg $args {_typed $arg}]
        while {[llength $typed] < 3} {lappend typed [::GX::ScientificTransportv1::empty]}
        lassign [split [dict get $meta id] .] family action
        if {$signalSpec ne {}&&[dict get $signalSpec profile] eq "signal_spectral"&&[dict get $book document_id] ne {}} {
            set captured [_capturedSignalCall [dict get $book document_id] $signalSpec $args [::GX::ScientificTransportv1::struct $typedOptions]]
            dict set captured inputs $args
            return $captured
        }
        set result [::GX::${namespace}::call $family $action {*}[lrange $typed 0 2] [::GX::ScientificTransportv1::struct $typedOptions]]
        set types [::GX::${namespace}::resultTypes]
    }
    set out [dict create values $result types $types inputs $args]
    if {$provider eq "math.numeric"} {
        set statistics [_numericStatistics $meta $args $result]
        if {$statistics ne {}} {dict set out captured_statistics $statistics}
    }
    if {$signalSpec ne {}} {dict set out captured_statistics [_signalStatistics $signalSpec $result]}
    return $out
}
proc ::GX::ScientificWorksheet::_resultFieldPaths {raw} {
    set out {}
    dict for {key value} [dict get $raw values] {
        set kind [expr {[dict exists [dict get $raw types] $key] ? [dict get [dict get $raw types] $key] : "number"}]
        if {$kind eq "struct" && ![catch {dict size $value}]} {
            dict for {nested unused} $value {lappend out "$key.$nested"}
        } else {lappend out $key}
    }
    if {[dict exists $raw captured_statistics]} {
        foreach field [dict keys [_capturedStatisticalFieldMap [dict get $raw captured_statistics]]] {if {$field ni $out} {lappend out $field}}
    }
    return $out
}
proc ::GX::ScientificWorksheet::_resultFieldValue {raw path} {
    set parts [split $path .]; set head [lindex $parts 0]
    if {![dict exists [dict get $raw values] $head]} {error "Unknown result field '$head'."}
    set chosen [dict get [dict get $raw values] $head]
    set kind [expr {[dict exists [dict get $raw types] $head] ? [dict get [dict get $raw types] $head] : "number"}]
    foreach nested [lrange $parts 1 end] {
        if {![dict exists $chosen $nested]} {error "Nested result field '$path' is unavailable."}
        set chosen [dict get $chosen $nested]
        set kind [expr {[llength $chosen] > 1 ? "vector" : "number"}]
    }
    if {$kind eq "struct"} {error "Choose a nested field under '$path'."}
    if {$kind eq "cell"} {
        if {[llength $chosen] > 1} {set kind vector} else {set kind text}
    }
    return [list $chosen $kind]
}
proc ::GX::ScientificWorksheet::applyOperation {book name inputs options destination field {model {}} {outputWindow {}}} {
    set book [_upgrade $book]; set destination [_cell $destination]
    set raw [_operationRaw $book $name $inputs $options $model]
    return [_applyCapturedOperation $book $name $inputs $options $destination $field $model $raw $outputWindow]
}
proc ::GX::ScientificWorksheet::_applyCapturedOperation {book name inputs options destination field model raw {outputWindow {}}} {
    set book [_upgrade $book];set destination [_cell $destination]
    set values [dict get $raw values]
    set availableFields [_resultFieldPaths $raw]
    if {$field eq ""} {
        if {[llength $availableFields] != 1} {error "Choose a result field: [join $availableFields {, }]."}
        set field [lindex $availableFields 0]
    }
    if {$field ni $availableFields} {error "Result field '$field' is unavailable. Choose: [join $availableFields {, }]."}
    set statisticalItem {}
    if {[dict exists $raw captured_statistics]&&[dict exists [_capturedStatisticalFieldMap [dict get $raw captured_statistics]] $field]} {
        set statisticalItem [_statisticalFieldItem [dict get $raw captured_statistics] $field $outputWindow]
    } elseif {[dict exists $raw captured_statistics]&&[dict exists [::GX::StatisticsV1::numericDataFields [dict get $raw captured_statistics]] fields $field]} {
        set statisticalItem [_statisticalDataFieldItem [dict get $raw captured_statistics] $field [dict get $values $field] $outputWindow 0 $values]
    }
    if {$statisticalItem ne {}} {
        set chosen [dict get $statisticalItem value];set kind [dict get $statisticalItem kind]
        if {$kind eq "matrix"} {
            set flat $chosen;set chosen {};set n [lindex [dict get $statisticalItem shape] 1]
            for {set i 0} {$i<[llength $flat]} {incr i $n} {lappend chosen [lrange $flat $i [expr {$i+$n-1}]]}
        }
    } else {
        if {$outputWindow ne {}} {error {Result row selection requires a captured statistical field}}
        lassign [_resultFieldValue $raw $field] chosen kind
    }
    set meta [dict get [functionCatalog $name] $name]
    set resultUnit ""
    if {[llength $inputs] && [dict exists $meta unit_behavior]} {
        set behavior [dict get $meta unit_behavior]
        if {$behavior in {preserve preserve_y field_specific}} {
            set sourceIndex [expr {$behavior eq "preserve_y" && [llength $inputs] > 1 ? 1 : 0}]
            if {![catch {set sourceItem [_expressionValue $book [lindex $inputs $sourceIndex]]}]} {
                if {$behavior ne "field_specific" || $field in {min max range sum mean median q25 q75 iqr std_population std_sample rms mad}} {set resultUnit [dict get $sourceItem unit]}
            }
        }
    }
    if {$kind in {vector matrix}} {
        set rows [llength $chosen]; set cols 1
        if {$kind eq "matrix" && $rows > 0} {set cols [llength [lindex $chosen 0]]; set chosen [concat {*}$chosen]}
    } else {set rows 1; set cols 1; set chosen [list $chosen]}
    lassign [_parts $destination] c0 r0
    set i 0; set pending [dict create]
    for {set r 0} {$r < $rows} {incr r} {
        for {set c 0} {$c < $cols} {incr c} {
            set address "[_columnName [expr {$c0+$c}]][expr {$r0+$r}]"
            if {[dict exists $book cells $address]} {error "#SPILL! Output cell $address is occupied. Clear or choose another destination."}
            set scalar [lindex $chosen $i]
            if {$statisticalItem ne {}} {set resultUnit [lindex [dict get $statisticalItem element_units] $i]}
            set cellKind [expr {[string is double -strict $scalar] ? "derived" : "text"}]
            dict set pending $address [dict create source $scalar kind $cellKind unit $resultUnit lineage [dict create operation $name field $field output_index $i operation_destination $destination]]
            incr i
        }
    }
    dict for {address cell} $pending {dict set book cells $address $cell}
    set definition [dict create operation $name inputs $inputs options $options model $model destination $destination field $field rows $rows columns $cols]
    if {$outputWindow ne {}} {dict set definition field_window $outputWindow}
    set contributors [_carryStatistics [_value {}] [dict get $raw inputs]]
    if {[dict exists $raw captured_statistics]} {
        set captured [dict get $raw captured_statistics];dict lappend contributors statistical_sources $captured
        if {[dict exists $captured provenance source_variables]} {
            set references [_sourceLineage $contributors]
            foreach reference [dict get $captured provenance source_variables] {if {$reference ni $references} {lappend references $reference}}
            dict set contributors source_lineage $references
        }
    }
    foreach key {statistical_sources source_lineage} {if {[dict exists $contributors $key]} {dict set definition $key [dict get $contributors $key]}}
    if {$statisticalItem ne {}} {dict set definition captured_statistics [dict get $raw captured_statistics]}
    if {[dict exists $statisticalItem statistical_data_field]} {dict set definition captured_data_values [dict get $statisticalItem value]}
    if {[dict exists $statisticalItem statistical_data_companions]} {dict set definition captured_data_companions [dict get $statisticalItem statistical_data_companions]}
    dict set book operations $destination $definition
    dict incr book revision
    variable cache; set cache [dict create]
    return [list $book $raw]
}
proc ::GX::ScientificWorksheet::_uiApplyFunctionDialog {w browser} {
    variable ui
    set name [lindex [$browser.tree selection] 0]
    if {$name eq "" || [string match "category:*" $name]} return
    set meta [dict get [functionCatalog $name] $name]
    if {[dict exists $meta worksheet_category] && [dict get $meta worksheet_category] eq "unavailable"} {_uiError $w [dict get $meta worksheet_reason]; return}
    set d $w.applyfunction; catch {destroy $d}; toplevel $d; wm title $d "Apply $name"
    set ui($w,apply_token) [::GX::interactiveDocumentSessionToken]
    catch {unset ui($w,apply_preview)}
    bind $d <Destroy> [list ::GX::ScientificWorksheet::_uiOperationClosed $w $d %W]
    ttk::label $d.help -text [dict get $meta summary] -wraplength 600
    pack $d.help -fill x -padx 8 -pady 5
    set ui($w,apply_name) $name; set ui($w,apply_count) 0
    set names [expr {[dict exists $meta arguments] ? [dict get $meta arguments] : [split [dict get $meta operands] ,]}]
    if {[dict exists $meta model_kinds]} {
        if {[dict exists $meta parent_operation]} {set names [lrange $names 1 end]} else {
            set filtered {}; foreach arg $names {if {$arg ni {model callback}} {lappend filtered $arg}}; set names $filtered
        }
    }
    foreach arg $names {
        if {$arg eq "" || $arg eq "options"} continue
        set n $ui($w,apply_count); incr ui($w,apply_count)
        ttk::label $d.l$n -text "$arg  ·  cell, range, formula, or quoted text"
        ttk::entry $d.e$n -textvariable ::GX::ScientificWorksheet::ui($w,apply_$n) -width 54
        set ui($w,apply_$n) [expr {$arg eq "session" ? "@session" : ""}]
        pack $d.l$n $d.e$n -fill x -padx 8
    }
    set ui($w,apply_options) ""; set ui($w,apply_field) ""; set ui($w,apply_destination) $ui($w,active)
    set ui($w,apply_model_kind) ""; set ui($w,apply_model_fields) ""
    if {[dict exists $meta model_kinds]} {
        set ui($w,apply_model_kind) [lindex [dict get $meta model_kinds] 0]
        set ui($w,apply_model_fields) ""
        ttk::label $d.modellabel -text "Declarative model; parameters use Worksheet cells/ranges (e.g. coefficients=A1:A3, center=B1:B3)" -wraplength 600
        ttk::combobox $d.modelkind -values [dict get $meta model_kinds] -textvariable ::GX::ScientificWorksheet::ui($w,apply_model_kind) -state readonly
        ttk::entry $d.modelfields -textvariable ::GX::ScientificWorksheet::ui($w,apply_model_fields)
        pack $d.modellabel $d.modelkind $d.modelfields -fill x -padx 8 -pady 2
    }
    ttk::label $d.optionslabel -text "Options: key=value pairs separated by spaces (values may reference cells)"
    ttk::entry $d.options -textvariable ::GX::ScientificWorksheet::ui($w,apply_options)
    ttk::label $d.fieldlabel -text "Result field (Preview lists available fields)"
    ttk::combobox $d.field -textvariable ::GX::ScientificWorksheet::ui($w,apply_field)
    set ui($w,apply_first_row) 1;set ui($w,apply_row_count) {}
    ttk::label $d.firstrowlabel -text "First result row (1-based)"
    ttk::entry $d.firstrow -textvariable ::GX::ScientificWorksheet::ui($w,apply_first_row)
    ttk::label $d.rowcountlabel -text "Number of result rows (blank = all; statistical vector fields)"
    ttk::entry $d.rowcount -textvariable ::GX::ScientificWorksheet::ui($w,apply_row_count)
    ttk::label $d.destlabel -text "Output starts at cell"
    ttk::entry $d.dest -textvariable ::GX::ScientificWorksheet::ui($w,apply_destination)
    ttk::button $d.preview -text "Preview fields" -command [list ::GX::ScientificWorksheet::_uiPreviewFunction $w]
    ttk::button $d.apply -text "Apply to cells" -command [list ::GX::ScientificWorksheet::_uiApplyFunction $w]
    foreach widget {optionslabel options fieldlabel field firstrowlabel firstrow rowcountlabel rowcount destlabel dest preview apply} {pack $d.$widget -fill x -padx 8 -pady 2}
}
proc ::GX::ScientificWorksheet::_uiOperationInputs {w} {
    variable ui
    set inputs {}; for {set i 0} {$i < $ui($w,apply_count)} {incr i} {lappend inputs $ui($w,apply_$i)}
    while {[llength $inputs] && [lindex $inputs end] eq ""} {set inputs [lrange $inputs 0 end-1]}
    set options [dict create]
    foreach item [split $ui($w,apply_options)] {
        if {$item eq ""} continue
        if {![regexp {^([A-Za-z][A-Za-z0-9_]*)=(.+)$} $item unused key val]} {error "Options must be key=value pairs."}
        dict set options $key $val
    }
    set model [dict create]
    if {[info exists ui($w,apply_model_kind)] && $ui($w,apply_model_kind) ne ""} {
        dict set model kind $ui($w,apply_model_kind)
        foreach item [split $ui($w,apply_model_fields)] {
            if {$item eq ""} continue
            if {![regexp {^([A-Za-z][A-Za-z0-9_]*)=(.+)$} $item unused key val]} {error "Model fields must be key=value pairs."}
            dict set model $key $val
        }
    }
    return [list $inputs $options $model]
}
proc ::GX::ScientificWorksheet::_uiOperationClosed {w dialog destroyed} {
    variable ui
    if {$destroyed eq $dialog} {catch {unset ui($w,apply_preview)};catch {unset ui($w,apply_token)}}
}
proc ::GX::ScientificWorksheet::_uiOperationKey {w inputs options model} {
    variable ui
    if {![info exists ui($w,apply_token)]||$ui($w,apply_token) ne [::GX::interactiveDocumentSessionToken]} {error {The Session changed; close this dialog and reopen the operation in the current Session.}}
    return [list $ui($w,apply_token) $ui($w,book) $ui($w,apply_name) $inputs $options $model]
}
proc ::GX::ScientificWorksheet::_uiOperationCurrent {w key windowId} {
    if {![winfo exists $w.applyfunction]||[winfo id $w.applyfunction] ne $windowId} {error {The operation dialog changed while calculating; reopen it before applying a result.}}
    lassign [_uiOperationInputs $w] inputs options model
    if {[_uiOperationKey $w $inputs $options $model] ne $key} {error {The Worksheet or operation inputs changed; preview or apply the current inputs again.}}
}
proc ::GX::ScientificWorksheet::_uiPreviewFunction {w} {
    variable ui
    if {[catch {
        lassign [_uiOperationInputs $w] inputs options model
        set key [_uiOperationKey $w $inputs $options $model];set windowId [winfo id $w.applyfunction]
        if {[info exists ui($w,apply_preview)]&&[dict get $ui($w,apply_preview) key] eq $key} {
            set raw [dict get $ui($w,apply_preview) raw]
        } else {
            catch {unset ui($w,apply_preview)}
            set raw [_operationRaw $ui($w,book) $ui($w,apply_name) $inputs $options $model]
            _uiOperationCurrent $w $key $windowId
            if {[dict exists $raw captured_statistics]} {set ui($w,apply_preview) [dict create key $key raw $raw]}
        }
        set fields [_resultFieldPaths $raw]
        $w.applyfunction.field configure -values $fields
        if {[llength $fields] == 1} {set ui($w,apply_field) [lindex $fields 0]}
        set ui($w,status) "Result fields: [join $fields {, }]. Choose one and Apply."
    } message]} {
        if {[info exists windowId]&&(![winfo exists $w.applyfunction]||[winfo id $w.applyfunction] ne $windowId)} return
        catch {unset ui($w,apply_preview)};if {[winfo exists $w]} {_uiError $w $message}
    }
}
proc ::GX::ScientificWorksheet::_uiApplyFunction {w} {
    variable ui
    if {[catch {
        lassign [_uiOperationInputs $w] inputs options model
        set key [_uiOperationKey $w $inputs $options $model];set windowId [winfo id $w.applyfunction]
        set snapshot $ui($w,book)
        set outputWindow [_uiResultWindow $w]
        set outputIdentity [list $ui($w,apply_destination) $ui($w,apply_field) $outputWindow]
        if {[info exists ui($w,apply_preview)]&&[dict get $ui($w,apply_preview) key] eq $key} {
            set raw [dict get $ui($w,apply_preview) raw]
            lassign [_applyCapturedOperation $snapshot $ui($w,apply_name) $inputs $options $ui($w,apply_destination) $ui($w,apply_field) $model $raw $outputWindow] book raw
        } else {
            lassign [applyOperation $snapshot $ui($w,apply_name) $inputs $options $ui($w,apply_destination) $ui($w,apply_field) $model $outputWindow] book raw
        }
        _uiOperationCurrent $w $key $windowId
        if {[list $ui($w,apply_destination) $ui($w,apply_field) [_uiResultWindow $w]] ne $outputIdentity} {error {Output destination or result row selection changed during calculation; apply the current selection again}}
        _uiRemember $w
        set ui($w,book) $book; _uiRefresh $w; destroy $w.applyfunction
        set ui($w,status) "Applied $ui($w,apply_name) at $ui($w,apply_destination)."
    } message]} {
        if {[info exists windowId]&&(![winfo exists $w.applyfunction]||[winfo id $w.applyfunction] ne $windowId)} return
        if {[winfo exists $w]} {_uiError $w $message}
    }
}

source [file join [file dirname [info script]] worksheet_statistical_resources_v1.tcl]
