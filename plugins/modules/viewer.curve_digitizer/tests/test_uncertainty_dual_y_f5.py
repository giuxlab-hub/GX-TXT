# SPDX-License-Identifier: GPL-3.0-or-later
"""F5: 14-parameter shared calibration Jacobians and covariance tests."""
from __future__ import annotations
import copy
import math
import sys
import unittest
from pathlib import Path
import numpy as np

MODULE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(MODULE/"python"))
from digitizer_model import Project,AxisConfig,CORNER_ORDER,CalibrationError
from uncertainty_engine import (checked_spec,propagate,compact_factors,decode_factors,
                                covariance_from_factors,UncertaintyError)


class SharedDualY(unittest.TestCase):
    def setUp(self):
        self.project=Project()
        self.project.x_axis=AxisConfig("Frequency","Hz",10.,10000.,"log")
        self.project.y_axis=AxisConfig("Gain","V",-2.,8.,"linear")
        self.project.y2_axis=AxisConfig("Amplitude","V",0.01,100.,"log")
        for label,px in zip(CORNER_ORDER,((22,242),(443,236),(38,12),(454,25))):
            self.project.calibration.set_corner(label,*px)
        self.pixels=np.array([[44.,212.],[120.,145.],[250.,81.],[381.,49.]])
        self.axes=["y1","y2","y1","y2"]
        self.spec={"mode":"pixel_calibration",
                   "pixel_distribution":"normal_standard_uncertainty",
                   "pixel_scale":[0.4,0.6],
                   "calibration_standard_uncertainty":([0.2]*8+[0.01,0.012,0.02,0.03,0.04,0.05]),
                   "rationale":"Reviewed synthetic independent input errors shared by two axes"}

    def test_numerical_analytic_local_and_corner_derivatives(self):
        p=self.project
        lin=p.calibration_linearization(self.pixels,self.axes)
        self.assertEqual(lin["calibration_jacobian"].shape,(8,14))
        self.assertEqual(lin["calibration_units"][-4:],["V"]*4)
        self.assertEqual(lin["calibration_ids"][-4:],
                         ["y_minimum","y_maximum","y2_minimum","y2_maximum"])
        self.assertTrue(np.all(lin["calibration_jacobian"][1::4,12:14]==0))
        self.assertTrue(np.all(lin["calibration_jacobian"][3::4,10:12]==0))
        for i,pixel in enumerate(self.pixels):
            for axis in range(2):
                plus=pixel.copy();minus=pixel.copy();plus[axis]+=1e-4;minus[axis]-=1e-4
                fd=(np.asarray(p.pixel_to_calibrated(*plus,self.axes[i]))-
                    np.asarray(p.pixel_to_calibrated(*minus,self.axes[i])))/2e-4
                np.testing.assert_allclose(fd,lin["point_jacobian"][2*i:2*i+2,axis],
                                           rtol=1e-6,atol=1e-8)
        for index in range(14):
            def perturb(sign):
                trial=copy.deepcopy(p)
                if index<8:
                    corner=CORNER_ORDER[index//2]
                    points=list(trial.calibration.pixels[corner])
                    points[index%2]+=sign*1e-4
                    trial.calibration.set_corner(corner,*points)
                else:
                    key=["x_minimum","x_maximum","y_minimum","y_maximum",
                         "y2_minimum","y2_maximum"][index-8]
                    owner=trial.x_axis if key.startswith("x_") else (
                        trial.y2_axis if key.startswith("y2_") else trial.y_axis)
                    attr=key.split("_",1)[1] if not key.startswith("y2_") else key[3:]
                    setattr(owner,attr,getattr(owner,attr)+sign*1e-5)
                return trial
            eps=1e-4 if index<8 else 1e-5
            pl=perturb(1);mi=perturb(-1)
            for i,pt in enumerate(self.pixels):
                fd=(np.asarray(pl.pixel_to_calibrated(*pt,self.axes[i]))-
                    np.asarray(mi.pixel_to_calibrated(*pt,self.axes[i])))/(2*eps)
                exact=lin["calibration_jacobian"][2*i:2*i+2,index]
                np.testing.assert_allclose(fd,exact,rtol=3e-5,atol=2e-6)

    def test_full_covariance_shared_corners_and_distinct_endpoint_sensitivities(self):
        r=propagate(self.project,self.pixels,self.spec,axis_ids=self.axes)
        self.assertEqual(r["shared_factors"].shape,(8,14))
        self.assertTrue(r["shared_calibration"])
        f=compact_factors([r["local_factors"]],[r["shared_factors"]])
        self.assertEqual(f["format"],"zlib-base64-float64-le-v2")
        local,shared=decode_factors(f)
        np.testing.assert_array_equal(local,r["local_factors"])
        np.testing.assert_array_equal(shared,r["shared_factors"])
        cy=covariance_from_factors(f,"y")
        self.assertGreater(abs(cy[0,1]),0.0,
                           "Y1 and Y2 are correlated by the same corners")
        self.assertGreaterEqual(np.linalg.eigvalsh(cy).min(),-1e-10)
        np.testing.assert_allclose(np.diag(cy),np.asarray(r["sigma_y"])**2)
        self.assertTrue(np.all(shared[1::4,12:]==0.0))
        self.assertTrue(np.all(shared[3::4,10:12]==0.0))

    def test_distinct_y_units_are_rejected_in_one_dataset(self):
        self.project.y2_axis.unit="deg"
        with self.assertRaisesRegex(CalibrationError,"mix physical Y units"):
            self.project.calibration_linearization(self.pixels,self.axes)
        # A split Dataset must still retain the full 14 shared parameter IDs.
        for name, subset in (("y1",[0,2]),("y2",[1,3])):
            axes=[name]*len(subset)
            px=self.pixels[subset]
            lin=self.project.calibration_linearization(px,axes)
            self.assertEqual(lin["calibration_jacobian"].shape,(4,14))
            self.assertEqual(lin["coordinate_units"][1],"deg" if name=="y2" else "V")
            result=propagate(self.project,px,self.spec,axis_ids=axes)
            self.assertEqual(result["units"][1],"deg" if name=="y2" else "V")

    def test_three_physical_override_values(self):
        spec={"mode":"physical_override",
              "override_standard_uncertainty":[0.1,0.2,0.7],
              "rationale":"Synthetic independent physical Y1 versus Y2 standards"}
        out=propagate(self.project,self.pixels,spec,axis_ids=self.axes)
        np.testing.assert_allclose(out["sigma_x"],0.1)
        np.testing.assert_allclose(out["sigma_y"],[0.2,0.7,0.2,0.7])
        self.assertFalse(out["shared_calibration"])
        self.assertTrue(np.all(out["shared_factors"]==0))
        with self.assertRaisesRegex(UncertaintyError,"exactly 3"):
            checked_spec({"mode":"physical_override",
                "override_standard_uncertainty":[0.1,0.2],"rationale":"old"},
                dual_y=True)

    def test_malformed_or_unbound_axes(self):
        with self.assertRaisesRegex(CalibrationError,"logical Y-axis ID"):
            self.project.calibration_linearization(self.pixels)
        for axes in (["y1"]*3,["y1","y3","y1","y2"]):
            with self.assertRaises(CalibrationError):
                self.project.calibration_linearization(self.pixels,axes)
        with self.assertRaises(UncertaintyError):
            checked_spec({"mode":"pixel_calibration",
                          "pixel_distribution":"normal_standard_uncertainty",
                          "pixel_scale":[1,1],
                          "calibration_standard_uncertainty":[.1]*12,
                          "rationale":"unreviewed old model"},dual_y=True)


if __name__=="__main__":
    unittest.main(verbosity=2)
