# SPDX-License-Identifier: GPL-3.0-or-later
"""Conservative, click-guided scale bar detection; never silently accepts a guess.

This helper does not edit image pixels or the source Dataset. If contrast cannot
isolate a long, approximately horizontal straight segment near the click, the
caller must ask the user to select its two endpoints manually.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
import numpy as np
from PIL import Image


class ScaleDetectionError(ValueError):
    pass


@dataclass(frozen=True)
class ScaleDetection:
    start: tuple[float, float]
    end: tuple[float, float]
    contrast: float
    pixels: float
    polarity: str


def _run_containing(mask: np.ndarray, index: int):
    """Run around a foreground pixel; bridge at most two isolated missing px."""
    n = len(mask)
    if not mask[index]:
        return None
    left = right = index
    gap = 0
    while left > 0:
        if mask[left - 1]:
            left -= 1
            gap = 0
        elif gap < 2:
            left -= 1
            gap += 1
        else:
            left += gap
            break
    gap = 0
    while right < n - 1:
        if mask[right + 1]:
            right += 1
            gap = 0
        elif gap < 2:
            right += 1
            gap += 1
        else:
            right -= gap
            break
    return left, right


def _terminal_tick_extent(image: Image.Image, end_x: float, shaft_y: float,
                          *, left_end: bool) -> tuple[float, float]:
    """Estimate the two outside edges of an upright SEM scale-bar terminal tick.

    Rejects candidates without a distinct vertical segment beyond the horizontal
    shaft. Only local pixels around the previously detected horizontal endpoint
    are inspected. The endpoints are never inferred from the printed scale label.
    """
    width, height = image.size
    cx, cy = int(round(end_x)), int(round(shaft_y))
    x0, x1 = max(0, cx-13), min(width, cx+14)
    y0, y1 = max(0, cy-15), min(height, cy+16)
    if x1 - x0 < 12 or y1-y0 < 21:
        raise ScaleDetectionError("Scale-bar terminal ticks are too close to the image boundary. Use two endpoints.")
    rgb = np.asarray(image.crop((x0,y0,x1,y1)).convert('RGB'), dtype=np.float32)
    local_y = cy-y0
    sample_x = cx + (6 if left_end else -6)
    sample_x = min(max(sample_x, x0), x1-1)-x0
    foreground = np.median(rgb[max(0,local_y-1):min(len(rgb),local_y+2),
                              max(0,sample_x-1):min(x1-x0,sample_x+2),:], axis=(0,1))
    bands=[]
    if local_y >= 10:
        bands.append(rgb[max(0,local_y-14):local_y-9,:,:])
    if local_y+14 < len(rgb):
        bands.append(rgb[local_y+10:min(len(rgb),local_y+15),:])
    if not bands:
        raise ScaleDetectionError("Cannot determine the local tick background. Use two endpoints.")
    background=np.median(np.concatenate(bands,axis=0),axis=(0,1))
    difference=foreground-background
    contrast=float(np.linalg.norm(difference))
    if contrast<45:
        raise ScaleDetectionError("Terminal ticks have insufficient contrast. Use two endpoints.")
    signal=(rgb-background)@(difference/contrast)
    mask=signal>=max(32.0,contrast*0.48)
    # Above and below the shaft, not the shaft itself. This prevents the shaft
    # from being mistaken for the vertical terminal tick.
    valid=np.ones(mask.shape[0],dtype=bool)
    valid[max(0,local_y-2):min(mask.shape[0],local_y+3)]=False
    counts=mask[valid].sum(axis=0)
    target=np.arange(x0,x1)
    near=np.abs(target-end_x)<=10
    peak=int(np.max(counts[near])) if np.any(near) else 0
    if peak<4:
        raise ScaleDetectionError("Terminal tick center cannot be identified. Select two endpoints manually.")
    required=max(4,int(round(peak*0.60)))
    good=near & (counts>=required)
    groups=[]
    start=None
    for i,ok in enumerate(list(good)+[False]):
        if ok and start is None:
            start=i
        elif not ok and start is not None:
            groups.append((start,i-1))
            start=None
    if not groups:
        raise ScaleDetectionError("Terminal tick center is ambiguous. Select two endpoints manually.")
    groups.sort(key=lambda g:(abs(((g[0]+g[1])/2+x0)-end_x),-(g[1]-g[0])))
    lo,hi=groups[0]
    if hi-lo>9:
        raise ScaleDetectionError("Terminal tick is too broad for a reliable center. Use two endpoints.")
    return float(x0+lo),float(x0+hi)


def detect_scale_bar(image: Image.Image, x: float, y: float, *, edge_mode: str = "center") -> ScaleDetection:
    """Return a candidate bar if local, relative brightness separates it clearly.

    Supports light/dark/colored bars and adaptive background contrast. Click somewhere on the long horizontal shaft, not label.
    There is intentionally no whole-image blind guess or automatic commitment.
    """
    width, height = image.size
    ix, iy = int(round(x)), int(round(y))
    if not 0 <= ix < width or not 0 <= iy < height or width < 35 or height < 35:
        raise ScaleDetectionError('Click inside the image on the scale bar.')
    margin = max(7, min(20, height // 28))
    if iy - margin < 0 and iy + margin >= height:
        raise ScaleDetectionError('Not enough surrounding image for scale detection. Use two endpoints.')
    search = min(width - 1, max(35, int(width * 0.75)))
    x0 = max(0, ix - search)
    x1 = min(width, ix + search + 1)
    y0 = max(0, iy-margin-6)
    y1 = min(height, iy+margin+7)
    # Crop before array conversion: even large SEM rasters cost only O(bar ROI)
    # memory, not O(entire image). RGB detects equal-luminance different hues.
    rgb = np.asarray(image.crop((x0, y0, x1, y1)).convert('RGB'), dtype=np.float32)
    backgrounds = []
    if iy - margin >= 0:
        backgrounds.append(rgb[iy-margin-y0:iy-margin//2-y0].mean(axis=0))
    if iy + margin < height:
        backgrounds.append(rgb[iy+margin//2-y0:iy+margin-y0].mean(axis=0))
    background = np.median(np.stack(backgrounds), axis=0)
    candidates = []
    for row in range(max(0, iy - 5), min(height, iy + 6)):
        difference = rgb[row-y0] - background
        lo, hi = max(0, ix-x0-2), min(x1-x0, ix-x0+3)
        # The color vector between bar and local background provides an
        # adaptive contrast projection, including colored or dark bars.
        direction = np.median(difference[lo:hi], axis=0)
        strength = float(np.linalg.norm(direction))
        if strength < 40:
            continue
        direction = direction / strength
        signal = difference @ direction
        local_contrast = float(np.max(signal[lo:hi]))
        if local_contrast < 38:
            continue
        threshold = max(30.0, min(95.0, local_contrast * 0.55))
        mask = signal >= threshold
        offsets = (0, -1, 1, -2, 2, -3, 3)
        found = None
        for off in offsets:
            center = ix - x0 + off
            if 0 <= center < len(mask) and mask[center]:
                found = _run_containing(mask, center)
                if found:
                    break
        if not found:
            continue
        a, b = found
        length = b-a
        if length < max(12, 0.018*width) or length > 0.75*width:
            continue
        surrounding_y = row + (7 if row+7 < height else -7)
        surrounding = float(np.median((rgb[surrounding_y-y0, a:b+1] - background[a:b+1]) @ direction))
        if surrounding > threshold * 0.7:
            continue
        if (x0+a <= 1 or x0+b >= width-2) and length > width*0.45:
            continue
        score = length * (min(local_contrast, 310)/310)**0.25
        luminance_direction = float(np.dot(direction, [0.2126, 0.7152, 0.0722]))
        polarity = 'light' if luminance_direction > 0.16 else 'dark' if luminance_direction < -0.16 else 'colored'
        candidates.append((score, (float(x0+a), float(row)), (float(x0+b), float(row)), local_contrast, polarity))
    if not candidates:
        raise ScaleDetectionError('No distinct horizontal scale bar was detected near the click. Use two endpoints.')
    candidates.sort(reverse=True, key=lambda c: c[0])
    chosen = candidates[0]
    # Rows of the same bar may vary. If two different lengths are equally
    # plausible, decline a false-precision result rather than guessing.
    for contender in candidates[1:]:
        if contender[0] > chosen[0] * 0.89 and (abs(contender[1][0]-chosen[1][0]) > 5 or abs(contender[2][0]-chosen[2][0]) > 5):
            raise ScaleDetectionError('Multiple possible scale bar edges detected. Use two endpoints.')
    if edge_mode not in ("center", "inner", "outer"):
        raise ScaleDetectionError("Unknown scale-bar tick-reference convention.")
    left = _terminal_tick_extent(image, chosen[1][0], chosen[1][1], left_end=True)
    right = _terminal_tick_extent(image, chosen[2][0], chosen[2][1], left_end=False)
    if edge_mode == "center":
        ax,bx=sum(left)/2,sum(right)/2
    elif edge_mode == "inner":
        ax,bx=max(left),min(right)
    else:
        ax,bx=min(left),max(right)
    if bx-ax<3:
        raise ScaleDetectionError("Detected terminal ticks overlap. Select two endpoints manually.")
    start=(float(ax),float(chosen[1][1]))
    end=(float(bx),float(chosen[2][1]))
    return ScaleDetection(start, end, chosen[3],
                          math.dist(start, end), chosen[4])
