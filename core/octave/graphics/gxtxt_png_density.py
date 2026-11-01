#!/usr/bin/env python3
"""Set derived PNG physical density without changing any pixel/IDAT bytes."""
# SPDX-License-Identifier: GPL-3.0-or-later
import os
from pathlib import Path
import stat
import struct
import sys
import zlib


def set_density(path, dpi):
    original = path.stat(follow_symlinks=False)
    ppm = round(dpi / 0.0254)
    if not stat.S_ISREG(original.st_mode) or original.st_nlink != 1 or not 0 < ppm <= 0xffffffff:
        raise ValueError('Expected ordinary owned PNG and finite density')
    temporary = path.with_name(path.name + '.density.' + str(os.getpid()))
    created = False
    try:
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as source:
            opened = os.fstat(source.fileno())
            if (opened.st_dev, opened.st_ino) != (original.st_dev, original.st_ino):
                raise ValueError('Derived PNG identity changed')
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, stat.S_IMODE(original.st_mode))
            os.fchmod(descriptor, stat.S_IMODE(original.st_mode))
            created = True
            with os.fdopen(descriptor, 'wb') as target:
                if source.read(8) != b'\x89PNG\r\n\x1a\n':
                    raise ValueError('Invalid PNG signature')
                target.write(b'\x89PNG\r\n\x1a\n')
                first = True
                while True:
                    header = source.read(8)
                    if len(header) != 8:
                        raise ValueError('Incomplete PNG')
                    length, kind = struct.unpack('>I4s', header)
                    if first and (kind != b'IHDR' or length != 13):
                        raise ValueError('Expected PNG IHDR')
                    if kind != b'pHYs':
                        target.write(header)
                    checksum = zlib.crc32(kind)
                    remaining = length
                    while remaining:
                        data = source.read(min(65536, remaining))
                        if not data:
                            raise ValueError('Truncated PNG chunk')
                        remaining -= len(data)
                        checksum = zlib.crc32(data, checksum)
                        if kind != b'pHYs':
                            target.write(data)
                    crc = source.read(4)
                    if len(crc) != 4 or struct.unpack('>I', crc)[0] != checksum & 0xffffffff:
                        raise ValueError('PNG chunk checksum mismatch')
                    if kind != b'pHYs':
                        target.write(crc)
                    if first:
                        density = struct.pack('>IIB', ppm, ppm, 1)
                        target.write(struct.pack('>I4s', 9, b'pHYs') + density + struct.pack('>I', zlib.crc32(b'pHYs' + density) & 0xffffffff))
                        first = False
                    if kind == b'IEND':
                        if length or source.read(1):
                            raise ValueError('Invalid PNG ending')
                        break
                after = path.stat(follow_symlinks=False)
                if (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) != (original.st_dev, original.st_ino, original.st_size, original.st_mtime_ns):
                    raise ValueError('Derived PNG changed during density update')
        os.replace(temporary, path)
        created = False
    finally:
        if created:
            temporary.unlink()


if __name__ == '__main__':
    set_density(Path(sys.argv[1]), int(sys.argv[2]))
