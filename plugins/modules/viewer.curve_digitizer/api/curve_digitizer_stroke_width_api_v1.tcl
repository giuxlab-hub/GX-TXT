# SPDX-License-Identifier: GPL-3.0-or-later
# CURVE_DIGITIZER_STROKE_WIDTH_API_v1: public, descriptive raster-ink widths.
# No private CORE access, fitting, implied uncertainty, or file-system I/O.
namespace eval ::GX::CurveDigitizerStrokeWidth {
    variable apiVersion 1
    variable schema gxtxt.curve_digitizer.stroke_width.v1
    variable ownApiDirectory [file dirname [info script]]
}

proc ::GX::CurveDigitizerStrokeWidth::_companionReady {} {
    variable ownApiDirectory
    if {![llength [info commands ::GX::CurveDigitizerCompanion::configurationRead]]} {
        source [file join $ownApiDirectory curve_digitizer_companion_api_v1.tcl]
    }
}

proc ::GX::CurveDigitizerStrokeWidth::configurationRead {documentId} {
    _companionReady
    # This is the documented Companion public read boundary. It uses the
    # current Session Interactive Document and its optimistic-source checks.
    set record [::GX::CurveDigitizerCompanion::configurationRead $documentId]
    set context [dict get $record configuration]
    set report [expr {[dict exists $context stroke_width_json] ?
        [dict get $context stroke_width_json] : "{}"}]
    return [dict create api_id CURVE_DIGITIZER_STROKE_WIDTH_API_v1 \
        schema_version 1 document_id $documentId \
        source_dataset_id [dict get $context source_dataset_id] \
        source_sha256 [dict get $context source_sha256] \
        stroke_width_json $report \
        interpretation {Per-curve descriptive raster line width in original pixels; no automatic metrological uncertainty or Numeric/Fitter propagation.}]
}

proc ::GX::CurveDigitizerStrokeWidth::curveRead {documentId curveId} {
    _companionReady
    if {[string trim $curveId] eq {}} {error {Curve ID is required.}}
    set context [::GX::CurveDigitizerCompanion::curveContext $documentId $curveId]
    foreach key {curve_id source_dataset_id source_sha256 stroke_width_status stroke_width_method stroke_width_px stroke_width_curve_json} {
        if {![dict exists $context $key]} {error "Companion missing public stroke-width field '$key'."}
    }
    return [dict create api_id CURVE_DIGITIZER_STROKE_WIDTH_API_v1 \
        schema_version 1 document_id $documentId \
        curve_id [dict get $context curve_id] \
        source_dataset_id [dict get $context source_dataset_id] \
        source_sha256 [dict get $context source_sha256] \
        status [dict get $context stroke_width_status] \
        method [dict get $context stroke_width_method] \
        width_px [dict get $context stroke_width_px] \
        curve_record_json [dict get $context stroke_width_curve_json] \
        propagated_uncertainty 0]
}

proc ::GX::CurveDigitizerStrokeWidth::hasPublished {datasetId} {
    if {[catch {set md [_publicationMetadata $datasetId]}]} {return 0}
    return [expr {[dict exists $md curve_digitizer.stroke_width_schema_version] &&
        [dict get $md curve_digitizer.stroke_width_schema_version] eq "1" &&
        [dict exists $md curve_digitizer.stroke_width_report_json]}]
}

proc ::GX::CurveDigitizerStrokeWidth::_publicationMetadata {datasetId} {
    if {[string trim $datasetId] eq {}} {error {Dataset ID is required.}}
    set session [::GX::sessionInspectionCurrentSession]
    ::GX::sessionInspectionDataset $datasetId $session
    set md [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $md curve_digitizer.plugin_id] ||
        [dict get $md curve_digitizer.plugin_id] ne "viewer.curve_digitizer"} {
        error {Dataset was not published by Curve Digitalizer.}
    }
    return $md
}

proc ::GX::CurveDigitizerStrokeWidth::publishedRead {datasetId} {
    set md [_publicationMetadata $datasetId]
    if {![dict exists $md curve_digitizer.stroke_width_schema_version] ||
        [dict get $md curve_digitizer.stroke_width_schema_version] ne "1" ||
        ![dict exists $md curve_digitizer.stroke_width_report_json]} {
        error {Published Dataset has no Stroke Width API v1 metadata; republish it.}
    }
    set source [expr {[dict exists $md curve_digitizer.source_dataset_id] ?
        [dict get $md curve_digitizer.source_dataset_id] : ""}]
    set sha [expr {[dict exists $md curve_digitizer.source_sha256] ?
        [dict get $md curve_digitizer.source_sha256] : ""}]
    return [dict create api_id CURVE_DIGITIZER_STROKE_WIDTH_API_v1 \
        schema_version 1 dataset_id $datasetId \
        source_dataset_id $source source_sha256 $sha \
        report_json [dict get $md curve_digitizer.stroke_width_report_json] \
        propagated_uncertainty 0 \
        interpretation {Per-curve descriptive raster stroke width; not a statistical uncertainty nor a substitute for a qualified uncertainty model.}]
}
