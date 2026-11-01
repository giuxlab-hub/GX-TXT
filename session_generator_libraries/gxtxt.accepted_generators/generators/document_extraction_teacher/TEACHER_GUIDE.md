# Teacher demonstration: document extraction

This private generator supplies two authentic PDF test cases. The separately provided executed DEMO Sessions contain OCR and table results, source images, Dataset notes and offline HTML.

## Scanned technical paper

1. Import `raw/middlebrook_loop_gain.pdf` as a `document.pdf` Dataset.
2. Open **Document Extractors** and preview page 10 with CORE OCR. Compare the recognized words with the original page image.
3. The pretested page yields 395 positioned words and the phrase “loop gain.” Verify equations, subscripts and circuit diagrams manually; OCR is a transcription aid.

The supplied Middlebrook paper is authorized only for this private teacher demonstration. Its redistribution rights were not established. Remove it from any later public package.

## Climatic tables

1. Import `raw/climate_tables.pdf` as a `document.pdf` Dataset.
2. Preview page 2 in the Table Extractor viewer. CORE detects three stacked 11×14 tables.
3. Check title, month headers, city names, January and annual values against the source image.
4. Export each reconstructed table, normalize the decimal comma where needed, and import normalized results as `table.generic` Datasets.

The executed climatic-table DEMO publishes three separate nine-row numeric Datasets and preserves the raw matrices.
