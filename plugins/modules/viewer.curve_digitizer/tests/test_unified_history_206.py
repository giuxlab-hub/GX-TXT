# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise exactly the real 2.0.6 history methods, without Tk or NumPy."""
import ast
import copy
import pathlib
import types
import unittest

src=pathlib.Path(__file__).resolve().parents[1]/'python'/'gxtxt_curve_digitizer.py'
tree=ast.parse(src.read_text(encoding='utf8'))
app=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='CurveDigitizerApp')
names={'_history_capture','snapshot','_restore_history','undo','redo'}
selected=[n for n in app.body if isinstance(n,ast.FunctionDef) and n.name in names]
assert len(selected)==len(names)
test_class=ast.ClassDef(name='HistoryCode',bases=[],keywords=[],body=selected,decorator_list=[])
mod=ast.Module(body=[test_class],type_ignores=[])
ast.fix_missing_locations(mod)
ns={'copy':copy}
exec(compile(mod,str(src),'exec'),ns)
HistoryCode=ns['HistoryCode']

class Model:
    def find_series(self,_id):return object()

class Harness(HistoryCode):
    def __init__(self):
        self.current_doc_id='doc1'
        self.session_token='session1'
        self.config={'tag':'original','tracing_constraints':
                     {'paths_by_curve':{'curve-1':[{'nodes':[[1,2],[3,4]]}]}}}
        self.active_series_id='curve-1'
        self.project=Model()
        self.proposal='p0'
        self.undo_stack=[]
        self.redo_stack=[]
        self._proposal_history=[]
        self.exclusion_selected_id=None
        self._proposal_last_insert=None
    def serialize_configuration(self):return copy.deepcopy(self.config)
    def _proposal_state(self):return copy.deepcopy(self.proposal)
    def restore_snapshot(self,cfg,*,persist=True):self.config=copy.deepcopy(cfg)
    def refresh_curve_tree(self):pass
    def exclusion_refresh_list(self):pass
    def _restore_proposal_state(self,state):self.proposal=copy.deepcopy(state)
    def persist(self):pass

class UnifiedHistory206(unittest.TestCase):
    def test_chronological_and_branch_redo(self):
        a=Harness()
        a.snapshot()
        a.config['tag']='exclusion'
        a.snapshot()
        a.config['tag']='curve'
        a.proposal='p2'
        a.undo()
        self.assertEqual((a.config['tag'],a.proposal),('exclusion','p0'))
        a.undo()
        self.assertEqual(a.config['tag'],'original')
        a.redo()
        self.assertEqual(a.config['tag'],'exclusion')
        a.snapshot()
        a.config['tag']='new_branch'
        self.assertEqual(a.redo_stack,[])

    def test_single_drag_preimage(self):
        a=Harness()
        a.config['tracing_constraints']['paths_by_curve']['curve-1'][0]['nodes'][0]=[8,9]
        a.snapshot(exclusion_previous=(0,0,[1,2]))
        a.config['tag']='dragged'
        a.undo()
        self.assertEqual(a.config['tracing_constraints']['paths_by_curve']['curve-1'][0]['nodes'][0],[1,2])

    def test_session_guard(self):
        a=Harness()
        a.snapshot()
        a.session_token='new_session'
        a.undo()
        self.assertFalse(a.undo_stack)
        self.assertFalse(a.redo_stack)

if __name__=='__main__':unittest.main(verbosity=2)
