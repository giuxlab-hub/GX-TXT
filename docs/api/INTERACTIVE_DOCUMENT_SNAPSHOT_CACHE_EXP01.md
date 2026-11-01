# Experimental checked Document working set

SPDX-License-Identifier: GPL-3.0-or-later

NOT ACCEPTED / NOT FOR INSTALLATION. Additive operations in the existing
INTERACTIVE_DOCUMENT_API_v1 family; canonical formats and P017 History unchanged.

```tcl
::GX::interactiveDocumentReadCached $documentId ?stored|current?
::GX::interactiveDocumentMetadataBatch $documentIds
::GX::interactiveDocumentCacheStatus
::GX::interactiveDocumentCacheConfigure {byte_budget 8388608 entry_budget 128}
::GX::interactiveDocumentCacheClear
```

Cached Read has the same metadata/payload result as Read. The first capture is
bounded to64MiB and verifies the actual captured bytes against the canonical
registry SHA-256. A warm hit requires the current full native file identity:
device, inode, size, mode, owner/group/link count, nanosecond mtime and ctime,
with a fresh no-follow walk of the supplied source ancestry. The caller supplies
only a Document ID. CORE resolves its approved canonical path and ownership.
No arbitrary file reader or raw pointer is exposed through the Viewer SDK.

Existing explicit `interactiveDocumentRead` is unchanged and hashes on every
call. Cached Read is a separate opt-in capability; non-Linux or an unavailable
native cache falls back to the explicit verified reader. Cache Status reports
`available 0` in that case. No cached scientific state is accepted after a
corruption error. Expected SHA is part of the native raw-byte key; canonical
metadata/Session/generation/revision remain checked by the Document owner.

Default native retention is8MiB/128 entries, LRU by use. Configure admits1..256MiB
and1..512 entries. Payload/key/identity/container bookkeeping is accounted;
`accounted_bytes` is not a measurement of total process RSS. Temporary bounded
capture/results and Tcl representations also occupy memory. One separately
bounded parsed registry (source up to4MiB) is reported as metadata_source_bytes;
its Tcl indexing overhead is not incorrectly counted as native payload bytes.
A source too large for retention is still checked. Inputs beyond the native64MiB
capture cap fall back to the existing explicit verified reader and its established
policy rather than rejecting an otherwise valid scientific Document.
Clear/eviction releases derived resources, never scientific Documents or History.
Session epoch transitions clear the working set. Status exposes hits, misses,
evictions, verified bytes and capacities, without canonical filesystem paths.

Metadata Batch reads one authoritative registry for at most4096 explicit IDs.
The owner reuses a validated parsed registry only when its full native identity
still matches. A cold parse uses the existing INI parser and checks the source
identity again before admitting its result. It cannot associate parsed B with
captured A after an intervening replacement. Unsupported/large/linked registry
sources keep the existing uncached reader. No second canonical registry or
persistent file format is introduced.

The existing NativeDocument sourceCapture operation retains its4MiB contract.
The additive native code is part of that same interpreter-owned library and
reuses its descriptor/ancestry checks; no new worker, thread or History engine.
The private `NativeDocument::snapshotCache` filesystem primitive is intentionally
not an admitted arbitrary-file SDK bridge.

`validation/dev111_p023_exp01/cache_contract.tcl` checks public warm reads, UTF-8,
same-size corruption with restored nanosecond mtime, explicit Read rejection,
recovery, revision/metadata visibility, eviction, Session ID reuse and disposal.
These are API contracts, not real-GUI acceptance or proof of overall speedup.
