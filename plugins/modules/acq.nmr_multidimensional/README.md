# Multidimensional NMRPipe acquisition

Import a **phase-corrected, real** 2-D or 3-D NMRPipe spectrum through the normal Acquisition page. Complex FIDs are intentionally rejected; process and phase them with NMRPipe or another trusted spectrometer workflow first. The importer preserves the exact selected source bytes in Session `raw/`, registers a binary `spectrum.nmr_multidimensional` Dataset, and records the canonical copy SHA-256 and source SHA-256. Enter the citation and rights in the import fields; the source is never assumed to have a particular license.

F1, F2 and F3 ppm coordinates, dimension shape, labels, nuclei and observed frequencies come from the NMRPipe header. `H` and `HN` map to `1H`, `N` to `15N`, and `CO`/`C`/`CA`/`CB` to `13C`; original header labels remain in metadata. The companion Multidimensional NMR Viewer handles contour and slice navigation.

The worker contains nmrglue 0.12 under its BSD-3-Clause terms in `runtime/vendor/`. NumPy and Matplotlib are required by the Python runtime.
