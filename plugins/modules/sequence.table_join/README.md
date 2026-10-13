# Sequential Table Join — `sequence.table_join`

SPDX-License-Identifier: GPL-3.0-or-later

Generic GX-TXT v0.8.9 analysis plugin for concatenating two or more canonical `timeseries.table` datasets into one global time series.

## Intended workflow

1. Import each instrument file as its own canonical dataset.
2. Enable **Sequential Table Join**.
3. In **Analysis**, select one segment as `primary`.
4. Press **+ Add source** for every other segment and select its Dataset ID.
5. Source order does not matter.
6. Set `Output Dataset ID`, for example `reactor.current.complete`.
7. Run the module.

The module sorts segments by the first value of `timestamp_s` (or the configured absolute-time column), validates them, writes `joined_sequence.csv`, and publishes it through Dataset Publication API v1 as a new canonical `timeseries.table` dataset.

A subsequent plotting module can therefore select the published dataset directly from the same session. A second acquisition/import pass is not required.

## Scientific rules

- at least two populated source datasets;
- every source must be `timeseries.table`;
- all CSV schemas must match exactly, including column order;
- the absolute-time column must be finite and strictly increasing inside every segment;
- selection order is ignored;
- segments are sorted by their actual first absolute timestamp;
- gaps are allowed and preserved;
- overlap is rejected;
- an identical timestamp at the boundary between two segments is rejected as an overlap/duplicate;
- no averaging, interpolation, resampling or implicit alignment is performed.

## Relative time

If `Global relative-time column` is non-empty (default `time_s`), the output relative time is rebuilt from the earliest absolute timestamp:

```text
time_s = timestamp_s - first_timestamp_of_earliest_segment
```

If the named relative-time column is absent from the input schema, it is appended. If the configuration field is blank, input columns are preserved unchanged.

## Outputs

- `joined_sequence.csv` — concatenated canonical table;
- `join_report.txt` — input order, chronological order, ranges and separation between adjacent segments;
- publication request handled by GX-TXT v0.8.9, resulting in the configured output Dataset ID in the Dataset Registry.

## Framework APIs used

- Standard Module API v1
- Analysis Source Map API v1 (`dynamic=1`)
- Dataset Publication API v1
- Dataset API v1
- Plugin Progress API v1

The plugin never edits `metadata/datasets.ini` directly.


## v3 metadata propagation

GX-TXT v0.9.1 variable metadata are read from each Analysis Source. Units and semantic roles must be consistent across joined segments. The published `timeseries.table` now carries those metadata through Dataset Publication API v1, so downstream generic plots can use framework display-unit conversion (for example `s -> h` and `A -> mA`). The join still performs no unit rescaling.
