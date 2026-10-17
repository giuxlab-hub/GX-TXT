"""Retained callable query adaptation; public Numeric and CORE remain owners."""
# SPDX-License-Identifier: GPL-3.0-or-later
import numpy as np
from gxtxt_script_bridge_server import BridgeError, CallbackRef, NumericArray


def run(host, callback, encoded):
    if not isinstance(callback, CallbackRef) or not isinstance(encoded, str):
        raise BridgeError('GXTXT:Fitter:Query', 'A live supervised callable and inert query request are required')
    identity = host.modules['SCRIPT_EXECUTION_API_v1'].invoke(host, 'current_callable', [])
    request = host.as_dict(host.call('::GX::DatasetCurveFit::_queryRegisteredPrepareJob', encoded, identity))
    text = lambda v: str(host.tcl.call('format', '%s%s', v, ''))
    vector = lambda v: np.asarray([float(x) for x in host.as_list(v)])
    captured = host.as_dict(request['model'])
    model = {name:text(captured[name]) for name in ('kind','source_sha256','binding_sha256','predictor_domain')}
    model['parameter_ids'] = [text(v) for v in host.as_list(captured['parameter_ids'])]
    for name in ('parameters','lower_bounds','upper_bounds','fixed_mask','initial_parameters'):
        if name in captured:
            model[name] = NumericArray(vector(captured[name]))
    model['callback'] = callback
    options = host.as_dict(request['options'])
    for name in list(options):
        if name in ('orientation','extrapolation'):
            options[name] = text(options[name])
        elif name in ('domain','translation','tangent_floors'):
            options[name] = NumericArray(vector(options[name]))
        else:
            values = vector(options[name])
            if values.size != 1:
                raise BridgeError('GXTXT:Fitter:Query', 'Scalar query option has an invalid shape')
            options[name] = float(values[0])
    scales = {name:options.pop(name) for name in ('derivative_scale','inverse_derivative_scale') if name in options}
    action = text(request['action']);values = NumericArray(vector(request['values']))
    numeric = host.modules['NUMERIC_API_v1']
    if action == 'query':
        result = numeric.invoke(host, 'model_query', [model, values, options])
        for raw, converted, scale in (('derivative','interpreted_derivative','derivative_scale'),
                                      ('inverse_derivative','interpreted_inverse_derivative','inverse_derivative_scale')):
            mapped = np.full(len(values.values), np.nan)
            raw_values = np.asarray(result[raw].values).ravel()
            valid = np.asarray(result[raw+'_valid'].values).ravel().astype(bool) & np.isfinite(raw_values)
            if scale in scales and np.any(valid):
                scaled = numeric.invoke(host, 'array_binary', ['multiply', {'kind':'vector','value':NumericArray(raw_values[valid])}, {'kind':'scalar','value':scales[scale]}])
                scaled_values = scaled['values']
                mapped[valid] = np.asarray(scaled_values.values if isinstance(scaled_values, NumericArray) else scaled_values).reshape(-1)
            valid &= np.isfinite(mapped)
            mapped[~valid] = np.nan
            result[converted] = NumericArray(mapped);result[converted+'_valid'] = NumericArray(valid.astype(float))
        points = np.asarray(result.pop('points').values).reshape(-1,2,order='F')
        result['x'] = NumericArray(points[:,0]);result['y'] = NumericArray(points[:,1])
        columns = ['query','x','y','predicted','is_extrapolated','derivative','derivative_valid',
                   'inverse_derivative','inverse_derivative_valid','tangent_x','tangent_y','model_response_derivative',
                   'interpreted_derivative','interpreted_inverse_derivative','interpreted_derivative_valid',
                   'interpreted_inverse_derivative_valid','difference_step']
    else:
        result = numeric.invoke(host, 'model_inverse', [model, values, NumericArray(vector(request['bracket'])), options])
        columns = ['targets','roots','valid','residual','is_extrapolated','iterations','function_evaluations']
    table = np.column_stack([np.asarray(result.pop(name).values).ravel() for name in columns])
    metadata = {name:(list(value.values) if isinstance(value, NumericArray) else value) for name,value in result.items()}
    resource = host.modules['MANAGED_RESOURCE_API_v1'].invoke(host, 'write_numeric', [text(request['document_id']), columns,
        NumericArray(table.ravel(order='F'), list(table.shape)), {'format':'float64_interleaved_le','role':'ephemeral_retained_query'}])
    return {'schema':'gxtxt.fitter_query_resource.v1','document_id':text(request['document_id']),
            'nonce':text(request['nonce']),'action':action,'resource':resource,'metadata':metadata,
            'lifetime':'temporary_until_request_consumed'}
