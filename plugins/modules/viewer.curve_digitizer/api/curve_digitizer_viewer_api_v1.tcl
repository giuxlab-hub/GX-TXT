# GX-TXT Curve Digitalizer Viewer backend API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::CurveDigitizer {
    variable version 2.0.3
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
    variable imageStages [dict create]
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
# Bridge of Configuration API v1. CORE owns typed validation, scopes,
# persistence, precedence and conflict detection. No plugin preferences file.
proc ::GX::CurveDigitizer::_settingId {key} {
    variable moduleId
    foreach {id descriptor} [::GX::configurationModuleFields $moduleId] {
        if {[dict get $descriptor module_key] eq $key} {return $id}
    }
    error "Curve Digitizer setting '$key' is not registered in GX-TXT Configuration."
}
proc ::GX::CurveDigitizer::_settingsRows {} {
    variable moduleId
    set lines {}
    foreach {id descriptor} [::GX::configurationModuleFields $moduleId] {
        set key [dict get $descriptor module_key]
        set resolved [::GX::configurationResolve $id]
        lappend lines [_record SETTING $key [dict get $resolved effective] [dict get $resolved origin]]
    }
    return [join $lines "\n"]
}
proc ::GX::CurveDigitizer::_settingsCommit {sessionToken rows} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} {
        error "GX-TXT Session changed; reload Curve Digitalizer preferences."
    }
    set changes {}
    set seen {}
    foreach line [split $rows "\n"] {
        if {$line eq ""} continue
        set fields [split $line "\t"]
        if {[llength $fields] != 3} {error "Invalid Curve Digitalizer settings transaction."}
        lassign $fields key encodedExpected encodedValue
        if {$key in $seen} {error "Duplicate setting in configuration transaction: $key"}
        lappend seen $key
        set id [_settingId $key]
        lappend changes [dict create id $id scope session expected [_b64d $encodedExpected] \
            value [_b64d $encodedValue] session_token $sessionToken]
    }
    if {[llength $changes]} {::GX::configurationCommit $changes}
    return [_settingsRows]
}
proc ::GX::CurveDigitizer::_settingsOpen {} {
    variable moduleId
    if {![llength [info commands ::GX::configurationModuleDialog]]} {
        error "GX-TXT Configuration module editor is unavailable."
    }
    # Host-owned Tk editor, with User defaults and Session override controls.
    ::GX::configurationModuleDialog $moduleId .
    return opened
}

proc ::GX::CurveDigitizer::_bootstrap {} {
    set session [_requireSession]
    set lines [list [_record SESSION [::GX::interactiveDocumentSessionToken]]]
    foreach unit [::GX::unitRegistryList] { lappend lines [_record UNIT $unit] }
    foreach role [::GX::semanticRegistryList] { lappend lines [_record ROLE $role] }
    foreach setting [split [_settingsRows] "\n"] { if {$setting ne ""} {lappend lines $setting} }
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
# Dataset Catalog/Namespace read-only projection. The registry, revision,
# Session token and namespace list belong to CORE; this viewer keeps no second
# authority and never changes the current namespace or Dataset membership.
proc ::GX::CurveDigitizer::_catalogState {} {
    set session [_requireSession]
    set snapshot [::GX::datasetCatalogSnapshot $session]
    return [_record STATE [::GX::interactiveDocumentSessionToken] \
        [dict get $snapshot session_token] [dict get $snapshot revision] \
        [dict get $snapshot current_namespace]]
}
proc ::GX::CurveDigitizer::_catalogPayload {} {
    set session [_requireSession]
    set snapshot [::GX::datasetCatalogSnapshot $session]
    set lines [list [_record STATE [::GX::interactiveDocumentSessionToken] \
        [dict get $snapshot session_token] [dict get $snapshot revision] \
        [dict get $snapshot current_namespace]]]
    foreach ns [::GX::datasetNamespaceList $session] {
        lappend lines [_record NAMESPACE $ns]
    }
    # The Catalog snapshot supplies the canonical namespace and fingerprint;
    # Session Inspection is only used to enforce the image-specific contract.
    foreach item [dict get $snapshot datasets] {
        set id [dict get $item dataset_id]
        set record [::GX::sessionInspectionDataset $id $session]
        set contract [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]
        set media [string tolower [expr {[dict exists $record media_type] ? [dict get $record media_type] : ""}]]
        if {$contract ne "image.raster" && ![string match "image/*" $media]} continue
        set registeredSha [dict get $item canonical_sha256]
        set format [expr {[dict exists $record format] ? [dict get $record format] : ""}]
        lappend lines [_record IMAGE $id [dict get $item namespace] $contract \
            $format $media $registeredSha]
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
    set rasterXs {}; set rasterYs {}; set calibrationKeys {}; set calibrationLabels {};set pointIds {}; set rowFormat {}
    set count 0
    foreach line [split $text "\n"] {
        if {$line eq ""} continue
        set fields [split $line "\t"]
        if {[llength $fields] ni {6 8 9 10 11}} { error "Invalid Curve Digitalizer publication row." }
        if {$rowFormat eq {}} { set rowFormat [llength $fields] }
        if {[llength $fields] != $rowFormat} { error "Mixed raster/nonraster publication rows." }
        lassign $fields curve64 label64 index x y family pixelX pixelY calibration64 calibrationLabel64
        if {$rowFormat >= 8} {
            if {![string is double -strict $pixelX] || ![string is double -strict $pixelY] ||
                ![expr {abs(double($pixelX)) < Inf && abs(double($pixelY)) < Inf}]} {
                error "Raster pixel coordinates must be finite."
            }
            lappend rasterXs $pixelX
            lappend rasterYs $pixelY
        }
        if {$rowFormat in {10 11}} {
            set mid [_b64d $calibration64]
            set mlabel [_b64d $calibrationLabel64]
            if {![regexp {^meas_[a-f0-9]{32}$} $mid]} {error {Invalid calibration measurement identity in publication rows.}}
            lappend calibrationKeys $mid
            lappend calibrationLabels $mlabel
        }
        if {$rowFormat in {9 11}} {
            set pointId [_b64d [lindex $fields end]]
            if {$pointId eq {} || [string length $pointId] > 160} {
                error {Invalid original point identity in row.}
            }
            lappend pointIds $pointId
        }
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
    return [dict create count $count curve_id $curveIds curve_label $curveLabels point_index $indices x $xs y $ys family_value $families \
        raster_available [expr {$rowFormat >= 8}] raster_x $rasterXs raster_y $rasterYs \
        calibration_available [expr {$rowFormat in {10 11}}] calibration_key $calibrationKeys calibration_label $calibrationLabels \
        point_available [expr {$rowFormat in {9 11}}] point_id $pointIds]
}
# v2.0: verify every uncertainty record against the CURRENT publication
# rows before any Dataset publication operation. Never trust the GUI's
# selected calibration or unsaved curve order without comparing actual rows.
proc ::GX::CurveDigitizer::_uncertaintyRows {text rows} {
    if {[string trim $text] eq {}} {return {}}
    set lines [split $text "\n"]
    if {[llength $lines] != [expr {[dict get $rows count]+2}]} {
        error {Uncertainty point count differs from exact publication rows.}
    }
    set report [_b64d [lindex $lines 0]]
    set factors [_b64d [lindex $lines 1]]
    if {[string length $report] > 20000 || [string length $factors] > 1150000 ||
        ![string match {*"gxtxt.curve_digitizer.uncertainty.v2"*} $report] ||
        ![string match {*"zlib-base64-float64-le-v1"*} $factors]} {
        error {Invalid or oversized uncertainty declaration/binding.}
    }
    set cids {};set pids {};set mids {};set sigx {};set sigy {};set covxy {}
    set seen [dict create]
    set n [dict get $rows count]
    for {set i 0} {$i<$n} {incr i} {
        set fields [split [lindex $lines [expr {$i+2}]] "\t"]
        if {[llength $fields] != 8} {error "Invalid uncertainty row $i."}
        lassign $fields curve64 point64 measurement64 x y sx sy cov
        set curve [_b64d $curve64];set point [_b64d $point64];set mid [_b64d $measurement64]
        if {$curve ne [lindex [dict get $rows curve_id] $i] ||
            $x ne [lindex [dict get $rows x] $i] || $y ne [lindex [dict get $rows y] $i]} {
            error "Uncertainty coordinate/curve identity differs at row $i."
        }
        if {[dict get $rows calibration_available] &&
            $mid ne [lindex [dict get $rows calibration_key] $i]} {
            error "Uncertainty calibration identity differs at row $i."
        }
        if {[dict get $rows point_available] && $point ne [lindex [dict get $rows point_id] $i]} {
            error "Uncertainty original point identity differs at row $i."
        }
        if {$point eq {} || [string length $point] > 160 ||
            ![string is double -strict $sx] || ![string is double -strict $sy] ||
            ![string is double -strict $cov] ||
            ![expr {abs(double($sx)) < Inf && abs(double($sy)) < Inf && abs(double($cov)) < Inf}] ||
            $sx<0 || $sy<0 || abs(double($cov)) > (double($sx)*double($sy)+1.0e-12)} {
            error "Invalid physical uncertainty at row $i."
        }
        set identity [list $mid $point]
        if {[dict exists $seen $identity]} {error "Repeated point identity within calibration at row $i."}
        dict set seen $identity 1
        lappend cids $curve;lappend pids $point;lappend mids $mid
        lappend sigx $sx;lappend sigy $sy;lappend covxy $cov
    }
    return [dict create report $report factors $factors curve_id $cids point_id $pids calibration_id $mids sigma_x $sigx sigma_y $sigy covariance_xy $covxy]
}

proc ::GX::CurveDigitizer::_publicationVariable {writer id displayLabel unit role dtype coordRole} {
    # The public variable_id/name remain stable technical identities. Human
    # labels are applied separately through Variable Schema API v3.
    set valueKind [expr {$dtype eq "string" ? "text" : "number"}]
    set spec [dict create name $id unit $unit semantic_role $role semantic_source plugin value_kind $valueKind dtype $dtype rank 1 dimension_ids row coordinate_role $coordRole axis_kind explicit]
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

# Decode typed UTF-8 strings prepared by the GUI. The host does not need
# a JSON package: nested manifests are stored as canonical JSON, while the
# public Tcl API reconstructs typed dictionaries from component fields.
proc ::GX::CurveDigitizer::_publicationCalibrationFields {records sourceDataset sourceSha} {
    if {[string length $records] > 4194304} { error "Calibration manifest is too large." }
    set fields [dict create]
    foreach line [split $records "\n"] {
        if {$line eq ""} continue
        set parts [split $line "\t"]
        if {[llength $parts] != 2} { error "Malformed calibration metadata record." }
        set key [_b64d [lindex $parts 0]]
        set value [_b64d [lindex $parts 1]]
        if {![regexp {^curve_digitizer\.[A-Za-z][A-Za-z0-9_.-]*$} $key]} {
            error "Invalid calibration metadata field '$key'."
        }
        if {[dict exists $fields $key]} { error "Duplicate calibration metadata field '$key'." }
        dict set fields $key $value
    }
    foreach key {source_dataset_id source_sha256 configuration_id calibration_type image_width image_height coordinate_origin y_direction physical_unit transform manifest_version calibration_manifest} {
        if {![dict exists $fields curve_digitizer.$key]} {
            error "Missing calibration metadata field '$key'."
        }
    }
    if {[dict get $fields curve_digitizer.source_dataset_id] ne $sourceDataset ||
        [string tolower [dict get $fields curve_digitizer.source_sha256]] ne [string tolower $sourceSha]} {
        error "Calibration metadata source identity does not match the publication source."
    }
    if {[dict get $fields curve_digitizer.calibration_type] ni {pixel scale_bar affine projective}} {
        error "Unsupported calibration classification."
    }
    if {[dict get $fields curve_digitizer.manifest_version] ne "1"} {
        error "Unsupported calibration manifest version."
    }
    foreach dimension {image_width image_height} {
        set d [dict get $fields curve_digitizer.$dimension]
        if {![string is integer -strict $d] || $d < 2} { error "Invalid image raster dimensions." }
    }
    if {[dict get $fields curve_digitizer.calibration_type] eq "scale_bar" &&
        ![dict exists $fields curve_digitizer.scale_bar]} {
        error "Scale-bar calibration requires a scale-bar record."
    }
    return $fields
}

# Dataset Notes API v1 owns canonical Dataset Markdown (.md) storage.
# Keep the existing note byte-for-byte; the digitizer only appends a named
# section when its content is not already present. Changed notes are added
# as another snapshot rather than silently erasing user edits/history.
proc ::GX::CurveDigitizer::_appendPublishedNotes {datasetId documentId configName notes} {
    if {[string length [encoding convertto utf-8 $notes]] > 262144} {
        error {Curve Digitalizer configuration notes exceed 256 KiB.}
    }
    set body [string trim $notes "\r\n"]
    if {[string trim $body] eq ""} {return empty}
    set heading [string map [list "\n" " " "\r" " " "\t" " "] $configName]
    set section "## Curve Digitalizer notes — $heading\n\n$body"
    set original [::GX::datasetUserNotes $datasetId]
    # Exact section boundary (not a prefix of a longer or edited note).
    set tail "${section}\n"
    if {[string length $original] >= [string length $tail] &&
        [string range $original end-[expr {[string length $tail]-1}] end] eq $tail} {
        return unchanged
    }
    if {[string first "${section}\n\n" $original] >= 0} {return unchanged}
    set separator ""
    if {$original ne ""} {
        if {[string match "*\n\n" $original]} {
            set separator ""
        } elseif {[string match "*\n" $original]} {
            set separator "\n"
        } else {
            set separator "\n\n"
        }
    }
    ::GX::datasetUserNotesSave $datasetId "${original}${separator}${section}\n"
    return written
}
# Publishing the numeric/file Dataset is a separate CORE transaction from
# Dataset Notes API. An MD-write error must never be reported as a failed
# Dataset publication: return an explicit note warning alongside the receipt.
proc ::GX::CurveDigitizer::_publicationNotesResult {datasetId documentId configName notes} {
    if {[catch {_appendPublishedNotes $datasetId $documentId $configName $notes} issue]} {
        set issue [string map [list "\r" " " "\n" " " "\t" " "] $issue]
        return "failed:$issue"
    }
    return $issue
}

source [file join [file dirname [info script]] curve_digitizer_numeric_core.tcl]
proc ::GX::CurveDigitizer::_publish {args} {
    if {[llength $args] ni {23 24 25 26}} { error "Invalid Curve Digitalizer publication request." }
    lassign $args sessionToken documentId datasetId displayName mode xLabel xUnit xRole yLabel yUnit yRole familyLabel familyUnit familyRole sourceDataset sourceSha calibrationType xScale yScale configName rowsText calibrationRecords layout configurationNotes uncertaintyText coreInline
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
    if {$layout ni {separate combined}} {error {Unsupported calibration publication layout.}}
    set rows [_parseRows $rowsText $familyMode]
    if {[dict get $rows calibration_available] != ($layout eq "combined")} {
        error {Publication layout and row calibration-key schema disagree.}
    }
    set uncertainty [_uncertaintyRows $uncertaintyText $rows]
    set contract [expr {$familyMode ? "curve_family.table" : "table.generic"}]
    set provenance "Curve Digitalizer configuration $documentId; source Dataset $sourceDataset; source SHA-256 $sourceSha; calibration $calibrationType; X scale $xScale; Y scale $yScale"
    set calibrationMetadata [_publicationCalibrationFields $calibrationRecords $sourceDataset $sourceSha]
    # Calibration types are part of one authoritative manifest, not separately
    # user-editable publication hints. Reject mismatched caller parameters.
    foreach field {publication_calibration_mode publication_calibration_ids publication_measurement_id} {
        if {![dict exists $calibrationMetadata curve_digitizer.$field]} {error "Missing calibration publication field $field."}
    }
    if {[dict get $calibrationMetadata curve_digitizer.publication_calibration_mode] ne $layout} {
        error {Publication layout disagrees with calibration provenance.}
    }
    set measurementCount [dict get $calibrationMetadata curve_digitizer.measurement_count]
    if {![string is integer -strict $measurementCount] || $measurementCount < 1 || $measurementCount > 200} {
        error {Invalid calibration measurement count.}
    }
    set selectedJson [dict get $calibrationMetadata curve_digitizer.publication_calibration_ids]
    if {![regexp {^\["meas_[a-f0-9]{32}"(,"meas_[a-f0-9]{32}")*\]$} $selectedJson]} {
        error {Invalid selected calibration measurement list.}
    }
    set selectedIds [regexp -all -inline {meas_[a-f0-9]{32}} $selectedJson]
    if {$uncertainty ne {} && [llength $selectedIds] != 1} {
        error {Uncertainty publication cannot mix multiple calibrations into one Dataset; publish separately to retain correct correlation semantics.}
    }
    if {$uncertainty ne {} && ![dict get $rows point_available]} {
        error {Uncertainty publication requires stable point IDs in canonical rows.}
    }
    set coreReview {}
    if {$uncertainty ne {}} {
        # No local NumPy result is authoritative: use the public dev097 Numeric
        # propagation/Statistics semantics and compare the submitted science.
        set coreReview [::GX::CurveDigitizerNumericCore::propagate $documentId $rowsText             [lindex $selectedIds 0] $rows $sourceDataset $sourceSha $coreInline [dict get $uncertainty factors]]
        set core [dict get $coreReview columns]
        set n [dict get $rows count]
        for {set i 0} {$i<$n} {incr i} {
            foreach key {sigma_x sigma_y covariance_xy} {
                set requested [lindex [dict get $uncertainty $key] $i]
                set calculated [lindex [dict get $core $key] $i]
                set tol [expr {1.e-9+1.e-8*abs(double($calculated))}]
                if {abs(double($requested)-double($calculated))>$tol} {
                    error "Local preflight and public CORE $key disagree at row $i; publication aborted."
                }
            }
        }
        foreach key {sigma_x sigma_y covariance_xy} {
            dict set uncertainty $key [dict get $core $key]
        }
    }

    if {[llength $selectedIds] != [llength [lsort -unique $selectedIds]] ||
        [llength $selectedIds] > $measurementCount ||
        ($layout eq "separate" && [llength $selectedIds] != 1)} {
        error {The publication selects duplicate or invalid measurement IDs.}
    }
    set primaryId [dict get $calibrationMetadata curve_digitizer.publication_measurement_id]
    if {$primaryId ne [lindex $selectedIds 0]} {
        error {Primary calibration must match the first selected measurement.}
    }
    set validAccepted {}
    for {set i 0} {$i < $measurementCount} {incr i} {
        set prefix curve_digitizer.measurement.${i}.
        foreach key {measurement_id valid state} {
            if {![dict exists $calibrationMetadata $prefix$key]} {error "Missing measurement provenance: $prefix$key"}
        }
        if {[dict get $calibrationMetadata ${prefix}valid] eq "1" &&
            [dict get $calibrationMetadata ${prefix}state] eq "accepted"} {
            lappend validAccepted [dict get $calibrationMetadata ${prefix}measurement_id]
        }
    }
    foreach mid $selectedIds {
        if {$mid ni $validAccepted} {error "Selected calibration measurement '$mid' is not accepted and valid."}
    }
    if {$layout eq "combined"} {
        foreach key [dict get $rows calibration_key] {
            if {$key ni $selectedIds} {
                error {A published row references a calibration outside the selected set.}
            }
        }
        # One scientific Variable Schema cannot mix incompatible physical units.
        foreach axis {x y} {
            set requiredUnit [expr {$axis eq "x" ? $xUnit : $yUnit}]
            for {set i 0} {$i<$measurementCount} {incr i} {
                set prefix curve_digitizer.measurement.${i}.
                if {[dict get $calibrationMetadata ${prefix}measurement_id] ni $selectedIds} continue
                set key ${prefix}transform.${axis}_unit
                if {![dict exists $calibrationMetadata $key] ||
                    [dict get $calibrationMetadata $key] ne $requiredUnit} {
                    error {Selected calibrations have incompatible scientific axis units.}
                }
            }
        }
    }
    set expectedClass [dict get $calibrationMetadata curve_digitizer.calibration_type]
    set oldClass [expr {$calibrationType eq "full_image_scale_bar" ? "scale_bar" : $calibrationType eq "full_image_pixels" ? "pixel" : ""}]
    if {$oldClass ne "" && $oldClass ne $expectedClass} {
        error "Calibration classification changed during publication."
    }
    set metadata [dict create \
        dataset.display_name $displayName \
        curve_digitizer.plugin_id viewer.curve_digitizer \
        curve_digitizer.plugin_version 2.0.3 \
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
    # Curve Dataset Schema v1: semantic roles are a public, versioned mapping
    # independent of variable ID, human label, CSV order, and plugin GUI state.
    # Publication V2 persists all mappings atomically with the payload.
    dict set metadata curve_digitizer.curve_schema_version 1
    dict set metadata curve_digitizer.curve_mode [expr {$familyMode ? "numerical_family" : "independent"}]
    dict set metadata curve_digitizer.curve_grouping curve_key
    dict set metadata curve_digitizer.curve_row_dimension row
    foreach {role variableId} {x x y y curve_key curve_id curve_name curve_label point_order point_index} {
        dict set metadata curve_digitizer.curve_column.$role $variableId
    }
    if {$familyMode} { dict set metadata curve_digitizer.curve_column.family_parameter family_value }
    if {[dict get $rows calibration_available]} {
        dict set metadata curve_digitizer.curve_column.calibration_key calibration_id
        dict set metadata curve_digitizer.curve_column.calibration_name calibration_label
        dict set metadata curve_digitizer.curve_grouping curve_key_and_calibration_key
    }

    # Original raster pixel coordinates are first-class numeric Dataset variables,
    # not references to a transient Interactive Document.
    if {[dict get $rows point_available]} {
        dict set metadata curve_digitizer.curve_column.point_id point_id
    }
    if {[dict get $rows raster_available]} {
        dict set metadata curve_digitizer.curve_column.raster_x pixel_x
        dict set metadata curve_digitizer.curve_column.raster_y pixel_y
        dict set metadata curve_digitizer.raster_reference original_source_image
    }
    # Never erase unrelated producer/user metadata during a republish.
    # Remove the previous Curve Digitalizer namespace first: optional fields
    # such as scale_bar must not survive when switching to pixel calibration.
    set previous [dict create]
    if {![catch {::GX::sessionInspectionDataset $datasetId $session}]} {
        set previous [::GX::datasetMetadataRead $session $datasetId]
        if {[dict exists $previous curve_digitizer.configuration_id] &&
            [dict get $previous curve_digitizer.configuration_id] ne [dict get $calibrationMetadata curve_digitizer.configuration_id]} {
            error {The output Dataset belongs to a different digitizer configuration. Choose a different name.}
        }
    }
    dict for {key value} $previous {
        if {[string match "curve_digitizer.*" $key]} { dict unset previous $key }
    }
    set metadata [dict merge $previous $metadata $calibrationMetadata]
    if {$uncertainty ne {}} {
        set covarianceUnit [::GX::CurveDigitizerNumericCore::covarianceUnit $xUnit $yUnit]
        dict set metadata curve_digitizer.uncertainty_schema_version 2
        dict set metadata curve_digitizer.uncertainty_report_json [dict get $uncertainty report]
        dict set metadata curve_digitizer.uncertainty_factors_json [dict get $uncertainty factors]
        dict set metadata curve_digitizer.uncertainty_point_count [dict get $rows count]
        dict set metadata curve_digitizer.uncertainty_covariance_xy_unit $covarianceUnit
        dict set metadata curve_digitizer.curve_column.point_id point_id
        dict set metadata curve_digitizer.curve_column.sigma_x sigma_x
        dict set metadata curve_digitizer.curve_column.sigma_y sigma_y
        dict set metadata curve_digitizer.curve_column.covariance_xy covariance_xy
    }
    set definition [dict create dataset_id $datasetId contract $contract storage csv replace_owned 1 producer_version 2.0.3 source "Curve Digitalizer: $configName" provenance $provenance notes $displayName source_dataset_ids [list $sourceDataset] structured_metadata $metadata]
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
        _publicationVariable $writer curve_id "Curve ID" "" curve_series_identifier string auxiliary
        _publicationVariable $writer curve_label "Curve label" "" curve_series_label string auxiliary
        _publicationVariable $writer point_index "Point index" "" curve_point_index int64 auxiliary
        if {[dict get $rows point_available]} {
            _publicationVariable $writer point_id "Original point ID" "" curve_point_identifier string auxiliary
        }
        if {[dict get $rows calibration_available]} {
            _publicationVariable $writer calibration_id "Calibration measurement ID" "" curve_calibration_identifier string auxiliary
            _publicationVariable $writer calibration_label "Calibration measurement label" "" curve_calibration_label string auxiliary
        }
        if {[dict get $rows raster_available]} {
            _publicationVariable $writer pixel_x "Original raster X" px curve_raster_x float64 coordinate
            _publicationVariable $writer pixel_y "Original raster Y" px curve_raster_y float64 coordinate
        }
        if {$uncertainty ne {}} {
            _publicationVariable $writer sigma_x "X standard uncertainty" $xUnit uncertainty_standard_x float64 auxiliary
            _publicationVariable $writer sigma_y "Y standard uncertainty" $yUnit uncertainty_standard_y float64 auxiliary
            _publicationVariable $writer covariance_xy "Within-point XY covariance" $covarianceUnit uncertainty_covariance_xy float64 auxiliary
        }
        set appendData [dict create x [dict get $rows x] y [dict get $rows y] curve_id [dict get $rows curve_id] curve_label [dict get $rows curve_label] point_index [dict get $rows point_index]]
        if {[dict get $rows raster_available]} {
            dict set appendData pixel_x [dict get $rows raster_x]
            dict set appendData pixel_y [dict get $rows raster_y]
        }
        if {[dict get $rows calibration_available]} {
            dict set appendData calibration_id [dict get $rows calibration_key]
            dict set appendData calibration_label [dict get $rows calibration_label]
        }
        if {$familyMode} { dict set appendData family_value [dict get $rows family_value] }
        if {[dict get $rows point_available]} {
            dict set appendData point_id [dict get $rows point_id]
        }
        if {$uncertainty ne {}} {
            foreach key {sigma_x sigma_y covariance_xy} {
                dict set appendData $key [dict get $uncertainty $key]
            }
        }
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
    if {[dict get $rows point_available]} {
        dict set schemaFields point_id [dict create label "Original point ID" unit ""]
    }
    if {[dict get $rows raster_available]} {
        dict set schemaFields pixel_x [dict create label "Original raster X" unit px]
        dict set schemaFields pixel_y [dict create label "Original raster Y" unit px]
    }
    if {[dict get $rows calibration_available]} {
        dict set schemaFields calibration_id [dict create label "Calibration measurement ID" unit ""]
        dict set schemaFields calibration_label [dict create label "Calibration measurement label" unit ""]
    }
    if {$uncertainty ne {}} {
        foreach {key label unit} [list sigma_x {X standard uncertainty} $xUnit sigma_y {Y standard uncertainty} $yUnit covariance_xy {Within-point XY covariance} $covarianceUnit] {
            dict set schemaFields $key [dict create label $label unit $unit]
        }
    }
    if {$familyMode} { dict set schemaFields family_value [dict create label $familyLabel unit $familyUnit] }
    _schemaEnhance $datasetId $schemaFields
    if {$uncertainty ne {}} {
        set coreBinding [dict create schema gxtxt.digitizer_publication_binding.v1 \
            dataset_id $datasetId payload_sha256 [dict get $result sha256] \
            point_count [dict get $rows count] x_variable_id x y_variable_id y \
            sigma_x_variable_id sigma_x sigma_y_variable_id sigma_y \
            point_id_variable_id point_id resources [dict get $coreReview resources]]
        ::GX::datasetMetadataUpdate $session $datasetId [dict create \
            curve_digitizer.uncertainty_dataset_sha256 [dict get $result sha256] \
            curve_digitizer.uncertainty_source_sha256 $sourceSha \
            curve_digitizer.uncertainty_binding $coreBinding]
    }

    set receipt [list [dict get $result dataset_id] [dict get $result path] [dict get $result sha256] $contract]
    if {[llength $args] >= 24} {
        lappend receipt [_publicationNotesResult $datasetId $documentId $configName $configurationNotes]
    }
    return [join $receipt "\t"]
}
# Rendered documentation is owned by the GX-TXT host and its public
# Documentation/GX-Markup services, not by a second Python Markdown parser.
# This helper opens a dedicated Help window without changing the scientific
# Dataset/Interactive Document state or accessing private Session paths.
proc ::GX::CurveDigitizer::_helpGoTo {w headings} {
    set toc $w.left.list
    set selected [$toc curselection]
    if {[llength $selected] != 1} return
    set title [lindex $headings [lindex $selected 0]]
    set body $w.right.body
    if {$title eq ""} return
    set where [$body search -exact -nocase -- $title 1.0]
    if {$where ne ""} {
        $body see $where
        $body tag remove gx_help_selection 1.0 end
        $body tag add gx_help_selection $where "$where + [string length $title] chars"
    }
}

proc ::GX::CurveDigitizer::_helpFind {w} {
    variable helpSearch
    set needle [string trim $helpSearch]
    if {$needle eq ""} return
    set body $w.right.body
    set start [$body index insert]
    set found [$body search -nocase -- $needle $start end]
    if {$found eq ""} { set found [$body search -nocase -- $needle 1.0 end] }
    $body tag remove gx_help_match 1.0 end
    if {$found ne ""} {
        set finish "$found + [string length $needle] chars"
        $body tag add gx_help_match $found $finish
        $body see $found
        $body mark set insert $finish
        focus $body
    } else {
        bell
    }
}

proc ::GX::CurveDigitizer::_helpWindow {} {
    variable helpSearch
    set w .gxCurveDigitizerHelp
    if {[winfo exists $w]} {
        wm deiconify $w
        raise $w
        focus -force $w
        return $w
    }
    foreach command {
        ::GX::documentationBrowserRefresh
        ::GX::documentationBrowserRead
        ::GX::markupRenderStringToWidget
    } {
        if {![llength [info commands $command]]} {
            error "GX-TXT documentation/markup service '$command' is unavailable."
        }
    }
    # Use the descriptor registered by Documentation API v1. Never hardcode a
    # second manual path or read the viewer's own Python package internals.
    ::GX::documentationBrowserRefresh
    set id module:viewer.curve_digitizer:guide
    set source [::GX::documentationBrowserRead $id]
    # GX-Markup v1 treats bare ``` as a code fence; strip optional Markdown
    # syntax-language labels from the DERIVED display text, not MANUAL.md.
    regsub -all -line {^```[[:alnum:]_+.-]+[ \t]*$} $source {```} source

    toplevel $w
    wm title $w "Curve Digitalizer — Rendered User Guide"
    wm geometry $w 1050x730
    wm minsize $w 640 430
    grid rowconfigure $w 1 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::frame $w.top
    grid $w.top -row 0 -column 0 -sticky ew -padx 10 -pady {8 5}
    ttk::label $w.top.title -text "Curve Digitalizer — User Guide" -font {TkDefaultFont 13 bold}
    ttk::label $w.top.engine -text "Rendered by GX-TXT GX-Markup"
    pack $w.top.title -side left
    pack $w.top.engine -side right

    ttk::panedwindow $w.panes -orient horizontal
    grid $w.panes -row 1 -column 0 -sticky nsew -padx 9
    ttk::frame $w.left
    ttk::frame $w.right
    $w.panes add $w.left -weight 1
    $w.panes add $w.right -weight 3

    ttk::label $w.left.title -text "Contents"
    pack $w.left.title -side top -anchor w -padx 4 -pady 3
    listbox $w.left.list -exportselection 0 -width 35 -activestyle none
    ttk::scrollbar $w.left.scroll -orient vertical -command [list $w.left.list yview]
    $w.left.list configure -yscrollcommand [list $w.left.scroll set]
    pack $w.left.scroll -side right -fill y
    pack $w.left.list -side left -fill both -expand 1

    text $w.right.body -wrap word -state disabled -padx 12 -pady 10 -font TkDefaultFont
    ttk::scrollbar $w.right.scroll -orient vertical -command [list $w.right.body yview]
    $w.right.body configure -yscrollcommand [list $w.right.scroll set]
    pack $w.right.scroll -side right -fill y
    pack $w.right.body -side left -fill both -expand 1
    ::GX::markupRenderStringToWidget $w.right.body $source
    $w.right.body tag configure gx_help_match -background #ffe28c -foreground #171717
    $w.right.body tag configure gx_help_selection -background #d4e8fa

    set headings {}
    foreach line [split $source "\n"] {
        if {[regexp {^(#{1,3})[[:space:]]+(.*)$} $line -> marks title]} {
            lappend headings $title
            set padding [string repeat "  " [expr {[string length $marks]-1}]]
            $w.left.list insert end "$padding$title"
        }
    }
    bind $w.left.list <<ListboxSelect>> [list ::GX::CurveDigitizer::_helpGoTo $w $headings]

    ttk::frame $w.bottom
    grid $w.bottom -row 2 -column 0 -sticky ew -padx 10 -pady {7 9}
    ttk::label $w.bottom.find_label -text "Find:"
    set helpSearch ""
    ttk::entry $w.bottom.find -textvariable ::GX::CurveDigitizer::helpSearch
    ttk::button $w.bottom.next -text "Find next" -command [list ::GX::CurveDigitizer::_helpFind $w]
    ttk::button $w.bottom.close -text "Close" -command [list destroy $w]
    pack $w.bottom.find_label -side left
    pack $w.bottom.find -side left -fill x -expand 1 -padx 6
    pack $w.bottom.next -side left
    pack $w.bottom.close -side right -padx {12 0}
    bind $w.bottom.find <Return> [list ::GX::CurveDigitizer::_helpFind $w]
    bind $w <F3> [list ::GX::CurveDigitizer::_helpFind $w]
    bind $w <Escape> [list destroy $w]
    update idletasks
    raise $w
    focus -force $w.bottom.find
    return $w
}


# Host-owned ImageMagick resolution, staging and CORE-owned Image Dataset publication.
# The Python GUI never writes registry/metadata/manifest files itself.
proc ::GX::CurveDigitizer::_imageTool {} {
    set result [::GX::runtimeToolStatus magick]
    if {![dict get $result available]} {
        return "unavailable\t[dict get $result message]"
    }
    set tool [dict get $result path]
    # Configured executable paths may contain spaces, especially on Windows.
    # Accept a real file as-is; auto_execok may return a one-element argv list.
    if {[file isfile $tool]} {
        set executable $tool
    } elseif {[llength $tool] == 1 && [file isfile [lindex $tool 0]]} {
        set executable [lindex $tool 0]
    } else {
        error {ImageMagick runtime must resolve to one existing executable.}
    }
    set version [string map [list "\n" { } "\r" { } "\t" { }] [dict get $result version]]
    return "$executable\t$version"
}
proc ::GX::CurveDigitizer::_imageStage {sessionToken} {
    variable imageStages
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; image staging was rejected.}}
    # Tcl owns the temporary output file and publication cleanup; Python is
    # restricted to filling this exact allocated file with PNG bytes.
    set fd [file tempfile stage]
    close $fd
    dict set imageStages $stage $sessionToken
    return $stage
}
proc ::GX::CurveDigitizer::_imageStagesCleanup {} {
    variable imageStages
    dict for {path token} $imageStages {
        catch {file delete -force -- $path}
    }
    set imageStages [dict create]
}
proc ::GX::CurveDigitizer::_imageStageCancel {sessionToken stage} {
    variable imageStages
    if {[dict exists $imageStages $stage] && [dict get $imageStages $stage] eq $sessionToken} {
        dict unset imageStages $stage
        catch {file delete -force -- $stage}
    }
    return cancelled
}
proc ::GX::CurveDigitizer::_readImageMetadata {payload} {
    set fields [dict create]
    foreach line [split $payload "\n"] {
        if {$line eq {}} continue
        set parts [split $line "\t"]
        if {[llength $parts] != 2} {error {Malformed Image Processing metadata record.}}
        set key [_b64d [lindex $parts 0]]
        set val [_b64d [lindex $parts 1]]
        if {![regexp {^curve_digitizer[.]image_processing[.][A-Za-z0-9_.-]+$} $key] ||
            [dict exists $fields $key] || [string length $val] > 1024 || [regexp {[\r\n]} $val]} {
            error {Invalid or duplicate Image Processing metadata field.}
        }
        dict set fields $key $val
    }
    return $fields
}
proc ::GX::CurveDigitizer::_imagePublish {sessionToken documentId sourceDataset sourceSha datasetId display stage records {configurationNotes ""}} {
    variable imageStages
    if {![dict exists $imageStages $stage] || [dict get $imageStages $stage] ne $sessionToken ||
        $sessionToken ne [::GX::interactiveDocumentSessionToken]} {
        error {Invalid, expired or foreign Image Processing staging token.}
    }
    dict unset imageStages $stage
    # Every attempted publication releases the only temporary image file.
    try {
        set session [_requireSession]
        set doc [::GX::interactiveDocumentRead $documentId]
        if {[dict get $doc module_id] ne {viewer.curve_digitizer} ||
            [dict get $doc provider_id] ne {curve_digitizer}} {
            error {The Interactive Document does not belong to Curve Digitalizer.}
        }
        set info [_sourceInfo $sourceDataset]
        if {[string tolower [dict get $info sha256]] ne [string tolower $sourceSha] ||
            ([dict get $info registered_sha256] ne {} &&
             [string tolower [dict get $info registered_sha256]] ne [string tolower $sourceSha])} {
            error {The canonical source Image Dataset SHA-256 changed; processed image was not published.}
        }
        set fields [_readImageMetadata $records]
        foreach {key expected} [list source_dataset_id $sourceDataset source_sha256 [string tolower $sourceSha] \
                                   producer_id viewer.curve_digitizer schema_version 1 \
                                   geometry_preserved 1 pixel_transform identity engine ImageMagick] {
            if {![dict exists $fields curve_digitizer.image_processing.$key] ||
                [dict get $fields curve_digitizer.image_processing.$key] ne $expected} {
                error "Image Processing manifest '$key' does not match its authoritative source."
            }
        }
        set count [dict get $fields curve_digitizer.image_processing.operation_count]
        if {![string is integer -strict $count] || $count < 1 || $count > 30} {
            error {Image Processing manifest has invalid operation count.}
        }
        for {set i 0} {$i < $count} {incr i} {
            foreach field {kind value} {
                if {![dict exists $fields curve_digitizer.image_processing.operation.$i.$field]} {
                    error "Missing Image Processing operation $i $field."
                }
            }
            set kind [dict get $fields curve_digitizer.image_processing.operation.$i.kind]
            if {$kind ni {grayscale channel gamma brightness_contrast auto_level contrast_stretch clahe threshold median negate sharpen}} {
                error "Unsupported or geometry-altering Image Processing operation '$kind'."
            }
        }
        if {![file isfile $stage] || [file size $stage] < 33 || [file size $stage] > 268435456} {
            error {Staged PNG is absent, empty or exceeds the 256 MiB limit.}
        }
        set fd [open $stage rb]
        try {set header [read $fd 24]} finally {close $fd}
        if {[string range $header 0 7] ne "\x89PNG\r\n\x1a\n" ||
            [string range $header 12 15] ne {IHDR}} {
            error {The processed image is not a valid PNG raster header.}
        }
        binary scan [string range $header 16 23] c8 rawDimensions
        set numeric {}
        foreach offset {0 4} {
            set value 0
            for {set i $offset} {$i < $offset+4} {incr i} {
                set value [expr {($value << 8) | ([lindex $rawDimensions $i] & 255)}]
            }
            lappend numeric $value
        }
        lassign $numeric width height
        foreach {field actual} [list image_width $width image_height $height] {
            if {[dict get $fields curve_digitizer.image_processing.$field] ne "$actual"} {
                error "Processed image dimensions disagree with PNG IHDR: $field."
            }
        }
        # Host supplies the actual original image name; never trust a GUI hint.
        set parent [::GX::sessionInspectionDataset $sourceDataset $session]
        set originalLabel [expr {[dict exists $parent display_name] && [dict get $parent display_name] ne {} ? [dict get $parent display_name] : $sourceDataset}]
        dict set fields curve_digitizer.image_processing.source_display_name $originalLabel
        if {[_cleanSingleLine $display {Image description}] eq {}} {set display $datasetId}
        dict set fields curve_digitizer.image_processing.output_description $display
        set result [::GX::datasetFilePublicationPublish $session viewer.curve_digitizer [dict create \
            dataset_id [_cleanSingleLine $datasetId {Image Dataset ID}] contract image.raster \
            format png source_file $stage storage_kind binary media_type image/png \
            producer_version 2.0.3 source_dataset_ids [list $sourceDataset] \
            provenance "Curve Digitalizer non-geometric ImageMagick enhancement of $sourceDataset; configuration $documentId" \
            notes "Processed image: $display" structured_metadata $fields]]
        set receipt "[dict get $result dataset_id]\t[dict get $result sha256]"
        if {$configurationNotes ne ""} {
            set configName "Image processing"
            append receipt "\t[_publicationNotesResult [dict get $result dataset_id] $documentId $configName $configurationNotes]"
        }
        return $receipt
    } finally {
        catch {file delete -force -- $stage}
    }
}

# Integration point: math.numeric NUMERIC_API_v1 is owned by GX-TXT.
# API reference: plugins/modules/math.numeric/NUMERIC_API_v1.md
# Do not emulate its numerical implementation or use its private worker.
# The guide fit is optional and only shapes the transient proposal path.
# The segment endpoints remain fixed; on failure the GUI uses a disclosed
# linear guide fallback, not a supposedly successful framework fit.
proc ::GX::CurveDigitizer::_assistNumericFit {tText xText yText queryText} {
    set t [split [string trim $tText]]
    set x [split [string trim $xText]]
    set y [split [string trim $yText]]
    set q [split [string trim $queryText]]
    if {[llength $t] < 3 || [llength $t] != [llength $x] ||
        [llength $t] != [llength $y] || [llength $q] < [llength $t]} {return {}}
    if {[catch {
        ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
        set options [dict create method pchip extrapolation error]
        set xx [dict get [::GX::NumericAPIv1::interpolate $t $x $q $options] yq]
        set yy [dict get [::GX::NumericAPIv1::interpolate $t $y $q $options] yq]
        if {[llength $xx] != [llength $q] || [llength $yy] != [llength $q]} {error {Unexpected fitting vector size}}
    } reason]} {
        return {}
    }
    set entries {}
    foreach px $xx py $yy {
        if {![string is double -strict $px] || ![string is double -strict $py]} {return {}}
        lappend entries "\[[format %.16g $px],[format %.16g $py]\]"
    }
    return "\[[join $entries ,]\]"
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
        SESSION_TOKEN { set payload [_record SESSION [::GX::interactiveDocumentSessionToken]] }
        CONFIG_READ {
            if {[llength $args] != 0} {error "CONFIG_READ accepts no arguments."}
            set payload [_settingsRows]
        }
        CONFIG_COMMIT {
            if {[llength $args] != 2} {error "CONFIG_COMMIT requires Session token and changes."}
            set payload [_settingsCommit [lindex $args 0] [lindex $args 1]]
        }
        CONFIG_OPEN {
            if {[llength $args] != 0} {error "CONFIG_OPEN accepts no arguments."}
            set payload [_settingsOpen]
        }
        CATALOG_REV {
            if {[llength $args] != 0} { error "CATALOG_REV does not accept arguments." }
            set payload [_catalogState]
        }
        CATALOG {
            if {[llength $args] != 0} { error "CATALOG does not accept arguments." }
            set payload [_catalogPayload]
        }
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
        IMAGE_TOOL {
            if {[llength $args]} {error {IMAGE_TOOL takes no arguments.}}
            set payload [_imageTool]
        }
        IMAGE_STAGE {
            if {[llength $args] != 1} {error {IMAGE_STAGE requires Session token.}}
            set payload [_imageStage [lindex $args 0]]
        }
        IMAGE_STAGE_CANCEL {
            if {[llength $args] != 2} {error {IMAGE_STAGE_CANCEL requires Session token and stage.}}
            set payload [_imageStageCancel {*}$args]
        }
        IMAGE_PUBLISH {
            if {[llength $args] ni {8 9}} {error {IMAGE_PUBLISH requires eight fields and optional configuration notes.}}
            set payload [_imagePublish {*}$args]
        }
        ASSIST_FIT {
            if {[llength $args] != 4} {error {ASSIST_FIT requires knot parameters, X, Y and query parameters.}}
            set payload [_assistNumericFit {*}$args]
        }
        PUBLISH { set payload [_publish {*}$args] }
        HELP_OPEN {
            if {[llength $args] != 0} { error "HELP_OPEN does not accept arguments." }
            set payload [_helpWindow]
        }
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
        _imageStagesCleanup
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
    _log "--- Curve Digitalizer 2.0.3; Tcl [info patchlevel]; platform=$::tcl_platform(platform) ---"
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
