# SPDX-License-Identifier: GPL-3.0-or-later
"""Opt-in image-space priors for non-destructive assisted trace proposals."""
from __future__ import annotations
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SMOOTHNESS = {'Off': 0.0, 'Gentle': 0.13, 'Strong': 0.48}

def _slopes(t, v):
    v = np.asarray(v, dtype=float)
    h = np.diff(t); d = np.diff(v) / h
    m = np.zeros_like(v)
    if len(v) == 2:
        m[:] = d[0]
        return m
    for k in range(1, len(v)-1):
        if d[k-1] * d[k] > 0:
            w1 = 2*h[k]+h[k-1]; w2 = h[k]+2*h[k-1]
            m[k] = (w1+w2)/(w1/d[k-1]+w2/d[k])
    def endpoint(h0,h1,d0,d1):
        candidate = ((2*h0+h1)*d0-h0*d1)/(h0+h1)
        if candidate*d0 <= 0: return 0.0
        if d0*d1 < 0 and abs(candidate) > 3*abs(d0): return 3*d0
        return candidate
    m[0]=endpoint(h[0],h[1],d[0],d[1])
    m[-1]=endpoint(h[-1],h[-2],d[-1],d[-2])
    return m

def spline_points(nodes, spacing=1.25):
    """C1 chord-length Hermite spline that passes through all red X nodes."""
    a=np.asarray(nodes,dtype=float)
    if a.ndim!=2 or a.shape[1]!=2 or not 2<=len(a)<=200 or not np.isfinite(a).all():
        raise ValueError('Exclusion path must have 2..200 finite pixel nodes.')
    length=np.linalg.norm(np.diff(a,axis=0),axis=1)
    if np.any(length < 0.1) or spacing<=0:
        raise ValueError('Exclusion nodes must be distinct.')
    t=np.concatenate(([0.0],np.cumsum(length)))
    mx,my=_slopes(t,a[:,0]),_slopes(t,a[:,1])
    result=[]
    for i in range(len(a)-1):
        count=max(1,int(math.ceil(length[i]/spacing)))
        s=np.arange(count,dtype=float)/count
        h=length[i]
        p=((2*s**3-3*s**2+1)[:,None]*a[i]+
           (s**3-2*s**2+s)[:,None]*h*np.array([mx[i],my[i]])+
           (-2*s**3+3*s**2)[:,None]*a[i+1]+
           (s**3-s**2)[:,None]*h*np.array([mx[i+1],my[i+1]]))
        result.extend(map(tuple,p.tolist()))
    result.append(tuple(a[-1]))
    if len(result)>12000: raise ValueError('Exclusion spline exceeds the bounded raster sampling.')
    return result

def exclusion_penalty(image_size, paths, width=6):
    """Rasterize a separate soft cost image, never changing the source raster."""
    if not paths: return None
    w,h=image_size
    if not 1<=int(width)<=40 or len(paths)>16:
        raise ValueError('Exclusion width/count is out of range.')
    canvas=Image.new('L',(w,h),0)
    painter=ImageDraw.Draw(canvas)
    for nodes in paths:
        if len(nodes)<2: continue
        points=spline_points(nodes)
        if any(not (0<=x<w and 0<=y<h) for x,y in points):
            raise ValueError('Exclusion spline leaves the source image.')
        painter.line([(int(round(x)),int(round(y))) for x,y in points],
                     fill=255,width=2*int(width)+1,joint='curve')
    return np.asarray(canvas.filter(ImageFilter.GaussianBlur(1.25)),dtype=np.float32)/255.

def second_order_indices(unary, radius, smoothness):
    """Banded second-order DP for offset changes with fixed guide endpoints."""
    lam=SMOOTHNESS.get(smoothness)
    if lam is None or smoothness=='Off': raise ValueError('Smoothness must be Gentle or Strong.')
    n,k=unary.shape
    if k!=2*radius+1 or n<2: raise ValueError('Malformed trace state dimensions.')
    if n*k*k > 3000000:
        raise ValueError('Smooth prior state is too large; narrow Corridor or increase Step.')
    costs=np.full((k,k),np.inf,dtype=float)
    history=np.full((n,k,k),-1,dtype=np.int16)
    center=radius
    if not np.isfinite(unary[0,center]): return None
    for b in range(max(0,center-4),min(k,center+5)):
        d=b-center
        costs[center,b]=unary[0,center]+unary[1,b]+.16*(abs(d)/max(radius,1))**2+.025*abs(d)
    for i in range(2,n):
        curr=np.full((k,k),np.inf,dtype=float)
        for b in range(k):
            past=np.arange(max(0,b-4),min(k,b+5))
            if not len(past): continue
            for c in range(max(0,b-4),min(k,b+5)):
                d=c-b
                candidate=costs[past,b]+lam*(c-2*b+past)**2
                candidate+=.16*(abs(d)/max(radius,1))**2+.025*abs(d)
                arg=int(np.argmin(candidate))
                if np.isfinite(candidate[arg]) and np.isfinite(unary[i,c]):
                    curr[b,c]=candidate[arg]+unary[i,c]
                    history[i,b,c]=int(past[arg])
        costs=curr
    c=center;b=int(np.argmin(costs[:,c]))
    if not np.isfinite(costs[b,c]): return None
    path=[c,b]
    for i in range(n-1,1,-1):
        a=int(history[i,b,c])
        if a<0:return None
        path.append(a);c,b=b,a
    path.reverse()
    return path
