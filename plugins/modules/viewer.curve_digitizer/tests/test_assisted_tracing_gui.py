# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk integration: no scientific point mutation without explicit Accept."""
from pathlib import Path
import sys,tkinter as tk
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e
from digitizer_model import Series

def records(*rows):
    return '\n'.join('\t'.join([key]+[b64e(str(x)) for x in values]) for key,values in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[key,v,'user']) for key,v in CORE_PREFS.items()))
        if cmd=='CONFIG_COMMIT':return records(*(('SETTING',[key,v,'session']) for key,v in CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
        if cmd=='IMAGE_TOOL':return ''
        raise AssertionError((cmd,args))
root=tk.Tk();root.geometry('1200x800')
app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('Assisted regression')
app.config['source']={'dataset_id':'example','sha256':'a'*64,'width':220,'height':120}
app.current_doc_id='test_doc';app.document_sha['test_doc']='a'*64
img=Image.new('RGB',(220,120),'white');ImageDraw.Draw(img).line([(6,60),(70,30),(110,70),(200,45)],fill='black',width=3)
app.set_image(img)
app.notebook.select(app.curves_tab)
series=Series(name='test');app.project.series=[series];app.active_series_id=series.id;app.refresh_curve_tree()
for label,x,y in [('bottom_left',0,119),('bottom_right',219,119),('top_left',0,0),('top_right',219,0)]:
    app.project.calibration.set_corner(label,x,y)
app.mode.set('guide')
for x,y in [(6,60),(70,30),(110,70),(200,45)]:app.canvas_press(x,y)
assert len(app.guide_points)==4
assert not series.points
app._finish_guided_proposal(None,'numeric API unavailable')
assert app.assisted_proposal and len(app.assisted_proposal.points)>20
assert not series.points
app.reject_guided_trace();assert not series.points and len(app.guide_points)==4
app._finish_guided_proposal(None,'fallback')
from tkinter import messagebox
old=messagebox.askyesno;messagebox.askyesno=lambda *args,**kw: True
try:app.accept_guided_trace()
finally:messagebox.askyesno=old
assert len(series.points)>20
assert all(p.origin=='assisted' for p in series.points)
assert app.assisted_proposal is not None and len(app.assist_accepted_segments)==3
# Presentation-only opacity changes preserve the authoritative raster image.
source=app.canvas.original_image
app.opacity_var.set(25);app.canvas_bg_var.set('#FFFFFF');app._apply_canvas_appearance()
assert app.canvas.original_image is source
assert app.canvas._display_image is not source
assert series.points[0].pixel_x>=0
app.notebook.select(app.calibration_tab)
app.delete_selected_point()
assert len(series.points)>20
root.destroy()
print('PASS guided proposals, rejection, acceptance, metadata origins, opacity and tab edit guards')
