# GX-TXT API Inventory — v0.9.7.61 delta

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.61 is an additive consumer-integration release. No new Temporal Set or FFT semantic API version is introduced.

## `analysis.fft_spectrum` 2.1.0

- Adds `analysis_mode=temporal_set` through the existing module configuration system.
- Consumes Temporal Set API v1 resources only through the standard runtime and public Octave helpers `gxtxt_temporal_set_from_runtime` and `gxtxt_temporal_set_member`.
- Supports public `segment_set` and regular sample-/duration-based `window_set` resources, including overlap, parent Dataset Selection and Temporal Set `partial_policy`.
- Publishes one canonical `spectrum.table` Dataset per Temporal member. This preserves independent frequency grids for variable-length arbitrary segments.
- Existing `full_record`, Dataset Selection and `fixed_block` modes remain available and retain their existing behavior.

## Dataset Publication API v2 Octave binding

The public `gxtxt_publication_v2_open` options structure now transports the existing Publication v2 definition fields `producer_version`, `source_dataset_ids`, `source_variable_ids`, `source`, `provenance`, and `notes` to CORE. These are not a new provenance model; they expose fields already defined by Dataset Publication API v2 to the standard Octave binding. Existing storage/capability-only calls remain compatible.

## Existing APIs preserved

Temporal Set API v1, Dataset Selection, Canonical Dataset API v2, Table Stream, Analysis Source runtime, elapsed-time APIs, Dataset Metadata, Graph Series, Publication semantics, spectrogram and plotting APIs are otherwise unchanged. `plot.dataset` is not modified in this release.

## Not added in 0.9.7.61

This release does not add parallel/multicore execution, spectrogram/STFT behavior, audio/image/math integration, plot 3-D work, simulation or instrument-control functionality.
