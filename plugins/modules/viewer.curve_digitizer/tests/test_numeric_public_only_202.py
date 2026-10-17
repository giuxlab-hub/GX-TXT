# SPDX-License-Identifier: GPL-3.0-or-later
"""Hermetic check: all numerical invocation is delegated to public CORE APIs.

No actual Numeric solver is mocked into production. Full dev097 integration is
owned by the separate framework integration task.
"""
import base64
import subprocess
import sys
import unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from digitizer_model import Project,AxisConfig,CORNER_ORDER
from gxtxt_curve_digitizer import CurveDigitizerApp
TCL=r'''
namespace eval ::GX {}
namespace eval ::GX::ScientificTransportv1 {}
namespace eval ::GX::NumericAPIv1 {}
namespace eval ::GX::StatisticsV1 {}
namespace eval ::GX::CurveDigitizer {}
proc ::GX::ScientificTransportv1::array {shape real} {dict create kind array shape $shape real $real}
proc ::GX::ScientificTransportv1::text {value} {dict create kind text value $value}
proc ::GX::ScientificTransportv1::struct {fields} {dict create kind struct fields $fields}
proc ::GX::modulePublicApiActivate {mod api} {if {$mod ne "math.numeric"} {error {Wrong provider}}}
proc ::GX::interactiveDocumentRead {doc} {dict create module_id viewer.curve_digitizer sha256 [string repeat a 64] payload {saved scientific configuration}}
proc ::GX::interactiveDocumentSessionToken {} {return session_2}
proc ::GX::CurveDigitizer::_sourceInfo {dataset} {dict create sha256 [string repeat b 64]}
set ::GX::writers {};set ::GX::serial 0
proc ::GX::interactiveDocumentResourceOpenWriter {doc metadata} {
    set key [incr ::GX::serial];dict set ::GX::writers $key [dict create content {} metadata $metadata];return $key
}
proc ::GX::interactiveDocumentResourceAppend {writer content} {
    dict append ::GX::writers $writer content $content
}
proc ::GX::interactiveDocumentResourceFinalize {writer} {
    set record [dict get $::GX::writers $writer];set body [dict get $record content]
    return [dict create sha256 [format %064x [string length $body]] size_bytes [string length $body] metadata [dict get $record metadata]]
}
proc ::GX::interactiveDocumentResourceAbort {writer} {error {Unexpected resource abort}}
set ::GX::numericCalls 0
proc ::GX::NumericAPIv1::callOperation {operation operands {opts {}}} {
    if {$operation ne "digitization_uncertainty"} {error {Wrong numerical operation}}
    incr ::GX::numericCalls
    set linear [dict get [lindex $operands 0] fields]
    set spec [dict get [lindex $operands 1] fields]
    if {[dict get $spec pixel_scale real] ne {0 0}} {error {Invented positive pixel localization}}
    set xys [dict get $linear coordinates real]
    set n 2
    set xy [list [list [lindex $xys 0] [lindex $xys 2]] [list [lindex $xys 1] [lindex $xys 3]]]
    set std {{0.3 0.5} {0.3 0.5}}
    set cxy {{0.09 0.03 0.25} {0.09 0.03 0.25}}
    return [dict create schema gxtxt.digitization_uncertainty.v1 point_count $n \
        coordinates $xy standard_uncertainty $std covariance_blocks $cxy \
        state_sha256 [string repeat c 64] summary [dict create point_count $n state_sha256 [string repeat c 64]]]
}
proc ::GX::StatisticsV1::digitizationInterpretation {summary context} {
    if {[dict get $context row_identity] ne "original_point_ids"} {error {Lost point order}}
    return [dict create schema gxtxt.digitization_interpretation.v1 summary $summary context $context]
}
source [lindex $argv 0]
set wire [binary decode base64 -strict [lindex $argv 1]]
set rows [dict create count 2 x {1.0 3.0} y {2.0 4.0} point_id {p1 p2} curve_id {c c} \
    curve_label {curve curve} point_index {0 1} family_value {}]
set result [::GX::CurveDigitizerNumericCore::propagate doc {} meas_123 $rows image [string repeat b 64] $wire]
if {$::GX::numericCalls!=1} {error {Numeric operation was not invoked exactly once}}
if {[dict get $result columns sigma_x] ne {0.3 0.3}} {error {CORE sigma was not authoritative}}
foreach role {configuration state points interpretation values} {
    if {![dict exists $result resources $role]} {error "Missing managed $role"}
}
puts {PASS: zero inputs sent to public Numeric and managed resources persisted}
'''
class PublicOnly(unittest.TestCase):
    def test_core_no_module_worker_or_files(self):
        p=Project();p.x_axis=AxisConfig('X','V',0,4,'linear');p.y_axis=AxisConfig('Y','mA',0,8,'linear')
        for name,xy in zip(CORNER_ORDER,((10,90),(90,90),(10,10),(90,10))):p.calibration.set_corner(name,*xy)
        # x=1,3 -> px=30,70; y=2,4 -> py=70,50
        lin=p.calibration_linearization(np.array([[30.,70.],[70.,50.]]))
        spec={'mode':'pixel_calibration','pixel_distribution':'rectangular_full_width',
              'pixel_scale':[0,0],'calibration_standard_uncertainty':[.2]*12,
              'rationale':'Zero pixel uncertainty, explicit calibration uncertainty'}
        wire=CurveDigitizerApp._core_inline_uncertainty(lin,spec,'meas_123')
        cmd=['tclsh','-',str(ROOT/'api/curve_digitizer_numeric_core.tcl'),base64.b64encode(wire.encode()).decode()]
        cp=subprocess.run(cmd,input=TCL,text=True,capture_output=True)
        self.assertEqual(cp.returncode,0,cp.stdout+cp.stderr)
        self.assertIn('PASS: zero inputs',cp.stdout)
        code=(ROOT/'api/curve_digitizer_numeric_core.tcl').read_text()+'\n'+(ROOT/'api/curve_digitizer_core_consumers.tcl').read_text()
        self.assertNotIn('exec [',code)
        self.assertNotIn('file tempfile',code)
        self.assertNotIn('resourceManagementAllocate',code)
if __name__=='__main__': unittest.main()
