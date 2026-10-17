"""Xvfb: verify central Configuration settings control an open Python viewer."""
import sys
import tkinter as tk
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e, b64d


def records(*rows):
    return '\n'.join('\t'.join([name] + [b64e(str(v)) for v in fields]) for name, fields in rows)

class Rpc:
    def __init__(self):
        self.values = dict(CORE_PREFS)
        self.n = 0
        self.out = {}
        self.changes = []
    def attach(self, root): pass
    def settings(self):
        return records(*(('SETTING',[key,val,'user']) for key,val in self.values.items()))
    def begin(self, cmd,*args):
        self.n += 1
        rid = str(self.n)
        assert cmd == 'CONFIG_READ',cmd
        self.out[rid] = self.settings()
        return rid
    def poll_response(self,rid):return self.out.pop(rid)
    def call(self, cmd,*args):
        if cmd == 'CONFIG_READ':return self.settings()
        if cmd == 'CONFIG_COMMIT':
            assert args[0] == 'session'
            updates = {}
            for line in args[1].splitlines():
                key, old, new = line.split('\t')
                assert self.values[key] == b64d(old)
                updates[key] = b64d(new)
            self.values.update(updates)
            self.changes.append(updates)
            return self.settings()
        raise AssertionError(cmd)

root=tk.Tk();root.withdraw()
rpc=Rpc()
payload=records(('SESSION',['session']), *(('SETTING',[k,v,'user']) for k,v in rpc.values.items()))
app=CurveDigitizerApp(root,rpc,bootstrap_payload=payload)
root.deiconify();root.update_idletasks()
assert app.show_scale_overlay.get() and not app.snap_enabled.get()
assert app.shared_settings['snap_radius']=='3'
# CORE central editor changes defaults with an already open viewer.
rpc.values['snap_radius'] = '12';rpc.values['snap_enabled']='1';rpc.values['show_point_numbers']='1'
app._sync_shared_settings()
assert app.snap_enabled.get() and app.snap_radius.get()==12 and app.show_numbers.get()
rpc.values['publication_layout']='combined'
rpc.values['publication_name_template']='[name].[index]'
app._sync_shared_settings()
assert app.publish_layout.get() == 'combined'
assert app.publish_name_template.get() == '[name].[index]'
# A direct viewer adjustment writes back via CORE transaction, not Documents.
app.snap_radius.set(4)
app.snap_changed()
assert rpc.values['snap_radius'] == '4'
assert app.shared_settings['snap_radius']=='4'
# The calibration's committed source and physical scale remain untouched.
app.config['scale_reference']={'pixel_length':151,'physical_length':10,'unit':'µm','edge_convention':'center'}
app.scale_length.set('10')
rpc.values['scale_length']='5'
app._sync_shared_settings()
assert app.scale_length.get() == '10'
# User can switch per-measurement tick edges without altering User/Session defaults.
app.scale_edge_convention.set('Outer edges of ticks')
app.scale_convention_changed()
assert rpc.values['scale_edge']=='center'
assert len(rpc.changes)==1
root.destroy()
print('PASS live CORE settings, local CORE commit, unchanged saved measurement, independent scale choice')
