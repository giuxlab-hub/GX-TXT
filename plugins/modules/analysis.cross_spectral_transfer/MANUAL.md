# Cross-Spectral & Transfer Function Analysis — Manual

## 1. Purpose

`analysis.cross_spectral_transfer` estimates how one measured signal relates to another in the frequency domain.

Typical use cases include:

- simultaneously acquired circuit input and output;
- two oscilloscope channels;
- excitation and response signals;
- two synchronized audio channels;
- sensor/reference measurements where transfer magnitude, phase and coherence are useful.

The first release intentionally requires both signals to belong to the **same GX-TXT Dataset**. This guarantees sample-to-sample synchronization without inventing an implicit alignment rule between independent Datasets.

## 2. Required Dataset

Bind three variables:

```text
Time / temporal variable
Input signal X
Output signal Y
```

The temporal coordinate must describe uniformly sampled data. A canonical uniform axis is used directly from Variable Schema metadata. An explicit time column is accepted only when its sample intervals are sufficiently uniform for FFT processing.

The module does not resample strongly non-uniform data.

## 3. Temporal Window Set

The analysis requires an existing GX-TXT Temporal Set of type `window_set`.

The Temporal Set owns segmentation. The module does not create a private window model.

For example:

```text
Basis       = Duration
Window size = 2 s
Step        = 1 s
Partial     = Drop
```

This is 50% overlap because the next window starts halfway through the previous window.

For every resolved member, the module reads only that bounded source range and computes paired FFTs for X and Y.

## 4. Spectral estimation

For each temporal window, after optional detrending and FFT weighting:

```text
X[k] = FFT(x[n] w[n])
Y[k] = FFT(y[n] w[n])
```

The one-sided auto/cross power spectral estimates use window-power normalization:

```text
Pxx = |X|^2 / (fs * sum(w^2))
Pyy = |Y|^2 / (fs * sum(w^2))
Pxy = conj(X) * Y / (fs * sum(w^2))
```

Interior positive-frequency bins are doubled for the one-sided representation.

The module averages these estimates across all resolved Temporal Set windows:

```text
Sxx = mean(Pxx)
Syy = mean(Pyy)
Sxy = mean(Pxy)
```

The cross-spectrum convention is therefore explicitly:

```text
Sxy = mean(conj(X) * Y)
```

## 5. Transfer estimators

Both common transfer estimators are calculated from the same averaged spectra.

### H1

```text
H1 = Sxy / Sxx
```

H1 is commonly preferred when measurement noise is mainly associated with the output/response channel.

### H2

```text
H2 = Syy / conj(Sxy)
```

H2 is often useful when input-side measurement noise is more significant.

In an ideal noiseless linear system H1 and H2 converge to the same transfer function.

Both estimators are published. Choosing H1 or H2 in a graph is a presentation choice and does not repeat the FFT calculation.

## 6. Magnitude-squared coherence

The module calculates:

```text
coherence = |Sxy|^2 / (Sxx * Syy)
```

The result is bounded to `[0,1]` within floating-point tolerance.

Values near 1 indicate a strong linear frequency-domain relationship between X and Y over the averaging windows. Lower values may indicate noise, nonlinear behavior, uncorrelated components or insufficient averaging. Coherence is not itself proof of causality.

## 7. FFT configuration

### FFT weighting window

Supported windows:

```text
rectangular
hann
hamming
blackman
blackman_harris
flat_top
```

The default is Hann.

### Detrending

```text
none
mean
linear
```

`mean` removes each window's DC mean independently and is the default.

### NFFT

`auto` uses the resolved full Temporal Window Set window length.

`explicit` allows a larger common NFFT. It must not be smaller than the full resolved window size. A partial final window, when the Temporal Set explicitly includes one, is zero-padded to the same NFFT.

## 8. Parallel execution

Each Temporal Set member is an independent CORE Parallel Execution work item.

The `Parallel workers` field accepts:

```text
auto
serial
positive integer
```

The actual worker count remains subject to the current CORE policy and maximum worker limit. The module does not create a private Octave worker pool.

Workers receive CORE's `recommended_internal_threads` hint through the standard numerical-thread environment controls used by the module.

Results are aggregated in deterministic Temporal Set order, independent of physical worker completion order.

## 9. Output Dataset

The module publishes one canonical `spectrum.table` with an implicit uniform frequency coordinate and variables equivalent to:

```text
input_psd
output_psd
cross_psd_real
cross_psd_imag
cross_psd_magnitude
cross_phase_deg
h1_real
h1_imag
h1_magnitude
h1_gain_db
h1_phase_deg
h2_real
h2_imag
h2_magnitude
h2_gain_db
h2_phase_deg
coherence
```

The complete complex quantities are represented by real/imaginary components so the Dataset remains directly reusable by ordinary GX-TXT numeric consumers.

The source Dataset, source variable IDs, Temporal Set and analysis configuration are retained in publication provenance and the text report.

## 10. Units

PSD unit labels are derived from the bound variable units, for example:

```text
V^2/Hz
A^2/Hz
```

Cross-PSD labels combine input/output units.

When input and output have the same unit, transfer magnitude is dimensionless. Otherwise the transfer-unit label is `output_unit/input_unit`.

Transfer gain in dB uses:

```text
20 log10(|H|)
```

PSD dB plotting uses:

```text
10 log10(PSD)
```

## 11. Graphs

The module offers four Graph Providers.

### Transfer magnitude

Displays H1 or H2 in linear magnitude or dB.

### Transfer phase

Displays H1 or H2 phase in degrees, wrapped or unwrapped.

### Magnitude-squared coherence

Displays coherence from 0 to 1.

### Input / output PSD

Optional overlay of input and output auto-PSD, in linear or dB representation.

## 12. Plot variants

Every graph supports GX-TXT Plot Module variants with:

```text
variant_data_model=module_cache
```

Variants reuse the same scientific persistent `plot.dataset` variants. They may change, for example:

- H1 vs H2;
- linear vs dB transfer magnitude;
- wrapped vs unwrapped phase;
- titles and labels;
- axis ranges/scales;
- legend and graphics settings;
- output format.

These changes do not repeat the cross-spectral calculation.

Scientific changes such as Temporal Set, FFT weighting, detrending or NFFT invalidate the cache and require recalculation.

## 13. Run mode

### Auto

Reuses a compatible scientific persistent `plot.dataset` variants when available; otherwise performs the complete analysis.

### Recalculate

Always recomputes all Temporal Set windows and republishes the Dataset.

### Render only

Refuses to compute. It succeeds only if a compatible persistent `plot.dataset` variants already exists.

## 14. Example workflow

1. Import or create a synchronized Dataset containing time, input and output signals.
2. In Variables, verify the three variable identities/units.
3. Create a Temporal `window_set`, for example 2 s windows with 1 s step.
4. Enable `Cross-Spectral & Transfer Function Analysis`.
5. Bind Time, Input X and Output Y.
6. Select the Temporal Window Set.
7. Leave Hann / mean detrend / Auto NFFT for a first run.
8. Run the module.
9. Inspect Transfer magnitude, Transfer phase and Coherence.
10. Create graph variants to compare H1/H2 or alternate plot presentations without recalculating.

## 15. Interpretation guidance

Use coherence together with transfer magnitude and phase. A gain/phase estimate in a region with poor coherence should not be interpreted with the same confidence as a region with coherence near one.

H1 and H2 are estimators with different noise assumptions; neither is universally superior. Their disagreement can itself be diagnostically useful.

## 16. Limitations

Version 1.1.1 intentionally does not:

- implicitly align two different Datasets;
- resample non-uniform data;
- implement MIMO transfer matrices;
- implement nonlinear transfer analysis;
- infer causality from coherence;
- hide Temporal Set segmentation inside a private module window model.

A future multi-source version must use explicit GX-TXT scientific alignment rather than assuming row equivalence between independent Datasets.

## 17. Public GX-TXT APIs used

- Standard Module API v1
- Analysis Source Map API v1
- Dataset Variable Schema v3 metadata exposed through Analysis Source
- Temporal Set API v1
- Table Stream API v3
- Parallel Execution API v1 `standard_octave` binding
- Dataset Publication API v2 / Storage Auto
- persistent `plot.dataset` variants API v1
- Graph Provider / Plot Module API v1
- Plot Module variants with `module_cache`
- shared graphics and Unit Registry/display-unit infrastructure
- Plugin Install API v1

## 18. Troubleshooting

### No Temporal Window Set is available

Create one in Variables → Temporal Sets. It must belong to the same Dataset and use the same bound time variable.

### Time axis is rejected as non-uniform

The module does not silently reinterpret irregular timestamps as uniform samples. Correct/resample the scientific data explicitly before spectral analysis.

### Explicit worker count is rejected

The requested value exceeds the current CORE worker policy. Use `auto` or a value within the configured limit.

### H1/H2 contains undefined bins

At frequencies where the required denominator has essentially zero spectral energy, a transfer estimate is mathematically undefined. Use the auto-PSD and coherence plots to identify such regions.

### Plot changes trigger no recalculation

That is intentional when only presentation changes. Use `Recalculate` after changing scientific analysis settings if an explicit rerun is desired.


## Numerical service architecture

Version 1.1.1 obtains generic FFT, frequency-grid construction, one-sided transform selection, detrending and reusable windows through public `NUMERIC_API_v1`. The service is resolved from public dependency metadata in the Standard Module runtime configuration, not from a hard-coded module path. Cross-spectrum construction, H1/H2/coherence definitions, PSD normalization and transfer-function semantics remain in this module.
