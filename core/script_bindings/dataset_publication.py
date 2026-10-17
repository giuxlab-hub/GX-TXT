"""Octave Script Bridge registration owned by Dataset Publication API v2."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray, ResourceNumericArray
import base64
import struct
import os
from contextlib import contextmanager
from pathlib import Path

REGISTRATION = {
    "api_id": "DATASET_PUBLICATION_API_v2", "api_version": 2,
    "provider_kind": "core", "provider_id": "dataset_publication",
    "documentation_ref": "docs/api/DATASET_PUBLICATION_API_v2.md",
    "operations": {
        "publish_managed_variables": {"name": "publish_managed_variables", "summary": "Publish owned nD arrays through the canonical binary Dataset writer", "argument_convention": "definition, dimension ID/size dictionary, Variable schema/resource bindings", "result_convention": "publication result struct with exact nD schema"},
        "publish_managed_columns": {"name": "publish_managed_columns", "summary": "Publish an owned binary64 column-major matrix through the canonical managed Dataset writer", "argument_convention": "definition, owned resource, ordered schema", "result_convention": "publication result struct"},
        "begin": {"name": "begin", "summary": "Prepare and open a managed Dataset writer", "argument_convention": "publication definition struct", "result_convention": "opaque writer token"},
        "declare_dimension": {"name": "declare_dimension", "summary": "Declare a Dataset dimension", "argument_convention": "writer, dimension_id, size, options struct", "result_convention": "empty string"},
        "declare_variable": {"name": "declare_variable", "summary": "Declare a stable Dataset variable", "argument_convention": "writer, variable_id, schema struct", "result_convention": "empty string"},
        "write_variable": {"name": "write_variable", "summary": "Write a declared variable", "argument_convention": "writer, variable_id, values, shape", "result_convention": "empty string"},
        "append": {"name": "append", "summary": "Append one bounded table chunk", "argument_convention": "writer, dimension_id, variable data struct", "result_convention": "empty string"},
        "finalize": {"name": "finalize", "summary": "Commit the managed Dataset", "argument_convention": "writer", "result_convention": "publication result struct"},
        "abort": {"name": "abort", "summary": "Abort a staged Dataset writer", "argument_convention": "writer", "result_convention": "empty string"},
        "writer_capabilities": {"name": "writer_capabilities", "summary": "Inspect the selected writer's supported operations", "argument_convention": "writer", "result_convention": "capability booleans"},
        "diagnostics": {"name": "diagnostics", "summary": "Inspect actual write transport counters", "argument_convention": "writer", "result_convention": "diagnostics struct"},
        "publish_series": {"name": "publish_series", "summary": "Publish one X/Y scientific series through the managed Dataset writer", "argument_convention": "series request struct", "result_convention": "publication result struct"},
        "publish_series_batch": {"name": "publish_series_batch", "summary": "Publish reviewed separate X/Y Datasets atomically", "argument_convention": "batch request struct", "result_convention": "batch publication receipt"},
    },
}
_ARGUMENTS = {
    "publish_managed_variables": [("definition", "publication definition"), ("dimensions", "dimension ID/size dictionary"), ("variables", "ordered Variable ID/schema/owned resource bindings")],
    "publish_managed_columns": [("definition", "publication definition struct"), ("resource", "owned Document numeric matrix resource"), ("schema", "ordered Variable schema list")],
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
    "writer_capabilities": [("writer", "opaque writer token")],
    "diagnostics": [("writer", "opaque writer token")],
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


@contextmanager
def _resources(host, writer):
    caps = host.as_dict(host.call('::GX::datasetPublicationV2WriterCapabilities', writer))
    scope = os.environ.get('GXTXT_BRIDGE_WORKSPACE') if str(caps.get('managed_binary_write', '0')) == '1' else None
    temporary = []
    try:
        yield dict(scope=scope, temporary=temporary)
    finally:
        for path in temporary: path.unlink(missing_ok=True)


def _binary(value, shape=None, scope=None, temporary=None):
    if not isinstance(value, NumericArray):
        return value
    if isinstance(shape, NumericArray): shape = shape.values
    if shape is None:
        import math
        shape = [math.prod(value.shape)]
    if isinstance(shape, str): shape = shape.replace(";", " ").split()
    if isinstance(shape, (int, float)): shape = [shape]
    if any(isinstance(x, bool) or int(x) != float(x) or int(x) < 0 for x in shape):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'shape requires nonnegative integer dimensions')
    shape = [int(x) for x in shape]
    if scope:
        from gxtxt_scientific_binary_v1 import write_buffer
        # The public write/append contract accepts flat row-major values with
        # an explicit logical shape. Resources themselves are column-major.
        # Reconstruct the incoming logical array, reshape in public C order,
        # then let the resource owner encode its F-order transport. Already
        # shaped resources and vector-only views can still forward unchanged.
        same_layout = list(value.shape) == shape or (
            sum(n != 1 for n in value.shape) <= 1 and
            sum(n != 1 for n in shape) <= 1)
        if isinstance(value, ResourceNumericArray) and same_layout:
            descriptor = dict(value.descriptor)
        else:
            array = value.values.reshape(value.shape, order='F').reshape(shape, order='C')
            descriptor = write_buffer(scope, array)
            temporary.append(Path(scope) / descriptor['resource_id'])
        descriptor['shape'] = ';'.join(map(str, descriptor['shape']))
        descriptor['resource_root'] = scope
        return {'__gxtxt_binary_resource':1, 'shape':';'.join(map(str,shape)), 'resource':descriptor}
    try:
        import numpy as np
        array = np.asarray(value.values).reshape(value.shape, order="F")
        dtype = array.dtype.name
        array = array.astype(array.dtype.newbyteorder('<'), copy=False)
        raw = array.tobytes(order="C")
    except ImportError:
        raw = struct.pack("<" + "d" * len(value.values), *value.values)
        dtype = 'float64'
    return {"__gxtxt_binary_block": 1, "dtype": dtype, "endian": "little",
            "shape": ";".join(map(str, shape)), "byte_count": len(raw),
            "base64": base64.b64encode(raw).decode("ascii")}


def invoke(host, operation, args):
    if operation == "publish_managed_variables" and len(args) == 3 and isinstance(args[0], dict) and isinstance(args[1], dict) and isinstance(args[2], (list, tuple)):
        result = host.as_dict(host.call("::GX::datasetPublicationV2PublishManagedVariables", host.session, host.module_id, *args))
        result.pop("path", None)
        result["variable_count"] = int(result["variable_count"])
        return host.record_publications(result)
    if operation == "publish_managed_columns" and len(args) == 3 and isinstance(args[0], dict) and isinstance(args[1], dict) and isinstance(args[2], (list, tuple)):
        result = host.as_dict(host.call("::GX::datasetPublicationV2PublishManagedColumns", host.session, host.module_id, *args))
        result.pop("path", None)
        result["row_count"] = int(result["row_count"])
        return host.record_publications(result)
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
    if operation == 'writer_capabilities' and len(args) == 1:
        return {k:bool(int(v)) for k,v in host.as_dict(host.call('::GX::datasetPublicationV2WriterCapabilities',writer)).items()}
    if operation == 'diagnostics' and len(args) == 1:
        return {k:int(v) for k,v in host.as_dict(host.call('::GX::datasetPublicationV2Diagnostics',writer)).items()}
    if operation == "declare_dimension" and len(args) == 4 and isinstance(args[3], dict):
        host.call("::GX::datasetPublicationV2DeclareDimension", writer, args[1], args[2], args[3])
        return ""
    if operation == "declare_variable" and len(args) == 3 and isinstance(args[2], dict):
        host.call("::GX::datasetPublicationV2DeclareVariable", writer, args[1], args[2])
        return ""
    if operation == "write_variable" and len(args) == 4:
        with _resources(host,writer) as transport:
            host.call("::GX::datasetPublicationV2WriteVariable", writer, args[1], _binary(args[2], args[3], **transport), args[3])
        return ""
    if operation == "append" and len(args) == 3 and isinstance(args[2], dict):
        with _resources(host,writer) as transport:
            data = {}
            for key, value in args[2].items():
                if isinstance(value, dict) and "shape" in value and "values" in value:
                    data[key] = {**value, "values": _binary(value["values"], value["shape"], **transport)}
                else:
                    data[key] = _binary(value, **transport)
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
