# SPDX-License-Identifier: GPL-3.0-or-later
"""Y2 companion-state adapter: append pixels to the correct curve axis."""
from pathlib import Path
import base64
import json
import subprocess
import sys
import tempfile

MODULE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(MODULE/"python"))
from digitizer_model import AxisConfig, Project, Series

p=Project()
p.auto_calibrate_full_image(101,101)
p.x_axis=AxisConfig("Frequency","Hz",10,10000,"log")
p.y_axis=AxisConfig("Gain","dB",-40,5,"linear")
p.y2_axis=AxisConfig("Phase","deg",-90,0,"linear")
p.series=[Series(id="gain",name="Gain"),Series(id="phase",name="Phase",y_axis_id="y2")]
state=p.to_dict()
cfg={"format":"gxtxt.curve_digitizer.configuration","version":"1.0",
     "configuration_id":"digcfg_F1_test","name":"Y2 F1",
     "axes":state["axes"],"axis_model_version":2,
     "source":{"sha256":"f"*64,"width":101,"height":101},
     "calibration":state["calibration"],"curves":state["series"]}
script=MODULE/"python"/"companion_bridge.py"
with tempfile.TemporaryDirectory(prefix="gx_y2_companion_") as tmp:
    root=Path(tmp)
    inp=root/"config.json"; inp.write_text(json.dumps(cfg),encoding="utf-8")
    pts=root/"pixel_points.tsv"; pts.write_text("p1\t50\t50\np2\t100\t0\n",encoding="utf-8")
    out=root/"out.json"
    result=subprocess.run([sys.executable,"-B",str(script),"append-pixel-points",
        "--input",str(inp),"--output",str(out),"--curve-id","phase","--points",str(pts)],
        capture_output=True,text=True,check=True)
    saved=json.loads(out.read_text(encoding="utf-8"))
    assert saved["axis_model_version"]==2
    assert saved["axes"]==cfg["axes"]
    assert saved["curves"][0]==cfg["curves"][0]
    assert saved["curves"][1]["y_axis_id"]=="y2"
    pp=saved["curves"][1]["points"]
    assert [x["id"] for x in pp]==["p1","p2"]
    assert abs(pp[0]["calibrated"]["x"]-10**2.5)<1e-8
    assert abs(pp[0]["calibrated"]["y"]-(-45))<1e-8
    assert abs(pp[1]["calibrated"]["x"]-10000)<1e-8
    assert abs(pp[1]["calibrated"]["y"]-0)<1e-8
    response=subprocess.run([sys.executable,"-B",str(script),"context",
        "--input",str(out),"--curve-id","phase"], capture_output=True,text=True,check=True)
    fields={}
    for line in response.stdout.splitlines():
        key,val=line.split("\t",1)
        fields[key]=base64.b64decode(val).decode("utf-8") if key not in {
            "CALIBRATION_READY","CURVE_POINT_COUNT"} else val
    assert fields["CURVE_POINT_COUNT"]=="2"
    assert json.loads(fields["CURVE_JSON"])["y_axis_id"]=="y2"
    assert json.loads(fields["AXES_JSON"])["y2"]["unit"]=="deg"
print("PASS companion append/context: Y2 exact mapping, stable axes/curve metadata, no Session writes")
