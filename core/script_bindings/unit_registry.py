"""Octave Script Bridge registration owned by Unit Registry API v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
import os
from pathlib import Path
import struct
import subprocess
import tempfile

from gxtxt_script_bridge_server import BridgeError, NumericArray

REGISTRATION = {
    "api_id": "UNIT_REGISTRY_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "unit_registry",
    "documentation_ref": "docs/api/UNIT_REGISTRY_API_v1.md",
    "operations": {
        "list": {"name": "list", "summary": "List registered unit symbols", "argument_convention": "no arguments", "result_convention": "cell of strings"},
        "definition": {"name": "definition", "summary": "Read a registered unit definition", "argument_convention": "unit symbol", "result_convention": "definition struct"},
        "compatible": {"name": "compatible", "summary": "Test conversion compatibility", "argument_convention": "source unit, target unit", "result_convention": "logical scalar"},
        "convert": {"name": "convert", "summary": "Convert numeric values using registered unit definitions", "argument_convention": "numeric scalar or array, source unit, target unit", "result_convention": "numeric scalar or array"},
        "conversion_plan": {"name": "conversion_plan", "summary": "Read the effective explicit unit conversion definition", "argument_convention": "source unit, target unit", "result_convention": "conversion descriptor"},
    },
}
_ARGUMENTS = {
    "list": [], "definition": [("unit", "unit symbol")],
    "compatible": [("source", "unit symbol"), ("target", "unit symbol")],
    "convert": [("values", "numeric scalar/vector/matrix"), ("source", "unit symbol"), ("target", "unit symbol")],
    "conversion_plan": [("source", "unit symbol"), ("target", "unit symbol"), ("source_override", "optional variable conversion struct")],
}
for _name, _fields in _ARGUMENTS.items():
    _operation = REGISTRATION["operations"][_name]
    _operation["arguments"] = [{"name": name, "kind": kind, "required": name != "source_override"} for name, kind in _fields]
    _operation["result_contract"] = _operation["result_convention"]
    _operation["unit_behavior"] = "Registry-defined compatible conversion" if _name == "convert" else "Registry symbols"


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
    if operation == "list" and not args:
        return host.as_list(host.call("::GX::unitRegistryList"))
    if operation == "definition" and len(args) == 1:
        return _definition(host, args[0])
    if operation == "compatible" and len(args) == 2:
        return bool(int(host.call("::GX::unitTclCompatible", *args)))
    if operation == "convert" and len(args) == 3:
        values, source, target = args
        return _convert(host, values, source, target)
    if operation == "conversion_plan" and len(args) in (2, 3):
        plan = host.as_dict(host.call("::GX::unitRegistryConversionPlan", *args))
        for name in ("source_definition", "target_definition"):
            plan[name] = host.as_dict(plan[name])
        plan["base_scale_ratio"] = float(plan["base_scale_ratio"])
        return plan
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for UNIT_REGISTRY_API_v1")
