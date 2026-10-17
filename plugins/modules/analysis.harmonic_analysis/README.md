<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Harmonic Analysis (`analysis.harmonic_analysis`)

Version **1.2.0** is a normal GX-TXT analysis plugin for harmonic measurements on an existing canonical `spectrum.table` Dataset.

It deliberately does **not** recompute an FFT. A spectrum may come from `analysis.fft_spectrum` or another compatible producer. The plugin binds the spectrum frequency coordinate and linear amplitude variable, detects the fundamental, locates integer harmonics, publishes a reusable `table.generic` result, reports THD, and creates three persistent `plot.dataset` variants for dBc, percent-of-fundamental and linear amplitude.

Generic grid analysis and descriptive reductions are consumed through the public `NUMERIC_API_v1` service supplied by `math.numeric`; harmonic selection, fundamental-relative interpretation and THD semantics remain module-specific.

The bundled student Session Generator creates a deterministic time-domain waveform with analytically known harmonic content so students can exercise the complete path:

```text
CSV -> canonical timeseries.table -> FFT Spectrum -> spectrum.table -> Harmonic Analysis
```

Install the module through the normal GX-TXT Plugin Install API. Import the bundled Session Generator through the Session Generator Library UI/API.

The complete existing local-peak estimator now belongs to public Numeric. CORE
owns THD interpretation, level-floor definitions and reporting. Publication keeps
the canonical seven component columns and adds a Dataset-local statistical
column binding with actual units and a payload seal, plus the captured summary.
Reports consume those validated published columns. Existing metric keys retain
their numeric values and add explicit status and quantity identifiers.
