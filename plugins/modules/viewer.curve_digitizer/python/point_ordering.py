# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-configuration scientific curve point ordering.

Ordered scientific coordinates are used after calibration. Source pixel
coordinates are only a provisional fallback before an accepted calibration.
Sorting is stable, so equal-X/equal-Y coordinates retain their prior order.
"""
import math

MODES = ('none', 'x', 'y')
SOURCES = ('insertion', 'x', 'y')


def normalize(policy):
    policy = policy if isinstance(policy, dict) else {}
    monotonic = policy.get('monotonicity', 'none')
    source = policy.get('source', 'insertion')
    if monotonic not in MODES or source not in SOURCES:
        raise ValueError('Invalid monotonicity / point ordering mode.')
    if monotonic != 'none' and source != monotonic:
        raise ValueError('A monotonic curve must be ordered by the same scientific axis.')
    return {'monotonicity': monotonic, 'source': source}


def order_points(points, policy, axis='x'):
    source = normalize(policy)['source']
    if source == 'insertion':
        return points
    def key(point):
        value = getattr(point, 'calibrated_' + source)
        if value is None or not math.isfinite(value):
            value = getattr(point, 'pixel_' + source)
            if source == 'y':
                value = -value  # upward scientific Y, provisional pre-calibration
        return value
    points.sort(key=key)
    return points


def order_series(series, policy):
    order_points(series.points, policy)


def order_project(project, policy):
    for series in project.series:
        order_series(series, policy)
