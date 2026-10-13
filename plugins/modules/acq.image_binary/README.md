# acq.image_binary

GX-TXT CORE module for importing binary raster image files.

## Features

- Imports PNG, JPEG, BMP and TIFF as opaque `image.raster` binary Datasets.
- Detects the format from content signatures rather than trusting the filename extension.
- Re-validates the framework-owned RAW snapshot during import and keeps RAW bytes authoritative.
- Publishes persistent structured metadata through Dataset Metadata API v1 using the Acquisition Handler `structured_metadata` transfer contract.
- Reads technical metadata such as dimensions, mode, bands, frame count, alpha and DPI when available.
- Reads available EXIF/TIFF tags, PNG textual metadata, IPTC fields, XMP packet data and selected container information.
- Preserves common image fields with convenient aliases such as camera make/model, capture date, orientation, software, exposure, ISO and lens information when present.
- Does not store opaque binary ICC/EXIF/Photoshop profile payloads in Dataset Metadata; only their sizes are recorded where useful.
- Does not intentionally decode image pixel arrays. The canonical Dataset remains the original opaque image bytes.
- Extended metadata extraction is fail-soft: if Python/Pillow is unavailable or a metadata parser rejects a file, signature-based import still works and basic source/format metadata is retained.
- No Tk dependency; the acquisition handler remains host-independent.

## Runtime dependency for extended metadata

Extended metadata extraction uses the module-owned `runtime/image_metadata.py` helper and requires Python 3 (or Python) with Pillow. The GX-TXT server environment already used for image/PDF processing provides Pillow. The core binary import path itself does not require Pillow.

## Persistent metadata examples

Typical keys include:

```text
source.original_filename
source.file_size_bytes
image.format
image.media_type
image.width_px
image.height_px
image.mode
image.camera_make
image.camera_model
image.datetime_original
image.orientation
image.exif.root.271_make
image.exif.exif.36867_datetimeoriginal
image.text.title
image.iptc.caption
image.xmp.packet
```

Unknown or format-specific fields remain namespaced metadata; CORE does not interpret their semantics.

## License

SPDX-License-Identifier: GPL-3.0-or-later
