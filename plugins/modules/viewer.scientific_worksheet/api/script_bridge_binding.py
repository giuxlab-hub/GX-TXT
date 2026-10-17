"""Public Worksheet value facades; opaque Book values never expose storage paths."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
_METHODS = {
 'new':('new',0,1), 'load':('load',1,1), 'save':('save',1,1),
 'set_cell':('setCell',3,3), 'set_typed_cell':('setTypedCell',3,3),
 'set_column':('setColumn',3,4), 'define_range':('defineRange',4,4),
 'create_sheet':('createSheet',2,2), 'select_sheet':('selectSheet',2,2),
 'rename_sheet':('renameSheet',3,3), 'delete_sheet':('deleteSheet',2,2),
 'chart_add':('chartAdd',2,2), 'chart_update':('chartUpdate',3,3), 'chart_remove':('chartRemove',2,2),
 'bind_dataset':('bindDataset',3,6), 'publish':('publish',5,6),
 'identity':('bookIdentity',1,1), 'inspect_cell':('value',2,2),
 'capture_operation':('captureOperationEncoded',1,1),
}
_ARGUMENTS = {
 'new':['name?'], 'load':['document_id'], 'save':['workbook_utf8'],
 'set_cell':['workbook_utf8','address','source'], 'set_typed_cell':['workbook_utf8','address','typed_item'],
 'set_column':['workbook_utf8','column','name','unit?'], 'define_range':['workbook_utf8','name','first','last'],
 'create_sheet':['workbook_utf8','name'], 'select_sheet':['workbook_utf8','name'],
 'rename_sheet':['workbook_utf8','old','new'], 'delete_sheet':['workbook_utf8','name'],
 'chart_add':['workbook_utf8','descriptor'], 'chart_update':['workbook_utf8','chart_id','descriptor'], 'chart_remove':['workbook_utf8','chart_id'],
 'bind_dataset':['workbook_utf8','dataset_id','mappings','first_row?','limit?','selection_id?'],
 'publish':['workbook_utf8','mappings','first','last','dataset_id','display_name?'],
 'identity':['workbook_utf8'], 'inspect_cell':['workbook_utf8','address'],
 'capture_operation':['request_base64'],
}
REGISTRATION = {
 'api_id':'SCIENTIFIC_WORKSHEET_API_v1', 'api_version':1,
 'provider_kind':'module', 'provider_id':'viewer.scientific_worksheet',
 'documentation_ref':'plugins/modules/viewer.scientific_worksheet/docs/MODEL_API.md',
 'operations':{name:{'name':name,'summary':'Existing public Worksheet model: '+name,
  'arguments':[{'name':arg.rstrip('?'),'kind':'public value','required':not arg.endswith('?')} for arg in _ARGUMENTS[name]],
  'argument_convention':', '.join(_ARGUMENTS[name]),
  'result_contract':('typed inspection receipt' if name=='inspect_cell' else 'public identity/publication receipt' if name in ('identity','publish') else 'opaque UTF-8 Workbook or bounded capture'),
  'unit_behavior':'Actual Worksheet/CORE Unit Registry and provider-owned scientific contracts; canonical source values unchanged'}
  for name in _METHODS}}
def _text(host,value):
 return value.decode('utf-8') if isinstance(value,bytes) else str(host.tcl.call('format','%s%s',value,''))
def invoke(host,operation,args):
 if operation not in _METHODS:
  raise BridgeError('GXTXT:ScriptBridge:UnknownOperation','Unknown public Worksheet operation')
 method,minimum,maximum=_METHODS[operation]
 if not minimum<=len(args)<=maximum:
  raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Invalid public Worksheet arguments for '+operation)
 host.call('::GX::modulePublicApiActivate','viewer.scientific_worksheet','SCIENTIFIC_WORKSHEET_API_v1')
 raw=host.call('::GX::ScientificWorksheet::'+method,*args)
 if operation=='bind_dataset':
  values=host.as_list(raw)
  return {'workbook_utf8':_text(host,values[0]),'row_count':int(values[1])}
 if operation=='inspect_cell':
  value=host.as_dict(raw)
  result={'kind':_text(host,value['kind']),'unit':_text(host,value['unit']),'value_utf8':_text(host,value['value'])}
  for key in ('shape','source_lineage','lineage','operation_status','stale_reason'):
   if key in value:result[key+'_utf8']=_text(host,value[key])
  return result
 if operation in ('identity','publish'):
  value=host.as_dict(raw)
  return {str(key):(int(item) if str(key) in ('revision','document_revision','row_count','sample_count') else _text(host,item)) for key,item in value.items()}
 return _text(host,raw)
