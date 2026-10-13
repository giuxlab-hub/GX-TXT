<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog — analysis.audio_decode

## 2.0.1
- Recalculates the stable decoded waveform Dataset through Publication v2
  `replace_owned=true`; CORE enforces same-owner replacement and rollback.

## 2.0.0
- Replaced the module-private WAV/RIFF decoder with CORE Audio Decode API v1.
- Removed `runtime/decode_wav_pcm.py` and its private-decoder tests.
- Replaced Dataset Publication API v1 / decimal CSV output with Dataset
  Publication API v2 chunked publication.
- Added Storage Auto requirements for append writes, typed numeric storage and
  implicit axes; range and sequential chunk access are preferences.
- Added a stable `sample` dimension, implicit uniform `time` coordinate and
  stable `channel_N` Variable IDs while retaining `time_s` / `chN` names.
- Channel output remains `float64`; integer PCM uses CORE `int32` transport and
  division by `2^31`, preserving the tested 1.0.4 PCM16/24/32 full-scale
  semantics exactly. Floating sources use CORE `float32` transport without
  clipping before conversion to module `float64` output.
- The normal path no longer creates `decoded.csv`, a full decoded PCM file, or
  an explicit time vector.
- Added bounded 65,536-frame decode/publication chunks and direct large-dataset
  read-back tests.
- Added Canonical Dataset API v2 and Table Stream API v3 validation, including
  direct late-range access and session relocation/copy tests.
- Preserved the existing amplitude scale/unit GUI controls and removed obsolete
  documentation referring to Python/NumPy as module runtime dependencies.

## 1.0.4
- Removed the ffmpeg/Octave hang path by moving linear-PCM WAV parsing to a
  bundled Python helper and writing CSV in bounded chunks.
- Added direct support/regression checks for 24-bit integer PCM and IEEE-float
  PCM, exact 32-bit integer round trips, channel separation, amplitude scaling,
  and refusal of A-law/mu-law payloads.

## 1.0.3
- Replaced the deadlocking ffmpeg stdout pipe with a temporary decoded file and
  chunked CSV write.

## 1.0.2
- Added progressive decode/write behavior.

## 1.0.1
- Tightened the linear-PCM codec whitelist.

## 1.0.0
- First release using Dataset Publication API v1 and explicit decimal CSV.
