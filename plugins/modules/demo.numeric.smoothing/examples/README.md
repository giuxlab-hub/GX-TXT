# Deterministic smoothing example

`smoothing_demo.csv` is the byte-identical reference copy of the scientific data
created by the portable `Smoothing` Session Generator supplied with this plugin.

Columns:

```text
time_s,reference_V,measured_V
```

The file contains 501 samples from 0 to 10 s at 0.02 s spacing. The clean signal
and deterministic measurement noise are generated with random seed 1974.
`generate_smoothing_demo.py` is a standalone reproduction helper; the canonical
GUI workflow uses the importable Session Generator package documented in
`../MANUAL.md`.
