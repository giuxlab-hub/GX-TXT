# MANAGED_RESOURCE_API_v1 — SB-014 boundary

This thin transport reuses the existing Interactive Document Resource writer,
reader, hash, Session and owner-generation checks. It does not create another
destination store. Python/Octave scripts address Document IDs and resource
receipts; no operation accepts a host path, callback, executable content or raw
Native pointer.

| Operation | Positional arguments | Result |
|---|---|---|
| write | document_id, metadata, bytes_base64 | immutable managed resource receipt |
| read | resource, start_byte, byte_count | bounded base64 data |
| info | resource | fully verified resource receipt |

Write decodes strict base64 with a 4 MiB bound and streams to the existing writer
in at most 1 MiB chunks. Reads use the existing 1 MiB bound and exact ranges.
Resource identity includes Document owner/generation, SHA-256, size and format
metadata. Missing/corrupt/stale-generation resources reject. Metadata contains
data; it cannot select a filesystem destination.

Canvas previews and workspace packages return these same managed receipts.
Existing larger scientific streaming services remain authoritative. Arbitrary
filesystem exporters and user-selected file dialogs remain host-only. This
cycle establishes the minimum safe managed destination policy; future detached
exporters must reuse it rather than bypass it.
