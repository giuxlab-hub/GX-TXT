# Changelog

## 1.0.2

- Corrected stale package tests for the current numerical framework.

## 1.0.1

- Publish `root_x` with the standard independent X role so the public plot.dataset graph can combine source and root-marker series.
- Place the focused Octave test callback in its own file so the real GNU Octave runner resolves it correctly.

## 1.0.0

- Initial `demo.numeric.root_finding` reference plugin for GX-TXT 0.9.7.86.
- Added stable X/Y Analysis Source bindings and optional X-range Dataset Selection.
- Composed public `NUMERIC_API_v1 dataset_interpolate` with callback-based `root_find` for explicit user brackets.
- Added configurable public interpolation method, non-finite policy, root tolerance and maximum iterations.
- Added Canonical root-result Dataset Publication with solver diagnostics and scientific units.
- Added `root_finding_report.txt` and metrics output.
- Added automatic source/zero-line/root visualization through the public `standard_octave` bridge to `PLOT_DATASET_API_v2`.
- Added portable deterministic Root Finding Session Generator and focused validation suites.
