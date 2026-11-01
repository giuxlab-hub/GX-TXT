# GX-TXT dev088 — integrated scientific foundations technical handoff

Authoritative assignment: `GXTXT_CORE_INTEGRATED_FOUNDATIONS_ASTRA_TASK_v5.md`,
read in full; v5 supersedes earlier tasks. Release **0.9.8.10-dev-088**, incremental
from verified published/installed dev087. Manual acceptance is **PENDING**.
This report describes implemented and tested behavior, not user acceptance.
Final publication hash and installed-process results are recorded in the versioned
external handoff and `publication.json`; the archive's hash cannot embed itself.

## A. Release, baseline and installation

Baseline archive SHA-256:
`e1a160d181bf682f7328dc474b706e4344ccc1b4e13c745c70fb17eb7ddcca29`.
All 5,303 baseline manifest files were checked against expanded/active trees before
development and rechecked before release. Development was isolated in
`/home/giu/electronics-server/work-agent/TK_GIUXLAB/_work_gxtxt_dev088_astra`.
The cleanup agent's final `GXTXT_DEEP_CLEANUP_20261012/REPORT.txt` explicitly states
all deletion work completed, no subsequent workspace cleanup/metadata edits, and
protection of Astra development. Its final audit has no protected/library changes.
No cleanup scripts or cleanup files were modified. No historical deployment script
was run. The new publisher is `validation/astra_dev088/release.py`.

Delivery paths (server):

- Archive: `/home/giu/electronics-server/scripts/GXTXT/framework/archives/gxtxt_pipeline_v09810dev_088.tar.gz`; adjacent `.sha256` is authoritative.
- Expanded: same root, `framework/expanded/gxtxt_pipeline_v09810dev_088`.
- Active: `/home/giu/script-ag/current/gxtxt`; alias `/home/giu/ag-script/current`.
- Restore: `/home/giu/electronics-server/work-agent/restore-points/gxtxt_pipeline_v09810dev_088.tar.gz` and sidecar.
- Preserved previous active tree: workspace `_backup_active_dev087_before_astra`.
- Plugins: `external_plugins/{archives,expanded}/viewer.curve_workbench_2.14.0` and `viewer.native_3d_0.9.5` (archives use `.zip`). CW requires framework dev088. Built-in modern Viewer remains 0.1.4. All previous packages remain.
- DEMO: ordered `DEMO/SESSION/GXTXT_DEMO_dev088`, portable `DEMO/EXPORT/GXTXT_DEMO_dev088.zip`, also included as framework `demo_sessions/GXTXT_DEMO_dev088.zip`.
- Evidence: workspace `_evidence_astra_dev088`; curated release evidence `docs/evidence/dev088/`.

Native build: Debian x86-64, `/usr/bin/c++`, VTK 9.3, existing retained OCCT
sysroot. No alternate renderer/backend introduced. Build command is cataloged
`build.py FRAMEWORK PRIVATE_BUILD`, with two candidate shared libraries copied.
ELF IDs: libgx3de `8e522f179821bad09033fb30ceea0c0f61ea73a1`;
Tcl transport `a5882761f472708155064cb0739af2cc26ca47db`.
Library SHA-256 values are in the framework manifest. Linux/X11 software rendering
was tested on the real Debian desktop, DISPLAY=:1. Other platforms need matching
native compilation. Existing user processes are preserved; restart to load dev088.

## B. Authority and architectural decisions

Modern Native3D/libgx3de remains the numerical/geometric/rendering authority;
Native2D retains curve definitions, constraints, image transforms and interactions.
The modern Viewer hosts CORE operations; Curve Workbench is the existing editor.
Interactive Documents/Resources own persistence. Unit Registry, canonical Dataset
Publication, Geometry Exchange, Scientific Multiview, Script Bridge and established
Installation Identity/Object Origin authorities are extended, not duplicated.
No second scene manager, renderer, image calibration engine or geometry solver.

Numerical constructors create native retained scientific objects directly from
finite numeric arrays. Indexed triangle meshes validate geometry; connected
PolyData supports vertex/line/polyline/triangle/polygon cells and point/cell arrays.
Masked grids remove complete incident quads at missing corners, retain source
indices and never interpolate. Circular sweeps create actual persistent triangles,
with per-point radii, transported frames, optional caps and source ring/segment IDs.
Zero/reversing/invalid paths fail; collision correction is not implied.
Lossless VTP restores arrays/connectivity. Legacy mesh intake remains geometry-only.

A working plane is O,N,U,V with normalized orthogonal right-handed basis V=N×U,
in one declared physical unit. World=O+uU+vV+wN; explicit Unit Registry conversion
handles differing axis units. Plane mapping includes valid UVW inverse; projection
sets w=0 and has no unique inverse. Invalid basis/units fail before owner commit.

Sections intersect the complete scientific mesh via the existing native section
engine; no visible-surface approximation. Disconnected/open/closed contours are
retained with explicit join tolerance. Supported OCCT B-Reps use native sections;
the resulting sampled profile is not claimed to be an analytical CAD curve.
Orthogonal projection flattens every source point, preserves scientific arrays,
retains overlaps and may degenerate cells. Editable projection follows actual source
boundary loops. It is not a silhouette. Closed solids retain full projected surface
but may have no editable boundary. STEP projection requires explicit tessellation.

Reference image: actual source-only modern native render, camera from +N, up=V,
explicit orthographic physical height and viewport aspect, clipping covers source
bounds, cube/plane/axes omitted. Resource metadata records normalized plane, source
SHA, camera, units, dimensions, translation and physical units per pixel. Native2D
uses bottom-left pixel edges: XY=translation+scale×pixel. Native3D top-left screen
coordinates describe centers: x_edge=x_screen+0.5, y_edge=height-y_screen-0.5.
The existing Native2D image attachment/calibration owns the actual overlay.

A `gxtxt.native3d.planar` v1 Document belongs to `viewer.engine_3d/engine_3d`.
It retains source resource, geometry diagnostics, plane, section, projected surface,
editable definitions, reference, accepted result, presentation and provenance.
Worker/object/profile tokens are never persisted. GUI intake creates a separate CW
workspace. Begin captures Session lifetime, document generation/revision/SHA. Accept
validates original source and definitions, derives a new planar curve, revalidates,
then performs one owner checkpoint. Cancel leaves the owner unchanged. Failed
staging collects unreferenced resources. Stale/deleted source cannot accept.
Saved drafts reacquire fresh tokens only for the same durable source identity;
stale drafts retain contents and expose Cancel, with Accept disabled. Closing CW
cancels its pending focus callback and edit token. Draft save is explicit.

Accept creates a new curve on the plane, never a mesh deformation or guessed depth.
Straight retained paths preserve all vertices; nonlinear edited families use 257
samples and are labeled approximate. Closure is stored separately from repeated
Native2D display endpoints. Source resources are immutable.

Selective presentation uses new target-object native update: styles/opacity/visibility
update the requested props without a whole-scene rebuild, camera reset or worker
replacement. Scalar/representation changes use the established full refresh path.
Source document revision is independent of presentation. Native render counters
prove the tested fast path. A discovered real transparency bug was fixed: VTK depth
peeling must disable multisampling when translucent props are present. Effective
MSAA=0 is explicit; opaque rendering keeps requested MSAA. This restored actual
source/working-plane translucency instead of silently missing translucent geometry.

Logical identity is client-provided exact `logical_point_id`/`logical_cell_id`
(nonnegative integer <=2^53−1), persisted in scientific arrays. Native picks resolve
it, never treat transient renderer indices as durable identity. Contour exports use
stable within-document contour IDs. Multiview maps `{layer_id association logical_id}`
to each related Native2D object. CW uses source document/revision plus contour ID;
selection focuses a native anchor and reverse picks highlight the related curve.

Geometry Exchange captures saved owners into managed resources, transports bounded
1 MiB chunks, validates integrity/lifetime, and uses existing atomic import. Limits
are now 16,384 objects/groups and 64 MiB transport; destination Documents remain
32 MiB. The implementation is a bounded retained snapshot, not unbounded native
streaming. Live descriptors stay same-Session; Session Portable carries committed
scientific resources independently.

Origin extends the existing representation: new scientific Documents, generated
resources and Dataset containers record the established installation creator and
parent source/session/owner identity. Imported raw resource creators remain unknown
unless supplied; local receive events do not invent authorship. Replacements retain
original Dataset creator. Geometry copies/derivations preserve parent origin and
receiving installation. Existing installation ledger/history/regeneration/recovery
was reused unchanged, verified in isolated roots, and preserved at deployment.

## C. Modern Viewer and D. historical deprecation

Modern `viewer.engine_3d` gains the Working plane / Curve Workbench dialog, saved
workflow selection, Source/Plane+results/Section/Projection/Plane-normal/Accepted
views, section/projection edit intake and logical contour focus. Existing orbit,
pan, zoom, resize, working-plane fields, layer properties and native worker remain.
Source color arrays and real source scale are retained. Saved workflow actions
reconstruct layers from verified resources; reference is orthographic and calibrated.

Historical `viewer.native_3d` remains installed with identical stable ID/backend/API.
Only its module descriptor, package descriptor and manual mark Legacy / Deprecated,
add replacement `viewer.engine_3d`, and increment package metadata to 0.9.5. Its
implementation was not removed or repurposed. Modern CORE `native3d` filenames are
not the deprecated provider. No new workflow runs through its backend. Existing
bundled dependencies remain compatible; no redundant dependency proof campaign.

## E. Curve Workbench

Intake uses actual retained Native2D paths, source contour identity and existing
workspace persistence. Calibrated locked reference image shares the physical frame;
existing display order retains background/raster then grid and editable geometry.
Show 3D Reference Image and a separate 0–100% opacity slider affect only the image.
Existing selection, handle editing, snapping, grid, pan/zoom, Undo/Redo and Save
remain authoritative. Accept and Cancel return to the modern Viewer with clear
semantics. Repeated intake creates distinct workspace names. Existing ordinary CW
GUI creation/edit/history/save and source-backed section/projection editing were
exercised. Dense contours need zoom to isolate adjacent handles; no decimation is
silently applied to the scientific profile.

## F. Changed files, public entry points and renames

Exhaustive changed/added file lists and hashes are supplied as
`DEV088_CHANGED_FILES.json` in this report directory and the publication receipt.
The dedicated git baseline records exact source changes. Groups:

- Native3D header/CMake/engine/renderer plus new numerical C++ source: constructors,
  logical IDs, lossless VTP, selective props, transparency; rebuilt two libraries.
- Native3D Tcl adapter/worker plus new numerical include: validated marshalling,
  plane mapping, projection/profile, discovery, pick/focus and presentation RPCs.
- CORE geometry/provider/GUI Tcl: additive capabilities, axes conversion, explicit
  orthographic camera/clips, layer color-array and selective GUI host path.
- New planar workflow/GUI Tcl: owner documents/resources/transactions and modern
  Viewer integration; framework loader sources these directly.
- CW API/UI/state/selection/persistence and new planar adapter: intake/reference,
  selection correspondence, Accept/Cancel, saved-draft lifetime and close cleanup.
- Geometry Exchange and Scientific Multiview Tcl: bounded resource transport,
  source origins, per-element descriptors and mapped pick/focus.
- Document/resource/Dataset publication plus new scientific-origin Tcl: reuse of
  established origin and installation authority; no new identity namespace.
- Python Script Bridge geometry/origin bindings: typed numerical/frame/conversion
  receipts and read-only origin discovery, usable from Python and Octave.
- Version markers, two plugin descriptors, legacy manual, API guides, this report,
  unfinished-only TODO, script catalog, validation/evidence and portable DEMO.

Public additions: native C `gx3de_scientific_masked_surface`,
`gx3de_scientific_sweep`, `gx3de_scientific_logical_id`, scientific VTP write and
`gx3de_target_object_presentation_set`; Tcl `native3DGeometryCall` new actions
indexed_mesh/polydata/masked_surface/sweep/load_scientific/logical_id/plane_frame/
project/projection_profile; `native3DGeometryConvertAxes`; planar ApiInfo/Create/
List/Show/Focus/EditBegin/EditAccept/EditCancel; Geometry Exchange ExportResource/
ImportResource; documentOriginRead/datasetOriginRead/resourceOriginRead. Existing
Multiview mappings and Viewer scene/layer fields extend their current contracts.
Exact argument schemas, units, budgets, errors and Tcl/Python/Octave examples are
in the modified API manuals and `INTEGRATED_FOUNDATIONS_dev088.md`.

**Actual rename/refactoring operations: none.** Existing definitions were edited
at their real source; additive helpers are directly loaded. No new `rename ...
*_base`, wrapper chain, duplicate replacement authority or alias stack was added.
Pre-existing wrapper remediation remains a separately scoped TODO.

## G. Executed requirement and cross-capability matrix

Paths below are relative to curated `docs/evidence/dev088/`, unless noted.
Every PASS is an engineering result; manual acceptance remains pending.

| Requirement | Implementation and executed evidence | Result |
|---|---|---|
| R01 | Native indexed mesh, finite/index/degeneracy/budget validation, resource VTP round trip; core03, bridge-final, native-final | PASS |
| R02 | Connected cells/arrays, durable IDs, 100 curves in one layer; core03, picking-final2, multiview01 | PASS |
| R03 | Declared mask removes incident quads, source indices/no interpolation; native-final, core03 | PASS |
| R04 | Persistent variable-radius transported sweep, caps/topology/export; native-final, core03, Python/Octave bridge-final | PASS |
| R05 | Existing color/scalar/representation/radius controls, new color-array path and selective style; real Ticino/Bunny, picking-final2, reopen-final, Thermal regression | PASS within documented backend/representation bounds |
| R06 | Selected object props, geometry-rebuild counter/camera/worker/document unchanged; picking-final2, reopen-final | PASS |
| R07 | 100 real renderer picks resolve 100 logical IDs in one object; picking-final2 and actual GUI Multiview two-way picks | PASS |
| R08 | Normalized world/plane mapping, units, image edges/view centers; native-final, bridge-final, two-plane picking-final2, scientific-final | PASS |
| R09 | Actual CW section/projection edit, Undo/Redo, Accept/Cancel, stale/lifecycle and restart; demo-final, reopen-final, lifecycle02, draft-restore | PASS |
| R10 | 1,100 retained objects transported through managed resource, cancel/stale/unchanged target; core03 | PASS bounded transport |
| R11 | Actual reference overlay, two calibrations, mapped picks, pan/zoom/resize, independent opacity; scientific-final, demo-final, reopen-final, multiview01 | PASS |
| R12 | Headless discovery and typed script routes, explicit errors/limits; core03, origin tests, bridge-final | PASS |
| R13 | Public callable schemas/examples/manuals, portable no-external-file DEMO, clean-process reopen | PASS |
| I01 | Pre-existing persistent identity; existing identity fixture concurrency/independent roots/restart | PASS reused |
| I02 | Pre-existing deliberate rotation only; identity-final | PASS reused |
| I03 | Pre-existing retained history; rotation/pending/corrupt recovery identity-final | PASS reused |
| I04 | New scientific Document/Dataset/resource/derivation origins; origin-create01/receive01 across independent installations | PASS extended |
| I05 | Established CORE-owned ledger mutations; scientific routes only read creator, public origin discovery read-only; identity-final and publication identity hash | PASS preserved |
| I06 | Existing identity discovery plus scientific document/dataset/resource origin read operations; origin-create01/bridge-final | PASS extended |
| I07 | Existing concurrent issuance/recovery/conflict refusal; identity-final, unchanged actual installation ledger | PASS preserved |
| I08 | New scientific source/derivation/copy lineage integrated with established Session transfer; origin receive + portable import | PASS extended |
| F-A | Numerical geometry through native/Tcl/Python/Octave, immutable source and durable resources | PASS core03/native-final/bridge-final |
| F-B | Durable 100-feature identity and real cross-view selection | PASS picking-final2/multiview01 |
| F-C | Actual CW handle edits and owner commit | PASS demo-final/reopen-final/draft-restore |
| F-D | Resource exchange exceeds previous 1,024 bound; cancellation/stale/rollback | PASS core03 |
| F-E | Existing identity plus scientific portable lineage/unknown source policy | PASS identity-final/origin-create01/origin-receive01 |
| F-F | Public Tcl/Python/Octave discovery and numerical use | PASS core03/bridge-final |
| F-G | Two real meshes, physical planes, section/project/reference calibration | PASS demo-final/scientific-final |
| F-H | Interactive return, Save/reopen and portable independent reproduction | PASS reopen-final/draft-restore; installed receipt in external handoff |

| Real GUI test | Executed actions and evidence | Result |
|---|---|---|
| GUI-3D-01 | Both full source meshes, real modern renderer; E01, viewer.png | PASS |
| GUI-3D-02 | Physical visible plane and translucent source; E02 | PASS |
| GUI-3D-03 | Section contours on plane; E03 | PASS |
| GUI-3D-04 | Full flattened source and boundary projection; E05, projection CW edit | PASS |
| GUI-3D-05 | Plane-normal orthographic reference; E06, numeric calibration | PASS |
| GUI-3D-06 | Accepted real edited retained curves in same modern Viewer; E12 | PASS |
| GUI-3D-07 | Clean process resources/reconstruction, orbit/pan/zoom/resize; E13/reopen-final | PASS |
| GUI-CW-01 | Real section intake/retained handle edit, both meshes; E07/E11 | PASS |
| GUI-CW-02 | Projection intake/handle edit/Accept; reopen-final/projection-workbench.png | PASS |
| GUI-CW-03 | 0%,25%,45%,99%,100% independent reference opacity; E07/E08/E09 | PASS |
| GUI-CW-04 | Real show/hide and retained geometry; E10 | PASS |
| GUI-CW-05 | Scale/translation/rotation/calibration unchanged under pan/zoom/resize | PASS reopen-final |
| GUI-CW-06 | Actual edited definition, Undo equals original, Redo equals edited | PASS demo-final |
| GUI-CW-07 | Independent Cancel and Accept, lifecycle failures/stale/deleted owner | PASS reopen-final/lifecycle02 |
| GUI-CW-08 | Saved draft reopened in second process, hidden 37% reference, fresh token Accept | PASS draft-save2/draft-restore |
| GUI-CW-09 | Ordinary creation, handle edit, Undo/Redo, Save with no planar context | PASS workbench-final5 |

The previous dev087 Thermal GUI campaign was rerun against dev088: axes/grid,
six rotations/reset, resize/large window, native export, canonical image Dataset
publication and normal reopen passed. Original Thermal/Ticino Sessions are verified
unchanged by release baseline/publication. Tests only use private copies.
Failed developmental attempts remain in private evidence, clearly excluded from
this final PASS set. These included test harness timing, missing Finish on ordinary
Line construction, clicking a hidden historical Select widget, and the repaired
translucency/draft-token issues. No evidence was silently deleted or relabeled.

## H. Scientific evidence

Bunny is Stanford Computer Graphics Laboratory's real zippered scan (35,947 points,
69,451 triangles, original holes/attributes retained). Source repository:
https://graphics.stanford.edu/data/3Dscanrep/ . Original archive SHA
`a5720bd96d158df403d153381b8411a727a1d73cff2f33dc9b212d6f75455b84`;
PLY SHA `b1acc63bece78444aa2e15bdcc72371a201279b98c6f5d4b74c993d02f0566fe`.
Scanner metric is not inferred. DEMO explicitly models it at 150 mm height.
Stanford research/free redistribution terms and noncommercial restriction are
retained; third-party data are not relicensed as GPL framework code.

Ticino is the existing real terrain/population-density geometry from verified
dev087 p0004 evidence (5,440 points,10,586 triangles). Graph axis declarations
km/km/m explicitly convert to m/m/m; scalar and original flat-cell RGB persist.
Original Dataset schema units are not overwritten. Actual physical aspect is kept.

| Quantity | Bunny (mm) | Ticino (m) |
|---|---:|---:|
| Workflow / Dataset | idoc_0002 / bunny_model | idoc_0005 / ticino_model |
| Original + normalized source Document | idoc_0001 | idoc_0004 |
| Plane origin | (0,80,0) | (35000,40000,300) |
| Input normal / U | (.2,1,.3) / (1,0,0) | (0,0,1) / (1,0,0) |
| Section tolerance | 1e-6 | 1e-5 |
| Section points / contours | 788 /1 | 516 /13 |
| Maximum section plane residual | 8.63e-15 | 0 |
| Maximum sampled section/source distance | 3.59e-15 | 1.20e-12 |
| Every projected vertex error | 5.69e-14 | 0 |
| Accepted plane residual | 1.48e-14 | 0 |
| Reference pixels | 1024×768 | 1024×768 |
| Physical units per pixel | .22263642880109039 | 113.15104166666667 |

Scientific JSON stores exact hashes, normalized bases, bounds, generation/revision,
image translations, counts and residuals. Projection checks cover every source
point and array; section/source closest-surface check samples31 actual contour
points independently with VTK. Calibration verifies four independent points in each
of two frames plus actual Native2D image inverse. Native screen registration error
<1e-9 pixels, inverse <1e-10 working units. Original full source VTPs are retained.

Curated E01–E12 are in `demo/{bunny,ticino}/`; E04 reuses the actual oblique Bunny
E03 frame, explicitly the same section. E08-low-opacity is25%; E08-zero separately
proves0%. E07 starts45%; E09-full is100%; E09-intermediate is99%. E10 hides image;
E11 is actual GUI edit; E12 actual accepted render. `reopen/E13-idoc_*.png` verifies
both reopened models. `viewer.png` and CW captures are actual X11 windows;
Native3D PNGs are actual backend renders, not screenshots of placeholders.

## I. DEMO and independent reproduction

Open a writable copy of ordered `DEMO/SESSION/GXTXT_DEMO_dev088`, or import the
portable ZIP into a new directory. It carries all resources and declares **zero
external file dependencies**. Source Documents preserve original/normalized VTP;
canonical Datasets are `bunny_model` and `ticino_model`; planar documents are above.
The portable package includes `DEMO_README.md`, `DEMO_MANIFEST.json`,
`SCIENTIFIC_EVIDENCE.json`, SHA256SUMS, original PLY/archive/source attribution and
E01–E13. It does not require the development worktree or a network connection.

GUI procedure: restart installed GX-TXT; open Session; open `viewer.engine_3d`;
Working plane / Curve Workbench; choose document; inspect six view modes; Edit
section/projection; toggle image/opacity; zoom and drag a handle; Undo/Redo; Accept
or independently Cancel; Save workspace and Session; reopen. Expected counts and
visuals are in DEMO_README. All command-line reproduction scripts require fresh
output directories and isolate XDG/identity. Full argument/side-effect catalog is
in SCRIPT_CATALOG. Public bridge fixture contains executable Python/Octave examples.

Canonical portable export/import was independently tested. Clean-process GUI
reopen used a private copy; final installed-process portable import and GUI result
are appended to external handoff after installation. The candidate report does
not pretend those post-publication results existed before archiving.

## J. Limits and next-agent state

Bounded numerical budgets:1M points/cells,6M connectivity entries,64 arrays/16M
Float64 values,64 MiB request; sweep <=1M ring vertices plus caps; profiles4096
contours/1M points; raster16–4096 per side. Tcl masked inputs still require finite
coordinates even at missing points. Logical IDs must be exact representable integers;
uniqueness remains client's declared scientific contract. Array types are numeric
Float64; unsupported string fields do not silently convert. Lossy formats are explicit.

Projection is orthogonal full-source/boundary, not visibility/silhouette analysis.
No depth inference, automatic reverse mesh/CAD deformation, sweep collision repair,
unbounded stream or cross-Session live exchange. B-Rep sections are sampled; CAD
reference/projection uses explicit tessellation. Scientific selection focuses an
anchor/related curve, not arbitrary CAD subshape editing. Styles outside the selective
fast path use normal refresh. GUI creation directly supports VTP/STL/OBJ; STEP
requires documented Tcl tessellation options. Other OS/backend builds are untested.

TODO removed the completed Astra scientific origin/R outcomes. The old large-exchange
follow-up was narrowed to unbounded streaming, cross-Session live descriptors and
unsupported frame/source-adapter cases. All previous manual-acceptance and unrelated
items remain. Added only dev088 manual acceptance. Historical legacy wrapper chains,
advanced rendering/layout, undeclared imported STEP units and unrelated module work
remain explicitly outside this assignment. No automatic post-release cleanup.

Next action is **manual acceptance**, not additional engineering or an intermediate
release. Preserve dedicated candidate, final evidence, baseline backup and previous
archives. Use the versioned external handoff/publication receipt for exact final
archive hash and installed verification. Do not rerun version-pinned publishers.
