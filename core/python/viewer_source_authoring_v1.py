"""C++ Project attachment adapter; caller owns project lock/CAS and publication.

No compilation, Dataset publication, project registry or source writer is here.
The existing C++ owner commits only the returned provenance pointer.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import base64
import hashlib
from pathlib import Path
import stat
import source_authoring_v1 as authoring

KEY = 'source_authoring_v1'

def descriptors(files):
    return {name: {'language': 'cpp', 'source_sha256': hashlib.sha256(raw).hexdigest()}
            for name, raw in files.items()}

def pointer(meta):
    value = meta.get('provenance', {}).get(KEY)
    if value is not None: authoring._pointer(value)
    return value

def package_payload(project):
    """Only the declared flat portable closure, with bounded ordinary members."""
    root = Path(project) / 'authoring'
    if not root.exists() and not root.is_symlink(): return {}
    if root.is_symlink() or not root.is_dir(): raise authoring.AuthoringError('Unsafe packaged authoring root')
    result = {}; total = 0
    for path in root.rglob('*'):
        if path.is_symlink(): raise authoring.AuthoringError('Linked packaged authoring member')
        if path.is_dir(): continue
        state = path.lstat(); name = path.relative_to(root).as_posix()
        limit = authoring.MAX_MANIFEST_BYTES if name == 'manifest.json' else authoring.MAX_NOTE_BYTES
        if (not stat.S_ISREG(state.st_mode) or state.st_nlink != 1 or state.st_size > limit
                or len(result) > authoring.MAX_NOTES + 256): raise authoring.AuthoringError('Invalid packaged authoring member')
        total += state.st_size
        if total > authoring.MAX_TOTAL_BYTES + authoring.MAX_MANIFEST_BYTES: raise authoring.AuthoringError('Packaged authoring byte bound exceeded')
        result[name] = path.read_bytes()
    return result

def validate(project, meta, files, installed=False, portable=None):
    value = pointer(meta)
    if value is None:
        if portable: raise authoring.AuthoringError('Undeclared authoring package content')
        return
    if portable is not None:
        state = authoring._validated_payload(portable, value)
    elif installed:
        state = authoring._validated_payload(package_payload(project), value)
    else: state = authoring.read(project, value)
    # Code may have been edited through the source owner since the last note.
    # Retain old note source hashes for truthful revised/missing diagnostics.
    return state

def resolve(project, meta, files, relative, file_key='', owner_key=''):
    value = pointer(meta)
    if owner_key and (not value or owner_key != value['owner_key']):
        raise authoring.AuthoringError('Associated C++ project identity changed')
    if file_key:
        state = authoring.read(project, value)
        if not state['manifest']: raise authoring.AuthoringError('Associated C++ file identity is unavailable')
        matches = [name for name, row in state['manifest']['files'].items()
                   if row['file_key'] == file_key and name in files]
        if len(matches) != 1: raise authoring.AuthoringError('Associated C++ file was removed; note was not retargeted')
        return matches[0]
    return relative

def projection(project, meta, files, relative, file_key='', owner_key=''):
    relative = resolve(project, meta, files, relative, file_key, owner_key)
    if relative not in files: raise authoring.AuthoringError('Select an admitted C++ source/header')
    value = pointer(meta); state = authoring.read(project, value)
    record = state['manifest']['files'].get(relative) if state['manifest'] else None
    text = authoring.file_note(project, value, relative) if record else None
    return dict(status='SAVED', note_state='saved' if text is not None else 'uncreated', owner_key=value['owner_key'] if value else '',
                file_key=record['file_key'] if record else '', relative=relative, language='cpp',
                source_sha256=hashlib.sha256(files[relative]).hexdigest(),
                source=files[relative].decode('utf-8'), note_base64=base64.b64encode(text.encode('utf-8')).decode('ascii') if text is not None else '', created=text is not None,
                authoring_revision=value['revision'] if value else '',
                project_id=value['owner_key'] if value else '', project_name=meta['module_id'],
                asset_snapshots={name:dict(item,schema='gxtxt.source_asset.v1',blob_key=item['sha256']) for name,item in (record or {}).get('assets',{}).items()})

def prepare(project, meta, files, payload):
    operation = payload['operation']; relative = resolve(project, meta, files, payload.get('relative'), payload.get('file_key', ''), payload.get('owner_key', ''))
    if operation not in {'note_identity', 'note_write'} or relative not in files:
        raise authoring.AuthoringError('Unknown note operation or source/header')
    allowed = {'operation', 'relative', 'file_key', 'owner_key', 'expected_project_sha256', 'expected_authoring_revision', 'expected_source_sha256'}
    if operation == 'note_write': allowed.update({'note_base64','asset_plan'})
    if set(payload) - allowed: raise authoring.AuthoringError('Unknown source-note request field')
    value = pointer(meta)
    if payload.get('expected_source_sha256') != hashlib.sha256(files[relative]).hexdigest():
        raise authoring.AuthoringError('C++ source changed before saving its note')
    if payload.get('expected_authoring_revision', '') != (value['revision'] if value else ''):
        raise authoring.AuthoringError('Source authoring revision changed')
    updates = {}
    if operation == 'note_write':
        encoded=payload.get('note_base64')
        if not isinstance(encoded,str) or len(encoded)>5592408:raise authoring.AuthoringError('Encoded note exceeds4MiB decoded bound')
        try:raw=base64.b64decode(encoded,validate=True);text=raw.decode('utf-8',errors='strict')
        except (ValueError,UnicodeError) as error:raise authoring.AuthoringError('Note must be base64 of valid UTF-8') from error
        if len(raw)>authoring.MAX_NOTE_BYTES or '\0' in text:raise authoring.AuthoringError('Note exceeds4MiB or contains NUL')
        updates={relative:text}
    asset_updates = None
    if 'asset_plan' in payload:
        import source_asset_codec_v1 as assets
        plan = payload['asset_plan']
        if not isinstance(plan,dict) or set(plan) != {'directory','index_sha256','index_size'}:
            raise authoring.AuthoringError('Expected a privately consumed asset plan')
        asset_updates = {relative:assets.read_plan(plan['directory'],plan['index_sha256'],plan['index_size'])}
    next_pointer = authoring.prepare(project, value, descriptors(files), updates, asset_updates=asset_updates)
    updated = copy.deepcopy(meta); updated['provenance'][KEY] = next_pointer
    return updated

def read_asset(project, meta, files, payload):
    allowed = {'operation','relative','file_key','owner_key','expected_project_sha256',
               'expected_authoring_revision','expected_asset_sha256','name','start','count'}
    if set(payload)-allowed: raise authoring.AuthoringError('Unknown source asset request field')
    relative = resolve(project,meta,files,payload.get('relative'),payload.get('file_key',''),payload.get('owner_key',''))
    if relative not in files: raise authoring.AuthoringError('Select an admitted C++ source/header')
    value = pointer(meta)
    if not value or payload.get('expected_authoring_revision') != value['revision']:
        raise authoring.AuthoringError('Source asset snapshot changed')
    state = authoring.read(project,value)
    record = state['manifest']['files'].get(relative)
    name = payload.get('name'); assets = (record or {}).get('assets',{})
    if name not in assets or assets[name]['sha256'] != payload.get('expected_asset_sha256'):
        raise authoring.AuthoringError('Source asset identity changed')
    raw = state['blobs'][assets[name]['sha256']]
    start,count = payload.get('start'),payload.get('count')
    if type(start) is not int or type(count) is not int or not 0 <= start <= len(raw) or not 1 <= count <= 1048576:
        raise authoring.AuthoringError('Source asset range must be bounded to1MiB')
    chunk=raw[start:start+count]
    return dict(bytes_base64=base64.b64encode(chunk).decode('ascii'),offset=start,count=len(chunk),
                eof=start+len(chunk)==len(raw),sha256=assets[name]['sha256'],size_bytes=len(raw))

def source_change(project, meta, files, new_meta, changed_files, renames):
    value = pointer(meta)
    if pointer(new_meta) != value: raise authoring.AuthoringError('Use Source Notes commands to change the reserved authoring pointer')
    if value is None: return new_meta
    next_pointer = authoring.prepare(project, value, descriptors(changed_files), renames=renames)
    updated = copy.deepcopy(new_meta); updated['provenance'][KEY] = next_pointer
    return updated

def export(project, meta):
    return authoring.export_payload(project, pointer(meta))

def import_into(project, meta, files, payload):
    old = pointer(meta)
    if old is None:
        if payload: raise authoring.AuthoringError('Undeclared authoring package content')
        return meta
    authoring._validated_payload(payload, old)
    updated = copy.deepcopy(meta)
    updated['provenance'][KEY] = authoring.import_payload(project, payload, descriptors(files))
    return updated
