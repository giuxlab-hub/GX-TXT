# SPDX-License-Identifier: GPL-3.0-or-later
"""Encode one inert documented-v2 frame for historical snapshot compatibility."""
import hashlib
from pathlib import Path
import struct
import sys

if len(sys.argv) != 5:
    raise SystemExit('usage: frame_fixture.py PATH IDENTITY REVISION PAYLOAD_FILE')
path, identity, revision, payload_file = sys.argv[1:]
path = Path(path)
if path.exists() or Path(str(path)+'.checkpoint').exists():
    raise SystemExit('Fresh fixture path required')
identity = identity.encode('utf-8')
header = b'GXH17\x00\x02\n' + struct.pack('<I', len(identity)) + identity
header += hashlib.sha256(header).digest()
payload = Path(payload_file).read_bytes()
prefix = struct.pack('<QI', int(revision), len(payload)) + bytes(32)
payload_digest = hashlib.sha256(prefix+payload).digest()
frame_header = prefix+payload_digest
frame = frame_header+hashlib.sha256(frame_header).digest()+payload
Path(str(path)+'.checkpoint').write_bytes(header+frame)
path.write_bytes(header)
