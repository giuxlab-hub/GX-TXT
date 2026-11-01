# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk regression: vertically stacked calibration/inline-verification layout."""
from __future__ import annotations

import json
import os
import sys
import tkinter as tk
from pathlib import Path
from PIL import Image, ImageGrab

MODULE=Path(__file__).resolve().parents[1]
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(MODULE/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,PLUGIN_VERSION
from digitizer_model import Project,AxisConfig


def records(*rows):
    return "\n".join("\t".join([name]+[b64e(str(v)) for v in values])
                     for name,values in rows)


class RPC:
    def attach(self, root):
        pass

    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return records(*(("SETTING",(k,v,"user")) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":
            return ""
        raise AssertionError("No actual Session/CORE operation is allowed")


root=tk.Tk()
root.geometry("1450x860+45+40")
assert PLUGIN_VERSION=="2.0.25",PLUGIN_VERSION
app=CurveDigitizerApp(root,RPC(),
    bootstrap_payload=records(("SESSION",("verification_mock",))))
try:
    base=ROOT/"test_fixtures/y2"
    m=json.loads((base/"test_03_lin_x_y1lin_y2log_manifest.json").read_text(encoding="utf-8"))
    project=Project()
    project.x_axis=AxisConfig.from_dict(m["axes"]["x"])
    project.y_axis=AxisConfig.from_dict(m["axes"]["y1"])
    project.y2_axis=AxisConfig.from_dict(m["axes"]["y2"])
    for tag,key in (("BL","bottom_left"),("BR","bottom_right"),
                    ("TL","top_left"),("TR","top_right")):
        project.calibration.set_corner(key,*m["plot_corners_px"][tag])
    app.project=project
    app.config=app.new_configuration("Inline verification")
    app.require_working_source=lambda:True
    app.persist=lambda:True
    app.image=Image.open(base/m["image_file"]).convert("RGB")
    app.gray_image=app.image.convert("L")
    app.canvas.set_image(app.image)
    for prefix,axis in (("x",project.x_axis),("y",project.y_axis)):
        for key,value in (("name",axis.name),("unit",axis.unit),
                          ("min",axis.minimum),("max",axis.maximum),
                          ("scale",axis.scale)):
            getattr(app,f"{prefix}_{key}").set(str(value))
    app._secondary_y_controls_from_model()
    app._refresh_secondary_axis_widgets()
    app.notebook.select(app.calibration_tab)
    app.refresh_measurements()
    app.update_cal_status()
    app.redraw()
    root.update()

    verification=app.verification_expansion.master
    calibration=verification.master
    assert int(verification.grid_info()["row"])==1
    top=calibration.grid_slaves(row=0,column=0)
    assert len(top)==1
    assert top[0] is not verification
    buttons=[child for child in top[0].winfo_children()[0].winfo_children()
             if child.winfo_class()=="TButton"]
    texts=[b.cget("text") for b in buttons]
    assert set(texts)=={"Set BL","Set BR","Set TL","Set TR","Clear corners"},texts
    assert app.verification_expansion.winfo_manager()==""
    assert app.verification_dialog is None
    initial_bbox=app.calibration_scroll_canvas.bbox("all")
    assert initial_bbox is not None
    if os.environ.get("GX_INLINE_COLLAPSED_SCREENSHOT"):
        screenshot=Path(os.environ["GX_INLINE_COLLAPSED_SCREENSHOT"])
        screenshot.parent.mkdir(parents=True,exist_ok=True)
        ImageGrab.grab().save(screenshot)
        print("COLLAPSED_SCREENSHOT",screenshot,flush=True)
    app.verification_toggle.invoke()
    root.update()
    assert app.verification_dialog is not None
    assert app.verification_dialog.window.winfo_toplevel() is root
    assert app.verification_expansion.winfo_manager()=="grid"
    assert app.verification_toggle.cget("text")=="Close verification"
    assert set(app.verification_dialog.controls)=={"x","y1","y2"}
    assert not any(isinstance(w,tk.Toplevel) for w in root.winfo_children())
    expanded_bbox=app.calibration_scroll_canvas.bbox("all")
    assert expanded_bbox is not None and expanded_bbox[3]>initial_bbox[3]+180
    app._verification_scroll_into_view()
    root.update()
    assert app.verification_toggle.winfo_ismapped()
    # At least the verification heading remains inside the viewport.
    top_screen=app.calibration_scroll_canvas.winfo_rooty()
    assert app.verification_toggle.winfo_rooty() >= top_screen-5
    assert app.verification_toggle.winfo_rooty() <= top_screen+app.calibration_scroll_canvas.winfo_height()+5
    mid_x=(m["plot_corners_px"]["BL"][0]+m["plot_corners_px"]["BR"][0])/2
    mid_y=(m["plot_corners_px"]["BL"][1]+m["plot_corners_px"]["TL"][1])/2
    app.canvas_press(mid_x,mid_y)
    app.exp_x.set("50")
    app.exp_y.set("2.6")
    app.exp_y2.set("1e0")
    root.update()
    assert app.verification_dialog.controls["y2"]["calculated"].get().startswith("1 ")
    assert app.verification_dialog.controls["y2"]["comparison"].get().startswith("0 decades")
    assert app.verification_dialog.controls["y1"]["comparison"].get()=="0 %"
    assert "Calculated Y2" in app.verify_result.get()
    app.verification_toggle.invoke()
    root.update()
    assert app.verification_dialog is None
    assert app.verification_expansion.winfo_manager()==""
    assert app.verification_toggle.cget("text")=="Verify calibration..."
    assert app.mode.get()=="add" and app.verify_point is None
    assert not any(isinstance(w,tk.Toplevel) for w in root.winfo_children())
    app.start_verification()
    app.notebook.select(app.curves_tab)
    root.update()
    assert app.verification_dialog is None
    print("PASS F4 inline layout: top corners, lower expanding verification, scrolling, Y2 logarithmic, no popup",flush=True)
finally:
    root.destroy()
