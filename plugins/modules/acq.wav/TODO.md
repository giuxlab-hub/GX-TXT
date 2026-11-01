<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# TODO — acq.wav

## Declared position (not a limitation — a design stance)

This importer accepts **raw, neutral audio only**: linear PCM. Compressed/lossy
formats are **refused by design**, and this is stated to the user, not silent.

The reason is provenance integrity. A canonical dataset's RAW snapshot + SHA-256
are meant to anchor *the measurement*. For raw PCM, the bytes **are** the
measured samples — the hash anchors truth. For a compressed file, the bytes are
a codec's recipe; the samples you would analyse are neither in the file nor in
the hash, and are reconstructed (with loss, codec- and version-dependent). A
compressed source is therefore **not neutral**, and registering it as raw would
make the RAW/SHA-256 anchor a falsehood. So compression belongs upstream: decode
to WAV/PCM first, then import — or, in future, as a separate downstream
codec→PCM stage over the Binary Foundation that honestly labels its output as
*derived*, not *measured*.

## Deliberately omitted

- **No decoding.** The importer keeps bytes opaque; sample extraction is
  `analysis.audio_decode` (downstream). Not folded in on purpose.
- **No compressed formats.** As above — refused by content check, not merely
  unsupported.
- **No RF64 / Wave64 (>4 GB), no BWF-specific metadata.** Rejected cleanly.
- **No 24-bit unpack / sample handling here** — inspection reads the `fmt`
  header only; sample-level work is the decoder's job.

## Possible future additions (when a workflow asks)

- A separate `acq.audio_transcode` (or decode stage) that takes a compressed
  source and produces a WAV/PCM `audio.waveform`, labelled as *derived*.
- RF64/Wave64 header support for very long captures.
- Carrying instrument/BWF metadata into dataset provenance.
