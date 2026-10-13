# GX-TXT Analysis Source Metadata Runtime Extension v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.1  
**Extends:** Analysis Source Map API v1, additively

## Purpose

The Dataset Registry already stores variable-level metadata. v0.9.1 transports that metadata into a module runtime so analysis code and generic renderers do not infer scientific units or roles from column names.

## Runtime

The existing source section remains valid and is enriched:

```ini
[analysis_source.primary]
dataset_id=reactor.electrical
path=/runtime/path/electrical.csv
kind=timeseries.table
columns=time_s,current_A
variables=time_s;current_A
units=s;A
semantic_roles=independent;measured
variable_count=2
```

The authoritative variable metadata are independent sections, avoiding reliance on parallel-list alignment:

```ini
[analysis_source.primary.variable.1]
name=time_s
unit=s
semantic_role=independent
original_header=Time
source_column=1

[analysis_source.primary.variable.2]
name=current_A
unit=A
semantic_role=measured
original_header=Current
source_column=2
```

The summary lists are convenience fields only.

## Analysis behavior

For a Scientific Analysis Definition variable:

```ini
[variable.current]
binding=current
```

if `unit=` or `role=` is blank, `gxtxt_analysis_run()` inherits them from the resolved `source.variable` metadata. Explicit definition metadata always wins.

Public lookup helper:

```octave
[unit,role,meta] = gxtxt_analysis_source_variable_meta(runtime_cfg,'primary','current_A');
```

The existing path-only helper remains backward-compatible:

```octave
source_map = gxtxt_analysis_source_map_from_runtime(runtime_cfg);
```

Its return type is unchanged.

## Plot use

With metadata propagated, generic plots may request `auto_units=1` and scale only the presentation layer, e.g. seconds to minutes or amperes to milliamperes, without parsing names such as `time_s` or `current_A`.

## v0.9.3.3 additive helper metadata

`gxtxt_analysis_source_variable_meta()` now returns two additional fields in `meta`:

```text
meta.source_id
meta.dataset_id
```

Together with the existing canonical `name`, `unit`, `semantic_role`, `original_header`, and `source_column`, this is sufficient for generic X, Y-left, Y-right, Z, Group/Family and C bindings. The framework does not infer units or roles from suffixes such as `_s` or `_A`.

## v0.9.5 dataset representation metadata

Each selected Analysis Source now also carries the canonical dataset representation metadata:

```ini
[analysis_source.primary]
contract=image.raster
format=tiff
storage_kind=binary
media_type=image/tiff
```

Existing runtimes remain compatible; `storage_kind` defaults to `text` when absent and `media_type` may be empty. This transport is host-independent and allows future modules to consume binary datasets without depending on Tcl/Tk.

## Current variable-ID use

Dataset Variable Schema API v2 adds variable_id, semantic_source/reason and typed parser/temporal fields to the variable runtime sections. gxtxt_analysis_source_variable_meta accepts a stable variable ID first, with name lookup for legacy runtimes. The runtime deliberately exposes the metadata needed by Octave consumers; canonical_unit, display_label and the complete editable schema remain available through the public Tcl Dataset Variable Schema API. See the tested [Variables Guide](../guides/VARIABLES_GUIDE.md).

## Dataset Metadata is a separate runtime resource (GX-TXT 0.9.7.57)

This API continues to describe Dataset representation and **variable-level**
metadata. Arbitrary Dataset-level structured metadata is intentionally separate
and is exposed by
[Analysis Source Dataset Metadata Runtime Extension v1](ANALYSIS_SOURCE_DATASET_METADATA_RUNTIME_v1.md).

Do not place arbitrary Dataset Metadata keys in variable sections or infer them
from variable names.
