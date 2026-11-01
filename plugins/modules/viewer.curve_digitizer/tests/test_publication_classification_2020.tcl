# SPDX-License-Identifier: GPL-3.0-or-later
# Extract the ACTUAL validation block from the distribution's Tcl
# publication handler. Execute against synthetic metadata, no GX-TXT host.
set root [file normalize [file join [file dirname [info script]] ..]]
set sourceFile [file join $root api curve_digitizer_viewer_api_v1.tcl]
set ch [open $sourceFile r];set source [read $ch];close $ch
set begin [string first {    set expectedClass [dict get $calibrationMetadata curve_digitizer.calibration_type]} $source]
set end [string first {    set metadata [dict create} $source $begin]
if {$begin<0 || $end <= $begin} {error {Could not isolate the live publication classification contract}}
set checker [string range $source $begin [expr {$end-1}]]
proc validate {report manifest} {
    set calibrationType $report
    set calibrationMetadata [dict create curve_digitizer.calibration_type $manifest]
    uplevel 0 $::checker
    return $reportedClass
}
proc check {actual expected label} {if {$actual ne $expected} {error "FAIL $label: expected '$expected', got '$actual'"}}
check [validate affine affine] affine {physical-axis full image}
check [validate projective projective] projective {projective scientific mapping}
check [validate pixel pixel] pixel {true source pixel axis}
check [validate full_image_pixels pixel] pixel {legacy source-pixel alias}
check [validate scale_bar scale_bar] scale_bar {source physical scale bar}
check [validate full_image_scale_bar scale_bar] scale_bar {legacy scale-bar alias}
check [validate four_point_homography affine] {} {legacy four-point hint}
set rc [catch {validate full_image_pixels affine} err]
check $rc 1 {old incorrect caller classification must fail closed}
check $err {Calibration classification changed during publication.} {wrong full-image-class refusal}
set rc [catch {validate pixel projective} err]
check $rc 1 {wrong scientific class must fail}
set rc [catch {validate bogus affine} err]
check $rc 1 {unknown caller class must fail}
check $err {Unsupported caller calibration classification.} {unknown class error}
puts "PASS: actual Tcl publication class contract; affine, pixel, scale bar, projective, legacy aliases and negative guards"
