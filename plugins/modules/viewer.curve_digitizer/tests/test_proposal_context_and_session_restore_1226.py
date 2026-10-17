# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression: editable proposal points + Session A -> B -> A raster restoration."""
import copy,hashlib,json,sys,tempfile,tkinter as tk
from pathlib import Path
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
import gxtxt_curve_digitizer as gui
from digitizer_model import Series

def records(*rows):
    return '\n'.join('\t'.join([kind]+[gui.b64e(str(v)) for v in vals]) for kind,vals in rows)
class Host:
    def __init__(self, path,sha):
        self.session='A';self.count=0;self.responses={};self.cfgs={};self.image_path=path;self.sha=sha
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'session']) for k,v in gui.CORE_PREFS.items()))
        if cmd=='SOURCE':return records(('PATH',[str(self.image_path)]),('SHA256',[self.sha]),('METADATA',['image.width_px','240']),('METADATA',['image.height_px','140']))
        if cmd=='IMAGE_TOOL':return ''
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'f'*64
        raise AssertionError((cmd,args))
    def begin(self,cmd,*args):
        self.count+=1;rid=str(self.count)
        if cmd=='SESSION_TOKEN':result=records(('SESSION',[self.session]))
        elif cmd=='BOOTSTRAP':
            result=records(('SESSION',[self.session]))
            if self.session in self.cfgs:
                result+='\n'+records(('DOCUMENT',[f'doc-{self.session}',json.dumps(self.cfgs[self.session]),'now','b'*64]))
            # IMPORTANT: no DATASET records. This reproduces the actual race:
            # documents can arrive before the async Dataset catalog.
        elif cmd=='CATALOG':
            result=records(('STATE',[self.session,'catalog-'+self.session,'3','']),
              ('NAMESPACE',['test']),('IMAGE',['test.raster','test','image.raster','png','image/png',self.sha]))
        else:raise AssertionError((cmd,args))
        self.responses[rid]=result;return rid
    def poll_response(self,rid):return self.responses.pop(rid)

with tempfile.TemporaryDirectory() as t:
    f=Path(t)/'sample.png';img=Image.new('RGB',(240,140),'white')
    ImageDraw.Draw(img).line([(8,105),(75,40),(155,76),(230,15)],fill='black',width=3)
    img.save(f);sha=hashlib.sha256(f.read_bytes()).hexdigest()
    root=tk.Tk();root.geometry('1360x830');host=Host(f,sha)
    app=gui.CurveDigitizerApp(root,host,bootstrap_payload=records(('SESSION',['A'])))
    cfg=app.new_configuration('restorable')
    cfg['source']={'dataset_id':'test.raster','sha256':sha,'width':240,'height':140}
    host.cfgs['A']=copy.deepcopy(cfg)
    host.cfgs['B']=copy.deepcopy(cfg)
    # Full Session rebootstrap; DOC is available first, catalog only afterward.
    for new_session in ('B','A'):
        host.session=new_session
        app._scheduled_session_check();app._poll_session_probe();app._poll_session_bootstrap()
        assert app.current_doc_id=='doc-'+new_session
        assert app.image is None, 'Initial catalog has not arrived yet'
        app.check_dataset_catalog(force=True);app._poll_catalog_reply()
        root.update_idletasks();root.update()
        assert app.image is not None, app.source_diag.get()
        assert app.image.getpixel((0,0))==(255,255,255)
        assert app.canvas.original_image is not None
        assert app.canvas.image_item is not None, 'Missing raster Tk item after reopening a Session'
        assert app.canvas.find_withtag('base_image'), 'Raster item absent from canvas'
        assert app.canvas.itemcget(app.canvas.image_item,'state')!='hidden'
    # Source image and temporary proposal are distinct from Session state.
    app.notebook.select(app.curves_tab)
    series=Series(name='curve');app.project.series=[series];app.active_series_id=series.id
    app.guide_points=[(8.,105.),(75.,40.),(155.,76.),(230.,15.)]
    app._finish_guided_proposal(None,'offline')
    assert app.assisted_proposal and not series.points
    old=copy.deepcopy(app.assisted_proposal)
    app.curve_monotonicity.set('x')
    app.add_correction_point(115,122)
    assert len(app.guide_points)==5,app.assist_status.get()
    assert app._proposal_hit(115,122)==('guide',2)
    # Delete the just-added correction: the original proposal must be EXACT,
    # not an approximate re-fit. This is crucial for cancelling mistakes.
    app.mode.set('delete');app.canvas_press(115,122)
    assert len(app.guide_points)==4,app.assist_status.get()
    assert app.assisted_proposal.segments==old.segments
    assert not series.points
    # Move an existing guide by context action, then undo.
    app._prepare_proposal_move(('guide',1))
    app.canvas_press(90,30);app.canvas_release(90,30)
    assert app.guide_points[1]==(90,30),app.assist_status.get()
    assert app._proposal_history
    app.undo_proposal_edit()
    assert app.guide_points[1]==(75.,40.)
    # Delete a generated point (NOT a scientific point), then restore it.
    seg=copy.deepcopy(app.assisted_proposal.segments[0])
    assert len(seg)>2
    num=len(seg)
    app._delete_proposal_point(('generated',0,1))
    assert len(app.assisted_proposal.segments[0])==num-1
    app.undo_proposal_edit()
    assert app.assisted_proposal.segments[0]==seg
    assert not series.points
    # Right-click uses a context menu for proposal points, ordinary right drag
    # must keep working as a pan gesture on empty raster areas.
    root.update_idletasks();root.update()
    px,py=app.canvas.image_to_canvas(*app.guide_points[1])
    assert app.canvas._on_right_press
    # Avoid leaving a popup menu open during automated GUI testing:
    original=tk.Menu.tk_popup
    captured=[]
    tk.Menu.tk_popup=lambda self,x,y:captured.append((x,y,self,[self.entrycget(i,'label') for i in range(self.index('end')+1) if self.type(i)=='command']))
    try:
        app.canvas.event_generate('<ButtonPress-3>',x=round(px),y=round(py))
        root.update()
    finally:
        tk.Menu.tk_popup=original
    assert captured and any('Move point'==label for label in captured[0][3]),captured
    assert any('Delete point'==label for label in captured[0][3]),captured
    assert not app.canvas._right_pan_active
    captured[0][2].invoke(3)  # delete the interior guide using the real menu command
    assert len(app.guide_points)==3, app.assist_status.get()
    app.undo_proposal_edit()
    assert len(app.guide_points)==4
    # Empty-space right-click is NOT swallowed; right drag must still pan.
    ex,ey=app.canvas.image_to_canvas(230.,129.)
    app.canvas.event_generate('<ButtonPress-3>',x=round(ex),y=round(ey))
    assert app.canvas._right_pan_active
    app.canvas.event_generate('<ButtonRelease-3>',x=round(ex),y=round(ey))
    assert not app.canvas._right_pan_active
    root.destroy()
print('PASS proposal move/delete/undo, right-click, Session A->B->A restored raster')
