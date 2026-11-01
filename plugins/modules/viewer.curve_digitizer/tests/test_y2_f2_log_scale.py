# SPDX-License-Identifier: GPL-3.0-or-later
"""F2 log-Y2 GUI apply and persistence against known synthetic ground truth."""
import csv, json, sys, tkinter as tk
from pathlib import Path
from PIL import Image
P=Path(__file__).resolve().parents[1]
ROOT=P.parents[2]
sys.path.insert(0,str(P/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import AxisConfig, DigitizedPoint, Project, Series
def rec(*rows):
    return "\n".join("\t".join([key]+[b64e(str(v)) for v in args]) for key,args in rows)
class Fake:
    def attach(self,root): pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":return rec(*(("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        raise RuntimeError(cmd)
base=ROOT/"test_fixtures/y2"
manifest=json.loads((base/"test_03_lin_x_y1lin_y2log_manifest.json").read_text(encoding="utf-8"))
root=tk.Tk();root.geometry("1450x850")
try:
    app=CurveDigitizerApp(root,Fake(),bootstrap_payload=rec(("SESSION",["mock"])))
    app.config=app.new_configuration("Y2 logarithmic")
    app.persist=lambda: True
    p=Project()
    p.x_axis=AxisConfig.from_dict(manifest["axes"]["x"])
    p.y_axis=AxisConfig.from_dict(manifest["axes"]["y1"])
    for c,key in (("BL","bottom_left"),("BR","bottom_right"),
                  ("TL","top_left"),("TR","top_right")):
        p.calibration.set_corner(key,*manifest["plot_corners_px"][c])
    app.project=p
    for prefix,axis in (("x",p.x_axis),("y",p.y_axis)):
        for field,val in (("name",axis.name),("unit",axis.unit),("min",axis.minimum),
                          ("max",axis.maximum),("scale",axis.scale)):
            getattr(app,f"{prefix}_{field}").set(str(val))
    app.set_secondary_axis_enabled(True)
    for key,val in (("name","Density"),("unit","a.u."),("role","measured"),
                    ("min","0.001"),("max","1000"),("scale","log")):
        getattr(app,"y2_"+key).set(val)
    assert app.commit_axes(True)
    assert app.project.y2_axis.scale=="log"
    assert app.project.calibration_ready()
    app.project.series=[Series(id="voltage",name="Voltage",y_axis_id="y1"),
                        Series(id="density",name="Density",y_axis_id="y2")]
    points={}
    with (base/manifest["truth_file"]).open(newline="",encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if int(row["point_order"]) not in (0,50,100,150,200,250,300,350,400):
                continue
            series=app.project.series[1] if row["curve_id"]=="density" else app.project.series[0]
            pt=DigitizedPoint(id=row["curve_id"]+row["point_order"],
                              pixel_x=float(row["pixel_x"]),pixel_y=float(row["pixel_y"]))
            app.project.update_point_calibration(pt,series.y_axis_id)
            assert abs(pt.calibrated_x-float(row["x"]))<1e-8
            assert abs(pt.calibrated_y-float(row["y"])) < 1e-9*(1+abs(float(row["y"])))
            series.points.append(pt)
    app.project.recalculate_all_points()
    config=app.serialize_configuration()
    restored=app.config_to_project(config)
    assert restored.y2_axis.scale=="log"
    assert restored.y2_axis.minimum==0.001
    assert restored.series[1].y_axis_id=="y2"
    assert len(config["calibration_measurements"]["items"])==1
    assert config["calibration_measurements"]["items"][0]["axes"]["y2"]["scale"]=="log"
    app.project=restored
    app.verify(790,360,draw=False)
    assert "Calculated Y2:" in app.verify_result.get()
    app.on_cursor(790,360)
    assert "Density:" in app.status.get()
    print("PASS F2 logarithmic Y2: GUI calibration, two distinct bindings, ground truth, Workspace and measurement")
finally:
    root.destroy()
