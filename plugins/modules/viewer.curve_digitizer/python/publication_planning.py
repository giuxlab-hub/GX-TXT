# SPDX-License-Identifier: GPL-3.0-or-later
"""Deterministic Dataset publication names and calibration selection.

Pure functions; framework operations and filesystem access remain in CORE.
"""
from __future__ import annotations
import re

DEFAULT_TEMPLATE = "[name].[calibration].curves"
PUBLICATION_LAYOUTS = ("separate", "combined")
TOKENS = ("name", "calibration", "calibration_id", "configuration", "index", "mode")
_TOKEN_PATTERN = re.compile(r"\[([A-Za-z_]+)\]")


def slug_part(value: str) -> str:
    # For dataset identities, never use opaque document IDs as human labels.
    out = re.sub(r"[^A-Za-z0-9_-]+", "_", str(value).strip().lower()).strip("_-")
    return out or "unnamed"


def validate_template(template: str) -> str:
    if not isinstance(template, str) or not template.strip() or len(template) > 220:
        raise ValueError("Dataset naming template must contain 1..220 characters.")
    used = _TOKEN_PATTERN.findall(template)
    if not used or "name" not in used:
        raise ValueError("Dataset naming template must include [name].")
    if any(key not in TOKENS for key in used):
        raise ValueError("Unknown publication token; use [name], [calibration], [calibration_id], [configuration], [index] or [mode].")
    residue = _TOKEN_PATTERN.sub("", template)
    if "[" in residue or "]" in residue:
        raise ValueError("Malformed Dataset naming template token.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]*", residue):
        raise ValueError("Only ASCII letters, digits, dot, underscore, hyphen and named tokens are allowed.")
    return template.strip()


def render_dataset_name(template: str, *, name: str, calibration: str,
                        calibration_id: str, configuration: str, index: int,
                        mode: str) -> str:
    template = validate_template(template)
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", name.strip()):
        raise ValueError("Base Dataset ID must begin with a letter and contain only letters, digits, _, - or .")
    values = {
        "name": name.strip(),
        "calibration": slug_part(calibration),
        "calibration_id": slug_part(calibration_id),
        "configuration": slug_part(configuration),
        "index": str(index),
        "mode": mode,
    }
    result = _TOKEN_PATTERN.sub(lambda m: values[m.group(1)], template)
    result = re.sub(r"[._-]+\.", ".", result).strip("._-")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", result) or len(result) > 128:
        raise ValueError("Rendered Dataset ID is invalid or longer than 128 characters.")
    return result


def plan_datasets(items: list[dict], selected_ids: list[str], *, layout: str,
                  template: str, name: str, configuration: str) -> list[dict]:
    """Preflight every ID before publication; preserve requested order."""
    if layout not in PUBLICATION_LAYOUTS:
        raise ValueError("Unknown publication layout.")
    if not selected_ids:
        raise ValueError("Select at least one accepted calibration measurement.")
    index = {item["id"]: item for item in items}
    if len(set(selected_ids)) != len(selected_ids):
        raise ValueError("Duplicate calibration measurement selection.")
    chosen = []
    for mid in selected_ids:
        if mid not in index:
            raise ValueError("Unknown calibration measurement selection.")
        measurement = index[mid]
        if measurement.get("state") != "accepted":
            raise ValueError(f"Calibration '{measurement.get('label', mid)}' is not accepted.")
        chosen.append(measurement)
    selected = chosen if layout == "separate" else [None]
    planned = []
    seen = set()
    for pos, item in enumerate(selected, 1):
        label = item["label"] if item else "combined"
        mid = item["id"] if item else "combined"
        dataset_id = render_dataset_name(template, name=name, calibration=label,
                    calibration_id=mid, configuration=configuration, index=pos, mode=layout)
        if dataset_id in seen:
            raise ValueError("Dataset naming collision. Include [calibration_id] or [index], or rename measurements.")
        seen.add(dataset_id)
        planned.append({"dataset_id": dataset_id, "measurement_ids": [item["id"]] if item else selected_ids,
                        "primary_id": item["id"] if item else selected_ids[0],
                        "display_label": label})
    return planned
