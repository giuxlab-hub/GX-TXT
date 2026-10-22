# SPDX-License-Identifier: GPL-3.0-or-later
"""Hermetic public contract and stroke editor state tests (no Tk display)."""
import copy
import importlib.util
import pathlib
import sys
import types
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Var:
    def __init__(self,value=None):self.v=value
    def get(self):return self.v
    def set(self,value):self.v=value
fake_tk=types.ModuleType('tkinter')
fake_tk.BooleanVar=Var
fake_tk.StringVar=Var
fake_tk.IntVar=Var
fake_tk.TclError=Exception
fake_tk.ttk=types.SimpleNamespace()
sys.modules['tkinter']=fake_tk
sys.modules['assisted_constraints']=types.SimpleNamespace(spline_points=lambda nodes,spacing=1.5:nodes)
sys.modules['stroke_width_measure']=types.SimpleNamespace(
    automatic_width=lambda *_args,**_kwargs:{'method':'automatic','width_px':3.5,'accepted_samples':15,'rejected_samples':4},
    manual_width=lambda *_args,**_kwargs:{'method':'manual','width_px':4.1,'accepted_samples':20,'rejected_samples':0})
spec=importlib.util.spec_from_file_location('stroke_ui_test',ROOT/'python'/'stroke_width_ui.py')
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class P:
    def __init__(self,i,x,y):self.id=i;self.pixel_x=x;self.pixel_y=y
class S:
    def __init__(self):self.id='curve_1';self.name='Test Curve';self.points=[P('a',2,8),P('b',10,8),P('c',18,8)]
class Canvas:
    def image_to_canvas(self,x,y):return x,y
class Harness(m.StrokeWidthUI):
    def __init__(self):
        self.loading_ui=False
        self.active_series_id='curve_1'
        self.series=S()
        self.config={'source':{'sha256':'SHA_A'}}
        self.image=object()
        self.mode=Var('add')
        self.canvas=Canvas()
        self.undo_stack=[];self.redo_stack=[]
        self.snapshots=0
        self.stroke_setup()
    def active_series(self):return self.series
    def snapshot(self):
        self.snapshots+=1
        self.undo_stack.append(self._history_capture())
    def _history_capture(self):return copy.deepcopy(self.stroke_serialize())
    def persist(self):self.config['stroke_width']=self.stroke_serialize()
    def redraw(self):pass
    def require_working_source(self):return True
class Stroke(unittest.TestCase):
    def test_default_and_curve_toggle(self):
        h=Harness()
        self.assertEqual(h.stroke_data,{})
        h.stroke_enabled.set(True)
        h.stroke_preferences_changed()
        self.assertTrue(h.stroke_active_record()['enabled'])
        self.assertEqual(h.stroke_active_record()['source_sha256'],'SHA_A')
        self.assertEqual(h.snapshots,1)
        self.assertEqual(h.stroke_summary(),'Test Curve: ACTIVE (automatic); measurement not yet computed.' if False else 'Test Curve: enabled; no valid current measurement.')
    def test_automatic_source_and_trace_staleness(self):
        h=Harness()
        h.stroke_enabled.set(True);h.stroke_preferences_changed()
        h.stroke_auto_measure()
        self.assertTrue(h.stroke_valid_result(h.series,h.stroke_active_record()))
        self.assertIn('3.50 px',h.stroke_summary())
        h.series.points[1].pixel_y+=3
        self.assertFalse(h.stroke_valid_result(h.series,h.stroke_active_record()))
        h.config['source']['sha256']='SHA_B'
        self.assertFalse(h.stroke_valid_result(h.series,h.stroke_active_record()))
        h.stroke_reset_curve()
        self.assertEqual(h.stroke_origin_sha,'SHA_B')
        self.assertFalse(h.stroke_active_record())
    def test_manual_node_drag_one_checkpoint(self):
        h=Harness()
        h.stroke_enabled.set(True);h.stroke_preferences_changed()
        h.stroke_method.set('manual');h.stroke_preferences_changed()
        h.stroke_visible=True
        h.stroke_edge_press(4,5)
        h.stroke_edge_press(20,5)
        before=h.snapshots
        h.stroke_edge_press(4,5)
        h.stroke_edge_drag(5,6)
        h.stroke_edge_release(6,6)
        self.assertEqual(h.snapshots,before)
        self.assertEqual(len(h.undo_stack),before+1)
        self.assertEqual(h.stroke_path()[0],[6,6])
        self.assertEqual(h.undo_stack[-1]['by_curve']['curve_1']['edges']['A'][0],[4,5])
    def test_public_api_and_metadata_registration(self):
        desc=(ROOT/'module.ini').read_text(encoding='utf8')
        gui=(ROOT/'python'/'gxtxt_curve_digitizer.py').read_text(encoding='utf8')
        api=(ROOT/'api'/'curve_digitizer_stroke_width_api_v1.tcl').read_text(encoding='utf8')
        self.assertIn('ids=CURVE_DIGITIZER_VIEWER_API_v1;',desc)
        self.assertIn('CURVE_DIGITIZER_STROKE_WIDTH_API_v1',desc)
        self.assertIn('entrypoint=api/curve_digitizer_stroke_width_api_v1.tcl',desc)
        for proc in ('configurationRead','curveRead','hasPublished','publishedRead'):
            self.assertIn('::GX::CurveDigitizerStrokeWidth::'+proc,api)
        self.assertIn('curve_digitizer.stroke_width_report_json',gui)
        self.assertIn('stroke_width',gui)
        self.assertIn('self.stroke_panel.pack_forget()',gui)
if __name__=='__main__':unittest.main(verbosity=2)
