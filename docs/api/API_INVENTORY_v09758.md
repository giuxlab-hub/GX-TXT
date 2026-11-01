# GX-TXT API Inventory — v0.9.7.58 delta

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.58 is an additive CORE release. Existing API versions remain unchanged.

## New public API

| API | Version | Implementation | Purpose |
|---|---:|---|---|
| Temporal Set API | 1 | `core/tcl/temporal_set_api_v1.tcl` | Persistent reusable Temporal Segment Sets and compact regular Temporal Window Sets over canonical time-series Datasets. |
| Temporal Set standard_octave binding | 1 | `core/octave/analysis/gxtxt_temporal_set_from_runtime.m`, `gxtxt_temporal_set_member.m` | Read a selected Temporal Set from normal module runtime and resolve one member without opening CORE persistence files. |

## Descriptor extension

Standard Module configuration accepts the additive `type=temporal_set` selector with `source_role` and `temporal_types` filtering. Existing descriptor types are unchanged.

## Existing APIs reused without version changes

- Dataset Selection API v1: optional parent `x_range` resource.
- Dataset Variable Schema API v3: stable temporal variable identity and uniform-axis metadata.
- Canonical Dataset API v2: bounded temporal-coordinate reads where explicit-axis mapping is required.
- Unit/Dimension infrastructure: compatible duration-unit conversion.
- Analysis Source and Standard Module runtime generation: transport host for selected Temporal Sets.

No public FFT, spectrogram, Table Stream, Dataset Metadata, plot, or elapsed-time conversion API changed in 0.9.7.58.
