"""Public Dataset Selection resources; independent canonical source members."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_ARGS = {'list': [], 'describe': ['selection_id'], 'ids': [], 'get': ['selection_id'], 'members': ['selection_id', 'operation'],
         'create_members': ['members', 'producer']}
REGISTRATION = {
    'api_id': 'DATASET_SELECTION_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'dataset_selection',
    'documentation_ref': 'docs/api/DATASET_SELECTION_API_v1.md',
    'operations': {name: {'name': name, 'summary': 'Canonical Selection resource: ' + name,
                         'arguments': [{'name': arg, 'kind': 'public value', 'required': True} for arg in args],
                         'argument_convention': ', '.join(args), 'result_convention': 'public Selection result',
                         'result_contract': 'Dataset/Variable IDs, source rows and predicates; no payload paths'}
                   for name, args in _ARGS.items()}
}

def _member(host, value):
    member = host.as_dict(value)
    for key in ('rows', 'variable_ids'):
        if key in member: member[key] = host.as_list(member[key])
    for key in ('row_filters', 'selection_filters'):
        if key in member: member[key] = [host.as_dict(v) for v in host.as_list(member[key])]
    return member

def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Invalid Dataset Selection operation/arguments')
    if operation in ('ids', 'list'):
        return host.as_list(host.call('::GX::sessionInspectionSelectionIds', host.session))
    if operation in ('get', 'describe'):
        resource = host.as_dict(host.call('::GX::sessionInspectionSelection', args[0], host.session))
        if resource.get('type') == 'members':
            resource['members'] = [_member(host, value) for value in host.as_list(resource['members'])]
            resource['member_count'] = int(resource['member_count'])
        return resource
    if operation == 'members':
        return [_member(host, value) for value in host.as_list(host.call('::GX::datasetSelectionMembers', host.session, *args))]
    if not isinstance(args[0], list) or not isinstance(args[1], dict):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'create_members needs a member list and producer struct')
    return str(host.call('::GX::datasetSelectionCreateMembers', host.session, *args))
