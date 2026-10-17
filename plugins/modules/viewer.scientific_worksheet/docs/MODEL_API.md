# Scientific Worksheet model API

SPDX-License-Identifier: GPL-3.0-or-later

The module retains public API identity `SCIENTIFIC_WORKSHEET_API_v1` and Tcl
namespace `::GX::ScientificWorksheet`. Product version 2.0.0 persists inert
`scientific_worksheet.v2` Workbooks through CORE Interactive Document and Session
Workspace. A Workbook is a value dictionary: a successful mutation returns the
new dictionary; errors do not modify canonical scientific inputs. The model uses
public Numeric, Signal, Statistical Result Semantics, Unit Registry, Dataset
Table Stream, Publication, Document, Workspace and managed Script Job services.
It does not provide a second scientific solver, Job engine or metadata store.

## Lifetime and persistence

`new ?name?`, `load documentId`, and `save book` retain their established roles.
Legacy v1 documents upgrade in memory with their cells, units, sheets, source
identities and captured statistics preserved; only explicit Save commits format
version 2. `listDocuments` lists the existing owner-scoped documents.

A live Book contains a process-local `_runtime` record. `bookIdentity book`
returns its opaque Session token, live Workbook identity, document ID,
generation, authoritative document revision, scientific revision and active
sheet. `validateBook book ?documentCheck?` rejects foreign Sessions, deleted or
replaced documents and outside scientific edits. `refreshBookAuthority book`
adopts a metadata-only revision only after comparing the saved scientific
payload exactly; it does not merge outside scientific edits. Session switching
never rebinds a stale Book implicitly.

`snapshot book` flushes the active sheet and strips process-local state for
persistence. Only the canonical sheets are persisted; an omitted active-sheet
cache is reconstructed on load. `prepareSave book` also reconciles metadata-only changes and retains
formula-owned scientific resources. `historySnapshot book` excludes embedded
History, Workspace metadata and managed-operation tickets to avoid recursion and
false scientific edits. `restoreBookIdentity snapshot currentBook` admits only
the same persistent Workbook UUID and current live owner. This safely restores
pre-first-save History while retaining the current canonical Document ID.
History/Undo/Redo remain owned by CORE Scientific Recipe; snapshots are not a
second timeline. Above 512 KiB the snapshot uses an existing content-addressed
Document Resource (bounded to 64 MiB) and returns a small owner-verified reference;
the Workbook must first be saved. Nested resource dependencies remain under the
same CORE garbage-collection and portable Workspace remapping authorities.
`scientificComparison book` returns a value-only canonical comparison excluding
History, Workspace metadata, managed tickets and pure sheet/viewport navigation;
it allocates no resources.

`workspaceValidate payload` validates the registered Workspace schema.
`workspaceOpen documentId` routes to the existing Worksheet Viewer. Workspace
name, Notes and preview metadata remain under Session Workspace ownership and
are preserved by ordinary model Save. Public Save also uses existing Workspace
Promote to adopt legacy unnamed documents without changing their Document IDs.

## Cells, references and calculation

Supported addresses are A1 through ZZ1000000. Formula ranges, imported row
windows, sort/filter windows, clipboard operations and spilled results are
bounded to 20000 cells/rows as applicable. A Dataset bind accepts 1–26 explicitly
mapped Variables per request; further columns may be bound separately. Visible
requests are bounded independently to 4096 cells. These are explicit interaction
bounds, not permission to truncate canonical Datasets.

`setCell book address source` accepts existing numeric, text and safe formula
inputs. `setTypedCell book address item` accepts `kind`, `value`, `unit`, and
optional lineage/shape. Kinds are scalar, text, boolean, complex, missing, nan,
vector and matrix. Missing and numerical NaN remain distinct. A matrix supplies
flat row-major values and shape `{rows columns}`. Complex values supply
`{shape {rows columns} real {...} imaginary {...}}`; a real/imaginary scalar pair
is accepted and normalized to that typed contract. Nonfinite real literals must
use the explicit nan kind; missing cells never become measured zeroes.

All destinations and overlapping spill anchors are checked before committing a
spill. Editing a spill member requires editing/clearing its anchor first.
`value book address`, `recalculate book ?all?`, `recalculateSelection`, and
`recalculateWorkbook` retain the bounded data-only formula grammar and existing
public provider dispatch. No untrusted Tcl evaluation occurs. Manual mode keeps
cached dependents until explicit recalculation; dirty dependencies are qualified
by sheet. Cache invalidation is confined to the owning live Workbook.

Sheet creation, duplication, selection, rename, deletion and movement preserve
their public functions. Rename and structural edits use the same quoted-string-
safe reference scanner as fill/copy. Absolute/mixed references retain their fill
semantics; structural insertion shifts absolute coordinates as well. Deleted
referenced coordinates remain explicit `#REF!` errors. `insertRows`, `deleteRows`,
`insertColumns`, and `deleteColumns` take Book, one-based numeric position and an
optional count. They scan occupied cells, reject capacity overflow and preserve
source-row lineage. Captured scientific operations must be explicitly unlinked
before structural changes to their output rows/columns.

`sortRows book first last columns directions` and `restoreRowOrder` use sparse
row permutations, stable source row identities and relative formula relocation.
Absolute references retain their absolute coordinates. `filterRows` changes row
visibility only; `showAllRows` restores it. Neither modifies canonical Dataset
bytes. `setColumn`, `defineRange` and `bindDataset` retain actual stable Variables,
source units, selections and absolute zero-based source-row ordinals.

## Units and clipboard

Scalar arithmetic delegates unit admission and scales to
`UNIT_REGISTRY_API_v1/arithmetic_plan`. Compatible sums/comparisons convert the
right operand to the left unit. Products, quotients and powers preserve physical
dimensions. Unitless offsets cannot silently be added to dimensioned values.
Unknown/opaque, nonlinear or absolute affine arithmetic rejects rather than
guessing. `convertUnit book first last targetUnit` explicitly delegates actual
values to CORE `unitRegistryConvertValues`; canonical source data remain intact.
Complex and array calculations continue through the actual typed provider APIs.

`clipboardCapture book first last` returns a typed inert clipboard with formulas,
units and lineage. `clipboardPaste book clipboard destination` and `copyRange`
shift only relative references and preflight the full target. `fillRange` uses
correct independent column and row deltas. `tsvEncode rows` and `tsvDecode text`
round-trip UTF-8 tabs, newlines, quotation marks and empty fields. External TSV is
bounded to 8 MiB/20000 cells and is never interpreted as Tcl source.

## Scientific operations and managed Jobs

`functionCatalog` and `functionHelp` retain actual public provider metadata.
`applyOperation` captures real typed numerical results and existing CORE
statistical semantics. Leaf kinds come from the provider transport descriptors,
including nested struct/cell fields; numeric-looking text remains text, booleans
remain boolean, and typed complex results remain complex. Higher-rank tensor
results require an explicit supported projection before cell application.
`operationStatus book destination` reports current/stale
state. Input edits mark dependent captures stale; the visible result remains
truthfully labelled. Stale captures cannot be published as current results.
`refreshOperation book destination ?inputs?` reuses the real provider and commits
only to still-owned destinations; explicit user edits remain collision guards.
`unlinkOperation` retains numerical values, units and source lineage while
removing captured-operation ownership.

For long work use `operationJobSubmit book operation inputs options ?model?`.
Save the Book first. The returned `scientific_worksheet.operation_ticket.v1`
references a genuine existing supervised Script Job. A registered immutable
Session adapter invokes the public Worksheet Bridge `capture_operation`; no
private process queue exists. Existing Jobs own admission, status, resource
cleanup, logs, progress, cancellation and recovery.

`operationJobStatus ticket` and `operationJobCancel ticket` delegate to that
owner. `operationJobResult book ticket` reads a completed bounded capture without
mutating a Book. `operationJobCollect book ticket destination field ?window?`
applies it using the same transactional captured-output authority as synchronous
operations. Both reject changed Workbook/Session identity or revision. Failed or
cancelled Jobs never invent output. Captures and requests are limited to 8 MiB;
large numerical resources use existing Document-owned statistical resources.

`operationJobRecover book ticket` explicitly rebinds a retained ticket after
reopen only when the canonical Job Session, Workbook UUID, Document generation
and exact scientific snapshot still agree. Tickets may be persisted in the
Workbook's `managed_operation_tickets` field; they are control receipts, not an
independent scientific store. Existing Jobs retain logs/state independently of a
Viewer window. The public Bridge takes one base64 UTF-8 inert request dictionary
and returns one bounded base64 typed capture; it never accepts executable Tcl.

## Publication and virtual-grid reads

`publish book mappings first last datasetId ?displayName?` stages scientific
metadata, captured statistical semantics, exact row-level lineage, cell kinds
and missing masks *before* CORE Dataset Publication Finalize. Each potentially
missing output has a canonical boolean companion Variable; missing is distinct
from numerical NaN even for an ordinary Dataset consumer. Rebinding a verified
Worksheet publication reads those companions through public bounded Dataset APIs. A failed preflight
creates no canonical Dataset. Each row record names output row/cell/sheet,
source-row identity, original Dataset/Variable IDs, exact source-row ordinal,
selection and expression. Integral columns publish as exact int64; mixed
binary64 columns reject integers that would lose precision. Scientific source
values, units, identities and original bytes are unchanged.

`viewportCells book firstRow firstColumn rowCount columnCount` and
`viewportRows book rowIds firstColumn columnCount` return `{identity cells
row_limit column_limit}`. Cells are keyed by the exact numeric `{row column}`
pair and contain address, bounded text, kind, unit and error. The noncontiguous
form supports existing filtered visibility without inventing a second row store.
The Native2D virtual grid paints these bounded records and owns viewport/input
presentation; it does not become a Workbook or scientific-value authority.
Potential spill producers are checked once per bounded viewport request, so
blank visible cells do not repeat a full sparse Workbook scan. This introduces
no extra index or persistent cache.


## Public chart descriptors and Script Bridge

`chartAdd book descriptor`, `chartUpdate book chartId changes` and
`chartRemove book chartId` return updated Book values. Stable `chart_N` IDs,
source sheet/columns/row range, supported Plot v4 2D kind, titles, styles, axes,
legend, annotations/panels and finite geometry are validated transactionally.
Kinds come from actual public Plot API capabilities. Sheet rename and structural
row/column changes preserve chart source references; deletion of an active chart
source is rejected until the chart is removed or rebound. Actual scientific
series and lineages are read through `columnValues`, not descriptor geometry.

The public Script Bridge offers `new`, `load`, `save`, `set_cell`,
`set_typed_cell`, `set_column`, `define_range`, `create_sheet`, `select_sheet`,
`rename_sheet`, `delete_sheet`, `chart_add`, `chart_update`, `chart_remove`,
`bind_dataset`, `publish`, `identity`, `inspect_cell` and `capture_operation`.
Workbook arguments/results are opaque UTF-8 values and must be passed through,
not decoded as a private storage format. `bind_dataset` returns
`{workbook_utf8, row_count}`. `inspect_cell` returns kind, unit and value_utf8 plus
available typed lineage/status receipts. Registered independent producers can
therefore build and publish Workbooks without private Viewer arrays or files.
The independently distributed Scientific Worksheet Examples generator is one
such consumer; it retains its real public producer in each generated Session.


## Legacy preview and publication compatibility

The existing Tcl `preview`, `previewOnArtifact` and `retainPlot` signatures remain
available. They route through public native Plot Dataset v4. A caller owns its
explicit destination directory. `retainPlot` commits the canonical Dataset and
Graph identity through existing publication/Session services before rendering.
An existing canonical historical Plot can be captured independently in native
v4 for an overlay without changing its original renderer owner, PlotSpec or PNG.
Unavailable canonical source remains an explicit error; no cache-only scientific
source is guessed and no automatic migration occurs.

The current Data menu separates **Publish Dataset** (the existing canonical
publication form) from **Charts / Publish** (the live native chart controller).
The retained compatibility preview dialog uses the existing CORE Resource
Management allocation/release/selected-cleanup authority. Closing/replacing the
preview or failing before image adoption releases only that allocation and its
Tk photo; retained canonical Graph files are never deleted by preview cleanup.

Dev102 extends this same public Workbook owner with multi-seed fill, sparse range
styles/merges/sizing, presentation Filter Views and explicit managed Python script
proposals. See [the versioned extension contracts](../../../../docs/api/SCIENTIFIC_WORKSHEET_DEV102.md)
and the module manual for working examples, limits and revision guarantees.
