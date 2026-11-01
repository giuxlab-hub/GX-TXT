"""Bounded, read-only source provider for explicit scientific JSON documents.

The existing CORE manager owns identity, registry, dispatch and typed envelopes.
Source policy owns consultation/export/cache permission. Scientific payloads are
opaque typed values: this provider does not claim domain validation or numerics.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import copy
import hashlib
import ipaddress
import functools
import http.client
import math
import json
import os
from pathlib import Path
import re
import ssl
import stat
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

LIBRARY_TYPE = 'scientific.reference.json'
LIBRARY_CAPABILITIES = dict(modes=['external', 'remote'], read_only=True,
    mutable=False, authentication_required=False, offline_available=False,
    list_entries=True, entry_info=True, search_entries=True, read_entry=True,
    export_entry=True, add_entry=False, remove_entry=False, verify=False)
REGISTRATION_SCHEMA = {
    'external': dict(required=['path'], optional=['expected_sha256']),
    'remote': dict(required=['endpoint'], optional=['cache', 'ca_file', 'loopback_http'])}
_MAX_BYTES = 8 * 1024 * 1024
_OPERATIONS = frozenset(('list_entries', 'entry_info', 'search_entries', 'read_entry', 'export_entry'))
_SHA = re.compile(r'[0-9a-f]{64}\Z')
_pending = None


class SourceError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__('Scientific reference source operation failed.')


def _fail(code):
    raise SourceError(code) from None


def _text(value, maximum=4096):
    if type(value) is not str or not 0 < len(value) <= maximum or '\0' in value:
        return False
    try:
        value.encode('utf-8')
        return True
    except UnicodeError:
        return False


def _pairs(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            _fail('integrity_failure')
        value[key] = item
    return value


def _parse(raw):
    if len(raw) > _MAX_BYTES:
        _fail('invalid_provider_response')
    try:
        def constant(_value):
            _fail('invalid_provider_response')
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=_pairs,
                           parse_constant=constant)
        budget = [100000]
        def walk(item, depth=0):
            budget[0] -= 1
            if budget[0] < 0 or depth > 32:
                _fail('invalid_provider_response')
            if isinstance(item, float) and not math.isfinite(item):
                _fail('invalid_provider_response')
            if isinstance(item, str):
                item.encode('utf-8')
            if isinstance(item, dict):
                for key in item:
                    key.encode('utf-8')
                for child in item.values():
                    walk(child, depth + 1)
            elif isinstance(item, list):
                for child in item:
                    walk(child, depth + 1)
        walk(value)
    except SourceError:
        raise
    except (ValueError, UnicodeError, RecursionError, TypeError):
        _fail('invalid_provider_response')
    if (type(value) is not dict or set(value) != {'schema', 'source_id', 'revision', 'license', 'policy', 'entries'}
            or value.get('schema') != 'gxtxt.scientific_reference_source.v1'
            or any(not _text(value.get(key)) for key in ('source_id', 'revision', 'license'))):
        _fail('invalid_provider_response')
    policy = value['policy']
    if (type(policy) is not dict or set(policy) - {'operations', 'policy_reference', 'cache_allowed', 'cache_max_age_seconds'}
            or not _text(policy.get('policy_reference'))
            or type(policy.get('operations')) is not list
            or any(type(op) is not str or op not in _OPERATIONS for op in policy['operations'])
            or len(policy['operations']) != len(set(policy['operations']))
            or type(policy.get('cache_allowed', False)) is not bool
            or type(policy.get('cache_max_age_seconds', 0)) is not int
            or not 0 <= policy.get('cache_max_age_seconds', 0) <= 3600):
        _fail('invalid_provider_response')
    entries = value['entries']
    if type(entries) is not list or len(entries) > 20000:
        _fail('invalid_provider_response')
    seen = set()
    for entry in entries:
        if (type(entry) is not dict or set(entry) != {'entry_id', 'metadata', 'provenance', 'payload'}
                or not _text(entry.get('entry_id')) or entry['entry_id'] in seen
                or type(entry['metadata']) is not dict or type(entry['provenance']) is not dict):
            _fail('invalid_provider_response')
        seen.add(entry['entry_id'])
    value['_document_sha256'] = hashlib.sha256(raw).hexdigest()
    return value


def _file(path):
    if not _text(path) or not Path(path).is_absolute():
        _fail('invalid_provider_configuration')
    try:
        entry = os.lstat(path)
        if not stat.S_ISREG(entry.st_mode):
            _fail('integrity_failure')
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            before = os.fstat(stream.fileno())
            if (entry.st_dev, entry.st_ino) != (before.st_dev, before.st_ino):
                _fail('integrity_failure')
            if not stat.S_ISREG(before.st_mode) or before.st_size > _MAX_BYTES:
                _fail('integrity_failure')
            raw = stream.read(_MAX_BYTES + 1)
            after = os.fstat(stream.fileno())
            stamp = lambda info: (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
            if len(raw) > _MAX_BYTES or stamp(before) != stamp(after):
                _fail('integrity_failure')
            return raw
    except SourceError:
        raise
    except OSError:
        _fail('temporarily_unavailable')


def _endpoint(configuration):
    endpoint = configuration.get('endpoint')
    if not _text(endpoint, 2048):
        _fail('invalid_provider_configuration')
    try:
        parsed = urllib.parse.urlsplit(endpoint)
        port = parsed.port
        host = parsed.hostname
    except ValueError:
        _fail('invalid_provider_configuration')
    if (not host or parsed.username is not None or parsed.password is not None
            or parsed.fragment or parsed.query or any(ord(c) < 33 for c in endpoint)):
        _fail('invalid_provider_configuration')
    if parsed.scheme != 'https':
        try:
            loopback = ipaddress.ip_address(host).is_loopback
        except ValueError:
            loopback = False
        if not (parsed.scheme == 'http' and loopback and configuration.get('loopback_http') == '1'):
            _fail('invalid_provider_configuration')
    if configuration.get('cache', 'off') not in {'off', 'permitted'}:
        _fail('invalid_provider_configuration')
    if configuration.get('loopback_http', '0') not in {'0', '1'}:
        _fail('invalid_provider_configuration')
    ca = configuration.get('ca_file')
    if ca is not None and (not _text(ca) or not Path(ca).is_absolute()):
        _fail('invalid_provider_configuration')
    return endpoint


def validate_registration(mode, configuration):
    schema = REGISTRATION_SCHEMA.get(mode)
    if (schema is None or type(configuration) is not dict
            or set(configuration) - set(schema['required']) - set(schema['optional'])
            or set(schema['required']) - set(configuration)):
        _fail('invalid_provider_configuration')
    if mode == 'external':
        if not _text(configuration['path']) or not Path(configuration['path']).is_absolute():
            _fail('invalid_provider_configuration')
        expected = configuration.get('expected_sha256')
        if expected is not None and (type(expected) is not str or not _SHA.fullmatch(expected)):
            _fail('invalid_provider_configuration')
    else:
        _endpoint(configuration)
    # No network or content read: registration is identity/configuration only.


def _identity(record):
    return hashlib.sha256(json.dumps(record, sort_keys=True, separators=(',', ':'),
                                    allow_nan=False).encode('utf-8')).hexdigest()


def _cache_path(key):
    root = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'gxtxt_pipeline' / 'scientific-reference-json-v1'
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        _fail('integrity_failure')
    return root / (key + '.json')


def _cache_read(path, key):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                    or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1
                    or info.st_size > _MAX_BYTES * 2):
                return None
            cached = json.loads(stream.read(_MAX_BYTES * 2 + 1))
        if (type(cached) is not dict or set(cached) != {'key', 'sha256', 'body_b64', 'etag', 'expires', 'fetched'}
                or cached['key'] != key or type(cached['etag']) is not str
                or len(cached['etag']) > 4096 or any(c in cached['etag'] for c in '\r\n')
                or type(cached['expires']) not in (int, float) or type(cached['fetched']) not in (int, float)
                or not 0 <= cached['expires'] - cached['fetched'] <= 3600
                or not cached['fetched'] <= time.time()):
            return None
        raw = base64.b64decode(cached['body_b64'], validate=True)
        if len(raw) > _MAX_BYTES or hashlib.sha256(raw).hexdigest() != cached['sha256']:
            return None
        document = _parse(raw)
        if not document['policy'].get('cache_allowed', False):
            return None
        cached['raw'] = raw
        cached['document'] = document
        return cached
    except (OSError, ValueError, TypeError, KeyError, SourceError):
        return None


def _cache_write(path, key, raw, document, etag, max_age):
    policy = document['policy']
    age = min(max_age, policy.get('cache_max_age_seconds', 0)) if policy.get('cache_allowed', False) else 0
    if age <= 0:
        return
    # A small, bounded provider cache; no automatic bulk mirror or directory sweep.
    if not path.exists() and len(list(path.parent.glob('*.json'))) >= 64:
        return
    now = time.time()
    envelope = dict(key=key, sha256=hashlib.sha256(raw).hexdigest(), body_b64=base64.b64encode(raw).decode('ascii'),
                    etag=etag, fetched=now, expires=now + age)
    fd, temporary = tempfile.mkstemp(prefix='.entry-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(envelope, stream, allow_nan=False, separators=(',', ':'))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def _remote(record):
    configuration = record['provider_config']
    endpoint = _endpoint(configuration)
    key = _identity(record)
    cache_path = None
    cached = None
    if configuration.get('cache', 'off') == 'permitted':
        cache_path = _cache_path(key)
        cached = _cache_read(cache_path, key)
        if cached and time.time() < cached['expires']:
            return cached['document']
    headers = {'Accept': 'application/json', 'User-Agent': 'GX-TXT-Scientific-Reference/1'}
    if cached and cached['etag']:
        headers['If-None-Match'] = cached['etag']
    try:
        context = ssl.create_default_context(cafile=configuration.get('ca_file'))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
            _NoRedirect(), urllib.request.HTTPSHandler(context=context))
        request = urllib.request.Request(endpoint, headers=headers, method='GET')
        deadline = time.monotonic() + 5
        try:
            response = opener.open(request, timeout=5)
        except urllib.error.HTTPError as error:
            if error.code != 304 or not cached:
                raise
            response = error
        with response:
            if response.status == 304:
                raw = cached['raw']
                document = cached['document']
            elif response.status == 200:
                if response.headers.get_content_type() != 'application/json':
                    _fail('invalid_provider_response')
                length = response.headers.get('Content-Length')
                if length is not None and (not length.isdigit() or int(length) > _MAX_BYTES):
                    _fail('invalid_provider_response')
                chunks = []
                count = 0
                while True:
                    if response.isclosed():
                        break
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        _fail('temporarily_unavailable')
                    # read1 performs at most one underlying receive. A buffered
                    # read(n) could wait for n bytes under a slow-drip peer and
                    # repeatedly renew its socket timeout. Tighten each actual
                    # receive to the ORIGINAL request's remaining body budget.
                    try:
                        response.fp.raw._sock.settimeout(remaining)
                    except (AttributeError, OSError):
                        _fail('temporarily_unavailable')
                    chunk = response.read1(min(65536, _MAX_BYTES + 1 - count))
                    if not chunk:
                        break
                    chunks.append(chunk)
                    count += len(chunk)
                    if count > _MAX_BYTES:
                        _fail('invalid_provider_response')
                if response.length not in (None, 0):
                    _fail('invalid_provider_response')
                raw = b''.join(chunks)
                if length is not None and len(raw) != int(length):
                    _fail('invalid_provider_response')
                document = _parse(raw)
            else:
                _fail('temporarily_unavailable')
            control = response.headers.get('Cache-Control', '')
            max_age = 0
            if not re.search(r'(?i)(?:^|,)\s*(?:no-store|no-cache|private)(?:=|\s|,|$)', control):
                match = re.search(r'(?i)(?:^|,)\s*max-age=([0-9]+)(?:\s|,|$)', control)
                if match:
                    max_age = min(int(match[1]), 3600)
            etag = response.headers.get('ETag', cached['etag'] if cached else '')
            if len(etag) > 4096 or any(c in etag for c in '\r\n'):
                _fail('invalid_provider_response')
            if cache_path is not None:
                if max_age and document['policy'].get('cache_allowed', False):
                    _cache_write(cache_path, key, raw, document, etag, max_age)
                else:
                    cache_path.unlink(missing_ok=True)
            return document
    except SourceError:
        raise
    except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException):
        # Expired cache is never an offline fallback or synthetic success.
        _fail('temporarily_unavailable')


def _load(record):
    configuration = record['provider_config']
    validate_registration(record['mode'], configuration)
    if record['mode'] == 'remote':
        return _remote(record)
    raw = _file(configuration['path'])
    if configuration.get('expected_sha256') and hashlib.sha256(raw).hexdigest() != configuration['expected_sha256']:
        _fail('integrity_failure')
    return _parse(raw)


def _public(function):
    @functools.wraps(function)
    def call(*args):
        try:
            return function(*args)
        except SourceError as error:
            return dict(error=dict(code=error.code, message='Scientific reference source refused this operation.'))
    return call


@_public
def library_content_policy(record, operation, parameters, framework_root):
    global _pending
    _pending = None
    document = _load(record)
    allowed = operation in document['policy']['operations']
    if allowed:
        _pending = (_identity(record), operation, document)
    return dict(allowed=allowed, policy_reference=document['policy']['policy_reference'],
                reason='' if allowed else 'Source policy forbids this operation.')


def _snapshot(record, operation):
    global _pending
    pending = _pending
    _pending = None
    document = pending[2] if pending and pending[:2] == (_identity(record), operation) else _load(record)
    if operation not in document['policy']['operations']:
        _fail('policy_restricted')
    return document


def _provenance(document, entry=None):
    result = copy.deepcopy(entry['provenance']) if entry else {}
    result.update(source_id=document['source_id'], source_revision=document['revision'], license=document['license'],
                  source_policy_reference=document['policy']['policy_reference'], source_document_sha256=document['_document_sha256'])
    return result


def _entry(document, entry_id):
    for entry in document['entries']:
        if entry['entry_id'] == entry_id:
            return entry
    _fail('entry_not_found')


def _page(record, parameters, operation):
    document = _snapshot(record, operation)
    query = parameters.get('query', '') if operation == 'search_entries' else ''
    if type(query) is not str or len(query) > 1024:
        _fail('invalid_request')
    token = parameters.get('continuation', '')
    query_key = hashlib.sha256(query.encode('utf-8')).hexdigest()[:16]
    identity = hashlib.sha256((document['source_id'] + '\0' + document['revision'] + '\0' + document['_document_sha256']).encode('utf-8')).hexdigest()[:16]
    offset = 0
    if token:
        parts = token.split(':')
        if len(parts) != 3 or parts[0] != identity or parts[1] != query_key or not parts[2].isdigit():
            _fail('invalid_request')
        offset = int(parts[2])
    rows = [entry for entry in document['entries'] if not query or query.casefold() in
            (entry['entry_id'] + ' ' + json.dumps(entry['metadata'], ensure_ascii=False)).casefold()]
    if offset > len(rows):
        _fail('invalid_request')
    limit = parameters.get('limit', 100)
    if type(limit) is not int or not 1 <= limit <= 200:
        _fail('invalid_request')
    selected = rows[offset:offset + limit]
    result = dict(records=[dict(entry_id=entry['entry_id'], metadata=copy.deepcopy(entry['metadata']),
                  provenance=_provenance(document, entry)) for entry in selected], total=len(rows))
    if offset + len(selected) < len(rows):
        result['continuation'] = f'{identity}:{query_key}:{offset + len(selected)}'
    return result


@_public
def list_entries(record, parameters, framework_root):
    return _page(record, parameters, 'list_entries')


@_public
def search_entries(record, parameters, framework_root):
    return _page(record, parameters, 'search_entries')


@_public
def entry_info(record, parameters, framework_root):
    document = _snapshot(record, 'entry_info')
    entry = _entry(document, parameters['entry_id'])
    return dict(entry_id=entry['entry_id'], metadata=copy.deepcopy(entry['metadata']), provenance=_provenance(document, entry))


@_public
def read_entry(record, parameters, framework_root):
    document = _snapshot(record, 'read_entry')
    entry = _entry(document, parameters['entry_id'])
    return dict(entry_id=entry['entry_id'], payload=copy.deepcopy(entry['payload']),
                metadata=copy.deepcopy(entry['metadata']), provenance=_provenance(document, entry))


@_public
def export_entry(record, parameters, framework_root):
    document = _snapshot(record, 'export_entry')
    if parameters.get('format') != 'json':
        _fail('unsupported_operation')
    entry = _entry(document, parameters['entry_id'])
    return dict(entry_id=entry['entry_id'], media_type='application/json', encoding='utf-8',
                data=json.dumps(entry, ensure_ascii=False, allow_nan=False, separators=(',', ':')),
                provenance=_provenance(document, entry))
