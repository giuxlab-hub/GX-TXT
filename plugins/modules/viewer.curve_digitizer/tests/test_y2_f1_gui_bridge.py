# SPDX-License-Identifier: GPL-3.0-or-later
"""F1 GUI-adapter regression under isolated Xvfb; no real Dataset/Session writes."""
import copy
import json
import sys
import tkinter as tk
from pathlib import Path
from PIL import Image

MODULE=Path(__file__).resolve().parents[1]
WORKTREE=Path(__file__).resolve().parents[4]
sys.path.insert(0, str(MODULE/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e, messagebox
from digitizer_model import Project, AxisConfig, Series, DigitizedPoint

def records(*rows):
    return "\n".join("\t".join([k]+[b64e(str(v)) for v in values]) for k,values in rows)

class RPC:
    def attach(self,root): pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return records(*(("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        raise AssertionError(f"No Session API call permitted in F1 test: {cmd}")

root=tk.Tk()
root.geometry("1250x760")
try:
    app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(("SESSION",["mock-session"])))
    cfg=app.new_configuration("Y2 F1 persistence")
    app.config=cfg
    project=Project()
    project.auto_calibrate_full_image(180,100)
    project.y_axis=AxisConfig("Gain","dB",-40,5,"linear")
    project.y2_axis=AxisConfig("Phase","deg",-100,10,"linear")
    project.series=[Series(id="gain",name="Gain",y_axis_id="y1",
                           points=[DigitizedPoint(pixel_x=80,pixel_y=70,id="p-g")]),
                    Series(id="phase",name="Phase",y_axis_id="y2",
                           points=[DigitizedPoint(pixel_x=80,pixel_y=70,id="p-p")])]
    project.recalculate_all_points()
    app.project=project
    for key,axis in (("x",project.x_axis),("y",project.y_axis)):
        for field,value in (("name",axis.name),("unit",axis.unit),
                            ("min",axis.minimum),("max",axis.maximum),
                            ("scale",axis.scale)):
            getattr(app,f"{key}_{field}").set(str(value))
    app.refresh_curve_tree()
    saved=app.serialize_configuration()
    assert saved["axis_model_version"]==2
    assert saved["axes"]["y2"]["unit"]=="deg"
    assert saved["curves"][0]["y_axis_id"]=="y1"
    assert saved["curves"][1]["y_axis_id"]=="y2"
    measurements=saved["calibration_measurements"]["items"]
    assert len(measurements)==1 and "y2" in measurements[0]["axes"]
    after=app.config_to_project(saved)
    assert after.to_dict()["series"]==project.to_dict()["series"]
    # New measurement with a distinct calibration and Y2 scale:
    app.config=saved
    app.project=after
    first=app._measurements()["active_id"]
    new=copy.deepcopy(measurements[0])
    new["id"]="meas_"+("2"*32)
    new["label"]="Second"
    new["axes"]["y2"]["maximum"]=20.0
    app.config["calibration_measurements"]["items"].append(new)
    app.measurement_selected_id=new["id"]
    app.persist=lambda: True  # No real document owner exists in F1 GUI mock
    app.activate_measurement()
    assert app.project.y2_axis.maximum==20.0
    assert app.project.series[1].y_axis_id=="y2"
    assert app.config["axes"]["y2"]["maximum"]==20.0
    app.measurement_selected_id=first
    app.activate_measurement()
    assert app.project.y2_axis.maximum==10.0
    # Switch to a historical calibration created BEFORE Y2 was enabled.
    legacy_measurement=copy.deepcopy(measurements[0])
    legacy_measurement["id"]="meas_"+("3"*32)
    del legacy_measurement["axes"]["y2"]
    app.config["calibration_measurements"]["items"].append(legacy_measurement)
    app.measurement_selected_id=legacy_measurement["id"]
    app.activate_measurement()
    assert app.project.y2_axis is not None
    assert "y2" in legacy_measurement["axes"]
    assert app.project.series[1].y_axis_id=="y2"
    # F5 now supports explicitly reviewed Y2 uncertainties, but a declaration
    # without its current scientific fingerprint must still fail closed.
    app.config["uncertainty"] = {"mode": "reviewed", "rationale": "F5 pending"}
    errors=[]
    original_showerror=messagebox.showerror
    app.require_working_source=lambda: True
    messagebox.showerror=lambda *args,**kwargs: errors.append(args)
    try: app.publish_dataset()
    finally: messagebox.showerror=original_showerror
    assert errors and "review" in errors[0][1].lower(), errors
    legacy=Project()
    legacy.auto_calibrate_full_image(100,60)
    app.project=legacy
    app.config=app.new_configuration("Legacy")
    legacy_cfg=app.serialize_configuration()
    assert legacy_cfg["version"]=="1.0"
    assert "axis_model_version" not in legacy_cfg
    assert "y2" not in legacy_cfg["axes"]
    print("PASS F1 GUI adapter: Y2 persistence, measurement switching, stale scientific uncertainty review guard, legacy format")
finally:
    root.destroy()
