"""Callback refit driver using the shared Numeric bootstrap stages."""
# SPDX-License-Identifier: GPL-3.0-or-later
import os
import time
import numpy as np
import scipy
from gxtxt_script_bridge_server import BridgeError, NumericArray


def _wire(value):
    value = np.asarray(value)
    if value.ndim == 1:
        value = value.reshape(-1, 1)
    return NumericArray(value.ravel(order='F'), list(value.shape))


def run(host, backend, model, predictors, response, plan, options=None):
    if (not isinstance(plan, dict) or plan.get('api_id') != 'STATISTICAL_FIT_BOOTSTRAP_PLAN_v1'
            or plan.get('status') != 'value' or plan.get('source_operation') != 'nonlinear_fit'):
        raise BridgeError('GXTXT:Numeric:Bootstrap', 'An eligible CORE nonlinear bootstrap plan is required')
    policy = plan.get('solver_policy', {})
    if (policy.get('backend') != 'scipy.optimize.least_squares'
            or policy.get('backend_version') != scipy.__version__):
        raise BridgeError('GXTXT:Numeric:Bootstrap', 'The captured callback solver backend/version must match this Job')
    if os.environ.get('GXTXT_JOB_INTERNAL_THREADS') != '1':
        raise BridgeError('GXTXT:Numeric:Bootstrap', 'Callback bootstrap requires a Job with one internal thread')
    n, p, reps = (int(plan[key]) for key in ('n', 'p', 'replicates'))
    if (not 2 <= n <= 1000000 or not 1 <= p <= 128 or not 20 <= reps <= 10000
            or n*reps > 10000000 or n*p*reps > 128000000
            or 80*n*p+176*n+32*reps*p+64*p*p > 536870912):
        raise BridgeError('GXTXT:Numeric:Bootstrap', 'Callback bootstrap exceeds the shared shape/work budget')
    if (model.get('source_sha256') != plan.get('model_source_sha256')
            or model.get('binding_sha256') != plan.get('model_binding_sha256')
            or model.get('parameter_ids') != plan.get('parameter_ids')
            or not np.array_equal(backend._array(model['parameters'], 'parameters').ravel(order='F'),
                                  backend._array(plan['source_parameters'], 'source parameters').ravel(order='F'))):
        raise BridgeError('GXTXT:Numeric:Bootstrap', 'Callback identity or parameters differ from the captured fit')
    for field in ('fixed_mask', 'lower_bounds', 'upper_bounds'):
        if field not in model or field not in policy or not np.array_equal(
                backend._array(model[field], field, finite=False).ravel(order='F'),
                backend._array(policy[field], field, finite=False).ravel(order='F')):
            raise BridgeError('GXTXT:Numeric:Bootstrap', 'Callback declaration differs from the captured '+field)
    settings = {name: policy[name] for name in (
        'lower_bounds', 'upper_bounds', 'fixed_mask', 'parameter_scales',
        'function_tolerance', 'gradient_tolerance', 'parameter_tolerance', 'max_function_evaluations')}
    settings.update(solver=policy['requested_solver'], method=policy['strategy'])
    numeric = host.modules['NUMERIC_API_v1']
    evaluated = backend.evaluate_model(host, model, predictors, {'jacobian': False})
    captured = dict(model)
    del captured['callback']
    captured.update(kind='registered_callback_evaluation', evaluation_query=predictors,
                    predicted=evaluated['predicted'])
    prepared = numeric.invoke(host, 'fit_bootstrap_prepare',
                              [captured, predictors, response, plan, options or {}])
    parameters = backend._array(prepared['parameters'], 'parameters').ravel(order='F')
    fixed = backend._array(prepared['fixed_mask'], 'fixed mask').ravel(order='F').astype(bool)
    samples = np.full((reps, len(parameters)), np.nan)
    statuses = np.zeros(reps, dtype=np.uint8)
    seeds = np.zeros(reps, dtype=np.uint32)
    seed = int(plan['seed'])
    messages = []
    attempted = 0
    started = time.perf_counter()
    deadline = started + float(plan['max_seconds'])
    for trial in range(reps):
        if time.perf_counter() >= deadline:
            break
        seeds[trial] = seed
        attempted += 1
        try:
            draw = numeric.invoke(host, 'fit_bootstrap_draw', [prepared, seed])
            seed = int(draw['next_seed'])
            if not np.all(np.isfinite(backend._array(draw['response'], 'response', finite=False))):
                statuses[trial] = 4
                continue
            local = dict(settings)
            if plan['weight_semantics'] != 'unweighted':
                local.update(weights=draw['weights'], weight_semantics=plan['weight_semantics'])
            current = backend.invoke_legacy(host, 'nonlinear_fit', [
                draw['predictors'], draw['response'], model['callback'], prepared['parameters'], local],
                deadline=deadline)
            values = backend._array(current['parameters'], 'parameters').ravel(order='F')
            if current['rank'] != int(plan['free_parameter_count']):
                statuses[trial] = 2
            elif not current['converged']:
                statuses[trial] = 3
            elif (values.size != parameters.size or not np.all(np.isfinite(values))
                  or not np.array_equal(values[fixed], parameters[fixed])):
                statuses[trial] = 4
            else:
                samples[trial] = values
                active = backend._array(current['active_bounds'], 'active bounds').ravel(order='F').astype(bool)
                statuses[trial] = 6 if np.any(active & ~fixed) else 1
        except Exception as failure:
            identifier = getattr(failure, 'identifier', '')
            if identifier in ('GXTXT:ScriptCallback:Timeout', 'GXTXT:ScriptCallback:Transport',
                              'GXTXT:ScriptCallback:UnknownCallback') or identifier.startswith('GXTXT:ScientificTransport:'):
                raise
            message = str(failure)[:512]
            if len(messages) < 8 and message not in messages:
                messages.append(message)
            if identifier == 'GXTXT:Numeric:BootstrapBudget':
                statuses[trial] = 7
                break
            statuses[trial] = 2 if 'rank deficient' in message.lower() or 'zero-spread' in message.lower() else 5
    execution = dict(attempted_count=attempted, next_seed=seed,
                     elapsed_seconds=time.perf_counter()-started, messages=messages)
    return numeric.invoke(host, 'fit_bootstrap_summarize',
                          [prepared, _wire(samples), _wire(statuses), _wire(seeds), execution])
