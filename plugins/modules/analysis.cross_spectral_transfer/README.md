# Cross-Spectral & Transfer Function Analysis

`analysis.cross_spectral_transfer` is an external GX-TXT analysis plugin for estimating the frequency-domain relationship between two synchronously sampled signals in one canonical Dataset.

The module consumes:

- one time / temporal variable;
- one input signal `X`;
- one output signal `Y`;
- one existing GX-TXT Temporal `window_set`.

It averages one-sided auto/cross spectral estimates over the resolved windows and publishes a canonical `spectrum.table` containing `Sxx`, `Syy`, complex `Sxy`, H1/H2 transfer functions, gain/phase quantities and magnitude-squared coherence.

Scientific convention:

```text
Sxy = mean(conj(X) * Y)
H1  = Sxy / Sxx
H2  = Syy / conj(Sxy)
coherence = |Sxy|^2 / (Sxx * Syy)
```

The module uses GX-TXT public APIs only: Analysis Source, Temporal Set, Table Stream v3, Parallel Execution v1, Dataset Publication v2 / Storage Auto, persistent `plot.dataset` variants and Graph Provider / Plot Module variants.

Minimum framework: **GX-TXT 0.9.7.82**.

See `MANUAL.md` for the complete scientific and operational guide.


## Numerical service architecture

Version 1.1.2 obtains generic FFT, frequency-grid construction, one-sided transform selection, detrending and reusable windows through public `NUMERIC_API_v1`. The service is resolved from public dependency metadata in the Standard Module runtime configuration, not from a hard-coded module path. Cross-spectrum construction, H1/H2/coherence definitions, PSD normalization and transfer-function semantics remain in this module. The corrected parallel worker was validated on a generated 12-window transfer experiment.
