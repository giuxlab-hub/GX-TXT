"""Both-language public Dataset Transform binding with execution-scoped tokens."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_ARGS = {
    "operations": [], "describe_operation": ["operation"], "validate": ["manifest"],
    "plan": ["manifest"], "release_plan": ["plan_id"], "execute": ["manifest_or_plan"],
    "open_view": ["manifest_or_plan"], "open_view_stream": ["view", "variable_ids", "chunk_rows", "options"],
    "close_view": ["view"], "provenance": ["dataset_id"],
}
REGISTRATION = {
    "api_id": "DATASET_TRANSFORM_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "dataset_transform",
    "documentation_ref": "docs/api/DATASET_TRANSFORM_API_v1.md",
    "operations": {name: {"name": name, "summary": "Generic structural Dataset transform: " + name,
                           "arguments": [{"name": arg, "kind": "opaque token" if arg in ("view", "plan_id") else "struct" if "manifest" in arg or arg == "options" else "public value", "required": True} for arg in args],
                           "argument_convention": ", ".join(args),
                           "result_convention": "public result", "result_contract": "logical identity or transform result without host paths",
                           "unit_behavior": "Explicit registry conversion only", "callback_behavior": "No callbacks"}
                   for name, args in _ARGS.items()}
}


def _state(host):
    return host.handles.setdefault("dataset_transform", {"plans": set(), "views": {}, "streams": {}})


def _dict(host, value):
    return host.as_dict(value)


def _manifest(host, value):
    raw = _dict(host, value)
    raw["api_version"] = int(raw["api_version"])
    raw["output"] = _dict(host, raw["output"])
    if "member_outputs" in raw["output"]: raw["output"]["member_outputs"] = _dict(host, raw["output"]["member_outputs"])
    raw["schema_policy"] = _dict(host, raw["schema_policy"])
    options = _dict(host, raw["options"])
    for name in ("rename", "display_labels", "target_units", "family_units", "metadata", "metadata_overrides", "baseline_options", "smoothing_options"):
        if name in options: options[name] = _dict(host, options[name])
    for name in ("variable_ids", "reorder", "family_axes", "members", "source_member_ids", "calibration_variable_ids"):
        if name in options: options[name] = host.as_list(options[name])
    if 'logarithms' in options:
        options['logarithms'] = [_dict(host, item) for item in host.as_list(options['logarithms'])]
        for item in options['logarithms']: item['reference'] = float(item['reference'])
    if "expected_coordinate_revision" in options: options["expected_coordinate_revision"]=int(options["expected_coordinate_revision"])
    for name in ("ranges", "keys"):
        if name in options: options[name] = [host.as_list(item) for item in host.as_list(options[name])]
    if "matrix" in options: options["matrix"] = NumericArray(host.as_list(options["matrix"]))
    raw["options"] = options
    sources = []
    for item in host.as_list(raw["sources"]):
        source = _dict(host, item)
        for name in ("variable_map", "convert_units", "assume_units", "family_coordinates"):
            if name in source: source[name] = _dict(host, source[name])
        for name in ("variable_ids", "rows"):
            if name in source: source[name] = host.as_list(source[name])
        for name in ("row_filters", "selection_filters"):
            if name in source: source[name] = [_dict(host, v) for v in host.as_list(source[name])]
        sources.append(source)
    raw["sources"] = sources
    return raw


def _log_transform(host, value):
    result = _dict(host, value)
    result['reference'] = float(result['reference'])
    return result


def _smoothing_receipt(host,value):
    receipt=_dict(host,value)
    for key in ('options','estimator'):receipt[key]=_dict(host,receipt[key])
    for key in ('original_n','smoothed_n','omitted_n'):receipt[key]=int(receipt[key])
    for key in ('window','degree','robust_iterations'):
        if key in receipt['options']:receipt['options'][key]=float(receipt['options'][key])
    for key in ('window','degree','original_count','robust_iterations','robust_iterations_completed','robust_zero_weight_count','maximum_work_units','robust_scale'):
        if key in receipt['estimator']:receipt['estimator'][key]=float(receipt['estimator'][key])
    return receipt


def _report(host, value):
    raw = _dict(host, value)
    if 'logarithm_receipt' in raw:
        receipt = _dict(host, raw['logarithm_receipt'])
        receipt['transforms'] = [_log_transform(host, v) for v in host.as_list(receipt['transforms'])]
        for key in ('row_count', 'chunk_limit'): receipt[key] = int(receipt[key])
        raw['logarithm_receipt'] = receipt
    if 'baseline_receipt' in raw:
        receipt = _dict(host, raw['baseline_receipt'])
        for key in ('options', 'estimator'):
            receipt[key] = _dict(host, receipt[key])
        for key in ('original_n', 'estimated_n', 'omitted_n'):
            receipt[key] = int(receipt[key])
        raw['baseline_receipt'] = receipt
    if 'smoothing_receipt' in raw:
        raw['smoothing_receipt']=_smoothing_receipt(host,raw['smoothing_receipt'])
    for name in ("api_version", "row_count", "max_input_chunk_rows", "sqlite_cache_bytes"):
        if name in raw: raw[name] = int(raw[name])
    if "valid" in raw: raw["valid"] = bool(int(raw["valid"]))
    raw["variables"] = [_dict(host, v) for v in host.as_list(raw["variables"])]
    fingerprints = []
    for item in host.as_list(raw["source_fingerprints"]):
        source = _dict(host, item)
        source["variable_ids"] = host.as_list(source["variable_ids"])
        source["row_count"] = int(source["row_count"])
        fingerprints.append(source)
    raw["source_fingerprints"] = fingerprints
    conversions = []
    for item in host.as_list(raw["conversions"]):
        conversion = _dict(host, item)
        for name in ("source_definition", "target_definition"):
            if name in conversion: conversion[name] = _dict(host, conversion[name])
        conversion["base_scale_ratio"] = float(conversion["base_scale_ratio"])
        conversions.append(conversion)
    raw["conversions"] = conversions
    calibrations = host.as_list(raw.get("calibrations", ()))
    raw["calibrations"] = []
    for item in calibrations:
        item=host.as_dict(item)
        for key in ("factor", "input_origin", "output_origin"):
            item[key]=float(item[key])
        item["identity"]=bool(int(item["identity"]))
        item["coordinate_revision"]=int(item["coordinate_revision"])
        raw["calibrations"].append(item)
    assumptions = host.as_list(raw.get("unit_assumptions", ()))
    raw["unit_assumptions"] = []
    for item in assumptions:
        assumption = _dict(host, item)
        assumption["source_schema_mutated"] = bool(int(assumption["source_schema_mutated"]))
        raw["unit_assumptions"].append(assumption)
    raw["family_coordinates"] = {key: NumericArray(host.as_list(values)) for key, values in _dict(host, raw["family_coordinates"]).items()}
    raw["family_parts"] = {key: int(value) for key,value in _dict(host, raw.get("family_parts", "")).items()}
    raw["variable_mapping"] = [_dict(host, item) for item in host.as_list(raw.get("variable_mapping", ()))]
    raw["compatibility_conflicts"] = host.as_list(raw.get("compatibility_conflicts", ()))
    raw["effective_options"] = _dict(host, raw.get("effective_options", ""))
    raw["member_descriptors"] = []
    for item in host.as_list(host.as_dict(value).get("member_descriptors", ())):
        descriptor = _dict(host, item)
        for axis in ("x", "y"): descriptor[f"{axis}_descriptor"] = _dict(host, descriptor[f"{axis}_descriptor"])
        raw["member_descriptors"].append(descriptor)
    if "manifest" in raw: raw["manifest"] = _manifest(host, raw["manifest"])
    return raw


def _request(host, value):
    if not isinstance(value, dict):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Transform request must be a manifest or plan struct")
    if "plan_id" in value and value["plan_id"] not in _state(host)["plans"]:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Unknown/released transform plan in this execution")
    return {"plan_id": value["plan_id"]} if "plan_id" in value else value


def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid Dataset Transform {operation} arguments")
    state = _state(host)
    if operation == "operations":
        return host.as_list(host.call("::GX::datasetTransformOperations"))
    if operation == "describe_operation":
        result = _dict(host, host.call("::GX::datasetTransformDescribeOperation", args[0]))
        result["metadata_policies"] = host.as_list(result["metadata_policies"])
        return result
    if operation in ("plan", "validate"):
        result = _report(host, host.call("::GX::datasetTransform" + operation.title(), host.session, _request(host, args[0])))
        if operation == "plan": state["plans"].add(result["plan_id"])
        return result
    if operation == "release_plan":
        token = args[0]
        if token not in state["plans"]:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Unknown transform plan")
        host.call("::GX::datasetTransformReleasePlan", token)
        state["plans"].remove(token);return True
    if operation == "execute":
        result = _dict(host, host.call("::GX::_datasetPrivateWithModule", host.module_id, "::GX::datasetTransformExecute", host.session, _request(host, args[0])))
        if "datasets" in result:
            datasets = [_dict(host, item) for item in host.as_list(result["datasets"])]
            return {"dataset_ids": host.as_list(result["dataset_ids"]), "datasets": [{key: item[key] for key in ("dataset_id", "row_count", "contract", "storage_provider", "sha256")} for item in datasets]}
        return {key: result[key] for key in ("dataset_id", "row_count", "contract", "storage_provider", "sha256")}
    if operation == "open_view":
        token = str(host.call("::GX::datasetTransformOpenView", host.session, _request(host, args[0])))
        state["views"][token] = True;return token
    if operation == "open_view_stream":
        view, variables, chunk_rows, options = args
        if view not in state["views"] or not isinstance(variables, list) or not isinstance(options, dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Unknown transform view or invalid stream options")
        stream = str(host.call("::GX::datasetTransformOpenViewStream", view, variables, chunk_rows, options))
        state["streams"][stream] = view
        host.handles.setdefault("table_stream", set()).add(stream)
        return stream
    if operation == "close_view":
        view = args[0]
        if view not in state["views"]:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Unknown or closed transform view")
        host.call("::GX::datasetTransformCloseView", view)
        for stream in list(state["streams"]):
            if state["streams"][stream] == view:
                host.handles.setdefault("table_stream", set()).discard(stream)
                del state["streams"][stream]
        del state["views"][view];return True
    if operation == "provenance":
        raw = _dict(host, host.call("::GX::datasetTransformProvenance", host.session, args[0]))
        if not raw: return {}
        raw["manifest"] = _manifest(host, raw["manifest"])
        raw["effective"] = _report(host, raw["effective"])
        if 'logarithm_lineage' in raw:
            lineage = []
            for item in host.as_list(raw['logarithm_lineage']):
                item = _dict(host, item)
                item['transform'] = _log_transform(host, item['transform'])
                item['inverse_eligible'] = bool(int(item['inverse_eligible']))
                lineage.append(item)
            raw['logarithm_lineage'] = lineage
        if "baseline_lineage" in raw:
            lineage = []
            for item in host.as_list(raw["baseline_lineage"]):
                item = _dict(host, item);receipt = _dict(host, item['correction'])
                for key in ('options', 'estimator'): receipt[key] = _dict(host, receipt[key])
                for key in ('original_n', 'estimated_n', 'omitted_n'): receipt[key] = int(receipt[key])
                item['correction'] = receipt;lineage.append(item)
            raw['baseline_lineage'] = lineage
        if "smoothing_lineage" in raw:
            lineage = []
            for item in host.as_list(raw["smoothing_lineage"]):
                item = _dict(host, item);item['smoothing']=_smoothing_receipt(host,item['smoothing']);lineage.append(item)
            raw['smoothing_lineage'] = lineage
        raw["metadata_conflicts"] = host.as_list(raw["metadata_conflicts"])
        return raw
    raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", operation)


def cleanup(host):
    state = _state(host)
    for view in list(state["views"]):
        invoke(host, "close_view", [view])
    for token in list(state["plans"]):
        invoke(host, "release_plan", [token])
