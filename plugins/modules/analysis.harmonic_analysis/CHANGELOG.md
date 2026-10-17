# 1.2.0 — dev097 statistical ownership

- Delegate the retained estimator to public Numeric and interpret once through CORE.
- Preserve scientific Dataset/Variable identities, add captured metadata and validated reports.
-

# Changelog

## 1.1.0

- Migrated all scientific result graphics from the module-private Octave renderer/render cache/rerender path to persistent `plot.dataset` / `PLOT_DATASET_API_v2` bar variants.
- Added separate persistent dBc, percent-of-fundamental and linear-amplitude variants; dBc uses shared `bar_baseline` so the zero-dBc fundamental remains visible without a private marker overlay.
- Added explicit `math.numeric` dependency and migrated generic grid analysis, descriptive reductions and THD sum-of-squares reduction to public `NUMERIC_API_v1`.
- Removed `render_cache.mat` and the three private render/rerender runtime files.

## 1.0.2

- Add the public CORE Octave I/O path to cache-only rerender, so direct rerenders resolve `gxtxt_ini_read` without relying on the standard-runner environment.

## 1.0.1

- Make the zero-dBc fundamental visibly marked in the default harmonic-level graph; the original zero-height bar falsely appeared absent under headless rendering.

## 1.0.0

- Added Dataset-native harmonic analysis for canonical `spectrum.table` inputs.
- Added automatic and explicit fundamental detection.
- Added integer harmonic tracking with configurable local bin search.
- Added linear amplitude, dBc and percent-of-fundamental output.
- Added THD ratio, percent and dB report values.
- Added canonical `table.generic` publication, provenance, report, metrics and cache-only graph variants.
- Added a portable Harmonic Analysis Session Generator for student exercises.

License: GPL-3.0-or-later.
