# GX-TXT PDF OCR Viewer

`viewer.pdf_ocr` is a GX-TXT Viewer plugin for page inspection, rectangular crop extraction and OCR of canonical `document.pdf` Datasets.

It is a GX-TXT workflow, not a packaged copy of the standalone PDFLab Crop & OCR utility. The source PDF is selected from the current Session, persistent interactive state is stored through Interactive Document API v1, and useful outputs are published as normal Canonical Datasets through Dataset File Publication API v1.

## Dataset workflow

```text
document.pdf Dataset
        ↓
PDF OCR Viewer
        ↓
page rendering / navigation / zoom / pan / ROI
        ├──→ image.raster Dataset
        ├──→ document.text Dataset
        └──→ derived document.pdf Dataset
```

The source PDF is never rewritten.

## Main capabilities

- Session `document.pdf` Dataset selection;
- page navigation;
- 150/200/300/400/600 DPI rendering through Poppler;
- zoom centered on the pointer;
- scrollbar, keyboard and middle-button pan;
- source-pixel ROI coordinates independent from preview zoom;
- ROI create/move/resize with eight handles;
- PNG crop publication as `image.raster`;
- direct whole-page publication as `image.raster`;
- Tesseract OCR on the selected ROI;
- UTF-8 ROI OCR publication as `document.text`;
- real whole-page Tesseract OCR published as `document.text`;
- real whole-PDF Tesseract OCR published as one UTF-8 `document.text` Dataset;
- whole-document OCR with OCRmyPDF and publication as a derived `document.pdf`;
- dynamic Tesseract language discovery via `tesseract --list-langs`;
- multi-language OCR combinations such as `eng+ita`, `chi_sim+eng` or `jpn+eng` when the corresponding traineddata are installed;
- Session-persistent Viewer workspace state through Interactive Document API v1;
- source Dataset lineage and structured Dataset Metadata for all published outputs.

## GX-TXT requirements

Minimum framework: **GX-TXT 0.9.7.84**.

Public APIs used:

- Viewer Provider API v1;
- Interactive Document API v1;
- Dataset File Publication API v1;
- Dataset Metadata API v1;
- Session Inspection API v1;
- Contract Registry API v1;
- Plugin Install API v1.

The plugin defines `document.text`; it does not require a CORE change for text Datasets.

See `DEPENDENCIES.md` and `MANUAL.md` for system requirements and operation.
