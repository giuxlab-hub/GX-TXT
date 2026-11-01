# SPDX-License-Identifier: GPL-3.0-or-later
"""F2 interactive Tk smoke: optional Y2 settings, calibration, curve dialog and safety."""
import csv
import json
import math
import sys
import tkinter as tk
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
P=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(P/"python"))
import gxtxt_curve_digitizer as gui
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import AxisConfig, DigitizedPoint, Project, Series, CalibrationError

def records(*rows):
    return "\n".join("\t".join([a]+[b64e(str(v)) for v in fields]) for a,fields in rows)
class RPC:
    def attach(self, root): pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return records(*(("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL": return ""
        raise AssertionError(cmd)
def walk(parent):
    for child in parent.winfo_children():
        yield child
        yield from walk(child)
def cb_by_label(window,label):
    items=[w for w in walk(window)
           if w.winfo_class()=="TCheckbutton" and w.cget("text")==label]
    assert len(items)==1, (label,items)
    return items[0]
def button(window,label):
    items=[w for w in walk(window)
           if w.winfo_class()=="TButton" and w.cget("text")==label]
    assert len(items)==1,(label,items)
    return items[0]

root=tk.Tk();root.geometry("1450x870")
rpc=RPC()
app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(("SESSION",["mock-only"])))
app.config=app.new_configuration("Y2 fixture test")
app.project=Project()
manifest=json.loads((ROOT/"test_fixtures/y2/test_01_logx_y1lin_y2lin_manifest.json").read_text())
for t,k in (("BL","bottom_left"),("BR","bottom_right"),("TL","top_left"),("TR","top_right")):
    app.project.calibration.set_corner(k,*manifest["plot_corners_px"][t])
app.project.x_axis=AxisConfig.from_dict(manifest["axes"]["x"])
app.project.y_axis=AxisConfig.from_dict(manifest["axes"]["y1"])
app.image=Image.open(ROOT/"test_fixtures/y2/test_01_logx_y1lin_y2lin.png").convert("RGB")
app.gray_image=app.image.convert("L")
app.canvas.set_image(app.image)
for key,axis in (("x",app.project.x_axis),("y",app.project.y_axis)):
    for attr,val in (("name",axis.name),("unit",axis.unit),("min",axis.minimum),
                     ("max",axis.maximum),("scale",axis.scale)):
        getattr(app,f"{key}_{attr}").set(str(val))
app.refresh_measurements()
root.update()
assert not app.project.y2_axis
assert app.calibration_y_heading.cget("text")=="Y axis"
assert all(not w.winfo_manager() for w in app.y2_calibration_widgets)
assert app.curve_tree.cget("columns") == "('label', 'family', 'points')" or tuple(root.tk.splitlist(app.curve_tree.cget("columns")))==("label","family","points")
commit_count=[0]
app._commit_pref_values=lambda *a: commit_count.__setitem__(0,commit_count[0]+1)
app.persist=lambda: True # F2 test has deliberately no live Session, no writes
app.open_viewer_settings();root.update()
w=app.settings_dialog
cb=cb_by_label(w,"Enable secondary Y axis")
cb.invoke()
button(w,"Apply").invoke()
root.update()
assert app.project.y2_axis is not None
assert app.project.y2_axis.name=="Y2"
assert app.calibration_y_heading.cget("text")=="Y1 axis"
app.notebook.select(app.calibration_tab);root.update()
assert all(x.winfo_ismapped() for x in app.y2_calibration_widgets)
assert tuple(root.tk.splitlist(app.curve_tree.cget("columns")))==("label","axis","family","points")
# Apply real calibrated bounds independently.
for key,value in (("name","Phase"),("unit","deg"),("role","measured"),
                  ("min","-100"),("max","10"),("scale","linear")):
    getattr(app,"y2_"+key).set(value)
assert app.commit_axes(True)
assert app.project.y2_axis.maximum == 10
# Switch the first curve to Y2 with the real optional SeriesDialog.
series1=Series(id="curve_gain",name="Gain",y_axis_id="y1",points=[
    DigitizedPoint(id="gain_pt",pixel_x=550,pixel_y=390)])
series2=Series(id="curve_phase",name="Phase",y_axis_id="y1",points=[
    DigitizedPoint(id="phase_pt",pixel_x=550,pixel_y=390)])
app.project.series=[series1,series2]
app.project.recalculate_all_points()
app.active_series_id=series2.id
app.refresh_curve_tree()
before=series2.points[0].calibrated_y
dialog=gui.SeriesDialog(root,series2,enable_y2=True)
root.update()
assert dialog.axis_var.get()=="Y1"
dialog.axis_var.set("Y2")
dialog.accept()
assert dialog.result["y_axis_id"]=="y2"
# Exercise actual edit_series using an event-driven dialog acceptance.
def drive_dialog():
    dialogs=[v for v in root.winfo_children() if isinstance(v,gui.SeriesDialog)]
    assert len(dialogs)==1, dialogs
    dlg=dialogs[0]
    dlg.axis_var.set("Y2")
    dlg.accept()
root.after(100,drive_dialog)
app.edit_series()
assert series2.y_axis_id=="y2"
assert series2.points[0].calibrated_y != before
assert math.isclose(series2.points[0].calibrated_y,
    app.project.pixel_to_calibrated(550,390,"y2")[1],rel_tol=1e-12)
assert app.curve_tree.item(series2.id,"values")[1]=="Y2"
# Disabling without explicit reassignment is refused before prefs mutate.
app.open_viewer_settings();root.update()
w=app.settings_dialog
cb=cb_by_label(w,"Enable secondary Y axis")
if cb.instate(["selected"]): cb.invoke()
errors=[]
old=gui.messagebox.showerror
gui.messagebox.showerror=lambda *args,**kwargs:errors.append(args)
committed=commit_count[0]
try: result=button(w,"Apply").invoke()
finally: gui.messagebox.showerror=old
assert errors and "Reassign" in errors[0][1],errors
assert commit_count[0]==committed,commit_count
assert app.project.y2_axis is not None
# Move to Y1 explicitly, and then disable.
series2.y_axis_id="y1";app.project.recalculate_all_points()
button(w,"Apply").invoke()
root.update()
assert app.project.y2_axis is None
assert app.calibration_y_heading.cget("text")=="Y axis"
assert all(not wid.winfo_manager() for wid in app.y2_calibration_widgets)
assert tuple(root.tk.splitlist(app.curve_tree.cget("columns")))==("label","family","points")
cfg=app.serialize_configuration()
assert "y2" not in cfg["axes"] and "axis_model_version" not in cfg
assert all("y_axis_id" not in s for s in cfg["curves"])
assert all("y2" not in m["axes"] for m in cfg["calibration_measurements"]["items"])
print("PASS F2 GUI: enable -> calibrate -> per-curve Y2 -> block disable -> Y1 reassign -> legacy OFF")
w.destroy();root.destroy()
