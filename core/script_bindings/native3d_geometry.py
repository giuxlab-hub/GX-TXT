"""Execution-owned opaque Native3D geometry on the public CORE authority."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_ARGS = {"api_info": [], "open": ["document_id"], "close": ["scene"], "scene_info": ["scene"],
         "convert_axes": ["scene", "object_token", "source_units", "target_unit"],
         "import_dataset": ["scene", "dataset_id", "working_unit", "assumed_input_unit"],
         "profile_from_sources": ["scene", "sources", "plane", "tolerance"],
         "profile_resources": ["scene", "profile_token"],
         "profile_view_resource": ["scene", "profile_token"],
         "export_resource": ["scene", "object_token", "format", "millimeters_per_working_unit", "placement"]}
for _operation in ("logical_id", "plane_frame", "indexed_mesh", "polydata", "masked_surface", "sweep", "project", "projection_profile", "load_scientific", "extrude", "box", "cylinder", "boolean", "duplicate", "mesh",
                   "describe", "compare_geometry", "compare_sections", "geometry_role", "anchor_describe", "delete", "transform", "profile_delete", "translate", "rotate",
                   "scale", "rescale_coordinates", "reset_transform", "clean", "weld", "orient", "heal", "clip", "profile_rescale", "section_profile",
                   "clip_cap", "self_intersections", "mesh_append", "mesh_merge", "mesh_stitch", "mesh_bridge", "mesh_heal_seam", "mesh_lod", "mesh_boundaries", "mesh_intersection_pairs", "group_copy", "group_duplicate", "group_delete", "measure", "align_three_points", "constraint_solve"):
    _ARGS[_operation] = ["scene", "request"]
for _family in ("selection_set", "layer", "saved_view"):
    for _action in ("create", "get", "list", "update", "delete"):
        _ARGS[_family+"_"+_action] = ["scene", "request"]
for _operation in ("selection_set_activate", "selection_set_apply", "layer_assign", "saved_view_restore"):
    _ARGS[_operation] = ["scene", "request"]
REGISTRATION = {
    "api_id": "NATIVE_3D_GEOMETRY_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "native3d_geometry",
    "documentation_ref": "docs/api/NATIVE_3D_GEOMETRY_API_v1.md",
    "operations": {name: {"name": name, "summary": "Scoped retained Native3D geometry: " + name,
                           "arguments": [{"name": arg, "kind": "opaque token" if arg == "scene" else "public value", "required": True} for arg in args],
                           "argument_convention": ", ".join(args),
                           "result_contract": "opaque scene/object/profile or bounded scientific descriptor",
                           "result_convention": "typed public geometry receipt"} for name, args in _ARGS.items()},
}


def _state(host):
    return host.handles.setdefault("native3d_geometry", {"scenes": set(), "objects": {}, "profiles": {}, "groups": {}, "group_members": {}})


def _receipt(host, raw):
    result = host.as_dict(raw)
    if "statistics" in result:
        binding = host.modules["STATISTICAL_RESULT_SEMANTICS_API_v1"]
        result["statistics"] = {name: binding.invoke(host, "validated_result", [record])
                                for name, record in host.as_dict(result["statistics"]).items()}
    for field in ("volume", "surface_area", "value", "maximum_residual", "reference_rms", "reference_mean", "reference_max", "symmetric_rms", "hausdorff_sampled", "closest_sampled", "area_difference", "volume_difference", "distance", "rmse", "symmetric_rmse", "closest_distance", "length_difference", "max_absolute", "mean_absolute", "position", "signed_residual", "tolerance"):
        if field in result:
            result[field] = float(result[field])
    for field in ("logical_id", "cell_count", "array_count", "input_points", "contour_count", "solids", "boundary_edges", "nonmanifold_edges",
                  "orientation_conflicts", "components", "edge_count", "loop_count", "intersecting_pairs", "constraint_status", "satisfied_count", "reference_vertices", "target_vertices", "reference_samples", "target_samples", "direction", "source_vertex", "sample_index", "count_a", "count_b", "sample_budget", "size_bytes", "point_count"):
        if field in result:
            result[field] = int(result[field])
    for field in ("closed", "topology_valid", "volume_defined", "unit_known", "has_normal", "has_tangent", "edges_truncated", "loops_truncated", "truncated", "reference_tessellated", "target_tessellated", "area_supported", "closest_exact", "projection_exact_a", "projection_exact_b"):
        if field in result:
            result[field] = bool(int(result[field]))
    for field in ("origin", "u_axis", "v_axis", "transform", "world_transform", "bounds_min", "bounds_max", "world_point", "normal", "tangent", "source", "projected", "closest_source", "closest_target", "bounds_min_difference", "bounds_max_difference", "closest_a", "closest_b"):
        if field in result:
            result[field] = NumericArray([float(x) for x in host.as_list(result[field])])
    for field in ("captured_plane", "plane"):
        if field in result:
            value = host.as_dict(result[field])
            result[field] = {key: NumericArray([float(x) for x in host.as_list(item)]) for key, item in value.items()}
    if "coordinate_conversion" in result:
        conversion = host.as_dict(result["coordinate_conversion"])
        conversion["factors"] = NumericArray([float(x) for x in host.as_list(conversion["factors"])])
        conversion["source_units"] = host.as_list(conversion["source_units"])
        result["coordinate_conversion"] = conversion
    if "points" in result:
        result["points"] = [NumericArray([float(x) for x in host.as_list(p)]) for p in host.as_list(result["points"])]
    if "source_bindings" in result:
        bindings = []
        for raw_binding in host.as_list(result["source_bindings"]):
            binding = host.as_dict(raw_binding)
            for field in ("xy_resource", "gap_resource", "source_rows_resource"):
                reference = host.as_dict(binding[field]);reference["metadata"] = host.as_dict(reference["metadata"])
                reference["size_bytes"] = int(reference["size_bytes"]);binding[field] = reference
            descriptor = host.as_dict(binding["source_descriptor"])
            for field in ("row_count", "display_budget"):
                descriptor[field] = int(descriptor[field])
            for field in ("variables", "source_identities"):
                descriptor[field] = [host.as_dict(item) for item in host.as_list(descriptor[field])]
            descriptor["request"] = host.as_dict(descriptor["request"])
            binding["source_descriptor"] = descriptor;bindings.append(binding)
        result["source_bindings"] = bindings
    if "members" in result:
        result["members"] = [_receipt(host, item) for item in host.as_list(result["members"])]
    if "selected_members" in result:
        result["selected_members"] = [_receipt(host, item) for item in host.as_list(result["selected_members"])]
    if "rows" in result: result["rows"] = [_receipt(host,item) for item in host.as_list(result["rows"])]
    for field in ("section_resources", "contours"):
        if field in result: result[field] = [_receipt(host,item) for item in host.as_list(result[field])]
    for field in ("xy_resource", "metadata"):
        if field in result:
            # Resource metadata belongs to the managed-resource contract. Its
            # origin is a provenance record, not a geometric XYZ origin vector.
            result[field] = (host.as_dict(result[field]) if field == "metadata" and
                             result.get("api_id") == "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"
                             else _receipt(host, result[field]))
    if "tessellation" in result: result["tessellation"] = host.as_dict(result["tessellation"])
    for field in ("member_states",):
        if field in result: result[field] = host.as_list(result[field])
    for field in ("visibility", "view"):
        if field in result: result[field] = host.as_dict(result[field])
    for field in ("selected_members",):
        if field in result: result[field] = [_receipt(host,item) for item in host.as_list(result[field])]
    for field in ("visible", "selectable", "locked"):
        if field in result: result[field] = bool(int(result[field]))
    if "opacity" in result: result["opacity"] = float(result["opacity"])
    if "edges" in result:
        result["edges"] = [[int(index) for index in host.as_list(pair)] for pair in host.as_list(result["edges"])]
    if "loops" in result:
        loops = []
        for raw_loop in host.as_list(result["loops"]):
            loop = host.as_dict(raw_loop)
            for field in ("loop_index", "vertex_count"):
                loop[field] = int(loop[field])
            loop["truncated"] = bool(int(loop["truncated"]))
            loop["source_indices"] = [int(index) for index in host.as_list(loop["source_indices"])]
            loop["world_points"] = [NumericArray([float(x) for x in host.as_list(point)]) for point in host.as_list(loop["world_points"])]
            loops.append(loop)
        result["loops"] = loops
    if "pairs" in result:
        pairs = []
        for raw_pair in host.as_list(result["pairs"]):
            pair = host.as_dict(raw_pair)
            for field in ("triangle_a", "triangle_b"):
                pair[field] = int(pair[field])
            pair["witness"] = NumericArray([float(x) for x in host.as_list(pair["witness"])])
            pairs.append(pair)
        result["pairs"] = pairs
    if "dataset_binding" in result:
        binding = host.as_dict(result["dataset_binding"])
        binding["coordinate_factor"] = float(binding["coordinate_factor"])
        binding["assumed_input_unit"] = bool(int(binding["assumed_input_unit"]))
        reference = host.as_dict(binding["source_resource"])
        reference["size_bytes"] = int(reference["size_bytes"])
        reference["metadata"] = host.as_dict(reference["metadata"])
        binding["source_resource"] = reference
        result["dataset_binding"] = binding
    return result


def invoke(host, operation, args):
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid Native3D geometry arguments")
    state = _state(host)
    if operation == "api_info":
        result = host.as_dict(host.call("::GX::native3DGeometryApiInfo"))
        for field in ("operations", "geometry_operations"):
            result[field] = host.as_list(result[field])
        result["raw_pointers"] = False;result["implicit_dataset_publication"] = False
        return result
    if operation == "open":
        token = str(host.call("::GX::native3DGeometryOpen", args[0]));state["scenes"].add(token);return token
    scene = args[0]
    if scene not in state["scenes"]:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Scene token is not owned by this script execution")
    if operation == "scene_info":
        result = host.as_dict(host.call("::GX::native3DGeometrySceneInfo", scene))
        result["revision"] = int(result["revision"]);result["worker_generation"] = int(result["worker_generation"])
        # Session lifetime is an authority-side guard, not a reusable script
        # credential or native-scene number.
        result.pop("session_token", None)
        return result
    if operation == "close":
        host.call("::GX::native3DGeometryClose", scene);state["scenes"].remove(scene)
        for collection in ("objects", "profiles", "groups"):
            for token, owner in list(state[collection].items()):
                if owner == scene:
                    del state[collection][token]
                    if collection == "groups":
                        state["group_members"].pop(token, None)
        return True
    if operation == "export_resource":
        if state["objects"].get(args[1]) != scene:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Object token is not owned by this scene/execution")
        result = host.as_dict(host.call("::GX::native3DGeometryExportResource", *args))
        result["size_bytes"] = int(result["size_bytes"])
        result["metadata"] = host.as_dict(result["metadata"])
        for field in ("bounds_min", "bounds_max", "transform"):
            if field in result["metadata"]:
                result["metadata"][field] = NumericArray([float(x) for x in host.as_list(result["metadata"][field])])
        return result
    if operation in ("profile_resources", "profile_view_resource"):
        if state["profiles"].get(args[1]) != scene:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Profile token is not owned by this scene/execution")
        command = "::GX::native3DGeometryProfileResources" if operation == "profile_resources" else "::GX::native3DGeometryProfileViewResource"
        if operation == "profile_view_resource":
            result = host.as_dict(host.call(command, *args));result["size_bytes"] = int(result["size_bytes"]);result["metadata"] = host.as_dict(result["metadata"])
            return result
        result = _receipt(host, host.call(command, *args))
        contours = []
        for item in host.as_list(result["contours"]):
            contour = host.as_dict(item);contour["closed"] = bool(int(contour["closed"]))
            reference = host.as_dict(contour["xy_resource"]);reference["metadata"] = host.as_dict(reference["metadata"]);reference["size_bytes"] = int(reference["size_bytes"])
            contour["xy_resource"] = reference;contours.append(contour)
        result["contours"] = contours
        return result
    if operation == "convert_axes":
        if state["objects"].get(args[1]) != scene:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Object token is not owned by this scene/execution")
        raw = host.call("::GX::native3DGeometryConvertAxes", *args)
    elif operation == "import_dataset":
        raw = host.call("::GX::native3DGeometryImportDataset", *args)
    elif operation == "profile_from_sources":
        sources = args[1]
        if not isinstance(sources, (list, tuple)) or not isinstance(args[2], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Source profiles require source structs and an explicit plane")
        owned_sources = host.handles.get("curve_source", {}).get("sources", set())
        for source in sources:
            if not isinstance(source, dict) or source.get("source_token") not in owned_sources:
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Profile source is not owned by this execution")
        raw = host.call("::GX::native3DGeometryProfileFromSources", *args)
    else:
        request = args[1]
        if not isinstance(request, dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Geometry request must be a struct")
        def validate_references(value, depth=0):
            if depth > 16:
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Geometry request is too deeply nested")
            if isinstance(value, dict):
                for field, item in value.items():
                    if field in ("object_token", "surface_object_token", "base", "tool", "profile_token", "group_token"):
                        collection = "profiles" if field == "profile_token" else "groups" if field == "group_token" else "objects"
                        if state[collection].get(item) != scene:
                            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Nested geometry reference is not owned by this scene/execution")
                    else:
                        validate_references(item, depth+1)
            elif isinstance(value, (list, tuple)):
                for item in value:
                    validate_references(item, depth+1)
        validate_references(request)
        for token in request.get("object_tokens", []):
            if state["objects"].get(token) != scene:
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Grouped object is not owned by this scene/execution")
        for field in ("object_token", "base", "tool", "profile_token", "group_token"):
            if field in request:
                collection = "profiles" if field == "profile_token" else "groups" if field == "group_token" else "objects"
                if state[collection].get(request[field]) != scene:
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Geometry token is not owned by this scene/execution")
        raw = host.call("::GX::native3DGeometryCall", scene, operation, request)
        if operation in ("delete", "profile_delete", "group_delete"):
            collection = "profiles" if operation == "profile_delete" else "groups" if operation == "group_delete" else "objects"
            token = request[{"profiles": "profile_token", "groups": "group_token", "objects": "object_token"}[collection]]
            del state[collection][token]
            if collection == "groups":
                for member in state["group_members"].pop(token, []):
                    state["objects"].pop(member, None)
            return True
    if operation in ("selection_set_list", "layer_list", "saved_view_list"):
        return [_receipt(host,item) for item in host.as_list(raw)]
    result = _receipt(host, raw)
    for field, collection in (("object_token", "objects"), ("profile_token", "profiles"), ("group_token", "groups")):
        if field in result:
            state[collection][result[field]] = scene
    if "group_token" in result:
        members = [item["object_token"] for item in result["members"]]
        state["group_members"][result["group_token"]] = members
        for member in members:
            state["objects"][member] = scene
    return result


def cleanup(host):
    for scene in list(_state(host)["scenes"]):
        invoke(host, "close", [scene])
