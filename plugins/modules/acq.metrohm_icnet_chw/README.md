# Metrohm IC Net CHW importer — native C candidate 0.3.0

GPL-3.0-or-later. Acquisition Handler Plugin API v1. Development target: dev110;
public contracts rebaselined against the officially deposited dev109. This source
candidate has decoder, callback and real public canonical registration/save-reopen
evidence. Normal installed Acquisition GUI acceptance remains pending.

The importer reads supported Metrohm IC Net binary CHW records directly. A
prebuilt C worker performs checked file reading, differential/run-length decoding,
trace/peak CSV writing and bounded native bulk processing. The minimal Tcl adapter
returns staged Dataset descriptors to the existing public Acquisition Handler.
CORE owns source snapshots/hashes, validation, Dataset registration, metadata,
transactions and Session persistence. No worker output by itself is a registered
Dataset. Opening/importing never invokes a compiler, linker or Python parser.

## Normal use and profiles

Install the complete matching package through the existing Plugin Manager, enable
the Acquisition module, select a source, inspect its metadata and use the normal
Acquisition import operation. Choose distinct Dataset IDs for related files and
keep them in the same appropriate experiment/Session. CORE retains each source
identity; the importer does not merge seven acquisitions into one trace.

`output_profile` defaults to `complete`:

- `complete`: `<id>` original CHW binary Dataset, `<id>.trace`, and optional
  `<id>.peaks` when valid integration records exist.
- `trace_and_peaks`: trace plus optional peak table.
- `trace_only`: trace only.

CORE retains its RAW snapshot and provenance in every profile, including when
no additional opaque CHW Dataset is requested. All canonical output files are
internal storage, with registration performed only by CORE.

## Scientific interpretation

The trace contract is `timeseries.table`, with stable variables `time_s`,
`time_min`, `signal_value` and signed int32 `adc_count`. The time grid starts at
sample index zero and uses the source S-section binary32 interval. Signal values
are original signed ADC integers multiplied by the source binary32 ADC step.
Both source floats are promoted to double; CSV uses the established 15-digit
format. Source channel/unit labels are preserved, not inferred from filenames.
The supplied originals declare `uS/cm`; that observation is not a universal CHW
unit assumption. No interpolation, resampling, smoothing or baseline correction
is applied.

The validated structural scope requires an S descriptor of 72 bytes, positive
finite scale, interval between 0 and 3,600 seconds and at most 2,000,000 samples.
T runs support zero differences and signed little-endian int8/int16/int32 deltas.
Offsets, section overlap, exact T consumption, sample/run counts and int32
cumulative range are checked. Input must be a regular file no larger than 128 MiB.
Unsupported/truncated/malformed variants fail explicitly.

Optional `chromatography.icnet.peaks` specializes `table.generic`. Columns retain
peak number, start/apex/end sample indices, index-derived approximate retention
in minutes and optional original U-log component labels. Invalid later peak
bounds discard the entire peak table with a warning, preserving the trace.
Unknown peak-record layouts do not produce invented peaks. These are original
integration records; this importer does not integrate peaks or identify analytes.
CP1252 source text converts explicitly to UTF8, including replacement for undefined
bytes. Absent labels remain empty. Embedded NUL in a source label is preserved
with explicit byte lengths. Local sample time and optional filename date remain
separate textual evidence; no timezone or absolute acquisition date is inferred.

## Platform and runtime

The supplied precompiled worker is Linux x86_64. Its observed ELF requirements are libc
with GLIBC symbols up to 2.34; development host used GCC 14.2 and glibc 2.41. No other
platform binary is claimed. A missing/nonexecutable/incompatible worker produces
an actionable error. Worker files must arrive prebuilt in the complete package.

The native hot path streams 4,096 ADC samples at a time rather than allocating a
full trace. Metadata and peak indices remain explicitly bounded by the admitted
input size; pathological long metadata can allocate more than the trace buffer.
The worker exclusively creates output files and removes only its own incomplete
outputs on decode, callback, close or protocol failure. It never writes sources.

## Evidence and limits

Offline C/source parity covers all 75,600 ADC samples from the seven supplied
originals, their generated trace values, metadata and 34 peak records, plus focused
synthetic malformed/encoding cases. Originals retain identical SHA256 hashes.
The same parity cases and native bulk/I/O tests passed leak-enabled ASan/UBSan.
Staged real Tcl callbacks were checked without CORE stubs; these checks do not
establish canonical registration or installed GUI behavior. Separate real CORE
public API checks imported all seven distinct acquisitions into a registered
generator-created Session, verified schema/metadata/source and payload hashes,
and passed public persistence plus fresh-process reopen. Installed GUI and
independent vendor reference acceptance remain separate.

A five-run, same-host seven-file CLI comparison measured legacy Python median
0.388945 s and native C median 0.070208 s, with peak worker RSS 14,548 versus 1,804 KiB.
These numbers include per-file worker execution and CSV writing. They are CLI
measurements for the recorded build/input set, not GUI responsiveness promises.
CORE still orchestrates normal source batches per source and remains responsible
for hashing/registry transactions. Native worker `--bulk` is verified separately;
it does not silently replace that canonical lifecycle.

Legacy 0.2.2 documentation reports vendor CDF/TXT comparisons. Those exports are
not among the current supplied inputs and were not independently revalidated.
Implementation parity must not be described as new vendor scientific validation.
Other IC Net detector/software variants require individual assessment. MagIC Net
`.idet` is outside this format scope. AIA/ANDI remains a separate importer.

## Maintainer build and internal worker protocol

Use CMake on `native/` during development/packaging, then include the matching
prebuilt worker under `runtime/bin/linux-x86_64/chw_worker`. CMake declares C only.
No build command belongs in the runtime adapter. `runtime/chw_inspect.py` and its
original tests are retained unchanged as historical source/reference material;
the production callback does not invoke them or require Python.

A single worker invocation emits existing `GXCHW1` metadata/warning/peak records
with Base64 UTF8 values. `--summary-peaks` suppresses per-peak protocol transfer
while native C still writes the full peak CSV; the Tcl adapter uses summary mode.
Explicit `--bulk` accepts at most 1,024 independent inputs and emits `GXCHWB1`, then
`F <ordinal> <base64 source path> <base64 original basename>`, one optional contained
GXCHW1 response and `E <ordinal> <status> <base64 diagnostic>` per input. Fields use
tabs. Pre-open errors can produce F/E with no contained response. Later errors
invalidate that input's partial response. Exit 2 indicates at least one failure;
rows ending with status 0 remain separate successes. Consumers must check every expected
ordinal/end record and must never merge or register raw worker outputs directly.

`--original-filename` preserves the selected UTF8 POSIX basename independently of
CORE's renamed RAW snapshot. Duplicate basenames in different directories retain
separate source ordinals/paths. An explicit basename never controls output paths.

Proprietary samples, reference exports and laboratory metadata are not bundled.
The preserved upstream archive/member hashes and current development evidence
scope are recorded in SOURCE_PROVENANCE.json and the source integrity notes.
