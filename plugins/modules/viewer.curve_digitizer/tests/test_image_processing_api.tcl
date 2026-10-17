# Headless, public-contract test for the processed Image Dataset read facade.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable sampleSha [string repeat a 64]
    variable derivedSha [string repeat b 64]
    variable metadata [dict create \
        curve_digitizer.image_processing.schema_version 1 \
        curve_digitizer.image_processing.producer_id viewer.curve_digitizer \
        curve_digitizer.image_processing.source_dataset_id original \
        curve_digitizer.image_processing.source_display_name {Source SEM photo} \
        curve_digitizer.image_processing.source_sha256 [string repeat a 64] \
        curve_digitizer.image_processing.engine ImageMagick \
        curve_digitizer.image_processing.engine_version {ImageMagick 7.1 test} \
        curve_digitizer.image_processing.geometry_preserved 1 \
        curve_digitizer.image_processing.pixel_transform identity \
        curve_digitizer.image_processing.image_width 10 \
        curve_digitizer.image_processing.image_height 6 \
        curve_digitizer.image_processing.operation_count 2 \
        curve_digitizer.image_processing.operation.0.kind grayscale \
        curve_digitizer.image_processing.operation.0.value {} \
        curve_digitizer.image_processing.operation.1.kind gamma \
        curve_digitizer.image_processing.operation.1.value 0.85 \
        curve_digitizer.image_processing.fingerprint [string repeat c 64]]
}
proc ::GX::sessionInspectionCurrentSession {} {return /tmp/processed_image_test}
proc ::GX::sessionInspectionDataset {did session} {
    if {$did eq {processed}} {return [dict create contract image.raster canonical_sha256 $::GX::derivedSha]}
    if {$did eq {original}} {return [dict create contract image.raster canonical_sha256 $::GX::sampleSha]}
    error "Unknown Dataset '$did'"
}
proc ::GX::datasetMetadataRead {session did} {
    if {$did eq {processed}} {return $::GX::metadata}
    return [dict create]
}
source [file join [file dirname [info script]] .. api curve_digitizer_image_processing_api_v1.tcl]
set m [::GX::CurveDigitizerImage::read processed]
if {[dict get $m source_dataset_id] ne {original}} {error {incorrect source}}
if {[dict get $m image_width] != 10 || [dict get $m geometry_preserved] != 1} {error {geometry mismatch}}
if {[llength [dict get $m processing_operations]] != 2} {error {lost processing order}}
if {[dict get [lindex [dict get $m processing_operations] 1] value] ne {0.85}} {error {gamma mismatch}}
set chain [::GX::CurveDigitizerImage::lineage processed]
if {[llength $chain] != 2 || [dict get [lindex $chain end] original] != 1} {error {invalid lineage}}
if {![::GX::CurveDigitizerImage::hasManifest processed] || [::GX::CurveDigitizerImage::hasManifest original]} {
    error {hasManifest classification failure}
}
set saved $::GX::metadata
dict set ::GX::metadata curve_digitizer.image_processing.geometry_preserved 0
if {![catch {::GX::CurveDigitizerImage::read processed}]} {error {incorrectly accepted transformed geometry}}
set ::GX::metadata $saved
dict set ::GX::metadata curve_digitizer.image_processing.operation.1.kind rotate
if {![catch {::GX::CurveDigitizerImage::read processed}]} {error {unrecognized operation accepted}}
set ::GX::metadata $saved
set ::GX::sampleSha [string repeat d 64]
if {![catch {::GX::CurveDigitizerImage::lineage processed}]} {error {modified source SHA not detected}}
puts {PASS image manifest, ordered filters, legacy image, source SHA lineage and invalid geometry}
