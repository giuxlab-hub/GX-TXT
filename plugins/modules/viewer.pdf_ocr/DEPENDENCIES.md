# Dependencies

## Mandatory runtime dependencies

The plugin requires:

```text
Python 3
Python tkinter
Pillow
Poppler: pdfinfo + pdftoppm
Tesseract OCR
OCRmyPDF
qpdf
```

Typical Debian packages are:

```sh
apt install \
  python3 python3-tk python3-pil \
  poppler-utils \
  tesseract-ocr \
  ocrmypdf qpdf
```

The plugin does **not** require ImageMagick.

## Tesseract languages

OCR language support is not hard-coded in the plugin. At startup the desktop adapter executes:

```text
tesseract --list-langs
```

and presents the installed traineddata to the user.

Installing another Tesseract language package therefore extends the Viewer without changing plugin code.

Examples on Debian include:

```text
tesseract-ocr-eng       English
tesseract-ocr-ita       Italian
tesseract-ocr-deu       German
tesseract-ocr-fra       French
tesseract-ocr-spa       Spanish
tesseract-ocr-rus       Russian
tesseract-ocr-jpn       Japanese
tesseract-ocr-kor       Korean
tesseract-ocr-chi-sim   Simplified Chinese
tesseract-ocr-chi-tra   Traditional Chinese
```

Package availability and exact language identifiers should be verified on the target Debian release with `apt` and `tesseract --list-langs`.

Multiple installed languages can be selected together. The plugin passes them to Tesseract/OCRmyPDF using the standard `lang1+lang2+...` form.

## Dependency policy

Dependency checks occur only when the Viewer backend is activated. Module discovery remains headless and does not initialize Tk or execute OCR tools.

The plugin uses CORE `gxtxt.pdf_canvas` for its Tk page canvas
and Poppler renderer. The backend passes the installed CORE Python directory to
support external plugin installations. Ordinary PDF Dataset reading uses this
shared component without OCRmyPDF/Tesseract/qpdf activation requirements; the
specialized OCR actions retain their existing dependency requirements.
