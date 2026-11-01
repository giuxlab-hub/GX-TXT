# 1.2.0 — DEV111-P035 candidate

Expose canonical ranked-reference outputs through the additive generic CORE
native Analysis form. Declare exact result columns/identity mapping and include
source SHA, full portable revision/schema hashes and result-role provenance.
Refuse a source changed during scientific work before publication. Existing
processing, matching, scores, units, source/output identities and public Numeric,
Publication and Plot owners remain unchanged. Independent acceptance pending.

## 1.1.2 — 2026-09-30

- Open standalone runtime Session through the supported Session API.

# Changelog

## 1.1.1 — GX-TXT 0.9.8.10-dev

- Aligned the module version after the GX-TXT 0.9.8.09 runtime correction; scientific behavior is unchanged in this stabilization block.

## 1.1.0 — 2026-09-25

- Migrated all generic vector normalization, vector similarity, common-grid construction and reusable reductions to public `NUMERIC_API_v1`.
- Removed the module-private scientific plot renderer, rerenderer and render cache.
- Published a plot-ready IR overlay Dataset and created the result as a persistent `plot.dataset` variant.
- Added shared reversed-axis usage through public `PLOT_DATASET_API_v2` `axis_direction`, preserving the conventional high-to-low wavenumber display without private axis code.
- Preserved IR-specific conversion, fingerprint weighting, peak-overlap, reference-library ranking, warnings and provenance semantics.


## 1.0.3 — 2026-09-24

- Pin each candidate to its exact reference-library version and content hash in the published ranking Dataset, report and output provenance, so later library updates cannot silently change historical interpretation.

## 1.0.2 — 2026-09-24

- Clarified the overlay legend as a top-ranked reference candidate, not an asserted identification; packaged the verified real-RefIMP workflow for the integrated release.

## 1.0.1 — 2026-09-24

- Made mean-centering explicit/default before unit-vector matching, avoiding shared positive baseline bias; kept unit-vector-only as a user choice.
- Ensured both nearly coincident overlay curves remain visible in headless GNU Octave and placed the legend outside the data area.
- Routed the Tcl analysis companion through a CORE bridge so the external plugin remains host-independent.

## 1.0.0 — 2026-09-24

- First Dataset-native IR spectroscopy and reference-matching consumer of the GX-TXT scientific Spectrum and Reference Library CORE APIs.

P035: consult registered reference Libraries through additive managed read
methods of the existing CORE Reference/Manager owners, including unchanged bulk
ranking. Retain real scientific and package versions separately, recheck Library
fingerprints before publication, and resolve exact stable Variable IDs (including
dots) without display-name aliases. No IR numerical algorithm change.

P035 reports per-Library declared population, actual bulk-scanned count and
actual exact-examined count separately. A top-N candidate count never stands
for the full reference population. Runtime diagnostics use the actual1.2.0
module version. Numeric preprocessing/ranking formulas remain unchanged.
