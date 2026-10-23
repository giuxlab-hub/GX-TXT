# HTML Viewer API v1 — current installed adapter

Provider: `viewer.html`; declared namespace `::GX::HTMLViewer`;
entrypoint `api/html.tcl`. The installed restricted adapter delegates rendering
and document selection to existing CORE public owners. Its full integrated
acceptance remains pending. The module's [user manual](../../plugins/modules/viewer.html/MANUAL.md)
describes its supported safe rendered content.

Activate through the existing Module public API owner:

```tcl
::GX::modulePublicApiActivate viewer.html HTML_VIEWER_API_v1
set capabilities [::GX::HTMLViewer::apiInfo]
set presentation [::GX::HTMLViewer::render {<h1>Observation</h1><p>Inert text.</p>}]
```

| Adapter operation | Exact host signature | Result / context |
| --- | --- | --- |
| `apiInfo` | no arguments | Dictionary with `api_id=HTML_VIEWER_API_v1`, `api_version=1`, `native_renderer=C`, `scripts=inactive`, `external_resources=inactive`. |
| `render` | `source` | Delegates the HTML string to the existing `documentRenderModel html` authority and returns its native presentation model. It does not register a Dataset or launch JavaScript. GUI presentation enablement does not disable this public rendering operation. |
| `open` | optional `context` dictionary, default empty | Requires enabled `viewer.html/html` presentation. An empty context opens the ordinary compatible Dataset selector. If supplied, `context.dataset_id` must identify a compatible canonical HTML Dataset in the current Session; that identity is preselected by the existing GUI Host. Returns the Viewer window. |

For an existing compatible canonical Dataset, the current host route is:

```tcl
set window [::GX::HTMLViewer::open [dict create dataset_id $datasetId]]
```

`$datasetId` must be an actual current-Session canonical identity, not a raw file
path. `datasetDocumentKind` resolves HTML through the existing declared contract,
media/language metadata and source association. A non-HTML selection fails
explicitly. Source inspection delegates to `datasetDocumentSourceOpen`; Session
lifetime changes require reopening, not a stale callback into another Session.

The no-context launcher offers the Session-aware compatible selector. With no
eligible Dataset it presents an empty selection and a readable prompt. Native
selection, rendering and close/reopen checks have been recorded; cross-Session
lifetime and final installed acceptance remain separate open gates.

Rendering supports the existing safe native presentation: headings, paragraphs,
lists, tables, links and preformatted code as documented by that owner.
JavaScript, forms, external/network resources and CSS are inactive; current
images are omitted. This is scientific document consultation, not a general
browser. Original canonical source bytes remain read-only and unchanged.

No `HTML_VIEWER_API_v1` Script Bridge registration or direct restricted C++ SDK
grant was present in the reviewed declaration inventory. Its existence must not
be advertised as an arbitrary `gxtxt_api_call` or C++ method. Current109's reviewed
`VIEWER_GUI_HOST_API_v1/document_bind` composes HTML through the existing shared
document owner and is a distinct typed SDK operation; consult that family's
current contract and project/profile admission.

The legacy inert text presentation provides Smaller, Larger and Reset controls.
They change local text fonts from 50% to 300% in 25 percentage-point steps;
Ctrl+plus (or Ctrl+equal), Ctrl+minus and Ctrl+0 offer the same actions while the
rendered document has focus. The existing document presentation owner keeps
these fonts local to that widget and deletes them with it. Zoom changes neither
canonical source nor the native HTML run model. This is text magnification;
CSS, external resources and JavaScript remain inactive. Native zoom acceptance
is pending the corresponding fresh-process GUI checks.

## TASK210 shared interactive host extension

The accepted existing-owner extension adds the host-only methods below. The
legacy `render source` still returns the same inert native run model, and `open
?context?` retains its Viewer selection contract. The original `apiInfo` fields
therefore describe that legacy operation; its additive `interactive` dictionary
reports the separate shared browser host. No new Script Bridge or restricted
C++ SDK admission follows from these Tcl host methods.

| Method | Exact arguments | Result |
| --- | --- | --- |
| `interactiveInfo` | none | `available`, bounded `reason`, backend/ABI/engine identity, declared and verified capabilities; performs no browser launch or compilation |
| `attach` | `parent ?options?` | Presentation receipt with opaque `handle`; options require `purpose=dataset` or `documentation`, optional `zoom_percent` |
| `load` | `handle source` | Asynchronous receipt; `source` is exactly `{kind dataset dataset_id ID}` or `{kind documentation document_id ID}` matching purpose |
| `navigate` | `handle request` | Asynchronous receipt; request has `action` and only that action's fields |
| `inspect` | `handle` | Current guarded presentation receipt |
| `detach` | `handle` | Cancels the owned managed process and releases presentation resources; repeat detach is supported |

The parent must be an existing owned Tk Frame. The host binds its native XID,
widget lifetime and source generation. A Dataset source must be canonical HTML
in the current Session; an indexed documentation ID must resolve through the
existing Documentation Browser owner. Neither operation accepts raw caller paths,
HTML strings, native window IDs, shell commands, JavaScript or arbitrary headers.

Navigation actions are `back`, `forward`, `home`, `reload`, `stop`, `relative`
with `target`, `zoom` with `percent`, and `find` with `text`. Zoom is50..300 in25
percent steps. Relative navigation stays inside the admitted package, with no
scheme, query, traversal, percent-encoded ambiguity or absolute path. Find text
is at most1024 bytes. The browser's user selection/copy remains ordinary native
interaction. The source API offers read-only source consultation independently.

Receipts have schema `gxtxt.html_presentation.v1`, `handle`, `generation`,
`state`, `purpose`, `source`, `zoom_percent`, `can_back`, `can_forward`, `title`,
`status`, `last_error`, `request_id` and `completed_request_id`. States include
`starting`, `loading`, `ready`, `unavailable`, `closing`, `closed` and `stale`.
The existing `<<GXHTMLChanged>>` Tk event retains its `handle`, `generation` and
`state` data keys and adds `receipt`: an immutable snapshot of this same public
receipt at notification time. It contains no native XID, process/channel, path,
resource lease or private binding. Existing consumers may ignore that additive
field. A queued callback must not infer completion from a later unrelated current
receipt; a subsequent resize/visibility acknowledgement may have advanced the
current `completed_request_id` before event delivery.

The typed HTML document owner provides two control rows: navigation, then Zoom
with Smaller/percentage/Larger/Reset. Steps use the unchanged absolute `navigate`
zoom request, bounded50..300 by25, and Reset requests100. Selection text is a
request rather than proof of native zoom: the displayed percentage comes only
from the guarded current presentation. Zoom actions wait for their exact request
completion in a source/handle/generation-matching event snapshot; unrelated or
unsolicited receipts cannot substitute for it. Terminal/source failure discards
the owned pending state. Widget/root incarnations, Session and source are checked
before callbacks; rebind, destruction and failed construction release owned
state. Only leaf controls receive state changes, not their layout Frames.

These restored control definitions and pure pending/receipt logic have no GUI
acceptance implication. Actual narrow layout, clicks, embedding and keyboard
focus remain separately tested by MAIN. No native Ctrl-key handler is added by
this control change; original keyboard parity remains unverified.
The public source identity changes only after matching native admission; the
previous surface is hidden while replacement is pending. A command receipt is
not proof of paint, CSS/JS execution or media playback. `<<GXHTMLChanged>>` on
the parent announces changes; consumers call `inspect`, without evaluating event
data. Source/Session changes invalidate the surface instead of rebinding it to
another Dataset. No PID, OS path or privileged browser channel is published.

Synchronous admission failures carry Tcl error code `{GX HTML CODE}`, including
`INVALID_ARGUMENT`, `UNKNOWN_HANDLE`, `HOST_GONE`, `HOST_IN_USE`, `SOURCE_KIND`,
`SOURCE_CHANGED`, `SESSION_CHANGED`, `NAVIGATION_BUSY` and runtime/capability
unavailability. Native failures appear asynchronously in `last_error` and the
presentation status. Timed-out navigation drains within a bound or retires its
owned host; reopening creates a fresh surface instead of accepting stale events.

When a managed cancellation is observed during polling, `last_error` retains
code `RUNTIME_EXITED` and the existing `code`/`message` keys. Its message appends
` Managed transport reason: TOKEN.`, where TOKEN is exactly `closed`,
`read_error`, `write_error`, `output_limit`, `timeout`, `cancelled` or `unknown`.
The first failure is retained through detach and terminal retirement. This is
a transport category, not proof of the cancellation initiator or native cause.
If terminal completion is the first observation, the existing generic closed
message remains; the diagnostic suffix is limited to the polling path.

The precompiled Qt6 WebEngine executable and SHA-bound `.info` receipt are
required under `core/nativegui/document/`. There is no compile-on-open fallback.
The current implementation supports X11 embedding only and needs the existing
managed request owner's public nonblocking `scriptJobRequestSend` and
`scriptJobRequestDrain` methods. Missing methods, binary/receipt mismatch,
unsupported platform or sandbox overrides produce explicit unavailability.
`available=1` establishes these admission prerequisites; `rendering_verified=0`
and empty `verified_capabilities` keep graphical acceptance separate.

The interactive host enables DOM, JavaScript, CSS, SVG and canvas in an isolated
off-the-record profile. Its custom nonce origin serves only ordinary bounded
web assets from the admitted root, with no symlinks, traversal, hidden paths or
implementation file types. Each source load has a new origin. Canonical Dataset
HTML is copied byte-for-byte through Resource Management into a private
presentation allocation containing only `index.html`; no authority over sibling
Session files is inferred. Relative Dataset asset bundles need an existing
canonical asset contract before they can be admitted. Installed documentation
packages use their declared package root and support relative web assets.

Page content receives no Tcl, Script Bridge, process, filesystem or scientific
publication bridge. Uploads, downloads, popups, privileged permissions, arbitrary
network, file URLs and remote debugging are denied. Recent native input authority
is one-use and bound to source generation/navigation before outward HTTP(S)
requests reach the existing safe opener. The experimental YouTube-only subresource
profile is bounded but actual client identification and playback remain
unverified; no spoofed Referer is inserted. Generator URI dispatch remains under
the existing generator owner's review and is unavailable in this batch.

Developer checks exercise the actual parser, confined reader, state reducer,
Tcl codec, catalog and metadata admission without starting a GUI. Embedded
rendering, focus/selection/copy, CSS/JS, media, parent destruction and complete
renderer-process drain still require MAIN-coordinated graphical validation.

Native-parent ownership follows the actual XID, including a closing or stale
process until managed completion. Recreating a Frame at the same Tcl path is a
new incarnation only when its native identity differs. Guides allocates a fresh
owned child Frame per manual/tutorial selection and destroys the retired child;
the surviving tutorial container is never reused as a native parent during drain.
Completed handles release private bindings, pending controls and allocations. At
most64 small terminal receipts remain for inspection/idempotent detach; older
handles return `UNKNOWN_HANDLE`. Active/draining handles are never evicted by
that retention bound. These source/lifetime rules still need actual GUI switch
and process-drain acceptance in MAIN's coordinated slot.
