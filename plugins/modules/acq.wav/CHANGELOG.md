<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog — acq.wav

## 1.0.0
- First release. Imports raw PCM audio (WAV) as a first-class **binary**
  `audio.waveform` canonical dataset (Binary Dataset Foundation v1).
- Neutrality enforced by **content**: the `fmt` chunk audio format is parsed
  (PCM integer / IEEE float, incl. WAVE_FORMAT_EXTENSIBLE) — not the `.wav`
  extension. Compressed/lossy payloads are refused on import with an explicit
  message.
- Metadata preview (Preview Descriptor API v1): codec, sample rate, channels,
  bit depth, duration. No sample decoding at import — bytes stay opaque.
- Pure Tcl, no external dependency (decoding to a time-series is the separate
  `analysis.audio_decode` step, which requires ffmpeg).
- Declares `variable_mapping=none` (v0.9.6 acquisition handler contract) so
  binary batch import does not fail the variable-mapping requirement.
- Validates the **RAW snapshot** bytes (`raw_path`) it registers, not the
  original source, closing a TOCTOU window.
- Header inspection now requires a `data` chunk and sane fmt fields
  (channels/sample-rate/bit-depth > 0); order-independent chunk walk.
- Formalizes the `audio.waveform` contract and ships CORE self-tests
  (valid PCM, fake file, compressed refusal, no-data refusal, byte-identical
  RAW->dataset, preview metadata). Requires framework >= 0.9.6.
