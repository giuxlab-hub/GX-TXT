# gxtxt.ir_waveform changelog

## 3.6.2

- Preserve historical unqualified comparison bindings that resolve a named
  signal in a separate canonical channel file when it is absent from the
  primary Dataset. Explicit Analysis Source bindings remain authoritative.

## 3.6.1

- Keep the 3.6.0 public Analysis Source Map integration, numerical API and
  Plot Dataset publication behavior.
- Interpret a dotted binding as source-qualified only when its prefix is a
  configured Analysis Source ID, as required by Analysis Source Map API v1.
  Dotted legacy primary-variable names remain intact.

## 3.6.0

- Replaces the legacy `config.dataset_id` selector with the framework-owned Analysis Source Map API v1.
- The required `primary` source now selects the real registered `timeseries.table` Dataset; `primary` is a source alias, not a Dataset name.
- Dataset-scoped binding choices are generated from the selected source, eliminating dependency on the removed legacy global/primary-variable configuration.
- Enables additional Analysis Source rows for comparison traces stored in separate canonical Datasets, as produced by multi-channel acquisition handlers.
- Runtime accepts source-qualified bindings such as `primary.CH3` and `source2.CH4`, while preserving old unqualified runtime configurations.
- Comparison traces resolve their selected Analysis Source path directly instead of guessing files by scanning legacy channel directories.

## 3.5.1

- Select the four waveform graphs by default. Comparison graphs remain available when comparison traces are bound; a single-signal run no longer fails the standard output contract by expecting unavailable comparison images.

## 3.5

- Route generic median, mean, RMS and interpolation operations through the discovered public `NUMERIC_API_v1` binding. Preserve IR-specific detection and classification rules.
- Keep the ten persistent public Plot.dataset graphs and default peak-preserving overview from 3.4.

## 3.4

- Routes ten graphs through canonical derived display Datasets and persistent public Plot.dataset variants, with no module-private figure renderer.
- Uses 6,000 peak-preserving overview points by default; full-resolution scientific burst analysis and cache rerender remain separate.

## 3.3

Analog-chain measurement and adaptive carrier recovery.

- Treats the user nominal carrier as a prior rather than a forced answer.
- Adds `carrier_search_mode`: `nominal_recovery`, `strict_nominal`, `automatic`.
- Adds configurable automatic carrier search band (default 33–60 kHz).
- Reports nominal carrier, measured carrier, deviation, lock source and lock quality.
- Emits an explicit warning when adaptive recovery is used.
- Adds reproducible analog-chain metrics for the primary trace and up to seven comparison traces.
- Adds `analog_chain_comparison.csv` and `analog_chain_timeseries.csv`.
- Adds quantitative comparison graphs for absolute voltage, baseline-removed voltage, carrier envelope, relative amplitude/gain and threshold margin.
- Quantitative stacked waveform comparisons use a common Y scale so real relative amplitudes are preserved visually.
- Adds an optional normalized comparison graph, disabled by default, with peak/Vpp/RMS normalization.
- Adds `ir_analysis_manifest.ini` as the deterministic interface to `gxtxt.ir_identify`.
- Adds adaptive-carrier regression: wrong 38 kHz nominal with a true 56 kHz signal.
- Retains v3.2 pulse counters and v3.1 coherent carrier-edge filtering.

### Compatibility

- Module API: v1.
- Target pipeline: GX-TXT v0.7.9.
- Single-channel operation remains valid.
- Existing core output files and graph IDs remain valid; comparison outputs are additive.


## 3.2

Multi-trace comparison and pulse diagnostics for GX-TXT Pipeline v0.7.9.

- Keeps one required primary IR signal; comparison traces remain optional.
- Adds seven optional comparison bindings (`compare1` ... `compare7`) using the existing Module API variable-binding mechanism.
- Loads comparison variables from canonical datasets in the current session.
- Adds graph provider `ir.compare` / `05_ir_comparison.png`.
- Adds `comparison_plot_mode` with `stacked` (default) and `overlay`.
- Comparison traces are display-only: carrier detection and MARK/SPACE analysis continue to use the primary signal exclusively.
- Adds pulse diagnostics to `riepilogo_VIR.txt`: total detected, carrier-locked, and rejected/spurious pulses.
- Stores comparison traces and pulse counts in `render_cache.mat` for rerendering.
- Adds `test_ir_waveform_comparison.m` and extends existing synthetic tests.

### Compatibility

- Module API: v1.
- Target pipeline: GX-TXT v0.7.9.
- Single-channel operation remains supported and requires no comparison binding.
- Existing v3.1 output filenames and graph IDs remain valid; `ir.compare` is additive.

## 3.1

Carrier-detection revision for GX-TXT Pipeline v0.7.9.

- Replaces the broad `0.50*Tnom .. 1.50*Tnom` carrier-period acceptance rule.
- Adds `carrier_lock_tolerance` (default `0.20`).
- Uses the nominal carrier frequency as a lock prior.
- Allows valid carrier-edge pairing across intervening spurious threshold crossings.
- Selects a coherent carrier-period cluster before estimating the measured frequency.
- Restricts pulse-width and duty-cycle estimation to carrier-locked pulses.
- Restricts subsequent MARK/SPACE reconstruction to carrier-locked pulses.
- Applies the same carrier-lock logic during the adaptive pretest.
- Adds `test_ir_waveform_carrier_lock.m`, covering the historical 38 kHz -> 62.5 kHz false lock.
- Extends the synthetic smoke test with a carrier-frequency assertion.

### Compatibility

- Module API: v1.
- Target pipeline: GX-TXT v0.7.9.
- Dataset contract remains `timeseries.table`.
- Existing output filenames and graph IDs are preserved.

## 3.0

Clean rewrite of the historical IR waveform module for the GX-TXT Standard Module API.
