# Changelog

## 1.1.0 — 2026-10-28

- Declare a CORE `chromatography.measurement` Dataset Group containing exactly
  the outputs selected by the profile. Trace is primary; original exporter peaks
  and byte-identical source container remain optional. Parser and numerical
  semantics are unchanged; CORE owns atomic group/source/namespace persistence.

## 1.0.2 — 2026-10-22

- Reject finite retention-time grids that lose strict ordering through floating-point rounding or time-unit conversion, without clamping or resampling.
- Use the same checked time iterator for inspection and import; retain negative increasing coordinates and all representable source values unchanged.
- Add CDF-1/CDF-2 regressions for large-delay uniform collapse and subnormal millisecond conversion collapse, with negative-axis positive controls.
- Present the parser's error reason without partial internal metadata protocol; verify callbacks using the actual framework runtime discovery rather than a substituted CORE command.

## 1.0.1 — 2026-10-22

- Reject computed retention-time coordinates that overflow to nonfinite values, during both inspection and import.
- Reject nonempty CDF variable payloads whose declared start overlaps the parsed file header.
- Add targeted CDF-1/CDF-2 regression fixtures for these malformed inputs; preserve the existing format scope, profiles, numerical values and public Acquisition Handler API v1 pathway.

## 1.0.0 — 2026-10-21

- First GX-TXT AIA/ANDI-CHROM standard NetCDF importer.
- Stdlib-only CDF-1 and CDF-2 reader with byte-bounds checks, typed data and optional record variables.
- Direct scientific signal/time acquisition with explicit detector/time units; uniform and nonuniform grids.
- Optional vendor integration peak table and optional byte-identical binary Dataset.
- Per-source preview, warnings and metadata; batch lifecycle through public GX-TXT Acquisition Handler API v1.
- Reproducible standalone decoder and Tcl callback tests; no CORE modifications.
