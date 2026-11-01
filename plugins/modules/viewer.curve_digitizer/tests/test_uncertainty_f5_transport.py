# SPDX-License-Identifier: GPL-3.0-or-later
"""Portable Python->real Tcl Numeric wire 12/14 and exact factor-integrity gate."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import numpy as np

MODULE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(MODULE/"python"))
from digitizer_model import Project,AxisConfig,CORNER_ORDER
from uncertainty_engine import propagate,compact_factors
from gxtxt_curve_digitizer import CurveDigitizerApp


def mkproject(dual=True):
    p=Project()
    p.x_axis=AxisConfig("Frequency","Hz",10,1e5,"log")
    p.y_axis=AxisConfig("Gain","V",-1,5,"linear")
    if dual:p.y2_axis=AxisConfig("Amplitude","V",0.001,1000,"log")
    for key,pt in zip(CORNER_ORDER,[(10,250),(460,248),(25,10),(478,28)]):
        p.calibration.set_corner(key,*pt)
    return p


p=mkproject()
pixels=np.asarray([[30.,190.],[120.,142.],[200.,97.],[380.,44.]],dtype=float)
axes=["y1","y2","y1","y2"]
mid="meas_"+"a"*32
pixel=dict(mode="pixel_calibration",
    pixel_distribution="normal_standard_uncertainty",pixel_scale=[.3,.5],
    calibration_standard_uncertainty=[.1]*8+[.01,.02,.03,.04,.05,.06],
    rationale="Synthetic physically reviewed source")
override=dict(mode="physical_override",override_standard_uncertainty=[.1,.2,.7],
              rationale="Synthetic physical values per logical axis")
lin=p.calibration_linearization(pixels,axes)
packet1=CurveDigitizerApp._core_inline_uncertainty(lin,pixel,mid,axis_ids=axes)
packet2=CurveDigitizerApp._core_inline_uncertainty(lin,override,mid,axis_ids=axes)
result=propagate(p,pixels,pixel,axis_ids=axes)
factors=compact_factors([result["local_factors"]],[result["shared_factors"]])
old=mkproject(dual=False)
legacy=old.calibration_linearization(pixels)
old_spec=dict(pixel,calibration_standard_uncertainty=[.1]*12)
packet3=CurveDigitizerApp._core_inline_uncertainty(legacy,old_spec,mid)
state={
    "independent_factor":result["local_factors"].reshape(8,2).tolist(),
    "shared_factor":result["shared_factors"].tolist()
}
with tempfile.TemporaryDirectory(prefix="gx_f5_numeric_wire_") as tmp:
    work=Path(tmp)
    packet_file=work/"packets.txt"
    packet_file.write_text("\n".join((packet1,packet2,packet3))+"\n",encoding="utf-8")
    factor_file=work/"factors.json"
    factor_file.write_text(json.dumps({
        "factors":json.dumps(factors,separators=(",",":")),
        "state":state
    }),encoding="utf-8")
    process=subprocess.run(
        ["tclsh",str(MODULE/"tests/test_uncertainty_f5_transport.tcl"),
         str(packet_file),str(factor_file)],
        capture_output=True,text=True,timeout=30,
    )
    if process.returncode:
        raise AssertionError("Real Tcl Numeric transport failed:\n"
                             +process.stdout+"\n"+process.stderr)
    assert "PASS F5 Tcl transport" in process.stdout,process.stdout
    print(process.stdout.strip())
