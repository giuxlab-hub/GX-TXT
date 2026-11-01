# SPDX-License-Identifier: GPL-3.0-or-later
"""Target-specific Acquisition project model for the existing Development owner.

This module validates/describes and plans edits. The caller owns the existing
ProjectFiles lock, write grant, atomic publisher and managed request lifecycle.
It grants no source access, helper execution, compilation or publication.
"""
from __future__ import annotations
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat

SCHEMA = 'gxtxt.acquisition_development_project.v1'
EDIT_SCHEMA = 'gxtxt.development_project_edit.v1'
DESCRIPTION_SCHEMA = 'gxtxt.development_project_description.v1'
MAX_FILE_BYTES = 65536
MAX_TEXT_BYTES = 1048576
MAX_FILES = 32
MAX_HELPERS = 32
MAX_FORMATS = 32
FIELDS = {'schema', 'module_id', 'version', 'name', 'description', 'license',
          'language', 'profile', 'source', 'source_files', 'helpers', 'formats',
          'capabilities', 'dependencies', 'provenance', 'tests'}
METADATA_FIELDS = {'module_id', 'version', 'name', 'description', 'license',
                   'capabilities', 'dependencies', 'provenance', 'tests', 'config_fields',
                   'input_contracts','provided_contracts'}
OPTIONAL_FIELDS={'config_fields','input_contracts','provided_contracts'}
CONFIG_TYPES = {'string','integer','number','double','boolean','choice'}
MAX_CONFIG_FIELDS = 32
IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$')
QUALIFIED_CPP = re.compile(r'^(?:::)?[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$')
STARTER = b'// SPDX-License-Identifier: GPL-3.0-or-later\n// Declare Acquisition callbacks here; no parser has been authored yet.\n'

class ProjectError(ValueError):
    def __init__(self, message, code='PROJECT_INVALID'):
        super().__init__(message)
        self.code = code

def fail(message, code='PROJECT_INVALID'):
    raise ProjectError(message, code)

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def encode(value):
    try:
        return (json.dumps(value, ensure_ascii=False, allow_nan=False,
                           sort_keys=True, indent=2) + '\n').encode('utf-8')
    except (ValueError, UnicodeError, TypeError) as error:
        raise ProjectError('Project metadata requires finite inert UTF-8 JSON') from error

def decode(raw):
    try:
        value = json.loads(raw.decode('utf-8'), parse_constant=lambda value: fail('Nonfinite JSON is forbidden'))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ProjectError('Project metadata is not bounded UTF-8 JSON') from error
    return value

def text(value, label, limit=512, empty=False):
    if not isinstance(value, str) or (not empty and not value.strip()):
        fail(label + ' must be text', 'PROJECT_METADATA')
    try:
        raw = value.encode('utf-8')
    except UnicodeError as error:
        raise ProjectError(label + ' must be UTF-8', 'PROJECT_ENCODING') from error
    if len(raw) > limit or any(ord(c) < 32 for c in value):
        fail(label + ' exceeds its one-line text bound', 'PROJECT_METADATA')
    return value

def string_list(value, label, maximum=64):
    if not isinstance(value, list) or len(value) > maximum:
        fail(label + ' must be a bounded list', 'PROJECT_METADATA')
    result = [text(item, label, 256) for item in value]
    if len(set(result)) != len(result):
        fail(label + ' must contain unique values', 'PROJECT_METADATA')
    return result

def json_object(value, label):
    if not isinstance(value, dict) or len(encode(value)) > 32768:
        fail(label + ' must be a bounded JSON object', 'PROJECT_METADATA')
    nodes = 0
    def visit(item, depth):
        nonlocal nodes
        nodes += 1
        if nodes > 4096 or depth > 16:
            fail(label + ' exceeds its nested metadata bound', 'PROJECT_METADATA')
        if item is None or isinstance(item, (str, bool, int)):
            if isinstance(item, str) and ('\0' in item or len(item.encode('utf-8')) > 8192):
                fail(label + ' has an invalid text value', 'PROJECT_METADATA')
        elif isinstance(item, float):
            if not math.isfinite(item): fail(label + ' contains nonfinite metadata')
        elif isinstance(item, list):
            for child in item: visit(child, depth + 1)
        elif isinstance(item, dict):
            for key, child in item.items():
                text(key, label + ' key', 128)
                visit(child, depth + 1)
        else:
            fail(label + ' contains a non-JSON value', 'PROJECT_METADATA')
    visit(value, 0)
    return value

def relative(name, language='cpp'):
    text(name, 'Relative file name', 192)
    if ('\\' in name or name.startswith('/') or
            any(part in {'', '.', '..'} for part in name.split('/')) or
            not re.fullmatch(r'[A-Za-z0-9_./-]+', name)):
        fail('Project source requires an ordinary relative path', 'SOURCE_TARGET')
    valid = (name == 'handlers.cpp' or name.startswith('src/') and name.endswith('.cpp')
             or name.startswith('include/') and name.endswith('.hpp')) if language == 'cpp' else (
             name.startswith('helpers/') and name.endswith('.py' if language == 'Python' else '.tcl'))
    if not valid:
        fail('Source path does not match its declared project language/role', 'SOURCE_TARGET')
    return name

def source_bytes(source, label='Source'):
    if not isinstance(source, str): fail(label + ' must be UTF-8 text', 'SOURCE_ENCODING')
    try: raw = source.encode('utf-8')
    except UnicodeError as error: raise ProjectError(label + ' is not UTF-8', 'SOURCE_ENCODING') from error
    if len(raw) > MAX_FILE_BYTES or b'\0' in raw:
        fail(label + ' exceeds 64 KiB or contains NUL', 'SOURCE_BOUND')
    return raw

def ordinary_read(project, name, limit=MAX_FILE_BYTES):
    path = project / name
    if any(p.is_symlink() for p in [path, *path.parents]):
        fail('Project source/ancestors must not be linked', 'SOURCE_TARGET')
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
                fail('Project source must be an ordinary bounded unlinked file', 'SOURCE_TARGET')
            raw = stream.read(limit + 1)
            after = os.fstat(stream.fileno())
            current = os.stat(path, follow_symlinks=False)
    except OSError as error:
        raise ProjectError('Registered source is unavailable: ' + name, 'SOURCE_TARGET') from error
    def identity(info):
        return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
                info.st_size, info.st_mtime_ns, info.st_ctime_ns)
    if len(raw) > limit or identity(before) != identity(after) or identity(after) != identity(current):
        fail('Source changed while reading: ' + name, 'SOURCE_CHANGED')
    if b'\0' in raw:
        fail('Project text contains NUL: ' + name, 'SOURCE_ENCODING')
    try: raw.decode('utf-8')
    except UnicodeError as error: raise ProjectError('Project source is not UTF-8: ' + name, 'SOURCE_ENCODING') from error
    return raw

def helper_validate(helper):
    expected = {'id', 'path', 'language', 'role', 'entrypoint'}
    if not isinstance(helper, dict) or set(helper) != expected:
        fail('Helper requires id/path/language/role/entrypoint', 'PROJECT_HELPER')
    if not isinstance(helper['id'], str) or not IDENTIFIER.fullmatch(helper['id']) or not isinstance(helper['language'], str) or helper['language'] not in {'Tcl', 'Python'} or helper['role'] != 'runtime_helper':
        fail('Invalid typed runtime helper declaration', 'PROJECT_HELPER')
    relative(helper['path'], helper['language'])
    symbol = text(helper['entrypoint'], 'Helper entrypoint', 192)
    pattern = QUALIFIED_CPP if helper['language'] == 'Tcl' else re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$')
    if not pattern.fullmatch(symbol) or any(part.startswith('__') for part in symbol.replace('::', '.').split('.')):
        fail('Helper entrypoint requires a finite declared function name', 'PROJECT_HELPER')

def profile_validate(profile, names):
    expected = {'id', 'name', 'source_kind', 'file_patterns', 'mime_types', 'recognize',
                'inspect', 'import', 'output_contracts', 'capabilities', 'dependencies', 'limits'}
    if not isinstance(profile, dict) or set(profile) != expected:
        fail('Profile fields must match the declared Acquisition profile schema', 'PROJECT_PROFILE')
    if not isinstance(profile['id'], str) or not re.fullmatch(r'[a-z][a-z0-9_-]{0,47}', profile['id']):
        fail('Profile ID must be module-local lowercase text', 'PROJECT_PROFILE')
    text(profile['name'], 'Profile name', 256)
    if not isinstance(profile['source_kind'], str) or profile['source_kind'] not in {'text', 'binary'}: fail('Profile source_kind must be text or binary', 'PROJECT_PROFILE')
    for key in ('file_patterns', 'mime_types', 'output_contracts', 'dependencies'):
        string_list(profile[key], 'Profile ' + key, 64)
    if not profile['output_contracts']: fail('Profile requires declared output contracts', 'PROJECT_PROFILE')
    for key in ('recognize', 'inspect', 'import'):
        binding = profile[key]
        if not isinstance(binding, dict) or set(binding) != {'file', 'symbol'}:
            fail('Profile binding requires registered file and C++ symbol', 'PROJECT_PROFILE')
        if binding['file'] not in names or not isinstance(binding['symbol'], str) or not QUALIFIED_CPP.fullmatch(binding['symbol']) or len(binding['symbol']) > 256:
            fail('Profile callback must refer to a registered C++ source/header and finite qualified symbol', 'PROJECT_PROFILE')
    capabilities_validate(profile['capabilities'])
    limits = profile['limits']
    if not isinstance(limits, dict) or len(limits) > 16:
        fail('Profile limits require a bounded map', 'PROJECT_PROFILE')
    for key, value in limits.items():
        if not re.fullmatch(r'[a-z][a-z0-9_]{0,47}', key) or type(value) is not int or value < 0 or value > 2**63 - 1:
            fail('Profile limits require named nonnegative exact integers', 'PROJECT_PROFILE')

def capabilities_validate(value):
    if not isinstance(value, list) or len(value) > 32:
        fail('Capabilities require a bounded typed list', 'PROJECT_CAPABILITY')
    seen = set()
    for item in value:
        if not isinstance(item, dict) or set(item) != {'api_id', 'version', 'operations'}:
            fail('Capability requires api_id/version/operations', 'PROJECT_CAPABILITY')
        api = text(item['api_id'], 'Public API ID', 128)
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*_v[0-9]+', api) or api in seen or type(item['version']) is not int or item['version'] < 1:
            fail('Invalid or duplicate public API capability declaration', 'PROJECT_CAPABILITY')
        string_list(item['operations'], 'Capability operations', 128)
        seen.add(api)

def config_value(field,value):
    """Validate already typed inert data, without parsing/filling ModuleCfg."""
    kind=field['type']
    if kind=='boolean':
        if type(value) is not bool:fail('Boolean configuration requires a typed boolean','PROJECT_CONFIG')
    elif kind=='integer':
        if type(value) is not int or not -(2**63)<=value<2**63:fail('Integer configuration exceeds signed 64-bit type','PROJECT_CONFIG')
    elif kind in {'number','double'}:
        try:valid=type(value) in {int,float} and math.isfinite(float(value))
        except (OverflowError,ValueError):valid=False
        if not valid:fail('Numeric configuration requires a finite typed number','PROJECT_CONFIG')
    else:
        if not isinstance(value,str) or len(value.encode('utf-8'))>4096 or any(ord(c)<32 for c in value) or value!=value.strip():
            fail('Configuration text must roundtrip the existing single-line Module descriptor without trimming','PROJECT_CONFIG')
        if field['required'] and value=='':fail('Required configuration text is empty','PROJECT_CONFIG')
        if kind=='choice' and value not in field['values'] and (value!='' or field['required']):fail('Configuration choice is not declared','PROJECT_CONFIG')
    if kind in {'integer','number','double'}:
        if 'min' in field and value<field['min'] or 'max' in field and value>field['max']:fail('Configuration value is outside its declared range','PROJECT_CONFIG')
    return copy.deepcopy(value)

def config_fields_validate(fields):
    if not isinstance(fields,list) or len(fields)>MAX_CONFIG_FIELDS or len(encode(fields))>32768:fail('Configuration schema requires at most 32 fields and 32 KiB','PROJECT_CONFIG')
    seen=set()
    for field in fields:
        if not isinstance(field,dict) or not {'id','type','label','default','required'}.issubset(field) or set(field)-{'id','type','label','default','required','values','min','max'}:
            fail('Configuration fields require id/type/label/default/required and finite optional constraints','PROJECT_CONFIG')
        identity=field['id'];kind=field['type']
        if not isinstance(identity,str) or not re.fullmatch(r'[a-z][a-z0-9_]{0,47}',identity) or identity=='format_profile' or identity in seen:fail('Duplicate/reserved/invalid configuration field ID','PROJECT_CONFIG')
        if not isinstance(kind,str) or kind not in CONFIG_TYPES or type(field['required']) is not bool:fail('Only declared inert scalar configuration types are supported','PROJECT_CONFIG')
        text(field['label'],'Configuration label',256)
        if field['label']!=field['label'].strip():fail('Configuration label must roundtrip Module descriptor whitespace','PROJECT_CONFIG')
        seen.add(identity)
        if kind=='choice':
            values=field.get('values')
            if not isinstance(values,list) or not 1<=len(values)<=64:fail('Choice requires 1..64 explicit values','PROJECT_CONFIG')
            string_list(values,'Configuration choices',64)
            if any(value!=value.strip() or ',' in value or ';' in value for value in values):fail('Choice values cannot change under Module splitList parsing','PROJECT_CONFIG')
        elif 'values' in field:fail('Only choice configuration has values','PROJECT_CONFIG')
        if kind not in {'integer','number','double'} and set(field)&{'min','max'}:fail('Only numeric configuration has min/max','PROJECT_CONFIG')
        for key in ('min','max'):
            if key not in field:continue
            if type(field[key]) not in {int,float} or kind=='integer' and type(field[key]) is not int:fail('Configuration bounds require the declared numeric type','PROJECT_CONFIG')
            probe=dict(field);probe.pop('min',None);probe.pop('max',None)
            config_value(probe,field[key])
        if 'min' in field and 'max' in field and field['min']>field['max']:fail('Configuration min exceeds max','PROJECT_CONFIG')
        config_value(field,field['default'])
    return fields

def config_schema_sha256(meta):
    return digest(encode(config_fields_validate(meta.get('config_fields',[]))))

def typed_config_payload(meta,values):
    """Read-only payload typing after CORE normalized its actual ModuleCfg.

    This is not an authority/default store. Caller binds schema/config hashes to
    the live registered module/profile scope. Unknown/missing keys refuse.
    """
    fields=config_fields_validate(meta.get('config_fields',[]));ids={row['id'] for row in fields}|{'format_profile'}
    if not isinstance(values,dict) or set(values)!=ids:fail('Configuration snapshot must contain exactly its declared fields and format_profile','PROJECT_CONFIG')
    if not isinstance(values['format_profile'],str) or values['format_profile'] not in {p['id'] for p in meta['formats']}:fail('Configuration profile is not declared','PROJECT_CONFIG')
    result={'format_profile':values['format_profile']}
    for field in fields:
        value=config_value(field,values[field['id']])
        # Core's declared numeric type is explicit; no spelling-based inference.
        result[field['id']]=float(value) if field['type'] in {'number','double'} else value
    if len(encode(result))>65536:fail('Typed configuration snapshot exceeds 64 KiB','PROJECT_CONFIG')
    return result

def contract_ids(value,label,maximum=64):
    if not isinstance(value,list) or len(value)>maximum:fail(label+' exceeds its bounded ID list','PROJECT_CONTRACT')
    for identity in value:
        # Existing CORE literal Contract identifier, including media-style IDs.
        if not isinstance(identity,str) or len(identity)>128 or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:+/-]*',identity):
            fail(label+' requires literal Contract Registry IDs','PROJECT_CONTRACT')
    if len(value)!=len(set(value)):fail(label+' contains duplicate IDs','PROJECT_CONTRACT')
    return value

def contract_declarations(meta):
    inputs=contract_ids(meta.get('input_contracts',[]),'Input contracts')
    provided=meta.get('provided_contracts',[])
    if not isinstance(provided,list) or len(provided)>64:fail('At most 64 provided contracts may be declared','PROJECT_CONTRACT')
    graph={}
    for row in provided:
        if not isinstance(row,dict) or set(row)!={'id','description','parents'}:fail('Provided contract requires id/description/parents only','PROJECT_CONTRACT')
        identity=contract_ids([row['id']],'Provided contract')[0]
        if identity in graph:fail('Duplicate provided contract identity','PROJECT_CONTRACT')
        text(row['description'],'Contract description',2048)
        if row['description']!=row['description'].strip():fail('Contract description must roundtrip Module descriptor whitespace','PROJECT_CONTRACT')
        parents=contract_ids(row['parents'],'Contract parents')
        if identity in parents:fail('Contract cannot inherit from itself','PROJECT_CONTRACT')
        graph[identity]=parents
    done=set();active=set()
    def visit(identity):
        if identity in active:fail('Provided contract declarations contain an inheritance cycle','PROJECT_CONTRACT')
        if identity in done:return
        active.add(identity)
        for parent in graph[identity]:
            if parent in graph:visit(parent)
        active.remove(identity);done.add(identity)
    for identity in graph:visit(identity)
    result={'input_contracts':inputs,'provided_contracts':provided}
    if len(encode(result))>32768:fail('Contract declarations exceed 32 KiB','PROJECT_CONTRACT')
    return copy.deepcopy(result)

def contract_declarations_sha256(meta):
    return digest(encode(contract_declarations(meta)))

def validate(meta):
    if not isinstance(meta, dict) or set(meta)-FIELDS-OPTIONAL_FIELDS or FIELDS-set(meta) or meta.get('schema') != SCHEMA:
        fail('Unknown Acquisition project schema/fields', 'PROJECT_POLICY')
    if meta['language'] != 'cpp' or meta['profile'] != 'acquisition_v1' or meta['source'] != 'handlers.cpp':
        fail('Acquisition target cannot override compiler/language/entrypoint policy', 'PROJECT_POLICY')
    module = text(meta['module_id'], 'Module ID', 128)
    if not re.fullmatch(r'[a-z][a-z0-9_.-]*', module) or module.endswith('.') or '..' in module:
        fail('Invalid Module ID', 'PROJECT_METADATA')
    if not isinstance(meta['version'], str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', meta['version']):
        fail('Version must be major.minor.patch', 'PROJECT_METADATA')
    text(meta['name'], 'Module name', 256)
    text(meta['description'], 'Description', 2048, empty=True)
    text(meta['license'], 'License declaration', 256)
    names = meta['source_files']
    if not isinstance(names, list) or not 1 <= len(names) <= MAX_FILES or names[0] != 'handlers.cpp' or any(not isinstance(n, str) for n in names) or len(set(names)) != len(names):
        fail('Acquisition source_files requires 1..32 unique compiled files with handlers.cpp first', 'PROJECT_SOURCES')
    for name in names: relative(name)
    helpers = meta['helpers']
    if not isinstance(helpers, list) or len(helpers) > MAX_HELPERS:
        fail('Acquisition helpers exceed their roster bound', 'PROJECT_HELPER')
    ids = set(); paths = set(names)
    for helper in helpers:
        helper_validate(helper)
        if helper['id'] in ids or helper['path'] in paths: fail('Duplicate helper identity/path', 'PROJECT_HELPER')
        ids.add(helper['id']);paths.add(helper['path'])
    formats = meta['formats']
    if not isinstance(formats, list) or len(formats) > MAX_FORMATS:
        fail('Acquisition formats require at most 32 profiles', 'PROJECT_PROFILE')
    ids = set()
    for profile in formats:
        profile_validate(profile, names)
        if profile['id'] in ids: fail('Duplicate module-local profile ID', 'PROJECT_PROFILE')
        ids.add(profile['id'])
    capabilities_validate(meta['capabilities'])
    config_fields_validate(meta.get('config_fields',[]))
    contract_declarations(meta)
    string_list(meta['dependencies'], 'Dependencies')
    json_object(meta['provenance'], 'Declared project provenance')
    json_object(meta['tests'], 'Tests')
    if len(encode(meta)) > MAX_FILE_BYTES: fail('Project manifest exceeds 64 KiB', 'PROJECT_BOUND')
    return meta

def roster(meta):
    rows = [{'relative': name, 'language': 'cpp', 'role': 'entrypoint' if name == 'handlers.cpp' else 'header' if name.endswith('.hpp') else 'translation_unit'} for name in meta['source_files']]
    rows.extend(dict(relative=h['path'], language=h['language'], role=h['role'], helper_id=h['id']) for h in meta['helpers'])
    return rows

def state(project, *, authoring_payload=None):
    raw = ordinary_read(project, 'project.json')
    meta = validate(decode(raw))
    files = {row['relative']: ordinary_read(project, row['relative']) for row in roster(meta)}
    if sum(map(len, files.values())) > MAX_TEXT_BYTES: fail('Project text closure exceeds 1 MiB', 'PROJECT_BOUND')
    import gxtxt_acquisition_source_notes_v1 as notes
    notes.validate(project,meta,files,authoring_payload)
    return meta, raw, files

def description(meta, raw, files):
    manifest = []
    for row in roster(meta):
        row = dict(row)
        content = files[row['relative']]
        entries = [p[key]['symbol'] for p in meta['formats'] for key in ('recognize', 'inspect', 'import') if p[key]['file'] == row['relative']]
        if row['role'] == 'runtime_helper':
            entries = [next(h['entrypoint'] for h in meta['helpers'] if h['path'] == row['relative'])]
        row.update(editable=True, size_bytes=len(content), sha256=digest(content), declared_entrypoints=sorted(set(entries)), validated_entrypoints=[], binding_status='unvalidated')
        row['source_notes_available']=row['language'] in {'cpp','Python'}
        row['source_notes_language']='cpp' if row['language']=='cpp' else 'python' if row['language']=='Python' else None
        row['source_notes_reason']='Existing SourceAuthoring owner' if row['source_notes_available'] else 'Tcl helper notes are unavailable in the existing SourceAuthoring owner; helper source remains editable'
        manifest.append(row)
    tree = digest(encode([{k: row[k] for k in ('relative', 'language', 'role', 'size_bytes', 'sha256')} for row in manifest]))
    project_sha = digest(raw)
    revision = 'development-project-revision-v1:' + digest(encode({'project_sha256': project_sha, 'source_tree_sha256': tree}))
    return {'schema': DESCRIPTION_SCHEMA, 'status': 'CATALOG', 'target': 'acquisition', 'project_schema': SCHEMA,
            'module_id': meta['module_id'], 'version': meta['version'], 'project_sha256': project_sha,
            'revision': revision, 'source_tree_sha256': tree, 'metadata': {key: meta.get(key,[]) if key in OPTIONAL_FIELDS else meta[key] for key in sorted(METADATA_FIELDS)},
            'config_fields':copy.deepcopy(meta.get('config_fields',[])),'config_schema_sha256':config_schema_sha256(meta),
            **contract_declarations(meta),'contract_declarations_sha256':contract_declarations_sha256(meta),
            'contract_declarations_status':'structural_declarations_only; actual Registry/provider/dependency compatibility is CORE-owned',
            'files': manifest, 'formats': copy.deepcopy(meta['formats']),
            'profile_sha256': {p['id']: digest(encode(p)) for p in meta['formats']},
            'limits': {'max_compiled_files': MAX_FILES, 'max_helpers': MAX_HELPERS, 'max_file_bytes': MAX_FILE_BYTES,
                       'max_text_bytes': MAX_TEXT_BYTES, 'max_formats': MAX_FORMATS,'max_config_fields':MAX_CONFIG_FIELDS},
            'build_available': True, 'runtime_available': False, 'project_test_available': True,
            'source_notes_available': True,
            'source_notes_reason': 'Existing SourceAuthoring owner; consult each file language/availability',
            'availability_reason': 'Actual Validate/Build/Export and explicit selected-source project Test use the existing admitted native CORE owners; Test discards outputs and never installs or publishes.'}

def defaults(metadata):
    if not isinstance(metadata, dict) or set(metadata) - METADATA_FIELDS:
        fail('New Acquisition project accepts declared metadata fields only', 'PROJECT_METADATA')
    result = {'schema': SCHEMA, 'module_id': '', 'version': '1.0.0', 'name': '', 'description': '',
              'license': 'GPL-3.0-or-later', 'language': 'cpp', 'profile': 'acquisition_v1', 'source': 'handlers.cpp',
              'source_files': ['handlers.cpp'], 'helpers': [], 'formats': [], 'capabilities': [],
              'dependencies': [], 'provenance': {}, 'tests': {},'config_fields':[],
              'input_contracts':[],'provided_contracts':[]}
    result.update(copy.deepcopy(metadata))
    if isinstance(result.get('provenance'), dict) and 'source_authoring_v1' in result['provenance']:
        fail('New projects cannot supply a Source Note owner pointer', 'SOURCE_NOTES')
    return validate(result)

def prepare_edit(project, payload):
    meta, raw, files = state(project)
    desc = description(meta, raw, files)
    if not isinstance(payload, dict) or payload.get('schema') != EDIT_SCHEMA:
        fail('Acquisition ProjectFiles requires its versioned request schema', 'PROJECT_REQUEST')
    op = payload.get('operation')
    if op == 'describe':
        if set(payload) != {'schema', 'operation'}: fail('Describe accepts no extra fields', 'PROJECT_REQUEST')
        return desc, None
    if payload.get('expected_revision') != desc['revision']:
        fail('Project/source closure changed; refresh before saving', 'SOURCE_CHANGED')
    if op == 'read':
        if set(payload) != {'schema', 'operation', 'relative', 'expected_revision'}: fail('Read fields are invalid', 'PROJECT_REQUEST')
        name = payload['relative']
        if name not in files and name != 'project.json': fail('Read requires a registered project source', 'SOURCE_TARGET')
        content = raw if name == 'project.json' else files[name]
        return {'status': 'SAVED', 'relative': name, 'source': content.decode('utf-8'), 'sha256': digest(content), 'size_bytes': len(content), 'revision': desc['revision']}, None
    candidate = copy.deepcopy(meta);updated = dict(files);removed = [];encoded = {}
    common = {'schema', 'operation', 'expected_revision'}
    def fields(keys):
        if set(payload) != common | set(keys): fail('Unknown or missing ProjectFiles operation fields', 'PROJECT_REQUEST')
    def match_file(name):
        if name not in files or name == 'handlers.cpp': fail('Choose a registered auxiliary file', 'SOURCE_TARGET')
        if payload.get('expected_sha256') != digest(files[name]): fail('Source changed externally', 'SOURCE_CHANGED')
    if op == 'add':
        fields({'file', 'source'})
        row = payload['file']
        if not isinstance(row, dict): fail('Add requires a typed file descriptor', 'SOURCE_TARGET')
        language = row.get('language');role = row.get('role');name = row.get('relative')
        if language == 'cpp':
            if set(row) != {'relative', 'language', 'role'}: fail('C++ file fields are invalid', 'SOURCE_TARGET')
            relative(name)
            if name == 'handlers.cpp' or role != ('header' if name.endswith('.hpp') else 'translation_unit'): fail('C++ auxiliary role does not match path', 'SOURCE_TARGET')
            candidate['source_files'].append(name)
        else:
            if set(row) != {'relative', 'language', 'role', 'helper_id', 'entrypoint'}: fail('Helper file fields are invalid', 'SOURCE_TARGET')
            helper = dict(id=row['helper_id'], path=name, language=language, role=role, entrypoint=row['entrypoint'])
            helper_validate(helper);candidate['helpers'].append(helper)
        if name in files or (project/name).exists() or (project/name).is_symlink(): fail('Source target already exists', 'SOURCE_TARGET')
        encoded[name] = source_bytes(payload['source']);updated[name] = encoded[name]
    elif op in {'remove', 'rename'}:
        fields({'relative', 'expected_sha256'} | ({'target'} if op == 'rename' else set()))
        name = payload['relative'];match_file(name)
        if any(p[k]['file'] == name for p in candidate['formats'] for k in ('recognize', 'inspect', 'import')) and op == 'remove':
            fail('Remove or change profile bindings before removing their source', 'PROJECT_PROFILE')
        if op == 'remove':
            candidate['source_files'] = [n for n in candidate['source_files'] if n != name]
            candidate['helpers'] = [h for h in candidate['helpers'] if h['path'] != name]
        else:
            target = payload['target'];language = next(r['language'] for r in roster(meta) if r['relative'] == name);relative(target, language)
            if target in files or (project/target).exists() or (project/target).is_symlink(): fail('Rename destination already exists', 'SOURCE_TARGET')
            if language == 'cpp' and name.endswith('.hpp') != target.endswith('.hpp'): fail('Rename must preserve compiled role', 'SOURCE_TARGET')
            candidate['source_files'] = [target if n == name else n for n in candidate['source_files']]
            for h in candidate['helpers']:
                if h['path'] == name: h['path'] = target
            for profile in candidate['formats']:
                for key in ('recognize', 'inspect', 'import'):
                    if profile[key]['file'] == name: profile[key]['file'] = target
            updated[target] = encoded[target] = updated[name]
        removed.append(name);updated.pop(name)
    elif op == 'save_all':
        fields({'files'})
        changes = payload['files']
        if not isinstance(changes, dict) or not 1 <= len(changes) <= 65: fail('Save All requires bounded changed files', 'SOURCE_TARGET')
        for name, item in changes.items():
            if name not in files and name != 'project.json': fail('Save target is not registered', 'SOURCE_TARGET')
            if not isinstance(item, dict) or set(item) != {'source', 'expected_sha256'}: fail('Save All file fields are invalid', 'SOURCE_TARGET')
            old = raw if name == 'project.json' else files[name]
            if item['expected_sha256'] != digest(old): fail('Source changed externally: ' + name, 'SOURCE_CHANGED')
            content = source_bytes(item['source']);encoded[name] = content
            if name == 'project.json':
                candidate = validate(decode(content))
                if candidate['source_files'] != meta['source_files'] or candidate['helpers'] != meta['helpers']:
                    fail('Use typed source actions to change the registered roster', 'PROJECT_SOURCES')
            else: updated[name] = content
    elif op in {'profile_put', 'profile_remove'}:
        fields({'profile', 'expected_profile_sha256'} if op == 'profile_put' else {'profile_id', 'expected_profile_sha256'})
        profile = payload.get('profile');identity = profile.get('id') if isinstance(profile, dict) else payload.get('profile_id')
        old = next((p for p in meta['formats'] if p['id'] == identity), None)
        if payload['expected_profile_sha256'] != (digest(encode(old)) if old is not None else None): fail('Profile changed externally', 'SOURCE_CHANGED')
        if op == 'profile_remove' and old is None: fail('Profile is not registered', 'PROJECT_PROFILE')
        if op == 'profile_put': profile_validate(profile, candidate['source_files'])
        candidate['formats'] = [copy.deepcopy(profile) if p['id'] == identity else p for p in candidate['formats'] if op != 'profile_remove' or p['id'] != identity]
        if op == 'profile_put' and old is None: candidate['formats'].append(copy.deepcopy(profile))
    elif op == 'metadata_set':
        fields({'patch'})
        patch = payload['patch']
        if not isinstance(patch, dict) or not patch or set(patch) - METADATA_FIELDS: fail('Unknown metadata patch field', 'PROJECT_METADATA')
        candidate.update(copy.deepcopy(patch))
    else:
        fail('Unknown Acquisition ProjectFiles operation', 'PROJECT_REQUEST')
    validate(candidate)
    if candidate.get('provenance', {}).get('source_authoring_v1') != meta.get('provenance', {}).get('source_authoring_v1'):
        fail('Source Note owner pointers cannot be authored as project metadata', 'SOURCE_NOTES')
    if sum(map(len, updated.values())) > MAX_TEXT_BYTES: fail('Project text closure exceeds 1 MiB', 'PROJECT_BOUND')
    if 'project.json' not in encoded or op != 'save_all': encoded['project.json'] = raw if candidate == meta else encode(candidate)
    expected = dict(files, **{'project.json': raw})
    expected.update({name: None for name in encoded if name not in expected})
    return None, {'operation': op, 'encoded': encoded, 'removed': removed, 'files': updated,
                  'metadata_raw': encoded['project.json'], 'expected_prestate': expected}
