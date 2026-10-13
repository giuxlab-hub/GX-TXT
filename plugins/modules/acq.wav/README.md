<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# WAV / PCM raw audio import (`acq.wav`)

_Framework >= 0.9.6._

**Imports raw (neutral) audio only.** Compressed/lossy sources (MP3, AAC, OGG,
ADPCM, A-law/mu-law, MP3-in-WAV…) are **refused by design**: they are not
neutral raw sources — their bytes are a codec's reconstruction recipe, not the
measurement. A raw PCM file's bytes *are* the measurement, so its RAW snapshot
and SHA-256 mean something; a compressed file's would not.

This importer registers a WAV as a first-class **binary** canonical dataset
(`audio.waveform`, `storage_kind=binary`, `media_type=audio/wav`) using the
Binary Dataset Foundation. The bytes are kept **opaque** and provenance-anchored.
It does **not** decode: turning the audio into a time-series is a separate,
downstream step — see `analysis.audio_decode`, which produces a
`timeseries.table` the FFT (and any analysis module) can consume.

## Neutrality is checked by content, not by name

WAV is a container: a `.wav` file may hold compressed audio (ADPCM, mu-law,
even MP3-in-WAV). `acq.wav` parses the `fmt` chunk and accepts only **linear
PCM** — integer (format 1) or IEEE float (format 3), including
`WAVE_FORMAT_EXTENSIBLE`. A non-PCM payload is rejected with an explanation,
even if it is named `.wav`. Refusing by content, not extension, is what makes
the neutrality guarantee real.

## Output

One binary `audio.waveform` dataset per file. Preview shows codec, sample rate,
channels, bit depth and duration (Preview Descriptor API metadata branch); the
payload itself stays opaque.

## Dependencies

None. Pure Tcl header inspection; no sample decoding here. (The downstream
`analysis.audio_decode` step requires `ffmpeg`/`ffprobe`.)

## Scope

WAV/PCM raw audio. RF64 / Wave64 (>4 GB) and exotic container extensions are
out of scope and rejected cleanly rather than guessed. See `TODO.md`.

## Installation

Install the ZIP from the **Modules** tab (Plugin Install API v1). No core edits.
