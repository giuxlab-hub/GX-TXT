# Curve Digitalizer Image Processing API

SPDX-License-Identifier: GPL-3.0-or-later

**Public API ID:** `CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1`  
**Provider:** `viewer.curve_digitizer` (GX-TXT CORE plugin)  
**Tcl namespace:** `::GX::CurveDigitizerImage`  
**Script Bridge provider:** `plugins/modules/viewer.curve_digitizer/api/script_bridge_binding.py`

## Purpose

Read the history and provenance of ImageMagick photometric enhancements that were
published as canonical `image.raster` Datasets. Consumers need only a canonical
Dataset ID, not the implementation details of Dataset Metadata API sidecars.
The source image and its SHA-256, processing sequence and original-coordinate
identity remain accessible independently of the Interactive Document.

This API does not process images, write metadata, make files or modify scientific
curves. It is a stable, read-only interpretation boundary. The normal CORE
`DATASET_FILE_PUBLICATION_API_v1` owns output publication and SHA-256.

## Image processing and geometry guarantees

Operations are deliberately limited to these photometric filters:
`grayscale`, `channel`, `gamma`, `brightness_contrast`, `auto_level`,
`contrast_stretch`, `clahe`, `threshold`, `median`, `negate`, `sharpen`.
Image dimensions are checked against the original after processing, and
publication verifies the PNG header dimensions against structured metadata.
Crop, resize, rotate, flip, shear, perspective and arbitrary command execution
are not supported. `pixel_transform=identity` and `geometry_preserved=true`
mean the **raster coordinate system and grid** have not changed; filters can
change the apparent placement/contrast of an edge and do not provide new
geometric metrology. Published originals are never overwritten.

## TCL API

```tcl
set manifest [::GX::CurveDigitizerImage::read $datasetId]
set operations [::GX::CurveDigitizerImage::operations $datasetId]
set lineage [::GX::CurveDigitizerImage::lineage $datasetId]
set supported [::GX::CurveDigitizerImage::hasManifest $datasetId]
```

Optional second argument `session` must equal the currently open GX-TXT Session.
An unknown or unrelated Dataset yields an explicit error from `read`; `hasManifest`
returns false. `lineage` recursively validates parents, bounded to 64 links,
and rejects missing/mismatched parent SHA-256 or cycles. It includes the original
Image Dataset as the last element. No image bytes are copied.

### `read` return fields

| Field | Contract |
| --- | --- |
| `api_id`, `api_version` | Stable public API identity and major version |
| `dataset_id` | Canonical output Dataset ID |
| `source_dataset_id` | Immediate Image Dataset parent |
| `source_display_name` | Human-readable source name at publication |
| `source_sha256` | SHA-256 of immediate canonical parent |
| `processing_operations` | Ordered list of dicts `{kind, value}` |
| `operation_count` | Number of ordered steps |
| `processing_engine` | `ImageMagick` |
| `processing_engine_version` | Captured installed runtime version |
| `geometry_preserved` | `1` / `true`, validated |
| `pixel_transform` | `identity` |
| `image_width`, `image_height` | Output raster dimensions in source pixels |
| `processing_fingerprint` | Deterministic SHA-256 of source identity, recipe and runtime version |
| `output_sha256` | CORE-registered output payload SHA-256 |

A separate human description is stored with the published Dataset notes. The
canonical Dataset ID remains the stable image identity.

A processing fingerprint identifies a specific recipe/source/runtime tuple.
It does not establish numerical equivalence between different engine releases.
`source_sha256` and `output_sha256` identify the exact image bytes.

### Errors

Missing Dataset, incompatible contract, missing/corrupted manifest, unsupported
schema, invalid dimensions, unknown operations and broken lineage raise Tcl errors
(or an explicit Script Bridge RemoteError). Missing fields are never filled by
guessing. Legacy Image Datasets without a processing manifest are still ordinary
valid `image.raster` sources, but `read` does not falsely claim they were processed.

## Python Script Bridge

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call

gxtxt_api_require('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1@1:viewer.curve_digitizer')
image_id = 'sem.enhanced'
info = gxtxt_api_call('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1', 'read', [image_id])
for op in info['processing_operations']:
    print(op['kind'], op['value'])
print('Original:', info['source_dataset_id'], info['source_sha256'])
parents = gxtxt_api_call('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1', 'lineage', [image_id])
```

## GNU Octave Script Bridge

```octave
assert(gxtxt_api_has('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1'));
info = gxtxt_api_call('CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1', 'read', {'sem.enhanced'});
disp(info.source_dataset_id);
for k = 1:numel(info.processing_operations)
  disp(info.processing_operations{k});
endfor
```

Both clients use the common provider-owned Script Bridge. The module registers
its `api_id`, version, argument/result descriptors and callable operations;
Bridge discovery verifies the exact `module.ini` declaration. Scripts have
no access to the Tcl implementation's storage paths or private viewer state.

## Persistence and source ownership

All fields are written as strings using `DATASET_METADATA_API_v1` inside the
file-publication transaction. The implementation uses a namespaced metadata
layout currently beginning `curve_digitizer.image_processing.` and indexed
`operation.N.kind`/`operation.N.value` keys. This is **not** a consumer contract:
callers must use `read`/`operations`/`lineage`. Changes to internal storage may
be implemented later without altering public operation semantics.

## Security and compatibility

ImageMagick is selected from CORE's `runtime.magick` preference via
`runtimeToolStatus magick`. Only allowlisted command arguments are accepted;
no shell or user-entered ImageMagick expression is executed. A missing runtime
disables enhancement/publication without disabling curve digitization.
The output PNG is staged into a host-created temporary file, checked and
published through `datasetFilePublicationPublish`. The stage is deleted after
success or error. CORE assigns the producer namespace and prevents the viewer
from overwriting an unrelated Dataset.
