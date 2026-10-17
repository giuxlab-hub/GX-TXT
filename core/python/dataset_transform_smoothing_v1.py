"""Preserving Dataset adapter; Numeric owns all smoothing computations."""
# SPDX-License-Identifier: GPL-3.0-or-later
import math
import numpy as np
from gxtxt_script_bridge_server import NumericArray


def rows(t):
    if len(t.sources) != 1:
        raise ValueError('Smoothing requires one canonical Dataset')
    source=t.sources[0];ids=source['selected_variable_ids']
    x_id,y_id=(t.option(k,source.get(k,'')) for k in ('x_variable_id','y_variable_id'))
    if x_id==y_id or x_id not in ids or y_id not in ids:
        raise ValueError('Smoothing requires distinct selected X/Y Variable IDs')
    xi,yi=ids.index(x_id),ids.index(y_id);n=source['row_count']
    if not 1<=n<=1000000:
        raise ValueError('Smoothing supports at most one million selected rows')
    if any(source['schema'][i]['dtype'] not in ('float32','float64') for i in (xi,yi)):
        raise ValueError('Smoothing axes require float32/float64; convert integer coordinates explicitly')
    opts=t.dictionary(t.option('smoothing_options',''))
    if set(opts)-{'method','window','degree','robust_iterations','nonfinite'}:
        raise ValueError('Unknown smoothing option')
    opts.setdefault('method','savitzky_golay')
    for k in ('window','degree','robust_iterations'):
        if k in opts:opts[k]=float(opts[k])
    x,y=np.empty(n),np.empty(n)
    for pos,record in enumerate(t.source_rows(source)):
        for a,i in ((x,xi),(y,yi)):a[pos]=math.nan if record[i+2] is None else float(record[i+2])
    result=t.host.modules['NUMERIC_API_v1'].invoke(t.host,'smooth',[NumericArray(x),NumericArray(y),opts])
    positions=np.asarray(result['source_row_positions'].values,dtype=np.int64).ravel()-1
    smoothed=np.full(n,np.nan);residual=np.full(n,np.nan)
    smoothed[positions]=np.asarray(result['y'].values).ravel();residual[positions]=np.asarray(result['residuals'].values).ravel()
    outputs={k:t.option(k+'_variable_id',default) for k,default in (
        ('smoothed','smoothed_y'),('residual','smoothing_residual'),('row','smoothing_source_row_ordinal'))}
    t.schema=[dict(v) for v in source['schema']]
    if len(set(outputs.values()))!=3 or set(outputs.values()).intersection(ids):
        raise ValueError('Smoothed, residual and source-row Variable IDs must be distinct and new')
    unit=source['schema'][yi].get('unit','')
    t.schema += [t.field(outputs['smoothed'],'float64',unit,'data'),t.field(outputs['residual'],'float64',unit,'data'),t.field(outputs['row'],'uint64')]
    facts={k:v for k,v in result.items() if not isinstance(v,NumericArray)}
    t.smoothing_receipt={'schema':'gxtxt.smoothing_transform.v1','provider':'math.numeric',
        'source_dataset_id':source['dataset_id'],'source_sha256':source['sha256'],
        'x_variable_id':x_id,'original_y_variable_id':y_id,
        **{k+'_variable_id':v for k,v in outputs.items()},'row_identity':'original_dataset_zero_based_uint64',
        'method':result['method'],'original_n':n,'smoothed_n':len(positions),'omitted_n':n-len(positions),
        'options':opts,'estimator':facts,'uncertainty_policy':'smoothing_induces_correlated_errors_no_parameter_inference'}
    for pos,record in enumerate(t.source_rows(source)):
        yield list(record[2:])+[smoothed[pos],residual[pos],int(record[1])]
