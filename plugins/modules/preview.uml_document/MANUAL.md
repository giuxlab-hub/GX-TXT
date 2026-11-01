# UML Preview 1.0.0

UML Preview presents canonical `document.uml` Datasets in the normal Dataset
Preview host. It is a genuine compiled C++ client of the shared CORE UML Document
service. Its Builder-authored design declares exactly Diagram, Source and
Metadata panes. The C++ callback matches the actual requested pane identity and
issues one public SDK document render intent for that declared component.

## Opening and controls

Enable Dataset Preview through framework Configuration and select a UML Dataset
in the Dataset Browser. The normal Contracts preference can select UML Preview
for `document.uml`; its role is primary and exact. Ordinary module enable/disable
and normal package removal remain authoritative. This module does not create a
standalone editor window or an additional notebook inside the Preview host.

Diagram uses the same semantic model, layout and Native2D/Cairo painter as UML
Editor and visual exports. Use its existing viewport controls to fit, zoom and
pan; semantic selection identifies source elements. Source is selectable exact
text with the common text editing/copy behavior and Find surface. Metadata shows
actual canonical Dataset identity, revision, SHA, producer and format. The module
has no canonical write, publication, source-file association or clipboard engine.

UML Editor is the separate optional Open visualizer for source and semantic
editing, canonical Save/Publish New, source/PNG/SVG export, Workspace and History.
This read-only Preview neither publishes nor modifies that editor's drafts.

## Supported profile and limits

The format is `.puml` or `.plantuml` using the explicitly bounded GX-TXT
`gxtxt.plantuml.v1` profile of PlantUML-compatible class and sequence syntax.
`text/vnd.plantuml` is a media hint, not a claim of registered MIME or complete
PlantUML/OMG UML compliance. No Java, external renderer, includes, macros, remote
service, arbitrary markup, source execution or XMI/Mermaid translation is used.
Unknown or unsupported syntax produces located diagnostics. Exact source stays
available even when a visual plan cannot be admitted; no fake success image.

| Family | Capability |
| --- | --- |
| Class and interface | Real names/aliases, member compartments, visibility, operations, association/dependency, generalization/realization, aggregation/composition and endpoint multiplicities. |
| Sequence | Actor/participant identities, ordered sync/async/reply/self messages and bounded nested alt/else, opt and loop frames. |
| Use case | Evaluated; separate semantic family needed, currently deferred. |
| Activity/state | Evaluated; separate invariants and layout needed, currently deferred. |
| Mermaid or XMI/UMLDI | Evaluated alternative/interchange formats; not implemented or silently substituted. |

CORE enforces 4 MiB valid UTF-8 source without NUL; 20000 lines and 8192 characters
per line; 512-character labels; class256 elements/1024 relationships; sequence64
participants/2048 messages/256 frames with depth8. These are admission bounds,
not a scale/performance promise. Text shaping uses the existing explicit bounded
PangoCairo native text owner and installed font fallback. Missing runtime/glyphs
or an unavailable bounded layout refuse honestly while source remains available.

## Authority and compatibility

The installed project requests only public Host document_command/value_get and
UML_DOCUMENT_API_v1 operations umlDocumentRead, umlDocumentParse and
umlDocumentLayout. Declaring kind=uml grants nothing. Missing operations explicitly
refuse; no default Markdown grant is substituted. The unchanged native ABI26/41
is used and existing Markdown native packages need no rebuild. CORE verifies the
normal installed package/source/binary receipts, actual Dataset/Session lifetime
and exact requested component before mounting the shared read-only pane.

Source and visual data are not duplicated into a module-owned scientific store.
There is no private Tcl, raw filesystem, Dataset registry, renderer or clipboard
bypass. Source Notes remain the distinct SOURCE_NOTE_API_v1 relationship, not a
fabricated UML Dataset or extra Associated Source pane.

Primary format references: https://plantuml.com/class-diagram and
https://plantuml.com/sequence-diagram; alternatives considered at
https://mermaid.js.org/syntax/classDiagram.html and https://www.omg.org/spec/UML/2.5.1.
No upstream implementation is copied or executed.
