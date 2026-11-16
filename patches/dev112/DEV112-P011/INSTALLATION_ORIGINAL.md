# P011 installation and rollback

All instructions are in English. P011 targets the exact deposited DEV112-P010
framework (version0.9.8.10-dev-112, patch010). It does not replay older cumulative
patch routes. Preserve the original installation, external apply receipt and
independently retained receipt SHA. Existing scientific data and user Sessions
are never patch payload.

Use the accompanying `apply.py`, overlay ZIP and adjacent SHA256 sidecar. Start
with its default read-only check:

```sh
python3 apply.py /path/to/P010-framework DEV112-P011-overlay.zip --check
```

The installer verifies complete source bytes/modes, exact baseline/postimage,
archive/member/manifest identities and safe ordinary paths before writing. It
refuses modified, mixed or incomplete source trees. Preserve unpublished work;
do not discard changes to make a check pass. Make a separate verified source
copy if the existing tree is customized.

Close the application and stop activity against the target before installation.
The flags acknowledge authorization/quiescence; they do not discover or stop
processes. No launcher, mount, service or active release is switched:

```sh
python3 apply.py /path/to/P010-framework DEV112-P011-overlay.zip \
  --apply --route post-p010 --owner-authorized --stopped \
  --receipt /separate/existing-directory/P011-apply-receipt.json
```

The external receipt path must be new and outside the framework. Retain its exact
SHA256 from successful stdout independently. Reapplication to the exact postimage
is a coherent no-op. A failed/interrupted receipt is not a successful install and
cannot authorize rollback; preserve the files/journal/stdout for explicit recovery
from retained source/preimages rather than rerunning against a mixed tree.

Rollback restores the exact P010 source through archive-bound preimages and
removes only admitted P011 additions. It requires the successful external receipt,
its independently retained SHA and the original target/installation identity:

```sh
python3 apply.py /path/to/P010-framework DEV112-P011-overlay.zip \
  --rollback --route post-p010 --owner-authorized --stopped \
  --receipt /separate/existing-directory/P011-apply-receipt.json \
  --receipt-sha256 EXACT_SHA_FROM_SUCCESSFUL_APPLY
```

Unknown changes after installation are preserved by refusal. Rollback does not
remove user Sessions, profiles or unrelated files. Packaging/installability and
actual tests are qualified only by the exact delivery acceptance records.

A complete source archive supports a separate new source directory. P011 also
includes the optional MCP adapter0.2.0 Debian package, its exact source and pinned
SDK dependencies. See `integrations/mcp/README.md` for independent package upgrade,
protected client configuration and compatibility diagnostics. Installing that
package does not start its service or grant Session access. Preserve existing
MCP configuration and credentials; framework patch labels do not gate admission.

Curve Viewer version1 Workspaces remain readable without mutation. Conversion
creates a separate Plot Workspace and refuses unsupported source transforms.
Curve Fitter retains scientific History and journals presentation separately.
Neither installer migrates Sessions. Existing ORION/SII delivery stays frozen.

The commands below are release procedures, not authorization to install or
activate P011. Owner authorization is required before using --apply.
OWNER_HANDOFF.md explains where the exact independent release decisions are recorded.

Preserve the full permissions recorded in the source archive and
`SOURCE_FILES.json`, including existing P010 files with mode `0664`. With GNU
tar, extract into a new empty directory using `--same-permissions`:

```sh
mkdir /path/to/new-empty-source
tar --extract --gzip --same-permissions \
  --file DEV112-P011-framework-source.tar.gz \
  --directory /path/to/new-empty-source
```

Verify the archive checksum first and compare extracted file hashes, sizes and
modes with `SOURCE_FILES.json`. Python's secure `tarfile` data filter can remove
group-write permission: a controlled extractor must restore each verified
regular member's declared mode before checking the full inventory. A Git
checkout records executable bits only and does not establish these full modes.

P011 ships matching Native2D and Native3D libraries with their source/build
receipts. Keep these pairs together and restart the application before testing
the new contracts. Native2D uses the existing Tcl/Tk8.6, Cairo and X11 runtime
libraries; its public C/Tcl exports are unchanged. To reproduce its source build
in a new private directory with the normal development headers available:

```sh
cmake -S core/native2d -B /private/new-native2d-build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build /private/new-native2d-build --target gx2dtcl -j2
```

Build only in a disposable output directory. Review dependency/source hashes
and the exact independent runtime validation before replacing any library.
The delivered source receipt documents the private Cairo header package used
in the P011 build; no system development package was installed by this work.

History acceptance and durable persistence are separate. If a journal write
fails, inspect the exact error and retain unsaved scientific work before closing.
Resolve the underlying storage error and reopen the saved Workspace to recover
its last durable state. The controlled P011 file-size failure test recovered the
valid durable prefix, exact scientific state and Preview through the original
owner; only the failed pending tab change was not persisted. This is a bounded
recovery result, not a promise that Clear, Save or arbitrary export can bypass
a failed journal. Original confirmations and ownership guards remain active.
