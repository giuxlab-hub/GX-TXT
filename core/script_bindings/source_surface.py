"""Non-executing public source models; editing and widgets remain host-owned."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
FIELDS={'info':[], 'scan':['language','source'], 'palette':['theme']}
REGISTRATION={'api_id':'SOURCE_SURFACE_API_v1','api_version':1,'provider_kind':'core','provider_id':'source_surface','documentation_ref':'docs/api/SOURCE_SURFACE_API_v1.md','operations':{name:{'name':name,'summary':'Shared CORE source '+name,'arguments':[{'name':arg,'kind':'string','required':True} for arg in fields],'result_contract':'Non-executing source capability/token model/palette'} for name,fields in FIELDS.items()}}
def invoke(host,operation,args):
    if operation not in FIELDS or len(args)!=len(FIELDS[operation]):raise BridgeError('GXTXT:Source:Arguments','Invalid Source Surface operation/arguments')
    command={'info':'::GX::sourceSurfaceApiInfo','scan':'::GX::sourceSurfaceScan','palette':'::GX::sourceSurfacePalette'}[operation]
    raw=host.call(command,*args);result=host.as_dict(raw)
    if operation=='scan':
        result['tokens']=[{str(k):(int(v) if k in {'start','end','line','column','end_line','end_column','byte_start','byte_end'} else str(v)) for k,v in host.as_dict(item).items()} for item in host.as_list(result['tokens'])]
        result['folds']=[[int(v) for v in host.as_list(item)] for item in host.as_list(result['folds'])]
        for key in ('line_count','characters','bytes','truncated'):result[key]=int(result[key])
    if operation=='info':
        for key in ('modes','operations','language_families'):result[key]=host.as_list(result[key])
    return result
