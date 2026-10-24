# SPDX-License-Identifier: GPL-3.0-or-later
"""Controlled valid-ZIP/foreign-History-owner fixture; no source Session writes."""
import hashlib
import struct
import sys
import zipfile
from pathlib import Path
archive, output, document, generation = sys.argv[1:]
assert not Path(output).exists()
with zipfile.ZipFile(archive) as z:
    entries = [(i, z.read(i.filename)) for i in z.infolist()]
name = f'session/metadata/history/{document}.preparation.gxh.checkpoint'
original = next(data for info, data in entries if info.filename == name)
length, = struct.unpack('<I', original[8:12])
identity = original[12:12+length]
old = generation.encode()
assert old in identity
new = (b'X' if old[:1] != b'X' else b'Y') + old[1:]
identity = identity.replace(old, new, 1)
changed = original[:12] + identity
changed += hashlib.sha256(changed).digest() + original[12+length+32:]
old_hash, new_hash = hashlib.sha256(original).hexdigest(), hashlib.sha256(changed).hexdigest()
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for info, data in entries:
        if info.filename == name:
            data = changed
        elif info.filename == 'gxtxt-session-package.ini':
            assert old_hash.encode() in data
            data = data.replace(old_hash.encode(), new_hash.encode())
        z.writestr(info, data)
