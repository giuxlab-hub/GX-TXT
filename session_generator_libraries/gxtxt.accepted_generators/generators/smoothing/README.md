# Smoothing Session Generator

This is a portable GX-TXT Session Generator API v1 package for the external
`demo.numeric.smoothing` numerical demonstration plugin.

Canonical destination library:

```text
GX-TXT Numerical Examples
```

Generator identity:

```text
Generator ID: smoothing
Name: Smoothing
Category: Mathematics
Version: 1.0.0
```

Import it from the GX-TXT `New Session` dialog by opening `Generate Session...`,
then `Manage Libraries...`, selecting `GX-TXT Numerical Examples`, and using
`Import Generator...`.

The generator creates an ordinary independent GX-TXT Session containing:

```text
raw/smoothing_demo.csv
metadata/ground_truth.txt
```

The CSV contains 501 uniformly spaced samples with columns:

```text
time_s
reference_V
measured_V
```

The reference signal, deterministic seeded Gaussian noise and three fixed
measurement spikes match the canonical data used by `demo.numeric.smoothing`.
The generated Session does not depend on this generator package after creation.

License: GNU GPL v3 or later.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
