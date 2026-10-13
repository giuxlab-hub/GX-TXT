# Grouped Statistics — Manual

## Scientific purpose

`analysis.statistics.grouped` calculates descriptive statistics separately for categories or exact numeric values of one grouping variable. Typical uses include measurements by site, treatment, instrument, sample class, season, or replicate group.

The module is deliberately focused. It is not an SQL aggregation engine, ANOVA module, hypothesis-test module, regression module, or data-cleaning tool.

## Inputs

The module consumes one Canonical Dataset through the public Analysis Source infrastructure.

Required configuration:

- one or more numeric **Value variables**;
- exactly one **Grouping variable**.

Optional configuration:

- one `x_range` Dataset Selection from the same source Dataset.

All variable bindings are persisted by the framework as stable `dataset_id + variable_id` identities. The module does not read Dataset Registry internals or construct Dataset file paths.

## Grouping variable

The grouping variable may be a Schema v3 `string` variable or a numeric variable.

String groups are matched exactly and their UTF-8 labels are preserved. An empty/whitespace-only string is a missing group value.

Numeric groups are formed from exact values exposed by the public Table Stream numeric view. `NaN`, `+Inf`, and `-Inf` are invalid group values.

Group order is deterministic: groups are numbered in order of first appearance in the selected data. The published `group_index` is therefore a stable coordinate for that analysis run, while `group_label` preserves the scientific category.

This first version supports one grouping key only.

## Selection

When an `x_range` Dataset Selection is configured, grouping and statistics are computed only from rows inside that Selection. The source Dataset remains unchanged.

## Missing / invalid group policy

`missing_group_policy` is explicit:

- `omit`: rows with a missing/invalid grouping value are excluded from every group and counted in the report;
- `error`: execution stops explicitly when such a row is encountered.

Rows omitted because the grouping value is invalid are distinct from rows excluded because a selected numeric value is non-finite.

## NaN / Inf value policy

`nonfinite_policy` is explicit for numeric value variables:

- `omit`: `NaN`, `+Inf`, and `-Inf` are excluded independently for each group × variable result;
- `error`: execution stops if a selected value contains a non-finite observation in a row that otherwise belongs to a valid group.

The output records the group observation count, finite `count`, and excluded non-finite count for every group × variable row.

## Statistics

For every group × selected value variable the module reports, where defined:

- finite count;
- minimum;
- maximum;
- mean;
- median;
- sample standard deviation;
- standard error of the mean;
- Q1;
- Q3;
- IQR.

The numerical definitions come from public `NUMERIC_API_v1`. Quartiles therefore use the API definition rather than a private implementation.

Location/range statistics are defined with at least one finite observation. Sample standard deviation and standard error require at least two finite observations. Undefined mathematical results are represented explicitly through `location_defined` and `sample_spread_defined`; they are not execution failures.

## Units

Each value variable retains its declared unit in the normalized result through the row-level `unit` column. Numeric statistic columns themselves have no single Dataset-wide unit because one result Dataset may contain variables with different dimensions.

The module never performs private unit conversion. Automatic plot grouping uses the public Unit Registry to determine whether selected variables may share an axis. Compatible units such as `V` and `mV` may share one plot; incompatible quantities are separated.

For canonical elapsed-time values exposed from `value_format=hms`, the public numeric representation is seconds and the module follows that CORE contract.

## Published grouped-result Dataset

The configured output Dataset contains one row per:

```text
group × selected value variable
```

Important columns include:

- `group_index`;
- `group_key`;
- `group_label`;
- `group_numeric_value` and `group_numeric_defined`;
- `group_variable_id`, `group_variable_name`, `group_unit`;
- `variable_id`, `variable_name`, `unit`;
- `observation_count`;
- `count`;
- `excluded_count`;
- `location_defined`;
- `sample_spread_defined`;
- `minimum`, `maximum`, `mean`, `median`;
- `standard_deviation`, `standard_error`;
- `q1`, `q3`, `iqr`.

The Dataset is machine-readable and may be consumed by other GX-TXT modules.

## Plot-support Dataset

When automatic graphs are enabled, the module publishes `<output_dataset_id>.plot`, one row per group, containing:

- numeric `group_index`;
- original `group_label`;
- group observation count;
- per-value-variable mean and SEM;
- per-value-variable median and asymmetric IQR deltas;
- per-value-variable finite count.

This Dataset exists because normal `plot.dataset` Graph Series bind variables, not filtered rows inside a normalized long-form summary. It is a normal derived Dataset published through Dataset Publication API v2, not a private plotting sidecar.

## Automatic graphs and variants

Automatic graphs use the public `PLOT_DATASET_API_v2` through the `standard_octave` public bridge. No private Octave plotting code is used.

For every compatible unit family the module creates two persistent variants:

1. **Grouped means ± SEM** using error-bar series.
2. **Grouped medians + IQR** using asymmetric error bars from median to Q1/Q3.

It also creates one **Group observation count** bar variant.

`plot.dataset` currently uses numeric X for these Cartesian/bar representations, so the X coordinate is `group_index`. The original category labels remain in the plot-support Dataset, report, and `automatic_graphs.ini`. For up to 10 groups the PlotSpec also adds public reference-line annotations carrying the group labels. This is presentation only; group identity remains in the published Dataset.

All automatic plots are persistent variants. They can be reopened and rerendered through normal GX-TXT plot facilities.

## Report

`grouped_statistics_report.txt` records:

- producer/version;
- input and output Dataset IDs;
- grouping variable identity;
- selected value variables;
- Selection;
- non-finite and missing-group policies;
- selected and excluded row counts;
- group-index mapping;
- actual computed statistics;
- undefined-result warnings;
- automatic graph information.

## Provenance and source immutability

Published Datasets identify the producer, producer version, source Dataset, source variables, Selection, and analysis policies through normal GX-TXT publication/provenance mechanisms.

The source Dataset is read-only. The module never deletes, replaces, filters, or mutates source values.

## Error behavior

Execution fails explicitly for invalid scientific configuration, including:

- no Dataset;
- no value variable;
- more or fewer than one grouping variable;
- non-numeric value variable;
- Selection from another Dataset;
- unsupported Selection type;
- invalid policy;
- invalid/missing groups when policy is `error`;
- non-finite values when policy is `error`;
- no valid groups after Selection/policy;
- output Dataset ID conflicts.

Mathematically undefined statistics for a valid group are reported as undefined and are not confused with execution failure.

## Performance and cancellation

The module is serial and low-overhead by design. Table Stream API v3 performs bounded source reads. Exact medians/quartiles require retaining the selected values per group, so memory use grows with the selected observations. No private worker pool is created.

## Public GX-TXT APIs used

- Standard Module API v1
- Analysis Source Map / Access Runtime
- Dataset Variable Schema v3
- Dataset Selection API v1
- Repeatable Config API v1
- Table Stream API v3
- Dataset Publication API v2 and Octave binding
- `NUMERIC_API_v1`
- Unit Registry API v1
- Plot Dataset API v2 and Octave bridge v1
- Progress API v1
- Plugin Install API v1
- Session Generator Library API v1 for the teaching package

## Limitations

- One grouping variable/key per analysis run.
- Numeric grouping is exact-value grouping; no automatic binning is performed.
- Grouped hypothesis tests and ANOVA are outside this module.
- Automatic categorical plots use numeric `group_index` because current `plot.dataset` Cartesian/bar X bindings are numeric. Original labels are preserved and explicitly mapped; no private categorical-axis implementation is introduced.
