# GX-TXT Document Extraction Viewer backends
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::DocumentExtractors {
    variable moduleId viewer.document_extractors
    variable version 1.0.1
    variable previewDir
    variable previewPhoto
    variable roi
    variable dragStart
    variable currentTable
    variable currentMatrix
    variable currentOcrText
    variable ui
    variable ocrSource
    variable ocrZoom
    array set previewDir {}
    array set previewPhoto {}
    array set roi {}
    array set dragStart {}
    array set currentTable {}
    array set currentMatrix {}
    array set currentOcrText {}
    array set ui {}
    array set ocrSource {}
    array set ocrZoom {}
}

proc ::GX::DocumentExtractors::_activate {} {
    foreach command {::GX::OCRLayoutAPIv1::apiInfo ::GX::TableExtractorAPIv1::apiInfo} {
        if {![llength [info commands $command]]} {
            error "Required CORE document extraction API is unavailable: $command"
        }
    }
    return 1
}

proc ::GX::DocumentExtractors::_session {} {
    return [::GX::sessionInspectionCurrentSession]
}

proc ::GX::DocumentExtractors::_datasetInfo {datasetId} {
    set session [_session]
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set contract [expr {[dict exists $ds contract] ? [dict get $ds contract] : [dict get $ds kind]}]
    if {![::GX::contractSatisfies $contract image.raster] && ![::GX::contractSatisfies $contract document.pdf]} {
        error "Dataset '$datasetId' is not compatible with image.raster or document.pdf."
    }
    set path [dict get [::GX::sessionInspectionDatasetPayload $datasetId $session] path]
    return [dict create id $datasetId contract $contract path $path \
        format [expr {[dict exists $ds format] ? [dict get $ds format] : ""}] \
        media_type [expr {[dict exists $ds media_type] ? [dict get $ds media_type] : ""}] descriptor $ds]
}

proc ::GX::DocumentExtractors::_compatibleIds {} {
    set out {}
    set session [_session]
    foreach id [::GX::sessionInspectionDatasetIds $session] {
        if {[catch {set ds [::GX::sessionInspectionDataset $id $session]}]} continue
        set contract [expr {[dict exists $ds contract] ? [dict get $ds contract] : [dict get $ds kind]}]
        if {![catch {::GX::contractSatisfies $contract image.raster} a] && $a} { lappend out $id; continue }
        if {![catch {::GX::contractSatisfies $contract document.pdf} a] && $a} { lappend out $id }
    }
    return [lsort -dictionary $out]
}

proc ::GX::DocumentExtractors::_safeId {value fallback} {
    set value [string trim $value]
    regsub -all {[^A-Za-z0-9_.-]+} $value . value
    set value [string trim $value .-_]
    if {$value eq ""} { set value $fallback }
    return [string range $value 0 119]
}

proc ::GX::DocumentExtractors::_cleanupPreview {mode} {
    variable previewDir
    variable previewPhoto
    variable ocrSource
    if {[info exists previewPhoto($mode)] && $previewPhoto($mode) ne ""} { catch {image delete $previewPhoto($mode)}; set previewPhoto($mode) "" }
    if {[info exists previewDir($mode)] && $previewDir($mode) ne ""} { catch {::GX::previewDescriptorCleanupDir $previewDir($mode)}; set previewDir($mode) "" }
    if {$mode eq "ocr"} { unset -nocomplain ocrSource(ocr) }
}

proc ::GX::DocumentExtractors::_previewArtifact {mode info page} {
    variable previewDir
    _cleanupPreview $mode
    set dir [::GX::previewDescriptorCreateTempDir]
    set previewDir($mode) $dir
    set path [dict get $info path]
    set artifact [dict create]
    set contract [dict get $info contract]
    set artifact [dict create]
    if {[::GX::contractSatisfies $contract image.raster]} {
        set artifact [::GX::datasetPreviewMediaArtifact $path [dict get $info media_type] [dict get $info format] $contract $dir]
    } elseif {[::GX::contractSatisfies $contract document.pdf]} {
        if {$page == 1} {
            set artifact [::GX::datasetPreviewMediaArtifact $path [dict get $info media_type] [dict get $info format] $contract $dir]
        }
        if {![dict size $artifact]} {
            set target [file join $dir "pdf-page-$page.png"]
            ::GX::OCRLayoutAPIv1::renderPdfPage $path $page $target [dict create dpi 120]
            set artifact [dict create path $target media_type image/png label "PDF page $page"]
        }
    }
    return $artifact
}

proc ::GX::DocumentExtractors::_pageCount {info} {
    if {[::GX::contractSatisfies [dict get $info contract] document.pdf]} {
        return [dict get [::GX::OCRLayoutAPIv1::pdfInfo [dict get $info path]] page_count]
    }
    return 1
}

proc ::GX::DocumentExtractors::_showPreview {mode} {
    variable ui
    variable previewPhoto
    variable roi
    _activate
    set id [set $ui($mode,sourceVar)]
    if {[string trim $id] eq ""} { return }
    set info [_datasetInfo $id]
    set page [set $ui($mode,pageVar)]
    set pages [_pageCount $info]
    if {![string is integer -strict $page] || $page < 1} { set page 1 }
    if {$page > $pages} { set page $pages }
    set $ui($mode,pageVar) $page
    catch {$ui($mode,pageSpin) configure -to $pages}
    if {$mode eq "ocr"} { _ocrShowPreview $info $page $pages; return }
    set artifact [_previewArtifact $mode $info $page]
    set c $ui($mode,canvas)
    $c delete all
    set roi($mode) {}
    if {![dict size $artifact]} {
        $c create text 20 20 -anchor nw -fill white -text "CORE Dataset Preview API could not create a visual preview."
        return
    }
    set img [image create photo -file [dict get $artifact path]]
    set previewPhoto($mode) $img
    set w [image width $img]; set h [image height $img]
    $c create image 0 0 -anchor nw -image $img -tags source
    $c configure -scrollregion [list 0 0 $w $h]
    ::GX::setStatus "Preview ready for $id (page $page/$pages)." 100
}

# The OCR canvas is only a view of this full-resolution render.  Its pixels
# are never used as the source for Dataset acquisition.
proc ::GX::DocumentExtractors::_ocrShowPreview {info page pages} {
    variable ui
    variable previewDir
    variable ocrSource
    variable ocrZoom
    variable roi
    set magick [::GX::datasetPreviewTool magick]
    if {$magick eq ""} { error "ImageMagick is required for the zoomable OCR preview and ROI acquisition." }
    _cleanupPreview ocr
    set dir [::GX::previewDescriptorCreateTempDir]
    set previewDir(ocr) $dir
    set source [file join $dir source.png]
    set contract [dict get $info contract]
    set dpi 0
    if {[::GX::contractSatisfies $contract document.pdf]} {
        set dpi [set $ui(ocr,dpiVar)]
        ::GX::OCRLayoutAPIv1::renderPdfPage [dict get $info path] $page $source [dict create dpi $dpi]
    } else {
        # Decode the canonical image without the Dataset Preview thumbnail limit.
        exec $magick [dict get $info path] -auto-orient $source 2>@1
    }
    set original [image create photo -file $source]
    set w [image width $original]; set h [image height $original]
    image delete $original
    if {$w < 1 || $h < 1} { error "The source image has no usable pixels." }
    set ocrSource(ocr) [dict create path $source width $w height $h dataset_id [dict get $info id] page $page dpi $dpi]
    set roi(ocr) {}
    set c $ui(ocr,canvas)
    $c xview moveto 0; $c yview moveto 0
    update idletasks
    set fit [expr {min(double(max(1,[winfo width $c]))/$w, double(max(1,[winfo height $c]))/$h)}]
    set ocrZoom(ocr) [expr {max(0.005,min(8.0,$fit))}]
    _ocrApplyZoom
    ::GX::setStatus "Preview ready for [dict get $info id] (page $page/$pages)." 100
}

proc ::GX::DocumentExtractors::_ocrApplyZoom {} {
    variable ui
    variable ocrSource
    variable ocrZoom
    variable previewPhoto
    variable roi
    if {![info exists ocrSource(ocr)]} return
    set zoom [expr {max(0.005,min(8.0,double($ocrZoom(ocr))))}]
    set ocrZoom(ocr) $zoom
    set source $ocrSource(ocr)
    set w [expr {max(1,round([dict get $source width]*$zoom))}]
    set h [expr {max(1,round([dict get $source height]*$zoom))}]
    set rendered [file join [file dirname [dict get $source path]] display.png]
    set magick [::GX::datasetPreviewTool magick]
    exec $magick [dict get $source path] -resize ${w}x${h}! $rendered 2>@1
    set photo [image create photo -file $rendered]
    set c $ui(ocr,canvas)
    set oldX [lindex [$c xview] 0]; set oldY [lindex [$c yview] 0]
    $c delete all
    if {[info exists previewPhoto(ocr)] && $previewPhoto(ocr) ne ""} { image delete $previewPhoto(ocr) }
    set previewPhoto(ocr) $photo
    $c create image 0 0 -anchor nw -image $photo -tags source
    $c configure -scrollregion [list 0 0 $w $h]
    $c xview moveto $oldX; $c yview moveto $oldY
    if {[info exists roi(ocr)] && [llength $roi(ocr)] == 4} {
        lassign $roi(ocr) x1 y1 x2 y2
        $c create rectangle [expr {$x1*$w}] [expr {$y1*$h}] [expr {$x2*$w}] [expr {$y2*$h}] -outline red -width 2 -dash {6 4} -tags roi
    }
    $ui(ocr,zoomLabel) configure -text [format "%.0f%%" [expr {$zoom*100}]]
}

proc ::GX::DocumentExtractors::_ocrZoomBy {factor} {
    variable ocrZoom
    if {![info exists ocrZoom(ocr)]} return
    set ocrZoom(ocr) [expr {$ocrZoom(ocr)*$factor}]
    _ocrApplyZoom
}

proc ::GX::DocumentExtractors::_ocrZoomSchedule {value} {
    variable ocrZoom
    variable ui
    set ocrZoom(ocr) $value
    if {[info exists ui(ocr,zoomTimer)]} { after cancel $ui(ocr,zoomTimer) }
    set ui(ocr,zoomTimer) [after 100 ::GX::DocumentExtractors::_ocrApplyZoom]
}

proc ::GX::DocumentExtractors::_ocrWheel {delta horizontal} {
    variable ui
    set c $ui(ocr,canvas)
    if {$horizontal} { $c xview scroll $delta units } else { $c yview scroll $delta units }
}

proc ::GX::DocumentExtractors::_ocrFit {} {
    variable ocrSource
    variable ocrZoom
    variable ui
    if {![info exists ocrSource(ocr)]} return
    set c $ui(ocr,canvas)
    set ocrZoom(ocr) [expr {min(double(max(1,[winfo width $c]))/[dict get $ocrSource(ocr) width], double(max(1,[winfo height $c]))/[dict get $ocrSource(ocr) height])}]
    _ocrApplyZoom
}

proc ::GX::DocumentExtractors::_ocrAcquire {} {
    variable ui
    variable roi
    variable ocrSource
    if {[catch {
        if {![info exists ocrSource(ocr)] || ![info exists roi(ocr)] || [llength $roi(ocr)] != 4} {
            error "Select a region in the preview first."
        }
        set src $ocrSource(ocr)
        lassign $roi(ocr) x1 y1 x2 y2
        set sw [dict get $src width]; set sh [dict get $src height]
        set left [expr {max(0,int(floor($x1*$sw)))}]
        set top [expr {max(0,int(floor($y1*$sh)))}]
        set right [expr {min($sw,int(ceil($x2*$sw)))}]
        set bottom [expr {min($sh,int(ceil($y2*$sh)))}]
        set width [expr {$right-$left}]; set height [expr {$bottom-$top}]
        if {$width < 1 || $height < 1} { error "The selected region has no source pixels." }
        set id [_safeId [set $ui(ocr,imageOutVar)] ocr.region]
        set sourceId [dict get $src dataset_id]
        set crop [file join [file dirname [dict get $src path]] roi.png]
        set magick [::GX::datasetPreviewTool magick]
        exec $magick [dict get $src path] -crop ${width}x${height}+${left}+${top} +repage $crop 2>@1
        set md [dict create image.source_dataset_id $sourceId image.source_page [dict get $src page] image.source_roi_norm $roi(ocr) image.source_pixel_bounds [list $left $top $right $bottom] image.source_render_dpi [dict get $src dpi] image.source_render_size [list $sw $sh]]
        set req [dict create dataset_id $id contract image.raster format png source_file $crop storage_kind binary media_type image/png producer_version 1.0.1 source_dataset_ids [list $sourceId] source "Generic OCR viewer; Dataset $sourceId" provenance "Full-resolution ROI of Dataset $sourceId, page [dict get $src page], pixels $left,$top to $right,$bottom at [dict get $src dpi] DPI" structured_metadata $md replace_owned 1]
        ::GX::datasetFilePublicationPublish [_session] viewer.document_extractors $req
        set $ui(ocr,imageOutVar) $id
        ::GX::setStatus "Published image Dataset: $id ($width × $height pixels)." 100
    } err]} { tk_messageBox -parent .gxGenericOcr -icon error -title "Generic OCR" -message $err }
}

proc ::GX::DocumentExtractors::_canvasPoint {mode x y} {
    variable ui
    variable previewPhoto
    set c $ui($mode,canvas)
    set x [$c canvasx $x]; set y [$c canvasy $y]
    if {![info exists previewPhoto($mode)] || $previewPhoto($mode) eq ""} { return [list 0 0] }
    set w [image width $previewPhoto($mode)]; set h [image height $previewPhoto($mode)]
    set x [expr {max(0,min($w,$x))}]; set y [expr {max(0,min($h,$y))}]
    return [list $x $y]
}

proc ::GX::DocumentExtractors::_roiStart {mode x y} {
    variable dragStart
    variable ui
    lassign [_canvasPoint $mode $x $y] sx sy
    set dragStart($mode) [list $sx $sy]
    $ui($mode,canvas) delete roi
    $ui($mode,canvas) create rectangle $sx $sy $sx $sy -outline red -width 2 -dash {6 4} -tags roi
}

proc ::GX::DocumentExtractors::_roiDrag {mode x y} {
    variable dragStart
    variable ui
    if {![info exists dragStart($mode)] || ![llength $dragStart($mode)]} return
    lassign $dragStart($mode) x1 y1
    lassign [_canvasPoint $mode $x $y] x2 y2
    $ui($mode,canvas) coords roi $x1 $y1 $x2 $y2
}

proc ::GX::DocumentExtractors::_roiEnd {mode x y} {
    variable dragStart
    variable roi
    variable previewPhoto
    if {![info exists dragStart($mode)] || ![llength $dragStart($mode)]} return
    lassign $dragStart($mode) x1 y1
    lassign [_canvasPoint $mode $x $y] x2 y2
    set dragStart($mode) {}
    if {![info exists previewPhoto($mode)] || $previewPhoto($mode) eq ""} return
    set w [image width $previewPhoto($mode)]; set h [image height $previewPhoto($mode)]
    set lx [expr {min($x1,$x2)}]; set rx [expr {max($x1,$x2)}]
    set ty [expr {min($y1,$y2)}]; set by [expr {max($y1,$y2)}]
    if {$rx-$lx < 2 || $by-$ty < 2} { set roi($mode) {}; return }
    set roi($mode) [list [expr {$lx/double($w)}] [expr {$ty/double($h)}] [expr {$rx/double($w)}] [expr {$by/double($h)}]]
}

proc ::GX::DocumentExtractors::_clearRoi {mode} {
    variable roi
    variable ui
    set roi($mode) {}
    catch {$ui($mode,canvas) delete roi}
}

proc ::GX::DocumentExtractors::_methodValue {label} {
    switch -- $label { "Native PDF text" {return native} OCR {return ocr} default {return auto} }
}

proc ::GX::DocumentExtractors::_commonOptions {mode} {
    variable ui
    variable roi
    set d [dict create \
        method [_methodValue [set $ui($mode,methodVar)]] \
        languages [string trim [set $ui($mode,langVar)]] \
        psm [set $ui($mode,psmVar)] \
        dpi [set $ui($mode,dpiVar)]]
    if {[info exists roi($mode)] && [llength $roi($mode)]} { dict set d roi $roi($mode) }
    return $d
}

proc ::GX::DocumentExtractors::_tableExtract {} {
    variable ui
    variable currentTable
    variable currentMatrix
    set mode table
    if {[catch {
        _activate
        set id [set $ui($mode,sourceVar)]
        set opts [_commonOptions $mode]
        dict set opts page [set $ui($mode,pageVar)]
        set expected [set $ui($mode,expectedVar)]
        if {$expected ne ""} { dict set opts expected_columns $expected }
        set result [::GX::TableExtractorAPIv1::extractDataset [_session] $id $opts]
        if {[dict get $result table_count] < 1} { error "No table could be reconstructed from the selected source/ROI." }
        set table [lindex [dict get $result tables] 0]
        set currentTable(table) $table
        set currentMatrix(table) [dict get $table matrix]
        _tableRenderMatrix
        ::GX::setStatus "Table extracted: [dict get $table row_count] rows × [dict get $table column_count] columns." 100
    } err]} {
        tk_messageBox -parent .gxTableExtractor -icon error -title "Table Extractor" -message $err
    }
}

proc ::GX::DocumentExtractors::_tableRenderMatrix {} {
    variable ui
    variable currentMatrix
    set tree $ui(table,tree)
    $tree delete [$tree children {}]
    set matrix [expr {[info exists currentMatrix(table)] ? $currentMatrix(table) : {}}]
    set cols 0; foreach row $matrix { if {[llength $row] > $cols} {set cols [llength $row]} }
    set ids {}; for {set i 0} {$i < $cols} {incr i} { lappend ids "c$i" }
    $tree configure -columns $ids -show headings
    set headerIndex [expr {[set $ui(table,headerVar)] ? 0 : -1}]
    set title ""
    if {$headerIndex == 0 && [llength $matrix] >= 2} {
        set second [lindex $matrix 1]
        set monthCount 0
        foreach cell $second {
            if {[string tolower [string trim $cell]] in {gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre january february march may june july august september october november december}} {incr monthCount}
        }
        if {$monthCount >= 6} {
            set headerIndex 1
            set title [string trim [join [lindex $matrix 0] " "]]
        }
    }
    catch {$ui(table,title) configure -text $title}
    set header [expr {$headerIndex >= 0 ? [lindex $matrix $headerIndex] : {}}]
    for {set i 0} {$i < $cols} {incr i} {
        set label [string trim [lindex $header $i]]
        if {$label eq ""} {set label [expr {$i == 0 && $headerIndex == 1 ? "Region" : "Column [expr {$i+1}]"}]}
        $tree heading c$i -text $label
        $tree column c$i -width [expr {$i == 0 ? 180 : 100}] -stretch 1
    }
    set r 0
    foreach row $matrix {
        if {$r <= $headerIndex} {incr r; continue}
        set values $row; while {[llength $values] < $cols} {lappend values ""}
        $tree insert {} end -id "r$r" -values $values
        incr r
    }
}

proc ::GX::DocumentExtractors::_tableBeginEdit {x y} {
    variable ui
    set tree $ui(table,tree)
    set item [$tree identify row $y]
    set col [$tree identify column $x]
    if {$item eq "" || $col eq "" || $col eq "#0"} return
    set ci [expr {[string range $col 1 end]-1}]
    set values [$tree item $item -values]
    set old [lindex $values $ci]
    set box [$tree bbox $item $col]
    if {![llength $box]} return
    catch {destroy $tree.edit}
    ttk::entry $tree.edit
    $tree.edit insert 0 $old
    lassign $box bx by bw bh
    place $tree.edit -x $bx -y $by -width $bw -height $bh
    focus $tree.edit; $tree.edit selection range 0 end
    bind $tree.edit <Return> [list ::GX::DocumentExtractors::_tableCommitEdit $item $ci]
    bind $tree.edit <Escape> [list destroy $tree.edit]
    bind $tree.edit <FocusOut> [list ::GX::DocumentExtractors::_tableCommitEdit $item $ci]
}

proc ::GX::DocumentExtractors::_tableCommitEdit {item ci} {
    variable ui
    variable currentMatrix
    set tree $ui(table,tree)
    if {![winfo exists $tree.edit]} return
    set value [$tree.edit get]
    catch {destroy $tree.edit}
    set values [$tree item $item -values]
    lset values $ci $value
    $tree item $item -values $values
    set ri [string range $item 1 end]
    set row [lindex $currentMatrix(table) $ri]
    while {[llength $row] <= $ci} {lappend row ""}
    lset row $ci $value
    lset currentMatrix(table) $ri $row
}

proc ::GX::DocumentExtractors::_tablePublish {} {
    variable ui
    variable currentMatrix
    variable roi
    if {[catch {
        if {![info exists currentMatrix(table)] || ![llength $currentMatrix(table)]} { error "Extract a table before publishing." }
        set id [_safeId [set $ui(table,outVar)] table.extracted]
        set matrix $currentMatrix(table)
        if {[set $ui(table,headerVar)] && [string trim [$ui(table,title) cget -text]] ne ""} {set matrix [lrange $matrix 1 end]}
        set table [dict create matrix $matrix]
        set schema [::GX::TableExtractorAPIv1::inferSchema $table [dict create first_row_header [set $ui(table,headerVar)]]]
        set columns [dict get $schema columns]; set rows [dict get $schema data_rows]
        if {![llength $rows] || ![llength $columns]} { error "The table has no publishable data rows." }
        set session [_session]; set sourceId [set $ui(table,sourceVar)]
        set definition [dict create dataset_id $id contract table.generic storage csv producer_version 1.0.1 source_dataset_ids [list $sourceId] source "Table Extractor viewer" provenance "TABLE_EXTRACTOR_API_v1 extraction from Dataset $sourceId" replace_owned 1]
        set plan [::GX::datasetPublicationV2Prepare $session viewer.document_extractors $definition]
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        try {
            ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
            set ci 0
            set chunk [dict create]
            foreach col $columns {
                set vid [dict get $col id]
                ::GX::datasetPublicationV2DeclareVariable $writer $vid [dict create name [dict get $col name] dtype [dict get $col dtype] dimension_ids row]
                set values {}; foreach row $rows {lappend values [lindex $row $ci]}
                dict set chunk $vid $values
                incr ci
            }
            ::GX::datasetPublicationV2Append $writer row $chunk
            set result [::GX::datasetPublicationV2Finalize $writer]
        } on error {e o} {
            catch {::GX::datasetPublicationV2Abort $writer}
            return -options $o $e
        }
        set md [dict create table.extraction.api TABLE_EXTRACTOR_API_v1 table.source_dataset_id $sourceId table.source_page [set $ui(table,pageVar)] table.method [_methodValue [set $ui(table,methodVar)]] table.first_row_header [set $ui(table,headerVar)]]
        if {[info exists roi(table)] && [llength $roi(table)]} { dict set md table.source_roi_norm $roi(table) }
        ::GX::datasetMetadataWrite $session $id $md
        set $ui(table,outVar) $id
        ::GX::setStatus "Published table Dataset: $id" 100
    } err]} { tk_messageBox -parent .gxTableExtractor -icon error -title "Table Extractor" -message $err }
}

proc ::GX::DocumentExtractors::_ocrRun {} {
    variable ui
    variable currentOcrText
    if {[catch {
        _activate
        set info [_datasetInfo [set $ui(ocr,sourceVar)]]
        set opts [_commonOptions ocr]
        set contract [dict get $info contract]; set path [dict get $info path]
        if {[::GX::contractSatisfies $contract image.raster]} {
            set layout [::GX::OCRLayoutAPIv1::extractImage $path $opts]
        } else {
            if {[set $ui(ocr,scopeVar)] eq "Document"} {
                set layout [::GX::OCRLayoutAPIv1::extractPdfDocument $path $opts]
            } else {
                set layout [::GX::OCRLayoutAPIv1::extractPdfPage $path [set $ui(ocr,pageVar)] $opts]
            }
        }
        set text [::GX::OCRLayoutAPIv1::toText $layout]
        set currentOcrText(ocr) $text
        set w $ui(ocr,text); $w delete 1.0 end; $w insert 1.0 $text
        ::GX::setStatus "OCR completed: [string length $text] characters." 100
    } err]} { tk_messageBox -parent .gxGenericOcr -icon error -title "Generic OCR" -message $err }
}

proc ::GX::DocumentExtractors::_ocrPublish {} {
    variable ui
    variable currentOcrText
    variable roi
    if {[catch {
        set text [expr {[info exists currentOcrText(ocr)] ? $currentOcrText(ocr) : [$ui(ocr,text) get 1.0 end-1c]}]
        if {[string trim $text] eq ""} { error "Run OCR before publishing." }
        set session [_session]; set sourceId [set $ui(ocr,sourceVar)]
        set id [_safeId [set $ui(ocr,outVar)] ocr.text]
        set ch [file tempfile path]; fconfigure $ch -encoding utf-8 -translation lf; puts -nonewline $ch $text; close $ch
        try {
            set md [dict create document.format "Plain text" text.encoding UTF-8 ocr.engine "OCR_LAYOUT_API_v1" ocr.languages [set $ui(ocr,langVar)] ocr.method [_methodValue [set $ui(ocr,methodVar)]] ocr.source_dataset_id $sourceId ocr.scope [string tolower [set $ui(ocr,scopeVar)]]]
            if {[info exists roi(ocr)] && [llength $roi(ocr)]} { dict set md ocr.source_roi_norm $roi(ocr) }
            set req [dict create dataset_id $id contract document.text format txt source_file $path storage_kind text media_type text/plain producer_version 1.0.1 source_dataset_ids [list $sourceId] source "Generic OCR viewer" provenance "OCR_LAYOUT_API_v1 extraction from Dataset $sourceId" structured_metadata $md replace_owned 1]
            ::GX::datasetFilePublicationPublish $session viewer.document_extractors $req
        } finally { catch {file delete -force -- $path} }
        set $ui(ocr,outVar) $id
        ::GX::setStatus "Published text Dataset: $id" 100
    } err]} { tk_messageBox -parent .gxGenericOcr -icon error -title "Generic OCR" -message $err }
}

proc ::GX::DocumentExtractors::_sourceRow {parent mode} {
    variable ui
    ttk::frame $parent.source
    pack $parent.source -fill x -padx 6 -pady 5
    set ui($mode,sourceVar) ::GX::DocumentExtractors::source_${mode}
    set $ui($mode,sourceVar) ""
    ttk::label $parent.source.l -text "Dataset:"
    ttk::combobox $parent.source.c -state readonly -width 42 -textvariable $ui($mode,sourceVar) -values [_compatibleIds]
    ttk::label $parent.source.pl -text "Page:"
    set ui($mode,pageVar) ::GX::DocumentExtractors::page_${mode}; set $ui($mode,pageVar) 1
    spinbox $parent.source.page -from 1 -to 1 -width 5 -textvariable $ui($mode,pageVar)
    set ui($mode,pageSpin) $parent.source.page
    ttk::button $parent.source.preview -text "Refresh preview" -command [list ::GX::DocumentExtractors::_showPreview $mode]
    ttk::button $parent.source.clear -text "Clear ROI" -command [list ::GX::DocumentExtractors::_clearRoi $mode]
    pack $parent.source.l $parent.source.c $parent.source.pl $parent.source.page $parent.source.preview $parent.source.clear -side left -padx 3
    bind $parent.source.c <<ComboboxSelected>> [list ::GX::DocumentExtractors::_showPreview $mode]
    set ids [_compatibleIds]; if {[llength $ids]} { set $ui($mode,sourceVar) [lindex $ids 0] }
}

proc ::GX::DocumentExtractors::_optionsRow {parent mode} {
    variable ui
    ttk::frame $parent.opts; pack $parent.opts -fill x -padx 6 -pady 3
    set ui($mode,methodVar) ::GX::DocumentExtractors::method_${mode}; set $ui($mode,methodVar) Auto
    set ui($mode,langVar) ::GX::DocumentExtractors::lang_${mode}; set $ui($mode,langVar) eng
    set ui($mode,psmVar) ::GX::DocumentExtractors::psm_${mode}; set $ui($mode,psmVar) 3
    set ui($mode,dpiVar) ::GX::DocumentExtractors::dpi_${mode}; set $ui($mode,dpiVar) 300
    ttk::label $parent.opts.ml -text "Method:"
    ttk::combobox $parent.opts.m -state readonly -width 17 -values {Auto {Native PDF text} OCR} -textvariable $ui($mode,methodVar)
    ttk::label $parent.opts.ll -text "Languages:"
    ttk::entry $parent.opts.lang -width 16 -textvariable $ui($mode,langVar)
    ttk::label $parent.opts.psml -text "PSM:"
    ttk::combobox $parent.opts.psm -state readonly -width 4 -values {3 6 7 11} -textvariable $ui($mode,psmVar)
    ttk::label $parent.opts.dpil -text "DPI:"
    ttk::combobox $parent.opts.dpi -state readonly -width 5 -values {150 200 300 400 600} -textvariable $ui($mode,dpiVar)
    pack $parent.opts.ml $parent.opts.m $parent.opts.ll $parent.opts.lang $parent.opts.psml $parent.opts.psm $parent.opts.dpil $parent.opts.dpi -side left -padx 3
}

proc ::GX::DocumentExtractors::_canvas {parent mode} {
    variable ui
    ttk::frame $parent.view; pack $parent.view -fill both -expand 1 -padx 6 -pady 4
    canvas $parent.view.c -background #303030 -height 420 -highlightthickness 0
    ttk::scrollbar $parent.view.sy -orient vertical -command [list $parent.view.c yview]
    ttk::scrollbar $parent.view.sx -orient horizontal -command [list $parent.view.c xview]
    $parent.view.c configure -yscrollcommand [list $parent.view.sy set] -xscrollcommand [list $parent.view.sx set]
    grid $parent.view.c -row 0 -column 0 -sticky nsew; grid $parent.view.sy -row 0 -column 1 -sticky ns; grid $parent.view.sx -row 1 -column 0 -sticky ew
    grid rowconfigure $parent.view 0 -weight 1; grid columnconfigure $parent.view 0 -weight 1
    set ui($mode,canvas) $parent.view.c
    bind $parent.view.c <ButtonPress-1> [list ::GX::DocumentExtractors::_roiStart $mode %x %y]
    bind $parent.view.c <B1-Motion> [list ::GX::DocumentExtractors::_roiDrag $mode %x %y]
    bind $parent.view.c <ButtonRelease-1> [list ::GX::DocumentExtractors::_roiEnd $mode %x %y]
}

proc ::GX::DocumentExtractors::_openTable {} {
    variable ui
    _activate; _session
    set w .gxTableExtractor
    if {[winfo exists $w]} {raise $w; focus $w; return [dict create status focused]}
    toplevel $w; wm title $w "GX-TXT Table Extractor"; wm geometry $w 1500x900
    _sourceRow $w table; _optionsRow $w table; _canvas $w table
    ttk::frame $w.actions; pack $w.actions -fill x -padx 6 -pady 4
    set ui(table,expectedVar) ::GX::DocumentExtractors::expected_table; set $ui(table,expectedVar) 0
    set ui(table,headerVar) ::GX::DocumentExtractors::header_table; set $ui(table,headerVar) 1
    set ui(table,outVar) ::GX::DocumentExtractors::out_table; set $ui(table,outVar) table.extracted
    ttk::label $w.actions.el -text "Expected columns (0=auto):"; spinbox $w.actions.e -from 0 -to 100 -width 5 -textvariable $ui(table,expectedVar)
    ttk::checkbutton $w.actions.h -text "First row is header" -variable $ui(table,headerVar) -command ::GX::DocumentExtractors::_tableRenderMatrix
    ttk::button $w.actions.extract -text "Extract table" -command ::GX::DocumentExtractors::_tableExtract
    ttk::label $w.actions.ol -text "Output Dataset ID:"; ttk::entry $w.actions.o -width 28 -textvariable $ui(table,outVar)
    ttk::button $w.actions.pub -text "Publish table.generic" -command ::GX::DocumentExtractors::_tablePublish
    pack $w.actions.el $w.actions.e $w.actions.h $w.actions.extract $w.actions.ol $w.actions.o $w.actions.pub -side left -padx 4
    ttk::label $w.tableTitle -text "" -font {TkDefaultFont 10 bold} -anchor w
    pack $w.tableTitle -fill x -padx 8
    set ui(table,title) $w.tableTitle
    ttk::frame $w.table; pack $w.table -fill both -expand 1 -padx 6 -pady 4
    ttk::treeview $w.table.t -show headings; ttk::scrollbar $w.table.sy -orient vertical -command [list $w.table.t yview]; ttk::scrollbar $w.table.sx -orient horizontal -command [list $w.table.t xview]
    $w.table.t configure -yscrollcommand [list $w.table.sy set] -xscrollcommand [list $w.table.sx set]
    grid $w.table.t -row 0 -column 0 -sticky nsew; grid $w.table.sy -row 0 -column 1 -sticky ns; grid $w.table.sx -row 1 -column 0 -sticky ew
    grid rowconfigure $w.table 0 -weight 1; grid columnconfigure $w.table 0 -weight 1
    set ui(table,tree) $w.table.t
    bind $w.table.t <Double-1> {::GX::DocumentExtractors::_tableBeginEdit %x %y}
    wm protocol $w WM_DELETE_WINDOW {::GX::DocumentExtractors::_cleanupPreview table; destroy .gxTableExtractor}
    if {[llength [_compatibleIds]]} { after 20 {::GX::DocumentExtractors::_showPreview table} }
    return [dict create status opened]
}

proc ::GX::DocumentExtractors::_openOcr {} {
    variable ui
    variable ocrZoom
    _activate; _session
    set w .gxGenericOcr
    if {[winfo exists $w]} {raise $w; focus $w; return [dict create status focused]}
    toplevel $w; wm title $w "GX-TXT Generic OCR"; wm geometry $w 1150x850
    _sourceRow $w ocr; _optionsRow $w ocr
    ttk::panedwindow $w.split -orient vertical
    pack $w.split -fill both -expand 1
    ttk::frame $w.split.preview
    ttk::frame $w.split.output
    $w.split add $w.split.preview -weight 1
    $w.split add $w.split.output -weight 1
    ttk::frame $w.split.preview.tools
    pack $w.split.preview.tools -fill x -padx 6 -pady 2
    set ocrZoom(ocr) 1.0
    ttk::button $w.split.preview.tools.fit -text "Fit page" -command ::GX::DocumentExtractors::_ocrFit
    ttk::button $w.split.preview.tools.out -text "−" -command [list ::GX::DocumentExtractors::_ocrZoomBy 0.8]
    ttk::scale $w.split.preview.tools.scale -from 0.01 -to 8.0 -variable ::GX::DocumentExtractors::ocrZoom(ocr) -command ::GX::DocumentExtractors::_ocrZoomSchedule
    ttk::button $w.split.preview.tools.in -text "+" -command [list ::GX::DocumentExtractors::_ocrZoomBy 1.25]
    ttk::label $w.split.preview.tools.value -text "100%" -width 6
    set ui(ocr,zoomLabel) $w.split.preview.tools.value
    set ui(ocr,imageOutVar) ::GX::DocumentExtractors::image_out_ocr
    set $ui(ocr,imageOutVar) ocr.region
    ttk::label $w.split.preview.tools.idlabel -text "Image Dataset ID:"
    ttk::entry $w.split.preview.tools.id -width 20 -textvariable $ui(ocr,imageOutVar)
    ttk::button $w.split.preview.tools.acquire -text "Acquire ROI image" -command ::GX::DocumentExtractors::_ocrAcquire
    pack $w.split.preview.tools.fit $w.split.preview.tools.out $w.split.preview.tools.scale $w.split.preview.tools.in $w.split.preview.tools.value $w.split.preview.tools.idlabel $w.split.preview.tools.id $w.split.preview.tools.acquire -side left -padx 3
    _canvas $w.split.preview ocr
    set c $ui(ocr,canvas)
    bind $c <ButtonPress-2> [list $c scan mark %x %y]
    bind $c <B2-Motion> [list $c scan dragto %x %y 1]
    bind $c <MouseWheel> {::GX::DocumentExtractors::_ocrWheel [expr {-%D/120}] 0}
    bind $c <Shift-MouseWheel> {::GX::DocumentExtractors::_ocrWheel [expr {-%D/120}] 1}
    bind $c <Button-4> {::GX::DocumentExtractors::_ocrWheel -3 0}
    bind $c <Button-5> {::GX::DocumentExtractors::_ocrWheel 3 0}
    set actions $w.split.output.actions
    ttk::frame $actions; pack $actions -fill x -padx 6 -pady 4
    set ui(ocr,scopeVar) ::GX::DocumentExtractors::scope_ocr; set $ui(ocr,scopeVar) Page
    set ui(ocr,outVar) ::GX::DocumentExtractors::out_ocr; set $ui(ocr,outVar) ocr.text
    ttk::label $actions.sl -text "Scope:"; ttk::combobox $actions.s -state readonly -width 10 -values {Page Document} -textvariable $ui(ocr,scopeVar)
    ttk::button $actions.run -text "Run OCR" -command ::GX::DocumentExtractors::_ocrRun
    ttk::label $actions.ol -text "Output Dataset ID:"; ttk::entry $actions.o -width 30 -textvariable $ui(ocr,outVar)
    ttk::button $actions.pub -text "Publish document.text" -command ::GX::DocumentExtractors::_ocrPublish
    pack $actions.sl $actions.s $actions.run $actions.ol $actions.o $actions.pub -side left -padx 4
    set textFrame $w.split.output.text
    ttk::frame $textFrame; pack $textFrame -fill both -expand 1 -padx 6 -pady 4
    text $textFrame.t -wrap word; ttk::scrollbar $textFrame.sy -orient vertical -command [list $textFrame.t yview]; $textFrame.t configure -yscrollcommand [list $textFrame.sy set]
    pack $textFrame.sy -side right -fill y; pack $textFrame.t -side left -fill both -expand 1
    set ui(ocr,text) $textFrame.t
    wm protocol $w WM_DELETE_WINDOW {::GX::DocumentExtractors::_cleanupPreview ocr; destroy .gxGenericOcr}
    if {[llength [_compatibleIds]]} { after 20 {::GX::DocumentExtractors::_showPreview ocr} }
    return [dict create status opened]
}

proc ::GX::DocumentExtractors::ocrDispatch {action scene} {
    switch -- $action { open - rerender {return [_openOcr]} default {error "Unsupported Generic OCR action '$action'."} }
}
proc ::GX::DocumentExtractors::tableDispatch {action scene} {
    switch -- $action { open - rerender {return [_openTable]} default {error "Unsupported Table Extractor action '$action'."} }
}

::GX::viewerBackendRegister document_ocr_tk ::GX::DocumentExtractors::ocrDispatch
::GX::viewerBackendRegister document_table_tk ::GX::DocumentExtractors::tableDispatch
