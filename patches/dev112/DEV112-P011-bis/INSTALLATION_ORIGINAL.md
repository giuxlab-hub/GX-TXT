# P011-bis atomic source installer

This package changes source only. It neither starts GX-TXT nor changes services,
launchers, active-release selection or user preferences. Owner authorization for
activation remains separate. Development packages are not release acceptance.

## Before applying

Use the existing installation owner and a stopped, ordinary directory target.
Keep every process using that target stopped, and prevent concurrent launch for
the entire transaction and cleanup. `--stopped-target` explicitly acknowledges
that operational boundary. The process scan detects observed usage and records
unavailable process maps; it is not a universal launch lock. The unchanged P011
baseline cannot enforce the new startup guard before source cutover.

The target must match every byte, size and file permission in the exact accepted
P011 inventory. Customized source is refused. Unmanaged regular files and maximal
wholly unmanaged directory subtrees are preserved, including nested Session
roots. Source-managed parent directory identities can change; do not put a
Session root in a directory mixed with release-owned source files. Such a mixed
layout is outside the directory-identity guarantee. An introduced source path
must not collide with unmanaged data or an existing unmanaged ancestor.

Linux `renameat2(RENAME_EXCHANGE)` and one filesystem for the target, its parent
and contents are required. Mountpoints, bind aliases, symlinks, hardlinked target
files, special files and mixed ownership are refused. The installer must belong
to the target group to preserve groups on new staging directories and files.
Source-managed directories need owner read/write/search access; unreadable data
is refused. Read-only wholly unmanaged subdirectories remain read-only and keep
their original inodes. Extended attributes/ACLs on managed source files or
managed directories are outside this package's metadata contract and are refused.
Unmanaged files retain their original inodes and attributes; unmanaged directory
subtrees are moved intact. Managed directory timestamps and inode identities are
not part of the source inventory. No original data file is chmodded or rewritten.
Metadata is bounded to 200,000 entries and 32 MiB per JSON record.

Verify the final delivery's SHA-256 checksums, then use the complete matching
package. Do not copy only apply.py or edit manifest/preimage/payload files.

Run the following commands from the complete atomic package directory. In the
final delivery this is `patch/atomic/`; in an extracted standalone atomic
package it is the directory containing `apply.py`, `MANIFEST.json` and `payload/`.

```sh
cd /absolute/path/to/delivery/patch/atomic
```

```sh
python3 apply.py check /absolute/path/to/framework
python3 apply.py apply /absolute/path/to/framework --stopped-target
python3 apply.py status /absolute/path/to/framework
```

Check verifies the exact baseline and probes atomic exchange in new empty
external directories. It does not change target files. Apply verifies package,
source, modes and ownership again, stages with unchanged-file hardlinks and new
payload inodes, and atomically exchanges the source root. It then restores
original unmanaged directory identities before reporting success. This is an
atomic **source cutover followed by journaled identity recovery**, not a claim
that every filesystem entry changes in one syscall. A repeated successful apply
with its matching external receipt is an unchanged no-op.

## Receipts and interruption recovery

The deterministic external directory is a sibling of the target:
`.TARGET_NAME.gxtxt-source-transactions/`. It contains mode-0600 staging intents,
transaction journals and per-transaction receipts, a latest-result record and
an exclusive installer lock. Its directory mode is 0700. Keep it with the
installation; the corrected CORE derives this location itself before any
configuration, Session, Resource or catalog initialization. A pending marker,
including malformed content, refuses corrected-source startup without evaluating
journal text.

A durable staging intent records canonical paths, matching package, parent/root/
stage identities and original entries **before the first hardlink**. Before
cutover, interruption recovery removes only a proven disposable clone and leaves
the exact original source/data in place. Once cutover begins, the journal binds
both source images and every original/cloned unmanaged directory identity.
Recovery infers completed exchanges from device/inode pairs, including a kill
between syscall and journal update. Foreign identities or changed content fail
closed and retain both trees. Do not remove pending.json, staging intents or a
retired tree manually.

```sh
python3 apply.py recover /absolute/path/to/framework --stopped-target
```

Use the **exact package that started the transaction**. A pre-cutover apply
recovery cancels that attempt; run a fresh apply afterward. Post-cutover recovery
finishes the admitted source image and original directory identity phase.
Rollback recovery completes the baseline stage before exposing the unguarded
baseline. A crash after receipt/marker completion can leave only a disposable
retired tree; the same recover command completes its proven cleanup. Success is
reported only after full source/mode and unmanaged-identity readback and a durable
external receipt. An I/O or durability failure leaves an explicit refusal or
pending recovery state, never a success assertion.

## Exact source rollback

Stop the target and prevent concurrent launch again:

```sh
python3 apply.py rollback /absolute/path/to/framework --stopped-target
```

Rollback requires the successful matching external receipt and exact admitted
postimage. It refuses modified release-owned files or foreign installation
identity. It stages from the **current** target, restores only owned baseline
preimages and removes only unchanged introduced source files. New unmanaged data
created after apply survives. Original unmanaged directory identities move into
the baseline stage while the corrected startup guard still protects the target;
only then is the complete baseline source exposed. An unchanged repeat rollback
is a no-op. No engine rebuild, scientific conversion or user-data rollback occurs.

The `--test-faults --fault-point NAME` options deliberately SIGKILL only explicitly
selected allocated scratch targets. They exist for independent interruption
validation and are not deployment steps or an admission bypass.
