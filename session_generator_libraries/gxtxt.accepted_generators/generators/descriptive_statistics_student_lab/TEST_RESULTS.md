# Test Results — Descriptive Statistics Student Lab 1.0.0

Date: 2026-09-24

Baseline: GX-TXT 0.9.7.86.

## PASS

- Python source compiles successfully.
- Standalone deterministic Session generation succeeds.
- Session Generator API v1 imports the single-generator ZIP into the standard Numerical Examples library.
- Generated Session contains the Canonical Dataset, Variable Schema v3, X-range Dataset Selection, stable Repeatable Config bindings, preselected `analysis.statistics.descriptive` run, generator provenance, deterministic ground truth and `STUDENT_GUIDE.txt`.
- Teaching data include compatible `V`/`mV`, incompatible `A`, constant/signed/single/two-value cases, `NaN`, `+Inf` and `-Inf` observations.

## SKIP in this build environment

- Running the generated Session through the production module requires GNU Octave, which is not installed in this build container. That runtime path is therefore not reported as PASS.
