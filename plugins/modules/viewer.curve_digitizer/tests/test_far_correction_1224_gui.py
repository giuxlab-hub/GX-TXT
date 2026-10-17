# SPDX-License-Identifier: GPL-3.0-or-later
"""GUI regression: far operator corrections are not proximity-gated."""
import pathlib, sys, tkinter as tk
from PIL import Image, ImageDraw
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series

def records(*rows):
    return '\n'.join('\t'.join([name]+[b64e(str(x)) for x in args]) for name,args in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
        if cmd=='IMAGE_TOOL':return ''
        raise AssertionError((cmd,args))
root=tk.Tk(); root.geometry('1380x920')
app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('far fix')
app.config['source']={'dataset_id':'raster','sha256':'a'*64,'width':360,'height':260}
app.current_doc_id='test';app.document_sha['test']='a'*64
image=Image.new('RGB',(360,260),'white')
d=ImageDraw.Draw(image)
d.line([(15,225),(110,80),(210,35),(340,23)],fill='black',width=3)
app.set_image(image)
app.notebook.select(app.curves_tab)
series=Series(name='synthetic');app.project.series=[series];app.active_series_id=series.id
app.refresh_curve_tree()
for label,x,y in [('bottom_left',0,259),('bottom_right',359,259),('top_left',0,0),('top_right',359,0)]:
    app.project.calibration.set_corner(label,x,y)
app.curve_monotonicity.set('x');app.point_order_source.set('x')
app.guide_points=[(15.,225.),(110.,80.),(210.,35.),(340.,23.)]
app._finish_guided_proposal(None,'offline')
assert len(app.assisted_proposal.segments)==3
assert int(float(app.assist_segment_spin.cget('to')))==3
before=[list(s) for s in app.assisted_proposal.segments]
# Stale Segment # 50 used to silently reject click despite usable X.
app.assist_segment.set(50)
app.mode.set('correction')
root.update_idletasks();root.update()
# Generate the real Tk click on an image coordinate far from the trace.
x,y=155.,240.
cx,cy=app.canvas.image_to_canvas(x,y)
assert 0<=cx<app.canvas.winfo_width() and 0<=cy<app.canvas.winfo_height(),(cx,cy)
app.canvas.event_generate('<ButtonPress-1>',x=round(cx),y=round(cy))
root.update()
assert len(app.guide_points)==5,app.assist_status.get()
assert abs(app.guide_points[2][0]-x)<1.1 and abs(app.guide_points[2][1]-y)<1.1,app.guide_points
assert len(app.assisted_proposal.segments)==4
assert app.assisted_proposal.segments[0]==before[0]
assert app.assisted_proposal.segments[-1]==before[-1]
assert app.assist_segment.get()==2
assert int(float(app.assist_segment_spin.cget('to')))==4
assert not series.points
assert 'inserted' in app.assist_status.get().lower(),app.assist_status.get()
# Rejection of a point outside monotonic guide span must be explicit.
n=len(app.guide_points)
app.canvas_press(355,200)
assert len(app.guide_points)==n
assert 'outside' in app.assist_status.get().lower()
# Without monotonicity, an invalid spinbox number recovers by a guide chord.
app.curve_monotonicity.set('none')
app.assist_segment.set(500)
app.canvas_press(170,235)
assert len(app.guide_points)==n+1,app.assist_status.get()
# Two-point proposal can be split even if the true trace would make a huge detour.
app.guide_points=[(16.,42.),(17.,42.)]
app._finish_guided_proposal(None,'offline')
assert len(app.assisted_proposal.segments[0])==2
app.curve_monotonicity.set('x');app.assist_segment.set(50)
app.canvas_press(16.5,240)
assert len(app.guide_points)==3,app.assist_status.get()
assert (16.5,240.) in app.assisted_proposal.points
root.destroy();print('PASS far correction real GUI click, monotonic auto-segment, stale spinbox, 2-vertex path')
