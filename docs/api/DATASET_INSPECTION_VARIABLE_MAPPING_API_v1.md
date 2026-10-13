# Dataset Inspection / Variable Mapping API v1

GX-TXT Pipeline v0.8.6 introduces a framework-owned API for inspecting and mapping variables in sessions that contain one or many canonical datasets.

The purpose is to make multi-dataset work understandable from the GUI without opening CSV files manually or reading framework source code.

## Guarantees

- RAW input files are never renamed or rewritten.
- Every dataset has an explicit Dataset ID and contract.
- The GUI can inspect pending batch imports and already imported canonical datasets.
- Original CSV header and canonical variable name are shown side by side.
- Per-dataset aliases, units and semantic roles are stored as dataset provenance.
- Canonical aliases are applied during canonicalization, so downstream modules see the canonical names in the canonical CSV itself.
- Existing single-file import remains compatible.
- Analysis Source Map API v1 continues to consume canonical variable names; no join, interpolation or resampling is performed by this API.

## Multi-CSV row actions

Each row in `acq.generic_csv` batch mode exposes:

- `Preview`: opens CSV Preview focused on that pending dataset.
- `Variables`: opens the Variables workspace focused on that pending dataset.

The batch table remains vertically and horizontally scrollable.

## CSV Preview

CSV Preview has a dataset selector. Choices may include:

- `Single-file input`
- `Pending: <dataset-id>`
- `Imported: <dataset-id>`

The preview reports:

- dataset state (`SINGLE`, `PENDING`, `IMPORTED`);
- Dataset ID;
- contract;
- file path;
- file size;
- delimiter and whether it was auto-detected;
- header-row count;
- detected column count;
- sampled data-row count;
- original-header to canonical-variable mapping;
- unit and semantic role where available;
- simple field-count consistency diagnostics;
- sampled data rows.

Imported datasets additionally expose stored provenance such as RAW source and canonical checksum when available.

## Variables workspace

The Variables tab is dataset-aware. Select the dataset from the `Dataset:` chooser.

Columns are intentionally ordered so the two names can be compared directly:

```text
Use | CSV col | Original header | Canonical variable | Unit | Semantic role | Instrument | Instrument channel
```

### Pending dataset

For a pending multi-CSV row, `Canonical variable`, `Unit`, `Semantic role`, and instrument metadata can be edited before import.

Example:

```text
Original header   Canonical variable
Vg1_V             Vg
Ib_mA             Ia
Ig1_mA             Ig
```

The canonicalized CSV will then contain:

```text
Vg,Ia,Ig
```

while the RAW file remains unchanged.

### Imported dataset

In API v1, an imported mapping was read-only and a change required re-import. Since GX-TXT 0.9.7.3, Dataset Variable Schema API v2 keeps RAW provenance read-only and makes canonical schema editable in place; see `DATASET_VARIABLE_SCHEMA_API_v2.md`.

### Single-file import

The historical single-file variable mapping remains supported and uses the same Original-header / Canonical-variable semantics.

## Registry metadata

Dataset registry entries may contain:

```ini
variables=Vg,Ia,Ig
var_count=3
var1_enabled=1
var1_source_column=1
var1_original_header=Vg1_V
var1_canonical=Vg
var1_unit=V
var1_semantic_role=independent
```

and analogous `varN_*` fields for additional variables.

The loader remains tolerant of older registries that contain only `columns=`. For those datasets the GUI treats the existing canonical column names as both original and canonical when no richer provenance exists.

## Relation to Analysis Source Map API v1

This API answers:

> What variables exist in each dataset, and what are their canonical names?

Analysis Source Map API v1 answers:

> Which datasets participate in this module run, and under which Source IDs?

A binding such as:

```text
sigma_y=uncertainty.sigma_total
```

therefore references `sigma_total` as the canonical variable exposed by the dataset mapped to source `uncertainty`.

This API never aligns datasets. Alignment remains an explicit Scientific Analysis operation.

## v0.8.7 incremental import state

The API distinguishes batch-row UI state from canonical Dataset Registry state:

- `Pending`: the configured Dataset ID is not registered in the current session;
- `Imported`: the Dataset ID is registered in the current session.

Incremental import into an existing session selects only rows that are both enabled and Pending. Dataset identity is determined by the canonical Dataset ID; existing IDs are not silently overwritten.

## dev089 Acquisition browser and pending review

The Acquisition page uses a right-side tree populated from installed acquisition
Module group/name/ID metadata and existing Importer Builder definitions. General
Builder, Contracts and Refresh actions sit above the tree. Selected importer
configuration and queue callbacks remain provider-dispatched. Queue cards retain
the existing widget paths, bindings, publication and successful-row pruning.
Preview and Variables select the corresponding existing Dataset notebook view.
Search/collapse/selection are transient; no new importer engine or Dataset state
is introduced. Changing importer clears its pending queue, as before.
