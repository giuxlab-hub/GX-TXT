# SPDX-License-Identifier: GPL-3.0-or-later
"""Real Jacobian->in-memory Tcl typed Numeric payload; no filesystem staging."""
import sys,subprocess,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from digitizer_model import Project,AxisConfig,CORNER_ORDER
from gxtxt_curve_digitizer import CurveDigitizerApp

TCL=r'''
namespace eval ::GX {}
namespace eval ::GX::ScientificTransportv1 {}
proc ::GX::ScientificTransportv1::array {shape real} {return [dict create kind array shape $shape real $real]}
proc ::GX::ScientificTransportv1::text {value} {return [dict create kind text value $value]}
proc ::GX::ScientificTransportv1::struct {fields} {return [dict create kind struct fields $fields]}
source [lindex $argv 0]
set packet [read stdin]
set pair [::GX::CurveDigitizerNumericCore::_inline $packet meas_123 2]
set lin [dict get [lindex $pair 0] fields]
set spec [dict get [lindex $pair 1] fields]
if {[dict get $spec pixel_scale real] ne {0 0}} {error {Zero pixel coordinates were replaced with invented epsilon}}
if {[dict get $lin point_jacobian shape] ne {4 2}} {error {Missing original point Jacobian dimensions}}
if {[dict get $lin calibration_jacobian shape] ne {4 12}} {error {Missing shared calibration Jacobian dimensions}}
if {[llength [dict get $spec calibration_standard_uncertainty real]] != 12} {error {Lost calibration uncertainty}}
if {[dict get $spec mode value] ne pixel_calibration} {error {Lost declared model}}
if {![catch {::GX::CurveDigitizerNumericCore::_inline $packet meas_999 2}]} {error {Mismatched measurement was accepted}}
puts PASS
'''
class CoreInline(unittest.TestCase):
    def test_zero_and_shared_inputs(self):
        p=Project();p.x_axis=AxisConfig('X','V',0,5,'linear');p.y_axis=AxisConfig('Y','mA',0,10,'linear')
        for name,xy in zip(CORNER_ORDER,((10,90),(90,90),(10,10),(90,10))):p.calibration.set_corner(name,*xy)
        import numpy as np
        jac=p.calibration_linearization(np.array([[25.,70.],[75.,40.]]))
        spec={'mode':'pixel_calibration','pixel_distribution':'rectangular_full_width',
              'pixel_scale':[0,0],'calibration_standard_uncertainty':[0.2]*8+[0.01]*4,
              'rationale':'Explicit zero localization; separately declared calibration uncertainty'}
        wire=CurveDigitizerApp._core_inline_uncertainty(jac,spec,'meas_123')
        src=Path(__file__).resolve().parents[1]/'api'/'curve_digitizer_numeric_core.tcl'
        import base64
        cp=subprocess.run(['tclsh','-',str(src),base64.b64encode(wire.encode()).decode()],input=TCL.replace('set packet [read stdin]','set packet [binary decode base64 [lindex $argv 1]]'),text=True,capture_output=True)
        self.assertEqual(cp.returncode,0,cp.stderr)
        self.assertEqual(cp.stdout.strip(),'PASS')
if __name__=='__main__': unittest.main()
