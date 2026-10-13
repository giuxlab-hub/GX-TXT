# Cepstrum Analysis 1.1.1

## Purpose

The module computes the **real cepstrum** of one uniformly sampled signal and exposes the result as normal GX-TXT data.

For a windowed signal `x[n]`, the implemented definition is:

```text
c[n] = real(IFFT(log(max(abs(FFT(x[n] w[n])), magnitude_floor))))
```

The horizontal coordinate is **quefrency** in seconds. A periodic harmonic spacing in the spectrum can produce a cepstral peak near the corresponding time period.

## Input

- Contract: `timeseries.table`
- Independent binding: a time-compatible variable
- Signal binding: one measured numeric variable

The current release requires uniform sampling. Explicit time coordinates are accepted when their interval is uniform within the runtime tolerance.

## Configuration

- Analysis window: rectangular, Hann, Hamming, Blackman-Harris, or flat-top
- Detrend: none, mean, or linear
- Log-magnitude floor in dB relative to the spectral maximum
- Minimum and maximum fundamental search frequency
- Output Dataset ID

The frequency search range is converted to the equivalent positive-quefrency range. The strongest cepstral peak inside that range is reported as the dominant periodicity.

## Output

The derived `table.generic` Dataset contains:

```text
quefrency_s
real_cepstrum
```

The module also writes:

```text
cepstrum_metrics.ini
cepstrum_report.txt
render_cache.mat
01_real_cepstrum.png
```

Graph variants use the cached scientific result and do not rerun the transform.

## Interpretation

A detected cepstral peak is evidence of periodic structure in the log-magnitude spectrum; it is not automatically proof of a unique physical fundamental. Peaks may also occur at multiples of the fundamental period. The configured search interval therefore remains part of the scientific method and is stored in the report/provenance.

The zero-quefrency term depends strongly on absolute amplitude scaling and the logarithm convention. Non-zero quefrency structure is the main scientific output.

## Relationship to other GX-TXT modules

- `analysis.fft_spectrum`: conventional single-signal spectrum and established spectral metrics
- `analysis.time_dependent_fft`: time-dependent FFT/STFT-style analysis
- `analysis.welch_spectrum`: averaged spectrum/PSD
- `analysis.cross_spectral_transfer`: transfer/coherence analysis
- `analysis.fractional_octave_spectrum`: fractional-octave band integration
- `analysis.harmonic_analysis`: explicit integer-harmonic table and THD from an existing spectrum
- `analysis.cepstrum`: periodicity in log-spectral structure

## Limitations

Version 1.1.1 implements the real cepstrum only. Complex cepstrum, phase unwrapping, minimum-phase reconstruction, speech-specific pitch tracking, and time-varying cepstral analysis are outside this release.

## Public GX-TXT APIs used

Analysis Source Map, Dataset Variable Schema, Table Stream, Dataset Publication v2, Progress, Graph Provider, Plot Module, Unit Registry, Plugin Install, Session Generator Library, and Documentation APIs.


## Shared numerical and graphics services

Version 1.1.1 uses public `NUMERIC_API_v1` for grid validation, FFT, IFFT, detrending, reusable analysis-window generation and polynomial peak refinement. The numerical service is resolved from public dependency metadata injected into the Standard Module runtime configuration; the module does not depend on the physical `math.numeric` installation path. The module retains only cepstrum-specific logarithmic-spectrum, quefrency and peak-interpretation semantics. Scientific result graphics use persistent `plot.dataset` / `PLOT_DATASET_API_v2`.
