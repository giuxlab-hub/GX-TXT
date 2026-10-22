# SPDX-License-Identifier: GPL-3.0-or-later
"""Image-constrained, operator-guided trace *proposals*.

The raster image remains immutable. The tracing implementation has no access to
Dataset publication or scientific point mutation. Only an explicit Curves-tab
Accept operation may promote a proposal to scientific points.

The optional GX-TXT NUMERIC_API_v1 fit is consumed as an advisory centerline;
the public API adapter lives in api/curve_digitizer_viewer_api_v1.tcl. No CORE
internal numerical functions or C/X11 backend are imported here.
"""
from __future__ import annotations
from dataclasses import dataclass, field
import math
import numpy as np
from PIL import Image
from assisted_constraints import exclusion_penalty, second_order_indices

Point = tuple[float, float]

@dataclass
class TraceProposal:
    points: list[Point]
    segment_count: int
    guidance: str
    mean_cost: float
    segments: list[list[Point]] = field(default_factory=list)
    segment_costs: list[float] = field(default_factory=list)
    # This is a diagnostic, not a calibrated scientific confidence or accuracy.
    ambiguous_segments: list[int] = field(default_factory=list)


def samples_from_guides(guides, *, step=2.0):
    if len(guides) < 2:
        raise ValueError('At least two guide points are required.')
    result = []
    for a,b in zip(guides,guides[1:]):
        length = math.dist(a,b)
        if length < 0.5:
            raise ValueError('Guide points must be separated by at least 0.5 pixel.')
        n = max(1, int(math.ceil(length/step)))
        for i in range(n):
            t=i/n
            result.append((float(a[0]*(1-t)+b[0]*t),float(a[1]*(1-t)+b[1]*t)))
    result.append(tuple(map(float,guides[-1])))
    return result


def _feature_maps(image):
    """Generate reusable image features without depending on OpenCV/scikit-image.

    Grid suppressor detects sparse, long, axis-aligned dark rows/columns; it is
    disabled for photograph-like images with broadly dark backgrounds. A mild
    gaussian luminance field makes local contrast sampling more stable.
    """
    rgb=np.asarray(image.convert('RGB'),dtype=np.float32)
    gray=(.299*rgb[:,:,0]+.587*rgb[:,:,1]+.114*rgb[:,:,2])/255.0
    h,w=gray.shape
    low,mid=np.percentile(gray,[15,55])
    dark=gray<min(.40,float(low+.055))
    row_strength=dark.mean(axis=1)
    col_strength=dark.mean(axis=0)
    rr=(row_strength>.40) & (row_strength>np.median(row_strength)+.24)
    cc=(col_strength>.40) & (col_strength>np.median(col_strength)+.24)
    if rr.mean()>.20: rr[:]=False
    if cc.mean()>.20: cc[:]=False
    grid=np.zeros((h,w),dtype=np.float32)
    if rr.any() or cc.any():
        grid[rr,:]=1.
        grid[:,cc]=1.
        # Slightly broaden printed grid lines without changing raster geometry.
        for shift in (-1,1):
            if rr.any(): grid[max(0,shift):h+min(0,shift),:]=np.maximum(grid[max(0,shift):h+min(0,shift),:],grid[max(0,-shift):h+min(0,-shift),:]*.55)
            if cc.any(): grid[:,max(0,shift):w+min(0,shift)]=np.maximum(grid[:,max(0,shift):w+min(0,shift)],grid[:,max(0,-shift):w+min(0,-shift)]*.55)
    return gray, rgb/255., grid


def _normal_contrast(gray,px,py,normals):
    """Local ridge response across the predicted tangent (dark or bright ink)."""
    h,w=gray.shape
    normal_x=np.rint(normals[:,0]*3).astype(int)[:,None]
    normal_y=np.rint(normals[:,1]*3).astype(int)[:,None]
    side1=gray[np.clip(py+normal_y,0,h-1),np.clip(px+normal_x,0,w-1)]
    side2=gray[np.clip(py-normal_y,0,h-1),np.clip(px-normal_x,0,w-1)]
    center=gray[py,px]
    return np.clip(np.maximum((side1+side2)*.5-center,center-(side1+side2)*.5)*2.0,0,1)


def _segment(image_features, a:Point, b:Point, reference, radius:int, match_strength:float,
             smoothness='Off', avoid_cost=None):
    """Bounded dynamic programming with colour, oriented line and grid costs.

    One full guide interval is optimized at once; fixed endpoints are guaranteed.
    Candidate positions lie on normals to the reference centerline. A small
    inter-column displacement cost discourages jumping between nearby traces.
    """
    gray,rgb,grid=image_features
    h,w=gray.shape
    ref=np.asarray(reference,dtype=np.float64)
    n=len(ref)
    if n<3:return [a,b],0.,False
    offsets=np.arange(-radius,radius+1,dtype=np.float64)
    nstates=len(offsets)
    tangents=np.gradient(ref,axis=0)
    tangent_norm=np.linalg.norm(tangents,axis=1)
    tangents=tangents/np.maximum(tangent_norm[:,None],1e-8)
    normals=np.stack([-tangents[:,1],tangents[:,0]],axis=1)
    coords=ref[:,None,:]+offsets[None,:,None]*normals[:,None,:]
    px=np.rint(coords[:,:,0]).astype(int);py=np.rint(coords[:,:,1]).astype(int)
    valid=(px>=0)&(py>=0)&(px<w)&(py<h)
    px=np.clip(px,0,w-1);py=np.clip(py,0,h-1)
    base=gray[py,px]
    targets=[];rgb_targets=[]
    for x,y in (a,b):
        ix=int(round(x));iy=int(round(y))
        x0=max(0,ix-1);x1=min(w,ix+2);y0=max(0,iy-1);y1=min(h,iy+2)
        targets.append(float(np.median(gray[y0:y1,x0:x1])))
        rgb_targets.append(np.median(rgb[y0:y1,x0:x1].reshape(-1,3),axis=0))
    t=np.linspace(0,1,n)[:,None]
    expected=(1-t)*targets[0]+t*targets[1]
    color_expected=((1-t[:,:,None])*rgb_targets[0]+t[:,:,None]*rgb_targets[1])
    gray_diff=np.abs(base-expected)
    rgb_diff=np.sqrt(np.mean((rgb[py,px]-color_expected)**2,axis=2))
    ridge=_normal_contrast(gray,px,py,normals)
    grid_penalty=grid[py,px]
    # The reference is advice, not a constraint. A grid line is penalized, not
    # forbidden, because the correct curve may legitimately cross it.
    unary=(.45*gray_diff+.40*rgb_diff+.55*(1.-ridge)+.65*grid_penalty)*match_strength
    unary+=.20*(offsets[None,:]/max(1,radius))**2
    if avoid_cost is not None:
        unary+=2.4*avoid_cost[py,px]
    unary[~valid]=np.inf
    unary[0,:]=np.inf;unary[0,radius]=0.
    unary[-1,:]=np.inf;unary[-1,radius]=0.
    if smoothness != 'Off':
        indices=second_order_indices(unary,radius,smoothness)
        if indices is None:
            return [tuple(map(float,p)) for p in ref],float('nan'),True
        path=[(float(coords[i,k,0]),float(coords[i,k,1])) for i,k in enumerate(indices)]
        path[0]=a;path[-1]=b
        mean=float(np.mean([unary[i,k] for i,k in enumerate(indices)]))
        return path,mean,bool(mean>0.65)
    costs=np.full((n,nstates),np.inf,dtype=np.float64)
    prev=np.full((n,nstates),-1,dtype=np.int16)
    costs[0,radius]=0.
    # Banded transition, vectorized over candidate offsets. Complexity scales
    # with O(samples * corridor_width * band), not full-image graph area.
    for i in range(1,n):
        for delta in range(-4,5):
            to_start=max(0,-delta);to_end=min(nstates,nstates-delta)
            if to_end<=to_start:continue
            to=np.arange(to_start,to_end)
            fr=to+delta
            score=costs[i-1,fr]+(.16*(abs(delta)/max(1,radius))**2+.025*abs(delta))
            improve=score<costs[i,to]
            sel=to[improve]
            costs[i,sel]=score[improve];prev[i,sel]=fr[improve]
        costs[i]+=unary[i]
    if not np.isfinite(costs[-1,radius]):
        return [tuple(map(float,p)) for p in ref],float('nan'),True
    index=radius;path=[];line_values=[]
    for i in range(n-1,-1,-1):
        path.append((float(coords[i,index,0]),float(coords[i,index,1])))
        line_values.append(float(unary[i,index]) if np.isfinite(unary[i,index]) else 0.)
        if i:index=int(prev[i,index])
    path.reverse();path[0]=a;path[-1]=b
    mean=float(np.mean(line_values))
    # A high image cost marks possible ambiguity, not a confidence percentile.
    return path,mean,bool(mean>0.65)


def compose_segments(segments):
    return [p for i,segment in enumerate(segments) for p in (segment if i==0 else segment[1:])]


def propose(image, guides, *, radius=8, step=2.0, snap_strength=1.0, reference=None,
            smoothness='Off', exclusions=(), exclusion_width=6):
    if not 2<=len(guides)<=500:raise ValueError('Provide between 2 and 500 guide points.')
    if not 1<=radius<=40 or not .5<=step<=10:raise ValueError('Invalid tracing radius/step.')
    points=[(float(x),float(y)) for x,y in guides]
    w,h=image.size
    for x,y in points:
        if not(math.isfinite(x) and math.isfinite(y)) or not(0<=x<w and 0<=y<h):
            raise ValueError('Guide point outside image bounds.')
    linear=samples_from_guides(points,step=step)
    fitted=None
    if reference is not None:
        candidate=[tuple(map(float,p)) for p in reference]
        if len(candidate)==len(linear) and all(0<=x<w and 0<=y<h for x,y in candidate):
            fitted=candidate
    features=_feature_maps(image)
    avoid=exclusion_penalty(image.size,exclusions,exclusion_width)
    segments=[];costs=[];ambiguous=[]
    pos=0
    for i,(a,b) in enumerate(zip(points,points[1:])):
        count=max(1,int(math.ceil(math.dist(a,b)/step)))
        segment_ref=linear[pos:pos+count+1]
        if fitted:
            curve_ref=fitted[pos:pos+count+1]
            # Let the fit represent curved segments; only reject pathological
            # excursions far outside a physically plausible local corridor.
            if max(math.dist(x,y) for x,y in zip(segment_ref,curve_ref))<=max(4*radius,60):
                segment_ref=curve_ref.copy()
                segment_ref[0],segment_ref[-1]=a,b
        path,cost,ambiguity=_segment(features,a,b,segment_ref,radius,snap_strength,
                                      smoothness=smoothness,avoid_cost=avoid)
        segments.append(path);costs.append(cost)
        if ambiguity or not math.isfinite(cost):ambiguous.append(i)
        pos+=count
    paths=compose_segments(segments)
    if len(paths)>10000:raise ValueError('Proposal exceeds 10,000 points; add closer guides or increase the step.')
    return TraceProposal(paths,len(segments),'core_numeric' if fitted else 'local_linear',
                         float(np.mean([v for v in costs if math.isfinite(v)])) if any(math.isfinite(v) for v in costs) else float('nan'),
                         segments,costs,ambiguous)


def repair(proposal, image, guides, changed_segment, *, radius=8,step=2.0,
           smoothness='Off', exclusions=(), exclusion_width=6):
    """Recalculate only a changed guide interval; other segments remain exact."""
    if not 0<=changed_segment<len(guides)-1:raise ValueError('Invalid guide interval.')
    old=proposal.segments
    if len(old)!=len(guides)-1:raise ValueError('Proposal/guide topology mismatch.')
    a,b=guides[changed_segment:changed_segment+2]
    ref=samples_from_guides([a,b],step=step)
    path,cost,ambiguous=_segment(_feature_maps(image),a,b,ref,radius,1.0,
                                  smoothness=smoothness,
                                  avoid_cost=exclusion_penalty(image.size,exclusions,exclusion_width))
    segments=[list(s) for s in old];segments[changed_segment]=path
    costs=list(proposal.segment_costs);costs[changed_segment]=cost
    ambiguity=[i for i in proposal.ambiguous_segments if i!=changed_segment]
    if ambiguous:ambiguity.append(changed_segment)
    merged=compose_segments(segments)
    if len(merged)>10000:raise ValueError('Proposal exceeds 10,000 points.')
    vals=[v for v in costs if math.isfinite(v)]
    return TraceProposal(merged,len(segments),'local_recalculation',float(np.mean(vals)) if vals else float('nan'),segments,costs,sorted(ambiguity))


def insert_correction(proposal,image,guides,segment_index, point_index,point,*,radius=8,step=2.0,
                      smoothness='Off', exclusions=(), exclusion_width=6):
    """Insert a locked operator guide; only the split interval is searched again."""
    if not 0<=segment_index<len(proposal.segments):raise ValueError('Invalid proposal segment.')
    curve=proposal.segments[segment_index]
    # A two-point generated span may still have a strongly curved true route;
    # allow a far operator guide to split it even without internal vertices.
    if len(curve)>2 and not 0<point_index<len(curve)-1:
        raise ValueError('Correction must lie inside a segment.')
    if len(curve)==2 and point_index not in (0,1):
        raise ValueError('Invalid correction anchor.')
    guides=list(guides);guides.insert(segment_index+1,tuple(map(float,point)))
    a,b,c=guides[segment_index:segment_index+3]
    feats=_feature_maps(image)
    avoid=exclusion_penalty(image.size,exclusions,exclusion_width)
    paths=[];costs=[];amb=[]
    for s,(u,v) in enumerate([(a,b),(b,c)]):
        path,cost,flag=_segment(feats,u,v,samples_from_guides([u,v],step=step),radius,1.,
                                smoothness=smoothness,avoid_cost=avoid)
        paths.append(path);costs.append(cost)
        if flag:amb.append(segment_index+s)
    segs=proposal.segments[:segment_index]+paths+proposal.segments[segment_index+1:]
    cs=proposal.segment_costs[:segment_index]+costs+proposal.segment_costs[segment_index+1:]
    ambiguous=[i if i<segment_index else i+1 for i in proposal.ambiguous_segments if i!=segment_index]
    ambiguous+=amb
    out=TraceProposal(compose_segments(segs),len(segs),'local_correction',float(np.mean([v for v in cs if math.isfinite(v)])),segs,cs,sorted(set(ambiguous)))
    return guides,out


def remove_guide(proposal,image,guides,guide_index,*,radius=8,step=2.0,
                 smoothness='Off', exclusions=(), exclusion_width=6):
    """Remove an interior guide and re-optimize ONLY its merged interval.

    Raster geometry and all unaffected proposal intervals are preserved. This
    function never touches the scientific curve, accepted points, or CORE.
    """
    if not 0<guide_index<len(guides)-1:
        raise ValueError('Only interior guide points can be removed.')
    if len(proposal.segments)!=len(guides)-1:
        raise ValueError('Proposal and guide count do not agree.')
    new_guides=guides[:guide_index]+guides[guide_index+1:]
    merged=propose(image,[guides[guide_index-1],guides[guide_index+1]],radius=radius,step=step,
                   smoothness=smoothness,exclusions=exclusions,exclusion_width=exclusion_width)
    segs=proposal.segments[:guide_index-1]+merged.segments+proposal.segments[guide_index+1:]
    costs=proposal.segment_costs[:guide_index-1]+merged.segment_costs+proposal.segment_costs[guide_index+1:]
    ambiguous=[i if i<guide_index-1 else i-1 for i in proposal.ambiguous_segments
               if i not in (guide_index-1,guide_index)]
    if merged.ambiguous_segments:ambiguous.append(guide_index-1)
    valid_costs=[v for v in costs if math.isfinite(v)]
    result=TraceProposal(compose_segments(segs),len(segs),'local_guide_removal',
                         float(np.mean(valid_costs)) if valid_costs else float('nan'),
                         segs,costs,sorted(set(ambiguous)))
    return new_guides,result
