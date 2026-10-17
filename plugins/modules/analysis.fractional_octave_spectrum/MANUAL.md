# Fractional-Octave Band Analysis — Manual

## Purpose

`analysis.fractional_octave_spectrum` converts a **linear power spectral density (PSD)** into octave or fractional-octave band quantities.

```text
spectrum.table containing frequency + linear PSD
        ↓
exact fractional-octave band integration
        ↓
canonical spectrum.table with one row per band
        ↓
persistent plot.dataset variants
```

It does not replace `analysis.welch_spectrum`. A normal workflow is `time series → Welch PSD → fractional-octave bands`.

## Scientific definition

The implementation uses the exact base-10 octave ratio:

```text
G = 10^(3/10)
fc(k) = 1000 * G^(k/N)
lower  = fc * G^(-1/(2N))
upper  = fc * G^(+1/(2N))
```

where `N` is the number of bands per octave. The module supports `N = 1, 3, 6`, corresponding to **1/1 octave, 1/3 octave, and 1/6 octave** analysis.

The module integrates a **linear power spectral density** over the exact lower/upper edges. Frequency-bin cells are bounded by midpoints between adjacent frequency samples. A cell intersecting a band edge contributes only its overlapping width.

```text
band_power = integral PSD(f) df
band_rms   = sqrt(band_power)
band_level_db = 20 log10(band_rms / reference_rms)
```

The RMS reference is configurable and defaults to `1` in the underlying signal unit.

## Result interpretation in version 1.2.0

The public Numeric `power_level` operation calculates RMS and logarithmic level
from the already integrated powers. CORE
`STATISTICAL_RESULT_SEMANTICS_API_v1` owns their physical units, reference, zero
policy and descriptive limits. One compact table retains each original band
number as its row identity; a separate descriptive summary records the published
band powers. Both are persisted with the Dataset and survive Session reopening.
The integration algorithm and existing Dataset/Variable IDs are unchanged.

A zero-power band has RMS zero and no finite dB level. Its published level is
`NaN` with CORE status `undefined` and an explanation. A numeric floor is not
reported as a measured level. If every band has zero power, the dB variant is
saved with an unavailable title and its reason is recorded in
`automatic_graphs.ini`; no dB image is rendered. Power and RMS plots still render.
Any previous finite `01_band_level_db.png` is preserved byte-for-byte under
`previous_graphs/` in the owning analysis directory, so it cannot appear as the
current zero result. Existing persistent variants and source payloads remain intact.

## Compliance note

This is FFT/PSD-domain band integration. It **does not claim IEC 61260 instrument-class compliance** and does not emulate a certified fractional-octave filter bank.

## Dataset requirements

Bind:

- **Frequency variable**: numeric, finite, strictly increasing, non-negative, with a unit compatible with `Hz`.
- **Linear PSD**: numeric, finite, non-negative and expressed as power density per Hz, for example `V^2/Hz`, `Pa^2/Hz`, or `1/Hz`.

Do not bind a logarithmic PSD such as dB/Hz. Energy integration must occur in linear power units.

Stable `dataset_id + variable_id` identities are resolved through Analysis Source.

## Frequency range

`Auto` uses only complete bands covered by the positive source spectrum. `Explicit` additionally clips to the requested minimum/maximum frequency.

No incomplete edge band is extrapolated or silently published.

## Output Dataset

The derived `spectrum.table` contains:

```text
center_frequency
band_number
lower_frequency
upper_frequency
bandwidth
band_power
band_rms
band_level_db
coverage_fraction
```

All frequency quantities are canonical Hz. `coverage_fraction` is expected to be 1 for every published band.

## Graphs and presentation

After publishing the band Dataset, the module creates three persistent `plot.dataset` variants:

- band level in dB;
- band RMS;
- band power.

Each uses `kind=bar` with Dataset-bound exact X intervals:

```text
lower_frequency → bar X lower bound
upper_frequency → bar X upper bound
center_frequency → stable X identity
```

This uses the public `PLOT_DATASET_API_v2` capability `bar_x_bounds`. The default X scale is logarithmic. Normal `plot.dataset` axis configuration, display units, legend controls, save/reopen and rerender therefore apply. A user may change the persistent series representation from bar to line without recalculating the fractional-octave analysis.

There is no module-private Render Cache or graph rerenderer in 1.1.0. Presentation changes are owned by `plot.dataset`.

## Session Generator for students

The plugin bundles `gxtxt_numerical_examples_fractional_octave_psd_1.0.0.zip`.

It creates a deterministic linear PSD with:

- 1 Hz spacing from 0 to 4096 Hz;
- white background PSD = `1e-6 V^2/Hz`;
- line power = `0.25 V^2` at 125 Hz;
- line power = `0.09 V^2` at 500 Hz;
- line power = `0.04 V^2` at 2000 Hz.

## Student workflow

1. Generate the example Session.
2. Import `raw/fractional_octave_psd.csv` through the normal CSV path.
3. Set `frequency_Hz` as independent, unit `Hz`.
4. Set `psd_V2_per_Hz` as measured, unit `V^2/Hz`.
5. Enable **Fractional-Octave Band Analysis**.
6. Bind Frequency and Linear PSD.
7. Choose `3` bands per octave and `Auto` range.
8. Use RMS reference `1`.
9. Run. The strongest excess-power bands contain approximately 125, 500 and 2000 Hz.
10. Inspect the three persistent plot.dataset variants for Band level, Band RMS and Band power.
11. Change presentation or create additional plot.dataset variants without recomputing the band integration.
12. Repeat with one band per octave and compare the coarser spectral resolution.

## Interpretation

A flat PSD does not produce equal band power in every octave band: wider bands integrate more white-noise power. Narrow spectral lines mainly contribute to the one band containing that line.

## Limitations

- requires a linear PSD as input;
- no scattered-frequency interpolation/resampling;
- no extrapolation beyond source support;
- no partial edge bands in 1.0.0;
- no IEC 61260 instrument-class compliance claim;
- logarithmic input must be converted back to a scientifically valid linear PSD by another workflow.

## Public GX-TXT APIs used

- Standard Module API v1 / `standard_octave`;
- Analysis Source;
- Canonical Dataset / Variable Schema;
- Table Stream v3;
- Unit Registry conversion;
- Dataset Publication API v2;
- Storage Auto;
- Graph Provider;
- `PLOT_DATASET_API_v2` / persistent variants;
- public `bar_x_bounds` interval-bar presentation;
- Plugin Install API;
- Session Generator Library API v1.
