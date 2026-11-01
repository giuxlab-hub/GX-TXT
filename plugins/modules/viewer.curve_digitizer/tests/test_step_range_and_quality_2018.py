# SPDX-License-Identifier: GPL-3.0-or-later
"""Ground truth Step up to 20 px; source fidelity and 100-point publication geometry."""
import sys,colorsys,math
from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from assisted_tracing import (ASSIST_STEP_MIN,ASSIST_STEP_MAX,samples_from_guides,
                             guide_curve_reference,propose,repair,insert_correction)
from assisted_sampling import sample_proposal_segments

assert (ASSIST_STEP_MIN,ASSIST_STEP_MAX)==(0.5,20.0)
def center(c,x):
    return 900-14*c-8*(2*((x-100)/1000)-1)**2
img=Image.new("RGB",(1201,1001),"white")
pencil=ImageDraw.Draw(img)
for c in range(50):
    col=tuple(round(v*255) for v in colorsys.hsv_to_rgb(c/50,.8,.7))
    samples=[(round(100+1000*j/299),round(center(c,100+1000*j/299))) for j in range(300)]
    pencil.line(samples,fill=col,width=1)
def errors(c,points):
    arr=np.asarray(points,dtype=float)
    dy=arr[:,1]-np.asarray([center(c,float(x)) for x in arr[:,0]])
    return float(np.sqrt(np.mean(dy*dy))),float(np.max(np.abs(dy)))
for c in (5,15):
    guides=[(float(x),center(c,x)) for x in (100.,600.,1100.)]
    length_at={}
    for step in (2.,5.,10.,15.,20.):
        candidate=propose(img,guides,radius=6,step=step,smoothness="Strong")
        rms,maxe=errors(c,candidate.points)
        assert rms<0.5 and maxe<1.1,(c,step,rms,maxe)
        assert candidate.points[0]==guides[0] and candidate.points[-1]==guides[-1]
        assert candidate.segment_count==2
        length_at[step]=len(candidate.points)
        sampled=sample_proposal_segments(candidate.segments,100)
        final=sampled[0]+sampled[1][1:]
        assert len(final)==100
        assert final[0]==guides[0] and final[-1]==guides[-1]
        assert sampled[0][-1]==guides[1]==sampled[1][0]
        rms100,maxe100=errors(c,final)
        assert rms100<0.5 and maxe100<1.1,(c,step,rms100,maxe100)
        print("Step",step,"c",c,"candidate",len(candidate.points),
              "reviewed_output",len(final),"RMS",round(rms,4),
              "output_RMS",round(rms100,4))
    assert length_at=={2.:503,5.:203,10.:103,15.:69,20.:53},length_at
    base=propose(img,guides,radius=6,step=20.,smoothness="Strong")
    for x,seg in ((420.,0),(720.,1)):
        target=(x,center(c,x))
        more,candidate=insert_correction(base,img,guides,seg,1,target,
                                         radius=6,step=20.,smoothness="Strong")
        assert len(more)==4 and len(candidate.segments)==3
        assert target==candidate.segments[seg][-1]==candidate.segments[seg+1][0]
        if seg==0:assert candidate.segments[-1]==base.segments[-1]
        else:assert candidate.segments[0]==base.segments[0]
        repaired=repair(candidate,img,more,seg,radius=6,step=20.,smoothness="Strong")
        assert len(repaired.segments)==3 and repaired.points[0]==guides[0]
        rms,maxe=errors(c,repaired.points)
        assert rms<.5 and maxe<1.1,(c,seg,rms,maxe)
for invalid in (0.49,20.01,float('inf'),float('nan')):
    guides=[(100.,822.),(600.,830.)]
    for fn in (lambda:samples_from_guides(guides,step=invalid),
               lambda:guide_curve_reference(guides,step=invalid),
               lambda:propose(img,guides,radius=6,step=invalid)):
        try:fn()
        except ValueError:pass
        else:raise AssertionError(("Expected invalid Step rejection",invalid))
print("PASS: Step 0.5..20 validation; synthetic family; corrections; 100-point output")
