# GX-TXT Python Script Workspace — nonstationary signal generator.
# SPDX-License-Identifier: GPL-3.0-or-later
# A standalone Session script. No Analysis Sources are required.

from gxtxt import gxtxt_api_call, gxtxt_api_require
import numpy as np
import time

DATASET_ID = "tutorial.stft_nonstationary_signal"
FS_HZ = 8192.0
DURATION_S = 16.0
N = int(FS_HZ * DURATION_S)         # 131072
F_START_HZ = 100.0
F_END_HZ = 3000.0
CHIRP_AMPLITUDE_V = 1.0
NOISE_RMS_V = 0.12
NOISE_SEED = 20261013
EVENT_TIMES_S = (4.0, 11.0)
EVENT_AMPLITUDES_V = (24.0, -20.0)
APPEND_CHUNK = 16384


def a(values):
    v = np.asarray(values, dtype=np.float64).reshape(-1)
    return {"kind": "array", "shape": [int(v.size), 1], "real": v}


def scalar(v):
    return a([float(v)])


def empty():
    return {"kind": "empty"}


def opts(fields):
    return {"kind": "struct", "fields": fields}


def signal(operation, x, b, c, options):
    result = gxtxt_api_call(
        "SIGNAL_API_v1", operation, [x, b, c, opts(options)]
    )
    return np.asarray(result["value_real"], dtype=np.float64).reshape(-1)


def add(x, y):
    result = gxtxt_api_call(
        "NUMERIC_API_v1", "array_binary",
        ["add", {"kind": "vector", "value": np.asarray(x, dtype=np.float64)},
         {"kind": "vector", "value": np.asarray(y, dtype=np.float64)}],
    )
    return np.asarray(result["values"], dtype=np.float64).reshape(-1)


def call_pub(operation, args):
    return gxtxt_api_call("DATASET_PUBLICATION_API_v2", operation, args)


gxtxt_api_require([
    "SIGNAL_API_v1@1:math.signal",
    "NUMERIC_API_v1@1:math.numeric",
    "DATASET_PUBLICATION_API_v2@2",
    "DATASET_METADATA_API_v1@1",
    "SESSION_PERSISTENCE_API_v1@1",
])

start = time.perf_counter()
t = np.arange(N, dtype=np.float64) / FS_HZ   # Coordinate support, not signal math.
chirp = signal("generate.chirp", a(t), scalar(F_START_HZ), scalar(F_END_HZ),
               {"amplitude": scalar(CHIRP_AMPLITUDE_V)})
noise = signal("generate.white_noise", a(t), empty(), empty(),
               {"amplitude": scalar(NOISE_RMS_V), "seed": scalar(NOISE_SEED)})

# Two discrete transient events using the framework generator, not handcrafted pulses.
transients = None
for instant, amplitude in zip(EVENT_TIMES_S, EVENT_AMPLITUDES_V):
    event_index = int(round(instant * FS_HZ)) + 1   # API index is one-based.
    event = signal("generate.impulse", a(t), empty(), empty(),
                   {"index": scalar(event_index), "amplitude": scalar(amplitude)})
    transients = event if transients is None else add(transients, event)

mixed = add(add(chirp, noise), transients)
if any(array.size != N or not np.isfinite(array).all()
       for array in (chirp, noise, transients, mixed)):
    raise RuntimeError("STFT_GENERATE: generated vectors have invalid length or values")

# New Dataset: create-only. Existing work is never replaced or removed.
definition = {
    "dataset_id": DATASET_ID,
    "contract": "table.generic",
    "storage": "hdf5",
    "replace_owned": False,
    "producer_version": "1.0.0",
    "source": "GX-TXT Python Script Workspace — STFT signal generation",
    "provenance": "SIGNAL_API_v1 chirp, seeded white noise and two impulses; NUMERIC_API_v1 addition.",
    "notes": "Sixteen-second synthetic nonstationary waveform with two known transient events.",
}
writer = call_pub("begin", [definition])
try:
    call_pub("declare_dimension", [writer, "sample", 0, {"extendible": 1}])
    call_pub("declare_variable", [writer, "v_time_s", {
        "dtype": "float64", "rank": 1, "dimension_ids": "sample",
        "coordinate_role": "coordinate", "axis_kind": "uniform",
        "axis_origin": 0.0, "axis_step": 1.0 / FS_HZ,
        "unit": "s", "semantic_role": "elapsed_time",
    }])
    for vid in ("v_signal_v", "v_chirp_v", "v_noise_v", "v_transients_v"):
        call_pub("declare_variable", [writer, vid, {
            "dtype": "float64", "rank": 1, "dimension_ids": "sample",
            "coordinate_variable_ids": "v_time_s", "coordinate_role": "data",
            "unit": "V", "semantic_role": "voltage",
        }])
    for at in range(0, N, APPEND_CHUNK):
        sl = slice(at, at + APPEND_CHUNK)
        call_pub("append", [writer, "sample", {
            "v_signal_v": mixed[sl],
            "v_chirp_v": chirp[sl],
            "v_noise_v": noise[sl],
            "v_transients_v": transients[sl],
        }])
        print(f"STFT_GENERATE appended={min(at + APPEND_CHUNK, N)}/{N}")
    published = call_pub("finalize", [writer])
    writer = None
except BaseException:
    if writer is not None:
        call_pub("abort", [writer])
    raise

metadata = {
    "tutorial.kind": "nonstationary_signal_stft",
    "signal.generator_api": "SIGNAL_API_v1",
    "signal.mixing_api": "NUMERIC_API_v1",
    "signal.fs_hz": str(FS_HZ),
    "signal.sample_count": str(N),
    "signal.duration_s": str(DURATION_S),
    "signal.chirp_start_hz": str(F_START_HZ),
    "signal.chirp_end_hz": str(F_END_HZ),
    "signal.chirp_amplitude_v": str(CHIRP_AMPLITUDE_V),
    "signal.noise_rms_v": str(NOISE_RMS_V),
    "signal.noise_seed": str(NOISE_SEED),
    "signal.event_times_s": ";".join(str(v) for v in EVENT_TIMES_S),
    "signal.event_amplitudes_v": ";".join(str(v) for v in EVENT_AMPLITUDES_V),
    "schema.time_variable_id": "v_time_s",
    "schema.signal_variable_id": "v_signal_v",
    "schema.chirp_variable_id": "v_chirp_v",
    "schema.noise_variable_id": "v_noise_v",
    "schema.transients_variable_id": "v_transients_v",
    "stft.window": "hann",
    "stft.window_samples": "2048",
    "stft.hop_samples": "256",
    "stft.nfft": "2048",
    "stft.pad": "true",
    "processing.elapsed_generation_seconds": f"{time.perf_counter() - start:.9g}",
}
gxtxt_api_call("DATASET_METADATA_API_v1", "update", [DATASET_ID, metadata])
gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])
print("PASS STFT_GENERATE ",
      f"dataset={published['dataset_id']} rows={N} fs={FS_HZ:g} "
      f"duration={DURATION_S:g}s chirp={F_START_HZ:g}..{F_END_HZ:g}Hz "
      f"events={EVENT_TIMES_S} storage=hdf5")
