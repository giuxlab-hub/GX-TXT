# UML Document API v1

The CORE owns one source parser, semantic editor and layout service. The notation
is **gxtxt.plantuml.v1**, a bounded GX-TXT profile of familiar PlantUML class and
sequence syntax. It is not full PlantUML, Mermaid, OMG UML conformance or XMI
interchange. No Java, JavaScript, external executable, include, macro, remote
service or source evaluation is used. The canonical format proposed for normal
Dataset integration is `.puml`/`.plantuml`, contract `document.uml`, with media
type hint `text/vnd.plantuml`; this does not assert IANA registration.

## Implemented pure CORE operations

| Command | Result and authority |
| --- | --- |
| `umlDocumentApiInfo` | Implemented profile, families, operations and enforced bounds. |
| `umlDocumentDetect filename source` | Pure `.puml`/`.plantuml` candidate and validated recognition receipt; filename is an inert hint, never read as a path. Invalid candidates retain located diagnostics; arbitrary Markdown/source files are not reclassified. |
| `umlDocumentParse source ?options?` | `gxtxt.uml.parse.v1`, exact source/SHA/byte count, family/title, semantic elements/relations/messages/frames/positions and source spans. `valid 0` returns located diagnostics without altering source. Control-option/UTF-8 size/NUL violations throw. Options are `profile gxtxt.plantuml.v1` and `family auto|class|sequence`. |
| `umlDocumentInspectElement parseReceipt id` | Reparsed current semantic item by stable ID; no caller-provided derived model is trusted. |
| `umlDocumentEdit source expectedSourceSHA operation request` | `gxtxt.uml.edit.v1`: exact candidate source/SHA, validated parsed model, affected IDs, explicit changed spans and human-readable effect summary. No canonical mutation. Stale SHA, invalid candidate, unsupported operation or wrong semantic type refuses. |
| `umlDocumentLayout parseReceipt ?options?` | `gxtxt.uml.layout.v1`: source SHA/profile/version, bounds, font/metric policy, shared Native2D primitive list, semantic hit map and layout SHA. Only option: finite `font_size` in 10..32 pixels. |

All parse receipts are inert, untrusted data. Inspection/layout reparse their exact
source and verify SHA, ignoring forged model fields. Spans are zero-based Tcl
Unicode-character offsets with an exclusive end, not byte offsets. The exact raw
UTF-8 source, including BOM, CRLF/LF, comments and whitespace, remains authoritative.
Different raw bytes produce different source SHA. Parsing/viewing allocate no
Dataset, Interactive Document, Session storage or secondary model registry.

Source limits: 4 MiB valid UTF-8 without NUL, 20000 lines, 8192 characters per line,
512-character plain labels; class diagrams up to 256 elements/1024 relationships;
sequence diagrams up to 64 declared participants/2048 messages/256 frames and
eight nested frames. Edit control dictionaries are at most 16 KiB; derived layout
is at most 50000 Native2D primitives. The existing native export pixel/file budgets
remain separate. Bounds are admission limits, not a promised scale/performance.

## Exact supported notation

Each document begins with `@startuml` and ends with `@enduml`. One optional
single-line `title` is supported. Ordinary single-quote comments and PlantUML
block comments are retained. Unsupported syntax produces a located error instead
of a partial-success diagram. Labels are plain text; markup, quote/backslash
escapes, control characters and embedded includes are unsupported.

Class/interface declarations use a stable ASCII alias (1..64 characters), with
quoted Unicode display names when needed. Members in multiline bodies preserve
their source order and visibility `+`, `-`, `#`, `~`; a single balanced parameter
list distinguishes operations from attributes. This validates diagram structure,
not a programming-language type system or executable member expressions.

```text
@startuml
title Orders — Ω
interface "Repository" as Repo {
  + load(id: int): Order
}
class "Order État" as Order {
  - total: Money
  + calculate(): Money
}
class Line
Repo <|.. Order
Order "1" *-- "0..*" Line : contains
@enduml
```

Class relationships: association `--`, dependency `-->`/`<--`/`..>`/`<..`,
generalization `<|--`/`--|>`, interface realization `<|..`/`..|>`, composition
`*--`/`--*` and aggregation `o--`/`--o`. Optional quoted endpoint multiplicities
are `*`, a nonnegative integer, `n..m` or `n..*`; ranges must be ordered, and an
explicit composite-whole upper bound cannot exceed one. Triangle targets,
reference existence, class/interface generalization kinds and inheritance cycles
are checked. Every endpoint must be explicitly declared. An implicit PlantUML
element declaration through a relationship is outside this profile.

Sequence diagrams support `actor`/`participant`, explicit aliases and declaration
order, synchronous `->`, asynchronous `->>` and dashed reply `-->` messages,
their reverse-arrow forms, and self messages. All participants must be declared.
Messages retain explicit source order. Control frames are `alt condition`,
`else condition`, `opt condition`, `loop description`, and `end`; frame nesting
and branch placement are validated. No execution, scheduling, timing semantics,
activation/create/destroy, concurrency or arbitrary UML fragment is claimed.

```text
@startuml
actor "User Ω" as User
participant "Web App" as App
participant Store
User -> App : log in
alt accepted
  App ->> Store : load asynchronously
  Store --> App : account
else rejected
  App --> User : error
end
@enduml
```

## Semantic edits and identity

Finite edit operations are `element_add`, `element_rename`, `element_delete`,
`member_add/edit/delete`, `relation_add/edit/delete`, `message_add/edit/delete`,
`message_move`, `frame_add/edit/delete`, `position_set`, and `layout_reset`.
Requests name exact current semantic IDs; elements retain their declared alias.
Deletion of connected elements requires explicit boolean `cascade` confirmation.
Moving a message across a control-frame boundary refuses; source/frame editing
must state that semantic change explicitly. Horizontal participant positions do
not alter message order; vertical participant movement is not a reorder operation.

Unanchored members/relationships/messages/frames derive IDs from their content
and duplicate occurrence. An explicit semantic edit may add a visible inert
`' @gx-id gx_…` comment to preserve that identity across later edits. New items
receive the same explicit source anchor. Duplicate/unattached anchors refuse.
Positions are documented source comments `' @gx-position Alias x y`; explicit
move/layout edits alter these comments and revalidate source. Reset removes only
those annotations. `' @gx-family sequence` can preserve an empty diagram's family.
These are GX-TXT profile annotations, not claimed PlantUML layout directives.

Every candidate edits only the reported spans and reparses the full result before
returning it. Unrelated source remains exact. A semantic edit needs a valid current
source; invalid free-text drafts must remain retained by the document host with
diagnostics and a clearly identified last-valid diagram. A parser/layout receipt
never authorizes a canonical write, file export or source-owner replacement.

## Rendering and family evaluation

The layout emits real class compartments, interface labels, connectors with
triangle/diamond/arrow semantics and multiplicities; sequence participants,
actors, dashed lifelines, ordered message heads/self calls and control frames.
The existing Native2D/Cairo primitive owner paints both embedded/full diagram
presentation and derived visual exports. Layout does not implement another pixel
renderer. Live presentation and visual export require the versioned opt-in Native2D
PangoCairo text engine, using its actual font metrics and painting. Pure headless
layout can return explicitly labelled conservative metrics; that is not visual
acceptance. Unknown glyphs or unavailable shaping refuse the visual operation
while retaining exact source. Font measurement is bounded to 12000 calls per
layout, with a disposable 4096-entry/1 MiB metrics cache. Actual native
screenshots/export inspection and independent acceptance remain required.

| Family/format | Current first-delivery decision |
| --- | --- |
| Class | Implemented semantic parser, editing and Native2D layout described above. |
| Sequence | Implemented distinct ordered-message/frame model, editing and layout. |
| Use case | Evaluated; actors/use cases/system boundaries need a separate semantic family. Deferred; no simulated active creation feature. |
| Activity/state | Evaluated; decision/transition/state/guard/initial/final invariants require separate models/layout. Deferred; ordinary flowcharts are not certified UML. |
| PlantUML | The precise subset above; no arbitrary upstream source compatibility. |
| Mermaid | Viable textual alternative, but different grammar/runtime and no current parser/interchange. Not silently substituted. |
| XMI/UMLDI | OMG interchange requires a real metamodel/tool mapping; XML parsing alone is insufficient. No import/export claim. |
| Private JSON | Derived debug/model data only; not a second authoritative UML format or claimed standard. |

The canonical operations below reuse existing Document/FilePublication authority.
Shared Editor/Workspace/History/portable integration, read-only three-pane
Preview and genuine compiled Builder clients remain separate
delivery gates. Their actual admission/bindings must
be recorded before availability is advertised; this pure CORE batch does not
claim those GUI/publication/package gates completed.

Primary notation/interchange references (consulted 2026-10-29):
[PlantUML class syntax](https://plantuml.com/class-diagram),
[PlantUML sequence syntax](https://plantuml.com/sequence-diagram),
[Mermaid class syntax](https://mermaid.js.org/syntax/classDiagram.html), and
[OMG UML 2.5.1/UMLDI/XMI](https://www.omg.org/spec/UML/2.5.1).
No third-party implementation was copied or invoked.

## Canonical Document operations

`umlDocumentDescribe datasetId ?options?` uses the existing shared document
description, actual canonical identity/producer/revision/SHA/metadata and exact
replacement policy. Optional `capability` is an actual CORE-issued producer/editor
capability, never a caller-declared actor. `expected_session` retains the existing
Session-token check. `declared_profile/family/parser_version/source_sha256` report
stored metadata literally; they do not invent missing origin claims.
The complete description is read within the existing Dataset Authority transaction.
Additive literal Registry fields are `source_module`, `producer_module`,
`producer_version`, `provenance`, `source`, and `source_dataset_ids`, plus the
actual `namespace`. `installed_producer_version` and
`installed_producer_dependencies` describe the current registered module
descriptor; they are separate from declared production provenance and can be
empty. No missing source version, revision or dependency is inferred.

The shared readonly Metadata pane reparses its literal source and checks its SHA
against the mounted canonical snapshot. It starts with readable notation,
diagram family, model schema/parser/profile version, source validity and semantic
counts, then ownership, Registry provenance/lineage and declared metadata. Missing
declarations say **Not declared**; conflicting family/version/SHA declarations
remain visible beside the independently parsed facts. Source snapshot SHA and
revision-state declarations are shown when actually present; an absent source
revision token stays absent. Current installed producer version/dependencies are
explicitly labelled as installation state, not the source's production
environment. Managed resource declarations show their public reference identity
or unavailability; this profile still admits no external image/include inputs.
The full opaque canonical revision remains last, selectable and reachable through
ordinary native Text keyboard/wheel/vertical scrolling. These presentation reads
grant no write capability and do not change canonical source, CAS, package bytes
or the guarded CORE receipt acknowledgement.

`umlDocumentRead datasetId ?options?` returns exact bounded source plus description
and a newly parsed source-bound result. It checks complete payload, integrity,
current Session incarnation and the full Dataset revision after reading. Invalid
or unsupported-profile sources remain readable with diagnostics. Missing metadata
does not become a false claim that another tool authored this GX-TXT profile.

`umlDocumentWrite capability request` uses the same existing Document request
check, Dataset Authority transaction, File Publication writer, namespace and
revision-bound producer edit grant as Markdown. Fields are `mode new` or
`replace_existing`, `dataset_id`, exact `text`, `expected_session`, and for same-ID
save `expected_revision` plus `expected_sha256`. An explicit new copy supplies
`source_dataset_id` and its full opaque `source_revision`. Semantic validation
occurs inside the write transaction before any canonical replacement. The writer
pins actual `uml.profile`, `uml.family`, `uml.parser_version` and
`uml.source_sha256` from the parsed source; request metadata/model is not authority.
This profile has no external image/include assets. Existing unsupported-profile
Datasets refuse same-ID conversion; explicit Publish New preserves their original.

Foreign replacement requires the existing exact producer-issued
`datasetFileEditAuthorize` grant. It neither transfers producer identity nor grants
namespace/admin access, and expires with the source revision. Full revision CAS
also rejects metadata-only changes whose payload SHA stayed equal. Default
Markdown write behavior and immutable native ABI remain unchanged. UML and
Markdown write routes cannot silently retype each other's existing Dataset.

Native client grants use these exact public Tcl operation names, not shortened
Script aliases or the declaration of `kind=uml`. Actual Document/SDK host admission
and per-operation tests are separate from a trusted CORE Tcl caller's capability.

## Shared diagram and managed exports

`umlDiagramMount parent source ?options?` and `umlDiagramCommand handle operation
?request?` are trusted CORE host operations, not portable callbacks or worker Tcl
entry points. They use the existing Native2D viewport owner and surface, shared
source-bound semantic plan, selection/hit paths, pan/zoom/fit and a confirmed
pointer-move callback. Relationship hit testing follows actual connector segments.
Fit capture records the intent rather than derived window dimensions; manual
pan/zoom and selected semantic identity are retained independently of source.
Options are finite `editable`, `on_select`, `on_move`, `on_activate`, `font_size`,
`controls`; callbacks must be live trusted CORE command prefixes.
Without an explicit `font_size`, a live diagram uses the actual configured
TkDefaultFont converted to pixels, bounded to 14..32 pixels. The same measured
font drives its layout and native painting. Explicit sizes and managed export
defaults retain their existing behavior. Fit still shows the complete diagram;
large diagrams can require zoom and pan for detailed reading.
Class relationship names use measured wrapped text blocks. Placement checks both
sides of existing connector segments against class boxes, other annotations and
all connector paths; it does not change endpoints, arrows or source positions.
If bounded placement cannot find clearance, layout refuses and the shared editor
retains its last valid diagram beside the current source. Layout/export bounds
include the measured height of every text line.
Fit reserves the actual shared viewport-control panel height, including larger
fonts and theme changes, so titles remain below its chrome. Manual zoom/pan is
retained when chrome geometry changes; source and semantic positions are unchanged.

`umlDocumentExport source source|png|svg ?options?` returns an ordinary managed
Resource allocation and receipt. Exact source export also accepts an invalid
local draft, explicitly recording `source_valid 0` and no layout SHA. Visual
export requires the current valid source and actual shaped native painter; it
returns source/layout/artifact SHA identities. Options `width`, `height` and
`font_size` are bounded: 64..8192 pixels per dimension, 16 megapixels and 16 MiB
artifact size. No caller path is accepted. A user-facing host must copy through
existing File Publication after an explicit destination grant, then call
`umlDocumentExportRelease receipt`. Managed export is not a Dataset publication
or an implicit worker filesystem capability.

The author fixtures exercise actual class/sequence rendering, managed PNG/SVG,
Greek/Arabic/CJK text, connector geometry and a native pointer move. This does
not certify the unfinished compiled Editor/Preview, a full visual matrix or
independent acceptance. See [Native2D opt-in text](NATIVE2D_TEXT_ENGINE_v1.md).

## Shared Editor and typed draft state

`documentEditorMount parent {kind uml ...}` delegates to `umlEditorMount` while
retaining the existing common Document editor-record lifetime. SourceSurface owns
literal text, Undo/Redo, selection/copy and Find/Replace. The same semantic source
owner handles diagram move, outline selection and UI_FIELD properties/creation
forms; changes reparse source before updating the diagram. Relationship property
edits preserve the original marker endpoint unless explicitly changed: target
triangles and composite-whole multiplicities are semantic data.
Fresh editor layouts allocate 32% to Source, 52% to Diagram and 16% to Outline.
Explicit saved or dragged splitter positions are restored without migration;
Reset panel layout requests the new defaults. The retained SourceSurface
Find/Replace controls start collapsed in an editable UML pane. Existing primary
commands or focused Ctrl+F/Ctrl+H reveal them; Escape returns to Source without
changing the query, replacement or text. Source and Outline have horizontal
scrolling for labels that exceed the available pane width.

`umlEditorCommand` has finite general commands `inspect`, `draft_get/set`,
`capture`, `restore`, `render`, `new`, `new_sequence`, `open`, `save_existing`,
`publish_new`, `semantic_edit`, `select`, `properties`, text/Find/Undo operations,
`fit`, zoom operations, `view_source/diagram/outline/properties/diagnostics`,
`reset_layout`, and managed `export`. Primary application commands can use finite
`add_class/interface/participant/actor/member/relation/message/frame`,
`edit_selected`, `delete_selected`, `message_up/down`, `auto_layout` actions.
Creation/properties forms apply against their exact source preimage; stale forms
refuse. Element deletion confirms connected removal. Sequence reorder preserves
frame boundaries; frame edits never silently reorder messages.

Invalid literal text stays visible with located diagnostics. The diagram is
explicitly labelled with its last-valid source SHA. Invalid source cannot replace
a canonical UML Dataset. A renderer/font/routing refusal likewise retains source
and identifies the older diagram rather than presenting it as current.

The owning Viewer captures `domain_state.uml_drafts` with strict
`gxtxt.uml_draft.v1` records: exact current/baseline/last-valid text, portable
baseline revision/SHA/identity, source cursor/selection/scroll anchors, selected
semantic identity, retained pane/splitter intent, fit/manual viewport and proposed
new destination ID. No parsed model, callback, widget, capability or worker path is
portable. Each text is bounded to 4 MiB; the domain is at most 64 documents/16 MiB.
Ordinary other domains keep their original 64 KiB boundary. The native Workspace
codec declares every type; no Tcl/JSON type guessing is used. Boolean and real
representations may normalize while source and opaque revision strings remain
exact. Restore validates before changing the editor and never publishes. Existing
canonical permission/revision is rechecked before Save Existing; a saved baseline
alone grants nothing. Actual source changes append through the existing History
owner, while restoration does not create new source-edit entries.

## Native clients and admission

Existing ABI-v1 `Host.document_bind` (26) and `Host.document_command` (41) admit
`kind=uml`. No C++ source body, Tcl command, filesystem path, parser object or
renderer crosses the native boundary. `document_view_v1` projects must explicitly
request `UML_DOCUMENT_API_v1` operations using these exact public Tcl names:

| Operation | Required behavior |
| --- | --- |
| `umlDocumentRead`, `umlDocumentParse`, `umlDocumentLayout` | Minimum actual readonly UML composition/binding/render admission. |
| `umlDocumentEdit` | Editable component, literal/semantic edits, New, Undo/Redo and property forms. |
| `umlDocumentWrite` | Save Existing/Publish New, plus unchanged exact Document capability/CAS/producer/namespace authority. |
| `umlDocumentExport` | Source/PNG/SVG export through managed resources and a trusted explicit user destination. |

The declared component kind grants none of these operations. Admission checks the
actual authoritative design independently of the C++ SDK call list. The trusted
host receives the recomputed operation set; portable design/context metadata is
not permission. Readonly mode refuses mutations even with a broader API request.
Native `export_source/png/svg` opens the CORE destination chooser and rechecks
Session/editor/source lifetime before File Publication. The worker receives only
a finite action, never the chosen path. Existing Markdown grants, SDK header,
adapter, Event/State layout and immutable packages are unchanged.

Author native fixtures use independently authored test-only C++ with normal
Development init/build/run and actual restricted worker. They demonstrate SDK41
render intents and missing Read/Edit/Write/Export refusals, not production-module
Builder GUI authorship, installed/cold compatibility or independent acceptance.

Sequence message `frame_context` additionally identifies the enclosing frame IDs
and current `alt` branch ordinals. Reorder and range wrapping require the same
exact frame/branch context, so moving across `else` cannot silently change a guard.
`message_move` accepts `id` and exactly one `before` or `after` message identity;
legacy `before {}` still means the top-level end. Explicit `after` permits moving
to the last position inside a frame without crossing its closing boundary.

The shared primary-action availability helper consults the actual current family,
valid source, selection and admitted operations. Class/interface actions disable
in sequence documents and actor/participant actions disable in class documents;
message/frame actions require real participants/messages. Invalid drafts retain
exact-source export while semantic/visual operations disable. Runtime native
checks remain independent: a disabled menu is never an authorization boundary.
No new-family creation control is advertised for deferred UML families.
