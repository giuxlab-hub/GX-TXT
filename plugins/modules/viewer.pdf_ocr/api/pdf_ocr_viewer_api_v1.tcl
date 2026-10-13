# GX-TXT PDF OCR Viewer backend API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::PdfOcrViewer {
    variable version 1.0.2
    variable moduleId viewer.pdf_ocr
    variable providerId pdf_ocr
    variable processChannel ""
    variable processPid ""
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
}

proc ::GX::PdfOcrViewer::_b64e {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}
proc ::GX::PdfOcrViewer::_b64d {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}
proc ::GX::PdfOcrViewer::_record {kind args} {
    set fields [list $kind]
    foreach arg $args { lappend fields [_b64e $arg] }
    return [join $fields "\t"]
}
proc ::GX::PdfOcrViewer::_send {channel requestId status payload} {
    puts $channel [join [list RES $requestId $status [_b64e $payload]] "\t"]
    flush $channel
}
proc ::GX::PdfOcrViewer::_requireSession {} {
    return [::GX::sessionInspectionCurrentSession]
}
proc ::GX::PdfOcrViewer::_dictDefault {d key default} {
    return [expr {[dict exists $d $key] ? [dict get $d $key] : $default}]
}
proc ::GX::PdfOcrViewer::_datasetInfo {datasetId} {
    set session [_requireSession]
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set contract [_dictDefault $ds contract [_dictDefault $ds kind ""]]
    if {![::GX::contractSatisfies $contract document.pdf]} {
        error "Dataset '$datasetId' does not satisfy document.pdf."
    }
    set payload [::GX::sessionInspectionDatasetPayload $datasetId $session]
    set path [dict get $payload path]
    set metadata [dict create]
    if {[llength [info commands ::GX::datasetMetadataRead]]} {
        if {[catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}]} { set metadata [dict create] }
    }
    return [dict create \
        id $datasetId path $path contract $contract \
        format [_dictDefault $ds format ""] \
        media_type [_dictDefault $ds media_type ""] \
        sha256 [dict get $payload sha256] \
        metadata $metadata]
}
proc ::GX::PdfOcrViewer::_pdfDatasetIds {} {
    set session [_requireSession]
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds $session] {
        if {[catch {set ds [::GX::sessionInspectionDataset $id $session]}]} continue
        set contract [_dictDefault $ds contract [_dictDefault $ds kind ""]]
        if {![catch {::GX::contractSatisfies $contract document.pdf} ok] && $ok} { lappend out $id }
    }
    return [lsort -dictionary $out]
}
proc ::GX::PdfOcrViewer::_bootstrap {} {
    set lines [list [_record SESSION [::GX::interactiveDocumentSessionToken]]]
    foreach id [_pdfDatasetIds] {
        set info [_datasetInfo $id]
        set title ""
        if {[dict exists [dict get $info metadata] pdf.title]} { set title [dict get [dict get $info metadata] pdf.title] }
        if {$title eq "" && [dict exists [dict get $info metadata] document.title]} { set title [dict get [dict get $info metadata] document.title] }
        set pages ""
        if {[dict exists [dict get $info metadata] document.page_count]} { set pages [dict get [dict get $info metadata] document.page_count] }
        lappend lines [_record DATASET $id [dict get $info contract] [dict get $info format] [dict get $info media_type] [dict get $info sha256] $title $pages]
    }
    foreach item [::GX::interactiveDocumentList viewer.pdf_ocr pdf_ocr] {
        set id [dict get $item id]
        set full [::GX::interactiveDocumentRead $id]
        lappend lines [_record DOCUMENT $id [dict get $full payload] [dict get $full updated_at]]
    }
    return [join $lines "\n"]
}
proc ::GX::PdfOcrViewer::_sourcePayload {datasetId} {
    set info [_datasetInfo $datasetId]
    set lines [list \
        [_record ID [dict get $info id]] \
        [_record PATH [dict get $info path]] \
        [_record SHA256 [dict get $info sha256]] \
        [_record CONTRACT [dict get $info contract]] \
        [_record FORMAT [dict get $info format]] \
        [_record MEDIA_TYPE [dict get $info media_type]]]
    dict for {key value} [dict get $info metadata] { lappend lines [_record METADATA $key $value] }
    return [join $lines "\n"]
}
proc ::GX::PdfOcrViewer::_documentCreate {payload} {
    set result [::GX::interactiveDocumentCreate viewer.pdf_ocr pdf_ocr gxtxt.pdf_ocr.workspace 1.0 $payload]
    return [dict get $result id]
}
proc ::GX::PdfOcrViewer::_documentUpdate {documentId payload sessionToken} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this PDF OCR Viewer window is stale." }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne "viewer.pdf_ocr" || [dict get $full provider_id] ne "pdf_ocr"} { error "Interactive Document '$documentId' is not owned by PDF OCR Viewer." }
    set result [::GX::interactiveDocumentUpdate $documentId $payload gxtxt.pdf_ocr.workspace 1.0]
    return [dict get $result id]
}
proc ::GX::PdfOcrViewer::_documentDelete {documentId sessionToken} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this PDF OCR Viewer window is stale." }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne "viewer.pdf_ocr" || [dict get $full provider_id] ne "pdf_ocr"} { error "Interactive Document '$documentId' is not owned by PDF OCR Viewer." }
    return [::GX::interactiveDocumentDelete $documentId]
}
proc ::GX::PdfOcrViewer::_checkSessionToken {token} {
    if {$token ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; publication was not performed." }
}
proc ::GX::PdfOcrViewer::_publishCommon {datasetId sourceDataset sourceFile contract format storageKind mediaType provenance metadata sessionToken} {
    variable moduleId
    variable version
    _checkSessionToken $sessionToken
    set session [_requireSession]
    _datasetInfo $sourceDataset
    set request [dict create \
        dataset_id $datasetId contract $contract format $format source_file $sourceFile \
        storage_kind $storageKind media_type $mediaType producer_version $version \
        source_dataset_ids [list $sourceDataset] source "PDF OCR Viewer derived output" \
        provenance $provenance structured_metadata $metadata replace_owned 1]
    set result [::GX::datasetFilePublicationPublish $session $moduleId $request]
    return [join [list [dict get $result dataset_id] [dict get $result path] [dict get $result sha256] [dict get $result contract]] "\t"]
}
proc ::GX::PdfOcrViewer::_publishText {datasetId sourceDataset sourceFile languages psm page roi sessionToken} {
    set metadata [dict create \
        document.format "Plain text" text.encoding "UTF-8" \
        ocr.engine "Tesseract" ocr.languages $languages ocr.psm $psm \
        ocr.source_dataset_id $sourceDataset ocr.source_page $page ocr.source_roi_px $roi \
        ocr.plugin_id viewer.pdf_ocr ocr.plugin_version 1.0.2]
    return [_publishCommon $datasetId $sourceDataset $sourceFile document.text txt text text/plain \
        "OCR text derived from Dataset $sourceDataset, page $page, ROI $roi" $metadata $sessionToken]
}
proc ::GX::PdfOcrViewer::_publishImage {datasetId sourceDataset sourceFile page dpi roi width height sessionToken} {
    set metadata [dict create \
        image.format PNG image.width_px $width image.height_px $height \
        image.source_pdf_dataset_id $sourceDataset image.source_page $page image.render_dpi $dpi image.source_roi_px $roi \
        image.derivation "PDF page raster crop" image.plugin_id viewer.pdf_ocr image.plugin_version 1.0.2]
    return [_publishCommon $datasetId $sourceDataset $sourceFile image.raster png binary image/png \
        "Raster crop derived from Dataset $sourceDataset, page $page, DPI $dpi, ROI $roi" $metadata $sessionToken]
}
proc ::GX::PdfOcrViewer::_publishPdf {datasetId sourceDataset sourceFile languages pageCount pdfVersion sessionToken} {
    set metadata [dict create \
        document.format PDF document.page_count $pageCount pdf.ocr true \
        ocr.engine "OCRmyPDF/Tesseract" ocr.languages $languages \
        ocr.source_dataset_id $sourceDataset ocr.plugin_id viewer.pdf_ocr ocr.plugin_version 1.0.2]
    if {[string trim $pdfVersion] ne ""} { dict set metadata pdf.version $pdfVersion }
    return [_publishCommon $datasetId $sourceDataset $sourceFile document.pdf pdf binary application/pdf \
        "OCR PDF derived from Dataset $sourceDataset" $metadata $sessionToken]
}
proc ::GX::PdfOcrViewer::_publishTextDocument {datasetId sourceDataset sourceFile languages psm pageCount dpi sessionToken} {
    set metadata [dict create         document.format "Plain text" text.encoding "UTF-8"         ocr.engine "Tesseract" ocr.languages $languages ocr.psm $psm         ocr.source_dataset_id $sourceDataset ocr.source_scope whole_pdf         ocr.source_page_count $pageCount ocr.render_dpi $dpi ocr.page_separator form_feed         ocr.plugin_id viewer.pdf_ocr ocr.plugin_version 1.0.2]
    return [_publishCommon $datasetId $sourceDataset $sourceFile document.text txt text text/plain         "Whole-document OCR text derived from Dataset $sourceDataset" $metadata $sessionToken]
}
proc ::GX::PdfOcrViewer::_handleRequest {channel line} {
    set fields [split $line "\t"]
    if {[llength $fields] < 3 || [lindex $fields 0] ne "REQ"} { error "Malformed PDF OCR Viewer backend request." }
    set requestId [lindex $fields 1]
    set command [lindex $fields 2]
    set args {}
    foreach encoded [lrange $fields 3 end] { lappend args [_b64d $encoded] }
    set payload ""
    switch -- $command {
        BOOTSTRAP { set payload [_bootstrap] }
        SOURCE {
            if {[llength $args] != 1} { error "SOURCE requires one Dataset ID." }
            set payload [_sourcePayload [lindex $args 0]]
        }
        DOC_CREATE {
            if {[llength $args] != 1} { error "DOC_CREATE requires one payload." }
            set payload [_documentCreate [lindex $args 0]]
        }
        DOC_UPDATE {
            if {[llength $args] != 3} { error "DOC_UPDATE requires document ID, payload and Session token." }
            set payload [_documentUpdate [lindex $args 0] [lindex $args 1] [lindex $args 2]]
        }
        DOC_DELETE {
            if {[llength $args] != 2} { error "DOC_DELETE requires document ID and Session token." }
            set payload [_documentDelete [lindex $args 0] [lindex $args 1]]
        }
        PUBLISH_TEXT {
            if {[llength $args] != 8} { error "PUBLISH_TEXT requires Dataset ID, source Dataset, file, languages, PSM, page, ROI and Session token." }
            set payload [_publishText {*}$args]
        }
        PUBLISH_IMAGE {
            if {[llength $args] != 9} { error "PUBLISH_IMAGE requires Dataset ID, source Dataset, file, page, DPI, ROI, width, height and Session token." }
            set payload [_publishImage {*}$args]
        }
        PUBLISH_PDF {
            if {[llength $args] != 7} { error "PUBLISH_PDF requires Dataset ID, source Dataset, file, languages, page count, PDF version and Session token." }
            set payload [_publishPdf {*}$args]
        }
        PUBLISH_TEXT_DOCUMENT {
            if {[llength $args] != 8} { error "PUBLISH_TEXT_DOCUMENT requires Dataset ID, source Dataset, file, languages, PSM, page count, render DPI and Session token." }
            set payload [_publishTextDocument {*}$args]
        }
        default { error "Unknown PDF OCR Viewer backend request '$command'." }
    }
    return [list $requestId $payload]
}
proc ::GX::PdfOcrViewer::_readable {channel} {
    variable processChannel
    variable processPid
    if {[eof $channel]} {
        catch {close $channel}
        if {$processChannel eq $channel} { set processChannel ""; set processPid "" }
        return
    }
    if {[gets $channel line] < 0} { return }
    if {[catch {lassign [_handleRequest $channel $line] requestId payload} failure options]} {
        set fields [split $line "\t"]
        set requestId [expr {[llength $fields] >= 2 ? [lindex $fields 1] : "0"}]
        catch {_send $channel $requestId ERR $failure}
        return
    }
    _send $channel $requestId OK $payload
}
proc ::GX::PdfOcrViewer::_pythonExecutable {} {
    foreach candidate {python3 python} {
        set path [auto_execok $candidate]
        if {$path ne ""} { return $path }
    }
    error "Python 3 is required by PDF OCR Viewer."
}
proc ::GX::PdfOcrViewer::_dependenciesCheck {python} {
    set missing {}
    if {[catch {exec $python -c {import tkinter; from PIL import Image, ImageTk}} failure]} {
        lappend missing "Python tkinter/Pillow ($failure)"
    }
    foreach command {pdfinfo pdftoppm tesseract ocrmypdf qpdf} {
        if {[auto_execok $command] eq ""} { lappend missing $command }
    }
    if {[llength $missing]} {
        error "PDF OCR Viewer dependencies are missing: [join $missing {, }]. See MANUAL.md for the required packages."
    }
    return 1
}
proc ::GX::PdfOcrViewer::_launch {} {
    variable processChannel
    variable processPid
    variable moduleRoot
    if {$processChannel ne ""} {
        if {![catch {puts $processChannel "CONTROL\tFOCUS"; flush $processChannel}]} { return [dict create status focused pid $processPid] }
        catch {close $processChannel}; set processChannel ""; set processPid ""
    }
    _requireSession
    set python [_pythonExecutable]
    _dependenciesCheck $python
    set script [file join $moduleRoot python pdf_ocr_viewer.py]
    if {![file isfile $script]} { error "PDF OCR Viewer desktop adapter is missing: $script" }
    set pipeline "|[list $python $script --core-python [file join $::GX::scriptDir core python]]"
    if {[catch {set channel [open $pipeline r+]} failure options]} { return -options $options "Unable to start PDF OCR Viewer desktop adapter: $failure" }
    fconfigure $channel -encoding utf-8 -translation lf -buffering line -blocking 0
    set processChannel $channel
    set processPid [pid $channel]
    fileevent $channel readable [list ::GX::PdfOcrViewer::_readable $channel]
    return [dict create status opened pid $processPid]
}
proc ::GX::PdfOcrViewer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender { return [_launch] }
        default { error "Unsupported PDF OCR Viewer action '$action'." }
    }
}

::GX::viewerBackendRegister pdf_ocr_tk ::GX::PdfOcrViewer::viewerDispatch
