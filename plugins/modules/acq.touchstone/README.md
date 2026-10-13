# Touchstone network acquisition

Imports measured `.sNp` S-parameter files (1–32 ports) through the normal acquisition handler. Touchstone v1 `RI`, `MA`, and `DB` data and Hz/kHz/MHz/GHz units are converted to a canonical `spectrum.table` with `frequency_Hz`, `sij_real`, and `sij_imag` variables. Port order follows Touchstone column-major order. The source reference impedance is retained in Dataset provenance. Touchstone 2 keyword records are diagnosed as unsupported.
