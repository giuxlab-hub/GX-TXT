# GX-TXT dev078 — Duplicate Experiment clone correction

Baseline: verified published/installed `0.9.8.10-dev-077`, archive SHA-256
`838ec6650d26dd5d99260561a47b6c74077f34ea4e03f2b3ef5a0a86494f4a75`.
Its archive/expanded/internal manifest, restore archive and installed/alias inventories
were independently checked before creating a fresh dev078 candidate. Previous releases
and versioned handoffs remain immutable. Delivery is one corrective framework release;
manual acceptance is pending. No phases 2/3, Analysis/SEM batch or Workbench development.

## Result and ownership policy

Session > **Duplicate Experiment...** and its **Duplicate Experiment** dialog use
the existing dev077 clone transaction. Public command names and signatures remain
unchanged, including `sessionExperimentClone`, `newExperimentDialog` and related
callbacks. The completed embedded Experiment GUI, removed controls, retained Project
New/Edit and independent Session/Projects/Dataset navigation remain in place.

| Treatment | Content and reason |
| --- | --- |
| Copy | Live enabled/disabled modules; reusable module parameters/configuration; actual instrument instances, values and Library relationships; Session parameters; Experiment metadata; saved/live Notes/Objective/Procedure and other non-observation Markdown; local scripts/metadata/checksums and valid external registrations/references; ordinary and hidden preparation files. These are the prepared environment. |
| Copy by owner | Independent non-Workspace Interactive Documents, exact active payloads, IDs/checksums/revision/generation/provenance, and their owned managed resources. Their Session lifetime and filesystem copies are independent. Safe preparation recovery and independent artifact viewer layers remain available through existing contracts. A document/resource/geometry extension alone does not identify scientific ownership. |
| Reset | Observations: zero-byte `observations.md`, empty Manifest/cfg/editor, including when the source has an unsaved observation draft. Existing graphs: selected offerings, graph-specific base settings, Variants/counters/bindings/graphics, Graph Series, axis/legend/style/Level Scale overrides, regions, annotations, PlotSpec v2, detached graph captures, graph notes/metadata and rendered graph outputs. New graphs can be created and saved normally. |
| Exclude by owner | Dataset registrations/payload/raw sources/metadata/resources/selections/profiles/materializations and identical payload copies; pending acquisition sources; Workspace documents and owned resources/notes/History/recovery/files; graph authorities and declared scientific outputs/runtime files. CORE's documented legacy module-owned render cache is excluded even when absent from the module's output list. |
| Preserve preferences | General `[graphics]`, `[graphics_3d]` and module-wide preferences unrelated to a particular graph remain preparation. Static installed graph offerings/default values remain module capabilities but start unselected. |
| Clarify | Mixed preparation documents with excluded scientific/Workspace/graph dependencies, retired/unknown resource ownership, unknown Workspace schema, or source-absolute paths needing provider-specific rewriting cancel duplication with document ID, owner/provider/schema and dependency. No source content is deleted, truncated, recategorized or converted. |

The document registry and managed-resource APIs remain the authorities. The worker
uses their existing readers/registry writer and preserves generations so existing
resource receipts resolve correctly in the new Session. It creates no second registry
or unbound/preparation placeholder for a Workspace. Registry absence in older Sessions
is valid and handled as an empty collection. Known Workspace contracts include the
registered Curve Workbench and the existing legacy PDF OCR/Table Extractor/3D Workbench
schemas; unknown schemas require clarification. Workspace implementations are unchanged.

Opaque author scripts/code documents and ordinary file contents remain verbatim and
are never rewritten or executed to neutralize author code. Managed resources resolve
by owner in the duplicate, rather than through source links. Directory/broken symlinks
or special files fail cleanly; ordinary file symlinks materialize. Provider-owned source
references that cannot be preserved safely require clarification, rather than invented
migrations. No ambiguous production document was recategorized in this cycle.

The authoritative Manifest clears unsafe scientific bindings while preserving the
remaining module configuration and proposed output IDs. Source preparation snapshots
restore temporary cfg changes in `finally`; cloning never saves/reloads the source.
Existing isolated staging, exclusive reservation, atomic commit, distinct Experiment
identity/Project membership and exact registry rollback remain. The per-clone omission
receipt records actual excluded entries; the read-only Script Bridge receipt now reports
retained document count, `observations=empty`, `graphs=reset` and duplicate policy.
Host-only filesystem clone creation remains documented; no existing bridge is removed.

Hidden CORE axis/legend/graph-map TSV transport files are also excluded; explicit
regressions verify those graph-owned styles/configurations are absent.

The legacy loaders overlay missing axis/per-graph fields. For a duplication receipt,
the wrapper clears those current arrays before loading existing authorities so a
Session switch cannot inherit the source's graph settings. It then loads the saved
records normally, including graphs subsequently created in the duplicate. Existing
Sessions without that receipt use their unchanged loader path.

## Implementation inventory

| File | Change |
| --- | --- |
| `core/tcl/session_experiment_worker.tcl` | Replace broad file-class/document exclusions with the owner plan; reset observations/graphs; preserve ordinary files/resources; validate staging. |
| `core/tcl/session_experiment_ownership.tcl` (new) | Private worker document/resource/dependency plan, authoritative subset copy, graph/output reset and viewer-layer ownership filtering. |
| `core/tcl/session_experiment_api_v1.tcl` | Accurate retained document count and receipt-scoped loading of reset graph state. Public signatures unchanged. |
| `app/session_experiment_gui.tcl` | Duplicate Experiment title/text and corrected preparation/reset explanation. Existing callback names unchanged. |
| `app/session_menus_dev065.tcl` | Rename only the Session menu label. |
| `gxtxt_pipeline.tcl`, `VERSION.txt` | Version dev078. |

README/CHANGELOG, the existing Session Experiment API manual, this report, exact
`CHANGED_FILES_dev078.txt`, acceptance receipt, focused validation/evidence,
SCRIPT_CATALOG, technical handoffs and unfinished-only TODO complete delivery.
The Phase 1 section implementation, Project APIs/protection manual, Workspace API,
all module/plugin implementations and Native2D/Native3D engines remain unchanged.

## Validation evidence and scope

Final PASS logs and directly inspected PNGs are bundled in `docs/evidence/dev078/`;
`visual-review.json` binds observations to screenshot SHA-256. The final product stamp
and publisher gate bind the archived implementation to the validated source.

- Public API fixture creates CSV and HDF5 Datasets, a real Workspace with owned
  resource/notes/recovery/History, an independent preparation document with a live
  managed resource/provenance, and an existing Octave script preparation document.
  It includes multiple enabled/disabled modules, nondefault parameters, two actual
  instrument instances including a Library link and disabled instance, four distinct
  notes, local/external scripts, Project membership, per-graph title/label/style,
  Variant, Graph Series, axes/legend/Level Scale overrides and graph artifacts.
- Exact complete source inventories survive cloning and independent activity. The
  duplicate retains real resource readability, document identity/generation/checksum,
  instrument settings/relationships, module states/configuration, scripts/checksums,
  ordinary files, independent geometry, temporary-looking preparation resources and
  revision notes. Scientific Dataset and Workspace authorities are absent; the actual
  retained document count is two. Independent artifact viewer state is preserved and
  the Dataset-owned layers, derived artifact snapshot, single-source scientific viewer
  document and its managed resource are absent.
- Empty observations, reset graphs and live resources survive Session Save/switch,
  close and fresh Tcl interpreter reopen. New Dataset publication, Workspace creation,
  Graph Series/Variant creation and subsequent graph save/reopen work normally.
- Collision rejection, a real broken-link mid-copy error and injected Project-index
  failure leave no half-created destination. Project rollback restores exact prior
  registry bytes; public association/detachment retain their semantics. An intentional
  mixed preparation/Dataset document names its owner/dependency in a clarification
  failure and retains its complete source bytes. No resolution policy was invented.
- Full application on authenticated local Xorg `:1` with actual mouse/keyboard input:
  menu/dialog rename, embedded Experiment, retained Project Edit/Markdown Save,
  cancellation/collision/recovery/duplicate/open, all four note editors and unsaved
  drafts, zero-byte/empty observation file/cfg/editor, visible clone fields, complete
  source inventory preservation, actual empty Workspace GUI list, retained managed
  preparation resource, existing Octave Script Viewer opening the retained document,
  Session Save, every Session section, Projects navigation/source notes and independent
  Dataset activation/XY Preview. Source observation drafts remain unchanged during
  snapshot; original saved observations remain unchanged after duplication/switch.
- Production saved audio (~1.9 GB) and descriptive-statistics Sessions are copied to
  disposable fixtures before opening. Their metadata/legacy links and original Dataset
  collections reopen; duplicate observations and graphs reset, scientific result/cache
  files are absent, and the production original's entire inventory is unchanged.
- Existing real Native2D/Native3D Preview tests cover render/camera/worker reuse,
  source/options/schema/replacement/Session invalidation, independent full viewer and
  resource release. HDF5 plane/media thumbnail/Clear expiry, categorical CSV/HDF5
  profile retention, real headless Python Script Bridge and CORE discovery pass.
- **All 3,240 existing CORE Tcl signatures survive with no renamed/removed command.**
  **439 effective Dataset procedure bodies are byte-identical**. Dataset GUI files,
  completed Phase 1 section integration, Workspace/Workbench APIs, modules/plugins,
  native engines/binaries and plugin/generator packages preserve baseline bytes.

Tests cover these concrete persisted authorities and fixtures; they do not claim every
third-party provider, arbitrary author script, codec or undocumented Session layout
was executed. Provider-specific ambiguous dependencies require user clarification.
After publication, the same real-GUI journey against installed dev078 and complete
active/alias/expanded/archive/restore parity are required before the final handoff.

Final fixtures explicitly persist a private `scripts.user_root` through the existing
Configuration API, in addition to isolated XDG paths. XDG alone does not relocate
the default Script Library. An early newly created test-only entry outside that private
root was moved into the evidence directory after verifying its creation time/content;
no pre-existing entry was replaced. `validation-isolation-correction.json` records
this correction. The final API/GUI and installed journey use the private library.

The publisher preserves a complete active dev077 backup and the protected plugin/
generator inventories. All three Debian deposit sections retain matching archives
and expanded sets. The previous API-ledger search result remains explicit in the
unchanged Project API manual and unfinished TODO; this cycle does not invent a ledger.

Stop after delivery for manual acceptance.

Duplicate GUI note drafts are retained in memory for the source Session and restored
in edit mode when returning to it in the same process, including pending observations.
No source note is saved by this restoration. The ordinary Save/Discard/Cancel callbacks
resume ownership of the restored editor; drafts are not persisted across app restart.
