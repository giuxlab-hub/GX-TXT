# GX-TXT Session Generator — Welch PSD

Deterministic teaching fixture for `analysis.welch_spectrum`.

The generator creates a 32 s, 1024 Hz Dataset containing a clean two-tone signal and a noisy measured signal. The expected spectral frequencies, signal powers, white-noise level and recommended Temporal Window Set are written to `metadata/welch_psd_ground_truth.txt`.

Generator ID: `welch_psd`  
Suggested Session: `welch-psd-example`  
Library: GX-TXT Numerical Examples  
Category: Signal Processing

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
