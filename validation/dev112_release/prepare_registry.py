#!/usr/bin/env python3
"""One real fresh CORE installation prepares the immutable release registry seed.

This is not a registry synthesizer or a clock shim. Actual existing CORE writes
all rows/timestamps. Freeze its result once; reproduce artifacts with that input.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import time
_spec = importlib.util.spec_from_file_location('dev112_release_builder', Path(__file__).with_name('build.py'))
release = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(release)


def tree_files(root):
 result = {}
 for path in sorted(root.rglob('*')):
  if path.is_symlink():
   raise ValueError('API-installed payload contains a symlink')
  if path.is_file():
   result[path.relative_to(root).as_posix()] = path
 return result


def prepare(repo, commit, output):
 repo = repo.resolve(); output = output.absolute()
 if output.exists() or not str(output).startswith('/srv/gxtxt/agents/scratch/DEV112-') or any(p.is_symlink() for p in (output, *output.parents)):
  raise ValueError('Fresh nonsymlink DEV112 seed output required')
 commit = release.approved_source(repo, commit)
 objects = release.Objects(repo, commit)
 try:
  modules = release.module_inventory(objects)
  policy, demos, non_demo, normal, bundled = release.policy_inventory(objects, modules)
  target = output / 'prepared_framework'; target.mkdir(parents=True)
  packages, origins = release.package_normal(objects, modules, normal, target)
  release.stage_source(objects, target, modules, demos | {m['id'] for m in normal})
  if (target / 'plugins/.registry/installed.ini').exists():
   raise ValueError('Fresh preparation must not import any existing registry')
  present = {p.name for p in (target / 'plugins/modules').iterdir() if p.is_dir()}
  if present != bundled:
   raise ValueError('Before API invocation only100 nonDemo bundled roots may exist')
  state = output / 'private_api_state'; state.mkdir(mode=0o700)
  adapter_path = target / 'distribution/migrate.py'
  spec = importlib.util.spec_from_file_location('dev112_actual_preparation_adapter', adapter_path)
  adapter = importlib.util.module_from_spec(spec); spec.loader.exec_module(adapter)
  items = [dict(item, path=str(target / item['path']), mode='install') for item in packages]
  started = time.time()
  # This shared owner invokes the actual synchronous Plugin Install API and its
  # existing process group/diagnostic/quiescence guards. Never stub clock/API.
  adapter.worker(target, items, state, 'official49')
  ended = time.time()
  registry = target / 'plugins/.registry/installed.ini'
  raw = registry.read_bytes(); sections = release.inspect_registry(raw, normal)
  api_log = (state / 'official49.log').read_text(encoding='utf-8')
  accepted = []
  for line in api_log.splitlines():
   if line.startswith('INSTALLED\t'):
    parts = line.split('\t')
    if len(parts) != 5:
     raise ValueError('Unexpected actual CORE installation receipt shape')
    accepted.append({'id': parts[1], 'type': parts[2], 'version': parts[3], 'action': parts[4]})
  if [(r['id'], r['type'], r['version'], r['action']) for r in accepted] != [(m['id'], 'module', m['version'], 'installed') for m in normal]:
   raise ValueError('Actual worker must confirm exactly49 fresh nonDemo installations')
  installed = {}
  for m in normal:
   root = target / m['source_module_path']; actual = tree_files(root)
   if set(actual) != set(m['members']):
    raise ValueError(f'API-installed payload file-set differs: {m["id"]}')
   for name, path in actual.items():
    source = m['members'][name]; pin = objects.identity(source)
    if release.digest(path) != pin['sha256'] or path.stat().st_size != pin['size']:
     raise ValueError(f'API changed accepted payload bytes: {m["id"]}/{name}')
    installed[source] = {'sha256': pin['sha256'], 'size': pin['size'], 'mode': stat.S_IMODE(path.stat().st_mode), 'git_executable': bool(pin['mode'] & 0o111)}
  present = {p.name for p in (target / 'plugins/modules').iterdir() if p.is_dir() and not p.name.startswith('.')}
  if present != non_demo:
   raise ValueError('Actual prepared framework must contain149 nonDemo roots only')
  for m in modules.values():
   if m['id'] not in bundled:
    continue
   for name, source in m['members'].items():
    path = target / source; pin = objects.identity(source)
    if not path.is_file() or path.is_symlink() or release.digest(path) != pin['sha256']:
     raise ValueError('CORE/ALWAYS payload changed during ordinary preparation')
  frozen = output / 'registry/installed.ini'
  release.write(frozen, raw, stat.S_IMODE(registry.stat().st_mode))
  receipt = {'schema': 'gxtxt.dev112.actual_api_preparation.v1', 'source_commit': commit, 'started_unix_actual': started, 'finished_unix_actual': ended, 'clock': 'Actual normal CORE/OS clocks; no stubs', 'worker_exit': 'successful normal adapter return', 'operations': accepted, 'registry_sections': sorted(sections), 'framework_roots': sorted(present), 'core_always_api_operations': 0, 'demo_api_operations': 0, 'private_state_shipped': False}
  release.write(output / 'receipts/api.log', (state / 'official49.log').read_bytes())
  release.write(output / 'receipts/api_plan.tsv', (state / 'official49.tsv').read_bytes())
  release.json_file(output / 'receipts/preparation.json', receipt)
  frozen_files = {}
  for name in ['registry/installed.ini', 'receipts/api.log', 'receipts/api_plan.tsv', 'receipts/preparation.json']:
   path = output / name
   frozen_files[name] = {'sha256': release.digest(path), 'size': path.stat().st_size, 'mode': stat.S_IMODE(path.stat().st_mode)}
  manifest = {'schema': 'gxtxt.dev112.registry_seed.v1', 'status': 'OFFICIAL_API_PREPARATION_SUCCEEDED', 'source_commit': commit, 'accepted_source': release.BASE, 'module_packaging_sha256': release.sha(objects.read('distribution/module_packaging.json')), 'non_demo_payload_fingerprint': release.non_demo_fingerprint(objects, modules, non_demo), 'managed_ids': [m['id'] for m in normal], 'packages': packages, 'tool_pins': {p: objects.identity(p)['sha256'] for p in ['distribution/migrate.py', 'distribution/install_worker.tcl', 'validation/dev112_release/prepare_registry.py']}, 'installed_payload_files': installed, 'frozen_files': frozen_files, 'qualification': 'Legitimate actual API registry seed; reproducibility uses these frozen bytes, not rerunning timestamps'}
  release.json_file(output / 'seed_manifest.json', manifest)
  result = {'status': manifest['status'], 'source_commit': commit, 'seed': str(output), 'seed_manifest_sha256': release.digest(output / 'seed_manifest.json'), 'registry_sha256': frozen_files['registry/installed.ini']['sha256'], 'managed': 49, 'expanded_non_demo': 149, 'demo_installed': 0}
  release.json_file(output / 'PREPARATION_REPORT.json', result)
  return result
 finally:
  objects.close()


def main():
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('repository', type=Path); parser.add_argument('commit'); parser.add_argument('new_seed_output', type=Path)
 args = parser.parse_args()
 print(json.dumps(prepare(args.repository, args.commit, args.new_seed_output), indent=2))


if __name__ == '__main__':
 main()
