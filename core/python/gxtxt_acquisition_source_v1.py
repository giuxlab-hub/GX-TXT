# SPDX-License-Identifier: GPL-3.0-or-later
"""Trusted Acquisition broker's selected-source capability implementation.

This module is not an authored plugin entrypoint or a grant-from-JSON service.
The existing Acquisition admission owner supplies the reviewed paths, immutable
request scope and live validator. Only its separate broker holds these FDs;
authored native/helper processes receive bounded slices, never paths or FDs.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
from typing import Callable


class SourceAccessError(ValueError):
    pass


def _uint(value, name, maximum=(1 << 64) - 1):
    if type(value) is not int or value < 0 or value > maximum:
        raise SourceAccessError(f'{name} must be a bounded unsigned integer')
    return value


def _identity(info):
    return (info.st_dev, info.st_ino, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


class AcquisitionSourceGrant:
    """One CORE-admitted request/phase; no canonical mutation authority.

    validate_scope must revalidate the actual producer/package, request lifetime,
    cancellation and, for import, live Session incarnation. It runs at admission,
    every exchange/hash chunk, and completion. Source-path and FD identity are
    checked independently here. A caller cannot omit this host-owned validator.
    """

    def __init__(self, scope: dict, sources: list[dict],
                 validate_scope: Callable[[dict], object], *,
                 byte_budget: int | None = None, call_budget: int = 262144):
        if not callable(validate_scope):
            raise SourceAccessError('A live CORE admission validator is required')
        if not isinstance(scope, dict) or set(scope) != {
                'request_id', 'phase', 'module_id', 'qualified_profile',
                'module_snapshot', 'session_token'}:
            raise SourceAccessError('Exact CORE Acquisition request scope required')
        for name in ('request_id', 'module_id', 'qualified_profile'):
            value = scope[name]
            if not isinstance(value, str) or not value or len(value) > 256 or '\x00' in value:
                raise SourceAccessError('Invalid request identity: ' + name)
        if scope['phase'] not in {'recognize', 'inspect', 'test', 'import'}:
            raise SourceAccessError('Unsupported Acquisition phase')
        if not isinstance(scope['module_snapshot'], dict) or not scope['module_snapshot']:
            raise SourceAccessError('Reviewed producer/package snapshot required')
        if not isinstance(scope['session_token'], str):
            raise SourceAccessError('Session incarnation must be explicit')
        if scope['phase'] == 'import' and not scope['session_token']:
            raise SourceAccessError('Import requires its live Session incarnation')
        # Copy inert data: later mutation of a request dictionary cannot retarget
        # this grant. The actual admission remains the host validator's job.
        self._scope = json.loads(json.dumps(scope, allow_nan=False))
        self._validator = validate_scope
        self._sources = []
        self._closed = False
        self._calls = self._bytes = 0
        self._call_budget = _uint(call_budget, 'call_budget', 262144)
        if not self._call_budget:
            raise SourceAccessError('Positive source call budget required')
        if not isinstance(sources, list) or not 1 <= len(sources) <= 64:
            raise SourceAccessError('Acquisition requires 1..64 selected sources')
        total = 0
        try:
            self._validate()
            for index, source in enumerate(sources):
                if not isinstance(source, dict) or set(source) != {
                        'path', 'logical_name', 'sha256'}:
                    raise SourceAccessError('Exact reviewed source record required')
                path = Path(source['path'])
                name, expected = source['logical_name'], source['sha256']
                if not path.is_absolute() or path.is_symlink():
                    raise SourceAccessError('Reviewed ordinary absolute source required')
                if not isinstance(name, str) or not name or len(name.encode('utf-8')) > 4096:
                    raise SourceAccessError('Bounded logical source name required')
                if expected is not None and (not isinstance(expected, str) or
                        not re.fullmatch('[0-9a-f]{64}', expected)):
                    raise SourceAccessError('Invalid reviewed source SHA-256')
                if self._scope['phase'] in {'test', 'import'} and expected is None:
                    raise SourceAccessError('Test/import requires the reviewed full source SHA-256')
                try:
                    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
                except OSError:
                    raise SourceAccessError('Reviewed source is not available as an ordinary readable file') from None
                try:
                    info = os.fstat(fd)
                    if not stat.S_ISREG(info.st_mode):
                        raise SourceAccessError('Selected source must be an ordinary file')
                    if info.st_size > 2147483648 or total + info.st_size > 2147483648:
                        raise SourceAccessError('Selected sources exceed the 2 GiB request bound')
                    record = dict(fd=fd, path=path, identity=_identity(info),
                                  index=index, logical_name=name, sha256=expected)
                    self._unchanged(record)
                    self._sources.append(record)
                    fd = None
                    total += info.st_size
                    if expected is not None and self._digest(record) != expected:
                        raise SourceAccessError('Selected source SHA differs from its reviewed snapshot')
                finally:
                    if fd is not None:
                        os.close(fd)
            default = (1048576 if self._scope['phase'] in {'recognize', 'inspect'}
                       else min(4294967296, max(65536, total * 2)))
            self._byte_budget = _uint(default if byte_budget is None else byte_budget,
                                      'byte_budget', 4294967296)
        except BaseException:
            self.close()
            raise

    def _validate(self):
        if self._closed:
            raise SourceAccessError('Acquisition source grant has ended')
        if self._validator(json.loads(json.dumps(self._scope))) is False:
            raise SourceAccessError('Acquisition admission or lifetime was revoked')

    def _unchanged(self, source):
        try:
            fd_info = os.fstat(source['fd'])
            path_info = os.stat(source['path'], follow_symlinks=False)
        except OSError:
            raise SourceAccessError('Reviewed source is no longer available') from None
        if not stat.S_ISREG(path_info.st_mode) or _identity(fd_info) != source['identity'] \
                or _identity(path_info) != source['identity']:
            raise SourceAccessError('Selected source identity changed after review')

    def _digest(self, source):
        self._validate()
        self._unchanged(source)
        digest = hashlib.sha256()
        offset = 0
        while offset < source['identity'][2]:
            self._validate()
            try:
                chunk = os.pread(source['fd'], min(65536, source['identity'][2] - offset), offset)
            except OSError:
                raise SourceAccessError('Reviewed source could not be verified') from None
            if not chunk:
                raise SourceAccessError('Reviewed source ended during verification')
            digest.update(chunk)
            offset += len(chunk)
        self._unchanged(source)
        return digest.hexdigest()

    @staticmethod
    def _descriptor(source):
        return dict(source_index=source['index'], logical_name=source['logical_name'],
                    size=source['identity'][2], source_sha256=source['sha256'],
                    full_sha_reviewed=source['sha256'] is not None)

    def descriptors(self):
        self._validate()
        for source in self._sources:
            self._unchanged(source)
        return [self._descriptor(source) for source in self._sources]

    def read(self, source_index, offset, count):
        self._validate()
        _uint(source_index, 'source_index', 63)
        if source_index >= len(self._sources):
            raise SourceAccessError('Source is outside this request')
        _uint(offset, 'offset')
        if not 1 <= _uint(count, 'count', 65536) <= 65536:
            raise SourceAccessError('Source slices require 1..65536 bytes')
        source = self._sources[source_index]
        self._unchanged(source)
        size = source['identity'][2]
        if offset > size:
            raise SourceAccessError('Source offset is outside the reviewed file')
        length = min(count, size - offset)
        if self._calls >= self._call_budget or length > self._byte_budget - self._bytes:
            raise SourceAccessError('Acquisition source phase budget exhausted')
        try:
            data = os.pread(source['fd'], length, offset)
        except OSError:
            raise SourceAccessError('Reviewed source could not be read') from None
        self._validate()
        self._unchanged(source)
        if len(data) != length:
            raise SourceAccessError('Selected source changed during its read')
        self._calls += 1
        self._bytes += len(data)
        return dict(offset=offset, byte_count=len(data), total_size=size,
                    eof=offset + len(data) == size, data=data)

    def finalize(self):
        """Recheck reviewed full hashes before CORE may consume parser outputs."""
        try:
            result = self.descriptors()
            for source in self._sources:
                if source['sha256'] is not None and self._digest(source) != source['sha256']:
                    raise SourceAccessError('Selected source changed before completion')
            self._validate()
            return result
        finally:
            self.close()

    def close(self):
        if self._closed:
            return
        self._closed = True
        for source in self._sources:
            try:
                os.close(source['fd'])
            except OSError:
                pass

    def __enter__(self):
        self._validate()
        return self

    def __exit__(self, *_):
        self.close()
