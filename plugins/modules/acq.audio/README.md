# `acq.audio` 1.0.1

Generic audio-file acquisition module integrated as a protected GX-TXT CORE module in GX-TXT 0.9.7.63.

It imports self-describing formats supported by the public GX-TXT Audio Decode
API and explicitly described headerless raw PCM as byte-preserving
`audio.source` datasets. It supports framework-owned multi-source batch import
and publishes FFprobe technical/tag metadata through Dataset Metadata API v1.
RAW interpretation fields therefore travel through the normal Dataset Metadata
runtime bridge rather than a private importer sidecar.

The module does not decode, resample, normalize or edit audio. Numeric sample
decoding remains a separate downstream analysis responsibility.

See [`AUDIO_IMPORTER_GUIDE.md`](AUDIO_IMPORTER_GUIDE.md) for the complete user
and architecture guide.
