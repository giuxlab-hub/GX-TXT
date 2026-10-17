## 1.3.0

- Use Numeric and the public CORE statistics API for grouped mean intervals,
  Pearson correlation, MAD and fit reporting; persist compact records in every
  derived and plotting Dataset.
- Replace the private t approximation with Numeric quantiles and retain genuine
  untruncated interval bounds. Label time-aggregate intervals as conditional.
- Interpret estimated SEM fit weights as relative, preserving canonical IDs and
  source measurements. Preserve descriptive QC/MAD teaching conventions.
- Load the plotting helper's fixed framework entry at global scope without
  dynamic statistical dispatch.

## 1.2.20

- Publish automatic graphs through Plot Dataset API v3 and commit current Session state through Session Persistence API v1.

# Changelog

## 1.2.1

- Renders both spatial views as persistent public Plot.dataset 3D variants
  from the already published site-summary Dataset.
- Gives the twelve 2D variants stable provider identities across reruns.
- Keeps all fourteen graphs in the automatic graph manifest and shared plot
  window, with no module-owned static figure renderer.

## 1.2.0

- Expanded the demonstration into one configurable analysis suite instead of separate specialized plugins.
- Added independent output switches for campaign summary, seasonality, wildfire analysis, uncertainty/QC, cross-site relationships, anomaly detection and spatial analysis.
- Added independent switches for automatic 2D rendering and 3D spatial rendering.
- Added configurable technical-replicate CV threshold, anomaly moving-median window, positive robust anomaly threshold and cross-site lag range.
- Added daily analytical-QC outputs and per-site QC plotting Datasets.
- Added positive robust anomaly detection using a moving-median baseline and MAD-based scale, plus per-site anomaly plotting Datasets.
- Added synchronized short-lag cross-site correlation analysis.
- Expanded automatic `plot.dataset` output from eight to twelve selectable 2D graphs.
- Added two optional 3D spatial views through public `PLOT_3D_API_v2` graphics helpers.
- Added elevation as an optional public binding with stable-variable fallback for Sessions created by generator 1.1.0.
- Updated the bundled Session Generator to 1.1.1 so new Sessions bind `elevation=primary.elevation_m` explicitly; the synthetic scientific data model and seed are unchanged.
- Kept derived scientific Datasets publication independent from presentation switches so reruns do not leave stale tables.
- Added focused regressions for configuration, binding contract, 12 PlotSpecs, graph-group filtering, generator integration and package installation.
- Set the supported framework minimum to GX-TXT 0.9.7.77 and verified Plugin Install API rejection on 0.9.7.76.

## 1.1.1

- Fixed the ready-to-run runtime binding contract for geographic coordinates.
- The module descriptor and generated Session correctly bind `latitude` and `longitude`; the Octave runtime had mistakenly requested a non-existent `coordinate` binding twice.
- Source validation now checks `latitude` and `longitude` explicitly, matching the public binding roles and generated runtime configuration.
- Added a focused binding-contract regression against GX-TXT 0.9.7.77.
- The bundled Session Generator remains version 1.1.0 because its generated Dataset, Variable Schema, Dataset Metadata, Analysis Source and bindings were already correct.

## 1.1.0

- Rebuilt the bundled Session Generator as a ready-to-run demonstration workflow.
- Generated Sessions now contain a registered canonical source Dataset, Dataset Variable Schema API v3 metadata, persisted Dataset Metadata, primary Analysis Source selection and stable variable bindings.
- The demo module is preselected for analysis; no CSV import, Dataset Metadata import, schema editing or manual binding is required.
- Persisted framework-compatible semantic roles (`independent`, `group`, `coordinate`, `concentration`, `generic`) together with stable scientific variable IDs and units, avoiding any post-install semantic-registry dependency.
- Replaced ambiguous wide graph-only Datasets with simple coordinate-aware per-site plotting Datasets.
- Split fire-exposure and fire-distance regression curves into independent two-variable Datasets.
- Published coordinate relationships on derived variables through Dataset Publication API v2.
- Added end-to-end public-API regressions against GX-TXT 0.9.7.75 and 0.9.7.76 for the ready-to-run generated Session and all eight PlotSpecs.

## 1.0.2

- Fixed automatic graph generation on real GX-TXT 0.9.7.75 runs.
- The Tcl plot helper now sources `gxtxt_pipeline.tcl` explicitly at global scope instead of from inside the helper procedure scope.
- This preserves framework globals such as `argv0` for the source-safe GX-TXT entry-point check and removes the `can't read "argv0": no such variable` failure.
- Added a focused regression that executes the same framework-source path from inside the helper procedure against an extracted GX-TXT baseline.

## 1.0.1

- Fixed the daily Dataset Publication v2 failure on real GX-TXT 0.9.7.74 runs.
- The all-days daily summary no longer publishes `nearest_fire_distance_km`, because that quantity is undefined on non-fire days and was represented as NaN.
- Active-fire distance remains available in the source Dataset and in `demo.environmental.levoglucosan.fire_relationships`, where every published row has a defined finite distance.
- Added an explicit pre-publication finite-value diagnostic so future derived-table mistakes identify the Dataset and variable before the Publication v2 bridge call.

## 1.0.0

- Initial release of `demo.environmental.levoglucosan_campaign`.
- Added the deterministic `sardinia_levoglucosan_campaign` Session Generator.
- Added a 365-day, four-site, three-replicate synthetic Sardinia campaign.
- Added explicit LOD/LOQ handling and retained below-limit measurements.
- Added Dataset Metadata import material with `data.synthetic=true`.
- Added daily Student-t confidence intervals for technical triplicates.
- Added monthly, seasonal, annual, fire/non-fire and geographical summaries.
- Added synchronized pairwise site correlations and weighted fire-exposure and
  active-fire-distance regressions.
- Added ten canonical derived Datasets through Dataset Publication API v2.
- Added eight automatic `plot.dataset` graphs, including error bars,
  uncertainty bands and a wildfire reference region.
- Added scientific text report and machine-readable metrics.
- Added generator, framework-import, PlotSpec and package regressions.
