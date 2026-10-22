# Session HTML Export API v1

SPDX-License-Identifier: GPL-3.0-or-later

Installed module `export.session_html` declares version1, entrypoint
`api/session_html_export_api_v1.tcl`, namespace `::SessionHtmlExport`. It creates
an offline read-only presentation export of the current Session. It does not
create an importable scientific Session archive or rerun analyses.

## Exact host entries

| Signature | Arguments/defaults | Result/effect |
|---|---|---|
| `::SessionHtmlExport::export destinationParent ?makeZip?` | required filesystem parent directory; optional Tcl boolean default1 | synchronous export; returns result dict below |
| `::SessionHtmlExport::guiExport` | no arguments | loads the native UI and runs its directory chooser/information/error dialogs; no stable export-result return contract |

Trusted-host explicit export example, after normal API activation and opening
the intended Session:

```tcl
::GX::modulePublicApiActivate export.session_html SESSION_HTML_EXPORT_API_v1
set receipt [::SessionHtmlExport::export $newExportParent 1]
```

This writes files and optionally ZIP; it is not a discovery/read-only example.
The caller chooses a new destination and normal overwrite policy applies.

The current Session is resolved through currentSessionInfo. The destination
parent is normalized/created, then `<session-name>-html` is selected. An existing
target is refused. With ZIP enabled the helper also refuses an existing matching
ZIP. A temporary Session Inspection snapshot is written beside the destination
and deleted in finally. The installed Python3 helper uses that snapshot and
actual existing Session files/artifacts; no author source is executed.

## Result and presentation bounds

Successful export returns dict keys `directory`, `zip`, `file_count`,
`dataset_count`, `graph_count`, parsed as strings from helper output. `zip` is
empty when disabled. `directory/index.html` is the offline entrypoint; output
includes bundled assets, original-file copies and export-manifest.json with
presentation provenance/file identities. It does not become a second scientific
state store. Units/schema/notes/provenance are displayed from available actual
Session information; absence is not scientifically inferred.

CSV chunks contain up to2000 rows; the browser displays up to200 at a time and
sorting/filtering operates on the loaded chunk. For a source CSV strictly larger
than67,108,864bytes (64MiB), the generated browser preview contains at most10,000
rows and visibly identifies that limit. The complete original CSV remains
available through its original/download link. Smaller CSVs retain all data rows
in generated chunks. Do not describe this browser preview as full-resolution
scientific processing, or assume every row is browsable merely because the
original file is retained.

Existing graphs are presented rather than recomputed. Unsupported binary data
are copied/listed without invented interpretation. Offline browser actions do
not write back to the Session. A portable Session archive is the proper complete
scientific transfer/restore format; HTML remains presentation.

## Errors, ownership and language exposure

No current Session, missing Inspection capability/module/helper, existing
destination/ZIP and helper/file errors propagate as Tcl errors from export.
The GUI instead shows native diagnostics and returns on cancellation/error.
The current Tcl wrapper invokes `python3` synchronously and declares no separate
Job/cancel/paged-export contract. It deletes its snapshot in finally, but does
not promise automatic rollback/removal of a partially written export directory
after helper failure. Preserve failed output for diagnosis; do not silently
overwrite it on retry.

This family has no registered Python/Octave Script Bridge operation and no
typed C++ SDK method. The Python helper is an implementation owned by the
module, not a public import/CLI contract for independent consumers. There is no
generic C++ invoke. Related public owners are
[Session Inspection](SESSION_INSPECTION_API_v1.md),
[Session Action Provider](SESSION_ACTION_PROVIDER_API_v1.md),
[Graph Notes](GRAPH_NOTES_API_v1.md) and
[Portable Session](PORTABLE_SESSION_API_v1.md). The module's user guide is
SESSION_HTML_EXPORT.md; its older broad CSV wording must be read with the exact
preview limits above. This source-backed reference is not a newly executed
export, scientific equivalence or offline-browser acceptance test.
