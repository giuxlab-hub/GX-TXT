# SPDX-License-Identifier: GPL-3.0-or-later
"""F1 model regression: shared geometry, per-curve Y transforms, legacy preservation."""
from __future__ import annotations
import copy
import csv
import json
import math
import sys
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1]
WORKTREE = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(MODULE / "python"))
from digitizer_model import (AxisConfig, CalibrationError, DigitizedPoint,
                             Project, Series)

FIXTURES = WORKTREE / "test_fixtures" / "y2"

def from_fixture(manifest):
    p = Project()
    ax = manifest["axes"]
    p.x_axis = AxisConfig.from_dict(ax["x"])
    p.y_axis = AxisConfig.from_dict(ax["y1"])
    if "y2" in ax:
        p.y2_axis = AxisConfig.from_dict(ax["y2"])
    for tag, name in (("BL", "bottom_left"), ("BR", "bottom_right"),
                      ("TL", "top_left"), ("TR", "top_right")):
        p.calibration.set_corner(name, *manifest["plot_corners_px"][tag])
    assert p.calibration_ready()
    return p

class TestY2ModelF1(unittest.TestCase):
    def test_legacy_roundtrip_is_unchanged(self):
        p = Project()
        p.auto_calibrate_full_image(320, 210)
        s = Series(id="legacy", name="Legacy", points=[
            DigitizedPoint(id="original-point", pixel_x=51.3, pixel_y=90.2)])
        p.series = [s]
        p.recalculate_all_points()
        before = p.to_dict()
        self.assertEqual(before["axes"].keys(), {"x", "y"})
        self.assertNotIn("axis_model_version", before)
        self.assertNotIn("y_axis_id", before["series"][0])
        self.assertNotIn("y2", before["axes"])
        after = Project.from_dict(copy.deepcopy(before)).to_dict()
        self.assertEqual(before, after)
        self.assertEqual(after["series"][0]["points"][0]["id"], "original-point")
        self.assertEqual(p.pixel_to_calibrated(51.3, 90.2),
                         p.pixel_to_calibrated(51.3, 90.2, "y1"))

    def test_fixtures_full_recalculation_and_roundtrip(self):
        totals = 0
        for path in sorted(FIXTURES.glob("test_*_manifest.json")):
            manifest = json.loads(path.read_text(encoding="utf-8"))
            p = from_fixture(manifest)
            expected = []
            series_by_id = {}
            with (FIXTURES / manifest["truth_file"]).open(
                    encoding="utf-8", newline="") as handle:
                for line in csv.DictReader(handle):
                    curve_id, axis_id = line["curve_id"], line["y_axis_id"]
                    if curve_id not in series_by_id:
                        series_by_id[curve_id] = Series(id=curve_id,
                            name=line["curve_name"], y_axis_id=axis_id)
                    self.assertEqual(series_by_id[curve_id].y_axis_id, axis_id)
                    point = DigitizedPoint(
                        id=f"{curve_id}_{line['point_order']}",
                        pixel_x=float(line["pixel_x"]),
                        pixel_y=float(line["pixel_y"]))
                    series_by_id[curve_id].points.append(point)
                    expected.append((point, float(line["x"]), float(line["y"])))
            p.series = list(series_by_id.values())
            p.recalculate_all_points()
            for pt, x, y in expected:
                self.assertAlmostEqual(pt.calibrated_x, x, delta=1e-9*(1+abs(x)))
                self.assertAlmostEqual(pt.calibrated_y, y, delta=1e-9*(1+abs(y)))
            snapshot = p.to_dict()
            self.assertEqual("y2" in snapshot["axes"], p.y2_axis is not None)
            if p.y2_axis is not None:
                self.assertEqual(snapshot["axis_model_version"], 2)
                self.assertTrue(all("y_axis_id" in s for s in snapshot["series"]))
            else:
                self.assertNotIn("axis_model_version", snapshot)
                self.assertTrue(all("y_axis_id" not in s for s in snapshot["series"]))
            restored = Project.from_dict(snapshot)
            restored.recalculate_all_points()
            self.assertEqual(restored.to_dict(), snapshot)
            totals += len(expected)
        self.assertEqual(totals, 2908)

    def test_no_missing_or_unknown_axis_silently_reinterpreted(self):
        p = Project()
        p.auto_calibrate_full_image(80, 60)
        s = Series(id="bad", y_axis_id="y2", points=[
            DigitizedPoint(pixel_x=10, pixel_y=20)])
        p.series = [s]
        with self.assertRaisesRegex(CalibrationError, "Unavailable"):
            p.recalculate_all_points()
        with self.assertRaisesRegex(CalibrationError, "Unavailable"):
            p.to_dict()
        p.y2_axis = AxisConfig(name="Y2", unit="dB", minimum=-30, maximum=10)
        p.recalculate_all_points()
        sample = p.to_dict()
        self.assertEqual(sample["series"][0]["y_axis_id"], "y2")
        invalid = copy.deepcopy(sample)
        invalid["series"][0]["y_axis_id"] = "right"
        with self.assertRaisesRegex(CalibrationError, "Unknown curve Y"):
            Project.from_dict(invalid)
        invalid = copy.deepcopy(sample)
        del invalid["axes"]["y2"]
        with self.assertRaisesRegex(CalibrationError, "inconsistent"):
            Project.from_dict(invalid)
        invalid = copy.deepcopy(sample)
        invalid["axes"]["y2"]["scale"] = "log"
        invalid["axes"]["y2"]["minimum"] = -1
        with self.assertRaisesRegex(CalibrationError, "positive"):
            Project.from_dict(invalid)

    def test_uncertainty_requires_explicit_axis_bindings_with_f5(self):
        p = Project()
        p.auto_calibrate_full_image(80, 60)
        p.y2_axis = AxisConfig(name="Y2", minimum=0, maximum=10)
        p.series = [Series(y_axis_id="y2")]
        with self.assertRaisesRegex(CalibrationError, "logical Y-axis ID"):
            p.calibration_linearization([(20.0, 30.0)])
        self.assertEqual(p.calibration_linearization([(20.0, 30.0)],["y2"])
                         ["calibration_jacobian"].shape, (2, 14))
        p.y2_axis = None
        p.series[0].y_axis_id = "y1"
        self.assertEqual(p.calibration_linearization([(20.0, 30.0)])
                         ["calibration_jacobian"].shape, (2, 12))

if __name__ == "__main__":
    unittest.main(verbosity=2)
