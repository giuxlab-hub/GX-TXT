# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression: 1.2.22 compact UI, click-to-delete, far correction and point sorting."""
from pathlib import Path
import sys,tkinter as tk
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series
from point_ordering import normalize

def records(*rows):return '\n'.join('\t'.join([kind]+[b64e(str(v)) for v in values]) for kind,values in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
        if cmd=='IMAGE_TOOL':return ''
        raise AssertionError((cmd,args))
root=tk.Tk();root.geometry('1300x860')
app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('order demo')
app.config['source']={'dataset_id':'raster','sha256':'a'*64,'width':320,'height':220}
app.current_doc_id='one';app.document_sha['one']='a'*64
img=Image.new('RGB',(320,220),'white');d=ImageDraw.Draw(img)
d.line([(12,190),(100,100),(210,65),(290,35)],fill='black',width=3)
app.set_image(img)
app.notebook.select(app.curves_tab)
series=Series(name='c');app.project.series=[series];app.active_series_id=series.id;app.refresh_curve_tree()
for label,x,y in [('bottom_left',0,219),('bottom_right',319,219),('top_left',0,0),('top_right',319,0)]:
    app.project.calibration.set_corner(label,x,y)
app.curve_monotonicity.set('x');app.point_order_source.set('x')
for x in (220,30,130):app.add_point(x,110)
assert [round(p.pixel_x) for p in series.points]==[30,130,220]
# Make sure the new mode deletes via an on-image click, undo-safe.
app.mode.set('delete');app.canvas_press(130,110)
assert [round(p.pixel_x) for p in series.points]==[30,220]
app.undo();series=app.active_series()
assert [round(p.pixel_x) for p in series.points]==[30,130,220]
# Re-add using Add, automatically inserted between existing points.
app.mode.set('add');app.canvas_press(80,110)
assert [round(p.pixel_x) for p in app.active_series().points]==[30,80,130,220]
# Guide points are sorted by calibrated X regardless of click sequence.
app.mode.set('guide')
for x,y in [(290,35),(12,190),(160,80)]:app.canvas_press(x,y)
assert [x for x,y in app.guide_points]==[12.,160.,290.]
app._finish_guided_proposal(None,'offline')
assert app.assisted_proposal and len(app.assisted_proposal.segments)==2
n=len(app.guide_points)
app.assist_segment.set(1)
app.mode.set('correction')
app.canvas_press(90,185)  # deliberately far from the proposed trace
assert len(app.guide_points)==n+1,app.assist_status.get()
assert len(app.assisted_proposal.segments)==3
assert not app.assist_accepted_segments
saved=app.serialize_configuration()
assert saved['curve_ordering']=={'monotonicity':'x','source':'x'}
assert [round(p['pixel']['x']) for p in saved['curves'][0]['points']]==[30,80,130,220]
# Other configurations keep their original insertion order.
new=app.new_configuration('different')
assert new['curve_ordering']=={'monotonicity':'none','source':'insertion'}
assert normalize(new['curve_ordering'])['source']=='insertion'
# UI has no deleted button; single-row snapping and a color swatch.
frame=next(c for c in app.curves_body.winfo_children() if c.winfo_class()=='TLabelframe' and c.cget('text')=='Point interaction')
texts=[c.cget('text') for c in frame.winfo_children() if c.winfo_class()=='TRadiobutton']
assert texts==['Add','Move','Delete','Add guide','Edit proposal','Add correction point'],texts
assert app.canvas_color_swatch.winfo_exists()
root.destroy();print('PASS 1.2.22 point ordering, delete mode, far correction and compact UI')
