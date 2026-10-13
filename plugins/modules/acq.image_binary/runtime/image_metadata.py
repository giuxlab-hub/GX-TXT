#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Extract non-pixel image metadata for acq.image_binary.

Protocol on stdout:
    GXIMGMD1
    M<TAB>base64(utf8 key)<TAB>base64(utf8 value)
    W<TAB>base64(utf8 warning)

The helper never emits raw binary profiles. It opens the image only far enough to
inspect container/header metadata; pixel arrays are not decoded intentionally.
"""
from __future__ import annotations

import argparse
import base64
import re
import sys
from typing import Any, Dict, Iterable, Tuple

try:
    from PIL import ExifTags, Image, IptcImagePlugin
except Exception as exc:  # pragma: no cover - exercised by Tcl fail-soft path
    raise SystemExit(f"Pillow is required for extended image metadata: {exc}")

MAX_TEXT = 65536
MAX_FIELD = 16384


def b64(text: str) -> str:
    return base64.b64encode(text.encode("utf-8", "replace")).decode("ascii")


def emit_metadata(key: str, value: Any) -> None:
    text = clean_text(value)
    if text == "":
        return
    print(f"M\t{b64(key)}\t{b64(text)}")


def emit_warning(message: str) -> None:
    print(f"W\t{b64(message)}")


def slug(text: Any) -> str:
    s = str(text).strip().lower()
    s = re.sub(r"[^0-9a-z_-]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s or "field"


def clean_text(value: Any, limit: int = MAX_FIELD) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        text = "1" if value else "0"
    elif isinstance(value, (int, float)):
        text = str(value)
    elif isinstance(value, bytes):
        # Keep textual metadata readable, but never expand opaque/binary profiles.
        decoded = None
        for enc in ("utf-8", "latin-1"):
            try:
                candidate = value.decode(enc)
            except UnicodeDecodeError:
                continue
            printable = sum(ch.isprintable() or ch in "\r\n\t" for ch in candidate)
            if candidate and printable / max(1, len(candidate)) >= 0.90:
                decoded = candidate
                break
        text = decoded if decoded is not None else f"<binary:{len(value)} bytes>"
    elif hasattr(value, "numerator") and hasattr(value, "denominator"):
        try:
            n = int(value.numerator)
            d = int(value.denominator)
            text = f"{n}/{d}" if d else str(value)
        except Exception:
            text = str(value)
    elif isinstance(value, (list, tuple)):
        text = ", ".join(clean_text(v, 2048) for v in value)
    elif isinstance(value, dict):
        parts = []
        for k in sorted(value, key=lambda x: str(x)):
            parts.append(f"{clean_text(k, 512)}={clean_text(value[k], 2048)}")
        text = "; ".join(parts)
    else:
        text = str(value)
    text = text.replace("\x00", "")
    if len(text) > limit:
        text = text[:limit] + f" … <truncated; original {len(text)} chars>"
    return text


def add_if_absent(md: Dict[str, str], key: str, value: Any) -> None:
    text = clean_text(value)
    if text and key not in md:
        md[key] = text


def add_exif_ifd(md: Dict[str, str], ifd_name: str, items: Iterable[Tuple[Any, Any]], tag_names: Dict[int, str]) -> Dict[str, Any]:
    by_name: Dict[str, Any] = {}
    for tag_id, value in items:
        try:
            tid = int(tag_id)
        except Exception:
            tid = -1
        name = tag_names.get(tid, f"tag_{tag_id}")
        field = f"{tid}_{slug(name)}" if tid >= 0 else slug(name)
        md[f"image.exif.{ifd_name}.{field}"] = clean_text(value)
        by_name[name] = value
    return by_name


def extract(path: str) -> Tuple[Dict[str, str], list[str]]:
    md: Dict[str, str] = {}
    warnings: list[str] = []
    with Image.open(path) as im:
        add_if_absent(md, "image.width_px", im.width)
        add_if_absent(md, "image.height_px", im.height)
        add_if_absent(md, "image.mode", im.mode)
        add_if_absent(md, "image.bands", ",".join(im.getbands()))
        add_if_absent(md, "image.frame_count", getattr(im, "n_frames", 1))
        add_if_absent(md, "image.animated", bool(getattr(im, "is_animated", False)))
        add_if_absent(md, "image.has_alpha", "A" in im.getbands())
        if getattr(im, "format", None):
            add_if_absent(md, "image.decoder_format", str(im.format).lower())

        info = getattr(im, "info", {}) or {}
        dpi = info.get("dpi")
        if isinstance(dpi, (tuple, list)) and len(dpi) >= 2:
            add_if_absent(md, "image.dpi_x", dpi[0])
            add_if_absent(md, "image.dpi_y", dpi[1])

        for profile_name, key in (("icc_profile", "image.profile.icc_bytes"), ("exif", "image.profile.exif_bytes"), ("photoshop", "image.profile.photoshop_bytes")):
            value = info.get(profile_name)
            if isinstance(value, (bytes, bytearray)):
                add_if_absent(md, key, len(value))

        # Generic small scalar/text container fields. Binary payloads are represented
        # only by byte counts to keep Dataset Metadata compact and UTF-8 safe.
        skip_info = {"icc_profile", "exif", "photoshop", "xmp", "XML:com.adobe.xmp", "dpi"}
        for key, value in info.items():
            if key in skip_info:
                continue
            out_key = f"image.info.{slug(key)}"
            if isinstance(value, (bytes, bytearray)):
                text = clean_text(value)
                if text.startswith("<binary:"):
                    add_if_absent(md, out_key + "_bytes", len(value))
                else:
                    add_if_absent(md, out_key, text)
            elif isinstance(value, (str, int, float, bool, tuple, list)):
                add_if_absent(md, out_key, value)

        # PNG text chunks have a dedicated dictionary in Pillow.
        text_map = getattr(im, "text", None)
        if isinstance(text_map, dict):
            used: Dict[str, int] = {}
            for name, value in text_map.items():
                base = slug(name)
                used[base] = used.get(base, 0) + 1
                suffix = "" if used[base] == 1 else f"_{used[base]}"
                add_if_absent(md, f"image.text.{base}{suffix}", value)

        # EXIF / TIFF metadata, including nested Exif and GPS IFDs when Pillow exposes them.
        exif = im.getexif()
        root_by_name: Dict[str, Any] = {}
        exif_by_name: Dict[str, Any] = {}
        if exif:
            root_by_name = add_exif_ifd(md, "root", exif.items(), ExifTags.TAGS)
            get_ifd = getattr(exif, "get_ifd", None)
            if callable(get_ifd):
                for ifd_id, ifd_name, names in (
                    (34665, "exif", ExifTags.TAGS),
                    (34853, "gps", getattr(ExifTags, "GPSTAGS", {})),
                    (40965, "interop", {}),
                ):
                    try:
                        nested = get_ifd(ifd_id)
                    except Exception:
                        nested = None
                    if nested:
                        by_name = add_exif_ifd(md, ifd_name, nested.items(), names)
                        if ifd_name == "exif":
                            exif_by_name = by_name

            aliases = {
                "Make": "image.camera_make",
                "Model": "image.camera_model",
                "Software": "image.software",
                "Artist": "image.artist",
                "Copyright": "image.copyright",
                "Orientation": "image.orientation",
                "DateTime": "image.datetime",
            }
            for tag_name, out_key in aliases.items():
                if tag_name in root_by_name:
                    add_if_absent(md, out_key, root_by_name[tag_name])
            exif_aliases = {
                "DateTimeOriginal": "image.datetime_original",
                "DateTimeDigitized": "image.datetime_digitized",
                "ExposureTime": "image.exposure_time",
                "FNumber": "image.f_number",
                "ISOSpeedRatings": "image.iso",
                "PhotographicSensitivity": "image.iso",
                "FocalLength": "image.focal_length",
                "LensModel": "image.lens_model",
                "LensMake": "image.lens_make",
                "UserComment": "image.user_comment",
            }
            combined_exif = dict(root_by_name)
            combined_exif.update(exif_by_name)
            for tag_name, out_key in exif_aliases.items():
                if tag_name in combined_exif:
                    add_if_absent(md, out_key, combined_exif[tag_name])

        # IPTC IIM metadata. Keep numeric record/dataset identity plus common aliases.
        try:
            iptc = IptcImagePlugin.getiptcinfo(im)
        except Exception as exc:
            warnings.append(f"IPTC metadata could not be read: {exc}")
            iptc = None
        if isinstance(iptc, dict):
            iptc_aliases = {
                (2, 5): "image.iptc.object_name",
                (2, 25): "image.iptc.keywords",
                (2, 55): "image.iptc.date_created",
                (2, 80): "image.iptc.byline",
                (2, 116): "image.iptc.copyright_notice",
                (2, 120): "image.iptc.caption",
            }
            for key, value in iptc.items():
                if isinstance(key, tuple) and len(key) == 2:
                    out_key = f"image.iptc.{key[0]}_{key[1]}"
                    add_if_absent(md, out_key, value)
                    alias = iptc_aliases.get(tuple(key))
                    if alias:
                        add_if_absent(md, alias, value)

        # XMP packet: retain textual XML as one opaque metadata value when reasonably
        # sized. The importer does not interpret XMP semantics.
        xmp = info.get("xmp", info.get("XML:com.adobe.xmp"))
        if xmp is None and exif:
            try:
                xmp = exif.get(700)  # XMLPacket
            except Exception:
                xmp = None
        if xmp is not None:
            xmp_text = clean_text(xmp, MAX_TEXT)
            if xmp_text and not xmp_text.startswith("<binary:"):
                add_if_absent(md, "image.xmp.packet", xmp_text)
            elif isinstance(xmp, (bytes, bytearray)):
                add_if_absent(md, "image.xmp.bytes", len(xmp))

    return md, warnings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    args = parser.parse_args()

    print("GXIMGMD1")
    try:
        metadata, warnings = extract(args.input)
    except Exception as exc:
        print(f"W\t{b64(f'Extended image metadata unavailable: {exc}')}")
        return 0

    for key in sorted(metadata):
        emit_metadata(key, metadata[key])
    for warning in warnings:
        emit_warning(warning)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
