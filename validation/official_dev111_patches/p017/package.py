#!/usr/bin/env python3
"""Local-only incremental P017 package and P016 application verification."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile

baseline, candidate, stage, reports = map(lambda p: Path(p).resolve(), sys.argv[1:])
if stage.exists():
    raise SystemExit('NEW_STAGE must not exist')
if baseline == candidate or not (baseline / 'VERSION.txt').is_file():
    raise SystemExit('Distinct completed local baseline and candidate required')

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def inventory(root):
    result = {}
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if d not in {'.git', '__pycache__'})
        for name in sorted(files):
            if name == '.git':
                continue
            p = Path(directory) / name
            if p.suffix in {'.pyc', '.o'} or name.endswith('.pending'):
                continue
            rel = p.relative_to(root).as_posix()
            if p.is_symlink():
                result[rel] = ('link', os.readlink(p))
            else:
                result[rel] = ('file', sha(p))
    return result

before, after = inventory(baseline), inventory(candidate)
provenance = json.loads((reports / 'PROVENANCE.json').read_text())
for rel, expected in provenance['source_and_tested_binary_pins'].items():
    if after.get(rel) != ('file', expected):
        raise SystemExit('Final tested source/binary pin mismatch ' + rel)
if sha(Path(provenance['baseline_archive'])) != provenance['baseline_archive_sha256']:
    raise SystemExit('Original P016 archive changed')
removed = sorted(set(before) - set(after))
if removed:
    raise SystemExit('Unexpected removal; use an explicit reviewed removal contract: ' + str(removed))
changes = [p for p in sorted(after) if before.get(p) != after[p]]
if any(after[p][0] != 'file' for p in changes):
    raise SystemExit('Changed symlinks require explicit handling')
if any('GX-TXT_REMAINING_WORK_TODO' in p for p in changes):
    raise SystemExit('Authoritative TODO must not change')
stage.mkdir(parents=True)
payload = stage / 'payload'
notes = payload / 'patch_notes' / 'DEV111-P017'
notes.mkdir(parents=True)
manifest = []
for rel in changes:
    target = payload / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidate / rel, target)
    manifest.append(dict(path=rel, action='replace' if rel in before else 'add',
                         before_sha256=before[rel][1] if rel in before else None,
                         after_sha256=after[rel][1], bytes=target.stat().st_size))
for source in sorted(reports.rglob('*')):
    if source.is_file():
        target = notes / source.relative_to(reports)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
(notes / 'FILES.json').write_text(json.dumps(dict(patch='DEV111-P017',
    baseline=str(baseline), candidate=str(candidate), changed_files=manifest), indent=2) + '\n')
(notes / 'CHANGED_FILES.txt').write_text('\n'.join(changes) + '\n')
hashes = {p.relative_to(payload).as_posix(): sha(p)
          for p in sorted(payload.rglob('*')) if p.is_file()}
(notes / 'PAYLOAD_SHA256SUMS').write_text(''.join(f'{digest}  {rel}\n' for rel, digest in hashes.items()))
archive = stage / 'DEV111-P017.zip'
with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as output:
    for p in sorted(payload.rglob('*')):
        if p.is_file():
            output.write(p, p.relative_to(payload).as_posix())
(stage / 'DEV111-P017.zip.sha256').write_text(f'{sha(archive)}  {archive.name}\n')
# Sparse application verification reads exact P016 preimages, extracts the ZIP
# into a fresh tree and verifies every postimage. Unchanged paths are proven by
# the complete tree inventories above; there is no system installation.
apply = stage / 'apply-verification'
apply.mkdir()
for row in manifest:
    if row['before_sha256']:
        p = apply / row['path']
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(baseline / row['path'], p)
        if sha(p) != row['before_sha256']:
            raise SystemExit('Baseline preimage mismatch ' + row['path'])
with zipfile.ZipFile(archive) as source:
    if source.testzip():
        raise SystemExit('ZIP CRC error')
    source.extractall(apply)
for row in manifest:
    if sha(apply / row['path']) != row['after_sha256']:
        raise SystemExit('Application postimage mismatch ' + row['path'])
receipt = dict(status='PASS', patch='DEV111-P017', changed_file_count=len(manifest),
    unchanged_file_count=len(after)-len(manifest), removed_files=removed,
    zip_sha256=sha(archive), zip_bytes=archive.stat().st_size,
    baseline_inventory_sha256=hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
    source_binary_match='PASS: candidate matches final tested source/binary pins',
    source_and_tested_binary_pins=provenance['source_and_tested_binary_pins'],
    baseline_archive_sha256=provenance['baseline_archive_sha256'],
    install_performed=False)
(stage / 'VERIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
