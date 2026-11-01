# TASK-9 / BUG9 — GX-TXT 0.9.8.10-dev-052 acceptance

One combined development cycle starts from the published, verified dev-051. Its archive, expanded inventory, restore and exact previous handoff are preserved. There is one worktree and one final release; no intermediate framework release or separate bug task is produced. All tests use private Sessions/XDG roots. Canonical user Sessions are not modified.

## Implemented scope and authorities

| Area | Final behavior |
|---|---|
| Dataset Transform | Complete typed projection/concatenation/filter/reversal/reordering/rename/affine/merge/key join/selection/family/extraction/split; common manifest planning, compatibility and metadata policies, bounded SQLite/binary transport, resource ownership and transactional publication. |
| Dataset storage / Preview | CSV/HDF5 parity; deterministic size-aware Auto; exact paged tables, goto and scientific headers, full-input calculations versus bounded display; source Schema/Metadata remain authoritative. |
| Catalog / selectors | Committed monotonic revision, snapshot/changed-since/subscriptions, shared selector-open refresh, coalesced advisory notifications and cascade to safe current Variable IDs; no polling timer/private registry consumers. |
| Multi-source selection / Extract | Independent source/member exact row identity and filters; Graph Selection, persistent Selection and dataset.extract delegate source resolution/science/publication to common CORE. |
| Metadata paste | Add multiple fields uses the existing portable `key=value` parser, first equals only, colon ordinary, full-block validation before editor changes; persistence only on Save. Import/Export retained. |
| Curve Fit source workspace | Additive stable Dataset and built-in sources, per-source preview/accept/visibility/remove/batches, exact filtered and selected input, accepted local geometry owned separately; atomic failed batch and frozen historical provenance. |
| Curve Fit science | Existing eleven models retained, X=f(Y), R=f(theta), ordered parametric polynomial/natural/periodic cubic, row/path/user parameterization, derivative/projection/residual conventions and exact model resource persistence. C-backed indexed cubic projection and sparse smoothing handle million-point foundations. |
| Curve Viewer | Additive read-only Dataset curves, style/direction/grid/aspect/polar, fit/zoom/pan, show/hide/remove, exact Preview, bounded native display, explicit export and persistent source identity. |
| Native2D geometry | Renderer-neutral aspect/grid/polar/direction/snapshot; retained point/line/construction/polyline/rectangle/circle/arc/ellipse/Bezier/spline definitions, native science versus explicit sampling; CAD groups/mirror/series/pivot/gizmos/nearest snap and physical scale distinct from unit conversion. |
| Constraints / topology | Native supported constraint families with explicit validation/tolerances/unsupported combinations; atomic endpoint joins, no general nonlinear solver assertion. Gap-aware primitives/bridges/composition/retained fragments preserve complete path direction and source lineage. |
| Measurement / comparison | Named logical captures, exact supported Native metrics/projections, explicitly sampled RMS/Hausdorff/closest policies, stale/missing/refresh, purple witnesses and exact-ID scientific reports, independent of viewport/display LOD. |
| Organization | Names/fragments/attributes, groups, Selection Sets, Layers, Saved Views, persistent highwater logical IDs and explicit stale references; Set names do not impose solver boundary-condition semantics. Parametric rectangular series retains independent originals, frame and regenerated members. |
| Construction/reference / units | Shared Native roles, default publication/export exclusion, explicit finite regular materialization; Unit Registry conversion reexpresses coordinates/parameters and preserves physical geometry, distinct from geometric scaling. |
| Curve Workbench publication | Common complete tuples for Dataset, edited source-row Native and unbound Native, explicit auxiliary absence/gap masks, Cartesian/polar/both, long full-member family and exact shared-X wide Schema, requested IDs, create-only collision and missing/stale source rejection. |
| Point-selection correction | Idle-coalesced selection synchronization, Native pending-selection lifecycle during held drag, scene/curve/lifetime generation checks and recursion guards. Stable point table refresh, Ctrl/Shift multi-selection, one-point X/Y, red Dataset-row locator and pure-Native distinction preserved. No blanket catch/drop of updates. |
| Native3D Workbench | Existing OCCT/VTK authority and shared renderer worker/IPC reused; real closed profile/plane/extrude New/Join/Cut/Intersect, B-Rep versus mesh distinction, tree/canvas/anchors/planes/sections, transform/gizmos/groups/alignment/constraints/measurements, full mesh repair/diagnostics/clip-cap and logical owned resource persistence. |
| Native3D comparison / organization | Complete surface and common-plane section comparisons with captured scientific policy, explicit stale refresh and unit conversion; shared role/Set/Layer/View/lock policy; candidate-scene structural mutations and exact rollback/one Undo. |
| Native3D exporters / consumers | Official complete STEP/STL/VTP export with Native quality/limits, read-only snapshot/revision, atomic geometry+inert JSON sidecar, canonical Dataset ID/contract/units/SHA/provenance; normal generic Viewer and Workbench Tool intake use public Dataset semantics. |
| Recipes / script extensions | Inert bounded semantic capture, resource/API/plugin/source/unit validation, controlled captured-result replay and Python export; ordinary Script Workspace and unchanged-source Builder W packaging, discovered typed actions and one transaction/Undo, disabled/absent/stale/failed proposal rejection. |
| Configuration / UI | Modules discovery/search/enablement/dependencies/Help/typed persistent settings with Session precedence; shared fields/color alpha/reset/inherit/chooser/validation, responsive control layout, scrolling keyboard focus, labels and narrow/font14 reachability. |
| Persistence / recovery | Interactive Document resources, atomic restore/SHA/symlink/lifetime checks, deleted-owner invalidation, highwater identity retirement, bounded explicit recovery journals, save/reopen, cooperative cancel and no implicit Registry pollution. |
| Script Bridge | Final provider-derived coverage:60 APIs. Python/Octave parity for safe public services, scoped logical geometry handles and owned resources; explicit host-only GUI/controller/raw destination exceptions. SB-014 remains the only authoritative remaining-work TODO. |

## User corrections

An entered Dataset name/ID is the requested public ID after standard validation and create-only collision checking. `my_fitted_curve` stays exactly that ID in Registry, Preview, Session, Plot Dataset and save/reopen. Generated IDs apply only where no ID is supplied/internal temporary resources. Common publication helpers implement the rule; Curve Workbench, measurement/deviation reports, Extract and geometry publication share it.

Built-in sample lineage uses `source_kind=builtin_sample`, `source_sample_id` and no source Dataset ID. Seven rich deterministic descriptors include sample ID/title/description, axis labels/units/semantic roles/value kinds, generator/model/version/parameters, scientific expectations and tolerance. Explicit Publish sample as Dataset transfers descriptors through normal Schema/Metadata. CSV sidecars retain the sample/real Dataset/accepted local CORE/published Dataset distinction.

The original `Native2D core clear selectionScene` busy crash is removed from synchronous Treeview selection handling. Rapid events keep one latest idle request. Native active gesture updates remain pending and apply after release; ownership/generation validation prevents stale updates. Table↔canvas refresh cannot recursively clear/rebuild. Native3D Escape similarly finishes its native gesture safely before preview re-render; old releases cannot finish a removed manipulator.

## Focused API / scientific acceptance

The reusable scripts are `validation/task9_dev052/`; workspace `SCRIPT_CATALOG.md` records exact arguments/version/side effects. All numerical claims use independent expected science or explicit native policies, never self-rendered appearance alone.

- Dataset Transform19 final PASS: CSV/HDF5 complete tuples, lineage, full selection/family policy, independent unit conversion, member-scoped reversals, exact requested-ID publication and late split rollback without catalog notification.
- Native Geometry PublicationFinal09 PASS: exact uint64 including18446744073709551615, text/descriptors, mixed unbound and edited Native/source rows, reversed gaps, Native bulk polar CW/theta-zero/deg/origin mask, long family/wide complete auxiliary Schema and presence, mismatched X and changed-owner atomic rejection.
- Native2D Bridge35 PASS: real registered Python and Octave scoped Native geometry/identity/primitives/series/constraints/measurements/comparison/views/roles, Source snapshot current/missing status and Native bulk-polar base64 contract; no implicit Dataset/source mutation. Native3D BridgeFinal12 covers independent surface and common-plane section science in both languages.
- Native2D C ASAN/UBSAN foundations cover aspect/grid/polar, coalesced selection and active drag, retained primitives, CAD/nearest snap/groups/series, constraints/join, identities/fragments, measurements/views/layers/Sets/direction/gap bridge/comparison. One-point primitives and invalid-output atomicity are included.
- Native3D engine/profile/scientific-mesh/role/comparison fixtures use complete geometry and independently known analytical volume/area/plane/distance/tolerance, complete STL/VTP/exact STEP reimport and malformed-input rollback. Existing native engine APIs and compatibility tests are reused.
- ResponsiveFinal04 PASS bounded event-loop/cancellation/owner invalidation and atomic commit. ResourcesFinal08 PASS1000 duplicate receipts and conflicting same-SHA size/generation rejection, complete binary fidelity/content hash/corruption/unsafe paths/restore rollback/readers. Lifecycle08 and LifetimeFinal14 PASS document deletion and A→B→A Session scope/highwater/stale-view preservation.
- Curve Numerical fixtures independently check polynomial/orientation/polar/parametric parameterization, C0/C1/C2 periodic seam, smoothing/PCHIP/Fourier/projection/geometric residuals and invalid input. GUI model/resource round trips reconstruct accepted science without refitting.

## Mandatory real GUI, usability and accessibility

These are actual Tcl/Tk windows with X11 pointer/key/clipboard interaction under Xvfb and the installed software Native3D backend. Public read APIs inspect independent science. Direct APIs alone are not counted as GUI acceptance. Failed exploratory attempts remain diagnostic evidence; accepted final logs below supersede them.

| Final evidence in workspace | Accepted workflow |
|---|---|
| `_validation_dev052_selectionFinal52.log` +fresh | Repeated single rows, rapid different rows/coalescing, Shift/Ctrl multi-selection, canvas click/held native drag/table synchronization, zoom/pan/switch curves, allowed X/Y edit, Escape, red row rings and save/reopen; Dataset-backed plus pure Native; no busy/Tcl dialog/stale request. |
| `_validation_dev052_fitIdentityFinal17.log` | Enter/publish `my_fitted_curve`, exact Registry/Preview/Plot Dataset and reopen; clear collision; complete built-in sample descriptor/Schema/provenance/CSV sidecar and explicit sample publication. |
| `_validation_dev052_publicationFinal09.log` +fresh | Real chosen CW/theta-zero90° frame, Dataset+independent Native full tuples, Cartesian/polar/both, long-family/wide masks/exactuint64/text, ID collision/Preview/source invariance/locator, save/reopen; keyboard Tab and font14/1100px publication+point/numeric Apply reachability. |
| `_validation_dev052_snapshotFinal02.log` | Normal exact source Preview, changed scientific Schema stale state/rejected tuple publication, missing-source reopen retains70001 owned local points and actionable Preview error without fake Dataset. |
| `_validation_dev052_fitLargeFinal11.log` +fresh | Million exact rows, independent fit/RMSE, bounded GUI/display/residual pages, loading/staging/active Numerical Escape, environment/handles, full accepted local result, size-aware exact-ID publication and restore without refit. |
| `_validation_dev052_fitWorkspaceFinal10.log` +fresh | Additive sources/batch previews/accepts/source switching/visibility, late-source atomic failure and frozen historical CSV ownership; local geometry creates no Dataset. |
| `_validation_dev052_fitRemoveFinal05.log` | Normal multi-source remove/selection/accepted ownership/persistence; deleted local source does not mutate its Dataset. |
| `_validation_dev052_configFinal04.log` | Modules search/real enablement/typed signed number/color/Session precedence/Help, narrow font14 Search/Save and reopen. |
| `_validation_dev052_datasetFinal02.log` | Metadata multi-field actual clipboard paste/full-block invalidity/Save/reopen/Import syntax, catalog notifications/selectors, CSV/HDF5/size-aware storage and bounded Preview. |
| `_validation_dev052_recipeFinal06.log` +fresh | Real recorder inspect/validate/export Python, ordinary Workspace staged result, unchanged source Builder W install/invoke, one Undo/Redo/source-plugin mismatch/no source mutation/row locator and test-plugin removal. |
| `_validation_dev052_recipe3DFinal07.log` | Real3D recorder/scientific replay, independent volume/placement, staged multi-action extension rollback and one Undo. |
| `_validation_dev052_cfdFinal03.log` +fresh | Full CFD profile/plane/extrusion24, real move/rotate/cancel/camera/NavCube, physical scale/transforms/group/align/constraint/union36, sections/measure3/area66/tessellate/repair/zero boundaries/crossings/cap18; official complete export and exact cfd_final_surface Dataset, normal Workbench Tool import/one Undo and generic Viewer exact ID/SHA/render/source invariance/reopen. |

Additional accepted real-GUI evidence includes Curve ViewerFinal04/fresh, Workbench Large15/fresh, Units09 and UnitsBulk07/fresh, shared Grid/Polar presentation, Direction10, Sketch08/09, Constraints04/Join02, Identity03, Bridge20/fresh, Series06/fresh, Collections05/fresh, Views05, Roles02/fresh/whole-sketch exporter, Measurements03, Comparison04/fresh, Export2D02/Export3D04, native3D Organization07/fresh/font14, Structural04/Combine05/Extrusion02, SurfaceComparison04/fresh and SectionComparison01/fresh, RecoveryGUI03 and DocumentDeleteGUI06. The workspace progress record lists the exact evidence directories and intermediate diagnoses.

Accessibility review covers default and larger fonts, narrow windows, keyboard traversal/activation, scrollable fields/tables/sidebar, complete unit/ID headings, visible validation/status and Save/Apply/Close, semantic selection beyond colors, contrast/alpha field normalization and cancel/error/rollback state. Publication/Workbench numeric scrolling, Preview headers/paging, organization tables/footer and shared form nested scroll were corrected after visual review. Screenshot artifacts live in private evidence directories. No claim of a screen-reader/platform/hardware matrix is made.

## Focused performance

| Scientific path | Local evidence |
|---|---|
| Native bulk polar1million | .108335 CPU seconds, ASAN; finite complete rows, independent translated/CW/radian values. |
| Native3D comparison | Two1million-triangle targets,501501vertices each,128 bounded reports:3.409204 CPU seconds; full target acceleration versus bounded query budget. |
| Indexed cubic projection |1million queries:2.291seconds, independently known geometry. |
| Sparse smoothing |1million straight-line input:.609seconds, independent solution. |
| Native2D CAD affine |1million points:.095seconds, complete exact geometry. |
| Native2D geometric comparison |1million-row bounded target:.319seconds, ASAN. |
| Final real Fit1million | Load11.319s; exact fit12.328s; full publication13.193s, including GUI/event/storage overhead. All scientific points retained; bounded GUI/native display and cancellation tested. |
| Duplicate resource collection |1000 identical receipts validated once per scan; conflicting receipts independently reject. Whole-document payload is not reread/hashed for each owner lookup. |

These are focused local Debian measurements, not promises for every machine. Counts, sample budgets, quality, actual storage provider and timings are explicit in the fixture receipts.

## Public policies and limitations

- Retained math/native geometry and Dataset identity remain distinct until explicit materialization. Exact complete source tuples, full native geometry and bounded display caches are never conflated.
- Native coordinate-frame science is explicit. Origin angle is undefined with a validity mask; normalization/unwrapping/degree conventions are recorded. Wide output never silently interpolates.
- Continuous Hausdorff extrema/general nonlinear constraint solving/robust triangle-mesh Boolean are not claimed. Metrics state sampled versus exact-supported projection and B-Rep versus mesh applicability. Unsupported combinations reject clearly before mutation.
- Recipes use captured scientific results and Session-owned resources, not version-dependent recomputation or an independently portable script with missing inputs. Size/history/resource bounds and explicit recovery choices remain enforced.
- Raw widget/controller/native-pointer/file-destination operations remain host-only. Deferred SB-014 is the sole remaining authoritative TODO, with the current dev-052 header.
- Release validation targets the installed Debian native stack/Tcl/Tk/Python/Octave and actual GUI workflows; no unsupported platform matrix is claimed.

## Documentation and packaging

Current README/changelog, Dataset/Transform/Source/Preview/catalog/metadata/publication/streams, Native2D/Native3D/units/constraints/primitives/measurements/roles/persistence, shared UI/config, recipe/extensions/Builder and manuals/help/architecture/API inventory/60-API bridge coverage describe final behavior. Public examples use public APIs. Reusable final fixtures ship under `validation/task9_dev052/`.

Changed/new external packages have matching full SHA manifests, embedded current_dev ZIPs and ordered archives/expanded pairs. Native2D CORE and Curve Workbench copies match, Native3D engine/shared adapter match their reviewed source/build. Final framework archive/expanded/active/alias/restore inventories are verified before declaring release completion. The exact051 handoff is retained separately before replacing the current handoff with full052 identity, checksums and acceptance.

Prepublication main application startup and official Plugin Install descriptor inspection passed in `_validation_dev052_prepublicationSmoke02.log`. All eight new/changed packages declare framework_min=0.9.8.10-dev-052, reject the predecessor and have full ZIP/expanded/embedded/SHA parity (`_validation_dev052_packages_final.log`). Previous package versions remain preserved.

Final owner-deletion regression: after missing-source restore, deleting the live Document releases cached Native geometry without attempting to close an absent Curve Source token. `_validation_dev052_snapshotDeletionBefore.log` reproduced the cleanup error; `_validation_dev052_snapshotDeletionAfter.log` validates the correction and unchanged stale/missing source workflow. Final Bridge inventory explicitly maps Native bulk polar and host-only shared scrolling/layout commands.
