# SPDX-License-Identifier: GPL-3.0-or-later
# Calibration API v1 additive methods; CORE dependencies mocked, no file I/O.
namespace eval ::GX {
    variable session /tmp/calib-session
    variable md {}
}
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::session}
proc ::GX::sessionInspectionDataset {id session} {
    if {$id ne "published" || $session ne $::GX::session} {error "Unknown Dataset"}
    return [dict create id $id contract table.generic]
}
proc ::GX::datasetMetadataRead {session id} {return $::GX::md}
proc assert_close {actual expected where {tol 1e-7}} {
    if {abs(double($actual)-double($expected)) > $tol} {
        error "$where: actual=$actual expected=$expected"
    }
}
proc assert_eq {actual expected where} {if {$actual ne $expected} {error "$where: actual=$actual expected=$expected"}}
proc fail_code {body expected} {
    if {![catch {uplevel 1 $body} reason opts]} {error "Expected error $expected"}
    if {[lrange [dict get $opts -errorcode] 0 [llength $expected]-1] ne $expected} {
        error "Unexpected error: $reason, [dict get $opts -errorcode]"
    }
}
source [file join [file dirname [info script]] .. api curve_digitizer_calibration_api_v1.tcl]
set digest [string repeat a 64]
set ::GX::md [dict create \
    curve_digitizer.plugin_id viewer.curve_digitizer \
    curve_digitizer.manifest_version 1 \
    curve_digitizer.source_dataset_id original-image \
    curve_digitizer.source_sha256 [string repeat b 64] \
    curve_digitizer.configuration_id idoc_01 \
    curve_digitizer.calibration_type projective \
    curve_digitizer.image_width 720 curve_digitizer.image_height 560 \
    curve_digitizer.coordinate_origin bottom_left curve_digitizer.y_direction up \
    curve_digitizer.physical_unit um \
    curve_digitizer.transform.convention column_vector_homogeneous_xy1 \
    curve_digitizer.transform.raster_origin top_left \
    curve_digitizer.transform.pixel_reference pixel_center \
    curve_digitizer.calibration_id cal_[string range $digest 0 23] \
    curve_digitizer.calibration_sha256 $digest \
    curve_digitizer.raster_geometry.source_to_calibration identity \
    curve_digitizer.calibration_method.type projective \
    curve_digitizer.calibration_method.point_selection manual_four_corners]
set H [list [list [expr {1.0/719.0}] 0.0 0.0] [list 0.0 [expr {-1.0/559.0}] 1.0] [list 0.0 0.0 1.0]]
for {set i 0} {$i<3} {incr i} {for {set j 0} {$j<3} {incr j} {
    dict set ::GX::md curve_digitizer.transform.h${i}${j} [lindex $H $i $j]
}}
foreach axis {x y} {
    dict set ::GX::md curve_digitizer.transform.${axis}_minimum 0
    dict set ::GX::md curve_digitizer.transform.${axis}_maximum [expr {$axis eq "x" ? 71.9 : 55.9}]
    dict set ::GX::md curve_digitizer.transform.${axis}_scale linear
    dict set ::GX::md curve_digitizer.transform.${axis}_unit um
}
set result [::GX::CurveDigitizerCalibration::transformPoints published {{0 0} {719 559} {123.5 330.5}} pixel_to_scientific]
assert_close [lindex $result 0 0] 0 origin-x
assert_close [lindex $result 0 1] 55.9 origin-y
assert_close [lindex $result 1 0] 71.9 last-x
assert_close [lindex $result 1 1] 0 last-y
set reverse [::GX::CurveDigitizerCalibration::transformPoints published $result scientific_to_pixel]
for {set i 0} {$i<3} {incr i} {
    foreach j {0 1} {assert_close [lindex $reverse $i $j] [lindex {{0 0} {719 559} {123.5 330.5}} $i $j] roundtrip}
}
set j [lindex [::GX::CurveDigitizerCalibration::jacobian published {{10 10}}] 0]
assert_eq [dict get $j valid] 1 valid
assert_close [lindex [dict get $j jacobian] 0 0] 0.1 Jxx
assert_close [lindex [dict get $j jacobian] 1 1] -0.1 Jyy
set un [lindex [::GX::CurveDigitizerCalibration::pointUncertainty published {{10 10}}] 0]
assert_eq [dict get $un status] unavailable unavailable_not_zero
set id [::GX::CurveDigitizerCalibration::identity published]
assert_eq [dict get $id calibration_id] cal_[string range $digest 0 23] fingerprint
fail_code {::GX::CurveDigitizerCalibration::transformPoints published {{720 0}} pixel_to_scientific} {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN}
fail_code {::GX::CurveDigitizerCalibration::transformPoints published {{-1 0}} pixel_to_scientific} {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN}
fail_code {::GX::CurveDigitizerCalibration::transformPoints published {{10 -1}} scientific_to_pixel} {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN}
# Logarithmic axis exact forward and reverse, including nonpositive rejection.
dict set ::GX::md curve_digitizer.transform.x_minimum 1
dict set ::GX::md curve_digitizer.transform.x_maximum 100
dict set ::GX::md curve_digitizer.transform.x_scale log
set val [::GX::CurveDigitizerCalibration::transformPoints published {{359.5 100}} pixel_to_scientific]
assert_close [lindex $val 0 0] 10 log_middle 1e-6
set r [::GX::CurveDigitizerCalibration::transformPoints published $val scientific_to_pixel]
assert_close [lindex $r 0 0] 359.5 log_inverse
fail_code {::GX::CurveDigitizerCalibration::transformPoints published {{0 40}} scientific_to_pixel} {CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN}
# A projective rather than affine matrix still roundtrips correctly.
dict set ::GX::md curve_digitizer.transform.h20 0.0001
set val [::GX::CurveDigitizerCalibration::transformPoints published {{100 200}} pixel_to_scientific]
set r [::GX::CurveDigitizerCalibration::transformPoints published $val scientific_to_pixel]
assert_close [lindex $r 0 0] 100 projective_inverse_x
assert_close [lindex $r 0 1] 200 projective_inverse_y
# Report only real provided uncertainty.
dict set ::GX::md curve_digitizer.uncertainty {"pixel_sigma_px":0.4}
dict set ::GX::md curve_digitizer.uncertainty.pixel_sigma_px 0.4
set un [lindex [::GX::CurveDigitizerCalibration::pointUncertainty published {{100 200}}] 0]
assert_eq [dict get $un status] reported_and_propagated propagated
if {[dict get $un output_sigma_x] <= 0 || [dict get $un output_sigma_y] <= 0} {error "Invalid uncertainty"}
puts "PASS calibration: roundtrip, log, projective, Jacobian, bounds, fingerprint and explicit uncertainty"
