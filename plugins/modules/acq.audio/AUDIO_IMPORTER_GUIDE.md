# Audio file import (`acq.audio`)

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

`acq.audio` imports audio files into a GX-TXT session as canonical opaque
`audio.source` datasets. The importer preserves the source bytes exactly; it
does **not** decode, normalize, resample, mix channels, or create sample/time
columns.

The integrated module targets GX-TXT 0.9.7.62 or newer and uses only public GX-TXT
APIs:

- Acquisition Handler Plugin API v1;
- Audio Decode API v1 for FFprobe-backed recognition and metadata inspection;
- Dataset Metadata API v1 through the acquisition `structured_metadata` transfer;
- Analysis Source Dataset Metadata Runtime Extension v1 for downstream runtime transport;
- Preview Descriptor API v1;
- Plugin Install API v1.

## Supported audio sources

For self-describing audio, format support is intentionally the same as the
current GX-TXT Audio Decode API / FFmpeg+FFprobe installation. The importer does
not maintain a private codec list.

Typical examples include:

- WAV / WAVE;
- FLAC;
- MP3;
- AAC / M4A / compatible MP4 audio containers;
- OGG / Vorbis / Opus;
- Matroska/WebM audio;
- other audio formats that the installed GX-TXT Audio Decode API can probe.

The file chooser deliberately allows any file. Recognition is content-based via
the public CORE probe. An unsupported or non-audio file is rejected.

## Headerless raw PCM

`.pcm` and `.raw` files have no header and cannot describe their own sampling
semantics. For those sources the user must explicitly provide:

- **Raw PCM sample format**: `u8`, `s16le`, `s16be`, `s24le`, `s24be`, `s32le`,
  `s32be`, `f32le`, `f32be`, `f64le`, or `f64be`;
- **Raw PCM sample rate [Hz]**;
- **Raw PCM channel count**.

No value is inferred from file size or filename.

The three settings are module configuration, so all raw PCM files imported in
one batch use the same hints. If raw PCM sources use different formats, sample
rates, or channel counts, import them in separate incremental passes with the
appropriate settings. Self-describing sources may be freely mixed in one batch.

## Mono, stereo, and multichannel sources

The importer preserves the original file as one `audio.source` dataset and
records the channel count and channel layout reported by CORE. Mono and stereo
are both supported; higher channel counts are accepted when the Audio Decode API
reports them.

The importer does not split stereo into separate datasets. Channel-to-variable
mapping belongs to the downstream audio decoder, where decoded channels become
scientific sample variables.

## Multiple audio streams

Containers may contain more than one audio stream. By default the first audio
stream is used for technical metadata. Set **Audio stream index** to select a
specific stream explicitly. The selected index and total audio stream count are
stored in Dataset Metadata.

Raw PCM has one elementary stream; its stream index must be blank or `0`.

## Multi-source workflow

`supports_batch=1` uses the framework-owned Acquisition source batch UI.

1. Select `Audio file import` in Acquisition.
2. Select the first file or enable **Use source batch**.
3. Use **+ Add source** / **Add sources...** to add more files.
4. Give every row a stable Dataset ID.
5. Import the enabled rows.

Each source becomes an independent `audio.source` dataset in the same session.
There is no implicit alignment, concatenation, resampling, or mixing.

## Dataset representation

For every source, GX-TXT keeps:

- the framework-owned RAW snapshot and SHA-256 provenance;
- a byte-for-byte canonical opaque copy under `datasets/`;
- `contract=audio.source`;
- binary storage metadata and an appropriate best-effort MIME type;
- structured Dataset Metadata extracted from the public audio probe.

The encoded file remains authoritative. Import does not create WAV, PCM, CSV,
HDF5, or decoded sample intermediates.

## Structured Dataset Metadata

The importer stores technical fields where reported, including:

- `source.original_filename`;
- `source.extension`;
- `source.byte_size`;
- `audio.container`;
- `audio.codec`;
- `audio.sample_rate_hz`;
- `audio.channels`;
- `audio.channel_layout`;
- `audio.sample_format`;
- `audio.bits_per_sample` / `audio.bits_per_raw_sample`;
- duration/frame information when FFprobe reports it;
- selected stream and stream count;
- raw PCM hints when applicable;
- probe backend/version information.

FFprobe container and selected-stream tags are preserved generically as:

```text
tags.container.<normalized-key>
tags.stream.<normalized-key>
```

Common tags are also mapped to convenient audio names such as:

```text
audio.title
audio.artist
audio.album
audio.album_artist
audio.genre
audio.date
audio.comment
audio.encoder
audio.language
audio.track
audio.disc
audio.copyright
```

Metadata do not alter the source bytes or Dataset scientific identity.

## Relationship to decoding

`acq.audio` owns file import and source metadata. It does not own numeric audio
decoding. A downstream decoder should consume `audio.source` and use the public
Audio Decode API to produce canonical sample variables and a uniform time axis.

The existing `analysis.audio_decode` remains a separate consumer with its own
input contract. This importer intentionally does not relabel compressed sources
as `audio.waveform` merely to fit another module. Contract changes in downstream
analysis modules are outside this acquisition integration.

For headerless raw PCM, the import metadata contain the exact input hints used.
GX-TXT exposes those fields to `standard_octave` Analysis
Sources through the public Dataset Metadata runtime bridge. A downstream module
can therefore obtain, for example, `audio.raw_input_format`,
`audio.raw_sample_rate_hz` and `audio.raw_channels` without opening
`metadata/datasets/*.ini`. `acq.audio` itself never reads or writes that sidecar
directly.

## Module installation and runtime validation

The bundled module is `CORE / OFF`: it is shipped with GX-TXT, remains disabled
by default, and is protected from uninstall. Its `plugin-package.ini` remains a
valid Plugin Install API v1 manifest so the same module directory can be
validated and packaged with the normal framework mechanism.

The integration regression covers WAV, FLAC, MP3 and explicit raw PCM, verifies
byte identity of both framework RAW provenance and canonical source storage, and
checks that RAW metadata are reproduced in a generated `standard_octave`
runtime through the public Analysis Source metadata bridge.

## Failure behavior

Import fails without registering a partial dataset when:

- the source is not recognized as audio;
- an explicit audio stream does not exist;
- raw PCM settings are missing or invalid;
- FFprobe cannot inspect the source;
- the canonical copy cannot be created;
- structured metadata are invalid or cannot be persisted.

Registry and Dataset Metadata lifecycle remain owned by CORE.
