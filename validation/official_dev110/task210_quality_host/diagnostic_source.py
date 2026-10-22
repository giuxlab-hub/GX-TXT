"""TASK210 TEST ONLY: synthetic reader-format inputs, not Digitizer production.

Run only as a genuinely registered Session Python Script through CORE. The
Bridge supplies analysis.python_script ownership; no module/context is asserted.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import json
import struct
import zlib
from pathlib import Path
from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call

gxtxt_api_require("DATASET_FILE_PUBLICATION_API_v1@1")
gxtxt_api_require("DATASET_PUBLICATION_API_v2@2")
context = gxtxt_context()
assert context["module_id"] == "analysis.python_script", "Requires the genuine registered Python Script runner"
output = Path(context["output_dir"])
description = "TASK210 TEST ONLY synthetic reader-format fixture; not vendor GUI production or scientific result"


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


# An independent, deliberately featureless 8x8 PNG. No calibration is inferred.
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff\xff\xff" * 8) * 8)) + chunk(b"IEND", b""))
image = output / "TASK210_DIAGNOSTIC_ONLY.png"
image.write_bytes(png)
receipts = []
for state in ("clean", "changed", "missing"):
    source_id = "qa210.source." + state
    dataset_id = "qa210.reader_format." + state
    diagnostic = {"diagnostic.task": "GX-TXT TASK210", "diagnostic.synthetic": "1",
                  "diagnostic.author": "GX210-MAIN1-SUB1 registered Python Script",
                  "diagnostic.claim": description, "diagnostic.planned_source_state": state}
    source = gxtxt_api_call("DATASET_FILE_PUBLICATION_API_v1", "publish", [{
        "dataset_id": source_id, "contract": "image.raster", "format": "png",
        "source_file": str(image), "storage_kind": "binary", "media_type": "image/png",
        "source": description, "provenance": description,
        "structured_metadata": dict(diagnostic), "immutable": False}])
    # plugin_id and report producer are REQUIRED READER-FORMAT DISCRIMINATORS.
    # Neither asserts the actual producer; CORE registry ownership remains the
    # real analysis.python_script runner, verified by the host before inspection.
    report = {"schema_version": "2", "producer": "viewer.curve_digitizer",
              "diagnostic_only": True, "actual_producer": "analysis.python_script",
              "claim": description, "point_origins": {"synthetic_diagnostic": 3},
              "curves": [], "calibrations": [], "issues": {"items": []},
              "segments": {"total": 0, "returned": 0, "truncated": False, "records": []},
              "image_evidence": {"available": False, "limitations": description}}
    metadata = dict(diagnostic)
    metadata.update({"dataset.display_name": "TEST ONLY synthetic Quality/source " + state,
        "curve_digitizer.plugin_id": "viewer.curve_digitizer",
        "curve_digitizer.source_dataset_id": source_id,
        "curve_digitizer.source_sha256": source["sha256"],
        "curve_digitizer.curve_schema_version": "1", "curve_digitizer.curve_mode": "independent",
        "curve_digitizer.curve_grouping": "curve_key", "curve_digitizer.curve_row_dimension": "row",
        "curve_digitizer.quality_schema_version": "2",
        "curve_digitizer.quality_report_json": json.dumps(report, separators=(",", ":")),
        "curve_digitizer.quality_status": "diagnostic_only_not_assessed",
        "curve_digitizer.quality_issue_count": "0", "curve_digitizer.quality_source_point_count": "3",
        "curve_digitizer.quality_published_row_count": "3", "curve_digitizer.quality_curve_count": "1",
        "curve_digitizer.quality_calibration_realizations": "0", "curve_digitizer.quality_segment_count": "0",
        "curve_digitizer.quality_evidence_available": "0", "curve_digitizer.image_width": "8",
        "curve_digitizer.image_height": "8"})
    values = {"x": [0.0, 1.0, 2.0], "y": [0.0, 1.0, 0.0],
              "curve_key": ["synthetic-only"] * 3, "curve_name": ["TEST ONLY"] * 3,
              "point_order": [0, 1, 2], "raster_x": [1.0, 3.0, 5.0], "raster_y": [2.0, 4.0, 2.0]}
    for role in values:
        metadata["curve_digitizer.curve_column." + role] = role
    writer = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "begin", [{
        "dataset_id": dataset_id, "contract": "table.generic", "storage": "csv",
        "expected_rows": 3, "estimated_numeric_bytes": 120, "source_dataset_ids": [source_id],
        "source": description, "provenance": description, "structured_metadata": metadata}])
    try:
        gxtxt_api_call("DATASET_PUBLICATION_API_v2", "declare_dimension", [writer, "row", 0, {"extendible": True}])
        for role, data in values.items():
            dtype = "string" if role in ("curve_key", "curve_name") else ("int64" if role == "point_order" else "float64")
            unit = "px" if role in ("raster_x", "raster_y") else ("1" if dtype != "string" else "")
            gxtxt_api_call("DATASET_PUBLICATION_API_v2", "declare_variable", [writer, role, {
                "dtype": dtype, "rank": 1, "dimension_ids": ["row"], "display_label": "TEST ONLY " + role,
                "unit": unit, "semantic_role": role, "coordinate_role": "data"}])
        # The CSV owner's supported table operation appends every declared
        # column together; complete-variable writes are single-column only.
        gxtxt_api_call("DATASET_PUBLICATION_API_v2", "append", [writer, "row", values])
        table = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "finalize", [writer])
    except BaseException:
        gxtxt_api_call("DATASET_PUBLICATION_API_v2", "abort", [writer])
        raise
    receipts.append({"state": state, "source": source, "table": table})
(output / "DIAGNOSTIC_PUBLICATIONS.json").write_text(json.dumps({
    "scope": description, "actual_script_context": context, "publications": receipts}, indent=2), encoding="utf-8")
print("DIAGNOSTIC_FIXTURES_PUBLISHED; no vendor GUI/scientific acceptance")
