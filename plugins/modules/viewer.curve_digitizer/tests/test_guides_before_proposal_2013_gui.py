# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression: early guide Move/Delete, Undo and fail-closed stale acceptance."""
import sys
from pathlib import Path
from tkinter import messagebox
import tkinter as tk
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e
from digitizer_model import Series
def records(*rows):
    return "\n".join("\t".join([key]+[b64e(str(v)) for v in vals]) for key,vals in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        raise AssertionError((cmd,args))
    def begin(self,cmd,*args):
        assert cmd=="ASSIST_FIT"
        return 1
    def poll_response(self,request_id):
        assert request_id==1
        return "null"
root=tk.Tk()
root.geometry("1200x800+4000+4000")
try:
    app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(("SESSION",["test"])))
    app.config=app.new_configuration("preproposal regression")
    app.config["source"]={"dataset_id":"synthetic","sha256":"a"*64,"width":220,"height":120}
    app.current_doc_id="doc"
    # No real Workspace API writes in an isolated GUI test.
    app.persist=lambda:True
    app.persist_later=lambda:None
    img=Image.new("RGB",(220,120),"white")
    ImageDraw.Draw(img).line([(6,60),(215,60)],fill="black",width=3)
    app.set_image(img)
    app.notebook.select(app.curves_tab)
    s=Series(name="reference")
    app.project.series=[s]
    app.active_series_id=s.id
    app.refresh_curve_tree()
    for key,x,y in [("bottom_left",0,119),("bottom_right",219,119),
                    ("top_left",0,0),("top_right",219,0)]:
        app.project.calibration.set_corner(key,x,y)
    root.update()
    app.mode.set("guide")
    for pt in [(6,60),(110,60),(210,60)]:
        app.canvas_press(*pt)
    assert len(app.guide_points)==3
    assert app.assisted_proposal is None
    assert app._proposal_hit(110,60)==("guide",1)
    # Move mode must select and drag an unproposed guide.
    app.mode.set("edit")
    app.canvas_press(110,60);app.canvas_drag(125,61);app.canvas_release(125,61)
    assert len(app.guide_points)==3
    assert app.guide_points[1]==(125.0,61.0),app.guide_points
    assert len(app.active_series().points)==0
    app.undo()
    assert app.guide_points[1]==(110.0,60.0),app.guide_points
    app.redo()
    assert app.guide_points[1]==(125.0,61.0)
    # Delete mode must delete a guide before proposal; Undo restores.
    app.mode.set("delete")
    app.canvas_press(125,61)
    assert len(app.guide_points)==2
    app.undo()
    assert len(app.guide_points)==3
    assert app.guide_points[1]==(125.0,61.0)
    # A source-bound exclusion changes the current proposal's validity.
    app._finish_guided_proposal(None,"local test")
    assert app.assisted_proposal is not None
    assert not app._assist_proposal_stale
    app.exclusion_new_path()
    app.exclusion_press(15,38);app.exclusion_press(210,38)
    app.exclusion_new_path()
    app.exclusion_press(15,84);app.exclusion_press(210,84)
    app.exclusion_width.set(3);app.exclusion_config_changed()
    app.assist_smoothness.set("Strong");app.exclusion_config_changed()
    assert len(app.exclusion_active_paths())==2
    assert app._assist_proposal_stale
    assert "Propose" in app.assist_status.get()
    app.accept_guided_trace()
    assert len(app.active_series().points)==0
    assert "Propose" in app.assist_status.get()
    # A regenerated candidate resets the stale flag, but acceptance still
    # requires an explicit operator confirmation.
    app.propose_guided_trace()
    assert app.assist_baseline_request==1
    # Accept cannot commit an old proposal while the numeric fit is pending.
    app.accept_guided_trace()
    assert len(app.active_series().points)==0
    assert "still being generated" in app.assist_status.get()
    app._poll_assisted_fit()
    assert app.assist_baseline_request is None
    assert not app._assist_proposal_stale
    assert app.assisted_proposal
    app.assist_output_points.set(64)
    old=messagebox.askyesno
    messagebox.askyesno=lambda *a,**kw:True
    try:app.accept_guided_trace()
    finally:messagebox.askyesno=old
    assert len(app.active_series().points)==64, (len(app.active_series().points),app.assist_status.get())
    print("PASS: preproposal Move/Delete/Undo/Redo; two exclusions; stale guard; async Propose; 64 accepted")
finally:
    root.destroy()
