"""Bounded registered manual curves; Numeric evaluates, CORE owns resources."""
# SPDX-License-Identifier: GPL-3.0-or-later
import numpy as np
from gxtxt_script_bridge_server import BridgeError, CallbackRef, NumericArray


def run(host, callback, payload):
    if not isinstance(callback, CallbackRef) or not isinstance(payload, str):
        raise BridgeError('GXTXT:Fitter:ManualModel', 'A live supervised callable and inert request are required')
    identity = host.modules['SCRIPT_EXECUTION_API_v1'].invoke(host, 'current_callable', [])
    prepared = host.as_dict(host.call('::GX::DatasetCurveFit::_parameterRegisteredPrepareJob', payload, identity))
    registered = host.as_dict(prepared['registered'])
    definition = host.as_dict(registered['definition'])
    context = host.as_dict(prepared['context'])

    def vector(value):
        return np.asarray([float(item) for item in host.as_list(value)])

    values = vector(prepared['parameters'])
    initial = vector(context['initial'])
    lower = vector(definition['lower_bounds'])
    upper = vector(definition['upper_bounds'])
    fixed = vector(definition['fixed_mask']).astype(bool) if 'fixed_mask' in definition else np.zeros(len(initial), dtype=bool)
    fixed |= lower == upper
    if (values.size != initial.size or values.size != lower.size or not np.all(np.isfinite(values))
            or np.any(values < lower) or np.any(values > upper) or np.any(values[fixed] != initial[fixed])):
        raise BridgeError('GXTXT:Fitter:ManualModel', 'Manual values violate their registered bounds or fixed values')
    query = vector(context['query'])
    model = {'kind': 'registered_callback', 'callback': callback, 'parameters': NumericArray(values),
             'parameter_ids': [str(v) for v in host.as_list(definition['parameter_ids'])],
             'source_sha256': str(registered['source_sha256']), 'binding_sha256': str(registered['declaration_sha256']),
             'predictor_domain': str(definition['predictor_domain']), 'lower_bounds': NumericArray(lower),
             'upper_bounds': NumericArray(upper), 'fixed_mask': NumericArray(fixed), 'initial_parameters': NumericArray(initial)}
    evaluated = host.modules['NUMERIC_API_v1'].invoke(host, 'nonlinear_evaluate', [model, NumericArray(query, [len(query), 1])])
    u = query - float(context['du'])
    v = np.asarray(evaluated['predicted'].values).ravel() - float(context['dv'])
    points = np.column_stack((v, u) if str(context['orientation']) == 'x_of_y' else (u, v))
    if not np.all(np.isfinite(points)):
        raise BridgeError('GXTXT:Fitter:ManualModel', 'Manual callback returned nonfinite physical coordinates')
    resource = host.modules['MANAGED_RESOURCE_API_v1'].invoke(host, 'write_numeric', [str(prepared['document_id']), ['x', 'y'],
        NumericArray(points.ravel(order='F'), list(points.shape)), {'format': 'float64_interleaved_le', 'role': 'ephemeral_manual_curve'}])
    return {'schema': 'gxtxt.fitter_parameter_resource.v1', 'document_id': str(prepared['document_id']),
            'nonce': str(prepared['nonce']), 'points': resource, 'evaluation_only': True, 'accepted': False,
            'lifetime': 'temporary_until_request_consumed'}
