# Object Origin API v1 — Project and Session/Experiment (dev083)

SPDX-License-Identifier: GPL-3.0-or-later

Read-only Tcl: `projectOriginRead projectId`, `sessionOriginRead ?session?`.
Script Bridge discovery: `OBJECT_ORIGIN_API_v1` operations `project(project_id)`
and `session()` (current Session). Python/Octave return structured origin, parent
and event records, including recursively decoded parent origin snapshots (inspection
depth limit 64). No setter, issuance or rotation operation is exposed.

Origin v1 is additive metadata in Project `origin` and Session `[origin] definition`:

| Field | Meaning |
| --- | --- |
| version | 1 |
| creator_installation | Installation UUID at actual creation, or literal `unknown` |
| created_at | Original creation time, blank when unknown |
| creation_kind | `project`, `session_experiment`, `duplicate`, or `unknown` |
| parent | Source object kind, Experiment ID, creator and declared origin snapshot |
| events | Ordered local import records: kind, installation_id, at, source_experiment_id, source_project_id |

CORE creation uses the dev082 `INSTALLATION_IDENTITY_API_v1` authority, never a
second serial. New Project persistence, normal makeSession/New Session, clean
Duplicate Experiment and Portable import are the actual event points. Rename,
association, Default reassignment and installation rotation preserve creator.
Duplicate has a new current-installation creator and a source parent with its origin
snapshot, while its scientific Datasets/Workspaces/graphs/observations remain empty.
Import retains the declared creator, appends a receiving event and keeps the original
organizational IDs in both the import event and project_link imported-ID fields.
Export adds `carrier_installation` and UTC export timestamp to the Portable package;
the Session origin and creator remain unchanged. Re-export from another installation
therefore distinguishes original creator, receiving/import events and current carrier.

Missing legacy origin returns `unknown`; encounter/open/rename never claims a local
creator retroactively. Unknown imported origin stays unknown with a receiving event.
Foreign origin is reported lineage, not certified authentication. Integrity hashes
verify content only. Invalid declared Session origin returns an explicit error.

Scientific object provenance uses the existing installation authority and the corresponding persistence owners. Project/Session identity remains independent from Dataset, Document and managed resource identities.

Persisted origin wins over configuration-only state on Save. Loading another Manifest
for configuration does not adopt its Project/Experiment IDs or creator. Original Format1
Sessions retain unknown creator until independent new creation/import events occur.

## Dev088 scientific owners

The former scientific-origin gap above is now extended at actual persistence points.
Read-only `documentOriginRead documentId`, `datasetOriginRead datasetId ?session?`,
and `resourceOriginRead resource` reuse Object Origin v1. Script Bridge exposes
`document(document_id)`, `dataset(dataset_id)`, `resource(resource)` through the same
`object_origin` provider; there is no new serial generator or normal module setter.

New Interactive Documents record creator at creation; updates retain it. Old records
read as unknown. Dataset numerical/file publication records creation of the **new
Dataset container**, source Dataset origins and Session lineage; this does not claim
the physical/raw source was created locally. Existing Dataset replacement retains
its original creator. Caller-supplied origin metadata on a new publication is retained.
Managed writers record generated-resource creation with owner Document/revision.
Raw file imports default to unknown creator with a receiving-installation event;
existing supplied resource origin is preserved. Native3D exported geometry explicitly
records derived-resource creation. Planar payloads add immutable source fingerprints,
plane/unit/operation, source revision and exact/approximate policy. Accepted results
have their own derived origin and parent source lineage.

Session Portable retains Dataset, Document and resource metadata byte-for-byte;
its established Session import event identifies the receiving installation without
rewriting each child's original creator. Session origin supplies the receiving context.
Legacy scientific objects are not retroactively attributed. Existing installation
persistence, confirmed rotation/history/recovery and CORE-only mutation are unchanged.
Verification of this contract covers two distinct isolated installations,
scientific publication, portable transfer and unknown-source preservation.
