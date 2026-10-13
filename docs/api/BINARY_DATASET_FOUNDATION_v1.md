# GX-TXT Binary Dataset Foundation v1

SPDX-License-Identifier: GPL-3.0-or-later

## Goal

GX-TXT v0.9.5 extends the existing Canonical Dataset model so a dataset can be stored as text or as opaque binary content without creating a parallel binary-dataset subsystem.

The framework remains format-agnostic. Plugins recognize, decode and analyse formats. GX-TXT transports, hashes, registers and routes the dataset.

## Dataset metadata

Canonical datasets may contain two additional metadata fields:

```text
storage_kind=text|binary
media_type=<MIME media type>
```

`storage_kind` defaults to `text` for backward compatibility. `media_type` is optional.

These fields are representation metadata, not scientific semantics. Scientific meaning continues to be expressed by the dataset `contract` / `kind`.

Examples:

```text
contract=image.raster
format=tiff
storage_kind=binary
media_type=image/tiff
```

```text
contract=audio.waveform
format=wav
storage_kind=binary
media_type=audio/wav
```

```text
contract=table.generic
format=csv
storage_kind=text
media_type=text/csv
```

No core decoder is implied by these examples.

## Acquisition Handler API

`import_proc` dataset result dictionaries may add:

```text
storage_kind binary
media_type image/tiff
```

The framework validates and persists the fields in the Dataset Registry. RAW snapshots and SHA-256 remain byte-safe and unchanged.

For opaque binary sources that expose no canonical variables, acquisition handlers may declare `variable_mapping=none`. This allows single-file and batch acquisition without inventing fake columns or variables. `variable_mapping=required` remains the default for backward compatibility.

## Dataset Publication API

Module-produced datasets may publish the same optional fields in their publication request:

```ini
[publication]
storage_kind=binary
media_type=application/x-hdf5
```

The Octave helper `gxtxt_dataset_publish_request()` accepts `meta.storage_kind` and `meta.media_type`.

## Analysis Source runtime

When a canonical dataset is selected as an Analysis Source, runtime transport includes:

```ini
[analysis_source.primary]
contract=image.raster
format=tiff
storage_kind=binary
media_type=image/tiff
```

Modules can therefore decide how to open the file without depending on Tcl/Tk or on the desktop host.

## Preview safety

An imported dataset with `storage_kind=binary` is never rendered by treating its bytes as text. If an acquisition plugin supplies a `dataset_preview_proc`, Preview Descriptor API v1 can provide metadata and/or a plugin-generated artifact. Without a preview provider, the framework shows registry metadata and explicitly leaves the binary payload opaque.

## Scope of v1

This foundation intentionally does not define pixel arrays, ROI geometry, calibration, image stacks, audio channel semantics, codecs or video frame models. Those can be added later by scientific contracts/modules without changing the storage/transport foundation.
