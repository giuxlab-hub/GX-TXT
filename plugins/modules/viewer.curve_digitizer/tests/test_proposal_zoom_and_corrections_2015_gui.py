# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk: edit selection in source pixels independent of zoom/pan and safe corrections."""
import sys,math,copy
from pathlib import Path
from types import SimpleNamespace
from PIL import Image,ImageDraw
import tkinter as tk
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,PLUGIN_VERSION
from digitizer_model import Series
def records(*rows):
 return "\n".join("\t".join([key]+[b64e(str(v)) for v in values]) for key,values in rows)
class RPC:
 def attach(self,root):pass
 def call(self,cmd,*args):
  if cmd=="CONFIG_READ":return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
  if cmd=="IMAGE_TOOL":return ""
  raise AssertionError((cmd,args))
root=tk.Tk()
root.geometry("1300x850+4200+4200")
try:
 app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(("SESSION",["test"])))
 assert PLUGIN_VERSION=="2.0.25"
 app.config=app.new_configuration("source pixel regression")
 app.config["source"]={"dataset_id":"img","sha256":"a"*64,"width":320,"height":200}
 app.current_doc_id="doc"
 def fakepersist():
  app.config["tracing_constraints"]=app.exclusion_record()
  return True
 app.persist=fakepersist
 app.persist_later=lambda:None
 image=Image.new("RGB",(320,200),"white")
 pen=ImageDraw.Draw(image)
 for x in range(15,305):
  y=100+round(3*math.sin(x/14))
  pen.point((x,y),fill=(30,30,210))
 app.set_image(image)
 app.notebook.select(app.curves_tab)
 series=Series(name="test")
 app.project.series=[series];app.active_series_id=series.id;app.refresh_curve_tree()
 for name,x,y in [("bottom_left",0,199),("bottom_right",319,199),
                  ("top_left",0,0),("top_right",319,0)]:
  app.project.calibration.set_corner(name,x,y)
 app.curve_monotonicity.set("x");app.point_order_source.set("x")
 app.guide_points=[(15.,100.),(160.,100.),(304.,100.)]
 app.assist_radius.set(8);app.assist_step.set(2.)
 app._finish_guided_proposal(None,"test")
 assert len(app.assisted_proposal.segments)==2
 original=copy.deepcopy(app.assisted_proposal.segments)
 pt=original[0][len(original[0])//2]
 # ImageCanvas callback must deliver the same original-source position at
 # arbitrary view scales, even after a significant pan.
 root.update()
 for factor in (1.0,4.0,8.0):
  app.canvas.scale=factor
  app.canvas.offset_x=100-pt[0]*factor
  app.canvas.offset_y=200-pt[1]*factor
  assert app._proposal_hit(*pt)[0]=="generated",("no source hit",factor,pt)
  assert app._proposal_hit(pt[0],pt[1]+20) is None,("too-distant hit",factor)
  app.mode.set("proposal_edit")
  cx,cy=app.canvas.image_to_canvas(*pt)
  app.canvas.event_generate("<ButtonPress-1>",x=round(cx),y=round(cy))
  root.update()
  assert app._assist_drag is not None and app._assist_drag[0]=="insert",(factor,app.assist_status.get())
  # Move the generated vertex 2 original pixels, not 2 pixels of canvas.
  px,py=pt[0],pt[1]+2
  dx,dy=app.canvas.image_to_canvas(px,py)
  app.canvas.event_generate("<B1-Motion>",x=round(dx),y=round(dy))
  app.canvas.event_generate("<ButtonRelease-1>",x=round(dx),y=round(dy))
  root.update()
  assert len(app.guide_points)==4,(factor,app.assist_status.get())
  assert math.dist(app.guide_points[1],(px,py))<0.65,(factor,app.guide_points[1],(px,py))
  assert app.assisted_proposal.segments[-1]==original[-1],factor
  assert not app.project.series[0].points
  app.undo()
  assert app.guide_points==[(15.,100.),(160.,100.),(304.,100.)],app.guide_points
  assert app.assisted_proposal.segments==original,("undo",factor)
 # Far correction remains allowed and is assigned by CALIBRATED X.
 app.mode.set("correction")
 app.canvas.scale=8;app.canvas.offset_x=150-95*8;app.canvas.offset_y=240-130*8
 cx,cy=app.canvas.image_to_canvas(95,130)
 app.canvas.event_generate("<ButtonPress-1>",x=round(cx),y=round(cy))
 root.update()
 assert len(app.guide_points)==4,app.assist_status.get()
 assert app.guide_points[1]==(95.,130.),app.guide_points
 assert app.assisted_proposal.segments[-1]==original[-1]
 assert (95.,130.) in app.assisted_proposal.points
 app.undo()
 assert app.assisted_proposal.segments==original
 # Changing constraints marks old path stale; prevent mixed-constraint edit.
 app.exclusion_new_path()
 app.exclusion_press(20,50);app.exclusion_press(280,50)
 assert app._assist_proposal_stale
 prior=copy.deepcopy(app.assisted_proposal.segments)
 n=len(app.guide_points)
 app.mode.set("correction")
 app.add_correction_point(95,130)
 assert len(app.guide_points)==n and app.assisted_proposal.segments==prior
 assert "Propose" in app.assist_status.get()
 app.mode.set("proposal_edit");app._begin_proposal_edit(*pt)
 assert app._assist_drag is None
 assert app.assisted_proposal.segments==prior
 app._finish_guided_proposal(None,"fresh")
 assert not app._assist_proposal_stale
 app.mode.set("correction");app.add_correction_point(95,130)
 assert len(app.guide_points)==n+1 and (95.,130.) in app.assisted_proposal.points,app.assist_status.get()
 print("PASS: real Tk events at zoom 1x/4x/8x; 6 raster-pixel selection; source correct insertion; far calibration correction; stale guards; Undo")
finally:
 root.destroy()
