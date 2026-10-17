# Scientific Worksheet model v2. Stable facades; CORE owns science and persistence.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificWorksheet {variable nextBook 0}
proc ::GX::ScientificWorksheet::_upgrade {book} {
    if {![dict exists $book sheets]} {
        dict set book sheets [dict create Sheet1 [_sheetData $book]]
        dict set book sheet_order Sheet1;dict set book active_sheet Sheet1
    }
    if {![dict exists $book options calculation_mode]} {dict set book options calculation_mode automatic}
    if {![dict exists $book presentation display_columns]} {dict set book presentation display_columns {A B C D E F G H I J K L}}
    foreach key {bindings column_metadata row_identity hidden_rows operations styles range_styles merges row_heights column_widths filter_views active_filter filter_hidden_rows scripts} {if {![dict exists $book $key]} {dict set book $key {}}}
    dict for {sheet body} [dict get $book sheets] {
        foreach key {bindings column_metadata row_identity hidden_rows operations styles range_styles merges row_heights column_widths filter_views active_filter filter_hidden_rows scripts} {if {![dict exists $body $key]} {dict set book sheets $sheet $key {}}}
    }
    if {[dict exists $book active_sheet_cache_omitted]} {
        dict for {key value} [dict get $book sheets [dict get $book active_sheet]] {dict set book $key $value}
        dict unset book active_sheet_cache_omitted
    }
    dict set book format scientific_worksheet.v2
    if {![dict exists $book workbook_uuid]} {dict set book workbook_uuid "worksheet-uuid#[pid]-[clock clicks]"}
    if {![dict exists $book _runtime]} {
        variable nextBook
        dict set book _runtime [dict create workbook_id "worksheet#[pid]-[clock clicks]-[incr nextBook]" session_token [::GX::interactiveDocumentSessionToken] owner_generation {} document_revision 0]
    }
    return $book
}
proc ::GX::ScientificWorksheet::new {{name "Untitled Worksheet"}} {return [_upgrade [_v1_new $name]]}
proc ::GX::ScientificWorksheet::bookIdentity {book} {
    set book [_upgrade $book]
    set identity {};foreach field {workbook_id session_token owner_generation document_revision} {dict set identity $field [dict get $book _runtime $field]}
    return [dict merge $identity [dict create document_id [dict get $book document_id] revision [dict get $book revision] active_sheet [dict get $book active_sheet]]]
}
proc ::GX::ScientificWorksheet::validateBook {book {documentCheck 1}} {
    if {![dict exists $book _runtime]} {error {Workbook has no live authority; load it through the public Worksheet API}}
    if {[dict get $book _runtime session_token] ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen this Worksheet before using it}}
    set id [dict get $book document_id]
    if {$documentCheck && $id ne ""} {
        set found {};foreach item [::GX::interactiveDocumentList viewer.scientific_worksheet scientific_worksheet] {if {[dict get $item id] eq $id} {set found $item;break}}
        if {$found eq {} || [dict get $found generation] ne [dict get $book _runtime owner_generation]} {error {Worksheet was deleted or replaced; reopen the document}}
        if {[dict get $found revision] != [dict get $book _runtime document_revision]} {error {Worksheet changed in another editor; reload before saving or editing}}
    }
    return [bookIdentity $book]
}
proc ::GX::ScientificWorksheet::snapshot {book} {
    set book [_flush $book];dict unset book _runtime
    # The sheets dictionary is canonical. Do not persist a second active copy.
    foreach field {cells columns ranges bindings column_metadata row_identity hidden_rows operations styles range_styles merges row_heights column_widths filter_views active_filter filter_hidden_rows scripts} {dict set book $field {}}
    dict set book active_sheet_cache_omitted 1
    return $book
}
proc ::GX::ScientificWorksheet::restoreBookIdentity {snapshot currentBook} {
    validateBook $currentBook
    if {[dict exists $snapshot history_resource]} {set snapshot [_historyExpand $snapshot]}
    if {![dict exists $snapshot workbook_uuid] || [dict get $snapshot workbook_uuid] ne [dict get $currentBook workbook_uuid]} {error {History snapshot belongs to another Worksheet}}
    dict set snapshot document_id [dict get $currentBook document_id]
    dict set snapshot _runtime [dict get $currentBook _runtime]
    _dropBookCache $currentBook
    return [_upgrade $snapshot]
}
proc ::GX::ScientificWorksheet::save {book} {
    set book [_upgrade $book];set book [refreshBookAuthority $book];validateBook $book
    set book [_flush [_formulaResourceReferences $book]]
    set id [dict get $book document_id]
    if {$id eq ""} {
        set item [::GX::interactiveDocumentCreate viewer.scientific_worksheet scientific_worksheet scientific_worksheet.v2 2 [snapshot $book]]
        dict set book document_id [dict get $item id]
    }
    set prior [dict get [::GX::interactiveDocumentRead [dict get $book document_id]] payload]
    if {[dict exists $prior workspace_metadata]} {dict set book workspace_metadata [dict get $prior workspace_metadata]}
    set item [::GX::interactiveDocumentUpdate [dict get $book document_id] [snapshot $book] scientific_worksheet.v2 2]
    # Existing public promotion adopts legacy documents without changing identity.
    ::GX::sessionWorkspacePromote [dict get $book document_id]
    set item [::GX::interactiveDocumentRead [dict get $book document_id]]
    dict set book workspace_metadata [dict get $item payload workspace_metadata]
    dict set book _runtime owner_generation [dict get $item generation]
    dict set book _runtime document_revision [dict get $item revision]
    dict set book _runtime base_payload [dict remove [snapshot $book] workspace_metadata]
    return $book
}
proc ::GX::ScientificWorksheet::load {id} {
    set item [::GX::interactiveDocumentRead $id]
    if {[dict get $item module_id] ne "viewer.scientific_worksheet" || [dict get $item provider_id] ne "scientific_worksheet" || [dict get $item format] ni {scientific_worksheet.v1 scientific_worksheet.v2}} {error {Document is not a supported Scientific Worksheet}}
    set book [dict get $item payload]
    if {[dict get $book format] ni {scientific_worksheet.v1 scientific_worksheet.v2}} {error {Unsupported Worksheet payload}}
    if {[dict exists $book _runtime]} {dict unset book _runtime}
    dict set book document_id $id;set book [_upgrade $book]
    dict set book _runtime owner_generation [dict get $item generation]
    dict set book _runtime document_revision [dict get $item revision]
    dict set book _runtime base_payload [dict remove [dict get $item payload] workspace_metadata _runtime]
    _dropBookCache $book
    return $book
}
proc ::GX::ScientificWorksheet::_key {book} {return "[dict get $book _runtime session_token]/[dict get $book _runtime workbook_id]/[dict get $book active_sheet]"}
proc ::GX::ScientificWorksheet::_dropBookCache {book} {
    variable cache;variable spill;variable dirty;variable automaticCacheSnapshots
    set prefix "[dict get $book _runtime session_token]/[dict get $book _runtime workbook_id]/"
    foreach name {cache spill dirty automaticCacheSnapshots} {
        upvar 0 $name entries
        foreach key [dict keys $entries] {if {[string first $prefix $key]==0} {dict unset entries $key}}
    }
}
proc ::GX::ScientificWorksheet::_loadSheet {book sheet} {
    if {![dict exists $book sheets $sheet]} {error "#REF! Unknown sheet '$sheet'."}
    dict set book active_sheet $sheet
    dict for {key value} [dict get $book sheets $sheet] {dict set book $key $value}
    return $book
}
proc ::GX::ScientificWorksheet::renameSheet {book old name} {
    set book [_flush $book];validateBook $book;_validSheetName $name
    if {![dict exists $book sheets $old] || [dict exists $book sheets $name]} {error {Source sheet is missing or destination already exists}}
    set data [dict get $book sheets $old];dict unset book sheets $old;dict set book sheets $name $data
    set order {};foreach item [dict get $book sheet_order] {lappend order [expr {$item eq $old?$name:$item}]};dict set book sheet_order $order
    set active [dict get $book active_sheet];if {$active eq $old} {set active $name}
    if {[dict exists $book charts]} {dict for {chartId chart} [dict get $book charts] {if {[dict exists $chart sheet] && [dict get $chart sheet] eq $old} {dict set book charts $chartId sheet $name}}}
    dict for {sheet body} [dict get $book sheets] {
        dict for {address cell} [dict get $body cells] {
            if {[dict get $cell kind] ne "formula"} continue
            dict set book sheets $sheet cells $address source [_rewriteReferences [dict get $cell source] rename $old $name]
        }
    }
    set book [_loadSheet $book $active];dict incr book revision;_dropBookCache $book
    return $book
}
proc ::GX::ScientificWorksheet::deleteSheet {book name} {
    set book [_flush $book];validateBook $book
    if {[llength [dict get $book sheet_order]]<2} {error {A workbook must have at least one sheet}}
    if {![dict exists $book sheets $name]} {error "Unknown sheet '$name'."}
    if {[dict exists $book charts]} {dict for {chartId chart} [dict get $book charts] {if {[dict exists $chart sheet] && [dict get $chart sheet] eq $name} {error "Sheet is a live source of chart $chartId; remove or rebind that chart before deleting its source"}}}
    dict unset book sheets $name;set order {};foreach sheet [dict get $book sheet_order] {if {$sheet ne $name} {lappend order $sheet}}
    dict set book sheet_order $order
    set active [dict get $book active_sheet];if {$active eq $name} {set active [lindex $order 0]}
    set book [_loadSheet $book $active];dict incr book revision;_dropBookCache $book
    return $book
}
# One string-safe reference scanner serves rename, fill and clipboard shifts.
proc ::GX::ScientificWorksheet::_rewriteReferences {source mode a b} {
    set result {};set quoted 0;set escaped 0;set length [string length $source]
    for {set i 0} {$i<$length} {} {
        set ch [string index $source $i]
        if {$ch eq {"} && !$escaped} {set quoted [expr {!$quoted}]}
        if {!$quoted && ($i==0 || ![regexp {[A-Za-z0-9_.$!]} [string index $source [expr {$i-1}]]]) && [regexp {^(?:[A-Za-z_][A-Za-z0-9_]*!)?\$?[A-Za-z]{1,3}\$?[1-9][0-9]*} [string range $source $i end] token]} {
            set end [expr {$i+[string length $token]}]
            if {$end==$length || ![regexp {[A-Za-z0-9_.$!]} [string index $source $end]]} {
                set ref [_reference $token];set sheet [dict get $ref sheet]
                if {$mode eq "structural"} {
                    lassign $a targetSheet formulaSheet axis position count deleting
                    if {$sheet eq $targetSheet || ($sheet eq {} && $formulaSheet eq $targetSheet)} {
                        lassign [_parts [dict get $ref address]] c r;set coordinate [expr {$axis eq "row"?$r:$c}]
                        if {$deleting && $coordinate >= $position && $coordinate < $position+$count} {set token {#REF!}} else {
                            if {$coordinate >= $position} {incr coordinate [expr {$deleting?-$count:$count}]}
                            if {$axis eq "row"} {set r $coordinate} else {set c $coordinate}
                            _cell "[_columnName $c]$r"
                            set token "[expr {$sheet eq {}?{}:"$sheet!"}][expr {[dict get $ref absolute_column]?{$}:{}}][_columnName $c][expr {[dict get $ref absolute_row]?{$}:{}}]$r"
                        }
                    }
                } elseif {$mode eq "rename"} {
                    if {$sheet eq $a} {set token "$b![lindex [split $token !] end]"}
                } else {
                    lassign [_parts [dict get $ref address]] c r
                    if {![dict get $ref absolute_column]} {incr c $a};if {![dict get $ref absolute_row]} {incr r $b}
                    set address "[_columnName $c]$r";_cell $address
                    set token "[expr {$sheet eq {}?{}:"$sheet!"}][expr {[dict get $ref absolute_column]?{$}:{}}][_columnName $c][expr {[dict get $ref absolute_row]?{$}:{}}]$r"
                }
                append result $token;set i $end;set escaped 0;continue
            }
        }
        append result $ch
        if {$ch eq "\\" && !$escaped} {set escaped 1} else {set escaped 0}
        incr i
    }
    return $result
}
proc ::GX::ScientificWorksheet::shiftFormula {source columnDelta rowDelta} {return [_rewriteReferences $source shift $columnDelta $rowDelta]}
proc ::GX::ScientificWorksheet::_dependencies {book formula} {
    set deps {};set tokens [_tokenize $formula];set current [dict get $book active_sheet]
    for {set i 0} {$i<[llength $tokens]-1} {incr i} {
        lassign [lindex $tokens $i] kind token
        if {$kind ne "identifier"} continue
        set ref [_reference $token]
        if {$ref ne {}} {
            set sheet [dict get $ref sheet];if {$sheet eq {}} {set sheet $current}
            set addresses [list [dict get $ref address]]
            if {[lindex [lindex $tokens [expr {$i+1}]] 1] eq ":"} {
                set last [_reference [lindex [lindex $tokens [expr {$i+2}]] 1]]
                if {$last eq {} || ([dict get $last sheet] ne {} && [dict get $last sheet] ne $sheet)} {error {#REF! Range endpoints must belong to the same sheet}}
                set addresses [rangeCells [dict get $ref address] [dict get $last address]];incr i 2
            }
            foreach address $addresses {dict set deps "$sheet!$address" 1}
        } elseif {[dict exists $book ranges $token]} {
            foreach address [dict get $book ranges $token] {dict set deps "$current!$address" 1}
        } elseif {[dict exists $book columns $token] && [lindex [lindex $tokens [expr {$i+1}]] 1] eq "\["} {
            set address "[dict get $book columns $token][lindex [lindex $tokens [expr {$i+2}]] 1]";_cell $address;dict set deps "$current!$address" 1
        }
    }
    return [dict keys $deps]
}
proc ::GX::ScientificWorksheet::_invalidate {book changed} {
    variable cache;variable spill;variable dirty
    set all [_flush $book];set queue {};foreach address $changed {lappend queue "[dict get $book active_sheet]!$address"}
    set affected {};while {[llength $queue]} {
        set target [lindex $queue 0];set queue [lrange $queue 1 end]
        if {[dict exists $affected $target]} continue
        dict set affected $target 1
        dict for {sheet data} [dict get $all sheets] {
            set selected [_loadSheet $all $sheet]
            dict for {address cell} [dict get $data cells] {
                if {[dict get $cell kind] ne "formula" || [catch {_dependencies $selected [dict get $cell source]} references]} continue
                if {$target in $references} {lappend queue "$sheet!$address"}
            }
        }
    }
    dict for {target unused} $affected {
        lassign [split $target !] sheet address
        set key [_key [_loadSheet $all $sheet]];dict set dirty $key $address 1
        if {[dict get $book options calculation_mode] eq "automatic" || $target in [lmap x $changed {format "%s!%s" [dict get $book active_sheet] $x}]} {
            if {[dict exists $cache $key $address]} {dict unset cache $key $address}
            if {[dict exists $spill $key]} {dict for {destination item} [dict get $spill $key] {if {[dict get $item anchor] eq $address} {dict unset spill $key $destination}}}
        }
    }
    return [dict keys $affected]
}
proc ::GX::ScientificWorksheet::setCell {book address source} {
    set book [_upgrade $book];validateBook $book;set address [_cell $address]
    _reserveBeforeEdit $book $address $address
    variable spill;set key [_key $book]
    if {[dict exists $spill $key $address]} {error {#SPILL! Edit the anchor or clear the spilled result first}}
    if {[string equal -nocase [string trim $source] NaN]} {lassign [_parts $address] c r;set column [_columnName $c];set unit [expr {[dict exists $book column_metadata $column unit]?[dict get $book column_metadata $column unit]:{}}];return [setTypedCell $book $address [dict create kind nan value NaN unit $unit]]}
    set result [_v1_setCell $book $address $source]
    if {[string toupper [string trim $source]] in {TRUE FALSE}} {dict set result cells $address kind boolean}
    set affected [_invalidate $book [list $address]]
    return [_staleOperations $result $affected $address]
}
proc ::GX::ScientificWorksheet::setTypedCell {book address item} {
    set book [_upgrade $book];validateBook $book;set address [_cell $address]
    foreach field {kind value unit} {if {![dict exists $item $field]} {error "Typed cell requires $field"}}
    set kind [dict get $item kind];set value [dict get $item value]
    if {$kind ni {scalar text boolean complex missing nan vector matrix}} {error {Unsupported typed cell kind}}
    if {$kind in {scalar vector matrix}} {
        foreach v $value {if {![string is double -strict $v] || [catch {expr {abs(double($v))<Inf}} finite] || !$finite} {error {Typed numeric cell requires finite real values; use explicit nan/missing kind}}}
        if {$kind eq "scalar" && [llength $value]!=1} {error {Scalar requires one value}}
    }
    if {$kind eq "boolean" && $value ni {0 1 TRUE FALSE}} {error {Boolean requires true/false or zero/one}}
    if {$kind eq "complex"} {
        if {[llength $value]==2 && [string is double -strict [lindex $value 0]] && [string is double -strict [lindex $value 1]]} {set value [dict create shape {1 1} real [list [lindex $value 0]] imaginary [list [lindex $value 1]]];dict set item value $value}
        foreach field {shape real imaginary} {if {![dict exists $value $field]} {error "Complex cell requires $field"}}
        lassign [dict get $value shape] rows cols
        if {![string is entier -strict $rows] || ![string is entier -strict $cols] || $rows<1 || $cols<1 || $rows*$cols>20000 || [llength [dict get $value real]]!=$rows*$cols || [llength [dict get $value imaginary]]!=$rows*$cols} {error {Invalid complex shape/components}}
        foreach v [concat [dict get $value real] [dict get $value imaginary]] {if {![string is double -strict $v] || ![expr {abs(double($v))<Inf}]} {error {Complex components must be finite}}}
    }
    if {$kind eq "matrix" && (![dict exists $item shape] || [llength [dict get $item shape]]!=2)} {error {Matrix requires two-dimensional shape}}
    set end $address
    if {$kind in {vector matrix}} {
        lassign [_parts $address] c r
        if {$kind eq "matrix"} {lassign [dict get $item shape] rows cols} else {set rows [llength $value];set cols 1}
        set end [_cell "[_columnName [expr {$c+$cols-1}]][expr {$r+$rows-1}]"]
    }
    _reserveBeforeEdit $book $address $end
    variable spill;set spillKey [_key $book]
    if {[dict exists $spill $spillKey $address]} {error {#SPILL! Typed edit overlaps another anchor}}
    set cell [dict create source $value kind $kind unit [dict get $item unit] lineage {}]
    foreach field {lineage shape} {if {[dict exists $item $field]} {dict set cell $field [dict get $item $field]}}
    if {$kind in {missing nan}} {dict set cell source NaN}
    if {$kind eq "boolean"} {dict set cell source [expr {$value in {1 TRUE}?"TRUE":"FALSE"}]}
    dict set book cells $address $cell
    if {$kind in {vector matrix}} {_registerSpill $book $address $item}
    dict incr book revision;set affected [_invalidate $book [list $address]]
    return [_staleOperations $book $affected $address]
}
proc ::GX::ScientificWorksheet::viewportCells {book firstRow firstColumn rowCount columnCount} {
    foreach n [list $firstRow $firstColumn $rowCount $columnCount] {if {![string is entier -strict $n] || $n<1} {error {Viewport indices and counts must be positive integers}}}
    if {$firstRow+$rowCount-1>1000000 || $rowCount*$columnCount>4096} {error {Viewport exceeds bounded Worksheet capacity}}
    set rows {};for {set r $firstRow} {$r<$firstRow+$rowCount} {incr r} {lappend rows $r}
    return [viewportRows $book $rows $firstColumn $columnCount]
}
proc ::GX::ScientificWorksheet::_binary {operator left right} {
    if {[dict get $left kind] ne "scalar" || [dict get $right kind] ne "scalar"} {error {Scalar arithmetic requires finite real scalar cells; use provider-owned typed operations for arrays/complex/missing/NaN}}
    set a [dict get $left value];set b [dict get $right value]
    if {![string is double -strict $a] || ![string is double -strict $b]} {error {Arithmetic requires real numeric values}}
    set plan [::GX::unitRegistryArithmeticPlan $operator [dict get $left unit] [dict get $right unit] $b]
    if {[dict get $plan left_scale]!=1} {set a [expr {$a*[dict get $plan left_scale]}]};if {[dict get $plan right_scale]!=1} {set b [expr {$b*[dict get $plan right_scale]}]}
    switch -- $operator {
        + {set result [expr {$a+$b}]} - {set result [expr {$a-$b}]}
        * {set result [expr {$a*$b}]} / {set result [expr {$a/double($b)}]}
        ^ {set result [expr {pow($a,$b)}]}
        < {set result [expr {$a<$b}]} > {set result [expr {$a>$b}]}
        <= {set result [expr {$a<=$b}]} >= {set result [expr {$a>=$b}]}
        == {set result [expr {$a==$b}]} != {set result [expr {$a!=$b}]}
    }
    if {![expr {abs(double($result))<Inf}]} {error {Nonfinite formula result}}
    set unit [dict get $plan output_unit];if {$unit eq "1"} {set unit {}}
    return [_carryStatistics [_value $result $unit] [list $left $right]]
}
proc ::GX::ScientificWorksheet::convertUnit {book first last targetUnit} {
    set book [_upgrade $book];validateBook $book;set pending {}
    foreach address [rangeCells $first $last] {
        set item [value $book $address]
        if {[dict get $item kind] eq "blank"} continue
        if {[dict get $item kind] ne "scalar"} {error {Unit conversion requires finite real scalar cells}}
        set sourceUnit [dict get $item unit];if {$sourceUnit eq {}} {set sourceUnit 1}
        set converted [lindex [::GX::unitRegistryConvertValues $sourceUnit $targetUnit [list [dict get $item value]]] 0]
        set lineage [dict create transform unit_conversion source_unit $sourceUnit target_unit $targetUnit source_lineage [_sourceLineage $item]]
        dict set pending $address [dict create source $converted kind manual unit $targetUnit lineage $lineage]
    }
    dict for {address cell} $pending {dict set book cells $address $cell}
    set columns {};foreach address [dict keys $pending] {lappend columns [_columnName [lindex [_parts $address] 0]]};set book [_reconcileColumnUnits $book $columns]
    dict incr book revision;set affected [_invalidate $book [dict keys $pending]];set book [_staleOperations $book $affected];if {[dict get $book options calculation_mode] eq "automatic"} {_dropBookCache $book}
    return $book
}
proc ::GX::ScientificWorksheet::_registerSpill {book anchor result} {
    variable spill;set key [_key $book];lassign [_parts $anchor] c0 r0
    set values [dict get $result value]
    if {[dict get $result kind] eq "matrix"} {lassign [dict get $result shape] rows cols} else {set rows [llength $values];set cols 1}
    if {![string is entier -strict $rows] || ![string is entier -strict $cols] || $rows<1 || $cols<1 || $rows*$cols!=[llength $values] || $rows*$cols>20000} {error {#VALUE! Invalid bounded spill shape}}
    _cell "[_columnName [expr {$c0+$cols-1}]][expr {$r0+$rows-1}]"
    set pending {};set i 0
    for {set r 0} {$r<$rows} {incr r} {for {set c 0} {$c<$cols} {incr c} {
        set address "[_columnName [expr {$c0+$c}]][expr {$r0+$r}]"
        if {$address ne $anchor && [dict exists $book cells $address]} {error "#SPILL! $address contains data"}
        if {[dict exists $spill $key $address] && [dict get $spill $key $address anchor] ne $anchor} {error "#SPILL! $address belongs to another anchor"}
        if {$address ne $anchor} {dict set pending $address [dict merge [_scalarComponent $result $i] [dict create origin spill anchor $anchor]]}
        incr i
    }}
    # Commit reservations only after every coordinate and collision is checked.
    if {[dict exists $spill $key]} {dict for {address item} [dict get $spill $key] {if {[dict get $item anchor] eq $anchor} {dict unset spill $key $address}}}
    dict for {address item} $pending {dict set spill $key $address $item}
}
proc ::GX::ScientificWorksheet::clipboardCapture {book first last} {
    validateBook $book;lassign [rectangle $first $last] c1 r1 c2 r2
    set first "[_columnName $c1]$r1";set last "[_columnName $c2]$r2"
    set cells {};set styles {};set merges {}
    foreach address [rangeCells $first $last] {
        set effective [styleAt $book $address];if {$effective ne {}} {dict set styles $address $effective}
        if {[dict exists $book cells $address]} {
            set cell [dict get $book cells $address]
            if {[dict exists $cell lineage operation_destination]} {set item [value $book $address];dict set cell lineage [dict create transform copied_guided_result source_cell $address operation [dict get $cell lineage operation] field [dict get $cell lineage field] source_lineage [_sourceLineage $item]];dict set cell kind manual;foreach field {statistical_sources source_lineage statistical_result statistical_field statistical_element statistical_window} {if {[dict exists $item $field]} {dict set cell $field [dict get $item $field]}}}
            dict set cells $address $cell
        }
    }
    dict for {anchor bounds} [dict get $book merges] {
        lassign $bounds a b c d
        if {$a>$c2 || $c<$c1 || $b>$r2 || $d<$r1} continue
        if {$a<$c1 || $b<$r1 || $c>$c2 || $d>$r2} {error {Copy the entire merged span or unmerge it first}}
        dict set merges $anchor $bounds
    }
    return [dict create styles $styles merges $merges format scientific_worksheet.clipboard.v2 source_identity [bookIdentity $book] first [_cell $first] last [_cell $last] cells $cells]
}
proc ::GX::ScientificWorksheet::clipboardPaste {book clip destination} {
    validateBook $book
    if {[dict get $clip format] ne "scientific_worksheet.clipboard.v2"} {error {Unsupported typed clipboard}}
    lassign [_parts [dict get $clip first]] c0 r0;lassign [_parts [dict get $clip last]] c1 r1;lassign [_parts $destination] dc dr
    set deltaC [expr {$dc-$c0}];set deltaR [expr {$dr-$r0}]
    _cell "[_columnName [expr {$c1+$deltaC}]][expr {$r1+$deltaR}]"
    set end "[_columnName [expr {$c1+$deltaC}]][expr {$r1+$deltaR}]"
    _reserveBeforeEdit $book $destination $end
    variable spill;set spillKey [_key $book]
    set pending {};foreach from [rangeCells [dict get $clip first] [dict get $clip last]] {
        lassign [_parts $from] c r;set to "[_columnName [expr {$c+$deltaC}]][expr {$r+$deltaR}]"
        if {[dict exists $spill $spillKey $to]} {error "#SPILL! Clipboard overlaps spilled output at $to"}
        if {[dict exists $clip cells $from]} {
            set cell [dict get $clip cells $from]
            if {[dict get $cell kind] eq "formula"} {dict set cell source [shiftFormula [dict get $cell source] $deltaC $deltaR]}
            if {[dict exists $cell lineage operation_destination]} {dict set cell lineage [dict create transform copied_guided_result source_cell $from source_lineage [_sourceLineage [dict create lineage [dict get $cell lineage]]]];dict set cell kind manual}
            dict set pending $to $cell
        } else {dict set pending $to {}}
    }
    set pendingStyles {};set pendingMerges {}
    dict for {from style} [::GX::datasetPublicationV2DictDefault $clip styles {}] {lassign [_parts $from] c r;dict set pendingStyles "[_columnName [expr {$c+$deltaC}]][expr {$r+$deltaR}]" [styleValidate $style]}
    dict for {from bounds} [::GX::datasetPublicationV2DictDefault $clip merges {}] {
        lassign $bounds c1 r1 c2 r2
        set start "[_columnName [expr {$c1+$deltaC}]][expr {$r1+$deltaR}]"
        dict set pendingMerges $start [list [expr {$c1+$deltaC}] [expr {$r1+$deltaR}] [expr {$c2+$deltaC}] [expr {$r2+$deltaR}]]
    }
    dict for {address style} $pendingStyles {dict set book styles $address $style}
    dict for {anchor bounds} $pendingMerges {dict set book merges $anchor $bounds}
    # Typed value copies are staged before mutation; overlap reads only clipboard.
    dict for {address cell} $pending {if {$cell eq {}} {if {[dict exists $book cells $address]} {dict unset book cells $address}} else {dict set book cells $address $cell}}
    dict incr book revision;set affected [_invalidate $book [dict keys $pending]];set book [_staleOperations $book $affected];if {[dict get $book options calculation_mode] eq "automatic"} {_dropBookCache $book}
    dict for {address cell} $pending {if {$cell ne {} && [dict get $cell kind] in {vector matrix}} {_evalCell $book $address {}}}
    return $book
}
proc ::GX::ScientificWorksheet::copyRange {book first last destination} {return [clipboardPaste $book [clipboardCapture $book $first $last] $destination]}
proc ::GX::ScientificWorksheet::tsvEncode {rows} {
    set output {};foreach row $rows {
        set fields {};foreach value $row {
            if {[regexp {[\t\r\n"]} $value]} {set value "\"[string map [list {"} {""}] $value]\""}
            lappend fields $value
        };lappend output [join $fields \t]
    };return [join $output \n]
}
proc ::GX::ScientificWorksheet::tsvDecode {text} {
    if {[string bytelength $text]>8388608} {error {External clipboard exceeds 8 MiB}}
    set rows {};set row {};set field {};set quoted 0;set closed 0
    for {set i 0} {$i<[string length $text]} {incr i} {
        set ch [string index $text $i]
        if {$quoted} {
            if {$ch eq {"}} {if {[string index $text [expr {$i+1}]] eq {"}} {append field {"};incr i} else {set quoted 0;set closed 1}} else {append field $ch}
        } elseif {$ch eq {"} && $field eq {} && !$closed} {set quoted 1
        } elseif {$ch in {\t \n \r}} {
            lappend row $field;set field {};set closed 0
            if {$ch ne "\t"} {lappend rows $row;set row {};if {$ch eq "\r" && [string index $text [expr {$i+1}]] eq "\n"} {incr i}}
        } else {if {$closed} {error {Unexpected text after quoted TSV field}};append field $ch}
    }
    if {$quoted} {error {Unclosed quoted TSV field}}
    if {$row ne {} || $field ne {} || $closed || ![llength $rows] || [string index $text end] eq "\t"} {lappend row $field;lappend rows $row}
    set count 0;foreach row $rows {incr count [llength $row]};if {$count>20000} {error {Clipboard exceeds 20000 cells}}
    return $rows
}
proc ::GX::ScientificWorksheet::_sourceLineage {item} {
    set records [expr {[dict exists $item source_lineage]?[dict get $item source_lineage]:{}}]
    if {[dict exists $item lineage source_lineage]} {foreach record [dict get $item lineage source_lineage] {if {$record ni $records} {lappend records $record}}}
    if {[dict exists $item lineage dataset_id] && [dict exists $item lineage variable_id]} {
        set record [dict get $item lineage]
        if {$record ni $records} {lappend records $record}
    }
    return $records
}
proc ::GX::ScientificWorksheet::_rowBounds {first last} {
    if {![string is entier -strict $first] || ![string is entier -strict $last] || $first<1 || $last<$first || $last>1000000 || $last-$first>=20000} {error {Operation requires 1–20000 rows within 1–1000000}}
}
proc ::GX::ScientificWorksheet::_permuteRows {book first last sources} {
    _rowBounds $first $last
    dict for {anchor bounds} [dict get $book merges] {lassign $bounds c1 r1 c2 r2;if {$r1<=$last && $r2>=$first} {error {Unmerge affected cells before sorting their scientific rows}}}
    set styleBuckets {};set styles [dict get $book styles]
    dict for {address style} $styles {lassign [_parts $address] c r;if {$r>=$first && $r<=$last} {dict set styleBuckets $r $c $style;dict unset styles $address}}
    set target $first;foreach source $sources {if {[dict exists $styleBuckets $source]} {dict for {c style} [dict get $styleBuckets $source] {dict set styles "[_columnName $c]$target" $style}};incr target}
    dict set book styles $styles
    set buckets {};set cells [dict get $book cells];set identities [dict get $book row_identity]
    dict for {address cell} [dict get $book cells] {
        lassign [_parts $address] c r
        if {$r<$first || $r>$last} continue
        dict set buckets $r $c $cell;dict unset cells $address
    }
    set target $first;foreach source $sources {
        if {$source<$first || $source>$last} {error {Invalid row permutation}}
        dict set identities $target [expr {[dict exists $book row_identity $source]?[dict get $book row_identity $source]:$source}]
        if {[dict exists $buckets $source]} {dict for {c cell} [dict get $buckets $source] {
            if {[dict get $cell kind] eq "formula"} {dict set cell source [shiftFormula [dict get $cell source] 0 [expr {$target-$source}]]}
            dict set cells "[_columnName $c]$target" $cell
        }}
        incr target
    }
    dict set book cells $cells;dict set book row_identity $identities;dict incr book revision
    # Captured outputs preserve identities but must be explicitly refreshed/unlinked.
    dict for {destination operation} [dict get $book operations] {dict set book operations $destination status stale;dict set book operations $destination stale_reason {Rows reordered}}
    _dropBookCache $book;return $book
}
proc ::GX::ScientificWorksheet::sortRows {book first last columns directions} {
    set book [_upgrade $book];validateBook $book;_rowBounds $first $last
    if {![llength $columns] || [llength $columns]!=[llength $directions]} {error {Choose matching sort columns and directions}}
    foreach c $columns {_columnNumber $c};foreach d $directions {if {$d ni {ascending descending}} {error {Sort direction must be ascending or descending}}}
    _ensureCalculationSnapshot $book
    set rows {};for {set r $first} {$r<=$last} {incr r} {
        set keys {};foreach c $columns {set item [_evalCell $book "[string toupper $c]$r" {}];lappend keys [dict get $item value]};lappend rows [list $r $keys]
    }
    set sorted [lsort -command [list ::GX::ScientificWorksheet::_compareRows $directions] $rows]
    return [_permuteRows $book $first $last [lmap item $sorted {lindex $item 0}]]
}
proc ::GX::ScientificWorksheet::restoreRowOrder {book first last} {
    set book [_upgrade $book];validateBook $book;_rowBounds $first $last
    set rows {};for {set r $first} {$r<=$last} {incr r} {lappend rows [list $r [expr {[dict exists $book row_identity $r]?[dict get $book row_identity $r]:$r}]]}
    return [_permuteRows $book $first $last [lmap item [lsort -integer -index 1 $rows] {lindex $item 0}]]
}
proc ::GX::ScientificWorksheet::operationStatus {book destination} {
    validateBook $book;set destination [_cell $destination]
    if {![dict exists $book operations $destination]} {error {No captured operation at this destination}}
    return [dict get $book operations $destination]
}
proc ::GX::ScientificWorksheet::unlinkOperation {book destination} {
    validateBook $book;set destination [_cell $destination]
    if {![dict exists $book operations $destination]} {error {No captured operation at this destination}}
    dict for {address cell} [dict get $book cells] {
        if {[dict exists $cell lineage operation_destination] && [dict get $cell lineage operation_destination] eq $destination} {
            set item [value $book $address];dict set cell lineage [dict create transform unlinked_captured_result operation [dict get $cell lineage operation] field [dict get $cell lineage field] source_lineage [_sourceLineage $item]];dict set cell kind manual;foreach field {statistical_sources source_lineage statistical_result statistical_field statistical_element statistical_window} {if {[dict exists $item $field]} {dict set cell $field [dict get $item $field]}}
            dict set book cells $address $cell
        }
    }
    dict unset book operations $destination;dict incr book revision;_dropBookCache $book;return $book
}
proc ::GX::ScientificWorksheet::refreshOperation {book destination {inputs {}}} {
    validateBook $book;set definition [operationStatus $book $destination]
    if {$inputs eq {}} {set inputs [dict get $definition inputs]}
    # Remove only still-owned cells. Explicit user edits remain collision guards.
    set candidate $book
    dict for {address cell} [dict get $candidate cells] {if {[dict exists $cell lineage operation_destination] && [dict get $cell lineage operation_destination] eq $destination} {dict unset candidate cells $address}}
    dict unset candidate operations $destination;_dropBookCache $candidate
    return [applyOperation $candidate [dict get $definition operation] $inputs [dict get $definition options] $destination [dict get $definition field] [dict get $definition model] [expr {[dict exists $definition field_window]?[dict get $definition field_window]:{}}]]
}
proc ::GX::ScientificWorksheet::columnValues {book column first last} {
    validateBook $book;_rowBounds $first $last;set column [string toupper $column];_columnNumber $column
    set values {};set sources {};set formulas {};set statistics {};set lineage {};set units {};set masks {};set kinds {}
    _ensureCalculationSnapshot $book
    for {set r $first} {$r<=$last} {incr r} {
        set address "$column$r";set item [_evalCell $book $address {}];set kind [dict get $item kind]
        if {[dict exists $item operation_status] && [dict get $item operation_status] eq "stale"} {error "Captured output at $address is stale; refresh or explicitly unlink it before publication"}
        if {$kind ni {scalar missing nan blank}} {error "Publication requires real scalar, explicit missing or NaN at $address"}
        set unit [dict get $item unit];if {$kind ni {blank missing} && !($kind eq "nan" && $unit eq {})} {dict set units $unit 1}
        lappend kinds $kind;lappend masks [expr {$kind in {blank missing}}]
        if {$kind in {blank missing}} {lappend values NaN} else {lappend values [dict get $item value]}
        set references [_sourceLineage $item];foreach record $references {dict set sources $record 1}
        set source {};if {[dict exists $book cells $address source]} {set source [dict get $book cells $address source]}
        lappend lineage [dict create output_row [expr {$r-$first}] sheet [dict get $book active_sheet] cell $address source_row_identity [expr {[dict exists $book row_identity $r]?[dict get $book row_identity $r]:$r}] sources $references expression $source]
        if {[string index $source 0] eq "=" && $source ni $formulas} {lappend formulas $source}
        set stats [_statisticalSources $item];if {$stats ne {}} {dict set statistics $address $stats}
    }
    if {[dict size $units]>1} {error {Column has mixed units; convert explicitly before publication}}
    set outputUnit [lindex [dict keys $units] 0];if {![dict size $units] && [dict exists $book column_metadata $column unit]} {set outputUnit [dict get $book column_metadata $column unit]}
    return [dict create values $values unit $outputUnit sources [dict keys $sources] formulas $formulas statistical_sources $statistics row_lineage $lineage missing_mask $masks cell_kinds $kinds]
}
proc ::GX::ScientificWorksheet::historySnapshot {book} {
    set state [dict remove [snapshot $book] history workspace_metadata managed_operation_tickets]
    if {[string bytelength $state]<=524288} {return $state}
    validateBook $book
    set document [dict get $book document_id]
    if {$document eq {}} {error {Save the Worksheet before a large scientific edit so CORE can own its bounded History resource}}
    variable historyResourceCache
    if {![info exists historyResourceCache]} {set historyResourceCache {}}
    set key "[dict get $book _runtime session_token]/[dict get $book workbook_uuid]"
    if {[dict exists $historyResourceCache $key] && [dict get $historyResourceCache $key state] eq $state} {return [dict get $historyResourceCache $key receipt]}
    set bytes [encoding convertto utf-8 $state]
    if {[string length $bytes]>67108864} {error {Worksheet History snapshot exceeds bounded 64 MiB managed resource; split the Workbook explicitly}}
    set dependencies [::GX::interactiveDocumentResourceReferences $state]
    set metadata [dict create format scientific_worksheet.snapshot.v2 origin [::GX::documentOriginRead $document] dependencies $dependencies scientific_authority 1]
    set writer [::GX::interactiveDocumentResourceOpenWriter $document $metadata]
    try {
        for {set offset 0} {$offset<[string length $bytes]} {incr offset 1048576} {::GX::interactiveDocumentResourceAppend $writer [string range $bytes $offset [expr {$offset+1048575}]]}
        set reference [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
    set receipt {};foreach field {format name workbook_uuid document_id revision active_sheet} {dict set receipt $field [dict get $state $field]}
    dict set receipt history_resource $reference
    dict set historyResourceCache $key [dict create state $state receipt $receipt]
    if {[dict size $historyResourceCache]>8} {dict unset historyResourceCache [lindex [dict keys $historyResourceCache] 0]}
    return $receipt
}
proc ::GX::ScientificWorksheet::workspaceValidate {payload} {
    foreach key {format name cells document_id revision sheets sheet_order active_sheet workbook_uuid} {if {![dict exists $payload $key]} {error "Worksheet Workspace requires $key"}}
    if {[dict get $payload format] ne "scientific_worksheet.v2" || [dict get $payload active_sheet] ni [dict get $payload sheet_order]} {error {Invalid Worksheet Workspace format or active sheet}}
    foreach sheet [dict get $payload sheet_order] {
        if {![dict exists $payload sheets $sheet]} {error {Worksheet sheet order refers to absent sheet}}
        set body [dict get $payload sheets $sheet]
        foreach layer [::GX::datasetPublicationV2DictDefault $body range_styles {}] {
            _presentationBoundsValidate [dict get $layer bounds];styleValidate [dict get $layer style]
            if {[dict get $layer borders] ni {{} all outer inner top bottom left right none}} {error {Invalid persisted range borders}}
        }
        dict for {address style} [::GX::datasetPublicationV2DictDefault $body styles {}] {_cell $address;styleValidate $style}
        dict for {anchor bounds} [::GX::datasetPublicationV2DictDefault $body merges {}] {
            _presentationBoundsValidate $bounds
            if {$anchor ne "[_columnName [lindex $bounds 0]][lindex $bounds 1]"} {error {Invalid persisted merge anchor}}
        }
        foreach axis {row column} field {row_heights column_widths} {
            dict for {index pixels} [::GX::datasetPublicationV2DictDefault $body $field {}] {
                ::GX::uiFieldNormalize [dict create type integer min 1 max [expr {$axis eq "row"?1000000:702}]] $index
                ::GX::uiFieldNormalize [dict create type integer min [expr {$axis eq "row"?16:35}] max 2000] $pixels
            }
        }
        dict for {address cell} [dict get $body cells] {_cell $address;foreach key {source kind unit} {if {![dict exists $cell $key]} {error "Persisted cell requires $key"}}}
    }
    return 1
}
proc ::GX::ScientificWorksheet::workspaceOpen {id} {::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1;return [open [dict create document_id $id]]}
proc ::GX::ScientificWorksheet::_structuralEdit {book axis position count deleting} {
    set book [_flush $book];validateBook $book
    set limit [expr {$axis eq "row"?1000000:702}]
    if {![string is entier -strict $position] || ![string is entier -strict $count] || $position<1 || $count<1 || $position+$count-1>$limit} {error {Structural edit is outside supported Worksheet bounds}}
    if {[dict size [dict get $book operations]]} {error {Unlink captured scientific operations before inserting or deleting their rows/columns}}
    set targetSheet [dict get $book active_sheet]
    set book [_remapChartSources $book $axis $position $count $deleting]
    set data [dict get $book sheets $targetSheet];set cells {}
    dict for {address cell} [dict get $data cells] {
        lassign [_parts $address] c r;set coordinate [expr {$axis eq "row"?$r:$c}]
        if {$coordinate >= $position} {
            if {$deleting && $coordinate<$position+$count} continue
            incr coordinate [expr {$deleting?-$count:$count}]
            if {$coordinate>$limit} {error {Insertion would move existing scientific cells beyond Worksheet capacity}}
            if {$axis eq "row"} {set r $coordinate} else {set c $coordinate}
        }
        dict set cells "[_columnName $c]$r" $cell
    }
    dict set data cells $cells
    set shiftedStyles {}
    dict for {address style} [dict get $data styles] {
        set address [_presentationShiftAddress $address $axis $position $count $deleting]
        if {$address ne {}} {dict set shiftedStyles $address $style}
    }
    dict set data styles $shiftedStyles
    set layers {}
    foreach layer [dict get $data range_styles] {
        lassign [dict get $layer bounds] c1 r1 c2 r2
        set interval [_presentationShiftInterval [expr {$axis eq "row"?$r1:$c1}] [expr {$axis eq "row"?$r2:$c2}] $position $count $deleting]
        if {$interval eq {}} continue
        if {$axis eq "row"} {lassign $interval r1 r2} else {lassign $interval c1 c2}
        dict set layer bounds [list $c1 $r1 $c2 $r2];lappend layers $layer
    }
    dict set data range_styles $layers
    set merges {}
    dict for {anchor bounds} [dict get $data merges] {
        lassign $bounds c1 r1 c2 r2
        set interval [_presentationShiftInterval [expr {$axis eq "row"?$r1:$c1}] [expr {$axis eq "row"?$r2:$c2}] $position $count $deleting]
        if {$interval eq {}} continue
        if {$axis eq "row"} {lassign $interval r1 r2} else {lassign $interval c1 c2}
        if {$c1!=$c2 || $r1!=$r2} {dict set merges "[_columnName $c1]$r1" [list $c1 $r1 $c2 $r2]}
    }
    dict set data merges $merges
    set field [expr {$axis eq "row"?"row_heights":"column_widths"}];set sizes {}
    dict for {index pixels} [dict get $data $field] {
        set interval [_presentationShiftInterval $index $index $position $count $deleting]
        if {$interval ne {}} {dict set sizes [lindex $interval 0] $pixels}
    }
    dict set data $field $sizes
    dict set data active_filter {};dict set data filter_hidden_rows {}
    dict for {name view} [dict get $data filter_views] {dict set data filter_views $name invalid_reason {Rows or columns changed. Review and save this Filter View before applying it again.}}
    if {$axis eq "row"} {
        foreach field {row_identity hidden_rows} {
            set values {};if {[dict exists $data $field]} {dict for {r value} [dict get $data $field] {
                if {$r >= $position} {if {$deleting && $r<$position+$count} continue;incr r [expr {$deleting?-$count:$count}];if {$r>$limit} continue}
                dict set values $r $value
            }};dict set data $field $values
        }
    } else {
        foreach field {column_metadata bindings} {
            set values {};if {[dict exists $data $field]} {dict for {column value} [dict get $data $field] {
                set c [_columnNumber $column];if {$c >= $position} {if {$deleting && $c<$position+$count} continue;incr c [expr {$deleting?-$count:$count}];if {$c>$limit} continue}
                dict set values [_columnName $c] $value
            }};dict set data $field $values
        }
        set columns {};dict for {name column} [dict get $data columns] {
            set c [_columnNumber $column];if {$c >= $position} {if {$deleting && $c<$position+$count} continue;incr c [expr {$deleting?-$count:$count}];if {$c>$limit} continue};dict set columns $name [_columnName $c]
        };dict set data columns $columns
    }
    set ranges {};dict for {name addresses} [dict get $data ranges] {
        set shifted {};foreach address $addresses {
            lassign [_parts $address] c r;set coordinate [expr {$axis eq "row"?$r:$c}]
            if {$coordinate >= $position} {if {$deleting && $coordinate<$position+$count} continue;incr coordinate [expr {$deleting?-$count:$count}];if {$coordinate>$limit} continue;if {$axis eq "row"} {set r $coordinate} else {set c $coordinate}}
            lappend shifted "[_columnName $c]$r"
        };dict set ranges $name $shifted
    };dict set data ranges $ranges
    dict set book sheets $targetSheet $data
    dict for {sheet body} [dict get $book sheets] {
        dict for {address cell} [dict get $body cells] {
            if {[dict get $cell kind] eq "formula"} {dict set book sheets $sheet cells $address source [_rewriteReferences [dict get $cell source] structural [list $targetSheet $sheet $axis $position $count $deleting] {}]}
        }
    }
    set book [_loadSheet $book $targetSheet];dict incr book revision;_dropBookCache $book;return $book
}
proc ::GX::ScientificWorksheet::insertRows {book position {count 1}} {return [_structuralEdit $book row $position $count 0]}
proc ::GX::ScientificWorksheet::deleteRows {book position {count 1}} {return [_structuralEdit $book row $position $count 1]}
proc ::GX::ScientificWorksheet::insertColumns {book position {count 1}} {return [_structuralEdit $book column $position $count 0]}
proc ::GX::ScientificWorksheet::deleteColumns {book position {count 1}} {return [_structuralEdit $book column $position $count 1]}
proc ::GX::ScientificWorksheet::refreshBookAuthority {book} {
    validateBook $book 0
    set id [dict get $book document_id];if {$id eq {}} {return $book}
    # The public registry is the live generation/revision authority. Read/hash
    # scientific payload only when its revision changed, never for every scroll.
    set current {};foreach entry [::GX::interactiveDocumentList viewer.scientific_worksheet scientific_worksheet] {if {[dict get $entry id] eq $id} {set current $entry;break}}
    if {$current eq {} || [dict get $current generation] ne [dict get $book _runtime owner_generation]} {error {Worksheet was deleted or replaced}}
    if {[dict get $current revision] != [dict get $book _runtime document_revision]} {
        set current [::GX::interactiveDocumentRead $id]
        if {[dict get $current generation] ne [dict get $book _runtime owner_generation]} {error {Worksheet was deleted or replaced}}
        set payload [dict get $current payload]
        if {![dict exists $book _runtime base_payload] || [dict remove $payload workspace_metadata _runtime] ne [dict get $book _runtime base_payload]} {error {Scientific Worksheet changed in another editor; reload before editing}}
        dict set book _runtime document_revision [dict get $current revision]
        if {[dict exists $payload workspace_metadata]} {dict set book workspace_metadata [dict get $payload workspace_metadata]}
    }
    return $book
}
proc ::GX::ScientificWorksheet::_reserveBeforeEdit {book first last} {
    lassign [rectangle $first $last] c1 r1 c2 r2
    dict for {anchor bounds} [dict get $book merges] {
        lassign $bounds a b c d
        if {$a>$c2 || $c<$c1 || $b>$r2 || $d<$r1} continue
        if {$first ne $last || $first ne $anchor} {error {Unmerge the presentation span before editing subordinate cells}}
    }
    _ensureCalculationSnapshot $book
    lassign [_parts $last] maxC maxR
    dict for {address cell} [dict get $book cells] {
        if {[dict get $cell kind] ni {formula vector matrix} || $address eq $first} continue
        lassign [_parts $address] c r
        if {$c<=$maxC && $r<=$maxR} {catch {_evalCell $book $address {}}}
    }
}
proc ::GX::ScientificWorksheet::prepareSave {book} {
    set book [refreshBookAuthority [_upgrade $book]];validateBook $book
    return [_flush [_formulaResourceReferences $book]]
}
proc ::GX::ScientificWorksheet::captureOperationEncoded {encoded} {
    if {[string length $encoded]>11184812} {error {Worksheet operation request exceeds 8 MiB}}
    set request [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    foreach key {book operation inputs options model} {if {![dict exists $request $key]} {error "Operation capture requires $key"}}
    set book [dict get $request book];workspaceValidate $book
    if {[dict exists $book _runtime]} {dict unset book _runtime};set book [_upgrade $book]
    set id [dict get $book document_id]
    if {$id ne {}} {
        set doc [::GX::interactiveDocumentRead $id]
        if {[dict get $doc module_id] ne "viewer.scientific_worksheet"} {error {Captured operation document owner differs}}
        dict set book _runtime owner_generation [dict get $doc generation];dict set book _runtime document_revision [dict get $doc revision]
    }
    set raw [_operationRaw $book [dict get $request operation] [dict get $request inputs] [dict get $request options] [dict get $request model]]
    if {[string bytelength $raw]>8388608} {error {Captured result exceeds bounded 8 MiB control result; choose a bounded operation/result window}}
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $raw]]
}
proc ::GX::ScientificWorksheet::operationJobSubmit {book operation inputs options {model {}}} {
    validateBook $book
    if {[dict get $book document_id] eq {}} {error {Save the Worksheet before managed scientific operation submission}}
    set request [dict create book [snapshot $book] operation $operation inputs $inputs options $options model $model]
    if {[string bytelength $request]>8388608} {error {Worksheet operation exceeds bounded 8 MiB Job request}}
    set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $request]]
    set code "# Managed Worksheet adapter; CORE Script Jobs owns worker/progress/cancel/recovery.\nfrom gxtxt import gxtxt_api_call\nprint('GXTXT_WORKSHEET_RESULT:' + gxtxt_api_call('SCIENTIFIC_WORKSHEET_API_v1', 'capture_operation', \['$encoded'\]), flush=True)\n"
    set scriptId "worksheet_operation_[clock clicks]"
    ::GX::scriptRegistrySave session $scriptId "Worksheet $operation" $code [dict create language Python required_apis SCIENTIFIC_WORKSHEET_API_v1]
    set job [::GX::scriptJobSubmit session:$scriptId {}]
    return [dict create format scientific_worksheet.operation_ticket.v1 job_id [dict get $job id] identity [bookIdentity $book] source_snapshot [historySnapshot $book] workbook_uuid [dict get $book workbook_uuid] operation $operation inputs $inputs options $options model $model]
}
proc ::GX::ScientificWorksheet::operationJobStatus {ticket} {return [::GX::scriptJobDescribe [dict get $ticket job_id]]}
proc ::GX::ScientificWorksheet::operationJobCancel {ticket} {return [::GX::scriptJobCancel [dict get $ticket job_id]]}
proc ::GX::ScientificWorksheet::operationJobResult {book ticket} {
    validateBook $book
    if {[dict get $ticket identity] ne [bookIdentity $book] || [dict get $ticket workbook_uuid] ne [dict get $book workbook_uuid]} {error {Worksheet or Session changed; completed result is retained in Jobs and cannot overwrite this Workbook}}
    set state [operationJobStatus $ticket]
    if {[dict get $state state] ne "COMPLETED"} {error "Worksheet scientific Job is [dict get $state state]; inspect its real Job log"}
    set text {};set offset 0
    while {1} {
        set chunk [::GX::scriptJobLogRead [dict get $ticket job_id] $offset 65536]
        if {![dict get $chunk available]} {error [dict get $chunk diagnostic]}
        append text [dict get $chunk content];if {[string bytelength $text]>12582912} {error {Worksheet Job log exceeds bounded capture size}}
        if {[dict get $chunk eof]} break
        set offset [dict get $chunk next_offset]
    }
    if {![regexp -line {^GXTXT_WORKSHEET_RESULT:([A-Za-z0-9+/=]+)$} $text unused encoded]} {error {Completed Job has no valid Worksheet capture receipt; inspect its retained log}}
    set raw [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    if {[catch {dict get $raw values}] || ![dict exists $raw types]} {error {Job result is not a captured typed scientific result}}
    return $raw
}
proc ::GX::ScientificWorksheet::operationJobCollect {book ticket destination field {outputWindow {}}} {
    set raw [operationJobResult $book $ticket]
    return [_applyCapturedOperation $book [dict get $ticket operation] [dict get $ticket inputs] [dict get $ticket options] $destination $field [dict get $ticket model] $raw $outputWindow]
}
proc ::GX::ScientificWorksheet::fillRange {book source targetEnd} {
    validateBook $book;set source [_cell $source];set targetEnd [_cell $targetEnd]
    set clip [clipboardCapture $book $source $source]
    if {![dict exists $clip cells $source]} {error {Source cell is empty}}
    set cell [dict get $clip cells $source];lassign [_parts $source] c0 r0;set pending {}
    foreach address [rangeCells $source $targetEnd] {
        if {$address eq $source} continue
        lassign [_parts $address] c r;set copy $cell
        if {[dict get $copy kind] eq "formula"} {dict set copy source [shiftFormula [dict get $copy source] [expr {$c-$c0}] [expr {$r-$r0}]]}
        dict set pending $address $copy
    }
    _reserveBeforeEdit $book $source $targetEnd
    variable spill;set key [_key $book]
    dict for {address cell} $pending {if {[dict exists $spill $key $address]} {error "#SPILL! Fill overlaps spilled output at $address"}}
    dict for {address cell} $pending {dict set book cells $address $cell}
    dict incr book revision;set affected [_invalidate $book [dict keys $pending]];set book [_staleOperations $book $affected];if {[dict get $book options calculation_mode] eq "automatic"} {_dropBookCache $book};return $book
}
proc ::GX::ScientificWorksheet::viewportRows {book rowIds firstColumn columnCount} {
    validateBook $book
    if {![string is entier -strict $firstColumn] || ![string is entier -strict $columnCount] || $firstColumn<1 || $columnCount<1 || $firstColumn+$columnCount-1>702 || [llength $rowIds]*$columnCount>4096} {error {Viewport exceeds Worksheet bounds or 4096-cell request limit}}
    foreach r $rowIds {if {![string is entier -strict $r] || $r<1 || $r>1000000} {error {Viewport row is outside 1–1000000}}}
    _ensureCalculationSnapshot $book
    # Discover potential spill producers once for this bounded read. Repeating
    # the full sparse scan for every blank viewport cell defeats virtual access.
    if {[llength $rowIds]} {
        set maxRow [lindex [lsort -integer $rowIds] end];set lastColumn [expr {$firstColumn+$columnCount-1}]
        dict for {anchor data} [dict get $book cells] {
            if {[dict get $data kind] ni {formula vector matrix}} continue
            lassign [_parts $anchor] c r
            if {$c<=$lastColumn && $r<=$maxRow} {foreach visibleRow $rowIds {if {$visibleRow>=$r && $visibleRow-$r<=20000} {catch {_evalCell $book $anchor {}};break}}}
        }
    }
    set cells {};foreach r $rowIds {for {set c $firstColumn} {$c<$firstColumn+$columnCount} {incr c} {
        set address "[_columnName $c]$r";set record [dict create address $address text {} kind blank unit {} error {}]
        if {[catch {set item [_evalCell $book $address {} 1]} message]} {dict set record kind error;dict set record error $message;dict set record text $message} else {
            foreach field {kind unit} {dict set record $field [dict get $item $field]}
            set text [dict get $item value];if {[dict get $item kind] eq "missing"} {set text {Missing}};if {[dict get $item kind] eq "nan"} {set text NaN}
            if {[dict exists $item operation_status] && [dict get $item operation_status] eq "stale"} {set text "Stale: $text";dict set record operation_status stale}
            set style [styleAt $book $address]
            if {$style ne {}} {set text [formatValue $item $style];dict set record style $style}
            set merge [mergeAt $book $address]
            if {$merge ne {}} {
                dict set record merge $merge
                set anchor [dict get $merge anchor];set anchorItem [_evalCell $book $anchor {} 1]
                set anchorStyle [styleAt $book $anchor]
                dict set record style $anchorStyle;set text [formatValue $anchorItem $anchorStyle]
            }
            dict set record text [string range $text 0 511]
        };dict set cells [list $r $c] $record
    }}
    return [dict create identity [bookIdentity $book] row_limit 1000000 column_limit 702 cells $cells]
}
proc ::GX::ScientificWorksheet::operationJobRecover {book ticket} {
    validateBook $book
    set job [operationJobStatus $ticket]
    if {[file normalize [dict get $job session]] ne [file normalize [_requireSession]] || [dict get $ticket workbook_uuid] ne [dict get $book workbook_uuid] || [dict get $ticket identity document_id] ne [dict get $book document_id] || [dict get $ticket identity owner_generation] ne [dict get $book _runtime owner_generation] || [dict get $ticket source_snapshot] ne [historySnapshot $book]} {error {Retained Job belongs to another Session, document generation or scientific Workbook state}}
    dict set ticket identity [bookIdentity $book]
    return $ticket
}
proc ::GX::ScientificWorksheet::_staleOperations {book affected {editedAddress {}}} {
    set book [_flush $book];set active [dict get $book active_sheet]
    dict for {sheet data} [dict get $book sheets] {
        set selected [_loadSheet $book $sheet]
        dict for {destination operation} [dict get $data operations] {
            set stale 0
            foreach input [concat [dict get $operation inputs] [dict values [dict get $operation options]]] {
                if {[catch {_dependencies $selected $input} refs]} {set stale 1;break}
                foreach ref $refs {if {$ref in $affected} {set stale 1;break}}
                if {$stale} break
            }
            if {$sheet eq $active && $editedAddress ne {}} {
                lassign [_parts $destination] c0 r0;lassign [_parts $editedAddress] c r
                if {$c >= $c0 && $c<$c0+[dict get $operation columns] && $r >= $r0 && $r<$r0+[dict get $operation rows]} {set stale 1}
            }
            if {$stale} {dict set book sheets $sheet operations $destination status stale;dict set book sheets $sheet operations $destination stale_reason {Scientific input or captured output changed; refresh or explicitly unlink}}
        }
    }
    return [_loadSheet $book $active]
}

proc ::GX::ScientificWorksheet::_historyExpand {snapshot} {
    set reference [dict get $snapshot history_resource]
    if {[dict get $reference metadata format] ne "scientific_worksheet.snapshot.v2" || [dict get $reference size_bytes]>67108864} {error {Invalid bounded Worksheet History resource}}
    set reader [::GX::interactiveDocumentResourceOpenReader $reference];set bytes {}
    try {while {1} {set chunk [::GX::interactiveDocumentResourceNext $reader];append bytes [dict get $chunk bytes];if {[dict get $chunk eof]} break}} finally {::GX::interactiveDocumentResourceCloseReader $reader}
    set state [encoding convertfrom utf-8 $bytes]
    if {[catch {dict size $state}] || [dict get $state workbook_uuid] ne [dict get $snapshot workbook_uuid]} {error {History resource belongs to another Workbook}}
    set dependencies [dict get $reference metadata dependencies]
    if {[llength $dependencies]} {set state [::GX::interactiveDocumentResourceRemapReferences $state $dependencies]}
    return $state
}

proc ::GX::ScientificWorksheet::_remapChartSources {book axis position count deleting} {
    if {![dict exists $book charts]} {return $book}
    set active [dict get $book active_sheet]
    dict for {id chart} [dict get $book charts] {
        if {![dict exists $chart sheet] || [dict get $chart sheet] ne $active} continue
        if {$axis eq "column"} {
            foreach field {x_column y_columns} {
                if {![dict exists $chart $field]} continue
                set columns {};foreach column [dict get $chart $field] {
                    set c [_columnNumber $column]
                    if {$c >= $position} {
                        if {$deleting && $c<$position+$count} {error "Column is a live source of chart $id; rebind or remove the chart before deleting it"}
                        incr c [expr {$deleting?-$count:$count}]
                    }
                    lappend columns [_columnName $c]
                };dict set chart $field $columns
            }
        } elseif {[dict exists $chart first] && [dict exists $chart last]} {
            set first [dict get $chart first];set last [dict get $chart last]
            if {$deleting} {
                if {$first >= $position && $first<$position+$count} {set first [expr {$position+$count}]}
                if {$last >= $position && $last<$position+$count} {set last [expr {$position-1}]}
                if {$last<$first} {error "Deletion would remove every source row of chart $id; rebind or remove the chart first"}
                if {$first >= $position+$count} {incr first -$count};if {$last >= $position+$count} {incr last -$count}
            } else {
                if {$position<=$first} {incr first $count};if {$position<=$last} {incr last $count}
            }
            _rowBounds $first $last;dict set chart first $first;dict set chart last $last
        }
        dict set book charts $id $chart
    }
    return $book
}
proc ::GX::ScientificWorksheet::_reconcileColumnUnits {book columns} {
    foreach column [lsort -unique $columns] {
        set number [_columnNumber $column];set units {}
        dict for {address cell} [dict get $book cells] {
            lassign [_parts $address] c r
            if {$c!=$number || [dict get $cell kind] in {text boolean missing}} continue
            dict set units [dict get $cell unit] 1
        }
        if {[dict size $units]==1} {
            dict set book column_metadata $column unit [lindex [dict keys $units] 0]
            dict set book column_metadata $column unit_state homogeneous
        } elseif {[dict size $units]>1} {
            dict set book column_metadata $column unit {}
            dict set book column_metadata $column unit_state mixed
            dict set book column_metadata $column actual_units [dict keys $units]
        }
    }
    return $book
}
proc ::GX::ScientificWorksheet::chartValidate {book descriptor} {
    validateBook $book
    foreach field {sheet x_column y_columns first last kind} {if {![dict exists $descriptor $field]} {error "Chart source descriptor requires $field"}}
    set selected [_activate $book [dict get $descriptor sheet]]
    _rowBounds [dict get $descriptor first] [dict get $descriptor last]
    set x [string toupper [dict get $descriptor x_column]];_columnNumber $x;dict set descriptor x_column $x
    if {![llength [dict get $descriptor y_columns]]} {error {Chart requires at least one explicit Y column}}
    foreach field {y_columns right_columns} {
        if {![dict exists $descriptor $field]} continue
        set columns {};foreach column [dict get $descriptor $field] {set column [string toupper $column];_columnNumber $column;lappend columns $column};dict set descriptor $field $columns
    }
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set info [::GX::PlotDatasetAPIv4::apiInfo]
    if {[dict get $descriptor kind] ni [dict get $info supported_2d_kinds]} {error {Chart kind is not supported by the registered public native Plot v4 authority}}
    foreach field {style axes} {if {[dict exists $descriptor $field] && [catch {dict size [dict get $descriptor $field]}]} {error "Chart $field must be a dictionary"}}
    if {[dict exists $descriptor geometry]} {
        if {[llength [dict get $descriptor geometry]]!=4} {error {Chart geometry requires x y width height}}
        lassign [dict get $descriptor geometry] x y width height
        foreach v [list $x $y $width $height] {if {![string is double -strict $v] || ![expr {abs(double($v))<Inf}]} {error {Chart geometry must be finite}}}
        if {$x<0 || $y<0 || $x>1 || $y>1 || $width<=0 || $height<=0 || $width>16 || $height>16} {error {Chart geometry exceeds its bounded normalized presentation area}}
    }
    return $descriptor
}
proc ::GX::ScientificWorksheet::chartAdd {book descriptor} {
    set book [_upgrade $book];validateBook $book
    set n 1;set id chart_1;while {[dict exists $book charts $id]} {set id chart_[incr n]}
    if {[dict exists $descriptor id]} {set id [dict get $descriptor id]}
    if {![regexp {^chart_[A-Za-z0-9_]+$} $id] || [dict exists $book charts $id]} {error {Chart ID is invalid or already exists}}
    set defaults [dict create id $id sheet [dict get $book active_sheet] x_column A y_columns B right_columns {} first 1 last 2 kind line title "Chart $n" style {line_width 1.5 marker none} axes {x {scale linear} y_left {scale linear}} legend inside annotations {} annotation {} panels overlay geometry {0.03 0.03 0.9 0.9} revision 1]
    set descriptor [chartValidate $book [dict merge $defaults $descriptor]];dict set descriptor id $id;dict set descriptor revision 1
    dict set book charts $id $descriptor;dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::chartUpdate {book id descriptor} {
    validateBook $book
    if {![dict exists $book charts $id]} {error {Chart does not exist}}
    if {[dict exists $descriptor id] && [dict get $descriptor id] ne $id} {error {A scientific chart identity cannot be changed by presentation editing}}
    set descriptor [chartValidate $book [dict merge [dict get $book charts $id] $descriptor]]
    dict set descriptor id $id;dict set descriptor revision [expr {[dict get $book charts $id revision]+1}]
    dict set book charts $id $descriptor;dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::chartRemove {book id} {validateBook $book;if {![dict exists $book charts $id]} {error {Chart does not exist}};dict unset book charts $id;dict incr book revision;return $book}
proc ::GX::ScientificWorksheet::scientificComparison {book} {
    # Value-only comparison, no resource write. View selection/viewport and
    # Workspace/History control metadata are not scientific semantic edits.
    return [dict remove [snapshot $book] history workspace_metadata managed_operation_tickets active_sheet presentation]
}
