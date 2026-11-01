"""Neutral normalized read adapter for existing managed .gxsrl providers.

Scientific validation, arrays and interpretation remain in the passed provider.
The existing manager supplies the verified immutable storage identity. No new
library registry, store, converter, payload cache or scientific parser exists.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import contextlib
import hashlib
import json
import sqlite3
from urllib.parse import quote

_OPERATIONS = frozenset(('list_entries', 'entry_info', 'search_entries', 'read_entry'))


def capabilities():
    return dict(modes=['managed'], read_only=True, mutable=False,
                authentication_required=False, offline_available=True,
                list_entries=True, entry_info=True, search_entries=True,
                read_entry=True, export_entry=False, add_entry=False,
                remove_entry=False, verify=True)


def policy(record, operation):
    allowed = record.get('mode', 'managed') == 'managed' and operation in _OPERATIONS
    return dict(allowed=allowed, policy_reference='gxtxt:managed-spectral-consultation-v1',
                reason='' if allowed else 'Managed source is immutable; no redistribution permission is inferred.')


def _error(code):
    return dict(error=dict(code=code, message='Managed reference content request was refused.'))


def _path(record):
    if record.get('mode', 'managed') != 'managed' or record.get('state') != 'installed':
        raise ValueError('Unsupported managed source state')
    # Reuse the same registry/storage authority as CORE content dispatch. The
    # import is lazy and performs no registry, provider or scientific operation.
    import scientific_library_manager as manager
    return manager.storage_path(manager.managed_root(), record)


@contextlib.contextmanager
def _connection(record):
    path = _path(record)
    connection = sqlite3.connect('file:' + quote(str(path), safe='/') + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    try:
        if connection.execute('PRAGMA user_version').fetchone()[0] != 1:
            raise ValueError('Unsupported storage schema')
        yield connection
    finally:
        connection.close()


def _provenance(record, row, metadata):
    result = json.loads(row['provenance_json'])
    result.update(source_library_id=record['library_id'],
                  source_library_version=record['version'],
                  source_library_content_hash=metadata['content_hash'],
                  source_payload_sha256=record['payload_sha256'])
    return result


def _metadata(row):
    return dict(spectrum=json.loads(row['fields_json']), entry=json.loads(row['metadata_json']),
                entity_id=row['entity_id'])


def content(record, parameters, operation, read_spectrum):
    if not policy(record, operation)['allowed']:
        return _error('policy_restricted')
    try:
        with _connection(record) as connection:
            metadata = dict(connection.execute('SELECT key,value FROM library_meta'))
            if metadata.get('library_id') != record['library_id']:
                return _error('integrity_failure')
            if operation in {'list_entries', 'search_entries'}:
                query = parameters.get('query', '') if operation == 'search_entries' else ''
                limit = parameters.get('limit', 100)
                if type(query) is not str or len(query) > 1024 or type(limit) is not int or not 1 <= limit <= 200:
                    return _error('invalid_request')
                query_hash = hashlib.sha256(query.encode('utf-8')).hexdigest()[:16]
                identity = metadata['content_hash'] + ':' + query_hash
                token = parameters.get('continuation', '')
                offset = 0
                if token:
                    prefix, separator, value = token.rpartition(':')
                    if not separator or prefix != identity or not value.isdigit() or len(value)>12:
                        return _error('invalid_request')
                    offset = int(value)
                clause = ''
                args = []
                if query:
                    # Bound, literal SQL substring search of existing compact
                    # metadata. This is not a scientific match/ranking engine.
                    clause = " WHERE instr(lower(spectrum_id),lower(?))>0 OR instr(lower(fields_json),lower(?))>0 OR instr(lower(metadata_json),lower(?))>0"
                    args = [query] * 3
                total = connection.execute('SELECT count(*) FROM spectra' + clause, args).fetchone()[0]
                if offset > total:
                    return _error('invalid_request')
                rows = connection.execute('SELECT spectrum_id,entity_id,fields_json,metadata_json,provenance_json FROM spectra' + clause + ' ORDER BY spectrum_id LIMIT ? OFFSET ?', args + [limit, offset]).fetchall()
                result = dict(records=[dict(entry_id=row['spectrum_id'], metadata=_metadata(row),
                    provenance=_provenance(record, row, metadata)) for row in rows], total=total)
                if offset + len(rows) < total:
                    result['continuation'] = identity + ':' + str(offset + len(rows))
                return result
            entry_id = parameters.get('entry_id')
            if type(entry_id) is not str or not entry_id or len(entry_id)>4096:
                return _error('invalid_request')
            row = connection.execute('SELECT spectrum_id,entity_id,fields_json,metadata_json,provenance_json,sample_count FROM spectra WHERE spectrum_id=?', (entry_id,)).fetchone()
            if row is None:
                return _error('entry_not_found')
            result = dict(entry_id=entry_id, metadata=_metadata(row), provenance=_provenance(record, row, metadata))
            if operation == 'entry_info':
                result['content_contract'] = json.loads(row['fields_json'])['contract']
            elif operation == 'read_entry':
                # Sole scientific array reader remains the original provider.
                # Existing CORE envelope converts tuple arrays to JSON lists,
                # preserving their exact double values and scalar metadata.
                options = parameters.get('options', {})
                if type(options) is not dict or set(options) - {'start', 'count'}:
                    return _error('invalid_request')
                total = row['sample_count']
                if options:
                    start, count = options.get('start'), options.get('count')
                    if type(start) is not int or type(count) is not int or start < 0 or not 0 <= count <= 32768 or start > total or count > total - start:
                        return _error('invalid_request')
                else:
                    start, count = 0, total
                    if total > 32768:
                        return dict(error=dict(code='invalid_request', message='Large spectra require explicit provider options start/count with count at most32768.'))
                payload = read_spectrum(_path(record), entry_id)
                if options:
                    payload['x'] = payload['x'][start:start + count]
                    payload['y'] = payload['y'][start:start + count]
                    result['metadata']['read_range'] = dict(start=start, count=count, total=total)
                result['payload'] = payload
            return result
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error, UnicodeError):
        return _error('integrity_failure')
