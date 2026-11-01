# SPDX-License-Identifier: GPL-3.0-or-later
# Hermetic F3 validation of the real Tcl backend, with public writer stubs only.
namespace eval ::GX {
  variable mockDefinition {}
  variable mockVariables {}
  variable mockAppend {}
  variable prepareCount 0
  variable mockSession /tmp/gxtxt_y2_mock_session
  variable mockSha [string repeat f 64]
}
proc ::GX::viewerBackendRegister {args} {}
proc ::GX::interactiveDocumentSessionToken {} {return session-token}
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::mockSession}
proc ::GX::sessionInspectionDataset {id session} {
  if {$id eq {original_image}} {
    return [dict create contract image.raster media_type image/png path original.png canonical_sha256 $::GX::mockSha format png]
  }
  error {No existing result}
}
proc ::GX::sessionInspectionResolveResource {path session} {
  return [dict create path $path sha256 $::GX::mockSha]
}
proc ::GX::datasetMetadataRead {session id} {return [dict create]}
proc ::GX::datasetPublicationV2Prepare {session module definition} {
  incr ::GX::prepareCount
  set ::GX::mockDefinition $definition
  return prepared
}
proc ::GX::datasetPublicationV2OpenWriter {plan} {return writer}
proc ::GX::datasetPublicationV2DeclareDimension {writer id size opts} {}
proc ::GX::datasetPublicationV2DeclareVariable {writer id spec} {
  dict set ::GX::mockVariables $id $spec
}
proc ::GX::datasetPublicationV2Append {writer dim data} {
  set ::GX::mockAppend $data
  return [llength [dict get $data x]]
}
proc ::GX::datasetPublicationV2Finalize {writer} {
  return [dict create dataset_id published path fake.csv sha256 $::GX::mockSha]
}
proc ::GX::datasetPublicationV2Abort {writer} {error {Unexpected abort}}
proc ::GX::datasetVariableSchemaUpdate {id changes} {}
proc ::GX::unitRegistryDefinition {unit} {return [dict create canonical_unit $unit]}
proc assert {actual expected why} {
  if {$actual ne $expected} {error "$why: expected $expected, got $actual"}
}
source [file join [file dirname [info script]] .. api curve_digitizer_viewer_api_v1.tcl]
set mid meas_0123456789abcdef0123456789abcdef
proc md {mode u1 u2 {combined 0}} {
  set metadata [dict create \
    curve_digitizer.source_dataset_id original_image \
    curve_digitizer.source_sha256 $::GX::mockSha \
    curve_digitizer.configuration_id digcfg_example \
    curve_digitizer.calibration_type affine \
    curve_digitizer.image_width 1600 curve_digitizer.image_height 900 \
    curve_digitizer.coordinate_origin bottom_left \
    curve_digitizer.y_direction up curve_digitizer.physical_unit {} \
    curve_digitizer.transform matrix curve_digitizer.manifest_version 1 \
    curve_digitizer.calibration_manifest "{}" \
    curve_digitizer.measurement_count 1 \
    curve_digitizer.publication_calibration_mode [expr {$combined ? "combined" : "separate"}] \
    curve_digitizer.publication_calibration_ids [format {["%s"]} $::mid] \
    curve_digitizer.publication_measurement_id $::mid \
    curve_digitizer.measurement.0.measurement_id $::mid \
    curve_digitizer.measurement.0.valid 1 \
    curve_digitizer.measurement.0.state accepted \
    curve_digitizer.measurement.0.transform.x_unit Hz \
    curve_digitizer.measurement.0.transform.y_unit $u1 \
    curve_digitizer.axis_schema_version 1 \
    curve_digitizer.curve_schema_version 2 \
    curve_digitizer.axis_mode $mode \
    curve_digitizer.axis_units_y1 $u1 \
    curve_digitizer.axis_units_y2 $u2 \
    curve_digitizer.axis_definitions_json {[{"measurement_id":"mock"}]} \
    curve_digitizer.curves_json {[{"curve_id":"gain"},{"curve_id":"phase"}]} \
    curve_digitizer.publication_set_id pubset_0123456789abcdef0123456789abcdef \
    curve_digitizer.curve_axis.gain y1 \
    curve_digitizer.curve_axis.phase y2]
  return $metadata
}
proc enc {metadata} {
  set lines {}
  dict for {k v} $metadata {
    lappend lines "[::GX::CurveDigitizer::_b64e $k]\t[::GX::CurveDigitizer::_b64e $v]"
  }
  return [join $lines "\n"]
}
proc row {curve axis x y {combined 0}} {
  set fields [list [::GX::CurveDigitizer::_b64e $curve] \
    [::GX::CurveDigitizer::_b64e "Curve $curve"] 0 $x $y {} 100.5 200.5]
  if {$combined} {
    lappend fields [::GX::CurveDigitizer::_b64e $::mid] \
                   [::GX::CurveDigitizer::_b64e {Measurement one}]
  }
  lappend fields [::GX::CurveDigitizer::_b64e [format "%s_p01" $curve]] $axis
  return [join $fields "\t"]
}
proc publish {u metadata rows {layout separate} {family generic}} {
  set args [list session-token idoc_0002 published {Y2 scientific test} $family \
    X Hz independent Y $u measured Family 1 family \
    original_image $::GX::mockSha affine log linear demo $rows \
    [enc $metadata] $layout {} {} {} 2]
  return [::GX::CurveDigitizer::_publish {*}$args]
}
set metadata [md mixed V V]
set rows [join [list [row gain y1 20 1] [row phase y2 30 2]] "\n"]
publish V $metadata $rows
set output [dict get $::GX::mockDefinition structured_metadata]
assert [dict get $output curve_digitizer.curve_schema_version] 2 schema
assert [dict get $output curve_digitizer.curve_column.y_axis_id] y_axis_id axis_column
assert [dict get $::GX::mockVariables y_axis_id semantic_role] curve_y_axis_identifier semantic
assert [dict get $::GX::mockAppend y_axis_id] {y1 y2} row_axes
assert [dict get $::GX::mockVariables y unit] V physical_unit
puts {PASS mixed-unit-compatible Y1/Y2 rows in one canonical Dataset}
set metadata [md y1 dB deg]
publish dB $metadata [row gain y1 20 -3]
assert [dict get $::GX::mockAppend y_axis_id] y1 split_y1
set metadata [md y2 dB deg]
publish deg $metadata [row phase y2 20 -45]
assert [dict get $::GX::mockAppend y_axis_id] y2 split_y2
assert [dict get $::GX::mockVariables y unit] deg split_unit
puts {PASS split Y1/Y2 preserve distinct variable units}
set metadata [md mixed V V 1]
publish V $metadata [join [list [row gain y1 20 1 1] [row phase y2 30 2 1]] "\n"] combined
assert [dict get $::GX::mockAppend calibration_id] [list $mid $mid] combined_measurements
assert [dict get $::GX::mockAppend y_axis_id] {y1 y2} combined_axes
puts {PASS combined calibration rows preserve both identities}
set before $::GX::prepareCount
set bad [md mixed V deg]
if {![catch {publish V $bad $rows}]} {error {Mixed different units accepted}}
assert $::GX::prepareCount $before preflight_no_write
set bad [md mixed V V]
if {![catch {publish V $bad [row gain right 20 1]}]} {error {Invalid axis accepted}}
if {![catch {publish V $bad [join [list [row gain y1 20 1] [row gain y2 30 2]] "\n"]}]} {
  error {One curve switched between axes}
}
dict set bad curve_digitizer.curve_axis.phase y1
if {![catch {publish V $bad $rows}]} {error {Metadata axis mismatch accepted}}
puts {PASS invalid units, unknown axes, inconsistent curve mappings refused before publish}
