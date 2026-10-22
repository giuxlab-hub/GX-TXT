"""Execution-owned Native2D geometry with bounded typed transport."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_OPERATIONS = "raster_snapshot raster_save raster_restore raster_roi_set raster_roi_get raster_roi_remove raster_layer_get raster_layer_update raster_prepare raster_submit raster_freeze axis_presentation composition_parts composition_traversal part_direction part_direction_batch part_render part_marker_geometry part_marker_hit part_marker_place part_pick image_calibration_reset selection_definition spline_line_plan spline_span_to_line composition_create composition_part composition_split composition_explode path_vertices path_split path_join primitive_publish dataset_promote selection_pick selection_region selection_set_apply selection_set_restore selection_set_bounds image_attach image_get image_update image_calibrate image_map symmetry_preview symmetry_construct canvas_preview spline_tangent_get spline_tangent_edit fit_all fit_selected fit_bounds zoom pan scene_bounds world_to_device device_to_world pixel_tolerance construct_attached placement_points placement_preview reference_connected sketch_status sketch_component dimension_infer dimension_preview dimension_apply dimension_geometry relationship_state relationship_hit construct construct_preview from_fit controls reference reference_resolve reference_point_index control_definition control_edit constraint_options constraint_apply constraint_location polar_bulk compare_geometry geometry_role series_create series_get series_list series_members series_update series_transform series_bounds series_delete series_explode saved_view_create saved_view_get saved_view_list saved_view_update saved_view_restore saved_view_delete view_state view_state_rescale layer_create layer_get layer_list layer_update layer_delete layer_assign selection_set_create selection_set_get selection_set_list selection_set_update selection_set_add_member selection_set_remove_member selection_set_delete selection_set_activate identity fragment_create fragment_get fragment_list fragment_update fragment_delete fragment_sample fragment_length fragment_bounds fragment_materialize sketch sketch_update sketch_evaluate sketch_sample sketch_materialize sketch_explode curve from_source describe metrics measure path_point replace_points points_page nearest_vertex rescale_coordinates affine series group group_members group_add group_remove ungroup delete endpoint_frame bridge spline compare selection pivot grid polar view style direction export_resource restore_resource constraint_create constraint_join constraint_get constraint_list constraint_update constraint_enable constraint_delete checkpoint".split()
_ARGS = {"api_info": [], "open": ["document_id"], "close": ["scene"]}
_ARGS["path_validate"] = ["points", "topology"]
_ARGS.update({name: ["scene", "request"] for name in _OPERATIONS})
REGISTRATION = {
    "api_id": "NATIVE_2D_GEOMETRY_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "native2d_geometry",
    "documentation_ref": "docs/api/NATIVE_2D_GEOMETRY_API_v1.md",
    "operations": {name: {"name": name, "summary": "Scoped retained Native2D geometry: " + name,
                           "arguments": [{"name": arg, "kind": "opaque token" if arg == "scene" else "public value", "required": True} for arg in args],
                           "argument_convention": ", ".join(args), "result_contract": "opaque tokens or bounded typed public geometry",
                           "result_convention": "public geometry receipt"} for name, args in _ARGS.items()},
}


def _state(host):
    return host.handles.setdefault("native2d_geometry", {"scenes": set()})


def _array(host, raw):
    return NumericArray([float(value) for value in host.as_list(raw)])


def _matrix(host, raw):
    rows = [host.as_list(row) for row in host.as_list(raw)]
    if not rows:
        return NumericArray([], [0, 2])
    return NumericArray([float(row[column]) for column in range(2) for row in rows], [len(rows), 2])


def _axis_presentation(host, raw):
    result = {}
    for axis, settings in host.as_dict(raw).items():
        fields = host.as_dict(settings)
        if 'ticks' in fields:
            ticks = host.as_dict(fields['ticks'])
            if 'precision' in ticks:
                ticks['precision'] = int(ticks['precision'])
            if ticks.get('step', 'auto') != 'auto':
                ticks['step'] = float(ticks['step'])
            fields['ticks'] = ticks
        if 'context' in fields:
            context = host.as_dict(fields['context'])
            if 'image_id' in context:
                context['image_id'] = int(context['image_id'])
            fields['context'] = context
        result[axis] = fields
    return result


def _receipt(host, raw):
    result = host.as_dict(raw)
    series_parameters = "columns" in result and "rows" in result
    for key, value in list(result.items()):
        if key == "axis_presentation":
            result[key] = _axis_presentation(host, value)
        elif key == "coordinate_units":
            result[key] = host.as_list(value)
        elif key in {"coordinate_relations", "original_source_variable_schema"}:
            # Ordered axis meanings retain the Unit Registry's literal strings.
            # Decode structure only; this transport does not evaluate relations.
            result[key] = {axis: host.as_dict(fields)
                           for axis, fields in host.as_dict(value).items()}
        elif key == "coordinate_frame":
            frame = host.as_dict(value)
            result[key] = {"schema_version": int(frame["schema_version"]), "method": frame["method"],
                           **{name: host.as_list(frame[name]) for name in ("reference_units", "target_units", "output_units")},
                           **{name: _array(host, frame[name]) for name in ("reference_matrix", "target_matrix")}}
        elif key == "statistics":
            binding = host.modules["STATISTICAL_RESULT_SEMANTICS_API_v1"]
            result[key] = {name: binding.invoke(host, "validated_result", [record])
                           for name, record in host.as_dict(value).items()}
        elif key.endswith("_base64"):
            result[key] = value.decode("ascii") if isinstance(value, bytes) else str(value)
        elif key == "cells":
            result[key] = {k: host.as_list(v) for k,v in host.as_dict(value).items()}
        elif key == "attributes":
            result[key] = host.as_dict(value)
        elif key == "metadata" and result.get("api_id") == "INTERACTIVE_DOCUMENT_RESOURCE_API_v1":
            # Same opaque metadata representation as MANAGED_RESOURCE_API_v1.
            # A provenance origin record must never be decoded as an XY vector.
            result[key] = host.as_dict(value)
        elif key == "rois":
            result[key] = {name: _receipt(host, record) for name, record in host.as_dict(value).items()}
        elif key in {"roi", "source_snapshot", "ticket"}:
            result[key] = host.as_dict(value)
        elif key in {"native_direction", "direction", "part_ref", "image_state", "resource", "polar_frame", "parameters", "snapshot", "manifest_resource", "source_snapshot", "roi", "view_state", "style", "metrics", "metadata", "source_descriptor", "request", "source_rows_resource", "gap_resource", "fragment_descriptor", "geometry_metadata", "bridge_descriptor", "definition", "sketch_definition", "geometry_parameters", "sampling", "reference", "tail_reference", "member", "conversion", "quality", "provenance", "conversion_provenance", "source_request"}:
            result[key] = _receipt(host, value)
        elif key in {"start", "end"} and "bridge_kind" in result:
            result[key] = _receipt(host, value)
        elif key in {"first", "last"} and (result.get("method") == "uniform_parameter" or "fragment_token" in result):
            result[key] = float(value)
        elif key in {"width", "height"}:
            result[key] = int(float(value))
        elif key in {"part_id", "ordinal", "part_identity_counter", "knot_count", "index_start", "index_step", "knot", "parameter_count", "rank", "dof", "branch", "sample_budget", "count_a", "count_b", "revision", "topology_epoch", "epoch", "unit_power", "point_count", "point_index", "a_index", "b_index", "axis_index", "segment", "row_count", "display_budget", "start", "count", "first", "last", "size_bytes", "display_rows", "max_index", "max_source_index", "index", "control_count", "object_count", "columns", "positions", "total", "subdivisions", "major_interval", "radial_major_interval", "angular_major_interval", "order", "line_style", "marker", "interpolation", "layer", "traversal_contract", "curved_samples"}:
            result[key] = None if key == "part_id" and not value else int(value)
        elif key in {"effective_direction", "reversed", "original_dataset_modified", "source_modified", "repeat_endpoint", "materialization_verified", "calibrated", "explicit", "incoming", "connected", "periodic", "analysis_complete", "hit", "solved", "driven", "placed", "area_supported", "projection_exact_a", "projection_exact_b", "closest_exact", "normal_output", "geometry_modified", "parameter", "missing", "angular", "exact", "unit_declared", "disabled", "valid", "geometry_supported", "general_solver", "circular", "include_origin", "rotate_geometry", "finite_bounds", "copy", "found", "intersects_image", "physical_scale", "assumed_undeclared", "closed", "c0", "c1_start", "c1_end", "tangent_start", "tangent_end", "display_is_scientific_data", "visible", "locked", "selectable", "selected", "enabled", "snap_enabled", "major_visible", "minor_visible", "axes_visible", "clockwise", "degrees", "present", "forward", "base_selected"}:
            result[key] = bool(int(value))
        elif key == "origin" and "creation_kind" in host.as_list(value):
            result[key] = host.as_dict(value)
        elif key == "viewport":
            fields = host.as_list(value)
            result[key] = {name: float(fields[i]) for i, name in enumerate(("width", "height", "left", "top", "right", "bottom"))}
            result[key]["world"] = _array(host, fields[6])
        elif key in {"tail", "tip", "head_left", "head_right", "translation", "annotation", "label", "clipped_bounds", "hit_bounds", "closest_a", "closest_b", "point_a", "point_b", "anchor", "bounds", "point", "derivative", "origin", "start_derivative", "end_derivative", "major_color", "minor_color", "axes_color", "color", "pivot", "step_u", "step_v", "frame", "matrix", "affine_matrix"}:
            result[key] = _array(host, value)
        elif key == "lines":
            result[key] = [_matrix(host, item) for item in host.as_list(value)]
        elif key == "tangents":
            result[key] = [[int(host.as_list(item)[0]), _array(host, host.as_list(item)[1]), _array(host, host.as_list(item)[2])] for item in host.as_list(value)]
        elif key in {"points", "controls", "calibration"}:
            result[key] = _matrix(host, value)
        elif key in {"images", "inputs", "series_containers", "saved_views", "layers", "selection_sets", "members", "fragments", "constraints", "objects", "parts", "segments", "variables", "source_identities", "coordinate_conversions", "handles", "compatible_constraints", "constituents"}:
            result[key] = [_receipt(host, item) for item in host.as_list(value)]
        elif key in {"missing_refs", "source_tokens", "object_tokens", "operations", "host_operations"}:
            result[key] = host.as_list(value)
        elif key in {"row_indices", "source_rows", "nodes", "control_map"}:
            # Logical row identities stay exact integers, including uint64
            # values beyond IEEE double precision; never cast these to floats.
            result[key] = [int(item) for item in host.as_list(value)]
        elif key == "value" and ("constraint_token" in result or "unit_power" in result or "kind" in result):
            result[key] = float(value)
        elif key in {"maximum_knot_error", "scale", "calibrated_distance", "curvature_tolerance", "symmetric_rmse", "hausdorff_sampled", "length_difference", "area_difference", "closest_distance", "measured_value", "residual", "angular_residual", "angular_tolerance", "spacing_x", "spacing_y", "angle_step", "t", "radius_x", "radius_y", "rotation", "angle_start", "angle_sweep", "factor", "distance", "red", "green", "blue", "opacity", "line_width", "length", "span_x", "span_y", "signed_area", "area_pixels_squared", "length_span_ratio", "max_absolute", "mean_absolute", "rmse", "fraction", "offset_px", "length_px", "head_scale", "tolerance", "angle", "spacing_x", "spacing_y", "major_width", "minor_width", "axes_width", "theta_zero", "radius_min", "radius_max", "angle_min", "angle_span", "radial_spacing", "angular_spacing"}:
            result[key] = float(value)
        elif key == "rows" and series_parameters:
            result[key] = int(value)
        elif key == "rows":
            result[key] = []
            for item in host.as_list(value):
                row = host.as_list(item)
                result[key].append({"position": float(row[0]), "signed_residual": float(row[1]), "absolute_residual": float(row[2]),
                                    "reference": _array(host, row[3]), "derived": _array(host, row[4])})
    return result



def _request(value, key=None):
    # A 1x2 matrix is one XY control, not a scalar vector. The generic Tcl
    # transport intentionally flattens vectors, so this geometry boundary
    # preserves the explicit Nx2 contract even for one-point primitives.
    if isinstance(value, NumericArray) and key in {"controls", "points", "calibration", "polygon", "vertices"}:
        if len(value.shape) == 2 and value.shape[1] == 2:
            rows = value.shape[0]
            return [[value.values[r + rows*c] for c in range(2)] for r in range(rows)]
        if value.shape == [2]:
            return [value.values]
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Geometry controls/points require an Nx2 matrix")
    if isinstance(value, dict) and key == "viewport":
        return [value[name] for name in ("width", "height", "left", "top", "right", "bottom")] + [value["world"]]
    if isinstance(value, dict):
        return {name: _request(item, name) for name, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_request(item) for item in value]
    return value


def invoke(host, operation, args):
    if operation == "path_validate" and len(args) == 2:
        rows = args[0]
        if isinstance(rows, NumericArray):
            import numpy as np
            rows = np.asarray(rows.values).reshape(rows.shape, order="F").tolist()
        result = host.as_dict(host.call("::GX::native2DGeometryPathValidate", rows, args[1]))
        return {"length": float(result["length"]), "signed_area": float(result["signed_area"]), "closed": bool(int(result["closed"]))}
    if operation not in _ARGS or len(args) != len(_ARGS[operation]):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid Native2D geometry arguments")
    state = _state(host)
    if operation == "api_info":
        result = _receipt(host, host.call("::GX::native2DGeometryApiInfo"))
        result["raw_pointers"] = False;result["implicit_dataset_publication"] = False
        result["api_version"] = int(result["api_version"]);result["point_page_limit"] = int(result["point_page_limit"])
        return result
    if operation == "open":
        scene = str(host.call("::GX::native2DGeometryOpen", args[0]))
        state["scenes"].add(scene)
        return scene
    scene = args[0]
    if not isinstance(scene, str) or scene not in state["scenes"]:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Scene token is not owned by this execution")
    if operation == "close":
        host.call("::GX::native2DGeometryClose", scene);state["scenes"].remove(scene);return True
    request = args[1]
    if not isinstance(request, dict):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Geometry request must be a struct")
    # View/snapshot round trips include aspect. Preserve the default value but
    # reject indirect overrides too; only native/module hosts may choose auto.
    if operation == "view_state" and isinstance(request.get("view_state"), dict):
        if request["view_state"].get("aspect", "xy_equal") != "xy_equal":
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Native2D aspect overrides are host/module-only")
    if operation == "from_source" and request.get("source_token") not in host.handles.get("curve_source", {}).get("sources", set()):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Curve Source is not owned by this execution")
    if operation == "checkpoint":
        raw = host.call("::GX::native2DGeometryCheckpoint", scene, request)
        # The document service owns the payload; geometry resources remain
        # ordinary public reference dictionaries in that payload.
        result = host.as_dict(raw)
        return {"id": result["id"], "generation": result["generation"], "revision": int(result["revision"])}
    if operation == "primitive_publish":
        raw = host.call("::GX::_datasetPrivateWithModule", host.module_id, "::GX::native2DGeometryCall", scene, operation, _request(request))
    else:
        raw = host.call("::GX::native2DGeometryCall", scene, operation, _request(request))
    if operation in {"series_delete", "saved_view_delete", "layer_delete", "selection_set_delete", "fragment_delete", "constraint_delete", "delete", "ungroup", "group_add", "group_remove"}:
        return bool(int(raw))
    if operation == "view":
        # Existing native view contract is a six-number frame plus world bounds.
        value = host.as_list(raw)
        return {"frame": NumericArray([float(item) for item in value[:6]]), "world": _array(host, value[6])}
    if operation == "part_marker_geometry":
        return {"geometry": _receipt(host, host.as_dict(raw)["geometry"])}
    return _receipt(host, raw)


def cleanup(host):
    for scene in list(_state(host)["scenes"]):
        invoke(host, "close", [scene])
