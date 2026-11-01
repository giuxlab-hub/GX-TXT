# SPDX-License-Identifier: GPL-3.0-or-later
"""Real Tk publication controller + exact F5 Y-axis Numeric wire; no Session writes."""
from __future__ import annotations
import base64
import json
import sys
from pathlib import Path

SOURCE=Path(__file__).resolve().parent/"test_y2_f3_gui_publication.py"
# The pre-existing F3/F4 case matrix is an isolated, deterministic mock-host
# regression. Its prepare() factory is reused rather than rewriting fixtures.
fixture_path = SOURCE
fixture_namespace = {"__name__":"f5_fixture_helpers", "__file__":str(fixture_path)}
fixture_source = fixture_path.read_text(encoding="utf-8")
assert "\nyes=gui.messagebox.askyesno" in fixture_source
exec(compile(fixture_source.split("\nyes=gui.messagebox.askyesno")[0],
             str(fixture_path), "exec"), fixture_namespace)
prepare = fixture_namespace["prepare"]
gui = fixture_namespace["gui"]
from uncertainty_engine import review_fingerprint,decode_factors

def reviewed(app,mode="pixel_calibration"):
    if mode=="pixel_calibration":
        spec=dict(mode=mode,pixel_distribution="normal_standard_uncertainty",
                  pixel_scale=[0.3,0.5],
                  calibration_standard_uncertainty=[0.1]*8+
                      [0.02,0.03,0.04,0.05,0.06,0.07],
                  rationale="Reviewed synthetic shared corners and independent axis-end scales")
    else:
        spec=dict(mode=mode,override_standard_uncertainty=[0.11,0.22,0.77],
                  rationale="Three explicit independent physical axis standard uncertainties")
    spec["review_fingerprint"]=review_fingerprint(app.serialize_configuration())
    app.config["uncertainty"]=spec
    return spec

original_error=gui.messagebox.showerror
original_warning=gui.messagebox.showwarning
original_yes=gui.messagebox.askyesno
gui.messagebox.askyesno=lambda *args,**kwargs:True
try:
    scenarios=[
        ("test_01_logx_y1lin_y2lin",False,"pixel_calibration",2),
        ("test_02_lin_x_lin_y",True,"pixel_calibration",1),
        ("test_03_lin_x_y1lin_y2log",False,"physical_override",2),
    ]
    for fixture,same_unit,mode,expected_jobs in scenarios:
        root,app,rpc,errors=prepare(fixture,same_unit=same_unit)
        gui.messagebox.showerror=lambda *a,**k:errors.append(a)
        warnings=[]
        gui.messagebox.showwarning=lambda *a,**k:warnings.append(a)
        captured=[]
        previous=rpc.call
        declared=reviewed(app,mode)
        def capture(cmd,*args):
            if cmd!="PUBLISH":return previous(cmd,*args)
            assert len(args)==27 and args[-1]=="2"
            assert args[24] and args[25],"F5 requires both statistical rows and CORE inline"
            lines=args[24].splitlines()
            report=json.loads(gui.b64d(lines[0]))
            factors=json.loads(gui.b64d(lines[1]))
            local,shared=decode_factors(factors)
            assert report["calibration_input_count"]==14
            assert shared.shape==(2*(len(lines)-2),14)
            assert len(lines)==len(args[20].splitlines())+2
            row_axes=[row.split("\t")[-1] for row in args[20].splitlines()]
            assert len(row_axes)==len(lines)-2
            assert report["axis_binding_variable_id"]=="y_axis_id"
            assert report["axes_in_dataset"]==sorted(set(row_axes))
            assert report["shared_calibration"]==(mode=="pixel_calibration")
            md={gui.b64d(k):gui.b64d(v) for record in args[21].splitlines()
                for k,v in [record.split("\t")]}
            assert md["curve_digitizer.uncertainty_calibration_input_count"]=="14"
            wire=args[25].split("\t")
            assert len(wire)==17 and wire[0]=="CORE_LINEARIZATION_V1"
            assert len(gui.b64d(wire[13]).split(";"))==14
            if mode=="pixel_calibration":
                assert len(wire[6].split(","))==14
                assert wire[7]==""
            else:
                assert wire[6]==""
                assert len(wire[7].split(","))==2*(len(lines)-2)
                # Column-major N×2 physical override has a distinct Y2.
                n=len(lines)-2
                yvals=[float(v) for v in wire[7].split(",")[n:]]
                axis=row_axes
                assert yvals==[declared["override_standard_uncertainty"][1]
                    if a=="y1" else declared["override_standard_uncertainty"][2]
                    for a in axis]
            captured.append((args,report,local,shared,md))
            contract="curve_family.table" if args[4]=="family" else "table.generic"
            return args[2]+"\t/mock/no-write.csv\t"+("a"*64)+"\t"+contract
        rpc.call=capture
        try:
            app.publish_dataset()
            assert not errors,errors
            assert not warnings,warnings
            assert len(captured)==expected_jobs,(fixture,expected_jobs,len(captured))
            if expected_jobs==2:
                assert len({rec[1]["publication_set_id"] for rec in captured})==1
                assert {rec[1]["axes_in_dataset"][0] for rec in captured}=={"y1","y2"}
            else:
                assert set(captured[0][1]["axes_in_dataset"])=={"y1","y2"}
            print("PASS F5 reviewed GUI CORE transport",fixture,mode,
                  "datasets",len(captured),flush=True)
        finally:root.destroy()
    # An old 12-input review is not accepted as a 14-input scientific model.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin")
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    try:
        old=reviewed(app,"pixel_calibration")
        old["calibration_standard_uncertainty"]=[0.1]*12
        app.publish_dataset()
        assert errors and not rpc.calls,errors
        print("PASS F5 stale 12-input uncertainty declaration rejected")
    finally:root.destroy()
    # A valid declaration still must be re-reviewed if a source point changes.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin")
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    try:
        reviewed(app)
        app.project.series[0].points[0].pixel_x += 0.31
        app.project.recalculate_all_points()
        app.publish_dataset()
        assert errors and "review" in errors[-1][1].lower(),errors
        assert not rpc.calls
        print("PASS F5 changed scientific point rejects old review")
    finally:root.destroy()
    # Distinct measurements in a single combined Dataset cannot silently be
    # represented as one shared 14-parameter calibration.
    root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin",
                                calibrations=2,combined=True)
    gui.messagebox.showerror=lambda *a,**k:errors.append(a)
    try:
        reviewed(app)
        app.publish_dataset()
        assert errors and not rpc.calls,errors
        print("PASS F5 multi-calibration combined uncertain output refused")
    finally:root.destroy()
finally:
    gui.messagebox.showerror=original_error
    gui.messagebox.showwarning=original_warning
    gui.messagebox.askyesno=original_yes
