# IR Spectroscopy and Reference Matching

`analysis.spectroscopy.ir` is a production GX-TXT analysis module for Dataset-native infrared preprocessing, peak extraction, transparent reference matching and persistent result visualization.

The module consumes stable `dataset_id + variable_id` bindings and preserves the source Dataset. The expected primary coordinate is wavenumber in `cm^-1`, either ascending or descending. The measured ordinate must be explicitly interpreted as absorbance, absorption index, transmittance fraction, percent transmittance, or relative transmission signal.

## Numerical architecture

Version 1.1.1 follows the mandatory GX-TXT `math.numeric` / `analysis.*` boundary. Generic reusable mathematics is obtained through the public `NUMERIC_API_v1`; the module does not own private replacements for those primitives. It currently uses public numerical services for:

- monotonic-grid validation;
- descriptive reductions used during conversion;
- baseline estimation;
- smoothing;
- differentiation;
- vector normalization;
- vector similarity;
- common-range calculation;
- uniform-grid generation;
- resampling;
- peak detection.

IR-specific scientific semantics remain in this module: ordinate interpretation, fingerprint weighting, peak-overlap scoring, reference-library compatibility, ranking thresholds, candidate warnings and report/provenance decisions.

## Graphics

Scientific result graphics use the public `plot.dataset` / `PLOT_DATASET_API_v2` path. The module publishes a plot-ready overlay Dataset and creates a persistent `plot.dataset` variant. The conventional IR wavenumber orientation is represented by the shared `axis_direction=reverse` capability, not by a module-private renderer. Standard plot.dataset legend, axes, range, scaling, persistence, save/reopen and rerender behavior therefore remain available.

The generated `01_ir_overlay.png` is a copy of the current `plot.dataset` provider artifact for convenient module output; `automatic_graphs.ini` records the persistent graph/variant identity.

## Outputs

The analysis publishes processed-spectrum, detected-peaks, ranked-candidates and plot-overlay Session Datasets, plus `ir_analysis_report.txt`, `01_ir_overlay.png` and `automatic_graphs.ini`. Scores are similarity measures, not calibrated probabilities. A weak top score is reported as `no convincing library match`. Version 1.1.1 assumes one dominant component and does not deconvolve mixtures.

The comparison grid, baseline, smoothing, normalization, derivative, scoring method, fingerprint region, peak tolerance and top-N are explicit settings. Method/phase differences remain warnings rather than suppressed metadata. Reference spectra are never destructively regridded in their libraries.

## Public GX-TXT APIs used

- `NUMERIC_API_v1`
- `PLOT_DATASET_API_v2`
- `DATASET_PUBLICATION_API_v2`
- `SCIENTIFIC_SPECTRUM_API_v1`
- `SCIENTIFIC_REFERENCE_LIBRARY_API_v1`

License: GNU GPL v3 or later.
