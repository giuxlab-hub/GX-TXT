## 1.1.2

- Open standalone runtime Session through the supported Session API.

# Changelog

## 1.1.1 — GX-TXT 0.9.8.10-dev

- Aligned the module version after the GX-TXT 0.9.8.09 runtime correction; scientific behavior is unchanged in this stabilization block.

## 1.1.0

- Migrated all generic vector normalization, vector similarity, common-grid construction and reusable reductions to public `NUMERIC_API_v1`.
- Removed the module-private scientific plot renderer, rerenderer and render cache.
- Published a plot-ready IR overlay Dataset and created the result as a persistent `plot.dataset` variant.
- Added shared reversed-axis usage through public `PLOT_DATASET_API_v2` `axis_direction`, preserving the conventional high-to-low wavenumber display without private axis code.
- Preserved IR-specific conversion, fingerprint weighting, peak-overlap, reference-library ranking, warnings and provenance semantics.


## 1.0.3

- Pin each candidate to its exact reference-library version and content hash in the published ranking Dataset, report and output provenance, so later library updates cannot silently change historical interpretation.

## 1.0.2

- Clarified the overlay legend as a top-ranked reference candidate, not an asserted identification; packaged the verified real-RefIMP workflow for the integrated release.

## 1.0.1

- Made mean-centering explicit/default before unit-vector matching, avoiding shared positive baseline bias; kept unit-vector-only as a user choice.
- Ensured both nearly coincident overlay curves remain visible in headless GNU Octave and placed the legend outside the data area.
- Routed the Tcl analysis companion through a CORE bridge so the external plugin remains host-independent.

## 1.0.0

- First Dataset-native IR spectroscopy and reference-matching consumer of the GX-TXT scientific Spectrum and Reference Library CORE APIs.
