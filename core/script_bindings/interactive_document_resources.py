"""CORE Resource dependency discovery/remapping using its existing owners."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
 'api_id':'INTERACTIVE_DOCUMENT_RESOURCE_API_v1','api_version':1,
 'provider_kind':'core','provider_id':'interactive_document_resources',
 'documentation_ref':'docs/api/INTERACTIVE_DOCUMENT_RESOURCE_API_v1.md',
 'operations':{name:{'name':name,'summary':'Existing CORE Resource/Workspace dependency '+name,
  'arguments':[{'name':'payload_utf8','kind':'inert UTF-8 value','required':True},{'name':arg,'kind':kind,'required':True}],
  'argument_convention':'payload_utf8, '+arg,'result_contract':result,'unit_behavior':'No numerical value or unit changes'}
  for name,arg,kind,result in [('references','document_id','optional owner string','serialized verified complete resource receipt list'),
                             ('remap_references','references_utf8','serialized current receipt list','serialized remapped inert UTF-8 value')]}}
def invoke(host,operation,args):
 if operation not in ('references','remap_references') or len(args)!=2 or not all(isinstance(v,str) for v in args):
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Resource dependencies require two inert UTF-8 strings')
 command='::GX::interactiveDocumentResourceReferences' if operation=='references' else '::GX::interactiveDocumentResourceRemapReferences'
 value=host.call(command,*args)
 return value.decode('utf-8') if isinstance(value,bytes) else str(host.tcl.call('format','%s%s',value,''))
