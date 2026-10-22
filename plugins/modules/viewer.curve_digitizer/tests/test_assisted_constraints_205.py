# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic path-prior tests; not a substitute for installed GUI/CORE tests."""
import sys
import unittest
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from assisted_constraints import spline_points,exclusion_penalty,second_order_indices

class Constraints204(unittest.TestCase):
    def test_nodes_and_undisturbed_raster(self):
        nodes=[(5,5),(20,8),(40,5),(60,15)]
        points=spline_points(nodes)
        self.assertEqual(points[0],nodes[0])
        self.assertEqual(points[-1],nodes[-1])
        for p in nodes:
            self.assertLess(min(np.linalg.norm(np.asarray(q)-p) for q in points),1e-9)
        raster=Image.new('L',(100,80),255)
        before=raster.tobytes()
        band=exclusion_penalty(raster.size,[[(8,20),(40,20),(90,25)]],3)
        self.assertGreater(float(band[20,40]),.9)
        self.assertLess(float(band[0,40]),.01)
        self.assertEqual(before,raster.tobytes())

    def test_gradual_vs_strong_jump_cost(self):
        n=55;radius=8;k=2*radius+1
        score=np.full((n,k),1.0)
        score[:,radius]=.25
        score[15:20,radius+4]=-.8
        score[0,:]=np.inf;score[0,radius]=0
        score[-1,:]=np.inf;score[-1,radius]=0
        mild=second_order_indices(score,radius,'Gentle')
        strong=second_order_indices(score,radius,'Strong')
        self.assertEqual((mild[0],mild[-1]),(radius,radius))
        self.assertEqual((strong[0],strong[-1]),(radius,radius))
        def changes(a):return sum(abs(a[i]-2*a[i-1]+a[i-2]) for i in range(2,len(a)))
        self.assertLessEqual(changes(strong),changes(mild))

    def test_bad_nodes_and_inputs_rejected(self):
        with self.assertRaises(ValueError):spline_points([(3,4),(3,4)])
        with self.assertRaises(ValueError):exclusion_penalty((50,50),[[(1,1),(7,7)]],41)
        with self.assertRaises(ValueError):
            second_order_indices(np.zeros((4,17)),8,'Off')

if __name__=='__main__':unittest.main()
