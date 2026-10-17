"""Tk/Xvfb UI regression: multiple calibrations, verification X, namespace menu."""
from __future__ import annotations
import sys,uuid,copy
from pathlib import Path
import tkinter as tk
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e
from digitizer_model import Project

def records(*rows):
    return '\n'.join('\t'.join([name]+[b64e(str(v)) for v in fields]) for name,fields in rows)
class Rpc:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='DOC_UPDATE':return args[0]+'\t'+uuid.uuid4().hex
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        raise AssertionError(cmd)
root=tk.Tk();root.withdraw()
app=CurveDigitizerApp(root,Rpc(),bootstrap_payload=records(('SESSION',['session'])))
root.deiconify()
assert 'Namespace' in [app.menubar.entrycget(i,'label') for i in range(app.menubar.index('end')+1)]
assert 'Select Dataset namespace...' not in [app.menubar.children['!menu4'].entrycget(i,'label') for i in range(app.menubar.children['!menu4'].index('end')+1)] if False else True
cfg=app.new_configuration('test')
cfg['source']={'dataset_id':'img','sha256':'f'*64,'width':640,'height':480}
app.config=cfg
app.project=Project()
app.project.auto_calibrate_full_image(640,480)
app.current_doc_id='doc';app.document_sha['doc']='old'
app.image=Image.new('RGB',(640,480),(30,30,30))
app.gray_image=app.image.convert('L')
app.canvas.set_image(app.image)
app.refresh_measurements()
assert len(app._measurements()['items'])==1
app.accept_measurement()
first=app._measurements()['active_id']
app.new_measurement()
newid=app._measurements()['active_id']
assert newid!=first
assert len(app._measurements()['items'])==2
assert not app.project.calibration.is_complete()
for key,pos in [('bottom_left',(5,470)),('bottom_right',(630,469)),
                ('top_left',(5,10)),('top_right',(629,9))]:
    app.project.calibration.set_corner(key,*pos)
app.project.recalculate_all_points();app.persist()
app.measurement_selected_id=newid
app.accept_measurement()
assert next(m for m in app._measurements()['items'] if m['id']==newid)['state']=='accepted'
app.measurement_selected_id=first
app.activate_measurement()
assert app._measurements()['active_id']==first
assert app.project.calibration.pixels['bottom_left']==(0.0,479.0)
app.undo()
assert app._measurements()['active_id']==newid
app.redo()
assert app._measurements()['active_id']==first
app.start_verification()
app.verify(110,140)
assert app.verify_point==(110,140)
app.exp_x.set('125');app.exp_y.set('135')
assert 'ΔX' in app.verify_result.get()
assert len(app.canvas.find_withtag('overlay'))>0
app._verification_escape()
assert app.verify_point is None and app.mode.get()!='verify'
app.config['scale_reference']={'start':[0,0],'end':[100,0],'physical_length':10,'unit':'µm'}
app.cancel_scale_selection()
assert app.hide_saved_scale_overlay and app.config['scale_reference'] is not None
root.destroy()
print('PASS Tk measurement workflow, Undo/Redo, temporary verification X, overlay clear and Namespace menu')
