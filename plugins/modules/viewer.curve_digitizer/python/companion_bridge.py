# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import base64
import json
import sys
import uuid
from pathlib import Path

from digitizer_model import DigitizedPoint, Project

CONFIG_FORMAT = "gxtxt.curve_digitizer.configuration"
CONFIG_VERSION = "1.0"


def _b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def _load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("format") != CONFIG_FORMAT:
        raise ValueError(f"Unsupported Curve Digitalizer configuration format: {data.get('format')!r}")
    if str(data.get("version", "")) != CONFIG_VERSION:
        raise ValueError(f"Unsupported Curve Digitalizer configuration version: {data.get('version')!r}")
    if not str(data.get("configuration_id", "")).strip():
        raise ValueError("Curve Digitalizer configuration_id is missing.")
    return data


def _project_from_config(cfg: dict) -> Project:
    source = cfg.get("source", {})
    return Project.from_dict({
        "version": cfg.get("version", CONFIG_VERSION),
        "image": {
            "path": "",
            "width": source.get("width", 0),
            "height": source.get("height", 0),
        },
        "axes": cfg.get("axes", {}),
        "calibration": cfg.get("calibration", {}),
        "series": cfg.get("curves", []),
        "notes": cfg.get("notes", ""),
        "display": cfg.get("display", {}),
        "snap": cfg.get("snap", {}),
    })


def command_context(args: argparse.Namespace) -> int:
    cfg = _load(Path(args.input))
    project = _project_from_config(cfg)
    curve = project.find_series(args.curve_id) if args.curve_id else None
    if args.curve_id and curve is None:
        raise ValueError(f"Curve ID {args.curve_id!r} does not exist in the selected configuration.")

    source = cfg.get("source", {})
    print("CONFIGURATION_ID\t" + _b64(str(cfg.get("configuration_id", ""))))
    print("CONFIGURATION_NAME\t" + _b64(str(cfg.get("name", ""))))
    print("SOURCE_DATASET_ID\t" + _b64(str(source.get("dataset_id", ""))))
    print("SOURCE_SHA256\t" + _b64(str(source.get("sha256", ""))))
    print("CALIBRATION_READY\t" + ("1" if project.calibration_ready() else "0"))
    print("AXES_JSON\t" + _b64(json.dumps(cfg.get("axes", {}), ensure_ascii=False, separators=(",", ":"))))
    print("CALIBRATION_JSON\t" + _b64(json.dumps(cfg.get("calibration", {}), ensure_ascii=False, separators=(",", ":"))))
    if curve is not None:
        curve_dict = next(c for c in cfg.get("curves", []) if str(c.get("id")) == args.curve_id)
        print("CURVE_ID\t" + _b64(curve.id))
        print("CURVE_NAME\t" + _b64(curve.name))
        print("CURVE_POINT_COUNT\t" + str(len(curve.points)))
        print("CURVE_JSON\t" + _b64(json.dumps(curve_dict, ensure_ascii=False, separators=(",", ":"))))
    return 0


def _read_pixel_points(path: Path) -> list[tuple[str, float, float]]:
    points: list[tuple[str, float, float]] = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        raw = raw.strip()
        if not raw:
            continue
        fields = raw.split("\t")
        if len(fields) not in (2, 3):
            raise ValueError(f"Invalid pixel point row {lineno}: expected 'x<TAB>y' or 'id<TAB>x<TAB>y'.")
        if len(fields) == 2:
            point_id = str(uuid.uuid4())
            x_text, y_text = fields
        else:
            point_id, x_text, y_text = fields
            point_id = point_id.strip() or str(uuid.uuid4())
        try:
            x, y = float(x_text), float(y_text)
        except ValueError as exc:
            raise ValueError(f"Invalid numeric pixel coordinate on row {lineno}.") from exc
        points.append((point_id, x, y))
    if not points:
        raise ValueError("No pixel points were supplied.")
    return points


def command_append(args: argparse.Namespace) -> int:
    input_path = Path(args.input)
    output_path = Path(args.output)
    cfg = _load(input_path)
    project = _project_from_config(cfg)
    if not project.calibration_ready():
        raise ValueError("The Curve Digitalizer configuration does not have a valid complete calibration.")
    curve = project.find_series(args.curve_id)
    if curve is None:
        raise ValueError(f"Curve ID {args.curve_id!r} does not exist in the selected configuration.")

    existing_ids = {p.id for series in project.series for p in series.points}
    for point_id, px, py in _read_pixel_points(Path(args.points)):
        if point_id in existing_ids:
            raise ValueError(f"Point ID {point_id!r} already exists in the configuration.")
        point = DigitizedPoint(
            id=point_id,
            manual_pixel_x=px,
            manual_pixel_y=py,
            pixel_x=px,
            pixel_y=py,
        )
        project.update_point_calibration(point)
        if point.calibrated_x is None or point.calibrated_y is None:
            raise ValueError("Unable to transform a proposed pixel point through the current calibration.")
        curve.points.append(point)
        existing_ids.add(point_id)

    # Reuse the same authoritative Curve Digitalizer point serialization. Only
    # the selected curve is changed; all unrelated configuration state remains
    # byte-semantically equivalent JSON data.
    for index, series in enumerate(project.series):
        if series.id == args.curve_id:
            cfg["curves"][index] = series.to_dict()
            break

    output_path.write_text(
        json.dumps(cfg, ensure_ascii=False, separators=(",", ":"), allow_nan=False),
        encoding="utf-8",
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Curve Digitalizer companion state bridge")
    sub = parser.add_subparsers(dest="command", required=True)

    context = sub.add_parser("context")
    context.add_argument("--input", required=True)
    context.add_argument("--curve-id", default="")
    context.set_defaults(func=command_context)

    append = sub.add_parser("append-pixel-points")
    append.add_argument("--input", required=True)
    append.add_argument("--output", required=True)
    append.add_argument("--curve-id", required=True)
    append.add_argument("--points", required=True)
    append.set_defaults(func=command_append)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
