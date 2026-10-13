# GX-TXT `analysis.cepstrum`

`analysis.cepstrum` is a Dataset-native real-cepstrum analysis plugin for GX-TXT.

It consumes a normal uniformly sampled `timeseries.table`, computes the real cepstrum, publishes a reusable quefrency-domain Dataset, estimates the dominant periodicity inside an explicit search interval, and renders the result through the shared GX-TXT graph infrastructure.

The plugin is intentionally separate from `analysis.fft_spectrum`: the FFT module publishes conventional frequency-domain spectra and established THD/SFDR/SINAD/ENOB metrics, while this plugin addresses periodic structure in the log-magnitude spectrum.

See `MANUAL.md` for the scientific definition and workflow.


## Shared numerical and graphics services

Version 1.1.1 uses public `NUMERIC_API_v1` for grid validation, FFT, IFFT, detrending, reusable analysis-window generation and polynomial peak refinement. The numerical service is resolved from public dependency metadata injected into the Standard Module runtime configuration; the module does not depend on the physical `math.numeric` installation path. The module retains only cepstrum-specific logarithmic-spectrum, quefrency and peak-interpretation semantics. Scientific result graphics use persistent `plot.dataset` / `PLOT_DATASET_API_v2`.
