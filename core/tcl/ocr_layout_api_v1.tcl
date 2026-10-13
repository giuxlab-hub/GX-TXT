# GX-TXT OCR and Layout Service API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# CORE-owned, versioned OCR API. Loaded at framework startup independently of
# module selection or GUI startup.

namespace eval ::GX::OCRLayoutAPIv1 {
    variable apiVersion 1
    variable supportedCapabilities {
        dependency_discovery tesseract_languages image_ocr pdf_info pdf_page_render
        pdf_native_text pdf_page_ocr pdf_auto_text pdf_document_layout
        normalized_coordinates roi_filter positioned_words plain_text_reconstruction
    }
}

proc ::GX::OCRLayoutAPIv1::_error {message} {
    return -code error "ocr.layout API v1: $message"
}

proc ::GX::OCRLayoutAPIv1::capabilities {} {
    variable supportedCapabilities
    return $supportedCapabilities
}

proc ::GX::OCRLayoutAPIv1::supports {capability} {
    expr {[lsearch -exact [capabilities] $capability] >= 0}
}

proc ::GX::OCRLayoutAPIv1::requireCapability {capability} {
    if {![supports $capability]} {_error "capability '$capability' is not supported"}
    return 1
}

proc ::GX::OCRLayoutAPIv1::_commandPath {name} {
    if {$name eq "tesseract" && [llength [info commands ::GX::runtimeToolResolve]]} {
        set p [::GX::runtimeToolResolve tesseract]
    } else {
        set p [auto_execok $name]
    }
    if {$p eq ""} { return "" }
    return [file normalize $p]
}

proc ::GX::OCRLayoutAPIv1::dependencyStatus {} {
    set out [dict create]
    foreach name {tesseract pdftotext pdftoppm pdfinfo} {
        set p [_commandPath $name]
        dict set out $name [dict create available [expr {$p ne ""}] path $p]
    }
    return $out
}

proc ::GX::OCRLayoutAPIv1::apiInfo {} {
    variable apiVersion
    return [dict create \
        api_name OCR_LAYOUT_API_v1 \
        api_version $apiVersion \
        owner CORE \
        capabilities [capabilities] \
        dependencies [dependencyStatus]]
}

proc ::GX::OCRLayoutAPIv1::_requireCommand {name} {
    set p [_commandPath $name]
    if {$p eq ""} {_error "required external command '$name' is unavailable"}
    return $p
}

proc ::GX::OCRLayoutAPIv1::_run {argv} {
    if {[llength $argv] == 0} {_error "internal command invocation is empty"}
    set executable [lindex $argv 0]
    lset argv 0 [_requireCommand $executable]
    if {[catch {set output [exec {*}$argv 2>@1]} failure options]} {
        return -options $options "ocr.layout API v1: $executable failed: $failure"
    }
    return $output
}

proc ::GX::OCRLayoutAPIv1::_fileRequired {path label} {
    set path [file normalize $path]
    if {![file isfile $path]} {_error "$label does not exist: $path"}
    return $path
}

proc ::GX::OCRLayoutAPIv1::_dictOptions {options} {
    if {$options eq ""} { return [dict create] }
    if {[catch {dict size $options}]} {_error "options must be a Tcl dict"}
    return $options
}

proc ::GX::OCRLayoutAPIv1::_option {options key default} {
    expr {[dict exists $options $key] ? [dict get $options $key] : $default}
}

proc ::GX::OCRLayoutAPIv1::_positiveInteger {value label} {
    if {![string is integer -strict $value] || $value < 1} {_error "$label must be a positive integer"}
    return $value
}

proc ::GX::OCRLayoutAPIv1::_finiteDouble {value label} {
    if {![string is double -strict $value]} {_error "$label must be numeric"}
    set d [expr {double($value)}]
    if {$d != $d || abs($d) == Inf} {_error "$label must be finite"}
    return $d
}

proc ::GX::OCRLayoutAPIv1::_normalizeRoi {roi} {
    if {$roi eq ""} { return {} }
    if {[llength $roi] != 4} {_error "roi must contain four normalized values: x1 y1 x2 y2"}
    lassign $roi x1 y1 x2 y2
    set x1 [_finiteDouble $x1 "roi x1"]
    set y1 [_finiteDouble $y1 "roi y1"]
    set x2 [_finiteDouble $x2 "roi x2"]
    set y2 [_finiteDouble $y2 "roi y2"]
    foreach v [list $x1 $y1 $x2 $y2] {
        if {$v < 0.0 || $v > 1.0} {_error "roi coordinates must be in the normalized range 0..1"}
    }
    if {$x2 <= $x1 || $y2 <= $y1} {_error "roi must have positive width and height"}
    return [list $x1 $y1 $x2 $y2]
}

proc ::GX::OCRLayoutAPIv1::languages {} {
    set text [_run [list tesseract --list-langs]]
    set out {}
    foreach line [split $text "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "List of available languages*" $line]} continue
        lappend out $line
    }
    return [lsort -dictionary -unique $out]
}

proc ::GX::OCRLayoutAPIv1::_parseKeyValueText {text} {
    set out [dict create]
    foreach line [split $text "\n"] {
        set pos [string first : $line]
        if {$pos < 1} continue
        set key [string tolower [string trim [string range $line 0 [expr {$pos-1}]]]]
        set value [string trim [string range $line [expr {$pos+1}] end]]
        if {$key ne ""} { dict set out $key $value }
    }
    return $out
}

proc ::GX::OCRLayoutAPIv1::pdfInfo {pdfPath} {
    requireCapability pdf_info
    set pdfPath [_fileRequired $pdfPath "PDF file"]
    set raw [_run [list pdfinfo $pdfPath]]
    set kv [_parseKeyValueText $raw]
    set pages [_option $kv pages 0]
    if {![string is integer -strict $pages] || $pages < 1} {_error "pdfinfo did not report a valid page count"}
    set out [dict create path $pdfPath page_count $pages]
    foreach {source target} {
        {pdf version} pdf_version
        encrypted encrypted
        {page size} page_size
        {page rot} page_rotation
        title title
        author author
        subject subject
        creator creator
        producer producer
    } {
        if {[dict exists $kv $source]} { dict set out $target [dict get $kv $source] }
    }
    return $out
}

proc ::GX::OCRLayoutAPIv1::_parseTsv {text method sourceKind sourcePath pageNumber options} {
    set lines [split $text "\n"]
    if {[llength $lines] < 2} {
        return [dict create api_version 1 source_kind $sourceKind source_path $sourcePath page $pageNumber method $method coordinate_unit "" page_width 0 page_height 0 word_count 0 words {}]
    }
    set header [split [lindex $lines 0] "\t"]
    set index [dict create]
    for {set i 0} {$i < [llength $header]} {incr i} { dict set index [lindex $header $i] $i }
    foreach required {level page_num left top width height conf text} {
        if {![dict exists $index $required]} {_error "positioned-text TSV is missing required column '$required'"}
    }
    set pageWidth 0.0
    set pageHeight 0.0
    set words {}
    set minConfidence [_finiteDouble [_option $options min_confidence -1] "min_confidence"]
    foreach line [lrange $lines 1 end] {
        if {[string trim $line] eq ""} continue
        set fields [split $line "\t"]
        set fieldCount [llength $fields]
        set levelIndex [dict get $index level]
        if {$levelIndex >= $fieldCount} continue
        set level [lindex $fields $levelIndex]
        set left [lindex $fields [dict get $index left]]
        set top [lindex $fields [dict get $index top]]
        set width [lindex $fields [dict get $index width]]
        set height [lindex $fields [dict get $index height]]
        if {$level eq "1"} {
            if {[string is double -strict $width] && [string is double -strict $height]} {
                set pageWidth [expr {double($width)}]
                set pageHeight [expr {double($height)}]
            }
            continue
        }
        if {$level ne "5"} continue
        set textIndex [dict get $index text]
        if {$textIndex >= $fieldCount} continue
        # A word normally occupies one TSV field. Preserve any unexpected tabs
        # in the token by joining excess fields back into the text field.
        set token [join [lrange $fields $textIndex end] "\t"]
        set token [string trim $token]
        if {$token eq "" || [string match "###*###" $token]} continue
        foreach {name value} [list left $left top $top width $width height $height] {
            if {![string is double -strict $value]} { set value 0 }
            set $name [expr {double($value)}]
        }
        set conf [lindex $fields [dict get $index conf]]
        if {![string is double -strict $conf]} { set conf -1 }
        set conf [expr {double($conf)}]
        if {$conf < $minConfidence} continue
        set block 0; set paragraph 0; set lineNo 0; set wordNo 0
        foreach {column variable} {block_num block par_num paragraph line_num lineNo word_num wordNo} {
            if {[dict exists $index $column]} {
                set ii [dict get $index $column]
                if {$ii < $fieldCount} { set $variable [lindex $fields $ii] }
            }
        }
        if {$pageWidth > 0 && $pageHeight > 0} {
            set xNorm [expr {$left / $pageWidth}]
            set yNorm [expr {$top / $pageHeight}]
            set wNorm [expr {$width / $pageWidth}]
            set hNorm [expr {$height / $pageHeight}]
        } else {
            set xNorm 0; set yNorm 0; set wNorm 0; set hNorm 0
        }
        lappend words [dict create \
            text $token confidence $conf \
            x $left y $top width $width height $height \
            x_norm $xNorm y_norm $yNorm width_norm $wNorm height_norm $hNorm \
            cx_norm [expr {$xNorm + $wNorm/2.0}] cy_norm [expr {$yNorm + $hNorm/2.0}] \
            block $block paragraph $paragraph line $lineNo word_index $wordNo \
            source $method]
    }
    set coordinateUnit [expr {$method eq "pdf_native" ? "pt" : "px"}]
    set out [dict create \
        api_version 1 source_kind $sourceKind source_path $sourcePath page $pageNumber \
        method $method coordinate_unit $coordinateUnit page_width $pageWidth page_height $pageHeight \
        word_count [llength $words] words $words]
    set roi [_normalizeRoi [_option $options roi {}]]
    if {[llength $roi]} { return [filterRoi $out $roi] }
    return $out
}

proc ::GX::OCRLayoutAPIv1::filterRoi {layout roi} {
    requireCapability roi_filter
    set roi [_normalizeRoi $roi]
    if {![dict exists $layout words]} {_error "layout does not contain positioned words"}
    lassign $roi x1 y1 x2 y2
    set outWords {}
    foreach word [dict get $layout words] {
        set cx [dict get $word cx_norm]
        set cy [dict get $word cy_norm]
        if {$cx >= $x1 && $cx <= $x2 && $cy >= $y1 && $cy <= $y2} { lappend outWords $word }
    }
    dict set layout words $outWords
    dict set layout word_count [llength $outWords]
    dict set layout roi_normalized $roi
    return $layout
}

proc ::GX::OCRLayoutAPIv1::_ocrOptions {options} {
    set options [_dictOptions $options]
    set langs [_option $options languages eng]
    if {[string trim $langs] eq ""} {_error "languages must not be empty"}
    set psm [_option $options psm 3]
    if {![string is integer -strict $psm] || $psm < 0 || $psm > 13} {_error "psm must be an integer from 0 to 13"}
    dict set options languages $langs
    dict set options psm $psm
    return $options
}

proc ::GX::OCRLayoutAPIv1::extractImage {imagePath {options {}}} {
    requireCapability image_ocr
    set imagePath [_fileRequired $imagePath "Image file"]
    set options [_ocrOptions $options]
    set langs [dict get $options languages]
    set psm [dict get $options psm]
    set tsv [_run [list tesseract $imagePath stdout -l $langs --psm $psm tsv]]
    return [_parseTsv $tsv tesseract image $imagePath 1 $options]
}

proc ::GX::OCRLayoutAPIv1::_pdfNative {pdfPath page options} {
    requireCapability pdf_native_text
    set tsv [_run [list pdftotext -f $page -l $page -tsv $pdfPath -]]
    return [_parseTsv $tsv pdf_native pdf $pdfPath $page $options]
}

proc ::GX::OCRLayoutAPIv1::_tempPrefix {} {
    set ch [file tempfile path]
    close $ch
    file delete -force -- $path
    return $path
}

proc ::GX::OCRLayoutAPIv1::renderPdfPage {pdfPath page outputPath {options {}}} {
    requireCapability pdf_page_render
    set pdfPath [_fileRequired $pdfPath "PDF file"]
    set info [pdfInfo $pdfPath]
    set page [_positiveInteger $page "page"]
    if {$page > [dict get $info page_count]} {_error "page $page is outside the PDF page range"}
    set options [_dictOptions $options]
    set dpi [_positiveInteger [_option $options dpi 300] "dpi"]
    set outputPath [file normalize $outputPath]
    file mkdir [file dirname $outputPath]
    set prefix [_tempPrefix]
    set tempOut "${prefix}.png"
    try {
        _run [list pdftoppm -f $page -l $page -singlefile -png -r $dpi $pdfPath $prefix]
        if {![file isfile $tempOut]} {_error "pdftoppm did not create the requested page image"}
        file rename -force -- $tempOut $outputPath
    } finally {
        catch {file delete -force -- $tempOut $prefix}
    }
    return [dict create path $outputPath page $page dpi $dpi format png media_type image/png]
}

proc ::GX::OCRLayoutAPIv1::_pdfOcr {pdfPath page options} {
    requireCapability pdf_page_ocr
    set options [_ocrOptions $options]
    set dpi [_positiveInteger [_option $options dpi 300] "dpi"]
    set prefix [_tempPrefix]
    set imagePath "${prefix}.png"
    try {
        renderPdfPage $pdfPath $page $imagePath [dict create dpi $dpi]
        set imageOptions $options
        dict unset imageOptions method
        set layout [extractImage $imagePath $imageOptions]
        dict set layout source_kind pdf
        dict set layout source_path $pdfPath
        dict set layout page $page
        dict set layout method tesseract
        dict set layout render_dpi $dpi
        return $layout
    } finally {
        catch {file delete -force -- $imagePath $prefix}
    }
}

proc ::GX::OCRLayoutAPIv1::extractPdfPage {pdfPath page {options {}}} {
    requireCapability pdf_auto_text
    set pdfPath [_fileRequired $pdfPath "PDF file"]
    set info [pdfInfo $pdfPath]
    set page [_positiveInteger $page "page"]
    if {$page > [dict get $info page_count]} {_error "page $page is outside the PDF page range"}
    set options [_dictOptions $options]
    set method [string tolower [_option $options method auto]]
    if {$method ni {auto native ocr}} {_error "method must be auto, native or ocr"}
    if {$method eq "native"} { return [_pdfNative $pdfPath $page $options] }
    if {$method eq "ocr"} { return [_pdfOcr $pdfPath $page $options] }
    set minWords [_option $options native_min_words 1]
    if {![string is integer -strict $minWords] || $minWords < 0} {_error "native_min_words must be a non-negative integer"}
    if {![catch {set native [_pdfNative $pdfPath $page $options]}]} {
        if {[dict get $native word_count] >= $minWords} { return $native }
    }
    return [_pdfOcr $pdfPath $page $options]
}

proc ::GX::OCRLayoutAPIv1::extractPdfDocument {pdfPath {options {}}} {
    requireCapability pdf_document_layout
    set pdfPath [_fileRequired $pdfPath "PDF file"]
    set info [pdfInfo $pdfPath]
    set pages {}
    for {set page 1} {$page <= [dict get $info page_count]} {incr page} {
        lappend pages [extractPdfPage $pdfPath $page $options]
    }
    return [dict create api_version 1 source_kind pdf source_path $pdfPath page_count [dict get $info page_count] pages $pages]
}

proc ::GX::OCRLayoutAPIv1::_layoutPageText {layout} {
    if {![dict exists $layout words]} {_error "layout does not contain words"}
    set grouped [dict create]
    set order {}
    foreach word [dict get $layout words] {
        set key "[dict get $word block],[dict get $word paragraph],[dict get $word line]"
        if {![dict exists $grouped $key]} { lappend order $key; dict set grouped $key {} }
        dict lappend grouped $key $word
    }
    # Sort line groups by their geometric position rather than trusting backend
    # numeric IDs, which may restart inside blocks.
    set sortable {}
    foreach key $order {
        set ws [dict get $grouped $key]
        set minY 2.0; set minX 2.0
        foreach w $ws {
            set y [dict get $w y_norm]; set x [dict get $w x_norm]
            if {$y < $minY} { set minY $y }
            if {$x < $minX} { set minX $x }
        }
        lappend sortable [list $minY $minX $key]
    }
    set lines {}
    foreach item [lsort -real -index 0 $sortable] {
        set ws [dict get $grouped [lindex $item 2]]
        set sorted [lsort -command ::GX::OCRLayoutAPIv1::_compareWordX $ws]
        set tokens {}
        foreach w $sorted { lappend tokens [dict get $w text] }
        if {[llength $tokens]} { lappend lines [join $tokens " "] }
    }
    return [join $lines "\n"]
}

proc ::GX::OCRLayoutAPIv1::_compareWordX {a b} {
    set ax [dict get $a x_norm]; set bx [dict get $b x_norm]
    if {$ax < $bx} { return -1 }
    if {$ax > $bx} { return 1 }
    return 0
}

proc ::GX::OCRLayoutAPIv1::toText {layoutOrDocument {options {}}} {
    requireCapability plain_text_reconstruction
    set options [_dictOptions $options]
    set separator [_option $options page_separator "\n\f\n"]
    if {[dict exists $layoutOrDocument pages]} {
        set pageTexts {}
        foreach pageLayout [dict get $layoutOrDocument pages] { lappend pageTexts [_layoutPageText $pageLayout] }
        return [join $pageTexts $separator]
    }
    return [_layoutPageText $layoutOrDocument]
}
