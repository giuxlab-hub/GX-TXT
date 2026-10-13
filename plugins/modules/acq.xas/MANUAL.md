# XAS spectra import — Manual

## Scientific scope

`acq.xas` imports XAS observations. It does not normalize spectra, determine
chemical states, perform EXAFS processing or run phase-sensitive detection.

## Source layouts

### Processed family

A wide table such as:

```text
Energy  mu_1  mu_2  ...  mu_N
```

is converted to canonical `spectrum.family` long form with stable variables
`member_id`, `parameter_value`, `spectral_x`, and `spectral_y`.

Until a physical family coordinate is known, `parameter_value` is the ordered
`spectrum_index` (unit `1`). Add experiment metadata later rather than inferring
time, phase, temperature or composition.

### Processed single spectrum

Select the Energy and `mu(E)` columns. The output contract is
`spectrum.scientific`.

### Raw transmission and fluorescence

Select one or more numerator and denominator columns by 1-based source-column
number. The module uses public `NUMERIC_API_v1` operations for detector sums,
division, absolute value and logarithm.

Transmission:

`mu(E) = ln(abs(sum(numerator) / sum(denominator)))`

Typical mapping is numerator `I0`, denominator `It`.

Fluorescence / explicit ratio:

`mu(E) = sum(numerator) / sum(denominator)`

Typical fluorescence mapping is numerator `If` detector channel(s), denominator
`I0`.

No detector dead-time correction is performed because no real source
format requiring it has yet been supplied.

## Energy units

Choose `eV` or `keV` explicitly when known. `auto` follows the practical
Athena/Demeter convention for an increasing edge scan: first energy above 100
is treated as eV, otherwise keV. Values are preserved in their source unit; the
normalization module performs any internal unit conversion through the public
Unit Registry helpers.

## Invalid values

`error` rejects NaN/Inf immediately. `omit_samples` removes only affected
samples and records that policy. It never replaces an invalid sample with zero.

## Provenance

The framework preserves the RAW source snapshot. The module records source
layout, column selection, energy unit, raw formula and non-finite policy as
Dataset metadata/provenance.
