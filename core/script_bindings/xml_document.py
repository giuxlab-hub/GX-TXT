"""Native public XML documents within the existing Python/Octave Bridge host."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from gxtxt_script_bridge_server import BridgeError
FIELDS={'create':['root_name'],'parse':['xml_text'],'parse_file':['authorized_path'],'root':['document'],'describe':['document','node'],'append':['document','parent','name','text'],'insert':['document','before','name','text'],'text':['document','node','value'],'add_text':['document','parent','text'],'attribute':['document','node','name','value'],'remove':['document','node'],'move':['document','node','parent'],'query':['document','node','tag'],'serialize':['document','indent'],'write':['document','destination'],'release':['document']}
REGISTRATION={'api_id':'XML_DOCUMENT_API_v1','api_version':1,'provider_kind':'core','provider_id':'xml_document','documentation_ref':'docs/api/XML_DOCUMENT_API_v1.md','operations':{name:{'name':name,'summary':'Native XML document '+name,'arguments':[{'name':k,'kind':'public value','required':False} for k in fields],'result_contract':'Opaque document/node, XML text or atomic file receipt'} for name,fields in FIELDS.items()}}
def invoke(host,operation,args):
    if operation not in FIELDS:raise BridgeError('GXTXT:XML:Operation','Unknown XML operation')
    args=list(args)
    if operation in {'write','parse_file'}:
        pos=1 if operation=='write' else 0
        root=Path(host.config.get('runtime','output_dir')).resolve() if operation=='write' else Path(host.session).resolve()
        path=Path(args[pos]);path=path if path.is_absolute() else root/path
        resolved=path.resolve()
        if not resolved.is_relative_to(root) or any(p.is_symlink() for p in [path,*path.parents] if p!=root.parent):
            raise BridgeError('GXTXT:XML:Authorization','XML file operation escaped the authorized run/Session root')
        args[pos]=str(resolved)
    result=host.call('::GX::xmlDocument',operation,*args)
    if operation=='describe':
        result=host.as_dict(result);result['children']=host.as_list(result['children']);result['attributes']=host.as_dict(result['attributes']);result['node_type']=int(result['node_type']);return result
    if operation=='query':return host.as_list(result)
    if operation=='write':
        receipt=host.as_dict(result);receipt['files']={str(k):host.as_dict(v) for k,v in host.as_dict(receipt['files']).items()};return receipt
    return str(result)
