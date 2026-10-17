# GX-TXT Python Script Workspace tutorial:
# demonstrate framework-governed Python parallel resource usage.
# v2: make the worker pickleable under GX-TXT exec(code, namespace).
#
# PARALLEL_EXECUTION_API_v1/resources supplies the worker policy.
# No Bridge calls are made from worker processes.
# The authoritative scientific spectrum remains the SIGNAL_API_v1 result
# produced by the previous tutorial step.
#
# SPDX-License-Identifier: GPL-3.0-or-later

from gxtxt import gxtxt_context, gxtxt_api_require, gxtxt_api_call
from concurrent.futures import ProcessPoolExecutor
import multiprocessing as mp
import pickle
import sys
import numpy as np
import os
import time


BENCHMARK_DATASET_ID = "tutorial.parallel_fft_benchmark_v2"

WINDOW_SAMPLES = 1 << 18       # 262,144
WINDOW_COUNT = 16
FFT_REPEATS_PER_WINDOW = 4
REQUESTED_WORKERS = 4
STREAM_CHUNK_ROWS = WINDOW_SAMPLES


def _fft_worker(payload):
    """Pure worker: intentionally no GX-TXT Bridge calls."""
    window_index, start_sample, values, sample_rate_hz, repeats = payload

    # Keep nested native libraries conservative inside process-level parallelism.
    os.environ["OMP_NUM_THREADS"] = "1"
    os.environ["OPENBLAS_NUM_THREADS"] = "1"
    os.environ["MKL_NUM_THREADS"] = "1"

    x = np.asarray(values, dtype=float)
    spectrum = None
    for _ in range(int(repeats)):
        spectrum = np.fft.rfft(x)

    power = np.abs(spectrum) ** 2
    if power.size <= 1:
        raise RuntimeError("parallel FFT worker received insufficient data")

    peak_index = int(np.argmax(power[1:]) + 1)
    peak_frequency_hz = peak_index * float(sample_rate_hz) / x.size

    return {
        "window_index": int(window_index),
        "start_sample": int(start_sample),
        "peak_frequency_hz": float(peak_frequency_hz),
        "peak_power": float(power[peak_index]),
    }


def read_direct_window(dataset_id, variable_id, start, count):
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
        raise RuntimeError("PARALLEL_FFT: direct window is empty")
    values = np.concatenate(blocks)
    if values.size != count:
        raise RuntimeError(
            f"PARALLEL_FFT: expected {count} samples, received {values.size}"
        )
    return values, diagnostics


def publish_benchmark(rows, metadata):
    definition = {
        "dataset_id": BENCHMARK_DATASET_ID,
        "contract": "table.generic",
        "storage": "auto",
        "replace_owned": False,  # never overwrite the earlier serial benchmark
        "producer_version": "1.0.0",
        "source_dataset_ids": [metadata["benchmark.source_dataset_id"]],
        "source": "Python Script Workspace parallel FFT policy benchmark",
        "provenance": (
            "Python ProcessPoolExecutor sized by PARALLEL_EXECUTION_API_v1 "
            "resource policy. Worker FFTs are benchmark-only; the authoritative "
            "scientific spectrum is produced separately through SIGNAL_API_v1."
        ),
        "notes": (
            "One row per independent FFT benchmark window. This Dataset records "
            "parallel execution behavior, not the authoritative Fourier result."
        ),
    }

    writer = gxtxt_api_call(
        "DATASET_PUBLICATION_API_v2", "begin", [definition]
    )
    try:
        gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2",
            "declare_dimension",
            [writer, "window", 0, {"extendible": 1}],
        )
        variables = (
            ("v_window_index", "", "independent"),
            ("v_start_sample", "", "independent"),
            ("v_peak_frequency_hz", "Hz", "derived"),
            ("v_peak_power", "", "derived"),
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
                        "dimension_ids": "window",
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
                "window",
                {
                    "v_window_index": np.asarray(
                        [row["window_index"] for row in rows], dtype=float
                    ),
                    "v_start_sample": np.asarray(
                        [row["start_sample"] for row in rows], dtype=float
                    ),
                    "v_peak_frequency_hz": np.asarray(
                        [row["peak_frequency_hz"] for row in rows], dtype=float
                    ),
                    "v_peak_power": np.asarray(
                        [row["peak_power"] for row in rows], dtype=float
                    ),
                },
            ],
        )
        result = gxtxt_api_call(
            "DATASET_PUBLICATION_API_v2", "finalize", [writer]
        )
        writer = None
    except Exception:
        if writer is not None:
            gxtxt_api_call("DATASET_PUBLICATION_API_v2", "abort", [writer])
        raise

    gxtxt_api_call(
        "DATASET_METADATA_API_v1",
        "update",
        [BENCHMARK_DATASET_ID, metadata],
    )
    return result


def main():
    ctx = gxtxt_context()

    gxtxt_api_require([
        "TABLE_STREAM_API_v3@3",
        "DATASET_METADATA_API_v1@1",
        "PARALLEL_EXECUTION_API_v1@1",
        "DATASET_PUBLICATION_API_v2@2",
        "SESSION_PERSISTENCE_API_v1@1",
    ])

    primary = ctx.get("inputs", {}).get("primary")
    if not isinstance(primary, dict) or not primary.get("dataset_id"):
        raise RuntimeError(
            "PARALLEL_FFT: bind tutorial.large_noisy_multitone to Analysis Source 'primary'"
        )

    dataset_id = str(primary["dataset_id"])
    source_metadata = gxtxt_api_call(
        "DATASET_METADATA_API_v1", "read", [dataset_id]
    )

    variable_id = str(
        source_metadata.get("schema.signal_variable_id", "")
    ).strip()
    sample_rate_hz = float(
        source_metadata.get("generation.sample_rate_hz", "0")
    )
    sample_count = int(
        source_metadata.get("generation.sample_count", "0")
    )

    if (
        not variable_id
        or sample_rate_hz <= 0
        or sample_count < WINDOW_COUNT * WINDOW_SAMPLES
    ):
        raise RuntimeError("PARALLEL_FFT: source Dataset metadata is incompatible")

    policy = gxtxt_api_call(
        "PARALLEL_EXECUTION_API_v1", "resources", []
    )

    enabled = str(policy.get("enabled", "0")).lower() in (
        "1", "true", "yes", "on"
    )
    default_workers = int(float(policy.get("default_workers", 1)))
    max_workers = int(float(policy.get("max_workers", 1)))
    recommended_internal_threads = int(
        float(policy.get("recommended_internal_threads", 1))
    )

    fork_available = "fork" in mp.get_all_start_methods()
    workers = (
        min(
            REQUESTED_WORKERS,
            default_workers,
            max_workers,
            WINDOW_COUNT,
        )
        if enabled and fork_available
        else 1
    )
    workers = max(1, int(workers))

    # Read independent direct HDF5 windows in the parent process.
    windows = []
    diagnostics = []
    for window_index in range(WINDOW_COUNT):
        start_sample = window_index * WINDOW_SAMPLES
        values, diag = read_direct_window(
            dataset_id, variable_id, start_sample, WINDOW_SAMPLES
        )
        windows.append(
            (
                window_index,
                start_sample,
                values,
                sample_rate_hz,
                FFT_REPEATS_PER_WINDOW,
            )
        )
        diagnostics.append(diag)

    serial_start = time.perf_counter()
    serial_rows = [_fft_worker(item) for item in windows]
    serial_seconds = time.perf_counter() - serial_start

    if workers > 1:
        # GX-TXT Script Workspace runs the script with exec(code, namespace),
        # not by importing a Python module.  The callable is therefore absent
        # from the actual sys.modules["__main__"], although pickle identifies
        # its module as "__main__".  Export it *temporarily* to make standard
        # ProcessPoolExecutor pickling work, including under explicit "fork".
        # This modifies only this transient Python process, never GX-TXT CORE.
        main_module = sys.modules["__main__"]
        old_worker = vars(main_module).get("_fft_worker", None)
        had_worker = hasattr(main_module, "_fft_worker")
        _fft_worker.__module__ = "__main__"
        setattr(main_module, "_fft_worker", _fft_worker)
        try:
            # Fail with an explicit explanation before creating the pool.
            pickle.dumps(_fft_worker)
            context = mp.get_context("fork")
            parallel_start = time.perf_counter()
            with ProcessPoolExecutor(
                max_workers=workers,
                mp_context=context,
            ) as pool:
                parallel_rows = list(pool.map(_fft_worker, windows))
            parallel_seconds = time.perf_counter() - parallel_start
        finally:
            # Restore the script runner's original __main__ namespace.
            if had_worker:
                setattr(main_module, "_fft_worker", old_worker)
            else:
                delattr(main_module, "_fft_worker")
    else:
        parallel_rows = list(serial_rows)
        parallel_seconds = serial_seconds

    bin_width_hz = sample_rate_hz / WINDOW_SAMPLES
    for serial_row, parallel_row in zip(serial_rows, parallel_rows):
        if serial_row["window_index"] != parallel_row["window_index"]:
            raise RuntimeError("PARALLEL_FFT: result ordering changed")
        if abs(
            serial_row["peak_frequency_hz"]
            - parallel_row["peak_frequency_hz"]
        ) > 0.5 * bin_width_hz:
            raise RuntimeError(
                "PARALLEL_FFT: serial and parallel peak frequencies differ"
            )

    speedup = (
        serial_seconds / parallel_seconds
        if parallel_seconds > 0
        else 0.0
    )

    benchmark_metadata = {
        "benchmark.kind": "python_parallel_fft_policy",
        "benchmark.source_dataset_id": dataset_id,
        "benchmark.authoritative_fourier_backend": "SIGNAL_API_v1",
        "benchmark.parallel_policy_api": "PARALLEL_EXECUTION_API_v1",
        "benchmark.python_executor": "ProcessPoolExecutor",
        "benchmark.bridge_calls_in_workers": "false",
        "benchmark.window_samples": str(WINDOW_SAMPLES),
        "benchmark.window_count": str(WINDOW_COUNT),
        "benchmark.fft_repeats_per_window": str(FFT_REPEATS_PER_WINDOW),
        "benchmark.requested_workers": str(REQUESTED_WORKERS),
        "benchmark.effective_workers": str(workers),
        "benchmark.policy_enabled": str(enabled).lower(),
        "benchmark.policy_default_workers": str(default_workers),
        "benchmark.policy_max_workers": str(max_workers),
        "benchmark.recommended_internal_threads": str(
            recommended_internal_threads
        ),
        "benchmark.serial_seconds": f"{serial_seconds:.17g}",
        "benchmark.parallel_seconds": f"{parallel_seconds:.17g}",
        "benchmark.speedup": f"{speedup:.17g}",
        "benchmark.bin_width_hz": f"{bin_width_hz:.17g}",
        "benchmark.first_stream_diagnostics": (
            str(diagnostics[0]) if diagnostics else ""
        ),
    }

    published = publish_benchmark(
        parallel_rows, benchmark_metadata
    )
    gxtxt_api_call("SESSION_PERSISTENCE_API_v1", "commit", [])

    print(
        "PASS PARALLEL_FFT_POLICY "
        f"dataset={dataset_id} workers={workers} "
        f"windows={WINDOW_COUNT} window_samples={WINDOW_SAMPLES} "
        f"repeats={FFT_REPEATS_PER_WINDOW} "
        f"serial_seconds={serial_seconds:.6g} "
        f"parallel_seconds={parallel_seconds:.6g} "
        f"speedup={speedup:.6g} "
        f"benchmark={published['dataset_id']}"
    )
    print(f"PARALLEL_FFT policy={policy}")


if __name__ == "__main__":
    main()
