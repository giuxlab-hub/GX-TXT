# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable modified 0;variable actualsha [string repeat a 64] }
namespace eval ::GX::CurveDigitizerCompanion {}
proc ::GX::modulePublicApiActivate {args} {}
proc ::GX::CurveDigitizerCompanion::publicationUncertainty {dataset} {
    if {$dataset ne {output}} {error {Unexpected Dataset}}
    return [dict create meaning CORE_validated binding [dict create dataset_id $dataset]]
}
proc ::GX::sessionInspectionCurrentSession {} {return /session}
proc ::GX::sessionInspectionDataset {id session} {
    if {$id eq {output}} {return [dict create contract table.generic canonical_sha256 [string repeat b 64]]}
    if {$id eq {source}} {return [dict create path image.png contract image.raster canonical_sha256 [string repeat a 64]]}
    error {missing dataset}
}
proc ::GX::sessionInspectionResolveResource {path session} {return [dict create path $path sha256 $::GX::actualsha]}
proc ::GX::datasetMetadataRead {session id} {return $::GX::md}
set ::GX::md [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
    curve_digitizer.uncertainty_schema_version 2 \
    curve_digitizer.uncertainty_binding [dict create schema gxtxt.digitizer_publication_binding.v1] \
    curve_digitizer.uncertainty_report_json {"schema":"gxtxt.curve_digitizer.uncertainty.v2"} \
    curve_digitizer.uncertainty_factors_json {"format":"zlib-base64-float64-le-v1"} \
    curve_digitizer.uncertainty_point_count 5 \
    curve_digitizer.source_dataset_id source \
    curve_digitizer.source_sha256 [string repeat a 64] \
    curve_digitizer.uncertainty_source_sha256 [string repeat a 64] \
    curve_digitizer.uncertainty_dataset_sha256 [string repeat b 64]]
source [file join [file dirname [info script]] .. api curve_digitizer_uncertainty_api_v1.tcl]
if {![::GX::CurveDigitizerUncertainty::hasReport output]} {error {Missing uncertainty}}
set r [::GX::CurveDigitizerUncertainty::read output]
if {[dict get $r source_integrity] ne {verified} || [dict get $r point_count] ne {5}} {error {Bad verified uncertainty reader}}
set ::GX::actualsha [string repeat c 64]
if {[dict get [::GX::CurveDigitizerUncertainty::read output] source_integrity] ne {changed}} {error {Changed source not detected}}
dict set ::GX::md curve_digitizer.uncertainty_dataset_sha256 [string repeat d 64]
if {![catch {::GX::CurveDigitizerUncertainty::read output}]} {error {Changed canonical output not rejected}}
puts {PASS: uncertainty v2 reader, source verification and immutable canonical byte binding}
