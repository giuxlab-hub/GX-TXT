# UV/Vis Spectral Family Quantitation

`analysis.spectroscopy.uvvis` 1.2.0 is a Dataset-native GX-TXT production analysis module for selected-wavelength quantitation from a canonical `spectrum.family`.

## Architecture

This module follows [the framework architecture overview](../../../ARCHITECTURE.md).

- `math.numeric` / `NUMERIC_API_v1` owns reusable mathematics such as regression, interpolation/resampling and peak detection.
- this module owns UV/Vis scientific workflow and semantics: selected analytical wavelength, absorbance blank subtraction, calibration/holdout roles, inverse concentration prediction, lambda-max suggestion, validity warnings, reporting and provenance.
- all scientific result graphics use persistent `plot.dataset` / `PLOT_DATASET_API_v2` variants.

No private renderer, rerenderer or plotting cache is part of the module.

## Inputs

Primary source: one `spectrum.family` Dataset containing absorbance spectra with wavelength in nm and concentration-like family parameter values.

Optional sources:

- blank `spectrum.scientific` for explicit absorbance subtraction;
- independent unknown `spectrum.scientific` for prediction.

## Configuration

- analytical wavelength [nm];
- semicolon-separated held-out member IDs;
- blank correction mode;
- peak-search wavelength interval.

Held-out members are not calibration standards. The module never silently relabels family members.

## Numerical services

The module consumes public NUMERIC_API capabilities for:

- linear regression;
- interpolation;
- resampling;
- descriptive statistics where generic reductions are required;
- peak detection.

The module does not implement private copies of these algorithms.

## Outputs

Machine-readable derived Datasets include selected responses, calibration results, residuals, held-out validation, optional unknown prediction and lambda-max information. When blank subtraction is active, a derived blank-corrected family Dataset is also published because the scientific values have changed.

The original family and optional source spectra remain unchanged.

## Automatic graphs

Three persistent `plot.dataset` variants are created:

1. full spectral-family overlay with the analytical wavelength marked by a reference line;
2. calibration/validation graph with standards, fitted regression, held-out observations and optional independent unknown;
3. calibration residuals with a zero-reference line and symmetric residual range.

The family overlay uses public numeric 2-D family grouping on the canonical `parameter_value` variable. It does not duplicate each source curve into a private plotting format.

## Interpretation

A high R-squared value alone does not establish selectivity, matrix compatibility or validity outside the calibration range. Held-out and unknown results are reported explicitly. Prediction intervals are not asserted unless a future documented workflow adds them through an appropriate public numerical/statistical service.

## Public GX-TXT APIs used

- `SPECTRAL_FAMILY_API_v1`
- `SCIENTIFIC_SPECTRUM_API_v1`
- `NUMERIC_API_v1`
- `DATASET_PUBLICATION_API_v2`
- `PLOT_DATASET_API_v2`
