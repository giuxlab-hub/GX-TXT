# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-curve raster ink-width diagnostics; no uncertainty propagation or CORE I/O."""
from __future__ import annotations
import math
import numpy as np
from PIL import Image
from assisted_constraints import spline_points

def _normal_profile(gray, x, y, nx, ny, radius=12, step=0.5):
    h,w=gray.shape
    ts=np.arange(-radius,radius+step/2,step,dtype=float)
    px=x+nx*ts; py=y+ny*ts
    if np.min(px)<0 or np.max(px)>=w-1 or np.min(py)<0 or np.max(py)>=h-1:
        return None,None
    x0=np.floor(px).astype(int); y0=np.floor(py).astype(int)
    a=px-x0; b=py-y0
    z=(gray[y0,x0]*(1-a)*(1-b)+gray[y0,x0+1]*a*(1-b)+
       gray[y0+1,x0]*(1-a)*b+gray[y0+1,x0+1]*a*b)
    return ts,z

def automatic_width(image, raster_points, *, radius=12, maximum_samples=100):
    """Estimate full stroke thickness normal to an accepted trace from source ink.
    Excludes gradients, merged strokes and insufficient local contrast.
    Returns descriptive widths in ORIGINAL raster pixels, never statistical σ.
    """
    if not 2<=int(radius)<=40:raise ValueError('Probe radius must be 2..40 px.')
    a=np.asarray(raster_points,dtype=float)
    if a.ndim!=2 or a.shape[1]!=2 or len(a)<3 or not np.isfinite(a).all():
        raise ValueError('Select a curve with at least three valid accepted points.')
    gray=np.asarray(image.convert('L'),dtype=float)/255.
    chosen=np.unique(np.linspace(1,len(a)-2,min(len(a)-2,maximum_samples),dtype=int))
    widths=[];positions=[];rejected=0
    for i in chosen:
        direction=a[i+1]-a[i-1]
        n=np.linalg.norm(direction)
        if n<1e-7:rejected+=1;continue
        nx,ny=-direction[1]/n,direction[0]/n
        t,z=_normal_profile(gray,*a[i],nx,ny,radius)
        if z is None:rejected+=1;continue
        edges=np.r_[z[:max(3,int(.18*len(z)))],z[-max(3,int(.18*len(z))):]]
        bg=float(np.median(edges))
        central=np.flatnonzero(abs(t)<=1.)
        if not len(central):rejected+=1;continue
        dark=bg-float(np.min(z[central]))
        bright=float(np.max(z[central]))-bg
        ink='dark' if dark>=bright else 'bright'
        contrast=max(dark,bright)
        if contrast<.14:rejected+=1;continue
        contrast_signal=(bg-z) if ink=='dark' else (z-bg)
        boundary=contrast*.5
        center=int(central[np.argmax(contrast_signal[central])])
        left=center;right=center
        while left>0 and contrast_signal[left-1]>=boundary:left-=1
        while right+1<len(z) and contrast_signal[right+1]>=boundary:right+=1
        if left==0 or right==len(z)-1:rejected+=1;continue
        width=float(t[right]-t[left]+.5)
        if not .75<=width<=min(2*radius-1,20):rejected+=1;continue
        # Flag a secondary high-contrast branch rather than treating a merged ink field
        # as an exact localization estimate.
        far=np.abs(t-t[center])>max(width*1.4,2.)
        if np.any(contrast_signal[far]>=.70*contrast):
            rejected+=1;continue
        widths.append(width)
        positions.append([float(a[i,0]),float(a[i,1]),width])
    if not widths:raise ValueError('No reliable cross-sections; try manual boundaries or another probe radius.')
    return {'method':'automatic','width_px':float(np.median(widths)),
            'min_px':float(np.min(widths)),'max_px':float(np.max(widths)),
            'iqr_px':float(np.subtract(*np.percentile(widths,[75,25]))),
            'accepted_samples':len(widths),'rejected_samples':rejected,
            'total_samples':len(chosen),'samples':positions}

def manual_width(edge_a,edge_b,*,samples=101):
    """Descriptive distance between two deliberately drawn, directed raster-edge splines."""
    aa=np.asarray(spline_points(edge_a,spacing=1),dtype=float)
    bb=np.asarray(spline_points(edge_b,spacing=1),dtype=float)
    def resample(q):
        d=np.linalg.norm(np.diff(q,axis=0),axis=1)
        t=np.r_[0,np.cumsum(d)]
        if t[-1]<2:raise ValueError('Boundary length is too short.')
        return np.column_stack([np.interp(np.linspace(0,t[-1],samples),t,q[:,j])
                                for j in (0,1)])
    a=resample(aa);b=resample(bb)
    center=(a+b)/2.
    tangent=np.gradient(center,axis=0)
    magnitude=np.linalg.norm(tangent,axis=1)
    if np.any(magnitude<1.e-8):raise ValueError('Boundary pair has a degenerate centerline.')
    normal=np.column_stack((-tangent[:,1],tangent[:,0]))/magnitude[:,None]
    signed=np.sum((b-a)*normal,axis=1)
    widths=np.abs(signed)
    if np.any(widths<.05) or (np.min(signed)<0 and np.max(signed)>0):
        raise ValueError('Boundary splines intersect, reverse side, or coincide.')
    return {'method':'manual','width_px':float(np.median(widths)),
            'min_px':float(np.min(widths)),'max_px':float(np.max(widths)),
            'iqr_px':float(np.subtract(*np.percentile(widths,[75,25]))),
            'accepted_samples':int(samples),'rejected_samples':0,'total_samples':int(samples),
            'samples':[[float(a[i,0]),float(a[i,1]),float(widths[i])]
                       for i in range(0,len(widths),max(1,len(widths)//25))]}
