<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Harmonic Analysis 1.1.0

## 1. Scientific purpose

`analysis.harmonic_analysis` measures the integer harmonic content of an **existing one-sided linear amplitude spectrum**. It is intentionally separate from the FFT calculation itself.

The module answers questions such as:

- What is the detected fundamental frequency?
- What amplitudes are present at H2, H3, ... Hn?
- What are those harmonic levels relative to the fundamental in dBc and percent?
- What total harmonic distortion (THD) follows from the tracked harmonics?

The source spectrum is never modified.

## 2. Intended workflow

```text
Canonical time-domain Dataset
    -> analysis.fft_spectrum or another compatible spectral producer
    -> canonical spectrum.table
    -> analysis.harmonic_analysis
    -> table.generic harmonic result
    -> report + persistent plot.dataset graphs
```

This division avoids duplicating FFT implementation inside the harmonic-analysis plugin.

## 3. Input contract

The source must be a canonical `spectrum.table` Dataset with:

- one strictly increasing, non-negative **Frequency** variable;
- one non-negative, **linear amplitude** spectrum variable.

For the standard `analysis.fft_spectrum` output, bind:

- Frequency -> `frequency`
- Amplitude spectrum -> `amplitude`

Do not bind `magnitude_dBc` as the amplitude input. THD requires linear amplitudes.

## 4. Numerical-service integration

Version 1.1.0 depends on protected CORE `math.numeric` and discovers `NUMERIC_API_v1` through the standard module dependency runtime bridge.

Reusable generic operations are delegated to the public numerical service:

- frequency-grid validation and nominal spacing through `grid_info`;
- finite/non-negative amplitude summary through `statistics`;
- maximum values used inside configured peak-search regions through `statistics`;
- sum-of-squares reduction used by the THD formula through `statistics`.

The following remain deliberately module-specific scientific semantics:

- automatic versus explicit fundamental selection;
- local bin search around expected integer harmonics;
- fundamental-relative dBc and percent interpretation;
- THD definition and reporting;
- harmonic Dataset publication and provenance.

The module does not implement a private FFT, private statistics framework or private peak-analysis service.

## 5. Fundamental detection

Two modes are available.

### Auto peak

The module searches the amplitude spectrum for the largest positive retained bin after the configured number of low-frequency/DC bins has been excluded.

This is appropriate when the fundamental is the dominant retained spectral component.

### Explicit

Enter the expected fundamental frequency. The module finds the largest spectral bin in a local window centered on that expected frequency.

Use this mode when a harmonic, spur, carrier, or other line may be larger than the fundamental.

## 6. Harmonic search

After resolving the fundamental at `f0`, the expected harmonic frequencies are:

```text
H1 = 1 * f0
H2 = 2 * f0
H3 = 3 * f0
...
Hn = n * f0
```

For each expected frequency that remains inside the available one-sided spectrum, the plugin searches a configurable number of neighboring bins and records the largest local amplitude.

`Search half-width [bins] = 0` means the nearest spectral bin only. A small positive value tolerates modest bin mismatch or leakage without turning the module into a general peak classifier.

The module does not alias harmonics back below Nyquist. Orders beyond the available frequency range are not published.

## 7. THD definition

Version 1.1.0 uses:

```text
THD = sqrt(H2^2 + H3^2 + ... + Hn^2) / H1
```

where every `Hk` is the detected **linear peak amplitude** published by this module.

Outputs include:

- THD ratio;
- THD percent;
- THD in dB: `20 log10(THD)`.

The configured highest harmonic order and the available spectrum therefore define the THD bandwidth of this result. The report states that explicitly.

The module does not present SFDR, SINAD, ENOB, THD+N, IEC audio weighting, or standards-specific distortion metrics as part of this workflow.

## 8. Published Dataset

The default output Dataset ID is:

```text
harmonic_analysis.result
```

The published `table.generic` contains one row per available harmonic order:

- `harmonic_order`
- `expected_frequency`
- `detected_frequency`
- `frequency_error`
- `amplitude`
- `amplitude_dBc`
- `amplitude_percent`

The result keeps source Dataset and source-variable provenance through Dataset Publication API v2.

## 9. Automatic graphs

Version 1.1.0 no longer owns a renderer, render cache or rerender implementation.

After publication it creates three persistent `plot.dataset` variants through `PLOT_DATASET_API_v2`:

1. harmonic levels in dBc;
2. harmonic levels as percent of the fundamental;
3. harmonic levels in the source linear amplitude unit.

All three use the shared public `kind=bar` representation. The dBc graph uses the public `bar_baseline` presentation state so H1 at exactly `0 dBc` remains visible without a module-private marker overlay.

Because these are normal persistent `plot.dataset` variants, shared framework controls apply directly, including legend behavior where useful, axis/range configuration, linear/log scaling when scientifically valid, save/reopen, rerender and normal export.

The analysis output directory receives conventional PNG copies of the provider-owned artifacts plus `automatic_graphs.ini`; the authoritative graph state remains the persisted `plot.dataset` variant.

## 10. Output files

The analysis output directory contains:

```text
harmonic_analysis_metrics.ini
harmonic_analysis_report.txt
automatic_graphs.ini
01_harmonic_levels_dbc.png
02_harmonic_levels_percent.png
03_harmonic_levels_linear.png
```

There is no module-private `render_cache.mat`.

## 11. Student Session Generator

The plugin bundles:

```text
session_generators/gxtxt_numerical_examples_harmonic_analysis_1.0.0.zip
```

Import it through the normal Session Generator Library UI/API. The generated Session contains a coherent 4096-sample waveform at 4096 Hz with:

- H1: 100 Hz, 1.000 V peak;
- H2: 200 Hz, 0.100 V peak;
- H3: 300 Hz, 0.050 V peak;
- H4: 400 Hz, 0.020 V peak;
- H5: 500 Hz, 0.010 V peak.

The analytical THD is stored in the generated ground-truth file.

For the exact teaching check, use `analysis.fft_spectrum` in Full record mode with a rectangular window and mean detrend. All lines are coherent with the one-second record, so they fall on exact 1 Hz FFT bins.

## 12. Important limitations

- The input must be a **linear amplitude spectrum**, not PSD, ASD, dB, or dBc data.
- Version 1.1.0 uses local peak-bin amplitudes. It does not perform standards-specific band integration around each harmonic.
- A non-coherent record or strongly windowed/leaky spectrum can require a larger local search window, but increasing the search window can also capture an unrelated nearby spur.
- Automatic fundamental detection assumes the fundamental is the largest retained spectral line.
- Integer harmonics only are analyzed in this release.

## 13. Public GX-TXT interfaces used

The plugin uses normal public framework surfaces only:

- Standard Module API v1
- Analysis Source Map API v1
- Dataset Variable Schema API v3
- Table Stream API v3
- Dataset Publication API v2
- Progress API v1
- `NUMERIC_API_v1`
- `PLOT_DATASET_API_v2`
- Graph Provider API v1
- Plugin Install API v1
- Session Generator Library API v1
- Unit Registry API v1

No private Dataset paths, private CSV readers, private numerical service, private graph renderer or CORE-private file access are required.
