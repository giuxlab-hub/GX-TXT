# SPDX-License-Identifier: GPL-3.0-or-later
"""Accept uses exact N; Resample changes only the live accepted batch."""
import sys,tkinter as tk
from pathlib import Path
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
import gxtxt_curve_digitizer as gui
from digitizer_model import Series,DigitizedPoint

def records(*rows):return '\n'.join('\t'.join([kind]+[gui.b64e(str(v)) for v in vals]) for kind,vals in rows)
class RPC:
 def attach(self,root):pass
 def call(self,cmd,*args):
  if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'session']) for k,v in gui.CORE_PREFS.items()))
  if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
  if cmd=='IMAGE_TOOL':return ''
  raise AssertionError((cmd,args))
root=tk.Tk();root.geometry('1350x850')
app=gui.CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['s'])))
app.config=app.new_configuration('N');app.config['source']={'dataset_id':'raster','sha256':'a'*64,'width':300,'height':160}
app.current_doc_id='one';app.document_sha['one']='a'*64
im=Image.new('RGB',(300,160),'white');d=ImageDraw.Draw(im)
d.line([(8,135),(110,65),(200,75),(290,35)],fill='black',width=3)
app.set_image(im);app.notebook.select(app.curves_tab)
series=Series(name='C');app.project.series=[series];app.active_series_id=series.id
for key,x,y in [('bottom_left',0,159),('bottom_right',299,159),('top_left',0,0),('top_right',299,0)]:
 app.project.calibration.set_corner(key,x,y)
manual=DigitizedPoint(pixel_x=250,pixel_y=110,manual_pixel_x=250,manual_pixel_y=110)
app.project.update_point_calibration(manual);series.points.append(manual)
app.guide_points=[(8.,135.),(110.,65.),(200.,75.),(290.,35.)]
app._finish_guided_proposal(None,'offline')
assert app.assisted_proposal and len(app.assisted_proposal.segments)==3
old=gui.messagebox.askyesno;gui.messagebox.askyesno=lambda *a,**kw:True
try:
 app.assist_output_points.set('29')
 app.accept_guided_trace()
 assert len(series.points)==30,(len(series.points),app.assist_status.get())
 assert len([p for p in series.points if p.origin=='assisted'])==29
 assert manual in series.points
 app.assist_output_points.set('51')
 app.resample_accepted_trace()
 assert len(series.points)==52
 assert manual in series.points
 assert len([p for p in series.points if p.origin=='assisted'])==51
 assert app.serialize_configuration()['assisted_tracing']['output_points']==51
 app.undo()
 assert len(app.active_series().points)==30
finally:
 gui.messagebox.askyesno=old
 root.destroy()
print('PASS output density Accept/Resample, manual preservation and Undo')
