# Dataset Group API v1

`::GX::datasetGroupApiInfo` describes the public storage/lifecycle owner. A Group is a
Session-local aggregate of existing canonical Dataset IDs, with ordered roles,
one Namespace and source provenance. It adds no scientific payload and is
independent of Variable Schema `group_id` and Library graph relationships.

All commands use the existing Dataset authority lock and durable recovery
journal. `metadata/dataset_groups.tcldict` is a bounded inert UTF-8 dictionary,
never sourced. Existing Sessions without this file have no Groups.

| Host operation | Behavior |
| --- | --- |
| `datasetGroupList session` | Ordered stored descriptors. |
| `datasetGroupGet session groupId` | Descriptor plus `status=COMPLETE|DEGRADED` and exact member issues. |
| `datasetGroupForDataset session datasetId` | Group ID or empty. One Dataset belongs to at most one Group. |
| `datasetGroupCreate session definition` | Validate all actual registered members and persist one new Group. |
| `datasetGroupMove session groupId namespace expectedRevision` | Move every member through the existing Namespace owner and advance Group revision atomically. |
| `datasetGroupDetach session groupId datasetId expectedRevision` | Remove only membership; preserve the Dataset. Last detach removes the wrapper. |
| `datasetGroupUngroup session groupId expectedRevision` | Remove wrapper only; preserve every Dataset. |

Creation requires `group_id`, `display_name`, qualified `group_contract`,
`primary_dataset_id` and `members`. Each member declares `dataset_id`, qualified
`role` and boolean `required`. CORE pins its actual contract, canonical SHA and
source-module/RAW SHA. IDs/roles/contracts are extensible declarations, without
domain-specific CORE vocabulary. All members must exist in one Namespace, the
primary must be a member, and duplicates/collisions are refused. Bounds: 1000
Groups, 1000 members per Group, 1 MiB total descriptor, 512-character labels.

The same descriptor retains creation time and the last128 inert history events
(create, move, detach, member rename and import), each with timestamp, revision
and bounded identity/Namespace details. History is diagnostic provenance, never
executable replay or scientific data. Group ZIP preserves it and original creation
time; import appends an explicit new event while retaining source revision/origin.
Old descriptors/packages without history remain compatible. The existing Dataset
authority journal rolls history back with membership and Namespace changes.

Move/detach/ungroup require the exact integer revision returned by Get. An error
rolls back all enlisted sidecars and the Group descriptor. Legacy single-member
`datasetNamespaceSet` refuses grouped members: explicitly move the whole Group
or detach first. Individual deletion similarly requires explicit detach/ungroup.
Normal Dataset rename retains membership/primary/source references and increments
Group revision inside its existing transaction. No payload SHA changes.

In the existing Dataset Browser, dragging a Group row onto a visible Namespace
asks for confirmation of the whole Group move. The gesture pins its Session
lifetime and Group revision at press; the normal `datasetGroupMove` authority
performs the move after review. Escape, an outside drop, unmapping, stale state
or a rejected review performs no move. Disclosure clicks and individual Dataset
activation retain their existing behavior; the older single-Dataset Namespace
Manager gesture is unchanged.

Acquisition handlers may return optional `dataset_group` with this creation
definition. Membership must exactly equal the handler's actual returned Dataset
IDs. The existing Acquisition transaction creates the Group after member
registration; any failure aborts the entire import. Handlers without this key
retain their existing behavior. A read-only Library relation does not create a
Group or canonical Dataset.

`datasetCatalogSnapshot` additively includes `dataset_groups`. Group-only changes
also notify existing subscribers; highlight alone does not activate members.
Source changes/missing members are reported as degraded; no guessed repair or
implicit retarget is performed. These host mutation commands are not Script
Bridge or restricted C++ filesystem capabilities.

The existing Dataset Browser measures its bounded recursive identity/role text
through the shared UI Field inspection-column owner. Horizontal scrolling reaches
the full measured text at the actual font instead of a fixed420pixel extent;
the nominal navigator width stays independent from that scrollable extent. The
existing Current Namespace/Active Dataset button wraps its complete caption
through the native button-label style. Main and Dataset-page notebooks use the
existing public compact selector when captions cannot fit, preserving notebook
paths, page identities, callbacks and normal tabs when sufficient room returns.
These are presentation changes; Group membership, activation, source bytes,
Namespace and scientific/portable transaction owners remain unchanged.

P030 additively exposes producer-scoped review/create and optional atomic batch
grouping through [Dataset Group Producer API v1](DATASET_GROUP_PRODUCER_API_v1.md).
These admitted facades serve all legitimate registered producer categories;
legacy host/admin mutation commands retain their authority restrictions.
