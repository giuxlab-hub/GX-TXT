"""Registered declarations, supervised identity and owned Job dependencies."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

_ARGS = {'callable_list': [], 'callable_describe': ['reference', 'callable_id'], 'current_callable': [], 'job_wait': ['job_id', 'timeout_seconds'], 'job_submit': ['reference', 'parameters']}
REGISTRATION = {
    'api_id': 'SCRIPT_EXECUTION_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'script_execution',
    'documentation_ref': 'docs/api/SCRIPT_EXECUTION_API_v1.md',
    'capabilities': ['registered_callable_declarations', 'supervised_callable_identity', 'owned_job_dependency_wait', 'supervised_job_submission'],
    'operations': {name: {'name': name, 'summary': 'Registered Script ' + name,
        'arguments': [{'name': arg, 'kind': {'parameters': 'dictionary', 'timeout_seconds': 'integer'}.get(arg, 'string'), 'required': True} for arg in args],
        'argument_convention': ', '.join(args),
        'result_contract': 'Verified declaration/identity or bounded supervised Job receipt; no arbitrary source paths'}
        for name, args in _ARGS.items()},
}


def _descriptor(host, raw):
    result = host.as_dict(raw)
    for key, value in result.items():
        result[key] = value.decode('ascii') if isinstance(value, bytes) else str(value)
    result['revision'] = int(result['revision'])
    return result


def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Invalid Script Execution operation arguments')
    if operation == 'job_submit':
        if not isinstance(args[0], str) or not isinstance(args[1], dict):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Job submission requires a registered reference and parameter dictionary')
        raw = host.as_dict(host.call('::GX::scriptJobSubmit', *args))
        return {'job_id': str(raw['id']), 'state': str(raw['state'])}
    if operation == 'job_wait':
        raw = host.as_dict(host.call('::GX::scriptJobWait', *args))
        return {'job_id': str(raw['id']), 'state': str(raw['state']),
                'wait_cancel_requested': bool(int(raw['wait_cancel_requested']))}
    if operation == 'callable_list':
        return [_descriptor(host, value) for value in host.as_list(host.call('::GX::scriptRegistryCallableList', host.session))]
    if operation == 'callable_describe':
        return _descriptor(host, host.call('::GX::scriptRegistryCallableDescribe', *args, host.session))
    if not host.config.has_section('registered_callable'):
        raise BridgeError('GXTXT:ScriptCallback:NoInvocation', 'This Job has no registered callable invocation')
    invocation = dict(host.config.items('registered_callable'))
    reference = host.config.get('config', 'registered_script')
    if invocation['source_sha256'] != host.config.get('config', 'script_sha256'):
        raise BridgeError('GXTXT:ScriptCallback:IdentityMismatch', 'Callable source differs from its Job snapshot')
    request = {key: invocation[key] for key in ('callable_id','source_sha256','revision','declaration_sha256','consumer_api','consumer_operation','payload_json')}
    host.call('::GX::scriptCallableInvocationValidate', reference, request, host.session)
    result = _descriptor(host, host.call('::GX::scriptRegistryCallableDescribe', reference, invocation['callable_id'], host.session))
    for key in ('source_sha256', 'revision', 'declaration_sha256'):
        if str(result[key]) != invocation[key]:
            raise BridgeError('GXTXT:ScriptCallback:IdentityMismatch', 'Registered callable changed during identity resolution')
    result.update({key: invocation[key] for key in ('consumer_api', 'consumer_operation')})
    result['run_id'] = host.run_id
    return result
