# SPDX-License-Identifier: GPL-3.0-or-later
"""Conservative data-only ImageMagick filter recommendation for raster tracing.

The score is a heuristic for visible features, NOT metrological fidelity or a
scientific quality score. It never modifies the image or publishes a Dataset.
All returned operations are validated by image_processing.normalize_operations.
"""
from __future__ import annotations
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance, ImageOps
from image_processing import normalize_operations


def _sample(image):
    out=image.convert('RGB')
    out.thumbnail((640,640),Image.Resampling.LANCZOS)
    return out


def _score(image):
    gray=np.asarray(image.convert('L'),dtype=np.float32)/255.
    h,w=gray.shape
    dy=np.abs(np.diff(gray,axis=0));dx=np.abs(np.diff(gray,axis=1))
    strength=np.concatenate((dy.ravel(),dx.ravel()))
    p=np.percentile(strength,[45,85,97])
    # Reward coherent mid-strength edges while suppressing noise and saturation.
    contrast=np.percentile(gray,95)-np.percentile(gray,5)
    saturated=float(((gray<.015)|(gray>.985)).mean())
    high_frequency=max(0,float(p[2]-p[1]))
    return float(1.3*p[1]+.6*contrast-.7*high_frequency-.16*saturated)


def recommend(image, *, preserve_color=True):
    """Return a validated, non-destructive suggestion plus its rationale.

    The candidates intentionally avoid threshold, heavy denoising, inversion,
    cropping, resampling, sharpening above 1 sigma and geometric changes.
    """
    source=_sample(image)
    arr=np.asarray(source,dtype=np.float32)
    channel_spread=float(np.mean(np.std(arr,axis=2)))
    g=source.convert('L')
    values=np.asarray(g,dtype=np.uint8)
    p5,p50,p95=np.percentile(values,[5,50,95])
    candidates=[]
    def add(label,ops,preview):
        candidates.append((label,normalize_operations(ops),_score(preview)))
    add('original',[],g)
    if p95-p5<185:
        add('auto levels',[{'kind':'auto_level','value':''}],ImageOps.autocontrast(g,cutoff=0))
    if p50>145:
        add('gentle gamma',[{'kind':'gamma','value':'0.9'}],g.point(lambda x:round(255*(x/255.)**(1/.9))))
    elif p50<95:
        add('gentle gamma',[{'kind':'gamma','value':'1.1'}],g.point(lambda x:round(255*(x/255.)**(1/1.1))))
    # PIL local contrast is only a proxy for ImageMagick CLAHE, never an exact
    # representation of the final processed image. The real pipeline is still
    # executed and previewed by the canonical ImageMagick subprocess.
    equal=ImageOps.equalize(g)
    blend=Image.blend(g,equal,.33)
    add('local contrast',[{'kind':'clahe','value':'8x8+128+2'}],blend)
    add('local contrast + gentle sharpening',[
        {'kind':'clahe','value':'8x8+128+2'}, {'kind':'sharpen','value':'0x0.7'}],
        blend.filter(ImageFilter.UnsharpMask(radius=.7,percent=45,threshold=4)))
    if p95-p5<150:
        stretched=ImageOps.autocontrast(g,cutoff=.7)
        add('auto levels + local contrast',[
            {'kind':'auto_level','value':''},{'kind':'clahe','value':'8x8+128+2'}],
            Image.blend(stretched,ImageOps.equalize(stretched),.30))
    scores=[v[2] for v in candidates]
    best_index=int(np.argmax(scores))
    # Do not recommend pointless changes when improvements are tiny.
    if best_index and scores[best_index]-scores[0]<.012:
        best_index=0
    name,operations,score=candidates[best_index]
    if not operations:
        # "Try" should still allow an explicitly visible, gentle candidate
        # if the baseline already has sufficient contrast.
        operations=[{'kind':'sharpen','value':'0x0.5'}]
        name='gentle sharpening (no clear automatic improvement detected)'
    # Multicolour traces need preservation: grayscale is never imposed.
    detail=f'Heuristic: {name}; source contrast p5–p95={p95-p5:.0f}/255, median={p50:.0f}/255; '
    detail+='colour information preserved.' if channel_spread>6 and preserve_color else 'no geometric transformation.'
    return normalize_operations(operations),detail
