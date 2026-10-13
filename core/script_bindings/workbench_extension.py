"""Owned research-script context and inert result transport for Workbench actions."""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
from gxtxt_script_bridge_server import BridgeError

REGISTRATION = {
    'api_id': 'WORKBENCH_EXTENSION_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'workbench_extension',
    'documentation_ref': 'docs/api/WORKBENCH_EXTENSION_API_v1.md',
    'operations': {
        'script_context': {'name': 'script_context', 'summary': 'Read the immutable logical extension context', 'arguments': [], 'argument_convention': 'no arguments', 'result_contract': 'logical context; no Native handles or private paths', 'result_convention': 'context struct'},
        'return_result': {'name': 'return_result', 'summary': 'Return a bounded structured mutation proposal to the owning Workbench', 'arguments': [{'name':'result','kind':'struct','required':True}], 'argument_convention':'result struct','result_contract':'owned execution result receipt','result_convention':'receipt struct'},
    },
}

def _context(host):
    encoded = host.config.get('workbench_extension','context',fallback='')
    if not encoded:
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','This execution has no Workbench extension context')
    try:
        raw = base64.b64decode(encoded, validate=True).decode('utf-8')
    except (ValueError, UnicodeError) as exc:
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid extension context transport') from exc
    result = host.as_dict(raw)
    for key in ('parameters','config_snapshot','units','working_plane'):
        if key in result:
            result[key] = host.as_dict(result[key])
    if 'selection' in result:
        result['selection'] = host.as_dict(result['selection'])
        for key in ('ids','point_indices'):
            if key in result['selection']:
                values = host.as_list(result['selection'][key])
                result['selection'][key] = [int(v) for v in values] if key=='point_indices' else values
    for field in ('parameters','config_snapshot'):
        for key,value in list(result.get(field,{}).items()):
            kind = str(host.call('::GX::moduleConfigField',host.module_id,key,'type','string'))
            if kind in ('number','double') and value!='':result[field][key]=float(value)
            elif kind=='integer' and value!='':result[field][key]=int(value)
            elif kind=='boolean':result[field][key]=str(value).lower() in ('1','true','yes','on')
    result['revision'] = int(result['revision'])
    # Restore the declared scalar types after inert Tcl transport; the shared
    # UI Field authority already performed normalization and validation.
    return result

def invoke(host, operation, args):
    if operation == 'script_context' and not args:
        return _context(host)
    if operation == 'return_result' and len(args)==1 and isinstance(args[0],dict):
        result = args[0]
        if result.get('status') != 'ok' or not isinstance(result.get('operations',[]),list):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Return status=ok and a list of structured operations')
        return host.as_dict(host.call('::GX::workbenchExtensionScriptResultWrite',str(host.runtime_path.parent),result))
    raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid extension result arguments')
