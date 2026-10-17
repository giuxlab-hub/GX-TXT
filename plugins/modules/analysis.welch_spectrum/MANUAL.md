# Welch PSD & Averaged Spectrum — Manual

## 1. Purpose

`analysis.welch_spectrum` estimates the averaged frequency content of one uniformly sampled signal. It is intended for stationary or approximately stationary measurements where a single full-record FFT is too sensitive to noise or record-specific fluctuations.

The module implements the Welch idea using GX-TXT resources rather than a private segmentation model:

```text
Canonical Dataset
    ↓
Analysis Source: time + signal
    ↓
Temporal Window Set
    ↓
periodogram for each resolved window
    ↓
arithmetic spectral average
    ↓
canonical spectrum.table
    ↓
variant-capable graph
```

It is distinct from:

- `analysis.fft_spectrum`, which produces a global FFT spectrum for one record/block;
- `analysis.time_dependent_fft`, which preserves the time evolution of the spectrum instead of averaging it;
- `analysis.cross_spectral_transfer`, which analyzes paired input/output signals and transfer/coherence relationships.

## 2. Installation

Install `analysis.welch_spectrum_1.2.0.zip` through the normal GX-TXT Plugin Install workflow.

Minimum supported framework: **GX-TXT 0.9.7.84**.

The plugin is external and does not modify CORE.

## 3. Dataset requirements

The selected Dataset must provide:

- one temporal/independent variable;
- one numeric measured signal variable;
- at least one existing Temporal `window_set` compatible with that Dataset and temporal variable.

Analysis Source bindings use the Dataset stable `variable_id`; column names are not used as technical identities.

The time coordinate must be uniformly sampled. A canonical implicit uniform axis is consumed directly from schema metadata. An explicit time variable is validated before FFT processing. Strongly non-uniform data are rejected rather than silently treated as uniform.

## 4. Temporal Window Set and overlap

The Temporal Set owns segmentation. The module does not generate overlapping segments privately.

For a sample-based Window Set:

```text
Window size = 2048 samples
Step        = 1024 samples
```

means that each segment contains 2048 samples and each new segment begins 1024 samples after the previous segment. The overlap is:

```text
overlap = 1 - step/window_size
        = 1 - 1024/2048
        = 0.5 = 50%
```

The same principle applies to duration-based Temporal Sets. Parent Selection and partial-window policy are also resolved by the framework.

For normal Welch analysis, `Drop` is recommended when an incomplete final segment would otherwise have a different statistical weight/window length.

## 5. Processing of each segment

Each resolved Temporal Set member is processed as:

```text
source samples
→ optional detrend/DC removal
→ FFT weighting window
→ FFT / zero padding to common NFFT
→ one-sided normalized periodogram
→ one-sided normalized amplitude spectrum
```

Supported FFT weighting windows:

- rectangular;
- Hann;
- Hamming;
- Blackman;
- Blackman-Harris;
- flat-top.

Supported detrend modes:

- `none`;
- `mean` — remove segment mean/DC;
- `linear` — remove a fitted linear trend.

## 6. NFFT

`Auto` sets NFFT to the resolved nominal Temporal Set window length in samples.

`Explicit` accepts an integer NFFT greater than or equal to the nominal window length. Larger NFFT values zero-pad the FFT. Zero padding changes frequency-grid spacing but does not create additional physical frequency resolution.

For sampling rate `Fs` and NFFT `N`:

```text
Δf = Fs / N
```

## 7. Power spectral density (PSD) normalization

For segment samples `x[n]`, weighting window `w[n]`, sampling frequency `Fs`, and FFT `X[k]` of `x[n]w[n]`, the two-sided periodogram normalization is:

```text
PSD[k] = |X[k]|² / (Fs * Σ w[n]²)
```

The module keeps the non-negative one-sided spectrum. Interior bins are multiplied by two; DC and, for even NFFT, Nyquist are not doubled.

The arithmetic mean across all resolved segments is the published Welch PSD.

For a signal unit such as `V`, the PSD unit is represented as `V^2/Hz`.

The report also records the equivalent noise bandwidth:

```text
ENBW = Fs * Σw² / (Σw)²
```

## 8. ASD

Amplitude spectral density is:

```text
ASD = sqrt(PSD)
```

For a voltage signal its unit is represented as `V/sqrt(Hz)`.

ASD is often convenient when comparing spectral noise with amplitude-domain specifications.

## 9. Mean amplitude spectrum

Each segment also produces a coherent-gain-normalized one-sided amplitude spectrum:

```text
A[k] = |X[k]| / |Σw|
```

with interior one-sided bins doubled. `mean_amplitude` is the arithmetic mean of those per-segment amplitude spectra.

This quantity is useful for stable deterministic tones, but it is **not** a replacement for PSD when characterizing broadband random noise.

## 10. PSD dB representation

The module publishes:

```text
psd_db = 10 log10(PSD)
```

with numerical reference 1 in the PSD unit. The dB variable is primarily a convenient display representation. The linear PSD remains the authoritative physical density.

## 11. Parallel execution

Independent Temporal Set windows are naturally parallel. The plugin uses **CORE Parallel Execution API v1** only; it does not create a private Octave pool.

To reduce process-startup overhead, windows are grouped into deterministic batches of up to eight windows. Each worker:

1. reads only the source ranges belonging to its batch;
2. computes normalized segment spectra;
3. returns accumulated PSD/amplitude sums and window count.

The main process merges batch results in deterministic input order. Serial and parallel execution therefore use the same scientific calculation and must produce equivalent spectra within normal floating-point tolerance.

Worker internal-thread hints come from CORE `recommended_internal_threads` to avoid oversubscription.

## 12. Large-data behavior

The complete source signal is not loaded into memory. Workers read only the resolved source ranges through Table Stream.

The output is compact: one common frequency grid plus four one-dimensional spectral variables. Publication v2 / Storage Auto chooses the physical storage provider.

## 13. Output Dataset

The published Dataset contract is `spectrum.table` with:

```text
frequency       [Hz]
psd             [signal_unit^2/Hz]
asd             [signal_unit/sqrt(Hz)]
mean_amplitude  [signal_unit]
psd_db          [dB]
```

`frequency` is a canonical implicit uniform axis with origin 0 and step `Fs/NFFT`.

Provenance records source Dataset/variables, Temporal Set, window, detrend, NFFT and module version.

## 14. Run modes and Render Cache

- **Auto**: reuse a compatible scientific cache if available; otherwise calculate.
- **Recalculate**: force a new spectral calculation.
- **Render only**: require a compatible cache and only regenerate the graph.

Graph-only changes do not require the Welch calculation to be repeated.

## 15. Graph and variants

Graph ID:

```text
analysis.welch_spectrum.spectrum
```

It supports Plot Module variants with `variant_data_model=module_cache`.

A variant may change presentation without recalculation, including:

- quantity: PSD dB / PSD linear / ASD / mean amplitude;
- title;
- X/Y labels;
- frequency-axis linear/log scale;
- Y-axis linear/log scale where values permit it;
- display frequency unit through normal GX-TXT graphics controls;
- axis ranges through standard Plot controls;
- optional PDF/SVG output.

Scientific settings such as Temporal Set, FFT window, detrend or NFFT are not graph variants. Changing them requires a new calculation.

## 16. Student Session Generator

The plugin bundles:

```text
gxtxt_numerical_examples_welch_psd_1.0.0.zip
```

Import it into the existing **GX-TXT Numerical Examples** Session Generator Library.

Generator ID: `welch_psd`  
Category: `Signal Processing`  
Suggested Session: `welch-psd-example`

The generated signal is 32 s at 1024 Hz:

```text
x(t) = 0.8 sin(2π·50t)
     + 0.35 sin(2π·123t)
     + deterministic white Gaussian noise, σ = 0.20 V
```

It includes both `clean_V` and `measured_V` so students can compare deterministic and noisy spectra.

Recommended Temporal Set:

```text
Basis        = Samples
Window size  = 2048
Step         = 1024
Partial      = Drop
Parent       = All dataset
```

This resolves to 31 segments, 50% overlap, NFFT 2048 in Auto mode and `Δf = 0.5 Hz`.

Expected prominent frequencies are 50 Hz and 123 Hz. Ground truth includes tone powers, the ideal one-sided white-noise PSD level and expected total mean-square signal power.

The generated `STUDENT_GUIDE.md` contains the complete exercise.

## 17. Interpretation

Welch averaging reduces periodogram variance by averaging spectral estimates from multiple overlapping segments. Overlap increases the number of available estimates without requiring a longer source record, although overlapping windows are statistically correlated.

Window choice affects leakage and equivalent noise bandwidth. A Hann window is a useful default for general spectral work; flat-top is useful when amplitude accuracy of isolated tones is more important than narrow main-lobe width.

PSD should be preferred over raw FFT magnitude when comparing broadband noise between recordings or segment lengths because PSD is normalized per unit bandwidth.

## 18. Limitations

- The signal must be sampled uniformly enough for FFT analysis.
- No resampling is performed.
- The first release analyzes one signal from one Dataset at a time.
- Complex-valued input is not declared as a supported input contract.
- Segment averaging is arithmetic and gives equal weight to each resolved segment.
- Very short included partial windows can have different ENBW; `Drop` is recommended for conventional Welch use.
- Zero padding improves frequency-grid interpolation, not physical spectral resolution.

## 19. Troubleshooting

**No Temporal Window Set is available**  
Create one in Variables → Temporal Sets. Ensure it uses the same Dataset and bound time variable.

**The result has poor frequency resolution**  
Increase the Temporal Set window size. Resolution is primarily set by segment duration, not by overlap.

**Too few averages / noisy PSD**  
Use a longer record, a smaller step (more overlap), or a shorter segment if scientifically acceptable.

**Strong DC component**  
Use `Detrend = mean` unless DC is intentionally part of the spectrum.

**Render only fails**  
The scientific cache is absent or stale because source data, Temporal Set or analysis parameters changed.

**Log plot is empty or incomplete**  
Log axes require strictly positive plotted values. DC at zero frequency is omitted automatically for log-X display.

## 20. Public GX-TXT APIs used

The implementation uses the current public facilities in GX-TXT 0.9.7.84:

- Analysis Source API;
- Canonical Dataset / Variable Schema;
- Temporal Set API v1;
- Table Stream API v3;
- elapsed-time / Unit Registry conversion;
- Parallel Execution API v1 and the `standard_octave` binding;
- Dataset Publication API v2;
- Storage Auto;
- Render Cache API;
- Graph Provider / Plot Module API v1 including module-cache variants;
- Plugin Install API;
- Session Generator Library API v1 for the bundled teaching fixture.

No private scheduler, private Dataset reader or CORE modification is used.

## Statistical semantics in 1.2.0

The public Numeric API owns final spectrum aggregation; the versioned CORE
statistical API owns units, quantity definitions and interpretation. Published
Dataset metadata and render caches retain the same captured result, including
source/Variable/Temporal Set IDs, window, detrending, NFFT, window rows, step and
partial-window policy. No sampling uncertainty is inferred from overlapping
windows. Dataset and Variable identifiers are unchanged.

Zero PSD is published with NaN in `psd_db`, since no finite logarithmic value
exists. An entirely zero PSD retains an explicitly unavailable dB plot variant;
its previous image is preserved under `previous_graphs/` and removed from the
current artifact path. Linear PSD, ASD and mean-amplitude views remain valid.
A zero non-DC spectrum has no peak frequency, including a DC-only signal.

Compatible caches rerender without spectral recomputation. A pre-1.2 cache lacks
this captured CORE result: cache-only rendering rejects it with a recalculation
message. Explicit recalculation or normal Auto analysis creates a current cache;
existing historical releases and source data are not migrated or rewritten.
