# Documentation Browser API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE indexes installed public manuals from the live module/model/instrument
catalog and `docs/api`. This service complements the descriptor contract in
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
text and links. Relative links remain inside the installed module's documentation
root, the installed public framework documentation tree, or its explicitly
declared installed API references. Invalid paths/formats
produce a visible diagnostic. Final symbolic-link files are refused before reading. HTTP(S) links use the existing safe web-link opener;
other URL schemes are not executed. HTML, MathJax, arbitrary image formats and
full browser layout are not promised by this renderer. Manual text is never a
script and has no Save/Edit callback. File reading retains the 2 MiB limit.
