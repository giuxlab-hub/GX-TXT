"""Read-only queries of the existing CORE Scientific Profile authority."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
    'api_id': 'DATASET_SCIENTIFIC_PROFILE_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'dataset_scientific_profile',
    'documentation_ref': 'docs/api/DATASET_SCIENTIFIC_PROFILE_API_v1.md',
    'operations': {name: {'name': name, 'summary': 'Nonmutating profile '+name,
        'arguments': [{'name': 'request', 'kind': 'struct', 'required': True}],
        'argument_convention': 'request struct', 'result_contract': 'honest available profile; no source scan',
        'result_convention': 'struct'} for name in ('describe', 'variable', 'distinct')}}

def summary(host, raw):
    s = host.as_dict(raw)
    if 'values' in s:
        # Lexical values preserve the exact filter transport. Dtype remains
        # explicit; never round int64/float values through JSON double here.
        s['values'] = host.as_list(s['values'])
    for key in ('observed', 'finite', 'missing', 'nan', 'positive_infinity',
                'negative_infinity', 'invalid', 'total', 'retained_bytes'):
        if key in s: s[key] = int(s[key])
    for key in ('complete', 'distinct_complete', 'strict', 'moments_available', 'moments_exact'):
        if key in s: s[key] = bool(int(s[key]))
    return s

def invoke(host, operation, args):
    if len(args) != 1 or not isinstance(args[0], dict):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Profile requires a request struct')
    r = args[0]
    if operation == 'describe':
        p = host.as_dict(host.call('::GX::datasetProfileDescribe', host.session, r['dataset_id']))
        p['content_identity'] = host.as_dict(p['content_identity'])
        # Scientific schema identity is the established opaque CORE stamp.
        p['scientific_schema_identity'] = str(p['scientific_schema_identity'])
        p['structure'] = [host.as_dict(v) for v in host.as_list(p['structure'])]
        p['variables'] = [summary(host, v) for v in host.as_list(p['variables'])]
        if 'summaries' in p: p['summaries'] = {k:summary(host,v) for k,v in host.as_dict(p['summaries']).items()}
        return p
    if operation == 'variable':
        s = summary(host, host.call('::GX::datasetProfileVariable', host.session, r['dataset_id'], r['variable_id']))
        s['structure'] = host.as_dict(s['structure'])
        return s
    if operation == 'distinct':
        p = host.as_dict(host.call('::GX::datasetProfileDistinct', host.session, r['dataset_id'], r['variable_id'], r.get('options', {})))
        p['values'] = host.as_list(p['values'])
        for key in ('returned','next','retained_count','observed'): p[key] = int(p[key])
        p['complete'] = bool(int(p['complete']))
        if p['cardinality'] != 'unknown': p['cardinality'] = int(p['cardinality'])
        return p
    raise BridgeError('GXTXT:ScriptBridge:UnknownOperation', 'Unknown profile operation')
