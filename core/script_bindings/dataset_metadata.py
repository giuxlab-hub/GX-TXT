"""Python/Octave Script Bridge registration owned by Dataset Metadata API v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

REGISTRATION = {
    "api_id": "DATASET_METADATA_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_metadata",
    "documentation_ref": "docs/api/DATASET_METADATA_API_v1.md",
    "operations": {
        "read": {"name": "read", "summary": "Read framework-managed Dataset metadata", "argument_convention": "dataset_id", "result_convention": "metadata struct"},
        "update": {"name": "update", "summary": "Update framework-managed Dataset metadata", "argument_convention": "dataset_id, updates struct", "result_convention": "metadata struct"},
        "unset": {"name": "unset", "summary": "Remove selected metadata keys", "argument_convention": "dataset_id, key cell", "result_convention": "metadata struct"},
    },
}
REGISTRATION["operations"]["parse_text"] = {
    "name": "parse_text", "summary": "Parse portable key=value metadata atomically",
    "argument_convention": "text", "result_convention": "validated metadata struct",
    "arguments": [{"name": "text", "kind": "UTF-8 string", "required": True}],
    "result_contract": "validated metadata struct",
}
for _name, _operation in REGISTRATION["operations"].items():
    if _name == "parse_text":
        continue
    _operation["arguments"] = [{"name": "dataset_id", "kind": "Dataset ID", "required": True}]
    if _name != "read":
        _operation["arguments"].append({"name": "updates" if _name == "update" else "keys",
                                        "kind": "metadata struct" if _name == "update" else "cell of strings",
                                        "required": True})
    _operation["result_contract"] = _operation["result_convention"]


for _name, _summary, _extra in (
    ("private_read", "Read all reserved Dataset metadata", None),
    ("private_update", "Update relative keys owned by this runtime module", ("updates", "metadata struct")),
    ("private_unset", "Unset relative keys owned by this runtime module", ("keys", "cell of strings")),
):
    _arguments = [{"name": "dataset_id", "kind": "Dataset ID", "required": True}]
    if _extra:
        _arguments.append({"name": _extra[0], "kind": _extra[1], "required": True})
    REGISTRATION["operations"][_name] = {
        "name": _name, "summary": _summary, "arguments": _arguments,
        "argument_convention": "dataset_id" + (", " + _extra[0] if _extra else ""),
        "result_convention": "private metadata struct", "result_contract": "private metadata struct",
    }
REGISTRATION["operations"]["private_owner"] = {
    "name": "private_owner", "summary": "Describe the trusted runtime module owner (no capability exposed)",
    "arguments": [], "argument_convention": "none", "result_convention": "owner struct",
    "result_contract": "module_id and owner_prefix",
}

for _name, _summary, _arguments, _result in (
    ("coordinate_read", "Read verified Dataset coordinate settings", [("dataset_id", "Dataset ID")], "versioned coordinate context"),
    ("coordinate_inspect", "Diagnose stale coordinate settings without applying them", [("dataset_id", "Dataset ID")], "status, reason, revision and current context when valid"),
    ("coordinate_update", "Persist display, view or calibration settings atomically", [("dataset_id", "Dataset ID"), ("updates", "Variable ID to settings struct"), ("expected_revision", "nonnegative integer")], "versioned coordinate context"),
    ("coordinate_reset", "Reset coordinate settings to identity", [("dataset_id", "Dataset ID"), ("expected_revision", "nonnegative integer")], "versioned coordinate context"),
    ("coordinate_validate", "Validate a stored coordinate context against its source", [("dataset_id", "Dataset ID"), ("context", "stored versioned context")], "validated stored context"),
    ("coordinate_values", "Convert bounded coordinate readouts with explicit effective mode", [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("values", "bounded real array"), ("options", "optional mode/unit/direction/source_unit_assumption struct")], "values, physical unit and source revision"),
    ("coordinate_view_range", "Apply persistent magnification to a canonical reference range", [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("reference_range", "two canonical endpoints")], "canonical viewport range and revision"),
    ("coordinate_snapshot_values", "Present a captured context without asserting current source validity", [("context", "resolved coordinate snapshot"), ("variable_id", "stable Variable ID"), ("values", "bounded real array"), ("options", "optional mode/unit/direction/source_unit_assumption struct")], "values, unit, revision and snapshot_only verification"),
    ("coordinate_snapshot_view_range", "Apply captured magnification without source IO", [("context", "resolved coordinate snapshot"), ("variable_id", "stable Variable ID"), ("reference_range", "two canonical endpoints")], "canonical viewport range, revision and snapshot_only verification"),
    ("coordinate_snapshot_affine_plan", "Classify captured presentation from an explicit Native unit frame", [("context", "resolved coordinate snapshot"), ("variable_id", "stable Variable ID"), ("native_unit", "physical unit of input geometry"), ("options", "optional mode/unit/direction/source_unit_assumption struct")], "affine flag, finite scale/offset when established, and snapshot_only verification"),
):
    REGISTRATION["operations"][_name] = dict(name=_name, summary=_summary,
        arguments=[dict(name=n, kind=k, required=n!="options") for n,k in _arguments],
        argument_convention=", ".join(n for n,k in _arguments), result_convention=_result, result_contract=_result)


def _coordinate_context(host, value):
    result=host.as_dict(value)
    for key in ("schema_version", "revision"):
        result[key]=int(result[key])
    if "persistent" in result:
        result["persistent"]=bool(int(result["persistent"]))
    variables={}
    for vid,settings in host.as_dict(result["variables"]).items():
        settings=host.as_dict(settings)
        settings["source"]=host.as_dict(settings["source"])
        for key in ("view_factor", "view_pivot", "calibration_factor", "input_origin", "output_origin"):
            settings[key]=float(settings[key])
        variables[vid]=settings
    result["variables"]=variables
    return result


def _bounded_coordinate_values(values):
    if isinstance(values, NumericArray):
        count=1
        for length in values.shape:
            count*=int(length)
        if count>4096 or values.dtype.startswith("complex") or values.dtype=="bool":
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Coordinate presentation requires at most 4096 real elements")
        return NumericArray(values.values, [count, 1], dtype=values.dtype), values.shape
    if isinstance(values, (int, float)) and not isinstance(values, bool):
        return [values], None
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Coordinate values require a bounded real scalar or array")

def invoke(host, operation, args):
    if operation=="coordinate_snapshot_affine_plan" and len(args) in (3,4):
        result=host.as_dict(host.call("::GX::datasetCoordinateSnapshotAffinePlan",*args))
        result["revision"]=int(result["revision"]);result["affine"]=bool(int(result["affine"]))
        for key in ("scale", "offset"):
            if key in result: result[key]=float(result[key])
        return result
    if operation in ("update", "unset", "private_update", "private_unset", "coordinate_update", "coordinate_reset") and args:
        host.call("::GX::_datasetNamespaceRequireModuleWrite", host.session, host.module_id, args[0])
    commands={"coordinate_read": ("Read",1), "coordinate_update": ("Update",3), "coordinate_reset": ("Reset",2), "coordinate_validate": ("Validate",2)}
    if operation in commands and len(args)==commands[operation][1]:
        return _coordinate_context(host, host.call("::GX::datasetCoordinate"+commands[operation][0], host.session, *args))
    if operation=="coordinate_inspect" and len(args)==1:
        result=host.as_dict(host.call("::GX::datasetCoordinateInspect",host.session,args[0]))
        result["revision"]=int(result["revision"])
        if "context" in result:
            result["context"]=_coordinate_context(host,result["context"])
        return result
    if operation in ("coordinate_values", "coordinate_snapshot_values") and len(args) in (3,4):
        values,shape=_bounded_coordinate_values(args[2])
        command=("::GX::datasetCoordinateValues",host.session) if operation=="coordinate_values" else ("::GX::datasetCoordinateSnapshotValues",)
        result=host.as_dict(host.call(*command,args[0],args[1],values,args[3] if len(args)==4 else {}))
        converted=[float(v) for v in host.as_list(result["values"])]
        result["values"]=converted[0] if shape is None else NumericArray(converted,shape)
        result["revision"]=int(result["revision"])
        return result
    if operation in ("coordinate_view_range", "coordinate_snapshot_view_range") and len(args)==3:
        values,shape=_bounded_coordinate_values(args[2])
        command=("::GX::datasetCoordinateViewRange",host.session) if operation=="coordinate_view_range" else ("::GX::datasetCoordinateSnapshotViewRange",)
        result=host.as_dict(host.call(*command,args[0],args[1],values))
        for key in ("canonical_range", "reference_range"):
            result[key]=NumericArray([float(v) for v in host.as_list(result[key])],[2,1])
        result["revision"]=int(result["revision"])
        for key in ("view_factor", "view_pivot"):
            result[key]=float(result[key])
        return result
    if operation == "private_owner" and not args:
        context = host.dataset_private_context()
        return {key: context[key] for key in ("module_id", "owner_prefix")}
    if operation == "private_read" and len(args) == 1:
        return host.as_dict(host.call("::GX::datasetPrivateMetadataRead", host.session, args[0]))
    if operation == "private_update" and len(args) == 2 and isinstance(args[1], dict):
        return host.as_dict(host.call("::GX::datasetPrivateMetadataUpdate", host.dataset_private_context()["capability"], host.session, args[0], args[1]))
    if operation == "private_unset" and len(args) == 2 and isinstance(args[1], list):
        return host.as_dict(host.call("::GX::datasetPrivateMetadataUnset", host.dataset_private_context()["capability"], host.session, args[0], args[1]))
    if operation == "parse_text" and len(args) == 1 and isinstance(args[0], str):
        return host.as_dict(host.call("::GX::datasetMetadataParseText", args[0]))
    if operation == "read" and len(args) == 1:
        return host.as_dict(host.call("::GX::datasetMetadataRead", host.session, args[0]))
    if operation == "update" and len(args) == 2 and isinstance(args[1], dict):
        return host.as_dict(host.call("::GX::datasetMetadataUpdate", host.session, args[0], args[1]))
    if operation == "unset" and len(args) == 2 and isinstance(args[1], list):
        return host.as_dict(host.call("::GX::datasetMetadataUnset", host.session, args[0], args[1]))
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} arguments for DATASET_METADATA_API_v1")
