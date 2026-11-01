# Scientific managed Preview client — P033 implementation contract

This specifies the additive `scientific_preview_command(form, operation, typedRequest)`
and `scientific_frame_bind(viewport, form)` methods of existing
PREVIEW_COMPONENT_GUI_API_v1. It grants no capability by itself. CORE must verify
normal compiled package admission, the exact requested operations, actual Preview
host, declared component roles, live Session/Dataset/revision and module lifetime.
Unavailable admission refuses. No filesystem access, publication or new cache API.

The next-event immutable `scientific_preview_result` envelope has fields
`operation`, `status`, `error`, `sequence`, `event_generation`, `result`, `view`,
and `form_id` (the actual declared controller ID, initially empty).
Completed command result is an empty typed object, failed/cancelled result null.
Initial snapshot is completed with result null, sequence0. Content lives in view:

- `source`: text fields dataset_id, contract, revision, canonical_sha256,
  source_sha256, producer. Revision is opaque text; unavailable SHA is empty,
  never invented. Identity comes from the canonical owners.
- `variables`: array of variable_id/display_label/dtype/unit/coordinate_role/
  semantic_role text, rank integer, shape integer array, dimension_ids and
  coordinate_variable_ids text arrays. Paging fields variable_total/offset/limit
  are integers. selected_variable is text, initially empty.
- `page`: typed null until a successful page; then variable_id/dtype/unit/order
  text, starts/counts integer arrays and **values text array**, preserving exact
  uint64/integer text and scientific numeric spelling. Order is canonical C.
  `coordinates` is an array of actual coordinate Variable slices, each with
  variable_id/dtype/unit/dimension_id text, rank integer, dimension_ids text array,
  starts/counts integer arrays and values text array. dimension_id is populated
  only for a rank1 coordinate. Referenced coordinate dimensions must match the
  selected Variable's actual dimensions; no coordinate is invented from row order.
  The48KiB wire bound includes coordinate slices; clients may request smaller
  pages. A rank1 data Variable with one actual coordinate permits genuine XY rows;
  other cases retain explicitly named Variables/indices, never fabricated X.
- `metadata` and `source_rows`: arrays of `{key:text,value:text}` with separate
  metadata_total/offset/limit and source_total/offset/limit integer fields.

`discover` accepts optional offset(default0), limit(default32,max64). It returns
actual enabled numeric Variables and their own dimensions, not first-two-column
scientific assumptions. `page` requires exactly variable_id, starts, counts:
actual rank, bounded extents, product at most512cells. Integer typed request
fields must really be integers, not booleans or rounded floats. `metadata` and
`source` accept optional offset(default0), limit(default16,max50). Every request
and returned wire envelope remains within48KiB; oversized reads explicitly refuse
and permit narrower pages. Values use the existing canonical Dataset hyperslab
owner; source bytes are never rewritten or republished.

Source rows include independent Dataset identity and source-declared metadata.
Uniform `measurement.source_metadata_key_encoding=utf8_hex_v1` plus
`measurement.source_metadata_value_encoding=utf8_hex_v1` explicitly declares the
reversible UTF-8 text projection: measurement.source_metadata.k_<hex-key> stores
hex-value, measurement.source_metadata_key.k_<hex-key> stores the original parser
label. CORE verifies that map and displays decoded text without a vendor branch.
Display keys distinguish `CORE identity:`, `Source header:` and `Source metadata:`
so an original header cannot impersonate independently pinned identity. A declaration
is not new scientific authority; canonical/source SHA identity stays separate. Multiline OWNER/copyright text is preserved; no lossy replacement.

Frame binding uses the genuine eight declared scientific_preview_components
roles, actual distinct X/Y dimension IDs and selected actual Variable. The
frame_indices field is strict JSON mapping non-X/Y dimension IDs to exact
nonnegative integers (empty object means zero defaults). CORE owns canonical
plane reads, dimension transpose for presentation, coordinates and Native2D.
No fake table/raster parent, source interpolation or private Dataset mutation.

CORE renders the three explicitly managed role tables after an accepted command,
using existing UI Field owners. Authored table_set may not overwrite these roles.
Values headings identify actual Variable/coordinate IDs and units; source indices
are labeled as indices. Native clients request pages and control their public
presentation operations; the three tables never substitute invented source data.

The runtime stores computed native module/grants from normal runtime_inspect,
compares READY binary identity, checks source/package snapshots, live Preview
context and a per-event request/generation scope. Strict typed indices reject
booleans/floats. Responses are transient bounded UI receipts, not a new persistent
scientific cache or cache API. Existing Preview/Canonical owners retain scientific
invalidation. Legacy sample-only numeric clients preserve their16-row path; the
new scientific profile receives exact canonical page receipts instead.

The implemented canonical read, typed command adapter and Frame binding are
qualified separately by their actual source, package and acceptance evidence.
Synthetic author admission checks do not establish installed/native acceptance.
A model declaration or this document alone grants no native operation. P033's
genuine compiled modules have focused independent scientific/API evidence;
final candidate and real-GUI acceptance remain mandatory release gates.

## Explicit Frame binding (native operation 47)

`scientific_frame_bind(viewport, form)` requires its admitted
`PREVIEW_COMPONENT_GUI_API_v1` native operation and all five declared Frame roles.
CORE populates choices with actual enabled rank≥2 canonical Variables and the
selected Variable's actual dimension IDs. Initial selections remain empty; select
a Variable and distinct X/Y dimensions explicitly. `frame_indices` is a JSON
object mapping actual remaining dimension IDs to exact integer indices; omitted
remaining dimensions select zero. Booleans, floating values, duplicate keys,
unknown/X/Y dimensions, negative or out-of-range indices are refused. UTF-8 input
is bounded to 4096 bytes. No producer/version-specific assumptions are made.

The existing canonical read owner prepares at most 128 cells per selected X/Y
dimension through exact typed hyperslabs. Existing Native2D scalar-plane rendering
and Preview descriptor/image viewing provide nearest-cell presentation and
Fit/100%/zoom. Transposition reorders whole typed cells and never converts uint64
values through floating point. The v1 external provider's unchanged C-order plan
is used only for its original orientation; explicit transposed planes use the same
built-in Native2D renderer. No fake `image.raster` Dataset, private plugin Canvas,
new renderer, persistent scientific cache or source mutation is introduced.

The existing result envelope adds nullable `view.frame`: text fields
`variable_id,dtype,unit,x_dimension_id,y_dimension_id,source_revision,minimum,maximum`,
integer arrays `starts,counts`, integer fields `finite_count,width,height`, and
`indices` records `{dimension_id:text,index:int}`. Revision remains opaque text;
range text preserves exact integer values. `width` and `height` are the rendered
plane's pixel extent; the existing renderer may use several pixels per source
cell. Logical dimensions remain the exact selected `counts`, identified by the
actual X/Y dimension IDs. Artifact paths and image bytes never
enter restricted C++ transport. Temporary PNG serialization uses the managed
Preview allocation and is removed after the existing descriptor owns its photo.
Failed operations report fresh failed/null results and preserve the previous
accepted plane for input/validation failures. Session/source/package/event guards
and control values are checked before presenting a newly prepared plane.

Author check `scientific_frame_author02` covers 54 scoped assertions with real
canonical data and shared image owners, but explicitly synthetic native admission.
It does **not** establish genuine C++ installation, real native GUI input, or
independent acceptance; those remain mandatory release gates. Initial author01
choice-refresh failure is retained, with the shared choice-domain ordering fixed.

### Original Metadata and Source values

CORE attaches the shared readonly original-cell inspector to these two declared
role tables. Double click a cell, press Enter on a selected row, or use its
**Inspect original value** context action to inspect complete original text.
The existing live scientific guard is checked before opening; the dialog is a
readonly snapshot, with standard text selection and a literal **Copy original
value** action. UTF-8 cell values are bounded to 64 KiB and retain tabs, LF and
CRLF. Standard table Ctrl+C remains sanitized TSV. This host presentation adds
no C++ operation, grant, renderer, source edit, cache or package requirement.

Frame presentation uses the existing descriptor image owner with an explicit nearest-cell Fit policy. The first successfully mapped plane fits the available viewport, including integer upscaling for small arrays, with space for the compact range/shape/identity summary. Fit, 100%, + and − change only the disposable display photo, within the existing16MiPixel bound. Canonical cells, starts/counts, source SHA and the full typed `source_revision` remain unchanged. The full original revision is inspectable in Source; the image caption does not dump the opaque Registry/metadata tuple. Other image consumers keep their default downscale-only Fit policy. A queued initial fit checks its actual widget incarnation and live scientific scope; explicit user view changes cancel that pending fit.

For a plane inside a scrolling UI_FIELD page, Fit measures the mapped intersection with native ancestor bounds. It aligns the existing tools at the beginning of the maintained viewport and waits for actual layout before fitting. An initially clipped plane defers its one-shot fit until visible; 100% or another explicit view cancels that pending fit. The viewport observer belongs to the exact widget incarnation and is removed on destruction. This changes only presentation, with the same canonical plane, source revision and SHA.

The four image-view buttons size to their actual labels instead of reserving
five characters each. This keeps the current Preview scale caption visible at
large fonts in the existing row. Commands, widget identities, image scale policy,
source values and scientific authority are unchanged.
