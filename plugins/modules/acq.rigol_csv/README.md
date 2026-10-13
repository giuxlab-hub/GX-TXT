# acq.rigol_csv

Standard Module API v1 acquisition/import plugin for supported Rigol oscilloscope and sequence CSV exports. It preserves the RAW source and produces canonical time-series datasets through the streaming Octave worker.

## Acquisition workflow

The acquisition module now uses its Acquisition Handler Plugin API v1 runtime instead of the legacy `rigol_csv` handler ID. This makes pending-file preview and variable discovery use the module's own inspector.

The inspector is intentionally lightweight and reads only the configured header plus a small sample. Large oscilloscope CSV exports are therefore previewed without loading or scanning the complete acquisition.

For native Rigol DS1000Z-style exports, channel names are taken from the first header row, units and timing values from the second row, and `Start` / `Increment` remain metadata rather than signal columns. The preview returns detected channels, timing metadata, field structure and sample rows.

See also `docs/guides/RIGOL_NATIVE_IMPORT.md`, `docs/api/DATASET_API_v1.md`, and `docs/api/MODULE_API_v1.md` in the GX-TXT framework sources.

Install `acq.rigol_csv_2.0.0.zip` through Plugin Install API v1. See
`MANUAL.md` for the current workflow and `CHANGELOG.md` for the change scope.
