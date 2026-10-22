# SPDX-License-Identifier: GPL-3.0-or-later
"""Headless live Companion stroke-width fields; no host or numeric dependencies."""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import types
import unittest
root=pathlib.Path(__file__).resolve().parents[1]
class Point:
    def __init__(self,d):
        self.id=d['id'];self.pixel_x=d['pixel_x'];self.pixel_y=d['pixel_y']
class Series:
    def __init__(self,d):
        self.id=d['id'];self.name=d['name'];self.points=[Point(p) for p in d['points']]
class Project:
    @classmethod
    def from_dict(cls,d):
        obj=cls();obj.series=[Series(x) for x in d['series']];return obj
    def find_series(self,cid):return next((x for x in self.series if x.id==cid),None)
    def calibration_ready(self):return False
fake=types.ModuleType('digitizer_model')
fake.Project=Project;fake.DigitizedPoint=Point
sys.modules['digitizer_model']=fake
spec=importlib.util.spec_from_file_location('companion_under_test',root/'python'/'companion_bridge.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Contract(unittest.TestCase):
    def config(self):
        pts=[{'id':'p1','pixel_x':1,'pixel_y':8},{'id':'p2','pixel_x':3,'pixel_y':9},{'id':'p3','pixel_x':5,'pixel_y':10}]
        key=hashlib.sha256(json.dumps([[p['id'],p['pixel_x'],p['pixel_y']] for p in pts],separators=(',',':')).encode()).hexdigest()
        return {'format':'gxtxt.curve_digitizer.configuration','version':'1.0',
                'configuration_id':'doc-conf','source':{'dataset_id':'image0','sha256':'sha-1'},
                'curves':[{'id':'curve-1','name':'Vintage curve','points':pts}],
                'stroke_width':{'source_sha256':'sha-1','by_curve':{'curve-1':{
                    'enabled':True,'source_sha256':'sha-1','method':'automatic',
                    'result':{'width_px':3.25,'trace_sha256':key}}}}}
    def run_context(self,cfg):
        with tempfile.TemporaryDirectory() as td:
            p=pathlib.Path(td)/'input.json'
            p.write_text(json.dumps(cfg),encoding='utf8')
            buf=io.StringIO()
            with contextlib.redirect_stdout(buf):
                module.command_context(types.SimpleNamespace(input=str(p),curve_id='curve-1'))
            encoded={}
            for raw in buf.getvalue().splitlines():
                a,b=raw.split('\t',1)
                encoded[a]=b if a in ('CALIBRATION_READY','CURVE_POINT_COUNT') else base64.b64decode(b).decode()
            return encoded
    def test_public_status_valid(self):
        f=self.run_context(self.config())
        self.assertEqual(f['STROKE_WIDTH_STATUS'],'measured')
        self.assertEqual(f['STROKE_WIDTH_PX'],'3.25')
        self.assertEqual(json.loads(f['STROKE_WIDTH_JSON'])['source_sha256'],'sha-1')
    def test_stale_trace_and_source(self):
        cfg=self.config()
        cfg['curves'][0]['points'][1]['pixel_y']=17
        self.assertEqual(self.run_context(cfg)['STROKE_WIDTH_STATUS'],'unavailable')
        cfg=self.config();cfg['source']['sha256']='sha-2'
        self.assertEqual(self.run_context(cfg)['STROKE_WIDTH_STATUS'],'unavailable')
    def test_opt_out(self):
        cfg=self.config()
        cfg['stroke_width']['by_curve']['curve-1']['enabled']=False
        result=self.run_context(cfg)
        self.assertEqual(result['STROKE_WIDTH_STATUS'],'inactive')
        self.assertEqual(result['STROKE_WIDTH_PX'],'')
if __name__=='__main__':unittest.main(verbosity=2)
