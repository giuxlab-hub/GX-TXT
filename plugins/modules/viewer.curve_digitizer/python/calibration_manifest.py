# SPDX-License-Identifier: GPL-3.0-or-later
"""Portable scientific calibration manifest for published Curve Digitalizer Datasets.

Pure functions: no CORE access, no filesystem writes and no UI dependencies.
The host persists these values through DATASET_PUBLICATION_API_v2.
"""
from __future__ import annotations

import base64
import json
import hashlib
import math
import re

import numpy as np

CANONICAL_UNITS = {"µm": "um", "μm": "um", "um": "um", "Å": "Angstrom", "A": "Angstrom"}
METADATA_PREFIX = "curve_digitizer."
MANDATORY = (
    "source_dataset_id", "source_sha256", "configuration_id", "calibration_type",
    "image_width", "image_height", "coordinate_origin", "y_direction",
    "physical_unit", "transform",
)


def _finite(value):
    f = float(value)
    if not math.isfinite(f):
        raise ValueError("Calibration manifest contains a non-finite numerical value.")
    return f


def _flat_matrix(matrix):
    arr = np.asarray(matrix, dtype=float)
    if arr.shape != (3, 3) or not np.isfinite(arr).all():
        raise ValueError("Invalid homography shape or coefficients.")
    return [[float(v) for v in row] for row in arr]


def _axis(axis):
    return {"minimum": _finite(axis.minimum), "maximum": _finite(axis.maximum),
            "scale": str(axis.scale), "unit": str(axis.unit)}


def build_manifest(config: dict, project, image_width: int, image_height: int, *, include_measurements=True) -> dict:
    """Build immutable calibration provenance from the live validated project."""
    w, h = int(image_width), int(image_height)
    if w < 2 or h < 2 or not project.calibration_ready():
        raise ValueError("A valid calibrated raster image is required.")
    source = config.get("source", {})
    sha = str(source.get("sha256", "")).strip().lower()
    if not str(source.get("dataset_id", "")).strip() or not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise ValueError("Source Image Dataset ID and SHA-256 are required.")
    configuration_id = str(config.get("configuration_id", "")).strip()
    if not configuration_id:
        raise ValueError("Configuration ID is required.")
    H, _ = project.calibration.matrix()
    if not np.isfinite(H).all():
        raise ValueError("Calibration homography is invalid.")
    x, y = project.x_axis, project.y_axis
    xa, ya = _axis(x), _axis(y)
    y_down = ya["minimum"] > ya["maximum"]
    normalized = _flat_matrix(H)
    transform = {
        "convention": "column_vector_homogeneous_xy1",
        "raster_origin": "top_left", "pixel_reference": "pixel_center",
        "normalized_coordinates": "x_left_to_right_y_bottom_to_top",
        "normalized_homography": normalized,
        "x_axis": xa, "y_axis": ya,
    }
    # The projective matrix alone maps to normalized plot coordinates;
    # append the exact linear axis mapping only where it is mathematically valid.
    scientific = None
    if x.scale == "linear" and y.scale == "linear":
        A = np.array([[x.maximum - x.minimum, 0, x.minimum],
                      [0, y.maximum - y.minimum, y.minimum], [0, 0, 1]], dtype=float)
        scientific = _flat_matrix(A @ H)
        transform["scientific_homography"] = scientific
    full_frame = project.is_full_image_calibration(w, h)
    relative_perspective = abs(float(H[2, 0])) * (w - 1) + abs(float(H[2, 1])) * (h - 1)
    affine = relative_perspective < 1e-7
    ref = config.get("scale_reference")
    bar = None
    if ref and full_frame:
        start = [_finite(v) for v in ref["start"]]
        end = [_finite(v) for v in ref["end"]]
        if any(not (0 <= point[0] <= w-1 and 0 <= point[1] <= h-1)
               for point in (start, end)):
            raise ValueError("Scale-bar reference lies outside the source raster.")
        px = math.dist(start, end)
        real = _finite(ref["physical_length"])
        if px < 3 or real <= 0:
            raise ValueError("Invalid scale bar geometry or declared length.")
        if not math.isclose(px, _finite(ref["pixel_length"]), rel_tol=1e-8):
            raise ValueError("Scale bar endpoints disagree with saved pixel length.")
        factor = real / px
        if x.scale != "linear" or y.scale != "linear" or not math.isclose(abs(x.maximum-x.minimum)/(w-1), factor, rel_tol=1e-7):
            raise ValueError("Scale bar reference is stale relative to calibrated axes.")
        if not math.isclose(abs(y.maximum-y.minimum)/(h-1), factor, rel_tol=1e-7):
            raise ValueError("X/Y physical scaling is inconsistent.")
        unit = str(ref["unit"])
        if x.unit != unit or y.unit != unit:
            raise ValueError("The saved scale bar unit does not match the axes.")
        bar = {"start_px": start, "end_px": end, "pixel_length": px,
               "physical_length": real, "unit": CANONICAL_UNITS.get(unit, unit),
               "display_unit": unit, "selection_method": str(ref.get("method", "unknown")),
               "edge_convention": str(ref.get("edge_convention", "unspecified"))}
    is_pixel = (full_frame and bar is None and x.unit == "px" and y.unit == "px"
                and x.scale == "linear" and y.scale == "linear"
                and math.isclose(x.minimum, 0, abs_tol=1e-8)
                and math.isclose(x.maximum, w - 1, abs_tol=1e-8)
                and math.isclose(y.minimum, h - 1 if y_down else 0, abs_tol=1e-8)
                and math.isclose(y.maximum, 0 if y_down else h - 1, abs_tol=1e-8))
    calibration_type = "scale_bar" if bar is not None else "pixel" if is_pixel else "affine" if affine else "projective"
    physical_unit = CANONICAL_UNITS.get(x.unit, x.unit) if x.unit == y.unit and x.unit != "px" else ""
    manifest = {
        "manifest_version": 1,
        "source_dataset_id": str(source["dataset_id"]), "source_sha256": sha,
        "configuration_id": configuration_id,
        "calibration_type": calibration_type,
        "image_width": w, "image_height": h,
        "coordinate_origin": "top_left" if y_down else "bottom_left",
        "y_direction": "down" if y_down else "up",
        "physical_unit": physical_unit,
        "transform": transform,
    }
    # These are original pixels of the Image Dataset given to the viewer.
    # Earlier cropping/rotation by the importer is unknown and not inferred.
    raster_geometry = {
        "reference_image": "source_dataset_raster",
        "source_pixel_space": "original_source_image",
        "calibration_pixel_space": "original_source_image",
        "crop": None, "rotation_degrees": 0, "resize": None,
        "source_to_calibration_homography": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
        "upstream_processing": "unknown",
    }
    manifest["raster_geometry"] = raster_geometry
    manifest["calibration_method"] = {
        "type": calibration_type,
        "point_selection": bar["selection_method"] if bar is not None else ("full_image" if full_frame else "manual_four_corners"),
        "tick_reference": bar["edge_convention"] if bar is not None else "not_applicable",
        "measurement_uncertainty": "not_quantified" if not config.get("uncertainty") else "provided",
    }
    if bar is not None:
        manifest["scale_bar"] = bar
    # Stable across distinct digitizations using the exact same raster/mapping;
    # deliberately independent of GUI config ID, labels and point tracing.
    identity = {
        "source_sha256": sha, "image_width": w, "image_height": h,
        "normalized_homography": normalized,
        "x_axis": {k: xa[k] for k in ("minimum", "maximum", "scale", "unit")},
        "y_axis": {k: ya[k] for k in ("minimum", "maximum", "scale", "unit")},
        "raster_geometry": raster_geometry,
    }
    canonical = json.dumps(identity, sort_keys=True, ensure_ascii=False,
                           separators=(",", ":"), allow_nan=False)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    manifest["calibration_id"] = "cal_" + digest[:24]
    manifest["calibration_sha256"] = digest
    manifest["calibration_identity_payload"] = canonical
    if include_measurements and isinstance(config.get("calibration_measurements"), dict):
        # Publish each manual realization separately, without treating its
        # dispersion as a computed uncertainty. This dataset remains usable
        # after the Interactive Document has been deleted.
        from digitizer_model import Project
        group = config["calibration_measurements"]
        items = group.get("items", [])
        if not 1 <= len(items) <= 200:
            raise ValueError("Calibration group must contain 1..200 measurements.")
        seen = set()
        records = []
        for item in items:
            mid = str(item.get("id", ""))
            if not re.fullmatch(r"meas_[0-9a-f]{32}", mid) or mid in seen:
                raise ValueError("Calibration measurements require distinct stable identities.")
            seen.add(mid)
            state = str(item.get("state", ""))
            if state not in ("draft", "accepted", "rejected"):
                raise ValueError("Invalid calibration measurement state.")
            trial = Project.from_dict({"axes": item.get("axes", {}),
                                       "calibration": item.get("calibration", {})})
            record = {"measurement_id": mid,
                      "label": str(item.get("label", mid)), "state": state,
                      "active": mid == group.get("active_id"),
                      "axes": item.get("axes", {}),
                      "corners_px": item.get("calibration", {}).get("points", {}),
                      "scale_reference": item.get("scale_reference")}
            if trial.calibration_ready():
                local_cfg = dict(config)
                local_cfg["scale_reference"] = item.get("scale_reference")
                local_manifest = build_manifest(local_cfg, trial, w, h,
                                                include_measurements=False)
                for key in ("calibration_id", "calibration_sha256", "calibration_type",
                            "transform", "scale_bar", "calibration_method"):
                    if key in local_manifest:
                        record[key] = local_manifest[key]
                record["valid"] = True
            else:
                if state == "accepted":
                    raise ValueError("Accepted calibration measurement is incomplete or invalid.")
                record["valid"] = False
            records.append(record)
        if group.get("active_id") not in seen:
            raise ValueError("Calibration group active measurement is missing.")
        active = next(v for v in records if v["active"])
        if not active["valid"] or active["state"] != "accepted":
            raise ValueError("The active calibration measurement must be accepted and valid.")
        if active["calibration_sha256"] != manifest["calibration_sha256"]:
            raise ValueError("Active and published calibration mappings disagree.")
        manifest["calibration_measurements"] = records
        manifest["calibration_group_id"] = group.get("group_id", "")
        manifest["active_measurement_id"] = group["active_id"]
        manifest["calibration_measurements_policy"] = "realizations_only_no_estimated_uncertainty"
    if isinstance(config.get("uncertainty"), dict) and config["uncertainty"]:
        # No uncertainty is fabricated from the exact four-corner reprojection.
        uncertainty = config["uncertainty"]
        json.dumps(uncertainty, allow_nan=False)
        manifest["uncertainty"] = uncertainty
    return manifest


def metadata_fields(manifest: dict) -> dict[str, str]:
    """Namespaced plain-string fields plus explicit numeric components for Tcl readers."""
    result = {
        "curve_digitizer.manifest_version": str(manifest["manifest_version"]),
        "curve_digitizer.calibration_manifest": json.dumps(manifest, ensure_ascii=False, separators=(",", ":"), allow_nan=False),
    }
    for k in MANDATORY:
        v = manifest[k]
        result[METADATA_PREFIX + k] = (json.dumps(v, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
                                       if isinstance(v, (dict, list)) else str(v))
    for k in ("calibration_id", "calibration_sha256", "calibration_identity_payload"):
        result[METADATA_PREFIX + k] = str(manifest[k])
    if "calibration_measurements" in manifest:
        result[METADATA_PREFIX + "calibration_group_id"] = str(manifest["calibration_group_id"])
        result[METADATA_PREFIX + "active_measurement_id"] = str(manifest["active_measurement_id"])
        result[METADATA_PREFIX + "measurement_count"] = str(len(manifest["calibration_measurements"]))
        result[METADATA_PREFIX + "calibration_measurements"] = json.dumps(
            manifest["calibration_measurements"], ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        for i, measurement in enumerate(manifest["calibration_measurements"]):
            prefix = METADATA_PREFIX + f"measurement.{i}."
            for key in ("measurement_id", "label", "state"):
                result[prefix+key] = str(measurement[key])
            result[prefix+"active"] = "1" if measurement["active"] else "0"
            result[prefix+"valid"] = "1" if measurement["valid"] else "0"
            for key in ("corners_px", "axes", "scale_reference"):
                result[prefix+key] = json.dumps(measurement.get(key), ensure_ascii=False,
                    separators=(",", ":"), allow_nan=False)
            if measurement["valid"]:
                for key in ("calibration_id", "calibration_sha256", "calibration_type"):
                    result[prefix+key] = str(measurement[key])
                t = measurement["transform"]
                for axis in ("x", "y"):
                    for key in ("minimum", "maximum", "scale", "unit"):
                        result[prefix+f"transform.{axis}_{key}"] = str(t[f"{axis}_axis"][key])
                for a in range(3):
                    for b in range(3):
                        result[prefix+f"transform.h{a}{b}"] = format(t["normalized_homography"][a][b], ".17g")

    for k in ("scale_bar", "uncertainty", "raster_geometry", "calibration_method"):
        if k in manifest:
            result[METADATA_PREFIX + k] = json.dumps(manifest[k], ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    t = manifest["transform"]
    result[METADATA_PREFIX + "transform.convention"] = t["convention"]
    result[METADATA_PREFIX + "transform.raster_origin"] = t["raster_origin"]
    result[METADATA_PREFIX + "transform.pixel_reference"] = t["pixel_reference"]
    for i in range(3):
        for j in range(3):
            result[f"{METADATA_PREFIX}transform.h{i}{j}"] = format(t["normalized_homography"][i][j], ".17g")
            if "scientific_homography" in t:
                result[f"{METADATA_PREFIX}transform.scientific_h{i}{j}"] = format(t["scientific_homography"][i][j], ".17g")
    for axis in ("x", "y"):
        for field, value in t[axis + "_axis"].items():
            result[f"{METADATA_PREFIX}transform.{axis}_{field}"] = str(value)
    result[METADATA_PREFIX + "raster_geometry.source_pixel_space"] = manifest["raster_geometry"]["source_pixel_space"]
    result[METADATA_PREFIX + "raster_geometry.calibration_pixel_space"] = manifest["raster_geometry"]["calibration_pixel_space"]
    result[METADATA_PREFIX + "raster_geometry.source_to_calibration"] = "identity"
    result[METADATA_PREFIX + "calibration_method.type"] = manifest["calibration_method"]["type"]
    result[METADATA_PREFIX + "calibration_method.point_selection"] = manifest["calibration_method"]["point_selection"]
    result[METADATA_PREFIX + "calibration_method.tick_reference"] = manifest["calibration_method"]["tick_reference"]
    result[METADATA_PREFIX + "calibration_method.measurement_uncertainty"] = manifest["calibration_method"]["measurement_uncertainty"]
    if "uncertainty" in manifest:
        for key, value in manifest["uncertainty"].items():
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", key) and isinstance(value, (str, int, float, bool)):
                result[f"{METADATA_PREFIX}uncertainty.{key}"] = str(value)
    if "scale_bar" in manifest:
        b = manifest["scale_bar"]
        for key in ("pixel_length", "physical_length", "unit", "display_unit", "selection_method", "edge_convention"):
            result[f"{METADATA_PREFIX}scale_bar.{key}"] = str(b[key])
        for end in ("start", "end"):
            for i, coord in enumerate(("x", "y")):
                result[f"{METADATA_PREFIX}scale_bar.{end}_{coord}"] = format(b[end + "_px"][i], ".17g")
    return result


def encode_metadata_records(values: dict[str, str]) -> str:
    def b64(value):
        return base64.b64encode(value.encode("utf-8")).decode("ascii")
    return "\n".join(f"{b64(key)}\t{b64(value)}" for key, value in sorted(values.items()))
