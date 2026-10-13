# Fractional-Octave PSD Session Generator

Creates a deterministic linear PSD from 0 to 4096 Hz with 1 Hz spacing, a known white PSD floor, and known line powers at 125, 500 and 2000 Hz. Intended for `analysis.fractional_octave_spectrum`.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.
