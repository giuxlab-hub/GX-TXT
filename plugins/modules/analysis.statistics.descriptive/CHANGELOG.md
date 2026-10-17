# Changelog

## 1.2.0

- Public CORE statistical-result interpretation and publication metadata.
- Numeric-owned mean uncertainty; explicit sampling assumptions and undefined/unavailable states.
- Existing scientific variable IDs and historical releases preserved.

## 1.1.0

- Added automatic public `plot.dataset` histogram and box/whisker variants using GX-TXT 0.9.7.86 `PLOT_DATASET_API_v2` through the public Plot Dataset Octave Bridge v1.
- Added compatible-unit grouping through the public Unit Registry.
- Added a published selected-sample Dataset so plots exactly follow the optional Dataset Selection without private data access.
- Added configurable histogram and box/whisker options.
- Added the deterministic ready-to-run Descriptive Statistics Student Lab Session Generator package, including a student exercise guide.
- Kept CORE unchanged.

## 1.0.0

- Added production `analysis.statistics.descriptive` module.
- Added repeatable multi-variable selection with stable Dataset/Variable identity supplied by GX-TXT CORE.
- Added optional X-range Dataset Selection support.
- Added explicit `omit` / `error` NaN/Inf policy and excluded-observation reporting.
- Added count, valid/excluded counts, min/max/range, mean, median, sample/population variance and standard deviation, standard error, Q1/Q3/IQR, RMS and configurable percentiles through `NUMERIC_API_v1`.
- Added reusable long-form Dataset Publication v2 output and human-readable report.
- Deliberately omitted private automatic plotting because the current public `plot.dataset` capabilities do not provide a scientifically appropriate histogram/boxplot or categorical summary representation for this workflow.
