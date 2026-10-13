# Generic CSV multi-import — GX-TXT Pipeline v0.8.6

`acq.generic_csv` supports both the historical single-file path and a new multi-CSV batch table.

## Single-file mode

The existing fields remain available and backward compatible:

```text
Acquisition CSV
Canonical dataset ID
Dataset contract / kind
CSV delimiter
Header rows
```

The Channels/Variables page can still be used by the established single-file path to rename/map source columns.

## Multi-CSV batch mode

In the Acquisition tab choose:

```text
Import module = acq.generic_csv
```

The `Multi-CSV canonical dataset import` table appears below the ordinary configuration.

Controls:

```text
Use batch table
+ Add CSV
Add multiple...
Clear
Contract registry...
```

Each enabled row contains:

```text
Use
CSV file
Dataset ID
Contract
Other / custom contract
Delimiter
Header rows
Preview
Variables
```

`Preview` shows the selected file structure and sample rows before import. `Variables` opens the per-dataset variable map, where Original header and Canonical variable are displayed side by side.

The table has vertical and horizontal scrolling and is intended for an arbitrary practical number of input CSV files.

### Add multiple files

`Add multiple...` allows selecting several files in one file-picker operation. GX-TXT creates one editable row per file and proposes a dataset ID from the filename.

Always review the proposed IDs before running the import.

## Contract selection

Known contract IDs are supplied by the Contract Registry and therefore come from the framework plus installed plugin descriptors.

Current framework contracts include:

```text
curve_family.table
raw.csv
table.generic
timeseries.table
```

If the correct contract is not listed, choose:

```text
Other...
```

and type the exact contract in the adjacent field.

The custom value is stored literally in the session manifest and dataset registry.

## Batch canonicalization

By default, batch mode uses the final configured header row as an identity mapping. Before import, each row may define an independent variable map. Canonical aliases are written into the canonical CSV header while RAW sources are preserved unchanged for provenance.

Example:

```text
Original header -> Canonical variable
Vg1_V           -> Vg
Ib_mA           -> Ia
Ig1_mA           -> Ig
```

The resulting layout is conceptually:

```text
session/
  raw/
    <dataset-id>/source.csv
  datasets/
    <dataset-id>.csv
  metadata/
    datasets.ini
    manifest.ini
```

Each dataset receives independent:

- ID;
- contract;
- source SHA-256;
- canonical SHA-256;
- canonical path;
- column list.

## Example

```text
electrical.csv  -> reactor.electrical -> timeseries.table
chemistry.csv   -> reactor.chemistry  -> table.generic
ftir_01.csv     -> ftir.sample01      -> Other... / spectrum.table
```

These datasets can then be consumed independently or jointly by analysis plugins and Scientific Analysis Definitions.

## Manifest persistence

Batch configuration is stored under:

```ini
[generic_csv_batch]
api_version=1
enabled=1
count=...

[generic_csv_batch.1]
...
```

Custom/unknown contract values are preserved even if their original provider plugin is no longer available.


See also `DATASET_INSPECTION_VARIABLE_MAPPING_API_v1.md` for the normative mapping/provenance contract.

## v0.8.7 — adding datasets after the session exists

The primary Import/Run action still creates the session and imports **all enabled** batch rows.

Once `currentSession` exists, the batch bar provides `Import enabled pending into current session`.

Eligibility is strictly:

```text
Use = enabled
AND
Status = Pending
```

The incremental command never calls `makeSession`, never clears `datasets.ini`, and never imports disabled rows. Rows already registered by Dataset ID are shown as `Imported` and are not imported again.
