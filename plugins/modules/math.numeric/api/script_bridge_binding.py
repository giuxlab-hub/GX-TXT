"""Octave Script Bridge registration owned by math.numeric / NUMERIC_API_v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray
from gxtxt_script_bridge_server import CallbackRef
import importlib.util
from pathlib import Path

_callback_module = None


def _callback_backend():
    global _callback_module
    if _callback_module is None:
        try:
            spec = importlib.util.spec_from_file_location("gxtxt_numeric_callback_foundation", Path(__file__).with_name("callback_foundation.py"))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            _callback_module = module
        except ImportError as exc:
            raise BridgeError("GXTXT:Numeric:BackendUnavailable", f"callback solver requires NumPy and SciPy: {exc}") from exc
    return _callback_module

REGISTRATION = {
    "api_id": "NUMERIC_API_v1", "api_version": 1,
    "provider_kind": "module", "provider_id": "math.numeric",
    "documentation_ref": "plugins/modules/math.numeric/NUMERIC_API_v1.md",
    "operations": {
        "polar_coordinates": {"name": "polar_coordinates", "summary": "Convert physical XY with an explicit polar frame and angular branch", "argument_convention": "X, Y, optional frame options", "result_convention": "theta, radius, undefined-angle mask and frame"},
        "cartesian_coordinates": {"name": "cartesian_coordinates", "summary": "Convert declared angles and nonnegative radii to physical XY", "argument_convention": "theta, radius, optional frame options", "result_convention": "physical X/Y and frame"},
        "curve_model_fit": {"name": "curve_model_fit", "summary": "Fit reconstructible functional, arc, Bezier, ordered parametric polynomial or periodic spline geometry", "argument_convention": "model, X, Y, optional options", "result_convention": "model state struct"},
        "curve_model_evaluate": {"name": "curve_model_evaluate", "summary": "Evaluate a persisted curve model", "argument_convention": "model state, query vector", "result_convention": "X/Y points struct"},
        "curve_model_project": {"name": "curve_model_project", "summary": "Project points to the nearest location on an arc or Bezier curve", "argument_convention": "model state, X, Y", "result_convention": "projected points, parameters and distances"},
        "curve_model_residual": {"name": "curve_model_residual", "summary": "Compute signed geometric projection distance and XY dispersion metrics", "argument_convention": "model state, X, Y", "result_convention": "projected points, signed distances and geometric metrics"},
        "array_unary": {"name": "array_unary", "summary": "Apply a public unary numerical operation", "argument_convention": "operation name, operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_binary": {"name": "array_binary", "summary": "Apply a public binary numerical operation", "argument_convention": "operation name, left operand struct, right operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_compare": {"name": "array_compare", "summary": "Build a numerical comparison mask", "argument_convention": "operation name, left operand struct, right operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_mask": {"name": "array_mask", "summary": "Apply a logical mask operation", "argument_convention": "operation name, first operand struct, optional second operand struct", "result_convention": "numerical result struct"},
        "array_select": {"name": "array_select", "summary": "Select values by mask", "argument_convention": "values operand struct, mask operand struct", "result_convention": "numerical result struct"},
        "array_where": {"name": "array_where", "summary": "Select true or false values by mask", "argument_convention": "mask, true values, false values as operand structs", "result_convention": "numerical result struct"},
        "array_reduce": {"name": "array_reduce", "summary": "Reduce a numeric array", "argument_convention": "operation name, operand struct, optional options struct", "result_convention": "numerical result struct"},
        "statistics_dataset": {"name": "statistics_dataset", "summary": "Compute statistics on a stable Dataset variable", "argument_convention": "dataset_id, variable_id, optional options struct", "result_convention": "statistics struct"},
        "linear_matrix": {"name": "linear_matrix", "summary": "Inspect, solve, or decompose a real or complex matrix", "argument_convention": "action, matrix struct, optional other matrix struct, optional options struct", "result_convention": "split-complex result struct"},
        "foundation": {"name": "foundation", "summary": "Vector, tensor, grid, geometry, sparse, statistics, calculus, ODE, constrained optimization and special-function primitives", "argument_convention": "family, action, three typed operands or execution-scoped callback handles, optional options struct", "result_convention": "structured mathematical result"},
        "root_find": {"name":"root_find","summary":"Find a scalar root with a registered callback","argument_convention":"callback, bracket or initial value, optional options","result_convention":"root and convergence diagnostics"},
        "minimize_1d": {"name":"minimize_1d","summary":"Minimize a scalar function on a bounded interval","argument_convention":"callback, bounds, optional options","result_convention":"minimum and convergence diagnostics"},
        "minimize": {"name":"minimize","summary":"Minimize a multivariate scalar function","argument_convention":"callback, initial point, optional options","result_convention":"minimum and convergence diagnostics"},
        "nonlinear_fit": {"name":"nonlinear_fit","summary":"Fit a registered model to observations","argument_convention":"X, Y, model callback, initial parameters, optional options","result_convention":"parameters, residuals and fit diagnostics"},
        "dataset_nonlinear_fit": {"name":"dataset_nonlinear_fit","summary":"Fit a registered model to stable Dataset variables","argument_convention":"Dataset ID, X/Y variable IDs, model callback, initial parameters, optional options","result_convention":"fit diagnostics and Dataset provenance"},
    },
}
_ARGUMENTS = {
    "polar_coordinates": [("X", "numeric vector"), ("Y", "numeric vector"), ("options", "struct")],
    "cartesian_coordinates": [("theta", "numeric vector"), ("radius", "numeric vector"), ("options", "struct")],
    "curve_model_fit": [("model", "model name"), ("X", "numeric vector"), ("Y", "numeric vector"), ("options", "struct")],
    "curve_model_evaluate": [("model", "model state struct"), ("query", "numeric vector")],
    "curve_model_project": [("model", "model state struct"), ("X", "numeric vector"), ("Y", "numeric vector")],
    "curve_model_residual": [("model", "model state struct"), ("X", "numeric vector"), ("Y", "numeric vector")],
    "array_unary": [("operation", "public numerical operation"), ("operand", "typed operand struct"), ("options", "struct")],
    "array_binary": [("operation", "public numerical operation"), ("left", "typed operand struct"), ("right", "typed operand struct"), ("options", "struct")],
    "array_compare": [("operation", "public comparison operation"), ("left", "typed operand struct"), ("right", "typed operand struct"), ("options", "struct")],
    "array_mask": [("operation", "public mask operation"), ("first", "typed operand struct"), ("second", "typed operand struct")],
    "array_select": [("values", "typed operand struct"), ("mask", "typed operand struct")],
    "array_where": [("mask", "typed operand struct"), ("true_values", "typed operand struct"), ("false_values", "typed operand struct")],
    "array_reduce": [("operation", "public reduction operation"), ("operand", "typed operand struct"), ("options", "struct")],
    "statistics_dataset": [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("options", "struct")],
    "linear_matrix": [("action", "public linear algebra action"), ("matrix", "matrix with real and optional imaginary parts"), ("other", "optional second matrix"), ("options", "struct")],
    "foundation": [("family", "mathematical family"), ("action", "public mathematical action"), ("a", "typed operand"), ("b", "typed operand"), ("c", "typed operand"), ("options", "typed options struct")],
    "root_find": [("callback","registered callback"),("initial","bracket or initial value"),("options","struct")],
    "minimize_1d": [("callback","registered callback"),("bounds","interval"),("options","struct")],
    "minimize": [("callback","registered callback"),("initial","initial point"),("options","struct")],
    "nonlinear_fit": [("X","predictors"),("Y","observations"),("model","registered callback"),("initial","initial parameters"),("options","struct")],
    "dataset_nonlinear_fit": [("dataset_id","Dataset ID"),("x_variable_id","stable X Variable ID"),("y_variable_id","stable Y Variable ID"),("model","registered callback"),("initial","initial parameters"),("options","struct")],
}
for _name, _fields in _ARGUMENTS.items():
    _operation = REGISTRATION["operations"][_name]
    _operation["arguments"] = [{"name": name, "kind": kind, "required": name not in ("options", "second")}
                               for name, kind in _fields]
    _operation["result_contract"] = _operation["result_convention"]
    _operation["unit_behavior"] = "Units follow NUMERIC_API_v1 operation contract"

COMMANDS = {
    "array_unary": "arrayUnary", "array_binary": "arrayBinary",
    "array_compare": "arrayCompare", "array_mask": "arrayMask",
    "array_select": "arraySelect", "array_where": "arrayWhere",
    "array_reduce": "arrayReduce", "statistics_dataset": "statisticsDataset",
    "linear_matrix": "linearMatrix",
    "foundation": "foundation",
}


def _activate(host):
    host.call("::GX::modulePublicApiActivate", "math.numeric", "NUMERIC_API_v1")


def _adapt(host, raw, result_types, prefix=""):
    fields = host.as_dict(raw)
    out = {}
    for key, value in fields.items():
        path = prefix + key
        kind = result_types.get(path)
        if kind == "number":
            out[key] = float(value)
        elif kind == "boolean":
            out[key] = str(value).lower() in ("1", "true", "yes", "on")
        elif kind == "vector":
            out[key] = NumericArray(host.as_list(value))
        elif kind == "matrix":
            rows = [host.as_list(row) for row in host.as_list(value)]
            count = len(rows)
            width = len(rows[0]) if rows else 0
            if any(len(row) != width for row in rows):
                raise BridgeError("GXTXT:ScriptBridge:Transport", "numerical matrix has unequal row lengths")
            out[key] = NumericArray([rows[r][c] for c in range(width) for r in range(count)], [count, width])
        elif kind == "tensor":
            tensor = host.as_dict(value)
            shape = [int(x) for x in host.as_list(tensor["shape"])]
            values = [float(x) for x in host.as_list(tensor["values"])]
            out[key] = NumericArray(values, shape)
        elif kind == "string":
            out[key] = str(value)
        elif kind == "struct":
            out[key] = _adapt(host, value, result_types, path + ".")
        elif kind == "cell":
            items = []
            for i, item in enumerate(host.as_list(value), 1):
                child = f"{path}.item{i}"
                types = {"value" + name[len(child):]: item_kind for name, item_kind in result_types.items()
                         if name == child or name.startswith(child + ".")}
                items.append(_adapt(host, {"value": item}, types)["value"])
            out[key] = items
        else:
            raise BridgeError("GXTXT:ScriptBridge:Transport", f"numerical result field {key} has no supported type")
    return out


def invoke(host, operation, args):
    _activate(host)
    if operation in ("polar_coordinates", "cartesian_coordinates"):
        if len(args) not in (2, 3) or (len(args) == 3 and not isinstance(args[2], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires two numeric vectors and optional frame options")
        raw = host.call("::GX::NumericAPIv1::callOperation", operation, [_curve_node(v) for v in args[:2]], _curve_node(args[2] if len(args) == 3 else {}))
        return _adapt(host, raw, host.as_dict(host.call("::GX::NumericAPIv1::resultTypes")))
    if operation in ("curve_model_fit", "curve_model_evaluate", "curve_model_project", "curve_model_residual"):
        expected = {"curve_model_fit": (3, 4), "curve_model_evaluate": (2, 2), "curve_model_project": (3, 3), "curve_model_residual": (3, 3)}[operation]
        if not expected[0] <= len(args) <= expected[1]:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} argument count")
        operands = args[:3] if operation == "curve_model_fit" else args
        options = args[3] if operation == "curve_model_fit" and len(args) == 4 else {}
        if not isinstance(options, dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "curve model options must be a struct")
        raw = host.call("::GX::NumericAPIv1::callOperation", operation, [_curve_node(v) for v in operands], _curve_node(options))
        return _adapt(host, raw, host.as_dict(host.call("::GX::NumericAPIv1::resultTypes")))
    if operation in ("root_find","minimize_1d","minimize","nonlinear_fit","dataset_nonlinear_fit"):
        return _callback_backend().invoke_legacy(host, operation, args)
    if operation == "statistics_dataset":
        if len(args) not in (2, 3):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "statistics_dataset requires dataset_id, variable_id, optional options")
        args = [host.session, args[0], args[1]] + ([args[2]] if len(args) == 3 else [])
    elif operation in ("array_unary", "array_reduce") and len(args) not in (2, 3):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires name, operand, optional options")
    elif operation in ("array_binary", "array_compare") and len(args) not in (3, 4):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires name, two operands, optional options")
    elif operation == "array_mask" and len(args) not in (2, 3):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_mask requires name and operand(s)")
    elif operation == "array_select" and len(args) != 2:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_select requires values and mask")
    elif operation == "array_where" and len(args) != 3:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_where requires mask and two alternatives")
    elif operation == "linear_matrix" and len(args) not in (2, 3, 4):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "linear_matrix requires action, matrix, optional other and options")
    elif operation == "foundation" and len(args) not in (5, 6):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "foundation requires family, action, three typed operands and optional options")
    callback_action = operation == "foundation" and (args[0] in ("ode", "constrained") or
        (args[0] == "calculus" and args[1] in ("gradient", "jacobian", "hessian", "directional")))
    if operation == "foundation" and len(args) == 5:
        args.append({} if callback_action else {"kind": "struct", "fields": {}})
    if callback_action:
        return _callback_backend().invoke(host, *args)
    if operation in ("array_unary", "array_binary", "array_compare", "array_mask", "array_select", "array_where", "array_reduce"):
        try:
            from gxtxt_scientific_binary_v1 import call
            import numpy as np
        except ImportError:
            pass
        else:
            def operand(item):
                if not isinstance(item, dict) or item.get("kind") not in ("scalar", "vector", "matrix") or "value" not in item:
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array operand requires scalar/vector/matrix kind and value")
                value = item["value"]
                if isinstance(value, NumericArray):
                    array = np.asarray(value.values).reshape(value.shape, order="F")
                else:
                    array = np.asarray(value, dtype=float)
                if item["kind"] == "scalar":
                    if array.size != 1: raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "scalar operand requires one value")
                    return float(array.reshape(-1)[0])
                if item["kind"] == "vector": return array.reshape(-1, 1, order="F")
                if array.ndim != 2 or not all(array.shape): raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "matrix requires nonempty two-dimensional values")
                return array
            named = operation not in ("array_select", "array_where")
            count = {"array_unary": 1, "array_binary": 2, "array_compare": 2, "array_reduce": 1,
                     "array_select": 2, "array_where": 3, "array_mask": len(args)-1}[operation]
            start = 1 if named else 0
            native_args = [operation] + ([args[0]] if named else []) + [operand(x) for x in args[start:start+count]]
            if operation in ("array_unary", "array_binary", "array_compare", "array_reduce"):
                options = args[start+count] if len(args)>start+count else {}
                if not isinstance(options, dict): raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "options must be a struct")
                native_args.append(options)
            return call(host, "gxtxt_numeric_v1", native_args)
    raw = host.call("::GX::NumericAPIv1::" + COMMANDS[operation], *args)
    result_types = host.as_dict(host.call("::GX::NumericAPIv1::resultTypes"))
    return _adapt(host, raw, result_types)


def _curve_node(value):
    if isinstance(value, str):
        return {"kind": "text", "value": value}
    if isinstance(value, NumericArray):
        return {"kind": "array", "shape": value.shape, "real": value.values} if len(value.values) else {"kind": "empty"}
    if isinstance(value, (int, float, bool)):
        return {"kind": "array", "shape": [1, 1], "real": [float(value)]}
    if isinstance(value, dict):
        return {"kind": "struct", "fields": {key: _curve_node(v) for key, v in value.items()}}
    if isinstance(value, (list, tuple)) and all(isinstance(v, (int, float)) for v in value):
        return {"kind": "array", "shape": [len(value), 1], "real": list(value)} if value else {"kind": "empty"}
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "curve models require text, numeric arrays and scalar structs")
