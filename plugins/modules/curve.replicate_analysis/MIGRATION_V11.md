# Replicate Curve Analysis v11 migration

GX-TXT 0.9.8.10-dev-031 changed the preferred Dataset and plotting interfaces substantially compared with the original module implementation.

Version 11 therefore uses:

- Analysis Source Map API v1 for source selection (`+ Add source`);
- Analysis Source runtime metadata and Dataset Variable Schema API v3 for stable variable identity;
- Table Stream API v3 for canonical Dataset reads;
- Dataset Publication API v2 for derived Dataset publication;
- Plot Dataset API v3 for persistent graphs.

## Derived Dataset layout

Version 10 and earlier could publish one Dataset for every accepted trace and one Dataset for every family profile. Version 11 replaces that fan-out with three compact long-form Datasets:

- `curve.replicate.traces`
- `curve.replicate.profiles`
- `curve.replicate.family_summary`

Old finalized Datasets named `curve.replicate.trace.*` and `curve.replicate.profile.*` are not deleted automatically. Dataset Publication API v2 deliberately has no public delete operation for finalized Datasets; the module does not call private CORE deletion procedures. Existing legacy publications can be deleted once from the normal Dataset management UI.

## Family binding migration

A text label such as `curve_label` is not the numeric family coordinate. When runtime metadata exposes exactly one numeric variable with semantic role `family`, v11 corrects an accidental text Family binding to that variable and records the correction in the analysis summary. For Curve Digitalizer output this normally maps `curve_label` to `family_value`.
