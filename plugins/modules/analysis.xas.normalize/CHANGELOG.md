# Changelog

## 1.0.2

- Correct two Octave stream cleanup blocks to use matching `unwind_protect` syntax.

## 1.0.1

- Correct the standard Octave runner path to the framework-relative module path used by GX-TXT 0.9.8.10.
- Keep all normalization mathematics on public NUMERIC_API_v1.

## 1.0.0

- Added Dataset-native single-spectrum and family normalization.
- Added automatic/manual E0, adaptive pre/post-edge ranges, edge-step
  normalization and optional flattening.
- All reusable numerical operations use `NUMERIC_API_v1`.
- Added explicit per-member diagnostics and failure policy.
