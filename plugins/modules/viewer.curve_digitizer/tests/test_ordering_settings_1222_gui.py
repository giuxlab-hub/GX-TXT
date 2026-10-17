# SPDX-License-Identifier: GPL-3.0-or-later
"""Viewer settings apply keeps monotonic ordering local to current config."""
import sys,tkinter as tk
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,b64d
from digitizer_model import Series,DigitizedPoint

def records(*rows):return '\n'.join('\t'.join([key]+[b64e(str(x)) for x in args]) for key,args in rows)
class RPC:
 def __init__(self):self.values=dict(CORE_PREFS)
 def attach(self,root):pass
 def call(self,cmd,*args):
  if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in self.values.items()))
  if cmd=='CONFIG_COMMIT':
   for line in args[1].splitlines():
    key,old,new=line.split('\t');self.values[key]=b64d(new)
   return self.call('CONFIG_READ')
  if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
  raise AssertionError((cmd,args))
root=tk.Tk();root.geometry('1350x850')
app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('first');app.current_doc_id='one';app.document_sha['one']='a'*64
app.project.series=[Series(name='c',points=[DigitizedPoint(pixel_x=x,pixel_y=30,calibrated_x=x,calibrated_y=30) for x in (70,5,50)])]
app.active_series_id=app.project.series[0].id
app.refresh_curve_tree()
app.open_viewer_settings();root.update()
w=app.settings_dialog

def walk(parent):
 for child in parent.winfo_children():
  yield child
  yield from walk(child)
combo=next(x for x in walk(w) if x.winfo_class()=='TCombobox' and 'Monotonic in X' in x.cget('values'))
order=next(x for x in walk(w) if x.winfo_class()=='TCombobox' and 'Sort by X' in x.cget('values'))
combo.set('Monotonic in X');root.update()
assert order.get()=='Sort by X',order.get()
apply=next(x for x in walk(w) if x.winfo_class()=='TButton' and x.cget('text')=='Apply')
apply.invoke();root.update()
assert app.curve_monotonicity.get()=='x'
assert app.point_order_source.get()=='x'
assert [p.pixel_x for p in app.project.series[0].points]==[5,50,70]
assert app.serialize_configuration()['curve_ordering']=={'monotonicity':'x','source':'x'}
root.destroy();print('PASS monotonicity and point order saved through viewer settings')
