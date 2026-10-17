# SPDX-License-Identifier: GPL-3.0-or-later
"""Deterministic arclength reduction of user-reviewed assisted trace proposals.

No fitting is performed here: the scientific proposal shape is retained and
only its sampling density is changed. Endpoints/guide constraints stay exact.
The output total counts shared guide endpoints exactly once.
"""
from __future__ import annotations

import math
import numpy as np


def sample_segment(points, total):
    """Sample a polyline to *total* vertices including exact endpoints."""
    if total < 2 or len(points) < 2:
        raise ValueError('Each proposed segment requires at least two points.')
    coords = np.asarray(points, dtype=float)
    if coords.ndim != 2 or coords.shape[1] != 2 or not np.isfinite(coords).all():
        raise ValueError('Proposed points must have finite X/Y values.')
    dist = np.linalg.norm(np.diff(coords, axis=0), axis=1)
    knots = np.concatenate(([0.0], np.cumsum(dist)))
    if knots[-1] <= 1e-9:
        raise ValueError('Cannot resample a zero-length trace segment.')
    stable = np.r_[True, np.diff(knots) > 1e-12]
    knots = knots[stable]
    coords = coords[stable]
    t = np.linspace(0.0, knots[-1], total)
    result = list(zip(np.interp(t, knots, coords[:, 0]),
                      np.interp(t, knots, coords[:, 1])))
    result[0] = tuple(map(float, points[0]))
    result[-1] = tuple(map(float, points[-1]))
    return result


def sample_proposal_segments(segments, total):
    """Return segment polylines totalling *total* unique proposal vertices.

    The available N-1 edges are allocated by largest remainder proportional
    to original geometric arclength; every segment gets at least one edge.
    Therefore every guide point remains a vertex and no interval disappears.
    """
    if not segments or any(len(s) < 2 for s in segments):
        raise ValueError('A proposal with valid segments is required.')
    total = int(total)
    if not len(segments) + 1 <= total <= 10000:
        raise ValueError(f'Output points must be between {len(segments)+1} and 10000.')
    lengths = np.asarray([sum(math.dist(a, b) for a, b in zip(s, s[1:]))
                          for s in segments], dtype=float)
    if not np.isfinite(lengths).all() or np.any(lengths < 1e-9):
        raise ValueError('Every guide interval must have nonzero finite length.')
    extra = total - 1 - len(segments)
    quotas = lengths / lengths.sum() * extra
    allocated = np.floor(quotas).astype(int)
    remaining = extra - int(allocated.sum())
    # Stable tie-breaking by original segment order.
    ranked = sorted(range(len(segments)), key=lambda i: (-(quotas[i] - allocated[i]), i))
    for i in ranked[:remaining]:
        allocated[i] += 1
    counts = [int(k) + 2 for k in allocated]  # one mandatory edge per interval
    output = [sample_segment(seg, n) for seg, n in zip(segments, counts)]
    assert sum(len(s) for s in output) - len(output) + 1 == total
    return output
