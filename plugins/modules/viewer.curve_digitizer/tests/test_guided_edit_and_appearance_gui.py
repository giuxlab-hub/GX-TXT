# SPDX-License-Identifier: GPL-3.0-or-later
"""Xvfb integration: local proposal edits and per-configuration appearance."""
import sys, pathlib,tkinter as tk
from PIL import Image,ImageDraw
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series

def records(*rows):
    return '\n'.join('\t'.join([key]+[b64e(str(x)) for x in values]) for key,values in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[key,v,'user']) for key,v in CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
        if cmd=='IMAGE_TOOL':return ''
        raise AssertionError((cmd,args))
root=tk.Tk();root.geometry('1150x830')
app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('one');app.config['source']={'dataset_id':'raster','sha256':'a'*64,'width':260,'height':160}
app.current_doc_id='one';app.document_sha['one']='a'*64
img=Image.new('RGB',(260,160),'white');d=ImageDraw.Draw(img)
for y in range(20,160,30):d.line((0,y,259,y),fill='gray',width=1)
d.line([(5,120),(70,62),(145,55),(250,30)],fill='black',width=3)
app.set_image(img);app.notebook.select(app.curves_tab)
series=Series(name='curve');app.project.series=[series];app.active_series_id=series.id;app.refresh_curve_tree()
for label,x,y in [('bottom_left',0,159),('bottom_right',259,159),('top_left',0,0),('top_right',259,0)]:
    app.project.calibration.set_corner(label,x,y)
app.guide_points=[(5,120),(70,62),(145,55),(250,30)]
app._finish_guided_proposal(None,'offline')
assert app.assisted_proposal and len(app.assisted_proposal.segments)==3
before=[list(z) for z in app.assisted_proposal.segments]
app.mode.set('proposal_edit');app._begin_proposal_edit(100,44)
assert app._assist_drag and app._assist_drag[0]=='insert'
app._finish_proposal_edit(98,48)
assert len(app.guide_points)==5
assert len(app.assisted_proposal.segments)==4
assert app.assisted_proposal.segments[0]==before[0]
assert app.project.series[0].points==[]
# Configuration A stores its own presentation, not CORE-wide mutable values.
app.opacity_var.set(35);app.canvas_bg_var.set('#8899AA');app._commit_canvas_appearance()
config_a=app.serialize_configuration()
assert config_a['display']['image_opacity']==35
assert config_a['display']['canvas_background']=='#8899aa'
config_b=app.new_configuration('two')
app.config=config_b;app.project=app.config_to_project(config_b)
app.current_doc_id='two';app.document_sha['two']='a'*64
app.sync_controls_from_config(reload_source=False)
assert app.opacity_var.get()==100
assert app.canvas_bg_var.get()=='#303030'
# Opening A again restores the per-config settings, even when CORE defaults differ.
app.config=config_a;app.project=app.config_to_project(config_a)
app.current_doc_id='one';app.sync_controls_from_config(reload_source=False)
assert app.opacity_var.get()==35
assert app.canvas_bg_var.get().lower()=='#8899aa'
# Processed selection must reject missing or stale previews.
app.assist_source.set('processed')
try:app._trace_input_image()
except ValueError:pass
else:raise AssertionError('missing processed preview should be rejected')
app.assist_source.set('auto')
assert app._trace_input_image() is app.image
root.destroy();print('PASS guide editing and independent per-configuration canvas appearance')
