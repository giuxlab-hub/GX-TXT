"""Location-opaque registered scientific provider client; no direct solver launch."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
COMMANDS={
 'core_capabilities':('::GX::scientificExecutionCoreCapabilities',[]),
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
 'import_results':('::GX::scientificExecutionImportResults',['job_id','output_token','request']),
 'circuit_inspect':('::GX::scientificExecutionCircuitInspect',['document_id','parameters']),
 'circuit_prepare':('::GX::scientificExecutionCircuitPrepare',['document_id','parameters','options']),
 'circuit_sweep_prepare':('::GX::scientificExecutionCircuitSweepPrepare',['document_id','parameters','items','options']),
 'circuit_sweep_submit':('::GX::scientificExecutionCircuitSweepSubmit',['preparation','options'])}
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
  if key in result:result[key]=int(result[key]) if str(result[key]) else None
 return result

def core_capabilities(host, raw):
 result=host.as_dict(raw)
 for key in ('numeric','statistics','scientific_execution','script_job','parallel_execution'):
  item=host.as_dict(result[key])
  for field in ('operations','foundation_operations','capabilities','octave_callback_operations','operation_kinds'):
   if field in item:item[field]=[str(v) for v in host.as_list(item[field])]
  if 'policy' in item:item['policy']=host.as_dict(item['policy'])
  result[key]=item
 return result

def circuit_receipt(host,raw):
 result=host.as_dict(raw)
 for key in ('document','parameters','source_guard','source_resource','component_values','net_mapping'):
  if key in result:result[key]=host.as_dict(result[key])
 if 'analyses' in result:result['analyses']=[str(v) for v in host.as_list(result['analyses'])]
 if 'probes' in result:result['probes']=[host.as_dict(v) for v in host.as_list(result['probes'])]
 if 'items' in result:result['items']=[circuit_receipt(host,v) for v in host.as_list(result['items'])]
 if 'coordination' in result:
  coordination=host.as_dict(result['coordination']);children=[]
  if 'results' not in coordination:
   result['coordination']=coordination
   return result
  for value in host.as_list(coordination['results']):
   child=host.as_dict(value)
   if 'value' in child:
    entry=circuit_receipt(host,child['value'])
    for field in ('submitted','coordination'):
     if field in entry and not isinstance(entry[field],dict):entry[field]=host.as_dict(entry[field])
    child['value']=entry
   children.append(child)
  coordination['results']=children;result['coordination']=coordination
 return result

def invoke(host,operation,args):
 if operation not in COMMANDS or (len(args)!=len(COMMANDS[operation][1]) and not (operation=='log' and len(args)==3)):
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid scientific execution operation arguments')
 host.call('::GX::scientificExecutionRegisterBuiltins')
 if operation=='circuit_sweep_submit' and (not isinstance(args[-1],dict) or set(args[-1])-{'workers','fail_fast','run_id'}):
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Script sweep options require a data dictionary; Tcl progress callbacks are not admitted')
 raw=host.call(COMMANDS[operation][0],*args)
 if operation=='node_list':return [host.normalize(host.as_dict(v)) for v in host.as_list(raw)]
 if operation=='node_inspect':
  result=host.as_dict(raw)
  providers=[]
  for value in host.as_list(result.get('providers',())):
   provider=host.as_dict(value);provider['tools']={str(k):bool(int(v)) for k,v in host.as_dict(provider['tools']).items()};provider['available']=bool(int(provider['available']));providers.append(provider)
  result['providers']=providers;result['policy']=host.as_dict(result['policy']);result['cores']=int(result['cores'])
  if 'core_apis' in result:result['core_apis']=core_capabilities(host,result['core_apis'])
  return host.normalize(result)
 if operation=='core_capabilities':return host.normalize(core_capabilities(host,raw))
 if operation.startswith('circuit_'):return host.normalize(circuit_receipt(host,raw))
 if operation=='destination':return str(raw)
 if operation=='discover':return [str(v) for v in host.as_list(raw)]
 if operation=='prepare':return str(raw)
 return host.normalize(receipt(host,raw))
