# GX-TXT Numerical Examples — 1D Minimization

Portable Session Generator for `demo.numeric.minimization` 1.0.0.

It creates `raw/minimization_1d.csv` with deterministic columns `x,f` sampled from:

```text
f(x) = (x - 1.75)^2 + 2
```

on `[-3,5]` with step `0.05`. The exact reference minimum is `x=1.75`, `f=2`.

The generated Session already registers the CSV as a canonical `table.generic` Dataset. A human/test reference file is written to `metadata/ground_truth.txt`; the analysis plugin does not read it during normal execution.

SPDX-License-Identifier: GPL-3.0-or-later

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
