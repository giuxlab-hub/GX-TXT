# GX-TXT Preview Descriptor API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Preview Descriptor API v1 lets a plugin describe a preview without requiring the framework to understand or decode the source format. It is intended primarily for binary acquisition sources and binary canonical datasets, but it is host-independent and may also be used by text handlers.

The plugin produces preview content. The framework owns preview workspace rendering, temporary preview storage, validation and cleanup.

## Framework-provided preview directory

When the common acquisition Preview workspace asks `inspect_proc` for a preview, the request contains:

```text
preview_dir=<absolute framework-owned temporary directory>
```

`dataset_preview_proc` receives the same field. A plugin that wants to create an artifact MUST write it inside this directory. The framework rejects path traversal and artifacts outside `preview_dir`.

When inspection is performed only for metadata/variable discovery, `preview_dir` may be empty. Plugins MUST therefore treat artifact generation as optional.

## Descriptor fields returned by the plugin

The inspection/dataset-preview result may contain:

```text
preview_kind=metadata
preview_metadata=<Tcl dict of label/value pairs>
```

or:

```text
preview_kind=artifact
preview_artifact=<Tcl dict>
```

with artifact fields:

```text
path=<path relative to preview_dir, or an absolute path still inside preview_dir>
media_type=<MIME media type>
label=<optional human-readable label>
```

Both branches may be requested with:

```text
preview_kind=metadata+artifact
```

`both` is accepted as an alias. `none` explicitly requests no preview content. For compatibility, absence of `preview_kind` preserves legacy text preview behavior; for a binary source, existing `metadata` is used as metadata preview when no explicit descriptor is returned.

## Rendering contract

The framework:

- renders metadata as label/value rows;
- may display visual artifacts supported by the current host renderer;
- never decodes the original binary source;
- does not itself generate thumbnails, waveforms or extracted frames; the separate CORE Dataset Preview API may create safe temporary fallback artifacts for registered media datasets;
- shows a safe fallback description when the host cannot display the declared artifact media type.

A plugin that needs guaranteed display in the current Tcl/Tk host should produce a simple image artifact such as PNG or another image format supported by the host. Future hosts, including GiuxLab-Calc, may render the same descriptor differently without changing the plugin.

## Security and lifecycle

Artifact paths are validated to remain below the framework-owned `preview_dir`. The directory is temporary and is removed after the host has consumed the preview. It is not part of the canonical dataset or scientific provenance unless the plugin separately publishes an artifact as a dataset/output.

## Non-goals

Preview Descriptor API v1 does not define audio playback, video playback, image decoding, codecs, ROI semantics or scientific image processing. Those belong to plugins and future scientific APIs.
