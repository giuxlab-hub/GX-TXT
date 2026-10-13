# GX-TXT Table Extractor backend API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::TableExtractor {
    variable version 1.0.1
    variable moduleId viewer.table_extractor
    variable providerId table_extractor
    variable processChannel ""
    variable processPid ""
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
}

proc ::GX::TableExtractor::_b64e {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}
proc ::GX::TableExtractor::_b64d {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}
proc ::GX::TableExtractor::_record {kind args} {
    set fields [list $kind]
    foreach arg $args { lappend fields [_b64e $arg] }
    return [join $fields "\t"]
}
proc ::GX::TableExtractor::_send {channel requestId status payload} {
    puts $channel [join [list RES $requestId $status [_b64e $payload]] "\t"]
    flush $channel
}
proc ::GX::TableExtractor::_dictDefault {d key default} {
    return [expr {[dict exists $d $key] ? [dict get $d $key] : $default}]
}
proc ::GX::TableExtractor::_requireSession {} {
    return [::GX::sessionInspectionCurrentSession]
}
proc ::GX::TableExtractor::_eligibleContract {contract} {
    foreach wanted {image.raster document.pdf} {
        if {![catch {::GX::contractSatisfies $contract $wanted} ok] && $ok} { return 1 }
    }
    return 0
}
proc ::GX::TableExtractor::_datasetInfo {datasetId} {
    set session [_requireSession]
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set contract [_dictDefault $ds contract [_dictDefault $ds kind ""]]
    if {![_eligibleContract $contract]} {
        error "Dataset '$datasetId' must satisfy image.raster or document.pdf."
    }
    set payload [::GX::sessionInspectionDatasetPayload $datasetId $session]
    set path [dict get $payload path]
    set actualSha [dict get $payload sha256]
    set metadata [dict create]
    if {[llength [info commands ::GX::datasetMetadataRead]]} {
        if {[catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}]} { set metadata [dict create] }
    }
    return [dict create id $datasetId path $path contract $contract format [_dictDefault $ds format ""] media_type [_dictDefault $ds media_type ""] sha256 $actualSha metadata $metadata]
}
proc ::GX::TableExtractor::_eligibleDatasetIds {} {
    set session [_requireSession]
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds $session] {
        if {[catch {set ds [::GX::sessionInspectionDataset $id $session]}]} continue
        set contract [_dictDefault $ds contract [_dictDefault $ds kind ""]]
        if {[_eligibleContract $contract]} { lappend out $id }
    }
    return [lsort -dictionary $out]
}
proc ::GX::TableExtractor::_bootstrap {} {
    set lines [list [_record SESSION [::GX::interactiveDocumentSessionToken]]]
    foreach id [_eligibleDatasetIds] {
        set info [_datasetInfo $id]
        set title ""
        set metadata [dict get $info metadata]
        foreach key {dataset.display_name document.title pdf.title image.description} {
            if {$title eq "" && [dict exists $metadata $key]} { set title [dict get $metadata $key] }
        }
        lappend lines [_record DATASET $id [dict get $info contract] [dict get $info format] [dict get $info media_type] [dict get $info sha256] $title]
    }
    foreach item [::GX::interactiveDocumentList viewer.table_extractor table_extractor] {
        set id [dict get $item id]
        set full [::GX::interactiveDocumentRead $id]
        lappend lines [_record DOCUMENT $id [dict get $full payload] [dict get $full updated_at]]
    }
    return [join $lines "\n"]
}
proc ::GX::TableExtractor::_sourcePayload {datasetId} {
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
proc ::GX::TableExtractor::_documentCreate {payload} {
    set result [::GX::interactiveDocumentCreate viewer.table_extractor table_extractor gxtxt.table_extractor.workspace 1.0 $payload]
    return [dict get $result id]
}
proc ::GX::TableExtractor::_documentUpdate {documentId payload sessionToken} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this Table Extractor window is stale." }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne "viewer.table_extractor" || [dict get $full provider_id] ne "table_extractor"} {
        error "Interactive Document '$documentId' is not owned by Table Extractor."
    }
    set result [::GX::interactiveDocumentUpdate $documentId $payload gxtxt.table_extractor.workspace 1.0]
    return [dict get $result id]
}
proc ::GX::TableExtractor::_documentDelete {documentId sessionToken} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this Table Extractor window is stale." }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne "viewer.table_extractor" || [dict get $full provider_id] ne "table_extractor"} {
        error "Interactive Document '$documentId' is not owned by Table Extractor."
    }
    return [::GX::interactiveDocumentDelete $documentId]
}
proc ::GX::TableExtractor::_parseTablePayload {payload} {
    set columns {}
    set rows {}
    foreach line [split $payload "\n"] {
        if {$line eq ""} continue
        set fields [split $line "\t"]
        set kind [lindex $fields 0]
        switch -- $kind {
            COL {
                if {[llength $fields] != 4} { error "Malformed Table Extractor column record." }
                set id [_b64d [lindex $fields 1]]
                set label [_b64d [lindex $fields 2]]
                set dtype [_b64d [lindex $fields 3]]
                if {$dtype ni {int64 float64 string}} { error "Unsupported Table Extractor column dtype '$dtype'." }
                lappend columns [dict create id $id label $label dtype $dtype]
            }
            ROW {
                set row {}
                foreach encoded [lrange $fields 1 end] { lappend row [_b64d $encoded] }
                lappend rows $row
            }
            default { error "Unknown Table Extractor table record '$kind'." }
        }
    }
    if {[llength $columns] == 0} { error "The extracted table has no columns." }
    if {[llength $rows] == 0} { error "The extracted table has no data rows." }
    set expected [llength $columns]
    set seen {}
    foreach col $columns {
        set id [dict get $col id]
        ::GX::datasetPublicationV2ValidateId variable $id
        if {$id in $seen} { error "Duplicate output variable ID '$id'." }
        lappend seen $id
    }
    foreach row $rows {
        if {[llength $row] != $expected} { error "Extracted table rows do not all have $expected columns." }
    }
    return [dict create columns $columns rows $rows]
}
proc ::GX::TableExtractor::_schemaEnhance {datasetId columns} {
    set changes [dict create]
    foreach col $columns {
        dict set changes [dict get $col id] [dict create display_label [dict get $col label] semantic_source plugin]
    }
    ::GX::datasetVariableSchemaUpdate $datasetId $changes
}
proc ::GX::TableExtractor::_publishTable {args} {
    variable version
    if {[llength $args] != 13} { error "Invalid Table Extractor publication request." }
    lassign $args sessionToken datasetId displayName sourceDataset sourceSha extractionMethod page roi languages psm tokenCount firstRowHeader tablePayload
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; publication was not performed." }
    set session [_requireSession]
    set sourceInfo [_datasetInfo $sourceDataset]
    if {[string tolower [dict get $sourceInfo sha256]] ne [string tolower $sourceSha]} {
        error "The source Dataset changed after extraction; publication was refused."
    }
    set table [_parseTablePayload $tablePayload]
    set columns [dict get $table columns]
    set rows [dict get $table rows]
    set provenance "Table Extractor; source Dataset $sourceDataset; source SHA-256 $sourceSha; method $extractionMethod; page $page; ROI $roi"
    set definition [dict create dataset_id $datasetId contract table.generic storage csv replace_owned 1 producer_version $version source "Table Extractor" provenance $provenance notes $displayName source_dataset_ids [list $sourceDataset]]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.table_extractor $definition]
    set writer ""
    if {[catch {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach col $columns {
            set id [dict get $col id]
            set dtype [dict get $col dtype]
            set spec [dict create name $id unit "" semantic_role "" dtype $dtype rank 1 dimension_ids row coordinate_role data axis_kind explicit]
            ::GX::datasetPublicationV2DeclareVariable $writer $id $spec
        }
        set appendData [dict create]
        set colCount [llength $columns]
        for {set ci 0} {$ci < $colCount} {incr ci} {
            set id [dict get [lindex $columns $ci] id]
            set values {}
            foreach row $rows { lappend values [lindex $row $ci] }
            dict set appendData $id $values
        }
        set appended [::GX::datasetPublicationV2Append $writer row $appendData]
        if {$appended != [llength $rows]} { error "Dataset Publication API appended $appended rows; expected [llength $rows]." }
        set result [::GX::datasetPublicationV2Finalize $writer]
    } failure options]} {
        if {$writer ne ""} { catch {::GX::datasetPublicationV2Abort $writer} }
        return -options $options $failure
    }
    _schemaEnhance $datasetId $columns
    set metadata [dict create \
        dataset.display_name $displayName \
        table_extractor.plugin_id viewer.table_extractor \
        table_extractor.plugin_version $version \
        table_extractor.source_dataset_id $sourceDataset \
        table_extractor.source_sha256 $sourceSha \
        table_extractor.source_contract [dict get $sourceInfo contract] \
        table_extractor.extraction_method $extractionMethod \
        table_extractor.source_page $page \
        table_extractor.source_roi_px $roi \
        table_extractor.ocr_languages $languages \
        table_extractor.ocr_psm $psm \
        table_extractor.layout_token_count $tokenCount \
        table_extractor.first_row_header $firstRowHeader \
        table_extractor.row_count [llength $rows] \
        table_extractor.column_count [llength $columns] \
        table_extractor.publication_timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]]
    ::GX::datasetMetadataWrite $session $datasetId $metadata
    return [join [list [dict get $result dataset_id] [dict get $result path] [dict get $result sha256] table.generic] "\t"]
}
proc ::GX::TableExtractor::_handleRequest {channel line} {
    set fields [split $line "\t"]
    if {[llength $fields] < 3 || [lindex $fields 0] ne "REQ"} { error "Malformed Table Extractor backend request." }
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
        PUBLISH_TABLE { set payload [_publishTable {*}$args] }
        default { error "Unknown Table Extractor backend request '$command'." }
    }
    return [list $requestId $payload]
}
proc ::GX::TableExtractor::_readable {channel} {
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
proc ::GX::TableExtractor::_pythonExecutable {} {
    foreach candidate {python3 python} {
        set path [auto_execok $candidate]
        if {$path ne ""} { return $path }
    }
    error "Python 3 is required by Table Extractor."
}
proc ::GX::TableExtractor::_dependenciesCheck {python} {
    set missing {}
    if {[catch {exec $python -c {import tkinter; from PIL import Image, ImageTk}} failure]} {
        lappend missing "Python tkinter/Pillow ($failure)"
    }
    foreach command {pdfinfo pdftoppm pdftotext tesseract} {
        if {[auto_execok $command] eq ""} { lappend missing $command }
    }
    if {[llength $missing]} {
        error "Table Extractor dependencies are missing: [join $missing {, }]. See DEPENDENCIES.md."
    }
    return 1
}
proc ::GX::TableExtractor::_launch {} {
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
    set script [file join $moduleRoot python table_extractor.py]
    if {![file isfile $script]} { error "Table Extractor desktop adapter is missing: $script" }
    set pipeline "|[list $python $script]"
    if {[catch {set channel [open $pipeline r+]} failure options]} { return -options $options "Unable to start Table Extractor desktop adapter: $failure" }
    fconfigure $channel -encoding utf-8 -translation lf -buffering line -blocking 0
    set processChannel $channel
    set processPid [pid $channel]
    fileevent $channel readable [list ::GX::TableExtractor::_readable $channel]
    return [dict create status opened pid $processPid]
}
proc ::GX::TableExtractor::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender { return [_launch] }
        default { error "Unsupported Table Extractor action '$action'." }
    }
}

::GX::viewerBackendRegister table_extractor_tk ::GX::TableExtractor::viewerDispatch
