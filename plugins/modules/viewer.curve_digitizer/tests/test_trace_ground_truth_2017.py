# SPDX-License-Identifier: GPL-3.0-or-later
"""Scientific regression: 1px colored families, 83 guides and local repairs.

The original synthetic family is reproduced in this test without external
files, CORE, Sessions or screenshots. This compares proposed SOURCE PIXEL
coordinates with the exact analytical centerline; it does not treat proposed
points as independent measurements.
"""
import colorsys,math,sys
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from assisted_tracing import propose,insert_correction,guide_curve_reference

W,H=1201,1001
CURVES=50
N=300
def center(c,x):
    return 900.-14.*c-8.*(2.*((x-100.)/1000.)-1.)**2
image=Image.new("RGB",(W,H),"white")
painter=ImageDraw.Draw(image)
for c in range(CURVES):
    color=tuple(round(v*255) for v in colorsys.hsv_to_rgb(c/CURVES,.8,.7))
    pts=[(round(100+1000*k/(N-1)),round(center(c,100+1000*k/(N-1))))
         for k in range(N)]
    painter.line(pts,fill=color,width=1)
def result_metrics(c,result):
    pts=np.asarray(result.points,dtype=float)
    error=pts[:,1]-np.array([center(c,float(x)) for x in pts[:,0]])
    return float(np.sqrt(np.mean(error*error))),float(np.max(np.abs(error))),int(np.count_nonzero(np.abs(error)>1.))
for c in (5,15):
    # At most three guide points: typical efficient assisted use.
    guides=[(x,center(c,x)) for x in (100.,600.,1100.)]
    for mode in ("Off","Gentle","Strong"):
        result=propose(image,guides,radius=6,step=2.,smoothness=mode)
        rms,maximum,outliers=result_metrics(c,result)
        print("Family",c,mode,"points",len(result.points),
              "RMS",round(rms,3),"MAX",round(maximum,3),"gt1",outliers)
        assert rms<.7,(c,mode,rms)
        assert maximum<=2.1,(c,mode,maximum)
        assert outliers<=15,(c,mode,outliers)
        assert result.points[0]==guides[0] and result.points[-1]==guides[-1]
    # The selected ink anchors need not be perfect; handle ±2 source-pixel clicks.
    for offset in (-2.,-1.,1.,2.):
        guides2=[(x,center(c,x)+offset) for x in (100.,600.,1100.)]
        r=propose(image,guides2,radius=6,step=2.,smoothness="Strong")
        rms,maximum,_=result_metrics(c,r)
        print("Shifted anchors",c,offset,"RMS",round(rms,3),"MAX",round(maximum,3))
        assert rms<.7 and maximum<=2.1,(c,offset,rms,maximum)
    # One real correction must preserve unrelated segments and join precisely.
    r=propose(image,guides,radius=6,step=2.,smoothness="Strong")
    for x,seg in [(420.,0),(720.,1)]:
        correction=(x,center(c,x))
        new_guides,repaired=insert_correction(r,image,guides,seg,1,correction,
                                              radius=6,step=2.,smoothness="Strong")
        rms,maximum,_=result_metrics(c,repaired)
        assert rms<.7 and maximum<=2.1,(c,seg,rms,maximum)
        assert len(new_guides)==4 and len(repaired.segments)==3
        assert new_guides[seg+1]==correction
        assert repaired.segments[seg][-1]==correction
        assert repaired.segments[seg+1][0]==correction
        if seg==0:
            assert repaired.segments[-1]==r.segments[-1]
        else:
            assert repaired.segments[0]==r.segments[0]
    # Stress topology: 83 operator-defined guides (the observed failure mode).
    # One shared C1 spline reference, not 82 independent piecewise chords.
    xs=np.linspace(100.,1100.,83)
    dense=[(float(x),center(c,float(x))) for x in xs]
    ref=guide_curve_reference(dense,step=2.)
    ref_array=np.asarray(ref)
    ref_error=np.abs(ref_array[:,1]-np.array([center(c,float(x)) for x in ref_array[:,0]]))
    print("Dense guides",c,"reference MAX",round(float(ref_error.max()),4))
    assert float(ref_error.max()) < .3
    rr=propose(image,dense,radius=6,step=2.,smoothness="Strong")
    rms,maximum,_=result_metrics(c,rr)
    print("Dense tracing",c,"segments",rr.segment_count,"RMS",round(rms,3),"MAX",round(maximum,3))
    assert rr.segment_count==82
    assert rms<.7 and maximum<=2.1
print("PASS analytic colored-family regression, shifted guides, local corrections and dense guidance")
