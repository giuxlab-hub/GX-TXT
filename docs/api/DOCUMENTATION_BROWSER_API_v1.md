# Documentation Browser API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE indexes installed public manuals from the live module/model/instrument
catalog and `docs/api`. Public provider API manuals declared by installed module descriptors are also indexed under `api:API_ID`, including manuals stored beside the provider implementation. Discovery reads descriptors without activating scientific code. Canonical framework references take precedence; conflicting provider-document declarations remain unavailable rather than guessing an owner. Relative provider manual paths must stay inside their installed module, with symbolic-link files refused. This service complements the descriptor contract in
[Documentation API v1](DOCUMENTATION_API_v1.md).

| Script operation | Arguments | Result |
|---|---|---|
| `list` | optional query string | Documentation descriptors, with filesystem paths removed |
| `read` | document ID returned by `list` | UTF-8 document text; files larger than 2 MiB are refused |

Python and Octave use the same registered public operations:

```python
entries = gxtxt_api_call('DOCUMENTATION_BROWSER_API_v1', 'list', ['Dataset'])
text = gxtxt_api_call('DOCUMENTATION_BROWSER_API_v1', 'read', [entries[0]['id']])
```

IDs identify the current installed document index. Unknown IDs fail explicitly.
Query matching is case-insensitive against ID, category, title and owner. The
About entry is generated from the actual framework version and license.

The Tcl host owns `::GX::documentationBrowserApiInfo`,
`::GX::documentationBrowserRefresh`, `::GX::documentationBrowserList ?query?`
and `::GX::documentationBrowserRead id`. Catalog reload rebuilds the index, so
plugin installation/removal does not leave stale entries. Index mutation, Help
widgets and `sessionDocumentationSnapshotModule` remain host lifecycle actions.
Reading documentation performs no scientific Dataset or Session publication.

## Independent Viewer manuals

`::GX::documentationBrowserOpenModuleWindow module_id ?parent?` is a host-only
GUI operation. It opens a non-modal read-only Tk toplevel titled with the installed
module's name. The descriptor's available `manual`, `guide`, then `quick_start`
is selected in that order. Missing or uninstalled documentation has an explicit
visible unavailable state; another module's guide is never substituted.

Each module window owns its search text, scroll position, current document and
Back/Forward navigation. Repeated invocation raises the same window. It survives
closing its requesting Viewer; closing it changes no Viewer or scientific state.
Find next, Ctrl+F, Escape, resizing and ordinary text selection are supported.

`documentationBrowserAttachViewerHelp module_id viewer_id window` connects a
normal Tk window returned by the public Viewer dispatcher to **Help → User
Manual… / F1**. Existing plugin-local F1/Help remains authoritative. A plugin can
call the shared operation directly; it does not require a framework modification.
Foreign/non-Tk backend results are not treated as Tk windows. The central Help
notebook retains its existing operation and state.

The existing GX-Markup renderer supplies headings, emphasis, code, simple table
text and links. In ordinary text paragraphs, emphasis delimiters may span source
line breaks; the rendered text retains those line breaks. Blank lines and the
existing heading, list, fenced-code, table and trusted-image blocks end that
paragraph. This changes presentation only: public documentation reads return the
unchanged source, including its markup delimiters and line breaks.
Relative links remain inside the installed module's documentation
root, the installed public framework documentation tree, or its explicitly
declared installed API references. Invalid paths/formats
produce a visible diagnostic. Final symbolic-link files are refused before reading. HTTP(S) links use the existing safe web-link opener;
other URL schemes are not executed. HTML, MathJax, arbitrary image formats and
full browser layout are not promised by this renderer. Manual text is never a
script and has no Save/Edit callback. File reading retains the 2 MiB limit.

Independent module windows also render standalone Markdown PNG image lines
(`![caption](images/example.png)`) through the existing markup owner's optional
trusted image callback. Paths must be relative and remain inside the installed
module root. Files are limited to 8 MiB and dimensions to 4096 × 4096; remote
images and final symbolic links are refused. Ordinary markup consumers need not
provide this callback and acquire no new file-reading capability.

Screenshots scale to the manual's available width. **Open screenshot at full
size** opens a separate native scrollable image window; closing either host
releases its owned photo resources. These are display resources, never a second
documentation store. Language-labelled fenced code blocks render as code.
Section links use normalized heading anchors, with the existing text-search
fallback for older documents. Manual search and history remain per module.

## Exact host and Script contracts

Index/read ownership is `core/tcl/documentation_browser_api_v1.tcl`; existing
main Help GUI entrypoints live in `app/gui/documentation_browser.tcl`, independent
manual integration in `app/gui/documentation_module_window.tcl`, and API-reference
resolution in `core/tcl/module_api_v1.tcl`. The actual Script declarations and
path projection are in `core/script_bindings/public_core_services.py`.

The following are public host entries in `::GX`; GUI entries require the existing
Tk host. A module manual window does not require a scientific Session.

| Tcl signature | Result and preconditions |
|---|---|
| `documentationBrowserApiInfo` | dict containing API name/version, `source descriptor_index`, and declared GUI host operation names |
| `documentationBrowserRefresh` | rebuilds the existing index from the loaded descriptor catalogs and installed docs; returns ordered document IDs; does not activate scientific module implementations |
| `documentationBrowserList ?query?` | query default `""`; ordered descriptor dict list for the current index |
| `documentationBrowserRead id` | UTF-8 text for current indexed ID, or generated About text; unknown IDs/file errors propagate |
| `documentationBrowserOpenReferenceWindow path module ?parent?` | an installed provider/public documentation path through the same confined independent manual owner; returns the actual window |
| `documentationBrowserOpenApiWindow api ?module? ?parent?` | normal indexed API reference in an independent manual window; returns that actual window |
| `documentationBrowserManualInspect window` | transient source-correlated presentation receipt for an owned manual window |
| `documentationBrowserOpenApi api` | selects the indexed `api:API_ID` in the existing main Help UI and raises root; returns that document ID; unavailable API manual errors |
| `documentationBrowserOpenModuleWindow module ?parent?` | parent default `{}`; returns/reuses module-owned independent manual toplevel; current implementation accepts parent but does not make the window transient |
| `documentationBrowserAttachViewerHelp module viewer window` | attaches to a normal Tk Viewer toplevel when eligible; side effect only, no stable result value |

Host descriptors contain `id`, `category`, `title`, `type`, `path`, `owner` and
`version`. **Only the Script Bridge list projection removes `path`.** Index IDs
include `api:NAME`, `module:ID:guide`/`manual`/`quick_start` and core guide/About
IDs; use IDs actually returned by list rather than synthesizing a guessed path.
The host refresh result is not the list of descriptors; call List after Refresh.

The actual Script registration declares only:

| Operation | Positional arguments | Result / transport |
|---|---|---|
| `list` | optional `query` string, omitted means `""` | Python list / Octave cell of descriptor structs, with path removed |
| `read` | required `document_id` string | Unicode/UTF-8 text |

For an already configured and admitted Python Script Bridge context:

```python
entries = gxtxt_api_call("DOCUMENTATION_BROWSER_API_v1", "list", ["SOURCE_SURFACE_API_v1"])
entry = next(item for item in entries if item["id"] == "api:SOURCE_SURFACE_API_v1")
text = gxtxt_api_call("DOCUMENTATION_BROWSER_API_v1", "read", [entry["id"]])
```

Octave uses the same operation names with a positional cell argument list:

```octave
entries = gxtxt_api_call('DOCUMENTATION_BROWSER_API_v1', 'list', {'SOURCE_SURFACE_API_v1'});
text = gxtxt_api_call('DOCUMENTATION_BROWSER_API_v1', 'read', {'api:SOURCE_SURFACE_API_v1'});
```

The runtime must provide the actual bridge functions/context; ordinary standalone
Python/Octave sessions do not gain them from this Markdown. There is no generic
C++ invoke and no typed `gx::Host` Documentation Browser method in the supported
SDK. Development's supported document-read projection remains a distinct
[Viewer Development](VIEWER_DEVELOPMENT_API_v1.md) contract.

## Resolver and failure boundaries

For a bare API reference the existing resolver first selects an existing common
`docs/api/NAME.md`; otherwise it considers valid module-relative
`public_api.NAME documentation` paths. A unique path resolves; multiple distinct
provider paths are ambiguous and unavailable. Shared API IDs must retain their
provider metadata even when a common family reference is selected. A missing
manual is not evidence that its implementation is missing or admitted.

`documentationBrowserRead` refuses files larger than 2,097,152 bytes and reads
UTF-8; it is not a filesystem read-by-path API. The low-level indexed Read and
the rendered module link/image reader are different paths: final-symlink and
allowed-root checks described above belong to the rendered module reader and
provider-relative resolver, and must not be generalized to every index read.
Removed files/unknown IDs can fail; a consumer should rediscover after catalog
changes. No document text is evaluated as code by these public operations.

The main Help view uses the same packaged PNG image owner as the independent
module manual window. Canonical guides resolve relative PNGs beneath the
framework `docs/` tree; indexed module documents retain their module root.
Images are bounded to 8 MiB and 4096 by 4096 pixels, fit the actual text width,
and expose an ordinary scrollable full-size screenshot window. Switching
documents releases the old image photos and screenshot window. This adds no
filesystem operation to Script or C++ clients.

AttachViewerHelp leaves an existing plugin-local F1 binding authoritative,
honors the existing host Help request policy, and currently excludes the
Curve Digitizer adapter. Its accepted `viewer` parameter does not select an
alternate module manual. A non-Tk result, non-toplevel or destroyed widget is
ignored. The operation is host lifecycle integration, not a Script command.

No scientific units apply to IDs, query text or UTF-8 manuals. Limits are byte
and image/presentation limits; scientific precision and the completeness of
each manual remain their actual public owner's responsibility. Discovery/read
success is not proof of all-functions documentation or release acceptance.

## HTML manuals and installed tutorial packages

The existing index also admits declared `.html`/`.htm` documents. HTML selection
opens the same module Guides window using the shared `HTML_VIEWER_API_v1`
interactive host; HTML is never passed to GX-Markup. Markdown/text keep their
existing renderer and original source bytes. An installed valid HTML manual is
preferred through `module:MODULE:html_manual`, followed by the existing manual,
guide and quick-start order. `module:MODULE:guide` remains unchanged for old
public/Script reads. Missing native capabilities show explicit HTML
unavailability and offer the preserved Markdown manual when installed.

The module window retains its invocation and repeated-open identity, with
Manual and Interactive Tutorial tabs. Tutorial selection uses the same descriptor
index, with independent native handles/lifetimes for the two presentations. Main
Help HTML selection delegates to this shared host. Curve Digitizer remains ASIS.
Its existing Help/F1/HELP_OPEN route remains separate from this shared window. Compatibility belongs to the existing CORE owner, without altering or monkey-patching the vendor implementation.

Installed packages are discovered at fixed versioned-framework paths:
`docs/guides/*/*/documentation-package.ini` and
`docs/tutorials/*/*/documentation-package.ini`. They do not introduce a registry
or a package installer. MAIN stages separately distributable packages through
normal framework delivery; no user-facing documentation ZIP installer is implied.
Each manifest has the single section `[documentation_package]`:

| Field | Contract |
| --- | --- |
| `api_version` | Exactly `1` |
| `id`, `module_id` | Stable safe IDs; module must be installed |
| `kind` | `manual` or `tutorial` |
| `version`, `title`, `license` | Required bounded content version/display/provenance text |
| `entrypoint` | Ordinary relative HTML/HTM file within this package |
| `entry_sha256` | Required lowercase SHA256 of the actual entrypoint bytes |
| `tested_module_version` | Optional descriptive provenance |
| `generator_library_id`, `generator_id` | Optional paired exact registered identities; no implicit library |
| `tested_generator_version` | Optional descriptive provenance |

Unknown keys, missing fields, invalid hashes, paths/symlinks outside the package,
uninstalled owners, duplicate IDs and conflicting manuals are unavailable with
catalog diagnostics. Version1 limits are16KiB manifest,2MiB entrypoint and1024
installed manifests. Registration IDs are `content:CONTENT_ID`; a manual also
gets its module selection alias. Three independently packaged tutorials therefore
appear as three ordinary same-catalog entries, without a new tutorial registry.
The normal public List result retains its original seven fields; host-only asset
root/manifest metadata never enters the Script list projection. Public Read
returns the original UTF-8 source, including HTML, under its existing2MiB limit.

Host-only `documentationBrowserResolve id` validates current manifest/source
identity and supplies the confined root to the shared browser;
`documentationBrowserModuleTutorials module_id` selects tutorial entries by
installed owner. Every native source switch rechecks admission. Relative assets
stay inside the package; a changed manifest/source requires catalog refresh and
reopening. Resource type and byte budgets remain browser presentation limits.
Generator metadata provides a native **Open Generate Session…** button beside
an admitted HTML manual/tutorial when its paired library/generator IDs are
declared. This host button calls the accepted `sessionGeneratorOpenSelection`
owner with that exact pair. It never installs, enables or runs a generator.
The existing dialog preserves the user's normal name/Location/Project and
documentation options; its ordinary Generate control remains the user's action.

The button is disabled while loading/unavailable or on another tab. Its action
captures the current indexed source and manifest SHA, module owner, pair,
selection serial, HTML handle/generation and actual window/child incarnations.
A click re-resolves and compares that identity; metadata-only pair changes,
source replacement, stale Session/window or retired handles require explicit
reload/reselection. A busy dialog produces bounded retry guidance without modal
theft or automatic retry. Completion updates only the surviving original context;
the Generator dialog keeps its own lifetime if the manual closes. Missing host
operation or HTML support retains plain normal-selection guidance. No URI,
page-script, Script Bridge or restricted SDK capability is introduced.

The native control uses the accepted host selection operation. It does not grant
URI dispatch, automatic generation or Session creation. Independent GUI
validation is required to establish the actual tab layout, renderer presentation
and retained plugin-local Help/F1 behavior; index/read success alone does not
establish them.

## Owned presentation inspection

`::GX::documentationBrowserManualInspect window` is a read-only host operation
for an actual independent manual window returned by the existing normal opening
route. Unknown/destroyed windows or changed window incarnations fail explicitly.
The result uses `gxtxt.documentation.presentation.v1` and contains `window`,
`window_id`, `module`, a positive presentation `generation`, `document_id`,
`path`, `source_sha256`, `format`, `renderer`, `state`, `error` and
`rendering_verified`.

Each attempted document selection owns a new transient receipt. Source identity
is validated before rendering; a source that changes while opening fails. The
existing GX-Markup path reports `ready` only after its synchronous widget update
succeeds. HTML retains the actual public `HTML_VIEWER_API_v1` native receipt,
renderer generation, loading/ready/error state and bounded error. Failure to
attach the actual HTML runtime remains visible even when the document file is
present. No new renderer, document index or persisted result registry is created.

A caller must correlate the actual window incarnation, document path, source
SHA and presentation generation before associating a result with an API/provider.
A reused window can display another source. `ready` is a renderer outcome, not
independent proof of correct pixels; `rendering_verified` remains false. Physical
paths and GUI lifetimes make this operation host-only. Existing Script list/read
projections and scientific admission remain unchanged.

`::GX::documentationBrowserOpenReferenceWindow path module ?parent?` opens an
explicit already-declared host/Bridge document when the common API-family manual
is a different valid surface. It validates the installed module/public-docs path
through the existing manual owner and its bounded source resolver, then reuses
the same module window, GX-Markup/HTML renderer and transient presentation receipt.
Linked documents remain in the existing derived documentation index; no second
manual file or persistence store is created. Outside, linked, oversized or
unsupported files fail. This physical-path GUI operation is host-only and adds
no Script read-by-path capability or scientific provider activation.

## P031 manual-host references

The existing module manual window provides primary File, View and References
menus. References links its descriptor-indexed preserved Markdown manual and
declared available `documentation.api_refs` through the same resolver, renderer,
source-SHA receipt and history. A current descriptor/index check at invocation
refuses stale, removed or undeclared targets. Missing references are visibly
unavailable. General navigation remains available through File/View and existing
controls. No document store, renderer, API capability or filesystem grant is
added. HTML resources retain their package containment; an HTML guide can point
readers to References for original Markdown and public CORE/API documents
without embedding dead cross-package/raw-Markdown HTML links.

The existing `documentation.html_manual` descriptor entry is indexed alongside
`guide` and `manual`, so a declared illustrated HTML manual can be the normal
User Manual while preserving the original Markdown reference. View also exposes
the existing shared HTML zoom operations (50–300%, 25% steps and reset100%) for
the active manual/tutorial; unavailable or bounded actions are disabled. This
changes presentation only, with source and native generation checks retained.
