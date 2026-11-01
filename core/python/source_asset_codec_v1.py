"""Strict inert PNG closure codec; no resource allocation, registry or grants."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import zlib

SCHEMA = 'gxtxt.source_asset.v1'
INDEX_SCHEMA = 'gxtxt.source_asset_index.v1'
MAX_IMAGE = 4 * 1024 * 1024
MAX_ASSETS = 256
MAX_TOTAL = 16 * 1024 * 1024
MAX_INDEX = 1024 * 1024
HEX = re.compile(r'[0-9a-f]{64}\Z')
NAME = re.compile(r'[A-Za-z][A-Za-z0-9_.-]{0,95}\Z')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def loads(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'Duplicate asset JSON field')
            result[key] = value
        return result
    require(isinstance(raw, bytes) and len(raw) <= MAX_INDEX, 'Bounded asset index required')
    return json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=unique)

def _png_image_data(parts, width, height, depth, colour, interlace):
    """Check the bounded filtered stream, without rendering or changing pixels."""
    # PNG 3 sections 7--10: packed rows, Adam7 reduced images, one zlib stream.
    # https://www.w3.org/TR/2025/REC-png-3-20250624/
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    passes = ((0, 0, 1, 1),) if not interlace else (
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
        (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))
    rows = []
    for x, y, dx, dy in passes:
        columns = max(0, (width - x + dx - 1) // dx)
        count = max(0, (height - y + dy - 1) // dy)
        if columns and count:
            rows.extend([((columns * channels * depth + 7) // 8)] * count)
    expected = sum(size + 1 for size in rows)
    scanlines = iter(rows)
    remaining = 0
    total = 0
    decoder = zlib.decompressobj()
    pending = b''.join(parts)
    try:
        while True:
            # Never use unbounded decompress/flush: even a tiny IDAT can expand
            # far past its IHDR budget. One extra byte detects excess output.
            block = decoder.decompress(pending, min(65536, expected - total + 1))
            total += len(block)
            require(total <= expected, 'PNG image data exceeds its scanline budget')
            position = 0
            while position < len(block):
                if not remaining:
                    size = next(scanlines, None)
                    require(size is not None, 'PNG has extra scanlines')
                    require(block[position] <= 4, 'Invalid PNG scanline filter')
                    position += 1
                    remaining = size
                used = min(remaining, len(block) - position)
                position += used
                remaining -= used
            require(not decoder.unused_data, 'Trailing PNG zlib data')
            if decoder.eof:
                require(not decoder.unconsumed_tail and total == expected
                        and remaining == 0 and next(scanlines, None) is None,
                        'PNG image data does not match its scanlines')
                break
            tail = decoder.unconsumed_tail
            require(block or len(tail) < len(pending), 'Truncated PNG zlib stream')
            pending = tail
    except zlib.error as error:
        raise ValueError('Invalid PNG IDAT zlib stream') from error

def png_dimensions(raw):
    require(isinstance(raw, bytes) and 45 <= len(raw) <= MAX_IMAGE
            and raw[:8] == b'\x89PNG\r\n\x1a\n', 'Bounded PNG required')
    offset = 8; first = True; image = False; ended = False; dimensions = None
    image_parts = []; image_closed = False
    while offset < len(raw):
        require(offset + 12 <= len(raw), 'Truncated PNG chunk')
        size = struct.unpack('>I', raw[offset:offset+4])[0]
        kind = raw[offset+4:offset+8]; end = offset + 12 + size
        require(end <= len(raw) and re.fullmatch(b'[A-Za-z]{4}', kind), 'Invalid PNG chunk')
        data = raw[offset+8:end-4]
        require(zlib.crc32(kind + data) & 0xffffffff == struct.unpack('>I', raw[end-4:end])[0], 'PNG CRC differs')
        if first:
            require(kind == b'IHDR' and size == 13, 'PNG IHDR required first')
            width, height, depth, colour, compression, filtering, interlace = struct.unpack('>IIBBBBB', data)
            require(1 <= width <= 4096 and 1 <= height <= 4096 and compression == filtering == 0
                    and interlace in (0, 1) and depth in {0:{1,2,4,8,16},2:{8,16},3:{1,2,4,8},4:{8,16},6:{8,16}}.get(colour,set()), 'Unsupported PNG header')
            dimensions = width, height
        else:
            require(kind != b'IHDR', 'Duplicate PNG header')
        if kind == b'IDAT':
            require(not image_closed, 'PNG IDAT chunks must be consecutive')
            image = True; image_parts.append(data)
        elif image:
            image_closed = True
        if kind == b'IEND':
            require(size == 0 and end == len(raw) and image, 'PNG requires final IEND after image data')
            ended = True
        offset = end; first = False
    require(ended, 'PNG IEND missing')
    _png_image_data(image_parts, width, height, depth, colour, interlace)
    return dimensions

def validate_asset(logical, record, raw):
    require(isinstance(logical, str) and NAME.fullmatch(logical), 'Invalid logical document asset name')
    required = {'sha256', 'size_bytes', 'metadata'}
    require(isinstance(record, dict) and set(record) in (required, required | {'origin_sha256'}), 'Unknown asset descriptor fields')
    require(isinstance(record['sha256'], str) and HEX.fullmatch(record['sha256'])
            and type(record['size_bytes']) is int and 0 < record['size_bytes'] <= MAX_IMAGE
            and len(raw) == record['size_bytes'] and sha(raw) == record['sha256'], 'Asset identity differs')
    if 'origin_sha256' in record:
        require(isinstance(record['origin_sha256'], str) and HEX.fullmatch(record['origin_sha256']), 'Invalid inert asset origin SHA')
    metadata = record['metadata']
    require(isinstance(metadata, dict) and set(metadata) == {'format','media_type','filename','role','width','height','scientific_authority','disposable'}, 'Asset metadata must use exact flat PNG fields')
    require(metadata['format'] == 'png' and metadata['media_type'] == 'image/png'
            and metadata['filename'] == logical
            and metadata['role'] == 'markdown_image' and metadata['scientific_authority'] is True
            and metadata['disposable'] is False and type(metadata['width']) is int
            and type(metadata['height']) is int, 'Invalid PNG scientific metadata')
    require(png_dimensions(raw) == (metadata['width'], metadata['height']), 'PNG header dimensions differ')
    return record

def validate_index(index_bytes, blobs):
    index = loads(index_bytes)
    require(isinstance(index, dict) and set(index) == {'schema','assets'} and index['schema'] == INDEX_SCHEMA
            and isinstance(index['assets'], dict) and len(index['assets']) <= 32, 'Bounded exact asset index required')
    require(isinstance(blobs, dict) and len(blobs) <= MAX_ASSETS and all(isinstance(v, bytes) for v in blobs.values()), 'Bounded asset blobs required')
    expected = set()
    for logical, record in index['assets'].items():
        require(isinstance(record, dict) and isinstance(record.get('sha256'), str), 'Invalid asset descriptor')
        key = record['sha256']; expected.add(key)
        require(key in blobs, 'Missing PNG blob')
        validate_asset(logical, record, blobs[key])
    require(expected == set(blobs) and sum(map(len, blobs.values())) <= MAX_TOTAL, 'Extra PNG blobs or aggregate bound exceeded')
    return {'assets': index['assets'], 'blobs': blobs}

def _directory(path):
    state = path.lstat()
    require(stat.S_ISDIR(state.st_mode) and stat.S_IMODE(state.st_mode) == 0o700, 'Asset directory must be ordinary mode0700')

def _file(path, maximum):
    state = path.lstat()
    require(stat.S_ISREG(state.st_mode) and state.st_nlink == 1 and stat.S_IMODE(state.st_mode) == 0o444
            and state.st_size <= maximum, 'Asset file must be bounded unlinked regular mode0444')
    with path.open('rb') as stream:
        before = stream.fileno(); opened = os.fstat(before)
        raw = stream.read(maximum + 1); after = os.fstat(before)
    fields = lambda s: (s.st_dev,s.st_ino,s.st_mode,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    require(fields(state) == fields(opened) == fields(after) and len(raw) <= maximum, 'Asset changed while reading')
    return raw

def read_plan(directory, index_sha256, index_size):
    root = Path(os.path.abspath(directory))
    require(all(not p.is_symlink() for p in [root, *root.parents]), 'Linked asset plan ancestor')
    _directory(root)
    require({p.name for p in root.iterdir()} == {'index.json','blobs'}, 'Unexpected asset plan member')
    require(isinstance(index_sha256, str) and HEX.fullmatch(index_sha256)
            and type(index_size) is int and 0 < index_size <= MAX_INDEX, 'Exact asset index pins required')
    raw = _file(root / 'index.json', MAX_INDEX)
    require(len(raw) == index_size and sha(raw) == index_sha256, 'Asset index pins differ')
    blob_root = root / 'blobs'; _directory(blob_root); blobs = {}
    for path in blob_root.iterdir():
        require(re.fullmatch(r'[0-9a-f]{64}\.png', path.name) and len(blobs) < MAX_ASSETS, 'Invalid bounded PNG member')
        blobs[path.stem] = _file(path, MAX_IMAGE)
        require(sum(map(len, blobs.values())) <= MAX_TOTAL, 'Asset plan aggregate bound exceeded')
    return validate_index(raw, blobs)
