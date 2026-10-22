#!/usr/bin/env python3
"""Deterministic source generation; no scientific-module imports or results.

The registered host creates the Session. This producer uses the same local
session_recipe.configure route as the existing numerical examples.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import colorsys
import csv
import hashlib
import json
from pathlib import Path
import shutil
import struct
import zlib

from session_recipe import configure

GENERATOR_ID = "calibrated_curve_family"
FAMILY_KEY = "synthetic-affine-family-v1"
CURVES, CALIBRATIONS, POINTS = 50, 5, 300
WIDTH, HEIGHT = 1201, 1001
RAW_COLUMNS = ["family_key", "curve_key", "curve_name", "family_parameter",
               "point_order", "point_id", "raster_x", "raster_y", "curve_index"]
COLUMNS = ["x_s", "y_V", "family_parameter", "family_key", "curve_key",
           "curve_name", "calibration_key", "calibration_name", "point_order",
           "point_id", "realization_id", "raster_x", "raster_y", "curve_index",
           "calibration_index"]


def number(value: float) -> str:
    return format(value, ".17g")


def source_point(curve: int, point: int) -> tuple[float, float]:
    t = point / (POINTS - 1)
    return 100.0 + 1000.0 * t, 900.0 - 14.0 * curve - 8.0 * (2.0 * t - 1.0) ** 2


def calibrated(px: float, py: float, calibration: int) -> tuple[float, float]:
    k = calibration
    return ((px - 100.0) * (1.0 + k / 1000.0) / 100.0 + k / 100.0,
            (900.0 - py) * (1.0 - k / 2000.0) / 100.0 - k / 200.0)


def calibration_manifest(k: int) -> dict:
    # Exact rational matrix coefficients, acting on [pixel_x, pixel_y, 1].
    return {"calibration_key": f"calibration-{k:02d}", "calibration_index": k,
            "name": f"Declared affine calibration {k}",
            "matrix_rational": [[[1000 + k, 100000], [0, 1], [-100000 + 900 * k, 100000]],
                                [[0, 1], [-(2000 - k), 200000],
                                 [900 * (2000 - k) - 1000 * k, 200000]]],
            "input_units": ["px", "px"], "output_units": ["s", "V"],
            "shared_scope": "All curves and points with this calibration_key",
            "interpretation": "Declared synthetic transform; not an estimated uncertainty or an independent acquisition"}


def raster_and_overlay(image: Path, overlay: Path) -> None:
    pixels = bytearray([255]) * (WIDTH * HEIGHT * 3)

    def dot(x: int, y: int, rgb: tuple[int, int, int]) -> None:
        if not (0 <= x < WIDTH and 0 <= y < HEIGHT):
            raise ValueError("Analytical path escaped the source raster")
        at = 3 * (y * WIDTH + x)
        pixels[at:at + 3] = bytes(rgb)

    def line(x0: int, y0: int, x1: int, y1: int, rgb: tuple[int, int, int]) -> None:
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        error = dx + dy
        while True:
            dot(x0, y0, rgb)
            if x0 == x1 and y0 == y1:
                break
            twice = 2 * error
            if twice >= dy:
                error += dy
                x0 += sx
            if twice <= dx:
                error += dx
                y0 += sy

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
           '<title>Synthetic source raster with exact analytical pixel paths</title>',
           '<desc>Illustrative source-coordinate overlay, not a GX-TXT Preview or computed result.</desc>',
           '<image href="../raw/source_image.png" width="1201" height="1001"/>']
    for curve in range(CURVES):
        rgb = tuple(round(v * 255) for v in colorsys.hsv_to_rgb(curve / CURVES, .8, .7))
        coordinates = [source_point(curve, i) for i in range(POINTS)]
        integer = [(round(x), round(y)) for x, y in coordinates]
        for a, b in zip(integer, integer[1:]):
            line(*a, *b, rgb)
        # SVG's pixel-cell corners differ from our zero-based pixel-center index.
        points = " ".join(f"{number(x + .5)},{number(y + .5)}" for x, y in coordinates)
        color = "#" + "".join(f"{v:02x}" for v in rgb)
        svg.append(f'<polyline id="curve-{curve:03d}" points="{points}" fill="none" stroke="{color}" stroke-width="0.6"/>')
    svg.append('</svg>')
    overlay.write_text("\n".join(svg) + "\n", encoding="utf-8")

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    scanlines = b"".join(b"\0" + pixels[y * WIDTH * 3:(y + 1) * WIDTH * 3]
                         for y in range(HEIGHT))
    image.write_bytes(b"\x89PNG\r\n\x1a\n" +
                      chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)) +
                      chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))


def generate(root: Path) -> None:
    # Existing registered host staging directories are allowed. Existing science
    # is never overwritten by this producer, including on a direct accidental rerun.
    for relative in ("raw/source_points.csv", "raw/calibrated_points.csv", "raw/source_image.png",
                     "reference/source_overlay.svg", "reference/analytical_reference.json",
                     "reference/source_integrity.sha256", "metadata/datasets.ini",
                     "datasets/calibrated.family.source.csv", "STUDENT_GUIDE.md"):
        if (root / relative).exists():
            raise FileExistsError(root / relative)
    for part in ("raw", "reference"):
        (root / part).mkdir(parents=True, exist_ok=True)
    raw_path, calibrated_path = root / "raw/source_points.csv", root / "raw/calibrated_points.csv"
    with raw_path.open("x", newline="", encoding="utf-8") as raw, \
            calibrated_path.open("x", newline="", encoding="utf-8") as output:
        rw, cw = csv.writer(raw, lineterminator="\n"), csv.writer(output, lineterminator="\n")
        rw.writerow(RAW_COLUMNS)
        cw.writerow(COLUMNS)
        for c in range(CURVES):
            curve, label = f"curve-{c:03d}", f"Synthetic source curve {c + 1:02d}"
            coordinates = [source_point(c, i) for i in range(POINTS)]
            for i, (px, py) in enumerate(coordinates):
                point = f"{curve}.point-{i:03d}"
                rw.writerow([FAMILY_KEY, curve, label, c, i, point, number(px), number(py), c])
            for k in range(CALIBRATIONS):
                calibration = f"calibration-{k:02d}"
                for i, (px, py) in enumerate(coordinates):
                    x, y = calibrated(px, py, k)
                    point = f"{curve}.point-{i:03d}"
                    cw.writerow([number(x), number(y), c, FAMILY_KEY, curve, label, calibration,
                                 f"Declared affine calibration {k}", i, point,
                                 f"{point}.{calibration}", number(px), number(py), c, k])
    raster_and_overlay(root / "raw/source_image.png", root / "reference/source_overlay.svg")
    spec = json.loads(Path(__file__).with_name("reference_spec.json").read_text(encoding="utf-8"))
    spec["calibrations"] = [calibration_manifest(k) for k in range(CALIBRATIONS)]
    spec["source_sha256"] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                              for name in ("raw/source_points.csv", "raw/calibrated_points.csv",
                                           "raw/source_image.png", "reference/source_overlay.svg")}
    (root / "reference/analytical_reference.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    (root / "reference/source_integrity.sha256").write_text(
        "".join(f"{digest}  {name}\n" for name, digest in spec["source_sha256"].items()), encoding="ascii")
    roles = {"x_s": "independent", "y_V": "measured", "family_parameter": "family",
             "family_key": "source_identity", "curve_key": "group_identity",
             "curve_name": "label", "calibration_key": "calibration_identity",
             "calibration_name": "label", "point_order": "point_order",
             "point_id": "point_identity", "realization_id": "observation_identity",
             "raster_x": "raster_coordinate", "raster_y": "raster_coordinate",
             "curve_index": "index", "calibration_index": "index"}
    units = {"x_s": "s", "y_V": "V", "family_parameter": "1", "raster_x": "px", "raster_y": "px"}
    dtypes = {"point_order": "int64", "curve_index": "int64", "calibration_index": "int64"}
    metadata = {"synthetic_source": "1", "source_reference": "reference/analytical_reference.json",
                "source_image_dataset_id": "calibrated.family.image",
                "source_grouping_variables": "curve_key;calibration_key",
                "source_order_variable": "point_order",
                "description": "Synthetic analytical source, five shared affine calibrations; not Digitizer/Analysis results"}
    configure(root, GENERATOR_ID, [
        dict(source="raw/source_points.csv", id="calibrated.family.raw", kind="table.generic",
             units=units, roles=dict(roles, raster_x="independent", raster_y="measured"),
             coordinate="raster_x", variable_ids={v: v for v in RAW_COLUMNS},
             dtypes=dtypes, metadata=dict(metadata, source_grouping_variables="curve_key")),
        dict(source="raw/calibrated_points.csv", id="calibrated.family.source", kind="curve_family.table",
             units=units, roles=roles, coordinate="x_s", variable_ids={v: v for v in COLUMNS},
             dtypes=dtypes, metadata=metadata),
        dict(source="raw/source_image.png", id="calibrated.family.image", binary=True,
             kind="image.raster", format="png", media_type="image/png"),
    ], [], "Synthetic analytical calibrated curve-family source")
    shutil.copyfile(Path(__file__).with_name("STUDENT_GUIDE.md"), root / "STUDENT_GUIDE.md")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    if args.generator_id not in (None, GENERATOR_ID):
        parser.error("Generator identity differs from this producer")
    generate(Path(args.target_session))
    print("Generated synthetic source: 50 curves x 5 calibrations x 300 points = 75000 rows; no Analysis results")


if __name__ == "__main__":
    main()
