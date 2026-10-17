"""Public Numeric retained queries for execution-scoped callback models."""
# SPDX-License-Identifier: GPL-3.0-or-later
import numpy as np
from gxtxt_script_bridge_server import BridgeError


def _error(message):
    raise BridgeError('GXTXT:Numeric:ModelQuery', message)


def _vector(backend, value, name, maximum):
    value = backend._array(value, name)
    if value.ndim > 2 or (value.ndim == 2 and min(value.shape) != 1) or not 1 <= value.size <= maximum:
        _error(f'{name} requires one to {maximum} exact finite values')
    return value.ravel(order='F')


def _scalar(backend, value, name):
    return float(backend._array(value, name, scalar=True).ravel()[0])


def _setup(backend, query, options, extra):
    allowed = {'domain', 'extrapolation', 'orientation', 'translation'} | extra
    if not isinstance(options, dict) or set(options) - allowed:
        _error('Unknown callback query option')
    query = _vector(backend, query, 'Query', 1000000)
    domain = _vector(backend, options.get('domain'), 'Retained training domain', 2)
    if domain.size != 2 or domain[0] >= domain[1]:
        _error('A finite increasing retained training domain is required')
    policy = options.get('extrapolation', 'error')
    if policy not in ('error', 'allow'):
        _error('Extrapolation must be error or explicit allow')
    outside = (query < domain[0]) | (query > domain[1])
    if policy == 'error' and np.any(outside):
        _error('Query is outside the retained training domain')
    orientation = options.get('orientation', 'y_of_x')
    if orientation not in ('y_of_x', 'x_of_y'):
        _error('Registered scalar callbacks require y_of_x or x_of_y orientation')
    delta = _vector(backend, options.get('translation', [0., 0.]), 'Translation', 2)
    if delta.size != 2:
        _error('Two physical coordinate translations are required')
    return query, domain, policy, outside, orientation, delta


def _predict(host, backend, model, values):
    result = backend.evaluate_model(host, model, backend._wire(values), {})
    return backend._array(result['predicted'], 'Model response').ravel(order='F')


def _differentiate(host, backend, model, x, base, step, relative):
    """Compare second-order one-sided estimates at actual representable nodes.

    Agreement is a numerical diagnostic, not a proof of differentiability.
    No unit response floor hides a small-amplitude cusp.
    """
    derivative = np.full(x.size, np.nan)
    if model.get('predictor_domain', 'finite_real') == 'positive_real':
        step = np.minimum(step, .25 * x)
    with np.errstate(over='ignore', invalid='ignore', divide='ignore'):
        xm, xmh, xph, xp = x-step, x-step/2, x+step/2, x+step
        possible = (np.isfinite(xm) & np.isfinite(xp) & (xm < xmh) &
                    (xmh < x) & (x < xph) & (xph < xp))
    if not np.any(possible):
        return derivative, possible, step, 'No representable two-sided difference stencil.'
    nodes = [np.where(possible, v, x) for v in (xm, xmh, xph, xp)]
    try:
        fm, fmh, fph, fp = [_predict(host, backend, model, v) for v in nodes]
    except BridgeError as failure:
        return derivative, np.zeros(x.size, dtype=bool), step, 'Difference evaluation unavailable: ' + str(failure)
    with np.errstate(over='ignore', invalid='ignore', divide='ignore'):
        am, bm, ap, bp = xmh-x, xm-x, xph-x, xp-x
        wl1, wl2 = bm/(am*(bm-am)), -am/(bm*(bm-am))
        wr1, wr2 = bp/(ap*(bp-ap)), -ap/(bp*(bp-ap))
        left = wl1*(fmh-base) + wl2*(fm-base)
        right = wr1*(fph-base) + wr2*(fp-base)
        scale = np.maximum(np.abs(left), np.abs(right))
        roundoff = 32*np.finfo(float).eps * (
            np.abs(wl1)*(np.abs(fmh)+np.abs(base)) + np.abs(wl2)*(np.abs(fm)+np.abs(base)) +
            np.abs(wr1)*(np.abs(fph)+np.abs(base)) + np.abs(wr2)*(np.abs(fp)+np.abs(base)))
        valid = possible & np.isfinite(left) & np.isfinite(right) & np.isfinite(roundoff)
        valid &= np.abs(left-right) <= relative*scale+roundoff
        derivative[valid] = .5*left[valid]+.5*right[valid]
        valid &= np.isfinite(derivative)
    derivative[~valid] = np.nan
    return derivative, valid, step, 'Two one-sided numerical estimates agree within the declared tolerance and roundoff bound; differentiability is not certified.'


def query_model(host, backend, model, values, options):
    query, domain, policy, outside, orientation, delta = _setup(backend, values, options,
        {'derivative', 'tangent_floors', 'difference_step', 'difference_relative_tolerance'})
    requested = options.get('derivative', 1.)
    requested = float(requested) if isinstance(requested, bool) else _scalar(backend, requested, 'Derivative flag')
    if requested not in (0., 1.):
        _error('Derivative must be boolean')
    floors = _vector(backend, options.get('tangent_floors', [0., 0.]), 'Tangent floors', 2)
    if floors.size != 2 or np.any(floors < 0):
        _error('Two nonnegative coordinate-tangent floors are required')
    relative = _scalar(backend, options.get('difference_relative_tolerance', 1e-4), 'Difference agreement tolerance')
    if not 1e-12 <= relative <= .1:
        _error('Difference agreement tolerance must be between 1e-12 and 0.1')
    if 'difference_step' in options:
        h = _scalar(backend, options['difference_step'], 'Difference step')
        if h <= 0:
            _error('Difference step must be positive in the independent coordinate unit')
        step = np.full(query.size, h)
    else:
        # Physical coordinate scales avoid inflating the stencil by a reversible
        # fitting translation. Unrepresentable increments remain unavailable.
        span = max(abs(domain[0]), abs(domain[1]), 1.)
        step = np.cbrt(np.finfo(float).eps)*np.maximum(span, np.abs(query))
    with np.errstate(over='ignore', invalid='ignore'):
        x = query + delta[0]
    base = _predict(host, backend, model, x)
    response = base-delta[1]
    if not np.all(np.isfinite(response)):
        _error('Physical model response is nonfinite')
    slope = np.full(query.size, np.nan); regular = np.zeros(query.size, dtype=bool)
    method = 'not_requested'; reason = 'Derivative not requested.'
    if requested:
        slope, regular, step, reason = _differentiate(host, backend, model, x, base, step, relative)
        method = 'two_sided_second_order_finite_difference_agreement'
    tx = np.where(regular, 1., np.nan); ty = slope.copy()
    points = np.column_stack((query, response))
    if orientation == 'x_of_y':
        points = points[:, ::-1]; tx, ty = ty, tx
    valid = regular & (np.abs(tx) > floors[0])
    inverse_valid = regular & (np.abs(ty) > floors[1])
    derivative = np.full(query.size, np.nan); inverse = derivative.copy()
    with np.errstate(over='ignore', invalid='ignore', divide='ignore'):
        derivative[valid] = ty[valid]/tx[valid]
        inverse[inverse_valid] = tx[inverse_valid]/ty[inverse_valid]
    valid &= np.isfinite(derivative); inverse_valid &= np.isfinite(inverse)
    derivative[~valid] = np.nan; inverse[~inverse_valid] = np.nan
    result = {'schema':'gxtxt.model_query.v1', 'parametric':False, 'extrapolation':policy,
              'orientation':orientation, 'derivative_method':method, 'derivative_reason':reason,
              'difference_relative_tolerance':relative, 'fit_performed':False, 'uncertainty_available':False}
    arrays = {'query':query, 'domain':domain, 'translation':delta, 'points':points, 'predicted':response,
              'is_extrapolated':outside, 'tangent_x':tx, 'tangent_y':ty, 'tangent_floors':floors,
              'derivative':derivative, 'derivative_valid':valid, 'inverse_derivative':inverse,
              'inverse_derivative_valid':inverse_valid, 'model_response_derivative':slope, 'difference_step':step}
    result.update({name:backend._wire(value) for name,value in arrays.items()})
    return result


def inverse_model(host, backend, model, targets, bracket, options):
    extra = {'x_tolerance', 'response_tolerance', 'max_iterations'}
    query, domain, policy, outside, orientation, delta = _setup(backend, bracket, options, extra)
    if query.size != 2 or query[0] >= query[1]:
        _error('Supply two increasing endpoints of an explicit continuous branch')
    targets = _vector(backend, targets, 'Inverse response targets', 64)
    xtol = _scalar(backend, options.get('x_tolerance', 1e-12), 'Inverse coordinate tolerance')
    ytol = _scalar(backend, options.get('response_tolerance', 1e-10), 'Inverse response tolerance')
    limit = _scalar(backend, options.get('max_iterations', 128), 'Inverse iteration limit')
    if xtol <= 0 or ytol <= 0 or not 1 <= limit <= 256 or limit != int(limit):
        _error('Positive absolute tolerances and an integer iteration budget 1..256 are required')
    qopts = {k:v for k,v in options.items() if k not in extra}; qopts['derivative'] = 0.
    endpoints = backend._array(query_model(host, backend, model, query, qopts)['predicted'], 'Endpoints').ravel()
    roots = np.full(targets.size, np.nan); residual = roots.copy()
    valid = np.zeros(targets.size, dtype=bool); iterations = np.zeros(targets.size); evaluations = iterations.copy(); reasons = []
    for index, target in enumerate(targets):
        a, b = endpoints-target
        if a == 0 and b == 0:
            reasons.append('Both bracket endpoints match; no unique local inverse is established.'); continue
        if a != 0 and b != 0 and np.sign(a) == np.sign(b):
            reasons.append('No sign-changing bracket; a local root is not established.'); continue
        def response(x):
            return float(backend._array(query_model(host, backend, model, [x], qopts)['predicted'], 'Inverse response').ravel()[0])-target
        try:
            if a == 0 or b == 0:
                root = query[0] if a == 0 else query[1]; converged = True
            else:
                solved = backend.solve_root(response, query, xtol, int(limit))
                root = solved.root; converged = solved.converged
                iterations[index] = solved.iterations; evaluations[index] = solved.function_calls
            value = response(root)
        except (BridgeError, ValueError, ArithmeticError) as failure:
            iterations[index] = np.nan; evaluations[index] = np.nan
            reasons.append('Root evaluation failed: '+str(failure)); continue
        if converged and np.isfinite(root) and query[0] <= root <= query[1] and np.isfinite(value) and abs(value) <= ytol:
            roots[index] = root; residual[index] = value; valid[index] = True
            reasons.append('Local root verified against response tolerance; global uniqueness is not certified.')
        else:
            reasons.append('Solver did not establish an in-bracket root within the response tolerance.')
    result = {'schema':'gxtxt.model_inverse.v1', 'reasons':reasons, 'x_tolerance':xtol, 'response_tolerance':ytol,
              'uniqueness':'not_certified', 'branch_contract':'caller_declares_continuous_branch',
              'fit_performed':False, 'uncertainty_available':False}
    arrays = {'targets':targets, 'roots':roots, 'valid':valid, 'residual':residual, 'bracket':query, 'domain':domain,
              'is_extrapolated':valid & ((roots < domain[0]) | (roots > domain[1])),
              'iterations':iterations, 'function_evaluations':evaluations}
    result.update({name:backend._wire(value) for name,value in arrays.items()})
    return result
