<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# TODO — analysis.fft_spectrum

## Deliberate scope

- No renderer: `plot.dataset` owns visualization.
- No STFT/spectrogram code: time-varying analysis is handled by the separate
  `analysis.spectrogram` module.
- No private HDF5/CSV reader or materialization path: canonical access belongs
  to CORE.
- No private selection/ROI/window implementation: Dataset Selection API v1 and Temporal Set API v1 own source-region semantics.
- No uncertainty propagation for THD/SFDR yet.
- No PSD mode yet.
- No Welch/averaged spectra yet; Temporal Set mode still computes independent ordinary FFT frames rather than a Welch or spectrogram product.
- No interpolated sub-bin fundamental estimator yet.

## Possible future additions

- PSD output as another canonical dependent variable.
- Welch/averaged global spectra, if a real workflow requires them.
- Optional sub-bin fundamental interpolation.
- Coherent-sampling diagnostics.
