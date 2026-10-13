# Changelog

## 1.0.1

- Read descriptor settings from the public Acquisition Handler inspect/import
  request. Preview and import use the same config without private CORE state.
- Retain the original canonical spectrum/family schema and source provenance.

## 1.0.0

- Added processed XAS single-spectrum and spectral-family import.
- Added raw transmission and fluorescence/ratio construction using
  `NUMERIC_API_v1`.
- Added stable Dataset Variable Schema v3 identities through the public
  Acquisition Handler `variable_schema` extension.
- Added explicit energy-unit and non-finite policies.
