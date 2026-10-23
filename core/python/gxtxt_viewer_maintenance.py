# SPDX-License-Identifier: GPL-3.0-or-later
"""Inert, finite existing-Viewer maintenance under the Development owner.

This is a trusted maintainer workflow, never a restricted C++ runtime capability.
No edited Tcl is sourced or evaluated. Promotion and real GUI/science acceptance
remain separate from lexical validation and candidate export.
"""
from __future__ import annotations
import configparser
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import tkinter
from zipfile import ZipFile

from gxtxt_project_grant import check_project_root, enforce_project_write
from gxtxt_job_supervisor import tcl_result

FRAMEWORK = Path(__file__).resolve().parents[2]
SCHEMA = 'gxtxt.viewer_maintenance_project.v2'
POLICY_REVISION = 'task210.trusted_existing_viewer.v2'
LIMIT = 65536
# MAIN-approved TASK210 source ownership; IDs are opaque transfer targets.
# This policy is not read from author-editable project metadata.
POLICY = {
    'viewer.interface_builder': ('interface_builder', 'viewer_interface_builder_tk', {
        'source_icons': ('api/icons.tcl', LIMIT, 'tcl', False),
        'doc_manual': ('MANUAL.md', LIMIT, 'markdown', False),
        'doc_changelog': ('CHANGELOG.md', LIMIT, 'markdown', False),
    }),
    'viewer.curve_workbench': ('curve_workbench', 'curve_workbench_tk', {
        'source_0': ('api/curve_workbench_coordinate_frames_v1.tcl', LIMIT, 'tcl', False),
        'source_1': ('api/curve_workbench_comparison_v4.tcl', LIMIT, 'tcl', False),
        'source_2': ('api/curve_workbench_interaction_v2.tcl', LIMIT, 'tcl', False),
        'source_3': ('api/curve_workbench_pointer.tcl', LIMIT, 'tcl', False),
        'source_4': ('api/curve_workbench_history.tcl', LIMIT, 'tcl', False),
        'source_5': ('api/curve_workbench_ui.tcl', LIMIT, 'tcl', False),
        'source_6': ('api/curve_workbench_viewport_v3.tcl', LIMIT, 'tcl', False),
        'source_7': ('api/curve_workbench_selection.tcl', LIMIT, 'tcl', False),
    }),
    'viewer.replicate_curve_analysis': ('replicate_consensus', 'replicate_consensus_tk', {
        'source_0': ('api/replicate_viewer.tcl', 131072, 'tcl', False),
        'doc_manual': ('MANUAL.md', LIMIT, 'markdown', False),
        'doc_interoperability': ('DIGITIZER_INTEROPERABILITY_API_v1.md', LIMIT, 'markdown', True),
    }),
}

# MAIN independently approved exact R1 source tuple; never project input.
# Outside source review06d38a37 and preserved candidate57d bind all three units.
REPLICATE_DIGITIZER_APPROVED_UNITS = {
    'api/replicate_viewer.tcl': 'b67da25f5fc98bbbb775c9aba127fcca7f33db8416f0663b94ed8bbf2c4e70f2',
    'MANUAL.md': '185bc2c12998aedf04effc2140a85f9142d43b2d0873763aac9a594e879cb2fe',
    'DIGITIZER_INTEROPERABILITY_API_v1.md': '0e78edc6d95705c28af4f3e7b569cf747d5c3478b3d0890fce445b737245da05',
}
REPLICATE_DIGITIZER_CONTEXT = ('Trusted provider-owned host API/current Session only; no generic Script/SDK/C++ grant, analysis, publication or private paths. Existing scientific service remains authoritative.')
REPLICATE_DIGITIZER_OPERATIONS = {
    'sourceCapabilities': {
        'command': '::GX::ReplicateViewer::sourceCapabilities', 'arguments': [], 'parameters': {},
        'result': {'type': 'capability declaration dictionary', 'description': 'Inert declared/enabled producer/API discovery; schemas/operations/page bound4096; activation not_requested, implicit_analysis0; no runtime acceptance.'},
        'context': REPLICATE_DIGITIZER_CONTEXT,
    },
    'describeDigitizerSource': {
        'command': '::GX::ReplicateViewer::describeDigitizerSource',
        'arguments': ['datasetId', ['options', {}]],
        'parameters': {
            'datasetId': {'type': 'current Session canonical Dataset ID', 'description': 'Actual unchanged Digitizer publication; public owner validation only.'},
            'options': {'type': 'bounded dictionary', 'description': 'Only start>=0(default0), count1..4096(default4096), expected_revision, expected_session_token. Later pages require first revision/token; caller compares every page source_identity as well.'},
        },
        'result': {'type': 'gxtxt.replicate.source_description.v1 dictionary', 'description': 'Public identity/revision/token, roles/publication/qualified provenance, finite actual joint groups, page counters and2MiB response bound. No fullscan; page counts and labels qualified.'},
        'context': REPLICATE_DIGITIZER_CONTEXT,
    },
    'prepareDigitizerTrace': {
        'command': '::GX::ReplicateViewer::prepareDigitizerTrace',
        'arguments': ['datasetId', 'selection', 'identities', 'expectation'],
        'parameters': {
            'datasetId': {'type': 'current Session canonical Dataset ID', 'description': 'Same public Dataset identity as discovery.'},
            'selection': {'type': 'dictionary', 'description': 'Required actual curve_key; combined calibration_key is actual published MID, separate accepts only primary MID. No label crossproduct.'},
            'identities': {'type': 'explicit scientific declarations dictionary', 'description': 'Required physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id; optional topology landmark_id direction phase_index additional_filters. Additional Graph predicates<=64/16KiB separately reviewed; no automatic independence.'},
            'expectation': {'type': 'exact current public expectation dictionary', 'description': 'Exactly source_revision source_identity session_token from discovery; stale expectation refuses, no silent refresh.'},
        },
        'result': {'type': 'gxtxt.replicate.prepared_trace.v1 dictionary', 'description': 'Complete trace with durable gxtxt.replicate.source_binding.v1 plus canonical full source_descriptor, qualifications, scientific_preflight=required.1..65536 original Dataset rows; no Job/publication/uncertainty weights.'},
        'context': REPLICATE_DIGITIZER_CONTEXT,
    },
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def regular(path, limit=67108864):
    if path.absolute() != path.resolve() or path.is_symlink():
        raise ValueError('Maintenance paths must not contain links')
    info = path.lstat()
    fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns', 'st_nlink', 'st_mode', 'st_uid')
    def valid(value):
        return stat.S_ISREG(value.st_mode) and value.st_nlink == 1 and 0 <= value.st_size <= limit
    if not valid(info):
        raise ValueError('Maintenance input must be a bounded singly linked regular file')
    # NONBLOCK also prevents a replaced FIFO from blocking before fstat can
    # reject it. The actual opened FD, not the pathname alone, owns this read.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not valid(before) or any(getattr(info, f) != getattr(before, f) for f in fields):
            raise ValueError('Maintenance input identity/mode changed before reading')
        raw = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    named = path.lstat()
    if (len(raw) > limit or not valid(after) or not valid(named)
            or path.absolute() != path.resolve()
            or any(getattr(before, f) != getattr(after, f) or getattr(after, f) != getattr(named, f)
                   for f in fields)):
        raise ValueError('Maintenance input identity/link/mode changed while reading')
    return raw, stat.S_IMODE(after.st_mode)


@contextmanager
def project_lock(project, *, create=False):
    """Serialize cooperative maintenance owners; never an external-process CAS.

    Fresh initialization alone creates the persistent lock. Other requests never
    create/replace/unlink one, including a rejected old prototype project.
    """
    lock = project / 'derived/maintenance.lock'
    if lock.parent.absolute() != lock.parent.resolve() or not lock.parent.is_dir():
        raise ValueError('Maintenance requires its real reserved derived directory')
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK
    if create:
        flags |= os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(lock, flags, 0o600)
    except FileNotFoundError as error:
        raise ValueError('Expected current reserved maintenance lock; preserve old project and stage a fresh path') from error
    acquired = False
    def verify():
        opened, named = os.fstat(fd), lock.lstat()
        for info in (opened, named):
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                    or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600):
                raise ValueError('Maintenance lock must be an owned singly linked mode0600 regular file')
        if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
            raise ValueError('Maintenance lock pathname no longer names its opened inode')
    try:
        verify()
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Maintenance project is busy in another cooperative request; no mutation was attempted') from error
        acquired = True
        verify()
        try:
            yield
        finally:
            verify()
    finally:
        try:
            if acquired:
                fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def require_absent(path):
    try:
        path.lstat()
    except FileNotFoundError:
        return
    raise ValueError('Approved document path already has an entry, including a dangling link; inspect before Save')


def inventory(root):
    if root.absolute() != root.resolve() or root.is_symlink() or not root.is_dir():
        raise ValueError('Maintenance source root must be a real directory')
    result = {}; total = 0
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
            raise ValueError('Maintenance refuses linked/special members')
        if path.is_dir():
            continue
        raw, mode = regular(path)
        total += len(raw)
        if len(result) >= 512 or total > 67108864:
            raise ValueError('Maintenance module exceeds 512 files / 64 MiB')
        result[path.relative_to(root).as_posix()] = {'sha256': sha(raw), 'bytes': len(raw), 'mode': mode}
    return result


def descriptor(raw):
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.read_string(raw.decode('utf-8'))
    return parser


def origin(module, provider):
    if module not in POLICY or POLICY[module][0] != provider:
        raise ValueError('Module/provider is outside the CORE maintenance policy')
    _, backend, files = POLICY[module]
    root = FRAMEWORK / 'plugins/modules' / module
    contents = inventory(root)
    meta = descriptor(regular(root / 'module.ini')[0])
    package = descriptor(regular(root / 'plugin-package.ini')[0])
    if (meta.get('meta', 'id') != module or meta.get('meta', 'kind') != 'viewer'
            or provider not in meta.get('viewers', 'ids').split(';')
            or meta.get('viewer.' + provider, 'backend') != backend
            or package.get('package', 'id') != module
            or package.get('package', 'version') != meta.get('meta', 'version')):
        raise ValueError('Installed original module/provider/package identity differs')
    version = meta.get('meta', 'version')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Maintenance requires a normal three-part original version')
    candidate = version.rsplit('.', 1)[0] + '.' + str(int(version.rsplit('.', 1)[1]) + 1)
    for name, bound, language, optional in files.values():
        if name not in contents and optional:
            continue
        raw, _ = regular(root / name, bound)
        text(raw, bound)
    return root, contents, candidate


def text(raw, limit):
    if len(raw) > limit or b'\0' in raw:
        raise ValueError('Maintenance source exceeds its finite UTF-8 bound or contains NUL')
    return raw.decode('utf-8', errors='strict')


def atomic_json(path, value):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.maintenance-', delete=False) as stream:
        stream.write((json.dumps(value, indent=2) + '\n').encode()); stream.flush(); os.fsync(stream.fileno())
        temporary = Path(stream.name)
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def initialize(project, request):
    if set(request) != {'module', 'provider'}:
        raise ValueError('Maintenance init requires the selected registered module/provider only')
    module, provider = request['module'], request['provider']
    if not isinstance(module, str) or module not in POLICY or POLICY[module][0] != provider:
        raise ValueError('Module/provider is outside the CORE maintenance policy')
    check_project_root(project, allow_missing=True)
    if project.exists():
        raise ValueError('Maintenance staging requires an absent fresh path; existing directories are preserved')
    # Exclusive mkdir reserves only this new project. Existing empty folders
    # are deliberately unsupported, never adopted or deleted by initialization.
    project.mkdir(mode=0o700)
    enforce_project_write(project)
    (project / 'derived').mkdir(mode=0o700)
    with project_lock(project, create=True):
        return stage_reserved(project, module, provider)


def stage_reserved(project, module, provider):
    record = None
    journal = project / 'maintenance-staging.json'
    atomic_json(journal, {'status': 'FRESH_PROJECT_RESERVED', 'module': module,
                         'provider': provider, 'original_modified': False})
    try:
        root, before, candidate = origin(module, provider)
        absent = sorted(name for name, _, _, optional in POLICY[module][2].values()
                        if optional and name not in before)
        record = {'schema': SCHEMA, 'policy_revision': POLICY_REVISION,
                  'module': module, 'provider': provider,
                  'origin': str(root), 'origin_inventory': before,
                  'origin_absent_files': absent, 'candidate_version': candidate}
        atomic_json(journal, {'status': 'STAGING_STARTED', 'origin': record, 'original_modified': False})
        shutil.copytree(root, project / 'module', copy_function=shutil.copy2)
        if inventory(project / 'module') != before or inventory(root) != before:
            raise ValueError('Original module changed while staging; partial project preserved')
        atomic_json(project / 'maintenance.json', record)
        atomic_json(journal, {'status': 'STAGED_AND_VERIFIED', 'origin': record, 'original_modified': False})
    except Exception as error:
        atomic_json(journal, {'status': 'FAILED_PARTIAL_PROJECT_PRESERVED', 'origin': record,
                             'module': module, 'provider': provider, 'error': str(error),
                             'original_modified': False})
        raise
    return {'status': 'MAINTENANCE_READY', 'project': str(project), **summary(record)}


def load(project):
    check_project_root(project)
    record = json.loads(regular(project / 'maintenance.json', 262144)[0])
    if (set(record) != {'schema', 'policy_revision', 'module', 'provider', 'origin',
                       'origin_inventory', 'origin_absent_files', 'candidate_version'}
            or record['schema'] != SCHEMA or record['policy_revision'] != POLICY_REVISION):
        raise ValueError('Expected current finite maintenance project; preserve old prototype and stage a fresh project')
    root, actual, candidate = origin(record['module'], record['provider'])
    definitions = POLICY[record['module']][2]
    absent = sorted(name for name, _, _, optional in definitions.values()
                    if optional and name not in actual)
    if (record['origin'] != str(root) or record['origin_inventory'] != actual
            or record['origin_absent_files'] != absent or record['candidate_version'] != candidate):
        raise ValueError('Original module changed or maintenance provenance was forged; restage explicitly')
    current = inventory(project / 'module')
    if set(actual) - set(current) or not (set(current) - set(actual)) <= set(absent):
        raise ValueError('Staged module member inventory changed')
    editable = {name for name, _, _, _ in definitions.values()}
    for name, info in current.items():
        if name not in actual:
            if info['mode'] != 0o644:
                raise ValueError('New approved document must retain CORE-fixed mode0644')
        elif info['mode'] != actual[name]['mode'] or (name not in editable and info != actual[name]):
            raise ValueError('Unapproved source/resource/native/metadata change: ' + name)
    return record, current


def summary(record, current=None):
    present = record['origin_inventory'] if current is None else current
    return {'module': record['module'], 'provider': record['provider'],
            'candidate_version': record['candidate_version'],
            'policy_revision': POLICY_REVISION,
            'files': {key: {'path': name, 'limit': bound, 'language': language,
                            'optional': optional, 'exists': name in present}
                      for key, (name, bound, language, optional) in POLICY[record['module']][2].items()},
            'original_preserved': True, 'source_execution': False, 'installed': False,
            'coverage': 'Trusted source maintenance only; Builder layout adoption and real GUI/scientific checks remain explicit owner obligations.'}


def validate(project, record, current):
    diagnostics = []; checks = []; interp = tkinter.Tcl()
    for identity, (name, bound, language, optional) in POLICY[record['module']][2].items():
        if name not in current:
            checks.append({'identity': identity, 'file': name, 'language': language,
                           'exists': False, 'check': 'Optional document not authored'})
            continue
        source = text(regular(project / 'module' / name, bound)[0], bound)
        checks.append({'identity': identity, 'file': name, 'language': language,
                       'exists': True, 'check': 'Tcl lexical completeness only' if language == 'tcl' else 'Inert bounded UTF-8 Markdown only'})
        if language == 'tcl' and not int(interp.call('info', 'complete', source)):
            diagnostics.append({'file': name, 'line': 1, 'column': 1, 'message': 'Tcl lexical structure is incomplete; no source was evaluated'})
    changed = [name for name in current if current[name] != record['origin_inventory'].get(name)]
    result = {'status': 'LEXICALLY_COMPLETE' if not diagnostics else 'INCOMPLETE',
              **summary(record, current), 'changed_files': changed, 'diagnostics': diagnostics,
              'file_checks': checks,
              'checks': ['registered bundled identity/provider/backend', 'unchanged original inventory',
                         'exact preserved member bytes/modes and optional-document absence provenance',
                         'finite UTF-8 source/document bounds', 'Tcl info complete only; Markdown inert data'],
              'not_checked': ['Tcl security/runtime behavior', 'Markdown semantics', 'dependencies', 'Builder layout adoption', 'GUI responsiveness', 'scientific correctness'],
              'inventory': current}
    atomic_json(project / 'derived/maintenance-validation.json', result)
    return result


def version_bytes(raw, section, version):
    source = raw.decode('utf-8')
    pattern = r'(?m)(^\[' + re.escape(section) + r'\][^\n]*\n)(.*?)(?=^\[|\Z)'
    matches = list(re.finditer(pattern, source, re.S))
    if len(matches) != 1:
        raise ValueError('Expected one packaging metadata section')
    match = matches[0]
    body, count = re.subn(r'(?m)^(version\s*=)[^\r\n]*', lambda m: m[1] + version, match[2])
    if count != 1:
        raise ValueError('Expected one packaging version field')
    return (source[:match.start()] + match[1] + body + source[match.end():]).encode('utf-8')


def replicate_contract_amendment(record, payload):
    """Finite CORE-owned inert metadata; no candidate Tcl evaluation or grant."""
    if (record['module'], record['provider']) != ('viewer.replicate_curve_analysis', 'replicate_consensus'):
        return None
    actual = {name: sha(payload[name]) if name in payload else None
              for name in REPLICATE_DIGITIZER_APPROVED_UNITS}
    approved = REPLICATE_DIGITIZER_APPROVED_UNITS
    admitted = (all(re.fullmatch(r'[0-9a-f]{64}', pin) for pin in approved.values())
                and actual == approved)
    if not admitted:
        # Conservative diagnostic trigger only, NOT parsing or authorization.
        # Unrecognized source still receives no additional advertised operation.
        source = payload['api/replicate_viewer.tcl']
        if any(name.encode('ascii') in source for name in REPLICATE_DIGITIZER_OPERATIONS):
            raise ValueError('Replicate three-operation metadata approval PENDING or source tuple mismatch; preserve source and request MAIN review before export')
        return None
    section = 'public_api.REPLICATE_VIEWER_API_v1'
    meta = descriptor(payload['module.ini'])
    if (meta.get(section, 'namespace') != '::GX::ReplicateViewer'
            or meta.get(section, 'entrypoint') != 'api/replicate_viewer.tcl'
            or meta.get(section, 'api_version') != '1'
            or meta.get('viewer.replicate_consensus', 'activation_api') != 'REPLICATE_VIEWER_API_v1'):
        raise ValueError('Replicate amendment requires its exact existing API namespace and provider')
    interp = tkinter.Tcl()
    def inert_dictionary(value):
        words = interp.splitlist(value)
        if len(words) % 2 or len(set(words[::2])) != len(words) // 2:
            raise ValueError('Expected an unambiguous inert public contract dictionary')
        return dict(zip(words[::2], words[1::2]))
    contract = inert_dictionary(meta.get(section, 'public_contract'))
    if contract.get('schema') != 'gxtxt.public_api_documentation.v1':
        raise ValueError('Expected existing Replicate documentation schema')
    operations = inert_dictionary(contract['operations'])
    if set(operations) != {'open', 'publish', 'dispatch', 'describeGui'}:
        raise ValueError('Expected exactly the four preserved Replicate operations')
    # Retain every original value as an opaque Tcl word. Only the operation
    # dictionary gains three static entries; no descriptor/grant field changes.
    operations.update(REPLICATE_DIGITIZER_OPERATIONS)
    contract['operations'] = operations
    # The existing Tcl list serializer necessarily escapes nested old operation
    # words containing braces. Use the Development owner's established manifest
    # encoding; parseIni/iniUnescape restores the exact inert Tcl list later.
    # Local import keeps unchanged legacy exports on their original path.
    from gxtxt_viewer_development import _manifest_value
    value = _manifest_value(tcl_result(contract))
    source = payload['module.ini'].decode('utf-8')
    pattern = r'(?m)(^\[' + re.escape(section) + r'\][^\n]*\n)(.*?)(?=^\[|\Z)'
    matches = list(re.finditer(pattern, source, re.S))
    if len(matches) != 1:
        raise ValueError('Expected one existing Replicate public API section')
    match = matches[0]
    body, count = re.subn(r'(?m)^(public_contract\s*=)[^\r\n]*', lambda m: m[1] + value, match[2])
    if count != 1:
        raise ValueError('Expected one existing Replicate public contract field')
    payload['module.ini'] = (source[:match.start()] + match[1] + body + source[match.end():]).encode('utf-8')
    return {'api': 'REPLICATE_VIEWER_API_v1', 'approved_units': dict(actual),
            'added_operations': list(REPLICATE_DIGITIZER_OPERATIONS),
            'changed_field': 'module.ini/' + section + '.public_contract'}


def export(project, record, current):
    result = validate(project, record, current)
    if result['status'] != 'LEXICALLY_COMPLETE':
        raise ValueError('Incomplete source blocks candidate export')
    payload = {name: regular(project / 'module' / name)[0] for name in current}
    version = record['candidate_version']
    payload['module.ini'] = version_bytes(payload['module.ini'], 'meta', version)
    payload['plugin-package.ini'] = version_bytes(payload['plugin-package.ini'], 'package', version)
    amendment = replicate_contract_amendment(record, payload)
    owner = FRAMEWORK / 'plugins/modules/tool.script_module_builder/runtime/builder.py'
    spec = importlib.util.spec_from_file_location('gxtxt_maintenance_package_owner', owner)
    builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)
    output = project / 'derived/candidates'
    identity = None
    if amendment is not None:
        normalized = builder.module_package_payload(payload)
        identity = sha(json.dumps({name: {'sha256': sha(raw), 'bytes': len(raw),
                                         'mode': current[name]['mode'] if name in current else 0o644}
                                   for name, raw in sorted(normalized.items())},
                                  sort_keys=True, separators=(',', ':')).encode('utf-8'))
        if output.absolute() != output.resolve() or output.is_symlink():
            raise ValueError('Source-bound candidate parent must not contain links')
        output.mkdir(mode=0o700, exist_ok=True)
        output = output / identity
        # No overwrite/adoption/retry, even for an earlier identical or partial
        # candidate. The unchanged standard writer owns ZIP/sidecar publication.
        output.mkdir(mode=0o700)
    package, digest = builder.write_module_zip(payload, record['module'], version,
                                             output, file_modes={name: info['mode'] for name, info in current.items()})
    with ZipFile(package) as archive:
        expected = builder.module_package_payload(payload)
        if set(archive.namelist()) != set(expected) or any(archive.read(name) != raw for name, raw in expected.items()):
            raise ValueError('Candidate package byte readback failed')
        if any(stat.S_IMODE(archive.getinfo(name).external_attr >> 16) != info['mode'] for name, info in current.items()):
            raise ValueError('Candidate preserved member mode readback failed')
    # Detect concurrent original or staged changes before returning success.
    _, after = load(project)
    if after != current:
        raise ValueError('Staged source changed during export; candidate remains unaccepted')
    result = {**result, 'status': 'MAINTENANCE_CANDIDATE_EXPORTED', 'package': str(package),
              'sha256': digest, 'packaging_changes': ['module.ini/meta.version', 'plugin-package.ini/package.version'] + sorted(set(current) & {'SHA256SUMS', 'SHA256SUMS.txt'}),
              'review_required': True, 'functional_validation': 'NOT_TESTED', 'package_readback': True}
    if amendment is not None:
        result['packaging_changes'].append(amendment['changed_field'])
        result['contract_amendment'] = amendment
        result['source_bound_export_identity'] = identity
    atomic_json(project / 'derived/maintenance-candidate.json', result)
    return result


def dispatch(operation, project, request):
    if not isinstance(request, dict):
        raise ValueError('Maintenance requires a typed request object')
    if operation == 'maintenance_init':
        return initialize(project, request)
    enforce_project_write(project)
    with project_lock(project):
        return dispatch_locked(operation, project, request)


def dispatch_locked(operation, project, request):
    record, current = load(project)
    if operation == 'maintenance_inspect':
        if set(request) - {'file_id'}:
            raise ValueError('Inspect accepts an opaque file ID only')
        if not request:
            return {'status': 'MAINTENANCE_READY', **summary(record, current)}
        filename, bound, language, optional = POLICY[record['module']][2][request['file_id']]
        if filename not in current:
            return {'status': 'SAVED', 'identity': request['file_id'], 'content': '',
                    'sha256': None, 'bytes': 0, 'read_only': False, 'exists': False,
                    'language': language}
        raw, _ = regular(project / 'module' / filename, bound)
        return {'status': 'SAVED', 'identity': request['file_id'], 'content': text(raw, bound),
                'sha256': sha(raw), 'bytes': len(raw), 'read_only': False, 'exists': True,
                'language': language}
    if operation == 'maintenance_save':
        if set(request) != {'file_id', 'expected_sha256', 'content'} or not isinstance(request['content'], str):
            raise ValueError('Save requires opaque file ID, expected SHA256 and UTF-8 text')
        filename, bound, language, optional = POLICY[record['module']][2][request['file_id']]
        target = project / 'module' / filename
        creating = filename not in current
        if creating:
            if not optional or filename not in record['origin_absent_files'] or request['expected_sha256'] is not None:
                raise ValueError('Only the exact absent approved document accepts expected_sha256 null')
            before, mode = None, 0o644
            require_absent(target)
        else:
            before, mode = regular(target, bound)
            if request['expected_sha256'] != sha(before):
                raise ValueError('Source changed after inspection; unsaved editor text must be preserved')
        raw = request['content'].encode('utf-8'); text(raw, bound)
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.maintenance-source-', delete=False) as stream:
            stream.write(raw); os.fchmod(stream.fileno(), mode)
            stream.flush(); os.fsync(stream.fileno()); temporary = Path(stream.name)
        try:
            if regular(temporary, bound) != (raw, mode):
                raise ValueError('Staged source byte/mode readback failed; original target was not replaced')
            if creating:
                # Same-filesystem publication refuses an intervening creation;
                # no replace, guessed empty-file hash, or overwrite fallback.
                require_absent(target)
                os.link(temporary, target)
            else:
                if regular(target, bound) != (before, mode):
                    raise ValueError('Source changed before atomic replacement')
                os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
        try:
            committed = regular(target, bound)
        except Exception as error:
            raise ValueError('Save may have committed but final readback failed; inspect before any retry') from error
        if committed != (raw, mode):
            raise ValueError('Save may have committed but final byte/mode readback failed; inspect before any retry')
        return {'status': 'SAVED', 'identity': request['file_id'], 'sha256': sha(raw),
                'bytes': len(raw), 'exists': True, 'created': creating,
                'language': language, 'source_execution': False}
    if request:
        raise ValueError('Validate/export take no author-controlled options')
    if operation == 'maintenance_validate':
        return validate(project, record, current)
    if operation == 'maintenance_export':
        return export(project, record, current)
    raise ValueError('Unknown finite maintenance operation')
