# Workbench Recovery API v1

CORE host API `WORKBENCH_RECOVERY_API_v1`, provider `workbench_recovery`.
Recovery lifecycle, filesystem journal access and modal choices are host-only;
extension scripts consume scientific geometry APIs and return owned results.

`workbenchRecoveryBegin document_id` opens the recovery lifecycle.
`workbenchRecoveryCheckpoint document_id ?receipt?` records a committed semantic
Interactive Document snapshot and a recent operation receipt.
`workbenchRecoveryInspect document_id` is read-only and returns absent, clean,
unclean or corrupt status. It cannot write the Session.
`workbenchRecoveryResolve document_id recover|saved` explicitly restores the
chosen snapshot through the normal Interactive Document Update API.
`workbenchRecoveryMarkSaved document_id` / `workbenchRecoveryClose document_id`
compact a valid journal and mark the current committed state clean. Explicit
Save can create an absent journal from the current valid Document. A corrupt
existing journal returns `status corrupt` with its reason and remains unchanged;
callers must inspect that status as well as exceptions.
`workbenchRecoveryForget document_id` explicitly removes only the recovery journal.

The inert journal retains complete UTF-8 semantic snapshots. The existing raw
`GXTXT_RECOVERY_V1` encoding remains readable. If the full envelope would exceed
the stored-byte budget, CORE writes a lossless `GXTXT_RECOVERY_ZLIB_V1` body;
it does not omit saved/latest snapshots or shorten their History. The envelope
SHA-256 checks the stored body before decoding. Each saved/latest snapshot's
SHA-256 separately checks its exact uncompressed UTF-8 payload. The same
Document/provider generation guards and same-directory atomic replacement
apply to both encodings. The journal has a 16 MiB stored-file budget and at most
128 recent semantic receipts. If the compressed envelope still exceeds the
budget, the write fails visibly and preserves the previous checkpoint. It
retains the last saved snapshot separately from the latest consistent checkpoint,
including provider/Document generation, revision, format, payload fingerprint,
source identities, geometry references and operation provenance. Native geometry
remains in owned content-addressed resources. Resource collection includes valid
saved/checkpoint references without duplicating large coordinate or mesh blobs.

Curve Workbench and 3D Workbench offer a real recovery dialog after unclean exit:
**Recover**, **Open last saved state** and inspection details. Cancel leaves the
saved Session untouched. A recovery choice does not advance the saved snapshot;
explicit Save or normal close does. A corrupt journal yields a visible diagnostic
and allows ordinary Document open/save/close. It is retained for inspection;
normal save does not claim that an invalid journal was repaired. A journal-write
failure after a scientific commit reports that the action committed and leaves
the previous consistent checkpoint intact. Failed scientific/checkpoint staging
does not advance the journal.

The shared Session Save hook marks existing valid Workbench journals clean.
Workbench controllers checkpoint semantic geometry/Undo/Redo boundaries rather
than pointer-movement events. Journals are recovery aids and do not replace the
normal Session save workflow.
