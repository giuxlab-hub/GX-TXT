#!/usr/bin/env python3
"""Deterministic, lossless DEV112 offline distribution of accepted P035 bytes.

 No module execution, compilation, resealing, developer Registry copying, policy changes or
old installation writes. Published originals are reused only after byte closure.
"""
import argparse
import importlib.util
import configparser
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tarfile
import zipfile

BASE = 'ce34988db2c7500b60f7235b237b2fdb67e5d434'
VERSION = '0.9.8.10-dev-112'
TODO_SHA = 'af36ec62f5f699c551b532d698980955e762585e6c0867d4a4220934fc2772fb'
RELEASES = Path('/srv/gxtxt/releases/GXTXT')
MODULE_ARCHIVES = RELEASES / 'external_plugins/archives'
P035 = RELEASES / 'framework/archives/patches/DEV111-P035.zip'
P035_SHA = '8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d'
MANDATORY = {
 'viewer.curve_digitizer': ('viewer.curve_digitizer_2.0.26_dev111_p032_standalone.zip', 'ded07ad9a85c79f68fa53866edef9a4a186ef06546882940526b56d9894a1198'),
 'preview.curve_digitizer': ('preview.curve_digitizer_0.1.12_dev111_p032_REQUIRES_CORE_BRIDGE_022.zip', '57a0ae932bef79c64d597299581f7319ed30548bc0c2a7846bcace34c436c5b2'),
}
OWNER_CORE = {'gxtxt.ir_identify', 'gxtxt.ir_waveform', 'model.spice_build_validate'}
DEFINITION_MANIFEST_SHA = '126f1567aff8eefa873708f2d2546d8886f8e2dca99fc8eb10ffe44ce67cc819'
RUNTIME_ROOTS = {'app', 'core', 'docs', 'examples', 'plugins', 'services', 'third_party', 'tools', 'session_generator_libraries', 'distribution'}
SHIP_VALIDATION = {'validation/dev112_release/build.py', 'validation/dev112_release/prepare_registry.py', 'validation/dev112_release/SCRIPT_CATALOG.md'}
HISTORICAL_DOC_ROOTS = ('docs/development/', 'docs/reports/', 'docs/evidence/')
# Finite current manual/API references reviewed against accepted ce349. The
# task210 README has no inline assets. Historical report image chains are not
# runtime roots and must not pull entire past verification campaigns back in.
REQUIRED_DOC_REFERENCES = {
 'docs/evidence/dev053/mixed-cad.png',
 'docs/evidence/dev053/fresh-mixed-cad.png',
 'docs/development/task210/ic_baseline_form/README.md',
 'docs/development/additive_preview_acceptance368/MOLECULE_ACCEPTANCE.json',
}
ROOT_OMIT = {'.gitignore', 'DEV092_TECHNICAL_HANDOFF.md', 'GUI_CHANGE_VISUAL_REVIEW.md', 'GUI_CHANGE_VISUAL_REVIEW.md.sha256', 'SHA256SUMS'}
GENERATED = {'distribution/manifests/files.json', 'distribution/manifests/plugins.json', 'distribution/manifests/provenance.json', 'distribution/manifests/GENERATOR_INVENTORY.json'}
OPTIONAL_IR = ['tum.refimp.ftir.2022_1.0.0.zip', 'tum.refimp.ftir.training.2022_1.0.0.zip', 'nist.pnnl.ir.optical_constants.2017_1.0.0.zip', 'openspecy.example.nitrocellulose.2017_1.0.0.zip']
GEO_LIBRARY = ('gxtxt_geospatial_examples_1.0.1.zip', 'c41084762fc20568142e70a55439a4c59a6fc2e14c2621282c2635298ba3e35e')
REUSED_P035 = Path('/srv/gxtxt/releases/dev111/patches/0035-ir-viewer-teaching-cache-bridge')
REUSED_PINS = {
 'ACCEPTANCE_A.json': '6419bdf4c92d60a74ff65fc35bc6022127a93b0bb172d2b963179ea5c54f2322',
 'ACCEPTANCE_B.json': 'aa572552cc8504b908d549a538bd8af87759f3d116f2bd08e932b162ad71a68a',
 'HANDOFF.md': 'fe17bbaba2bff2ff44ecf5bc601f3c0b7b638bab80c1a46124fdebd820ba95fa',
}


def sha(data):
 return hashlib.sha256(data).hexdigest()


def digest(path):
 h = hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda: stream.read(1024 * 1024), b''):
   h.update(chunk)
 return h.hexdigest()


def relative(name):
 p = PurePosixPath(name)
 if not name or p.is_absolute() or '..' in p.parts or '\\' in name or str(p) != name or any(ord(c) < 32 for c in name):
  raise ValueError(f'Unsafe relative path: {name!r}')
 return p


def ini(data):
 parser = configparser.ConfigParser(interpolation=None, strict=False)
 parser.read_string(data.decode('utf-8-sig'))
 return {section: dict(parser.items(section)) for section in parser.sections()}


def git(repo, *args):
 return subprocess.check_output(['git', '-C', str(repo), *args])


class Objects:
 def __init__(self, repo, commit):
  self.repo, self.commit = repo, commit
  self.entries = {}
  for line in git(repo, 'ls-tree', '-rz', commit).split(b'\0'):
   if not line:
    continue
   head, path = line.split(b'\t', 1)
   mode, kind, oid = head.decode().split()
   name = path.decode('utf-8'); relative(name)
   if kind != 'blob' or mode not in ('100644', '100755'):
    raise ValueError(f'Unsupported Git object/mode (no symlinks/submodules): {name} {mode}')
   self.entries[name] = {'oid': oid, 'mode': 0o755 if mode == '100755' else 0o644}
  self.process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
  self.identities = {}

 def read(self, path):
  oid = self.entries[path]['oid']
  self.process.stdin.write((oid + '\n').encode()); self.process.stdin.flush()
  header = self.process.stdout.readline().decode().split()
  if len(header) != 3 or header[1] != 'blob':
   raise ValueError(f'Git blob unavailable: {path}')
  data = self.process.stdout.read(int(header[2]))
  if self.process.stdout.read(1) != b'\n':
   raise ValueError('Git batch framing error')
  return data

 def identity(self, path):
  oid = self.entries[path]['oid']
  if oid not in self.identities:
   data = self.read(path); self.identities[oid] = {'sha256': sha(data), 'size': len(data)}
  return dict(self.identities[oid], mode=self.entries[path]['mode'])

 def close(self):
  self.process.stdin.close(); self.process.stdout.close()
  if self.process.wait(timeout=15) != 0:
   raise ValueError('Git object reader failed')


def approved_source(repo, commit):
 if git(repo, 'status', '--porcelain', '--untracked-files=all').strip():
  raise ValueError('Repository must be clean; commit reviewed DEV112 metadata/tools first')
 full = git(repo, 'rev-parse', '--verify', commit + '^{commit}').decode().strip()
 if subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', BASE, full]).returncode:
  raise ValueError('Source must descend from accepted P035 ce349')
 ordinary = {'VERSION.txt', 'PATCH_LEVEL.txt', 'gxtxt_pipeline.tcl', 'GX-TXT_REMAINING_WORK_TODO.md', 'GX-TXT_REMAINING_WORK_TODO.md.sha256', 'SCRIPT_CATALOG.md', 'SCRIPT_CATALOG.md.sha256'}
 original_paths = set(filter(None, git(repo, 'ls-tree', '-rz', '--name-only', BASE).decode().split('\0')))
 changed = git(repo, 'diff', '--name-only', '-z', BASE, full).decode().split('\0')
 module_exceptions = {'plugins/modules/' + ident + '/module.ini' for ident in OWNER_CORE}
 module_exceptions |= {'plugins/modules/gxtxt.ir_waveform/SHA256SUMS.txt', 'plugins/modules/analysis.definition_demo/plugin-package.ini'}
 for name in filter(None, changed):
  approved_new = name not in original_paths and (name == 'INSTALL_DEV112.md' or name.startswith('distribution/') or name in SHIP_VALIDATION)
  if name not in ordinary and name not in module_exceptions and not approved_new:
   raise ValueError(f'Unapproved behavior/module/source change after P035: {name}')
 for ident in OWNER_CORE:
  path = 'plugins/modules/' + ident + '/module.ini'
  before = git(repo, 'show', BASE + ':' + path)
  after = git(repo, 'show', full + ':' + path)
  if after.count(b'core=1\n') != 1 or after.replace(b'core=1\n', b'', 1) != before or ini(after)['meta'].get('core') != '1':
   raise ValueError(f'Only the owner-authorized CORE insertion is allowed: {ident}')
 sums = 'plugins/modules/gxtxt.ir_waveform/SHA256SUMS.txt'
 old_desc = git(repo, 'show', BASE + ':plugins/modules/gxtxt.ir_waveform/module.ini')
 new_desc = git(repo, 'show', full + ':plugins/modules/gxtxt.ir_waveform/module.ini')
 expected_sums = git(repo, 'show', BASE + ':' + sums).replace((sha(old_desc) + '  ./module.ini').encode(), (sha(new_desc) + '  ./module.ini').encode())
 if git(repo, 'show', full + ':' + sums) != expected_sums:
  raise ValueError('Only waveform module.ini checksum line may change')
 if sha(git(repo, 'show', full + ':plugins/modules/analysis.definition_demo/plugin-package.ini')) != DEFINITION_MANIFEST_SHA:
  raise ValueError('Only the owner-approved definition Demo package manifest is allowed')
 old = git(repo, 'show', BASE + ':gxtxt_pipeline.tcl')
 new = git(repo, 'show', full + ':gxtxt_pipeline.tcl')
 if new != old.replace(b'variable version "0.9.8.10-dev-111"', b'variable version "0.9.8.10-dev-112"'):
  raise ValueError('gxtxt_pipeline.tcl change must be the exact version string only')
 if git(repo, 'show', full + ':VERSION.txt') != (VERSION + '\n').encode():
  raise ValueError('Source VERSION.txt must declare DEV112')
 if git(repo, 'show', full + ':PATCH_LEVEL.txt') != b'000\n':
  raise ValueError('Standalone DEV112 PATCH_LEVEL must be000')
 if sha(git(repo, 'show', full + ':GX-TXT_REMAINING_WORK_TODO.md')) != TODO_SHA:
  raise ValueError('Reconciled accepted TODO identity differs')
 if git(repo, 'show', full + ':GX-TXT_REMAINING_WORK_TODO.md.sha256').decode().strip() != TODO_SHA + '  GX-TXT_REMAINING_WORK_TODO.md':
  raise ValueError('TODO sidecar differs')
 catalog = git(repo, 'show', full + ':SCRIPT_CATALOG.md')
 if git(repo, 'show', full + ':SCRIPT_CATALOG.md.sha256').decode().strip() != sha(catalog) + '  SCRIPT_CATALOG.md':
  raise ValueError('Catalog sidecar differs')
 return full


def module_inventory(objects):
 modules = {}
 for name in objects.entries:
  match = re.fullmatch(r'plugins/modules/([^/]+)/module.ini', name)
  if not match:
   continue
  ident = match[1]; metadata = ini(objects.read(name))['meta']
  if metadata.get('id') != ident:
   raise ValueError(f'Module directory/descriptor identity mismatch: {ident}')
  prefix = 'plugins/modules/' + ident + '/'
  members = {p[len(prefix):]: p for p in objects.entries if p.startswith(prefix)}
  selectable = metadata.get('selectable', '1').casefold()
  if selectable not in {'0', '1', 'true', 'false', 'yes', 'no', 'on', 'off'}:
   raise ValueError(f'Unsupported accepted selectable literal: {ident} {selectable}')
  # Exact existing moduleIsAlwaysAvailable projection, never a new policy.
  always = metadata.get('kind', '') == 'acquisition' or selectable in {'0', 'false', 'no', 'off'}
  modules[ident] = {'id': ident, 'type': 'module', 'version': metadata['version'], 'core_literal': metadata.get('core', 'MISSING'), 'always_available': always, 'source_module_path': prefix[:-1], 'depends': [v.strip() for v in metadata.get('depends', '').split(';') if v.strip()], 'members': members}
 if len(modules) != 164:
  raise ValueError(f'Accepted module roster changed: {len(modules)}')
 counts = {key: sum(m['core_literal'] == key for m in modules.values()) for key in ('0', '1', 'MISSING')}
 if counts != {'0': 114, '1': 47, 'MISSING': 3}:
  raise ValueError(f'Accepted core declarations changed: {counts}')
 return modules


def zip_identity(path):
 if path.is_symlink() or not path.is_file():
  raise ValueError(f'Original must be an ordinary file: {path}')
 with zipfile.ZipFile(path) as z:
  manifests = [n for n in z.namelist() if n.endswith('plugin-package.ini') and n.count('/') <= 2]
  if len(manifests) != 1:
   return None
  manifest = manifests[0]; package = ini(z.read(manifest)).get('package', {})
  return package, manifest[:-len('plugin-package.ini')]


def original_matches(path, prefix, module, objects):
 expected = {name: objects.identity(source)['sha256'] for name, source in module['members'].items()}
 actual, modes = {}, {}
 with zipfile.ZipFile(path) as z:
  for info in z.infolist():
   if info.is_dir():
    continue
   relative(info.filename)
   if stat.S_ISLNK(info.external_attr >> 16) or not info.filename.startswith(prefix):
    return False, None
   name = info.filename[len(prefix):]
   relative(name)
   if name in actual:
    return False, None
   actual[name] = sha(z.read(info)); modes[name] = (info.external_attr >> 16) & 0o777
 if expected != actual:
  return False, None
 compatible = all(bool(modes[n] & 0o111) == bool(objects.entries[module['members'][n]]['mode'] & 0o111) for n in modes)
 return True, {'member_count': len(actual), 'executable_bit_compatible': compatible, 'original_modes': sorted(set(modes.values())), 'member_modes': modes}


def published_index():
 index = {}
 for path in sorted(MODULE_ARCHIVES.glob('*.zip')):
  identity = zip_identity(path)
  if identity:
   package, prefix = identity
   if package.get('type') == 'module':
    index.setdefault((package.get('id'), package.get('version')), []).append((path, prefix))
 return index


def write(path, data, mode=0o644):
 path.parent.mkdir(parents=True, exist_ok=True)
 with path.open('xb') as stream:
  stream.write(data)
 path.chmod(mode)


def json_file(path, value):
 write(path, (json.dumps(value, sort_keys=True, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))


def lossless_zip(path, module, objects):
 with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
  for name, source in sorted(module['members'].items()):
   info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0)); info.create_system = 3
   info.external_attr = (stat.S_IFREG | objects.entries[source]['mode']) << 16
   info.compress_type = zipfile.ZIP_DEFLATED
   z.writestr(info, objects.read(source), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def order_plugins(plugins, modules, bundled_ids):
 pending = {p['id']: p for p in plugins}; done = set(bundled_ids); result = []
 while pending:
  ready = sorted(i for i in pending if set(modules[i]['depends']) <= done)
  if not ready:
   unresolved = {i: sorted(set(modules[i]['depends']) - done) for i in pending}
   raise ValueError(f'Unresolved/cyclic module dependencies: {unresolved}')
  for ident in ready:
   result.append(pending.pop(ident)); done.add(ident)
 return result


def selection(name):
 if name in SHIP_VALIDATION:
  return True, 'reproducible_builder'
 if name in GENERATED:
  raise ValueError(f'Generated manifest must not be tracked in source: {name}')
 for root in HISTORICAL_DOC_ROOTS:
  if name.startswith(root):
   if name in REQUIRED_DOC_REFERENCES:
    return True, 'explicit_current_manual_or_API_reference'
   suffix = name[len(root):]
   if root != 'docs/evidence/' and '/' not in suffix and PurePosixPath(name).suffix.lower() in {'.md', '.html', '.htm'}:
    return True, 'top_level_technical_prose'
   group = suffix.split('/')[0] if '/' in suffix else '__top_raw__'
   return False, 'historical_document_campaign:' + root + group
 p = PurePosixPath(name)
 if p.parts[0] not in RUNTIME_ROOTS:
  if len(p.parts) == 1 and name not in ROOT_OMIT:
   return True, 'root_runtime_document'
  return False, 'historical_or_development_root:' + p.parts[0]
 if name.startswith('plugins/.registry/'):
  return False, 'mutable_plugin_registry'
 if name.startswith('plugins/modules/'):
  return True, 'accepted_module_payload_unchanged'
 if any(part in {'__pycache__', '.pytest_cache', 'CMakeFiles'} for part in p.parts):
  return False, 'generated_cache'
 if p.parts[0] == 'core' and any(part in {'test', 'tests', 'fixtures', 'validation', 'build'} for part in p.parts[1:]):
  return False, 'core_development_tests_or_intermediates'
 return True, 'accepted_runtime_resource'


def copy_original(source, target, expected=None):
 if source.is_symlink() or not source.is_file():
  raise ValueError(f'Original unavailable: {source}')
 actual = digest(source)
 if expected and actual != expected:
  raise ValueError(f'Original SHA differs: {source}')
 shutil.copyfile(source, target); target.chmod(0o644)
 if digest(target) != actual:
  raise ValueError('Original copy integrity failed')
 return actual


def optional_packages(bundle):
 if digest(P035) != P035_SHA:
  raise ValueError('Accepted P035 archive differs')
 with zipfile.ZipFile(P035) as z:
  packages = json.loads(z.read('patch_notes/DEV111-P035/GENERATOR_PACKAGES.json'))['packages']
 rows = []
 for item in packages:
  source = RELEASES / 'session_generators/archives' / item['filename']
  relative_name = 'distribution/packages/' + item['filename']
  copied = copy_original(source, bundle / relative_name, item['sha256'])
  rows.append({'id': item['id'], 'type': item['kind'], 'version': item['version'], 'path': relative_name, 'sha256': copied, 'original_path': str(source), 'installation': 'explicit existing Generator Library/Generator owner; never automatic'})
 if len(rows) != 6:
  raise ValueError('Accepted P035 five-generator plus teaching Library roster differs')
 filename, expected = GEO_LIBRARY
 source = RELEASES / 'session_generators/archives' / filename
 relative_name = 'distribution/packages/' + filename
 copied = copy_original(source, bundle / relative_name, expected)
 rows.append({'id': 'org.giuxlab.gxtxt.geospatial_examples', 'type': 'generator_library', 'version': '1.0.1', 'path': relative_name, 'sha256': copied, 'original_path': str(source), 'installation': 'explicit existing Generator Library owner; never replace a default/user Library automatically'})
 for filename in OPTIONAL_IR:
  source = RELEASES / 'scientific_libraries/archives' / filename
  relative_name = 'distribution/packages/' + filename
  copied = copy_original(source, bundle / relative_name)
  rows.append({'id': filename.removesuffix('_1.0.0.zip'), 'type': 'scientific_library', 'version': '1.0.0', 'path': relative_name, 'sha256': copied, 'original_path': str(source), 'installation': 'optional explicit Scientific Library Manager; never automatic'})
 return rows


def generator_inventory(objects, bundle, optional):
 """Describe exact active source closure, not historical archive duplication."""
 prefix = 'session_generator_libraries/'
 source_files = {name: objects.identity(name) for name in sorted(objects.entries) if name.startswith(prefix)}
 libraries = []; generators = []
 for name in source_files:
  basename = PurePosixPath(name).name
  if basename not in {'session-generator-library.ini', 'generator.ini'}:
   continue
  kind = 'library' if basename == 'session-generator-library.ini' else 'generator'
  fields = ini(objects.read(name))[kind]
  ident = fields[kind + '_id']; version = fields['version']
  row = {'id': ident, 'version': version, 'descriptor': name, 'descriptor_sha256': source_files[name]['sha256']}
  if kind == 'library':
   row['source_root'] = str(PurePosixPath(name).parent)
   row['delivery'] = 'EXACT_ACCEPTED_SOURCE_LIBRARY'
   libraries.append(row)
  else:
   generators.append(row)
 if len(libraries) != 4 or len(generators) != 44 or len({r['id'] for r in generators}) != 44:
  raise ValueError('Accepted four-source-Library/44-Generator identity coverage differs')
 for row in libraries:
  root = row['source_root'] + '/'
  row['generators'] = [r for r in generators if r['descriptor'].startswith(root)]
  row['source_file_count'] = sum(name.startswith(root) for name in source_files)
 supplemental = []
 for item in optional:
  if item['type'] != 'generator_library':
   continue
  with zipfile.ZipFile(bundle / item['path']) as archive:
   descriptors = [n for n in archive.namelist() if PurePosixPath(n).name == 'session-generator-library.ini']
   if len(descriptors) != 1:
    raise ValueError('Supplemental Library needs one normal descriptor')
   fields = ini(archive.read(descriptors[0]))['library']
   if (fields['library_id'], fields['version']) != (item['id'], item['version']):
    raise ValueError('Supplemental Generator Library identity differs')
   supplied = []
   for name in sorted(archive.namelist()):
    if PurePosixPath(name).name == 'generator.ini':
     values = ini(archive.read(name))['generator']
     supplied.append({'id': values['generator_id'], 'version': values['version'], 'descriptor': name})
   if not {r['id'] for r in supplied} <= {r['id'] for r in generators}:
    raise ValueError('Unexpected supplemental Generator logical ID')
   supplemental.append({'id': item['id'], 'version': item['version'], 'path': item['path'], 'sha256': item['sha256'], 'generators': supplied, 'delivery': 'NORMAL_ORIGINAL_EXPLICIT_LIBRARY_IMPORT'})
 if len(supplemental) != 2 or len({r['id'] for r in libraries + supplemental}) != 6:
  raise ValueError('Six current Generator Library identities must remain available')
 for name, identity in source_files.items():
  target = bundle / name
  if not target.is_file() or digest(target) != identity['sha256'] or target.stat().st_size != identity['size']:
   raise ValueError('Complete accepted Generator source/resource closure differs')
 omitted = [name for name in objects.entries if name.startswith('session_generator_packages/')]
 return {'schema': 'gxtxt.dev112.generator_coverage.v1', 'source_commit': objects.commit, 'source_libraries': libraries, 'source_generators': generators, 'source_files': source_files, 'supplemental_libraries': supplemental, 'counts': {'source_libraries': 4, 'current_generator_ids': 44, 'required_library_ids': 6, 'source_files': len(source_files), 'excluded_historical_package_paths': len(omitted)}, 'qualification': 'Complete accepted active source/resource closure preserved. Historical duplicate/older package paths add no Generator logical IDs and are omitted; matching published descriptors are not a replacement for source payload. Supplemental Library imports use existing owner explicitly, without automatic default/user Library replacement. No Generator or scientific execution inferred.'}


def reused_evidence(bundle):
 target = bundle / 'distribution/reused_p035'
 target.mkdir(parents=True)
 result = []
 for name, expected in REUSED_PINS.items():
  source = REUSED_P035 / name
  copied = copy_original(source, target / name, expected)
  result.append({'path': 'distribution/reused_p035/' + name, 'sha256': copied, 'original_path': str(source), 'qualification': 'Original accepted P035 evidence reused; not a new DEV112 functional campaign'})
 return result


def closure(bundle, manifest_path='distribution/manifests/files.json'):
 result = []
 for path in sorted(bundle.rglob('*')):
  if path.is_symlink():
   raise ValueError(f'Symlink in staged bundle: {path}')
  if path.is_file() and path.relative_to(bundle).as_posix() != manifest_path:
   result.append({'path': path.relative_to(bundle).as_posix(), 'sha256': digest(path), 'size': path.stat().st_size, 'mode': stat.S_IMODE(path.stat().st_mode)})
 return result


def archive_bundle(bundle, path, root_name='gxtxt_pipeline_v09810dev_112'):
 with path.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as gz, tarfile.open(fileobj=gz, mode='w|', format=tarfile.PAX_FORMAT) as tar:
  for source in sorted(p for p in bundle.rglob('*') if p.is_file()):
   name = root_name + '/' + source.relative_to(bundle).as_posix()
   entry = tarfile.TarInfo(name); entry.size = source.stat().st_size
   entry.mode = stat.S_IMODE(source.stat().st_mode); entry.uid = entry.gid = entry.mtime = 0
   entry.uname = entry.gname = ''
   with source.open('rb') as stream:
    tar.addfile(entry, stream)
 # Read back every archive member, including the manifest's own exact bytes.
 expected = {p.relative_to(bundle).as_posix(): {'sha256': digest(p), 'size': p.stat().st_size, 'mode': stat.S_IMODE(p.stat().st_mode)} for p in bundle.rglob('*') if p.is_file()}
 actual = {}
 with tarfile.open(path, 'r|gz') as tar:
  for item in tar:
   if not item.isfile() or not item.name.startswith(root_name + '/'):
    raise ValueError('Unexpected archive member/type')
   name = item.name.removeprefix(root_name + '/'); relative(name)
   if name in actual:
    raise ValueError('Duplicate archive member')
   h = hashlib.sha256()
   with tar.extractfile(item) as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
     h.update(chunk)
   actual[name] = {'sha256': h.hexdigest(), 'size': item.size, 'mode': item.mode}
 if expected != actual:
  raise ValueError('Archive readback closure differs')


def policy_inventory(objects, modules):
 policy_path = 'distribution/module_packaging.json'
 policy = json.loads(objects.read(policy_path))
 demos = set(policy['demo_ids'])
 if len(demos) != 15 or not demos <= modules.keys():
  raise ValueError('Purpose-reviewed15 Demo roster differs')
 if set(policy['owner_required_core']) != OWNER_CORE:
  raise ValueError('Owner CORE exception roster differs')
 for ident in demos:
  if modules[ident]['core_literal'] == '1' or modules[ident]['always_available']:
   raise ValueError(f'Demo must be a normal optional module: {ident}')
 for ident in policy['owner_confirmed_always']:
  if not modules[ident]['always_available']:
   raise ValueError(f'Existing acquisition ALWAYS predicate differs: {ident}')
 non_demo = set(modules) - demos
 normal = [m for i, m in modules.items() if i in non_demo and m['core_literal'] == '0' and not m['always_available']]
 bundled = non_demo - {m['id'] for m in normal}
 normal = order_plugins(normal, modules, bundled)
 if (len(non_demo), len(normal), len(bundled)) != (149, 49, 100):
  raise ValueError('Expected149 nonDemo,49 API-prepared,100 other bundled modules')
 return policy, demos, non_demo, normal, bundled


def payload(module, objects, extras=None):
 rows = {name: objects.identity(source) for name, source in module['members'].items()}
 for name, extra in (extras or {}).items():
  relative(name)
  if name in rows or digest(Path(extra['path'])) != extra['sha256']:
   raise ValueError('Demo resource collision or original resource SHA differs')
  rows[name] = {'sha256': extra['sha256'], 'size': Path(extra['path']).stat().st_size, 'mode': 0o644}
 return rows


def verify_payload_zip(path, prefix, expected):
 actual, modes = {}, {}
 with zipfile.ZipFile(path) as z:
  for item in z.infolist():
   if item.is_dir():
    continue
   relative(item.filename)
   if not item.filename.startswith(prefix) or stat.S_ISLNK(item.external_attr >> 16):
    return False, None
   name = item.filename[len(prefix):]; relative(name)
   if name in actual:
    return False, None
   data = z.read(item); actual[name] = {'sha256': sha(data), 'size': len(data)}
   modes[name] = (item.external_attr >> 16) & 0o777 or 0o644
 expected_bytes = {n: {'sha256': v['sha256'], 'size': v['size']} for n, v in expected.items()}
 if expected_bytes != actual:
  return False, None
 return True, {'member_count': len(actual), 'member_modes': modes, 'original_modes': sorted(set(modes.values())), 'executable_bit_compatible': all(bool(modes[n] & 0o111) == bool(expected[n]['mode'] & 0o111) for n in modes)}


def package_module(module, objects, destination, index, extras=None):
 destination.mkdir(parents=True, exist_ok=True)
 ident = module['id']; expected = payload(module, objects, extras)
 candidates = index.get((ident, module['version']), [])
 if ident in MANDATORY:
  filename, required = MANDATORY[ident]; original = MODULE_ARCHIVES / filename
  if digest(original) != required:
   raise ValueError(f'Mandatory original differs: {ident}')
  info = zip_identity(original)
  if not info or info[0].get('id') != ident or info[0].get('version') != module['version']:
   raise ValueError('Mandatory original package identity differs')
  candidates = [(original, info[1])]
 chosen = None; proof = None
 for path, prefix in candidates:
  match, candidate = verify_payload_zip(path, prefix, expected)
  if match:
   chosen, proof = path, candidate; break
 if chosen:
  target = destination / chosen.name
  package_sha = copy_original(chosen, target, MANDATORY[ident][1] if ident in MANDATORY else None)
  origin = {'kind': 'EXACT_PUBLISHED_ORIGINAL', 'original_path': str(chosen), **proof}
 else:
  if ident in MANDATORY:
   raise ValueError(f'Mandatory original payload differs: {ident}')
  target = destination / (ident + '_' + module['version'] + '_accepted.zip')
  with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
   for name, row in sorted(expected.items()):
    data = objects.read(module['members'][name]) if name in module['members'] else Path(extras[name]['path']).read_bytes()
    if sha(data) != row['sha256']:
     raise ValueError('Payload changed during wrapper creation')
    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0)); info.create_system = 3
    info.external_attr = (stat.S_IFREG | row['mode']) << 16
    z.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
  match, proof = verify_payload_zip(target, '', expected)
  if not match:
   raise ValueError('Lossless wrapper readback differs')
  package_sha = digest(target)
  origin = {'kind': 'LOSSLESS_APPROVED_SOURCE_WRAPPER', 'checksum_manifests_regenerated': False, **proof}
 base = {k: v for k, v in module.items() if k != 'members'}
 return dict(base, filename=target.name, sha256=package_sha, origin=origin), expected


def package_normal(objects, modules, normal, target):
 index = published_index(); packages = []; provenance = []
 for m in normal:
  item, expected = package_module(m, objects, target / 'distribution/packages', index)
  item['path'] = 'distribution/packages/' + item['filename']
  item['delivery'] = 'PREINSTALLED_MANAGED_NO_USER_INSTALL'
  packages.append({k: v for k, v in item.items() if k != 'origin'})
  provenance.append(item)
 return packages, provenance


def stage_source(objects, target, modules, excluded, managed_modes=None):
 omitted = {}; included = []; legacy = {}
 for name, entry in sorted(objects.entries.items()):
  keep, reason = selection(name)
  match = re.match(r'^plugins/modules/([^/]+)/', name)
  if match and match[1] in excluded:
   keep, reason = False, 'module_not_in_this_preparation_stage'
  if name == 'distribution/demo_install.py':
   keep, reason = False, 'separate_demo_artifact_only'
  if not keep:
   omitted[reason] = omitted.get(reason, 0) + 1; continue
  mode = (managed_modes or {}).get(name, entry['mode'])
  write(target / name, objects.read(name), mode); included.append(name)
  other = re.fullmatch(r'plugins/(models|instruments|analysis_definitions)/([^/]+)/(model|instrument|analysis)\.ini', name)
  if other:
   meta = ini(objects.read(name)).get('meta', {})
   legacy[other[2]] = {'id': meta.get('id', other[2]), 'type': {'models': 'model', 'instruments': 'instrument', 'analysis_definitions': 'analysis_definition'}[other[1]], 'version': meta.get('version', ''), 'source_module_path': str(PurePosixPath(name).parent), 'reason': 'Accepted legacy unmanaged source; no manufactured registry'}
 if len(legacy) != 18:
  raise ValueError('All18 legacy nonmodule roots must remain')
 return included, omitted, list(legacy.values())


def non_demo_fingerprint(objects, modules, non_demo):
 rows = {ident: {n: {'sha256': objects.identity(p)['sha256'], 'size': objects.identity(p)['size'], 'git_executable': bool(objects.entries[p]['mode'] & 0o111)} for n, p in sorted(modules[ident]['members'].items())} for ident in sorted(non_demo)}
 return sha(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode())


def inspect_registry(data, normal):
 parsed = ini(data)
 expected = {m['id']: m for m in normal}
 sections = {name.removeprefix('plugin.'): values for name, values in parsed.items() if name.startswith('plugin.')}
 if set(sections) != set(expected) or len(parsed) != 49:
  raise ValueError('Frozen registry must contain exactly49 actual nonDemo API registrations')
 for ident, values in sections.items():
  if (values.get('id'), values.get('type'), values.get('version')) != (ident, 'module', expected[ident]['version']):
   raise ValueError(f'Registry identity differs: {ident}')
  if not values.get('installed_at') or not values.get('updated_at') or not values.get('package_file'):
   raise ValueError('Registry must preserve actual CORE timestamps/package identity')
 return sections


def seed_input(seed, expected_sha, commit, objects, modules, policy, non_demo, normal):
 seed = seed.resolve()
 manifest_path = seed / 'seed_manifest.json'
 if digest(manifest_path) != expected_sha:
  raise ValueError('Frozen seed manifest SHA differs')
 manifest = json.loads(manifest_path.read_text())
 if manifest.get('schema') != 'gxtxt.dev112.registry_seed.v1' or manifest.get('status') != 'OFFICIAL_API_PREPARATION_SUCCEEDED':
  raise ValueError('A successful actual API preparation seed is required')
 if manifest['source_commit'] != commit or manifest['accepted_source'] != BASE:
  raise ValueError('Seed and build must use the same clean source commit')
 if manifest['module_packaging_sha256'] != sha(objects.read('distribution/module_packaging.json')) or manifest['non_demo_payload_fingerprint'] != non_demo_fingerprint(objects, modules, non_demo):
  raise ValueError('Seed policy or payload identity differs')
 for p, pin in manifest['tool_pins'].items():
  if p not in {'distribution/migrate.py', 'distribution/install_worker.tcl', 'validation/dev112_release/prepare_registry.py'} or objects.identity(p)['sha256'] != pin:
   raise ValueError('Actual preparation tool identity differs')
 if set(manifest['tool_pins']) != {'distribution/migrate.py', 'distribution/install_worker.tcl', 'validation/dev112_release/prepare_registry.py'}:
  raise ValueError('Seed tool identity set differs')
 expected_paths = {p for m in normal for p in m['members'].values()}; modes = {}
 for name, row in manifest['installed_payload_files'].items():
  if name not in expected_paths or row['sha256'] != objects.identity(name)['sha256'] or row['size'] != objects.identity(name)['size'] or row['mode'] < 0 or row['mode'] > 0o777:
   raise ValueError('Seed installed payload identity differs')
  modes[name] = row['mode']
 if set(modes) != expected_paths:
  raise ValueError('Seed must bind every actual API-installed payload file')
 if set(manifest['frozen_files']) != {'registry/installed.ini', 'receipts/api.log', 'receipts/api_plan.tsv', 'receipts/preparation.json'}:
  raise ValueError('Only exact registry and actual API receipts may enter the release')
 for name, row in manifest['frozen_files'].items():
  relative(name); path = seed / name
  if path.is_symlink() or not path.is_file() or digest(path) != row['sha256'] or path.stat().st_size != row['size'] or stat.S_IMODE(path.stat().st_mode) != row['mode']:
   raise ValueError('Frozen preparation registry/receipt input differs')
 receipt = json.loads((seed / 'receipts/preparation.json').read_text())
 expected_operations = [(m['id'], 'module', m['version'], 'installed') for m in normal]
 if receipt.get('schema') != 'gxtxt.dev112.actual_api_preparation.v1' or receipt.get('source_commit') != commit or [(r['id'], r['type'], r['version'], r['action']) for r in receipt.get('operations', [])] != expected_operations:
  raise ValueError('Actual API preparation receipt differs from the49 fresh operations')
 if receipt.get('core_always_api_operations') != 0 or receipt.get('demo_api_operations') != 0 or manifest['managed_ids'] != [m['id'] for m in normal]:
  raise ValueError('CORE/ALWAYS/Demo cannot enter registry preparation')
 inspect_registry((seed / 'registry/installed.ini').read_bytes(), normal)
 return manifest, modes


def complete_manifest(bundle, commit, manifest_path='distribution/manifests/files.json'):
 manifest = {'release': VERSION, 'source_commit': commit, 'accepted_source': BASE, 'files': closure(bundle, manifest_path)}
 json_file(bundle / manifest_path, manifest)
 if manifest['files'] != closure(bundle, manifest_path):
  raise ValueError('Staged closure changed')
 return manifest


def build(repo, commit, output, seed, seed_sha):
 repo = repo.resolve(); output = output.absolute()
 if output.exists() or not str(output).startswith('/srv/gxtxt/agents/scratch/DEV112-') or any(p.is_symlink() for p in (output, *output.parents)):
  raise ValueError('Use a new nonsymlink DEV112 RAID output')
 commit = approved_source(repo, commit); objects = Objects(repo, commit)
 try:
  modules = module_inventory(objects)
  policy, demos, non_demo, normal, bundled_ids = policy_inventory(objects, modules)
  frozen, modes = seed_input(seed, seed_sha, commit, objects, modules, policy, non_demo, normal)
  bundle = output / 'bundle'; bundle.mkdir(parents=True)
  packages, origins = package_normal(objects, modules, normal, bundle)
  if [(p['id'], p['sha256']) for p in packages] != [(p['id'], p['sha256']) for p in frozen['packages']]:
   raise ValueError('Actual prepared package inputs differ from final build')
  included, omitted, legacy = stage_source(objects, bundle, modules, demos, modes)
  for required in ('distribution/migrate.py', 'distribution/install_worker.tcl', *SHIP_VALIDATION):
   if not (bundle / required).is_file():
    raise ValueError(f'Required release/preparation tool absent: {required}')
  supplemental = []; index = published_index()
  viewer, _ = package_module(modules['viewer.curve_digitizer'], objects, bundle / 'distribution/packages', index)
  viewer['path'] = 'distribution/packages/' + viewer['filename']; viewer['delivery'] = 'BUNDLED_CORE_ORIGINAL_PROVENANCE_ONLY'; supplemental.append(viewer)
  optional = optional_packages(bundle); evidence = reused_evidence(bundle)
  generators = generator_inventory(objects, bundle, optional)
  json_file(bundle / 'distribution/manifests/GENERATOR_INVENTORY.json', generators)
  seed = seed.resolve(); reg = frozen['frozen_files']['registry/installed.ini']
  write(bundle / 'plugins/.registry/installed.ini', (seed / 'registry/installed.ini').read_bytes(), reg['mode'])
  for name, pin in frozen['frozen_files'].items():
   if name.startswith('receipts/'):
    write(bundle / 'distribution/preparation' / name.removeprefix('receipts/'), (seed / name).read_bytes(), pin['mode'])
  write(bundle / 'distribution/preparation/seed_manifest.json', (seed / 'seed_manifest.json').read_bytes())
  demo_bundle = output / 'demos'; (demo_bundle / 'packages').mkdir(parents=True)
  resource = policy['geospatial_documentation_resource']; demo_rows = []; demo_origins = []
  for ident in sorted(demos):
   extras = {resource['member']: {'path': resource['original'], 'sha256': resource['sha256']}} if ident == resource['module_id'] else None
   item, _ = package_module(modules[ident], objects, demo_bundle / 'packages', index, extras)
   item['path'] = 'packages/' + item['filename']; item['delivery'] = 'SEPARATE_DEMO_EXPLICIT_INSTALL_ONLY'
   demo_origins.append(item); demo_rows.append({k: v for k, v in item.items() if k != 'origin'})
  write(demo_bundle / 'install_demo.py', objects.read('distribution/demo_install.py'))
  write(demo_bundle / 'README.md', objects.read('distribution/DEMO_INSTALL.md'))
  write(demo_bundle / 'module_packaging.json', objects.read('distribution/module_packaging.json'))
  demo_manifest = {'release': VERSION, 'source_commit': commit, 'plugins': demo_rows, 'source_policy_sha256': sha(objects.read('distribution/module_packaging.json'))}
  json_file(demo_bundle / 'packages.json', demo_manifest)
  demo_files = complete_manifest(demo_bundle, commit, 'files.json')
  demo_archive = output / 'gxtxt_demo_modules_v09810dev_112.tar.gz'
  archive_bundle(demo_bundle, demo_archive, 'gxtxt_demo_modules_v09810dev_112')
  bundled = [{k: v for k, v in modules[i].items() if k != 'members'} for i in sorted(bundled_ids)] + legacy
  demo_metadata = [{k: v for k, v in item.items() if k not in {'path', 'origin'}} for item in demo_rows]
  manifest = {'release': VERSION, 'source_commit': commit, 'accepted_source': BASE, 'plugins': packages, 'bundled': bundled, 'demo_plugins': demo_metadata, 'supplemental_packages': supplemental, 'optional_packages': optional, 'registry_seed': {'manifest_sha256': seed_sha, 'path': 'plugins/.registry/installed.ini', **reg}, 'counts': {'source_modules': 164, 'framework_modules': 149, 'demo_modules': 15, 'literal_core1': 47, 'literal_core0': 114, 'missing_core': 3, 'preinstalled_managed': 49, 'other_bundled_modules': 100, 'legacy_other_types': 18}, 'installation': 'All149 nonDemo modules already expanded.49 normal API registrations are frozen actual preparation output; no user base installation.'}
  json_file(bundle / 'distribution/manifests/plugins.json', manifest)
  json_file(bundle / 'distribution/manifests/provenance.json', {'release': VERSION, 'source_commit': commit, 'accepted_source': BASE, 'owner_authorized_source_exceptions': sorted(OWNER_CORE), 'module_packages': origins, 'supplemental_originals': supplemental, 'optional_originals': optional, 'reused_P035_evidence': evidence, 'official_registry_preparation': {'seed_manifest_sha256': seed_sha, 'source_commit': frozen['source_commit'], 'registry_sha256': reg['sha256'], 'qualification': 'Real fresh CORE API output, normal clock; reproducibility uses same frozen seed, not repeated API timestamps'}, 'separate_demo_artifact': {'filename': demo_archive.name, 'sha256': digest(demo_archive), 'demo_packages': demo_origins, 'geospatial_original_resource': resource}, 'source_selection': {'included_source_files': included, 'omitted_counts': omitted, 'documentation_policy': {'explicit_required_references': sorted(REQUIRED_DOC_REFERENCES), 'qualification': 'Historical prose unchanged; raw past proof links may point to excluded campaigns; current references retained explicitly.'}}, 'original_P035_archive_sha256': P035_SHA})
  files = complete_manifest(bundle, commit)
  archive = output / 'gxtxt_pipeline_v09810dev_112.tar.gz'; archive_bundle(bundle, archive)
  result = {'status': 'BUILT_READBACK_VERIFIED_NOT_RELEASE_ACCEPTANCE', 'release': VERSION, 'source_commit': commit, 'archive': str(archive), 'archive_sha256': digest(archive), 'archive_bytes': archive.stat().st_size, 'file_count': len(files['files']) + 1, 'counts': manifest['counts'], 'seed_manifest_sha256': seed_sha, 'demo_archive': str(demo_archive), 'demo_archive_sha256': digest(demo_archive)}
  demo_result = {'status': result['status'], 'release': VERSION, 'source_commit': commit, 'archive': str(demo_archive), 'archive_sha256': digest(demo_archive), 'archive_bytes': demo_archive.stat().st_size, 'file_count': len(demo_files['files']) + 1, 'demo_count': 15}
  json_file(output / 'BUILD_REPORT.json', result); json_file(output / 'DEMO_BUILD_REPORT.json', demo_result)
  return result, demo_result
 finally:
  objects.close()


def main():
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('repository', type=Path); parser.add_argument('commit'); parser.add_argument('new_output', type=Path)
 parser.add_argument('--registry-seed', required=True, type=Path); parser.add_argument('--registry-seed-sha256', required=True)
 args = parser.parse_args()
 print(json.dumps(build(args.repository, args.commit, args.new_output, args.registry_seed, args.registry_seed_sha256), indent=2))


if __name__ == '__main__':
 main()
