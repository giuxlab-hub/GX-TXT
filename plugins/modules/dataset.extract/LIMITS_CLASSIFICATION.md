# dataset.extract 1.3.0 — Remaining-limit classification

SPDX-License-Identifier: GPL-3.0-or-later

This document classifies the limits carried forward from 1.1.0 without reopening the module architecture.

| Topic | Classification | 1.3.0 decision |
|---|---|---|
| Dataset Variable Schema preservation for pure subset/projection publication | Existing API sufficient in GX-TXT 0.9.7.19 | Resolved. Use Dataset Publication API v1 `schema_source_dataset_id` plus ordered `schema_source_variable_ids`. CORE assigns fresh derived IDs and inherits interpretation metadata. |
| Normal / one-row / zero-row schema fidelity | Existing API sufficient in GX-TXT 0.9.7.19 | Resolved for the fields implemented by publication schema inheritance. Preservation no longer depends on value inference. |
| One canonical source per run | Deliberate scientific boundary | Keep one source. No cross-dataset reuse of selection bounds, join, or alignment is implied. |
| Selection types | Existing API already sufficient | Consume the types defined by Dataset Selection API v1. Current API v1 defines `x_range` and `rectangle`; membership remains delegated to `gxtxt_selection_mask()`. |
| Source read-only behavior | Module responsibility | Enforced by design and covered by source SHA-256 regression in the real-runtime test. |
| Row order | Module responsibility | Preserved exactly; no sorting step exists. |
| Output variable projection | Module responsibility | `all` means active canonical source columns; `trace` means selected canonical X/Y variables. X == Y is emitted once. |
| Source Use=no variables | Deliberate canonical-dataset boundary | Use=no variables are not active physical columns in the canonical table and are not materialized. |
| Reusing an existing output Dataset ID owned by dataset.extract | Existing Dataset Publication API behavior | GX-TXT 0.9.7.19 still permits owner republish. Version 1.3.0 does not add a private create-only workaround. |
| Conditional GUI disable/hide | Genuine Standard Module UI limitation, presentation-only | Unchanged and unrelated to schema inheritance. The descriptor remains static and host-independent. |

## Scientific boundary

The module remains exactly:

```text
source canonical dataset
-> row filtering
-> column projection
-> new canonical derived dataset
```

It does not interpolate, resample, align, sort, join, average, build consensus data, convert units, or generate synthetic points.
