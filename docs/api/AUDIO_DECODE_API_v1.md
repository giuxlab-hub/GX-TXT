# Audio Decode API v1

Audio Decode API v1 is a generic CORE service backed by FFmpeg and FFprobe. It
does not define scientific Dataset policy and does not publish results.

## Dependencies and probe

`audioDecodeDependencyInfo` reports executable paths and versions.
`audioProbe` safely invokes FFprobe with argv and reports audio streams,
deterministic selected stream index, container codec fields, sample rate,
channels, layout, source sample format, reliable bit depth, duration and frame
count when reported. `metadata_status` distinguishes known, reported and
not-reported fields.

Existing forms remain valid:

```tcl
set metadata [::GX::audioProbe $path]
set metadata [::GX::audioProbe $path $streamIndex]
```

## Container and stream tags

GX-TXT 0.9.7.38 adds two dictionaries to every probe result:

```text
container_tags
stream_tags
```

`container_tags` contains tags from the FFprobe format section.
`stream_tags` contains tags from the selected audio stream. Each entry in
`streams` also contains its own `tags` dictionary. Keys and values are
preserved as reported, including unknown keys and original key case. CORE does
not merge container and stream dictionaries and does not map tags to
application fields such as `audio.artist`. Files without reported tags return
empty dictionaries.

## Explicit raw PCM input hints

Headerless raw PCM input uses the existing probe/decode operations with an
optional hints dictionary:

```tcl
set hints [dict create \
    input_format s16le \
    sample_rate 48000 \
    channels 2]

set metadata [::GX::audioProbe $path $hints]
set handle [::GX::audioDecodeOpen $path [dict merge $hints [dict create \
    sample_format float32 \
    chunk_frames 4096]]]
```

The same `input_format`, `sample_rate` and `channels` values are
passed explicitly to FFprobe and FFmpeg. If any raw hint is supplied, all three
are required. CORE never derives them from filename, file size or content
heuristics.

Supported raw input formats are:

```text
u8
s16le s16be
s24le s24be
s32le s32be
f32le f32be
f64le f64be
```

`audioProbe` returns the normalized dictionary as `input_hints`. Invalid,
partial or unsupported hints fail with an explicit error. Formatted WAV, FLAC,
MP3 and other inputs require no hints and retain the existing behavior.

The additive call forms are:

```tcl
::GX::audioProbe $path $optionsDict
::GX::audioProbe $path $streamIndex $optionsDict
::GX::audioDecodeOpen $path $optionsDict
```

The standard Octave helpers accept the same option fields in a struct.

## Bounded decode

`audioDecodeOpen` owns one persistent FFmpeg process.
`audioDecodeNext` returns a bounded block with frame count, channel count,
sample format, interleaved raw typed bytes and EOF. Decode output formats are
`float32`, `int16` and `int32`. Float32 uses FFmpeg native floating
decode with nominal full scale -1.0 to +1.0. Channel order is FFmpeg stream
order; semantic channel names are not invented. The default audio stream is
the first audio stream reported by FFprobe, or callers may request an explicit
stream index.

No complete decoded file is created. Working payload is channels multiplied by
`chunk_frames` multiplied by bytes per sample. `audioDecodeClose`
terminates and releases the process.

Standard Octave helpers provide probe, open, next, diagnostics and close. The
persistent Tcl bridge owns FFmpeg; modules do not invoke or parse FFmpeg
privately. Paths and options are passed as argv entries and support spaces and
Unicode without shell construction.

Missing FFmpeg/FFprobe, missing streams, invalid input, unsupported formats,
invalid raw hints and failed decodes return explicit errors.
