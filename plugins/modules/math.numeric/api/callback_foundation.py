"""Execution-scoped callback operations for the public NUMERIC_API foundation."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import numpy as np
from scipy.integrate import solve_ivp
from scipy.optimize import minimize, root_scalar, minimize_scalar, least_squares

from gxtxt_script_bridge_server import BridgeError, CallbackRef, NumericArray


def _array(value, name, *, scalar=False, finite=True):
    if isinstance(value, NumericArray):
        result = np.asarray(value.values).reshape(value.shape, order="F")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        result = np.asarray(value, dtype=float)
    elif isinstance(value, (list, tuple, np.ndarray)):
        try:
            result = np.asarray(value)
        except (TypeError, ValueError) as exc:
            raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be numeric") from exc
    else:
        raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be numeric")
    if result.dtype.kind not in 'biuf' or np.iscomplexobj(result):
        raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be real numeric data")
    if result.dtype.kind in 'iu' and (np.any(result > 2**53) or (result.dtype.kind == 'i' and np.any(result < -(2**53)))):
        raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} contains integers not exactly representable by the float64 solver")
    result = np.asarray(result, dtype=float)
    if scalar and result.size != 1:
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", f"{name} must be scalar")
    if finite and not np.all(np.isfinite(result)):
        raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be finite")
    return result


def _wire(value):
    value = np.asarray(value, dtype=float)
    if value.ndim == 0:
        return float(value)
    if value.ndim == 1:
        value = value.reshape((-1, 1))
    return NumericArray(value.ravel(order="F"), value.shape)


def _result(value):
    value = np.asarray(value, dtype=float)
    return {"value_real": _wire(value), "value_imaginary": _wire(np.zeros_like(value))}


def _invoke(host, ref, *values):
    if not isinstance(ref, CallbackRef):
        raise BridgeError("GXTXT:ScriptCallback:InvalidArguments", "expected a registered callback handle")
    args = [_wire(value) if isinstance(value, (np.ndarray, np.number)) else value for value in values]
    return host.invoke_callback(ref, *args)


def _vector_return(host, ref, name, *args, length=None, scalar=False, column=False):
    raw = _invoke(host, ref, *args)
    try:
        result = _array(raw, name)
    finally:
        host.release_callback_values(raw)
    # Octave's wire format represents a 1-by-1 result as a scalar. It satisfies
    # the column contract only when this invocation expects exactly one row.
    if column and not (result.ndim == 0 and length == 1 or result.ndim == 1 or result.ndim == 2 and result.shape[1] == 1):
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "Declared model response must be N-by-1")
    if scalar and result.size != 1:
        raise BridgeError("GXTXT:Numeric:InvalidObjective", f"{name} must return a finite real scalar")
    if length is not None and result.size != length:
        raise BridgeError("GXTXT:Numeric:InvalidRHS", f"{name} returned {result.size} values; expected {length}")
    return result.ravel(order="F")


def _constraints(host, ref, x):
    raw = _invoke(host, ref, x)
    try:
        if not isinstance(raw, dict) or "equality" not in raw or "inequality" not in raw:
            raise BridgeError("GXTXT:Numeric:InvalidConstraint", "nonlinear callback must return equality and inequality fields")
        eq = _array(raw["equality"], "nonlinear equality").ravel(order="F")
        ineq = _array(raw["inequality"], "nonlinear inequality").ravel(order="F")
        return eq, ineq
    finally:
        host.release_callback_values(raw)


def _fit_policy(options, count):
    """Validate the actual Script callback backend, including evaluation-only runs."""
    allowed = {'solver', 'method', 'max_iterations', 'max_function_evaluations', 'tolerance',
               'function_tolerance', 'gradient_tolerance', 'parameter_tolerance', 'parameter_scales',
               'weights', 'sigma', 'weight_semantics', 'lower_bounds', 'upper_bounds', 'fixed_mask',
               'response_shape', 'selection', 'weight_variable_id'}
    if set(options)-allowed:
        raise BridgeError('GXTXT:Numeric:Solver', 'Unsupported Script callback options: '+', '.join(sorted(set(options)-allowed)))
    requested = options.get('solver', 'auto')
    if requested not in ('auto', 'least_squares', 'scipy_least_squares'):
        raise BridgeError('GXTXT:Numeric:Solver', 'Script callbacks use auto or scipy_least_squares; another backend cannot be selected implicitly')
    method = options.get('method', 'trf')
    if method not in ('trf', 'dogbox'):
        raise BridgeError('GXTXT:Numeric:Solver', 'Script callback method must be trf or dogbox')
    if 'max_iterations' in options and 'max_function_evaluations' in options:
        raise BridgeError('GXTXT:Numeric:Solver', 'Choose an explicit function-evaluation budget or legacy max_iterations, not both')
    def scalar(name, fallback):
        value = _array(options.get(name, fallback), name)
        if value.size != 1:
            raise BridgeError('GXTXT:Numeric:Solver', name + ' must be one finite scalar')
        return float(value.ravel()[0])
    legacy = scalar('max_iterations', 400)
    if legacy != int(legacy) or not 1 <= legacy <= 100000:
        raise BridgeError('GXTXT:Numeric:Solver', 'Legacy max_iterations must be an integer from 1 to 100000')
    limit = scalar('max_function_evaluations', 20*legacy)
    if limit != int(limit) or not 1 <= limit <= 2000000:
        raise BridgeError('GXTXT:Numeric:Solver', 'max_function_evaluations must be an integer from 1 to 2000000')
    tolerance = scalar('tolerance', 1e-8)
    settings = {}
    for name in ('function_tolerance', 'gradient_tolerance', 'parameter_tolerance'):
        value = scalar(name, tolerance)
        if value <= np.finfo(float).eps:
            raise BridgeError('GXTXT:Numeric:Solver', name + ' must exceed binary64 machine epsilon')
        settings[name] = value
    scales = _array(options.get('parameter_scales', np.ones(count)), 'parameter_scales').ravel(order='F')
    if scales.size != count or np.any(scales <= 0):
        raise BridgeError('GXTXT:Numeric:Solver', 'parameter_scales must contain one positive physical scale per parameter')
    return dict(requested_solver=requested, method=method, max_function_evaluations=int(limit),
                parameter_scales=scales, **settings)


def evaluate_model(host, model, predictors, options):
    """Evaluate an explicitly live declared callback, without fitting again."""
    import re
    if not isinstance(model, dict) or model.get('kind') != 'registered_callback' or not isinstance(model.get('callback'), CallbackRef):
        raise BridgeError('GXTXT:Numeric:Model', 'Evaluation needs a live registered callback model')
    if not isinstance(options, dict) or set(options)-{'jacobian'} or options.get('jacobian', False) not in (True,False,0,1):
        raise BridgeError('GXTXT:Numeric:Options', 'Prediction accepts only a boolean jacobian option')
    parameters = _array(model.get('parameters'), 'model parameters').ravel(order='F')
    x = _array(predictors, 'predictors')
    if x.ndim == 1:
        x = x.reshape(-1,1)
    ids = model.get('parameter_ids', [])
    if (not 1 <= parameters.size <= 128 or len(ids) != parameters.size or len(set(ids)) != len(ids)
            or any(not isinstance(v,str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}',v) for v in ids)
            or x.ndim != 2 or x.shape[1] != 1 or x.shape[0] < 1):
        raise BridgeError('GXTXT:Numeric:Model', 'Callback model parameter identities or N-by-1 predictor shape differ')
    source = model.get('source_sha256', '')
    binding = model.get('binding_sha256', '')
    if not re.fullmatch(r'[0-9a-f]{64}', source) or not re.fullmatch(r'[0-9a-f]{64}', binding):
        raise BridgeError('GXTXT:Numeric:Model', 'Callback evaluation requires its exact source and declaration SHA')
    domain = model.get('predictor_domain', 'finite_real')
    if domain not in ('finite_real','positive_real') or (domain == 'positive_real' and np.any(x <= 0)):
        raise BridgeError('GXTXT:Numeric:Model', 'Predictors are outside the declared callback domain')
    jacobian = bool(options.get('jacobian',False))
    if x.shape[0]*(parameters.size if jacobian else 1)*8 > 512*1024*1024:
        raise BridgeError('GXTXT:Numeric:Memory', 'Callback prediction output exceeds 512 MiB')
    lower = _array(model.get('lower_bounds',[-np.inf]*parameters.size), 'lower bounds', finite=False).ravel(order='F')
    upper = _array(model.get('upper_bounds',[np.inf]*parameters.size), 'upper bounds', finite=False).ravel(order='F')
    if lower.size != parameters.size or upper.size != parameters.size or np.any(np.isnan(lower)) or np.any(np.isnan(upper)) or np.any(lower > upper) or np.any(parameters < lower) or np.any(parameters > upper):
        raise BridgeError('GXTXT:Numeric:Model', 'Prediction parameters violate their declared bounds')
    fixed = _array(model.get('fixed_mask', np.zeros(parameters.size)), 'fixed_mask').ravel(order='F')
    if fixed.size != parameters.size or not np.all(np.isin(fixed, [0, 1])):
        raise BridgeError('GXTXT:Numeric:Model', 'Prediction fixed_mask must contain one boolean per parameter')
    fixed = fixed.astype(bool) | (lower == upper)
    with host.callback_argument(model['callback'], _wire(x)) as operand:
        def predict(p):
            return _vector_return(host,model['callback'],'model prediction',p,operand,length=x.shape[0],column=True)
        predicted = predict(parameters)
        result = {'predicted':_wire(predicted),'parameters':_wire(parameters),
                  'parameter_ids':list(ids),'predictor_ids':['predictor'],
                  'source_sha256':source,'binding_sha256':binding,'evaluation_only':True,
                  'prediction_bytes':int(predicted.nbytes),'jacobian_bytes':0,
                  'fixed_mask':_wire(fixed),'free_parameter_count':int(np.count_nonzero(~fixed))}
        if jacobian:
            # Differentiate only estimable coordinates. Fixed columns remain
            # zero, matching the full-order covariance from nonlinear_fit.
            matrix = np.zeros((x.shape[0], parameters.size))
            for i in np.flatnonzero(~fixed):
                step = np.cbrt(np.finfo(float).eps)*max(1.,abs(parameters[i]))
                plus = parameters.copy();minus = parameters.copy()
                plus[i] = min(upper[i],parameters[i]+step)
                minus[i] = max(lower[i],parameters[i]-step)
                if plus[i] == minus[i]:
                    raise BridgeError('GXTXT:Numeric:Precision', 'No representable finite-difference interval inside parameter bounds')
                a = predicted if plus[i] == parameters[i] else predict(plus)
                b = predicted if minus[i] == parameters[i] else predict(minus)
                matrix[:,i] = (a-b)/(plus[i]-minus[i])
            if not np.all(np.isfinite(matrix)):
                raise BridgeError('GXTXT:Numeric:Precision', 'Callback prediction Jacobian is nonfinite')
            result.update(jacobian=_wire(matrix),jacobian_bytes=int(matrix.nbytes),jacobian_method='bounded_central_finite_difference')
        return result


def invoke(host, family, action, a, b, c, options):
    if not isinstance(options, dict):
        raise BridgeError("GXTXT:Numeric:InvalidArguments", "callback options must be a struct")
    if family == "ode" and action == "solve":
        times = _array(b, "times").ravel(order="F")
        y0 = _array(c, "initial state").ravel(order="F")
        if times.size < 2 or np.any(np.diff(times) <= 0):
            raise BridgeError("GXTXT:Numeric:InvalidGrid", "times must be strictly increasing")
        reltol = float(options.get("reltol", 1e-6))
        abstol = float(options.get("abstol", 1e-9))
        max_step = float(options.get("max_step", np.inf))
        if reltol <= 0 or abstol <= 0 or max_step <= 0 or np.isnan(max_step):
            raise BridgeError("GXTXT:Numeric:InvalidTolerance", "ODE tolerances and maximum step must be positive")

        def rhs(t, y):
            if "cancel" in options and bool(_invoke(host, options["cancel"], float(t), y)):
                raise BridgeError("GXTXT:ScriptCallback:Cancelled", "ODE cancelled by script callback")
            if "progress" in options:
                _invoke(host, options["progress"], float((t-times[0])/(times[-1]-times[0])), float(t), y)
            return _vector_return(host, a, "ODE RHS", float(t), y, length=y0.size)

        solution = solve_ivp(rhs, (times[0], times[-1]), y0, method="RK45",
                             t_eval=times if times.size > 2 else None,
                             rtol=reltol, atol=abstol, max_step=max_step)
        if not solution.success:
            raise BridgeError("GXTXT:Numeric:SolverFailure", solution.message)
        state = solution.y.T
        return {"time": _wire(solution.t), "state_real": _wire(state),
                "state_imaginary": _wire(np.zeros_like(state)), "success": True,
                "cancelled": False, "output_count": int(solution.t.size), "method": "RK45"}

    if family == "calculus" and action in ("gradient", "jacobian", "hessian", "directional"):
        x = _array(b, "point").ravel(order="F")
        h = _array(options.get("step", np.finfo(float).eps**0.25 * (1 + np.abs(x))), "step")
        h = np.broadcast_to(h.ravel(order="F"), x.shape)
        if np.any(h <= 0):
            raise BridgeError("GXTXT:Numeric:InvalidTolerance", "finite-difference step must be positive")
        def f(point):
            return _vector_return(host, a, "function", point)
        f0 = f(x)
        jac = np.empty((f0.size, x.size))
        for j in range(x.size):
            step = np.zeros_like(x); step[j] = h[j]
            plus, minus = f(x+step), f(x-step)
            if plus.size != f0.size or minus.size != f0.size:
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", "callback return shape changed during differentiation")
            jac[:, j] = (plus-minus)/(2*h[j])
        if action == "jacobian":
            return _result(jac)
        if f0.size != 1:
            raise BridgeError("GXTXT:Numeric:DimensionMismatch", "scalar objective required")
        if action == "gradient":
            return _result(jac.ravel())
        if action == "directional":
            direction = _array(c, "direction").ravel(order="F")
            if direction.size != x.size or np.linalg.norm(direction) == 0:
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", "nonzero matching direction required")
            return _result(float(jac @ (direction/np.linalg.norm(direction))))
        hessian = np.empty((x.size, x.size))
        for i in range(x.size):
            ei = np.zeros_like(x); ei[i] = h[i]
            for j in range(x.size):
                ej = np.zeros_like(x); ej[j] = h[j]
                hessian[i,j] = (f(x+ei+ej)[0]-f(x+ei-ej)[0]-f(x-ei+ej)[0]+f(x-ei-ej)[0])/(4*h[i]*h[j])
        return _result((hessian+hessian.T)/2)

    if family == "constrained" and action == "solve":
        x0 = _array(b, "initial point").ravel(order="F")
        if not isinstance(c, dict):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "constraints must be a struct")
        n = x0.size
        lower = _array(c.get("lower", [-np.inf]*n), "lower bounds", finite=False).ravel(order="F")
        upper = _array(c.get("upper", [np.inf]*n), "upper bounds", finite=False).ravel(order="F")
        if lower.size != n or upper.size != n or np.any(lower > upper) or np.any(np.isnan(lower)) or np.any(np.isnan(upper)):
            raise BridgeError("GXTXT:Numeric:DimensionMismatch", "invalid bounds")
        def matrix(key):
            if key not in c: return np.empty((0,n))
            value = _array(c[key], key)
            if value.size == 0: return np.empty((0,n))
            if value.ndim != 2 or value.shape[1] != n:
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", f"{key} must have {n} columns")
            return value
        aeq, amat = matrix("Aeq"), matrix("A")
        beq = _array(c.get("beq", []), "beq").ravel(order="F")
        bound = _array(c.get("b", []), "b").ravel(order="F")
        if aeq.shape[0] != beq.size or amat.shape[0] != bound.size:
            raise BridgeError("GXTXT:Numeric:DimensionMismatch", "linear constraint rows and targets differ")
        nonlinear = c.get("nonlinear")
        def objective(x): return float(_vector_return(host, a, "objective", x, scalar=True)[0])
        constraints = []
        if aeq.shape[0]: constraints.append({"type":"eq", "fun":lambda x: aeq@x-beq})
        if amat.shape[0]: constraints.append({"type":"ineq", "fun":lambda x: bound-amat@x})
        if nonlinear is not None:
            eq0, ineq0 = _constraints(host, nonlinear, x0)
            if eq0.size: constraints.append({"type":"eq", "fun":lambda x: _constraints(host, nonlinear, x)[0]})
            if ineq0.size: constraints.append({"type":"ineq", "fun":lambda x: _constraints(host, nonlinear, x)[1]})
        gradient = options.get("gradient")
        jac = (lambda x: _vector_return(host, gradient, "gradient", x, length=n)) if gradient is not None else None
        result = minimize(objective, x0, method="SLSQP", jac=jac, bounds=list(zip(lower, upper)),
                          constraints=constraints, options={"maxiter":int(options.get("max_iterations",100)),
                          "ftol":float(options.get("tolerance",1e-6))})
        x = result.x
        eq = aeq@x-beq; ineq = bound-amat@x
        if nonlinear is not None:
            neq, nineq = _constraints(host, nonlinear, x)
            eq = np.r_[eq, neq]; ineq = np.r_[ineq, nineq]
        violation = max([0.0, *np.abs(eq), *(-ineq), *(lower-x), *(x-upper)])
        tolerance = float(options.get("constraint_tolerance",1e-6))
        def finite_jacobian(function):
            baseline = np.asarray(function(x), dtype=float).ravel()
            out = np.empty((baseline.size, n))
            for j in range(n):
                step = np.sqrt(np.finfo(float).eps)*(1+abs(x[j]))
                delta = np.zeros(n); delta[j] = step
                plus = np.asarray(function(x+delta), dtype=float).ravel()
                minus = np.asarray(function(x-delta), dtype=float).ravel()
                if plus.size != baseline.size or minus.size != baseline.size:
                    raise BridgeError("GXTXT:Numeric:DimensionMismatch", "constraint shape changed during diagnostics")
                out[:,j] = (plus-minus)/(2*step)
            return out
        grad = jac(x) if jac is not None else finite_jacobian(lambda v: [objective(v)]).ravel()
        eq_jac = aeq
        ineq_jac = -amat
        if nonlinear is not None:
            if neq.size: eq_jac = np.vstack((eq_jac, finite_jacobian(lambda v: _constraints(host, nonlinear, v)[0])))
            if nineq.size: ineq_jac = np.vstack((ineq_jac, finite_jacobian(lambda v: _constraints(host, nonlinear, v)[1])))
        active_ineq = np.flatnonzero(ineq <= tolerance)
        active_lower = np.flatnonzero(x-lower <= tolerance)
        active_upper = np.flatnonzero(upper-x <= tolerance)
        active_matrix = np.vstack((eq_jac, ineq_jac[active_ineq], np.eye(n)[active_lower], -np.eye(n)[active_upper]))
        multipliers = np.linalg.lstsq(active_matrix.T, grad, rcond=None)[0] if active_matrix.size else np.empty(0)
        stationarity = float(np.linalg.norm(grad-active_matrix.T@multipliers)) if active_matrix.size else float(np.linalg.norm(grad))
        dual = multipliers[eq.size:]
        slacks = np.r_[ineq[active_ineq], x[active_lower]-lower[active_lower], upper[active_upper]-x[active_upper]]
        complementarity = float(np.linalg.norm(dual*slacks))
        dual_violation = max([0.0, *(-dual)])
        return {"point": _wire(x), "objective": float(result.fun), "status": int(result.status),
                "converged": bool(result.success and violation <= tolerance and stationarity <= 10*tolerance and dual_violation <= 10*tolerance),
                "iterations": int(result.nit), "function_evaluations": int(result.nfev),
                "equality_residual": _wire(eq), "inequality_slack": _wire(ineq),
                "maximum_violation": float(violation), "backend_multipliers": _wire(np.empty(0)),
                "kkt_multipliers": _wire(multipliers), "kkt_stationarity_norm": stationarity,
                "kkt_complementarity_norm": complementarity, "kkt_dual_violation": float(dual_violation),
                "active_inequalities": _wire(active_ineq+1), "active_lower_bounds": _wire(active_lower+1),
                "active_upper_bounds": _wire(active_upper+1), "method": "SLSQP"}

    raise BridgeError("GXTXT:Numeric:UnknownOperation", f"unsupported callback foundation action {family}/{action}")


def solve_root(function, initial, tolerance, maximum):
    """Shared root owner for callback operations and retained-model inversion."""
    return (root_scalar(function, bracket=initial, method="brentq", xtol=tolerance, maxiter=maximum)
            if len(initial) == 2 else root_scalar(function, x0=initial[0],
                x1=initial[0]+0.01*(1+abs(initial[0])), method="secant", xtol=tolerance, maxiter=maximum))


def invoke_legacy(host, operation, args, *, deadline=None):
    options = args[-1] if args and isinstance(args[-1], dict) and operation != "dataset_nonlinear_fit" else {}
    if operation in ("root_find", "minimize_1d", "minimize"):
        if len(args) not in (2, 3):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", f"{operation} requires callback, input and optional options")
        callback, operand = args[:2]
        if len(args) == 3: options = args[2]
        if not isinstance(options, dict):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "options must be a struct")
        tolerance = float(options.get("tolerance",1e-8))
        maximum = int(options.get("max_iterations",400))
        if tolerance <= 0 or maximum < 1:
            raise BridgeError("GXTXT:Numeric:InvalidTolerance", "invalid solver limits")
        if operation == "root_find":
            initial = _array(operand, "root bracket/initial guess").ravel(order="F")
            if initial.size not in (1,2):
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", "root bracket needs one or two values")
            f = lambda x: float(_vector_return(host, callback, "root function", float(x), scalar=True)[0])
            result = solve_root(f, initial, tolerance, maximum)
            return {"root":float(result.root), "fval":f(result.root), "converged":bool(result.converged),
                    "exitflag":1 if result.converged else 0, "iterations":int(result.iterations),
                    "function_evaluations":int(result.function_calls), "solver":result.method}
        if operation == "minimize_1d":
            bounds = _array(operand, "bounds").ravel(order="F")
            if bounds.size != 2 or bounds[0] >= bounds[1]:
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", "minimize_1d requires increasing finite bounds")
            f = lambda x: float(_vector_return(host, callback, "objective", float(x), scalar=True)[0])
            result = minimize_scalar(f, bounds=bounds, method="bounded", options={"xatol":tolerance,"maxiter":maximum})
            return {"x":float(result.x), "fval":float(result.fun), "converged":bool(result.success),
                    "exitflag":1 if result.success else 0, "iterations":int(result.nit),
                    "function_evaluations":int(result.nfev), "solver":"bounded"}
        initial = _array(operand, "initial parameters").ravel(order="F")
        f = lambda x: float(_vector_return(host, callback, "objective", x, scalar=True)[0])
        result = minimize(f, initial, method="Nelder-Mead", options={"xatol":tolerance,
                          "fatol":float(options.get("function_tolerance",1e-8)), "maxiter":maximum})
        return {"x":_wire(result.x), "fval":float(result.fun), "converged":bool(result.success),
                "exitflag":1 if result.success else 0, "iterations":int(result.nit),
                "function_evaluations":int(result.nfev), "solver":"Nelder-Mead"}

    if operation not in ("nonlinear_fit", "dataset_nonlinear_fit"):
        raise BridgeError("GXTXT:Numeric:UnknownOperation", operation)
    if operation == "nonlinear_fit":
        if len(args) not in (4,5):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "nonlinear_fit requires X, Y, model callback and initial parameters")
        X, y, model, initial = args[:4]
        options = args[4] if len(args)==5 else {}
        provenance = {}
    else:
        if len(args) not in (5,6):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "dataset_nonlinear_fit requires Dataset, X/Y variable IDs, model callback and initial parameters")
        dataset_id, xid, yid, model, initial = args[:5]
        options = args[5] if len(args)==6 else {}
        if not isinstance(options, dict):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "options must be a struct")
        if "TABLE_STREAM_API_v3" not in host.bindings:
            raise BridgeError("GXTXT:ScriptBridge:UnknownAPI", "TABLE_STREAM_API_v3 is required for Dataset fitting")
        stream_api = host.modules["TABLE_STREAM_API_v3"]
        ids = [xid,yid]
        weight_id = options.get("weight_variable_id", "")
        if weight_id: ids.append(weight_id)
        token = stream_api.invoke(host,"open_dataset",[dataset_id,ids,4096])
        columns = {key:[] for key in ids}
        try:
            metadata = stream_api.invoke(host,"metadata",[token])
            while True:
                chunk = stream_api.invoke(host,"next",[token])
                for key in ids:
                    block = chunk["values"][key]
                    columns[key].extend(block.values if isinstance(block,NumericArray) else block)
                if str(chunk.get("eof","0")) in ("1","True","true"):
                    break
        finally:
            stream_api.invoke(host,"close",[token])
        X,y = columns[xid],columns[yid]
        if weight_id: options = {**options,"weights":columns[weight_id]}
        units = {row.get("variable_id"):row.get("unit", "") for row in metadata.get("variables",[])}
        provenance = {"dataset_id":dataset_id,"x_variable_id":xid,"y_variable_id":yid,
                      "weight_variable_id":weight_id,"x_unit":units.get(xid,""),"y_unit":units.get(yid,""),
                      "selection_id":options.get("selection",{}).get("id", "")}
    if not isinstance(options, dict):
        raise BridgeError("GXTXT:Numeric:InvalidArguments", "options must be a struct")
    x = _array(X,"X")
    if x.ndim == 1: x=x.reshape((-1,1))
    yy = _array(y,"Y").ravel(order="F")
    p0 = _array(initial,"initial parameters").ravel(order="F")
    selection = options.get("selection")
    if isinstance(selection,dict) and str(selection.get("enabled","1")).lower() not in ("0","false","no"):
        if operation == "dataset_nonlinear_fit" and selection.get("source_dataset_id",dataset_id) != dataset_id:
            raise BridgeError("GXTXT:Numeric:InvalidSelection", "Selection belongs to another Dataset")
        if selection.get("type") not in ("x_range", "rectangle"):
            raise BridgeError("GXTXT:Numeric:InvalidSelection", "Unsupported Selection type")
        if operation == "dataset_nonlinear_fit":
            if selection.get("x_variable_id") != xid or (selection["type"] == "rectangle" and selection.get("y_variable_id") != yid):
                raise BridgeError("GXTXT:Numeric:InvalidSelection", "Selection variable identity differs from fit variables")
        xmin, xmax = sorted((float(selection["x_min"]), float(selection["x_max"])))
        mask = np.isfinite(x[:,0]) & (x[:,0] >= xmin) & (x[:,0] <= xmax)
        if selection.get("type") == "rectangle":
            ymin, ymax = sorted((float(selection["y_min"]), float(selection["y_max"])))
            mask &= np.isfinite(yy) & (yy >= ymin) & (yy <= ymax)
        x=x[mask]; yy=yy[mask]
        for key in ("weights","sigma"):
            if key in options:
                options={**options,key:_array(options[key],key).ravel(order="F")[mask]}
    if x.ndim != 2 or x.shape[0] != yy.size or yy.size < 1:
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "fit needs one predictor row per nonempty observation")
    if not 1 <= p0.size <= 128 or yy.size*p0.size*8 > 512*1024*1024:
        raise BridgeError('GXTXT:Numeric:Memory', 'Callback fitting requires 1..128 parameters and a Jacobian within 512 MiB')
    weights = _array(options.get("weights",np.ones(yy.size)),"weights").ravel(order="F")
    if 'weights' in options and 'sigma' in options:
        raise BridgeError('GXTXT:Numeric:InvalidOperand', 'Choose precision weights or sigma, not both')
    semantics = "relative" if "weights" in options else "unweighted"
    if "sigma" in options:
        sigma = _array(options["sigma"],"sigma").ravel(order="F")
        if sigma.size != yy.size or np.any(sigma <= 0):
            raise BridgeError("GXTXT:Numeric:InvalidOperand", "sigma must be positive and match Y")
        weights=1/sigma**2; semantics="inverse_variance"
    if 'weight_semantics' in options:
        declared = options['weight_semantics']
        if (declared not in ('unweighted', 'relative', 'inverse_variance')
                or 'sigma' in options and declared != 'inverse_variance'
                or declared != 'unweighted' and not ('weights' in options or 'sigma' in options)
                or declared == 'unweighted' and np.any(weights != 1)):
            raise BridgeError('GXTXT:Numeric:InvalidOperand', 'Weight semantics contradict the supplied precision model')
        semantics = declared
    if weights.size != yy.size or np.any(weights <= 0):
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "weights must be positive and match Y")
    lower = _array(options.get("lower_bounds",[-np.inf]*p0.size),"lower bounds",finite=False).ravel(order="F")
    upper = _array(options.get("upper_bounds",[np.inf]*p0.size),"upper bounds",finite=False).ravel(order="F")
    if lower.size != p0.size or upper.size != p0.size or np.any(lower > upper) or np.any(p0 < lower) or np.any(p0 > upper):
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "invalid parameter bounds")
    if np.any(np.isnan(lower)) or np.any(np.isnan(upper)):
        raise BridgeError("GXTXT:Numeric:InvalidOperand", "parameter bounds cannot contain NaN")
    fixed = _array(options.get('fixed_mask', np.zeros(p0.size)), 'fixed_mask').ravel(order='F')
    if fixed.size != p0.size or not np.all(np.isin(fixed, [0, 1])):
        raise BridgeError('GXTXT:Numeric:DimensionMismatch', 'fixed_mask must contain one boolean per parameter')
    fixed = fixed.astype(bool) | (lower == upper)
    free = np.flatnonzero(~fixed)
    if yy.size < free.size:
        raise BridgeError('GXTXT:Numeric:DimensionMismatch', 'fit has fewer observations than free parameters')
    response_shape = options.get('response_shape', 'vector')
    if response_shape not in ('vector', 'column') or (response_shape == 'column' and (x.ndim != 2 or x.shape[1] != 1)):
        raise BridgeError('GXTXT:Numeric:DimensionMismatch', 'Declared functional model needs N-by-1 predictors and response')
    policy = _fit_policy(options, p0.size)
    scales = policy['parameter_scales'][free]
    # SciPy's active-bound tolerance uses its coordinate magnitudes. Passing
    # x_scale alone leaves tiny physical intervals classified as active. Solve
    # q=p/scale explicitly so bounds, stopping tests and rank share that space.
    with np.errstate(over='ignore', invalid='ignore', divide='ignore'):
        scaled_initial = p0[free]/scales
        scaled_lower = lower[free]/scales
        scaled_upper = upper[free]/scales
    if (not np.all(np.isfinite(scaled_initial)) or
            np.any(np.isfinite(lower[free]) & ~np.isfinite(scaled_lower)) or
            np.any(np.isfinite(upper[free]) & ~np.isfinite(scaled_upper)) or
            np.any(scaled_lower >= scaled_upper)):
        raise BridgeError('GXTXT:Numeric:Precision', 'Physical parameter scaling cannot represent initial values or bounds')
    import scipy
    import time
    started = time.perf_counter()
    callback_evaluations = 0
    with host.callback_argument(model, _wire(x)) as predictors:
        def predicted(p):
            nonlocal callback_evaluations
            if deadline is not None and time.perf_counter() >= deadline:
                raise BridgeError('GXTXT:Numeric:BootstrapBudget', 'Shared bootstrap refit time budget exhausted')
            callback_evaluations += 1
            value = _vector_return(host, model, "model", p, predictors, column=response_shape == "column")
            if deadline is not None and time.perf_counter() >= deadline:
                raise BridgeError('GXTXT:Numeric:BootstrapBudget', 'Shared bootstrap refit time budget exhausted after callback')
            if value.size != yy.size:
                raise BridgeError("GXTXT:Numeric:DimensionMismatch", "model output must match observations")
            return value
        def expand(q):
            p = p0.copy()
            p[free] = q*scales
            return p
        fitted = p0.copy()
        active = np.zeros(p0.size, dtype=bool)
        jacobian = np.zeros((yy.size, p0.size))
        if free.size:
            result = least_squares(lambda q: np.sqrt(weights)*(predicted(expand(q))-yy),scaled_initial,bounds=(scaled_lower,scaled_upper),
                                   method=policy['method'], x_scale=1.0,
                                   max_nfev=policy['max_function_evaluations'],
                                   xtol=policy['parameter_tolerance'],ftol=policy['function_tolerance'],
                                   gtol=policy['gradient_tolerance'])
            fitted = expand(result.x)
            active[free] = result.active_mask != 0
            jacobian[:,free] = result.jac/scales
            solver = 'least_squares'
            converged, exitflag, evaluations, message = bool(result.success), int(result.status), int(result.nfev), str(result.message)
            jacobian_evaluations = int(result.njev) if result.njev is not None else -1
        else:
            solver, converged, exitflag, evaluations = 'fixed_evaluation', True, 1, 1
            message = 'All parameters fixed; optimizer not invoked'
            jacobian_evaluations = 0
        pred=predicted(fitted)
    elapsed = time.perf_counter()-started
    residual=yy-pred; wr=np.sqrt(weights)*residual
    sse=float(wr@wr)
    rank=0;condition=float('nan');basis=np.zeros((0,0))
    if free.size:
        # Diagnose a column-normalized design, then map covariance back to the
        # original physical parameters. Raw J conditioning depends on units.
        columns = jacobian[:,free]
        column_scales = np.max(np.abs(columns), axis=0)
        column_scales[column_scales == 0] = 1
        norms = np.linalg.norm(columns/column_scales, axis=0)
        column_scales *= np.where(norms > 0, norms, 1)
        if not np.all(np.isfinite(column_scales)):
            raise BridgeError('GXTXT:Numeric:Precision', 'Callback Jacobian column scales exceed finite binary64 range')
        _, singular, vt = np.linalg.svd(columns/column_scales, full_matrices=False)
        threshold = np.finfo(float).eps*max(yy.size,free.size)*singular[0]
        identified = singular > threshold
        rank=int(np.count_nonzero(identified))
        condition=float(singular[0]/singular[-1]) if rank==free.size else float('inf')
        basis = (vt[identified].T / singular[identified]) / column_scales[:,None]
    dof=yy.size-rank
    infer=dof>0 and rank==free.size and not np.any(active)
    covariance_scale=(1.0 if semantics=='inverse_variance' else sse/dof) if infer else float('nan')
    # Use the actual weighted Jacobian singular values. Forming J.T@J first
    # squares its condition number and can lose identifiable parameter modes.
    covariance=np.full((p0.size,p0.size),np.nan)
    if infer:
        covariance=np.zeros((p0.size,p0.size))
        covariance[np.ix_(free,free)]=(basis@basis.T)*covariance_scale
    standard=np.sqrt(np.maximum(np.diag(covariance),0))
    total=float(np.sum(weights*(yy-np.average(yy,weights=weights))**2))
    r2=1-sse/total if total>0 else (1.0 if sse==0 else float("nan"))
    out={"parameters":_wire(fitted),"predicted":_wire(pred),"residuals":_wire(residual),
         'numeric_api':'NUMERIC_API_v1','operation':'nonlinear_fit','n':int(yy.size),'p':int(p0.size),
         'free_parameter_count':int(free.size),'fixed_mask':_wire(fixed),'active_bounds':_wire(active),
         "weighted_residuals":_wire(wr),"objective":sse,"sse":sse,"rss":sse,
         'response_rmse':float(np.sqrt((residual@residual)/yy.size)),
         'mae':float(np.mean(np.abs(residual))),'max_abs_error':float(np.max(np.abs(residual))),
         "rmse":float(np.sqrt(sse/dof)) if dof>0 else float("nan"),
         "residual_rmse":float(np.sqrt((residual@residual)/dof)) if dof>0 else float("nan"),
         "response_variance":total/float(np.sum(weights)),"r_squared":r2,"adjusted_r_squared":1-(1-r2)*(yy.size-1)/dof if dof>0 else float("nan"),
         "dof":dof,"rank":rank,"condition_number":condition,
         "covariance":_wire(covariance),"standard_errors":_wire(standard),"jacobian":_wire(jacobian),
         "weighted":semantics!="unweighted","weight_semantics":semantics,
         "covariance_scale":covariance_scale,
         "reduced_chi_squared":sse/dof if dof>0 and semantics=='inverse_variance' else float("nan"),
         "solver":solver, "converged":converged,"exitflag":exitflag,
         "iterations":-1 if free.size else 0,"function_evaluations":evaluations,"solver_message":message}
    out['solver_receipt'] = {
        'schema':'gxtxt.callback_solver_receipt.v1', 'method':solver,
        'requested_solver':policy['requested_solver'], 'strategy':policy['method'],
        'backend':'scipy.optimize.least_squares', 'backend_version':scipy.__version__,
        'derivative_method':'forward_finite_difference_free_parameters',
        'iteration_convention':'not_reported_by_scipy' if free.size else 'optimizer_not_invoked',
        'iterations':out['iterations'], 'function_evaluations':evaluations,
        'jacobian_evaluations':jacobian_evaluations, 'callback_evaluations':callback_evaluations,
        'exitflag':exitflag, 'converged':converged, 'solver_message':message,
        'solver_seconds':elapsed, 'solver_objective':sse, 'loss':'linear',
        'max_function_evaluations':policy['max_function_evaluations'],
        'function_tolerance':policy['function_tolerance'],
        'gradient_tolerance':policy['gradient_tolerance'],
        'parameter_tolerance':policy['parameter_tolerance'],
        'parameter_scales':_wire(policy['parameter_scales']), 'initial_parameters':_wire(p0),
        'lower_bounds':_wire(lower), 'upper_bounds':_wire(upper), 'fixed_mask':_wire(fixed),
        'condition_convention':'unit_norm_free_jacobian_columns',
        'scale_convention':'physical_parameter_equals_scaled_parameter_times_scale',
    }
    out.update(provenance)
    return out
