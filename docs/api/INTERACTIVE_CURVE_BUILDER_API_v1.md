# INTERACTIVE_CURVE_BUILDER_API_v1

Version 1, provider `viewer.interactive_curve_builder` descriptor version 1.2.1,
namespace `::GX::InteractiveCurveBuilder`, entrypoint
api/interactive_curve_builder_api_v1.tcl. Internal implementation/publication
version remains 1.2.0. This existing Tcl host selects canonical source rows,
delegates numerical evaluation to NUMERIC_API_v1 and explicitly publishes new
curves. No direct family Script binding or typed C++ SDK method is registered.

## Complete non-underscore function signatures

All names below use the namespace prefix; underscore UI/support functions are
internal callbacks rather than additional generic Script/C++ operations.

| Exact signature | Return / effect |
|---|---|
| `datasetIds` | Sorted current Dataset IDs with at least two enabled numeric table-shaped Variables |
| `variables datasetId` | `{numeric IDS family IDS}` of enabled rank-one Variables; family includes text keys |
| `sourceRows datasetId xId yId ?zId=""? ?tId=""? ?familyId=""? ?familyValue=""? ?selectionId=""? ?options={}?` | Exact canonical-row records with finite selected coordinates, source bindings and optional captured filter/payload/schema identity |
| `familyValues datasetId familyId` | Sorted exact distinct values streamed from that Variable; not limited to numeric keys |
| `evaluate rows mode method ?degree=2? ?samples=101? ?parameterMode=variable? ?options={}?` | Inert Numeric-backed preview arrays, units/source rows/order/statistical result metadata |
| `publish preview datasetId ?displayName=""?` | Create-only canonical CSV Dataset, then metadata; canonical receipt plus source_dataset_ids/source_rows |
| `ordering rows mode parameterMode ?startIndex=0?` | Public Numeric point-sequence ordering receipt plus original_rows/ordered_rows/mode/parameter_mode |
| `sourcePlotCaption rows scope` | Presentation text naming full/selected source scope and fit-row count |
| `sourcePlotSeries rows ?scope=full? ?useT=0?` | Graph-series definitions retaining actual Dataset/Variable/filter/row identity |
| `renderPreview preview destinationDir ?scope=full?` | 2D transient graph artifact path; creates/removes a temporary Plot variant |
| `renderPreview3D preview destinationDir` | 3D transient graph artifact path |
| `openPlot datasetId ?sourceRows={}? ?scope=full?` | Creates/renders/opens a persistent Plot variant and returns its reference |
| `open ?context={}?` | Opens/focuses `.interactive_curve_builder`, returns Tk path |
| `viewerDispatch action scene` | open/rerender only, delegates scene.open_context to open |
| `workspaceValidate payload` | Checks declared inert working-context schema/lineage; returns 1 |
| `workspaceOpen id` | Activates API and opens named Workspace; returns Tk path |

## Canonical source rows, units and bounds

sourceRows requires X/Y numeric Variables, optional numeric Z/t, optional exact
family/member keys and optional existing X-range/rectangle Dataset selection
bound to matching canonical Variables. options accepts only member_id,
member_value,member_enabled,family_enabled,progress. Family defaults enabled
when both familyId/value are nonempty; explicit flags allow an empty exact key.
Enabled filters require a Variable; family/member rank must be one. Combination
is AND, with exact string equality and no Cartesian expansion.

Table Stream uses chunks of 4096. Missing/nonfinite selected x/y/z/t rows are
omitted; retained `row` is the original global canonical ordinal, not the output
list index. Records include dataset_id,row,x/y/z/t IDs, family ID/value and
selected coordinate values. With nonempty options they additionally capture
member fields, source_sha256, source_schema_identity and complete filter_binding.
The legacy empty-options path does not add those identity guards; do not claim
its rows have independently captured old-source hashes. sourceRows/familyValues
materialize their returned lists and impose no universal total-row bound here.

Evaluation requires at least two rows, mode 2d/3d and method
nearest/linear/cubic/spline/pchip/line/polynomial. Polynomial degree is integer
0 through selected_count−1. Matching axes across selected sources require exact
same unit symbols; no implicit conversion of compatible-but-different symbols.
3D arc_length requires equal X/Y/Z units; planar geometry ordering requires
equal X/Y units. Explicit parameter mode uses canonical t for 3D; otherwise
3D arc length follows original point sequence. Independent nodes must be strictly
increasing after the chosen ordering; duplicate X/t and zero-length arc segments
reject. These are declared numeric/unit conditions, not a proof of physical
correspondence or zero measurement uncertainty.

Requested samples is integer 2–100000. The actual target grid is the sorted
unique union of that uniform grid and every original node, so output count can
exceed the requested sample count. Preview records requested samples separately.
Numeric owns interpolation/regression/polynomial fit/evaluation/residual results;
interpolation uses extrapolation=error. 2D functional output evaluates Y on X;
3D evaluates X/Y/Z on t or cumulative arc parameter. Planar geometry_auto can
produce parametric X/Y and retain a separate t. Statistical Semantics interprets
line/polynomial training results with actual units and unspecified noise, not
new accuracy or coverage claims.

## Ordering review and preview identity

ordering delegates point_sequence_order to Numeric, verifying a bijective returned
permutation. It rejects temporal axes/contracts and mixed Dataset/family/member
characteristics. Policy is x_monotone or geometry_auto for arc_length, with
explicit startIndex. It records original/ordered rows and real Numeric review/
segment diagnostics. It is a proposed sequence, not a private topology engine.

evaluate options consumes auto_order,ordering_receipt,reviewed. A supplied
receipt must match exact original rows, mode and parameter mode; required review
must be explicit, and disconnected segment_starts reject one-curve interpolation.
With nonempty options, available source payload/schema captures are checked
against current identity. Without auto-order, legacy 2D X / 3D t sorting or
original arc sequence remains and is recorded when options is nonempty. No
unknown-options whitelist is enforced by evaluate itself; sourceRows has its
separate stricter whitelist.

The preview includes mode/method/degree/samples/parameter_mode,target,units,
source_rows/source_count, evaluated axes, optional fits/diagnostics/ordering and
statistical_results. Treat the same trusted evaluate result as immutable input
to publish; it is not a signed container proving arbitrary supplied arrays equal
the Numeric calculation.

## Publication and graph phases

publish verifies available captured payload/schema identities, reconstructs the
statistical interpretation and validates matching request fields, then delegates
create-only Publication v2. Output is table.generic CSV, float64 explicit row
Variables: 2D x/y, optional t for parametric planar curves; 3D t/x/y/z, with
actual per-axis units and first-source semantic roles. It records source IDs,
Variable bindings and original row identities. There is no independent replay
of every supplied preview array to prove its numerical origin.

After canonical finalize, metadata writes method/mode/parameter/degree/requested
samples, source rows/bindings/fingerprints/schema identities, units, target grid,
diagnostics/statistics and ordering provenance (input/output canonical order).
A later metadata or graph failure does not imply canonical finalize rolled back.
Keep the actual Dataset receipt and reconcile before retrying a create-only ID.

sourcePlotSeries scopes full or selected; selected passes explicit canonical row
ordinals, full retains full source series. Family/member series planning uses
public Graph Series with maximum 256 discovered members, exact identity filters
and source_row_continuity. Ambiguous family meanings require explicit binding;
shortened labels never replace identity. Graph/display scope does not change
which rows were used for Numeric evaluation or publication.

Current renderPreview/openPlot/renderPreview3D explicitly activate
PLOT_DATASET_API_v3 and its real transient/PlotSpec methods. This is retained
legacy code, not demonstrated Plot v4 parity or permission for new restricted
Viewers to declare deprecated v3. The descriptor also still references v3.
The integrated requirement for new scientific graph consumers to use v4 remains
separate; a documentation update cannot silently migrate those methods. 2D
renderPreview deletes its temporary variant in finally; destinationDir is a
trusted host artifact location. openPlot creates a lasting variant and chooses
3D only when t/z Variables exist. No generic restricted client path authority
is created by these host functions.

## Workspace and activation

open requires Tk, current Session and Numeric capabilities. Context accepts
dataset_id/source_dataset_id, workspace_id and workspace_name. Dataset is a
preferred selector; an existing window is focused unless a different requested
Workspace causes its normal close path. Close saves an existing named context;
anonymous drafts are not implicitly published scientific data. Saved context
contains version1 settings,lineage,selected,next and optional workspace_metadata,
with no History/Recipe/runtime. Lineage is bounded to 200000 entries, exact
canonical row IDs and 64-hex payload/schema hashes; selected IDs must exist.
Settings constrain mode/parameter/method/display scope/boolean choices.

Restore checks actual source payload/schema identity and reloads finite canonical
rows; stale source requires explicit reload. Workspace writes use generation/
revision/payload conflict handling. Public workspaceValidate is structural and
does not itself reload/compute rows; the open adapter performs that phase.
UI displays first 500 preview rows while publication uses the full preview.

## Source-backed host example and acceptance boundary

```tcl
set rows [::GX::InteractiveCurveBuilder::sourceRows $dataset $xId $yId \
    {} {} {} {} {} [dict create family_enabled 0]]
set preview [::GX::InteractiveCurveBuilder::evaluate $rows 2d linear 2 101 variable \
    [dict create auto_order 0]]
# Explicit new output; the canonical writer owns schema and create-only commit.
set receipt [::GX::InteractiveCurveBuilder::publish $preview $newDatasetId {Built curve}]
```

Unexecuted documentation example using actual public contracts and valid
compatible finite rows. It is not permission to compute privately in a new
Viewer, reinterpret source units, bypass Numeric/Publication, or claim native
GUI/3D graph/independent scientific acceptance. Those gates remain explicit.
