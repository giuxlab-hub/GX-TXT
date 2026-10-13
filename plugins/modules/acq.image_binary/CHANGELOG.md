# Changelog

## [1.2.0]
- Added persistent structured image metadata through Acquisition Handler Plugin API v1 and Dataset Metadata API v1.
- Added module-owned Pillow metadata helper for technical image/container fields plus EXIF/TIFF, PNG text, IPTC and XMP metadata.
- Added convenient aliases for common photographic fields while retaining raw namespaced tag identity.
- Metadata is extracted from the framework-owned RAW snapshot used for canonical import.
- Kept signature-based import authoritative and fail-soft when extended metadata extraction is unavailable.
- Kept image pixels opaque; no scientific image analysis or intentional pixel-array decoding was added.

## [1.1.0]
- Promoted to v0.9.6 CORE standards.
- Changed recognition to strictly use magic numbers (PNG, JPEG, BMP, TIFF) instead of file extensions.
- Implemented `variable_mapping=none` API.
- `import_proc` now securely copies from framework-owned `raw_path` and re-verifies signatures.
- Implemented explicit Preview Descriptor API metadata.
- Normalizes dataset canonical extension based on detected magic number.
- Added `plugin-package.ini` and a test suite.
- Added SPDX-License-Identifier tags.
