# Spectral Features — Manual

## 1. Purpose

`analysis.spectral_features` calculates compact descriptors from an existing non-negative, one-sided spectrum. It is intended for generic signal, measurement, vibration, acoustics, audio, and laboratory workflows where a spectrum needs a small set of reusable descriptive quantities.

The plugin is deliberately separate from FFT generation. It consumes `spectrum.table`; it does **not** call `fft`, recompute the source spectrum, or implement private source-file readers.

## 2. Normal workflow

```text
source time series
→ FFT Spectrum / Welch Spectrum
→ canonical spectrum.table
→ Spectral Features
→ summary Dataset
→ report + graph
```

Use `analysis.harmonic_analysis` when the scientific question concerns an integer harmonic family and THD. Use `analysis.spectral_features` when the question concerns the overall distribution of spectral content across frequency.

## 3. Input

Required Analysis Source contract:

```text
spectrum.table
```

Required bindings:

- **Frequency** — independent frequency coordinate;
- **Spectral value** — one non-negative spectrum variable.

The frequency unit must be compatible with Hz through the public Unit Registry. The module preserves the source frequency unit in published frequency-valued descriptors.

The frequency coordinate must be non-negative, strictly increasing, and uniformly spaced. Version 1.2.0 intentionally requires a uniform grid because the amplitude/power bin interpretation is then unambiguous and matches normal FFT/Welch outputs.

## 4. Input spectral semantics

The **Input spectral semantics** setting is scientific configuration, not merely a display option.

### Amplitude

For an amplitude spectrum `A[k]`, the descriptor weight is:

```text
P[k] = A[k]^2
```

### Power

For an already power-valued spectrum:

```text
P[k] = value[k]
```

### PSD

For a uniformly spaced PSD:

```text
P[k] ∝ PSD[k]
```

The constant frequency-bin width cancels in normalized descriptors, so the same normalized weighting is used. This is why v1 requires uniform spacing.

The plugin never guesses these semantics from a column name. The user chooses them explicitly.

## 5. DC handling

`Exclude DC bin = yes` removes the exact zero-frequency bin before descriptors are calculated. It does not alter the source Dataset.

This is useful when DC offset is not part of the frequency-distribution question. Set it to `no` when DC is scientifically meaningful.

## 6. Frequency descriptors

Let normalized power-equivalent weights be:

```text
q[k] = P[k] / sum(P)
```

Then:

- **Dominant frequency** — frequency of the maximum `P[k]`;
- **Spectral centroid** — `sum(f[k] q[k])`;
- **RMS frequency** — `sqrt(sum(f[k]^2 q[k]))`;
- **Spectral bandwidth** — weighted standard deviation around the centroid;
- **F05/F50/F85/F95** — first discrete frequency bins whose cumulative normalized power reaches 5%, 50%, 85%, and 95%;
- **90% occupied bandwidth** — `F95 - F05`.

Percentile frequencies are deliberately discrete-bin results in v1. They are not silently interpolated between FFT bins.

## 7. Shape descriptors

### Spectral flatness

```text
geometric_mean(P) / arithmetic_mean(P)
```

An exact zero power-equivalent bin makes the exact flatness zero. Very small numerical FFT residuals can therefore materially affect the displayed flatness of an otherwise ideal sparse line spectrum; this is mathematically expected and is not hidden by an automatic floor.

### Spectral crest factor

```text
max(P) / mean(P)
```

A highly concentrated spectrum has a high spectral crest factor.

### Normalized spectral entropy

```text
H = -sum(q[k] log(q[k])) / log(N)
```

with zero-weight terms omitted from the sum and `N` equal to the number of analysed frequency bins. Values near zero describe highly concentrated spectra; larger values describe a broader distribution. Interpretation depends on frequency range, resolution, windowing, and the input semantics.

## 8. Output Datasets

The module publishes a compact `table.generic` summary Dataset, default ID:

```text
spectral_features.summary
```

It contains one row with:

```text
dominant_frequency
spectral_centroid
rms_frequency
spectral_bandwidth
frequency_05
frequency_50
frequency_85
frequency_95
occupied_bandwidth_90
spectral_flatness
spectral_crest_factor
spectral_entropy
bin_count
```

It also publishes a plot-ready distribution Dataset with ID:

```text
<summary_dataset_id>.distribution
```

containing `frequency`, `normalized_power`, `normalized_power_percent`, `cumulative_power_percent`, and `relative_power_db`. This derived Dataset is reusable by other GX-TXT tools; it is not a private render cache.

The source Dataset remains unchanged. Publication provenance records the source Dataset, stable variable IDs, module version, selected input semantics, and DC policy.

## 9. Report

`spectral_features_report.txt` records the actual bindings, units, settings, definitions, calculated descriptor values, and Publication result.

`spectral_features_metrics.ini` provides a compact machine-readable run summary in addition to the published Dataset.

## 10. Numerical architecture and graphs

Version 1.2.0 discovers the public `NUMERIC_API_v1` `spectral_features`
operation through the module dependency bridge. Numeric owns the existing grid,
weighted-moment, quantile, flatness, crest and entropy calculation.
`STATISTICAL_RESULT_SEMANTICS_API_v1` owns the result definitions, physical units,
applicability and reports. Both output Datasets retain the full captured record;
Save/Open and export do not repeat the calculation. These are descriptive bin
distributions: spectral bins do not establish independent repeated observations,
parameter covariance, confidence intervals or regression degrees of freedom.

For amplitude input, the sum of bin weights has squared-amplitude units. For
power or PSD input, it retains the input unit. In particular, the PSD-bin sum
omits frequency-bin width and is **not integrated physical power**. The original
Variable IDs and INI metric names remain stable. Plot legends contain units once.
The public Numeric operation and CORE interpretation also work in real Python
and Octave Script Bridge Jobs and in Worksheet guided operations.

After publication it creates three persistent `plot.dataset` variants from the distribution Dataset:

- relative power [dB];
- normalized power per bin [%];
- cumulative power [%].

There is no module-private renderer or `render_cache.mat`. Save/reopen, rerender, axes/ranges/scales and normal export are owned by the shared `plot.dataset` infrastructure.

## 11. Student Session Generator

The package includes:

```text
gxtxt_numerical_examples_spectral_features_1.0.0.zip
```

Import it into **GX-TXT Numerical Examples**. It generates a coherent 4096-sample signal at 4096 Hz containing:

- 100 Hz at 1.000 V peak;
- 300 Hz at 0.500 V peak;
- 900 Hz at 0.250 V peak.

Use a full-record rectangular FFT with mean detrend. With **Amplitude** semantics and DC excluded, the ideal power-equivalent line weights are `1`, `0.25`, and `0.0625`.

This produces analytically useful reference values including:

- dominant frequency: 100 Hz;
- centroid: approximately 176.190476 Hz;
- RMS frequency: approximately 251.661148 Hz;
- bandwidth: approximately 179.694879 Hz;
- F50: 100 Hz;
- F85: 300 Hz;
- F95: 300 Hz;
- 90% occupied bandwidth: 200 Hz.

The generated `STUDENT_GUIDE.md` gives the complete exercise and discussion questions.

## 12. Limitations

Version 1.2.0 intentionally does not provide:

- another FFT or STFT implementation;
- harmonic identification or THD;
- psychoacoustic weighting;
- octave/fractional-octave integration;
- automatic noise-floor removal;
- arbitrary non-uniform frequency-grid integration;
- classification or machine-learning features.

Those are separate scientific concerns.

## 13. Public GX-TXT APIs used

- Standard Module API v1;
- Analysis Source API / stable variable bindings;
- Dataset Variable Schema API v3;
- Table Stream API v3;
- Unit Registry API v1;
- Dataset Publication API v2 / Storage Auto;
- Progress API v1;
- Graph Provider API v1;
- `PLOT_DATASET_API_v2`;
- `NUMERIC_API_v1`;
- Plugin Install API v1;
- Session Generator Library API v1.

All product-facing technical text, source comments, tests, and documentation are in English.
