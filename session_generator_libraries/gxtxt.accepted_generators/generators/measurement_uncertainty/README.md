# GX-TXT Numerical Examples — Measurement Uncertainty

Portable Session Generator for the `demo.numeric.uncertainty` reference plugin.

It creates `raw/measurement_uncertainty_demo.csv` with five deterministic voltage measurements, their measurement standard uncertainties, and a separately labelled explicit inverse-variance reference-weight column. The plugin consumes the generated canonical Dataset; it does not read generator-private ground truth.

The weight column is generated explicitly as `1/sigma^2` for demonstration and validation. This conversion is deliberately performed by the generator, not silently by the analysis plugin.

License: GNU GPL v3 or later.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
