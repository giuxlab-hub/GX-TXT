# Canonical Sketch Dataset API v1 — dev-070

SPDX-License-Identifier: GPL-3.0-or-later

`geometry.sketch`, format `gxsketch`, media type
`application/vnd.gxtxt.sketch`, extension `.gxsketch`, uses the existing Canonical
Dataset Registry and Dataset File Publication transaction. Creation is explicit.
A Workspace remains a document/draft and does not become a Dataset on Save.

The portable file is one UTF-8 Tcl dictionary, parsed as data, never evaluated.
Top-level fields: `schema gxtxt.geometry.sketch`, `version 1.0`, `objects`,
`constraints`, `parameters`, `provenance`. No other top-level fields are accepted.
`objects` maps stable logical IDs to `{name definition units metadata? provenance?}`.
`definition` is the public Native2D retained definition, including family, defining
controls, exact Spline tangent arms, matrices, nested/composed parts, reversal and
canonical shared-node IDs. `units` is the x/y pair of Unit Registry symbols.
`constraints` maps logical IDs to records with a `definition` (Native constraint
specification with logical object IDs in a/b/axis), optional expression and normal
geometric dimension/annotation fields. `parameters` is the CORE Parameter Service
local definition dictionary; formula dependencies and declared units are retained.
`provenance` is portable descriptive data, never an instruction or a source binding.

CORE validates a maximum 64 MB data document in a temporary Native scene, validates
all retained definitions and supported constraints, and uses the CORE evaluator for
parameters and expressions. Native's existing geometric bounds also apply (including
256 composite parts and 65536 defining controls). Unrepresentable or cross-boundary
constraint dependencies are reported; they are never silently dropped.

## Tcl

- `::GX::sketchDatasetValidate sketch` returns validated data or an error.
- `::GX::sketchDatasetReadFile path` validates a portable file.
- `::GX::sketchDatasetRead session datasetId` checks canonical contract and hash.
- `::GX::sketchDatasetPublish session moduleId datasetId sketch ?options?` uses
  Dataset File Publication, returning its identity/hash receipt. Normal ownership
  and namespace checks apply. `replace_owned 1 expected_sha256 HASH` performs an
  optimistic update; absent replacement is creation only.
- `::GX::sketchDatasetPreview path pngPath` uses Native and the shared renderer.
- `::GX::sketchDatasetPointGeometry scene object ?kind? ?index?` returns retained
  point/Polyline/Line definitions from exact point-backed coordinates and breaks.
  Large continuous series are chunked with a shared endpoint; gaps stay separate.
- `::GX::sketchDatasetSubsetRelations scene extracted constraints` remaps references
  and preserved shared nodes using the existing Native connection/constraint authority.
- `::GX::sketchDatasetParameters context` captures local expressions and external
  Session values as named local parameters. Captured Session formulas remain in
  descriptions; a standalone Sketch has no live dependency on its source Session.

The default-enabled `acq.sketch_dataset` handler provides standard inspection/import.
CORE preview dispatch handles this contract regardless of the producing module.
Open Dataset starts Curve Workbench with a new editable draft. The draft binding
stores the canonical identity and expected hash, not separate Dataset authority.

## Python and Octave Script Bridge

`SKETCH_DATASET_API_v1` offers `validate`, `read`, `publish`, each taking one request
struct. `read`: `{dataset_id}`; `validate`: `{sketch}`; `publish`:
`{dataset_id, sketch, options?}`. Python dictionaries and Octave structs use normal
Bridge conversion. Returned objects include typed retained controls/parts/tangents.
The authenticated executing script owns its publications; the caller cannot supply
another module's identity. Example:

```python
from gxtxt import gxtxt_api_call as api
sketch = {'schema':'gxtxt.geometry.sketch', 'version':'1.0',
          'objects':{'line':{'name':'Line','definition':
              {'family':'line','controls':[[0,0],[12,0]]}, 'units':['mm','mm']}},
          'constraints':{}, 'parameters':{}, 'provenance':'My construction'}
r = api('SKETCH_DATASET_API_v1', 'publish',
        [{'dataset_id':'my_sketch','sketch':sketch}])
```

## Compatible Native extensions

`selection_definition`, `spline_line_plan`, `spline_span_to_line` are additive
`NATIVE_2D_GEOMETRY_API_v1` Bridge operations using a scene token and request
`{object_token, index}`. Existing ownership/lifetime rules apply. The first returns
an exact retained definition. The pure plan returns `definition` and `control_map`.
The last transactionally changes geometry within the same object identity.
Tcl Native has the same names and `(scene, objectId, index)` arguments.
C adds `gx2d_selection_definition_owned`, `gx2d_spline_line_plan`,
`gx2d_spline_span_to_line`, `gx2d_selection_control_sources`; release owned definitions
with `gx2d_control_definition_release`. Existing C signatures and POD layouts remain.

Individual Spline spans inside composites retain the existing segment namespace:
`2000000000 + part*65536 + span`. Whole object is `3000000000`; controls use the
existing canonical control namespace. Source indices are semantic, not tessellation
rows. Selected spans retain a two-knot Spline with explicit exact arms. Conversion
freezes the original arms for every untouched span, inserts one retained Line,
retains transforms/reversal and shared nodes, and remaps supported constraints.
An incompatible relationship rejects the transaction. Parameter-interval fragment
definitions on the affected Path must first be removed because their old intervals
cannot safely be reinterpreted after subdivision. Unrelated fragments do not block it.
Existing selection sets referencing old topology become stale under Native's normal
revision rules; Workbench clears transient selection after a successful edit.
