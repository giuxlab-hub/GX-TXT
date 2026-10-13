# demo.numeric.peaks 1.0.2

External GX-TXT demonstration/reference plugin for the public peak-analysis capabilities of `math.numeric` / `NUMERIC_API_v1` in GX-TXT 0.9.7.82.

The plugin demonstrates the normal Dataset-aware workflow:

```text
Canonical Dataset
→ Analysis Source X/Y bindings
→ NUMERIC_API_v1 dataset_find_peaks
→ published detected-peaks Dataset
→ peak_detection_report.txt
→ 01_peak_detection.png
```

It does not contain a private peak detector, prominence algorithm or width algorithm. It does not perform baseline correction, chromatographic integration, peak fitting, deconvolution or spectral assignment.

Install a `demo.numeric.peaks` 1.0.2 package through the normal GX-TXT Plugin Install interface/API. A portable `GX-TXT Numerical Examples → Mathematics → Peak Detection` Session Generator package is included under `session_generators/` and is also distributed separately.

License: GNU GPL v3 or later.
