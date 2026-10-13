# File Publication API v1

SPDX-License-Identifier: GPL-3.0-or-later

`filePublicationPublishBundle artifacts ?create_only|replace?` publishes explicit
exports and their sidecars. Each artifact is `{id destination writer}`; IDs and
destinations must be distinct and the bundle contains 1–64 artifacts. A writer
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

Curve Fit exports and Workbench exporters use this common authority. Large
Curve Fit model JSON is streamed in bounded chunks beside the CSV; its metadata
records a relative filename and exact CSV/model hashes. Session Datasets remain
published through the existing Dataset Publication APIs.
