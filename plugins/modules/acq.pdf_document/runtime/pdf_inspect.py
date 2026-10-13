#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read the minimum canonical PDF document properties for acq.pdf_document.

The helper performs no OCR, text extraction, page rendering, repair or rewrite.
It emits a compact UTF-8-safe line protocol consumed by the Tcl acquisition
handler. Fatal validation errors are reported on stderr with a non-zero exit.
"""
from __future__ import annotations

import argparse
import base64
import logging
import os
import re
import sys
from pathlib import Path


def b64(value: object) -> str:
    return base64.b64encode(str(value).encode("utf-8", "strict")).decode("ascii")


def emit_meta(key: str, value: object) -> None:
    print(f"M\t{b64(key)}\t{b64(value)}")


def emit_warning(message: str) -> None:
    print(f"W\t{b64(message)}")


def fail(message: str) -> "None":
    print(message, file=sys.stderr)
    raise SystemExit(2)


def pdf_header_version(path: Path) -> str:
    try:
        with path.open("rb") as fh:
            head = fh.read(1024)
    except OSError as exc:
        fail(f"PDF source could not be read: {exc}")
    match = re.search(br"%PDF-([0-9]+\.[0-9]+)", head)
    if match is None:
        fail("PDF signature was not detected in the document header")
    return match.group(1).decode("ascii", "strict")


def text_value(value: object) -> str | None:
    if value is None:
        return None
    try:
        out = str(value)
    except Exception:
        return None
    return out if out != "" else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ns = ap.parse_args()
    path = Path(ns.input)
    if not path.is_file():
        fail("PDF source is not a regular file")
    if not os.access(path, os.R_OK):
        fail("PDF source is not readable")

    version = pdf_header_version(path)

    try:
        from pypdf import PdfReader
    except Exception as exc:
        fail(f"Required Python package pypdf is unavailable: {exc}")

    # pypdf may recover old but readable xref tables and log a warning to
    # stderr. Preserve that warning in our protocol instead of mixing it into
    # the machine-readable stdout stream consumed by the Tcl handler.
    parser_warnings: list[str] = []

    class CaptureWarnings(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            parser_warnings.append(record.getMessage())

    pdf_logger = logging.getLogger("pypdf")
    pdf_logger.addHandler(CaptureWarnings())
    pdf_logger.propagate = False
    try:
        reader = PdfReader(str(path), strict=True)
    except Exception as exc:
        fail(f"PDF structure is invalid or unreadable: {exc}")

    encrypted = bool(getattr(reader, "is_encrypted", False))
    if encrypted:
        # Empty-password encryption can be inspected without asking the user for
        # a secret. Password-protected documents that hide mandatory properties
        # fail explicitly because page_count is part of document.pdf validity.
        try:
            reader.decrypt("")
        except Exception:
            pass

    try:
        page_count = len(reader.pages)
    except Exception as exc:
        if encrypted:
            fail(f"Encrypted PDF cannot be inspected sufficiently for import: {exc}")
        fail(f"PDF page tree is invalid or unreadable: {exc}")
    if page_count < 1:
        fail("PDF contains no importable pages")

    print("GXPDF1")
    emit_meta("document.format", "PDF")
    emit_meta("document.page_count", page_count)
    emit_meta("pdf.version", version)
    emit_meta("pdf.encrypted", "true" if encrypted else "false")

    metadata_map = {
        "/Title": "pdf.title",
        "/Author": "pdf.author",
        "/Subject": "pdf.subject",
        "/Keywords": "pdf.keywords",
        "/Creator": "pdf.creator",
        "/Producer": "pdf.producer",
        "/CreationDate": "pdf.creation_date",
        "/ModDate": "pdf.modification_date",
    }
    try:
        md = reader.metadata
    except Exception as exc:
        md = None
        emit_warning(f"Optional PDF document metadata could not be read: {exc}")
    if md:
        for src_key, dst_key in metadata_map.items():
            try:
                value = text_value(md.get(src_key))
            except Exception as exc:
                emit_warning(f"Optional metadata field {src_key} could not be read: {exc}")
                continue
            if value is not None:
                emit_meta(dst_key, value)

    for warning in parser_warnings:
        emit_warning(f"PDF parser: {warning}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
