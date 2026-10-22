# AIA/ANDI Chromatography Importer 1.0.2

**Source/API baseline:** officially deposited GX-TXT 0.9.8.10-dev-109; integration target dev110. The upstream 1.0.0 package targeted dev108. **License:** GNU GPL v3 or later; full license text is included in `LICENSE`. All UI, source comments and documentation are in English. The module does not modify CORE. Version 1.0.2 has source/parser tests, actual public canonical import/rollback/reopen evidence and real-CORE callback checks. Installed GUI and independent vendor-reference acceptance remain pending.

## Purpose

Import instrument-independent AIA/ANDI-CHROM chromatograms (`.cdf`, optionally `.nc`) directly as GX-TXT canonical datasets, **not by requiring users to export CSV first**. The input CDF is classic NetCDF CDF-1 or CDF-2; it is decoded by a small **stdlib-only** Python reader. AIA/ANDI and NetCDF are not exclusive to Metrohm. A file with a `.cdf` extension alone is *not* proof of AIA/ANDI chromatography. The parser checks its actual contents and refuses wrong file types, unsupported units and corrupt files.

### Acquisition flow

Use the normal public Plugin Manager installation workflow and select CDF files through the standard Acquisition source chooser after integration. Actual source-package and ZIP admission have passed for version 1.0.2; installed GUI workflow acceptance remains pending. Batch operations remain governed by the host's existing Acquisition Handler API v1. Per-source inspect returns metadata and a small scientific preview. Files are re-read from the framework-owned RAW snapshot during import; source files are never edited.

**Default: `trace_and_peaks`**

- `<dataset_id>.trace`: canonical `timeseries.table` containing `time_s`, `time_min`, and `signal_value` with original detector unit from the CDF (e.g. `uS/cm`). The importer reads native `ordinate_values` directly, preserving floating point values with 17 significant digits in canonical CSV. This is internal GX-TXT storage and does not require a user-managed intermediate export. Variable Schema v3 holds stable IDs and explicit units.
- `<dataset_id>.peaks`: `chromatography.aia.peaks` (parent `table.generic`) when the source contains peak retention data. The table includes peak index/retention time and *only* optional fields actually available in the source (names, starts/ends, areas, heights, amounts, baseline coordinates). These values are the vendor's precomputed integration, **not** newly integrated results.

**`trace_only`** publishes only `<dataset_id>.trace`. **`complete`** also publishes `<dataset_id>` as an opaque binary `chromatography.aia.raw` Dataset containing a byte-identical CDF copy. In every mode, GX-TXT already preserves the original framework-owned RAW snapshot with source and canonical SHA-256, so the extra binary Dataset is optional to reduce bulk-import overhead. There is no manual Dataset Registry write.

## Timing policy

- If `ordinate_values:uniform_sampling_flag = Y`, use `actual_delay_time + sample_index * actual_sampling_interval` in the declared `retention_unit`. `time_s`/`time_min` are explicit unit conversions. `actual_run_time_length` mismatches generate a warning rather than silently changing the time grid.
- If flag `N`, use the **explicit** strictly increasing `raw_data_retention` values. Never replace a nonuniform grid with an invented fixed interval.
- Unknown/missing `retention_unit`, missing valid uniform interval, missing nonuniform retention grid, unknown sampling flag, nonfinite values or incompatible shapes are rejected instead of inventing defaults. Original AIA numeric values are not smoothed, scaled, integrated or filtered.
- `peak_area` is not assigned a guessed physical unit: different exporting CDS products express it differently. `peak_amount` uses `peak_amount_unit` only if declared.

## Compatibility and scope

- Supported: ASTM E1947-style **chromatographic** AIA/ANDI NetCDF Classic CDF-1 and CDF-2 containers; 1-D `ordinate_values`; uniform and explicit nonuniform retention axes; optional peak tables; IEEE 32- and 64-bit numeric fields, classic fixed and record arrays. Python 3 is the only runtime dependency.
- Explicitly unsupported: ANDI-MS mass-spectral scan files, CDF-5, NetCDF-4/HDF5, multichannel arrays inside one `ordinate_values` variable and vendor-specific nested container formats. Handling a third-party vendor's AIA/ANDI-CHROM export is structurally possible but **not certified without a representative test file**.
- The helper caps total input file size at 512 MiB and metadata fields at 1 MiB. All scientific payload writing stays inside the output directory chosen by GX-TXT. No data is sent to any network service.

## Validation evidence

The upstream 1.0.0 package reported comparisons of seven paired Metrohm IC Net 2.3 AIA exports against SciPy and corresponding CHW measurements. Those private CDF fixtures are not included and were not available in the current task audit. **These are retained historical assertions, not new version 1.0.2 validation results.** See `VALIDATION.md` and `SOURCE_PROVENANCE.json`.

For version 1.0.2, the actual staged module unittest suite ran 13 tests: 12 passed, one optional real-source case skipped. This includes CDF-1/CDF-2 regressions for finite uniform time rounding and nonuniform time-unit conversion collapse, with negative increasing axes preserved. No clamping or resampling is performed. The following separate fixture and callback results apply to the retained 1.0.1 source baseline: Six independently generated and qualified CDF-1/CDF-2 fixed/record fixtures retained exact signals and axes; two malformed fixtures were rejected. Separate staged Tcl callback checks used the real released dev109 CORE Python-tool discovery, with no CORE stub, and verified inspect/import/datasetPreview, profile descriptor counts, schema, units, values and RAW hashes. These are synthetic source/callback checks, with no canonical Dataset registration or GUI. The bundled `tests/check_acquisition.tcl` now uses actual CORE runtime discovery with isolated RAID roots and checks valid profiles plus clean precision-error diagnostics, without substituting CORE commands.

Separate real public API verification admitted the package, imported qualified CDF-1/CDF-2 into a registered-generator Session, checked canonical schema/units/values and source/payload hashes, and passed persistence plus fresh-process reopening. A focused1.0.2 rerun rejected both precision-collapse files without changing26 existing public Dataset records or payload hashes. The final adapter changes only failure-message presentation and was checked through actual callbacks after that canonical run. Normal installed GUI acceptance and the unavailable independent vendor comparison remain pending.

Run tests from the plugin directory:

```bash
python3 -m unittest discover -s tests -v
ANDI_FIXTURE_DIR=/path/to/cdf/examples python3 -m unittest discover -s tests -v
```

For a direct inspection:

```bash
python3 runtime/andi_chromatography.py --mode inspect --input example.cdf
```

The helper output is an internal base64-escaped line protocol read only by `runtime/acquisition_handler.tcl`; it is not intended as a user-facing format.

## Scientific limitations

The importer preserves *reported* integrated peaks; it does not recompute baseline correction, quantitation, response factors or peak identities. Chromatography/IC techniques depend on calibration, detector and method; no analyte identity is inferred from retention time alone. The dataset retains acquisition metadata and provenance to support independently documented follow-on analysis.
