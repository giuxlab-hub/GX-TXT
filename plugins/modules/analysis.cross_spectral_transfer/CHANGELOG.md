# Changelog

## 1.1.3

- Classified the independently packaged module as a managed external plugin.

## 1.1.2

- Fixed the parallel Octave worker script so the scientific window calculation starts correctly after dependency validation.
- Validated the installed module on a generated 12-window Session: published H1/H2 gain, phase and coherence at three known input tones, plus persistent Plot.dataset variants.
- Raised the required GX-TXT framework version to 0.9.8.06.

## 1.1.1

- Completed the numerical-service migration after `math.numeric` gained transform primitives.
- Replaced module-local FFT, detrending and window generation with public `NUMERIC_API_v1`; one-sided bin selection and frequency-grid construction now also use the public numerical service.
- Preserved cross-spectrum, H1/H2, coherence and PSD normalization semantics in the scientific module.
- Resolve `NUMERIC_API_v1` through Standard Module runtime dependency metadata instead of a hard-coded `math.numeric` filesystem path.

## 1.1.0

- Migrated all scientific result graphs to persistent `plot.dataset` variants.
- Removed the module-private plotting and rerender implementation.
- Added `math.numeric` as a dependency and use of public `NUMERIC_API_v1` for generic detrending statistics and polynomial fitting.
- Published plot-ready unwrapped-phase and dB PSD variables so graph variants remain Dataset-native.

## 1.0.0

Initial release.

- Added canonical same-Dataset `time + input X + output Y` binding model.
- Added Temporal `window_set` averaging.
- Added Hann, Hamming, Blackman, Blackman-Harris, flat-top and rectangular FFT weighting windows.
- Added none/mean/linear detrending.
- Added automatic or explicit NFFT.
- Added CORE Parallel Execution API v1 window processing and serial fallback.
- Added one-sided averaged `Sxx`, `Syy`, complex `Sxy`, H1/H2 transfer estimates and magnitude-squared coherence.
- Added canonical `spectrum.table` publication through Publication v2 / Storage Auto.
- Added Render Cache with Auto / Recalculate / Render only execution modes.
- Added Graph Providers for transfer magnitude, transfer phase, coherence and input/output PSD.
- Added persistent Plot Module variants using `variant_data_model=module_cache`.
