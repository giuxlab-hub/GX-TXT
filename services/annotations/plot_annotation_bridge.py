#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Small JSON<->TSV bridge for GX-TXT Plot Annotation API v1.

The Tcl GUI intentionally does not depend on tcllib/json.  Values are transferred
as base64 UTF-8 strings so tabs/newlines in labels are lossless.
"""
from __future__ import annotations
import base64, json, os, sys, tempfile

NUMERIC = {
    "x", "y", "x1", "y1", "x2", "y2", "z_index", "stroke_width",
    "font_size", "rotation_deg", "fill_opacity", "width_px", "height_px", "dpi",
}
BOOL = {"visible", "locked", "bold", "italic", "border", "enabled"}


def b64e(value: object) -> str:
    return base64.b64encode(str(value).encode("utf-8")).decode("ascii")


def b64d(value: str) -> str:
    return base64.b64decode(value.encode("ascii")).decode("utf-8")


def scalar(key: str, value: str):
    if key in BOOL:
        return str(value).strip().lower() in {"1", "true", "yes", "on"}
    if key in NUMERIC:
        s = str(value).strip()
        if s == "":
            return 0
        try:
            return int(s) if key in {"z_index", "width_px", "height_px", "dpi"} else float(s)
        except ValueError:
            return 0
    return value


def read_json(path: str) -> int:
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    meta = {
        "annotation_api_version": doc.get("annotation_api_version", 1),
        "plot_id": doc.get("plot_id", ""),
        "base_plot": doc.get("base_plot", ""),
        "enabled": doc.get("enabled", True),
    }
    canvas = doc.get("canvas") or {}
    meta.update({
        "width_px": canvas.get("width_px", 0),
        "height_px": canvas.get("height_px", 0),
        "dpi": canvas.get("dpi", 200),
    })
    for k, v in meta.items():
        print("META\t%s\t%s" % (k, b64e(int(v) if isinstance(v, bool) else v)))
    for idx, obj in enumerate(doc.get("objects") or []):
        if not isinstance(obj, dict):
            continue
        for k, v in obj.items():
            if isinstance(v, (dict, list)):
                v = json.dumps(v, ensure_ascii=False, separators=(",", ":"))
            elif isinstance(v, bool):
                v = int(v)
            print("OBJ\t%d\t%s\t%s" % (idx, k, b64e(v)))
    return 0


def write_json(tsv: str, path: str) -> int:
    meta = {}
    objects: dict[int, dict] = {}
    with open(tsv, "r", encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            if parts[0] == "META" and len(parts) >= 3:
                meta[parts[1]] = b64d(parts[2])
            elif parts[0] == "OBJ" and len(parts) >= 4:
                idx = int(parts[1])
                key = parts[2]
                objects.setdefault(idx, {})[key] = b64d(parts[3])
    doc = {
        "annotation_api_version": int(meta.get("annotation_api_version", "1") or 1),
        "plot_id": meta.get("plot_id", ""),
        "base_plot": meta.get("base_plot", ""),
        "enabled": scalar("enabled", meta.get("enabled", "1")),
        "canvas": {
            "width_px": int(float(meta.get("width_px", "0") or 0)),
            "height_px": int(float(meta.get("height_px", "0") or 0)),
            "dpi": int(float(meta.get("dpi", "200") or 200)),
        },
        "objects": [],
    }
    for idx in sorted(objects):
        src = objects[idx]
        obj = {}
        for k, v in src.items():
            obj[k] = scalar(k, v)
        doc["objects"].append(obj)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".annotations-", suffix=".json", dir=os.path.dirname(os.path.abspath(path)))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=False)
            f.write("\n")
        validate(tmp)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return 0


def validate_document(doc) -> None:
    import math
    if not isinstance(doc, dict):
        raise ValueError("annotation document must be an object")
    if int(doc.get("annotation_api_version", 0)) != 1:
        raise ValueError("annotation_api_version must be 1")
    if not isinstance(doc.get("objects", []), list):
        raise ValueError("objects must be an array")
    ids = set()
    allowed = {"text", "line", "arrow", "rectangle", "ellipse"}
    for obj in doc.get("objects", []):
        if not isinstance(obj, dict):
            raise ValueError("annotation object must be an object")
        oid = str(obj.get("id", "")).strip()
        if not oid or oid in ids:
            raise ValueError("annotation object ids must be non-empty and unique")
        ids.add(oid)
        if obj.get("type") not in allowed:
            raise ValueError("unsupported annotation type: %r" % (obj.get("type"),))
        if obj.get("space", "figure_norm") != "figure_norm":
            raise ValueError("v1 currently supports only figure_norm coordinates")
        for key in NUMERIC & obj.keys():
            if not isinstance(obj[key], (int, float)) or not math.isfinite(obj[key]):
                raise ValueError(f"annotation {key} must be finite numeric")


def validate(path: str) -> int:
    with open(path, "r", encoding="utf-8") as f:
        validate_document(json.load(f))
    print("OK")
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: plot_annotation_bridge.py read FILE | write TSV JSON | validate FILE", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == "read" and len(sys.argv) == 3:
        return read_json(sys.argv[2])
    if cmd == "write" and len(sys.argv) == 4:
        return write_json(sys.argv[2], sys.argv[3])
    if cmd == "validate" and len(sys.argv) == 3:
        return validate(sys.argv[2])
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
