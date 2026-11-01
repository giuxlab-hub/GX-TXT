"""Typed, immutable Library records. Scientific Library Manager owns installation.

This module has no Dataset writer, networking, registry or renderer. Type wrappers
in ordinary plugins reuse these fixed normalized content hooks.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import base64
import hashlib
import json
from pathlib import Path

CAPABILITIES = dict(modes=['managed'], read_only=True, mutable=False,
    authentication_required=False, offline_available=True, list_entries=True,
    entry_info=True, search_entries=True, read_entry=True, export_entry=True,
    add_entry=False, remove_entry=False, verify=True)

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')

def entry_hash(entry):
    return hashlib.sha256(canonical({k:v for k,v in entry.items() if k != 'content_sha256'})).hexdigest()

def load(path):
    value = json.loads(Path(path).read_text(encoding='utf-8'))
    if value.get('schema') != 'gxtxt.library_records.v1' or not isinstance(value.get('entries'), dict):
        raise ValueError('Unsupported typed Library payload')
    return value

def validate(path, manifest, framework):
    import scientific_library_graph as graph
    value = load(path)
    if value.get('library_type') != manifest['library_type']:
        raise ValueError('Library record type differs from manifest')
    schemas = graph.schemas()
    for key, entry in value['entries'].items():
        if key != entry.get('entry_id'):
            raise ValueError('Entry identity differs from payload index')
        graph.validate_entry(entry, manifest['library_type'], schemas)
        if entry.get('content_sha256') != entry_hash(entry):
            raise ValueError('Library entry content SHA256 mismatch')
    return dict(entry_ids=sorted(value['entries']), entry_count=len(value['entries']))

def _payload(record):
    import scientific_library_manager as manager
    return load(manager.storage_path(manager.managed_root(), record))

def _entry(record, parameters):
    entry = _payload(record)['entries'].get(parameters['entry_id'])
    if entry is None or entry.get('tombstone'):
        raise ValueError('Library entry is absent or tombstoned')
    return entry

def _provenance(entry):
    return dict(entry.get('provenance', {}), entry_revision=entry['revision'], content_sha256=entry['content_sha256'])

def _page(record, parameters, query=''):
    payload = _payload(record)
    rows = [e for _,e in sorted(payload['entries'].items()) if not e.get('tombstone') and
            query.casefold() in canonical(e).decode('utf-8').casefold()]
    identity = hashlib.sha256(canonical([record['payload_sha256'], query])).hexdigest()
    token = parameters.get('continuation', '')
    offset = 0
    if token:
        prefix, separator, number = token.rpartition(':')
        if not separator or prefix != identity or not number.isdecimal():
            raise ValueError('Stale Library entry continuation')
        offset = int(number)
    limit = parameters.get('limit',100)
    selected = rows[offset:offset+limit]
    result = dict(records=[dict(entry_id=e['entry_id'], metadata=dict(e['fields'], record_type=e['record_type'],
        label=e.get('label',e['entry_id'])), provenance=_provenance(e)) for e in selected], total=len(rows))
    if offset + limit < len(rows):
        result['continuation'] = identity + ':' + str(offset+limit)
    return result

def list_entries(record, parameters, framework):
    return _page(record, parameters)

def search_entries(record, parameters, framework):
    query = parameters['query']
    if not isinstance(query, str):
        raise ValueError('Typed Library search expects text')
    return _page(record,parameters,query)

def entry_info(record, parameters, framework):
    entry = _entry(record, parameters)
    return dict(entry_id=entry['entry_id'], content_contract=entry.get('content_contract',''),
        metadata=dict(entry['fields'], record_type=entry['record_type'], label=entry.get('label',''),
                      resources=entry.get('resources',[])), provenance=_provenance(entry))

def read_entry(record, parameters, framework):
    entry = _entry(record, parameters)
    return dict(entry_id=entry['entry_id'], metadata=entry['fields'], provenance=_provenance(entry), payload=entry)

def export_entry(record, parameters, framework):
    entry = _entry(record, parameters)
    return dict(entry_id=entry['entry_id'], media_type='application/json', encoding='utf-8',
        data=canonical(entry).decode('utf-8'), provenance=_provenance(entry))

def library_content_policy(record, operation, parameters, framework):
    return dict(allowed=operation in {'list_entries','search_entries','entry_info','read_entry','export_entry'})

def activate(new_payload, old_payload, library_id):
    pass

def rollback_activate(old_payload, library_id):
    pass

def deactivate(managed_payload, library_id):
    pass
