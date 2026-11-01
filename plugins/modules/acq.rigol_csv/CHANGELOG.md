## 2.3.1 — DEV111-P031

- Add a genuine illustrated HTML Rigol import tutorial through the existing
  Documentation Browser; retain the technical Markdown reference and actual API
  navigation. Native importer context actions reuse current selection.
- Documentation/descriptor-only module update; parser source/binary, full float64
  canonical publication, exact RAW preservation and Group semantics unchanged.

# Changelog

## 2.0.0 — 2026-09-29

- Route Rigol import through its Acquisition Handler Plugin API callback.
- Preview configured headers and a bounded data sample, with channel names,
  units, timing metadata and trailing-field structure from the actual source.
- Keep the established streaming Octave worker and canonical time-series
  Dataset output. The inspector reads descriptor configuration from the public
  callback request and worker count from Configuration API v1.
- Package the module through Plugin Install API v1 for GX-TXT 0.9.8.10-dev.
# 2.1.0

- Prefer actual CORE HDF5 for large numeric imports, preserving float64 samples,
  typed stable variables and exact RAW/canonical hashes.
- Add bounded native CSV parsing after measured Octave parser hotspot, with
  retained Octave/HDF5 and round-trip-precision CSV alternatives.
- Publish selected independent channels as one persistent Dataset Group through
  the existing Acquisition/Dataset transaction; record source-grounded metadata.

## 2.2.0 — 2026-10-28

- Use the existing managed request owner for normal GUI import. Show bounded
  parser progress, per-channel binary publication and a visible Cancel import.
- Keep all selected channels in the same Dataset transaction. Cancellation
  drains the owned process group before existing journal recovery, preserving
  prior canonical data and original RAW. A committed receipt wins late cancel.
- Preserve synchronous six/seven-argument import APIs and unchanged numeric
  parser source/binary. No new Job, Registry or scientific storage writer.

## 2.3.0 — 2026-10-28

- Explicitly admit the generated numeric transport as consumable after CORE
  validates it. CORE removes a buffer after its final successful consumer,
  retaining shared time arrays until every selected channel has used them.
- Preserve source RAW, canonical float64 values, Group atomicity and recovery.
- Keep the measured lower-memory serial provider path for normal import.
  Existing public managed-write concurrency is available for explicit consumers;
  a configured worker count does not promise parallel CSV parsing.

- Reuse one managed Group workspace with contained channel scopes and verified
  post-cancel resource cleanup, reducing allocation/release/cleanup calls 4→1.
- Retain explicit self-contained canonical time axes and selected serial defaults.
  Same-configuration shared collector import 17.389489→16.012613s; whole-architecture
  control 34.340439→28.021367s, full float64 identity preserved and storage noise
  disclosed in the scoped performance report.
