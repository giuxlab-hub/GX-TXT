# SPDX-License-Identifier: GPL-3.0-or-later
"""API catalog packaging and inert runtime reconciliation. Never runs plugin installers.

Only --build imports the existing trusted installed declaration discovery owner.
--stage parses descriptors and literal AST data and never imports plugin sources.
"""
from pathlib import Path
import argparse
import ast
import configparser
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tkinter
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gxtxt_job_supervisor import tcl_result

IDENTITY = 'gxtxt.api_catalog.distribution.v2'
EXTENSIONS = {'.tcl', '.py', '.json', '.hpp', '.h', '.ini'}
SKIP = {'__pycache__', 'images', 'resources', 'native', 'review'}


def inventory(root):
    files = {root / name for name in ('gxtxt_pipeline.tcl', 'PATCH_LEVEL.txt', 'PATCH.txt', 'VERSION.txt')}
    def walk(directory, depth=0):
        if depth > 8:
            raise ValueError('Catalog inventory depth exceeds bound')
        for path in sorted(directory.iterdir()) if directory.is_dir() else []:
            if path.is_symlink():
                continue
            if path.is_dir():
                if path.name not in SKIP:
                    walk(path, depth + 1)
            elif path.suffix in EXTENSIONS:
                files.add(path)
    for name in ('core/tcl', 'core/python', 'core/script_bindings', 'core/development'):
        walk(root / name)
    for module in sorted((root / 'plugins/modules').iterdir()):
        if module.is_dir() and not module.is_symlink():
            files.update(module / name for name in ('module.ini', 'SHA256SUMS.txt', 'SHA256SUMS'))
            walk(module / 'api')
    if len(files) > 10000:
        raise ValueError('Catalog inventory exceeds10000files')
    return sorted(files, key=lambda path: path.as_posix())


def bounded_bytes(path, maximum=16 * 1024 * 1024):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Catalog source must be an ordinary file: ' + str(path))
    before = path.stat()
    if before.st_size > maximum:
        raise ValueError('Catalog source exceeds bounded file size: ' + str(path))
    with path.open('rb') as stream:
        value = stream.read(maximum + 1)
    after = path.stat()
    if len(value) > maximum or (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns) or len(value) != before.st_size:
        raise ValueError('Catalog source changed or exceeded bound: ' + str(path))
    return value


def sha(path, maximum=16 * 1024 * 1024):
    return hashlib.sha256(bounded_bytes(path, maximum)).hexdigest() if path.is_file() else None


def declaration_ast(path):
    """Top-level metadata identity; function bodies/imports are never executed."""
    tree = ast.parse(bounded_bytes(path).decode('utf-8'), filename=str(path))
    nodes = [node for node in tree.body if not isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))]
    return hashlib.sha256(ast.dump(ast.Module(body=nodes, type_ignores=[]), include_attributes=False).encode()).hexdigest()


class Catalog:
    def __init__(self, root):
        self.root = root
        self.documentation = set()
        self.core_sources = {}
        manifest_path = root / 'core/api_catalog/source_manifest.json'
        if manifest_path.is_file():
            prior = json.loads(bounded_bytes(manifest_path, 4 * 1024 * 1024))
            self.documentation.update(prior.get('documentation', []))
        self.tcl = tkinter.Tcl()
        self.tcl.call('load', str(root / 'core/api_catalog/libgxtxt_api_catalog.so'), 'Gxtxt_api_catalog')

    def native(self, *args):
        return self.tcl.call('::GX::apiCatalogNative', *args)

    def string(self, value):
        # Tcl objects must retain their Tcl representation, never Python tuple repr.
        return self.tcl.call('format', '%s', value)

    def dictionary(self, value):
        if isinstance(value, dict):
            return value
        words = self.tcl.splitlist(value)
        if len(words) % 2:
            raise ValueError('Malformed metadata dictionary')
        return dict(zip(words[::2], words[1::2]))

    def resolve_documentation(self, reference, provider):
        path = Path(reference)
        if not reference or path.is_absolute() or '..' in path.parts:
            return '', 'invalid_identity'
        candidates = [self.root / path]
        if provider and provider != 'CORE':
            candidates += [self.root / 'plugins/modules' / provider / path, self.root / 'plugins/modules' / provider / 'docs' / path]
        selected = next((candidate for candidate in candidates if candidate.is_file() and not candidate.is_symlink()), candidates[0])
        selected = selected.resolve()
        if not selected.is_relative_to(self.root):
            return '', 'invalid_identity'
        relative = selected.relative_to(self.root).as_posix()
        self.documentation.add(relative)
        return relative, 'available' if selected.is_file() and not selected.is_symlink() else 'missing'

    def manifest(self):
        files = set(inventory(self.root))
        # Parse only inert descriptor documentation references, never API code.
        for module in sorted((self.root / 'plugins/modules').iterdir()):
            descriptor = module / 'module.ini'
            if not descriptor.is_file() or module.is_symlink():
                continue
            ini = configparser.ConfigParser(interpolation=None, strict=True)
            ini.read_string(bounded_bytes(descriptor).decode('utf-8'))
            for api in filter(None, ini.get('public_apis', 'ids', fallback='').split(';')):
                self.resolve_documentation(ini.get('public_api.' + api, 'documentation', fallback='docs/api/' + api + '.md'), module.name)
            # A literal Script Bridge declaration can own a different manual
            # from the host descriptor. Inventory it before taking the stage's
            # source snapshot, using the same nonexecuting parser as staging.
            # Dynamic declarations remain pending (or reuse their previously
            # packaged documentation identities); they are never imported.
            for binding_path in sorted((module / 'api').glob('script_bridge_binding*.py')):
                try:
                    bindings = literal_binding(binding_path)
                except (ValueError, TypeError, KeyError, SyntaxError):
                    continue
                for binding in bindings:
                    if isinstance(binding, dict) and isinstance(binding.get('documentation_ref'), str):
                        self.resolve_documentation(binding['documentation_ref'], module.name)
        files.update(self.root / name for name in self.documentation)
        files = sorted(files, key=lambda path: path.as_posix())
        entries = {}
        total = sum(path.stat().st_size for path in files if path.is_file())
        if total > 256 * 1024 * 1024:
            raise ValueError('Catalog source bytes exceed256MiB')
        for path in files:
            entry = {'sha256': sha(path)}
            if path.is_file() and path.name.startswith('script_bridge_binding') and path.suffix == '.py':
                entry['metadata_ast_sha256'] = declaration_ast(path)
            entries[path.relative_to(self.root).as_posix()] = entry
        fingerprint = self.native('fingerprint', self.tcl.call('list', *(str(p) for p in files)), str(self.root))
        return {'schema': 'gxtxt.api_catalog.sources.v2', 'fingerprint': fingerprint, 'files': entries, 'documentation': sorted(self.documentation)}

    def record(self, identity, api, provider, surface, language, version, title, summary, payload, source=None, operation='', contract=None):
        source = source or {}
        contract = contract or {}
        metadata = {key: source.get(key, '') for key in ('provider_version', 'declaration_ref', 'declaration_sha256', 'documentation', 'deprecated', 'superseded_by')}
        if not metadata['provider_version'] and str(metadata['declaration_ref']).startswith('core/'):
            metadata['provider_version'] = bounded_bytes(self.root / 'VERSION.txt', 4096).decode().strip()
        metadata['documentation'], metadata['documentation_status'] = self.resolve_documentation(metadata['documentation'], source.get('provider', provider))
        languages = contract.get('languages', 'Python Octave')
        languages = languages if isinstance(languages, list) else self.tcl.splitlist(languages)
        metadata.update(operation=operation, public_documented=1,
                        python=int(surface == 'script_bridge' and 'Python' in languages),
                        octave=int(surface == 'script_bridge' and 'Octave' in languages),
                        cpp_sdk=int(surface == 'cpp_sdk'), arguments=contract.get('arguments', ''),
                        result_contract=contract.get('result_contract', contract.get('result_convention', contract.get('result_type', ''))))
        if surface == 'script_bridge':
            language = 'all' if metadata['python'] and metadata['octave'] else 'Python' if metadata['python'] else 'Octave'
        payload = dict(payload, catalog_meta=metadata)
        return {'id': identity, 'api_id': api, 'provider_id': provider, 'surface': surface,
                'language': language, 'version': version, 'title': title, 'summary': summary, 'payload': payload}

    def host_arguments(self, contract):
        parameters = self.dictionary(contract.get('parameters', ''))
        result = []
        seen = set()
        for token in self.tcl.splitlist(contract.get('arguments', '')):
            words = self.tcl.splitlist(token)
            name = str(words[0]) if words else ''
            optional = name.startswith('?') and name.endswith('?')
            name = name.strip('?')
            if name not in parameters or name in seen:
                continue
            parameter = self.dictionary(parameters[name])
            argument = {'name': name, 'kind': parameter.get('type', ''), 'description': parameter.get('description', ''),
                        'required': parameter.get('required', 0 if optional or len(words) == 2 or name == 'args' else 1)}
            if 'default' in parameter:
                argument.update(default=parameter['default'], required=parameter.get('required', 0))
            elif len(words) == 2:
                argument['default'] = str(words[1])
            result.append(argument)
            seen.add(name)
        for name, raw in parameters.items():
            if name in seen:
                continue
            parameter = self.dictionary(raw)
            argument = {'name': name, 'kind': parameter.get('type', ''), 'description': parameter.get('description', ''),
                        'required': parameter.get('required', 0 if 'default' in parameter else -1)}
            if 'default' in parameter:
                argument['default'] = parameter['default']
            result.append(argument)
        return result

    def core_provenance(self, provider):
        provider = dict(provider)
        if provider.get('declaration_ref'):
            return provider
        command = provider.get('host_entrypoint', '')
        if command and not self.core_sources:
            for path in sorted((self.root / 'core/tcl').glob('*.tcl')):
                text = bounded_bytes(path).decode('utf-8')
                for name in re.findall(r'^\s*proc\s+(::[A-Za-z_][A-Za-z0-9_:]*)\s', text, re.M):
                    self.core_sources.setdefault(name, path)
        source = self.core_sources.get(command, self.root / 'core/tcl/workbench_extension_api_v1.tcl')
        provider.update(declaration_ref=source.relative_to(self.root).as_posix(), declaration_sha256=sha(source),
                        provider_version=bounded_bytes(self.root / 'VERSION.txt', 4096).decode().strip())
        return provider

    def binding_source(self, source, descriptor):
        source = dict(source)
        for key in ('declaration_ref', 'declaration_sha256', 'provider_version'):
            if key in descriptor:
                source[key] = descriptor[key]
        # The registered binding owns its documentation identity independently
        # of a host-provider row (which may not exist for script-only APIs).
        if 'documentation_ref' in descriptor:
            source['documentation'] = descriptor['documentation_ref']
        return source

    def family_provenance(self, records):
        members = {}
        for record in records:
            if record['surface'] == 'family':
                continue
            payload = self.dictionary(record['payload'])
            metadata = self.dictionary(payload['catalog_meta'])
            member = {key: metadata.get(key, '') for key in ('provider_version', 'declaration_ref', 'declaration_sha256', 'documentation', 'documentation_status')}
            member.update(provider_id=record['provider_id'], source_role=record['surface'])
            if not member['declaration_ref'] or not member['declaration_sha256']:
                raise ValueError('Declared record lacks source provenance: ' + record['id'])
            key = tuple(member.items())
            members.setdefault(record['api_id'], {})[key] = member
            metadata['source_kind'] = 'declared'
            metadata['source_members'] = [member]
            payload['catalog_meta'] = metadata
            record['payload'] = payload
        for record in records:
            if record['surface'] != 'family':
                continue
            sources = list(members.get(record['api_id'], {}).values())
            if not sources:
                raise ValueError('Aggregate family has no declaring sources: ' + record['api_id'])
            payload = self.dictionary(record['payload'])
            metadata = self.dictionary(payload['catalog_meta'])
            # The representative is explicitly labeled aggregate; complete
            # provider-qualified membership is preserved in a separate relation.
            metadata.update({key: sources[0][key] for key in ('provider_version', 'declaration_ref', 'declaration_sha256')})
            if metadata.get('documentation_status') != 'available':
                documented = next((member for member in sources if member.get('documentation_status') == 'available'),
                                  next((member for member in sources if member.get('documentation')), None))
                if documented:
                    metadata.update(documentation=documented['documentation'], documentation_status=documented['documentation_status'])
            metadata.update(source_kind='aggregate_reference_only', source_members=sources)
            payload['catalog_meta'] = metadata
            record['payload'] = payload
        return records

    def records(self, catalog):
        result = []
        for api, raw in catalog.items():
            family = self.dictionary(raw)
            providers = [self.dictionary(p) for p in self.tcl.splitlist(family.get('providers', ''))]
            for provider in providers:
                if not provider.get('declaration_ref'):
                    provider = self.core_provenance(provider)
                owner, version = provider['provider'], provider.get('version', '')
                if owner == 'CORE':
                    provider.setdefault('declaration_ref', 'core/tcl/workbench_extension_api_v1.tcl')
                    provider.setdefault('declaration_sha256', sha(self.root / provider['declaration_ref']))
                result.append(self.record(f'host:{api}:{owner}:{version}', api, owner, 'host', 'all', version, owner,
                                          provider.get('summary', ''), {'api': api, 'row': provider, 'surface': 'host'}, provider))
                if provider.get('host_operation_contracts'):
                    for name, value in self.dictionary(provider['host_operation_contracts']).items():
                        contract = self.dictionary(value)
                        arguments = self.host_arguments(contract)
                        result_contract = self.dictionary(contract.get('result', '')).get('description', '')
                        normalized = {'arguments': arguments, 'result_contract': result_contract}
                        result.append(self.record(f'documented:{api}:{owner}:{version}:{name}', api, owner, 'host', 'all', version, name,
                                                  contract.get('context', ''), {'api': api, 'row': provider, 'surface': 'host', 'operation': name}, provider, name, normalized))
                declared_contracts = self.dictionary(provider.get('host_operation_contracts', ''))
                operations = provider.get('operations', '')
                operations = operations if isinstance(operations, list) else self.tcl.splitlist(operations)
                for name in operations:
                    if name in declared_contracts:
                        continue
                    unknown = {'arguments': [], 'result_contract': 'Not declared by the owner metadata; consult its manual'}
                    result.append(self.record(f'documented:{api}:{owner}:{version}:{name}', api, owner, 'host', 'all', version, name,
                                              provider.get('summary', ''), {'api': api, 'row': provider, 'surface': 'host', 'operation': name}, provider, name, unknown))
            source = next((p for p in providers if p.get('provider') == 'CORE'), providers[0] if providers else {})
            result.append(self.record('family:' + api, api, 'CORE', 'family', 'all', family.get('version', ''), api,
                                      family.get('summary', ''), family, source))
            if family.get('script_descriptor'):
                descriptor = self.dictionary(family['script_descriptor'])
                owner = descriptor['provider_id']
                source = dict(next((p for p in providers if p.get('provider') == owner), source))
                source = self.binding_source(source, descriptor)
                for name, raw_operation in self.dictionary(descriptor['operations']).items():
                    contract = self.dictionary(raw_operation)
                    result.append(self.record(f'script:{api}:{owner}:{name}', api, owner, 'script_bridge', 'all', descriptor['api_version'], name,
                                              contract.get('summary', ''), {'api': api, 'row': contract, 'surface': 'script_bridge', 'operation': name, 'provider': owner}, source, name, contract))
            for method, raw_contract in self.dictionary(family.get('cpp_methods', '')).items():
                contract = self.dictionary(raw_contract)
                header = contract.get('sdk_header', 'core/development/sdk/gxtxt_viewer_sdk_v1.hpp')
                if header not in {'core/development/sdk/gxtxt_viewer_sdk_v1.hpp', 'core/development/sdk/gxtxt_acquisition_sdk_v1.hpp'}:
                    raise ValueError('SDK metadata names an unavailable CORE target header')
                sdk_source = dict(source, provider='CORE', provider_version=bounded_bytes(self.root / 'VERSION.txt', 4096).decode().strip(),
                                  declaration_ref=header, declaration_sha256=sha(self.root / header))
                scope = contract.get('scope') or ('Workspace' if 'gx::Workspace::' in contract.get('signature', '') else 'Host')
                result.append(self.record(f'cpp:{api}:{method}', api, 'CORE', 'cpp_sdk', 'Cpp', family.get('version', ''), scope + '::' + method,
                                          contract.get('signature', ''), {'api': api, 'row': contract, 'surface': 'cpp_sdk', 'operation': method}, sdk_source, method, contract))
        return self.family_provenance(result)

    def save(self, output, records, manifest):
        output.mkdir(parents=True, exist_ok=False)
        database = output / 'catalog.sqlite'
        handle = self.native('open', str(database), IDENTITY)
        try:
            status = self.dictionary(self.native('reconcile', handle, manifest['fingerprint'], tcl_result(records)))
            self.native('validate', handle)
        finally:
            self.native('close', handle)
        with sqlite3.connect(database) as connection:
            if connection.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                raise ValueError('Catalog integrity validation failed')
            connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')
            if connection.execute('PRAGMA journal_mode=DELETE').fetchone() != ('delete',):
                raise ValueError('Packaged catalog seed could not leave WAL mode')
            counts = {name: connection.execute('SELECT count(*) FROM ' + name).fetchone()[0] for name in ('records', 'declaration_sources', 'catalog_source_members', 'operation_visibility', 'operation_arguments')}
        connection.close()
        manifest.update(database_sha256=sha(database, 64 * 1024 * 1024), counts=counts, native_status={k: str(v) for k, v in status.items()})
        (output / 'source_manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        return manifest


def build(catalog, output):
    before = catalog.manifest()
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    result = subprocess.run([sys.executable, '-I', '-B', str(catalog.root / 'core/python/gxtxt_viewer_development.py'), '--api-browser-tcl'],
                            capture_output=True, check=True, timeout=40, env=environment)
    if len(result.stdout) > 16 * 1024 * 1024:
        raise ValueError('Trusted catalog extraction exceeds16MiB')
    response = catalog.dictionary(result.stdout.decode())
    if response.get('ok') != '1':
        raise ValueError(response.get('error', 'Trusted extraction failed'))
    apis = catalog.dictionary(catalog.dictionary(response['result'])['apis'])
    # Packaging-only trusted extraction retains exact binding provenance.
    from gxtxt_script_bridge_server import discover_registrations
    bindings, modules = discover_registrations()
    for api, descriptor in bindings.items():
        family = catalog.dictionary(apis[api])
        descriptor = dict(descriptor)
        declaration = Path(modules[api].__file__).resolve()
        descriptor.update(declaration_ref=declaration.relative_to(catalog.root).as_posix(), declaration_sha256=sha(declaration))
        family['script_descriptor'] = descriptor
        apis[api] = family
    records = catalog.records(apis)
    manifest = catalog.manifest()
    if any(manifest['files'].get(name) != entry for name, entry in before['files'].items()):
        raise ValueError('Sources changed during trusted packaging extraction')
    return catalog.save(output, records, manifest)


def literal_binding(path):
    tree = ast.parse(bounded_bytes(path).decode('utf-8'))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id in {'REGISTRATION', 'REGISTRATIONS'} for target in node.targets):
            value = ast.literal_eval(node.value)
            for statement in tree.body:
                if isinstance(statement, (ast.Import, ast.ImportFrom)):
                    continue
                if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    if statement.decorator_list or statement.args.defaults or any(statement.args.kw_defaults) or statement.returns or any(argument.annotation for argument in statement.args.args):
                        raise ValueError('Decorated/default/annotated binding definitions require packaged extraction')
                    continue
                if isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Constant) and isinstance(statement.value.value, str):
                    continue
                if isinstance(statement, ast.Assign) and all(isinstance(target, ast.Name) for target in statement.targets):
                    ast.literal_eval(statement.value)
                    continue
                raise ValueError('Dynamic top-level binding metadata requires packaged extraction')
            return value if isinstance(value, list) else [value]
    raise ValueError('Binding metadata requires inert declaration/packaged catalog')


def stage(catalog, output):
    packaged = catalog.root / 'core/api_catalog'
    manifest = json.loads(bounded_bytes(packaged / 'source_manifest.json', 4 * 1024 * 1024))
    if manifest.get('schema') != 'gxtxt.api_catalog.sources.v2' or sha(packaged / 'catalog.sqlite', 64 * 1024 * 1024) != manifest['database_sha256']:
        raise ValueError('Packaged catalog is missing, corrupt or incompatible')
    current = catalog.manifest()
    differences = sorted(key for key in set(manifest['files']) | set(current['files']) if manifest['files'].get(key) != current['files'].get(key))
    documents = set(manifest.get('documentation', [])) | set(current.get('documentation', []))
    if any(not name.startswith('plugins/modules/') and name not in documents for name in differences):
        raise ValueError('Changed CORE definitions require a newly packaged catalog; previous snapshot preserved')
    modules = {name.split('/')[2] for name in differences if name.startswith('plugins/modules/')}
    handle = catalog.native('open_readonly', str(packaged / 'catalog.sqlite'), IDENTITY)
    try:
        records = []
        for offset in range(0, 50000, 1000):
            page = catalog.dictionary(catalog.native('query', handle, tcl_result({'offset': offset, 'limit': 1000})))
            rows = [catalog.dictionary(row) for row in catalog.tcl.splitlist(page['rows'])]
            records.extend(rows)
            if len(rows) < 1000:
                break
    finally:
        catalog.native('close', handle)
    pending = []
    original_records = list(records)
    original_families = {row['api_id']: catalog.dictionary(row['payload']) for row in records if row['surface'] == 'family'}
    for module in sorted(modules):
        directory = catalog.root / 'plugins/modules' / module
        records = [row for row in records if row['provider_id'] != module]
        descriptor = directory / 'module.ini'
        if not descriptor.is_file():
            continue
        ini = configparser.ConfigParser(interpolation=None, strict=True)
        ini.read_string(bounded_bytes(descriptor).decode('utf-8'))
        if ini.get('meta', 'id') != module:
            raise ValueError('Module descriptor identity mismatch: ' + module)
        sources = {}
        for api in filter(None, ini.get('public_apis', 'ids', fallback='').split(';')):
            section = 'public_api.' + api
            version = ini.get(section, 'api_version')
            source = {'api_id': api, 'provider': module, 'provider_version': ini.get('meta', 'version'), 'version': version,
                      'declaration_ref': descriptor.relative_to(catalog.root).as_posix(), 'declaration_sha256': sha(descriptor),
                      'documentation': ini.get(section, 'documentation', fallback='docs/api/' + api + '.md'),
                      'name': ini.get(section, 'name', fallback=api), 'enabled': '0', 'pending': '1'}
            if ini.has_option(section, 'public_contract'):
                contract = catalog.dictionary(ini.get(section, 'public_contract'))
                if contract.get('schema') != 'gxtxt.public_api_documentation.v1':
                    raise ValueError('Invalid inert public contract schema: ' + api)
                source['host_operation_contracts'] = contract.get('operations', '')
                source['summary'] = contract.get('purpose', '')
            sources[api] = source
            records.append(catalog.record(f'host:{api}:{module}:{version}', api, module, 'host', 'all', version, module,
                                          source.get('summary', ''), {'api': api, 'row': source, 'surface': 'host'}, source))
            for name, value in catalog.dictionary(source.get('host_operation_contracts', '')).items():
                contract = catalog.dictionary(value)
                if any(key not in contract for key in ('command', 'arguments', 'parameters', 'result', 'context')) or not catalog.dictionary(contract['result']).get('type'):
                    raise ValueError('Invalid documented operation contract: ' + api + '/' + name)
                arguments = catalog.host_arguments(contract)
                normalized = {'arguments': arguments, 'result_contract': catalog.dictionary(contract.get('result', '')).get('description', '')}
                records.append(catalog.record(f'documented:{api}:{module}:{version}:{name}', api, module, 'host', 'all', version, name,
                                              contract.get('context', ''), {'api': api, 'row': source, 'surface': 'host', 'operation': name}, source, name, normalized))
        for path in sorted((directory / 'api').glob('script_bridge_binding*.py')):
            relative = path.relative_to(catalog.root).as_posix()
            prior = manifest['files'].get(relative, {})
            if prior.get('sha256') == sha(path):
                for old in original_records:
                    if old['provider_id'] != module or old['surface'] != 'script_bridge':
                        continue
                    payload = catalog.dictionary(old['payload'])
                    if catalog.dictionary(payload.get('catalog_meta', '')).get('declaration_ref') != relative:
                        continue
                    contract = catalog.dictionary(payload['row'])
                    api = old['api_id']
                    if api not in sources or old['version'] != sources[api]['version']:
                        pending.append({'module': module, 'source': relative, 'reason': 'Registered API version differs from changed descriptor'})
                        continue
                    source = dict(sources[api], declaration_ref=relative, declaration_sha256=sha(path))
                    previous = catalog.dictionary(payload.get('catalog_meta', ''))
                    descriptor = catalog.dictionary(original_families.get(api, {}).get('script_descriptor', ''))
                    if descriptor.get('documentation_ref'):
                        source = catalog.binding_source(source, {'documentation_ref': descriptor['documentation_ref']})
                    elif previous.get('documentation'):
                        source['documentation'] = previous['documentation']
                    records.append(catalog.record(old['id'], api, module, 'script_bridge', old['language'], old['version'], old['title'], old['summary'], payload, source, payload['operation'], contract))
                continue
            try:
                bindings = literal_binding(path)
            except (ValueError, TypeError, KeyError, SyntaxError) as error:
                pending.append({'module': module, 'source': relative, 'reason': 'Unsupported inert extraction: ' + str(error)})
                continue
            for binding in bindings:
                api = binding['api_id']
                if binding['provider_id'] != module or not ini.has_section('public_api.' + api) or str(binding['api_version']) != ini.get('public_api.' + api, 'api_version'):
                    raise ValueError('Script registration owner/version differs')
                for name, contract in binding['operations'].items():
                    if contract.get('name') != name or not isinstance(contract.get('arguments'), list) or not contract.get('result_contract') or not contract.get('summary'):
                        raise ValueError('Script operation lacks an explicit argument/result contract')
                    for argument in contract['arguments']:
                        if not isinstance(argument, dict) or not argument.get('name') or not argument.get('kind') or type(argument.get('required', True)) is not bool:
                            raise ValueError('Invalid explicit Script Bridge argument contract')
                    records.append(catalog.record(f'script:{api}:{module}:{name}', api, module, 'script_bridge', 'all', binding['api_version'], name,
                                                  contract.get('summary', ''), {'api': api, 'row': contract, 'surface': 'script_bridge', 'operation': name, 'provider': module}, catalog.binding_source(dict(sources[api], declaration_ref=relative, declaration_sha256=sha(path)), binding), name, contract))
    for record in records:
        payload = catalog.dictionary(record['payload'])
        metadata = catalog.dictionary(payload.get('catalog_meta', ''))
        metadata['documentation'], metadata['documentation_status'] = catalog.resolve_documentation(metadata.get('documentation', ''), record['provider_id'])
        payload['catalog_meta'] = metadata
        record['payload'] = payload
    # Rebuild families from provider-qualified rows; removed providers cannot
    # survive through a stale CORE-owned family presentation record.
    records = rebuild_families(catalog, records)
    unique = {}
    for record in records:
        if record['id'] in unique and record != unique[record['id']]:
            raise ValueError('Conflicting catalog record identity: ' + record['id'])
        unique[record['id']] = record
    if catalog.manifest()['fingerprint'] != current['fingerprint']:
        raise ValueError('Sources changed during inert reconciliation; previous snapshot preserved')
    current['pending_metadata'] = pending
    current['changed_modules'] = sorted(modules)
    current['admission'] = 'next_process_snapshot_only'
    return catalog.save(output, list(unique.values()), current)


def rebuild_families(catalog, records):
    records = [row for row in records if row['surface'] != 'family']
    groups = {}
    for row in records:
        groups.setdefault(row['api_id'], []).append(row)
    result = []
    for api, rows in sorted(groups.items()):
        hosts = [row for row in rows if row['surface'] == 'host' and row['id'].startswith('host:')]
        scripts = [row for row in rows if row['surface'] == 'script_bridge']
        if not hosts and not scripts:
            continue
        result.extend(rows)
        providers = [catalog.dictionary(catalog.dictionary(row['payload'])['row']) for row in hosts]
        versions = {str(row['version']) for row in hosts + scripts}
        family = dict(providers[0]) if providers else {'api_id': api, 'provider': scripts[0]['provider_id'], 'version': scripts[0]['version']}
        family.update(api_id=api, providers=tcl_result(providers), version_conflict=int(len(versions) > 1))
        if len(providers) > 1:
            family['provider'] = ''
            family['provider_selection'] = 'multiple_declaring_owners; inspect provider-qualified declaration'
        if len(versions) > 1:
            family['version'] = ''
            family['provider_selection'] = 'conflicting_declared_versions; inspect provider-qualified declaration'
        if scripts:
            owners = {row['provider_id'] for row in scripts}
            if len(owners) != 1:
                raise ValueError('Conflicting Script Bridge declaring providers: ' + api)
            operations = {catalog.dictionary(row['payload'])['operation']: catalog.dictionary(catalog.dictionary(row['payload'])['row']) for row in scripts}
            family['script_descriptor'] = {'api_id': api, 'api_version': scripts[0]['version'], 'provider_id': scripts[0]['provider_id'], 'operations': operations}
        methods = {catalog.dictionary(row['payload'])['operation']: catalog.dictionary(catalog.dictionary(row['payload'])['row']) for row in rows if row['surface'] == 'cpp_sdk'}
        family['cpp_methods'] = methods
        family['sdk_exposed'] = int(bool(methods))
        source = catalog.dictionary(catalog.dictionary(rows[0]['payload']).get('catalog_meta', ''))
        result.append(catalog.record('family:' + api, api, 'CORE', 'family', 'all', family.get('version', ''), api, family.get('summary', ''), family, source))
    return catalog.family_provenance(result)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['build', 'stage'])
    parser.add_argument('framework', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    catalog = Catalog(args.framework.resolve())
    manifest = (build if args.operation.lstrip('-') == 'build' else stage)(catalog, args.output)
    print(tcl_result({'ok': True, 'result': {'schema': manifest['schema'], 'fingerprint': manifest['fingerprint'], 'output': str(args.output), 'pending_metadata': manifest.get('pending_metadata', [])}}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(tcl_result({'ok': False, 'error': str(error)}), flush=True)
        raise SystemExit(1)
