"""Provider-owned Script Bridge binding for SIGNAL_API_v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from gxtxt_script_bridge_server import BridgeError, NumericArray

_OPERATIONS = {}
for line in (Path(__file__).with_name("operations_v1.tsv")).read_text(encoding="utf-8").splitlines():
    if line and not line.startswith("#"):
        name, summary = line.split("|", 1)
        _OPERATIONS[name] = {"name": name, "summary": summary, "argument_convention": "a, b, c typed operands; optional typed options struct", "result_convention": "typed numeric result struct", "arguments": [{"name": key, "kind": "typed operand", "required": key != "options"} for key in ("a","b","c","options")], "result_contract": "numeric and diagnostic fields", "unit_behavior": "Operation-specific; see provider documentation"}
_FAMILIES = {}
for line in (Path(__file__).with_name("family_contracts_v1.tsv")).read_text(encoding="utf-8").splitlines():
    if line and not line.startswith("#"):
        fields = line.split("|")
        if len(fields) != 7:
            raise RuntimeError("invalid scientific family contract")
        family, operands, input_shapes, result_shapes, units, complex_behavior, errors = fields
        _FAMILIES[family] = {"operands": operands, "input_shapes": input_shapes,
                             "result_shapes": result_shapes, "units": units,
                             "complex_behavior": complex_behavior, "errors": errors.split(";")}
for name, operation in _OPERATIONS.items():
    operation.update(_FAMILIES[name.split(".", 1)[0]])

_OPERATIONS["statistical_contract"] = {
    "operation_kind": "metadata",
    "name": "statistical_contract", "summary": "Resolve a Signal operation's registered CORE statistical contract",
    "argument_convention": "signal_operation string", "result_convention": "bounded public contract dictionary",
    "arguments": [{"name": "signal_operation", "kind": "string", "required": True}],
    "result_contract": "Numeric operation and CORE model identity; no calculation or interpretation copy",
    "unit_behavior": "Actual units and availability are supplied by the public CORE API"}

REGISTRATION = {"api_id": "SIGNAL_API_v1", "api_version": 1, "provider_kind": "module", "provider_id": "math.signal", "documentation_ref": "plugins/modules/math.signal/SIGNAL_API_v1.md", "operations": _OPERATIONS}

def _adapt(host, raw, types):
    out = {}
    for key, value in host.as_dict(raw).items():
        kind = types.get(key)
        if kind == "number":
            out[key] = float(value)
        elif kind == "boolean":
            out[key] = str(value).lower() in ("1", "true", "yes", "on")
        elif kind == "string":
            out[key] = str(value)
        elif kind == "vector":
            values = [float(x) for x in host.as_list(value)]
            out[key] = NumericArray(values, [len(values), 1])
        elif kind == "matrix":
            rows = [host.as_list(row) for row in host.as_list(value)]
            nr = len(rows); nc = len(rows[0]) if rows else 0
            if any(len(row) != nc for row in rows):
                raise BridgeError("GXTXT:ScriptBridge:Transport", "matrix rows differ")
            out[key] = NumericArray([float(rows[r][c]) for c in range(nc) for r in range(nr)], [nr, nc])
        elif kind == "tensor":
            tensor = host.as_dict(value)
            shape = [int(x) for x in host.as_list(tensor["shape"])]
            values = [float(x) for x in host.as_list(tensor["values"])]
            out[key] = NumericArray(values, shape)
        else:
            raise BridgeError("GXTXT:ScriptBridge:Transport", f"unsupported result field {key} type {kind}")
    return out

def invoke(host, operation, args):
    if operation not in _OPERATIONS:
        raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", operation)
    if operation == "statistical_contract":
        if len(args) != 1 or not isinstance(args[0], str):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "statistical_contract requires one Signal operation string")
        host.call("::GX::modulePublicApiActivate", "math.signal", "SIGNAL_API_v1")
        result = {str(k): str(v) for k, v in host.as_dict(host.call("::GX::SignalAPIv1::statisticalContract", args[0])).items()}
        result["api_version"] = int(result["api_version"])
        return result
    if len(args) not in (3,4):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "scientific operation requires a, b, c and optional options")
    host.call("::GX::modulePublicApiActivate", "math.signal", "SIGNAL_API_v1")
    family, action = operation.split(".", 1)
    if len(args) == 3:
        args.append({"kind": "struct", "fields": {}})
    # CORE bulk channel calls this provider's unchanged public Octave function.
    # Legacy Tcl callers continue to use ScientificTransportv1.
    try:
        from gxtxt_scientific_binary_v1 import call, native
    except ImportError:
        pass
    else:
        options = dict(args[3])
        fields = dict(options.get("fields", {}))
        projection_node = fields.pop("result_fields", None)
        projection = None
        if projection_node is not None:
            projected = native(projection_node)
            projection = projected.split(",") if isinstance(projected, str) else projected
            if not isinstance(projection, list) or not all(isinstance(x, str) and x for x in projection):
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "result_fields must name result fields")
        options["fields"] = fields
        return call(host, "gxtxt_signal_v1", [family, action] + [native(v) for v in args[:3]] + [native(options)], projection)
    raw = host.call("::GX::SignalAPIv1::call", family, action, *args)
    types = host.as_dict(host.call("::GX::SignalAPIv1::resultTypes"))
    return _adapt(host, raw, types)
