# GX-TXT dev085 — focused validation / technical report

Baseline: verified published, working dev084, archive SHA-256
`17b89d1a9a44bc32683b84ea553e7fa71550b83852fcae5a71e09ae12ae1c06c`.
Scope: direct Sessions Project Home and complete portable Project import/export.
No unrelated redesign, scientific-module changes or extensive regression campaign.

| Essential check | Result |
|---|---|
| Project Home navigation | PASS |
| Whole Project GUI export | PASS |
| GUI import into installation B | PASS |
| Reopen/save/restart imported Sessions | PASS |
| Identifier/provenance/scientific integrity | PASS |
| Failure handling and rollback | PASS |

Six essential checks PASS; no unresolved FAIL. User manual acceptance remains pending.
Real GUI uses unmodified plain tclsh entry, native Xorg keyboard/mouse, native file
choosers, save confirmation and completion/error dialogs in private installation A/B.
[The operator matrix](DEV085_OPERATOR_MATRIX.md) links reviewed screens, input journals and persistent receipts.
The imported Project contains two independent measured Sessions, notes, registered
Python scripts, canonical voltage CSVs and a Project calibration resource. Both
Sessions were opened, saved, closed and reopened; five source rows rendered normally.
Twenty Session payload files (except the necessarily relocated organizational/runtime
Manifest), all Project resources and fifteen complete module snapshots match ZIP bytes.

Implementation reuses public Session Portable export/validation/staging/dependency
services, existing Project membership and metadata, installation/origin APIs and the
existing journal. A transport-only container adds exact SHA-256 inventory, nested
reference/Dataset checks, Project resources and transitive module snapshots. Modules
are retained as inert resources; existing runtime diagnostics remain authoritative.
Source identifiers persist in origin.events across Save/restart; optional imported
link aliases are not the persistence authority. New local Project/Experiment IDs
and final Session paths are assigned without changing Session-scoped scientific IDs.
A new import reloads the registry under the existing journal writer lock and commits
one entire Project directory. Post-move failure restores registry/catalog preimages
and removes staged owned data. Repeated import/retransfer retains original lineage
and snapshots; unsafe roots, occupied archives and damaged packages are refused.

GUI changes are confined to one visible Sessions button, two Projects toolbar actions
and their existing browser projection. Existing selectors/Session navigation remain.
No new Tcl rename wrappers; all 101 installed module descriptors and their complete
provider trees, native libraries, generators and plugin inventories are byte-preserved.
Existing wrapper chains are retained; safe removal requires separately tracing their
complete consumers and is recorded as unfinished work, not part of this correction.

Development harness corrections are disclosed: a first API assertion incorrectly
expected Payload.status instead of the documented path/hash result; corrected and
rerun. An early coordinate batch queued clicks before dismissing the existing native
Save confirmation; those steps/screens are excluded and reopened/home journeys were
repeated with acknowledged dialogs. No application background errors were observed.

Publication gates archive/internal SHA256SUMS/tree/active/alias/restore parity and
historical releases, with a retained complete dev084 active backup and rollback.
Independent native tar/SHA256SUMS/diff receipts and installed GUI readback supplement
this immutable report after publication in the versioned handoff. The ordered Debian
framework archives/expanded sections stay paired; external plugins and Session
Generators remain unchanged. The real user's identity and data are not used by tests.

Contract and bounds: [Project Portable API v1](../api/PROJECT_PORTABLE_API_v1.md).
Export uses saved authoritative Session state. Missing/unresolved source resources
fail rather than silently producing an incomplete package. Runtime dependency code
is not auto-installed; Project transport is a host filesystem capability and does
not expose arbitrary paths/installation writes through the research Script Bridge.
The new authority catalog covers reviewed Project/transport owners; the remaining
framework-wide catalog is explicitly unfinished. SHA integrity is not authentication.
