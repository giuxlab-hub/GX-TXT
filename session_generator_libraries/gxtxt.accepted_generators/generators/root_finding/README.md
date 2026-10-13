# GX-TXT Numerical Examples — Root Finding

Portable Session Generator for the `demo.numeric.root_finding` reference plugin.

- Library: `GX-TXT Numerical Examples`
- Category: `Mathematics`
- Generator: `Root Finding`
- Generator ID: `root_finding`
- Version: `1.0.0`

The generator creates `raw/root_finding.csv` with columns `x` and `f`, where

```text
f(x) = (x + 2) * (x - 0.5) * (x - 3)
```

on a deterministic grid from -4 to +4 with step 0.05. The exact simple roots are -2, 0.5 and 3.

`metadata/ground_truth.txt` is for tests and human inspection only. The demo plugin must consume the imported Canonical Dataset and must not read this file during analysis.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
