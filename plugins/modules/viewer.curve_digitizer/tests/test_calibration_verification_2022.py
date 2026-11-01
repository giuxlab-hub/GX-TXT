# SPDX-License-Identifier: GPL-3.0-or-later
"""Deterministic verification on 2,908 synthetic points and edge cases."""
import csv
import json
import math
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[4]
MODULE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(MODULE/"python"))
from digitizer_model import AxisConfig, Project
from calibration_verification import evaluate_verification,parse_reference,ReferenceValueError

FIXTURES=ROOT/"test_fixtures"/"y2"


def project_from_manifest(m):
    p=Project()
    axes=m["axes"]
    p.x_axis=AxisConfig.from_dict(axes["x"])
    p.y_axis=AxisConfig.from_dict(axes["y1"])
    p.y2_axis=AxisConfig.from_dict(axes["y2"]) if "y2" in axes else None
    for key,corner in (("BL","bottom_left"),("BR","bottom_right"),
                       ("TL","top_left"),("TR","top_right")):
        p.calibration.set_corner(corner,*m["plot_corners_px"][key])
    return p


class CalibrationVerificationTests(unittest.TestCase):
    def test_reference_parser(self):
        lin=AxisConfig("X","V",0,10,"linear")
        log=AxisConfig("Frequency","Hz",1,1e5,"log")
        self.assertIsNone(parse_reference("  ",lin))
        self.assertEqual(parse_reference("1e3",log),1000.0)
        self.assertEqual(parse_reference("10^3",log),1000.0)
        self.assertEqual(parse_reference("10^(-3)",log),0.001)
        self.assertEqual(parse_reference("1,5e3",log),1500.0)
        self.assertEqual(parse_reference("3",log),3.0) # not automatically 10**3!
        self.assertEqual(parse_reference("-3,5",lin),-3.5)
        for text in ("0","-1","-1e3","nan","inf","-inf"):
            with self.assertRaises(ReferenceValueError,msg=text):
                parse_reference(text,log)
        for text in ("1.0,5","not-a-number","10^2000"):
            with self.assertRaises(ReferenceValueError,msg=text):
                parse_reference(text,lin)

    def test_verification_all_fixtures(self):
        count=0
        for manifest_path in sorted(FIXTURES.glob("test_*_manifest.json")):
            manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
            project=project_from_manifest(manifest)
            with (FIXTURES/manifest["truth_file"]).open(newline="",encoding="utf-8") as handle:
                for data in csv.DictReader(handle):
                    axis_id=data["y_axis_id"]
                    values=evaluate_verification(
                        project,float(data["pixel_x"]),float(data["pixel_y"]),
                        {"x":data["x"],axis_id:data["y"]})
                    axes={entry.axis_id:entry for entry in values}
                    assert len(values)==(3 if project.y2_axis is not None else 2)
                    self.assertEqual(axes["x"].error,None)
                    self.assertEqual(axes[axis_id].error,None)
                    for key in ("x",axis_id):
                        axis=axes[key]
                        self.assertLess(abs(axis.delta)/(1+abs(axis.reference)),2e-10)
                        if axis.scale=="log":
                            self.assertEqual(axis.comparison_kind,"decades")
                            self.assertLess(abs(axis.comparison),2e-10)
                        else:
                            self.assertIn(axis.comparison_kind,("percent","none"))
                    count+=1
        self.assertEqual(count,2908)

    def test_logarithmic_deviations_in_decades_not_log_units(self):
        p=Project()
        p.x_axis=AxisConfig("Frequency","Hz",1,1e4,"log")
        p.y_axis=AxisConfig("Amplitude","V",0,10,"linear")
        p.y2_axis=AxisConfig("Density","1",1e-3,1e3,"log")
        p.auto_calibrate_full_image(101,101)
        p.x_axis=AxisConfig("Frequency","Hz",1,1e4,"log")
        p.y_axis=AxisConfig("Amplitude","V",0,10,"linear")
        p.y2_axis=AxisConfig("Density","1",1e-3,1e3,"log")
        values=evaluate_verification(
            p,50,50,{"x":"10","y1":"4","y2":"10"})
        x,y1,y2=values
        self.assertAlmostEqual(x.measured,100,places=9)
        self.assertAlmostEqual(x.delta,90,places=9)
        self.assertAlmostEqual(x.comparison,1.0,places=9)
        self.assertAlmostEqual(y1.measured,5.0,places=9)
        self.assertAlmostEqual(y1.comparison,25,places=9)
        self.assertAlmostEqual(y2.measured,1.0,places=9)
        self.assertAlmostEqual(y2.comparison,-1.0,places=9)
        self.assertIn("decades",y2.comparison_display)

    def test_blank_and_invalid_are_not_reported_as_errors_in_calibration(self):
        p=Project()
        p.auto_calibrate_full_image(100,100)
        p.y2_axis=AxisConfig("Y2","mA",0.001,10,"log")
        entries=evaluate_verification(p,50,30,{"x":"","y1":"","y2":"-1"})
        self.assertEqual([x.delta for x in entries],[None,None,None])
        self.assertEqual(entries[0].reference_display,"—")
        self.assertIn("strictly positive",entries[2].error)
        self.assertEqual(entries[2].measured>0,True)
        self.assertEqual(entries[2].comparison_display,"—")


if __name__=="__main__":
    unittest.main(verbosity=2)
