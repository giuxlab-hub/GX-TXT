# Validation and limitations — AIA/ANDI-CHROM 1.0.2

Status: current1.0.2 source/parser and focused real public canonical import/rollback/save-reopen checks passed. Earlier1.0.1 evidence is retained separately. Final failure-message formatting was retested through actual callbacks. Installed GUI and independent vendor comparison remain unverified. No original scientific Session or source file was changed.

## Current TASK210 evidence

### Version 1.0.2 finite-axis followup

The actual staged 1.0.2 suite ran on 2026-10-22: **13 cases, 12 PASS, 1 optional vendor SKIP**. Only the new regressions and existing full unit suite were run for this followup; no broad campaign was repeated.

Two finite-coordinate failures were first reproduced against the retained 1.0.1 runtime. A uniform grid with delay `1e16 s` and interval `1 s` became `[1e16, 1e16, 1.0000000000000002e16] s`. An explicitly increasing subnormal millisecond grid `[5e-324, 1e-323, 1.5e-323] ms` became `[0, 0, 0] s`. Both were previously accepted by direct calls and CLI inspection/import; source fixtures, emitted CSV and receipts are retained separately.

Version 1.0.2 rejects computed seconds that are not strictly increasing and uses the same checked iterator for preview and import. It does not clamp, shift or resample data. The two new test methods cover CDF-1/CDF-2 and require clear CLI rejection without output payloads. Positive controls explicitly retain uniform `[-2, -1, 0] s` and nonuniform `[-.002, -.0005, 0] s` grids unchanged, including their declared units. Existing normal trace/peak, nonuniform, finite-value, corrupt-file and overflow regressions also pass. The optional vendor case remains skipped because its private CDF files are unavailable.

### Version 1.0.1 source and callback evidence retained

The earlier actual staged 1.0.1 module unittest suite ran on 2026-10-22 with bytecode disabled and temporary fixtures confined to owned RAID scratch: **11 cases, 10 PASS, 1 SKIP**. The skipped case requires `ANDI_FIXTURE_DIR` and makes no vendor comparison claim. Cases cover CDF-1/CDF-2, explicit nonuniform sampling, unsupported/missing time units/axes, malformed/HDF input, nonfinite ordinates, CSV trace/peak output, computed-time overflow rejection and header-overlapping payload rejection. Both new regression methods cover CDF-1 and CDF-2; their CLI checks reject invalid inputs without creating trace/peak payloads.

Focused checks of the then-staged 1.0.1 runtime also passed **8/8 fixtures**: independently qualified fixed CDF-1/CDF-2, float32 record CDF-1/CDF-2, packed-single-record int16 CDF-1/CDF-2, plus the two malformed sources. The six valid cases preserved exactly `[2, 3, 4]` ordinates and `[0, 1, 2]` seconds against independent SciPy readback. The original source, reviewed 1.0.1 proposal and then-staged runtime SHA continuity is recorded in `SOURCE_PROVENANCE.json`.

A separate 1.0.1 staged Tcl review sourced the actual released dev109 framework through its source-safe entry point, with private XDG and installation-identity roots. The real `::GX::runtimeToolRequired python` resolved `/usr/bin/python3`; it was not replaced by a stub. The exact upstream Tcl adapter was pointed only at the exact proposed reader review artifact. Eight callback scenarios and ten numeric/hash postchecks passed:

- With synthetic vendor-like peak fields, profile descriptor counts were `trace_only=1`, `trace_and_peaks=2`, `complete=3`.
- Without peaks, counts were `1`, `1`, `2` respectively.
- Inspect/import/datasetPreview, stable variable IDs, explicit coordinate relationships, units, original peak fields and complete RAW byte hashes were checked.
- Overflow and header-overlap inputs returned clear inspect, import and Dataset-preview diagnostics.

These checks invoked callbacks directly. They did not register a module, create a Session, validate the framework's canonical transaction/rollback, persist Dataset schema, or load a GUI. The bundled callback check now sources actual CORE/runtime discovery and tests three valid profiles plus two precision-error diagnostics in isolated RAID roots; it substitutes no CORE command. Scratch evidence locations and hashes are in the provenance manifest; they are evidence references, not runtime dependencies.

## Preserved upstream assertions — not re-executed

The unmodified 1.0.0 source ZIP asserted tests on seven user-provided Metrohm IC Net 2.3 CDF-1 exports and matching CHW records: 75,600 ordinates, 34 reported integration peaks, exact Python-float agreement with SciPy on the float32 ordinates, and CHW/CDF maximum differences below 1.91e-6 µS/cm. Its original per-file table and validation text remain preserved in the original ZIP (SHA256 in `SOURCE_PROVENANCE.json`). Those private CDF comparison files are not distributed here and were not available for the current source audit. This release does not promote those assertions into current validation results.

The earlier scratch probe attempt used a SciPy record fixture with zero-rank timing scalars whose written data did not match its intended values. It was rejected as a fixture-construction issue, retained separately, and replaced by independently qualified fixtures. No importer record-decoding defect or vendor result is claimed from that attempt.

## Unsupported and pending

Supported source scope remains classic CDF-1/CDF-2, one numeric ordinate vector, declared uniform or explicit nonuniform retention grid and optional original peak fields. The fixes reject malformed coordinates/offsets; they do not clamp values, change units, resample traces or recompute vendor integration.

CDF-5, NetCDF-4/HDF5, ANDI-MS, multidimensional/multichannel ordinate arrays and unknown vendor-specific containers remain unsupported. Other CDS vendors' exports are not certified. The reader retains its 512 MiB input limit and 1 MiB metadata-field limit.

Real developer canonical evidence is separate from the source tests above. SUB3 public-importers-003 admitted both module trees through pluginPackageOpen/Close and checked23 imported objects across180 create and179 fresh-process reopen checks, including the two qualified AIA fixtures alongside seven CHW originals. Its AIA Python-worker hash was not explicitly pinned; the source was held stable, and that omission is preserved. The focused public-aia102-001 run pins the actual1.0.2 worker, adapter and descriptors. It imports both valid CDF variants, checks public schema/units/values and Session persistence/reopen, and rejects both precision-collapse fixtures with26 existing public records and payload hashes unchanged around each rejection (24 create checks,17 reopen checks). The final adapter catch-only formatting change removes partial internal protocol from the displayed reason; its three valid profiles and two negative callbacks pass after that run. Exact versioned receipts are referenced in SOURCE_PROVENANCE.json.

Pending work: normal installed package enablement, Acquisition GUI behavior and complete-profile/optional-peak cases through that GUI, duplicate-ID and GUI batch-row handling, independent vendor comparison if approved CDF references become available. MAIN alone schedules installed GUI validation and integration. These developer API results are not GUI or vendor scientific acceptance.
