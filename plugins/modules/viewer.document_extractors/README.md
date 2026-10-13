# GX-TXT Document Extraction Viewers

This plugin provides two Dataset-native Viewer Providers:

- **Generic OCR**
- **Table Extractor**

Both accept canonical `image.raster` and `document.pdf` Datasets. They never open arbitrary source files.

Source inspection uses the existing CORE `Dataset Preview API v1`. OCR/layout work is delegated to `OCR_LAYOUT_API_v1`; table reconstruction is delegated to `TABLE_EXTRACTOR_API_v1`.

The viewers add only interaction and publication:

- normalized ROI selection over the preview;
- page/method/language/PSM/DPI controls;
- OCR text preview and `document.text` publication;
- table preview, cell correction and `table.generic` publication.

No private Tesseract, Poppler or table-reconstruction implementation is present in this plugin.
