# Shared GX-Markup navigation (P031)

This extends the existing CORE renderer and DOCUMENT_SOURCE_API_v1 presentation.
It adds no renderer, source store, filesystem browser or Script/native grant.
P030 archives, scientific payloads, source-note associations and Groups retain
their owners.

`markupRenderStringToWidget widget source ?imageCommand? ?linkContext?` retains
previous call forms. Obtain a host-only context with `markdownNavigationContext
kind identity ?options?`: `documentation` uses an existing index ID; `dataset`
uses a canonical Markdown Dataset ID; `session_file` uses a relative Markdown
filename registered in the current Session Files browser. No root/path option
exists. Optional `open_command`/`status_command` are trusted live host command
prefixes, never commands from Markdown. Contexts are transient UI data, not
portable capabilities, Workspace payloads or metadata.

Every activation rederives the owner/root/source SHA and applicable Session/full
Dataset revision. Caller-edited root fields grant nothing. Missing/stale identity
refuses. Canonical relative paths must resolve to registered Markdown Datasets;
arbitrary Session files do not become Datasets. SOURCE_NOTE_API_v1 source-file
associations remain distinct; no Group is manufactured.

Canonical payload paths may contain hidden components when the target is an
exact registered Markdown Dataset. Registry identity is checked before reading
or opening the destination; this does not admit unregistered hidden files or
change Documentation/Session Files restrictions.

| Case | Supported behavior |
| --- | --- |
| `#heading` | Actual same-document heading scroll/focus without a trusted external base. |
| Headings | Existing ATX levels1–3 outside fenced code. |
| Normalization | Lowercase Unicode; retain Unicode alphanumerics; remove other punctuation; collapse whitespace/underscore/hyphen to one hyphen, trim edges; empty becomes `section`. No Unicode normalization. |
| Duplicates/collisions | First unused slug, then `-1`, `-2`, etc., checking all earlier IDs in deterministic source order. |
| Inline/fenced code | Literal, with no false links or anchors. |
| Documentation | Declared/indexed module documents or the existing public framework `docs/` root; existing renderer and Back/Forward owner. Unindexed private module targets refuse. |
| Canonical Markdown | Actual same-Session canonical identity/revision/SHA and existing Open policy; a separate consultation preserves editable drafts. |
| Session Files | Current token, registered browser item, regular Markdown and existing selection/Open owner. |
| Fragments | Bounded Unicode-alphanumeric/underscore/hyphen IDs; one strict UTF-8 percent decoding pass, lowercase lookup. |
| Untrusted/lost base | Relative links visibly refuse; no guessed CWD or Session root. Same-document anchors work on an ordinary unbound renderer. |
| External HTTP(S) | Existing explicit opener, no automatic linked-document fetch. |
| Managed images | Existing image callback/resource authority unchanged; no arbitrary managed Markdown root is invented. |
| External Open association | Existing policy respected; absence of a shared heading surface is reported, not claimed as successful external scrolling. |

Root-scoped `..` is admitted only within the rederived root. Root/target
components are checked without following symlinks, including inward links.
Targets must be readable regular files. Canonical/Session links require Markdown;
Documentation retains its existing HTML/text contracts. Absolute/network paths,
unsafe schemes, NUL/control bytes, invalid UTF-8, repeated encoding, ambiguous
paths, unsafe fragments, missing files and source/base loss refuse without
mutation. Markdown retains the4MiB bound; Documentation keeps its existing
smaller read limit.

Normal same-link non-drag mouse release and focused Enter navigate. Press and
selection drag do not; Shift-selection stays inert. Tab/Shift-Tab focus links
then leave the Text widget. Existing UI text editing owns native selection,
Ctrl+A and copy. Unknown headings preserve document/scroll and report status.
Hosts use status lines; a bare renderer reports actual refusal visibly.

`markupNavigationInspect widget` returns derived anchor/link/focus/status data.
`markupNavigationFollow widget target` returns `navigated`, `opened` or `refused`.
These host operations add no Script Bridge or restricted C++ capabilities.
Existing C++ Documents/Preview inherit them through the unchanged Document host.
Independent native/cold/portable and exact-release support qualification belongs
to the final P031 acceptance, not author reports.

When normal Live Preview finalization writes its own reserved render receipt,
CORE acknowledges that exact serialized transaction in its current read-only
compiled Markdown panes. Only a baseline matching the full revision immediately
before that write, with the same Session, canonical SHA and assets, can advance
to its verified post-commit revision. Text, selection, scroll, worker and widget
identities stay intact. An already stale pane, unrelated metadata change or
editable draft receives no acknowledgement; full stale-identity/CAS refusal
continues to apply. This is private host finalization, not a new producer grant.
The same serialized receipt owner delegates read-only UML metadata finalization
to the shared UML Document owner. UML source/semantic/diagram state and editable
baselines remain separate and unchanged; this adds no Markdown parsing to UML.
