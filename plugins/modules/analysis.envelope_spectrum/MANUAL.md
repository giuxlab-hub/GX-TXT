# Envelope Spectrum & Demodulation Analysis — Manual

## Purpose

`analysis.envelope_spectrum` extracts the amplitude envelope of a uniformly sampled signal with an analytic-signal (Hilbert-transform) construction and computes the FFT spectrum of that envelope.

Typical uses include amplitude modulation, resonance demodulation, impulsive vibration analysis and educational bearing/fault-frequency examples.

## Architecture

The module owns the envelope-analysis workflow and its scientific meaning. Reusable mathematics is delegated to public `math.numeric` / `NUMERIC_API_v1`, and scientific result graphs are delegated to public `plot.dataset` / `PLOT_DATASET_API_v2`.

```text
Canonical Dataset
        ↓
Analysis Source + optional Dataset Selection
        ↓
NUMERIC_API_v1 detrend / FFT / analytic signal / windows / statistics
        ↓
module-specific demodulation and spectrum semantics
        ↓
Dataset Publication v2
        ↓
canonical time-envelope Dataset + spectrum Dataset
        ↓
plot.dataset persistent graphs / variants
```

The module does not contain a private FFT/window/detrend implementation and does not contain a private scientific result renderer.

## Scientific workflow

```text
canonical time-domain Dataset
        ↓
optional Dataset Selection
        ↓
input detrend
        ↓
optional resonance/carrier isolation
        ↓
analytic signal
        ↓
absolute value = envelope
        ↓
optional envelope-mean removal
        ↓
windowed FFT
        ↓
time-domain envelope Dataset + envelope spectrum Dataset
```

## Analytic signal

For a real record `x[n]`, the public numerical service constructs the analytic signal with the standard discrete FFT Hilbert multiplier: DC is preserved, positive-frequency bins are doubled, negative-frequency bins are suppressed, and the Nyquist bin is preserved for even record lengths. The envelope is the magnitude of the resulting complex analytic signal.

The generic analytic-signal primitive belongs to `NUMERIC_API_v1`; this module decides when and why it is used for envelope demodulation.

## Optional demodulation band

`Pre-demodulation isolation = ideal_fft_bandpass` applies an ideal zero-phase frequency-domain bandpass before the analytic-signal step. The specified lower and upper frequencies must satisfy `0 < low < high < Nyquist`.

The module defines the scientific band-selection workflow. The underlying FFT, IFFT and two-sided frequency grid come from `NUMERIC_API_v1`.

This is deliberately documented as an **ideal FFT bandpass**, not as a Butterworth, FIR or instrument-compliance filter. Its circular/record-boundary behavior should be considered when the selected record contains strong endpoint discontinuities or short transients.

Use `none` when the signal is already narrowband or when no resonance/carrier isolation is desired.

## Input Dataset

Bind:

- one uniformly sampled Time / temporal variable;
- one measured Signal variable.

Both bindings resolve through Analysis Source to stable `dataset_id + variable_id` identities.

Uniform canonical time axes are consumed without materializing the entire time column. Explicit time variables are accepted only when public `NUMERIC_API_v1` grid diagnostics confirm a strictly increasing uniform grid within the module tolerance of `1e-6` relative step deviation.

## Dataset Selection

An optional framework `x_range` Dataset Selection may restrict the analyzed time interval. No private interval-selection model is introduced.

## Input detrend

- `none` — leave the selected signal unchanged;
- `mean` — remove its arithmetic mean;
- `linear` — remove a fitted linear trend.

All three modes use the public numerical detrending primitive.

## Envelope DC handling

`remove_mean` is the normal choice for an envelope spectrum because the average envelope otherwise creates a dominant 0 Hz line. `keep` is available when the DC component is scientifically relevant.

The envelope mean and RMS reported by the module are obtained from public descriptive statistics.

## Envelope-spectrum FFT window

Supported weighting windows:

- rectangular;
- Hann;
- Hamming;
- Blackman;
- Blackman-Harris;
- flat-top.

Window generation and normalization metadata are supplied by `NUMERIC_API_v1`. The module retains the envelope-spectrum semantics: amplitude normalization uses coherent gain, PSD normalization uses `fs * sum(w^2)`, and one-sided interior bins are doubled according to amplitude/PSD conventions.

## NFFT

`auto` uses the selected record length. `explicit` permits zero padding but must be greater than or equal to the number of selected samples.

Zero padding changes frequency-grid interpolation, not physical resolution.

## Output Datasets

The module publishes two canonical derived Datasets through Dataset Publication v2 and Storage Auto.

### Envelope spectrum — `spectrum.table`

- `frequency` [Hz];
- `envelope_amplitude` [source signal unit];
- `envelope_psd` [source-unit squared per Hz];
- `envelope_psd_db` [dB re 1 source-unit squared/Hz].

### Time-domain envelope — `timeseries.table`

- `time` [s], stored as a uniform coordinate;
- `envelope` [source signal unit].

Publishing the full envelope as a Dataset makes it reusable by other GX-TXT analyses instead of keeping it only in a private render cache.

## Graphs and persistent variants

The module creates standard `plot.dataset` graphs for:

1. envelope amplitude spectrum;
2. envelope PSD in dB;
3. envelope PSD in linear units;
4. time-domain analytic envelope.

These are normal persistent `plot.dataset` variants. Axis ranges, linear/log scaling where scientifically valid, labels, shared presentation controls, save/reopen and rerender are provided by the common graphics framework rather than reimplemented by this module.

Presentation changes do not repeat the envelope calculation; operate on the persisted `plot.dataset` graph/variant.

## Student example

The bundled Session Generator creates an 8 s, 8192 Hz amplitude-modulated carrier:

```text
carrier = 2048 Hz
primary envelope modulation = 47 Hz, amplitude 0.40
secondary envelope modulation = 93 Hz, amplitude 0.15
white noise sigma = 0.03
```

Recommended workflow:

1. Import `raw/envelope_spectrum_demo.csv`.
2. Bind Time to `time_s` and Signal to `measured_V`.
3. Use the full record.
4. Set Input detrend = `mean`.
5. Set Pre-demodulation isolation = `ideal_fft_bandpass`.
6. Set band = `1500 ... 2600 Hz`.
7. Set Envelope DC handling = `remove_mean`.
8. Set FFT window = `hann` and NFFT = `auto`.
9. Run the module.
10. Expect dominant envelope-spectrum peaks at 47 Hz and 93 Hz. With 8 s of data, the frequency spacing is 0.125 Hz.
11. Inspect the published time-domain envelope and create additional `plot.dataset` variants as needed.

## Large-data behavior

The source is read with bounded Table Stream chunks, but a global analytic-signal FFT requires the selected signal record in memory. The published time-envelope Dataset is then written in bounded Publication chunks. For very long recordings, create a Dataset Selection for the interval of interest. This is the same fundamental global-transform constraint as other full-record FFT workflows; the module does not pretend that Hilbert/FFT demodulation is a constant-memory transform.

## Limitations

- real, uniformly sampled input only;
- one signal at a time;
- the optional band isolation is an ideal FFT-domain filter with circular record boundaries;
- no order tracking or rotational-speed resampling;
- no bearing-frequency diagnosis database;
- no claim of instrument-standard demodulation-filter compliance.

## Public GX-TXT APIs used

- Analysis Source API;
- Dataset Selection API;
- Variable Schema / stable variable identity;
- Table Stream API v3;
- Unit Registry / requested-unit conversion;
- `NUMERIC_API_v1`;
- Dataset Publication API v2;
- Storage Auto;
- Graph Provider / `PLOT_DATASET_API_v2`;
- progress infrastructure;
- Plugin Install API;
- standard Octave runtime.

The only CORE extension required by this migration is the generic `NUMERIC_API_v1` analytic-signal primitive, implemented in `math.numeric` for reuse by any future consumer.

SPDX-License-Identifier: GPL-3.0-or-later
