# Peak Detection Session Generator

Portable GX-TXT Session Generator API v1 package for `demo.numeric.peaks`.

```text
Library: GX-TXT Numerical Examples
Generator ID: peak_detection
Name: Peak Detection
Category: Mathematics
Version: 1.0.0
```

The generated ordinary Session contains `raw/peak_detection_demo.csv` and `metadata/ground_truth.txt`. The CSV is deterministic and contains three separated Gaussian-like peaks centered on X = 20 s, 50 s and 78 s.

The normal demo plugin consumes only the imported Canonical Dataset. It does not read the generator-private ground-truth file.

License: GNU GPL v3 or later.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
