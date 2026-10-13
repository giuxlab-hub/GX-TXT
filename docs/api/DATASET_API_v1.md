# Canonical Dataset API v1

GPL-3.0-or-later

Each session stores dataset metadata in:

```text
metadata/datasets.ini
```

A dataset record contains at least an ID, contract/kind, format, path, source module and integrity metadata where available.

## Canonical variables

CSV columns are represented by canonical variables. For generic CSV import the default is:

```text
original CSV header -> canonical variable with the same name
```

The user may change the canonical name and add:

- unit;
- semantic role;
- source column;
- source instrument channel;
- instrument ID;
- instrument channel/terminal.

The RAW input is never modified. `acq.generic_csv` writes a canonical CSV under `datasets/` using the enabled variable map and canonical names. This prevents an alias from being only cosmetic: the analysis runtime sees the canonical column name that is actually present in the dataset.

Example:

```text
CSV C1 header: Voltage
canonical:      Va_V
unit:           V
role:           independent
instrument:     scope_lab
channel:        CH1
```

## Separation from modules

Dataset metadata does not encode knowledge of Curve Family Fitting, IR analysis or any other consumer. Analysis modules bind their required roles to canonical variables independently.

## Structured Dataset metadata

Dataset Metadata API v1 associates one persistent namespaced key/value sidecar
with a canonical Dataset ID. It is independent from Variable Schema and
Dataset Notes, preserves fields unknown to CORE, and is deleted with its
Dataset. See DATASET_METADATA_API_v1.md.

## Session deletion

CORE exposes one dataset-scoped lifecycle operation:

    set result [::GX::datasetDelete $session $datasetId]

The operation removes the Dataset ID and all of its registry metadata from the
current session. It deletes the authoritative storage object only when its path
is a regular file strictly below the session datasets/ directory and no other
registered dataset uses that path. It also removes the dataset note when the
note is stored below notes/datasets/.

RAW/source files are never deletion targets, including source paths inside the
session raw/ directory or absolute paths outside the session. Analysis
outputs, selections, graph configuration and other provider resources are not
generically cascade-deleted. CORE Graph Series that directly reference the deleted
Dataset ID are pruned immediately; provider-owned sidecars remain the provider's
responsibility and may reconcile their stale references through their public lifecycle.

The returned dictionary contains dataset_id, registry_removed,
canonical_storage_deleted, note_deleted, metadata_deleted and cleanup_errors.

## v0.8.8: publishing module-produced datasets

Analysis modules must not edit `metadata/datasets.ini` directly. Dataset Publication API v1 provides the framework-owned route for registering reusable files produced by modules, including contract, format, variables, units, semantic roles, provenance and authoritative SHA-256. See `DATASET_PUBLICATION_API_v1.md`.

## v0.9.5 representation metadata

Canonical datasets may contain `storage_kind=text|binary` and optional `media_type=<MIME>`. These fields describe how the canonical dataset is stored; they do not replace or redefine the scientific dataset contract. See `BINARY_DATASET_FOUNDATION_v1.md`.

## v0.9.7.3 variable schema extension

Dataset Variable Schema API v2 adds stable variable IDs, editable post-import schema and typed-value metadata while retaining this registry and existing Dataset IDs. See `DATASET_VARIABLE_SCHEMA_API_v2.md`.

### Dataset deletion and Graph Series references (0.9.7.42)

Deleting a registered dataset also prunes CORE Graph Series records that directly reference that dataset. This prevents stale dataset IDs from making plot editors/runtimes unusable. Providers remain responsible for reconciling any provider-owned sidecar presentation state; `plot.dataset` 3.3.1 performs that reconciliation lazily and removes dead artifacts when no valid series remain. Surviving Graph Series are never rebound to another dataset automatically.
