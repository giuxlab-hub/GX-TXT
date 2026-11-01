# SPDX-License-Identifier: GPL-3.0-or-later
"""Isolated GUI scientific publication: 3x100 raster points x k0/k1/k4.

This verifies the actual GUI client publication request, manifest and full
900-row content. A fake public RPC returns an in-memory receipt; it NEVER
creates a real GX-TXT Dataset/Session/Workspace.
"""
from pathlib import Path
import json,sys,uuid,tkinter as tk
from tkinter import messagebox
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,b64d,PLUGIN_VERSION
from digitizer_model import Series,DigitizedPoint,AxisConfig
from calibration_manifest import build_manifest
def records(*rows):
    return "\n".join("\t".join([k]+[b64e(str(v)) for v in vals]) for k,vals in rows)
class FakeRPC:
    def __init__(self):self.requests=[];self.n=0
    def attach(self,root):pass
    def begin(self,*args):self.n+=1;return self.n
    def poll_response(self,_):return None
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        if cmd=="PUBLISH":
            self.requests.append(args)
            return "digitized.tutorial02.family.combined.curves\t/mock/no-write.csv\t"+'f'*64+"\tcurve_family.table"
        raise AssertionError((cmd,len(args)))
def create():
    rpc=FakeRPC()
    root=tk.Tk();root.geometry("1250x820+4250+4250")
    app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(("SESSION",["test_session"])))
    assert PLUGIN_VERSION=="2.0.25"
    app.persist=lambda:True
    app.persist_later=lambda:None
    app.current_doc_id="test_doc"
    app.session_token="test_session"
    app.config=app.new_configuration("Tutorial 02 — Family")
    app.config["source"]={"dataset_id":"calibrated.family.image","sha256":"b"*64,
                          "width":1201,"height":1001}
    app.project=app.config_to_project(app.config)
    app.project.auto_calibrate_full_image(1201,1001)
    app.project.x_axis=AxisConfig("Time","s",-0.964,11.084,"linear")
    app.project.y_axis=AxisConfig("Voltage","V",-1.018,8.962,"linear")
    app.project.series=[]
    image=Image.new("RGB",(1201,1001),"white")
    pen=ImageDraw.Draw(image)
    for c in (5,15,25):
        def center(x):return 900-14*c-8*(2*((x-100)/1000)-1)**2
        pen.line([(int(x),int(round(center(x)))) for x in range(100,1101)],
                 fill=(160,30+c*2,120),width=1)
        s=Series(name=f"Source curve {c+1:02d}",parameter_name="c",
                 parameter_value=str(c),parameter_unit="1")
        for index in range(100):
            x=100+1000*index/99
            pt=DigitizedPoint(pixel_x=x,pixel_y=center(x),
                              manual_pixel_x=x,manual_pixel_y=center(x),origin="assisted")
            app.project.update_point_calibration(pt)
            s.points.append(pt)
        app.project.series.append(s)
    app.set_image(image)
    app.family_enabled.set(True)
    app.family_label.set("c")
    app.family_unit.set("1")
    app.family_role.set("family")
    app.x_name.set("Time")
    app.x_unit.set("s")
    app.x_min.set("-0.964");app.x_max.set("11.084")
    app.y_name.set("Voltage")
    app.y_unit.set("V")
    app.y_min.set("-1.018");app.y_max.set("8.962")
    group={"group_id":"calgrp_"+uuid.uuid4().hex,"active_id":None,"items":[]}
    for k in (0,1,4):
        mid="meas_"+uuid.uuid4().hex
        axes={"x":AxisConfig("Time","s",-1+0.009*k,11+0.021*k,"linear").to_dict(),
              "y":AxisConfig("Voltage","V",-1-0.0045*k,9-0.0095*k,"linear").to_dict()}
        group["items"].append({"id":mid,"label":f"k{k}","state":"accepted",
                               "axes":axes,"calibration":app.project.calibration.to_dict(),
                               "scale_reference":None})
        if k==4:group["active_id"]=mid
    app.config["calibration_measurements"]=group
    app.config["uncertainty"]={"mode":"none"}
    app.config["scale_reference"]=None
    app.output_dataset_id.set("digitized.tutorial02.family")
    app.output_display_name.set("Tutorial 02 - Three curves")
    app.publish_layout.set("combined")
    app.refresh_curve_tree()
    app.refresh_publish_measurements()
    app.select_all_publish_measurements()
    manifest=build_manifest(app.serialize_configuration(),app.project,1201,1001)
    assert manifest["calibration_type"]=="affine",manifest["calibration_type"]
    assert all(x["calibration_type"]=="affine" for x in manifest["calibration_measurements"])
    return root,app,rpc
old_yes=messagebox.askyesno;old_err=messagebox.showerror
errors=[]
messagebox.askyesno=lambda *a,**k:True
messagebox.showerror=lambda *a,**k:errors.append((a,k))
root,app,rpc=create()
try:
    app.publish_dataset()
    assert not errors,errors
    assert len(rpc.requests)==1,len(rpc.requests)
    req=rpc.requests[0]
    assert req[2]=="digitized.tutorial02.family.combined.curves",req[2]
    assert req[4]=="family"
    assert req[16]=="affine",("reported class",req[16])
    assert req[22]=="combined",req[22]
    rows=req[20].splitlines()
    assert len(rows)==900,len(rows)
    for row in rows:
        fields=row.split("\t")
        assert len(fields)==11,len(fields)
        assert b64d(fields[8]).startswith("meas_")
    assert len({b64d(row.split("\t")[0]) for row in rows})==3
    assert len({b64d(row.split("\t")[8]) for row in rows})==3
    assert sorted({row.split("\t")[5] for row in rows})==["15","25","5"]
    # Verify the structured metadata sent in the exact request.
    meta={}
    for entry in req[21].splitlines():
        k,v=entry.split("\t")
        meta[b64d(k)]=b64d(v)
    assert meta["curve_digitizer.calibration_type"]=="affine"
    assert meta["curve_digitizer.measurement_count"]=="3"
    assert meta["curve_digitizer.publication_calibration_mode"]=="combined"
    assert json.loads(meta["curve_digitizer.publication_calibration_ids"])
    assert "Published 1 Dataset(s)" in app.publish_result.get(),app.publish_result.get()
    print("PASS: native GUI 900-row combined request; manifest=affine; three curves, three calibrations, no edits to real Session")
finally:
    messagebox.askyesno=old_yes;messagebox.showerror=old_err
    for event in root.tk.call("after","info"):
        try:root.after_cancel(event)
        except tk.TclError:pass
    try:root.destroy()
    except tk.TclError:pass  # a queued Tk callback may already have been removed
