"""Explicit native Workspace nodes for both Python and Octave Script Bridge.

Scalar annotations are strings, retaining exact spellings and signed zero.
No serialized Tcl Workspace payload is accepted or produced by this interface.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_ARGS = {
    'query': ['provider', 'owner', 'prefix', 'offset', 'limit'],
    'metadata': ['id'], 'get': ['id'], 'properties': ['id'], 'status': ['id'], 'flush': ['id'],
    'create': ['provider', 'name', 'state', 'properties', 'provenance', 'asynchronous'],
    'save': ['expected', 'state', 'properties', 'asynchronous'],
    'save_as': ['id', 'name'], 'rename': ['expected', 'name'],
    'notes': ['expected', 'text'], 'delete': ['expected', 'confirmed'],
    'history_save': ['expected', 'name', 'record', 'auxiliary', 'context'],
    'history_list': ['id'], 'history_get': ['id', 'archive'],
    'history_rename': ['expected', 'archive', 'name'],
    'history_delete': ['expected', 'archive', 'confirmed'],
}
_COMMANDS = dict(zip(_ARGS, [
    'nativeWorkspaceQuery', 'nativeWorkspaceMetadata', 'nativeWorkspaceGet',
    'nativeWorkspaceProperties', 'nativeWorkspaceStatus', 'nativeWorkspaceFlush',
    'nativeWorkspaceCreate', 'nativeWorkspaceSave', 'nativeWorkspaceSaveAs',
    'nativeWorkspaceRename', 'nativeWorkspaceNotes', 'nativeWorkspaceDelete',
    'nativeWorkspaceHistorySave', 'nativeWorkspaceHistoryList', 'nativeWorkspaceHistoryGet',
    'nativeWorkspaceHistoryRename', 'nativeWorkspaceHistoryDelete',
]))
_ARGS['resource_copy_tree'] = ['id', 'graph']
_COMMANDS['resource_copy_tree'] = 'managedResourceCopyTree'
REGISTRATION = {
    'api_id': 'NATIVE_WORKSPACE_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'native_workspace',
    'documentation_ref': 'docs/api/NATIVE_WORKSPACE_API_v1.md',
    'operations': {name: {'name': name, 'summary': 'Typed native Workspace: ' + name,
        'arguments': [{'name': arg, 'kind': 'explicit public value', 'required': True} for arg in args],
        'argument_convention': ', '.join(args), 'result_contract': 'native receipt or explicit typed graph',
        'result_convention': 'generation/revision receipt; asynchronous acceptance is distinct from durability'}
        for name, args in _ARGS.items()},
}


def _invalid(message):
    raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', message)


def to_tcl(value, depth=0):
    if depth > 64 or not isinstance(value, dict) or set(value) != {'kind', 'value'}:
        _invalid('A native node requires kind/value within depth64')
    kind, data = value['kind'], value['value']
    if kind in {'object', 'resource'}:
        if not isinstance(data, dict):
            _invalid('Native object/resource requires a field map')
        data = {key: to_tcl(item, depth+1) for key, item in data.items()}
    elif kind == 'array':
        if not isinstance(data, (list, tuple)):
            _invalid('Native array requires ordered nodes')
        data = [to_tcl(item, depth+1) for item in data]
    elif kind == 'null':
        if data not in (None, ''):
            _invalid('Native null value must be null or empty')
        data = ''
    elif kind in {'text', 'int', 'real', 'bool'}:
        if not isinstance(data, (str, int, float, bool)):
            _invalid('Native scalar requires its explicit scalar annotation')
    else:
        _invalid('Unsupported native Workspace kind')
    return [kind, data]


def from_tcl(host, raw, depth=0):
    if depth > 64:
        _invalid('Native response exceeds depth64')
    parts = host.as_list(raw)
    if len(parts) != 2:
        _invalid('Malformed native typed response')
    kind, data = str(parts[0]), parts[1]
    if kind in {'object', 'resource'}:
        data = {str(key): from_tcl(host, value, depth+1) for key, value in host.as_dict(data).items()}
    elif kind == 'array':
        data = [from_tcl(host, value, depth+1) for value in host.as_list(data)]
    elif kind == 'null':
        data = None
    else:
        data = str(data)
    return {'kind': kind, 'value': data}


def metadata(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in {'revision', 'durable_revision', 'queued_bytes', 'size_bytes'}:
            result[key] = int(value)
        elif key in {'accepted', 'pending', 'failed', 'has_notes', 'has_preview'}:
            result[key] = bool(int(value))
        elif key in {'state', 'properties', 'provenance'}:
            result[key] = from_tcl(host, value)
    return result


def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        _invalid('Invalid native Workspace operation/arguments')
    values = dict(zip(_ARGS[operation], args))
    if operation in {'create', 'save'}:
        state = to_tcl(values['state'])
        provider = values.get('provider')
        if provider is None:
            expected = values['expected']
            if not isinstance(expected, dict) or not {'id', 'generation', 'revision'} <= set(expected):
                _invalid('Native Save requires held id/generation/revision')
            provider = host.as_dict(host.call('::GX::nativeWorkspaceMetadata', expected['id']))['provider_id']
        host.call('::GX::nativeWorkspaceScriptValidate', provider, state)
    if operation == 'delete':
        expected = values['expected']
        host.call('::GX::sessionWorkspaceDelete', expected['id'], values['confirmed'], expected)
        return metadata(host, host.call('::GX::nativeWorkspaceStatus', expected['id']))
    converted = []
    for key, value in values.items():
        converted.append(to_tcl(value) if key in {'state', 'properties', 'provenance', 'record', 'auxiliary', 'context', 'graph'} else value)
    raw = host.call('::GX::'+_COMMANDS[operation], *converted)
    if operation == 'query':
        return [metadata(host, item) for item in host.as_list(raw)]
    if operation in {'properties', 'history_list', 'history_get', 'resource_copy_tree'}:
        return from_tcl(host, raw)
    return metadata(host, raw)
