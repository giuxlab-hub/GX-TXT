# GX-TXT Curve Digitalizer Viewer backend API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::CurveDigitizer {
    variable version 1.2.2
    variable moduleId viewer.curve_digitizer
    variable providerId curve_digitizer
    variable processChannel ""
    variable processPid ""
    # Module-local lifecycle state. "opened" means process creation only;
    # READY is emitted by Python after the Tk widgets are actually mapped.
    variable processReady 0
    variable processReadBusy 0
    variable processExitReported 0
    variable diagnosticShown 0
    variable pollTimer ""
    variable startupTimer ""
    variable hostLogPath ""
    variable pythonLogPath ""
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
}

proc ::GX::CurveDigitizer::_b64e {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}
proc ::GX::CurveDigitizer::_b64d {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}
proc ::GX::CurveDigitizer::_record {kind args} {
    set fields [list $kind]
    foreach arg $args { lappend fields [_b64e $arg] }
    return [join $fields "\t"]
}
proc ::GX::CurveDigitizer::_send {channel requestId status payload} {
    puts $channel [join [list RES $requestId $status [_b64e $payload]] "\t"]
    flush $channel
}
proc ::GX::CurveDigitizer::_requireSession {} {
    return [::GX::sessionInspectionCurrentSession]
}
proc ::GX::CurveDigitizer::_imageDatasetIds {} {
    set session [_requireSession]
    set out {}
    foreach id [::GX::sessionInspectionDatasetIds $session] {
        set record [::GX::sessionInspectionDataset $id $session]
        set contract [string trim [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]]
        set media [string tolower [string trim [expr {[dict exists $record media_type] ? [dict get $record media_type] : ""}]]]
        if {$contract eq "image.raster" || [string match "image/*" $media]} { lappend out $id }
    }
    return [lsort -dictionary $out]
}
proc ::GX::CurveDigitizer::_sourceInfo {datasetId} {
    set session [_requireSession]
    set record [::GX::sessionInspectionDataset $datasetId $session]
    set contract [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]
    set media [string tolower [expr {[dict exists $record media_type] ? [dict get $record media_type] : ""}]]
    if {$contract ne "image.raster" && ![string match "image/*" $media]} { error "Dataset '$datasetId' is not a compatible Image Dataset." }
    # The GUI must still report a changed source as STALE SOURCE. Resolve its
    # Session file safely, then retain both measured and registered digests.
    set payload [::GX::sessionInspectionResolveResource [dict get $record path] $session]
    set path [dict get $payload path]
    set sha [dict get $payload sha256]
    set registeredSha [dict get $record canonical_sha256]
    set format [dict get $record format]
    set metadata [dict create]
    if {[llength [info commands ::GX::datasetMetadataRead]]} {
        if {[catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}]} { set metadata [dict create] }
    }
    return [dict create id $datasetId path $path sha256 $sha registered_sha256 $registeredSha contract $contract media_type $media format $format metadata $metadata]
}
proc ::GX::CurveDigitizer::_bootstrap {} {
    set session [_requireSession]
    set lines [list [_record SESSION [::GX::interactiveDocumentSessionToken]]]
    foreach unit [::GX::unitRegistryList] { lappend lines [_record UNIT $unit] }
    foreach role [::GX::semanticRegistryList] { lappend lines [_record ROLE $role] }
    foreach id [_imageDatasetIds] {
        _log "Bootstrap: checking Image Dataset $id"
        set info [_sourceInfo $id]
        lappend lines [_record DATASET $id [dict get $info contract] [dict get $info format] [dict get $info media_type] [dict get $info sha256]]
    }
    foreach item [::GX::interactiveDocumentList viewer.curve_digitizer curve_digitizer] {
        set id [dict get $item id]
        _log "Bootstrap: reading configuration $id"
        set full [::GX::interactiveDocumentRead $id]
        lappend lines [_record DOCUMENT $id [dict get $full payload] [dict get $full updated_at] [dict get $full sha256]]
    }
    return [join $lines "\n"]
}
proc ::GX::CurveDigitizer::_sourcePayload {datasetId} {
    set info [_sourceInfo $datasetId]
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
proc ::GX::CurveDigitizer::_documentCreate {payload} {
    set result [::GX::interactiveDocumentCreate viewer.curve_digitizer curve_digitizer gxtxt.curve_digitizer.configuration 1.0 $payload]
    return "[dict get $result id]	[dict get $result sha256]"
}
proc ::GX::CurveDigitizer::_documentUpdate {documentId payload sessionToken {expectedSha ""}} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this Curve Digitalizer window is stale." }
    if {[string trim $expectedSha] ne ""} {
        set current [::GX::interactiveDocumentRead $documentId]
        if {[string tolower [dict get $current sha256]] ne [string tolower [string trim $expectedSha]]} {
            error "This Curve Digitalizer configuration changed outside this window. Reload it before saving to avoid overwriting newer scientific state."
        }
    }
    set result [::GX::interactiveDocumentUpdate $documentId $payload gxtxt.curve_digitizer.configuration 1.0]
    return "[dict get $result id]	[dict get $result sha256]"
}
proc ::GX::CurveDigitizer::_documentDelete {documentId sessionToken} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; this Curve Digitalizer window is stale." }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne "viewer.curve_digitizer" || [dict get $full provider_id] ne "curve_digitizer"} { error "Interactive Document '$documentId' is not owned by Curve Digitalizer." }
    return [::GX::interactiveDocumentDelete $documentId]
}
proc ::GX::CurveDigitizer::_cleanSingleLine {value label} {
    set value [string trim $value]
    if {[string first "\n" $value] >= 0 || [string first "\r" $value] >= 0} { error "$label must be a single line." }
    return $value
}
proc ::GX::CurveDigitizer::_parseRows {text familyMode} {
    set curveIds {}; set curveLabels {}; set indices {}; set xs {}; set ys {}; set families {}
    set count 0
    foreach line [split $text "\n"] {
        if {$line eq ""} continue
        set fields [split $line "\t"]
        if {[llength $fields] != 6} { error "Invalid Curve Digitalizer publication row." }
        lassign $fields curve64 label64 index x y family
        set curveId [_b64d $curve64]
        set curveLabel [_b64d $label64]
        if {![string is integer -strict $index] || $index < 0} { error "Invalid point_index '$index'." }
        if {![string is double -strict $x] || ![string is double -strict $y]} { error "Digitized X/Y values must be numeric." }
        if {$familyMode && ![string is double -strict $family]} { error "Every curve must have a numeric family value before curve-family publication." }
        lappend curveIds $curveId; lappend curveLabels $curveLabel; lappend indices $index; lappend xs $x; lappend ys $y
        if {$familyMode} { lappend families $family }
        incr count
    }
    if {$count == 0} { error "There are no calibrated digitized points to publish." }
    return [dict create count $count curve_id $curveIds curve_label $curveLabels point_index $indices x $xs y $ys family_value $families]
}
proc ::GX::CurveDigitizer::_publicationVariable {writer id displayLabel unit role dtype coordRole} {
    # The public variable_id/name remain stable technical identities. Human
    # labels are applied separately through Variable Schema API v3.
    set spec [dict create name $id unit $unit semantic_role $role dtype $dtype rank 1 dimension_ids row coordinate_role $coordRole axis_kind explicit]
    ::GX::datasetPublicationV2DeclareVariable $writer $id $spec
}
proc ::GX::CurveDigitizer::_schemaEnhance {datasetId fields} {
    set changes [dict create]
    dict for {variableId info} $fields {
        set update [dict create display_label [dict get $info label] semantic_source plugin]
        set unit [dict get $info unit]
        if {$unit ne ""} {
            set definition [::GX::unitRegistryDefinition $unit]
            set canonical [dict get $definition canonical_unit]
            if {$canonical ne ""} { dict set update canonical_unit $canonical }
        }
        dict set changes $variableId $update
    }
    ::GX::datasetVariableSchemaUpdate $datasetId $changes
}

proc ::GX::CurveDigitizer::_publish {args} {
    if {[llength $args] != 21} { error "Invalid Curve Digitalizer publication request." }
    lassign $args sessionToken documentId datasetId displayName mode xLabel xUnit xRole yLabel yUnit yRole familyLabel familyUnit familyRole sourceDataset sourceSha calibrationType xScale yScale configName rowsText
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} { error "The GX-TXT Session changed; publication was not performed." }
    set session [_requireSession]
    set datasetId [_cleanSingleLine $datasetId "Output Dataset ID"]
    set displayName [_cleanSingleLine $displayName "Output Dataset name"]
    set configName [_cleanSingleLine $configName "Configuration name"]
    if {$datasetId eq ""} { error "Output Dataset ID is required." }
    set familyMode [expr {$mode eq "family"}]
    if {!$familyMode && $mode ne "generic"} { error "Publication mode must be generic or family." }
    set sourceInfo [_sourceInfo $sourceDataset]
    if {[string tolower [dict get $sourceInfo sha256]] ne [string tolower $sourceSha]} { error "The source image payload changed after this configuration was calibrated. Create a new configuration or explicitly reset it before publication." }
    set rows [_parseRows $rowsText $familyMode]
    set contract [expr {$familyMode ? "curve_family.table" : "table.generic"}]
    set provenance "Curve Digitalizer configuration $documentId; source Dataset $sourceDataset; source SHA-256 $sourceSha; calibration $calibrationType; X scale $xScale; Y scale $yScale"
    set definition [dict create dataset_id $datasetId contract $contract storage csv replace_owned 1 producer_version 1.2.2 source "Curve Digitalizer: $configName" provenance $provenance notes $displayName source_dataset_ids [list $sourceDataset]]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.curve_digitizer $definition]
    set writer ""
    if {[catch {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        set n [dict get $rows count]
        # CSV tables are written through the sequential append path required by
        # Dataset Publication API v2. The extendible row dimension is grown once
        # with all columns, preserving the user's original point order.
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        _publicationVariable $writer x $xLabel $xUnit $xRole float64 coordinate
        if {$familyMode} { _publicationVariable $writer family_value $familyLabel $familyUnit $familyRole float64 auxiliary }
        _publicationVariable $writer y $yLabel $yUnit $yRole float64 data
        _publicationVariable $writer curve_id "Curve ID" "" identifier string auxiliary
        _publicationVariable $writer curve_label "Curve label" "" category string auxiliary
        _publicationVariable $writer point_index "Point index" "" index int64 auxiliary
        set appendData [dict create x [dict get $rows x] y [dict get $rows y] curve_id [dict get $rows curve_id] curve_label [dict get $rows curve_label] point_index [dict get $rows point_index]]
        if {$familyMode} { dict set appendData family_value [dict get $rows family_value] }
        set appended [::GX::datasetPublicationV2Append $writer row $appendData]
        if {$appended != $n} { error "Dataset Publication API appended $appended rows; expected $n." }
        set result [::GX::datasetPublicationV2Finalize $writer]
    } failure options]} {
        if {$writer ne ""} { catch {::GX::datasetPublicationV2Abort $writer} }
        return -options $options $failure
    }
    set schemaFields [dict create \
        x [dict create label $xLabel unit $xUnit] \
        y [dict create label $yLabel unit $yUnit] \
        curve_id [dict create label "Curve ID" unit ""] \
        curve_label [dict create label "Curve label" unit ""] \
        point_index [dict create label "Point index" unit ""]]
    if {$familyMode} { dict set schemaFields family_value [dict create label $familyLabel unit $familyUnit] }
    _schemaEnhance $datasetId $schemaFields

    set metadata [dict create \
        dataset.display_name $displayName \
        curve_digitizer.plugin_id viewer.curve_digitizer \
        curve_digitizer.plugin_version 1.2.2 \
        curve_digitizer.configuration_document_id $documentId \
        curve_digitizer.configuration_name $configName \
        curve_digitizer.source_dataset_id $sourceDataset \
        curve_digitizer.source_sha256 $sourceSha \
        curve_digitizer.calibration_type $calibrationType \
        curve_digitizer.x_scale $xScale \
        curve_digitizer.y_scale $yScale \
        curve_digitizer.x_label $xLabel \
        curve_digitizer.x_unit $xUnit \
        curve_digitizer.y_label $yLabel \
        curve_digitizer.y_unit $yUnit \
        curve_digitizer.publication_contract $contract \
        curve_digitizer.publication_timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]]
    if {$familyMode} {
        dict set metadata curve_digitizer.family_label $familyLabel
        dict set metadata curve_digitizer.family_unit $familyUnit
    }
    ::GX::datasetMetadataWrite $session $datasetId $metadata
    return [join [list [dict get $result dataset_id] [dict get $result path] [dict get $result sha256] $contract] "\t"]
}
proc ::GX::CurveDigitizer::_handleRequest {channel line} {
    set fields [split $line "\t"]
    if {[llength $fields] < 3 || [lindex $fields 0] ne "REQ"} { error "Malformed Curve Digitalizer backend request." }
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
            if {[llength $args] ni {3 4}} { error "DOC_UPDATE requires document ID, payload, Session token and optional expected document SHA-256." }
            set expectedSha [expr {[llength $args] == 4 ? [lindex $args 3] : ""}]
            set payload [_documentUpdate [lindex $args 0] [lindex $args 1] [lindex $args 2] $expectedSha]
        }
        DOC_DELETE {
            if {[llength $args] != 2} { error "DOC_DELETE requires document ID and Session token." }
            set payload [_documentDelete [lindex $args 0] [lindex $args 1]]
        }
        PUBLISH { set payload [_publish {*}$args] }
        default { error "Unknown Curve Digitalizer backend request '$command'." }
    }
    return [list $requestId $payload]
}
# Startup repair r2: diagnostics and transport lifecycle remain in this module.
# No CORE procedure is replaced. Protocol arguments remain base64-encoded UTF-8.
proc ::GX::CurveDigitizer::_log {message} {
    variable hostLogPath
    if {$hostLogPath eq ""} { return }
    # A diagnostics-write failure must not abort a scientific RPC transaction.
    catch {
        set f [open $hostLogPath a]
        try {
            fconfigure $f -encoding utf-8 -translation lf
            puts $f "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $message"
        } finally { close $f }
    }
}
proc ::GX::CurveDigitizer::_showFailure {message} {
    variable diagnosticShown
    variable hostLogPath
    variable pythonLogPath
    if {$diagnosticShown} { return }
    set diagnosticShown 1
    _log "ERROR: $message"
    set detail "Host log: $hostLogPath\nPython log: $pythonLogPath"
    if {[llength [info commands ::tk_messageBox]]} {
        ::tk_messageBox -title "GX-TXT Curve Digitalizer" -icon error -type ok -message $message -detail $detail
    } else {
        puts stderr "$message\n$detail"
    }
}
proc ::GX::CurveDigitizer::_disconnect {channel} {
    variable processChannel
    variable processPid
    variable processReady
    variable pollTimer
    variable startupTimer
    catch {fileevent $channel readable {}}
    catch {close $channel}
    if {$processChannel eq $channel} {
        foreach timer [list $pollTimer $startupTimer] {
            if {$timer ne ""} { after cancel $timer }
        }
        set processChannel ""; set processPid ""; set processReady 0
        set pollTimer ""; set startupTimer ""
    }
}
proc ::GX::CurveDigitizer::_drain {channel} {
    variable processReady
    variable processExitReported
    variable startupTimer
    # Bound the work per event. Read to the current buffer boundary, rather
    # than relying on one new OS pipe notification for every queued line.
    for {set i 0} {$i < 16} {incr i} {
        if {[gets $channel line] < 0} {
            if {[eof $channel]} {
                set premature [expr {!$processReady && !$processExitReported}]
                _log "Child pipe reached EOF (ready=$processReady)."
                _disconnect $channel
                if {$premature} {
                    _showFailure "Curve Digitalizer exited before its window became ready. See the Python log for the startup error."
                }
            }
            return
        }
        # Only remove a frame terminator, never whitespace inside arguments.
        set line [string trimright $line "\r"]
        if {$line eq ""} { continue }
        set fields [split $line "\t"]
        if {[lindex $fields 0] eq "EVT"} {
            set event [lindex $fields 1]
            switch -- $event {
                READY {
                    set processReady 1
                    if {$startupTimer ne ""} { after cancel $startupTimer; set startupTimer "" }
                    _log "GUI READY: widgets created and window mapped."
                }
                FOCUSED { _log "GUI acknowledged FOCUS." }
                FAILED { set processExitReported 1; _log "GUI reported initialization failure; see Python log." }
                CLOSED { set processExitReported 1; _log "GUI closed normally (including startup cancellation)." }
                STARTING { _log "Python process entered GUI startup." }
                default { _log "Unknown child lifecycle event: $event" }
            }
            continue
        }
        set requestId [expr {[llength $fields] >= 2 ? [lindex $fields 1] : "0"}]
        _log "RPC begin id=$requestId command=[lindex $fields 2]"
        if {[catch {lassign [_handleRequest $channel $line] requestId payload} failure options]} {
            _log "RPC failed id=$requestId: [dict get $options -errorinfo]"
            _send $channel $requestId ERR $failure
        } else {
            _send $channel $requestId OK $payload
            _log "RPC response queued id=$requestId characters=[string length $payload]"
        }
    }
}
proc ::GX::CurveDigitizer::_readable {channel} {
    variable processChannel
    variable processReadBusy
    if {$channel ne $processChannel || $processReadBusy} { return }
    set processReadBusy 1
    try {
        if {[catch {_drain $channel} failure options]} {
            # Uncaught fileevent errors remove the handler. Never leave Python
            # silently waiting for a reply on an abandoned connection.
            _log "Transport failure: [dict get $options -errorinfo]"
            _disconnect $channel
            _showFailure "Curve Digitalizer communication failed: $failure"
        }
    } finally { set processReadBusy 0 }
}
proc ::GX::CurveDigitizer::_pollChannel {channel} {
    variable processChannel
    variable pollTimer
    set pollTimer ""
    if {$channel ne $processChannel} { return }
    _readable $channel
    if {$channel eq $processChannel} {
        set pollTimer [after 100 [list ::GX::CurveDigitizer::_pollChannel $channel]]
    }
}
proc ::GX::CurveDigitizer::_startupCheck {channel} {
    variable processChannel
    variable processReady
    variable startupTimer
    set startupTimer ""
    if {$channel eq $processChannel && !$processReady} {
        _showFailure "Curve Digitalizer started, but its window did not become ready within 60 seconds. Inspect the startup logs; process creation alone does not confirm a working viewer."
    }
}
proc ::GX::CurveDigitizer::_pythonExecutable {} {
    # Respect the same Python runtime selected in Configuration > Runtime.
    # Resolver results can be a literal path or auto_execok's command list.
    if {[llength [info commands ::GX::runtimeToolRequired]]} {
        set resolved [::GX::runtimeToolRequired python]
        if {[file isfile $resolved]} { return [list $resolved] }
        return $resolved
    }
    foreach candidate {python3 python} {
        set resolved [auto_execok $candidate]
        if {$resolved ne ""} { return $resolved }
    }
    error "Python 3 is required by the Curve Digitalizer desktop adapter."
}
proc ::GX::CurveDigitizer::_pythonDependenciesCheck {python} {
    set probe {import sys; assert sys.version_info >= (3, 10), "Python 3.10 or newer is required"; import tkinter; import numpy; from PIL import Image, ImageTk; print(sys.executable); print(sys.version)}
    if {[catch {exec {*}$python -c $probe 2>@1} result]} {
        error "Curve Digitalizer requires Python 3.10 or newer with tkinter, NumPy and Pillow: $result"
    }
    _log "Python dependency check: $result"
    return 1
}
proc ::GX::CurveDigitizer::_launch {} {
    variable processChannel
    variable processPid
    variable moduleRoot
    variable processReady
    variable processExitReported
    variable diagnosticShown
    variable hostLogPath
    variable pythonLogPath
    variable pollTimer
    variable startupTimer
    if {$processChannel ne ""} {
        if {![catch {puts $processChannel "CONTROL\tFOCUS"; flush $processChannel}]} {
            _log "FOCUS requested for existing child (ready=$processReady)."
            return [dict create status focused pid $processPid]
        }
        _disconnect $processChannel
    }
    set session [_requireSession]
    set logDir [file join $session logs]
    file mkdir $logDir
    set hostLogPath [file join $logDir curve_digitizer_host.log]
    set pythonLogPath [file join $logDir curve_digitizer_python.log]
    set diagnosticShown 0; set processReady 0; set processExitReported 0
    _log "--- Curve Digitalizer 1.2.2; Tcl [info patchlevel]; platform=$::tcl_platform(platform) ---"
    set python [_pythonExecutable]
    _log "Python command: $python"
    _pythonDependenciesCheck $python
    set script [file join $moduleRoot python gxtxt_curve_digitizer.py]
    if {![file isfile $script]} { error "Curve Digitalizer desktop adapter is missing: $script" }
    set err [open $pythonLogPath a]
    try {
        fconfigure $err -encoding utf-8 -translation lf
        puts $err "\n--- Curve Digitalizer startup [clock format [clock seconds]] ---"
        flush $err
        # stderr is separate from the protocol: retain import errors, Tk errors
        # and tracebacks even when GX-TXT was launched without a console.
        set pipeline "|[list {*}$python -u $script 2>@ $err]"
        if {[catch {set channel [open $pipeline r+]} failure options]} {
            return -options $options "Unable to start Curve Digitalizer desktop adapter: $failure"
        }
    } finally { close $err }
    # CRLF from Windows and LF from Unix must decode to the same request.
    fconfigure $channel -encoding utf-8 -translation {auto lf} -buffering line -blocking 0
    set processChannel $channel
    set processPid [pid $channel]
    _log "Child created pid=$processPid; waiting for GUI READY."
    fileevent $channel readable [list ::GX::CurveDigitizer::_readable $channel]
    # Nonblocking timer fallback also drains buffered data when OS pipe-event
    # delivery is delayed. It never runs a second reader concurrently.
    set pollTimer [after 100 [list ::GX::CurveDigitizer::_pollChannel $channel]]
    set startupTimer [after 60000 [list ::GX::CurveDigitizer::_startupCheck $channel]]
    return [dict create status opened pid $processPid]
}
proc ::GX::CurveDigitizer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender { return [_launch] }
        default { error "Unsupported Curve Digitalizer viewer action '$action'." }
    }
}

::GX::viewerBackendRegister curve_digitizer_tk ::GX::CurveDigitizer::viewerDispatch
