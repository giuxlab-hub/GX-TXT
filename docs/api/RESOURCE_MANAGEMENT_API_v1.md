# Framework Resource Management API v1

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in dev093. This CORE authority accounts for reclaimable resources
across the framework. Session and job identifiers are reporting dimensions;
neither owns this registry. It does not replace Dataset Publication, managed
document resources, native rendering caches or their recovery contracts.

## Host interfaces

Python hosts import `ResourceManager` from `core/python/gxtxt_resource_manager.py`.
Tcl hosts use the following additive API; options are Tcl dictionaries.

| Python method | Tcl host command | Result |
| --- | --- | --- |
| `allocate(subsystem, **options)` | `resourceManagementAllocate subsystem ?options?` | resource record including `id`, `path` |
| `observe(path, subsystem, **options)` | `resourceManagementObserve path subsystem ?options?` | inspection-only record |
| `release(id, state, retention_seconds)` | `resourceManagementRelease id ?state? ?retention?` | revised record |
| `inventory(rescan=False)` | `resourceManagementInventory ?rescan?` | records and category/subsystem summary |
| `reconcile()` | `resourceManagementCall reconcile` | owner reconciliation and bounded rescan |
| `cleanup(ids)` | `resourceManagementCleanup idList` | per-resource audit results |
| `policy(**changes)` | `resourceManagementPolicy ?options?` | persistent storage policy |

This is an internal host authority, not an arbitrary-path Script Bridge method.
Trusted adapters allocate paths and give scripts only the already authorized
transport capability. `observe` never grants deletion rights to a supplied path.

`allocate` options include `kind` (`directory` or `file`), safe file `suffix`,
`category`, `job_id`, `session`, `dataset_id`, `lifetime`, `owner_pid`,
`retention_seconds`, and `expected_bytes`. The allocation creates a private
directory; a file allocation also creates an empty `data<suffix>`. Owners may
stream files inside a directory allocation and remove them during normal
operation. A context allocation avoids one registry call per binary chunk.

```python
manager = ResourceManager()
resource = manager.allocate("script_bridge", job_id=job_id,
                            expected_bytes=estimated_temporary_bytes)
try:
    # Only CORE-chosen paths under resource['path'] enter the typed channel.
    execute_with_private_workspace(resource["path"])
finally:
    manager.release(resource["id"])
    manager.cleanup([resource["id"]])
    manager.close()
```

`release` requires the living owner, or a verified dead/replaced owner identity.
It is an explicit assertion that no process will continue using the allocation.
The caller must first stop/reap its child workers; releasing while a child still
writes violates the producer contract. GUI cleanup cannot release active resources.
After a crash, PID, Linux process start time and boot ID prevent PID reuse from
being mistaken for continued ownership. Unknown liveness remains protected.

Tcl command wrappers pass their Tcl PID as owner, not the short-lived helper PID.
`resourceManagementAsync operation argumentList callback` invokes the same API
in an independent local helper and delivers `(code, result)` through a fileevent.
Configuration uses this path for scans. Tcl response dictionaries are data and
are never evaluated as scripts.

## Persistence, budgets and retention

The GUI uses `<user-configuration-directory>/resource-management`; allocation
storage starts under `<configured-temp-directory>/resources-v1`. Python-only
default is `$XDG_STATE_HOME/gxtxt_pipeline/resources` (standard home fallback).
CORE passes `GXTXT_RESOURCE_ROOT` and `GXTXT_RESOURCE_STORAGE` to workers so
every process shares one framework authority. Existing registries retain their
recorded allocation directory when a preference changes; old resources cannot
be accidentally reinterpreted against a new root.

SQLite transactions serialize admission, release and cleanup across real
processes. FULL synchronization protects the registry; WAL permits readers.
Every cleanup result records resource ID, category, exact path, bytes, time and
result in the registry audit table. No automatic cleanup or server-wide sweep
runs on startup, reconciliation, refresh or release.

Default admission budget is 10 GiB of known managed occupancy/reservations;
`expected_bytes` reserves budget before computation. A rescan updates actual
occupancy. This is conservative admission/back-pressure, not a kernel disk quota:
producers must provide realistic estimates and the Job Supervisor separately
enforces job policy. Protected scientific payloads do not consume a temporary
allocation reservation. Setting `max_bytes=0` explicitly disables that budget.

Default retained-diagnostic lifetime is seven days, configurable as
`retention_seconds`. Existing resources keep their explicit retention. Released
cache with zero retention is retained indefinitely, preserving warm caches.
A crashed diagnostic/cache allocation retains its category; crash does not
convert it into immediately removable scratch. Ordinary dead-owner temporary
allocations become `verified_orphan`. Expired resources become eligible for
explicit selected cleanup; expiration itself never deletes files.

## Resource classes and existing owners

| Resource | Existing authority | Accounting / cleanup |
| --- | --- | --- |
| Job transport buffers and context workspace | Script Bridge / ScientificTransport | managed allocation, active lease, owner release |
| Job logs and source snapshots | Job Supervisor provenance | protected observation, or explicitly retained diagnostic allocation |
| HDF5 `.partial`, backup and journal | Dataset Publication transaction | inspection only; transaction recovery decides cleanup |
| Canonical Dataset payloads | Dataset Registry / Publication | protected observation |
| Managed document blobs, history and retired owners | Interactive Document Resource API | protected; existing reference-aware collector only |
| Native3D mesh/repeat/scientific caches | native hash/schema-checked cache backend | reusable observation; never purged by job cleanup |
| Native3D PNG frames, consultation and Dataset previews | viewer lifecycle | live path observation; existing close/dispose cleans |
| Native2D retained scene and raster photo cache | Native2D scene / canvas lifecycle | in-memory owner authority; not disk cleanup targets |
| Dataset materializations | source/schema/hash-validated storage policy | reusable observation; no generic recursive deletion |
| Analysis render caches and outputs | Render Cache API / module authority | protected aggregate; no MAT-extension cleanup heuristic |
| Historical unregistered files in configured storage | unknown legacy owner | conservative inspection, never eligible |

Explicit Configuration rescan inspects known native and current Session owner
locations and current consultation-preview paths. Sessions previously reported
by jobs remain represented independently of whichever Session is now selected.
It does not enumerate every user Session, crawl `/tmp`, or infer ownership from
an extension, age or naming pattern. Other subsystems can add exact observations.
In-memory native graphics retain their own budgets and disposal methods; the
Configuration table reports measured disk resources, not invented native RAM.

## Filesystem safety and accounting limits

Only manager-generated allocation directories can be removed. Cleanup checks
the recorded directory device/inode under a locked registry transaction,
revalidates the owner lease and retention, and uses directory descriptors with
`O_NOFOLLOW`. Symlinks, hard-linked regular files, special objects and filesystem
boundary crossings refuse cleanup. Root components cannot be symlinks, and
authority/storage roots must be owned and not group/world writable.

Scans are bounded at 100,000 entries per resource; an incomplete or unsafe scan
blocks removal and displays its reason. Recursive scans happen only on explicit
rescan, observation or selected cleanup. Ordinary Refresh uses cached byte
counts and checks liveness. Overlapping inspection records are counted once in
summary totals; each row retains its own inclusive byte count. Files changing
during a scan make that measurement provisional until a subsequent rescan.

The registry is not recovery authority for scientific publication. In particular,
`metadata/.dataset_transactions`, its lock inode and transaction backups are
protected even when the original PID is dead. Publication recovery must finish
or roll back these transactions through its own cross-process lock.

## Configuration

The **Cache & Temporary Storage** tab is inside existing Configuration. It shows
known occupancy, category totals, recoverable bytes, subsystem, job, Session,
age, retention and cleanup decision. Refresh reads known accounting; Refresh /
rescan measures known paths in a separate helper so Tk stays responsive. Select
eligible rows and use **Clean eligible selection**; active or unknown selections
are refused, with the actual deletion checks repeated in CORE. Budget and default
diagnostic retention have their own explicit Save storage policy action.

## Portability and validation

The current filesystem/process backend targets local Debian. Windows adaptation
must preserve the common authority and use native process creation identity and
safe filesystem primitives; absence of `/proc` must never imply a dead owner.
No Windows or remote execution adapter is implemented here. The future local
supervisor/tray contract remains with the Job API and its platform backend.

`validation/async_dev093_resources/test_resources.py FRAMEWORK NEW_OUTPUT`
tests live leases, a real killed worker, process identity, independent concurrent
cleanup, symlink/hardlink/inode safety, scientific/recovery preservation, warm
cache preservation, diagnostic retention, admission and Tcl/async round trips.
Root integration supplies the real Debian Configuration GUI acceptance.
