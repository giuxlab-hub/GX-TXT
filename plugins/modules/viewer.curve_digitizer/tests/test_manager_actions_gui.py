"""Repeated-calibration manager safety actions, including active draft deletion."""
import sys,tkinter as tk,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from PIL import Image
from tkinter import messagebox,simpledialog
from digitizer_model import Project
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e

def records(*rows):return '\n'.join('\t'.join([kind]+[b64e(str(v)) for v in args]) for kind,args in rows)
class Rpc:
    def attach(self,r):pass
    def call(self,cmd,*a):
        if cmd=='DOC_UPDATE':return a[0]+'\t'+uuid.uuid4().hex
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        raise AssertionError(cmd)
root=tk.Tk();root.withdraw()
app=CurveDigitizerApp(root,Rpc(),bootstrap_payload=records(('SESSION',['session'])))
app.current_doc_id='doc';app.config=app.new_configuration('repeat')
app.config['source']={'dataset_id':'image','sha256':'a'*64}
app.image=Image.new('RGB',(200,100));app.canvas.set_image(app.image)
app.project=Project();app.project.auto_calibrate_full_image(200,100)
app.refresh_measurements()
first=app._measurements()['active_id']
app.new_measurement()
second=app._measurements()['active_id']
orig=messagebox.askyesno;messagebox.askyesno=lambda *a,**k:True
try:app.cancel_measurement()
finally:messagebox.askyesno=orig
assert len(app._measurements()['items'])==1
assert app._measurements()['active_id']==first
app.measurement_selected_id=first
orig=simpledialog.askstring;simpledialog.askstring=lambda *a,**k:'Calibration Main'
try:app.rename_measurement()
finally:simpledialog.askstring=orig
assert app._measurements()['items'][0]['label']=='Calibration Main'
# More than a single visible Treeview page, scroll is supported.
for i in range(9):app.new_measurement()
assert len(app._measurements()['items'])==10
assert app.measurement_table.cget('height')==5
assert app.measurement_table.cget('yscrollcommand')
root.destroy()
print('PASS cancel active draft, rename stable identity, long scrollable measurement manager')
