# Changelog

## 1.1.0 — GX-TXT 0.9.8.10-dev-097

- Use generic CORE propagation/summary semantics for output, reports and metadata.
- Reuse weighted-summary uncertainty; remove the redundant one-parameter fit.
- Require explicit Gaussian known-sigma assumptions for reduced chi-squared.
- Preserve Dataset, graph, summary row and legacy report identities; add states,
  reasons and CORE quantity IDs, with undefined singleton sample spread.

## 1.0.1 — GX-TXT 0.9.8.05

- Uses public plot.dataset variants and shared uncertainty and reduction services.

## 1.0.0 — GX-TXT 0.9.8.05 integration

- Published a canonical measurement-series Dataset and moved both graph modes to public Plot.dataset Plot Variants.
- Kept only Dataset identities and presentation settings in the rerender cache; verified standard uncertainty and explicit weight modes independently.

## 1.0.0

- Initial external uncertainty/weight numerical reference plugin for GX-TXT 0.9.7.82.
- Added explicit standard-uncertainty and explicit-statistical-weight interpretations.
- Added public NUMERIC_API execution, Dataset Publication, report and Graph Provider output.
- Bundled deterministic Measurement Uncertainty Session Generator.
