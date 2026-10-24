#!/usr/bin/env python3
"""New-only P017 release and paired archive/expanded mirrors; no activation."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

stage, release, mirrors = map(lambda p: Path(p).resolve(), sys.argv[1:])
archive = stage / 'DEV111-P017.zip'
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
receipt = json.loads((stage / 'VERIFICATION.json').read_text())
if receipt['status'] != 'PASS' or receipt['zip_sha256'] != digest:
    raise SystemExit('Staged verification/hash mismatch')
mirror_archive = mirrors / 'framework' / 'archives' / 'patches' / archive.name
expanded = mirrors / 'framework' / 'expanded' / 'patches' / 'DEV111-P017'
if any(p.exists() for p in (release, mirror_archive, expanded)):
    raise SystemExit('P017 destinations must all be new; refusing overwrite')
release.mkdir(parents=True)
for name in ('DEV111-P017.zip', 'DEV111-P017.zip.sha256', 'VERIFICATION.json'):
    shutil.copy2(stage / name, release / name)
mirror_archive.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(archive, mirror_archive)
shutil.copy2(stage / 'DEV111-P017.zip.sha256', Path(str(mirror_archive)+'.sha256'))
expanded.mkdir(parents=True)
with zipfile.ZipFile(archive) as source:
    if source.testzip():
        raise SystemExit('ZIP CRC error')
    source.extractall(expanded)
    for row in source.infolist():
        if row.is_dir():
            continue
        expected = hashlib.sha256(source.read(row.filename)).hexdigest()
        actual = hashlib.sha256((expanded / row.filename).read_bytes()).hexdigest()
        if expected != actual:
            raise SystemExit('Expanded mirror mismatch ' + row.filename)
if hashlib.sha256(mirror_archive.read_bytes()).hexdigest() != digest:
    raise SystemExit('Archive mirror mismatch')
result = dict(status='PASS', release=str(release), archive=str(mirror_archive),
              expanded=str(expanded), sha256=digest, activation=False)
(release / 'DEPOSIT.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
