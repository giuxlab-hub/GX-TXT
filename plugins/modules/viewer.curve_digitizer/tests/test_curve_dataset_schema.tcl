# Standalone public Dataset Schema API contract exercise (no GX-TXT disk writes).
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable currentSession /tmp/gxtxt_test_current_session
    variable mockContract table.generic
    variable mockMetadata {}
    variable mockVariables {}
}
proc ::GX::sessionInspectionCurrentSession {} { return $::GX::currentSession }
proc ::GX::sessionInspectionDataset {datasetId session} {
    if {$datasetId ne "test_curves" || $session ne $::GX::currentSession} { error "Unknown Dataset" }
    return [dict create id $datasetId contract $::GX::mockContract]
}
proc ::GX::datasetMetadataRead {session datasetId} { return $::GX::mockMetadata }
proc ::GX::datasetVariableV3ById {datasetId varId} {
    if {![dict exists $::GX::mockVariables $varId]} { error "Unknown variable: $varId" }
    return [dict get $::GX::mockVariables $varId]
}
proc assert {actual expected label} {
    if {$actual ne $expected} { error "$label: expected '$expected' got '$actual'" }
}
proc expectError {body match} {
    if {![catch {uplevel 1 $body} error]} { error "Expected error matching $match" }
    if {![string match "*$match*" $error]} { error "Wrong error: $error" }
}

source [file join [file dirname [info script]] .. api curve_digitizer_dataset_schema_api_v1.tcl]
set ::GX::mockMetadata [dict create \
    curve_digitizer.plugin_id viewer.curve_digitizer \
    curve_digitizer.curve_schema_version 1 \
    curve_digitizer.curve_mode independent \
    curve_digitizer.curve_grouping curve_key \
    curve_digitizer.curve_row_dimension row]
# Deliberately rename ALL the technical Variable IDs: consumers must still work.
set technical [dict create x zz_X y yy_Y curve_key membership curve_name title point_order sequence family_parameter u_parameter]
foreach role {x y curve_key curve_name point_order family_parameter} {
    set var [dict get $technical $role]
    if {$role in {x y family_parameter}} {set dtype float64} elseif {$role eq "point_order"} {set dtype int64} else {set dtype string}
    dict set ::GX::mockVariables $var [dict create variable_id $var dtype $dtype rank 1 dimension_ids row display_label "Completely arbitrary label"]
    if {$role ne "family_parameter"} {dict set ::GX::mockMetadata curve_digitizer.curve_column.$role $var}
}
set m [::GX::CurveDigitizerDataset::read test_curves]
assert [dict get $m mode] independent "Independent classification"
assert [dict get $m columns curve_key] membership "Renamed variable ID lookup"
assert [dict get $m columns curve_name] title "Display label not semantic source"
assert [::GX::CurveDigitizerDataset::column test_curves point_order] sequence "Semantic lookup"
assert [dict get $m legacy_inferred] 0 "New contract"
assert [::GX::CurveDigitizerDataset::hasSchema test_curves] 1 "Positive discovery"
expectError {::GX::CurveDigitizerDataset::column test_curves family_parameter} "No 'family_parameter'"

set ::GX::mockContract curve_family.table
dict set ::GX::mockMetadata curve_digitizer.curve_mode numerical_family
dict set ::GX::mockMetadata curve_digitizer.curve_column.family_parameter u_parameter
set m [::GX::CurveDigitizerDataset::read test_curves]
assert [dict get $m columns family_parameter] u_parameter "Family mapping"
assert [dict get $m grouping_role] curve_key "Family still groups by curve key"

# Combined realization mapping: consumers must group by curve AND calibration.
foreach {role var dtype} {calibration_key cal_technical string calibration_name cal_title string} {
    dict set ::GX::mockVariables $var [dict create variable_id $var dtype $dtype rank 1 dimension_ids row display_label "arbitrary"]
    dict set ::GX::mockMetadata curve_digitizer.curve_column.$role $var
}
dict set ::GX::mockMetadata curve_digitizer.curve_grouping curve_key_and_calibration_key
set combined [::GX::CurveDigitizerDataset::read test_curves]
assert [dict get $combined grouping_roles] {curve_key calibration_key} "Composite curve grouping"
assert [dict get $combined publication_calibration_mode] combined "Combined publication mode"
assert [dict get $combined columns calibration_key] cal_technical "Calibration identity independent of Variable ID"
dict unset ::GX::mockMetadata curve_digitizer.curve_column.calibration_name
expectError {::GX::CurveDigitizerDataset::read test_curves} "Combined publications require"
dict set ::GX::mockMetadata curve_digitizer.curve_column.calibration_name cal_title
dict set ::GX::mockMetadata curve_digitizer.curve_grouping curve_key
# optional key mapping is not a mandatory grouping role for separate outputs
foreach role {calibration_key calibration_name} {
    dict unset ::GX::mockMetadata curve_digitizer.curve_column.$role
}

set ::GX::mockContract table.generic
expectError {::GX::CurveDigitizerDataset::read test_curves} "disagree"
set ::GX::mockContract curve_family.table
set old [dict get $::GX::mockMetadata curve_digitizer.curve_column.curve_key]
dict set ::GX::mockMetadata curve_digitizer.curve_column.curve_key yy_Y
expectError {::GX::CurveDigitizerDataset::read test_curves} "Two semantic roles"
dict set ::GX::mockMetadata curve_digitizer.curve_column.curve_key $old
set oldType [dict get $::GX::mockVariables membership dtype]
dict set ::GX::mockVariables membership dtype float64
expectError {::GX::CurveDigitizerDataset::read test_curves} "must refer to a text variable"
dict set ::GX::mockVariables membership dtype $oldType

dict unset ::GX::mockMetadata curve_digitizer.curve_column.point_order
expectError {::GX::CurveDigitizerDataset::read test_curves} "Missing semantic column mapping"
# No manifest: exact original technical layout, verified against V3; no label guessing.
set ::GX::mockContract table.generic
set ::GX::mockMetadata [dict create curve_digitizer.plugin_id viewer.curve_digitizer]
foreach {role var dtype} {x x float64 y y float64 curve_key curve_id string curve_name curve_label string point_order point_index int64} {
    dict set ::GX::mockVariables $var [dict create variable_id $var dtype $dtype rank 1 dimension_ids row display_label "does not matter"]
}
set m [::GX::CurveDigitizerDataset::read test_curves]
assert [dict get $m legacy_inferred] 1 "Legacy marked explicitly"
assert [dict get $m columns curve_key] curve_id "Legacy technical ID"
dict unset ::GX::mockVariables curve_id
expectError {::GX::CurveDigitizerDataset::read test_curves} "Unknown variable"
set ::GX::mockMetadata [dict create curve_digitizer.plugin_id not-the-digitizer]
expectError {::GX::CurveDigitizerDataset::read test_curves} "not published"
puts "PASS: 13 public-contract checks, renamed IDs, legacy and malformed states"
