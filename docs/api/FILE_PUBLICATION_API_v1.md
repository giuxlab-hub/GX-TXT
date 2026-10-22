# File Publication API v1

SPDX-License-Identifier: GPL-3.0-or-later

`filePublicationPublishBundle artifacts ?create_only|replace? ?options?` publishes explicit
exports and their sidecars. Each artifact is `{id destination writer}`; IDs and
destinations must be distinct and the bundle contains 1–4096 artifacts. A writer
callback receives an owned output channel and a context with `completed`
receipts for preceding artifacts. Receipts expose the requested destination,
SHA-256 and byte count, allowing metadata to describe an already staged model
or CSV without reading its entire contents into a GUI list.

All writers finish before publication begins. Each visible file appears with
complete bytes; the bundle commit does not yield to GUI callbacks. Create-only
is the default. Explicit replacement stages backups and restores the original
bundle if a later artifact fails. Destination changes during preparation fail
without overwriting the other writer. Symlink and non-file destinations fail
preflight. An unexpected concurrent replacement during rollback is reported as
a recovery error, with its backup preserved.

Optional `options {create_parents 1}` permits explicitly requested nested export
directories, such as a TeX project's linked figures and bibliography. Default0
retains the existing requirement that destination directories already exist.
Preflight validates the complete bundle before creating any directories. On
failure, newly created empty directories are removed; existing directories or
directories containing published/other files remain. This extends the same
complete-file transaction; it is not an alternative project exporter.

Curve Fit exports and Workbench exporters use this common authority. Large
Curve Fit model JSON is streamed in bounded chunks beside the CSV; its metadata
records a relative filename and exact CSV/model hashes. Session Datasets remain
published through the existing Dataset Publication APIs.

`filePublicationTextDocument destination text text|pdf ?options?` adds a complete
section-document writer to the same create-only transaction. Text writes exact
UTF-8, including Unicode and line breaks. PDF delegates pagination to the existing
printing compositor; options are `page` (default A4), `orientation` (portrait)
and `margin_mm` (15). The service does not replace scientific plot/figure export
or save Dataset edits. It is host-only because the explicit external destination
belongs to the user's GUI file-selection workflow, not a Script Job capability.
