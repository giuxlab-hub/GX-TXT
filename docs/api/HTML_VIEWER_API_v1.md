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

Rendered HTML document components provide Smaller, Larger and Reset controls.
They change local text fonts from 50% to 300% in 25 percentage-point steps;
Ctrl+plus (or Ctrl+equal), Ctrl+minus and Ctrl+0 offer the same actions while the
rendered document has focus. The existing document presentation owner keeps
these fonts local to that widget and deletes them with it. Zoom changes neither
canonical source nor the native HTML run model. This is text magnification;
CSS, external resources and JavaScript remain inactive. Native zoom acceptance
is pending the corresponding fresh-process GUI checks.
