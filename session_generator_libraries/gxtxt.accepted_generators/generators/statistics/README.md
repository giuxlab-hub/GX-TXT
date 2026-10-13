# Statistics Session Generator

Portable GX-TXT Session Generator API v1 package for `demo.numeric.statistics`.

```text
Library: GX-TXT Numerical Examples
Generator ID: statistics
Name: Statistics
Category: Mathematics
Version: 1.0.0
```

The generated ordinary Session contains `raw/statistics_demo.csv`, a canonical numeric Dataset, and `metadata/ground_truth.txt`. The raw CSV retains three missing-value markers (`NA`, `missing`, and `invalid`); the canonical Dataset maps those three markers to `NaN` and retains one zero-weight finite observation. This demonstrates the public non-finite and weight policies without relying on Tcl parsing of literal infinity tokens.

The `weight` column is an explicit statistical weight. It is not a measurement-uncertainty column.

The generated Session does not depend on this package after creation.

License: GNU GPL v3 or later.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
