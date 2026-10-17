# SPDX-License-Identifier: GPL-3.0-or-later
import sys, tkinter as tk
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from uncertainty_dialog import UncertaintyDialog
class Fake:
 def __init__(self,root):
  self.root=root;self.config={'uncertainty':{'mode':'none'},'scale_reference':None};self.snapshots=0;self.persisted=0
 def serialize_configuration(self):return self.config
 def commit_axes(self,flag):return True
 def snapshot(self):self.snapshots+=1
 def persist(self):self.persisted+=1;return True
root=tk.Tk();root.withdraw()
app=Fake(root);w=UncertaintyDialog(app)
assert w.values['pixel_scale'].get()==''
assert w.values['calibration_standard_uncertainty'].get()==''
assert w.values['override_standard_uncertainty'].get()==''
w.values['mode'].set('physical_override')
w.values['override_standard_uncertainty'].set('0.2 0.4')
w.values['rationale'].set('Reviewed physical standard uncertainty values')
w.apply()
assert app.config['uncertainty']['mode']=='physical_override'
assert app.config['uncertainty']['override_standard_uncertainty']==[.2,.4]
assert app.persisted==1 and app.snapshots==1
w.destroy();root.destroy()
print('PASS: v2.0 uncertainty dialog, explicit declaration and per-document persistence')
