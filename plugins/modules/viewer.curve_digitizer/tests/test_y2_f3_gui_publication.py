# SPDX-License-Identifier: GPL-3.0-or-later
"""Real Tk publication controller + mocked public RPC: no Session/CORE writes."""
from __future__ import annotations
import copy
import csv
import json
import sys
import tkinter as tk
import uuid
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
MODULE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(MODULE/"python"))
import gxtxt_curve_digitizer as gui
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e, b64d
from digitizer_model import AxisConfig, Project, Series, DigitizedPoint

def rec(*rows):
    return "\n".join("\t".join([k]+[b64e(str(v)) for v in fields]) for k,fields in rows)
class RPC:
    def __init__(self):
        self.calls=[]
        self.groups=[]
        self.group_allowed=True
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return rec(*(("SETTING",(k,v,"user")) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        if cmd=="GROUP_CAPABLE":
            return "1" if self.group_allowed else "0"
        if cmd=="GROUP_CREATE":
            assert len(args)==4
            token,gid,label,members=args
            assert gid.startswith("cdg_")
            self.groups.append(dict(group_id=gid,label=label,
                                    members=members.splitlines()))
            return gid
        if cmd=="PUBLISH":
            assert len(args)==27,len(args)
            assert args[26]=="2",args[-1]
            assert args[24]=="" and args[25]=="", "Y2 uncertainty is not yet supported"
            metadata={}
            for line in args[21].splitlines():
                k,v=line.split("\t",1);metadata[b64d(k)]=b64d(v)
            rows=[line.split("\t") for line in args[20].splitlines()]
            assert rows and all(len(line) in (10,12) for line in rows)
            assert metadata["curve_digitizer.axis_schema_version"]=="1"
            assert metadata["curve_digitizer.curve_schema_version"]=="2"
            assert all(row[-1] in ("y1","y2") for row in rows)
            self.calls.append(dict(args=args,md=metadata,rows=rows))
            contract="curve_family.table" if args[4]=="family" else "table.generic"
            return f"{args[2]}\t/mock/{args[2]}.csv\t"+("a"*64)+f"\t{contract}"
        raise AssertionError((cmd,len(args)))

def prepare(fixture_id, *, same_unit=False, calibrations=1,
            combined=False, family=False):
    fixture=ROOT/"test_fixtures"/"y2"
    manifest=json.loads((fixture/f"{fixture_id}_manifest.json").read_text(encoding="utf-8"))
    rpc=RPC()
    root=tk.Tk();root.geometry("1200x800")
    app=CurveDigitizerApp(root,rpc,bootstrap_payload=rec(("SESSION",("f3_mock",))))
    app.current_doc_id="mock_doc"
    app.persist=lambda:True
    app.persist_later=lambda:None
    app.config=app.new_configuration(fixture_id)
    app.config["source"]={
        "dataset_id":"fixture_image","sha256":"f"*64,
        "width":1600,"height":900,"format":"png","media_type":"image/png",
    }
    p=Project()
    p.x_axis=AxisConfig.from_dict(manifest["axes"]["x"])
    p.y_axis=AxisConfig.from_dict(manifest["axes"]["y1"])
    if "y2" in manifest["axes"]:
        p.y2_axis=AxisConfig.from_dict(manifest["axes"]["y2"])
    else:
        p.y2_axis=copy.deepcopy(p.y_axis)
        p.y2_axis.name="Y2"
    if same_unit:
        p.y2_axis.unit=p.y_axis.unit
    for tag,key in (("BL","bottom_left"),("BR","bottom_right"),
                    ("TL","top_left"),("TR","top_right")):
        p.calibration.set_corner(key,*manifest["plot_corners_px"][tag])
    series={}
    with (fixture/manifest["truth_file"]).open(newline="",encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if int(row["point_order"]) not in (0,100,200,300,400):
                continue
            cid=row["curve_id"]
            axis=row["y_axis_id"]
            if axis=="y1" and len(series)==0:
                pass
            if cid not in series:
                series[cid]=Series(id=cid,name=row["curve_name"],y_axis_id=axis,
                                   parameter_value="1",parameter_unit="1")
            series[cid].points.append(DigitizedPoint(
                id=f"{cid}_{row['point_order']}",pixel_x=float(row["pixel_x"]),
                pixel_y=float(row["pixel_y"])))
    if same_unit and all(s.y_axis_id=="y1" for s in series.values()):
        # Fixture02 is legacy: reinterpret one curve via the optional axis.
        series[list(series)[-1]].y_axis_id="y2"
    p.series=list(series.values())
    p.recalculate_all_points()
    app.project=p
    app.image=Image.open(fixture/manifest["image_file"]).convert("RGB")
    app.gray_image=app.image.convert("L")
    app.canvas.set_image(app.image)
    for name,axis in (("x",p.x_axis),("y",p.y_axis),("y2",p.y2_axis)):
        for field,val in (("name",axis.name),("unit",axis.unit),
                          ("min",axis.minimum),("max",axis.maximum),
                          ("scale",axis.scale)):
            getattr(app,f"{name}_{field}").set(str(val))
    app.family_enabled.set(family)
    app.family_label.set("measurement")
    app.family_unit.set("1")
    app.output_dataset_id.set("digitized.test")
    app.output_display_name.set("F3 test")
    group={"group_id":"calgrp_"+uuid.uuid4().hex,"active_id":None,"items":[]}
    for k in range(calibrations):
        mid="meas_"+uuid.uuid4().hex
        axes=app._project_axes_snapshot()
        if k:
            axes["y"]["maximum"]+=k
            axes["y2"]["maximum"]+=k
        group["items"].append(dict(id=mid,label=f"Calibration {k+1}",
            state="accepted",axes=axes,calibration=p.calibration.to_dict(),
            scale_reference=None))
        if k==0:group["active_id"]=mid
    app.config["calibration_measurements"]=group
    app.publish_layout.set("combined" if combined else "separate")
    app.refresh_publish_measurements()
    if calibrations>1:
        app.select_all_publish_measurements()
    app.require_working_source=lambda:True
    errors=[];app._test_f3_errors=errors
    app.active_series_id=p.series[0].id
    app.refresh_curve_tree()
    return root,app,rpc,errors

yes=gui.messagebox.askyesno
err=gui.messagebox.showerror
gui.messagebox.askyesno=lambda *a,**k:True
try:
    cases=[
        ("test_01_logx_y1lin_y2lin",False,1,False,False,2),
        ("test_02_lin_x_lin_y",True,1,False,False,1),
        ("test_03_lin_x_y1lin_y2log",False,1,False,False,2),
        ("test_01_logx_y1lin_y2lin",False,2,False,False,4),
        ("test_01_logx_y1lin_y2lin",False,2,True,False,2),
        ("test_02_lin_x_lin_y",True,2,True,True,1),
    ]
    for fixture,same_unit,measurements,combined,family,expected in cases:
        root,app,rpc,errors=prepare(fixture,same_unit=same_unit,
            calibrations=measurements,combined=combined,family=family)
        gui.messagebox.showerror=lambda *a,**k:errors.append(a)
        try:
            app.publish_dataset()
            assert not errors,(fixture,errors)
            assert len(rpc.calls)==expected,(fixture,len(rpc.calls),expected)
            assert app.publish_result.get().startswith(f"Published {expected} Dataset")
            set_ids={c["md"]["curve_digitizer.publication_set_id"] for c in rpc.calls}
            assert len(set_ids)==1
            assert len({c["args"][2] for c in rpc.calls})==expected
            for call in rpc.calls:
                md=call["md"]
                mode=md["curve_digitizer.axis_mode"]
                rows=call["rows"]
                axes={row[-1] for row in rows}
                if mode=="mixed":
                    assert axes=={"y1","y2"}
                    assert md["curve_digitizer.axis_units_y1"]==md["curve_digitizer.axis_units_y2"]
                else:assert axes=={mode}
                if combined:
                    assert all(len(row)==12 for row in rows)
                else:
                    assert all(len(row)==10 for row in rows)
                for row in rows:
                    cid=b64d(row[0]);axis=row[-1]
                    assert md[f"curve_digitizer.curve_axis.{cid}"]==axis
                assert "curve_digitizer.calibration_manifest" in md
            print("PASS",fixture,"unit-same" if same_unit else "unit-split",
                  "calibrations",measurements,"combined",combined,
                  "family",family,"datasets",len(rpc.calls),flush=True)
        finally:root.destroy()
    # Opt-in grouping applies equally to axis splits and multiple calibration
    # splits. A single canonical output is never wrapped needlessly.
    for fixture,same_unit,measurement_count,expected_datasets in (
        ("test_01_logx_y1lin_y2lin",False,1,2),
        ("test_01_logx_y1lin_y2lin",False,2,4),
        ("test_02_lin_x_lin_y",True,1,1)):
        root,app,rpc,errors=prepare(fixture,same_unit=same_unit,
                                    calibrations=measurement_count)
        gui.messagebox.showerror=lambda *a,**k:errors.append(a)
        try:
            assert not app.publish_group_datasets.get()  # default OFF
            app.publish_group_datasets.set(True)
            config=app.serialize_configuration()
            assert config["publication"]["group_datasets"] is True
            app.publish_dataset()
            assert not errors,errors
            assert len(rpc.calls)==expected_datasets
            assert len(rpc.groups)==(1 if expected_datasets>1 else 0)
            if rpc.groups:
                assert rpc.groups[0]["members"]==[
                    record["args"][2] for record in rpc.calls]
                assert "Dataset Group: cdg_" in app.publish_result.get()
            print("PASS F4 optional Group",fixture,
                  "members",expected_datasets,"grouped",bool(rpc.groups))
        finally:
            root.destroy()
    # Capability absent with grouping requested: abort BEFORE any Dataset.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin")
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    try:
        rpc.group_allowed=False
        app.publish_group_datasets.set(True)
        app.publish_dataset()
        assert len(rpc.calls)==0 and not rpc.groups
        assert errors and "capability" in errors[0][1]
        print("PASS F4 grouping missing authority: no Dataset writes")
    finally:root.destroy()
    # Group capacity is a preflight check: 33 calibrations x two axes would
    # require 66 outputs, and must fail before any Dataset publication.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin",calibrations=33)
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    try:
        app.publish_group_datasets.set(True)
        app.select_all_publish_measurements()
        app.publish_dataset()
        assert not rpc.calls and not rpc.groups
        assert errors and "64" in errors[-1][1],errors
        print("PASS F4 >64 grouped outputs refused before any Dataset write")
    finally:root.destroy()
    # Failed Group creation must remain a *separate* failure after successful
    # canonical publications. The GUI never asserts rolled-back Datasets.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin")
    warnings=[]
    oldwarning=gui.messagebox.showwarning
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    gui.messagebox.showwarning=lambda *a,**k:warnings.append(a)
    original_call=rpc.call
    def group_create_failure(command,*args):
        if command=="GROUP_CREATE":
            raise gui.RpcError("Simulated stale member revision")
        return original_call(command,*args)
    rpc.call=group_create_failure
    try:
        app.publish_group_datasets.set(True)
        app.publish_dataset()
        assert len(rpc.calls)==2 and not rpc.groups
        assert "Dataset Group: FAILED" in app.publish_result.get()
        assert warnings and "Simulated stale" in warnings[-1][1]
        print("PASS F4 Group failure isolated from two published canonical Dataset receipts")
    finally:
        gui.messagebox.showwarning=oldwarning
        root.destroy()
finally:
    gui.messagebox.askyesno=yes
    gui.messagebox.showerror=err
