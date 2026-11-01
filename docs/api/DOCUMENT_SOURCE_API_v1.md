# Document Source API v1

SPDX-License-Identifier: GPL-3.0-or-later

The existing CORE document source owner provides guarded canonical Markdown
reading and editing. `documentSourceApiInfo` describes the interface.
Dataset File Publication, Dataset Authority, Metadata, managed resources and
GX-Markup retain their existing responsibilities. A document is a canonical
`document.text` Dataset, not an executable source or a numeric Variable.

## Headless operations

`documentSourceRequest capability operation request` accepts `describe`, `read`
and `write`. The capability is issued by CORE for the actual module. No actor,
producer identity, shell command, source pathname or Tcl callback can be supplied
through the request. Script Bridge and restricted native SDK admission belong
to their existing hosts; this Tcl facade does not issue those grants.

Describe with an empty request returns the current publication context without creating a Dataset; otherwise describe/read require `dataset_id`. Optional `expected_session` rejects a changed
Session. Read accepts `limit`, between1 and4194304 UTF-8 bytes, default4194304.
It returns `source`, `complete`, `bytes`, `sha256`, the opaque Dataset `revision`
and Session receipt, producer/immutable state, human-readable structured metadata,
managed `assets`, association diagnostics, and `can_replace` for the actual actor.
Read preserves UTF-8 and CRLF bytes; malformed UTF-8 fails. A bounded preview may
omit an incomplete final Unicode scalar and reports `complete=false`.

Python and Octave discover this service through the existing Script Bridge
under `DOCUMENT_SOURCE_API_v1`. Each operation takes one request structure:

```python
from gxtxt import gxtxt_api_call
context = gxtxt_api_call("DOCUMENT_SOURCE_API_v1", "describe", [{}])
created = gxtxt_api_call("DOCUMENT_SOURCE_API_v1", "write", [dict(
    mode="new", dataset_id="my_note", text="# Note\n",
    expected_session=context["session"])])
```

Octave uses `gxtxt_api_call('DOCUMENT_SOURCE_API_v1','describe',{struct()})`.
Script revisions are opaque, transient receipts from describe/read/write; callers
return the exact receipt for replacement or copy. They cannot supply internal
Registry revision tokens. Receipts are scoped to the current bridge/Session and
limited to128 recent revisions. A restarted Job must reread before replacement.
Actual runtime capabilities determine the producer; API calls accept no actor
selector. Committed writes enter the normal Job publication bookkeeping.

The compatible existing `datasetDocumentRead id ?limit?` remains available;
its default is262144 bytes. Its existing `source`, `complete`, and `sha256`
fields are preserved, with an additional byte count.

Write request:

```text
mode                 new | replace_existing
dataset_id           reviewed destination ID
text                 UTF-8 text, at most4MiB, without NUL
expected_session     exact Session receipt from the source owner
expected_revision    required for replace_existing
expected_sha256      required for replace_existing
source_dataset_id    optional original when publishing a distinct copy
source_revision      required with source_dataset_id
assets               optional logical-name → managed-resource descriptor map
```

`datasetDocumentWrite capability request` is the same operation. New publication
creates a distinct Markdown Dataset and never replaces an existing ID. Copy
publication retains source Dataset lineage and the supplied source snapshot SHA.
An unchanged source revision is marked `current_verified`; a prior snapshot is
honestly marked `declared_prior_revision`, allowing Publish New after stale
Save Existing refusal while preserving the current original. Replacement requires the
complete current Dataset revision and SHA, keeps its ID and producer, and is
permitted only for the same file-publication producer or an explicit existing
producer-issued current-revision edit grant. Immutable, foreign and stale
documents fail without changing their previous content. Namespace permissions
and grant policy remain owned by Dataset File Publication.

Payload staging, Registry, Metadata and protected managed-asset references commit
in one Dataset Authority transaction. A failure restores the former canonical
state; callers retain their draft. The result is a new Describe receipt. The
facade does not manufacture a foreign producer grant or publish a source note
association from user-supplied metadata.

Asset references use existing Interactive Document resources. Up to32 logical
names are accepted, each4MiB at most and16MiB total. Existing resources remain
subject to strict owner-generation/Session/size/SHA validation. Asset content is
not automatically published as another Dataset. Portable copying and Workspace
adoption use their existing owners rather than author-selected storage paths.

Trusted hosts can create the first image owner without a preexisting Workspace
using `datasetDocumentAssetOwnerCreate capability ?origin?`, then call
`datasetDocumentAssetWrite capability owner logical_name metadata bytes`.
The ordinary existing Interactive Document has provider `markdown_assets`,
format `gxtxt.markdown_assets.v1`, and contains resource references, never another
Markdown body. Validate/Close use `datasetDocumentAssetOwnerValidate` and
`datasetDocumentAssetOwnerClose`. Dataset/Workspace/History references retain
immutable resources when this carrier retires; discarded unpublished resources
are removed through the existing resource owner.

The privileged portable importer uses
`_datasetDocumentAssetOwnerCreateForImport origin`, where origin is exactly
`{operation portable_dataset_import source_dataset_id OLD destination_dataset_id NEW}`.
Its fixed CORE resource owner is `core.document_source`; this grants no foreign
Dataset producer identity. `_datasetDocumentAssetOwnerCloseForImport owner`
performs matching generation/Session-guarded cleanup on success or rollback,
including collection of exact unreferenced retired resources. These host helpers
are not script-callable actor selectors.

Markdown image targets use `assets/LOGICAL_NAME`, for example
`![caption](assets/image.png)`, with `image.png` in the managed asset map.
The shared trusted callback resolves that logical name against verified
resource receipts; the Markdown text cannot select a filesystem root.

`sourceNotePortableMetadata metadata sourceDatasetId newDatasetId` strips the
reserved `_gxtxt.framework.source_note_v1` primary attachment and old edit grant
on generic Dataset copy/import. It retains a validated inert association under
`_gxtxt.framework.source_note_origin_v1`. A copied note never silently becomes
the primary note for another source; explicit source-owner reconciliation is
required. Source association callbacks and unknown schema fields are rejected.

## Trusted embedded editor

`documentEditorMount parent options` returns an opaque process-local handle.
Options include `mode=editable|read_only`, `initial`, `dataset_id`, the actual
module `capability`, `assets`, `toolbar`, a trusted `on_change(handle, receipt)` callback and an optional
trusted `on_command(handle, operation)` callback.
New consumers default to no toolbar; general commands belong to their existing
primary menus. An editable mount reuses `buildMarkupEditorWidget` with the
existing Markdown Source Surface (syntax, Find/Replace, text editing) and shared
rendered pane. No additional top-level or editor engine is created.

Read-only mounts accept `pane=rendered|source|metadata|associated_source`.
The standard Preview host supplies its existing tab containers; the document
owner creates no second Preview notebook. Associated Source delegates to the
source-note authority when present and otherwise reports unavailable honestly.
Source, rendered and metadata text use native selection and UI Text Editing.

`documentEditorCommand handle operation ?request?` currently implements:

- `inspect`, `draft_get`, `draft_set`, `render`, `capture`, `restore`, `dispose`;
- `new`, `open`, `save_existing`, `publish_new`;
- `cut`, `copy`, `paste`, `select_all`, `undo`, `redo`, `find`, `replace`;
- `heading1`, `heading2`, `heading3`, `bold`, `italic`, `inline_code`, `code_block`,
  `bullet_list`, `numbered_list`, `table`, `link`, `quote`, `rule`, `color`;
- `view_source`, `view_rendered`, `view_outline`, `view_properties`,
  `view_resources`, `reset_layout`;
- `zoom_in`, `zoom_out`, `zoom_reset`;
- `insert_image`, `replace_image`, `remove_image`.

Open/Publish New receive an explicit reviewed `dataset_id` from their trusted
host. New/Open refuse a dirty transition until the host has performed the
normal Save/Discard/Cancel decision and supplied `discard_confirmed=true`.
Find/Replace focus existing Source Surface controls. Hiding a pane forgets and
reinserts the same widget through the existing ttk pane owner; it does not destroy
the draft. This follows the existing CurveWorkbench show/collapse concept:
retained panes and controls, no alternate layout manager. Outline headings
select the actual source line. Properties show the bound canonical ID, producer,
baseline SHA, permissions and reviewed destination. Resources inspect managed
image identity/metadata and provide Add/Replace/Remove actions.

With `on_command`, focused-source CtrlS/CtrlShiftS invoke exactly
`save_existing`/`publish_new` through the trusted parent primary command path.
F8/F7/Ctrl0 invoke the corresponding zoom command from source or rendered text;
read-only mounts with no callback apply local presentation zoom. Native clipboard
and Undo/Redo and the shared Source Surface Find/Replace bindings are preserved.

Image actions accept an explicit trusted `{name bytes caption}` request or use
the normal PNG chooser. They bound encoded bytes to4MiB and dimensions to4096,
validate with the existing Tk PNG decoder, and use the existing managed-resource
writer. Metadata uses declared `resource_metadata` fields: format/media_type,
filename, role=markdown_image, width/height, scientific_authority=true and
disposable=false, plus the writer's typed origin. Images resolve only
`assets/LOGICAL_NAME`; arbitrary Markdown paths cannot select filesystem data.
Insert adds Markdown text, replacement retains its logical name, and removal
changes the draft asset map while preserving the source for explicit review.
The image owner receipt is transient and retires through its existing owner on
disposal; Dataset/Workspace/History references retain published resources.

Inspect reports status, Dataset ID, dirty/read-only state, association, baseline
SHA and Session. `can_replace` is the admitted binding permission snapshot;
`permission_state=binding_snapshot_revalidated_on_save` makes this explicit.
Keystroke notifications do not acquire Dataset locks or hash canonical files.
Every Save still revalidates the complete live revision and permission.

Capture returns `gxtxt.markdown_draft.v1` with text, baseline text/identity,
managed-resource receipts, pane visibility, source cursor/selection/scroll,
zoom factor, reviewed destination ID, and normalized splitter ratios keyed by
stable logical names (`splitters.main`). Scroll fields `xview`/`yview` contain one
normalized first anchor; the visible end fraction depends on the viewport and
is never durable user intent. Restore also reads a legacy two-fraction pair.
Splitters start with logical default ratios before mapping. The existing ttk
owner applies those ratios on map/resize and records actual sash gestures;
mapping alone never changes capture. Optional keys such as
`main_source_rendered` preserve custom ratios for retained visibility layouts,
without widget paths. Baseline image references are retained
separately in `baseline.assets`, so image-only changes and History restoration
remain truthful. The baseline uses a fixed identity record; no widget path,
callback, module capability or transient image-owner receipt is persisted.
The live Session carrier path is removed from the saved revision token.
Restore changes the draft only and never publishes or overwrites a Dataset.
Existing Workspace/History hosts own persistence and resource adoption. A
restored stale baseline remains stale and cannot silently become Save authority.

Portable Dataset, Dataset Group and dependent Graph export use the existing
Portable Resource owner to collect each declared image reference through the
managed-resource authority. A bounded package index and deduplicated image
blobs accompany the canonical text and metadata. Import verifies their exact
association, SHA and size, adopts image bytes under a fresh Interactive Document
asset carrier, and remaps resource identities without editing Markdown URLs
(`assets/LOGICAL_NAME`). Successful Dataset metadata retains retired carrier
resources. Failed imports retire their request-owned carriers after the Dataset
authority has rolled back. Generic copies retain source-note lineage separately
without creating a live primary association or inheriting an old edit grant.

Viewer Workspace capture encodes Markdown drafts explicitly: text and baseline
text, immutable canonical baseline, current and baseline asset maps, pane
visibility, cursor/scroll positions, zoom and reviewed destination ID. Image
references use existing typed resources, with existing resource metadata field
semantics and inert text extensions. Workspace/History Save and Restore never
publish the canonical document. No capability, callback, Tk path or temporary
asset-owner receipt is persisted. Native Workspace retention and Save As remain
the existing shared owners.

Source-note canonical integration and final Documents/Preview modules require
their separate language, native GUI and installed-artifact gates. Shared-owner
author tests do not constitute independent release acceptance.

## Shared rendering subset

The existing GX-Markup owner supports plain paragraphs, ATX headings1–3,
bold/italic, inline and fenced code, lists, readable fixed-font pipe tables,
GX-Markup colors, simple HTTP(S) links, block quotes and separators. All
consumers call the same renderer; malformed markup remains visible text.
Inline styles respect configured font sizes, including enlarged fonts. Plain
paragraph runs are inserted together rather than copying their remainder for
every character.

Internal heading anchors and relative Markdown document navigation remain an
explicit unsupported subset and display literal syntax. Authorized documentation
PNG roots use the existing trusted Documentation Browser callback; canonical
managed images use the same renderer with the existing strict resource owner.
Neither path permits the Markdown text to choose an arbitrary filesystem root.
Source and rendered text retain native selection and shared clipboard behavior.

Trusted hosts rebuilding an editor retain its captured assets before destroying
the old host. `datasetDocumentAssetOwnerRetain capability assets ?owner?`
creates/reuses the ordinary Markdown asset carrier and retains references only;
it copies no Markdown or bytes. Restore retains both draft and baseline assets
before applying text, with at most64 references/32MiB for those two snapshots.
It preserves reference identity and captures no capability/carrier. The host
must close its temporary handoff carrier only after replacement restore has
adopted references, or after explicit reviewed discard. Reader tokens alone are
insufficient across owner deletion: the normal resource Delete owner drains its
readers. Resource Delete policy is unchanged.

P031 adds shared heading anchors and authorized relative Markdown navigation
through the same renderer/Document host. Optional host context identifies an
existing documentation entry, registered Session Files item or canonical
Markdown Dataset and rechecks source SHA/full revision/Session on activation.
It accepts no arbitrary root, adds no Script/native capability, and preserves
editor drafts when opening another canonical document. See
[shared Markdown navigation](MARKDOWN_NAVIGATION_v1.md) for normalization,
supported contexts, keyboard/selection behavior and explicit refusals.
