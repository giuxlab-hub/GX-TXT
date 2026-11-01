# Test Results

- PASS — deterministic generation from repeated runs.
- PASS — generated schema is exactly `x,f`.
- PASS — analytical reference minimum is `x=1.75`, `f=2`.
- PASS — generator contains no random input and no plugin-private data dependency.

Runtime integration is validated by the companion `demo.numeric.minimization` package test suite.

## 1.0.1 — Task 007

- PASS — public Generator Library import, clean generation, open/save/reopen, canonical Dataset and persisted Analysis configuration.
- PASS — real Tk Analysis execution, save/reopen/rerun, HTML export, and rendered graph inspection.
- PASS — independent source hash, canonical shape and scientific/structural oracle in `validation/gxtxt-0.9.8.10-dev-007-full-regression-generator-viewer-audit/broad_agent/numerical_science_results.tsv`.
