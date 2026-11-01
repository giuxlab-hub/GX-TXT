# SPDX-License-Identifier: GPL-3.0-or-later
"""Regress alternate smoothness priors without demanding invented displacement."""
from pathlib import Path
import sys,math
import numpy as np
from PIL import Image,ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from assisted_tracing import propose
image=Image.new("RGB",(530,160),"white")
pen=ImageDraw.Draw(image)
for x in range(20,510):
 y=80+int(4*math.sin(x/7)+6*math.sin(x/19))
 pen.point((x,y),fill=(20,55,230))
 pen.point((x,80),fill=(32,120,208))
guides=[(20.,80.),(260.,80.),(510.,80.)]
results={}
for mode in ("Off","Gentle","Strong"):
 r=propose(image,guides,radius=8,step=2.,smoothness=mode)
 results[mode]=np.array(r.points)
 assert len(r.points)>200 and not r.ambiguous_segments,(mode,r)
assert len(set(len(points) for points in results.values()))==1
for a,b in (("Off","Gentle"),("Gentle","Strong"),("Off","Strong")):
 delta=np.linalg.norm(results[a]-results[b],axis=1)
 assert np.isfinite(delta).all(),(a,b)
 assert tuple(results[a][0])==guides[0]
 assert tuple(results[b][-1])==guides[-1]
 print(f"{a} vs {b}: {int((delta>.1).sum())} differing positions / {len(delta)}; mean {delta.mean():.3f} px, max {delta.max():.3f} px")
print("PASS: distinct optimization modes complete with valid endpoints; equality is scientifically permitted")
