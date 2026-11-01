# SPDX-License-Identifier: GPL-3.0-or-later
"""Versioned Y1/Y2 canonical publication planning; no CORE or GUI dependencies.

Dataset Group creation is separately owned by F4. This module only plans
physical-unit-correct table.generic / true curve_family.table outputs.
"""
from __future__ import annotations

import math
import re
from collections import Counter
from typing import Any

from publication_planning import plan_datasets

AXES = ("y1", "y2")
AXIS_METADATA_VERSION = "1"
CURVE_SCHEMA_VERSION = "2"


def _axis(axes: dict, identifier: str) -> dict:
    key = "y" if identifier == "y1" else "y2"
    result = axes.get(key)
    if not isinstance(result, dict):
        raise ValueError(f"Missing {identifier} scientific axis declaration.")
    if str(result.get("scale")) not in ("linear", "log"):
        raise ValueError(f"Invalid {identifier} scientific scale.")
    lo, hi = float(result["minimum"]), float(result["maximum"])
    if not math.isfinite(lo) or not math.isfinite(hi) or lo == hi:
        raise ValueError(f"Invalid {identifier} scientific interval.")
    if result["scale"] == "log" and (lo <= 0 or hi <= 0):
        raise ValueError(f"Nonpositive logarithmic {identifier} interval.")
    return result


def _unit(axes: dict, identifier: str) -> str:
    return str(_axis(axes, identifier).get("unit", ""))


def _id_with_axis(base: str, axis_id: str, *, split: bool) -> str:
    result = f"{base}.{axis_id}" if split else base
    if (not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", result)
            or len(result) > 128):
        raise ValueError("Y-axis publication requires a unique Dataset ID no longer than 128 characters.")
    return result


def plan_y2_datasets(items: list[dict], selected_ids: list[str], *,
                     layout: str, template: str, name: str, configuration: str,
                     series: list[Any], fallback_y2: dict | None = None) -> list[dict]:
    """Refine the already-tested calibration plan only where physical units require it.

    Output uses one scientific X/Y variable pair per Dataset, with an explicit
    row-axis discriminator in every Y2-capable publication. 'mixed' contains
    same-unit curves on both axes; otherwise independently emit y1 / y2 outputs.
    """
    ordinary = plan_datasets(items, selected_ids, layout=layout,
                             template=template, name=name, configuration=configuration)
    active = [s for s in series if s.points]
    if not active:
        raise ValueError("No calibrated curve points were selected.")
    used = {s.y_axis_id for s in active}
    if not used.issubset(AXES):
        raise ValueError("Unknown curve Y axis binding.")
    index = {item["id"]: item for item in items}
    plan = []
    names = set()
    for original in ordinary:
        measurements = [index[mid] for mid in original["measurement_ids"]]
        axes_list = []
        for item in measurements:
            axes = dict(item["axes"])
            if "y2" not in axes and fallback_y2 is not None:
                axes["y2"] = dict(fallback_y2)
            _axis(axes, "y1")
            _axis(axes, "y2")
            axes_list.append(axes)
        x_units = {str(axes["x"].get("unit", "")) for axes in axes_list}
        for axis_id in used:
            if len({_unit(a, axis_id) for a in axes_list}) != 1:
                raise ValueError(f"Combined {axis_id} calibration rows require a single physical Y unit.")
        if len(x_units) != 1:
            raise ValueError("Combined calibration rows require a single physical X unit.")
        both = used == {"y1", "y2"}
        same_unit = all(_unit(axes, "y1") == _unit(axes, "y2") for axes in axes_list)
        split = bool(both and not same_unit)
        modes = ("y1", "y2") if split else ("mixed",) if both else tuple(sorted(used))
        for axis_mode in modes:
            dataset_id = _id_with_axis(original["dataset_id"], axis_mode, split=split)
            if dataset_id in names:
                raise ValueError("Y2 Dataset naming collision across selected calibration realizations.")
            names.add(dataset_id)
            subset = active if axis_mode == "mixed" else [
                series for series in active if series.y_axis_id == axis_mode]
            y_unit = _unit(axes_list[0], "y1" if axis_mode == "mixed" else axis_mode)
            plan.append({
                **original,
                "dataset_id": dataset_id,
                "axis_mode": axis_mode,
                "curve_ids": [s.id for s in subset],
                "x_unit": next(iter(x_units)),
                "y_unit": y_unit,
                "axis_units": {axis: _unit(axes_list[0], axis) for axis in AXES},
                "split_by_unit": split,
            })
    return plan


def metadata_for_y2(config: dict, job: dict, measurements: list[dict],
                    series: list[Any], publication_set_id: str) -> dict[str, str]:
    """Opaque versioned internals for the eventual stable public API adapter."""
    import json
    selected = {s.id: s for s in series if s.id in job["curve_ids"]}
    if not selected:
        raise ValueError("Y2 publication contains no actual curves.")
    axes = []
    for item in measurements:
        ax = dict(item["axes"])
        if "y2" not in ax:
            ax["y2"] = dict(config["axes"]["y2"])
        axes.append({
            "measurement_id": item["id"],
            "label": item["label"],
            "x": dict(ax["x"]), "y1": dict(ax["y"]), "y2": dict(ax["y2"]),
            "original_scale_reference_y1": item.get("scale_reference"),
        })
    curves = [{
        "curve_id": s.id,
        "curve_name": s.name,
        "axis_id": s.y_axis_id,
        "point_count_per_calibration": len(s.points),
        "family_parameter_name": s.parameter_name,
        "family_parameter_value": s.parameter_value,
        "family_parameter_unit": s.parameter_unit,
    } for s in selected.values()]
    result = {
        "curve_digitizer.axis_schema_version": AXIS_METADATA_VERSION,
        "curve_digitizer.curve_schema_version": CURVE_SCHEMA_VERSION,
        "curve_digitizer.axis_mode": job["axis_mode"],
        "curve_digitizer.axis_units_y1": job["axis_units"]["y1"],
        "curve_digitizer.axis_units_y2": job["axis_units"]["y2"],
        "curve_digitizer.axis_definitions_json": json.dumps(
            axes, separators=(",", ":"), ensure_ascii=False, allow_nan=False),
        "curve_digitizer.curves_json": json.dumps(
            curves, separators=(",", ":"), ensure_ascii=False, allow_nan=False),
        "curve_digitizer.publication_set_id": publication_set_id,
        "curve_digitizer.publication_axis_id": job["axis_mode"],
        "curve_digitizer.calibration_manifest_scope": (
            "reference_y1_when_mixed" if job["axis_mode"] == "mixed" else job["axis_mode"]),
        "curve_digitizer.split_by_unit": "1" if job["split_by_unit"] else "0",
        "curve_digitizer.axis_model_version": "2",
    }
    for series_id, entry in selected.items():
        if not re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", series_id):
            raise ValueError(f"Curve ID {series_id!r} cannot be represented in Dataset metadata.")
        result[f"curve_digitizer.curve_axis.{series_id}"] = entry.y_axis_id
    return result
