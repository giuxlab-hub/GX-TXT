# GX-TXT Python Script Workspace tutorial:
# stream the complete large HDF5 Dataset with bounded memory and compute
# chunk-wise statistics through NUMERIC_API_v1.
#
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call
import numpy as np
import time
import math


SUMMARY_DATASET_ID = "tutorial.large_signal_stream_summary"
STREAM_CHUNK_ROWS = 1 << 18     # 262,144


def numeric_vector(values):
    return {"kind": "vector", "value": np.asarray(values, dtype=float).reshape(-1)}


def numeric_scalar(value):
    return {"kind": "scalar", "value": float(value)}


def numeric_reduce(operation, values):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_reduce",
        [operation, numeric_vector(values), {"axis": 0}],
    )
    return float(np.asarray(result["values"], dtype=float).reshape(-1)[0])


def numeric_unary_scalar(operation, value):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_unary",
        [operation, numeric_scalar(value)],
    )
    return float(np.asarray(result["values"], dtype=float).reshape(-1)[0])


ctx = gxtxt_context()

gxtxt_api_require([
    "TABLE_STREAM_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "NUMERIC_API_v1@1:math.numeric",
    "DATASET_PUBLICATION_API_v2@2",
    "SESSION_PERSISTENCE_API_v1@1",
])

primary = ctx.get("inputs", {}).get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError(
        "LARGE_STREAM: bind tutorial.large_noisy_multitone to Analysis Source 'primary'"
    )

dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [dataset_id])
signal_variable_id = str(metadata.get("schema.signal_variable_id", "")).strip()
if not signal_variable_id:
    raise RuntimeError("LARGE_STREAM: source Dataset metadata lacks schema.signal_variable_id")

stream = gxtxt_api_call(
    "TABLE_STREAM_API_v3",
    "open_dataset",
    [
        dataset_id,
        [signal_variable_id],
        STREAM_CHUNK_ROWS,
        {"start": 0, "count": -1, "require_direct": True},
    ],
)

total_count = 0
total_sum = 0.0
total_sum_squares = 0.0
global_min = None
global_max = None
chunk_count = 0

scan_start = time.perf_counter()
try:
    stream_metadata = gxtxt_api_call(
        "TABLE_STREAM_API_v3", "metadata", [stream]
    )

    while True:
        chunk = gxtxt_api_call("TABLE_STREAM_API_v3", "next", [stream])
        values = np.asarray(
            chunk["values"][signal_variable_id], dtype=float
        ).reshape(-1)

        if values.size:
            # The heavy numerical reductions are framework operations.
            chunk_sum = numeric_reduce("sum", values)
            chunk_rms = numeric_reduce("rms", values)
            chunk_min = numeric_reduce("minimum", values)
            chunk_max = numeric_reduce("maximum", values)

            n = int(values.size)
            total_count += n
            total_sum += chunk_sum
            total_sum_squares += (chunk_rms * chunk_rms) * n
            global_min = chunk_min if global_min is None else min(global_min, chunk_min)
            global_max = chunk_max if global_max is None else max(global_max, chunk_max)
            chunk_count += 1

            if chunk_count % 4 == 0:
                elapsed = time.perf_counter() - scan_start
                print(
                    f"LARGE_STREAM chunks={chunk_count} rows={total_count} "
                    f"elapsed={elapsed:.3f}s"
                )

        if bool(chunk.get("eof", False)):
            break

    diagnostics = gxtxt_api_call(
        "TABLE_STREAM_API_v3", "diagnostics", [stream]
    )
finally:
    gxtxt_api_call("TABLE_STREAM_API_v3", "close", [stream])

scan_seconds = time.perf_counter() - scan_start
if total_count < 1:
    raise RuntimeError("LARGE_STREAM: no observations were read")

mean_value = total_sum / total_count
mean_square = total_sum_squares / total_count
rms_value = numeric_unary_scalar("sqrt", mean_square)
throughput = total_count / scan_seconds

definition = {
    "dataset_id": SUMMARY_DATASET_ID,
    "contract": "table.generic",
    "storage": "auto",
    "replace_owned": True,
    "producer_version": "1.0.0",
    "source_dataset_ids": [dataset_id],
    "source_variable_ids": [signal_variable_id],
    "source": "Python Script Workspace large Dataset stream benchmark",
    "provenance": (
        "Complete bounded-memory scan through TABLE_STREAM_API_v3. "
        "Chunk reductions use NUMERIC_API_v1."
    ),
    "notes": "One-row summary of the complete large signal Dataset.",
}

writer = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "begin", [definition])
try:
    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "declare_dimension",
        [writer, "row", 0, {"extendible": 1}],
    )

    variables = (
        ("v_sample_count", "", "derived"),
        ("v_mean_v", "V", "derived"),
        ("v_rms_v", "V", "derived"),
        ("v_min_v", "V", "derived"),
        ("v_max_v", "V", "derived"),
        ("v_scan_seconds", "s", "derived"),
        ("v_samples_per_second", "1/s", "derived"),
    )
    for variable_id, unit, role in variables:
        gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2",
            "declare_variable",
            [
                writer,
                variable_id,
                {
                    "dtype": "float64",
                    "rank": 1,
                    "dimension_ids": "row",
                    "coordinate_role": "data",
                    "unit": unit,
                    "semantic_role": role,
                },
            ],
        )

    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "append",
        [
            writer,
            "row",
            {
                "v_sample_count": np.asarray([float(total_count)]),
                "v_mean_v": np.asarray([mean_value]),
                "v_rms_v": np.asarray([rms_value]),
                "v_min_v": np.asarray([global_min]),
                "v_max_v": np.asarray([global_max]),
                "v_scan_seconds": np.asarray([scan_seconds]),
                "v_samples_per_second": np.asarray([throughput]),
            },
        ],
    )
    published = gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2", "finalize", [writer]
    )
    writer = None
except Exception:
    if writer is not None:
        gxtxt_api_call("DATASET_PUBLICATION_API_v2", "abort", [writer])
    raise

summary_metadata = {
    "benchmark.kind": "large_dataset_full_stream",
    "benchmark.source_dataset_id": dataset_id,
    "benchmark.data_access": "TABLE_STREAM_API_v3",
    "benchmark.numeric_backend": "NUMERIC_API_v1",
    "benchmark.require_direct": "true",
    "benchmark.chunk_rows": str(STREAM_CHUNK_ROWS),
    "benchmark.chunk_count": str(chunk_count),
    "benchmark.sample_count": str(total_count),
    "benchmark.scan_seconds": f"{scan_seconds:.17g}",
    "benchmark.samples_per_second": f"{throughput:.17g}",
    "benchmark.stream_diagnostics": str(diagnostics),
}

gxtxt_api_call(
    "DATASET_METADATA_API_v1",
    "update",
    [SUMMARY_DATASET_ID, summary_metadata],
)
gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS LARGE_STREAM_SCAN "
    f"source={dataset_id} samples={total_count} chunks={chunk_count} "
    f"mean={mean_value:.9g}V rms={rms_value:.9g}V "
    f"min={global_min:.9g}V max={global_max:.9g}V "
    f"seconds={scan_seconds:.6g} "
    f"throughput={throughput:.6g} samples/s "
    f"summary={published['dataset_id']}"
)
print(f"LARGE_STREAM diagnostics={diagnostics}")
