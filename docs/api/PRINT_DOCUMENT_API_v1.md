# Print Studio and Print Document API v1

SPDX-License-Identifier: GPL-3.0-or-later

Use the existing main **Print / PDF** tab. Select Session content in the right
Content dock, inspect its source Preview and choose an available representation.
**Add selected content** adds only that item to the separate ordered Document
list. Browsing does not change the print queue or submit a printer job.

For a table, select its queue row and enter explicit Variable IDs, zero-based
first source row and count (1–10000, at most 64 columns). Apply the range.
Duplicate, remove or move queue items; Undo/Redo changes the composition through
the existing Scientific Recipe History owner. Save/Open composition uses the
current Session's existing Interactive Documents. A draft from another Session
must be discarded or reopened in its original Session before saving.

Set A4/A3/Letter, portrait/landscape, margins and artwork rows/columns in Page
setup. Tables and text paginate independently with repeated column headings,
units and exact source-row identities. Numeric strings are preserved without
intentional rounding, including 64-bit integers. Very large projections require
an explicit smaller range. Unsupported glyphs produce a diagnostic rather than
silently disappearing. Artwork fits the chosen physical cell without cropping;
original raster output below 100 effective PPI produces a resolution notice.

**Update Preview** explicitly accepts current source identities, freezes the
selected scientific content and assembles/validates its PDF asynchronously.
The main canvas and page thumbnails render that same final PDF with Poppler.
Previous/Next, page number, Fit Page/Width, zoom and drag scrolling use the frozen
PDF; they do not reload scientific Datasets or execute Analysis. Page/layout or
source changes mark the document stale and block Print/Save PDF until updated.
The old frame may remain visible while a replacement is prepared, with its
Update required status. New composition clears the old document.

**Save PDF…** explicitly publishes the reviewed PDF through File Publication.
It verifies its bytes and scientific source guards again, and confirms any
replacement in the standard file chooser. Export does not submit to CUPS and
remains available during failed/hung printer discovery. Scientific source
Dataset/analysis directories are protected from this derived-document export.

Printer / Export shows actual CUPS queues and selected-printer capabilities.
Refresh and Cancel Query operate asynchronously. Missing CUPS, no queues,
authorization, offline, timeout and output-limit failures remain distinct.
Duplex/media/color/resolution/tray choices come from the selected queue;
unavailable choices are disabled. The configurable CUPS timeout is 250–30000 ms
per OS command (default 3000). The last verified queue/cache is remembered, but
submission revalidates capabilities and document/source SHA. Only explicit
**Print** submits. The returned CUPS ID means accepted/spooled; it does not prove
physical completion. Job Status and Cancel Submitted Job use that actual ID.

Diagnostics opens a normally collapsed bottom drawer. Its visibility and the
user-dragged dock width/log height are Configuration-owned preferences. The
same command catalog drives menu, toolbar, right-dock actions and shortcuts.

## Scientific owners and supported sources

Canonical tables use Variable Schema and bounded Table Stream reads, including
accepted remote providers with account-local node configuration references.
Remote media with no declared original-file transfer offers metadata instead
of treating its small Preview as print authority. Source Preview uses the
accepted Session Preview Cache; its default/custom Render ownership is retained.

Original image/PDF/text payloads are verified by Session Inspection and remain
read-only. PDF insertion preserves source vectors and page order. Tables/text
use the existing Matplotlib PDF compositor; pypdf assembles pages and transparent
headers/footers. qpdf checks the final structure. Limits are 200 items/pages,
8 MiB recipe/text, 16 MiB selected table strings, 64 MiB original media and 96 MiB
final PDF. Errors leave the previous reviewed PDF intact.
Prepared content is bounded to 32 MiB and the managed intermediate tree to
384 MiB inside a 768 MiB reservation. Raster headers are inspected asynchronously
through `printDocumentMediaInfo`: single-frame 1/L/LA/P/PA/RGB/RGBA/CMYK images
up to 32 megapixels are supported. High-bit-depth, floating-point and multi-frame
sources offer metadata with an explicit reason; their values are never silently
reduced to an 8-bit image. Table columns use supported rank-one canonical types;
complex or multidimensional columns require another declared representation.
Source selections and late Preview/media results are scoped to the current
Session token and selection generation.

Native 2D Graphs and explicit XY projections use public Plot v4 widget export.
Print Studio never changes Plot Dataset implementation. Native3D Graph capture
uses its existing public scientific snapshot/presentation/render services into
managed private resources, with the frozen camera/axes/legend and 2400×1800
artwork; local source payloads are limited to 64 MiB. Arbitrary CAD/array scenes
without an accepted paper projection have an explicit metadata synopsis.
Graph annotation layers use the existing annotation compositor in the managed
worker; their original artwork and annotation files are never rewritten.

## Host contract

`printRecipeNew`, `printRecipeValidate`, `printRecipeHistoryCreate/Edit` and
`printRecipeDocumentSave/Read` retain the existing History/Interactive Document
authorities. Save checks the expected document generation/revision/SHA.
`printRecipeSourceSignature kind id` and `printContentDescribe kind id` expose
actual source identity and supported presentations, not another source registry.

`printDocumentRequest operation arguments callback` supports compose, page,
thumbnails, source_preview, verify and export. It allocates through Resource
Management before starting a bounded common Script Job auxiliary request.
Compose arguments contain current Session and inert recipe/configuration/node
reference data. Success returns the managed resource ID plus PDF path/SHA,
source manifest, pages/dimensions and notices. Call `printDocumentRelease id`
when finished. Page requests lease their source resource until their worker is
reaped; cancellation and delayed retirement cannot delete active outputs.
`printDocumentCancel token` cancels owned work, including allocations in flight.
No new scientific scheduler or process-killing engine is introduced.

`printCupsRequest operation arguments callback` is the bounded OS adapter.
`printCupsQuery channel operation arguments callback` coalesces requests on
four channels (discovery/capabilities/submission/status), waits for cancellation
cleanup, and delivers only the newest generation. `printCupsCancel channel`
invalidates pending replies; `printCupsState` exposes scoped diagnostics.
Commands use argument arrays, no shell interpolation. The common Supervisor
owns descendant cleanup. Resources/private node credential references must be
excluded from public evidence; receipts identify hashes and bounded outcomes.
