# SPDX-License-Identifier: GPL-3.0-or-later
"""Curve Digitizer published-quality report v2.

Read-only, reproducible observations, generated at Dataset publication time.
The *published source raster* and original pixel coordinates are the authority:
no visual appearance setting, GUI canvas or private Session document is needed
by consumers. Image evidence is a heuristic and NEVER metrological accuracy.
"""
from __future__ import annotations

import math
from collections import Counter

import numpy as np

QUALITY_SCHEMA_VERSION = "2"
MAX_SEGMENT_RECORDS = 1500  # metadata must remain bounded for large datasets
MAX_ISSUES = 400           # further occurrences are counted, not suppressed silently
EVIDENCE_SAMPLE_LIMIT = 12000
LINE_EVIDENCE_THRESHOLD = 12.0  # uint8 luminance steps; observational only


def _finite(x):
    try:
        val = float(x)
        return val if math.isfinite(val) else None
    except (TypeError, ValueError):
        return None


def _stat(values):
    arr = np.asarray([v for v in values if v is not None and math.isfinite(float(v))], dtype=float)
    if not arr.size:
        return {"count": 0, "median": None, "maximum": None, "mean": None, "minimum": None}
    return {"count": int(arr.size), "median": float(np.median(arr)),
            "maximum": float(np.max(arr)), "minimum": float(np.min(arr)), "mean": float(np.mean(arr))}


def _pixel_gray(gray, x, y):
    ix, iy = int(round(x)), int(round(y))
    if 0 <= ix < gray.shape[1] and 0 <= iy < gray.shape[0]:
        return float(gray[iy, ix])
    return None


def _segment_evidence(gray, a, b):
    """Signed line-versus-flank contrast; not a fitted path/error metric.

    Cross-profile normal is defined by the vector a->b. Results are null if
    flanks leave the source image. A grid crossing can produce high contrast
    too; evidence explicitly cannot distinguish it from the wanted curve.
    """
    dx, dy = b[0]-a[0], b[1]-a[1]
    length = math.hypot(dx, dy)
    if length < 1e-10:
        return {"sample_count": 0, "signed_contrast_median": None,
                "absolute_contrast_median": None, "visible_fraction": None}
    nx, ny = -dy/length, dx/length
    n = max(1, min(7, int(math.ceil(length/3))))
    signed = []
    for i in range(n):
        t = (i+.5)/n
        x, y = a[0]+t*dx, a[1]+t*dy
        center = _pixel_gray(gray, x, y)
        left = _pixel_gray(gray, x+nx*4, y+ny*4)
        right = _pixel_gray(gray, x-nx*4, y-ny*4)
        if None in (center, left, right):
            continue
        signed.append(.5*(left+right)-center)
    if not signed:
        return {"sample_count": 0, "signed_contrast_median": None,
                "absolute_contrast_median": None, "visible_fraction": None}
    return {"sample_count": len(signed),
            "signed_contrast_median": float(np.median(signed)),
            "absolute_contrast_median": float(np.median(np.abs(signed))),
            "visible_fraction": round(sum(abs(v)>=LINE_EVIDENCE_THRESHOLD for v in signed)/len(signed), 4)}


def _calibration_summary(item, project, image_size, issue):
    from digitizer_model import AxisConfig, Calibration
    measurement_id = str(item.get("id", ""))
    result = {"measurement_id": measurement_id, "label": str(item.get("label", measurement_id)),
              "state": str(item.get("state", "")), "published": True,
              "geometry_valid": False, "homography_condition": None,
              "homography_condition_scope": "coordinate_scale_dependent_not_accuracy",
              "four_control_reprojection_rms": None,
              "independent_verification": {"available": False, "status": "not_recorded"},
              "axis_units": {}, "point_count": sum(len(s.points) for s in project.series)}
    try:
        cal = Calibration.from_dict(item["calibration"])
        x = AxisConfig.from_dict(item["axes"]["x"])
        y = AxisConfig.from_dict(item["axes"]["y"])
        x.validate();y.validate()
        result["axis_units"] = {"x": x.unit, "y": y.unit}
        polygon = [cal.pixels[k] for k in ("bottom_left", "bottom_right", "top_right", "top_left")]
        if len({(round(p[0], 9), round(p[1], 9)) for p in polygon}) != 4:
            issue("error", "control_points_duplicate", "Calibration corners are duplicated", measurement_id=measurement_id)
        def cross(a,b,c):
            return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        signs = [cross(polygon[i],polygon[(i+1)%4],polygon[(i+2)%4]) for i in range(4)]
        area = abs(sum(polygon[i][0]*polygon[(i+1)%4][1]-polygon[i][1]*polygon[(i+1)%4][0] for i in range(4)))/2
        result["control_polygon_area_px2"] = area
        convex = all(v>1e-7 for v in signs) or all(v < -1e-7 for v in signs)
        if not convex or area < 1:
            issue("error", "calibration_geometry_invalid", "Calibration quadrilateral is degenerate or nonconvex", measurement_id=measurement_id)
        w,h = image_size
        if any(not(0<=px<w and 0<=py<h) for px,py in polygon):
            issue("warning", "corner_outside_image", "Calibration corner outside raster bounds", measurement_id=measurement_id)
        H, cond = cal.matrix()
        result["homography_condition"] = float(cond) if math.isfinite(cond) else None
        result["four_control_reprojection_rms"] = cal.reprojection_rms()
        result["geometry_valid"] = bool(convex and area>=1 and math.isfinite(cond))
        if not result["geometry_valid"]:
            issue("error", "homography_condition_invalid", "Calibration geometry failed validation", measurement_id=measurement_id)
    except (ValueError, KeyError, TypeError, ArithmeticError, np.linalg.LinAlgError) as exc:
        issue("error", "calibration_invalid", str(exc), measurement_id=measurement_id)
    return result


def inspect(config, project, image_size, *, measurements=None, publication_layout="separate",
            published_row_count=None, raster_image=None, point_ordering="insertion",
            monotonicity="none"):
    """Compute v2 diagnostics from the exact scientific publication inputs.

    `project` holds the common source raster clicks; `measurements` MUST contain
    only calibration realizations used by this publication job. No legacy
    compatibility is implied. `published_row_count` is the actual count of rows
    built by the caller, not the count of original click points.
    """
    w,h = map(int, image_size)
    if w<=0 or h<=0:
        raise ValueError("Invalid source raster dimensions")
    measurements = list(measurements or [])
    if not measurements:
        raise ValueError("Publication quality requires the selected calibration measurements")
    if publication_layout not in ("separate", "combined"):
        raise ValueError("Invalid calibration publication layout")
    source_points = sum(len(s.points) for s in project.series)
    expected_rows = source_points * len(measurements)
    if published_row_count is None or int(published_row_count) != expected_rows:
        raise ValueError(f"Published row count {published_row_count} disagrees with {expected_rows} expected calibration realizations")
    issue_records=[]
    totals=Counter()
    def issue(severity, code, message, **ref):
        totals[severity] += 1
        if len(issue_records)<MAX_ISSUES:
            issue_records.append({"severity": severity,"code":code,"message":message,**ref})
    try:
        project.x_axis.validate();project.y_axis.validate()
    except Exception as exc:
        issue("error", "axis_invalid", str(exc))
    cals=[_calibration_summary(item,project,(w,h),issue) for item in measurements]
    gray=None
    if raster_image is not None:
        if raster_image.size != (w,h):
            raise ValueError("Image evidence raster dimensions do not match source image")
        gray = np.asarray(raster_image.convert("L"), dtype=np.uint8)
    all_lengths=[];curve_reports=[];suspect_segments=[];segment_records=[];trace_samples=0
    origin_total=Counter();all_segment_count=0
    evidence_complete=0
    # A per-curve robust spacing threshold prevents a very densely sampled
    # neighboring series from setting the scale for another curve.
    for series in project.series:
        pts=series.points
        origin_counts=dict(Counter(getattr(p,"origin","manual") for p in pts))
        origin_total.update(origin_counts)
        coords=[(float(p.pixel_x),float(p.pixel_y)) for p in pts]
        lengths=[math.dist(a,b) for a,b in zip(coords,coords[1:])]
        all_lengths.extend(lengths)
        nonzero=[v for v in lengths if v>=1e-8]
        median=float(np.median(nonzero)) if nonzero else None
        extreme_threshold=max(15.0,8.0*median) if median is not None else None
        flags_counter=Counter();line_evidence=[];segments=[]
        for j, (a,b) in enumerate(zip(coords,coords[1:])):
            length=lengths[j]
            flags=[]
            if length<.1:flags.append("repeated_consecutive_point")
            if extreme_threshold is not None and length>extreme_threshold:flags.append("long_segment")
            sample=False
            # deterministic cap; exhaustive for ordinary curve counts
            if gray is not None and trace_samples < EVIDENCE_SAMPLE_LIMIT:
                evidence=_segment_evidence(gray,a,b)
                trace_samples+=evidence["sample_count"]
                sample=True
                if evidence["visible_fraction"] is not None:
                    line_evidence.append(evidence["visible_fraction"])
                    evidence_complete+=1
            else:
                evidence=None
            if evidence is not None and evidence["sample_count"] >= 2 and evidence["visible_fraction"] == 0.0:
                flags.append("weak_local_contrast")
            if flags:
                for code in flags:
                    flags_counter[code]+=1
                    issue("warning" if code=="repeated_consecutive_point" else "info",code,
                          "Inspect this interval on the source raster",curve_id=series.id,
                          segment_index=j, raster_start=list(a), raster_end=list(b))
            record={"curve_id":series.id,"segment_index":j,
                    "raster_start":[a[0],a[1]],"raster_end":[b[0],b[1]],
                    "length_px":round(length,6),"flags":flags,
                    "raster_evidence":evidence if sample else None}
            segments.append(record)
            all_segment_count+=1
        if not pts:
            issue("warning", "empty_curve", "Curve contains no points",curve_id=series.id)
        outbounds=[i for i,(x,y) in enumerate(coords) if not(0<=x<w and 0<=y<h)]
        if outbounds:
            issue("warning", "point_outside_image", f"{len(outbounds)} points outside source raster",
                  curve_id=series.id, point_indices=outbounds[:40], omitted_indices=max(0,len(outbounds)-40))
        # Image-space monotonic direction is a separate check from the
        # scientific calibration; the axis values may be log-transformed.
        mono_violations={"x":0,"y":0}
        if monotonicity in ("x","y") and len(pts)>1:
            coords_real=[getattr(p,"calibrated_"+monotonicity) for p in pts]
            valid=[_finite(v) for v in coords_real]
            mono_violations[monotonicity]=sum(a is not None and b is not None and a>b+1e-12
                                            for a,b in zip(valid,valid[1:]))
            if mono_violations[monotonicity]:
                issue("warning", "monotonicity_violation", "Curve order violates declared monotonicity",
                      curve_id=series.id, count=mono_violations[monotonicity])
        curve_reports.append({"curve_id":series.id,"curve_label":series.name,
            "source_point_count":len(pts),"source_segment_count":len(segments),
            "point_origins":origin_counts,
            "raster_bounds_px":({"xmin":min(x for x,_ in coords),"xmax":max(x for x,_ in coords),
                                  "ymin":min(y for _,y in coords),"ymax":max(y for _,y in coords)} if coords else None),
            "spacing_px":_stat(lengths),"raster_evidence_visible_fraction":_stat(line_evidence),
            "flag_counts":dict(flags_counter), "point_outside_image_count":len(outbounds),
            "monotonicity_violations":mono_violations,
            "publication_rows":len(pts)*len(measurements)})
        segment_records.extend(segments)
    # Bounded report; retain all flagged intervals, then a reproducible sample
    # of the rest, never silently truncating without coverage metadata.
    if len(segment_records)>MAX_SEGMENT_RECORDS:
        flagged=[s for s in segment_records if s["flags"]]
        unflagged=[s for s in segment_records if not s["flags"]]
        slots=max(0,MAX_SEGMENT_RECORDS-len(flagged))
        if len(flagged)>MAX_SEGMENT_RECORDS:
            segment_records=flagged[:MAX_SEGMENT_RECORDS]
        else:
            chosen=[unflagged[(i*len(unflagged))//slots] for i in range(slots)] if slots else []
            segment_records=sorted(flagged+chosen,key=lambda s:(s["curve_id"],s["segment_index"]))
    # Variation between published realizations is observable disagreement,
    # not a confidence interval, standard uncertainty, or instrument error.
    # Estimate at deterministic source-pixel samples without modifying rows.
    realization_spread = {"available": False, "sampled_raster_points": 0,
                          "x_range": _stat([]), "y_range": _stat([]),
                          "meaning": "descriptive spread across calibration realizations; not a standard uncertainty"}
    if len(measurements)>1:
        from digitizer_model import AxisConfig, Calibration
        transforms=[]
        for item in measurements:
            try:
                calibration=Calibration.from_dict(item["calibration"])
                axes=(AxisConfig.from_dict(item["axes"]["x"]),
                      AxisConfig.from_dict(item["axes"]["y"]))
                transforms.append((calibration,axes))
            except (KeyError, ValueError, TypeError):
                transforms=[]
                break
        samples=[(float(pt.pixel_x),float(pt.pixel_y)) for sr in project.series for pt in sr.points]
        if transforms and samples:
            stride=max(1,int(math.ceil(len(samples)/500)))
            spreads_x=[];spreads_y=[]
            for point in samples[::stride]:
                try:
                    projected=[(axes[0].from_unit(cal.pixel_to_unit(*point)[0]),
                                axes[1].from_unit(cal.pixel_to_unit(*point)[1]))
                               for cal,axes in transforms]
                    spreads_x.append(max(v[0] for v in projected)-min(v[0] for v in projected))
                    spreads_y.append(max(v[1] for v in projected)-min(v[1] for v in projected))
                except (ValueError, ArithmeticError, OverflowError, np.linalg.LinAlgError):
                    continue
            realization_spread={"available":bool(spreads_x),"sampled_raster_points":len(spreads_x),
                "x_range":_stat(spreads_x),"y_range":_stat(spreads_y),
                "axis_units": {"x":measurements[0]["axes"]["x"]["unit"],
                               "y":measurements[0]["axes"]["y"]["unit"]},
                "meaning":"descriptive spread across calibration realizations; not a standard uncertainty"}
    report={"schema_version":QUALITY_SCHEMA_VERSION,"producer":"viewer.curve_digitizer",
      "scope":"published_dataset_snapshot","image_space":"original_source_image_pixel_centers",
      "source":{"dataset_id":str(config.get("source",{}).get("dataset_id","")),
                "sha256":str(config.get("source",{}).get("sha256","")),
                "raster_width_px":w,"raster_height_px":h},
      "publication":{"layout":publication_layout,
        "calibration_measurement_ids":[str(m.get("id","")) for m in measurements],
        "calibration_realization_count":len(measurements),
        "unique_raster_point_count":source_points,
        "published_row_count":int(published_row_count),
        "curve_count":len(project.series),
        "source_segment_count":all_segment_count,
        "ordering_source":point_ordering,"declared_monotonicity":monotonicity},
      "calibrations":cals,"calibration_realization_spread":realization_spread,
      "point_origins":dict(origin_total),
      "curves":curve_reports,
      "segments":{"records":segment_records,"total":all_segment_count,
          "returned":len(segment_records),"truncated":len(segment_records)<all_segment_count,
          "sampling_policy":"all_flagged_then_uniform_subset; flagged truncated only if limit exceeded",
          "coordinate_system":"source_raster_pixels"},
      "image_evidence":{"available":gray is not None,"method":"local_center_vs_perpendicular_flanks",
          "threshold_uint8":LINE_EVIDENCE_THRESHOLD,"flank_distance_px":4,
          "sample_limit":EVIDENCE_SAMPLE_LIMIT,"sampled_segment_count":evidence_complete,
          "sampling_complete":evidence_complete==sum(1 for n in all_lengths if n>1e-10),
          "limitations":"Grid lines, text, intersections and illumination can mimic the desired curve. Contrast is evidence of local image structure, not accuracy."},
      "geometry":{"segment_length_px":_stat(all_lengths)},
      "issues":{"items":issue_records,"total":sum(totals.values()),
                "returned":len(issue_records),"omitted":sum(totals.values())-len(issue_records),
                "counts_by_severity":dict(totals)},
      "status":"errors" if totals["error"] else "warnings" if totals["warning"] else "observations" if totals["info"] else "ok",
      "metrology":{"accuracy":{"status":"not_assessed"},
                    "uncertainty":{"status":"not_assessed"},
                    "independent_calibration_verification":{"status":"not_recorded"},
                    "four_control_reprojection_is_accuracy":False}}
    return report
