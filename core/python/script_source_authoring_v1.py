"""Subordinate Script Registry attachment adapter, never a Registry writer.

Existing Tcl Registry/Project locks own all mutation/CAS. The existing
script_project CLI transports only owner-created inert requests to this module.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import configparser
import json
from pathlib import Path
import re
import source_authoring_v1 as authoring
import source_asset_codec_v1 as asset_codec
from script_api_declarations import tcl

KEY = 'source_authoring_v1'

def decode_pointer(value):
    if value in (None, '', {}): return None
    if isinstance(value, str):
        import tkinter
        fields = tkinter.Tcl().splitlist(value)
        if len(fields) != 6: raise authoring.AuthoringError('Invalid Registry authoring pointer')
        value = dict(zip(fields[::2], fields[1::2]))
    return authoring._pointer(value)

def record_pointer(root):
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.read(Path(root) / 'script.ini', encoding='utf-8')
    return decode_pointer(parser.get('script', KEY, fallback=''))

def verify_tree(root, pointer):
    """Retain exact complete local history; never sweep/copy unadmitted files."""
    root = authoring._root(root); pointer = decode_pointer(pointer)
    tree = root / 'authoring'
    if pointer is None:
        if tree.exists() or tree.is_symlink(): raise authoring.AuthoringError('Undeclared Registry authoring content')
        return []
    authoring.read(root, pointer)
    authoring._directory(tree)
    if {p.name for p in tree.iterdir()} != {'revisions'}: raise authoring.AuthoringError('Unexpected authoring history member')
    revisions = tree / 'revisions'; authoring._directory(revisions)
    result = []
    for revision in revisions.iterdir():
        if not re.fullmatch('[0-9a-f]{64}', revision.name): raise authoring.AuthoringError('Unknown authoring revision')
        manifest = asset_codec.loads(authoring._file(revision / 'manifest.json', authoring.MAX_MANIFEST_BYTES))
        value = dict(pointer, revision=revision.name, schema=manifest['schema'])
        authoring.read(root, value); result.append(value)
    return result

def carry(source, target, pointer):
    pointer = decode_pointer(pointer)
    for revision in verify_tree(source, pointer):
        payload = authoring.export_payload(source, revision)
        actual = authoring._store(target, payload)
        if actual != revision: raise authoring.AuthoringError('Carried authoring history differs')

def validate_record(root, override=None):
    root = authoring._root(root)
    actual = record_pointer(root)
    pointer = decode_pointer(override) if override is not None else actual
    if actual and pointer and actual['owner_key'] != pointer['owner_key']:
        raise authoring.AuthoringError('Registry attachment owner cannot be replaced')
    verify_tree(root, actual or pointer)

def resolve(root, pointer, descriptors, reference):
    descriptors = authoring._source_files(descriptors)
    state = authoring.read(root, pointer); manifest = state['manifest']
    relative = reference.get('relative'); authoring._relative(relative)
    owner_key = reference.get('owner_key', ''); file_key = reference.get('file_key', '')
    if owner_key and (not pointer or owner_key != pointer['owner_key']):
        raise authoring.AuthoringError('Source owner identity changed')
    if file_key:
        matches = [name for name, record in (manifest['files'].items() if manifest else []) if record['file_key'] == file_key]
        if len(matches) != 1: raise authoring.AuthoringError('Source file key is missing/detached or unrelated')
        relative = matches[0]
    if relative not in descriptors: raise authoring.AuthoringError('Choose an active registered source file')
    expected = reference.get('expected_source_sha256', '')
    if expected and descriptors[relative]['source_sha256'] != expected:
        raise authoring.AuthoringError('Source revision changed')
    record = manifest['files'].get(relative) if manifest else None
    if file_key and (record is None or record['file_key'] != file_key):
        raise authoring.AuthoringError('Source path was reused by another file identity')
    text = authoring.file_note(root, pointer, relative) if record else None
    return dict(relative=relative, owner_key=pointer['owner_key'] if pointer else '',
                file_key=record['file_key'] if record else '', authoring_revision=pointer['revision'] if pointer else '',
                created=text is not None, language=descriptors[relative]['language'],
                source_sha256=descriptors[relative]['source_sha256'],
                note_base64=base64.b64encode(text.encode('utf-8')).decode('ascii') if text is not None else '',
                asset_snapshots={name:dict(row, schema=asset_codec.SCHEMA, blob_key=row['sha256'])
                                 for name,row in (record.get('assets', {}).items() if record else [])})

def dispatch(root, request):
    operation = request['operation']; pointer = decode_pointer(request.get('pointer'))
    if operation == 'validate':
        verify_tree(root, pointer)
        return {'valid': True, 'note_count': len(authoring.read(root, pointer)['notes'])}
    if operation == 'carry':
        carry(root, request['target'], pointer); return {'valid': True}
    descriptors = authoring._source_files(request['source_files'])
    if operation == 'sync':
        if pointer:
            carry(request['source_root'], root, pointer)
            pointer = authoring.prepare(root, pointer, descriptors, renames=request.get('renames', {}))
        return {'pointer': tcl(pointer) if pointer else ''}
    if operation in {'clone', 'copy'}:
        if pointer:
            payload = authoring.export_payload(request['source_root'], pointer)
            original = authoring._source_files(request['source_descriptors']) if operation == 'copy' else descriptors
            if set(original) != set(descriptors) or any(original[n]['language'] != descriptors[n]['language'] for n in original):
                raise authoring.AuthoringError('Source/target copy requires identical relative file identities and language')
            # Import against ORIGINAL code first; only explicit copy may then
            # rebase new owner/file keys onto the already saved target buffers.
            pointer = authoring.import_payload(root, payload, original)
            if operation == 'copy': pointer = authoring.prepare(root, pointer, descriptors)
        state = authoring.read(root, pointer)
        return {'pointer': tcl(pointer) if pointer else '',
                'files': {n: row['file_key'] for n, row in state['manifest']['files'].items()} if state['manifest'] else {}}
    reference = request['reference']; projection = resolve(root, pointer, descriptors, reference)
    if operation == 'asset_read':
        if request.get('expected_authoring_revision') != projection['authoring_revision']:
            raise authoring.AuthoringError('Source asset snapshot changed')
        name = request.get('name'); descriptor = projection['asset_snapshots'].get(name)
        if descriptor is None or request.get('expected_asset_sha256') != descriptor['sha256']:
            raise authoring.AuthoringError('Source asset identity changed')
        start, count = request.get('start'), request.get('count')
        if type(start) is not int or type(count) is not int or start < 0 or not 1 <= count <= 1048576 or start > descriptor['size_bytes']:
            raise authoring.AuthoringError('Bounded asset chunk offset/count required')
        raw = authoring.read(root, pointer)['blobs'][descriptor['sha256']]
        chunk = raw[start:start+count]
        return dict(bytes_base64=base64.b64encode(chunk).decode('ascii'), offset=start, count=len(chunk),
                    eof=start+len(chunk)==len(raw), sha256=descriptor['sha256'], size_bytes=len(raw))
    if operation == 'prepare':
        if request.get('expected_authoring_revision') != (pointer['revision'] if pointer else ''):
            raise authoring.AuthoringError('Source authoring changed; reopen before saving')
        updates = {}
        if 'note_base64' in request:
            encoded = request['note_base64']
            if not isinstance(encoded, str) or len(encoded) > 5592408: raise authoring.AuthoringError('Encoded note exceeds4MiB')
            try: raw = base64.b64decode(encoded, validate=True); text = raw.decode('utf-8', errors='strict')
            except (ValueError, UnicodeError) as error: raise authoring.AuthoringError('Note must be exact UTF-8') from error
            authoring._text(raw); updates[projection['relative']] = text
        asset_updates = None
        if 'asset_plan' in request:
            plan = request['asset_plan']
            if not isinstance(plan, dict) or set(plan) != {'directory','index_sha256','index_size'}:
                raise authoring.AuthoringError('Consumed internal asset plan required')
            asset_updates = {projection['relative']: asset_codec.read_plan(plan['directory'], plan['index_sha256'], plan['index_size'])}
        pointer = authoring.prepare(root, pointer, descriptors, updates, asset_updates=asset_updates)
        projection = resolve(root, pointer, descriptors, reference)
    elif operation != 'read': raise authoring.AuthoringError('Unknown source authoring operation')
    return dict(projection, pointer=tcl(pointer) if pointer else '')

def portable(root, pointer):
    return authoring.export_payload(root, decode_pointer(pointer))

def import_portable(root, payload, descriptors):
    return tcl(authoring.import_payload(root, payload, descriptors)) if payload else ''
