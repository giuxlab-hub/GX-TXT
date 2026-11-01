# 2D Family modernization requirement

SPDX-License-Identifier: GPL-3.0-or-later

## Current status

GX-TXT 0.9.7.22 Graph Series API v1 binds one whole canonical dataset to one
stable X variable and one stable Y variable. It has no public row-selection or
group-membership predicate. Therefore `plot.dataset` cannot represent one
family member as a real modern Graph Series without extending that public
capability.

The legacy private row-grouping implementation has been removed from the 2D
worktree and must not be restored.

## Minimum future Graph Series semantics

A family-expanded Graph Series needs the existing fields:

```text
dataset_id
x_variable_id
y_variable_id
axis
enabled
order
```

plus an optional row selection whose minimum useful exact-equality form is:

```text
filter_variable_id
predicate = exact_equal
filter_source_value = <exact canonical source value>
```

`filter_source_value` is scientific identity. It must be preserved independently
of display formatting or legend text.

For example, canonical source value `-2.5` remains the member identity even if
the legend later displays `-2.50 V`. Two distinct canonical values must never be
merged because formatting rounds them to the same displayed string.

## Intended workflow

```text
family definition
  -> enumerate exact canonical member values
  -> one Graph Series per member with row predicate
  -> normal PlotSpec presentation
  -> normal plot.dataset 2D renderer
```

No hidden PlotSpec filter, `series_id` encoding, private family registry,
temporary per-member CSV, legacy family renderer, or second renderer is an
acceptable substitute.
