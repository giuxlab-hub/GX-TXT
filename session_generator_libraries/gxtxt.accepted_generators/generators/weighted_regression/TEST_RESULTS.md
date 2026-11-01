# Test Results — Weighted Regression Session Generator 1.0.0

Reference framework: `GX-TXT 0.9.7.72`

Validation was performed with the real Session Generator API v1 package/import/generation path.

```text
PASS generator descriptor/package validation
PASS import into GX-TXT Numerical Examples
PASS discovery as Mathematics / Weighted Regression
PASS generation of an independent GX-TXT Session
PASS weighted linear CSV generation
PASS weighted cubic CSV generation
PASS ground-truth sidecar generation
PASS second independent Session generation
PASS byte-for-byte deterministic repeat generation
```

Canonical generated CSV SHA-256 values:

```text
weighted_linear_regression.csv
93ca088a59c9a7458645b3556ea147ee9e1f9174c2fe5ad5e9bbafa43041eed3

weighted_polynomial_fitting.csv
84d9224e8094f2d8a2bbb78b21b8ba48edf6877fd16a830cf219b8af4374be20
```

The generator does not install or modify GX-TXT framework files. Its metadata sidecars are documentation/import material; `demo.numeric.regression` does not read them directly.

## 1.0.1 — Task 007

- PASS — public Generator Library import, clean generation, open/save/reopen, canonical Dataset and persisted Analysis configuration.
- PASS — real Tk Analysis execution, save/reopen/rerun, HTML export, and rendered graph inspection.
- PASS — independent source hash, canonical shape and scientific/structural oracle in `validation/gxtxt-0.9.8.10-dev-007-full-regression-generator-viewer-audit/broad_agent/numerical_science_results.tsv`.
