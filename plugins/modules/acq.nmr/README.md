# NMR JCAMP-DX acquisition

Imports measured one-dimensional JCAMP-DX 6 NTUPLES spectra and raw FIDs with real and imaginary ASDF pages. The original JCAMP file is retained by the standard acquisition path. The canonical Dataset has `spectral_x` in chemical shift ppm and `spectral_y` in arbitrary intensity units. Source headers and explicit processing parameters are attached as `nmr.*` structured metadata.

For raw FIDs, the importer applies an exponential window, zero filling, complex Fourier transform and a user supplied zero-order phase. The defaults are 2 Hz, 4× and 0°. The user should inspect phase and chemical shift against known references. This importer does not infer a molecular assignment or silently phase correct. Two-dimensional JCAMP data are rejected.

The Python runtime needs NumPy. This module has no private graph rendering.

The public NUMERIC API's Octave `fft` accepts complex input, but its Tcl `fft` facade currently accepts real input only (see `NUMERIC_API_v1.md`, `fft` contract). Bruker FIDs have distinct real and imaginary channels, and discarding the imaginary channel changes phase and peak positions. The importer therefore performs its complex FFT inside its format worker with NumPy. Its window, zero filling, phase, dwell time, carrier and reference parameters are explicit metadata. Subsequent baseline, peak detection and integration use the public NUMERIC API.
