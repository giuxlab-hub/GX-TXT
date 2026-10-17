"""Location-opaque registered scientific provider client; no direct solver launch."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
COMMANDS={
 'node_list':('::GX::scientificExecutionNodeList',[]),
 'node_inspect':('::GX::scientificExecutionNodeInspect',['node_id']),
 'destination':('::GX::scientificExecutionDestination',['destination']),
 'discover':('::GX::scientificExecutionDiscover',[]),
 'describe':('::GX::scientificExecutionDescribe',['provider_id']),
 'prepare':('::GX::scientificExecutionPrepare',['provider_id','parameters','resources','options']),
 'discard':('::GX::scientificExecutionDiscard',['prepared_token']),
 'submit':('::GX::scientificExecutionSubmit',['prepared_token']),
 'status':('::GX::scientificExecutionStatus',['job_id']),
 'reconnect':('::GX::scientificExecutionReconnect',['job_id']),
 'cancel':('::GX::scientificExecutionCancel',['job_id']),
 'log':('::GX::scientificExecutionLog',['job_id','offset','count','previous_receipt']),
 'outputs':('::GX::scientificExecutionOutputs',['job_id']),
 'read_output':('::GX::scientificExecutionReadOutput',['job_id','output_token','offset','count','generation']),
 'read_records':('::GX::scientificExecutionReadRecords',['job_id','output_token','offset','count','generation']),
 'freeze_resource':('::GX::scientificExecutionFreezeResource',['job_id','output_token','document_id']),
 'import_results':('::GX::scientificExecutionImportResults',['job_id','output_token','request'])}
REGISTRATION={'api_id':'SCIENTIFIC_EXECUTION_API_v1','api_version':1,'provider_kind':'core',
 'provider_id':'scientific_execution','documentation_ref':'docs/api/SCIENTIFIC_EXECUTION_API_v1.md',
 'operations':{name:{'name':name,'summary':'Registered durable scientific execution '+name,
  'arguments':[{'name':arg,'kind':'public value','required':arg!='previous_receipt'} for arg in args],
  'argument_convention':', '.join(args),'result_contract':'Opaque provider, Job, resource or canonical Dataset receipt'}
  for name,(_,args) in COMMANDS.items()}}

def receipt(host,raw):
 result=host.as_dict(raw)
 for key in ('outputs',):
  if key in result:result[key]=[receipt(host,v) for v in host.as_list(result[key])]
 if 'records' in result:result['records']=[[str(x) for x in host.as_list(row)] for row in host.as_list(result['records'])]
 if 'columns' in result:result['columns']=[host.as_dict(v) for v in host.as_list(result['columns'])]
 if 'tools' in result:result['tools']=[str(v) for v in host.as_list(result['tools'])]
 for key in ('parameters','summary','source_identities','policy','usage','metadata'):
  if key in result:result[key]=host.as_dict(result[key]) if str(result[key]) else {}
 if 'parameters' in result:result['parameters']={str(k):host.as_dict(v) for k,v in result['parameters'].items()}
 for key in ('size_bytes','next_offset','source_generation','pid'):
  if key in result:result[key]=int(result[key])
 return result

def invoke(host,operation,args):
 if operation not in COMMANDS or (len(args)!=len(COMMANDS[operation][1]) and not (operation=='log' and len(args)==3)):
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid scientific execution operation arguments')
 host.call('::GX::scientificExecutionRegisterBuiltins')
 raw=host.call(COMMANDS[operation][0],*args)
 if operation=='node_list':return [host.normalize(host.as_dict(v)) for v in host.as_list(raw)]
 if operation=='node_inspect':
  result=host.as_dict(raw)
  providers=[]
  for value in host.as_list(result.get('providers',())):
   provider=host.as_dict(value);provider['tools']={str(k):bool(int(v)) for k,v in host.as_dict(provider['tools']).items()};provider['available']=bool(int(provider['available']));providers.append(provider)
  result['providers']=providers;result['policy']=host.as_dict(result['policy']);result['cores']=int(result['cores'])
  return host.normalize(result)
 if operation=='destination':return str(raw)
 if operation=='discover':return [str(v) for v in host.as_list(raw)]
 if operation=='prepare':return str(raw)
 return host.normalize(receipt(host,raw))
