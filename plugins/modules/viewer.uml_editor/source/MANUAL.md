# UML Editor

UML Editor is a compiled C++ client of the shared CORE UML Document service.
The interface, menus and Contract Visualizer role were authored in the existing
Viewer Interface Builder. The existing Development Workspace builds, tests and
exports its native source; normal Plugin Manager installs the package.

## Create, open and save

Open a Session before publication. File > New class diagram or New sequence
diagram creates a local draft. Use Model to declare elements, members,
relationships, participants, messages and control frames. Source and Diagram
share the same semantic parser. Class-only and sequence-only commands follow
the current family; select an item for Properties or Delete. Drag an element to
record an explicit source position. Sequence participant movement is horizontal;
Move message earlier/later changes order only inside its existing frame/branch.
Properties and creation use standard shared fields; stale forms refuse.

File > Open selects a canonical document.uml Dataset. Save Existing replaces
that exact Dataset only with legitimate producer ownership or a revision-bound
producer grant, current Session, complete revision and source SHA. Protected
foreign sources remain intact; Publish New creates an explicit independent copy
with source lineage. Metadata-only changes also make an old save stale. No
source file is represented by a fake Dataset, and no Group/Notes relation is
invented. Ctrl+S and Ctrl+Shift+S route to the declared save commands.

Invalid text stays visible with located diagnostics. Any retained diagram is
labelled with its last-valid source SHA. Invalid source cannot replace canonical
UML. Undo/Redo source edit uses the existing SourceSurface. History retains source
and canonical identity transitions; Workspace Save preserves drafts and view
intent without publishing them. Normal close reviews unsaved work. Workspace
reopen/portable restore never implicitly publishes or grants foreign replacement.

## Diagram navigation and exports

View controls retain Source, Diagram, Outline, Properties and Diagnostics panels.
Use Fit, F8/F7 zoom, Ctrl+0 reset zoom or the existing local viewport controls.
Source text remains selectable/searchable/copyable with the shared text editing
and Find/Replace owner. File > Export source writes exact UTF-8, including a local
invalid draft explicitly as raw source. PNG and SVG require the current valid
source and use the same Native2D/Cairo shaped painter as Diagram. The normal
save chooser grants only the selected destination; no worker filesystem access
or silent Dataset publication is involved. Unavailable shaping/glyphs refuse the
visual operation while keeping the source inspectable.

## Supported notation and limits

The canonical text profile is gxtxt.plantuml.v1: a GX-TXT bounded subset of
PlantUML-compatible class and sequence notation. It is not full PlantUML, OMG UML,
Mermaid or XMI compliance. Source uses .puml/.plantuml; text/vnd.plantuml is a
media hint, not a registered-MIME claim. There is no Java, remote renderer,
include, macro, markup evaluation or executable source.

Class/interface diagrams support explicit aliases, visibility/attributes/
operations, association/dependency/generalization/realization/composition/
aggregation, multiplicities and source-backed positions. Sequence diagrams
support actors/participants, synchronous/asynchronous/reply/self messages,
alt/else/opt/loop control frames and explicit order. Unknown syntax produces
located diagnostics rather than a partial-success diagram. Use case, activity
and state families were evaluated and remain unsupported; no active creation
control claims them. XMI/Mermaid import/export is not implemented.

Source is at most 4 MiB UTF-8 without NUL, 20000 lines and 8192 characters per
line, with 512-character labels. Class bounds are 256 elements/1024 relations;
sequence bounds are 64 participants/2048 messages/256 frames/eight nested frames.
These are admission bounds, not a performance promise. The shared API manual
provides the exact grammar and diagnostics. API Catalog exposes actual operations
and explicit native grants; a component kind supplies no permission.

```text
@startuml
interface Repository {
  + load(id: int): Order
}
class Order {
  - total: Money
}
class Line
Repository <|.. Order
Order "1" *-- "0..*" Line : contains
@enduml
```

```text
@startuml
actor User
participant App
participant Store
User -> App : log in
alt accepted
  App ->> Store : load
  Store --> App : account
else rejected
  App --> User : error
end
@enduml
```

## Public owners and compatibility

CORE owns UML_DOCUMENT_API_v1, DOCUMENT_SOURCE_API_v1, SourceSurface,
Native2D/PangoCairo metrics and pixels, Dataset/File Publication, Registry,
Session Workspace/History and portable resources. The native module routes a
finite declared command table through existing SDK ABI26/41; it contains no
private Tcl, renderer, filesystem, clipboard or scientific store. Explicit
Read/Parse/Layout/Edit/Write/Export operations are independent grants; canonical
write admission remains exact producer/namespace/revision authority.

GPL-3.0-or-later. Primary notation references:
https://plantuml.com/class-diagram
https://plantuml.com/sequence-diagram
No third-party implementation is copied or executed.
