# SPDX-License-Identifier: GPL-3.0-or-later
"""Headless scientific tests for v2.0 dev097 integration."""
import unittest, sys, numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'python'))
from digitizer_model import Project, AxisConfig, CORNER_ORDER
from uncertainty_engine import (checked_spec, propagate, compact_factors,
    decode_factors, covariance_from_factors, UncertaintyError, review_fingerprint)

class UncertaintyTests(unittest.TestCase):
    def setUp(self):
        p=Project()
        p.x_axis=AxisConfig('X','V',0.2,12.,'log')
        p.y_axis=AxisConfig('Y','mA',-1.,4.,'linear')
        for name,xy in zip(CORNER_ORDER,[(20,240),(430,236),(35,10),(452,23)]):
            p.calibration.set_corner(name,*xy)
        self.p=p
        self.pixels=np.array([[45.,225.],[160.,120.],[390.,40.]])
    def pixel(self):
        return dict(mode='pixel_calibration',pixel_distribution='rectangular_full_width',
                    pixel_scale=[1.,2.],calibration_standard_uncertainty=[.2]*8+[.01]*4,
                    rationale='Synthetic independent quantization-cell widths and shared calibration perturbations')
    def test_analytic_point_derivatives_against_finite_difference(self):
        lin=self.p.calibration_linearization(self.pixels)
        for row,point in enumerate(self.pixels):
            for k in (0,1):
                delta=1e-4
                a=point.copy();b=point.copy();a[k]+=delta;b[k]-=delta
                observed=(np.array(self.p.pixel_to_calibrated(*a))-
                    np.array(self.p.pixel_to_calibrated(*b)))/(2*delta)
                np.testing.assert_allclose(observed,lin['point_jacobian'][row*2:row*2+2,k],rtol=4e-7,atol=1e-8)
    def test_analytic_shared_corner_derivatives(self):
        linear=self.p.calibration_linearization(self.pixels)
        from copy import deepcopy
        eps=1e-3
        for k in range(8):
            p1=deepcopy(self.p);p2=deepcopy(self.p)
            name=CORNER_ORDER[k//2]; axis=k%2
            a=list(p1.calibration.pixels[name]);a[axis]+=eps;p1.calibration.set_corner(name,*a)
            b=list(p2.calibration.pixels[name]);b[axis]-=eps;p2.calibration.set_corner(name,*b)
            for i,pixel in enumerate(self.pixels):
                finite=(np.array(p1.pixel_to_calibrated(*pixel))-np.array(p2.pixel_to_calibrated(*pixel)))/(2*eps)
                exact=linear['calibration_jacobian'][2*i:2*i+2,k]
                np.testing.assert_allclose(finite,exact,rtol=2e-5,atol=1e-7)
    def test_shared_factor_covariance(self):
        r=propagate(self.p,self.pixels,self.pixel())
        self.assertTrue(r['shared_calibration'])
        fac=compact_factors([r['local_factors']],[r['shared_factors']])
        local,shared=decode_factors(fac)
        cx=covariance_from_factors(fac,'x');cy=covariance_from_factors(fac,'y')
        self.assertTrue(np.all(np.linalg.eigvalsh(cx)>=-1e-10))
        self.assertGreater(abs(cx[0,1]),0)
        np.testing.assert_allclose(np.diag(cx),np.square(r['sigma_x']))
        np.testing.assert_allclose(np.diag(cy),np.square(r['sigma_y']))
        self.assertEqual(local.shape,(3,2,2))
        self.assertEqual(shared.shape,(6,12))
    def test_override_independent(self):
        spec={'mode':'physical_override','override_standard_uncertainty':[.4,.8],
              'rationale':'Explicit physical review'}
        r=propagate(self.p,self.pixels,spec)
        self.assertFalse(r['shared_calibration'])
        np.testing.assert_allclose(r['sigma_x'],.4)
        np.testing.assert_allclose(r['sigma_y'],.8)
        np.testing.assert_allclose(r['covariance_xy'],0)
        f=compact_factors([r['local_factors']],[r['shared_factors']])
        np.testing.assert_allclose(covariance_from_factors(f,'y'),np.eye(3)*.64)
    def test_scale_bar_model_is_not_misrepresented(self):
        with self.assertRaisesRegex(UncertaintyError,'SEM scale-bar'):
            checked_spec(self.pixel(),scale_bar=True)
        with self.assertRaises(UncertaintyError):
            checked_spec({'mode':'physical_override','override_standard_uncertainty':[1,2]})
    def test_review_fingerprint_tracks_science_not_presentation(self):
        base={'source':{'dataset_id':'original','sha256':'aaa'},
              'axes':{'x':{'minimum':0,'maximum':1}},
              'curves':[{'id':'c1','points':[{'id':'p1','pixel':{'x':2,'y':3}}]}],
              'calibration':{'points':{}},'notes':'first','display':{'image_opacity':90}}
        import copy
        later=copy.deepcopy(base)
        later['notes']='second';later['display']['image_opacity']=20
        self.assertEqual(review_fingerprint(base),review_fingerprint(later))
        later['curves'][0]['points'][0]['pixel']['x']=4
        self.assertNotEqual(review_fingerprint(base),review_fingerprint(later))

    def test_explicit_zero_pixel_localization_with_shared_calibration(self):
        spec=self.pixel()
        spec['pixel_scale']=[0.0,0.0]
        self.assertEqual(checked_spec(spec)['pixel_scale'],[0.0,0.0])
        r=propagate(self.p,self.pixels,spec)
        self.assertTrue(r['shared_calibration'])
        self.assertTrue(np.any(np.asarray(r['sigma_x'])>0))
        self.assertTrue(np.any(np.asarray(r['sigma_y'])>0))
        self.assertTrue(np.all(r['local_factors']==0.0))
        self.assertTrue(np.any(r['shared_factors']!=0.0))
        self.assertTrue(np.all(np.isfinite(r['covariance_xy'])))
    def test_explicit_all_zero_does_not_create_minimum_sigma(self):
        spec=self.pixel()
        spec['pixel_scale']=[0.,0.]
        spec['calibration_standard_uncertainty']=[0.]*12
        r=propagate(self.p,self.pixels,spec)
        self.assertFalse(r['shared_calibration'])
        self.assertEqual(r['sigma_x'],[0.]*len(self.pixels))
        self.assertEqual(r['sigma_y'],[0.]*len(self.pixels))
        self.assertEqual(r['covariance_xy'],[0.]*len(self.pixels))
        with self.assertRaises(UncertaintyError):
            checked_spec({**spec,'pixel_scale':[-.1,0.]})

    def test_matrix_limit(self):
        p=Project()
        for name,xy in zip(CORNER_ORDER,[(0,100),(100,100),(0,0),(100,0)]):p.calibration.set_corner(name,*xy)
        arr=np.stack((np.arange(513,dtype=float)%100, np.full(513,50.)),axis=1)
        r=propagate(p,arr,dict(mode='physical_override',override_standard_uncertainty=[.1,.1],rationale='test'))
        fac=compact_factors([r['local_factors']],[r['shared_factors']])
        with self.assertRaisesRegex(UncertaintyError,'512'):
            covariance_from_factors(fac)

if __name__=='__main__':unittest.main()
