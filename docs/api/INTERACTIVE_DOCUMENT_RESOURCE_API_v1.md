# Interactive Document Resource API v1

An optional derivative may declare both `disposable=1` and
`scientific_authority=0` in its metadata. Workspace preflight/reference discovery
still validates logical owner/generation and SHA syntax, but permits a missing
or corrupt optional blob so its owning service can rebuild. Reader/Info remain
strict and verify complete size/SHA. Scientific resources retain strict
preflight. `interactiveDocumentResourceFinalize writer ?repair_disposable?` and
`interactiveDocumentNative2DStore document scene object ?metadata?
?repair_disposable?` default to false; true can atomically repair only a freshly
verified derivative with those two explicit flags. Symlinks are always rejected.
This adds no caller-selected storage path or scientific mutation authority.

CORE owns content-addressed binary resources associated with a real Session
Interactive Document. These resources do not register Datasets. References
contain the document ID, SHA-256, byte size, format and public metadata; no
private storage path is returned.

Open a writer with `interactiveDocumentResourceOpenWriter document metadata`.
Append binary chunks of at most 1 MiB, then finalize or abort. Finalization
verifies an existing content-addressed object before deduplicating it. Writer
tokens are process-local and Session-scoped. A failed writer can be aborted.

`interactiveDocumentResourceInfo` verifies identity, size and hash.
`interactiveDocumentResourceReadChunk reference start count` bounds arbitrary
reads to 1 MiB. For sequential bulk transfer, OpenReader/Next/CloseReader verify
the hash on opening and completion and keep bounded buffers. Reader tokens are
Session-scoped. Missing/corrupt resources and cross-Session use raise explicit
errors.

`interactiveDocumentResourceReadRanges reference {{start count} ...}` reads
an ordered sparse page with one verification transaction. It validates all
ranges first, permits at most 65536 ranges and 1 MiB total output, and returns
binary blocks in request order. This supports exact row locators without
repeated full-resource hashes or exposing a storage path.

`interactiveDocumentResourceCollect document ?live_references?` removes complete
blobs that are referenced by neither the current document payload/history nor
the supplied live preview references. It validates the full reference/deletion
set first, retains pending writers and rejects symlinks. The scan has explicit
depth and node limits. Close discarded previews before collecting; an accepted
geometry resource remains referenced in the saved document. Append accepts
binary byte values only; encode Unicode explicitly before calling it.
Singleton lists of accepted records retain nested resources during collection.

Collection also retains references from committed Dataset metadata, other
documents and active readers in the current Session lifetime. Deleting a
document closes its current reader/writer handles and removes unreferenced
blobs. Scientific blobs still referenced by published Datasets or other
documents remain readable under a retired resource owner, which accepts no new
writes and is not an Interactive Document entry. `Collect` also accepts such an
owner and removes it after its last reference is released. New references carry
the owner's persistent `owner_generation`; explicit document-ID reuse cannot
revive a former generation's reference. Opaque handle scope changes on Session
switch/return and same-path directory replacement. Portable content references
can be reopened in a newly opened copy of the Session.

The Native2D Store/Restore adapters stream complete geometry as interleaved
float64 little-endian XY, without a whole-geometry Tcl list. Failed restore
removes its partial native object. ImportNumeric streams an explicitly supplied
owned Numeric runtime artifact into CORE storage; it does not reconstruct any
canonical Dataset or Session target path.
Native2DRestoreWithGaps additionally consumes an owned
`native2d.uint8_break_before_v1` resource, one 0/1 byte per finite point. It
preserves missing-pair gaps across chunk boundaries and rolls back partial
geometry on any XY/mask shape, content or lifecycle failure.

Interactive Document metadata now includes a positive monotonic `revision`.
Older documents start at revision 1. Changed payload/format increments it;
an unchanged save preserves it. Extension contexts validate document ownership
and revision before execution.


## Registry ownership and bounded verification

Owner generation resolves against the authoritative Document registry without reading/hashing complete scientific payload for each receipt. Resource collection validates each distinct receipt identity once per complete bounded scan; a same-SHA receipt with changed size/generation is independently validated and rejected. Full SHA/corruption/symlink/lifetime validation is retained. Scientific arrays remain in owned resources rather than repeated GUI/history lists.


## Read-only dependency discovery and portable remapping

`interactiveDocumentResourceReferences value ?document?` returns the original
full verified resource receipts nested in an inert value. An optional Document
ID restricts results to that owner. It reuses the existing portable Workspace
reference enumerator and the same bounded validation scanner as Collect,
including nested metadata, Session/generation checks, SHA verification and
optional-derivative policy. It writes, deletes and allocates nothing. Scientific
interpretations and origins are preserved in the complete returned metadata.

`interactiveDocumentResourceRemapReferences value references` validates the
supplied current receipts and delegates rewriting to the existing portable
Workspace remapper, keyed by scientific content SHA. Untouched text keeps its
exact representation. A referenced resource absent from the supplied mapping
rejects; no guessed owner or filesystem path is accepted. This is an explicit
value transformation, not a resource or Dataset mutation.

Python and Octave expose `references`, arguments `{payload_utf8, document_id}`,
and `remap_references`, arguments `{payload_utf8, references}`. A consumer storing
an opaque History snapshot in a managed blob can retain the full dependencies
in its resource metadata. Existing Collect/export/import scanners preserve them;
after import, restore can explicitly remap embedded owner references through
that same existing authority. No separate dependency registry is introduced.
