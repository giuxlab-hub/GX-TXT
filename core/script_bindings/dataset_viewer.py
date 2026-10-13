"""Read-only Dataset viewer dispatch discovery for researcher scripts."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
    'api_id': 'DATASET_VIEWER_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'dataset_viewer',
    'documentation_ref': 'docs/api/DATASET_VIEWER_API_v1.md',
    'operations': {'describe': {'name': 'describe',
        'summary': 'Resolve canonical contract, format and CORE consultation target',
        'arguments': [{'name': 'request', 'kind': 'struct', 'required': True}],
        'argument_convention': 'request struct', 'result_contract': 'read-only dispatch descriptor',
        'result_convention': 'struct'}}}
def invoke(host, operation, args):
    if operation != 'describe' or len(args) != 1 or not isinstance(args[0], dict):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'describe requires {dataset_id: ...}')
    result = host.as_dict(host.call('::GX::datasetViewerDescribe', args[0]['dataset_id']))
    for key in ('read_only', 'implicit_publication'):
        result[key] = bool(int(result[key]))
    return result
