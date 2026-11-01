# Test Results — Statistics Session Generator 1.0.0

Reference framework: `GX-TXT 0.9.7.82`  
Validation date: 2026-09-24

- PASS — package import through Session Generator Library API v1.
- PASS — identity `GX-TXT Numerical Examples / Mathematics / Statistics`.
- PASS — repeated generation produces byte-identical `raw/statistics_demo.csv`.
- PASS — normal Session structure and generator provenance are produced.
- PASS — generated CSV imports through normal GX-TXT Acquisition as a Canonical `table.generic` Dataset.
- PASS — independent reference calculations verify the deterministic descriptive, quantile and weighted-statistics ground truth.

The analysis plugin does not read `metadata/ground_truth.txt` during normal operation.

## 1.0.1 — Task 007

- PASS — public Generator Library import, clean generation, open/save/reopen, canonical Dataset and persisted Analysis configuration.
- PASS — real Tk Analysis execution, save/reopen/rerun, HTML export, and rendered graph inspection.
- PASS — independent source hash, canonical shape and scientific/structural oracle in `validation/gxtxt-0.9.8.10-dev-007-full-regression-generator-viewer-audit/broad_agent/numerical_science_results.tsv`.
