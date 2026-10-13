# demo.numeric.statistics

`demo.numeric.statistics` is an independently installable GX-TXT reference plugin that demonstrates the public statistical numerical services already supplied by `math.numeric` / `NUMERIC_API_v1` in GX-TXT 0.9.7.82.

It is intentionally not a production statistics workbench. The plugin contains no private implementation of mean, median, variance, standard deviation, quantiles or weighted statistics.

## Public operations demonstrated

GX-TXT 0.9.7.82 exposes:

- `dataset_statistics` / `statisticsDataset`;
- `statistics`;
- `quantiles`;
- `dataset_weighted_statistics` / `weightedStatisticsDataset`;
- `weighted_statistics`.

The current public numerical API does **not** expose standalone statistical covariance or correlation operations. Those modes are therefore not implemented or emulated here.

## Outputs

Each successful run publishes two normal `table.generic` Datasets through Dataset Publication API v2:

- the configured summary Dataset, default `demo.numeric.statistics.result`, in long form (`statistic`, `value`, `unit`, `definition`);
- `<summary-id>.series`, containing the observations actually included by the public operation plus mean/median reference series, and explicit weights in weighted mode.

The module also writes `statistics_report.txt`, `statistics_metrics.ini`, `render_cache.mat`, and the automatic graph `01_statistics_values.png`.

## Portable example

The plugin bundles `session_generators/gxtxt_numerical_examples_statistics_1.0.0.zip`. Import it into the existing `GX-TXT Numerical Examples` library with `Import Generator...`; it adds `Mathematics -> Statistics` without modifying the framework archive.

See `MANUAL.md` for the full workflow, semantics and test status.

License: GNU GPL v3 or later.
