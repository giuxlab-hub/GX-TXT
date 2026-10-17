# 2.3.0 — dev097 statistical ownership

- Delegate the retained estimator to public Numeric and interpret once through CORE.
- Preserve scientific Dataset/Variable identities, add captured metadata and validated reports.
-

<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog — analysis.fft_spectrum

## 2.2.0

- Use the public `NUMERIC_API_v1` binding for FFT, window, detrend and median primitives. Preserve spectrum-specific scaling and selection rules.

## 2.1.1
- Recalculates stable full-record, fixed-block, Selection and Temporal Set
  outputs using Publication v2 `replace_owned=true`.
- Same-owner verification and rollback remain CORE responsibilities; the
  module cannot replace a Dataset published by another producer.

## 2.1.0
- Added additive `temporal_set` analysis mode backed exclusively by public Temporal Set API v1 runtime helpers.
- Processes every `segment_set` or `window_set` member as an independent FFT without concatenating separated source regions.
- Uses CORE-resolved zero-based row ranges for sample-, duration-, overlap-, parent-Selection and partial-window semantics; no private window generator or temporal-unit conversion was added.
- Publishes one canonical `spectrum.table` Dataset per Temporal Set member, preserving independent frequency grids for variable-length segments and standard source/member provenance.
- Preserved full-record, Dataset Selection and fixed-block workflows and retained the established FFT mathematics.
- Uses bounded canonical source reads per member and introduces no module-private parallel execution.

## 2.0.0
- Migrated canonical input reads from direct CSV parsing to Table Stream API v3
  over Canonical Dataset API v2.
- Added direct support for canonical HDF5 datasets, including the uniformly
  sampled multi-channel waveform produced by `analysis.audio_decode 2.0.0`.
- Uses stable Dataset/Variable IDs supplied by the Standard Module runtime.
- Uses Schema v3 uniform-axis metadata directly for sample rate and sample
  ranges; implicit time coordinates are not materialized merely to obtain `fs`.
- Added optional Dataset Selection API v1 `x_range` input. Full-record mode
  transforms the selected interval; fixed-block positioning is relative to it.
- Preserved the existing FFT algorithm, windows, coherent-gain normalization,
  single-sided scaling, THD, SFDR, SINAD, ENOB, and harmonic metrics.
- Publishes `spectrum.table` through Dataset Publication API v2 and Storage Auto
  with typed numeric variables and an implicit uniform frequency coordinate.
- Removed the authoritative `spectrum.csv` output and all Publication v1 use.
- Keeps computed annotations and text/INI metric reports.
- Explicitly remains a global/single-frame FFT module; STFT and spectrogram
  behavior are owned by `analysis.spectrogram`.

## 1.1.0
- Added explicit Analysis mode: `full_record` and `fixed_block`.
- Added independent FFT length and fixed-block placement.
- Kept FFT window strictly as the weighting function.
- Added block metadata and regression coverage.

## 1.0.0
- First release with selectable FFT windows, single-sided amplitude spectrum,
  THD/SFDR/SINAD/ENOB metrics, Publication v1 spectrum output, and computed
  annotations.
