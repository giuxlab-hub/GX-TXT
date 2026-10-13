# analysis.spectral_features 1.1.0

`analysis.spectral_features` is a GX-TXT Dataset-native scientific workflow for compact descriptive characterization of an **existing** non-negative, one-sided spectrum.

It does not recompute the source FFT. Version 1.1.0 follows the mandatory GX-TXT numerical boundary: generic reusable mathematics is consumed from `math.numeric` through public `NUMERIC_API_v1`, while spectral-feature definitions and amplitude/power/PSD interpretation remain in the analysis module.

Normal workflow:

```text
timeseries.table
→ analysis.fft_spectrum or analysis.welch_spectrum
→ spectrum.table
→ analysis.spectral_features
→ summary Dataset + plot-ready distribution Dataset
→ persistent plot.dataset variants
```

## Scientific features

- dominant frequency;
- spectral centroid;
- RMS frequency;
- spectral bandwidth;
- 5%, 50%, 85%, and 95% weighted cumulative-power frequencies;
- 90% occupied bandwidth (`F95 - F05`);
- spectral flatness;
- spectral crest factor;
- normalized spectral entropy;
- explicit amplitude, power, or PSD input semantics;
- optional DC-bin exclusion.

## Shared services

Generic grid checks, descriptive reductions, weighted statistics, arbitrary weighted quantiles, and cumulative sums are obtained through `NUMERIC_API_v1`. Scientific result plots are persistent `plot.dataset` / `PLOT_DATASET_API_v2` variants. The module contains no private plotting subsystem and no private replacement for these generic numerical primitives.

The module publishes:

- `<output_dataset_id>` — one-row reusable feature summary;
- `<output_dataset_id>.distribution` — frequency, normalized power, cumulative power, and relative-power variables used by normal downstream tools and plots.

Install `analysis.spectral_features_1.1.0.zip` through the normal Plugin Install API. The bundled `gxtxt_numerical_examples_spectral_features_1.0.0.zip` remains the deterministic student fixture.
