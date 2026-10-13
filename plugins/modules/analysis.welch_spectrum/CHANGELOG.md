# Changelog

## 1.1.0

- Use the public `NUMERIC_API_v1` binding in workers for FFT, detrending and window generation; retain Welch PSD scaling and aggregation semantics.

## 1.0.0

- Initial external `analysis.welch_spectrum` release for GX-TXT 0.9.7.84.
- Added Dataset-native Welch averaged PSD, ASD and mean-amplitude calculation.
- Reused GX-TXT Temporal Window Sets for segment size, step/overlap, parent Selection and partial-window policy.
- Added regular-axis metadata sampling and explicit-axis uniformity validation.
- Added deterministic batched execution through CORE Parallel Execution API v1.
- Added Publication v2 / Storage Auto canonical `spectrum.table` output.
- Added cache-aware Auto / Recalculate / Render only execution.
- Added variant-capable Welch spectrum Graph Provider with PSD dB, PSD linear, ASD and mean-amplitude views.
- Added bundled deterministic `welch_psd` Session Generator and student exercise.
