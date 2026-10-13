# gxtxt.ir_waveform v3.6.2

Native GX-TXT analysis module for **GX-TXT 0.9.8.10-dev**.
License: **GNU GPL v3 or later**.

Version 3.6.2 publishes ten available IR graphs through canonical display Datasets and persistent public Plot.dataset variants. Its four single-signal graphs are enabled by default; enable comparison graphs after binding comparison traces. The overview uses 6,000 peak-preserving display points; numerical burst analysis continues to use the full source signal. Reusable median, mean, RMS and interpolation operations use the discovered public `math.numeric` API. Carrier detection rules, burst semantics and thresholds remain in this module.

## Dataset selection and bindings in v3.6

The module uses **Analysis Source Map API v1**. Select the real canonical input Dataset in the `primary` source row. The word `primary` is only the source alias required by the framework; the module does not look for a Dataset named `primary`.

After selecting the primary Dataset, the binding controls are populated from that Dataset itself. For example, a Rigol Dataset containing `time_s` and `CH3` exposes `primary.time_s` and `primary.CH3`. The IR waveform signal must come from the primary source.

For optional comparison traces stored in separate Datasets, use **Add source**, select the additional Dataset, and bind the comparison trace from that source (for example `source2.CH4`). This is the expected layout for acquisition handlers that publish one canonical time-series Dataset per oscilloscope channel. Old unqualified runtime bindings remain accepted as primary-source bindings.

A dot in a canonical variable name is preserved. The prefix is treated as a
source ID only when it matches a configured Analysis Source row.

## Purpose

The module analyzes one primary IR waveform and can optionally follow the same physical signal through multiple nodes of an analog chain. The primary trace remains the only trace used for carrier detection and MARK/SPACE reconstruction. Comparison traces are diagnostic and quantitative.

## Carrier search in v3.3

The nominal carrier frequency is now explicitly a **prior**, not a forced result.

Modes:

- `nominal_recovery` (default): first lock near the nominal frequency; if that fails, search a configurable physically plausible band and continue with the measured carrier;
- `strict_nominal`: do not leave the nominal search window;
- `automatic`: discover the carrier directly inside the configured search band.

Defaults:

- nominal: 38 kHz;
- nominal lock tolerance: ±20%;
- adaptive search band: 33–60 kHz.

The report records nominal frequency, measured frequency, deviation, search mode, lock source and lock quality. If recovery is used, the report contains an explicit warning. The measured value is always used for subsequent timing analysis.

## Analog-chain comparison

One primary signal plus up to seven optional comparison traces can be selected. For each trace v3.3 calculates and stores:

- baseline;
- robust noise sigma;
- active polarity;
- command-window minimum, maximum and Vpp;
- carrier-envelope amplitude;
- analysis threshold;
- median margin above threshold;
- relative carrier amplitude versus the primary trace;
- normalization scale used by the optional normalized graph.

Numerical outputs:

- `analog_chain_comparison.csv` — one row per node/trace;
- `analog_chain_timeseries.csv` — envelope, threshold margin and gain versus time on the primary envelope time grid.

The comparison is intended to make measurements such as

`VIR -> QIN_C -> OUT_PRE -> V_OUT_POT_SENS`

reproducible across boards, revisions or measurement sessions.

## Comparison graphs

Quantitative graphs:

- `ir.compare` — absolute voltage, real amplitudes and DC offsets preserved;
- `ir.compare_baseline` — baseline removed, amplitudes still in volts;
- `ir.compare_envelope` — carrier envelopes;
- `ir.compare_gain` — relative carrier amplitude versus the primary signal;
- `ir.compare_margin` — envelope minus calculated threshold.

Optional graph:

- `ir.compare_normalized` — normalized waveform comparison. It is **disabled by default** because it deliberately removes absolute-amplitude information.

Normalization method is selectable: `peak`, `vpp`, or `rms`.

Absolute and baseline-removed comparisons support `stacked` and `overlay` views. In stacked mode the quantitative traces use a shared Y scale, so relative amplitudes remain directly comparable instead of being hidden by per-pane autoscaling. Normalized comparison follows the same display mode.

## Pulse diagnostics

The textual report contains:

- total threshold-detected pulses;
- carrier-locked pulses;
- rejected/spurious pulses.

## Protocol-identification data exchange

v3.3 writes `ir_analysis_manifest.ini`, containing the dataset, signal, measured carrier, lock metadata and path to `eventi_mark_space.csv`. This is the deterministic data exchange consumed by **gxtxt.ir_identify v2.0**.

Protocol identification therefore remains logically separate from waveform extraction.

## Core numerical outputs

- `eventi_mark_space.csv`
- `burst.csv`
- `duration_clusters_comparison.csv`
- `analog_chain_comparison.csv`
- `analog_chain_timeseries.csv`
- `ir_analysis_manifest.ini`
- `riepilogo_VIR.txt`
- `render_cache.mat`

## Tests

Included tests:

- `test_ir_waveform_synthetic.m`
- `test_ir_waveform_carrier_lock.m`
- `test_ir_waveform_adaptive_carrier.m`
- `test_ir_waveform_comparison.m`

The adaptive-carrier regression deliberately supplies 38 kHz as nominal while generating a real 56 kHz carrier; v3.3 must recover the measured carrier instead of forcing 38 kHz.
