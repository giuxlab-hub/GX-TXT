# SPDX-License-Identifier: GPL-3.0-or-later
"""Headless regression: exclusion-list identity, toggles, edit transactions."""
import copy
import importlib.util
import pathlib
import sys
import types
import unittest

root=pathlib.Path(__file__).resolve().parents[1]
fake=types.ModuleType('assisted_constraints')
fake.spline_points=lambda nodes,spacing=2: nodes
sys.modules['assisted_constraints']=fake
tk=types.ModuleType('tkinter')
tk.messagebox=types.SimpleNamespace(askyesno=lambda *_args,**_kw:True)
sys.modules['tkinter']=tk
spec=importlib.util.spec_from_file_location('exclusion_under_test',
                                      root/'python'/'assisted_exclusion_ui.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Variable:
    def __init__(self,value):self.value=value
    def get(self):return self.value
    def set(self,value):self.value=value

class Surface:
    def image_to_canvas(self,x,y):return x,y

class Harness(module.ExclusionControls):
    def __init__(self):
        self.active_series_id='curve-A'
        self.config={'source':{'sha256':'sourceA'}}
        self.assist_smoothness=Variable('Off')
        self.exclusion_enabled=Variable(True)
        self.exclusion_width=Variable(6)
        self.exclusion_path_index=Variable(1)
        self.exclusion_status=Variable('')
        self.mode=Variable('add')
        self.loading_ui=False
        self.canvas=Surface()
        self.root=object()
        self.history=[]
        self.snapshots=0
        self.assisted_proposal=None
        self.exclusion_setup()
    def require_working_source(self):return True
    def snapshot(self,**kwargs):
        self.snapshots+=1
        self.history.append((copy.deepcopy(self.exclusion_paths),kwargs))
    def persist(self):
        self.config['tracing_constraints']=self.exclusion_record()
    def redraw(self):pass

class Exclusion206(unittest.TestCase):
    def test_create_nodes_move_toggle_and_clear(self):
        h=Harness()
        h.exclusion_new_path()
        self.assertEqual(len(h.exclusion_entries()),1)
        h.exclusion_press(10,20)
        h.exclusion_press(40,50)
        self.assertEqual(len(h.exclusion_active_paths()),1)
        self.assertEqual(len(h.exclusion_entries()[0]['nodes']),2)
        h.exclusion_press(10,20)
        h.exclusion_move(18,20)
        before=h.snapshots
        h.exclusion_release(18,20)
        self.assertEqual(h.snapshots,before+1)
        self.assertEqual(h.history[-1][1]['exclusion_previous'][2],[10,20])
        stable=h.exclusion_entries()[0]['id']
        h.exclusion_toggle_path(stable)
        self.assertEqual(h.exclusion_active_paths(),())
        self.assertFalse(h.exclusion_entries()[0]['enabled'])
        h.exclusion_toggle_path(stable)
        self.assertEqual(len(h.exclusion_active_paths()),1)
        h.exclusion_clear_all()
        self.assertFalse(h.exclusion_paths)
        self.assertEqual(h.exclusion_origin_sha,'sourceA')

    def test_per_path_enable_independent_from_selection(self):
        h=Harness()
        h.exclusion_new_path()
        h.exclusion_press(1,1);h.exclusion_press(25,25)
        first=h.exclusion_entries()[0]['id']
        h.exclusion_new_path()
        h.exclusion_press(50,50);h.exclusion_press(80,80)
        second=h.exclusion_entries()[1]['id']
        self.assertEqual(len(h.exclusion_active_paths()),2)
        h.exclusion_toggle_path(first)
        self.assertEqual(h.exclusion_selected_id,second)
        self.assertEqual(len(h.exclusion_active_paths()),1)
        self.assertEqual(h.exclusion_active_paths()[0],h.exclusion_entries()[1]['nodes'])
        h.exclusion_enabled.set(False)
        self.assertEqual(h.exclusion_active_paths(),())
        self.assertTrue(h.exclusion_entries()[1]['enabled'])
        h.exclusion_enabled.set(True)
        self.assertEqual(len(h.exclusion_active_paths()),1)

    def test_legacy_migration_stable_identity(self):
        h=Harness()
        h.config['tracing_constraints']={'source_sha256':'sourceA',
            'paths_by_curve':{'curve-A':[[[1,2],[3,4]],[[6,7],[8,9]]]}}
        h.exclusion_load()
        ids=[p['id'] for p in h.exclusion_entries()]
        self.assertTrue(all(p['enabled'] for p in h.exclusion_entries()))
        h.exclusion_load()
        self.assertEqual(ids,[p['id'] for p in h.exclusion_entries()])

    def test_width_change_has_config_checkpoint(self):
        h=Harness()
        h.persist()
        h.exclusion_width.set(9)
        h.exclusion_config_changed()
        self.assertEqual(h.snapshots,1)
        self.assertTrue(h.history[-1][1].get('saved_config'))
        self.assertEqual(h.config['tracing_constraints']['width'],9)
        h.exclusion_config_changed()
        self.assertEqual(h.snapshots,1)

if __name__=='__main__':unittest.main(verbosity=2)
