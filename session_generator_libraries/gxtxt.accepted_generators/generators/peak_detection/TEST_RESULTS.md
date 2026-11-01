# Test Results

## 1.0.0 — 2026-09-24

- PASS: package contains a valid Session Generator API v1 descriptor.
- PASS: generator output is deterministic across repeated runs.
- PASS: generated CSV has 101 rows plus header and columns `sample`, `x_s`, `signal_V`.
- PASS: source construction has intended analytical centers X = 20, 50 and 78.
- PASS: no random input is used.
- PASS: ground truth is separate from the normal plugin/Dataset interface.

## 1.0.1 — Task 007

- PASS — public Generator Library import, clean generation, open/save/reopen, canonical Dataset and persisted Analysis configuration.
- PASS — real Tk Analysis execution, save/reopen/rerun, HTML export, and rendered graph inspection.
- PASS — independent source hash, canonical shape and scientific/structural oracle in `validation/gxtxt-0.9.8.10-dev-007-full-regression-generator-viewer-audit/broad_agent/numerical_science_results.tsv`.
