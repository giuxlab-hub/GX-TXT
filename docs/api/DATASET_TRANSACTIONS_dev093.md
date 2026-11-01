# Local Dataset publication transactions (dev093)

SPDX-License-Identifier: GPL-3.0-or-later

The canonical Dataset Registry, Metadata, Namespace and Publication APIs retain
ownership of their existing resources. The Catalog transaction now uses one
reentrant per-Session OS lock. Linux `flock` releases when the lock helper exits,
including process death; stale PID files are never treated as locks. This targets
local Linux filesystems with durable rename and fsync. A future native Windows
adapter must implement equivalent local locking/durability; remote execution and
a Windows implementation are outside this release.

Publication v2 prepare records `operation=creating|replacing` and an opaque full
revision expectation. `replace_owned=true` authorizes replacement if the ID already
exists; it does not prevent first creation. Prepare and commit both enforce producer,
publication API, immutable protection, assigned module namespace and existing target.
A user move, metadata edit, schema change, ownership change, competing create or
replacement after prepare invalidates the commit. Numerical generation, streaming,
provider final validation and whole-file hashing run outside the commit lock.

`::GX::datasetRevisionToken datasetId ?session?` reads under the same authority and
returns an opaque equality token containing the canonical descriptor and metadata
SHA-256. Consumers must not parse it or use a display label as scientific identity.
It changes for metadata/schema/namespace changes even when payload bytes do not.

The existing Catalog mutation wrappers remain the observer boundary. Public
metadata read-modify-write, private metadata/namespace placement, legacy publication
batch, file publication, schema mutation, import, delete and rename enter the same
reentrant authority. Bare legacy register/save callers use their last-read record
baseline: only changed records are merged into a fresh committed registry, and a
conflicting change to the same record rejects the save. Unrelated concurrent records
are preserved. Observer callbacks run after durable commit, without the lock held.

Before an authoritative resource changes, CORE records its exact path and durable
preimage (or prior absence) below `metadata/.dataset_transactions/txn-UUID/`.
Publication enlists the payload, Dataset Registry and metadata sidecar together.
Successful completion syncs every enlisted file and containing directory, then
atomically persists and syncs the committed journal marker. Before that marker,
restart rolls back; after it, restart only finishes cleanup. Cleanup failure cannot
convert a durable committed transaction into rollback. No new scientific registry
or parallel namespace is introduced.

`::GX::datasetPublicationRecover session` takes the same lock, reconciles pending
journals, reloads the registry and returns `{session ... recovered 1 dataset_ids ...}`.
It is idempotent and is used on ordinary canonical load and by job cancellation or
supervisor restart. A failure to recover is an error, never a successful publication.

Streaming writers also record exact staging paths and the owner/worker process
identities (PID, process start time and boot ID), plus the staging inode. Recovery
removes an abandoned `.partial` only after all recorded owners are dead and its
inode still matches. Active resources, changed/unknown inodes and other files are
retained. Staging and recovery records are protected recovery resources; the global
cache UI may account for them, but does not own deletion. Normal finalize/abort
release staging records. Legacy v1 continues to register producer-written module
output files; it cannot undo a producer's changes made before the registration call.

Validation `validation/async_dev093_publication/run.py FRAMEWORK NEW_OUTPUT` uses
independent OS processes and deterministic barriers for collisions, stale revisions
and legacy saver merging. It kills both Tcl and the lock helper at placement,
registry and metadata boundaries, then opens a new process for recovery. It covers
create/replace, ownership, namespace moves, immutable protection, HDF5 typed append
and exact 262144-value readback, file publication, abort, staging-owner death and
injected ENOSPC. The journal protects authoritative state on I/O failure; recovery
may require the underlying disk/permission problem to be resolved before reopening.

### Input revision tokens

`datasetRevisionToken datasetId ?session?` returns an opaque token of the persisted
canonical registry record and exact structured-metadata digest under the same
transaction lock. Lazy in-memory schema enrichment during reads does not change
this token. Committed schema/metadata/namespace changes do. Registry CAS baselines
are refreshed from the committed loader view, retaining pending local projections
without misclassifying them as an independent committed edit.
