# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic raster fixtures for the real pixel-width measuring functions.

Requires the module's NumPy and Pillow dependencies.
These tests do not claim the original instrument's metrological accuracy.
"""
import pathlib
import sys
import unittest
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"python"))
from stroke_width_measure import automatic_width,manual_width

class StrokeRaster209(unittest.TestCase):
    def test_five_pixel_uniform_ink(self):
        image=Image.new("L",(400,160),255)
        ink=ImageDraw.Draw(image)
        ink.line(((25,80),(360,80)),fill=0,width=5)
        raster=[(float(x),80.) for x in np.linspace(35,350,110)]
        result=automatic_width(image,raster,radius=12)
        self.assertGreaterEqual(result["accepted_samples"],50)
        self.assertEqual(result["total_samples"],result["accepted_samples"]+result["rejected_samples"])
        self.assertLess(abs(result["width_px"]-5),1.1)
        self.assertEqual(result["method"],"automatic")
    def test_two_drawn_parallel_edges(self):
        result=manual_width([[30,40],[360,40]],[[30,45],[360,45]])
        self.assertAlmostEqual(result["width_px"],5.,places=3)
        self.assertEqual(result["rejected_samples"],0)
        self.assertEqual(result["method"],"manual")
    def test_invalid_trace_never_becomes_zero_sigma(self):
        image=Image.new("L",(100,100),255)
        with self.assertRaises(ValueError):
            automatic_width(image,[(10,20),(20,20)],radius=12)
        with self.assertRaises(ValueError):
            manual_width([[5,5],[10,10]],[[5,5],[10,10]])
if __name__=="__main__":unittest.main(verbosity=2)
