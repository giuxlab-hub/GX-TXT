#!/usr/bin/env bash
# DEV111-P002: one-command offline installer; close GX-TXT first.
set -euo pipefail
patch_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
operation=apply
if [[ ${1:-} == --rollback ]]; then operation=rollback; shift; fi
if [[ ${1:-} == --help || ${1:-} == -h || $# != 1 ]]; then
    printf '%s\n' 'Close GX-TXT, then: ./apply.sh /path/to/gxtxt' 'Optional rollback: ./apply.sh --rollback /path/to/gxtxt'
    [[ $# == 1 ]] && exit 0 || exit 2
fi
python3 - "$patch_dir" "$1" "$operation" <<'PY'
import sys, pathlib, hashlib, json, os, stat, tempfile, datetime, platform
patch,root=map(lambda s:pathlib.Path(s).resolve(strict=True),sys.argv[1:3]);operation=sys.argv[3]
def fail(message): raise RuntimeError(message)
def digest(data): return hashlib.sha256(data).hexdigest()
def content(path):
    if path.is_symlink() or not path.is_file(): fail(f'Missing or incompatible file: {path}')
    return path.read_bytes()
def main():
    manifest=json.loads((patch/'MANIFEST.json').read_text())
    if manifest['patch_id']!='DEV111-P002' or manifest['required_predecessor_patch']!=1: fail('Wrong patch manifest.')
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'): fail('This patch requires Linux x86_64 (matching the native dev111 distribution).')
    for record in manifest['predecessor_files']:
        path=root/record['path']
        if digest(content(path))!=record['sha256']: fail(f'DEV111-P001 is required; incompatible predecessor file: {record["path"]}')
    for record in manifest.get('required_unchanged_files',[]):
        if digest(content(root/record['path']))!=record['sha256']: fail(f'Incompatible required native engine: {record["path"]}')
    oldkey,newkey=('before_sha256','after_sha256') if operation=='apply' else ('after_sha256','before_sha256')
    expected=[];payload={};before={};modes={}
    for record in manifest['files']:
        name=record['path'];relative=pathlib.PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts: fail('Invalid patch path.')
        target=root/name
        if not target.parent.resolve().is_relative_to(root): fail(f'Target escapes framework root: {name}')
        old,new=record[oldkey],record[newkey]
        data=content(target) if target.exists() or target.is_symlink() else None
        if (digest(data) if data is not None else None)!=old: fail(f'Incompatible file: {name}. Expected {"P001/base" if operation=="apply" else "P002"} bytes; no files changed.')
        before[name]=data;modes[name]=stat.S_IMODE(target.stat().st_mode) if data is not None else record['mode']
        if new is not None:
            source=patch/('payload' if operation=='apply' else 'originals')/name
            replacement=content(source)
            if digest(replacement)!=new: fail(f'Damaged patch payload: {name}')
            payload[name]=replacement
        expected.append(record)
    # Compatibility and payload checks finish before any framework replacement.
    backup=pathlib.Path(tempfile.mkdtemp(prefix='.DEV111-P002-'+operation+'-',dir=root))
    for name,data in before.items():
        if data is not None:
            saved=backup/name;saved.parent.mkdir(parents=True,exist_ok=True);saved.write_bytes(data);saved.chmod(modes[name])
    (backup/'operation.json').write_text(json.dumps({'patch':'DEV111-P002','operation':operation,'before':{r['path']:r[oldkey] for r in expected}},indent=2)+'\n')
    changed=[]
    def replace(target,data,mode):
        target.parent.mkdir(parents=True,exist_ok=True)
        fd,temporary=tempfile.mkstemp(prefix='.P002-',dir=target.parent)
        try:
            with os.fdopen(fd,'wb') as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
            os.chmod(temporary,mode);os.replace(temporary,target)
        finally:
            if os.path.exists(temporary):os.unlink(temporary)
    try:
        for record in expected:
            name=record['path'];target=root/name
            # Refuse a change made since preflight, rather than overwrite it.
            current=content(target) if target.exists() else None
            if current!=before[name]: fail(f'File changed during installation: {name}')
            if record[newkey] is None:target.unlink()
            else:replace(target,payload[name],modes[name])
            changed.append(name)
    except BaseException:
        for name in reversed(changed):
            if before[name] is None:(root/name).unlink(missing_ok=True)
            else:replace(root/name,before[name],modes[name])
        raise
    print(f'DEV111-P002 {operation} complete. Backup: {backup}\nYou can reopen GX-TXT.')
try: main()
except Exception as error:
    print(f'ERROR: {error}',file=sys.stderr);sys.exit(1)
PY
