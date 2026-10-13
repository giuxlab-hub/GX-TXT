# NMR Spectrum Viewer

A dedicated 1-D NMR workbench shows nucleus, observed frequency, solvent, reference, source type and source SHA-256; numerical peak and integration tables appear after `analysis.spectroscopy.nmr`. It opens persistent Plot Dataset variants with the conventional reversed ppm axis by default. The direction can be changed explicitly. Compatible same-nucleus spectra can be overlaid. The standard Plot Dataset editor owns zoom, pan, graph appearance and export.

The viewer stores its selected Dataset, overlay, axis direction and graph variant in the Session's `metadata/nmr_spectrum_viewer.ini`. Its plots use only `PLOT_DATASET_API_v3`.

The window also opens before a Session is selected or when the current Session has no NMR spectrum. It displays a clear empty message and disables source-dependent controls. Open a compatible Session and reopen the viewer to populate the source selector. No state file is read or written without a Session.
