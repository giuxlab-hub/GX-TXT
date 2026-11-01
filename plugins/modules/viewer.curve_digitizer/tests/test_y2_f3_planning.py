# SPDX-License-Identifier: GPL-3.0-or-later
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from publication_y2 import plan_y2_datasets,metadata_for_y2
from digitizer_model import Series,DigitizedPoint

def item(i,y1="dB",y2="deg",x="Hz"):
    return {
        "id": "meas_"+str(i)*32, "label": "Calibration "+str(i),
        "state":"accepted",
        "axes":{
            "x":{"minimum":10,"maximum":1e5,"scale":"log","unit":x},
            "y":{"minimum":-40,"maximum":5,"scale":"linear","unit":y1},
            "y2":{"minimum":-100,"maximum":0,"scale":"linear","unit":y2},
        }
    }
def curves():
    return [Series(id="gain",name="Gain",y_axis_id="y1",points=[DigitizedPoint()]),
            Series(id="phase",name="Phase",y_axis_id="y2",points=[DigitizedPoint()])]
def plan(items,layout="separate",series=None):
    return plan_y2_datasets(items,[x["id"] for x in items],layout=layout,
        template="[name].[calibration].curves",name="bode",configuration="Bode",
        series=curves() if series is None else series)
class TestY2Planning(unittest.TestCase):
    def test_different_units_split(self):
        jobs=plan([item(1)])
        self.assertEqual([j["dataset_id"] for j in jobs],
                         ["bode.calibration_1.curves.y1","bode.calibration_1.curves.y2"])
        self.assertEqual([j["axis_mode"] for j in jobs],["y1","y2"])
        self.assertEqual([j["y_unit"] for j in jobs],["dB","deg"])
        for j in jobs:self.assertEqual(len(j["curve_ids"]),1)
    def test_same_units_one_dataset_with_two_logical_axes(self):
        jobs=plan([item(1,"V","V")])
        self.assertEqual(len(jobs),1)
        self.assertEqual(jobs[0]["axis_mode"],"mixed")
        self.assertEqual(jobs[0]["y_unit"],"V")
        md=metadata_for_y2({"axes":{"y2":item(1)["axes"]["y2"]}},jobs[0],
                           [item(1,"V","V")],curves(),"pubset_abc")
        self.assertEqual(md["curve_digitizer.curve_schema_version"],"2")
        self.assertEqual(md["curve_digitizer.curve_axis.phase"],"y2")
    def test_multicalibration_separate_split_and_combined(self):
        pair=[item(1),item(2)]
        jobs=plan(pair,"separate")
        self.assertEqual(len(jobs),4)
        self.assertEqual(len({j["dataset_id"] for j in jobs}),4)
        jobs=plan(pair,"combined")
        self.assertEqual(len(jobs),2)
        self.assertTrue(all(len(j["measurement_ids"])==2 for j in jobs))
        pair=[item(1,"V","V"),item(2,"V","V")]
        jobs=plan(pair,"combined")
        self.assertEqual(len(jobs),1)
        self.assertEqual(jobs[0]["axis_mode"],"mixed")
    def test_incompatible_combined_units_refused(self):
        with self.assertRaisesRegex(ValueError,"single physical Y"):
            plan([item(1,"V","A"),item(2,"V","mA")],"combined")
        with self.assertRaisesRegex(ValueError,"single physical X"):
            plan([item(1,"V","V","Hz"),item(2,"V","V","kHz")],"combined")
    def test_just_one_used_axis(self):
        for series in [curves()[:1],curves()[1:]]:
            jobs=plan([item(1)],series=series)
            self.assertEqual(len(jobs),1)
            self.assertEqual(jobs[0]["axis_mode"],series[0].y_axis_id)
            self.assertEqual(jobs[0]["dataset_id"],"bode.calibration_1.curves")
    def test_collision_bound_and_empty_refused(self):
        with self.assertRaisesRegex(ValueError,"longer than 128"):
            plan_y2_datasets([item(1)],[item(1)["id"]],layout="separate",
                template="[name].[calibration].curves",name="B"+"b"*118,
                configuration="Bode",series=curves())
        with self.assertRaisesRegex(ValueError,"No calibrated curve"):
            plan([item(1)],series=[Series(id="empty")])
if __name__=="__main__":unittest.main(verbosity=2)
