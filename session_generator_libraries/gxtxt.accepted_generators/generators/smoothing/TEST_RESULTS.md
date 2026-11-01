# Test Results — Smoothing Session Generator 1.0.0

Reference framework: `GX-TXT 0.9.7.72`

Validation date: 2026-09-23

The portable generator package was imported through Session Generator Library
API v1 into the installed `GX-TXT Numerical Examples` library in an isolated
GX-TXT user profile.

Executed validation:

```text
PASS generator package import
PASS generator ID/name/category/version/type discovery
PASS generation of two independent ordinary GX-TXT Sessions
PASS required Session directory structure
PASS raw/smoothing_demo.csv creation
PASS metadata/ground_truth.txt creation
PASS metadata/session_generator.ini provenance creation
PASS byte-identical repeat generation
PASS generated CSV matches the canonical demo.numeric.smoothing example
```

Canonical generated CSV SHA-256:

```text
cb2ec3a7cd62cfd026be0dc31ee975479da697224978d023d9cea6a56a20ebd2
```

The generated Session remains independent of the generator package after
creation, as required by Session Generator Library API v1.

## 1.0.1 — Task 007

- PASS — public Generator Library import, clean generation, open/save/reopen, canonical Dataset and persisted Analysis configuration.
- PASS — real Tk Analysis execution, save/reopen/rerun, HTML export, and rendered graph inspection.
- PASS — independent source hash, canonical shape and scientific/structural oracle in `validation/gxtxt-0.9.8.10-dev-007-full-regression-generator-viewer-audit/broad_agent/numerical_science_results.tsv`.
