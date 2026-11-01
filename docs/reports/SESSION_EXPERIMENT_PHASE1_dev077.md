# GX-TXT dev077 — Session / Experiment Phase 1

Delivery status: verified candidate for versioned publication; **manual acceptance
pending**. Baseline is the published and installed `0.9.8.10-dev-076`, archive SHA-256
`e2057d64745a058de90fa43a837800e8ce51820dde24d61ea097b8d81e5af0d4`.
The publisher verifies immutable baseline/archive/expanded/internal hashes, creates
new dev077 archive/expanded/restore outputs, preserves the active dev076 backup,
and verifies complete active/alias/source parity. The external-plugin and Session
Generator sections retain their complete baseline inventories.

The existing Experiment panel is now the sixth internal Session section. Its actual
widgets, editing callbacks and Markdown/GX-Markup documents are reused. The top-level
Experiment tab and only Associate current Session / Experiments / Detach Session
controls are removed. Project New/Edit and the independent Projects page remain.
Ordinary Session switches offer Save/Discard/Cancel for edited notes; New Experiment
captures drafts without committing them to the source.

New Experiment creates a separate Session path and Experiment ID through an isolated
CORE worker, then adds its distinct Project membership using the existing API.
The mandatory correction supersedes the original assignment: **zero Datasets, zero
Workspaces, zero Interactive Documents**. Workspace documents, owned resources,
History/recovery, geometry and viewer state are excluded wholesale. There is no
Curve Workbench conversion, migration, reconstruction or partial preservation.
The Workspace API implementation and all Workbench/plugin/native implementations
remain byte-identical to dev076. Full source Session inventories are checked before
and after cloning, including scientific data and Workspace resources.

Non-data preparation is preserved: module enablement/configuration, instrumentation,
Session parameters, analysis/plot/Variant definitions, graph styles/filter definitions,
registered scripts/checksums, notes, metadata and ordinary/hidden preparation files.
Scientific input/Selection bindings are cleared; pending file inputs are disabled.
Graph Series retain reusable definitions with empty Dataset IDs and disabled state;
inspection reports unavailable/unbound and ordinary runtime lists exclude them.
Proposed output Dataset IDs remain configuration. New data can subsequently be
published independently using the existing Dataset APIs. Generated results/cache
(including saved audio MAT render caches) and identical scientific payload copies
outside canonical storage are excluded. The per-clone receipt lists omitted entries.

Cloning rejects collisions and paths inside the source. Exclusive reservation and
atomic commit prevent partially valid destinations; failure cleans owned staging.
Project persistence failure restores prior registry bytes/membership and deletes the
new destination. Broken/directory symlinks and special files fail cleanly; ordinary
file symlinks are materialized. Author scripts retain exact bytes and are neither
rewritten nor executed. Arbitrary future execution follows their existing contracts.
The read-only preparation receipt is available through Tcl and the Python/Octave
Script Bridge; filesystem clone creation remains a host administrative operation.

## Modified implementation inventory

| File | Purpose |
| --- | --- |
| `app/sessions_page_redesign.tcl` | Embed existing Experiment panel in Session selector/content. |
| `app/session_menus_dev065.tcl` | New Experiment command and removal of the top-level tab. |
| `app/session_experiment_gui.tcl` (new) | Name/root dialog, recoverable errors, successful clone/open and note-switch guard. |
| `core/tcl/project_api_v1.tcl` | Remove only three widget constructions; retain all public callbacks. |
| `core/tcl/dataset_notes_api_v1.tcl` | Avoid rebuilding/dropping drafts on a cancelled Session chooser. |
| `core/tcl/session_experiment_api_v1.tcl` (new) | Source-safe live snapshot, clone transaction, Project rollback and Manifest receipt. |
| `core/tcl/session_experiment_worker.tcl` (new) | Isolated preparation copy, complete experimental-data exclusion and safe rebinding. |
| `core/python/session_experiment_files.py` (new) | Exclusive reservation, atomic commit and owned cleanup. |
| `core/tcl/graph_series_api_v1.tcl` | Preserve explicitly disabled unbound definitions; honest unavailable descriptors. |
| `core/script_bindings/public_core_services.py` | Additive read-only preparation service. |
| `gxtxt_pipeline.tcl`, `VERSION.txt` | Load new components and version dev077. |

README, CHANGELOG, existing Project/Graph API manuals, new Session Experiment API
manual, this report, exact changed-file inventory, acceptance receipt, focused evidence,
validation fixtures/publisher, SCRIPT_CATALOG and unfinished-only TODO complete the
delivery. `CHANGED_FILES_dev077.txt` contains the exact release inventory.

## Validation and practical scope

All final logs in `docs/evidence/dev077/` pass without Tcl/Python/background errors.

- Full application on authenticated local Xorg `:1`, actual mouse/keyboard input:
  embedded panel, retained fields/Markdown Save, Project Edit, every Session section,
  New Experiment cancellation/collision/recovery/create/open, captured note drafts,
  clone field screen hit-target after repaint, existing Save command, Projects
  navigation/source notes and independent Dataset activation/XY Preview.
- Synthetic API fixture: CSV/HDF5, bound and independent Workbench/native-viewer
  documents, managed resources, History/recovery and geometry. Clone has no Datasets,
  Workspaces/documents/resources/geometry; all source bytes unchanged. Instrument and
  parameter values, module/Graph/Variant setup, scripts/checksums and hidden files
  survive. Fresh interpreter restart/save/reopen/new independent Dataset, distinct
  Project entries and unchanged association/detachment semantics pass. Real broken
  link mid-copy failure and injected Project-index failure both restore clean state.
- Actual empty-clone Workspaces GUI: empty list and absent document/resources/history
  authorities; no Workbench operations or changes.
- Saved audio (~1.9 GB) and descriptive-statistics Sessions: only disposable copies
  opened; metadata/config/legacy links and original Dataset collections reopen;
  preparation clones remain empty after save/reopen. Production source inventories
  are unchanged. Generated CSV/HDF5/MAT/NPY results are absent from clones.
- Real headless Python Script Bridge: existing Session/Workspace/API discovery and
  new read-only receipt pass without Tk.
- Focused inherited dev076 Preview regressions: actual Native2D/Native3D rendering,
  hidden-return reuse/camera/worker retention, source/options/schema/replacement/Session
  invalidation, independent full viewer and resource disposal; HDF5 plane/media
  thumbnail/Clear expiry; categorical CSV/HDF5 profile retention. CORE headless
  discovery passes. These are explicit-framework disposable validation fixtures;
  historical version-pinned publishers were not executed.
- **3,229 existing CORE Tcl argument/default signatures are preserved**, with 11
  additive commands. **439 effective Dataset procedure bodies are byte-identical**.
  Dataset page files, plugins and native binaries are unchanged. Runtime evidence is
  focused as described above; it does not claim every third-party script/provider,
  codec, module or arbitrary Session layout was executed.

Visual review inspects the actual screenshots and records their SHA-256/observations
in `visual-review.json`. The source-code stamp binds all final tests to the product
being archived. After publication the same real-GUI journey is required against the
installed runtime; its log and full installed-tree verification receipt live in the
workspace evidence directory and are prerequisites for the final handoff.

## Apparently unused API register

**No authoritative register was located**, despite framework filename/content,
tooling, workspace authoritative/current/historical Markdown, compito, server task
documents, electronics-server and Codex project filename searches. Search terms and
scope are recorded in `api-search.json`. No parallel register was invented and no
claim is made that the presumed register was updated. The existing
`docs/api/PROJECT_API_v1.md` now explicitly protects these intentionally GUI-detached,
still-supported command contracts:

- `::GX::projectAssociateCurrentExperiment projectId`
- `::GX::projectDetachCurrentExperiment`
- `::GX::projectAssociateExperiment projectId experimentId sessionPath experimentName`
- `::GX::projectDetachExperiment experimentId`
- `::GX::projectSelectDialog`, `::GX::projectSelectDialogAssociate w`
- `::GX::projectDetachCurrentExperimentDialog`
- `::GX::projectExperimentsDialog`, `::GX::projectOpenExperimentFromList w`
- `::GX::projectListExperiments projectId`, `::GX::projectGuiOpenExperiment`
- `::GX::openSessionPath path`

They retain association/detachment without moving scientific files, legacy Project
link semantics and internal/programmatic/Projects-page navigation. Their GUI removal
does not make them dead code. Locating the presumed register remains in the TODO.

Phase 1 only. Manual acceptance is pending. Phases 2/3 and separate Analysis/Dataset
selector work were not started. Stop after delivery.
