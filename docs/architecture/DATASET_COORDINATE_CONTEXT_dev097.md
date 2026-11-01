# Dataset coordinate context

Dataset Metadata owns persistent coordinate settings; Unit Registry owns physical
conversion; Dataset Transform owns explicit derived numeric materialization.
Workspace state owns bindings and the coordinate policy applied to a view.
No renderer-private Dataset settings store is used.

## Independent operations

- **Axis display unit:** compatible re-expression of one canonical Variable;
  source values, units and stable IDs do not change. Missing source units require
  an explicit recorded assumption. Known incompatible units cannot be relabelled.
- **Dataset view magnification:** a positive per-variable factor and source-unit
  pivot define the fitted view range. Apply the factor from the canonical reference
  range, never from an already magnified range. Transient pan/zoom is separate.
- **Calibration:** an explicit positive per-variable factor and input/output
  origins define `effective = output_origin + factor * (canonical - input_origin)`.
  Saving a definition does not opt numerical consumers into effective coordinates.
- **Materialize calibration:** publish a new Derived Dataset with exact source SHA,
  Variable lineage and a consumed-calibration receipt. Its active calibration is
  identity; the original data remain unchanged.

## Public authority and bounded snapshots

[DATASET_METADATA_API_v1](../api/DATASET_METADATA_API_v1.md) provides read, update,
reset, validate and inspect operations plus bounded coordinate values, view ranges
and affine plans. One additive versioned context is stored under the framework's
reserved metadata namespace and stable Variable IDs. It binds source SHA,
dtype/value-kind/unit/format and revision. Unknown variables, invalid factors,
incompatible units and stale source/schema fail explicit application. Missing
settings mean identity. Dataset Authority transactions own writes and rollback.

Canonical Table Stream/Numeric reads stay canonical. Metadata replacement,
publication, Session transfer, duplication and Transform inheritance preserve,
rebind or explicitly consume context through the same owner. Public snapshot
operations take a captured resolved context without source IO; receipts say
`snapshot_only`. Source-bound operations say `source_verified`. Consumers verify
bindings when loading and invalidate them on source/schema/policy changes.

Unit Registry classifies affine relations from its parsed arithmetic grammar.
Nonlinear definitions use registered pointwise conversion; they are never
approximated from a few sampled values. Native2D owns geometry and constraints.
Displacements use affine scale only; coordinate values include the origin.

## Workbench

Independent display units feed axes/ticks, cursor, paged points, retained handles,
inverse numeric editing, selection intervals, exports, transform and dimension
forms. Workspace/History persist overrides and the canonical viewport reference.
Source relations and working frames remain separate from display units. Different
scientific frames have separate saved views; compatible original bindings can be
aligned explicitly. Unbound curves and missing-unit sources accept deliberate
scientific declarations with rationale and provenance. Known Dataset meanings,
parents/derived geometry and constraints prevent incompatible reinterpretation.

Unlike physical axes use signed response residuals; raw mixed-unit path distance
is unavailable. Compatible geometric comparisons use CORE-normalized temporary
native frames, retaining actual evaluation matrices, units and publication
provenance. Native/Numeric performs statistical reductions once. Metric rotation,
reflection and dimensions require a common native unit; independent translation,
scale, pivots and axis dimensions preserve their own physical units. Symbolic
parameter expressions remain native and numeric entries are stored canonically.

## Preview and scientific Dataset viewer

`scientific_dataset_coordinates_v1.tcl` adapts bounded canonical Curve Source
buffers through the existing snapshot APIs. It retains original points and row
lineage, converts only display units, and changes the Native viewport through the
shared view-range owner. Preview renders that exact viewport in current-view mode.
Reprojection starts from retained canonical points. Metadata-aware Preview cache
invalidation and the full viewer's source-guarded refresh apply edits once.
Canonical table pages and numerical calibration remain separate.

The full viewer requires a common coordinate policy for overlays. Source selectors
identify source units; rendered axes/legends/readouts identify displayed units.
Unsupported coordinate-policy types, such as Boolean axes, retain their legacy
canonical display without a fabricated numeric schema. Source-byte and schema
changes still invalidate the view; metadata bookkeeping alone does not.

## Plot Dataset

The CORE Octave presentation adapter reuses public snapshot affine plans and
bounded pointwise conversion through the real Script Bridge. Plot caches keep
canonical samples while their axis metadata retains captured coordinate snapshots.
Current source-bound rerender refreshes these snapshots without repeating unchanged
preparation. Detached Clones use captured contexts without source IO. Physical
unit compatibility is resolved after these declared Variable relations are known.
Explicit graph units/ranges precede Dataset defaults; shared policies must agree.
Linked X magnification applies once across the linked axes. Auxiliary uncertainties
and bands preserve their own physical relations, and nonlinear region selection
fails explicitly instead of using a false affine inverse.

Static XYZ and Native3D Plot preview share converted points, fitted limits and
aspect. A derived successful-render receipt detects metadata-only policy changes.
It stores no settings authority; the public Dataset context remains authoritative.
The existing independent canonical Viewer representation retains its own geometry.

## Direct Dataset XYZ

The existing compact CORE host converts bounded original triples through the same
Dataset snapshot operations. VTP points use display units; original canonical
triples and one-based source rows remain retained. A view-owned normalized frame
maps the independent displayed ranges into the scientific cube. Its fixed camera
prevents automatic fitting from cancelling persistent magnification. Calibrated
ticks show physical values, with each source pivot/factor in the legend. Resize,
camera reset and warm activation reuse the same scene. Metadata changes invalidate
it before another activation; there is no renderer-owned settings authority.

HMS Dataset/Curve Source readers expose canonical seconds. XYZ and shared2D
presentation first use the public elapsed-time conversion to recover the declared
source-unit frame in a temporary buffer, then apply the common coordinate policy.
Original retained arrays remain seconds. Numerical calibration remains unapplied.

## Release verification

Final package inclusion and the single frozen scientific/API/Script/integrity/
performance campaign remain required.
The final GUI gate is the user-approved single installed Debian smoke; prior valid
GUI evidence is reused and omitted matrices are NOT RUN — USER-ACCEPTED.
