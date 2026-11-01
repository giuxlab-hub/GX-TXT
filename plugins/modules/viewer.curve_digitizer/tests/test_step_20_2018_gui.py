# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk GUI: 20 px Step widget, real proposal and 100 accepted output points."""
from pathlib import Path
import sys,tkinter as tk
from tkinter import messagebox
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,PLUGIN_VERSION
from digitizer_model import Series
def records(*items):
    return "\n".join("\t".join([key]+[b64e(str(v)) for v in vals]) for key,vals in items)
class RPC:
    def __init__(self):self.counter=0
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        raise AssertionError((cmd,args))
    def begin(self,cmd,*args):
        assert cmd=="ASSIST_FIT"
        self.counter+=1
        return self.counter
    def poll_response(self,request):
        assert 1<=request<=self.counter
        return "null"
rpc=RPC()
root=tk.Tk()
root.geometry("1210x800+4250+4250")
try:
    app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(("SESSION",["test"])))
    assert PLUGIN_VERSION=="2.0.25"
    assert float(app.assist_step_spin.cget("to"))==20.
    assert float(app.assist_step_spin.cget("from"))==0.5
    cfg=app.new_configuration("step20 GUI")
    cfg["source"]={"dataset_id":"img","sha256":"a"*64,"width":300,"height":200}
    app.config=cfg
    app.current_doc_id="test-doc"
    app.persist=lambda:True
    app.persist_later=lambda:None
    im=Image.new("RGB",(300,200),"white")
    draw=ImageDraw.Draw(im)
    draw.line((20,90,280,90),fill=(55,20,210),width=1)
    app.set_image(im)
    app.notebook.select(app.curves_tab)
    series=Series(name="study")
    app.project.series=[series];app.active_series_id=series.id
    app.refresh_curve_tree()
    for label,x,y in (("bottom_left",0,199),("bottom_right",299,199),("top_left",0,0),("top_right",299,0)):
        app.project.calibration.set_corner(label,x,y)
    app.guide_points=[(20.,90.),(150.,90.),(280.,90.)]
    app.assist_step.set(20.)
    app.assist_smoothness.set("Strong")
    root.update()
    # Invalid Step typed while the optional Numeric fit is pending must
    # discard that candidate, not crash the Tk event loop.
    app.propose_guided_trace()
    assert rpc.counter==1 and app.assist_baseline_request==1
    app.assist_step.set("invalid")
    app._poll_assisted_fit()
    assert "discarded" in app.assist_status.get()
    app.assist_step.set(20.)
    app.propose_guided_trace()
    assert rpc.counter==2 and app.assist_baseline_request==2
    app._poll_assisted_fit()
    assert "Proposal [Strong]" in app.assist_status.get()
    assert "Step 20 source px" in app.assist_status.get()
    assert len(app.assisted_proposal.points)==15
    app.assist_output_points.set("100")
    # A Step edit after Propose must never accept an earlier preview.
    app.assist_step.set(10.)
    app.accept_guided_trace()
    assert "Step changed" in app.assist_status.get()
    assert not app.active_series().points
    app.assist_step.set(20.)
    original=messagebox.askyesno
    messagebox.askyesno=lambda *a,**kw:True
    try:app.accept_guided_trace()
    finally:messagebox.askyesno=original
    assert len(app.active_series().points)==100
    assert all(p.origin=="assisted" for p in app.active_series().points)
    # Invalid range is stopped BEFORE a Numeric job is dispatched.
    app.assist_step.set(21.)
    prev=rpc.counter
    app.propose_guided_trace()
    assert rpc.counter==prev and "Step must" in app.assist_status.get()
    app.assist_step.set(0.4)
    app.propose_guided_trace()
    assert rpc.counter==prev and "Step must" in app.assist_status.get()
    print("PASS real Tk Step spinbox=20, proposal=15 points, Accept=100, stale/invalid safeguards")
finally:
    for job in root.tk.call("after","info"):
        try:root.after_cancel(job)
        except tk.TclError:pass
    root.destroy()
