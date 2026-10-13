<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Audio decode (`analysis.audio_decode`)

The `standard_octave` decoder recalculates its stable decoded Dataset ID through
Dataset Publication API v2 same-owner replacement. CORE refuses cross-owner
replacement and restores the prior artifact and registry entry if publication
does not commit. The module is compatible with large Canonical Datasets and
delegates audio parsing and decoding to CORE rather than maintaining a separate
audio parser, FFmpeg wrapper or decimal CSV materialization path. Audio decoding is delegated to **CORE Audio Decode API v1** and canonical
waveform publication uses **Dataset Publication API v2** with **Storage Auto**.

## Data flow

```text
audio.waveform source
    -> CORE Audio Decode API v1
    -> bounded decoded chunks
    -> normalized scientific samples
    -> Dataset Publication API v2
    -> Storage Auto
    -> canonical timeseries.table
```

The normal decoding path creates neither a complete intermediate decoded PCM file nor a decimal waveform CSV.

## Scientific representation

The output dataset uses stable logical identities:

```text
dimension_id: sample
coordinate variable_id: time
channel variable_ids: channel_1, channel_2, ...
```

Output display names follow the current canonical conventions:

```text
time_s
ch1
ch2
...
```

The time coordinate is an implicit uniform Variable Schema v3 coordinate:

```text
origin = 0
step   = 1 / sample_rate
count  = decoded frame count
```

The time payload is therefore not stored once per sample. Canonical Dataset API
v2 and Table Stream API v3 reconstruct only the requested range.

Channel variables are published as `float64`, preserving the documented `float64` scientific output representation.

## Amplitude semantics

The 1.x scientific convention is retained:

- integer PCM is normalized to full scale using the signed PCM denominator;
- floating PCM remains floating full-scale data and is not clipped to +/-1;
- `amplitude_scale` applies one linear multiplier after decoding;
- `amplitude_unit` labels the resulting channel variables.

For integer-like sources the module requests `int32` from Audio Decode API v1
and converts with:

```text
sample_FS = int32_sample / 2^31
```

This is exactly equivalent to the 1.0.4 result for the tested PCM16, PCM24 and
PCM32 fixtures. Floating sources request `float32` and are converted to the
module's `float64` output without clipping. The deterministic float32 fixture is
also exactly equivalent to 1.0.4.

Audio Decode API v1 intentionally exposes only `float32`, `int16` and `int32`
transport formats. Consequently a source whose original scientific precision
exceeds those transports (for example PCM float64 or integer PCM wider than
32 bits) cannot retain every precision bit of the old private parser. The
module does not add a private fallback; this limitation is explicit rather than
silently reintroducing module-owned decoding.

## Storage

The module requests:

```text
storage = auto
required:  append_write, typed_numeric, implicit_axis
preferred: range_write, sequential_chunks
```

It does **not** select HDF5 directly. Under GX-TXT 0.9.7.28 the current Storage
Auto policy selects a provider satisfying those capabilities; for the tested
waveform path this is HDF5. Downstream consumers use Dataset IDs and Variable
IDs, never the provider path.

## Chunking

The decode/publication chunk is **65,536 frames**. Working waveform memory is
bounded by the channel count and current chunk rather than total duration.
Publication v2 receives one bounded append per channel for each decoded chunk.

## Input format scope

The module consumes the `audio.waveform` Analysis Source contract. The current
bundled `acq.wav` acquisition module supplies neutral linear-PCM WAV sources and
therefore remains the normal GUI path.

CORE Audio Decode API v1 itself is FFmpeg-based and can decode additional audio
containers/codecs. `analysis.audio_decode` does not add a second format filter;
if another valid GX-TXT source workflow provides an `audio.waveform` resource,
the public CORE decoder determines whether it is decodable. Acquisition
ownership is intentionally not changed by this module migration.

## Output and downstream access

The published `timeseries.table` is immediately usable through:

- Canonical Dataset API v2;
- Table Stream API v3;
- `plot.dataset` when it consumes canonical large datasets;
- the planned large-dataset migration of `analysis.fft_spectrum`;
- future Spectrogram and DSP modules;
- `dataset.extract` through canonical dataset access.

FFT consumers can obtain the selected channel, sample dimension, sample count,
uniform `dt`, numeric dtype and bounded ranges without module-private metadata.

## Provenance and diagnostics

Publication v2 automatically records the module ID, effective storage provider,
provider version, selection reason, publication/schema/access API versions and
canonical SHA-256 in the Dataset Registry.

`decode_info.txt` records run-level decoder metadata and diagnostics, including
source container/codec/sample format where reported by Audio Decode API v1,
sample rate, channel count, selected stream, requested decode format, chunk
sizes, FFmpeg/FFprobe versions, Publication v2 capabilities and effective
provider. It is a diagnostic artifact, not scientific identity and not a user
note.

The GX-TXT 0.9.7.28 Octave Publication v2 binding does not expose the optional
Tcl publication-definition fields `source_dataset_ids`, `source`,
`producer_version` or `provenance`. The module therefore does not edit the
Dataset Registry privately to add them.

## GUI

The existing useful controls are retained:

- `Full-scale to real-unit scale`;
- `Amplitude unit`.

No FFmpeg arguments, HDF5 paths, writer controls or chunk-transport controls are
exposed to users.

## Tests

`tests/run_audio_decode_test.sh` performs:

- deterministic fixture generation;
- static architecture checks;
- a real CORE large-data chain test:
  `Audio Decode v1 -> Publication v2 -> Storage Auto -> Canonical v2 -> Table Stream v3`;
- the full `standard_octave` module integration test when Octave is available.

The Octave integration covers mono/stereo PCM, PCM24/PCM32 exact full-scale
mapping, float32, amplitude scaling, multi-chunk data, direct late-range reads,
implicit time, Unicode/spaces paths, optional FLAC decoding, failure cleanup and
session relocation/copy.

## Deployment

`analysis.audio_decode` is a **bundled GX-TXT module**. This source package is
for replacing/updating the bundled module in the framework source tree; it is
not intended to override an installed bundled module through Plugin Install API
v1. The required framework baseline is GX-TXT **0.9.7.28** or newer with the
same public APIs.
