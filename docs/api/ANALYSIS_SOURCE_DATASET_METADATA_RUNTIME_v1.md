# Analysis Source Dataset Metadata Runtime Extension v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.7.57  
**Extends:** Dataset Metadata API v1 and Analysis Source Map API v1, additively

## Purpose

Dataset Metadata API v1 owns the authoritative persistent namespaced metadata
resource for a canonical Dataset. Analysis modules running through
`standard_octave` must not know or open the storage sidecar used by CORE.

This runtime extension provides the bridge:

```text
Dataset Metadata API v1
        ↓
selected Analysis Source
        ↓
standard_octave runtime.ini
        ↓
public Octave CORE API
        ↓
analysis module
```

CORE does not interpret metadata namespaces. `audio.*`, `image.*`,
`experimental.*`, `source.*` and future namespaces are transported as opaque
Dataset Metadata keys and string values.

## Derived runtime contract

For each selected Analysis Source, CORE rereads Dataset Metadata API v1 while
`runtime.ini` is generated. Runtime is derived state; the persistent Dataset
Metadata resource remains authoritative.

Example:

```ini
[analysis_source_dataset_metadata_api]
api_version=1

[analysis_source.primary.dataset_metadata]
api_version=1
dataset_id=audio.recording01
found=1
count=4

[analysis_source.primary.dataset_metadata.1]
key=audio.raw_channels
value=2

[analysis_source.primary.dataset_metadata.2]
key=audio.raw_input_format
value=s16le

[analysis_source.primary.dataset_metadata.3]
key=audio.raw_sample_rate_hz
value=48000

[analysis_source.primary.dataset_metadata.4]
key=source.original_filename
value=test.raw
```

The ordering of indexed entries is not semantic. Consumers must use the exact
`key` string.

### Exact metadata identity

Dataset Metadata keys are deliberately stored as **values** in indexed runtime
entries. They are never converted into INI section names or Octave struct field
names.

This invariant is required because legal keys such as:

```text
collision.a-b
collision.a_b
collision.a.b
```

can become ambiguous if punctuation is normalized to underscores. The public
Octave lookup compares the original key strings exactly.

### UTF-8 and line breaks

Values retain Dataset Metadata API v1 semantics: opaque UTF-8 strings with the
normal GX-TXT INI escaping for embedded line breaks. A value is unescaped by
the shared runtime INI reader before it is returned to a module.

### Missing metadata

A Dataset is not required to own a Dataset Metadata resource. In that normal
case runtime contains:

```ini
[analysis_source.primary.dataset_metadata]
api_version=1
dataset_id=dataset.without.metadata
found=0
count=0
```

This does not fail analysis.

An optional Analysis Source with no selected Dataset also exposes an empty
resource when it is present in the runtime source list.

## Public Octave CORE API

### Read the complete resource

```octave
meta = gxtxt_analysis_source_dataset_metadata(runtime_cfg, 'primary');
```

`runtime_cfg` may be either a parsed `gxtxt_ini_read()` structure or the path
to `runtime.ini`.

The returned structure contains:

```text
meta.api_version
meta.found
meta.source_id
meta.dataset_id
meta.count
meta.keys
meta.values
```

`meta.keys` and `meta.values` are parallel cell arrays. Arbitrary Dataset
Metadata keys are not exposed as struct fields.

### Exact field lookup

```octave
[value, found] = gxtxt_analysis_source_dataset_metadata_get( ...
    runtime_cfg, 'primary', 'audio.raw_sample_rate_hz');
```

`found` is independent of `value`. Therefore a present field whose value is an
empty string is distinguishable from a missing field.

An optional fourth argument supplies the value returned when the key is absent:

```octave
[value, found] = gxtxt_analysis_source_dataset_metadata_get( ...
    runtime_cfg, 'primary', 'audio.title', 'Untitled');
```

The function still returns `found=false` when the default is used.

The same API works for additional and dynamically added Analysis Source IDs:

```octave
meta = gxtxt_analysis_source_dataset_metadata(runtime_cfg, 'uncertainty');
meta = gxtxt_analysis_source_dataset_metadata(runtime_cfg, 'aux_7');
```

## Regeneration and authority

Modules must never edit Dataset Metadata through runtime data. To change
persistent metadata, callers use the public Tcl Dataset Metadata API v1.

On the next normal standard-module runtime generation, CORE rereads that
resource and serializes the current values. Stale runtime data is not an
authoritative cache and is not reused as the source of metadata.

Modules must not open or depend on:

```text
metadata/datasets/*.ini
```

The storage path is intentionally not published in this runtime extension.

## Compatibility

- Analysis Source Map API v1 is unchanged.
- `gxtxt_analysis_source_map_from_runtime()` still returns source IDs mapped to
  canonical runtime paths.
- Analysis Source Metadata Runtime v1 variable metadata is unchanged.
- Analysis Source Access Runtime v2 is unchanged.
- Canonical Dataset APIs and scientific data are unchanged.
- Existing N-source modules receive metadata for every selected source.
- Historical single-source standard modules keep their existing `[dataset]`
  contract and do **not** gain an `[analysis_sources]` section. Their dataset is
  exposed to this metadata API as the compatibility source ID `primary`.
