# SPDX-License-Identifier: GPL-3.0-or-later
# Sparse Workbook presentation; values, formula evaluation and source identities
# remain in the existing Worksheet model. Native2D owns all device geometry.
proc ::GX::ScientificWorksheet::rectangle {first last} {
    lassign [_parts $first] c1 r1;lassign [_parts $last] c2 r2
    return [list [expr {min($c1,$c2)}] [expr {min($r1,$r2)}] [expr {max($c1,$c2)}] [expr {max($r1,$r2)}]]
}
proc ::GX::ScientificWorksheet::mergeAt {book address} {
    lassign [_parts $address] c r
    dict for {anchor bounds} [::GX::datasetPublicationV2DictDefault $book merges {}] {
        lassign $bounds c1 r1 c2 r2
        if {$c>=$c1 && $c<=$c2 && $r>=$r1 && $r<=$r2} {return [dict create anchor $anchor bounds $bounds]}
    }
    return {}
}
proc ::GX::ScientificWorksheet::mergeRange {book first last {unmerge 0}} {
    validateBook $book;set bounds [rectangle $first $last];lassign $bounds c1 r1 c2 r2
    set anchor "[_columnName $c1]$r1";set end "[_columnName $c2]$r2"
    set cells [rangeCells $anchor $end]
    set merges [::GX::datasetPublicationV2DictDefault $book merges {}]
    dict for {other rect} $merges {
        lassign $rect a b c d
        if {$a>$c2 || $c<$c1 || $b>$r2 || $d<$r1} continue
        if {!$unmerge && $rect eq $bounds} {return $book}
        if {!$unmerge || $a<$c1 || $b<$r1 || $c>$c2 || $d>$r2} {error {Selection partially overlaps a merge. Unmerge the complete span first.}}
        dict unset merges $other
    }
    if {!$unmerge} {
        if {$anchor eq $end} {return $book}
        _reserveBeforeEdit $book $anchor $end
        variable spill;set key [_key $book]
        foreach address $cells {
            if {[dict exists $spill $key $address] || [dict exists $book operations $address]} {error {Merge overlaps a live scientific spill/operation}}
            # Refusal avoids hiding measurements, formulas or source provenance.
            if {$address ne $anchor && [dict exists $book cells $address] && [dict get $book cells $address source] ne {}} {error "Merge would hide nonempty cell $address. Move its data explicitly first."}
        }
        dict set merges $anchor $bounds
    }
    dict set book merges $merges;dict incr book revision
    return $book
}
proc ::GX::ScientificWorksheet::styleValidate {style} {
    set result {}
    dict for {key value} $style {
        switch $key {
            align {if {$value ni {general left center right}} {error {Invalid horizontal alignment}}}
            valign {if {$value ni {top middle bottom}} {error {Invalid vertical alignment}}}
            wrap - bold - italic - underline - grouping {set value [::GX::uiFieldNormalize {type boolean} $value]}
            foreground - background - border_color {set value [::GX::uiFieldColor $value]}
            font_family {if {[string length $value]>128 || [regexp {[\r\n]} $value]} {error {Invalid font family}}}
            font_size {set value [::GX::uiFieldNormalize {type integer min 6 max 72} $value]}
            rotation {set value [::GX::uiFieldNormalize {type number min -90 max 90} $value]}
            border_width {set value [::GX::uiFieldNormalize {type number min 0 max 12} $value]}
            border_style {if {$value ni {solid dashed dotted}} {error {Invalid border style}}}
            border_edges {foreach edge $value {if {$edge ni {top bottom left right}} {error {Invalid border edge}}}}
            category {if {$value ni {General Number Scientific Engineering Percentage Date Time Text Custom}} {error {Invalid display category}}}
            decimals {set value [::GX::uiFieldNormalize {type integer min 0 max 17} $value]}
            custom {if {$value ni {0 0.0 0.00 0.000 0.00E+00 0% 0.00%}} {error {Supported custom formats: 0, 0.0, 0.00, 0.000, 0.00E+00, 0%, 0.00%}}}
            default {error "Unknown cell style '$key'"}
        }
        dict set result $key $value
    }
    return $result
}
proc ::GX::ScientificWorksheet::_presentationBoundsValidate {bounds} {
    if {[llength $bounds]!=4} {error {A presentation range requires four bounds}}
    lassign $bounds c1 r1 c2 r2
    foreach value [list $c1 $c2] {::GX::uiFieldNormalize {type integer min 1 max 702} $value}
    foreach value [list $r1 $r2] {::GX::uiFieldNormalize {type integer min 1 max 1000000} $value}
    if {$c2<$c1 || $r2<$r1} {error {Invalid presentation range order}}
}
proc ::GX::ScientificWorksheet::_rangeStyleAt {style borders bounds c r} {
    if {$borders eq {}} {return $style}
    lassign $bounds c1 r1 c2 r2;set edges {}
    foreach {edge condition} [list top [expr {$r==$r1}] bottom [expr {$r==$r2}] left [expr {$c==$c1}] right [expr {$c==$c2}]] {
        if {$borders eq "all" || ($borders eq "outer" && $condition) || ($borders eq "inner" && !$condition) || $borders eq $edge} {lappend edges $edge}
    }
    dict set style border_edges $edges;return $style
}
proc ::GX::ScientificWorksheet::styleAt {book address} {
    lassign [_parts $address] c r;set result {}
    foreach layer [::GX::datasetPublicationV2DictDefault $book range_styles {}] {
        lassign [dict get $layer bounds] c1 r1 c2 r2
        if {$c>=$c1 && $c<=$c2 && $r>=$r1 && $r<=$r2} {set result [dict merge $result [_rangeStyleAt [dict get $layer style] [dict get $layer borders] [dict get $layer bounds] $c $r]]}
    }
    return [dict merge $result [::GX::datasetPublicationV2DictDefault [dict get $book styles] $address {}]]
}
proc ::GX::ScientificWorksheet::formatRange {book first last style {borders {}}} {
    validateBook $book;set style [styleValidate $style];set bounds [rectangle $first $last];lassign $bounds c1 r1 c2 r2
    if {$borders ni {{} all outer inner top bottom left right none}} {error {Invalid border application}}
    if {($c2-$c1+1)*($r2-$r1+1)>20000} {
        set patchStyle $style
        set layers [dict get $book range_styles]
        # Equal ranges coalesce; full-column presentation never allocates cells.
        set kept $layers
        if {[llength $kept]} {
            set lastLayer [lindex $kept end]
            if {[dict get $lastLayer bounds] eq $bounds && [dict get $lastLayer borders] eq $borders} {set style [dict merge [dict get $lastLayer style] $style];set kept [lrange $kept 0 end-1]}
        }
        if {[llength $kept]>=2048} {error {Workbook has 2048 range styles. Consolidate presentation ranges first.}}
        lappend kept [dict create bounds $bounds style $style borders $borders];dict set book range_styles $kept
        dict for {address prior} [dict get $book styles] {
            lassign [_parts $address] c r
            if {$c>=$c1 && $c<=$c2 && $r>=$r1 && $r<=$r2} {dict set book styles $address [dict merge $prior [_rangeStyleAt $patchStyle $borders $bounds $c $r]]}
        }
    } else {
        foreach address [rangeCells "[_columnName $c1]$r1" "[_columnName $c2]$r2"] {
            lassign [_parts $address] c r
            dict set book styles $address [dict merge [styleAt $book $address] [_rangeStyleAt $style $borders $bounds $c $r]]
        }
    }
    dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::formatValue {item style} {
    set value [dict get $item value];set kind [dict get $item kind]
    if {$kind ni {scalar dataset manual number} || ![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {return $value}
    set category [::GX::datasetPublicationV2DictDefault $style category General]
    set decimals [::GX::datasetPublicationV2DictDefault $style decimals 2]
    if {$category eq "Custom"} {
        set custom [::GX::datasetPublicationV2DictDefault $style custom 0.00]
        if {[string match *% $custom]} {set category Percentage;set decimals [expr {$custom eq "0%"?0:2}]
        } elseif {$custom eq "0.00E+00"} {set category Scientific;set decimals 2
        } else {set category Number;set decimals [expr {max(0,[string length $custom]-2)}]}
    }
    switch $category {
        Number {set value [format %.*f $decimals $value]}
        Scientific {set value [format %.*e $decimals $value]}
        Engineering {set exponent [expr {$value==0?0:int(floor(log10(abs($value))/3))*3}];set value "[format %.*f $decimals [expr {$value/pow(10,$exponent)}]]e[format %+03d $exponent]"}
        Percentage {set value "[format %.*f $decimals [expr {$value*100.}]]%"}
        Date - Time {
            # Explicit Unix UTC epoch representation; never infer Excel serials.
            if {[dict get $item unit] ni {s {}}} {error {Date/Time display requires explicit Unix seconds (unit s or dimensionless)}}
            set value [clock format [expr {wide(floor($value))}] -gmt 1 -format [expr {$category eq "Date"?"%Y-%m-%d":"%H:%M:%S"}]]
        }
    }
    if {$category eq "Number" && [::GX::datasetPublicationV2DictDefault $style grouping 0]} {
        lassign [split $value .] whole fraction;set sign {};if {[string index $whole 0] eq "-"} {set sign -;set whole [string range $whole 1 end]}
        set groups {};while {[string length $whole]>3} {set groups ",[string range $whole end-2 end]$groups";set whole [string range $whole 0 end-3]}
        set value "$sign$whole$groups";if {$decimals} {append value .$fraction}
    }
    return $value
}
proc ::GX::ScientificWorksheet::setSizes {book axis first last pixels} {
    validateBook $book
    if {$axis ni {row column}} {error {Sizing axis must be row or column}}
    set max [expr {$axis eq "row"?1000000:702}];set min [expr {$axis eq "row"?16:35}]
    foreach n [list $first $last] {::GX::uiFieldNormalize [dict create type integer min 1 max $max] $n}
    set pixels [::GX::uiFieldNormalize [dict create type integer min $min max 2000] $pixels]
    if {$last<$first || $last-$first>20000} {error {Sizing range exceeds 20000 rows/columns}}
    set key [expr {$axis eq "row"?"row_heights":"column_widths"}]
    for {set i $first} {$i<=$last} {incr i} {dict set book $key $i $pixels}
    dict incr book revision;return $book
}
proc ::GX::ScientificWorksheet::navigationExtent {book {address A1}} {
    validateBook $book;lassign [_parts $address] c r;set maxC [expr {max(12,$c+4)}];set maxR [expr {max(50,$r+20)}]
    foreach key {cells styles} {foreach address [dict keys [::GX::datasetPublicationV2DictDefault $book $key {}]] {lassign [_parts $address] c r;set maxC [expr {max($maxC,$c+4)}];set maxR [expr {max($maxR,$r+20)}]}}
    foreach key {hidden_rows filter_hidden_rows row_heights} {foreach row [dict keys [dict get $book $key]] {set maxR [expr {max($maxR,$row+20)}]}}
    dict for {anchor bounds} [dict get $book merges] {set maxC [expr {max($maxC,[lindex $bounds 2]+4)}];set maxR [expr {max($maxR,[lindex $bounds 3]+20)}]}
    return [dict create rows [expr {min(1000000,$maxR)}] columns [expr {min(702,$maxC)}]]
}
proc ::GX::ScientificWorksheet::fillRange {book source targetEnd {sourceEnd {}} {mode auto}} {
    validateBook $book
    if {$sourceEnd eq {}} {set sourceEnd $source}
    if {$mode ni {auto copy series}} {error {Fill mode must be auto, copy or series}}
    lassign [rectangle $source $sourceEnd] c1 r1 c2 r2
    lassign [_parts $targetEnd] tc tr
    set first "[_columnName [expr {min($c1,$tc)}]][expr {min($r1,$tr)}]";set last "[_columnName [expr {max($c2,$tc)}]][expr {max($r2,$tr)}]"
    set destinations [rangeCells $first $last];_reserveBeforeEdit $book $first $last
    set clip [clipboardCapture $book "[_columnName $c1]$r1" "[_columnName $c2]$r2"]
    set vertical [expr {$c1==$c2 && $r2>$r1 && $tc==$c1}];set horizontal [expr {$r1==$r2 && $c2>$c1 && $tr==$r1}]
    set values {};set prefix {};set numeric 1;set unit {};set series 0
    if {$mode ne "copy" && ($vertical || $horizontal)} {
        foreach address [rangeCells "[_columnName $c1]$r1" "[_columnName $c2]$r2"] {
            set item [value $book $address];set raw [dict get $item value]
            if {[dict get $item kind] eq "text" && [regexp {^(.*?)(-?[0-9]+)$} $raw -> pre suffix]} {
                if {$values eq {}} {set prefix $pre};if {$prefix ne $pre} {set numeric 0;break};set raw $suffix
            }
            if {[dict exists $book cells $address] && [dict get $book cells $address kind] eq "formula"} {set numeric 0;break}
            if {![string is double -strict $raw] || [catch {expr {abs(double($raw))<Inf}} finite] || !$finite || ($values ne {} && [dict get $item unit] ne $unit)} {set numeric 0;break}
            set unit [dict get $item unit];lappend values $raw
        }
        if {$numeric && [llength $values]>=2} {
            set step [expr {[lindex $values 1]-[lindex $values 0]}];set series 1
            for {set i 2} {$i<[llength $values]} {incr i} {if {abs([lindex $values $i]-[lindex $values 0]-$i*$step)>1e-12*max(1,abs([lindex $values $i]))} {set series 0;break}}
        }
    }
    if {$mode eq "series" && !$series} {error {Fill Series requires consistent numerical or numbered-text seeds}}
    variable spill;set key [_key $book];set pending {};set styles [dict get $book styles]
    foreach address $destinations {
        lassign [_parts $address] c r
        if {$c>=$c1 && $c<=$c2 && $r>=$r1 && $r<=$r2} continue
        if {[dict exists $spill $key $address]} {error "#SPILL! Fill overlaps $address"}
        set sc [expr {$c1+(($c-$c1)%($c2-$c1+1)+($c2-$c1+1))%($c2-$c1+1)}]
        set sr [expr {$r1+(($r-$r1)%($r2-$r1+1)+($r2-$r1+1))%($r2-$r1+1)}]
        set from "[_columnName $sc]$sr"
        if {![dict exists $clip cells $from]} {dict set pending $address {};continue}
        set cell [dict get $clip cells $from]
        if {$series} {
            set offset [expr {$vertical?$r-$r1:$c-$c1}];set generated [expr {[lindex $values 0]+$offset*$step}]
            set cell [dict create source $generated kind manual unit $unit]
            if {$prefix ne {}} {dict set cell source "$prefix$generated";dict set cell kind text}
        } elseif {[dict get $cell kind] eq "formula"} {dict set cell source [shiftFormula [dict get $cell source] [expr {$c-$sc}] [expr {$r-$sr}]]}
        if {[dict exists $cell lineage]} {dict set cell lineage [dict create transform worksheet_fill source_cell $from original_lineage [dict get $cell lineage]]}
        dict set pending $address $cell
        if {[dict exists $styles $from]} {dict set book styles $address [dict get $styles $from]}
    }
    dict for {address cell} $pending {if {$cell eq {}} {if {[dict exists $book cells $address]} {dict unset book cells $address}} else {dict set book cells $address $cell}}
    dict incr book revision;set affected [_invalidate $book [dict keys $pending]];set book [_staleOperations $book $affected];_dropBookCache $book
    return $book
}

proc ::GX::ScientificWorksheet::_presentationShiftInterval {first last position count deleting} {
    if {!$deleting} {if {$first>=$position} {incr first $count};if {$last>=$position} {incr last $count};return [list $first $last]}
    set end [expr {$position+$count-1}]
    if {$first>=$position && $last<=$end} {return {}}
    if {$first>=$position} {set first [expr {max($first,$end+1)-$count}]}
    if {$last>$end} {incr last -$count} elseif {$last>=$position} {set last [expr {$position-1}]}
    return [list $first $last]
}
proc ::GX::ScientificWorksheet::_presentationShiftAddress {address axis position count deleting} {
    lassign [_parts $address] c r;set n [expr {$axis eq "row"?$r:$c}]
    set result [_presentationShiftInterval $n $n $position $count $deleting]
    if {$result eq {}} {return {}}
    set n [lindex $result 0]
    if {$axis eq "row"} {set r $n} else {set c $n}
    return [_cell "[_columnName $c]$r"]
}
