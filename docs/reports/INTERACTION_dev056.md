# GX-TXT dev-056 frozen interaction implementation and acceptance

The source baseline is the published and validated dev-055 archive, SHA-256
`a786716eff7caf38f8ca7ddaa975a2b2c3c86d61571d0b282af07e3e790922b5`.
The sole candidate is `_work_gxtxt_dev056`, copied from its matching canonical
expanded release. The versioned dev-055 handoff was the baseline authority.
Published releases, `_work_gxtxt_dev055`, previous handoffs, unrelated modules
and canonical user Sessions are preserved. See `DEV056_AUDIT.md` for the complete
authority/reuse audit and the deliberately omitted optional Line conversion.

## Implemented frozen scope

The shared Tk viewport host supplies nine semantic anchors, deterministic
priority lanes, collapsible scrollable panels, font-scaled framework raster
glyphs and accessible fixed chrome. Eleven standard view actions use existing
Native view/grid/aspect authorities. Controls wrap and overflow into More in
small windows. Explicit panel reopening overrides automatic compact layout.
Workbench Settings controls the existing utility panels; Sketch and the lower
Compare/residual area collapse without reserving empty canvas space. Semantic
right-click menus combine checked Native control/segment/object actions with
Workbench publication/conversion actions. Widget paths and transient feedback
remain host-only, never another scene or saved geometry authority.

Segmented curve exposes the existing retained Polyline prominently. More than
ten segments, individual controls/segments, semantic closure and existing
constraints use the same retained authority. Continuous Line still creates
independent connected objects. Conversion is not advertised: preserving every
constraint/fragment/group/captured ordinal/provenance reference needs a separate
reviewed topology transaction. Existing Mirror retains editable picked axes,
correct numeric initialization, separate outputs and Undo/Redo.

Optional spline tangent offsets extend the existing cubic evaluator. Dense
knot-relative incoming/outgoing offsets share evaluation, derivatives, bounds,
solver parameters, transforms, units, history and serialization. Legacy missing
arm records reproduce the original Catmull-Rom curve exactly. Endpoints expose
one relevant arm; internal knots expose two independent controls. Native C owns
all geometry and solver decisions. The extended C POD requires zero initialization
and rebuilding consumers; the three shipped adapters are identical. There is
no claim of a binary-compatible old struct size or periodic topology.

Reference rasters are immutable existing Interactive Document resources. Native
owns retained rectangle geometry, similarity transform, opacity/visibility/lock,
calibration pixel points and derived physical distance. Pixel coordinates use a
lower-left origin; Pillow's top-down device mapping is explicitly inverted.
Calibration uses one uniform scale, and normal attachment starts in equal XY
aspect. Nonuniform stretch/reflection rejects atomically. Calibrated points are
real controls usable by existing references and dimensions. Solver edits change
the retained transform, never pixel coordinates or a duplicate calibration scale.
Working-unit conversion uses the existing Unit Registry and updates the unit
label. Changing points in an active relationship rejects.

Axis-first symmetric construction reuses existing reflection and persistent
Symmetry constraints. Preview, source, mirror and relationship commit through
one Native transaction/history action. Source edits follow through the existing
solver. Unsupported families and explicit tangent symmetry reject; no false
exact result, periodic spline claim or new global solver is introduced.

Session Workspace API extends the existing Document registry with metadata and
registered providers. Multiple named Workbench workspaces have distinct IDs,
payloads, resource ownership, notes and previews. The Session window lists type,
provider and preview, refreshes after changes, and opens through the provider.
Generic UTF-8 notes reuse the existing GX-Markup editor/renderer. Export/import
uses existing Portable Resource ZIP tooling; hashes, collisions, provider state,
resource ownership and remapped payloads validate before exposing a new workspace.
Failed imports discard private staging. Nested managed receipts are transported.

Current/fit canvas PNG previews use Native view transforms and presentation
snapshots with bounded dimensions and managed destinations. Shared raster
underlay precedes vectors; opacity alpha blends over actual underlying pixels.
Line styles, direction markers, optional grid/axes/dimensions/constraints/text
use scene data. Selection, gizmos, UI chrome and host transient feedback are
excluded. A guarded synchronous render restores view and feedback even on error.
Pillow is an explicit host raster dependency; Python does device compositing,
not model geometry or calibration. Raster dimensions/cache and script writes are
bounded. Existing immutable resource writers implement SB-014 destinations;
scripts never supply arbitrary host paths or callbacks.

Portable scoped Native2D operations include views/mapping/tolerance, tangent
get/edit, image attach/state/calibration/mapping, symmetry preview/construct and
canvas preview. Workspace, managed-resource and note APIs have public registration,
Python typed receipts and common Octave transport. Tk layout, file dialogs,
context acquisition and pixel glyphs are host-only discovery policies.

## Validation and evidence authority

Focused fixtures run real X11 pointer/keyboard workflows, normal WM close,
fresh-process continued editing, dirty crash recovery and cross-Session package
GUI opening. Workspaces have separate notes and previews. Independent C fixtures
check legacy equality, endpoint/lock/rejection, affine tangents, finite-difference
G2 direction/curvature, calibration mapping, solver-driven scale, unit conversion,
symmetry persistence and atomic rejection. Pixel oracles independently verify
raster/vector blending, layer opacity/visibility, selection/transient exclusion,
current versus fit, deterministic hashes and error-path state restoration.

Both Python and Octave execute through genuine Script Workspace processes;
headless Tcl API calls alone are not counted as language acceptance. Existing
relevant dev-055/dev-054 GUI/scientific suites cover chaining/attachment/closure,
mixed selection, combined/separate publication, units, graphical constraints and
dimensions, Fixed rejection, representations, Curve Fit clipping, recovery and
main startup. The final runner requires 19 CTest, 19 ASAN/UBSAN fixtures and all
18 scientific cases, including the million-row persistent workflow.

The final source and installed `acceptance.json` receipts contain actual process
commands/exits, log hashes and an unchanged behavior digest. They are validated
by `_validation_dev056_source_gate.json` and the post-publication/release gates;
this report does not substitute for a PASS receipt. Rejected exploratory logs
are retained and never rewritten as passing evidence. Publication compares full
archive/expanded/active/alias/restore inventories and package parity, preserving
all frozen predecessor hashes. TODO gates compare current authoritative bytes,
including archive/restore, with missing/stale negative checks. Versioned-first
handoff gates compare actual CURRENT/root bytes and SHA-256, with missing/stale/
different negative fixtures.

## Limits and stop condition

Existing bounded local solver limits, singular/conditioning/global rank issues,
unsupported exact symmetry and resolved numeric driving dimensions remain as
truthfully documented API boundaries. Workspace promotion requires a registered
compatible provider. Optional panel pinning is not advertised. Raster previews
are bounded snapshots; they are not editable model replacements.

One final dev-056 release is the completion boundary. TASK-10, Native3D,
Scientific Libraries, named parameter expressions and the final HTML guide do
not begin in this cycle. The unfinished-only TODO remains authoritative. After
the user's manual acceptance, a separate documentation task should capture
clean screenshots, a reproducible demo Session/workspace and the complete
multi-page HTML guide for online documentation and NotebookLM source material.
