# GX-TXT API Inventory — v0.9.7.60 delta

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.60 is an additive CORE release. Existing public API versions are preserved.

## New public API

- [Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md)
  - canonical input semantic: `value_kind=elapsed_time` numeric seconds;
  - missing requested target: `s`;
  - explicit target conversion through Unit Registry / Unit Dimension infrastructure;
  - Tcl helpers: `elapsedTimeCanonicalUnit`, `elapsedTimeRequestedUnit`, `elapsedTimeConvert`;
  - Octave helper: `gxtxt_elapsed_time_convert`;
  - scalar/list Tcl values and normal scalar/vector/matrix Octave values;
  - explicit rejection of unknown or incompatible target units;
  - no Dataset or schema mutation.

## Unit Registry API v1 additions

CORE registers three exact scale units whose canonical unit is `s`:

```text
a   = 31557600 s          Julian year
ka  = 31557600000 s       1000 Julian years
Ma  = 31557600000000 s    1000000 Julian years
```

Existing `s`, `min`, `h`, and `day` intrinsic semantics are unchanged. No generic `year` alias is added.

## Existing APIs preserved

- Elapsed Time Contract v1: canonical/default numeric elapsed time remains seconds.
- Dataset Variable Schema: preserved source-unit metadata is not rewritten or reinterpreted by requested-unit conversion.
- Canonical Dataset API v2 and Table Stream APIs: canonical numeric values are unchanged.
- Temporal Set API v1: internal duration resolution remains based on canonical temporal values; no presentation-unit dependency is introduced.
- Analysis Source runtime and `standard_octave`: existing derived Unit Registry transport is reused through `GXTXT_UNIT_REGISTRY_FILE`.
- Dataset Metadata, Dataset Selection, Publication, FFT, spectrogram and plotting APIs are unchanged.

## Not added in 0.9.7.60

This release does not integrate Temporal Sets into FFT, modernize spectrogram, integrate audio/image/math modules, change plot UX, add parallel execution, simulation, or instrument-control functionality.
