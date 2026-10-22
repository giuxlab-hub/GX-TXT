# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression for the per-curve selection and optional stroke panel refresh."""
import ast
from pathlib import Path
import unittest

source=Path(__file__).resolve().parents[1]/"python"/"gxtxt_curve_digitizer.py"
tree=ast.parse(source.read_text(encoding="utf-8"))
cls=next(c for c in tree.body if isinstance(c,ast.ClassDef) and c.name=="CurveDigitizerApp")
method=next(m for m in cls.body if isinstance(m,ast.FunctionDef) and m.name=="on_curve_selected")
stub=ast.ClassDef(name="SelectedCurve",bases=[],keywords=[],body=[method],decorator_list=[])
unit=ast.Module(body=[stub],type_ignores=[])
ast.fix_missing_locations(unit)
scope={}
exec(compile(unit,str(source),"exec"),scope)

class FakeTree:
    def __init__(self):self.row=("trace_B",)
    def selection(self):return self.row

class App(scope["SelectedCurve"]):
    def __init__(self):
        self.curve_tree=FakeTree()
        self.active_series_id="trace_A"
        self.guide_points=[(1,2)]
        self.assisted_proposal=object()
        self.assist_accepted_segments={1}
        self.assist_accepted_point_ids={1:[42]}
        self._assist_sampling_spec="old"
        self._assist_drag=("guide",0)
        self._assist_preview_cursor=(10,20)
        self.selected_point_id="old point"
        self.panel_curve="trace_A"
        self.calls=[]
    def stroke_refresh(self):
        self.panel_curve=self.active_series_id
        self.calls.append(("stroke_refresh",self.active_series_id))
    def update_selected(self):self.calls.append(("update_selected",self.active_series_id))
    def redraw(self):self.calls.append(("redraw",self.active_series_id))

class SelectionRegression(unittest.TestCase):
    def test_switch_updates_stroke_panel_to_same_curve(self):
        app=App()
        app.on_curve_selected()
        self.assertEqual(app.active_series_id,"trace_B")
        self.assertEqual(app.panel_curve,"trace_B")
        self.assertEqual(app.guide_points,[])
        self.assertIsNone(app.assisted_proposal)
        self.assertEqual(app.calls[0],("stroke_refresh","trace_B"))
    def test_reselect_active_keeps_proposal(self):
        app=App()
        app.curve_tree.row=("trace_A",)
        proposal=app.assisted_proposal
        app.on_curve_selected()
        self.assertIs(app.assisted_proposal,proposal)
        self.assertEqual(app.panel_curve,"trace_A")

if __name__=="__main__": unittest.main(verbosity=2)
