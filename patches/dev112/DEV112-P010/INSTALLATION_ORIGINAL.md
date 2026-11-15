# P010 installation and rollback

All instructions are in English. P010 targets the exact deposited DEV112-P009
framework (version0.9.8.10-dev-112, patch009). It does not replay older cumulative
patch routes. Preserve the original installation, external apply receipt and
independently retained receipt SHA. Existing scientific data and user Sessions
are never patch payload.

Use the accompanying `apply.py`, overlay ZIP and adjacent SHA256 sidecar. Start
with its default read-only check:

```sh
python3 apply.py /path/to/P009-framework DEV112-P010-overlay.zip --check
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
python3 apply.py /path/to/P009-framework DEV112-P010-overlay.zip \
  --apply --route post-p009 --owner-authorized --stopped \
  --receipt /separate/existing-directory/P010-apply-receipt.json
```

The external receipt path must be new and outside the framework. Retain its exact
SHA256 from successful stdout independently. Reapplication to the exact postimage
is a coherent no-op. A failed/interrupted receipt is not a successful install and
cannot authorize rollback; preserve the files/journal/stdout for explicit recovery
from retained source/preimages rather than rerunning against a mixed tree.

Rollback restores the exact P009 source through archive-bound preimages and
removes only admitted P010 additions. It requires the successful external receipt,
its independently retained SHA and the original target/installation identity:

```sh
python3 apply.py /path/to/P009-framework DEV112-P010-overlay.zip \
  --rollback --route post-p009 --owner-authorized --stopped \
  --receipt /separate/existing-directory/P010-apply-receipt.json \
  --receipt-sha256 EXACT_SHA_FROM_SUCCESSFUL_APPLY
```

Unknown changes after installation are preserved by refusal. Rollback does not
remove user Sessions, profiles or unrelated files. Packaging/installability and
actual tests are qualified only by the exact delivery acceptance records.

A complete source archive supports a separate new source directory. The DXF
export module also has an independently installable Plugin Manager package.
The synthetic reference generator is separate reproducible example material;
run it only with a new output root, following its README. New Mathematics models
use native provider2/version2; old provider1/version1 records remain readable.
No module-availability/default policy is silently changed.

Preserve the full permissions recorded in the source archive and
`SOURCE_FILES.json`, including existing P009 files with mode `0664`. With GNU
tar, extract into a new empty directory using `--same-permissions`:

```sh
mkdir /path/to/new-empty-source
tar --extract --gzip --same-permissions \
  --file DEV112-P010-framework-source.tar.gz \
  --directory /path/to/new-empty-source
```

Verify the archive checksum first and compare extracted file hashes, sizes and
modes with `SOURCE_FILES.json`. Python's secure `tarfile` data filter can remove
group-write permission: a controlled extractor must restore each verified
regular member's declared mode before checking the full inventory. A Git
checkout records executable bits only and does not establish these full modes.
