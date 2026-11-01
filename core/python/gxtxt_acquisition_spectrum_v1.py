# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixed CORE CSV/JCAMP decoder over an existing Acquisition SourceGrant.

No authored path/helper selection, source FD handoff, Library access or output
authority. Request-local parsed pages are inert source data; the existing
prepared-output/publication owners still validate every canonical output.
"""
from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import secrets
import re

import scientific_spectrum_import as parser


class _GrantedBytes:
    """Only the read interface used by the common parser; never a real path."""

    def __init__(self, content, name, identity):
        self._content, self.name, self._identity = content, name, identity

    def resolve(self):
        return self._identity

    def open(self, mode, encoding=None, newline=None):
        if mode == 'rb':
            return io.BytesIO(self._content)
        if mode == 'r':
            return io.TextIOWrapper(io.BytesIO(self._content), encoding=encoding, newline=newline)
        raise ValueError('Granted scientific source is read-only')

    def read_text(self, encoding):
        return self._content.decode(encoding)


class AcquisitionSpectrumPages:
    SOURCE_BYTES = 33554432
    SAMPLES = 1000000
    PARSES = 4
    PAGE_ROWS = 2048
    CONTROL_BYTES = 49152

    def __init__(self, sources, check, validate_value=None):
        self.sources, self.check = sources, check
        self.validate_value = validate_value
        self._parsed = {}
        self._samples = 0

    @staticmethod
    def _uint(value, maximum, label):
        if type(value) is not int or not 0 <= value <= maximum:
            raise ValueError('Invalid scientific source ' + label)
        return value

    @classmethod
    def _options(cls, value):
        fields = {'spectrum_id', 'display_name', 'spectrum_kind', 'entity_id',
                  'x_quantity', 'x_unit', 'y_quantity', 'y_representation', 'y_unit',
                  'x_column', 'y_column', 'header', 'delimiter', 'metadata', 'provenance'}
        if not isinstance(value, dict) or set(value) - fields:
            raise ValueError('Scientific source options require finite documented fields')
        result = dict(value)
        for key, item in result.items():
            if key in {'metadata', 'provenance'}:
                if not isinstance(item, dict) or len(item) > 128 or any(
                        not isinstance(k, str) or not k or not isinstance(v, str)
                        or '\x00' in k or '\x00' in v for k, v in item.items()):
                    raise ValueError('Scientific source annotations require bounded text maps')
                if key == 'metadata' and any(k.startswith('jcamp.') for k in item):
                    raise ValueError('Scientific source annotations cannot replace original JCAMP headers')
                if key == 'provenance' and set(item) & {
                        'source_sha256', 'source_filename', 'source_format', 'parser'}:
                    raise ValueError('Scientific source provenance cannot replace CORE source identity')
            elif not isinstance(item, str) or '\x00' in item:
                raise ValueError('Scientific source option values must be text')
        if len(json.dumps(result, ensure_ascii=False, allow_nan=False).encode()) > cls.CONTROL_BYTES:
            raise ValueError('Scientific source options exceed 48 KiB')
        return result

    def parse(self, args):
        self.check()
        if not isinstance(args, dict) or set(args) != {'source_index', 'format', 'options'}:
            raise ValueError('Scientific source parse requires index, format and options')
        index = self._uint(args['source_index'], 63, 'index')
        if args['format'] not in ('csv', 'jcamp'):
            raise ValueError('Scientific source format must be csv or jcamp')
        options = self._options(args['options'])
        if not callable(self.validate_value):
            raise ValueError('Scientific Spectrum value owner is unavailable')
        validation_options = dict(options)
        descriptors = self.sources.descriptors()
        if index >= len(descriptors):
            raise ValueError('Scientific source is outside the admitted request')
        source = descriptors[index]
        if not 0 < source['size'] <= self.SOURCE_BYTES:
            raise ValueError('Scientific source exceeds the 32 MiB parser bound')
        if len(self._parsed) >= self.PARSES or self._samples >= self.SAMPLES:
            raise ValueError('Scientific source request parser budget exhausted')
        content = bytearray()
        while len(content) < source['size']:
            self.check()
            chunk = self.sources.read(index, len(content), min(65536, source['size'] - len(content)))
            content.extend(chunk['data'])
        digest = hashlib.sha256(content).hexdigest()
        if source['source_sha256'] is not None and digest != source['source_sha256']:
            raise ValueError('Scientific source SHA differs from its reviewed source')
        identity = 'acquisition-source:' + self.sources._scope['request_id'] + ':' + str(index)
        granted = _GrantedBytes(bytes(content), source['logical_name'], identity)
        metadata = options.pop('metadata', {})
        provenance = options.pop('provenance', {})
        function = parser.parse_csv if args['format'] == 'csv' else parser.parse_jcamp
        fields, metadata, provenance, pairs = function(granted, options, metadata, provenance,
                                                      max_samples=self.SAMPLES - self._samples)
        self.check()
        self.sources.descriptors()  # same actual FD/path identity after parsing
        validation = self.validate_value(dict(source_index=index, format=args['format'],
            options=validation_options, source_sha256=digest, row_count=len(pairs), source_identity=identity))
        if (not isinstance(validation, dict) or set(validation) != {
                'sample_count', 'spectrum_hash', 'source_hash', 'x_ordering', 'x_min', 'x_max'}
                or validation['source_hash'] != digest
                or str(validation['sample_count']) != str(len(pairs))
                or not isinstance(validation['spectrum_hash'], str)
                or not re.fullmatch('[0-9a-f]{64}', validation['spectrum_hash'])
                or validation['x_ordering'] not in {'ascending', 'descending'}):
            raise ValueError('Scientific Spectrum value owner returned a different source identity')
        self.check()
        self.sources.descriptors()
        fields.update(validation)
        token = secrets.token_hex(32)
        reply = dict(parse_token=token, row_count=len(pairs), source_index=index,
                     source_sha256=digest, fields=fields, metadata=metadata, provenance=provenance,
                     value_qualification='SCIENTIFIC_SPECTRUM_API_v1_VALIDATED',
                     parser_sha256=hashlib.sha256(Path(parser.__file__).read_bytes()).hexdigest())
        if len(json.dumps(reply, ensure_ascii=False, allow_nan=False).encode()) > self.CONTROL_BYTES:
            raise ValueError('Scientific source metadata exceeds 48 KiB; no truncated result')
        self._parsed[token] = pairs
        self._samples += len(pairs)
        return reply

    def read(self, args):
        self.check()
        if not isinstance(args, dict) or set(args) != {'parse_token', 'offset', 'count'}:
            raise ValueError('Scientific source page requires exact token, offset and count')
        token = args['parse_token']
        if not isinstance(token, str) or token not in self._parsed:
            raise ValueError('Scientific source parse token is unavailable in this request')
        pairs = self._parsed[token]
        offset = self._uint(args['offset'], len(pairs), 'page offset')
        count = self._uint(args['count'], self.PAGE_ROWS, 'page count')
        if count == 0:
            raise ValueError('Scientific source pages require 1..2048 rows')
        self.sources.descriptors()  # does not bypass source revocation after parse
        page = pairs[offset:offset + count]
        return dict(offset=offset, row_count=len(page), total_rows=len(pairs),
                    eof=offset + len(page) == len(pairs),
                    x=[x for x, _ in page], y=[y for _, y in page])

    def close(self):
        self._parsed.clear()
        self._samples = 0
