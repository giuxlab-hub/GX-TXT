# analysis.welch_spectrum

**Welch PSD & Averaged Spectrum** is an external GX-TXT analysis plugin for averaged frequency-domain characterization of a stationary or approximately stationary signal.

- Module ID: `analysis.welch_spectrum`
- Version: `1.1.0`
- Minimum framework: GX-TXT `0.9.7.84`
- License: GPL-3.0-or-later

The module consumes one Dataset through Analysis Source, binds a time variable and one signal variable, and uses an existing GX-TXT Temporal `window_set` as the Welch segment definition. It does not maintain a second private overlap/window generator.

Version 1.1.0 obtains FFT, symmetric window generation and detrending through the discovered public `math.numeric` API. Welch's PSD normalization and averaging remain here.

For each resolved Temporal Set member it computes a normalized one-sided periodogram and amplitude spectrum. The module averages those independent segment results and publishes a canonical `spectrum.table` containing:

- `frequency` — implicit uniform frequency coordinate;
- `psd` — averaged one-sided power spectral density;
- `asd` — square root of PSD;
- `mean_amplitude` — arithmetic mean of per-segment coherent-gain-normalized amplitude spectra;
- `psd_db` — `10 log10(PSD)` with reference value 1 in the PSD numerical unit.

The default graph is variant-capable through the normal GX-TXT Plot Module API and can display PSD dB, linear PSD, ASD, or mean amplitude without repeating the spectral calculation.

A portable student Session Generator is bundled under `session_generators/` and is also distributed separately as `gxtxt_numerical_examples_welch_psd_1.0.0.zip`.

See `MANUAL.md` for the scientific definitions, workflow and student example.
