## 0.2.2

## 0.3.0 — native C development candidate

- Move file reading, differential decoding, trace/peak CSV and bounded worker bulk processing to prebuilt C; retain minimal public Acquisition Handler Tcl adapter.
- Preserve original selected basename independently of renamed RAW, checked source scale/time, exact integer ADCs and optional peak records.
- Use summary metadata for Tcl while native C streams peak files; exclusively create and clean only owned incomplete outputs.
- Record offline source/native parity, sanitizer, adapter and CLI measurements separately from vendor-scientific/canonical/GUI acceptance.

- Version-only update of v0.2.1 optimized importer. No changes to parsing, scientific calculations, API or import behavior.

# Changelog

## 0.2.1
- Decode the RAW CHW once per import callback and produce canonical signal CSV and metadata from that same decode; eliminate duplicate helper subprocess and repeated reads.
- Preserve full 0.2.0 behavior in the default `complete` profile; add `trace_and_peaks` and `trace_only` profiles for less expensive bulk publication.
- Clean up incomplete newly created CSV output on parser failure without touching pre-existing targets.
- Add regression and timing tests; no CORE modifications.


## 0.2.0

- Reverse engineered the CHW T-section differential codec with block run modes
  0/3/4/5 (zero, signed 8/16/32-bit deltas).
- Added exact integer ADC sample reconstruction and physical-signal scaling
  using the native float32 coefficient stored in the S section.
- Acquired and published a full `timeseries.table` Dataset with stable V3
  variable identities and canonical time in seconds/minutes.
- Preserved the original CHW without modification and retained the existing
  integrated-peak Dataset.
- Cross-validated seven 2014 CHW files against paired AIA/ANDI NetCDF and three
  text variants; confirmed 34 peak positions and 10,800 identical ADC integers.
- Added codec mode, bounds, sample-count, overflow, write-safety tests.
- Same external-plugin API and stable ID; no GX-TXT CORE changes.

## 0.1.0

- Initial Metrohm IC Net CHW structural importer; opaque preservation and
  provisional integrated peak metadata without signal decoding.
