# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np

CORNER_ORDER = ("bottom_left", "bottom_right", "top_left", "top_right")
DEST = {
    "bottom_left": (0.0, 0.0),
    "bottom_right": (1.0, 0.0),
    "top_left": (0.0, 1.0),
    "top_right": (1.0, 1.0),
}


def _finite(value) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def _axis_diagnostics(axis_name: str, data: dict) -> list[dict]:
    out = []
    label = str(data.get("name", axis_name.upper()))
    scale = str(data.get("scale", "linear")).lower()
    minimum = data.get("minimum")
    maximum = data.get("maximum")
    valid_numeric = _finite(minimum) and _finite(maximum)
    if not valid_numeric:
        out.append({"severity": "error", "code": f"{axis_name}_range_nonfinite", "message": f"{label}: axis minimum/maximum must be finite numeric values."})
        return out
    lo, hi = float(minimum), float(maximum)
    if hi <= lo:
        out.append({"severity": "error", "code": f"{axis_name}_range_order", "message": f"{label}: maximum must be greater than minimum."})
    else:
        out.append({"severity": "ok", "code": f"{axis_name}_range", "message": f"{label}: range is valid ({lo:g} … {hi:g})."})
    if scale not in {"linear", "log"}:
        out.append({"severity": "error", "code": f"{axis_name}_scale", "message": f"{label}: unsupported scale mode {scale!r}."})
    elif scale == "log" and (lo <= 0.0 or hi <= 0.0):
        out.append({"severity": "error", "code": f"{axis_name}_log_domain", "message": f"{label}: logarithmic axes require strictly positive limits."})
    else:
        out.append({"severity": "ok", "code": f"{axis_name}_scale", "message": f"{label}: {scale} scale domain is valid."})
    return out


def _polygon_area(points: list[tuple[float, float]]) -> float:
    s = 0.0
    for i, (x1, y1) in enumerate(points):
        x2, y2 = points[(i + 1) % len(points)]
        s += x1 * y2 - x2 * y1
    return 0.5 * s


def _cross(a, b, c) -> float:
    return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])


def _orientation(a, b, c, eps=1e-12):
    v = _cross(a, b, c)
    if abs(v) <= eps:
        return 0
    return 1 if v > 0 else -1


def _on_segment(a, b, c, eps=1e-12):
    return (min(a[0], c[0])-eps <= b[0] <= max(a[0], c[0])+eps and
            min(a[1], c[1])-eps <= b[1] <= max(a[1], c[1])+eps)


def _segments_intersect(a, b, c, d) -> bool:
    o1, o2, o3, o4 = (_orientation(a,b,c), _orientation(a,b,d), _orientation(c,d,a), _orientation(c,d,b))
    if o1 != o2 and o3 != o4 and 0 not in (o1,o2,o3,o4):
        return True
    if o1 == 0 and _on_segment(a,c,b): return True
    if o2 == 0 and _on_segment(a,d,b): return True
    if o3 == 0 and _on_segment(c,a,d): return True
    if o4 == 0 and _on_segment(c,b,d): return True
    return False


def calculate(axes: dict, calibration: dict, image_width: int | None = None, image_height: int | None = None) -> dict:
    diagnostics: list[dict] = []
    diagnostics.extend(_axis_diagnostics("x", axes.get("x", {})))
    diagnostics.extend(_axis_diagnostics("y", axes.get("y", {})))

    raw_points = calibration.get("points", {}) if isinstance(calibration, dict) else {}
    missing = [name for name in CORNER_ORDER if name not in raw_points]
    if missing:
        diagnostics.append({"severity": "error", "code": "calibration_incomplete", "message": "Calibration is incomplete; missing: " + ", ".join(missing) + "."})
        return {"ready": False, "condition_number": None, "reprojection_rms": None, "diagnostics": diagnostics}

    pixels = {}
    try:
        for name in CORNER_ORDER:
            p = raw_points[name]
            x, y = float(p["pixel_x"]), float(p["pixel_y"])
            if not math.isfinite(x) or not math.isfinite(y):
                raise ValueError
            pixels[name] = (x, y)
    except (KeyError, TypeError, ValueError):
        diagnostics.append({"severity": "error", "code": "calibration_nonfinite", "message": "Calibration control points must contain finite pixel coordinates."})
        return {"ready": False, "condition_number": None, "reprojection_rms": None, "diagnostics": diagnostics}

    # Duplicate / near-duplicate control points.
    coords = list(pixels.values())
    distances = [math.hypot(coords[i][0]-coords[j][0], coords[i][1]-coords[j][1]) for i in range(4) for j in range(i+1,4)]
    min_dist = min(distances)
    if min_dist < 1.0:
        diagnostics.append({"severity": "error", "code": "control_points_duplicate", "message": f"Calibration control points are coincident or closer than one pixel (minimum separation {min_dist:.3g} px)."})
    else:
        diagnostics.append({"severity": "ok", "code": "control_point_separation", "message": f"Calibration control-point minimum separation: {min_dist:.3g} px."})

    # Polygon order around the quadrilateral is BL -> BR -> TR -> TL.
    poly = [pixels["bottom_left"], pixels["bottom_right"], pixels["top_right"], pixels["top_left"]]
    area = abs(_polygon_area(poly))
    if area < 1.0:
        diagnostics.append({"severity": "error", "code": "control_polygon_area", "message": f"Calibration quadrilateral area is too small ({area:.3g} px²)."})
    else:
        diagnostics.append({"severity": "ok", "code": "control_polygon_area", "message": f"Calibration quadrilateral area: {area:.6g} px²."})

    if _segments_intersect(poly[0], poly[1], poly[2], poly[3]) or _segments_intersect(poly[1], poly[2], poly[3], poly[0]):
        diagnostics.append({"severity": "error", "code": "control_polygon_self_intersection", "message": "Calibration control-point quadrilateral self-intersects."})
    else:
        signs = [_orientation(poly[i], poly[(i+1)%4], poly[(i+2)%4]) for i in range(4)]
        nonzero = [s for s in signs if s]
        if len(nonzero) < 4 or any(s != nonzero[0] for s in nonzero):
            diagnostics.append({"severity": "warning", "code": "control_polygon_nonconvex", "message": "Calibration control-point quadrilateral is non-convex or nearly collinear; review the four selected corners."})
        else:
            diagnostics.append({"severity": "ok", "code": "control_polygon_convex", "message": "Calibration control-point quadrilateral is convex."})

    if image_width and image_height:
        outside = [name for name, (x,y) in pixels.items() if x < 0 or y < 0 or x > image_width or y > image_height]
        if outside:
            diagnostics.append({"severity": "warning", "code": "control_points_outside_image", "message": "Calibration control points outside the reported source image bounds: " + ", ".join(outside) + "."})
        else:
            diagnostics.append({"severity": "ok", "code": "control_points_inside_image", "message": "All calibration control points lie inside the reported source image bounds."})

    rows, rhs = [], []
    for name in CORNER_ORDER:
        x, y = pixels[name]
        u, v = DEST[name]
        rows.append([x, y, 1, 0, 0, 0, -u*x, -u*y]); rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v*x, -v*y]); rhs.append(v)
    a = np.asarray(rows, dtype=float)
    b = np.asarray(rhs, dtype=float)
    rank = int(np.linalg.matrix_rank(a))
    if rank < 8:
        diagnostics.append({"severity": "error", "code": "homography_degenerate", "message": f"Homography system is degenerate (rank {rank}/8)."})
        return {"ready": False, "condition_number": None, "reprojection_rms": None, "diagnostics": diagnostics}

    cond = float(np.linalg.cond(a))
    h = np.linalg.solve(a, b)
    H = np.asarray([[h[0],h[1],h[2]],[h[3],h[4],h[5]],[h[6],h[7],1.0]], dtype=float)
    errors = []
    for name in CORNER_ORDER:
        x, y = pixels[name]; eu, ev = DEST[name]
        q = H @ np.asarray([x,y,1.0], dtype=float)
        if abs(q[2]) < 1e-15:
            diagnostics.append({"severity": "error", "code": "homography_singular", "message": "Projective transform is singular at a calibration control point."})
            return {"ready": False, "condition_number": cond, "reprojection_rms": None, "diagnostics": diagnostics}
        u, v = q[0]/q[2], q[1]/q[2]
        errors.append((u-eu)**2 + (v-ev)**2)
    rms = math.sqrt(sum(errors)/len(errors))
    diagnostics.append({"severity": "info", "code": "homography_condition", "message": f"Homography solve matrix condition number: {cond:.6g}. This value depends on pixel-coordinate scale and should be interpreted as a numerical diagnostic, not a quality score."})
    diagnostics.append({"severity": "info", "code": "reprojection_rms", "message": f"Four-control-point reprojection RMS: {rms:.6g} in normalized calibration coordinates. With exactly four control points this mainly checks internal transform consistency, not digitization accuracy."})
    return {"ready": True, "condition_number": cond, "reprojection_rms": rms, "diagnostics": diagnostics}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--axes", required=True)
    parser.add_argument("--calibration", required=True)
    parser.add_argument("--image-width", type=int, default=0)
    parser.add_argument("--image-height", type=int, default=0)
    args = parser.parse_args()
    axes = json.loads(Path(args.axes).read_text(encoding="utf-8"))
    calibration = json.loads(Path(args.calibration).read_text(encoding="utf-8"))
    print(json.dumps(calculate(axes, calibration, args.image_width or None, args.image_height or None), ensure_ascii=False, separators=(",", ":"), allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
