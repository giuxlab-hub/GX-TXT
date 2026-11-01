# GX-TXT 0.9.8.10-dev-094 technical handoff

SPDX-License-Identifier: GPL-3.0-or-later

Baseline: officially published dev093, archive SHA-256
`80638c5c506075d317f14e5aa4b21a0c54c64f668112f6408c9f3f6060753d49`.
All 5861 source files matched archive, expanded, restore and active installation
before creating isolated Git branch `stabilization/dev094`.

## Integrated changes

- Curve Viewer **0.2.0**: semantic family members, explicit manual binding,
  non-destructive typed filters, independent logical curves and exact named
  Workspace identity. The ordinary no-family 2D view remains compact/read only.
- Independent Scientific Curve Dataset Publisher **1.0.0**: normal installable,
  optional `export.curve_dataset` package/action. Exact filtered scientific rows,
  dtypes, units, original row lineage and structured provenance; create-only
  CORE Publication v2 with no sampled-canvas or private registry path.
- Dataset Curve Fit **0.4.0**: resizable scrollable left controls, large right
  Native2D plot, grouped existing commands and accessible residual data. Named
  A/B Workspaces, exact IDs and in-place legacy v1 compatibility; numerical
  fitting/source/selection/publication engines remain unchanged.
- Curve Workbench **2.15.1**: explicit Workspace → Clear History, reusable CORE
  Scientific Recipe rebase and existing document/recovery commit. Preserve current
  scientific state/resources/notes; rollback failed precommit; subsequent editing
  starts a new complete History without raising limits.
- Central **Configuration → Modules**: all installed modules and public fields,
  typed User/Session editors, structured shortcuts and tables, precise inheritance,
  application timing and conflict/draft handling. Central/local surfaces share
  one CORE schema/value/validation/scoped transaction. Save handles late and hidden
  fields while retaining Appearance, Native3D and dev093 cache preferences.

See [user guide](../guides/STABILIZATION_dev094.md) and
[architectural API-change report](DEV094_API_DECISIONS.md) for ownership, generic
module authoring, additive contracts and encountered legacy wrapper decisions.

## Acceptance evidence

Curated candidate logs/screenshots are under `docs/reports/dev094_evidence`.
The release publisher additionally requires **fresh-extracted packaged-artifact**
tests; their separate immutable outputs/receipt are under workspace
`_evidence_stabilization_dev094/package-suite` and `package-suite.json`.
No result is inferred from an informational module list or headless GUI substitute.

Configuration coverage visits every installed module and every configurable
field, with an unknown descriptor-only disabled fixture. Real local Debian Xorg
`:1` screenshots show editable Workbench shortcuts **before Viewer activation**,
invalid/conflicting edits, typed second-module settings, Session overrides and
successful Save. Actual native input proves central→local→central F8/F9 bindings,
two-open-editor/rich-form conflicts, late registration/draft retention, table edits,
unprojected global fields and fresh-process restart. Cache storage policy, font,
Native3D and workers survive. Modules without settings show accurate metadata.

The 20,000-row family fixture renders at budget 16 but publishes exactly **1850**
independently checked X/Y/original-row tuples, with source bytes unchanged.
int64 values above 2^53 and NaN/Inf scientific rows remain exact; the existing
Native2D precision guard rejects unrepresentable coordinates. Lineage gaps match
sync/async reopening. Collision/empty/stale revision/generation/Session failures
leave no phantom Dataset. Real GUI install/disable/uninstall/reinstall, publication,
Preview, edited filters and Session reopen complete the optional-module proof.

Family edge tests cover text IDs, name-only fallback, multiple semantic families,
bounded discovery and an explicit member outside its sampled values. Async close
releases tokens; stale windows cannot save into a new Session. Both viewers retain
independent A/B state and use normal notes/duplicate/export/import/delete. Fit v1
accepted records reopen and promote to v2 on the same document ID.

Fit screenshots at **1100×700, 1280×840 and 1800×1000** demonstrate a large canvas;
all relocated menu commands retain their callbacks/enabled states. Real rectangle
selection, clear, model dropdown, preview/accept, zoom/pan and residual visibility
exercise the unchanged scientific controller. Seven deterministic model fixture
dictionaries match dev093 byte-for-byte; five classical models also pass exact
source/filters/selection/residual/orientation/export/publication regressions.

A representative private 33 MiB Workbench Session with calibrated image and
retained/parametric geometry exercises the 8 MiB and 4096-step blockers, native
confirmation/cancel, save-permission failure rollback, browsing/gesture rejection,
exact state/resources/notes/other Workspace preservation and a real constrained
native drag after reset. CORE additionally proves an unknown host can reuse rebase.
Save/reopen and portable transfer retain the post-reset science and recovery.

## Packaging and preservation

Pinned `validation/stabilization_dev094/release.py` builds four versioned plugin
ZIPs and framework `gxtxt_pipeline_v09810dev_094.tar.gz`, with full SHA-256 source
manifest, changed-file inventory, fresh extraction and no `.git`/bytecode artifacts.
Publication requires every packaged gate, installs atomically with a complete
`_backup_active_dev093_for_dev094`, adds matching framework/external-plugin pairs
and restore archive, and verifies source/archive/expanded/active/alias/restore
parity. Session Generator pairs remain unchanged. All historical archives and
dev093 expanded/restore copies are preserved.

Original scientific Sessions are never test fixtures. A complete live read-only
snapshot protects independently saved user document changes; release operations
never overwrite them. Installation identity is preserved. The owner GUI remains
running; reopen GX-TXT to load this release. Publication SHA-256 and exact delivery
paths are recorded in `published.json` and the current workspace handoff, outside
the self-hashed archive to avoid a circular archive hash.

Only the completed central-module-configurator and Dataset Curve Fit layout TODOs
are removed. Windows ports, new models, broader GUI/Workbench/Native3D work and
unrelated historical manual-acceptance items remain outside this completed task.
