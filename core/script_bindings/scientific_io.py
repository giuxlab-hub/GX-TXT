"""Opaque authorized source tokens; user/admin grants remain host-only."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
COMMANDS={
 'capabilities':('::GX::scientificIoCapabilities',[]),
 'browse':('::GX::scientificIoBrowse',['scope_token','directory_token','offset','count']),
 'import':('::GX::scientificIoImport',['scope_token','entry_token','request']),
 'describe':('::GX::scientificIoDescribeDataset',['dataset_id']),
 'read':('::GX::scientificIoReadDataset',['dataset_id','offset','count']),
 'export':('::GX::scientificIoExportDataset',['scope_token','dataset_id','filename'])}
REGISTRATION={'api_id':'SCIENTIFIC_IO_API_v1','api_version':1,'provider_kind':'core','provider_id':'scientific_io',
 'documentation_ref':'docs/api/SCIENTIFIC_IO_API_v1.md',
 'operations':{name:{'name':name,'summary':'Authorized location-opaque scientific I/O '+name,
 'arguments':[{'name':arg,'kind':'public value','required':True} for arg in args],
 'argument_convention':', '.join(args),'result_contract':'Bounded page, opaque token or canonical Dataset receipt'}
 for name,(_,args) in COMMANDS.items()}}
def invoke(host,operation,args):
 if operation not in COMMANDS or len(args)!=len(COMMANDS[operation][1]):
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid scientific I/O arguments')
 values=list(args)
 if operation in ('browse','import','export'):values.insert(1,host.module_id)
 result=host.as_dict(host.call(COMMANDS[operation][0],*values))
 if 'entries' in result:result['entries']=[host.as_dict(v) for v in host.as_list(result['entries'])]
 for key in ('size_bytes','next_offset','total_entries'):
  if key in result:result[key]=int(result[key])
 return host.normalize(result)
