# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression: 100 means 100 points for an accepted trace or segment;
CORE Session replacement clears stale scientific state without saving to it."""
from __future__ import annotations
import sys
import tkinter as tk
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'python'))
import gxtxt_curve_digitizer as gui
from digitizer_model import Series
from assisted_tracing import TraceProposal


def records(*rows):
    return '\n'.join('\t'.join([kind]+[gui.b64e(str(x)) for x in vals]) for kind,vals in rows)

class Host:
    def __init__(self):
        self.session='A';self.count=0;self.payloads={};self.writes=[];self.new_document=None
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'session']) for k,v in gui.CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':
            self.writes.append((self.session,cmd,args))
            return args[0]+'\t'+'a'*64
        if cmd=='IMAGE_TOOL':return ''
        raise AssertionError((cmd,args))
    def begin(self,cmd,*args):
        self.count+=1;rid=str(self.count)
        if cmd=='SESSION_TOKEN': payload=records(('SESSION',[self.session]))
        elif cmd=='BOOTSTRAP':
            payload=records(('SESSION',[self.session]))
            if self.new_document is not None:
                payload+='\n'+records(('DOCUMENT',['doc-new',gui.json.dumps(self.new_document),'now','b'*64]))
        else: raise AssertionError(cmd)
        self.payloads[rid]=payload;return rid
    def poll_response(self,rid):return self.payloads.pop(rid)

root=tk.Tk();root.geometry('1380x830');host=Host()
app=gui.CurveDigitizerApp(root,host,bootstrap_payload=records(('SESSION',['A'])))
app.current_doc_id='doc-old';app.config=app.new_configuration('Old')
app.documents['doc-old']=app.config;app.document_sha['doc-old']='a'*64
app.notebook.select(app.curves_tab)
app.project.series=[Series(name='Target')];app.active_series_id=app.project.series[0].id
app.image=Image.new('RGB',(320,200),'white')
app.set_image(app.image)
app.guide_points=[(10,110),(70,60),(130,90),(200,35),(300,15)]
app._finish_guided_proposal(None,'offline')
assert app.assisted_proposal is not None,len(app.assisted_proposal.segments)
app.assist_output_points.set('100')
old=gui.messagebox.askyesno;gui.messagebox.askyesno=lambda *args,**kwargs:True
try:
    # Accept only one interval: this was about 8 points when the whole proposal
    # used a 100-point budget. It must now add exactly 100 points.
    app.assist_segment.set(1)
    app.accept_guided_segment()
    assert len(app.project.series[0].points)==100, (len(app.project.series[0].points),app.assist_status.get())
    # A second contiguous interval must add 100 NEW points, not ~8, while
    # avoiding the guide junction already present in the first acceptance.
    app.assist_segment.set(2)
    app.accept_guided_segment()
    assert len(app.project.series[0].points)==200, (len(app.project.series[0].points),app.assist_status.get())
    app.assist_output_points.set('150')
    app.resample_accepted_trace()
    assert len(app.project.series[0].points)==150, app.assist_status.get()

finally:gui.messagebox.askyesno=old

app.undo_stack.append({'dummy':'prior-session'})
app.auto_catalog_watch.set(False) # token polling is independent of catalog auto-refresh
app.persist_later()
app.guide_points.append((12,120))
prior=host.writes[:]
host.session='B'
host.new_document=app.new_configuration('New session configuration')
app._scheduled_session_check()
app._poll_session_probe()
assert app.session_refreshing
app._poll_session_bootstrap()
assert app.session_token=='B'
assert not app.session_refreshing
assert not app.catalog_session_invalid
assert app.current_doc_id=='doc-new'
assert len(app.project.series)==0
assert not app.guide_points and app.assisted_proposal is None
assert app.undo_stack==[]
assert getattr(app, '_persist_after', None) is None
assert not app.assist_accepted_segments
assert app.assist_output_points.get()=='0'
assert host.writes==prior,'Rebootstrap must not save old-Session scientific data'
# Test empty new Session also clears the source and configuration selector.
host.session='C';host.new_document=None
app._scheduled_session_check();app._poll_session_probe();app._poll_session_bootstrap()
assert app.session_token=='C' and not app.current_doc_id
assert not app.documents and not app.guide_points
assert app.canvas.original_image is None and app.source_var.get()==''
root.destroy()
print('PASS exact density partial acceptance, resampling, new-session and empty-session rebinding')
