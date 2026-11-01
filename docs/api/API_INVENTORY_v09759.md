# GX-TXT API Inventory — v0.9.7.59 delta

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.59 is a stabilization release. No existing public API version is replaced or renumbered.

## New public contract

- [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md)
  - semantic scope: `value_kind=elapsed_time`;
  - current textual format: `value_format=hms`;
  - public default numeric representation: seconds;
  - source parsing and future requested-unit conversion are separate concerns.

## Existing APIs clarified by the contract

- Dataset Variable Schema API v2: HMS source values normalize to numeric elapsed seconds.
- Canonical Dataset API v2: existing typed CSV behavior is confirmed as the authoritative seconds representation.
- Table Stream API v3: Dataset-backed numeric transport preserves Canonical Dataset seconds.
- Table Stream API v2: legacy Octave numeric conversion is aligned to the same seconds representation.
- Analysis Source runtime metadata: existing `value_kind`, `value_format`, `unit`, `time_reference`, and `time_origin` fields remain unchanged; consumers read numeric data through CORE and do not reinterpret HMS source text.
- Temporal Set API v1: `elapsed_time` / `hms` temporal variables use numeric unit `s` for segment/window resolution.

## Not added in 0.9.7.59

This release does not add the later requested-unit elapsed-time API. It does not add target-unit parameters for `min`, `h`, `day`, Julian year, `ka`, or `Ma`.

No FFT, spectrogram, Dataset Selection, Dataset Metadata, Analysis Source, plotting schema, Publication, Unit Registry, or storage API version changes in 0.9.7.59.
