"""Negotiate public Bridge contracts independently of GX-TXT release labels."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tkinter

from .config import ConfigurationError, framework_info


# These features enrich the generic Bridge; they are not prerequisites for
# unrelated APIs. Original live discovery remains the invocation authority.
FEATURE_CONTRACTS = {
    'document_tex': ('INTERACTIVE_DOCUMENT_API_v1', 1, ('tex_build', 'tex_cancel', 'tex_export')),
    'registered_scripts': ('SCRIPT_EXECUTION_API_v1', 1, ('registry_list', 'registry_read')),
    'script_debugger': ('SCRIPT_JOB_API_v1', 1, ('debug_submit', 'debug_read', 'debug_control')),
}


def declarations(settings):
    """Read inert installed public declarations; no Session or API activation."""
    result = framework_info(settings['framework_root'])
    entrypoint = Path(settings['framework_root']) / 'core/python/gxtxt_script_bridge_server.py'
    try:
        done = subprocess.run(
            [settings['python'], '-B', str(entrypoint), '--metadata-tcl'],
            capture_output=True, timeout=30,
            env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
    except subprocess.TimeoutExpired:
        raise ConfigurationError('SCRIPT_BRIDGE metadata discovery exceeded its 30-second budget') from None
    if len(done.stdout) > 16777216:
        raise ConfigurationError('SCRIPT_BRIDGE metadata discovery exceeded its 16 MiB budget')
    if done.returncode:
        raise ConfigurationError('Missing or incompatible SCRIPT_BRIDGE metadata discovery contract (--metadata-tcl)')
    t = tkinter.Tcl()
    try:
        data = done.stdout.decode('utf-8')
        if not t.getboolean(t.call('dict', 'get', data, 'ok')):
            raise ConfigurationError('SCRIPT_BRIDGE reported unavailable public declarations')
        if t.call('dict', 'get', data, 'execution_context') != 'inactive_metadata_only':
            raise ConfigurationError('SCRIPT_BRIDGE metadata discovery must be inactive_metadata_only')
        registrations = t.call('dict', 'get', data, 'registrations')
        ids = t.splitlist(t.call('dict', 'keys', registrations))
        features = {}
        for feature, (api, version, operations) in FEATURE_CONTRACTS.items():
            missing = []
            actual = None
            if not t.getboolean(t.call('dict', 'exists', registrations, api)):
                missing.append(f'{api} API version {version}')
            else:
                actual = str(t.call('dict', 'get', registrations, api, 'api_version'))
                if actual != str(version):
                    missing.append(f'{api}: expected API version {version}; found {actual}')
                for operation in operations:
                    if not t.getboolean(t.call('dict', 'exists', registrations, api, 'operations', operation)):
                        missing.append(f'{api}/{operation}')
            features[feature] = {'available': not missing, 'api_id': api,
                                 'required_api_version': version, 'actual_api_version': actual,
                                 'required_operations': list(operations), 'missing': missing}
    except (tkinter.TclError, UnicodeError):
        raise ConfigurationError('Invalid SCRIPT_BRIDGE public metadata contract: expected inactive registration dictionary with API versions and operations') from None
    result.update(
        compatibility_basis='public_contracts_not_framework_release',
        declared_api_count=len(ids),
        declaration_sha256=hashlib.sha256(done.stdout).hexdigest(),
        features=features,
        capability_state='installed_declarations_verified_runtime_context_required',
        runtime_contract={'api_id': 'OCTAVE_SCRIPT_BRIDGE_API_v1', 'api_version': 1,
                          'transport_version': 2, 'binary_descriptor_version': 2,
                          'execution_profile': 'authorized_direct'},
        runtime_verified=False)
    return result


def runtime(info):
    """Validate the actual authenticated original host, never infer from a tag."""
    if not isinstance(info, dict):
        raise ConfigurationError('SCRIPT_BRIDGE info must return a public contract dictionary')
    checks = {
        'api_id': 'OCTAVE_SCRIPT_BRIDGE_API_v1',
        'api_version': 1,
        'execution_profile': 'authorized_direct',
        'active': True,
    }
    for key, expected in checks.items():
        if info.get(key) != expected:
            raise ConfigurationError(f'SCRIPT_BRIDGE/{key}: required {expected!r}; found {info.get(key)!r}')
    versions = info.get('supported_transport_versions', [info.get('transport_version')])
    if not isinstance(versions, (list, tuple)) or 2 not in versions:
        raise ConfigurationError(f'SCRIPT_BRIDGE transport version 2 is required; found {versions!r}')
    binary = info.get('binary_descriptor_versions', [])
    if not isinstance(binary, (list, tuple)) or 2 not in binary:
        raise ConfigurationError(f'SCRIPT_BRIDGE binary descriptor version 2 is required; found {binary!r}')
    return {'api_id': info['api_id'], 'api_version': info['api_version'],
            'transport_version': 2, 'binary_descriptor_version': 2,
            'execution_profile': info['execution_profile'], 'runtime_verified': True}
