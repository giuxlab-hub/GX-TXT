# Replicate Curve Analysis v15.2 — Graphics Integration

## Scope

v15.2 keeps the v15/v15.1 architecture: `curve.replicate_analysis` owns scientific Dataset production and graph identity; `plot.dataset` remains the public scientific renderer. The module contains no private result renderer.

## Family uncertainty bands

`PLOT_DATASET_API_v2` does not allow `band` on a Series that still carries `family_variable_id`. The producer must expand that family representation before rendering. v15.2 does this in the bridge using only framework Dataset APIs:

1. Read the family and optional label variables through `TABLE_STREAM_API_v3`.
2. Preserve source encounter order.
3. Create one PlotSpec Series per family member.
4. Remove `family_variable_id`, `family_label_prefix`, and the label-only secondary variable from each expanded Series.
5. Add `row_filters=[exact_equal(family_variable_id, member)]`.
6. Preserve `band.lower_variable_id`, `band.upper_variable_id`, Series style, axis, ordering and existing filters.
7. Apply any active family filter before expansion so no empty family Series are emitted.

This is equivalent to the public Graph Series family-expansion model while keeping the user's producer Graph Series unchanged in the Session.

## Dataset access

No input or derived Dataset is opened through a filesystem path. Family expansion and family-summary labels use Table Stream API calls against Dataset IDs and stable Variable IDs.

## Existing graphics services

v15.2 preserves the v15.1 integration for Graphics inheritance, Plot layout, Axes/Grid, Legend, Level Scale, Series presentation, Annotation, Region Selection, Variants/Clone, USE state, rerender/cache, export/print and `.gxtxt_plotmeta`.
