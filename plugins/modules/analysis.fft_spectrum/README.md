<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# FFT Spectrum & Error Analysis (`analysis.fft_spectrum`)

Version **2.3.0** delegates the complete retained FFT lobe estimator to public `math.numeric`. CORE statistical semantics owns quality definitions, units, availability, metrics and reports. Normal and Temporal Set spectrum publications retain their canonical identities and capture source lineage plus the interpreted summary.

It consumes the public Temporal Set API v1 and recalculates stable output IDs
using Dataset Publication API v2 same-owner replacement. Publication is
transactional and refuses output owned by another module. The normal
full-record, fixed-block and Dataset Selection workflows remain available.

This module remains a **single-frame FFT/spectrum analysis**. Processing a
Temporal Window Set means running that same FFT independently for each resolved
member. It does not turn the module into an STFT/spectrogram implementation;
time-varying spectrogram analysis remains the responsibility of
`analysis.spectrogram`.

## Data flow

Supported single-frame modes:

```text
canonical timeseries.table
    -> Analysis Source / stable variable bindings
    -> Table Stream API v3 / Canonical Dataset API v2
    -> optional Dataset Selection x_range
    -> full_record or fixed_block
    -> established FFT/window/normalization/metrics
    -> Dataset Publication API v2 / Storage Auto
    -> canonical spectrum.table
```

Temporal Set mode:

```text
canonical timeseries.table
    -> Analysis Source
    -> authoritative Temporal Set resource
    -> standard runtime
    -> gxtxt_temporal_set_from_runtime()
    -> gxtxt_temporal_set_member()
    -> bounded Table Stream range read
    -> established FFT calculation
    -> one canonical spectrum.table per Temporal Set member
```

Recalculation republishes the same stable Dataset ID with
`replace_owned=true`. CORE verifies the existing Publication v2 owner and
restores the prior artifact and registry entry if finalization fails.

The module never opens Temporal Set registry files, HDF5 files, or source CSV
files directly. Regular window generation, overlap, duration-to-row mapping,
parent Selection handling, and partial-window policy all remain CORE
responsibilities.

## Input

- Contract: `timeseries.table`.
- Binding `independent`: sample/time axis.
- Binding `signal`: one measured variable/channel to analyse.
- Optional `Data selection`: Dataset Selection `x_range` used by the legacy
  `full_record` and `fixed_block` modes.
- Optional `Temporal Set`: public `segment_set` or `window_set` resource used
  only when `Analysis mode = temporal_set`.

The module remains single-signal per run. Multiple channels are analysed by
choosing the required signal binding rather than through audio-specific logic.

## Analysis modes

### `full_record`

Preserved behavior. The complete source record is analysed, or the complete
configured Dataset Selection interval when one is active.

### `fixed_block`

Preserved behavior. The existing FFT length and `start`, `center`, or
`explicit` block-position rules are applied inside the source record or the
configured Dataset Selection. `fixed_block + fft_length=auto` remains an
explicit error.

### `temporal_set`

The selected public Temporal Set is consumed exactly as CORE resolved it.
Every member is transformed independently.

A legacy `config.selection` is not applied in this mode. If a Temporal Set
needs a parent interval, associate the Dataset Selection with the Temporal Set
itself. Supplying both a module Selection and Temporal Set mode is rejected
rather than silently applying a second private range operation.

## Arbitrary `segment_set`

For a segment set such as:

```text
A: 0 s  ... 20 s
B: 35 s ... 80 s
C: 90 s ... 110 s
```

the module performs:

```text
FFT(A)
FFT(B)
FFT(C)
```

The separated source regions are **never concatenated** before the transform.
Stable Temporal Segment identity, member index, label, source row range and
temporal interval are retained in the output provenance and module metrics.

### Variable-length segments

Arbitrary segments may contain different sample counts. Their FFTs can
therefore have different frequency resolution and different frequency grids.
Version 2.1.0 publishes each member as a **separate canonical `spectrum.table`
Dataset** rather than forcing unlike spectra into one rectangular table.

Dataset IDs are deterministic:

```text
<source-dataset>.spectrum.<temporal-set-id>.<member-id>
```

Each published Dataset uses standard Dataset Publication API provenance fields
for the source Dataset, source variables, producer version and Temporal Set
member/range information.

## Regular `window_set`

Sample-based and duration-based window sets are supported through the same
public Temporal Set runtime binding. The FFT module does not calculate window
starts or overlap itself.

For example, a CORE definition of:

```text
window = 200 samples
step   = 100 samples
```

is consumed through its resolved `row_start`/`row_count` members. Overlapping,
non-overlapping and gapped windows therefore follow the exact Temporal Set API
semantics.

Duration-based windows use the canonical temporal values supplied by CORE. The
module does not contain `/60`, `/3600`, or other private temporal conversion
factors. The canonical `elapsed_time` base representation remains seconds; any
explicit consumer conversion belongs to the public elapsed-time requested-unit
API.

## Parent Dataset Selection

A Temporal Set may reference a Dataset Selection. CORE resolves the effective
parent interval before runtime generation. FFT receives only members contained
inside that resolved interval and reads the corresponding bounded source rows.

A missing Dataset, temporal variable or parent Selection is an explicit CORE
runtime-generation error. The module never falls back to `full_record` when a
requested Temporal Set is stale or invalid.

## Partial windows

Temporal Set API v1 owns `partial_policy`:

- `drop`: no partial final member is generated;
- `include`: the final member may have fewer rows than the nominal window.

FFT consumes the member exactly as resolved. If a member contains fewer than
the existing FFT minimum of eight samples, analysis fails explicitly for that
member; the module does not enlarge, pad or silently drop it.

## Sampling rate and source access

For a canonical **uniform** independent coordinate, Schema v3 metadata are
authoritative:

```text
origin
step
count
```

The sampling rate is `fs = 1 / step`. For Temporal Set members only the signal
rows identified by the member are read. The complete source signal is not
materialized merely because the set contains many windows.

For explicit-coordinate canonical datasets, the Temporal Set row range is read
through Table Stream and both coordinate and signal values are loaded only for
the current member. The established explicit-axis compatibility behavior uses
the median step and reports nonuniform sampling.

## FFT mathematics retained

The numerical calculation is the established 2.0.0 implementation, extracted
into one shared internal function so all range modes use exactly the same
algorithm:

- windows: `rectangular`, `hann`, `hamming`, `blackman_harris`, `flat_top`;
- detrend: `none`, `mean`, `linear`;
- coherent-gain correction `mean(window)`;
- single-sided peak-amplitude spectrum;
- DC is not doubled;
- even-N Nyquist is not doubled;
- `magnitude_dBc` is relative to the detected/explicit fundamental;
- THD, SFDR, SINAD, ENOB and tracked harmonic levels are unchanged.

`FFT window` remains the weighting function only. A Temporal Window Set is a
source-range resource and is unrelated to the FFT weighting-window choice.

## Canonical outputs

Legacy `full_record` and `fixed_block` modes retain the historical output
Dataset ID:

```text
<source-dataset>.spectrum
```

Temporal Set mode publishes one `spectrum.table` for each member. Every result
uses the existing logical schema:

```text
dimension: frequency_bin

coordinate:
    variable_id = frequency
    axis_kind   = uniform
    origin      = 0
    step        = fs / N

variables:
    amplitude
    magnitude_dbc
```

The output frequency coordinate remains implicit/uniform. Dataset Publication
API v2 / Storage Auto chooses the physical provider.

### Provenance

Temporal member publications use the standard Publication API provenance
fields rather than module-private metadata sidecars. They record, where
applicable:

- source Dataset ID;
- independent and signal variable IDs;
- producer/module version;
- Temporal Set ID;
- member ID and member index;
- source row start/count;
- `[start,end)` temporal bounds and temporal unit;
- optional member label in publication notes.

The module also writes the declared `fft_metrics.ini` and `fft_report.txt`.
In Temporal Set mode these contain a summary plus one section/report block per
member and the corresponding published Dataset ID.

Computed annotation files continue to use the public Computed Data Annotation
API. Temporal Set mode gives each member annotation resource a unique filename.

Version 2.1.0 does not create intermediate spectrum CSV files or one temporary
source file per member.

## Performance characteristics

Temporal Window Sets stay compact in persistent/runtime state. A 100,000,000
row uniform fixture resolving to 48,827 windows is covered by the source-level
regression without opening the payload during CORE resolution.

Each FFT member is independent, so a Temporal Window Set naturally exposes a
future parallel work unit of **one resolved Temporal Set member**. Version
2.1.0 deliberately remains serial and does not use Octave parallel packages,
MPI, worker pools or shell-spawned FFT jobs. Framework-level parallelism should
be introduced only after execution measurements on a machine with GNU Octave
show that member-level FFT work justifies the scheduling/public API overhead.

## Validation

Run the module tests from inside a GX-TXT framework tree:

```bash
bash plugins/modules/analysis.fft_spectrum/tests/run_fft_spectrum_test.sh
```

Run the source/runtime Temporal Set integration regression with:

```bash
tclsh tests/test_v09761_fft_temporal_runtime.tcl
```

The Octave integration test covers retained full-record/fixed-block/Selection
behavior plus segment sets, sample windows, duration windows, parent Selection,
partial-window handling and member publication/provenance when GNU Octave is
available. Environments without GNU Octave must report that part as `SKIP`.

## License

GNU GPL v3 or later.

CORE distinguishes corrected amplitude lobe RSS from raw coherent FFT-bin powers.
Existing level-floor and lobe-overlap conventions are explicit. Component reports
use bounded CORE rows, preserving unavailable levels without discarding valid
amplitudes. Numerical policies and prior scientific Datasets are preserved;
legacy metric keys now include statistical status and quantity identifiers.
