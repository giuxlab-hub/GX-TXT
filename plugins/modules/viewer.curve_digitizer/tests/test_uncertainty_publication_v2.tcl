# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] test_publication_manifest.tcl]
# mock Dataset metadata mutation after canonical publication
proc ::GX::datasetMetadataUpdate {session dataset fields} {
    dict for {k v} $fields {dict set ::GX::mockMetadata $k $v}
}
set ::GX::mockMetadata [dict create]
# The REAL plugin requires dev097 Numeric/CORE; the hermetic contract test
# provides a deterministic mock ONLY to verify publication request wiring.
# Never ship a scientific runtime fallback to this mock implementation.
proc ::GX::CurveDigitizerNumericCore::propagate {doc rowsText mid rows source sha inline} {
    set n [dict get $rows count]
    if {$n != 2} {error {Test CORE stub expects exactly two source rows}}
    set columns [dict create x [dict get $rows x] y [dict get $rows y] \
        sigma_x {0.1 0.3} sigma_y {0.2 0.4} covariance_xy {0 0}]
    return [dict create columns $columns resources \
        [dict create state mock_state points mock_points configuration mock_configuration \
            interpretation mock_interpretation values mock_values] meaning mock_semantics]
}

set mid meas_0123456789abcdef0123456789abcdef
set e ::GX::CurveDigitizer::_b64e
set curveRows [join [list \
    "[$e first]\t[$e {Groove left}]\t0\t1.3\t2.4\t\t20.1\t40.2\t[$e stable_point_a]" \
    "[$e second]\t[$e {Groove right}]\t0\t1.5\t2.0\t\t21.5\t42.0\t[$e stable_point_b]" \
] "\n"]
set report {"schema":"gxtxt.curve_digitizer.uncertainty.v2","row_count":2}
set factors {"format":"zlib-base64-float64-le-v1","shape_local":[2,2,2]}
set body "[$e $report]\n[$e $factors]"
append body "\n[$e first]\t[$e stable_point_a]\t[$e $mid]\t1.3\t2.4\t0.1\t0.2\t0"
append body "\n[$e second]\t[$e stable_point_b]\t[$e $mid]\t1.5\t2.0\t0.3\t0.4\t0"
set args [lreplace $callArgs 20 20 $curveRows]
lappend args {} $body {mock_inline}
set receipt [::GX::CurveDigitizer::_publish {*}$args]
if {[dict get $::GX::mockAppend point_id] ne {stable_point_a stable_point_b}} {error "Wrong original point identity"}
if {[dict get $::GX::mockAppend sigma_x] ne {0.1 0.3}} {error "Wrong sigma X"}
if {[dict get $::GX::mockAppend sigma_y] ne {0.2 0.4}} {error "Wrong sigma Y"}
if {![dict exists $::GX::mockVariables covariance_xy]} {error "Covariance not declared"}
if {[dict get $::GX::mockDefinition structured_metadata curve_digitizer.uncertainty_schema_version] ne 2} {error {Missing v2 uncertainty schema}}
if {[dict get $::GX::mockMetadata curve_digitizer.uncertainty_dataset_sha256] ne $::GX::mockSha} {error {Missing canonical byte binding}}
if {![dict exists $::GX::mockMetadata curve_digitizer.uncertainty_binding resources state]} {error {Missing CORE/Fitter retained state binding}}
set wrong [string map [list 1.3 1.4] $body]
if {![catch {::GX::CurveDigitizer::_publish {*}[lreplace $args end-1 end-1 $wrong]}]} {error {Changed coordinate not rejected}}
set wrong [string map [list [$e stable_point_b] [$e falsified_id]] $body]
if {![catch {::GX::CurveDigitizer::_publish {*}[lreplace $args end-1 end-1 $wrong]}]} {error {Changed identity not rejected}}
# Scientific guard: different calibration realizations are not independent
# draws of the original raster clicks; combined uncertainty is refused.
set mid2 meas_abcdef0123456789abcdef0123456789
set md2 $md
set ids [format {["%s","%s"]} $mid $mid2]
dict set md2 curve_digitizer.publication_calibration_mode combined
dict set md2 curve_digitizer.publication_calibration_ids $ids
dict set md2 curve_digitizer.measurement_count 2
dict set md2 curve_digitizer.measurement.1.measurement_id $mid2
dict set md2 curve_digitizer.measurement.1.valid 1
dict set md2 curve_digitizer.measurement.1.state accepted
dict set md2 curve_digitizer.measurement.1.transform.x_unit px
dict set md2 curve_digitizer.measurement.1.transform.y_unit px
set encoded {}
dict for {k v} $md2 {lappend encoded "[$e $k]\t[$e $v]"}
set combinedRows "[$e first]\t[$e {Groove left}]\t0\t1.3\t2.4\t\t20.1\t40.2\t[$e $mid]\t[$e {Calibration 1}]\t[$e stable_point_a]"
append combinedRows "\n[$e first]\t[$e {Groove left}]\t0\t1.3\t2.4\t\t20.1\t40.2\t[$e $mid2]\t[$e {Calibration 2}]\t[$e stable_point_a]"
set combinedArgs [lreplace $args 20 20 $combinedRows]
set combinedArgs [lreplace $combinedArgs 21 21 [join $encoded "\n"]]
set combinedArgs [lreplace $combinedArgs 22 22 combined]
set combinedBody "[$e $report]\n[$e $factors]"
append combinedBody "\n[$e first]\t[$e stable_point_a]\t[$e $mid]\t1.3\t2.4\t0.1\t0.2\t0"
append combinedBody "\n[$e first]\t[$e stable_point_a]\t[$e $mid2]\t1.3\t2.4\t0.1\t0.2\t0"
set combinedArgs [lreplace $combinedArgs end-1 end-1 $combinedBody]
if {![catch {::GX::CurveDigitizer::_publish {*}$combinedArgs} failure] ||
    ![string match {*multiple calibrations*} $failure]} {
    error "Combined uncertainty must reject cross-calibration correlations: $failure"
}

puts {PASS: uncertainty columns, ordered point_id, physical sigma and covariance, source and canonical byte binding}
