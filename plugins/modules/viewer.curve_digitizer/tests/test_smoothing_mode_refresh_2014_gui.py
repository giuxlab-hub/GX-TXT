# SPDX-License-Identifier: GPL-3.0-or-later
"""Real Tk regression: mode selection re-proposes, status exposes applied mode."""
from pathlib import Path
import sys,tkinter as tk,math
from tkinter import messagebox
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,PLUGIN_VERSION
from digitizer_model import Series
def records(*rows):
 return "\n".join("\t".join([key]+[b64e(str(x)) for x in vals]) for key,vals in rows)
class RPC:
 def __init__(self):self.n=0
 def attach(self,root):pass
 def call(self,cmd,*args):
  if cmd=="CONFIG_READ":return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
  if cmd=="IMAGE_TOOL":return ""
  raise AssertionError((cmd,args))
 def begin(self,cmd,*args):
  assert cmd=="ASSIST_FIT"
  self.n+=1
  return self.n
 def poll_response(self,request_id):
  assert 1<=request_id<=self.n
  return "null"
rpc=RPC()
root=tk.Tk()
root.geometry("1220x800+4000+4000")
try:
 app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(("SESSION",["test"])))
 assert PLUGIN_VERSION=="2.0.25"
 app.config=app.new_configuration("smoothing regression")
 app.config["source"]={"dataset_id":"synthetic","sha256":"b"*64,"width":300,"height":170}
 app.current_doc_id="doc"
 def save():
  app.config["tracing_constraints"]=app.exclusion_record()
  return True
 app.persist=save
 app.persist_later=lambda:None
 im=Image.new("RGB",(300,170),"white")
 draw=ImageDraw.Draw(im)
 for x in range(12,289):
  y=85+round(4*math.sin(x/7)+6*math.sin(x/19))
  draw.point((x,y),fill=(20,55,230))
  draw.point((x,85),fill=(32,120,208))
 app.set_image(im)
 app.notebook.select(app.curves_tab)
 series=Series(name="test curve")
 app.project.series=[series];app.active_series_id=series.id;app.refresh_curve_tree()
 for key,x,y in [("bottom_left",0,169),("bottom_right",299,169),("top_left",0,0),("top_right",299,0)]:
  app.project.calibration.set_corner(key,x,y)
 app.guide_points=[(12.,85.),(150.,85.),(288.,85.)]
 app.assist_radius.set(8)
 app.assist_step.set(2)
 root.update()
 # First explicit Propose at Off
 app.propose_guided_trace()
 assert rpc.n==1 and app.assist_baseline_request==1
 app._poll_assisted_fit()
 first=list(app.assisted_proposal.points)
 assert "Proposal [Off]" in app.assist_status.get(),app.assist_status.get()
 # Changing prior must automatically start a NEW proposal; no acceptance yet
 app.assist_smoothness.set("Strong")
 app.assist_smoothness_selected()
 assert rpc.n==2 and app.assist_baseline_request==2
 assert app._assist_proposal_stale
 assert "Strong" in app.assist_status.get()
 app.accept_guided_trace()
 assert not app.active_series().points
 assert "still being generated" in app.assist_status.get()
 app._poll_assisted_fit()
 second=list(app.assisted_proposal.points)
 assert not app._assist_proposal_stale
 assert "Proposal [Strong]" in app.assist_status.get(),app.assist_status.get()
 assert "Compared with the previous proposal:" in app.assist_status.get(),app.assist_status.get()
 changed=sum(math.dist(a,b)>0.1 for a,b in zip(first,second))
 # Different priors can legitimately choose identical geometry on a unique
 # well-identified raster. Verify a fresh proposal and accurate status instead.
 assert f"{changed}/{len(second)} positions changed" in app.assist_status.get()
 assert len(app.active_series().points)==0
 # Gentle also triggers its own numeric search.
 app.assist_smoothness.set("Gentle")
 app.assist_smoothness_selected()
 assert rpc.n==3 and app.assist_baseline_request==3
 app._poll_assisted_fit()
 assert "Proposal [Gentle]" in app.assist_status.get()
 # Once accepted, mode change must preserve the segment bookkeeping.
 old=messagebox.askyesno
 messagebox.askyesno=lambda *a,**k:True
 try:
  app.assist_output_points.set(64)
  app.accept_guided_segment()
 finally:
  messagebox.askyesno=old
 assert app.assist_accepted_segments
 total=len(app.active_series().points)
 assert total>0
 app.assist_smoothness.set("Off")
 app.assist_smoothness_selected()
 assert rpc.n==3,"Automatic refresh after partial acceptance would reset point provenance"
 assert app.assist_accepted_segments
 assert len(app.active_series().points)==total
 assert "Accepted segments exist" in app.assist_status.get()
 print("PASS: Off->Strong->Gentle refreshed via normal API, distinct search, descriptive status, accepted-segment guard")
finally:
 root.destroy()
