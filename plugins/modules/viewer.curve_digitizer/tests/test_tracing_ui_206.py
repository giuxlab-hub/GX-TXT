# SPDX-License-Identifier: GPL-3.0-or-later
"""Static integration contract for the 2.0.6 Tk arrangement and menu routes."""
from pathlib import Path
import ast
import unittest
source=(Path(__file__).resolve().parents[1]/'python'/'gxtxt_curve_digitizer.py').read_text(encoding='utf8')
exclusions=(Path(__file__).resolve().parents[1]/'python'/'assisted_exclusion_ui.py').read_text(encoding='utf8')
class UI206(unittest.TestCase):
    def test_two_rows_and_real_per_path_list(self):
        self.assertIn('settings.grid(row=0, column=0',source)
        self.assertIn('actions.grid(row=0, column=1',source)
        self.assertIn('exclude.grid(row=1,column=0,columnspan=2',source)
        self.assertIn('self.exclusion_list=ttk.Treeview',source)
        self.assertIn('self.exclusion_list.bind("<Button-1>",self.exclusion_table_click)',source)
        self.assertNotIn('text="Path #"',source)
        self.assertNotIn('"Undo X"',source)
        self.assertNotIn('"Redo X"',source)
    def test_global_undo_redo_actions(self):
        self.assertIn('command=self.undo',source)
        self.assertIn('command=self.redo',source)
        self.assertIn('self._history_capture(proposal_override=before)',source)
        self.assertIn('self.snapshot(exclusion_previous=(i,j,start))',exclusions)
        self.assertIn("target['enabled']=not target['enabled']",exclusions)
        self.assertIn("self.snapshot(saved_config=True)",exclusions)
        self.assertIn('self._assist_proposal_stale',source)
        ast.parse(source);ast.parse(exclusions)
if __name__=='__main__':unittest.main(verbosity=2)
