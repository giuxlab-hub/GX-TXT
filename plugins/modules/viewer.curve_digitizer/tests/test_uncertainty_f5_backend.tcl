# SPDX-License-Identifier: GPL-3.0-or-later
# F5: exercise real Tcl _publish with mocked CORE Numeric/Publication receipts.
source [file join [file dirname [info script]] test_y2_f3_publication_api.tcl]
namespace eval ::GX {
    variable lastF5Metadata {}
    variable numericInvocations 0
}
proc ::GX::datasetMetadataUpdate {session datasetId fields} {
    set ::GX::lastF5Metadata $fields
}
rename ::GX::CurveDigitizerNumericCore::propagate ::GX::CurveDigitizerNumericCore::originalPropagate
proc ::GX::CurveDigitizerNumericCore::propagate {doc rowsText selected rows dataset sha inline factors} {
    incr ::GX::numericInvocations
    if {$inline ne "reviewed_M14_numeric_packet" || $factors eq {}} {
        error {Numeric core review missing or different}
    }
    set c [dict create x [dict get $rows x] y [dict get $rows y] \
        sigma_x {0.5 0.5} sigma_y {0.6 0.7} covariance_xy {0.03 0.04}]
    return [dict create columns $c resources [dict create state mock_mat_ref] \
        point_count 2]
}
proc payload {} {
    set report {{"schema":"gxtxt.curve_digitizer.uncertainty.v2","calibration_input_count":14,"mode":"pixel_calibration"}}
    set factor {{"format":"zlib-base64-float64-le-v2","shape_shared":[4,14]}}
    set lines [list [::GX::CurveDigitizer::_b64e $report] [::GX::CurveDigitizer::_b64e $factor]]
    foreach {cid pid x y sx sy cov} {gain gain_p01 20 1 0.5 0.6 0.03 phase phase_p01 30 2 0.5 0.7 0.04} {
        lappend lines [join [list [::GX::CurveDigitizer::_b64e $cid] \
            [::GX::CurveDigitizer::_b64e $pid] [::GX::CurveDigitizer::_b64e $::mid] \
            $x $y $sx $sy $cov] "\t"]
    }
    return [join $lines "\n"]
}
proc publish_f5 {core {unc {}}} {
    if {$unc eq {}} {set unc [payload]}
    set md [md mixed V V]
    set rows [join [list [row gain y1 20 1] [row phase y2 30 2]] "\n"]
    set args [list session-token idoc_0002 published {Y2 F5 numeric test} generic \
        X Hz independent Y V measured Family 1 family \
        original_image $::GX::mockSha affine log linear demo $rows \
        [enc $md] separate {} $unc $core 2]
    return [::GX::CurveDigitizer::_publish {*}$args]
}
set before $::GX::prepareCount
set receipt [publish_f5 reviewed_M14_numeric_packet]
assert [dict get $::GX::mockDefinition structured_metadata curve_digitizer.uncertainty_schema_version] 2 schema
assert [dict get $::GX::mockDefinition structured_metadata curve_digitizer.uncertainty_covariance_xy_unit] Hz*V covariance_unit
assert [dict get $::GX::mockAppend sigma_x] {0.5 0.5} sigma_x
assert [dict get $::GX::mockAppend sigma_y] {0.6 0.7} sigma_y
assert [dict get $::GX::mockAppend covariance_xy] {0.03 0.04} covariance
assert [dict get $::GX::mockAppend y_axis_id] {y1 y2} y_axis_bindings
assert [dict get $::GX::lastF5Metadata curve_digitizer.uncertainty_dataset_sha256] $::GX::mockSha retention_identity
assert $::GX::numericInvocations 1 numeric_called_once
puts {PASS F5 Tcl publisher: canonical sigma/cov columns and retained CORE binding for mixed Y1/Y2}
# Rejected payload must not reach CORE Prepare, even when a Numeric stub exists.
set before $::GX::prepareCount
if {![catch {publish_f5 {}}]} {
    error {Missing CORE linearization was not refused}
}
assert $::GX::prepareCount $before missing_core_no_publication
set badRows [split [payload] "\n"]
set badFactor [::GX::CurveDigitizer::_b64d [lindex $badRows 1]]
set badFactor [string map [list {zlib-base64-float64-le-v2} {zlib-base64-float64-le-v1}] $badFactor]
lset badRows 1 [::GX::CurveDigitizer::_b64e $badFactor]
set bad [join $badRows "\n"]
if {![catch {publish_f5 reviewed_M14_numeric_packet $bad}]} {
    error {M12 factors were accepted for Y2}
}
assert $::GX::prepareCount $before bad_factors_no_publication
puts {PASS F5 backend fails closed before canonical Dataset Prepare without M14 evidence}
