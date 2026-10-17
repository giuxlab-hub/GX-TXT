# GX-TXT Curve Digitalizer Companion API v1
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::CurveDigitizerCompanion {
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
    variable ownerModule viewer.curve_digitizer
    variable ownerProvider curve_digitizer
    variable documentFormat gxtxt.curve_digitizer.configuration
    variable documentFormatVersion 1.0
}

source [file join [file dirname [info script]] curve_digitizer_uncertainty_v1.tcl]

proc ::GX::CurveDigitizerCompanion::_requireSession {} {
    return [::GX::sessionInspectionCurrentSession]
}

proc ::GX::CurveDigitizerCompanion::_ownedDocumentRead {documentId} {
    variable ownerModule
    variable ownerProvider
    variable documentFormat
    variable documentFormatVersion
    _requireSession
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne $ownerModule || [dict get $full provider_id] ne $ownerProvider} {
        error "Interactive Document '$documentId' is not owned by Curve Digitalizer."
    }
    if {[dict get $full format] ne $documentFormat || [dict get $full format_version] ne $documentFormatVersion} {
        error "Interactive Document '$documentId' uses an unsupported Curve Digitalizer configuration format/version."
    }
    return $full
}

proc ::GX::CurveDigitizerCompanion::_pythonExecutable {} {
    foreach candidate {python3 python} {
        set path [auto_execok $candidate]
        if {$path ne ""} { return $path }
    }
    error "Python 3 is required for Curve Digitalizer companion state operations."
}

proc ::GX::CurveDigitizerCompanion::_writeTempUtf8 {text pathVar} {
    upvar 1 $pathVar path
    set chan [file tempfile path]
    fconfigure $chan -encoding utf-8 -translation lf
    puts -nonewline $chan $text
    close $chan
    return $path
}

proc ::GX::CurveDigitizerCompanion::_runBridgeContext {payload {curveId ""}} {
    variable moduleRoot
    set payloadPath ""
    try {
        _writeTempUtf8 $payload payloadPath
        set cmd [list [_pythonExecutable] [file join $moduleRoot python companion_bridge.py] context --input $payloadPath]
        if {$curveId ne ""} { lappend cmd --curve-id $curveId }
        if {[catch {set output [exec {*}$cmd]} failure options]} {
            return -options $options "Unable to inspect Curve Digitalizer configuration: $failure"
        }
        set result [dict create]
        foreach line [split $output "\n"] {
            if {$line eq ""} continue
            set fields [split $line "\t"]
            set key [lindex $fields 0]
            set value [join [lrange $fields 1 end] "\t"]
            switch -- $key {
                CALIBRATION_READY - CURVE_POINT_COUNT { dict set result [string tolower $key] $value }
                default {
                    if {[catch {set decoded [encoding convertfrom utf-8 [binary decode base64 $value]]}]} {
                        error "Invalid Curve Digitalizer companion bridge record '$key'."
                    }
                    dict set result [string tolower $key] $decoded
                }
            }
        }
        return $result
    } finally {
        if {$payloadPath ne ""} { catch {file delete -force $payloadPath} }
    }
}

proc ::GX::CurveDigitizerCompanion::sessionToken {} {
    _requireSession
    return [::GX::interactiveDocumentSessionToken]
}

proc ::GX::CurveDigitizerCompanion::configurationList {} {
    variable ownerModule
    variable ownerProvider
    _requireSession
    set out {}
    foreach item [::GX::interactiveDocumentList $ownerModule $ownerProvider] {
        set full [_ownedDocumentRead [dict get $item id]]
        set context [_runBridgeContext [dict get $full payload]]
        lappend out [dict create \
            document_id [dict get $full id] \
            document_sha256 [dict get $full sha256] \
            configuration_id [dict get $context configuration_id] \
            configuration_name [dict get $context configuration_name] \
            source_dataset_id [dict get $context source_dataset_id] \
            source_sha256 [dict get $context source_sha256] \
            calibration_ready [dict get $context calibration_ready]]
    }
    return $out
}

proc ::GX::CurveDigitizerCompanion::configurationRead {documentId} {
    set full [_ownedDocumentRead $documentId]
    return [dict create \
        document_id [dict get $full id] \
        document_sha256 [dict get $full sha256] \
        configuration [_runBridgeContext [dict get $full payload]] \
        payload [dict get $full payload]]
}

proc ::GX::CurveDigitizerCompanion::curveContext {documentId curveId} {
    set curveId [string trim $curveId]
    if {$curveId eq ""} { error "Curve ID is required." }
    set full [_ownedDocumentRead $documentId]
    set context [_runBridgeContext [dict get $full payload] $curveId]
    dict set context document_id [dict get $full id]
    dict set context document_sha256 [dict get $full sha256]
    return $context
}

proc ::GX::CurveDigitizerCompanion::sourceResolve {documentId} {
    set session [_requireSession]
    set full [_ownedDocumentRead $documentId]
    set context [_runBridgeContext [dict get $full payload]]
    set datasetId [string trim [dict get $context source_dataset_id]]
    set expectedSha [string tolower [string trim [dict get $context source_sha256]]]
    if {$datasetId eq ""} { error "Curve Digitalizer configuration '$documentId' has no source Image Dataset." }

    set record [::GX::sessionInspectionDataset $datasetId $session]
    set contract [string trim [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]]
    set media [string tolower [string trim [expr {[dict exists $record media_type] ? [dict get $record media_type] : ""}]]]
    if {$contract ne "image.raster" && ![string match "image/*" $media]} {
        error "Dataset '$datasetId' is no longer a compatible Image Dataset."
    }
    set payload [::GX::sessionInspectionResolveResource [dict get $record path] $session]
    set path [dict get $payload path]
    set actualSha [dict get $payload sha256]
    if {$actualSha ne [string tolower [dict get $record canonical_sha256]] ||
        ($expectedSha ne "" && $actualSha ne $expectedSha)} {
        error "STALE SOURCE — the source image SHA-256 changed after the Curve Digitalizer configuration was created."
    }
    set metadata [dict create]
    if {[llength [info commands ::GX::datasetMetadataRead]]} {
        if {[catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}]} { set metadata [dict create] }
    }
    return [dict create \
        dataset_id $datasetId \
        path $path \
        sha256 $actualSha \
        contract $contract \
        media_type $media \
        metadata $metadata]
}

proc ::GX::CurveDigitizerCompanion::commitPixelPoints {documentId curveId expectedDocumentSha sessionToken pointsText} {
    variable moduleRoot
    variable documentFormat
    variable documentFormatVersion
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} {
        error "The GX-TXT Session changed; assisted points were not committed."
    }
    set full [_ownedDocumentRead $documentId]
    set currentSha [string tolower [dict get $full sha256]]
    set expectedDocumentSha [string tolower [string trim $expectedDocumentSha]]
    if {$expectedDocumentSha eq "" || $currentSha ne $expectedDocumentSha} {
        error "Curve Digitalizer configuration changed since the assistant loaded it; reload before committing points."
    }
    set context [_runBridgeContext [dict get $full payload] $curveId]
    if {![dict get $context calibration_ready]} {
        error "Curve Digitalizer calibration is incomplete or invalid."
    }
    # Source identity is revalidated immediately before the write so stale image
    # bytes cannot receive new assisted points under an old calibration.
    sourceResolve $documentId

    set payloadPath ""; set pointsPath ""; set outputPath ""
    try {
        _writeTempUtf8 [dict get $full payload] payloadPath
        _writeTempUtf8 $pointsText pointsPath
        set outChan [file tempfile outputPath]
        close $outChan
        set cmd [list [_pythonExecutable] [file join $moduleRoot python companion_bridge.py] append-pixel-points \
            --input $payloadPath --output $outputPath --curve-id $curveId --points $pointsPath]
        if {[catch {exec {*}$cmd} failure options]} {
            return -options $options "Unable to commit assisted Curve Digitalizer points: $failure"
        }
        set in [open $outputPath r]
        fconfigure $in -encoding utf-8 -translation lf
        set updatedPayload [read $in]
        close $in
        set updated [::GX::interactiveDocumentUpdate $documentId $updatedPayload $documentFormat $documentFormatVersion]
        return [dict create \
            document_id [dict get $updated id] \
            document_sha256 [dict get $updated sha256] \
            curve_id $curveId]
    } finally {
        foreach path [list $payloadPath $pointsPath $outputPath] {
            if {$path ne ""} { catch {file delete -force $path} }
        }
    }
}
