# GX-TXT Python Script Workspace tutorial:
# perform framework-native Fourier/spectral analysis on a bounded selection
# from the large HDF5 signal Dataset.
#
# Periodogram and Welch PSD use SIGNAL_API_v1.
# dB conversion uses NUMERIC_API_v1.
# Results are published and plotted through normal GX-TXT APIs.
#
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call
import numpy as np
import time


SPECTRUM_DATASET_ID = "tutorial.large_signal_spectrum"

ANALYSIS_SAMPLES = 1 << 19      # 524,288
PERIODOGRAM_SAMPLES = 1 << 16   # 65,536
NFFT = 1 << 16                  # 65,536
STREAM_CHUNK_ROWS = 1 << 17     # 131,072
PSD_FLOOR = 1e-30


def signal_empty():
    return {"kind": "empty"}


def signal_array(values):
    array = np.asarray(values, dtype=float).reshape(-1)
    return {"kind": "array", "shape": [int(array.size), 1], "real": array}


def signal_scalar(value):
    return signal_array(np.asarray([float(value)], dtype=float))


def signal_struct(fields):
    return {"kind": "struct", "fields": fields}


def numeric_vector(values):
    return {"kind": "vector", "value": np.asarray(values, dtype=float).reshape(-1)}


def numeric_scalar(value):
    return {"kind": "scalar", "value": float(value)}


def numeric_unary(operation, values):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_unary",
        [operation, numeric_vector(values)],
    )
    return np.asarray(result["values"], dtype=float).reshape(-1)


def numeric_binary_vector_scalar(operation, values, scalar):
    result = gxtxt_api_call(
        "NUMERIC_API_v1",
        "array_binary",
        [operation, numeric_vector(values), numeric_scalar(scalar)],
    )
    return np.asarray(result["values"], dtype=float).reshape(-1)


def read_range_stream(dataset_id, variable_id, start, count):
    stream = gxtxt_api_call(
        "TABLE_STREAM_API_v3",
        "open_dataset",
        [
            dataset_id,
            [variable_id],
            STREAM_CHUNK_ROWS,
            {
                "start": int(start),
                "count": int(count),
                "require_direct": True,
            },
        ],
    )
    blocks = []
    try:
        while True:
            chunk = gxtxt_api_call("TABLE_STREAM_API_v3", "next", [stream])
            values = np.asarray(
                chunk["values"][variable_id], dtype=float
            ).reshape(-1)
            if values.size:
                blocks.append(values)
            if bool(chunk.get("eof", False)):
                break
        diagnostics = gxtxt_api_call(
            "TABLE_STREAM_API_v3", "diagnostics", [stream]
        )
    finally:
        gxtxt_api_call("TABLE_STREAM_API_v3", "close", [stream])

    if not blocks:
        raise RuntimeError("FOURIER: selected range is empty")
    return np.concatenate(blocks), diagnostics


ctx = gxtxt_context()

gxtxt_api_require([
    "TABLE_STREAM_API_v3@3",
    "DATASET_METADATA_API_v1@1",
    "SIGNAL_API_v1@1:math.signal",
    "NUMERIC_API_v1@1:math.numeric",
    "DATASET_PUBLICATION_API_v2@2",
    "PLOT_DATASET_API_v3@3:plot.dataset+plotspec",
    "SESSION_PERSISTENCE_API_v1@1",
])

primary = ctx.get("inputs", {}).get("primary")
if not isinstance(primary, dict) or not primary.get("dataset_id"):
    raise RuntimeError(
        "FOURIER: bind tutorial.large_noisy_multitone to Analysis Source 'primary'"
    )

dataset_id = str(primary["dataset_id"])
metadata = gxtxt_api_call("DATASET_METADATA_API_v1", "read", [dataset_id])

signal_variable_id = str(metadata.get("schema.signal_variable_id", "")).strip()
sample_rate_hz = float(metadata.get("generation.sample_rate_hz", "0"))
sample_count = int(metadata.get("generation.sample_count", "0"))

if not signal_variable_id or sample_rate_hz <= 0 or sample_count < ANALYSIS_SAMPLES:
    raise RuntimeError("FOURIER: source metadata is incomplete or incompatible")

start_sample = (sample_count - ANALYSIS_SAMPLES) // 2

read_start = time.perf_counter()
signal_values, stream_diagnostics = read_range_stream(
    dataset_id,
    signal_variable_id,
    start_sample,
    ANALYSIS_SAMPLES,
)
read_seconds = time.perf_counter() - read_start

if signal_values.size != ANALYSIS_SAMPLES:
    raise RuntimeError(
        f"FOURIER: requested {ANALYSIS_SAMPLES} samples, received {signal_values.size}"
    )

periodogram_input = signal_values[:PERIODOGRAM_SAMPLES]

periodogram_start = time.perf_counter()
periodogram = gxtxt_api_call(
    "SIGNAL_API_v1",
    "spectral.periodogram",
    [
        signal_array(periodogram_input),
        signal_empty(),
        signal_scalar(sample_rate_hz),
        signal_struct({
            "nfft": signal_scalar(NFFT),
        }),
    ],
)
periodogram_seconds = time.perf_counter() - periodogram_start

welch_start = time.perf_counter()
welch = gxtxt_api_call(
    "SIGNAL_API_v1",
    "spectral.welch",
    [
        signal_array(signal_values),
        signal_empty(),
        signal_scalar(sample_rate_hz),
        signal_struct({
            "nfft": signal_scalar(NFFT),
            "overlap": signal_scalar(0.5),
        }),
    ],
)
welch_seconds = time.perf_counter() - welch_start

frequency_periodogram = np.asarray(
    periodogram["frequency_hz"], dtype=float
).reshape(-1)
frequency_welch = np.asarray(
    welch["frequency_hz"], dtype=float
).reshape(-1)
psd_periodogram = np.asarray(
    periodogram["psd_real"], dtype=float
).reshape(-1)
psd_welch = np.asarray(
    welch["psd_real"], dtype=float
).reshape(-1)

if frequency_periodogram.size != frequency_welch.size:
    raise RuntimeError("FOURIER: periodogram and Welch frequency grids differ in length")
if not np.allclose(
    frequency_periodogram, frequency_welch, rtol=0.0, atol=1e-12
):
    raise RuntimeError("FOURIER: periodogram and Welch frequency grids differ")

# Framework numerical API performs the PSD -> dB conversion.
safe_periodogram = numeric_binary_vector_scalar(
    "maximum", psd_periodogram, PSD_FLOOR
)
safe_welch = numeric_binary_vector_scalar(
    "maximum", psd_welch, PSD_FLOOR
)
periodogram_db = numeric_binary_vector_scalar(
    "multiply", numeric_unary("log10", safe_periodogram), 10.0
)
welch_db = numeric_binary_vector_scalar(
    "multiply", numeric_unary("log10", safe_welch), 10.0
)

definition = {
    "dataset_id": SPECTRUM_DATASET_ID,
    "contract": "table.generic",
    "storage": "auto",
    "replace_owned": True,
    "producer_version": "1.0.0",
    "source_dataset_ids": [dataset_id],
    "source_variable_ids": [signal_variable_id],
    "source": "Python Script Workspace framework Fourier tutorial",
    "provenance": (
        "Periodogram and Welch PSD computed through SIGNAL_API_v1 from a direct "
        "HDF5 range selected through TABLE_STREAM_API_v3. dB conversion uses "
        "NUMERIC_API_v1."
    ),
    "notes": "Fourier/spectral comparison for the large noisy multi-tone Dataset.",
}

writer = gxtxt_api_call("DATASET_PUBLICATION_API_v2", "begin", [definition])
try:
    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "declare_dimension",
        [writer, "frequency", 0, {"extendible": 1}],
    )

    variables = (
        ("v_frequency_hz", "Hz", "coordinate", "independent"),
        ("v_periodogram_psd_v2_hz", "V^2/Hz", "data", "derived"),
        ("v_welch_psd_v2_hz", "V^2/Hz", "data", "derived"),
        ("v_periodogram_db_hz", "dB", "data", "derived"),
        ("v_welch_db_hz", "dB", "data", "derived"),
    )
    for variable_id, unit, coordinate_role, semantic_role in variables:
        gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2",
            "declare_variable",
            [
                writer,
                variable_id,
                {
                    "dtype": "float64",
                    "rank": 1,
                    "dimension_ids": "frequency",
                    "coordinate_role": coordinate_role,
                    "unit": unit,
                    "semantic_role": semantic_role,
                },
            ],
        )

    gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2",
        "append",
        [
            writer,
            "frequency",
            {
                "v_frequency_hz": frequency_welch,
                "v_periodogram_psd_v2_hz": psd_periodogram,
                "v_welch_psd_v2_hz": psd_welch,
                "v_periodogram_db_hz": periodogram_db,
                "v_welch_db_hz": welch_db,
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

spectrum_metadata = {
    "spectral.kind": "periodogram_and_welch",
    "spectral.backend": "SIGNAL_API_v1",
    "spectral.db_backend": "NUMERIC_API_v1",
    "spectral.source_dataset_id": dataset_id,
    "spectral.source_variable_id": signal_variable_id,
    "spectral.sample_rate_hz": f"{sample_rate_hz:.17g}",
    "spectral.selection_start_sample": str(start_sample),
    "spectral.selection_count": str(ANALYSIS_SAMPLES),
    "spectral.periodogram_samples": str(PERIODOGRAM_SAMPLES),
    "spectral.nfft": str(NFFT),
    "spectral.welch_overlap": "0.5",
    "performance.range_read_seconds": f"{read_seconds:.17g}",
    "performance.periodogram_seconds": f"{periodogram_seconds:.17g}",
    "performance.welch_seconds": f"{welch_seconds:.17g}",
    "stream.diagnostics": str(stream_diagnostics),
}

gxtxt_api_call(
    "DATASET_METADATA_API_v1",
    "update",
    [SPECTRUM_DATASET_ID, spectrum_metadata],
)

# Native Plot Dataset overlay.
spec = gxtxt_api_call(
    "PLOT_DATASET_API_v3",
    "new_spec",
    ["plot.dataset.xy", "Large noisy signal Fourier analysis"],
)

periodogram_series = {
    "id": "periodogram",
    "dataset_id": SPECTRUM_DATASET_ID,
    "x_variable_id": "v_frequency_hz",
    "y_variable_id": "v_periodogram_db_hz",
    "axis": "left",
    "kind": "line",
    "label": "Periodogram",
}
welch_series = {
    "id": "welch",
    "dataset_id": SPECTRUM_DATASET_ID,
    "x_variable_id": "v_frequency_hz",
    "y_variable_id": "v_welch_db_hz",
    "axis": "left",
    "kind": "line",
    "label": "Welch",
}

panel = {
    "id": "main",
    "title": "PSD comparison",
    "axes": {
        "x": {"label": "Frequency [Hz]"},
        "y_left": {"label": "PSD [dB V^2/Hz]"},
    },
    "annotations": [],
    "series": [periodogram_series, welch_series],
}
spec["panels"] = [panel]

if not gxtxt_api_call(
    "PLOT_DATASET_API_v3", "validate_spec", [spec]
):
    raise RuntimeError("FOURIER: PlotSpec validation returned false")

plot_ref = gxtxt_api_call(
    "PLOT_DATASET_API_v3", "create_plot", [spec, "variant"]
)
gxtxt_api_call("PLOT_DATASET_API_v3", "render", [plot_ref])
artifacts = gxtxt_api_call(
    "PLOT_DATASET_API_v3", "artifacts", [plot_ref]
)

gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

print(
    "PASS LARGE_SIGNAL_FOURIER "
    f"source={dataset_id} spectrum={published['dataset_id']} "
    f"selected_samples={ANALYSIS_SAMPLES} nfft={NFFT} "
    f"read_seconds={read_seconds:.6g} "
    f"periodogram_seconds={periodogram_seconds:.6g} "
    f"welch_seconds={welch_seconds:.6g} "
    f"variant={plot_ref['variant_id']} "
    f"artifact={artifacts.get('graph_artifact', '')}"
)
print(f"FOURIER stream_diagnostics={stream_diagnostics}")
