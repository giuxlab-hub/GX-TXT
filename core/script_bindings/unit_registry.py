"""Octave Script Bridge registration owned by Unit Registry API v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
import os
from pathlib import Path
import struct
import subprocess
import tempfile

from gxtxt_script_bridge_server import BridgeError, NumericArray
from gxtxt_unit_program_v1 import decode_program

REGISTRATION = {
    "api_id": "UNIT_REGISTRY_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "unit_registry",
    "documentation_ref": "docs/api/UNIT_REGISTRY_API_v1.md",
    "operations": {
        "arithmetic_plan": {"name":"arithmetic_plan", "summary":"Plan dimension-preserving scalar arithmetic over registered linear units", "argument_convention":"operator, left unit, right unit, optional integer exponent", "result_convention":"output unit and authoritative operand scales"},
        "list": {"name": "list", "summary": "List registered unit symbols", "argument_convention": "no arguments", "result_convention": "cell of strings"},
        "definition": {"name": "definition", "summary": "Read a registered unit definition", "argument_convention": "unit symbol", "result_convention": "definition struct"},
        "compatible": {"name": "compatible", "summary": "Test conversion compatibility", "argument_convention": "source unit, target unit", "result_convention": "logical scalar"},
        "convert": {"name": "convert", "summary": "Convert numeric values using registered unit definitions", "argument_convention": "numeric scalar or array, source unit, target unit", "result_convention": "numeric scalar or array"},
        "convert_values": {"name": "convert_values", "summary": "Convert up to 4096 finite binary64 coordinate/control values in process", "argument_convention": "values, source, target, optional source_override", "result_convention": "numeric scalar or array"},
        "conversion_plan": {"name": "conversion_plan", "summary": "Read the effective explicit unit conversion definition", "argument_convention": "source unit, target unit", "result_convention": "conversion descriptor"},
        "affine_plan": {"name": "affine_plan", "summary": "Classify the declared forward or inverse conversion algebraically", "argument_convention": "source, target, optional source_override, optional direction", "result_convention": "conversion descriptor with affine flag and finite scale/offset when established"},
        "differential_ratio_plan": {"name":"differential_ratio_plan", "summary":"CORE unit plan for differential numerator/denominator, including affine offset cancellation", "argument_convention":"numerator unit, denominator unit, optional output unit", "result_convention":"versioned value/unavailable plan; finite scale only when established"},
        "homogeneous_coordinate_plan": {"name":"homogeneous_coordinate_plan", "summary":"Validate a common proportional Euclidean coordinate frame of any known physical dimension", "argument_convention":"source unit, target unit", "result_convention":"versioned homogeneous plan with exact scale; rejects unknown, opaque and affine origins"},
        "formula_program": {"name": "formula_program", "summary": "Read the Unit Registry parsed formula program", "argument_convention": "formula", "result_convention": "versioned arithmetic tree"},
    },
}
_ARGUMENTS = {
    "arithmetic_plan": [("operator", "arithmetic operator"), ("left_unit", "unit symbol"), ("right_unit", "unit symbol"), ("exponent", "optional integer exponent")],
    "list": [], "definition": [("unit", "unit symbol")],
    "compatible": [("source", "unit symbol"), ("target", "unit symbol")],
    "convert": [("values", "numeric scalar/vector/matrix"), ("source", "unit symbol"), ("target", "unit symbol")],
    "convert_values": [("values", "bounded numeric scalar/vector/matrix"), ("source", "unit symbol"), ("target", "unit symbol"), ("source_override", "optional variable conversion struct")],
    "conversion_plan": [("source", "unit symbol"), ("target", "unit symbol"), ("source_override", "optional variable conversion struct")],
    "affine_plan": [("source", "unit symbol"), ("target", "unit symbol"), ("source_override", "optional variable conversion struct"), ("direction", "optional forward/inverse")],
    "differential_ratio_plan": [("numerator", "unit symbol"), ("denominator", "unit symbol"), ("target", "optional output unit")],
    "homogeneous_coordinate_plan": [("source", "unit symbol"), ("target", "unit symbol")],
    "formula_program": [("formula", "registered formula grammar string")],
}
for _name, _fields in _ARGUMENTS.items():
    _operation = REGISTRATION["operations"][_name]
    _operation["arguments"] = [{"name": name, "kind": kind, "required": name not in ("source_override", "direction", "exponent") and not (_name == "differential_ratio_plan" and name == "target")} for name, kind in _fields]
    _operation["result_contract"] = _operation["result_convention"]
    _operation["unit_behavior"] = "Registry-defined compatible conversion" if _name in ("convert", "convert_values") else "Registry symbols"


def _definition(host, symbol):
    return host.as_dict(host.call("::GX::unitRegistryDefinition", symbol))


def _convert(host, values, source, target):
    if isinstance(values, NumericArray):
        shape, data = values.shape, values.values
    elif isinstance(values, (int, float)):
        shape, data = None, [float(values)]
    else:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "convert requires numeric scalar or array")
    adapter = Path(__file__).with_name("unit_convert_adapter.m")
    with tempfile.TemporaryDirectory(prefix="gxtxt-unit-bridge-") as directory:
        input_path = Path(directory) / "input.bin"
        output_path = Path(directory) / "output.bin"
        input_path.write_bytes(struct.pack("<" + "d" * len(data), *data))
        environment = os.environ.copy()
        registry = host.call("::GX::unitRegistryWriteRuntimeFile")
        if registry:
            environment["GXTXT_UNIT_REGISTRY_FILE"] = str(registry)
        proc = subprocess.run(["octave-cli", "--quiet", "--no-gui", str(adapter),
                               str(input_path), str(output_path), str(len(data)), source, target],
                              capture_output=True, text=True, env=environment, check=False)
        if proc.returncode:
            raise BridgeError("GXTXT:ScriptBridge:RemoteError", f"UNIT_REGISTRY_API_v1/convert: {proc.stderr.strip()}")
        raw = output_path.read_bytes()
        if len(raw) != 8 * len(data):
            raise BridgeError("GXTXT:ScriptBridge:Transport", "unit conversion returned an invalid numeric payload")
        result = list(struct.unpack("<" + "d" * len(data), raw))
    return result[0] if shape is None else NumericArray(result, shape)


def invoke(host, operation, args):
    if operation == "arithmetic_plan" and len(args) in (3, 4):
        plan = host.as_dict(host.call("::GX::unitRegistryArithmeticPlan", *args))
        for name in ("output_unit", "dimension_key"):
            plan[name] = str(host.tcl.call("format", "%s%s", plan[name], ""))
        for name in ("left_scale", "right_scale"):
            plan[name] = float(plan[name])
        return plan
    if operation == "homogeneous_coordinate_plan" and len(args) == 2:
        plan = host.as_dict(host.call("::GX::unitRegistryHomogeneousCoordinatePlan", *args))
        for name in ("schema", "source_unit", "target_unit", "dimension_key"):
            plan[name] = str(host.tcl.call("format", "%s%s", plan[name], ""))
        plan["scale"] = float(plan["scale"])
        plan["offset"] = float(plan["offset"])
        plan["physical_length"] = bool(int(plan["physical_length"]))
        return plan
    if operation == "formula_program" and len(args) == 1:
        return decode_program(host, host.call("::GX::unitFormulaProgram", args[0]))
    if operation == "list" and not args:
        return host.as_list(host.call("::GX::unitRegistryList"))
    if operation == "definition" and len(args) == 1:
        return _definition(host, args[0])
    if operation == "compatible" and len(args) == 2:
        return bool(int(host.call("::GX::unitTclCompatible", *args)))
    if operation == "convert" and len(args) == 3:
        values, source, target = args
        return _convert(host, values, source, target)
    if operation == "convert_values" and len(args) in (3, 4):
        values, source, target = args[:3]
        if isinstance(values, NumericArray):
            count = 1
            for length in values.shape:
                count *= int(length)
            if count > 4096 or values.dtype.startswith("complex") or values.dtype == "bool":
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "convert_values requires at most 4096 real elements")
            shape, data = values.shape, NumericArray(values.values, [count, 1], dtype=values.dtype)
        elif isinstance(values, (int, float)) and not isinstance(values, bool):
            shape, data = None, [values]
        else:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "convert_values requires a bounded numeric scalar or array")
        override = args[3] if len(args) == 4 else {}
        converted = [float(v) for v in host.as_list(host.call("::GX::unitRegistryConvertValues", source, target, data, override))]
        return converted[0] if shape is None else NumericArray(converted, shape)
    if operation == "differential_ratio_plan" and len(args) in (2, 3):
        plan = host.as_dict(host.call("::GX::unitRegistryDifferentialRatioPlan", *args))
        # Tcl may retain a list internal representation for a textual enum.
        # Preserve the public schema's string fields, independently of shimmering.
        for name in ("schema", "status", "numerator_unit", "denominator_unit",
                     "requested_unit", "output_unit", "dimension_key", "reason", "offset_policy"):
            plan[name] = str(host.tcl.call("format", "%s%s", plan[name], ""))
        if plan["status"] == "value":
            plan["scale"] = float(plan["scale"])
            for name in ("numerator_basis", "denominator_basis", "output_basis"):
                basis = host.as_dict(plan[name])
                for number in ("scale", "affine_offset"):
                    basis[number] = float(basis[number])
                for text in ("unit", "canonical_unit", "dimension_key"):
                    basis[text] = str(host.tcl.call("format", "%s%s", basis[text], ""))
                plan[name] = basis
        return plan
    if operation in ("conversion_plan", "affine_plan") and (len(args) in (2, 3) or operation == "affine_plan" and len(args) == 4):
        command = "::GX::unitRegistryAffinePlan" if operation == "affine_plan" else "::GX::unitRegistryConversionPlan"
        plan = host.as_dict(host.call(command, *args))
        for name in ("source_definition", "target_definition"):
            plan[name] = host.as_dict(plan[name])
        plan["base_scale_ratio"] = float(plan["base_scale_ratio"])
        if operation == "affine_plan":
            plan["affine"] = bool(int(plan["affine"]))
            for name in ("scale", "offset"):
                if name in plan:
                    plan[name] = float(plan[name])
        return plan
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for UNIT_REGISTRY_API_v1")
