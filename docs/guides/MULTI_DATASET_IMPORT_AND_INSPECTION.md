# Multi-dataset import and inspection

This guide describes the recommended v0.8.6 workflow when an analysis uses many CSV files.

## 1. Add CSV files

In `Acquisition`, select `acq.generic_csv`, enable `Use batch table`, then use `+ Add CSV` or `Add multiple...`.

Assign each enabled row:

- a stable Dataset ID;
- the appropriate contract;
- delimiter (`auto` is normally appropriate);
- number of header rows.

## 2. Inspect before import

Do not guess variable names.

For each batch row use:

- `Preview` to inspect detected structure and sampled data;
- `Variables` to compare source headers and canonical names.

For example:

```text
Dataset ID: 2d21-cal7
Original header -> Canonical variable
Vg1_V           -> Vg
Ib_mA           -> Ia
Ig1_mA           -> Ig
```

A second dataset can have a completely independent map:

```text
Dataset ID: uncertainty_profile
Original header -> Canonical variable
Vg1_V           -> Vg
Ib_mA           -> Ia
sigma_total     -> sigma_total
```

## 3. Import

Run the acquisition/import. Every enabled batch row becomes one canonical dataset in the new session.

The canonical CSV contains the configured canonical variable names. RAW files are copied for provenance and remain unchanged.

## 4. Verify after import

Open `CSV Preview` or `Variables` and choose `Imported: <dataset-id>`.

Verify:

- contract;
- canonical file;
- variables;
- original-to-canonical mapping;
- units and semantic roles;
- RAW provenance.

You should not need to open the original CSV manually to discover its headers.

## 5. Use in an analysis module

With Analysis Source Map API v1, map datasets to source IDs, for example:

```text
primary      -> 2d21-cal7
uncertainty  -> uncertainty_profile
```

Bindings can then use qualified names:

```text
x=primary.Vg
y=primary.Ig
family=primary.Ia
sigma_y=uncertainty.sigma_total
```

No automatic join, interpolation or resampling occurs at source selection time.

## v0.8.7 — Pending versus Imported

A batch row is `Imported` when its Dataset ID already exists in the Dataset Registry of the current session; otherwise it is `Pending`.

After the first session-creating import, additional CSV rows may be added normally. Enable only the rows that should enter the existing session and use `Import enabled pending into current session`. Disabled rows remain Pending and available for Preview/Variables inspection.

Preview and Variables selectors no longer list one Dataset ID simultaneously as both Pending and Imported.
