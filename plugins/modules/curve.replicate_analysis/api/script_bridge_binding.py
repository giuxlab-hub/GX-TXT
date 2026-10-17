"""Independent CORE Replicate service; no ordinary Analysis enablement."""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
from gxtxt_script_bridge_server import BridgeError, NumericArray

_ARGS = {'capabilities':[], 'preflight':['request'], 'preflight_encoded':['request_base64'],
         'submit':['request'], 'status':['ticket'], 'cancel':['ticket'], 'result':['ticket'],
         'publish':['ticket'], 'describe_output':['dataset_id'], 'encode_result':['result']}
REGISTRATION = dict(api_id='CURVE_REPLICATE_ANALYSIS_API_v1', api_version=1,
    provider_kind='module', provider_id='curve.replicate_analysis',
    documentation_ref='plugins/modules/curve.replicate_analysis/SCIENTIFIC_API.md',
    operations={op:dict(name=op, summary='Public Replicate service: '+op,
        arguments=[dict(name=k,kind='public value',required=True) for k in keys],
        result_contract='versioned scientific/Job/canonical output receipt') for op,keys in _ARGS.items()})

def _text(host, value):
    return str(host.tcl.call('format','%s%s',value,''))

def _request(host, raw):
    request={k:_text(host,v) for k,v in host.as_dict(raw).items()}
    request['reference_frame']={k:_text(host,v) for k,v in host.as_dict(request['reference_frame']).items()}
    request['grid_points']=int(request['grid_points'])
    request['independent_observation_count']=int(request['independent_observation_count'])
    traces=[]
    for value in host.as_list(request['traces']):
        trace={k:_text(host,v) for k,v in host.as_dict(value).items()}
        if 'filters' in trace: trace['filters']=[{k:_text(host,x) for k,x in host.as_dict(v).items()} for v in host.as_list(trace['filters'])]
        if 'phase_index' in trace: trace['phase_index']=int(trace['phase_index'])
        traces.append(trace)
    request['traces']=traces
    return request

def _plain(value):
    if isinstance(value, NumericArray):
        return [v.item() if hasattr(v,'item') else v for v in value.values]
    if isinstance(value,dict): return {k:_plain(v) for k,v in value.items()}
    if isinstance(value,(list,tuple)): return [_plain(v) for v in value]
    return value

def invoke(host, operation, args):
    if operation not in _ARGS or len(args)!=len(_ARGS[operation]):
        raise BridgeError('GXTXT:Replicate:Arguments','Invalid public Replicate operation arguments')
    host.call('::GX::modulePublicApiActivate','curve.replicate_analysis','CURVE_REPLICATE_ANALYSIS_API_v1')
    if operation=='encode_result':
        raw=str(host.tcl.call('format','%s',host.tcl_arg(_plain(args[0]))))
        return base64.b64encode(raw.encode('utf-8')).decode('ascii')
    if operation=='preflight_encoded':
        args=[base64.b64decode(args[0],validate=True).decode('utf-8')]
        operation='preflight'
    result=host.call('::GX::Replicate::'+operation,*args)
    if operation=='preflight':return _request(host,result)
    if operation=='capabilities':
        receipt={k:_text(host,v) for k,v in host.as_dict(result).items()}
        for key in ('methods','designs','operations','uncertainty'):receipt[key]=host.as_list(receipt[key])
        for key in ('api_version','maximum_traces','maximum_points_per_trace','maximum_xy_vertices','maximum_grid'):receipt[key]=int(receipt[key])
        receipt['implicit_analysis_enable']=bool(int(receipt['implicit_analysis_enable']))
        return receipt
    if operation in ('status','cancel'):return {k:_text(host,v) for k,v in host.as_dict(result).items()}
    if operation=='publish':
        raw=host.as_dict(result);receipt={k:_text(host,v) for k,v in raw.items()}
        receipt['outputs']={k:_text(host,v) for k,v in host.as_dict(raw['outputs']).items()}
        receipt['dataset_ids']=[_text(host,v) for v in host.as_list(raw['dataset_ids'])]
        return receipt
    # Tickets preserve their exact request serialization for immutable Job checks.
    if operation=='submit':return _text(host,result)
    if operation=='result':
        raw=host.as_dict(result)
        receipt={k:_text(host,v) for k,v in raw.items()}
        receipt['columns']={k:[float(x) for x in host.as_list(v)] for k,v in host.as_dict(raw['columns']).items()}
        for field in ('units','roles','qualifications','metadata'):
            receipt[field]={k:_text(host,v) for k,v in host.as_dict(raw[field]).items()}
        receipt['original_traces']={}
        for key,value in host.as_dict(raw['original_traces']).items():
            trace=host.as_dict(value)
            receipt['original_traces'][key]=dict(points=[[float(x) for x in host.as_list(point)] for point in host.as_list(trace['points'])],source_rows=[int(row) for row in host.as_list(trace['source_rows'])],identity={k:_text(host,v) for k,v in host.as_dict(trace['identity']).items()},descriptor_utf8=_text(host,trace['descriptor']))
        receipt['aligned_traces']={key:[[float(x) for x in host.as_list(point)] for point in host.as_list(value)] for key,value in host.as_dict(raw['aligned_traces']).items()}
        receipt['source_rows']={k:{field:([int(x) for x in host.as_list(value)] if field=='source_rows' else _text(host,value)) for field,value in host.as_dict(v).items()} for k,v in host.as_dict(raw['source_rows']).items()}
        return receipt
    if operation=='describe_output':
        raw=host.as_dict(result)
        return dict(dataset_id=_text(host,raw['dataset_id']),metadata={k:_text(host,v) for k,v in host.as_dict(raw['metadata']).items()},schema=[{k:_text(host,v) for k,v in host.as_dict(row).items()} for row in host.as_list(raw['schema'])])
    return host.normalize(result)
