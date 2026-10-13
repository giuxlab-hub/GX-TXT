# Changelog

## 1.1.0

- Replaced all private scientific result rendering with persistent `plot.dataset` / `PLOT_DATASET_API_v2` graphs.
- Published the full time-domain analytic envelope as a reusable canonical `timeseries.table` in addition to the existing `spectrum.table`.
- Migrated FFT/IFFT, analytic-signal construction, frequency grids, one-sided transform selection, detrending, reusable windows, grid diagnostics and descriptive reductions to public `NUMERIC_API_v1`.
- Removed module-cache rendering, private rerender code and private local window/detrend implementations.
- Preserved the module-specific ideal FFT band-selection, envelope-spectrum normalization and demodulation semantics.

## 1.0.1

- Read the full explicit-time Table Stream instead of opening an empty range.

## 1.0.0

- Initial external release for GX-TXT 0.9.7.84.
- Dataset-native time/signal binding through Analysis Source.
- Optional Dataset Selection x-range.
- Analytic signal via FFT Hilbert multiplier.
- Optional ideal zero-phase FFT band isolation before demodulation.
- Reusable envelope spectrum Dataset through Publication v2 / Storage Auto.
- Module-cache graph variants for envelope spectrum and time-domain envelope.
- Auto/Recalculate/Render-only cache workflow.
- Bundled deterministic student Session Generator.
