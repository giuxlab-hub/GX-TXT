# SPDX-License-Identifier: GPL-3.0-or-later
# Public read-only uncertainty for Curve Digitizer 2.0 datasets.
# This does not change canonical Dataset bytes or invoke GUI dependencies.
namespace eval ::GX::CurveDigitizerUncertainty {}
proc ::GX::CurveDigitizerUncertainty::_read {datasetId} {
    if {[string trim $datasetId] eq {}} {error {Dataset ID required.}}
    set session [::GX::sessionInspectionCurrentSession]
    set ds [::GX::sessionInspectionDataset $datasetId $session]
    set md [::GX::datasetMetadataRead $session $datasetId]
    foreach {key expected} {curve_digitizer.plugin_id viewer.curve_digitizer curve_digitizer.uncertainty_schema_version 2} {
        if {![dict exists $md $key] || [dict get $md $key] ne $expected} {
            error {This Dataset does not have the Curve Digitizer 2.0 uncertainty publication contract.}
        }
    }
    foreach key {curve_digitizer.uncertainty_report_json curve_digitizer.uncertainty_factors_json curve_digitizer.uncertainty_dataset_sha256 curve_digitizer.uncertainty_point_count} {
        if {![dict exists $md $key]} {error "Uncertainty binding is missing $key."}
    }
    set canonical {}
    foreach key {canonical_sha256 sha256} {
        if {[dict exists $ds $key]} {set canonical [dict get $ds $key];break}
    }
    if {$canonical ne {} && ![string equal -nocase $canonical [dict get $md curve_digitizer.uncertainty_dataset_sha256]]} {
        error {Digitized Dataset bytes have changed since the uncertainty publication.}
    }
    # This API is now CORE-qualified: a v2.0 local-only report must NOT be
    # mistaken for an admissible correlated covariance/Fitter publication.
    if {![dict exists $md curve_digitizer.uncertainty_binding]} {
        error {Dataset lacks a dev097 CORE-reviewed uncertainty binding; republish through 2.0.2.}
    }
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
    set verified [::GX::CurveDigitizerCompanion::publicationUncertainty $datasetId]
    if {$verified eq {}} {error {CORE uncertainty binding is unavailable or invalid.}}
    set sourceId [dict get $md curve_digitizer.source_dataset_id]
    if {[dict get $md curve_digitizer.uncertainty_source_sha256] ne [dict get $md curve_digitizer.source_sha256]} {
        error {Uncertainty source binding differs from Dataset source identity.}
    }
    set integrity unknown
    if {[catch {set src [::GX::sessionInspectionDataset $sourceId $session]}]} {
        set integrity missing
    } else {
        set measured {}
        if {[dict exists $src path]} {
            if {![catch {set resolved [::GX::sessionInspectionResolveResource [dict get $src path] $session]}] &&
                [dict exists $resolved sha256]} {
                set measured [dict get $resolved sha256]
            }
        }
        if {$measured ne {}} {
            set integrity [expr {[string equal -nocase $measured [dict get $md curve_digitizer.source_sha256]] ? {verified} : {changed}}]
        } else {
            # A catalog digest is a registry identity, not proof of bytes.
            set integrity unverified
        }
    }
    return [dict create dataset_id $datasetId source_dataset_id $sourceId \
        source_integrity $integrity point_count [dict get $md curve_digitizer.uncertainty_point_count] \
        dataset_sha256 [dict get $md curve_digitizer.uncertainty_dataset_sha256] \
        report_json [dict get $md curve_digitizer.uncertainty_report_json] \
        factors_json [dict get $md curve_digitizer.uncertainty_factors_json] \
        core_meaning [dict get $verified meaning] \
        core_binding [dict get $verified binding]]
}
proc ::GX::CurveDigitizerUncertainty::hasReport {datasetId} {
    expr {![catch {_read $datasetId}]}
}
proc ::GX::CurveDigitizerUncertainty::read {datasetId} {
    set full [_read $datasetId]
    dict set full schema gxtxt.curve_digitizer.uncertainty.v2
    dict set full api_id CURVE_DIGITIZER_UNCERTAINTY_API_v1
    dict set full api_version 1
    return $full
}
proc ::GX::CurveDigitizerUncertainty::reportJson {datasetId} {
    dict get [_read $datasetId] report_json
}
proc ::GX::CurveDigitizerUncertainty::factorsJson {datasetId} {
    dict get [_read $datasetId] factors_json
}

# Public numerical meaning: validated and qualified by CORE, not by the GUI.
proc ::GX::CurveDigitizerUncertainty::coreMeaning {datasetId} {
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
    return [::GX::CurveDigitizerCompanion::publicationUncertainty $datasetId]
}
proc ::GX::CurveDigitizerUncertainty::publishCovariance {datasetId outputDatasetId axis} {
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
    return [::GX::CurveDigitizerCompanion::publishCovariance $datasetId $outputDatasetId $axis]
}
