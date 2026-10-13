# acq.xas

GX-TXT Acquisition Handler for X-ray absorption spectroscopy (XAS) text data.

It supports:

- processed single spectra: `Energy + mu(E)`;
- processed families: `Energy + mu_1(E) + ... + mu_N(E)`;
- raw transmission: `mu(E) = ln(abs(sum(numerator)/sum(denominator)))`;
- raw fluorescence/ratio: `mu(E) = sum(numerator)/sum(denominator)`.

External text parsing uses `TABULAR_TEXT_API_v1`. Raw reusable vector arithmetic
uses `NUMERIC_API_v1`. Canonical Dataset registration, stable variable IDs,
metadata, RAW preservation and rollback remain CORE-owned.

For a processed family without experimental family metadata, the first release
uses `spectrum_index = 1..N` as the explicit provisional family coordinate.
Physical time, phase, temperature or other experiment metadata must not be
invented.
