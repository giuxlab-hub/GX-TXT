<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# TODO — analysis.audio_decode

## Current architectural boundaries

- Acquisition ownership is unchanged. `acq.wav` remains the normal bundled
  source of `audio.waveform` datasets and currently accepts neutral PCM WAV.
- Audio decoding, FFmpeg/FFprobe process ownership and chunk transport belong to
  CORE Audio Decode API v1.
- Storage selection, canonical writing, atomic commit and registry publication
  belong to CORE Dataset Publication API v2 / Storage Auto.
- Plotting and large-waveform graphical reduction remain outside this module.

## Framework binding limitation observed

The GX-TXT 0.9.7.28 `standard_octave` Publication v2 binding exposes storage
requirements/preferences and the writer lifecycle, but not the optional
publication-definition provenance fields (`source_dataset_ids`, `source`,
`producer_version`, `provenance`, `notes`). The module deliberately does not
work around this by editing the Dataset Registry. Automatic Publication v2
provenance remains authoritative; additional run diagnostics are written to
`decode_info.txt`.

## Possible future work

- Preserve trustworthy source channel labels when a future source contract
  exposes them explicitly.
- Add explicit stream selection only if the Analysis Source/GUI contract needs
  multi-stream audio selection.
- Revisit precision policy if a future CORE Audio Decode API adds `float64` or
  wider integer transport.
