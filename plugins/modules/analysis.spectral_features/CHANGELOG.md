# Changelog

## 1.2.0 — dev097

- Public Numeric spectral-distribution operation owns the existing calculation.
- Public CORE owns scalar definitions, units, applicability, reports and persisted metadata.
- Preserved Dataset/Variable and metric identities, fixed duplicate legend units, and declared the existing Plot Dataset dependency.
- Tested analytical spectra, Worksheet units, both real Script languages, 100,001-bin bounded interpretation, module publication, reopening and three plot outputs.

## 1.1.0

- Added explicit `math.numeric` dependency and migrated generic grid/reduction operations to public `NUMERIC_API_v1`.
- Extended `math.numeric` 1.4.0 with generic `weighted_quantiles` and `cumulative_sum` primitives required by this consumer.
- Published a reusable plot-ready distribution Dataset instead of private render-cache state.
- Migrated all scientific result graphics to persistent `plot.dataset` / `PLOT_DATASET_API_v2` variants.
- Removed the private Octave renderer and rerender path.

## 1.0.0

- Added `analysis.spectral_features` as an external Dataset-native spectrum consumer.
- Added dominant/centroid/RMS/bandwidth, cumulative-frequency, occupied-bandwidth, flatness, crest-factor and entropy descriptors.
- Added explicit amplitude/power/PSD semantics and optional DC exclusion.
- Added canonical summary Dataset publication, report, metrics, cache-only graph variants, tests, and a portable student Session Generator.
