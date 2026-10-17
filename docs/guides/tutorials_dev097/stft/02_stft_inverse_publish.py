# GX-TXT Python Script Workspace — STFT, inverse STFT and canonical results.
# SPDX-License-Identifier: GPL-3.0-or-later
# Analysis Source: primary -> tutorial.stft_nonstationary_signal
# The complete complex rank-2 STFT is published as HDF5; small derived
# table Datasets are created for the standard 2D/3D Plot Dataset renderer.

from gxtxt import gxtxt_context, gxtxt_api_call, gxtxt_api_require
import numpy as np
import time

MATRIX_ID = "tutorial.stft_complex_matrix"
RECON_ID = "tutorial.stft_reconstruction"
TRACE_ID = "tutorial.stft_trace_preview"
GRID_ID = "tutorial.stft_spectrogram_xyz"
STREAM_ROWS = 16384
TRACE_STRIDE = 16
GRID_FREQ_STRIDE = 8
GRID_FRAME_STRIDE = 8
PSD_FLOOR = 1.0e-15


def api(api_id, operation, *args):
    return gxtxt_api_call(api_id, operation, list(args))


def a(values):
    v = np.asarray(values, dtype=np.float64).reshape(-1, order="F")
    return {"kind": "array", "shape": [int(v.size), 1], "real": v}


def complex_matrix(real, imaginary):
    r = np.asarray(real, dtype=np.float64)
    im = np.asarray(imaginary, dtype=np.float64)
    if r.ndim != 2 or r.shape != im.shape:
        raise RuntimeError("STFT_ANALYZE: real and imaginary matrices have different shapes")
    return {
        "kind": "array", "shape": [int(r.shape[0]), int(r.shape[1])],
        "real": r.ravel(order="F"), "imaginary": im.ravel(order="F"),
    }


def scalar(value):
    return a([value])


def empty():
    return {"kind": "empty"}


def opts(fields):
    return {"kind": "struct", "fields": fields}


def vector(values):
    return {"kind": "vector", "value": np.asarray(values, dtype=np.float64).reshape(-1)}


def numeric(op, operation, *operands):
    result = api("NUMERIC_API_v1", op, operation, *operands)
    return np.asarray(result["values"], dtype=np.float64).reshape(-1)


def unary(name, values):
    return numeric("array_unary", name, vector(values))


def binary(name, left, right):
    a1 = vector(left) if np.ndim(left) else {"kind": "scalar", "value": float(left)}
    a2 = vector(right) if np.ndim(right) else {"kind": "scalar", "value": float(right)}
    return numeric("array_binary", name, a1, a2)


def reduction(name, values):
    result = api("NUMERIC_API_v1", "array_reduce", name, vector(values), {"axis": 0})
    v = np.asarray(result["values"], dtype=np.float64).reshape(-1)
    if v.size != 1:
        raise RuntimeError("STFT_ANALYZE: reduction did not return one value")
    return float(v[0])


def signal(operation, operand_a, operand_b, operand_c, options):
    return api("SIGNAL_API_v1", operation, operand_a, operand_b, operand_c, opts(options))


def read_signal(dataset_id, variable_id):
    stream = api("TABLE_STREAM_API_v3", "open_dataset", dataset_id, [variable_id],
                 STREAM_ROWS, {"start": 0, "count": -1, "require_direct": True})
    blocks = []
    try:
        while True:
            chunk = api("TABLE_STREAM_API_v3", "next", stream)
            values = np.asarray(chunk["values"][variable_id], dtype=np.float64).reshape(-1)
            if values.size:
                blocks.append(values)
            if str(chunk.get("eof", "0")).lower() in ("true", "1", "yes", "on"):
                break
        diagnostics = api("TABLE_STREAM_API_v3", "diagnostics", stream)
    finally:
        api("TABLE_STREAM_API_v3", "close", stream)
    if not blocks:
        raise RuntimeError("STFT_ANALYZE: no signal samples returned")
    return np.concatenate(blocks), diagnostics


def begin(dataset_id, parent, title, notes, storage="hdf5"):
    return api("DATASET_PUBLICATION_API_v2", "begin", {
        "dataset_id": dataset_id,
        "contract": "table.generic", "storage": storage,
        "replace_owned": False,
        "producer_version": "1.0.0",
        "source_dataset_ids": [parent],
        "source": title,
        "provenance": "SIGNAL_API_v1 STFT forward/inverse, NUMERIC_API_v1 diagnostics and STFT power; Dataset Publication API v2.",
        "notes": notes,
    })


def pub(op, *args):
    return api("DATASET_PUBLICATION_API_v2", op, *args)


def declare(writer, variable_id, dims, unit, role, coordinate_role="data"):
    pub("declare_variable", writer, variable_id, {
        "dtype": "float64", "rank": len(dims),
        "dimension_ids": ";".join(dims),
        "coordinate_role": coordinate_role,
        "unit": unit, "semantic_role": role,
    })


def publish_regular_table(dataset_id, parent, title, notes, columns, units, roles, storage="hdf5"):
    sizes = {np.asarray(data).size for data in columns.values()}
    if len(sizes) != 1:
        raise RuntimeError("STFT_ANALYZE: table columns are not aligned")
    writer = begin(dataset_id, parent, title, notes, storage)
    try:
        pub("declare_dimension", writer, "row", 0, {"extendible": 1})
        for vid in columns:
            declare(writer, vid, ["row"], units.get(vid, ""), roles.get(vid, "derived"),
                    "coordinate" if vid in {"v_time_s", "v_frequency_hz"} else "data")
        count = next(iter(sizes))
        for start in range(0, count, STREAM_ROWS):
            sl = slice(start, min(start + STREAM_ROWS, count))
            pub("append", writer, "row", {
                vid: np.asarray(array, dtype=np.float64).reshape(-1)[sl]
                for vid, array in columns.items()
            })
        receipt = pub("finalize", writer)
        writer = None
        return receipt
    except BaseException:
        if writer is not None:
            pub("abort", writer)
        raise


gxtxt_api_require([
    "TABLE_STREAM_API_v3@3", "DATASET_METADATA_API_v1@1",
    "SIGNAL_API_v1@1:math.signal", "NUMERIC_API_v1@1:math.numeric",
    "DATASET_PUBLICATION_API_v2@2", "SESSION_PERSISTENCE_API_v1@1",
])
ctx = gxtxt_context()
source = ctx.get("inputs", {}).get("primary")
if not isinstance(source, dict) or not source.get("dataset_id"):
    raise RuntimeError("STFT_ANALYZE: bind source Dataset with Semantic alias 'primary'")
source_id = str(source["dataset_id"])
meta = api("DATASET_METADATA_API_v1", "read", source_id)
if meta.get("tutorial.kind") != "nonstationary_signal_stft":
    raise RuntimeError("STFT_ANALYZE: unexpected Dataset type; check source metadata")

source_variable_id = str(meta["schema.signal_variable_id"])
fs = float(meta["signal.fs_hz"])
expected_n = int(meta["signal.sample_count"])
win_length = int(meta["stft.window_samples"])
hop = int(meta["stft.hop_samples"])
nfft = int(meta["stft.nfft"])
if not (fs > 0 and nfft >= win_length >= 2 and 0 < hop <= win_length):
    raise RuntimeError("STFT_ANALYZE: invalid STFT metadata parameters")

started = time.perf_counter()
y, stream_diagnostics = read_signal(source_id, source_variable_id)
if len(y) != expected_n:
    raise RuntimeError(f"STFT_ANALYZE: expected {expected_n} samples, obtained {len(y)}")

# Hann is a window-coefficient construction helper. STFT and inverse STFT
# themselves are executed exclusively by SIGNAL_API_v1.
window = np.hanning(win_length).astype(np.float64)
metrics = signal("spectral.window_metrics", a(window), empty(), scalar(fs), {})

forward = signal("stft.forward", a(y), a(window), scalar(hop), {
    "nfft": scalar(nfft), "pad": scalar(1), "sample_rate": scalar(fs),
})
S_real = np.asarray(forward["value_real"], dtype=np.float64)
S_imag = np.asarray(forward["value_imaginary"], dtype=np.float64)
if S_real.ndim != 2 or S_real.shape != S_imag.shape or S_real.shape[0] != nfft:
    raise RuntimeError(f"STFT_ANALYZE: unexpected STFT matrix shape: {S_real.shape}")
frame_time = np.asarray(forward["time_seconds"], dtype=np.float64).reshape(-1)
frequency = np.asarray(forward["frequency_hz"], dtype=np.float64).reshape(-1)
if len(frame_time) != S_real.shape[1] or len(frequency) != nfft:
    raise RuntimeError("STFT_ANALYZE: returned axes do not match STFT matrix")

inverse = signal("stft.inverse", complex_matrix(S_real, S_imag), a(window), scalar(hop), {
    "nfft": scalar(nfft),
    "pad_left": scalar(forward["pad_left"]),
    "original_length": scalar(forward["original_length"]),
})
reconstructed = np.asarray(inverse["value_real"], dtype=np.float64).reshape(-1)
if len(reconstructed) != len(y) or not np.isfinite(reconstructed).all():
    raise RuntimeError("STFT_ANALYZE: reconstructed signal has invalid shape/values")

residual = binary("subtract", y, reconstructed)
residual_sq = unary("square", residual)
rmse = float(unary("sqrt", [reduction("mean", residual_sq)])[0])
max_abs = reduction("maximum", unary("abs", residual))
print(f"STFT_ANALYZE stft_matrix={S_real.shape} reconstruct_rmse={rmse:.12g}V "
      f"max_abs={max_abs:.12g}V elapsed={time.perf_counter()-started:.3f}s")
if rmse > 1.0e-8:
    raise RuntimeError("STFT_ANALYZE: inverse STFT RMSE exceeds 1e-8 V acceptance threshold")

# A. Keep the COMPLETE complex transform in the Session as a real rank-2
# HDF5 scientific Dataset. The frequency axis is the full two-sided FFT index.
writer = begin(MATRIX_ID, source_id, "STFT complex matrix", "Full two-sided complex STFT with independent frequency and frame coordinates")
try:
    pub("declare_dimension", writer, "frequency", nfft, {"extendible": 0})
    pub("declare_dimension", writer, "frame", int(S_real.shape[1]), {"extendible": 0})
    declare(writer, "v_frequency_hz", ["frequency"], "Hz", "frequency", "coordinate")
    declare(writer, "v_frame_start_s", ["frame"], "s", "elapsed_time", "coordinate")
    for vid in ("v_stft_real", "v_stft_imag"):
        pub("declare_variable", writer, vid, {
            "dtype": "float64", "rank": 2, "dimension_ids": "frequency;frame",
            "coordinate_variable_ids": "v_frequency_hz;v_frame_start_s",
            "coordinate_role": "data", "unit": "V", "semantic_role": "derived",
        })
    pub("write_variable", writer, "v_frequency_hz", frequency, [nfft])
    pub("write_variable", writer, "v_frame_start_s", frame_time, [len(frame_time)])
    # Publication API v2 expects flat ROW-MAJOR values for rank>1.
    pub("write_variable", writer, "v_stft_real", S_real.ravel(order="C"),
        [nfft, int(S_real.shape[1])])
    pub("write_variable", writer, "v_stft_imag", S_imag.ravel(order="C"),
        [nfft, int(S_real.shape[1])])
    matrix_receipt = pub("finalize", writer)
    writer = None
except BaseException:
    if writer is not None:
        pub("abort", writer)
    raise
print(f"STFT_ANALYZE published matrix={matrix_receipt['dataset_id']}")

# B. Publish FULL reconstructed signal and residual on implicit uniform time.
writer = begin(RECON_ID, source_id, "Inverse STFT reconstruction", "Complete inverse-STFT reconstruction and error trace")
try:
    pub("declare_dimension", writer, "sample", 0, {"extendible": 1})
    pub("declare_variable", writer, "v_time_s", {
        "dtype": "float64", "rank": 1, "dimension_ids": "sample",
        "coordinate_role": "coordinate", "axis_kind": "uniform",
        "axis_origin": 0.0, "axis_step": 1.0 / fs,
        "unit": "s", "semantic_role": "elapsed_time",
    })
    for vid in ("v_reconstructed_v", "v_residual_v"):
        pub("declare_variable", writer, vid, {
            "dtype": "float64", "rank": 1, "dimension_ids": "sample",
            "coordinate_variable_ids": "v_time_s", "coordinate_role": "data",
            "unit": "V", "semantic_role": "derived",
        })
    for at in range(0, len(y), STREAM_ROWS):
        sl = slice(at, min(at + STREAM_ROWS, len(y)))
        pub("append", writer, "sample", {
            "v_reconstructed_v": reconstructed[sl], "v_residual_v": residual[sl],
        })
    reconstruction_receipt = pub("finalize", writer)
    writer = None
except BaseException:
    if writer is not None:
        pub("abort", writer)
    raise
print(f"STFT_ANALYZE published reconstruction={reconstruction_receipt['dataset_id']}")

# C. Small one-dimensional preview Dataset for fast, native Plot Dataset 2D.
indices = np.arange(0, len(y), TRACE_STRIDE)
trace_receipt = publish_regular_table(
    TRACE_ID, source_id, "STFT time trace preview",
    "Decimated solely for display. Validation metrics use every original sample.",
    {
        "v_time_s": indices / fs,
        "v_original_v": y[indices],
        "v_reconstructed_v": reconstructed[indices],
        "v_residual_v": residual[indices],
    },
    {"v_time_s": "s", "v_original_v": "V", "v_reconstructed_v": "V", "v_residual_v": "V"},
    {"v_time_s": "independent", "v_original_v": "derived", "v_reconstructed_v": "derived", "v_residual_v": "derived"},
)

# D. Sample a compact time-frequency XYZ grid, and use the framework's
# NUMERIC_API_v1 for one-sided PSD power and logarithmic scaling.
# Keep all complex coefficients in the matrix Dataset above.
positive = np.arange(0, nfft // 2 + 1, GRID_FREQ_STRIDE)
frames = np.arange(0, S_real.shape[1], GRID_FRAME_STRIDE)
rp = S_real[np.ix_(positive, frames)].reshape(-1)
ip = S_imag[np.ix_(positive, frames)].reshape(-1)
power = binary("add", unary("square", rp), unary("square", ip))
window_sum_sq = float(metrics["power_gain"]) * win_length
if not window_sum_sq > 0:
    raise RuntimeError("STFT_ANALYZE: invalid Hann window power")
power = binary("divide", power, fs * window_sum_sq)
# For a real signal, inner positive-frequency bins carry double-sided power.
factor = np.where((positive > 0) & (positive < nfft // 2), 2.0, 1.0)
factor = np.repeat(factor, len(frames))
power = binary("multiply", power, factor)
power_db = binary("multiply", unary("log10", binary("maximum", power, PSD_FLOOR)), 10.0)
frame_centers = frame_time[frames] + (win_length / 2.0) / fs
frequency_grid, time_grid = np.meshgrid(frequency[positive], frame_centers, indexing="ij")
grid_receipt = publish_regular_table(
    GRID_ID, source_id, "STFT spectrogram visualization grid",
    "One-sided PSD dB from a subsampled matrix, arranged as regular XYZ points for native Plot Dataset 3D.",
    {
        "v_time_s": time_grid.ravel(order="C"),
        "v_frequency_hz": frequency_grid.ravel(order="C"),
        "v_psd_db": power_db,
    },
    {"v_time_s": "s", "v_frequency_hz": "Hz", "v_psd_db": "dB"},
    {"v_time_s": "independent", "v_frequency_hz": "independent", "v_psd_db": "derived"},
)

base_meta = {
    "stft.source_dataset_id": source_id,
    "stft.analysis_api": "SIGNAL_API_v1",
    "stft.numeric_api": "NUMERIC_API_v1",
    "stft.window": "hann",
    "stft.window_samples": str(win_length), "stft.hop_samples": str(hop),
    "stft.nfft": str(nfft), "stft.frames": str(S_real.shape[1]),
    "stft.pad_left": str(int(forward["pad_left"])),
    "stft.original_length": str(int(forward["original_length"])),
    "stft.reconstruction_rmse_v": f"{rmse:.17g}",
    "stft.reconstruction_max_abs_v": f"{max_abs:.17g}",
    "stft.window_enbw_hz": str(float(metrics["equivalent_noise_bandwidth_hz"])),
    "stft.frame_coordinate": "frame_start_s",
    "stft.full_matrix_dataset_id": MATRIX_ID,
    "stft.full_reconstruction_dataset_id": RECON_ID,
    "stft.trace_preview_dataset_id": TRACE_ID,
    "stft.xyz_plot_dataset_id": GRID_ID,
}
for dataset_id, addition in (
    (MATRIX_ID, {"stft.kind": "complex_stft_rank2", "stft.dimension_order": "frequency;frame"}),
    (RECON_ID, {"stft.kind": "reconstructed_signal"}),
    (TRACE_ID, {"stft.kind": "trace_preview", "stft.display_stride": str(TRACE_STRIDE)}),
    (GRID_ID, {"stft.kind": "spectrogram_xyz", "stft.frequency_stride": str(GRID_FREQ_STRIDE),
               "stft.frame_stride": str(GRID_FRAME_STRIDE), "stft.one_sided_psd": "true",
               "stft.log_reference": "1 V^2/Hz", "stft.plot_time_coordinate": "frame_center_s"}),
):
    api("DATASET_METADATA_API_v1", "update", dataset_id, {**base_meta, **addition})
api("SESSION_PERSISTENCE_API_v1", "commit")

print("PASS STFT_ANALYZE ",
      f"matrix={MATRIX_ID} shape={S_real.shape} reconstruction={RECON_ID} "
      f"preview={TRACE_ID} xyz={GRID_ID} grid_rows={power_db.size} "
      f"rmse_v={rmse:.12g} max_abs_v={max_abs:.12g} "
      f"elapsed_s={time.perf_counter()-started:.4g}")
print(f"STFT stream_diagnostics={stream_diagnostics}")
