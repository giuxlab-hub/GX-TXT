# Observable Dataset catalog extension

Metadata commits include a persisted revision independent of timestamp resolution
and a lightweight display-label field. Same-length edits in the same second remain
observable. Metadata/schema write authorities coalesce their nested Registry saves,
so subscribers see final file contents after success and receive no provisional
notification if the transaction rolls back. Registered Script Workspace execution
also reconciles committed Bridge-process Registry changes on completion.

SPDX-License-Identifier: GPL-3.0-or-later

This is an additive capability of `CANONICAL_DATASET_API_v2`. It observes logical
Session Dataset identities and schemas without reading scientific payloads.
Notifications are advisory; snapshots and explicit queries remain authoritative.

| Tcl operation | Contract |
| --- | --- |
| `datasetCatalogRevision(?session?)` | Current process-monotonic integer revision; explicit query reconciles committed registry changes from other processes. |
| `datasetCatalogSnapshot(?session?)` | Session token, revision, ordered stable Dataset IDs, lightweight contract/storage/label/fingerprint summaries. |
| `datasetCatalogChangedSince(revision, ?session?)` | Change flag, revision, bounded change receipts, and `reset_required` if the retained history is insufficient or a foreign revision is supplied. |
| `datasetCatalogSubscribe(callback, ?session?)` | In-process subscription token. Callback receives a receipt after commit. |
| `datasetCatalogUnsubscribe(token)` | Remove subscription. |

Receipts contain revisions before/after, Session token, change kind, added,
deleted, and changed IDs, plus rename pairs when the rename authority supplies
them. History retains the last 128 receipts. Snapshot queries never choose a
new scientific input. Public publication, file publication, acquisition, delete,
rename, and registry persistence authorities coalesce nested writes into one
notification after their successful return. Failed transactions emit no receipt.
Subscriber errors cannot roll back a committed Dataset, and recursive read-only
refreshes do not cause notification loops. Session transitions invalidate the
catalog identity and are reported to existing subscribers.

`datasetSelectorAttach(widget, choice_callback, ?changed_callback?)` installs a
shared Tk combobox `-postcommand` revision check. It refreshes choices only after
a revision change, preserves the current input, and keeps a missing historical
choice visible rather than choosing another Dataset. Existing label/contract
filter callbacks remain authoritative. The adapter has no polling timer.
Detach happens on widget destruction. GUI adapters and in-process callbacks are
host-only; script discovery/snapshot/changed-since queries are safe.

The revision is a process-local observation sequence, not a global persistent
Session edit counter. Clients must retain and compare the Session token as well
as the revision, and obtain a fresh snapshot after `reset_required`.
