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
