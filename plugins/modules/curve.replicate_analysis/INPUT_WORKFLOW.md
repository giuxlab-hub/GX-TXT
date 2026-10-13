# Replicate Curve Analysis — Input workflow

Normal use is deliberately simple:

1. Select the primary canonical Dataset.
2. Use the framework-owned **+ Add source** control for every additional Dataset.
3. Bind X, Y and Family when present.
4. Leave **Repeated-data handling = automatic**.
5. Leave Replicate binding on **auto / blank** unless the CSV already contains a true replicate/curve ID column.

## What `automatic` means

### CSV contains `replicate_id`, `curve_id`, `trace_id`, ...

The module detects the column and uses exact trace membership. CSV row order is ignored. Statistics use the original trace-based random-effects ANOVA.

### CSV has repeated digitizations but no ID column

The module **does not guess how many replicates exist**. Point count is not replicate count: one digitization may contain far more points than another.

Instead each `source + family` is treated as an **unlabelled repeated-point cloud**:

- every digitized point is preserved;
- CSV row order is ignored;
- no r1/r2/r3 labels are invented;
- a deterministic local-linear estimate gives the source consensus curve;
- local residual dispersion estimates within-source digitization repeatability;
- dispersion between source consensus curves estimates between-source/session variation;
- `sigma_total = sqrt(sigma_within^2 + sigma_between^2)`;
- `y_sem` is left unavailable because the number of statistically independent repeats is not encoded in the CSV.

This is the correct mode when curves were digitized an unequal number of times and/or with very different numbers of clicked points.

## Fit-ready CSV

The number of raw points or repeat digitizations never determines fitting weight.

- With explicit trace IDs, `reference_grid` uses a real reference trace.
- With an unlabelled point cloud, no individual reference trace exists. Therefore `reference_grid` automatically falls back to a fixed uniform grid of `fit_output_grid_points` points per family over the valid common domain.
- `uniform_grid` explicitly requests the same fixed-grid behavior.

`consensus_for_fitting.csv` remains a clean X / Family / Y file for `curvefit.family_global`.

## Legacy ordered CSV

Use `legacy_ordered_rows` only when row order is known to encode consecutive curves. It is never required for normal v6 use.
