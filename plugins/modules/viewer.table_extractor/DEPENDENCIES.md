# Table Extractor Dependencies

## GX-TXT

Required framework baseline:

```text
GX-TXT >= 0.9.7.84
```

Required public facilities:

- Viewer Provider API v1
- Interactive Document API v1
- Session / Dataset inspection
- Contract Registry API v1
- Dataset Publication API v2
- Dataset Variable Schema API v3
- Dataset Metadata API v1
- Plugin Install API v1

The source Session must contain at least one Dataset satisfying:

```text
image.raster
```

or:

```text
document.pdf
```

## Python

Required:

- Python 3
- Tkinter
- Pillow

## Poppler

Required commands:

```text
pdfinfo
pdftoppm
pdftotext
```

`pdftotext` must support TSV positioned-text output (`-tsv`).

## Tesseract

Required:

```text
tesseract
```

The plugin discovers installed languages dynamically.

Additional language support is added by installing the corresponding Tesseract traineddata/language package. No plugin modification is required.

Typical Debian package naming is:

```text
tesseract-ocr-<language>
```

Examples include English, Italian, German, French, Japanese, Korean, Russian, Simplified Chinese and Traditional Chinese packages as provided by the installed Debian release.

## Not required

Table Extractor does not require:

- OCRmyPDF
- qpdf
- ImageMagick
- Ghostscript

Those tools may be useful elsewhere in a PDF workflow but are not part of this plugin's extraction path.
