# SPDX-License-Identifier: GPL-3.0-or-later
"""Interactive Tk verification smoke using deterministic scientific fixture data."""
import csv
import json
import os
import sys
import tkinter as tk
from pathlib import Path

from PIL import Image, ImageGrab

WORKTREE = Path(__file__).resolve().parents[4]
MODULE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODULE / "python"))
from digitizer_model import Project, AxisConfig
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e, PLUGIN_VERSION


def records(*rows):
    return "\n".join("\t".join([name]+[b64e(str(v)) for v in values]) for name,values in rows)

class Rpc:
    def attach(self, root):
        pass
    def call(self, command, *args):
        if command=="CONFIG_READ":
            return records(*(("SETTING",(k,v,"user")) for k,v in CORE_PREFS.items()))
        if command=="IMAGE_TOOL":
            return ""
        raise AssertionError(command)

def sample(name, curve_id):
    base=WORKTREE/"test_fixtures/y2"
    manifest=json.loads((base/(name+"_manifest.json")).read_text(encoding="utf-8"))
    with (base/manifest["truth_file"]).open(newline="",encoding="utf-8") as handle:
        rows=[r for r in csv.DictReader(handle) if r["curve_id"]==curve_id]
    return base,manifest,rows[120]

def prepare(app, base, manifest):
    p=Project()
    p.x_axis=AxisConfig.from_dict(manifest["axes"]["x"])
    p.y_axis=AxisConfig.from_dict(manifest["axes"]["y1"])
    p.y2_axis=AxisConfig.from_dict(manifest["axes"]["y2"]) if "y2" in manifest["axes"] else None
    p.x_axis.name=manifest["axes"]["x"].get("label","X")
    p.y_axis.name=manifest["axes"]["y1"].get("label","Y1")
    if p.y2_axis is not None:
        p.y2_axis.name=manifest["axes"]["y2"].get("label","Y2")
    for label,corner in (("BL","bottom_left"),("BR","bottom_right"),
                         ("TL","top_left"),("TR","top_right")):
        p.calibration.set_corner(corner,*manifest["plot_corners_px"][label])
    app.project=p
    app.config=app.new_configuration("Verification")
    app.current_doc_id="isolated_mock"
    app.stale_source=False
    app.catalog_session_invalid=False
    app.require_working_source=lambda:True
    app.persist=lambda:True
    app.image=Image.open(base/manifest["image_file"]).convert("RGB")
    app.gray_image=app.image.convert("L")
    app.canvas.set_image(app.image)
    for prefix,axis in (("x",p.x_axis),("y",p.y_axis)):
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

root=tk.Tk();root.geometry("1450x850+45+40")
try:
    assert PLUGIN_VERSION=="2.0.25",PLUGIN_VERSION
    app=CurveDigitizerApp(root,Rpc(),bootstrap_payload=records(("SESSION",("test",))))
    base,m,row=sample("test_01_logx_y1lin_y2lin","phase")
    prepare(app,base,m)
    root.update()
    app.start_verification()
    assert app.verification_dialog is not None
    assert app.verification_dialog.window.winfo_toplevel() is root
    assert app.verification_dialog.window.winfo_class() != "Toplevel"
    assert app.verification_expansion.winfo_manager()=="grid"
    assert app.verification_toggle.cget("text")=="Close verification"
    assert app.mode.get()=="verify"
    assert root.grab_current() is None, "Verification window must not block graph clicks"
    assert set(app.verification_dialog.controls)=={"x","y1","y2"}
    assert not any(isinstance(w,tk.Toplevel) for w in root.winfo_children())
    x,y=float(row["pixel_x"]),float(row["pixel_y"])
    app.canvas_press(x,y)
    app.exp_x.set(row["x"])
    app.exp_y2.set(row["y"])
    root.update()
    assert "Calculated X:" in app.verify_result.get()
    assert "Calculated Y2:" in app.verify_result.get()
    assert "Δlog10(X)" in app.verify_result.get()
    assert "decades" in app.verification_dialog.controls["x"]["comparison"].get()
    assert app.verification_dialog.controls["y1"]["delta"].get()=="—"
    app.exp_x.set("-20")
    root.update()
    assert "strictly positive" in app.verification_dialog.errors.get()
    assert app.verification_dialog.controls["x"]["comparison"].get()=="Invalid reference"
    app.exp_x.set(row["x"])
    app.exp_y2.set(row["y"])
    root.update()
    assert app.verification_dialog.errors.get()==""
    app._verification_scroll_into_view()
    if os.environ.get("GX_VERIFICATION_SCREENSHOT"):
        path=Path(os.environ["GX_VERIFICATION_SCREENSHOT"])
        path.parent.mkdir(parents=True,exist_ok=True)
        ImageGrab.grab().save(path)
        print("SCREENSHOT",path,flush=True)
    app._verification_clear_expected()
    assert app.exp_x.get()=="" and app.exp_y2.get()==""
    app.clear_verification()
    assert app.verification_dialog is None
    assert app.verify_point is None
    assert app.mode.get()=="add"
    assert app.verification_expansion.winfo_manager()==""
    assert app.verification_toggle.cget("text")=="Verify calibration..."
    # Legacy monoaxis regression.
    base,m,row=sample("test_02_lin_x_lin_y","linear")
    prepare(app,base,m)
    app.start_verification()
    root.update()
    assert set(app.verification_dialog.controls)=={"x","y1"}
    app.canvas_press(float(row["pixel_x"]),float(row["pixel_y"]))
    app.exp_x.set(row["x"])
    app.exp_y.set(row["y"])
    assert "ΔX" in app.verify_result.get()
    assert "ΔY" in app.verify_result.get()
    assert "Calculated Y2" not in app.verify_result.get()
    assert "%" in app.verification_dialog.controls["x"]["comparison"].get()
    # Changing mode away from Verify closes both its marker and window.
    app.mode.set("add")
    assert app.verification_dialog is None and app.verify_point is None
    # Log-Y2 fixture verifies unit/scale identity and three separate fields.
    base,m,row=sample("test_03_lin_x_y1lin_y2log","density")
    prepare(app,base,m)
    app.start_verification()
    app.canvas_press(float(row["pixel_x"]),float(row["pixel_y"]))
    app.exp_x.set(row["x"])
    app.exp_y2.set(row["y"])
    root.update()
    assert "decades" in app.verification_dialog.controls["y2"]["comparison"].get()
    assert "×" in app.verification_dialog.controls["y2"]["comparison"].get()
    assert "a.u." in app.verification_dialog.controls["y2"]["calculated"].get()
    # While the modeless window is active, the logical Y2 checkbox must be
    # able to reconfigure its rows without destroying the source marker.
    app.set_secondary_axis_enabled(False)
    assert set(app.verification_dialog.controls)=={"x","y1"}
    app.set_secondary_axis_enabled(True)
    assert set(app.verification_dialog.controls)=={"x","y1","y2"}
    app.clear_verification()
    # Do not leave a hidden Verify mode active after switching UI sections.
    app.notebook.select(app.calibration_tab)
    app.start_verification()
    app.notebook.select(app.curves_tab)
    root.update()
    assert app.verification_dialog is None and app.verify_point is None
    assert app.mode.get()=="add"
    print("PASS F3V GUI: modeless window, physical/log references, live updates, errors, legacy, Y2",flush=True)
finally:
    root.destroy()
