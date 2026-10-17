# Descriptive Statistics — User and Technical Manual

## Purpose

`analysis.statistics.descriptive` computes ordinary descriptive statistics for one or more numeric variables from one Canonical Dataset. It is intentionally focused: grouped statistics, correlation, distributions, outlier detection and weighted statistics belong to separate modules.

## Input

Choose one Dataset through the normal Analysis Source control. Add one or more rows to **Variables** and choose the numeric variables to summarize. GX-TXT persists variable choices with Dataset-qualified stable variable identities and resolves the current names at runtime.

An optional `x_range` Dataset Selection may restrict the rows used by every selected variable. The module never reads private Dataset files and never mutates the source Dataset.

## Statistics

For each variable the module reports:

- selected observation count;
- finite/valid observation count;
- excluded NaN/Inf count;
- minimum, maximum and range;
- mean and median;
- sample and population variance;
- sample and population standard deviation;
- standard error of the mean, defined as sample standard deviation divided by the square root of the valid count;
- Q1, Q3 and IQR;
- RMS;
- additional configured percentiles.

`NUMERIC_API_v1` supplies minimum/maximum/range, mean, median, quartiles, IQR, population/sample variance and standard deviation, RMS and quantiles. Quartiles/quantiles therefore use the API's documented Hyndman-Fan type 7 definition. The module derives only the standard error from the API's sample standard deviation and valid count.

## NaN / Inf policy

**Omit** explicitly excludes NaN, `+Inf` and `-Inf` from numerical statistics and reports the number excluded. **Error** stops the analysis if any selected observation for a variable is non-finite. No non-finite value is silently mixed into valid data.

Rows excluded because they lie outside an optional Dataset Selection are not counted as missing/non-finite observations; they are outside the analyzed subset.

## Undefined valid states

With exactly one valid observation, sample variance, sample standard deviation and standard error are mathematically undefined. The output Dataset stores `NaN` for those values and sets `defined=false`. The report writes `undefined`. This is distinct from execution failure.

A selected variable with zero observations or zero finite observations is an explicit error.

## Additional percentiles

The **Additional percentiles** field accepts values from 0 through 100 separated by commas or semicolons, for example:

```text
1;5;10;90;95;99
```

Q1, median and Q3 are already standard outputs, so configured 25, 50 and 75 percentiles are not duplicated.

## Output Dataset

The module publishes a compact long-form `table.generic` Dataset. Each row is one statistic for one source variable.

Columns:

| Column | Meaning |
|---|---|
| `variable_id` | stable source Variable ID |
| `variable_name` | current source variable name |
| `statistic` | statistic identifier |
| `value` | numerical result |
| `defined` | whether the result is mathematically defined |
| `unit` | numerical result base unit |
| `unit_power` | `0` for counts, `1` for source-unit results, `2` for variance |
| `observation_count` | selected observations before non-finite filtering |
| `valid_count` | finite observations used |
| `excluded_count` | selected NaN/Inf observations excluded |

The `value` column intentionally has no Dataset-level unit because a long-form result contains dimensionless counts, source-unit quantities and squared-unit variances in the same column. `unit + unit_power` preserves the dimensional interpretation without inventing private unit conversion rules. For Dataset variables declared as `value_kind=elapsed_time`, Table Stream exposes the public canonical numeric representation in seconds; the summary therefore reports `unit=s` for computed values instead of relabelling canonical seconds with the source display unit.

## Report

`descriptive_statistics_report.txt` contains the actual results, source Dataset, selected variables, Selection ID, non-finite policy, counts, warnings, producer version and publication information.

`descriptive_statistics_summary.ini` contains a compact machine-oriented run summary in addition to the published Dataset.

## Automatic graphs

Version 1.1.0 uses public `PLOT_DATASET_API_v2` distribution series through **Plot Dataset Octave Bridge v1** (`gxtxt_plot_dataset_v2`), available from GX-TXT 0.9.7.86. The production module does not source the GX-TXT desktop host or write private plot state. When **Create automatic distribution plots** is enabled, the module publishes a small derived sample Dataset containing exactly the selected observations and then creates persistent `plot.dataset` variants for:

- histogram;
- box/whisker summary with optional outlier display.

The plot sample Dataset is a normal published GX-TXT Dataset with provenance. It is not a private cache and the source Dataset remains unchanged. `NaN`, `+Inf` and `-Inf` are preserved in this intermediate Dataset; `plot.dataset` applies its documented finite-sample distribution policy.

Variables are grouped only when their units are compatible according to the public Unit Registry. For example, `V` and `mV` may share a plot because `plot.dataset` can use the common unit service; `A` is placed in a separate plot. No local unit-conversion formula is implemented by this module.

Each automatic graph is created as a normal persistent **plot variant**, so the user can open, edit, rerender and preserve it through the standard GX-TXT plot workflow. The generated PNG copies are listed in `automatic_graphs.ini`.

Configuration:

- **Histogram bins**: `auto` or an integer from 2 through 512;
- **Histogram normalization**: `count`, `probability` or `density`;
- **Box/whisker IQR multiplier**: positive number, default `1.5`;
- **Show box/whisker outliers**: boolean.

These plots are descriptive overviews. Distribution-specific frequency tables, empirical CDFs and explicit binning workflows remain the responsibility of `analysis.statistics.distribution`.

## Student teaching Session

The package includes `session_generators/gxtxt_descriptive_statistics_student_lab_1.0.0.zip`, a Session Generator API v1 package intended for the standard `GX-TXT Numerical Examples` library. It creates a ready-to-run Session containing:

- `V` and `mV` variables to demonstrate compatible units;
- an `A` variable to demonstrate automatic separation of incompatible quantities;
- constant, signed, single-value and two-value variables;
- explicit `NaN` observations;
- a persisted `x_range` Dataset Selection;
- stable Variable IDs and preconfigured Repeatable Config rows;
- reference values in `metadata/ground_truth.txt`;
- a root-level `STUDENT_GUIDE.txt` with the first run and follow-up exercises.

The production module does not depend on this generator. It is only deterministic teaching/test material.

## Provenance

The published Dataset records the producer module/version, source Dataset, source Variable IDs and normal Publication provenance. Optional Selection identity and analysis configuration are also present in the report/run summary.

## Errors

The module fails explicitly for missing Dataset, no selected variable, duplicate variable selection, unresolved/missing stable Variable ID, text/non-numeric variables, invalid percentile values, invalid output Dataset ID, incompatible Selection source, unsupported Selection type, empty selection result, zero finite observations, and non-finite data when policy is `error`.

## Public GX-TXT APIs used

- Standard Module API v1
- Analysis Source Map API v1
- Analysis Source Access Runtime v2
- Dataset Variable Schema API v3
- Dataset Selection API v1
- Repeatable Config API v1
- Table Stream API v3
- Dataset Publication API v2 and Octave binding
- `NUMERIC_API_v1` from `math.numeric`
- Unit Registry API v1
- Plot Module API v1
- `PLOT_DATASET_API_v2`
- Plot Dataset Octave Bridge v1 (`gxtxt_plot_dataset_v2`)
- Progress API v1
- Plugin Install API v1
- Session Generator Library API v1

## Limitations

This module is not grouped statistics, distribution analysis, correlation, outlier detection, weighted statistics, regression or fitting. It does not perform local unit conversion and does not combine variables into a shared statistic. Ordinary numeric variables are summarized in their declared source unit; elapsed-time values follow the CORE canonical-seconds contract. Because variables are summarized independently, selecting variables with incompatible units is valid and never causes them to be combined or compared.

## Statistical interpretation (dev097)

Published results include the public `STATISTICAL_RESULT_SEMANTICS_API_v1`
record, with units, statuses, reasons and source identity. Numeric computes all
estimates. Sampling standard errors assume independent observations with finite
variance; they do not establish Gaussian noise or confidence intervals. A single
finite observation has no estimated sample spread or sampling standard error.
Existing output variable IDs remain unchanged.
