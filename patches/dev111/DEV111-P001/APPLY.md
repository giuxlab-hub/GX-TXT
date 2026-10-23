# DEV111-P001 — staged patch, NOT installed

> **GitHub source compatibility:** This patch was compared with published GX-TXT dev-111-r3 main commit 4daf135e49378eff1f413310bc17cf32f1928c44. All six preimage SHA-256 and two unchanged owner guards matched. The independent original Linux source commit 83b391de4b81a87e4e76f477491371b58cdc3a40 is not a source-bytes mismatch.
>
> **Installer permissions limitation:** Every touched file has a required original mode of 0664 (manifest decimal 436). Normal Git checkouts have tracked mode 100644 and commonly materialize as 0644, so the original installer refuses those clones. Do not bypass this refusal: use the compatible original extracted r3 installation or separately validate a Git-clone-specific installer.
>
> **Release status:** Staged and focused-test verified; NOT installed. The official main source and original release archives are unchanged. Full GUI/scientific regression is not asserted.

---

Requires explicit user authorization before performing the apply or rollback steps.
Target: GX-TXT 0.9.8.10-dev-111 artifact r3, source
83b391de4b81a87e4e76f477491371b58cdc3a40, predecessor patch 0.
Archive SHA-256: c31721b84e8f66cd385c1df4d82fae76e32ca816f2bec7f74c434ac720d26cfe.

Review MANIFEST.json, product.diff and VALIDATION.md. Back up any unsaved work,
save and close GX-TXT normally (including other GUIs/CLI processes using this
target). Confirm the target release using the original acceptance receipt. Keep
the original archive and complete existing release rollback unchanged.
The patch does not alter any plugin package, release marker, Session or Dataset.
It requires restarting GX-TXT; there is no live/hot apply.

From this patch directory, first verify delivered bytes:

```sh
sha256sum -c SHA256SUMS
```

After user authorization, set TARGET to the intended extracted/installed framework
root, PATCH to this patch directory, and OP to apply. The following exact Python
sequence preflights EVERY touched path and two unchanged owner/version guards
before any replacement. It refuses wrong old hashes, symlinks, changed permissions,
missing files and unexpected ZIP members. It retains exact original-file backups
and a transaction log in a new target-local directory. File replacements are
atomic individually; the batch requires a closed application. On interruption,
keep that transaction directory and complete/reverse from its recorded preimages;
do not bypass a hash refusal or retry a partial batch blindly.

```sh
TARGET=/path/to/gxtxt
PATCH=/absolute/path/to/extracted/DEV111-P001
OP=apply
python3 - "$TARGET" "$PATCH" "$OP" <<'PY'
import sys, pathlib, json, hashlib, zipfile, os, stat, tempfile
root=pathlib.Path(sys.argv[1]).resolve(strict=True)
patch=pathlib.Path(sys.argv[2]).resolve(strict=True)
op=sys.argv[3]
assert op in {'apply','rollback'}
m=json.loads((patch/'MANIFEST.json').read_text())
assert m['patch_id']=='DEV111-P001' and m['required_predecessor_patch']==0
sha=lambda b:hashlib.sha256(b).hexdigest()
for guard in m['unchanged_guards']:
    p=root/guard['path']
    assert p.is_file() and not p.is_symlink() and sha(p.read_bytes())==guard['sha256'], ('wrong release/owner',p)
archive=patch/('DEV111-P001.zip' if op=='apply' else 'ROLLBACK.zip')
assert sha(archive.read_bytes())==m['archives'][archive.name]['sha256']
oldkey,newkey=('before_sha256','after_sha256') if op=='apply' else ('after_sha256','before_sha256')
with zipfile.ZipFile(archive) as z:
    paths=[r['path'] for r in m['files']]
    assert len(z.namelist())==len(paths) and set(z.namelist())==set(paths)
    data={p:z.read(p) for p in paths}
preimages={}
for r in m['files']:
    rel=pathlib.PurePosixPath(r['path']);assert not rel.is_absolute() and '..' not in rel.parts
    p=root/rel
    assert p.parent.resolve().is_relative_to(root) and not p.is_symlink() and p.is_file(), p
    b=p.read_bytes();assert sha(b)==r[oldkey], ('preflight old hash mismatch',p)
    assert stat.S_IMODE(p.stat().st_mode)==r['mode'], ('preflight mode mismatch',p)
    assert sha(data[r['path']])==r[newkey], ('payload hash mismatch',p)
    preimages[r['path']]=b
print('PASS preflight: all paths; no files replaced yet')
transaction=pathlib.Path(tempfile.mkdtemp(prefix='.DEV111-P001-'+op+'-',dir=root))
for r in m['files']:
    backup=transaction/r['path'];backup.parent.mkdir(parents=True,exist_ok=True)
    backup.write_bytes(preimages[r['path']]);os.chmod(backup,r['mode'])
log=transaction/'TRANSACTION.json'
state={'operation':op,'completed':[],'patch':'DEV111-P001'}
log.write_text(json.dumps(state,indent=2)+'\n')
for r in m['files']:
    p=root/r['path']
    assert sha(p.read_bytes())==r[oldkey], ('changed since preflight',p)
    fd,tmp=tempfile.mkstemp(prefix='.DEV111-P001-',dir=p.parent)
    try:
        with os.fdopen(fd,'wb') as f:
            f.write(data[r['path']]);f.flush();os.fsync(f.fileno())
        os.chmod(tmp,r['mode']);os.replace(tmp,p)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
    assert sha(p.read_bytes())==r[newkey]
    state['completed'].append(r['path']);log.write_text(json.dumps(state,indent=2)+'\n')
print('PASS',op,'; retained transaction/preimages:',transaction)
PY
```

Restart GX-TXT normally. In Modules, show/hide an enabled module and inspect
Analysis. Confirm both toolbar commands and selected name; do not execute runtime
reset unless independently intended. Save Config in each Session to persist its
visibility choice through the existing Session/configuration workflow.

Rollback after authorization: close the application, verify SHA256SUMS again,
run the same sequence with OP=rollback. It requires ALL six post-P001 hashes
and restores ONLY the six r3 files from ROLLBACK.zip. Restart normally. Old code
ignores the additive `module_state.analysis_hidden` key; saved Run preferences
and scientific state were not removed or repurposed. Do not remove the key or
rewrite Sessions as part of rollback. No migration/activation helper is needed.

Do not edit the immutable official r3 archive/expanded release, release markers,
three-section package catalog, or authoritative unfinished-work TODO to apply
this staged patch. Any future P002 must require the post-P001 hashes in this
manifest, and any touched P002 file must be rolled back before rolling back P001.

The framework's original root SHA256SUMS remains the immutable r3 inventory.
After applying an overlay, use this patch's per-file before/after hashes for the
six changed files; do not misreport those expected differences as an unchanged
full r3 tree, or regenerate the entire framework inventory/package.
