# Headless publication contract test: simulate public CORE APIs, not CORE paths.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable mockDefinition {}
    variable mockVariables {}
    variable mockAppend {}
    variable mockDatasetContract table.generic
    variable mockSession /tmp/curve_digitizer_mock_session
    variable mockSha [string repeat a 64]
}
proc ::GX::viewerBackendRegister {args} {}
proc ::GX::interactiveDocumentSessionToken {} {return session-token}
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::mockSession}
proc ::GX::sessionInspectionDataset {datasetId session} {
    if {$datasetId eq "original_image"} {return [dict create contract image.raster media_type image/png path original_image.png canonical_sha256 $::GX::mockSha format png]}
    error "No existing result Dataset"
}
proc ::GX::sessionInspectionResolveResource {path session} {
    return [dict create path $path sha256 $::GX::mockSha]
}
proc ::GX::datasetMetadataRead {session id} {return [dict create]}
proc ::GX::datasetPublicationV2Prepare {session module request} {
    set ::GX::mockDefinition $request
    return prepared
}
proc ::GX::datasetPublicationV2OpenWriter {plan} {return writer}
proc ::GX::datasetPublicationV2DeclareDimension {writer id size options} {}
proc ::GX::datasetPublicationV2DeclareVariable {writer id spec} {dict set ::GX::mockVariables $id $spec}
proc ::GX::datasetPublicationV2Append {writer dimension data} {
    set ::GX::mockAppend $data
    return [llength [dict get $data x]]
}
proc ::GX::datasetPublicationV2Finalize {writer} {return [dict create dataset_id published path mock.csv sha256 $::GX::mockSha]}
proc ::GX::datasetPublicationV2Abort {writer} {error "Unexpected abort"}
proc ::GX::datasetVariableSchemaUpdate {datasetId changes} {}
proc ::GX::unitRegistryDefinition {unit} {return [dict create canonical_unit $unit]}
proc assert {actual expected what} {if {$actual ne $expected} {error "$what: expected $expected but was $actual"}}

source [file join [file dirname [info script]] .. api curve_digitizer_viewer_api_v1.tcl]
set rows [join [list "[::GX::CurveDigitizer::_b64e first]\t[::GX::CurveDigitizer::_b64e {Groove left}]\t0\t1.3\t2.4\t\t20.1\t40.2" "[::GX::CurveDigitizer::_b64e second]\t[::GX::CurveDigitizer::_b64e {Groove right}]\t0\t1.5\t2.0\t\t21.5\t42.0"] "\n"]
set b64 ::GX::CurveDigitizer::_b64e
set md [dict create curve_digitizer.source_dataset_id original_image curve_digitizer.source_sha256 $::GX::mockSha \
 curve_digitizer.configuration_id idoc_0002 curve_digitizer.calibration_type pixel \
 curve_digitizer.image_width 720 curve_digitizer.image_height 560 curve_digitizer.coordinate_origin bottom_left \
 curve_digitizer.y_direction up curve_digitizer.physical_unit px curve_digitizer.transform matrix \
 curve_digitizer.manifest_version 1 curve_digitizer.calibration_manifest {} \
 curve_digitizer.measurement_count 1 curve_digitizer.publication_calibration_mode separate \
 curve_digitizer.publication_calibration_ids {["meas_0123456789abcdef0123456789abcdef"]} \
 curve_digitizer.publication_measurement_id meas_0123456789abcdef0123456789abcdef \
 curve_digitizer.measurement.0.measurement_id meas_0123456789abcdef0123456789abcdef \
 curve_digitizer.measurement.0.valid 1 curve_digitizer.measurement.0.state accepted \
 curve_digitizer.measurement.0.transform.x_unit px curve_digitizer.measurement.0.transform.y_unit px]
set encoded {}
dict for {k v} $md {lappend encoded "[::GX::CurveDigitizer::_b64e $k]\t[::GX::CurveDigitizer::_b64e $v]"}
set metaRecords [join $encoded "\n"]
set callArgs [list session-token idoc_0002 published {Two grooves} generic X px independent Y px measured Family V family \
 original_image $::GX::mockSha full_image_pixels linear linear sem_00 $rows $metaRecords separate]
set receipt [::GX::CurveDigitizer::_publish {*}$callArgs]
set outmd [dict get $::GX::mockDefinition structured_metadata]
assert [dict get $outmd curve_digitizer.curve_schema_version] 1 schema_version
assert [dict get $outmd curve_digitizer.curve_mode] independent independent
assert [dict get $outmd curve_digitizer.curve_column.curve_key] curve_id curve_id_role
assert [dict get $outmd curve_digitizer.curve_column.curve_name] curve_label curve_name_role
assert [dict get $outmd curve_digitizer.curve_column.point_order] point_index order_role
assert [dict exists $outmd curve_digitizer.curve_column.family_parameter] 0 no_family_key
assert [dict get $::GX::mockVariables curve_id semantic_role] curve_series_identifier semantic_registry_id
assert [dict get $::GX::mockVariables curve_id value_kind] text text_kind
assert [dict get $::GX::mockVariables curve_label semantic_role] curve_series_label display_semantic_role
assert [dict get $::GX::mockVariables point_index semantic_role] curve_point_index order_semantic_role
assert [dict get $::GX::mockDefinition producer_version] 2.0.2 producer_version
assert [dict get $::GX::mockAppend curve_id] {first second} independent_groups
assert [dict get $::GX::mockAppend pixel_x] {20.1 21.5} original_raster_x
assert [dict get $::GX::mockAppend pixel_y] {40.2 42.0} original_raster_y
assert [dict get $outmd curve_digitizer.curve_column.raster_x] pixel_x raster_semantic_role
assert [dict get $outmd curve_digitizer.curve_column.raster_y] pixel_y raster_semantic_role
assert [dict get $::GX::mockVariables pixel_x semantic_role] curve_raster_x raster_registry_role

set familyRows [join [list "[::GX::CurveDigitizer::_b64e first]\t[::GX::CurveDigitizer::_b64e {Family 1}]\t0\t0.0\t2.5\t-2" "[::GX::CurveDigitizer::_b64e second]\t[::GX::CurveDigitizer::_b64e {Family 2}]\t0\t0.0\t4.0\t-4"] "\n"]
set familyArgs [lreplace $callArgs 4 4 family]
set familyArgs [lreplace $familyArgs 20 20 $familyRows]
set receipt [::GX::CurveDigitizer::_publish {*}$familyArgs]
set fammd [dict get $::GX::mockDefinition structured_metadata]
assert [dict get $fammd curve_digitizer.curve_mode] numerical_family family_mode
assert [dict get $fammd curve_digitizer.curve_column.family_parameter] family_value family_role
assert [dict get $::GX::mockAppend family_value] {-2 -4} family_values
assert [dict exists $fammd curve_digitizer.curve_column.raster_x] 0 legacy_row_compatibility
# Combined rows repeat original raster points but distinguish calibration realizations.
set mid meas_0123456789abcdef0123456789abcdef
set md2 $md
 dict set md2 curve_digitizer.publication_calibration_mode combined
set encoded {}
dict for {k v} $md2 {lappend encoded "[::GX::CurveDigitizer::_b64e $k]\t[::GX::CurveDigitizer::_b64e $v]"}
set combinedRows "[::GX::CurveDigitizer::_b64e first]\t[::GX::CurveDigitizer::_b64e {Groove left}]\t0\t1.3\t2.4\t\t20.1\t40.2\t[::GX::CurveDigitizer::_b64e $mid]\t[::GX::CurveDigitizer::_b64e {Calibration one}]"
set combinedArgs [lreplace $callArgs 20 20 $combinedRows]
set combinedArgs [lreplace $combinedArgs 21 21 [join $encoded "\n"]]
set combinedArgs [lreplace $combinedArgs 22 22 combined]
::GX::CurveDigitizer::_publish {*}$combinedArgs
set combinedMetadata [dict get $::GX::mockDefinition structured_metadata]
assert [dict get $combinedMetadata curve_digitizer.curve_column.calibration_key] calibration_id calibration_semantic
assert [dict get $::GX::mockAppend calibration_id] [list $mid] combined_calibration_key
assert [dict get $::GX::mockVariables calibration_id semantic_role] curve_calibration_identifier calibration_variable_role
puts "PASS: new raster columns, legacy rows, separate/combined, independent/family, semantics"
