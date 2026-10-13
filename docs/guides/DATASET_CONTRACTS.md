# Dataset contracts available in GX-TXT Pipeline v0.8.4

This document lists the framework contract IDs shipped/discovered in the complete v0.8.4 plugin set bundled in this release.

The live GUI is authoritative: open **Acquisition → acq.generic_csv → Contract registry...** to see contracts discovered from the currently installed plugin descriptors and which modules produce/consume them.

## `raw.csv`

Purpose: raw CSV source accepted by acquisition/import modules.

Declared/consumed by the acquisition layer. It is normally **not** the canonical `kind` to assign to a finished imported table.

## `table.generic`

Purpose: generic canonical tabular dataset without a more specific structural contract.

Current producer:

```text
acq.generic_csv
```

Current consumer in the supplied plugin set:

```text
analysis.definition_demo
```

Typical uses include summary tables, chemistry tables and Scientific Analysis Definition inputs.

## `timeseries.table`

Purpose: canonical time-series table.

Current producer:

```text
acq.rigol_csv
```

Current consumers include:

```text
gxtxt.ir_waveform
gxtxt.ir_identify
```

## `curve_family.table`

Purpose: canonical family-of-curves table.

Current consumers include:

```text
curvefit.family_global
model.spice_build_validate
```

## Custom contracts

Do not invent a different ID when an existing contract already describes the dataset adequately.

When a genuinely different or undeclared contract is required, the Generic CSV importer supports:

```text
Other...
```

The entered value is preserved exactly.

Plugins may optionally declare new contracts through the Contract Registry API v1. See:

```text
docs/api/CONTRACT_REGISTRY_API_v1.md
```

## v0.9.4 specialization rule

Contract compatibility is no longer limited to literal equality. `timeseries.table` and `curve_family.table` are specializations of `table.generic`. Plugin-provided contracts may declare `parents=table.generic` (or another registered parent) in their descriptor. This allows the CORE `plot.dataset` module to accept future canonical tabular contracts without hard-coding every contract ID. Unknown contracts remain exact-match only until a provider declares their parent relationship.
