"""Explicit optional P019 rollback; refuses later/different product changes."""
from pathlib import Path
import hashlib,json,shutil,sys
root=Path(sys.argv[1]).resolve()
notes=root/'patch_notes/DEV111-P019'
manifest=json.loads((notes/'FILES.json').read_text())['changed_files']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in manifest:
    p=root/row['path']
    if not p.resolve().is_relative_to(root) or not p.is_file() or p.is_symlink() or sha(p)!=row['after_sha256']:
        raise SystemExit('Refusing divergent postimage: '+row['path'])
    if row['before_sha256'] is not None:
        source=notes/'rollback-preimages'/row['path']
        if not source.is_file() or source.is_symlink() or sha(source)!=row['before_sha256']:
            raise SystemExit('Invalid rollback preimage: '+row['path'])
for row in manifest:
    p=root/row['path']
    if row['before_sha256'] is None:
        p.unlink()
    else:
        shutil.copy2(notes/'rollback-preimages'/row['path'],p)
print('P018 product preimages restored; patch_notes evidence retained. Restart required.')
