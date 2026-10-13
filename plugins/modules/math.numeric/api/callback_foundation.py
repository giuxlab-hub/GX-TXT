"""Execution-scoped callback operations for the public NUMERIC_API foundation."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import numpy as np
from scipy.integrate import solve_ivp
from scipy.optimize import minimize, root_scalar, minimize_scalar, least_squares

from gxtxt_script_bridge_server import BridgeError, CallbackRef, NumericArray


def _array(value, name, *, scalar=False, finite=True):
    if isinstance(value, NumericArray):
        result = np.asarray(value.values, dtype=float).reshape(value.shape, order="F")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        result = np.asarray(value, dtype=float)
    elif isinstance(value, (list, tuple, np.ndarray)):
        try:
            result = np.asarray(value, dtype=float)
        except (TypeError, ValueError) as exc:
            raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be numeric") from exc
    else:
        raise BridgeError("GXTXT:Numeric:InvalidOperand", f"{name} must be numeric")
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


def _vector_return(host, ref, name, *args, length=None, scalar=False):
    result = _array(_invoke(host, ref, *args), name)
    if scalar and result.size != 1:
        raise BridgeError("GXTXT:Numeric:InvalidObjective", f"{name} must return a finite real scalar")
    if length is not None and result.size != length:
        raise BridgeError("GXTXT:Numeric:InvalidRHS", f"{name} returned {result.size} values; expected {length}")
    return result.ravel(order="F")


def _constraints(host, ref, x):
    raw = _invoke(host, ref, x)
    if not isinstance(raw, dict) or "equality" not in raw or "inequality" not in raw:
        raise BridgeError("GXTXT:Numeric:InvalidConstraint", "nonlinear callback must return equality and inequality fields")
    eq = _array(raw["equality"], "nonlinear equality").ravel(order="F")
    ineq = _array(raw["inequality"], "nonlinear inequality").ravel(order="F")
    return eq, ineq


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


def invoke_legacy(host, operation, args):
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
            result = (root_scalar(f, bracket=initial, method="brentq", xtol=tolerance, maxiter=maximum)
                      if initial.size == 2 else root_scalar(f, x0=initial[0], x1=initial[0]+0.01*(1+abs(initial[0])), method="secant", xtol=tolerance, maxiter=maximum))
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
                      "selection_id":options.get("selection_id","")}
    if not isinstance(options, dict):
        raise BridgeError("GXTXT:Numeric:InvalidArguments", "options must be a struct")
    x = _array(X,"X")
    if x.ndim == 1: x=x.reshape((-1,1))
    yy = _array(y,"Y").ravel(order="F")
    p0 = _array(initial,"initial parameters").ravel(order="F")
    selection = options.get("selection")
    if operation == "dataset_nonlinear_fit" and options.get("selection_id"):
        provider = host.modules.get("DATASET_SELECTION_API_v1")
        if provider is None:
            raise BridgeError("GXTXT:ScriptBridge:UnknownAPI", "DATASET_SELECTION_API_v1 is required for selected Dataset fitting")
        selection = provider.invoke_api(host,"DATASET_SELECTION_API_v1","describe",[options["selection_id"]])
    if isinstance(selection,dict) and str(selection.get("enabled","1")).lower() not in ("0","false","no"):
        if operation == "dataset_nonlinear_fit" and selection.get("source_dataset_id",dataset_id) != dataset_id:
            raise BridgeError("GXTXT:Numeric:InvalidSelection", "Selection belongs to another Dataset")
        mask = (x[:,0] >= float(selection["x_min"])) & (x[:,0] <= float(selection["x_max"]))
        if selection.get("type") == "rectangle":
            mask &= (yy >= float(selection["y_min"])) & (yy <= float(selection["y_max"]))
        x=x[mask]; yy=yy[mask]
        for key in ("weights","sigma"):
            if key in options:
                options={**options,key:_array(options[key],key).ravel(order="F")[mask]}
    if x.shape[0] != yy.size or yy.size < p0.size:
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "fit needs one X row per Y and at least as many observations as parameters")
    weights = _array(options.get("weights",np.ones(yy.size)),"weights").ravel(order="F")
    semantics = "relative" if "weights" in options else "unweighted"
    if "sigma" in options:
        sigma = _array(options["sigma"],"sigma").ravel(order="F")
        if sigma.size != yy.size or np.any(sigma <= 0):
            raise BridgeError("GXTXT:Numeric:InvalidOperand", "sigma must be positive and match Y")
        weights=1/sigma**2; semantics="inverse_variance"
    if weights.size != yy.size or np.any(weights <= 0):
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "weights must be positive and match Y")
    lower = _array(options.get("lower_bounds",[-np.inf]*p0.size),"lower bounds",finite=False).ravel(order="F")
    upper = _array(options.get("upper_bounds",[np.inf]*p0.size),"upper bounds",finite=False).ravel(order="F")
    if lower.size != p0.size or upper.size != p0.size or np.any(lower > upper) or np.any(p0 < lower) or np.any(p0 > upper):
        raise BridgeError("GXTXT:Numeric:DimensionMismatch", "invalid parameter bounds")
    def predicted(p):
        value = _vector_return(host, model, "model", p, x)
        if value.size != yy.size:
            raise BridgeError("GXTXT:Numeric:DimensionMismatch", "model output must match observations")
        return value
    result = least_squares(lambda p: np.sqrt(weights)*(predicted(p)-yy),p0,bounds=(lower,upper),
                           max_nfev=int(options.get("max_iterations",400))*20,
                           xtol=float(options.get("tolerance",1e-8)),ftol=float(options.get("tolerance",1e-8)),
                           gtol=float(options.get("tolerance",1e-8)))
    pred=predicted(result.x); residual=yy-pred; wr=np.sqrt(weights)*residual
    sse=float(wr@wr); rank=int(np.linalg.matrix_rank(result.jac)); dof=yy.size-rank
    covariance_scale=sse/dof if dof>0 and rank==p0.size else float("nan")
    if semantics=="inverse_variance": covariance_scale=1.0
    covariance=np.linalg.pinv(result.jac.T@result.jac)*covariance_scale if np.isfinite(covariance_scale) else np.full((p0.size,p0.size),np.nan)
    standard=np.sqrt(np.maximum(np.diag(covariance),0))
    total=float(np.sum(weights*(yy-np.average(yy,weights=weights))**2))
    r2=1-sse/total if total>0 else (1.0 if sse==0 else float("nan"))
    out={"parameters":_wire(result.x),"predicted":_wire(pred),"residuals":_wire(residual),
         "weighted_residuals":_wire(wr),"objective":sse,"sse":sse,"rss":sse,
         "rmse":float(np.sqrt(sse/dof)) if dof>0 else float("nan"),
         "residual_rmse":float(np.sqrt((residual@residual)/dof)) if dof>0 else float("nan"),
         "r_squared":r2,"adjusted_r_squared":1-(1-r2)*(yy.size-1)/dof if dof>0 else float("nan"),
         "dof":dof,"rank":rank,"condition_number":float(np.linalg.cond(result.jac)),
         "covariance":_wire(covariance),"standard_errors":_wire(standard),"jacobian":_wire(result.jac),
         "weighted":semantics!="unweighted","weight_semantics":semantics,
         "covariance_scale":covariance_scale,
         "reduced_chi_squared":sse/dof if dof>0 else float("nan"),
         "solver":"least_squares", "converged":bool(result.success),"exitflag":int(result.status),
         "iterations":int(result.nfev),"function_evaluations":int(result.nfev),"solver_message":str(result.message)}
    out.update(provenance)
    return out
