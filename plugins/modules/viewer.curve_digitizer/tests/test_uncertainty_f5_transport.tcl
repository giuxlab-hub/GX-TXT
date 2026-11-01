# SPDX-License-Identifier: GPL-3.0-or-later
# Real F5 Curve Digitalizer Tcl transport/guard, with scientific owner stubs.
package require json
package require sha256
namespace eval ::GX::ScientificTransportv1 {}
proc ::GX::ScientificTransportv1::array {shape values} {
    return [dict create shape $shape values $values]
}
proc ::GX::ScientificTransportv1::text {value} {return $value}
proc ::GX::ScientificTransportv1::struct {value} {return $value}
proc ::GX::sessionInspectionCurrentSession {} {return /tmp/f5_inert_session}
proc ::GX::datasetStorageSha256Bytes {session raw} {
    return [::sha2::sha256 -hex $raw]
}
proc assert {actual expected message} {
    if {$actual ne $expected} {
        error "$message: expected '$expected', received '$actual'"
    }
}
proc requireError {body what} {
    if {![catch {uplevel 1 $body} message]} {
        error "$what should have failed before CORE writer."
    }
}
source [file join [file dirname [info script]] .. api curve_digitizer_numeric_core.tcl]
set input [open [lindex $argv 0] r]
fconfigure $input -encoding utf-8 -translation lf
set packets [split [string trim [read $input]] "\n"]
close $input
set measurement meas_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
assert [llength $packets] 3 packet_count
lassign [::GX::CurveDigitizerNumericCore::_inline [lindex $packets 0] $measurement 4] lin spec
assert [dict get $lin calibration_jacobian shape] {8 14} dynamic_14_jac
assert [dict get $spec calibration_standard_uncertainty shape] {1 14} dynamic_14_unc
assert [llength [dict get $lin calibration_ids items]] 14 shared_identifiers
assert [dict get $lin coordinates shape] {4 2} physical_coordinates
assert [dict get $lin point_jacobian shape] {8 2} local_jac
lassign [::GX::CurveDigitizerNumericCore::_inline [lindex $packets 1] $measurement 4] lin spec
assert [dict get $lin calibration_jacobian shape] {8 14} override_14_jac
assert [dict get $spec override_standard_uncertainty shape] {4 2} override_matrix
set overrides [dict get $spec override_standard_uncertainty values]
assert [llength $overrides] 8 override_values_count
foreach got [lrange $overrides 0 3] {
    if {abs(double($got)-0.1)>1e-14} {error {Wrong X physical override}}
}
foreach got [lrange $overrides 4 7] want {0.2 0.7 0.2 0.7} {
    if {abs(double($got)-double($want))>1e-14} {
        error {Wrong Y1/Y2 physical override}
    }
}
lassign [::GX::CurveDigitizerNumericCore::_inline [lindex $packets 2] $measurement 4] lin spec
assert [dict get $lin calibration_jacobian shape] {8 12} legacy_12_jac
assert [dict get $spec calibration_standard_uncertainty shape] {1 12} legacy_12_unc
requireError {::GX::CurveDigitizerNumericCore::_inline [lindex $packets 0] wrong_measurement 4} stale_measurement
requireError {::GX::CurveDigitizerNumericCore::_inline [lindex $packets 0] $measurement 3} wrong_row_count
set input [open [lindex $argv 1] r]
set testState [::json::json2dict [read $input]]
close $input
set state [dict get $testState state]
set record [dict get $testState factors]
assert [::GX::CurveDigitizerNumericCore::_checkPreflightFactors $record $state 4] verified factor_integrity
# A mismatched 14-parameter declaration cannot masquerade as legacy factor v1.
set broken [string map [list {zlib-base64-float64-le-v2} {zlib-base64-float64-le-v1}] $record]
requireError {::GX::CurveDigitizerNumericCore::_checkPreflightFactors $broken $state 4} mismatched_factor_schema
# Actual numerical factor errors must not be hidden by matching marginal sigma.
set corrupt $state
set sh [dict get $corrupt shared_factor]
set first [lindex $sh 0]
lset first 0 [expr {[lindex $first 0]+0.5}]
lset sh 0 $first
dict set corrupt shared_factor $sh
requireError {::GX::CurveDigitizerNumericCore::_checkPreflightFactors $record $corrupt 4} modified_CORE_factor
puts {PASS F5 Tcl transport: exact physical 14 shared inputs, physical Y1/Y2 overrides, legacy12, bounded retained factor guard}
