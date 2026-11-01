# dev-059 discovery — published dev-057 architecture map

Baseline: GX-TXT 0.9.8.10-dev-057 / Curve Workbench 2.6.0 / Dataset Curve Fit 0.3.5.
This is a pre-implementation audit, not a release handoff or GUI acceptance.
The complete dev-059 task, dev-057 versioned handoff, CURRENT continuity,
general rules and operational unfinished TODO were read before changes.
The current task and user-confirmed local-display acceptance supersede older
remote-X11 and dev-055 fallback instructions in the operational history.

## Evidence and limits

`TK_GIUXLAB/_evidence_dev059_baseline.json` binds the fresh
`_work_gxtxt_dev059` to the immutable published dev-057 inventory and freezes
all three ordered server sections and prior handoffs. No dev-058 product code
was copied. Product source, versions and adapters are still exactly dev-057.

`_evidence_dev059_architecture01` traces the published expanded source;
`_evidence_dev059_architecture02` traces the fresh candidate. Each contains
`architecture.json` and `procedures.tsv`; the second also contains
`delegation_chains.txt`. The JSON records every executed definition/rename,
its source/line/body, final loaded command ownership, source hashes, state keys,
Native operations and conservative local/CORE references.

The load runs in a headless Tcl interpreter. Only viewer-backend and recipe-host
registration callbacks are stubbed. No GUI is created and no Workbench operation
is invoked. Thus this establishes loaded definitions and alias resolution, not
behavioral parity. Dynamic dispatch and branch ordering still require source
review and real GUI evidence before any refactor can be accepted.

Observed: 28 sourced Workbench files, 626 procedure definitions, 199 executed
renames, 594 surviving loaded procedures and 32 direct overwrites. The six
late files named by the task account for exactly 55 renames. Renames also
exist throughout the preceding feature stack. Counting only late files misses
most of the integration dependency graph.

## Source/load order

The main `gxtxt_pipeline.tcl` loads application controllers, then the CORE
Dataset, Session, Native2D, document, viewport and recovery authorities.
Module discovery loads the Workbench API entry. Its final source statements
establish the following exact Workbench order (filenames below are in
`plugins/modules/viewer.curve_workbench/api/`):

1. `curve_workbench_api_v1.tcl`
2. `curve_workbench_source_v2.tcl`
3. `curve_workbench_geometry_v2.tcl`
4. `curve_workbench_cad_v2.tcl`
5. `curve_workbench_units_v2.tcl`
6. `curve_workbench_recovery_v1.tcl`
7. `curve_workbench_lifecycle_v1.tcl`
8. `curve_workbench_sketch_v1.tcl`
9. `curve_workbench_constraints_v1.tcl`
10. `curve_workbench_measurements_v1.tcl`
11. `curve_workbench_identity_v1.tcl`
12. `curve_workbench_collections_v1.tcl`
13. `curve_workbench_views_v1.tcl`
14. `curve_workbench_series_v1.tcl`
15. `curve_workbench_extensions_v1.tcl`
16. `curve_workbench_roles_v1.tcl`
17. `curve_workbench_comparison_v1.tcl`
18. `curve_workbench_recipe_v1.tcl`
19. `curve_workbench_interaction_v1.tcl`
20. `curve_workbench_representation_v1.tcl`
21. `curve_workbench_sketch_constraints_v2.tcl`
22. `curve_workbench_interaction_v2.tcl`
23. `curve_workbench_viewport_v3.tcl`
24. `curve_workbench_fluidity_v4.tcl`
25. `curve_workbench_selection_v4.tcl`
26. `curve_workbench_comparison_v4.tcl`
27. `curve_workbench_representation_v4.tcl`
28. `curve_workbench_backing_v4.tcl`

The backend is registered after viewport_v3, before fluidity/selection/comparison/
representation/backing_v4 finish replacing procedures. Calls made after loading
therefore resolve to the later definitions, not necessarily the source containing
the original registration or widget callback.

## Responsibility and state map

| Responsibility | Existing authority and integration | Invariant to preserve |
|---|---|---|
| Logical records | `CurveWorkbench::st($w,curves)` in api/source/backing; record `native` maps logical identity to Native object | Logical names/source bindings are host records, not an alternate geometry engine |
| Geometry/math | `core/native2d/gx2d.c`, sketch/construction/CAD/constraints/solver includes; `gx2d_tcl.c` is the adapter | Retained definitions and real controls/segments are mathematical authority; render samples are disposable |
| Public geometry API | `core/tcl/native2d_geometry_api_v1.tcl`; owned scene/object tokens and working units; `core/script_bindings/native2d_geometry.py` | Reuse scoped APIs for modules/scripts; host does not duplicate math |
| Dataset backing | Canonical Dataset v2, Curve Source, Table Stream; Workbench source_v2, geometry_v2, backing_v4 | Untouched Dataset geometry is locked and saved as validated bindings; no private authoritative copy |
| Semantic selection | Native `selection_set_*`, pick and region; selection_v4 projects it into `sketchSelection`/`objectSelection`; active remains property focus | One semantic set; `selectionScene` aliases scene, `selectionObject` identifies focused owner |
| Chrome/layout | CORE `native2d_viewport_host_v1.tcl`; viewport_v3 adapts Workbench panels, palette, tools and Settings | Layout invalidates on actual geometry/chrome changes, not every scientific redraw |
| Scientific redraw/feedback | api_v1 base draw plus CAD, Join, measurements, comparison, interaction, sketch, tangent, raster and semantic overlays | Draw ordering and transient feedback filtering matter; no full layout or save per view event |
| Pointer/keyboard | Final selection_v4 handlers delegate through viewport/interaction/sketch/CAD/geometry paths | Priority includes semantic gestures, image calibration, zoom box, tangent handles, construction, relationship handles and transforms; preserve cancellation and capture ownership |
| CAD/gizmo/pivot | cad_v2 plus sketch_constraints_v2 and Native `pivot`, `gizmo`, drag/affine operations | Native owns custom pivot and transform math; UI must route placement to that authority |
| Constraints | constraints_v1 then sketch_constraints_v2 and interaction_v2; Native interaction eligibility, exact solver and dimensional APIs | GUI selection references must reach the exact solver; representable/diagnosable is not proof of enforcement |
| Persistence/recovery | Base `_save` builds payload version 2; Session Workspace wraps Interactive Document; lifecycle guards and Workbench Recovery own journals | Session token, owner generation, immutable binding validation and partial-restore save refusal must survive |
| Undo/redo | api_v1 snapshots plus CAD `@cad`; multiple contributors capture units, constraints, identities, collections, views, series, recipes, images, selection and comparison | One transaction restores complete semantic state; restore images before dependent constraints; no display-cache topology |
| Comparison/residual | comparison_v4 explicitly stores enabled/config/record, using existing Native comparison | Focus, drawing or reference choice cannot silently activate/retarget a comparison |
| Reference images | viewport_v3 UI, Native image calibration/transform/clip; managed document resources and shared host raster worker | One scene-owned async raster lifecycle; dispose it on close; stale work cannot resurrect pixels |
| Commands | Dispersed callbacks in base GUI, `_cadGui` chain, `_commandMenu`, `_paletteAction`, sketch menu builders and late `open` replacements | No single configurable registry yet; consolidate callbacks before adding registry surfaces |
| Bridge | Framework Script Bridge runtime, provider bindings and owned Native geometry tokens | Python/Octave use the same public authorities; privileged metadata needs authenticated host caller identity |

`st` is a shared host array, not independent feature stores. Its Native-backed
projections and GUI-only transient fields must be distinguished during cleanup.
`architecture.json` lists the state-key references for every loaded procedure;
this is a reference inventory, not an assertion that every reference writes state.

## Critical resolved delegation chains

These counts include the entry definition and its referenced older aliases.
Conditional branches need not traverse every definition during one event.

- `_draw`: 12 definitions; `selection_v4` → `viewport_v3` → `viewport_v3` → `viewport_v3` → `interaction_v2` → `sketch_constraints_v2` → `interaction_v1` → `comparison_v1` → `measurements_v1` → `constraints_v1` → `cad_v2` → `api_v1`.
- `_mouseDown`: 10 definitions; `selection_v4` → `viewport_v3` → `viewport_v3` → `interaction_v2` → `sketch_constraints_v2` → `interaction_v1` → `constraints_v1` → `cad_v2` → `geometry_v2` → `api_v1`.
- `_mouseMove`: 7 definitions; `selection_v4` → `viewport_v3` → `sketch_constraints_v2` → `interaction_v1` → `cad_v2` → `geometry_v2` → `api_v1`.
- `_mouseUp`: 8 definitions; `selection_v4` → `fluidity_v4` → `viewport_v3` → `sketch_constraints_v2` → `interaction_v1` → `cad_v2` → `geometry_v2` → `api_v1`.
- `open`: 7 definitions; `representation_v4` → `selection_v4` → `fluidity_v4` → `viewport_v3` → `interaction_v2` → `source_v2` → `api_v1`.
- `_save`: 4 definitions; `fluidity_v4` → `lifecycle_v1` → `recovery_v1` → `api_v1`.
- `_close`: 6 definitions; `fluidity_v4` → `viewport_v3` → `lifecycle_v1` → `recovery_v1` → `geometry_v2` → `source_v2`.
- `_cadState`: 15 definitions; `comparison_v4` → `selection_v4` → `viewport_v3` → `viewport_v3` → `sketch_constraints_v2` → `recipe_v1` → `comparison_v1` → `series_v1` → `views_v1` → `collections_v1` → `identity_v1` → `measurements_v1` → `constraints_v1` → `units_v2` → `cad_v2`.
- `_cadRestoreState`: 15 definitions; `comparison_v4` → `selection_v4` → `viewport_v3` → `viewport_v3` → `sketch_constraints_v2` → `interaction_v1` → `comparison_v1` → `series_v1` → `views_v1` → `collections_v1` → `identity_v1` → `measurements_v1` → `constraints_v1` → `units_v2` → `cad_v2`.
- `_cadGui`: 24 definitions; `comparison_v4` → `viewport_v3` → `viewport_v3` → `viewport_v3` → `interaction_v2` → `sketch_constraints_v2` → `interaction_v1` → `recipe_v1` → `comparison_v1` → `roles_v1` → `roles_v1` → `extensions_v1` → `series_v1` → `views_v1` → `collections_v1` → `identity_v1` → `measurements_v1` → `constraints_v1` → `constraints_v1` → `sketch_v1` → `lifecycle_v1` → `recovery_v1` → `units_v2` → `cad_v2`.
- `_coordinates`: 6 definitions; `interaction_v2` → `sketch_constraints_v2` → `interaction_v1` → `constraints_v1` → `geometry_v2` → `api_v1`.
- `_treeSelect`: 5 definitions; `selection_v4` → `interaction_v1` → `cad_v2` → `geometry_v2` → `api_v1`.

The full alias names and source lines are in `delegation_chains.txt`. Direct
replacement also matters: `_changed` in comparison_v4 deliberately calls
`_changed_comparison_base`; it does not delegate to the immediately preceding
`_changed`. `_cancelGesture` is a direct replacement in sketch_constraints_v2.
Blindly concatenating wrappers would therefore change behavior.

The view scheduler lives in fluidity_v4: one 16 ms draw callback, a resettable
350 ms persistence callback, pending-frame flush on delegated mouse release,
and cancellation on close. Base pan/wheel handlers use these helpers. Preserve
fast-path early returns as well as delegated cleanup paths.

## Independently verified dev-057 scope gaps

- Dataset display coupling exists in published source: `_addRecord` derives
  `direction_marker.interpolation` from display style. Tangent-angle measurements
  in `gx2d_measurements.inc:99–100` and legacy constraint evaluation in
  `gx2d_constraints.inc:90–91` pass it into `gx2d_curve_point_frame`. A Native
  correction and invariance tests are required; changing only Workbench labels
  cannot fix the public scientific contract.
- `_selectionMode` currently uses Alt for subtract and Shift/Ctrl for add.
  dev-059 explicitly requires Shift subtract and Ctrl add.
- `_treeSelect` has semantic synchronization, but list rebuilding and fallback
  through property focus remain intertwined. Multi-selection/context/bulk action
  acceptance cannot be inferred from the existence of a Treeview selection API.
- `_createCommit` in interaction_v2 has family-specific continuation and resets
  normal completed primitives via `_sketchIdle`. The Line tool is remapped to
  retained path by selection_v4. Sticky behavior must be made consistent using
  the final active construction path, not obsolete interaction_v1 definitions.
- representation_v4 restricts Join to two `line/polyline/path` records. Existing
  Native path vertices/Join/Split and canonical publication must be extended for
  exact heterogeneous topology; generic grouping is not sufficient evidence of
  an ordered traversable path.
- Native already contains exact tangent equations for line/round, round/round,
  endpoint jets and some mixed endpoint/round cases. It is incorrect to conclude
  from a hidden GUI action that all tangent solving is absent. However,
  `interaction_is_line` recognizes retained Line/construction Line and an open
  two-control Path only; multi-segment Path selection needs dedicated investigation.
  The whole-object tangent equation uses a first segment, while other dimension
  families explicitly preserve selected segment indices. The GUI additionally
  filters option receipts using `general_solver` (plus Fixed). Both eligibility
  and solving must be tested for the exact requested Line-segment/Arc workflow.
- The existing local solver is bounded to 256 parameters, 1024 rows and 64
  objects. Preserve its truthful limitations and atomic candidate adoption.

These are source findings, not a new local-GUI reproduction of the user's bugs.

## Dataset authorities and browser integration map

| Operation | Existing owner |
|---|---|
| Canonical identity, describe/read | Dataset registry / `canonical_dataset_api_v2.tcl`, provider capability handles |
| Catalog and observers | `dataset_catalog_v1.tcl`, revision/snapshot/subscribe/changed-since/transaction |
| Publish/create | `dataset_publication_api_v2.tcl`, file-publication API and existing publication bridges |
| Metadata | `dataset_metadata_api_v1.tcl`, `metadata/datasets/<stable-stem>.ini` with Dataset identity check |
| Rename | `dataset_rename_api_v1.tcl`; the existing operation changes Dataset ID and dependent references, so it is not namespace movement |
| Delete/lifecycle | Existing resource lifecycle / Dataset deletion authority; new browser commands must reuse it |
| Variables | `dataset_variable_schema_api_v3.tcl` over existing schema APIs |
| Notes | `dataset_notes_api_v1.tcl` / scientific notes editor |
| Scientific selections | `dataset_selection_api_v1.tcl`; distinct from GUI selected Dataset navigation |
| Transformations | `dataset_transform_api_v1.tcl` and responsive worker integration |
| Export | Existing portable Dataset resource export, tabular/publication APIs where appropriate |
| Dataset page focus | `variableDatasetChoice`, imported/pending parsing in Dataset Inspection, `refreshNativeVariablesGui`; Preview also has `csvPreviewDatasetChoice` |
| Page presentation | `app/dataset_page_actions.tcl` extends existing Variables page with metadata, notes, preview and ZIP actions |
| Script metadata | `core/script_bindings/dataset_metadata.py` registers read/update/unset/parse_text, delegates to CORE |

`_gxtxt.framework.*` and a robustly encoded `_gxtxt.module.*` are legal under
the existing metadata key validator (dot-separated alphanumeric/underscore/hyphen
segments). No reserved ownership enforcement exists in these write/update/unset
paths today. Public write/replace operations must preserve or reject protected
keys correctly, including import/bulk editing, rather than merely hiding them.

Two ordinary UI surfaces need filtering: the metadata editor and
`datasetPageRenderSections`, which currently merges all structured metadata into
its details table. Ordinary portable metadata text export must also filter.
The underlying Session persistence must retain private fields.

Metadata commit currently saves registry revision before final metadata-file
rename. The observable catalog wraps registry saves. New namespace observers
must see committed metadata and rollback consistently; simply adding a tree
subscriber could observe stale namespace contents. Audit commit/notification
ordering before integration.

The browser must adapt the existing Dataset navigation state, keeping stable IDs
as item payloads while namespace strings are organizational metadata. Namespace
movement must not call the current ID-changing `datasetRename` operation. A
missing explicit namespace must resolve dynamically to Session current namespace
without rewriting old Datasets.

The bridge runtime already carries `module_id`; metadata writes currently pass
only session, Dataset ID and updates. Ownership must come from trusted execution
context rather than an arbitrary owner string supplied by the script. The full
Dataset operation/bridge completeness audit is still unfinished: this table maps
existing entry points and integration hazards, not a completeness PASS.

## Consolidation sequence once the local GUI prerequisite is available

1. Capture real local Linux dev-057 workflows and focused parity fixtures for
   semantic selection, exact retained paths, immutable Dataset binding/promotion,
   publication, constraints, images, comparison, persistence/recovery and fluidity.
2. Replace repeated lifecycle/state composition with explicitly ordered helpers
   in their existing authorities. Preserve the observed initialization/restore
   order, owner checks, recovery boundaries and close-time cancellation.
3. Consolidate scene draw and gesture dispatch into explicit responsibility
   stages. Keep Native math/selection/pivot/solver APIs; remove dead overridden
   implementations only after parity fixtures show their replacements own behavior.
4. Consolidate command dispatch, then implement the requested UX, exact compound/
   heterogeneous path support and Native scientific-policy separation incrementally.
5. Extend existing Dataset metadata/publication/Session authorities, enforce caller
   ownership, audit APIs/bridges, then connect the namespace tree to existing focus.
6. Execute every required real GUI constraint workflow and the complete task gate;
   publish only after full source-bound acceptance, otherwise issue a failure report.

No refactoring has started. Local GUI baseline/parity, all requested dev-059
implementation, and the complete acceptance matrix remain outstanding.

## Incremental consolidation checkpoint

The map above remains the original057 baseline inventory. Candidate audit05 now has31sources,587definitions,150renames and555loadedprocedures. Workspace state, scene sequencing and persistence have explicit owners;49rename wrappers removed. Candidate working report and CURRENT checkpoint identify actual parity tests and remaining GUI/task work. No full consolidation or acceptance PASS is claimed.

## Unpublished consolidation checkpoint11

Explicit state, scene, persistence, pointer, UI/open and semantic list controllers
now replace111 of199 original rename wrappers;88remain. Audit11 records actual
34source load order and599definitions/569loaded procedures. A new command registry
is being connected to all input surfaces; its bulk actions retain existing
history, Native exact reconstruction and canonical Dataset binding authorities.
Native scientific tangents are presentation-independent; point-backed semantic
segments now preserve explicit entity kind instead of guessing from row ordinal.
These changes remain incomplete and unpublished; source-bound GUI05/Native02
receipts and candidate working report describe their partial verification.


## Final unpublished Dataset ownership extension

CORE Dataset Metadata remains the sole private/ordinary metadata resource and
registry-index authority. Ordinary APIs filter/reject reserved _gxtxt fields;
private writes use CORE-issued module capabilities. Module activation and Viewer
open supply the trusted context; Python/Octave Bridge derives ownership from its
runtime module, not request arguments. Internal framework writes own namespace.
The existing catalog transaction wraps the single metadata commit, avoiding a
parallel commit store or additional per-public-operation wrappers.

Dataset namespaces reside in _gxtxt.framework.dataset_namespace. Current namespace
uses existing cfg/Session Manifest; the catalog reports both. V2/file publication
choose acquisition-current/module-default or explicit placement and preserve
placement for owned replacement. Legacy importer pinning coverage is unfinished.
The browser is a catalog projection; Preview's legacy choice name aliases the
existing Variables choice. It has no independent selected-Dataset authority.

Final audit12 remains34 sources,599 definitions,569 loaded Workbench procedures,
88 renames. That count scopes Workbench source, not new CORE Dataset APIs. Current
runtime GUI07 includes the default/named workspace-label corrections. Overall
release gate FAIL: see the implementation failure report. This is not a release.
