# GX-TXT Numerical Examples — Harmonic Analysis

Portable Session Generator for a coherent multi-harmonic waveform with analytical THD ground truth.

Import this package through the normal GX-TXT Session Generator Library UI/API. It creates the files needed for the student workflow; it does not install the Harmonic Analysis plugin itself.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.

For the complete exercise, run **FFT Spectrum** first to publish the spectrum Dataset, then select **Harmonic Analysis** or **Spectral Features** on the Run page and run again. Both stages, including save/reopen/rerun, were validated.
