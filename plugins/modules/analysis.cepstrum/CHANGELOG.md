# Changelog

## 1.1.1

- Completed the numerical-service migration after `math.numeric` gained transform primitives.
- Replaced module-local FFT, IFFT, detrending and window generation with public `NUMERIC_API_v1` calls.
- Retained only cepstrum-specific logarithmic-spectrum, quefrency and peak-selection semantics in the module.
- Resolve `NUMERIC_API_v1` through Standard Module runtime dependency metadata instead of a hard-coded `math.numeric` filesystem path.

## 1.1.0

- Migrated the real-cepstrum scientific graph to persistent `plot.dataset` / `PLOT_DATASET_API_v2`; removed the module-private renderer and rerender path.
- Added `math.numeric` as an explicit dependency and use `NUMERIC_API_v1` for grid validation, mean detrending, linear detrending and quadratic peak refinement. FFT/IFFT and cepstral window construction remain local because NUMERIC_API_v1 does not expose those operations.
- Added a `plot.dataset` graph manifest and retained the conventional PNG artifact as a copy of the provider-owned render.

## 1.0.2

- Add the public CORE Octave I/O path to cache-only rerender, so `gxtxt_ini_read` resolves in a standalone rerender.

## 1.0.1

- Default graph viewport now focuses on the searched quefrency and detected period, excluding the zero-quefrency spike; local Y limits reveal the actual periodicity. Explicit X limits remain honored.

## 1.0.0

- Added Dataset-native real-cepstrum analysis for uniformly sampled time series.
- Added configurable detrending, FFT windows, logarithmic spectral floor, and fundamental search interval.
- Added automatic dominant positive-quefrency peak detection and equivalent-frequency reporting.
- Added reusable `table.generic` publication, report, metrics, scientific render cache, and graph rerendering.
- Added independent student Session Generator package and focused validation.
