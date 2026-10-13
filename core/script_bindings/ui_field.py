"""Headless declarative UI value validation and canonical color accessors."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
    'api_id': 'UI_FIELD_API_v1', 'api_version': 1,
    'provider_kind': 'core', 'provider_id': 'ui_field',
    'documentation_ref': 'docs/api/UI_FIELD_API_v1.md',
    'operations': {
        name: {'name': name, 'summary': summary,
               'arguments': [{'name': arg, 'kind': kind, 'required': True} for arg,kind in arguments],
               'argument_convention': ', '.join(arg for arg,kind in arguments),
               'result_convention': result, 'result_contract': result}
        for name,summary,arguments,result in (
            ('api_info','Read supported declarative field types',[], 'field API descriptor'),
            ('normalize','Validate one declarative value',[('descriptor','struct'),('value','public value')], 'canonical value'),
            ('color_components','Read canonical RGB and presentation opacity',[('color','canonical color')], 'rgb/alpha struct'))
    }
}
def invoke(host, operation, args):
    if operation == 'api_info' and not args:
        info=host.as_dict(host.call('::GX::uiFieldApiInfo'))
        info['types']=host.as_list(info['types']);info['api_version']=int(info['api_version'])
        return info
    if operation == 'normalize' and len(args)==2 and isinstance(args[0],dict):
        result=host.call('::GX::uiFieldNormalize',*args)
        kind=args[0].get('type','string')
        if str(result)=='': return ''
        if kind=='integer': return int(result)
        if kind in ('double','number'): return float(result)
        if kind=='boolean': return bool(int(result))
        if kind=='color' and args[0].get('alpha'):
            color=host.as_dict(result);color['alpha']=float(color['alpha']);return color
        return str(result)
    if operation == 'color_components' and len(args)==1:
        color=host.as_dict(host.call('::GX::uiFieldColorComponents',args[0]))
        color['alpha']=float(color['alpha']);return color
    raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid UI_FIELD_API_v1 arguments')
