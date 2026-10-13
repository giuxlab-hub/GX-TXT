"""Octave Script Bridge registration owned by Dataset Publication API v2."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray
import base64
import struct

REGISTRATION = {
    "api_id": "DATASET_PUBLICATION_API_v2", "api_version": 2,
    "provider_kind": "core", "provider_id": "dataset_publication",
    "documentation_ref": "docs/api/DATASET_PUBLICATION_API_v2.md",
    "operations": {
        "begin": {"name": "begin", "summary": "Prepare and open a managed Dataset writer", "argument_convention": "publication definition struct", "result_convention": "opaque writer token"},
        "declare_dimension": {"name": "declare_dimension", "summary": "Declare a Dataset dimension", "argument_convention": "writer, dimension_id, size, options struct", "result_convention": "empty string"},
        "declare_variable": {"name": "declare_variable", "summary": "Declare a stable Dataset variable", "argument_convention": "writer, variable_id, schema struct", "result_convention": "empty string"},
        "write_variable": {"name": "write_variable", "summary": "Write a declared variable", "argument_convention": "writer, variable_id, values, shape", "result_convention": "empty string"},
        "append": {"name": "append", "summary": "Append one bounded table chunk", "argument_convention": "writer, dimension_id, variable data struct", "result_convention": "empty string"},
        "finalize": {"name": "finalize", "summary": "Commit the managed Dataset", "argument_convention": "writer", "result_convention": "publication result struct"},
        "abort": {"name": "abort", "summary": "Abort a staged Dataset writer", "argument_convention": "writer", "result_convention": "empty string"},
        "publish_series": {"name": "publish_series", "summary": "Publish one X/Y scientific series through the managed Dataset writer", "argument_convention": "series request struct", "result_convention": "publication result struct"},
        "publish_series_batch": {"name": "publish_series_batch", "summary": "Publish reviewed separate X/Y Datasets atomically", "argument_convention": "batch request struct", "result_convention": "batch publication receipt"},
    },
}
_ARGUMENTS = {
    "begin": [("definition", "publication definition struct")],
    "declare_dimension": [("writer", "opaque writer token"), ("dimension_id", "string"),
                          ("size", "nonnegative integer"), ("options", "struct")],
    "declare_variable": [("writer", "opaque writer token"), ("variable_id", "stable Variable ID"),
                         ("schema", "Schema v3 struct")],
    "write_variable": [("writer", "opaque writer token"), ("variable_id", "stable Variable ID"),
                       ("values", "numeric array or cell"), ("shape", "dimension vector")],
    "append": [("writer", "opaque writer token"), ("dimension_id", "string"),
               ("variable_data", "struct")],
    "finalize": [("writer", "opaque writer token")],
    "abort": [("writer", "opaque writer token")],
    "publish_series": [("request", "series request struct")],
    "publish_series_batch": [("request", "batch request struct")],
}
for _name, _fields in _ARGUMENTS.items():
    REGISTRATION["operations"][_name]["arguments"] = [
        {"name": name, "kind": kind, "required": True} for name, kind in _fields]
    REGISTRATION["operations"][_name]["result_contract"] = REGISTRATION["operations"][_name]["result_convention"]


def _writers(host):
    return host.handles.setdefault("dataset_publication", set())


def _require(host, token):
    if token not in _writers(host):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "unknown or closed Dataset writer token")
    return token


def _binary(value, shape=None):
    if not isinstance(value, NumericArray):
        return value
    if isinstance(shape, NumericArray): shape = shape.values
    if shape is None: shape = [len(value.values)]
    if isinstance(shape, str): shape = shape.replace(";", " ").split()
    shape = [int(x) for x in shape]
    try:
        import numpy as np
        array = np.asarray(value.values, dtype="<f8").reshape(value.shape, order="F")
        raw = array.tobytes(order="C")
    except ImportError:
        raw = struct.pack("<" + "d" * len(value.values), *value.values)
    return {"__gxtxt_binary_block": 1, "dtype": "float64", "endian": "little",
            "shape": ";".join(map(str, shape)), "byte_count": len(raw),
            "base64": base64.b64encode(raw).decode("ascii")}


def invoke(host, operation, args):
    if operation == "publish_series_batch" and len(args) == 1 and isinstance(args[0], dict):
        request = args[0]
        if set(request) != {"series"} or not isinstance(request["series"], (list, tuple)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "batch request needs a series list")
        raw = host.as_dict(host.call("::GX::datasetPublicationV2PublishBatch", host.session, host.module_id, request["series"]))
        datasets = [host.as_dict(item) for item in host.as_list(raw["datasets"])]
        for item in datasets:
            item.pop("path", None)
        return host.record_publications({"output_count": int(raw["output_count"]), "atomic": bool(int(raw["atomic"])),
                "dataset_ids": host.as_list(raw["dataset_ids"]), "datasets": datasets})
    if operation == "publish_series" and len(args) == 1 and isinstance(args[0], dict):
        result = host.as_dict(host.call("::GX::datasetPublicationV2PublishSeries", host.session, host.module_id, args[0]))
        result.pop("path", None)
        return host.record_publications(result)
    if operation == "begin" and len(args) == 1 and isinstance(args[0], dict):
        plan = host.call("::GX::datasetPublicationV2Prepare", host.session, host.module_id, args[0])
        writer = str(host.call("::GX::datasetPublicationV2OpenWriter", plan))
        _writers(host).add(writer)
        return writer
    if not args:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires a writer token")
    writer = _require(host, args[0])
    if operation == "declare_dimension" and len(args) == 4 and isinstance(args[3], dict):
        host.call("::GX::datasetPublicationV2DeclareDimension", writer, args[1], args[2], args[3])
        return ""
    if operation == "declare_variable" and len(args) == 3 and isinstance(args[2], dict):
        host.call("::GX::datasetPublicationV2DeclareVariable", writer, args[1], args[2])
        return ""
    if operation == "write_variable" and len(args) == 4:
        host.call("::GX::datasetPublicationV2WriteVariable", writer, args[1], _binary(args[2], args[3]), args[3])
        return ""
    if operation == "append" and len(args) == 3 and isinstance(args[2], dict):
        data = {}
        for key, value in args[2].items():
            if isinstance(value, dict) and "shape" in value and "values" in value:
                data[key] = {**value, "values": _binary(value["values"], value["shape"])}
            else:
                data[key] = _binary(value)
        host.call("::GX::datasetPublicationV2Append", writer, args[1], data)
        return ""
    if operation == "finalize" and len(args) == 1:
        result = host.as_dict(host.call("::GX::datasetPublicationV2Finalize", writer))
        _writers(host).remove(writer)
        result.pop("path", None)
        return host.record_publications(result)
    if operation == "abort" and len(args) == 1:
        host.call("::GX::datasetPublicationV2Abort", writer)
        _writers(host).remove(writer)
        return ""
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for DATASET_PUBLICATION_API_v2")


def cleanup(host):
    for writer in list(_writers(host)):
        try:
            host.call("::GX::datasetPublicationV2Abort", writer)
        finally:
            _writers(host).discard(writer)
