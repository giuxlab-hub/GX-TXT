"""Geometry-preserving ImageMagick processing for the GX-TXT Curve Digitalizer.

Original canonical image bytes, pixel coordinates, and geometric calibration are
never modified. Only allowlisted photometric operations can reach ImageMagick.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import hashlib
import io
import json
import math
import os
import re
import subprocess
from PIL import Image, UnidentifiedImageError

MAX_PIXELS = 90_000_000
MAX_OUTPUT_BYTES = 256 * 1024 * 1024
MAX_OPERATIONS = 30
OPERATION_KINDS = (
    "grayscale", "channel", "gamma", "brightness_contrast", "auto_level",
    "contrast_stretch", "clahe", "threshold", "median", "negate", "sharpen",
)
DEFAULT_PARAMETERS = {
    "grayscale": "", "channel": "Red", "gamma": "1.0", "brightness_contrast": "0,20",
    "auto_level": "", "contrast_stretch": "1", "clahe": "8x8+128+3",
    "threshold": "50", "median": "1", "negate": "", "sharpen": "0x1",
}

class ProcessingError(ValueError):
    pass


def _number(raw, label, minimum, maximum):
    try:
        value = float(str(raw))
    except (TypeError, ValueError):
        raise ProcessingError(f"{label} requires a numeric value.") from None
    if not math.isfinite(value) or not minimum <= value <= maximum:
        raise ProcessingError(f"{label} must be between {minimum} and {maximum}.")
    return format(value, ".12g")


def normalize_operations(operations):
    if not isinstance(operations, list) or len(operations) > MAX_OPERATIONS:
        raise ProcessingError(f"At most {MAX_OPERATIONS} processing steps are supported.")
    out = []
    for op in operations:
        if not isinstance(op, dict) or set(op) != {"kind", "value"}:
            raise ProcessingError("Each processing step requires kind and value only.")
        kind, value = op["kind"], str(op["value"]).strip()
        if kind not in OPERATION_KINDS:
            raise ProcessingError(f"Unsupported processing operation: {kind}")
        if kind in {"grayscale", "auto_level", "negate"}:
            if value:
                raise ProcessingError(f"{kind} does not accept parameters.")
        elif kind == "channel":
            if value not in {"Red", "Green", "Blue", "Luminance"}:
                raise ProcessingError("Channel must be Red, Green, Blue or Luminance.")
        elif kind == "gamma":
            value = _number(value, "Gamma", 0.05, 10)
        elif kind == "brightness_contrast":
            parts = value.split(",")
            if len(parts) != 2:
                raise ProcessingError("Brightness/contrast requires brightness,contrast.")
            value = ",".join(_number(part, "Brightness/contrast", -100, 100) for part in parts)
        elif kind == "contrast_stretch":
            value = _number(value, "Contrast stretch percentage", 0, 20)
        elif kind == "threshold":
            value = _number(value, "Threshold percentage", 0, 100)
        elif kind == "median":
            value = _number(value, "Median radius", 1, 10)
        elif kind == "clahe":
            if not re.fullmatch(r"(?:[248]|16|32)x(?:[248]|16|32)\+(?:64|128|256)\+(?:1|2|3|4|5)", value):
                raise ProcessingError("CLAHE requires WxH+bins+clip, e.g. 8x8+128+3.")
        elif kind == "sharpen":
            if not re.fullmatch(r"0x(?:0\.[1-9]|[1-4](?:\.[0-9])?)", value):
                raise ProcessingError("Sharpen requires 0xSigma in the allowed range 0.1–4.9.")
        out.append({"kind": kind, "value": value})
    return out


def command_arguments(operations):
    args = []
    for op in normalize_operations(operations):
        kind, v = op["kind"], op["value"]
        if kind == "grayscale": args.extend(["-colorspace", "Gray"])
        elif kind == "channel":
            if v == "Luminance": args.extend(["-colorspace", "Gray"])
            else: args.extend(["-channel", v[0], "-separate", "+channel"])
        elif kind == "gamma": args.extend(["-gamma", v])
        elif kind == "brightness_contrast": args.extend(["-brightness-contrast", v.replace(",", "x")])
        elif kind == "auto_level": args.extend(["-auto-level"])
        elif kind == "contrast_stretch": args.extend(["-contrast-stretch", f"{v}%"])
        elif kind == "clahe": args.extend(["-clahe", v])
        elif kind == "threshold": args.extend(["-threshold", f"{v}%"])
        elif kind == "median": args.extend(["-median", v])
        elif kind == "negate": args.extend(["-negate"])
        elif kind == "sharpen": args.extend(["-sharpen", v])
    return args


def image_fingerprint(source_id, sha256, operations, engine_version):
    body = {"schema": 1, "source_dataset_id": source_id, "source_sha256": sha256,
            "operations": normalize_operations(operations), "engine": engine_version}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def apply_processing(source: Image.Image, executable: str, operations):
    operations = normalize_operations(operations)
    if not operations:
        return source.copy()
    if not executable or not os.path.isfile(executable) or not os.access(executable, os.X_OK):
        raise ProcessingError("ImageMagick is unavailable. Configure it under GX-TXT Configuration > Runtime.")
    if source.width * source.height > MAX_PIXELS:
        raise ProcessingError("Image exceeds the processing pixel safety limit.")
    stream = io.BytesIO()
    source.save(stream, "PNG")
    # Do not use shell=True, user paths, image geometry operators or MVG/URL delegates.
    # The input is the already decoded canonical raster, not a path or remote URL.
    cmd = [executable, "-limit", "thread", "2", "png:-", *command_arguments(operations), "png:-"]
    try:
        completed = subprocess.run(cmd, input=stream.getvalue(), capture_output=True,
                                   timeout=75, check=False)
    except subprocess.TimeoutExpired as exc:
        raise ProcessingError("ImageMagick processing exceeded the runtime limit.") from exc
    except OSError as exc:
        raise ProcessingError(f"ImageMagick could not start: {exc}") from exc
    if completed.returncode:
        detail = completed.stderr.decode("utf-8", "replace")[-800:]
        raise ProcessingError(f"ImageMagick processing failed: {detail}")
    if not completed.stdout or len(completed.stdout) > MAX_OUTPUT_BYTES:
        raise ProcessingError("ImageMagick returned an empty or oversized image.")
    try:
        decoded = Image.open(io.BytesIO(completed.stdout))
        decoded.load()
        if decoded.size != source.size:
            raise ProcessingError("Processing modified image dimensions; output was rejected.")
        if getattr(decoded, "n_frames", 1) != 1:
            raise ProcessingError("Processing must produce exactly one raster image.")
        return decoded.convert("RGB")
    except (OSError, UnidentifiedImageError) as exc:
        raise ProcessingError("ImageMagick returned an undecodable raster.") from exc


def metadata(source_id, source_sha256, source_display_name, image, operations, version):
    steps = normalize_operations(operations)
    if not steps: raise ProcessingError("Publish requires at least one processing operation.")
    if not re.fullmatch(r"[a-fA-F0-9]{64}", source_sha256):
        raise ProcessingError("A verified original image SHA-256 is required.")
    fields = {
        "curve_digitizer.image_processing.schema_version": "1",
        "curve_digitizer.image_processing.producer_id": "viewer.curve_digitizer",
        "curve_digitizer.image_processing.source_dataset_id": source_id,
        "curve_digitizer.image_processing.source_display_name": source_display_name,
        "curve_digitizer.image_processing.source_sha256": source_sha256.lower(),
        "curve_digitizer.image_processing.engine": "ImageMagick",
        "curve_digitizer.image_processing.engine_version": version,
        "curve_digitizer.image_processing.geometry_preserved": "1",
        "curve_digitizer.image_processing.pixel_transform": "identity",
        "curve_digitizer.image_processing.image_width": str(image.width),
        "curve_digitizer.image_processing.image_height": str(image.height),
        "curve_digitizer.image_processing.operation_count": str(len(steps)),
        "curve_digitizer.image_processing.fingerprint": image_fingerprint(source_id, source_sha256, steps, version),
    }
    for idx, op in enumerate(steps):
        fields[f"curve_digitizer.image_processing.operation.{idx}.kind"] = op["kind"]
        fields[f"curve_digitizer.image_processing.operation.{idx}.value"] = op["value"]
    return fields
