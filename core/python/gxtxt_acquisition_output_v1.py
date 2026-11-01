# SPDX-License-Identifier: GPL-3.0-or-later
"""CORE broker's typed staging buffers, not a Dataset writer or public grant.

Only the admitted parent constructs this owner. Authored actors get opaque IDs;
the trusted native worker alone receives private precreated buffer identities.
Final arrays are handed to the existing Acquisition/Publication transaction.
The Resource owner, not this class, removes the private workspace after reap.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat


class OutputAccessError(ValueError):
    pass


WIDTHS = dict(float32=4, float64=8, int8=1, int16=2, int32=4, int64=8,
              uint8=1, uint16=2, uint32=4, uint64=8, bool=1)


def _integer(value, label, maximum):
    if type(value) is not int or not 0 <= value <= maximum:
        raise OutputAccessError('Invalid bounded integer: ' + label)
    return value


def _id(value, label, dataset=False):
    pattern = r'[A-Za-z0-9_.-]+' if dataset else r'[A-Za-z][A-Za-z0-9_.-]*'
    if not isinstance(value, str) or len(value) > 256 or not re.fullmatch(pattern, value) or value in {'.', '..'}:
        raise OutputAccessError('Invalid ' + label)
    return value


def _clone(value):
    try:
        wire = json.dumps(value, allow_nan=False, ensure_ascii=False)
        if len(wire.encode('utf-8')) > 196608:
            raise OutputAccessError('Output metadata exceeds the control bound')
        return json.loads(wire)
    except (ValueError, TypeError, OverflowError):
        raise OutputAccessError('Output metadata must be bounded finite JSON') from None


class AcquisitionOutputBuffers:
    """Request-scoped write-only staging; seal only after the actor is reaped.

    validate_scope rechecks live CORE authority/cancellation on every exchange.
    validate_definition invokes the existing CORE contract/namespace/producer
    preflight before any allocation. Neither callback is supplied by a producer.
    This transport enforces rank/byte/identity bounds but does not replace those
    scientific and publication owners. Any failed exchange poisons this owner.
    """

    def __init__(self, root, scope, validate_scope, validate_definition, *,
                 byte_budget=2147483648):
        if not callable(validate_scope) or not callable(validate_definition):
            raise OutputAccessError('Live CORE scope and definition validators required')
        self._scope = _clone(scope)
        if not isinstance(self._scope, dict) or self._scope.get('phase') not in {'test', 'import'}:
            raise OutputAccessError('Only Test/import may prepare numeric outputs')
        self._validate_scope = validate_scope
        self._validate_definition = validate_definition
        self._root = Path(root)
        if not self._root.is_absolute():
            raise OutputAccessError('CORE must provide an absolute private Resource root')
        info = self._root.stat(follow_symlinks=False)
        if not stat.S_ISDIR(info.st_mode) or self._root.resolve() != self._root:
            raise OutputAccessError('CORE Resource root must be an ordinary resolved directory')
        self._root_identity = info.st_dev, info.st_ino
        self._budget = _integer(byte_budget, 'byte_budget', 2147483648)
        self._root_fd = os.open(self._root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        self._outputs = {}
        self._dataset_ids = set()
        self._bytes = 0
        self._write_calls = 0
        self._failed = self._sealed = self._closed = False
        try:
            self._check()
            if os.listdir(self._root_fd):
                raise OutputAccessError('Typed output Resource root must initially be empty')
        except BaseException:
            self.close()
            raise

    def _check(self):
        if self._closed or self._failed or self._sealed:
            raise OutputAccessError('Typed output capability has ended')
        if self._validate_scope(_clone(self._scope)) is False:
            raise OutputAccessError('Acquisition authority or lifetime was revoked')
        try:
            current = self._root.stat(follow_symlinks=False)
            opened = os.fstat(self._root_fd)
        except OSError:
            raise OutputAccessError('Typed output Resource root is unavailable') from None
        if not stat.S_ISDIR(current.st_mode) or (current.st_dev, current.st_ino) != self._root_identity or (opened.st_dev, opened.st_ino) != self._root_identity:
            raise OutputAccessError('Typed output Resource identity changed')

    def _buffer(self, output_id, variable_id):
        if not isinstance(output_id, str) or output_id not in self._outputs:
            raise OutputAccessError('Output is outside this request')
        output = self._outputs[output_id]
        if not isinstance(variable_id, str) or variable_id not in output['buffers']:
            raise OutputAccessError('Variable is outside this output')
        return output, output['buffers'][variable_id]

    def _stat(self, buffer):
        try:
            info = os.stat(buffer['name'], dir_fd=self._root_fd, follow_symlinks=False)
        except OSError:
            raise OutputAccessError('Issued typed buffer is unavailable') from None
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or (info.st_dev, info.st_ino) != buffer['identity']:
            raise OutputAccessError('Issued typed buffer identity changed')
        held = os.fstat(buffer['fd'])
        if held.st_nlink != 1 or (held.st_dev, held.st_ino) != buffer['identity']:
            raise OutputAccessError('Original typed buffer was detached or replaced')
        return info

    def prepare(self, declaration):
        try:
            self._check()
            item = _clone(declaration)
            if not isinstance(item, dict) or set(item) not in (
                    {'definition', 'row_count', 'variables'},
                    {'definition', 'dimensions', 'variables'}):
                raise OutputAccessError('Exact prepared numeric declaration required')
            definition, variables = item['definition'], item['variables']
            if not isinstance(definition, dict) or 'dataset_id' not in definition or 'contract' not in definition:
                raise OutputAccessError('Existing Publication definition is required')
            dataset_id = _id(definition['dataset_id'], 'Dataset ID', True)
            if dataset_id in self._dataset_ids or len(self._outputs) >= 64:
                raise OutputAccessError('Duplicate Dataset or excessive output count')
            explicit = 'dimensions' in item
            if explicit:
                dimensions = item['dimensions']
                if not isinstance(dimensions, dict) or not 1 <= len(dimensions) <= 16:
                    raise OutputAccessError('Explicit output requires 1..16 dimensions')
                for dim, size in dimensions.items():
                    _id(dim, 'dimension ID')
                    if not _integer(size, 'dimension size', 536870912):
                        raise OutputAccessError('Dimensions must have positive exact sizes')
                rows = 0
            else:
                rows = _integer(item['row_count'], 'row_count', 536870912)
                if not rows:
                    raise OutputAccessError('Positive row count required')
                dimensions = {'row': rows}
            if not isinstance(variables, list) or not 1 <= len(variables) <= 128:
                raise OutputAccessError('1..128 real variables required')
            schemas = {}
            used_dimensions = set()
            added = 0
            for variable in variables:
                if not isinstance(variable, dict) or set(variable) != {'variable_id', 'schema'}:
                    raise OutputAccessError('Variable requires only its ID and canonical schema')
                vid = _id(variable['variable_id'], 'variable ID')
                schema = variable['schema']
                if vid in schemas or not isinstance(schema, dict):
                    raise OutputAccessError('Unique variables with canonical schemas required')
                dtype = schema.get('dtype')
                if not isinstance(dtype, str) or dtype not in WIDTHS:
                    raise OutputAccessError('Unsupported typed numeric dtype')
                if explicit:
                    ids = schema.get('dimension_ids')
                    if not isinstance(ids, list) or not 1 <= len(ids) <= 16 or any(
                            not isinstance(dim, str) or dim not in dimensions for dim in ids) or len(set(ids)) != len(ids):
                        raise OutputAccessError('Variable requires unique admitted dimension IDs')
                    shape = [dimensions[dim] for dim in ids]
                    rows = max(rows, shape[0])
                else:
                    ids, shape = ['row'], [rows]
                for key, expected in dict(variable_id=vid, rank=len(ids), dimension_ids=ids, shape=shape).items():
                    if key in schema and (schema[key] != expected or (key == 'rank' and type(schema[key]) is not int)):
                        raise OutputAccessError('Contradictory numeric schema: ' + key)
                    if key == 'shape' and key in schema and any(type(size) is not int for size in schema[key]):
                        raise OutputAccessError('Variable shape must use exact integer sizes')
                    schema[key] = expected
                if schema.get('order', 'F') != 'F' or schema.get('endian', 'little') != 'little':
                    raise OutputAccessError('Typed Acquisition buffers require little-endian column-major values')
                used_dimensions.update(ids)
                elements = 1
                for size in shape:
                    elements *= size
                    if elements > 536870912 // WIDTHS[dtype]:
                        raise OutputAccessError('Variable exceeds the existing 512 MiB transport bound')
                count = elements * WIDTHS[dtype]
                if count > 536870912:
                    raise OutputAccessError('Variable exceeds the existing 512 MiB transport bound')
                schemas[vid] = dict(schema=schema, expected_bytes=count)
                added += count
            if used_dimensions != set(dimensions):
                raise OutputAccessError('Every declared dimension must belong to a real Variable')
            if added > self._budget - self._bytes:
                raise OutputAccessError('Aggregate typed output byte budget exceeded')
            if self._validate_definition(_clone(item)) is not True:
                raise OutputAccessError('CORE publication preflight did not admit this output')
            self._check()
            output_id = secrets.token_hex(16)
            buffers = {}
            self._outputs[output_id] = dict(definition=definition, row_count=rows, buffers=buffers, finished=False)
            if explicit:
                self._outputs[output_id]['dimensions'] = dimensions
            # Partial allocation stays in the owned Resource and cannot be
            # published; caller reaps the actor then releases that Resource.
            for vid, schema in schemas.items():
                name = secrets.token_hex(24) + '.bin'
                fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                             0o600, dir_fd=self._root_fd)
                try:
                    info = os.fstat(fd)
                    buffers[vid] = dict(schema=schema['schema'], name=name, fd=fd,
                        identity=(info.st_dev, info.st_ino), expected_bytes=schema['expected_bytes'],
                        authorized_bytes=0, sha256=None, pending_chunk=None)
                    fd = None
                finally:
                    if fd is not None:
                        os.close(fd)
            self._dataset_ids.add(dataset_id)
            self._bytes += added
            return dict(output_id=output_id,
                variables=[dict(variable_id=vid, byte_count=b['expected_bytes']) for vid, b in buffers.items()],
                _private_buffers=[dict(variable_id=vid, buffer_id=b['name'][:-4], path=str(self._root / b['name']),
                    device=b['identity'][0], inode=b['identity'][1], expected_bytes=b['expected_bytes']) for vid, b in buffers.items()])
        except BaseException:
            self._failed = True
            raise

    def authorize_write(self, request):
        try:
            self._check()
            if not isinstance(request, dict) or set(request) not in (
                    {'output_id', 'variable_id', 'offset', 'byte_count'},
                    {'output_id', 'variable_id', 'offset', 'byte_count', 'chunk_sha256'}):
                raise OutputAccessError('Output writes carry bounded metadata only')
            output, buffer = self._buffer(request['output_id'], request['variable_id'])
            offset = _integer(request['offset'], 'offset', 536870912)
            count = _integer(request['byte_count'], 'byte_count', 65536)
            if self._write_calls >= 262144 or output['finished'] or not count or offset != buffer['authorized_bytes'] or count > buffer['expected_bytes'] - offset:
                raise OutputAccessError('Output writes must be bounded, sequential and in range')
            if self._stat(buffer).st_size != offset:
                raise OutputAccessError('Prior authorized write did not complete exactly')
            self._verify_pending(buffer)
            if 'chunk_sha256' in request and (not isinstance(request['chunk_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', request['chunk_sha256'])):
                raise OutputAccessError('Malformed chunk SHA-256')
            buffer['authorized_bytes'] += count
            buffer['pending_chunk'] = (offset, count, request.get('chunk_sha256'))
            self._write_calls += 1
            return dict(authorized=True, offset=offset, byte_count=count)
        except BaseException:
            self._failed = True
            raise

    def _verify_pending(self, buffer):
        pending = buffer['pending_chunk']
        if pending is None or pending[2] is None:
            return
        fd = os.open(buffer['name'], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=self._root_fd)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or (info.st_dev, info.st_ino) != buffer['identity']:
                raise OutputAccessError('Typed chunk identity changed')
            data = os.pread(fd, pending[1], pending[0])
            if len(data) != pending[1] or hashlib.sha256(data).hexdigest() != pending[2]:
                raise OutputAccessError('Authorized typed chunk SHA-256 differs')
        finally:
            os.close(fd)

    def _digest(self, buffer):
        before = self._stat(buffer)
        if before.st_size != buffer['expected_bytes'] or buffer['authorized_bytes'] != buffer['expected_bytes']:
            raise OutputAccessError('Typed variable is incomplete or has unauthorized bytes')
        self._verify_pending(buffer)
        fd = os.open(buffer['name'], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=self._root_fd)
        try:
            opened = os.fstat(fd)
            if (opened.st_dev, opened.st_ino) != buffer['identity']:
                raise OutputAccessError('Typed buffer changed while opening')
            digest = hashlib.sha256()
            total = 0
            while total < before.st_size:
                self._check()
                chunk = os.read(fd, min(65536, before.st_size - total))
                if not chunk:
                    raise OutputAccessError('Typed buffer ended during verification')
                digest.update(chunk)
                total += len(chunk)
            after = self._stat(buffer)
            identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
            if identity(before) != identity(after) or identity(opened) != identity(os.fstat(fd)):
                raise OutputAccessError('Typed buffer changed during verification')
            return digest.hexdigest()
        finally:
            os.close(fd)

    def finish(self, request):
        try:
            self._check()
            if not isinstance(request, dict) or set(request) != {'output_id', 'variables'}:
                raise OutputAccessError('Exact output completion receipt required')
            output_id = request['output_id']
            if not isinstance(output_id, str) or output_id not in self._outputs:
                raise OutputAccessError('Output is outside this request')
            output = self._outputs[output_id]
            receipts = request['variables']
            if output['finished'] or not isinstance(receipts, list) or len(receipts) != len(output['buffers']):
                raise OutputAccessError('Exactly one completion per real variable required')
            seen = set()
            for receipt in receipts:
                if not isinstance(receipt, dict) or set(receipt) != {'variable_id', 'byte_count', 'sha256'}:
                    raise OutputAccessError('Malformed typed completion receipt')
                vid = receipt['variable_id']
                if not isinstance(vid, str) or vid in seen or vid not in output['buffers']:
                    raise OutputAccessError('Duplicate or unrelated variable completion')
                seen.add(vid)
                buffer = output['buffers'][vid]
                if type(receipt['byte_count']) is not int or receipt['byte_count'] != buffer['expected_bytes'] or receipt['sha256'] != self._digest(buffer):
                    raise OutputAccessError('Typed completion byte count or SHA-256 differs')
                buffer['sha256'] = receipt['sha256']
            output['finished'] = True
            return dict(output_id=output_id, state='PROVISIONAL_UNTIL_ACTOR_REAP')
        except BaseException:
            self._failed = True
            raise

    def seal(self, *, actor_reaped):
        try:
            self._check()
            if actor_reaped is not True or not self._outputs or any(not o['finished'] for o in self._outputs.values()):
                raise OutputAccessError('Complete outputs and actual actor reaping required')
            result = []
            for output in self._outputs.values():
                variables = []
                for vid, buffer in output['buffers'].items():
                    if self._digest(buffer) != buffer['sha256']:
                        raise OutputAccessError('Typed output changed before final sealing')
                    variables.append(dict(variable_id=vid, schema=_clone(buffer['schema']), path=str(self._root / buffer['name']), sha256=buffer['sha256']))
                plan = dict(definition=_clone(output['definition']), row_count=output['row_count'], variables=variables)
                if 'dimensions' in output:
                    plan['dimensions'] = _clone(output['dimensions'])
                result.append(plan)
            self._check()
            self._sealed = True
            return result
        except BaseException:
            self._failed = True
            raise
        finally:
            self.close()

    def finished_output_ids(self):
        self._check()
        if not self._outputs or any(not output['finished'] for output in self._outputs.values()):
            raise OutputAccessError('All declared outputs must have exact completion receipts')
        return tuple(self._outputs)

    def close(self):
        if not self._closed:
            self._closed = True
            for output in self._outputs.values():
                for buffer in output['buffers'].values():
                    os.close(buffer['fd'])
            os.close(self._root_fd)
