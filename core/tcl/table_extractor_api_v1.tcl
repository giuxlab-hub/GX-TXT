# GX-TXT Table Extraction Service API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# CORE-owned, versioned table extraction API. Loaded at framework startup.

namespace eval ::GX::TableExtractorAPIv1 {
    variable apiVersion 1
    variable supportedCapabilities {
        layout_input dataset_input image_input pdf_input normalized_geometry
        row_clustering column_inference table_reconstruction matrix_export csv_export
        schema_inference
    }
}

proc ::GX::TableExtractorAPIv1::_error {message} {
    return -code error "table.extractor API v1: $message"
}

proc ::GX::TableExtractorAPIv1::capabilities {} {
    variable supportedCapabilities
    return $supportedCapabilities
}

proc ::GX::TableExtractorAPIv1::supports {capability} {
    expr {[lsearch -exact [capabilities] $capability] >= 0}
}

proc ::GX::TableExtractorAPIv1::_ocr {} {
    foreach cmd {extractImage extractPdfPage filterRoi} {
        if {![llength [info commands ::GX::OCRLayoutAPIv1::$cmd]]} { _error "OCR_LAYOUT_API_v1 command '$cmd' is unavailable" }
    }
    return ::GX::OCRLayoutAPIv1
}

proc ::GX::TableExtractorAPIv1::apiInfo {} {
    variable apiVersion
    set ocr [_ocr]
    return [dict create \
        api_name TABLE_EXTRACTOR_API_v1 \
        api_version $apiVersion \
        owner CORE \
        capabilities [capabilities] \
        ocr_layout_api [${ocr}::apiInfo]]
}

proc ::GX::TableExtractorAPIv1::_dictOptions {options} {
    if {$options eq ""} { return [dict create] }
    if {[catch {dict size $options}]} { _error "options must be a Tcl dict" }
    return $options
}

proc ::GX::TableExtractorAPIv1::_option {options key default} {
    expr {[dict exists $options $key] ? [dict get $options $key] : $default}
}

proc ::GX::TableExtractorAPIv1::_median {values} {
    if {![llength $values]} { return 0.0 }
    set v [lsort -real $values]
    set n [llength $v]
    set m [expr {$n / 2}]
    if {$n % 2} { return [expr {double([lindex $v $m])}] }
    return [expr {(double([lindex $v [expr {$m-1}]]) + double([lindex $v $m])) / 2.0}]
}

proc ::GX::TableExtractorAPIv1::_mean {values} {
    if {![llength $values]} { return 0.0 }
    set sum 0.0
    foreach v $values { set sum [expr {$sum + double($v)}] }
    return [expr {$sum / double([llength $values])}]
}

proc ::GX::TableExtractorAPIv1::_compareWordYX {a b} {
    set ay [dict get $a cy_norm]; set by [dict get $b cy_norm]
    if {$ay < $by} { return -1 }
    if {$ay > $by} { return 1 }
    set ax [dict get $a x_norm]; set bx [dict get $b x_norm]
    if {$ax < $bx} { return -1 }
    if {$ax > $bx} { return 1 }
    return 0
}

proc ::GX::TableExtractorAPIv1::_compareWordX {a b} {
    set ax [dict get $a x_norm]; set bx [dict get $b x_norm]
    if {$ax < $bx} { return -1 }
    if {$ax > $bx} { return 1 }
    return 0
}

proc ::GX::TableExtractorAPIv1::_bboxWords {words} {
    if {![llength $words]} { return {} }
    set x1 1.0; set y1 1.0; set x2 0.0; set y2 0.0
    foreach w $words {
        set wx1 [dict get $w x_norm]
        set wy1 [dict get $w y_norm]
        set wx2 [expr {$wx1 + [dict get $w width_norm]}]
        set wy2 [expr {$wy1 + [dict get $w height_norm]}]
        if {$wx1 < $x1} { set x1 $wx1 }
        if {$wy1 < $y1} { set y1 $wy1 }
        if {$wx2 > $x2} { set x2 $wx2 }
        if {$wy2 > $y2} { set y2 $wy2 }
    }
    return [list $x1 $y1 $x2 $y2]
}

proc ::GX::TableExtractorAPIv1::_wordConfidence {w} {
    if {![dict exists $w confidence] || ![string is double -strict [dict get $w confidence]]} { return -1.0 }
    return [expr {double([dict get $w confidence])}]
}

proc ::GX::TableExtractorAPIv1::_clusterRows {words} {
    set words [lsort -command ::GX::TableExtractorAPIv1::_compareWordYX $words]
    if {![llength $words]} { return {} }
    set heights {}
    foreach w $words { lappend heights [expr {max(0.0001, double([dict get $w height_norm]))}] }
    set tolerance [expr {max(0.003, [_median $heights] * 0.65)}]
    set rows {}
    set centers {}
    foreach word $words {
        set cy [dict get $word cy_norm]
        set best -1; set bestDistance 2.0
        for {set i 0} {$i < [llength $centers]} {incr i} {
            set distance [expr {abs($cy - [lindex $centers $i])}]
            if {$distance <= $tolerance && $distance < $bestDistance} { set best $i; set bestDistance $distance }
        }
        if {$best < 0} {
            lappend rows [list $word]
            lappend centers $cy
        } else {
            set row [lindex $rows $best]
            lappend row $word
            lset rows $best $row
            set ys {}
            foreach rw $row { lappend ys [dict get $rw cy_norm] }
            lset centers $best [_median $ys]
        }
    }
    set sortable {}
    for {set i 0} {$i < [llength $rows]} {incr i} { lappend sortable [list [lindex $centers $i] $i] }
    set out {}
    foreach item [lsort -real -index 0 $sortable] {
        lappend out [lsort -command ::GX::TableExtractorAPIv1::_compareWordX [lindex $rows [lindex $item 1]]]
    }
    return $out
}

proc ::GX::TableExtractorAPIv1::_candidateBoundaries {rows} {
    if {![llength $rows]} { return {} }
    set heights {}
    foreach row $rows { foreach w $row { lappend heights [expr {max(0.0001, double([dict get $w height_norm]))}] } }
    set minGap [expr {max(0.006, [_median $heights] * 0.85)}]
    set candidates {}
    set ri 0
    foreach row $rows {
        for {set i 0} {$i < [expr {[llength $row]-1}]} {incr i} {
            set left [lindex $row $i]; set right [lindex $row [expr {$i+1}]]
            set left2 [expr {[dict get $left x_norm] + [dict get $left width_norm]}]
            set gap [expr {[dict get $right x_norm] - $left2}]
            if {$gap >= $minGap} { lappend candidates [list [expr {($left2 + [dict get $right x_norm]) / 2.0}] $gap $ri] }
        }
        incr ri
    }
    return $candidates
}

proc ::GX::TableExtractorAPIv1::_compareCandidatePos {a b} {
    set ax [lindex $a 0]; set bx [lindex $b 0]
    if {$ax < $bx} { return -1 }
    if {$ax > $bx} { return 1 }
    return 0
}

proc ::GX::TableExtractorAPIv1::_compareRankScore {a b} {
    set as [lindex $a 1]; set bs [lindex $b 1]
    if {$as > $bs} { return -1 }
    if {$as < $bs} { return 1 }
    return 0
}

proc ::GX::TableExtractorAPIv1::_inferBoundaries {rows expectedColumns} {
    set candidates [_candidateBoundaries $rows]
    if {![llength $candidates]} { return {} }
    set heights {}
    foreach row $rows { foreach w $row { lappend heights [expr {max(0.0001, double([dict get $w height_norm]))}] } }
    set tolerance [expr {max(0.008, [_median $heights] * 1.6)}]
    set groups {}
    foreach item [lsort -command ::GX::TableExtractorAPIv1::_compareCandidatePos $candidates] {
        if {![llength $groups]} { lappend groups [list $item]; continue }
        set last [lindex $groups end]
        set positions {}
        foreach e $last { lappend positions [lindex $e 0] }
        if {abs([lindex $item 0] - [_mean $positions]) > $tolerance} {
            lappend groups [list $item]
        } else {
            lappend last $item
            lset groups end $last
        }
    }
    set rowCount [expr {max(1,[llength $rows])}]
    set minSupport [expr {$rowCount <= 2 ? 1 : max(2, int(ceil($rowCount * 0.35)))}]
    set ranked {}
    foreach group $groups {
        set positions {}; set gaps {}; set seen [dict create]
        foreach e $group {
            lappend positions [lindex $e 0]
            lappend gaps [lindex $e 1]
            dict set seen [lindex $e 2] 1
        }
        set support [dict size $seen]
        if {$expectedColumns > 0 || $support >= $minSupport} {
            set pos [_median $positions]
            set score [expr {$support * 1000.0 + [_mean $gaps]}]
            lappend ranked [list $pos $score $support]
        }
    }
    if {$expectedColumns > 0} {
        set needed [expr {max(0,$expectedColumns-1)}]
        set ranked [lrange [lsort -command ::GX::TableExtractorAPIv1::_compareRankScore $ranked] 0 [expr {$needed-1}]]
    }
    set positions {}
    foreach item $ranked { lappend positions [lindex $item 0] }
    return [lsort -real $positions]
}

proc ::GX::TableExtractorAPIv1::_cellDict {rowIndex columnIndex words} {
    set words [lsort -command ::GX::TableExtractorAPIv1::_compareWordX $words]
    set tokens {}; set confidences {}
    foreach w $words {
        lappend tokens [dict get $w text]
        set c [_wordConfidence $w]
        if {$c >= 0} { lappend confidences $c }
    }
    return [dict create \
        row $rowIndex column $columnIndex \
        text [string trim [join $tokens " "]] \
        confidence [expr {[llength $confidences] ? [_mean $confidences] : -1.0}] \
        bbox_norm [_bboxWords $words] \
        words $words]
}

proc ::GX::TableExtractorAPIv1::_reconstruct {words expectedColumns} {
    set rows [_clusterRows $words]
    if {![llength $rows]} { return [dict create row_count 0 column_count 0 matrix {} rows {} boundaries_norm {} bbox_norm {} confidence -1] }
    set boundaries [_inferBoundaries $rows $expectedColumns]
    set colCount [expr {[llength $boundaries] + 1}]
    if {$expectedColumns > 0 && $colCount != $expectedColumns} {
        # With sparse rows there may be too few recurring gaps. Use the strongest
        # candidates already returned; never invent equal-width columns silently.
    }
    set matrix {}; set structuredRows {}; set allConf {}
    set ri 0
    foreach row $rows {
        set buckets {}
        for {set c 0} {$c < $colCount} {incr c} { lappend buckets {} }
        foreach word $row {
            set ci 0; set cx [dict get $word cx_norm]
            while {$ci < [llength $boundaries] && $cx > [lindex $boundaries $ci]} { incr ci }
            set bucket [lindex $buckets $ci]; lappend bucket $word; lset buckets $ci $bucket
            set conf [_wordConfidence $word]; if {$conf >= 0} { lappend allConf $conf }
        }
        set cells {}; set values {}
        for {set ci 0} {$ci < $colCount} {incr ci} {
            set cell [_cellDict $ri $ci [lindex $buckets $ci]]
            lappend cells $cell; lappend values [dict get $cell text]
        }
        set nonempty 0; foreach v $values { if {[string trim $v] ne ""} { set nonempty 1; break } }
        if {$nonempty} {
            lappend matrix $values
            lappend structuredRows [dict create row_index $ri bbox_norm [_bboxWords $row] cells $cells]
            incr ri
        }
    }
    return [dict create \
        row_count [llength $matrix] column_count $colCount matrix $matrix rows $structuredRows \
        boundaries_norm $boundaries bbox_norm [_bboxWords $words] \
        confidence [expr {[llength $allConf] ? [_mean $allConf] : -1.0}]]
}

# Many reports place several tables on one page with the same column header.
# Use repeated, predominantly textual header rows as anchors; each occurrence
# starts a separate table. Pages without repeated headers keep the old path.
proc ::GX::TableExtractorAPIv1::_splitRepeatedHeaders {words} {
    set rows [_clusterRows $words]
    if {[llength $rows] < 6} { return [list $words] }
    set signatures [dict create]
    set counts [dict create]
    for {set i 0} {$i < [llength $rows]} {incr i} {
        set row [lindex $rows $i]
        set tokens {}
        foreach w $row {
            set token [string tolower [string trim [dict get $w text]]]
            if {$token ne ""} { lappend tokens $token }
        }
        if {[llength $tokens] < 4} continue
        set numeric 0
        foreach token $tokens {
            if {[string is double -strict [string map {, .} $token]]} { incr numeric }
        }
        if {$numeric * 4 > [llength $tokens]} continue
        set signature [join $tokens " "]
        dict lappend signatures $signature $i
        dict set counts $signature [llength $tokens]
    }
    set best {} ; set bestScore 0
    dict for {signature positions} $signatures {
        if {[llength $positions] < 2} continue
        set score [expr {[llength $positions] * [dict get $counts $signature]}]
        if {$score > $bestScore} { set best $positions; set bestScore $score }
    }
    if {[llength $best] < 2} { return [list $words] }
    set starts {}
    foreach anchor $best {
        set start $anchor
        if {$anchor > 0} {
            set prior [lindex $rows [expr {$anchor - 1}]]
            set numeric 0
            foreach w $prior {
                if {[string is double -strict [string map {, .} [dict get $w text]]]} { incr numeric }
            }
            if {$numeric <= 2} { set start [expr {$anchor - 1}] }
        }
        lappend starts $start
    }
    set groups {}
    for {set i 0} {$i < [llength $starts]} {incr i} {
        set first [lindex $starts $i]
        set last [expr {$i + 1 < [llength $starts] ? [lindex $starts [expr {$i + 1}]] - 1 : [llength $rows] - 1}]
        set group {}
        foreach row [lrange $rows $first $last] { foreach w $row { lappend group $w } }
        if {[llength $group]} { lappend groups $group }
    }
    return [expr {[llength $groups] ? $groups : [list $words]}]
}

proc ::GX::TableExtractorAPIv1::extractLayout {layout {options {}}} {
    set options [_dictOptions $options]
    if {![dict exists $layout words]} { _error "layout does not contain positioned words" }
    set words [dict get $layout words]
    set expected [_option $options expected_columns 0]
    if {![string is integer -strict $expected] || $expected < 0} { _error "expected_columns must be zero or a positive integer" }
    if {[_option $options split_repeated_headers 1]} {
        set groups [_splitRepeatedHeaders $words]
    } else {
        set groups [list $words]
    }
    set tables {}
    set tableIndex 0
    foreach group $groups {
        set reconstructed [_reconstruct $group $expected]
        if {[dict get $reconstructed row_count] > 0} {
            lappend tables [dict merge [dict create table_index $tableIndex] $reconstructed]
            incr tableIndex
        }
    }
    set source [dict create]
    foreach key {source_kind source_path page method coordinate_unit page_width page_height roi_normalized render_dpi} {
        if {[dict exists $layout $key]} { dict set source $key [dict get $layout $key] }
    }
    return [dict create api_version 1 source $source word_count [llength $words] table_count [llength $tables] tables $tables]
}

proc ::GX::TableExtractorAPIv1::_layoutOptions {options} {
    set out [dict create]
    foreach key {method languages psm dpi roi min_confidence native_min_words} {
        if {[dict exists $options $key]} { dict set out $key [dict get $options $key] }
    }
    return $out
}

proc ::GX::TableExtractorAPIv1::extractImage {imagePath {options {}}} {
    set options [_dictOptions $options]
    set ocr [_ocr]
    set layout [${ocr}::extractImage $imagePath [_layoutOptions $options]]
    return [extractLayout $layout $options]
}

proc ::GX::TableExtractorAPIv1::extractPdfPage {pdfPath page {options {}}} {
    set options [_dictOptions $options]
    set ocr [_ocr]
    set layout [${ocr}::extractPdfPage $pdfPath $page [_layoutOptions $options]]
    return [extractLayout $layout $options]
}

proc ::GX::TableExtractorAPIv1::_datasetInfo {session datasetId} {
    foreach cmd {::GX::sessionInspectionDataset ::GX::contractSatisfies ::GX::datasetResolvePath} {
        if {![llength [info commands $cmd]]} { _error "required Dataset API command is unavailable: $cmd" }
    }
    if {![file isdirectory $session]} { _error "Session does not exist: $session" }
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set contract [expr {[dict exists $ds contract] ? [dict get $ds contract] : [dict get $ds kind]}]
    set path [::GX::datasetResolvePath $session $datasetId]
    if {![file isfile $path]} { _error "Dataset '$datasetId' has no readable canonical payload" }
    return [dict create dataset_id $datasetId contract $contract path $path descriptor $ds]
}

proc ::GX::TableExtractorAPIv1::extractDataset {session datasetId {options {}}} {
    set options [_dictOptions $options]
    set info [_datasetInfo $session $datasetId]
    set contract [dict get $info contract]
    set path [dict get $info path]
    if {[::GX::contractSatisfies $contract image.raster]} {
        set result [extractImage $path $options]
    } elseif {[::GX::contractSatisfies $contract document.pdf]} {
        set page [_option $options page 1]
        if {![string is integer -strict $page] || $page < 1} { _error "page must be a positive integer" }
        set result [extractPdfPage $path $page $options]
    } else {
        _error "Dataset '$datasetId' contract '$contract' is not compatible with image.raster or document.pdf"
    }
    dict set result source_dataset_id $datasetId
    dict set result source_contract $contract
    return $result
}

proc ::GX::TableExtractorAPIv1::tableToMatrix {table} {
    if {![dict exists $table matrix]} { _error "table does not contain a matrix" }
    return [dict get $table matrix]
}

proc ::GX::TableExtractorAPIv1::_csvCell {value separator} {
    set needs [expr {[string first $separator $value] >= 0 || [string first "\"" $value] >= 0 || [string first "\n" $value] >= 0 || [string first "\r" $value] >= 0}]
    set value [string map [list "\"" "\"\""] $value]
    return [expr {$needs ? "\"$value\"" : $value}]
}

proc ::GX::TableExtractorAPIv1::tableToCsv {table {options {}}} {
    set options [_dictOptions $options]
    set separator [_option $options separator ,]
    if {[string length $separator] != 1} { _error "CSV separator must be one character" }
    set lines {}
    foreach row [tableToMatrix $table] {
        set cells {}
        foreach value $row { lappend cells [_csvCell $value $separator] }
        lappend lines [join $cells $separator]
    }
    return [join $lines "\n"]
}

proc ::GX::TableExtractorAPIv1::_normalizeNumeric {value} {
    return [string map [list "−" "-" "–" "-"] [string trim $value]]
}

proc ::GX::TableExtractorAPIv1::_inferDtype {values} {
    if {![llength $values]} { return string }
    set normalized {}
    foreach v $values { lappend normalized [_normalizeNumeric $v] }
    foreach v $normalized { if {$v eq ""} { return string } }
    set allInt 1; set allFloat 1
    foreach v $normalized {
        if {![regexp {^[+-]?\d+$} $v]} { set allInt 0 }
        if {![regexp {^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$} $v]} { set allFloat 0 }
    }
    if {$allInt} { return int64 }
    if {$allFloat} { return float64 }
    return string
}

proc ::GX::TableExtractorAPIv1::_sanitizeVariableId {label index} {
    set value [string tolower [string trim $label]]
    regsub -all {[^a-z0-9_]+} $value _ value
    set value [string trim $value _]
    if {$value eq ""} { set value "column_[expr {$index+1}]" }
    if {![regexp {^[a-z]} $value]} { set value "column_$value" }
    return [string range $value 0 79]
}

proc ::GX::TableExtractorAPIv1::inferSchema {table {options {}}} {
    set options [_dictOptions $options]
    set header [_option $options first_row_header 1]
    set matrix [tableToMatrix $table]
    if {![llength $matrix]} { return [dict create columns {} data_rows {}] }
    set colCount 0
    foreach row $matrix { if {[llength $row] > $colCount} { set colCount [llength $row] } }
    set normalized {}
    foreach row $matrix {
        set r $row
        while {[llength $r] < $colCount} { lappend r "" }
        lappend normalized $r
    }
    if {$header} {
        set labels [lindex $normalized 0]
        set dataRows [lrange $normalized 1 end]
    } else {
        set labels {}; for {set i 0} {$i < $colCount} {incr i} { lappend labels "Column [expr {$i+1}]" }
        set dataRows $normalized
    }
    set seen [dict create]; set columns {}
    for {set i 0} {$i < $colCount} {incr i} {
        set label [string trim [lindex $labels $i]]
        if {$label eq ""} { set label "Column [expr {$i+1}]" }
        set base [_sanitizeVariableId $label $i]
        set count [expr {[dict exists $seen $base] ? [dict get $seen $base] + 1 : 1}]
        dict set seen $base $count
        set id [expr {$count == 1 ? $base : "${base}_$count"}]
        set values {}; foreach row $dataRows { lappend values [lindex $row $i] }
        lappend columns [dict create id $id name $label dtype [_inferDtype $values] unit "" semantic_role ""]
    }
    return [dict create columns $columns data_rows $dataRows first_row_header [expr {$header ? 1 : 0}]]
}
