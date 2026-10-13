# Changelog

## 1.0.1

- Integrated the supplied acquisition implementation into GX-TXT 0.9.7.63 as a protected, disabled-by-default CORE module.
- Kept probing and raw PCM interpretation on public Audio Decode API v1; no private FFmpeg execution path was added.
- Validated RAW PCM Dataset Metadata transport through the public Analysis Source runtime bridge.
- Added current-baseline installer/discovery, invalid RAW-parameter, byte-preservation and optional real-session regressions.

## 1.0.0

- Added generic `audio.source` acquisition through Audio Decode API v1 probing.
- Added byte-preserving import for self-describing FFmpeg/FFprobe-supported audio.
- Added explicit headerless raw PCM import using CORE raw-input hints.
- Added mono, stereo and multichannel metadata handling.
- Added framework-owned batch/multi-source support.
- Added Dataset Metadata API v1 structured metadata transfer.
- Added preservation of FFprobe container and selected-stream tags.
- Added non-CSV metadata preview.
