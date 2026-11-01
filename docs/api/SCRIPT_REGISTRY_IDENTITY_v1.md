# Script Registry identity comparisons v1

This additive host interface belongs to the existing Script Registry / Script
Execution v1 owner. It creates no new Registry, source store, filesystem grant,
Session authority or public script execution permission.

`scriptRegistryIdentityApiInfo` and `scriptExecutionApiInfo.registry_identity`
describe the actual supported projections and guarded operations. A successful
Save/Update/ProjectSave/ProjectUpdate returns the exact committed metadata,
including these read-only fields; Describe/Read also compute them:

| Field | Meaning |
| --- | --- |
| `record_sha256` | SHA-256 of the complete authoritative `script.ini`, distinct from executable source/project SHA. |
| `owner_context` | Opaque comparison of scope, normalized configured Registry root and its device/inode identity. Stable across unrelated record edits and Session switches for the same User root. |

Read verifies that the record hash remains unchanged through source/project and
authoring-pointer checks, retrying boundedly if another writer published a new
record. These projections are not stored in `script.ini` or accepted as creation
metadata. They are comparisons, not capability tokens. Actual native Module,
foreground user action, window, source grant and opaque Session lifetime remain
separate authorization checks. An explicit host Session path retains its normal
meaning; a root context never grants access to a Session.

`scriptRegistryUpdate` and `scriptRegistryProjectUpdate` accept optional metadata
controls `expected_revision`, `expected_sha256`, `expected_record_sha256` and
`expected_owner_context`. Full-record/context pins must be exact lowercase
SHA-256 strings. They are checked inside the same existing kind-specific owner
locks as the source update; Project checks are repeated after acquiring its lock.
Controls are removed before writing metadata. Source SHA remains the ordinary
required positional argument. No controls means the existing API call remains
valid. Returned source/project descriptors refer to the committed revision,
instead of rereading and accidentally adopting a later writer's revision.

The full-record pin catches metadata-only changes and same-ID/source/revision
replacement with different record contents. Context comparison catches an
otherwise identical record in another configured User root or Session root.
The low-level writer also refuses a context change during preparation before
publication. This does not promise a distributed lock over arbitrary external
filesystem/Configuration/Session writers or protection against privileged
same-byte replacement. Native lifetime guards must still refuse stale contexts.

`scriptRegistryProjectExport reference destination ?session? ?expected?` accepts
the same expected fields in an optional final dictionary. It freezes the selected
Session and full record/context, obtains the existing Project/source-note writer
lock and rechecks identity before and after export. Only a complete verified ZIP
is renamed from its owned pending file to a new destination. Failure removes that
pending output and preserves any existing destination. Legacy calls remain valid;
they also pin the actual record selected at entry. Export does not revise source
or note metadata.

Delete, assignment and copy-with-notes corrections are separate
operations. Their stricter identity/transaction gates must not be inferred from
these Update capabilities; consumers must refuse when the required actual owner
operation is unavailable. Existing SourceNote associations and canonical Dataset
Groups keep their distinct owners and semantics.
