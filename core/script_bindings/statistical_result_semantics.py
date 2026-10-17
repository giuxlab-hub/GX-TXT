"""Thin both-language binding to the in-process CORE statistical authority."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray, ResourceNumericArray
from contextlib import ExitStack
import math
import os

_ARGS = {"profile_eligibility": ["model_id", "operation", "context"], "profile_settings": ["settings"], "profile_plan": ["source", "settings"], "profile_interpretation": ["source", "numeric"], "profile_report": ["meaning"], "digitization_interpretation": ["summary", "context"], "digitization_fit_plan": ["meaning", "kind", "orientation"], "digitization_report": ["meaning"], "gls_interpretation": ["numeric", "context"], "gls_report": ["result"], "api_info": [], "models": [], "model": ["model_id"],
         "fit_suggestions": ["numeric", "candidates", "context", "entries", "criterion"],
         "fit_suggestions_report": ["result"],
         "physical_plausibility": ["source", "rules", "context"],
         "physical_plausibility_report": ["result"],
         "derived_properties_plan": ["source", "definitions"],
         "derived_properties_interpretation": ["source", "numeric"],
         "derived_properties_report": ["source", "numeric"],
         "residual_sequence_interpretation": ["numeric", "context"],
         "nested_f_plan": ["reduced", "full"],
         "nested_f_interpretation": ["reduced", "full", "numeric"],
         "bootstrap_settings": ["settings"],
         "bootstrap_plan": ["source", "settings"],
         "bootstrap_interpretation": ["source", "numeric"],
         "influence_plan": ["source"],
         "influence_interpretation": ["source", "numeric"],
         "log_response_plan": ["source"],
         "log_response_interpretation": ["source", "numeric", "prediction"],
         "model_selection_plan": ["result", "binding"],
         "model_comparison": ["entries", "criterion"],
         "store_columns": ["document_id", "prototype", "columns"],
         "bind_resource_columns": ["prototype", "resource", "column_variables", "row_count", "row_start"],
         "resource_binding_table": ["result", "start", "count"],
         "resource_field_elements": ["result", "field", "start", "count"],
         "bind_columns": ["prototype", "column_variables", "row_count", "row_start"],
         "binding_table": ["dataset_id", "record_name", "start", "count"],
         "from_native_comparison": ["method", "receipt", "context", "provenance"],
         "validated_result": ["result"],
         "quantities": [], "interpret": ["request"], "interpret_table": ["request"],
         "numeric_data_fields": ["result"], "numeric_field_map": ["operation"], "numeric_fields": ["result"],
         "numeric_model": ["operation", "facts"], "numeric_field_elements": ["result", "field"],
         "from_numeric_table": ["model_id", "operation", "rows", "context", "provenance"],
         "from_numeric_columns": ["model_id", "operation", "row_ids", "raw_columns", "common_raw", "context", "provenance"],
         "table_csv_rows": ["result", "mapping", "row_ids"],
         "table_rows": ["result", "mapping", "row_ids"], "table_select": ["result", "row_ids"], "table_values": ["result", "quantities"], "table_report": ["result", "row_ids", "quantities"], "validate": ["result"],
         "solver_report": ["result", "details"], "report": ["result", "quantities"], "parameter_report": ["result"], "feature": ["result", "quantity"],
         "publication_metadata": ["named_results"],
         "parameter_inference_plan": ["result", "confidence"],
         "parameter_rows": ["result"], "parameter_ini_report": ["result"], "parameter_correlation_report": ["result"],
         "ini_report": ["result", "mapping"],
         "scalar_rows": ["result", "mapping"],
         "prediction_inference_plan": ["result", "kind", "confidence"],
         "prediction_interpretation": ["source", "numeric"],
         "with_parameter_uncertainty": ["result", "confidence", "numeric"],
         "from_numeric": ["model_id", "operation", "numeric_result", "context", "metrics", "provenance"]}
REGISTRATION = {
    "api_id": "STATISTICAL_RESULT_SEMANTICS_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "statistical_result_semantics",
    "documentation_ref": "docs/api/STATISTICAL_RESULT_SEMANTICS_API_v1.md",
    "capabilities": ["profile_likelihood", "residual_sequence", "nested_f_tests", "bootstrap_refits", "logarithmic_response", "model_comparison", "model_catalog", "residual_semantics", "parameter_identity", "interpretation", "validated_reporting", "compact_statistical_tables", "numeric_field_interpretation", "dataset_column_bindings", "managed_resource_column_bindings", "validated_csv_presentation", "numeric_data_contracts"],
    "operations": {name: {"name": name, "summary": "CORE statistical result " + name,
        "arguments": [{"name": arg, "kind": "public value", "required": not (name == "nested_f_interpretation" and arg == "numeric" or name == "bootstrap_plan" and arg == "settings" or name == "log_response_interpretation" and arg == "prediction" or name in ("bind_columns", "bind_resource_columns") and arg == "row_start" or name == "numeric_model" and arg == "facts" or name in ("table_rows", "table_csv_rows") and arg == "row_ids" or name == "solver_report" and arg == "details" or name == "report" and arg == "quantities" or name == "from_numeric" and arg in ("metrics", "provenance") or name in ("from_numeric_table", "from_numeric_columns") and arg == "provenance" or name == "prediction_inference_plan" and arg in ("kind", "confidence") or name == "parameter_inference_plan" and arg == "confidence" or name == "with_parameter_uncertainty" and arg == "numeric")} for arg in args],
        "argument_convention": ", ".join(args),
        "result_contract": "Versioned public scientific meaning; no numerical recomputation",
        "unit_behavior": "Explicit physical residual and parameter units"}
        for name, args in _ARGS.items()},
}


def _profile_result(host, raw):
    """Transport only: preserve the public CORE's typed bounded profile records."""
    result = host.as_dict(raw)
    integers = {'api_version', 'max_refits', 'original_fit_count', 'n', 'p', 'free_parameter_count', 'parameter_index', 'workspace_bytes_max', 'work_units_max', 'attempted_count', 'successful_count', 'failed_count', 'workspace_bytes_bound', 'baseline_improved'}
    numbers = {'confidence', 'search_lower', 'search_upper', 'initial_step', 'parameter_tolerance', 'max_seconds', 'baseline_sse', 'estimate', 'threshold', 'elapsed_seconds', 'value', 'searched_value', 'likelihood_ratio', 'bracket_inside', 'bracket_outside'}
    for key, value in result.items():
        if key in integers:
            result[key] = int(float(value))
        elif key in numbers:
            result[key] = float(value)
        elif key in ('parameter_ids', 'parameter_units', 'parameter_roles', 'assumptions'):
            result[key] = [_bootstrap_text(host, v) for v in host.as_list(value)]
        elif key == 'source_parameters':
            result[key] = _numeric(host, key, value)
        elif key in ('settings', 'plan', 'interval', 'lower', 'upper'):
            result[key] = _profile_result(host, value)
        elif key == 'solver_policy':
            result[key] = _solver_receipt(host, value)
        elif key == 'observation_signature':
            result[key] = _bootstrap_signature(host, value)
        elif key == 'request':
            request = host.as_dict(value)
            result[key] = {'source_request': _request(host, request['source_request']), 'numeric': _profile_result(host, request['numeric'])}
        else:
            result[key] = _bootstrap_text(host, value)
    return result


def _digitization_result(host, raw):
    text=lambda value:str(host.tcl.call('format','%s%s',value,''))
    result=host.as_dict(raw)
    for key in set(result)-{'api_version','assumptions','summary','context','columns'}:result[key]=text(result[key])
    result['api_version']=int(result['api_version'])
    result['assumptions']=[text(v) for v in host.as_list(result['assumptions'])]
    if 'summary' in result:
        summary=host.as_dict(result['summary'])
        integers={'point_count','calibration_input_count'};booleans={'has_shared_calibration','has_xy_correlation'};floats={'maximum_absolute_xy_correlation','correlation_roundoff_tolerance'}
        for key in set(summary)-integers-booleans-floats-{'coordinate_units'}:summary[key]=text(summary[key])
        for key in integers:summary[key]=int(float(summary[key]))
        for key in booleans:summary[key]=bool(int(summary[key]))
        for key in floats:summary[key]=float(summary[key])
        summary['coordinate_units']=[text(v) for v in host.as_list(summary['coordinate_units'])]
        result['summary']=summary;result['context']={key:text(value) for key,value in host.as_dict(result['context']).items()}
        result['columns']={key:{field:text(value) for field,value in host.as_dict(column).items()} for key,column in host.as_dict(result['columns']).items()}
    return result


def _log_context(host, raw):
    result = host.as_dict(raw)
    result['reference'] = float(result['reference'])
    result['inverse_eligible'] = bool(int(result['inverse_eligible']))
    return result


_INFLUENCE_FIELDS = ('schema method n p rank dof input_count weight_semantics scale_method residual_scale near_one_tolerance leverage_roundoff_count deletion_available_count scaled_available_count maximum_leverage leverage_sum maximum_cook_distance leverage_review_threshold cook_review_threshold high_leverage_count high_cook_count row_identity factorization_reused fit_count block_rows').split()


def _influence_plan(host, raw):
    result = host.as_dict(raw)
    for key in ('api_id', 'status', 'reason', 'response_unit', 'coordinate_space', 'weight_semantics'):
        result[key] = str(host.tcl.call('format', '%s', result[key]))
    for key in ('api_version', 'n', 'p', 'rank', 'dof'):
        result[key] = int(float(result[key])) if str(result[key]) else ''
    result['assumptions'] = [str(host.tcl.call('format', '%s', v)) for v in host.as_list(result['assumptions'])]
    return result


def _influence_interpretation(host, raw):
    result = host.as_dict(raw)
    for key in ('api_version', 'row_count'): result[key] = int(float(result[key]))
    result['plan'] = _influence_plan(host, result['plan'])
    result['columns'] = {key: {field: str(host.tcl.call('format', '%s', value)) for field, value in host.as_dict(column).items()} for key, column in host.as_dict(result['columns']).items()}
    result['assumptions'] = [str(host.tcl.call('format', '%s', v)) for v in host.as_list(result['assumptions'])]
    request = host.as_dict(result['request'])
    request['source_request'] = _request(host, request['source_request'])
    facts = host.as_dict(request['numeric'])
    for key in ('schema', 'method', 'weight_semantics', 'scale_method', 'row_identity'):
        facts[key] = str(host.tcl.call('format', '%s', facts[key]))
    for key in ('n', 'p', 'rank', 'dof', 'input_count', 'leverage_roundoff_count', 'deletion_available_count', 'scaled_available_count', 'high_leverage_count', 'high_cook_count', 'fit_count', 'block_rows'):
        facts[key] = int(float(facts[key]))
    for key in ('residual_scale', 'near_one_tolerance', 'maximum_leverage', 'leverage_sum', 'maximum_cook_distance', 'leverage_review_threshold', 'cook_review_threshold'):
        facts[key] = float(facts[key])
    facts['factorization_reused'] = bool(int(facts['factorization_reused']))
    request['numeric'] = facts;result['request'] = request
    return result


def _log_plan(host, raw):
    result = host.as_dict(raw)
    result['api_version'] = int(result['api_version'])
    result['reference'] = float(result['reference'])
    result['transform'] = _log_context(host, result['transform'])
    result['log_standard_deviation'] = float(result['log_standard_deviation']) if str(result['log_standard_deviation']) else ''
    result['assumptions'] = [str(v) for v in host.as_list(result['assumptions'])]
    return result


def _log_interpretation(host, raw):
    result = host.as_dict(raw)
    for key in ('api_version', 'row_count', 'interval_available_count'): result[key] = int(float(result[key]))
    result['confidence'] = float(result['confidence']) if str(result['confidence']) else ''
    result['plan'] = _log_plan(host, result['plan'])
    result['columns'] = {key: host.as_dict(value) for key, value in host.as_dict(result['columns']).items()}
    result['assumptions'] = [str(v) for v in host.as_list(result['assumptions'])]
    request = host.as_dict(result['request'])
    request['source_request'] = _request(host, request['source_request'])
    request['prediction_request'] = _request(host, request['prediction_request']) if str(request['prediction_request']) else ''
    facts = host.as_dict(request['numeric'])
    for key in ('n', 'interval_available_count'): facts[key] = int(float(facts[key]))
    for key in ('reference', 'log_standard_deviation', 'log_bias_correction', 'confidence'):
        facts[key] = float(facts[key]) if str(facts[key]) else ''
    facts['mean_available'] = bool(int(facts['mean_available']))
    request['numeric'] = facts;result['request'] = request
    return result


def _model(host, raw):
    result = host.as_dict(raw)
    result["parameter_ids"] = host.as_list(result["parameter_ids"])
    return result


def _numeric(host, key, raw):
    if key in ("covariance", "output_covariance", "source_covariance", "parameter_correlation", "cluster_centers", "sample_covariance_real", "sample_covariance_imaginary"):
        rows = [host.as_list(row) for row in host.as_list(raw)]
        width = len(rows[0]) if rows else 0
        return NumericArray([float(rows[r][c]) for c in range(width) for r in range(len(rows))], [len(rows), width])
    if key in ("foundation_coefficients", "foundation_coefficient_real", "foundation_coefficient_imaginary", "cluster_populations", "cluster_within_ss", "sample_covariance_eigenvalues_real", "sample_covariance_eigenvalues_imaginary", "standard_errors", "output_standard_uncertainties", "source_parameters", "lower", "upper", "quantiles", "quantile_probabilities", "signal_harmonic_bin_powers", "harmonic_orders"):
        return NumericArray([float(x) for x in host.as_list(raw)])
    if key == "converged":
        return bool(int(raw))
    return float(raw)


def _parameters(host, raw):
    result = []
    for item in host.as_list(raw):
        item = host.as_dict(item)
        if "value" in item:
            item["value"] = float(item["value"])
        result.append(item)
    return result


def _complex_summary(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in ("parameter_ids", "parameter_units", "channel_ids", "channel_units", "component_ids", "component_units"):
            result[key] = [str(host.tcl.call("format", "%s", item)) for item in host.as_list(value)]
        elif key in ("observation_rows", "response_count", "residual_component_count"):
            result[key] = int(value)
        else:
            result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _implicit_summary(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in ("parameter_ids", "parameter_units", "predictor_ids", "predictor_units"):
            result[key] = [str(host.tcl.call("format", "%s", item)) for item in host.as_list(value)]
        elif key == "observation_count": result[key] = int(value)
        elif key in ("measurement_error_distance", "normalization_is_measurement_sigma"):
            result[key] = bool(int(value))
        elif key == "normalization":
            normalization = host.as_dict(value)
            result[key] = {"value": float(normalization["value"]), "unit": str(host.tcl.call("format", "%s", normalization["unit"])), "role": str(host.tcl.call("format", "%s", normalization["role"]))}
        else: result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _rational_summary(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in ("parameter_ids", "parameter_units"):
            result[key] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(value)]
        elif key == "evaluation_count": result[key] = int(float(value))
        elif key in ("evaluation_domain", "observation_domain"): result[key] = NumericArray([float(v) for v in host.as_list(value)], [1, 2])
        elif key == "domain_receipt":
            receipt = host.as_dict(value)
            for field, item in list(receipt.items()):
                if field in ("numerator_degree", "denominator_degree", "interval_nodes"): receipt[field] = int(item)
                elif field == "possible_common_factor": receipt[field] = bool(int(item))
                elif field in ("denominator_constant", "denominator_coefficient_bound", "relative_margin_lower_bound", "pole_tolerance"): receipt[field] = float(item)
                elif field in ("domain", "denominator_coefficients_descending", "parameters"):
                    vals = [float(v) for v in host.as_list(item)]
                    receipt[field] = NumericArray(vals, [1, len(vals)])
                elif field == "poles_real_imag":
                    rows = host.as_list(item)
                    vals = [float(host.as_list(row)[col]) for col in range(2) for row in rows]
                    receipt[field] = NumericArray(vals, [len(rows), 2])
                else: receipt[field] = str(host.tcl.call("format", "%s", item))
            result[key] = receipt
        else: result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _surface_summary(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in ("parameter_ids", "parameter_units", "predictor_ids", "predictor_units"):
            result[key] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(value)]
        elif key == "interpolation_performed": result[key] = bool(int(value))
        elif key == "observation_receipt":
            receipt = host.as_dict(value)
            for field, item in list(receipt.items()):
                if field in ("original_count", "retained_count", "nonfinite_count", "source_linear_index_base"): receipt[field] = int(item)
                elif field in ("sorting_performed", "interpolation_performed"): receipt[field] = bool(int(item))
                elif field == "original_shape": receipt[field] = NumericArray([int(v) for v in host.as_list(item)], [1, 2])
                else: receipt[field] = str(host.tcl.call("format", "%s", item))
            result[key] = receipt
        elif key == "observation_domain":
            domain = host.as_dict(value)
            result[key] = {"bounds": _numeric(host, "covariance", domain["bounds"]),
                           "meaning": str(host.tcl.call("format", "%s", domain["meaning"]))}
        else: result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _knot_summary(host, raw):
    result = host.as_dict(raw)
    for key, value in list(result.items()):
        if key in ("degree", "continuity_order", "knot_count", "source_count", "basis_dimension"): result[key] = int(float(value))
        elif key == "domain": result[key] = NumericArray([float(v) for v in host.as_list(value)], [1, 2])
        else: result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _context(host, raw):
    result = host.as_dict(raw)
    if "gls" in result: result["gls"] = _gls_result(host, result["gls"])
    if "complex" in result: result["complex"] = _complex_summary(host, result["complex"])
    if "implicit" in result: result["implicit"] = _implicit_summary(host, result["implicit"])
    if "knot_spline" in result: result["knot_spline"] = _knot_summary(host, result["knot_spline"])
    if "rational" in result: result["rational"] = _rational_summary(host, result["rational"])
    if "surface" in result: result["surface"] = _surface_summary(host, result["surface"])
    if "conditional_parameter_units" in result:
        receipt = {key: str(host.tcl.call("format", "%s", value))
                   for key, value in host.as_dict(result["conditional_parameter_units"]).items()}
        for key in ("exponent_value", "reference_magnitude"):
            if key in receipt:
                receipt[key] = float(receipt[key])
        result["conditional_parameter_units"] = receipt
    if "response_transform" in result:
        result["response_transform"] = _log_context(host, result["response_transform"])
    if "smoothing" in result:
        facts=host.as_dict(result["smoothing"])
        facts["bindings"]=[{k:str(host.tcl.call("format", "%s", v)) for k,v in host.as_dict(b).items()} for b in host.as_list(facts["bindings"])]
        result["smoothing"]=facts
    if "baseline_correction" in result:
        result["baseline_correction"] = {key: str(host.tcl.call("format", "%s", value)) for key, value in host.as_dict(result["baseline_correction"]).items()}
    if "regional_fit" in result:
        facts = host.as_dict(result["regional_fit"])
        for key in ("region_counts", "breakpoint_values", "breakpoint_fixed", "sample_coincidence_counts"):
            facts[key] = NumericArray([float(v) for v in host.as_list(facts[key])])
        for key in ("breakpoint_ids", "continuity"):
            facts[key] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(facts[key])]
        facts["schema"] = str(host.tcl.call("format", "%s", facts["schema"]))
        result["regional_fit"] = facts
    for key in ("has_intercept", "exclude_dc", "signal_zero", "noise_zero", "peak_resolved"):
        if key in result:
            result[key] = bool(int(result[key]))
    for key in ("group_index", "output_index"):
        if key in result:
            result[key] = int(float(result[key]))
    for key in ("cluster_ids", "output_ids", "output_units"):
        if key in result:
            result[key] = [str(host.tcl.call("format", "%s", value)) for value in host.as_list(result[key])]
    for key in ("confidence", "reference_rms", "sample_rate", "fundamental_hz", "fundamental_bin"):
        if key in result:
            result[key] = float(result[key])
    if "assumptions" in result:
        result["assumptions"] = host.as_list(result["assumptions"])
    # A captured translation is opaque public provenance, never evaluated here.
    # The scalar Tcl dictionary is preserved losslessly through both languages.
    return result


def _solver_receipt(host, raw):
    result = host.as_dict(raw)
    vectors = ("initial_parameters", "parameter_scales", "lower_bounds", "upper_bounds", "fixed_mask")
    numbers = ("iterations", "function_evaluations", "jacobian_evaluations", "callback_evaluations", "max_function_evaluations", "exitflag", "solver_seconds", "solver_objective", "threads_used", "function_tolerance", "gradient_tolerance", "parameter_tolerance", "max_iterations", "max_seconds", "loss_scale")
    for key, value in result.items():
        if key == "multistart":
            result[key] = _multistart_receipt(host, value)
        elif key == "orthogonal_xy":
            result[key] = {str(name): (int(float(item)) if name in ("nuisance_parameter_count", "residual_component_count") else str(host.tcl.call("format", "%s", item))) for name, item in host.as_dict(value).items()}
        elif key in vectors:
            result[key] = NumericArray([float(v) for v in host.as_list(value)])
        elif key in numbers:
            result[key] = float(value)
        elif key in ("converged", "jacobi_scaling"):
            result[key] = bool(int(value))
        else:
            result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _multistart_receipt(host, raw):
    result = host.as_dict(raw)
    for key, value in result.items():
        if key == "initials":
            result[key] = _numeric(host, "covariance", value)
        elif key in ("range_lower", "range_upper"):
            result[key] = NumericArray([float(v) for v in host.as_list(value)])
        elif key == "trials":
            trials = []
            for entry in host.as_list(value):
                trial = host.as_dict(entry)
                trial["index"] = int(float(trial["index"]))
                for name in ("initial_parameters", "parameters"):
                    if name in trial:
                        trial[name] = NumericArray([float(v) for v in host.as_list(trial[name])])
                if "solver_receipt" in trial:
                    trial["solver_receipt"] = _solver_receipt(host, trial["solver_receipt"])
                trials.append(trial)
            result[key] = trials
        elif key in ("requested_count", "seed", "next_seed", "strategy_version", "selected_index", "converged_count", "attempted_count", "completed_count", "error_count", "max_seconds", "elapsed_seconds"):
            result[key] = float(value)
        else:
            result[key] = str(host.tcl.call("format", "%s", value))
    return result


def _request(host, raw):
    result = host.as_dict(raw)
    result["numerical"] = {key: _numeric(host, key, value) for key, value in host.as_dict(result["numerical"]).items()}
    result["context"] = _context(host, result["context"])
    result["provenance"] = _provenance(host, result["provenance"])
    if "solver_receipt" in result:
        result["solver_receipt"] = _solver_receipt(host, result["solver_receipt"])
    if "parameters" in result:
        result["parameters"] = _parameters(host, result["parameters"])
    if "parameter_uncertainty" in result:
        receipt = host.as_dict(result["parameter_uncertainty"])
        receipt["confidence"] = float(receipt["confidence"])
        if "numeric" in receipt:
            numeric = host.as_dict(receipt["numeric"])
            numeric["plan"] = _plan(host, numeric["plan"])
            numeric["correlation"] = _numeric(host, "parameter_correlation", numeric["correlation"])
            for key in ("lower", "upper", "critical_value"):
                if key in numeric:
                    numeric[key] = _numeric(host, key, numeric[key])
            receipt["numeric"] = numeric
        result["parameter_uncertainty"] = receipt
    return result


def _provenance(host, raw):
    result = host.as_dict(raw)
    if "smoothing" in result:
        receipt = host.as_dict(result["smoothing"])
        receipt["workspace_bytes_bound"] = float(receipt["workspace_bytes_bound"])
        selected = host.as_dict(receipt["smoothing_selection"])
        for key in ("selected_lambda", "selected_edf", "evaluations", "grid_count", "refinement_budget"):
            if key in selected: selected[key] = float(selected[key])
        selected["selected_gcv"] = float(selected["selected_gcv"]) if str(selected["selected_gcv"]) else ""
        selected["boundary_optimum"] = bool(int(selected["boundary_optimum"]))
        if "lambda_bounds" in selected:
            selected["lambda_bounds"] = NumericArray([float(v) for v in host.as_list(selected["lambda_bounds"])])
            selected["candidates"] = _numeric(host, "covariance", selected["candidates"])
            selected["candidate_columns"] = [str(v) for v in host.as_list(selected["candidate_columns"])]
        receipt["smoothing_selection"] = selected
        result["smoothing"] = receipt
    for name in ("observation_signature", "physical_observation_signature"):
        if name in result:
            signature = host.as_dict(result[name])
            result[name] = {key: float(value) if key in ("n", "log_weight_sum", "response_offset", "predictor_count") else str(host.tcl.call("format", "%s", value)) for key, value in signature.items()}
    if "prediction_source_request" in result:
        result["prediction_source_request"] = _request(host, result["prediction_source_request"])
    if "polynomial_propagation_basis" in result:
        result["polynomial_propagation_basis"] = _propagation_basis(host, result["polynomial_propagation_basis"])
    if "prediction_plan" in result:
        result["prediction_plan"] = _prediction_plan(host, result["prediction_plan"])
    if "binding_resource" in result:
        result["binding_resource"] = _resource_reference(host, result["binding_resource"])
    if "binding_row_start" in result:
        result["binding_row_start"] = int(result["binding_row_start"])
    if "dataset_binding" in result:
        result["dataset_binding"] = {str(key): str(host.tcl.call("format", "%s", value))
                                     for key, value in host.as_dict(result["dataset_binding"]).items()}
    if "dataset_binding" in result and "source_variables" in result:
        # Dataset adapters own these canonical pair records. Unrelated caller
        # provenance retains its existing unconstrained representation.
        sources = [host.as_dict(item) for item in host.as_list(result["source_variables"])]
        result["source_variables"] = [{str(key): str(host.tcl.call("format", "%s", value))
                                       for key, value in item.items()} for item in sources]
    return result


def _nested_f_plan(host, raw):
    numbers = {"api_version", "n", "reduced_p", "full_p", "reduced_sse", "full_sse", "numerator_df", "denominator_df"}
    result = {}
    for key, value in host.as_dict(raw).items():
        text = str(host.tcl.call("format", "%s", value))
        result[key] = float(text) if key in numbers and text else text
    return result


def _nested_f(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    for key in ("api_id", "schema", "status", "reason"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    result["plan"] = _nested_f_plan(host, result["plan"])
    result["assumptions"] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(result["assumptions"])]
    quantities = {}
    for key, value in host.as_dict(result["quantities"]).items():
        quantities[key] = {k: float(v) if k == "value" else str(host.tcl.call("format", "%s", v)) for k, v in host.as_dict(value).items()}
    result["quantities"] = quantities
    request = host.as_dict(result["request"])
    for role in ("reduced", "full"):
        entry = host.as_dict(request[role])
        entry["id"] = str(host.tcl.call("format", "%s", entry["id"]))
        entry["result"] = _result(host, entry["result"])
        entry["binding"] = {k: str(host.tcl.call("format", "%s", v)) for k, v in host.as_dict(entry["binding"]).items()}
        request[role] = entry
    numeric = host.as_dict(request["numeric"])
    if numeric:
        numeric["plan"] = _nested_f_plan(host, numeric["plan"])
        for key in ("numeric_api", "operation", "status", "reason"):
            numeric[key] = str(host.tcl.call("format", "%s", numeric[key]))
        for key in ("f_statistic", "p_value", "numerator_df", "denominator_df", "sse_reduction"):
            numeric[key] = float(numeric[key])
        numeric["sse_roundoff_clamped"] = bool(int(numeric["sse_roundoff_clamped"]))
    request["numeric"] = numeric
    result["request"] = request
    return result


def _selection_plan(host, raw):
    numbers = {"api_version", "n", "free_parameter_count", "weighted_sse", "log_weight_sum"}
    result = {}
    for key, value in host.as_dict(raw).items():
        text = str(host.tcl.call("format", "%s", value))
        result[key] = float(text) if key in numbers and text != "" else text
    return result


def _selection_numeric(host, raw):
    result = host.as_dict(raw)
    for key in ("numeric_api", "operation"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    result["plan"] = _selection_plan(host, result["plan"])
    for key in ("n", "free_parameter_count", "likelihood_parameter_count", "log_likelihood", "aic", "aicc", "bic", "variance_mle"):
        result[key] = float(result[key])
    result["aicc_computed"] = bool(int(result["aicc_computed"]))
    return result


def _model_comparison(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    for key in ("api_id", "schema", "criterion", "status"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    for key in ("ranked_ids", "reasons", "assumptions"):
        result[key] = [str(host.tcl.call("format", "%s", value)) for value in host.as_list(result[key])]
    rows = []
    for raw_row in host.as_list(result["rows"]):
        row = host.as_dict(raw_row)
        for key in ("id", "model_id", "status", "reason", "unit"):
            row[key] = str(host.tcl.call("format", "%s", row[key]))
        row["plan"] = _selection_plan(host, row["plan"])
        for key in ("value", "n", "free_parameter_count"):
            text = str(host.tcl.call("format", "%s", row[key]))
            row[key] = float(text) if text else ""
        if "numeric" in row:
            row["numeric"] = _selection_numeric(host, row["numeric"])
        rows.append(row)
    result["rows"] = rows
    request = host.as_dict(result["request"])
    entries = []
    for raw_entry in host.as_list(request["entries"]):
        entry = host.as_dict(raw_entry)
        entry["id"] = str(host.tcl.call("format", "%s", entry["id"]))
        entry["result"] = _result(host, entry["result"])
        entry["binding"] = {key: str(host.tcl.call("format", "%s", value)) for key, value in host.as_dict(entry["binding"]).items()}
        if "numeric" in entry:
            entry["numeric"] = _selection_numeric(host, entry["numeric"])
        entries.append(entry)
    result["request"] = {"entries": entries, "criterion": str(host.tcl.call("format", "%s", request["criterion"]))}
    return result


def _plan(host, raw):
    result = host.as_dict(raw)
    for key in ("api_id", "status", "reason", "source_model_id", "coefficient_space", "distribution", "approximation", "interval_status", "interval_reason"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    result["api_version"] = int(result["api_version"])
    result["confidence"] = float(result["confidence"])
    result["degrees_of_freedom"] = str(host.tcl.call("format", "%s", result["degrees_of_freedom"]))
    if result["degrees_of_freedom"] != "":
        result["degrees_of_freedom"] = float(result["degrees_of_freedom"])
    for key in ("parameter_ids", "parameter_units"):
        result[key] = host.as_list(result[key])
    for key in ("source_parameters", "source_covariance"):
        result[key] = _numeric(host, key, result[key])
    return result


def _characteristic_fields(host, raw):
    result = host.as_dict(raw)
    scalar = lambda value: float(str(host.tcl.call('format', '%s', value)))
    integer = {'observation_count', 'distinct_predictors', 'peak_count', 'trough_count', 'n', 'predictor_count'}
    boolean = {'duplicate_predictors', 'positive_predictors', 'response_one_sign', 'constant_response', 'linear_like', 'periodic_hint', 'saturating_hint', 'fitted', 'accepted'}
    numeric = {'predictor_minimum', 'predictor_maximum', 'response_minimum', 'response_maximum', 'period', 'tail_slope_ratio', 'log_weight_sum'}
    for key, value in result.items():
        if key in integer: result[key] = int(scalar(value))
        elif key in boolean: result[key] = bool(int(scalar(value)))
        elif key in numeric: result[key] = scalar(value)
        elif key == 'thresholds': result[key] = {k: scalar(v) for k, v in host.as_dict(value).items()}
        elif key == 'observation_signature': result[key] = _characteristic_fields(host, value)
        else: result[key] = str(host.tcl.call('format', '%s', value))
    return result


def _gls_result(host, raw):
    result = host.as_dict(raw)
    text = lambda value: str(host.tcl.call('format', '%s', value))
    for key in ('api_id', 'schema'): result[key] = text(result[key])
    result['api_version'] = int(float(text(result['api_version'])))
    result['assumptions'] = [text(v) for v in host.as_list(result['assumptions'])]
    result['parameters'] = [{k: float(text(v)) if k == 'value' else text(v) for k, v in host.as_dict(item).items()} for item in host.as_list(result['parameters'])]
    result['quantities'] = {k: _quantity(host, k, v) for k, v in host.as_dict(result['quantities']).items()}
    sequence = host.as_dict(result['whitened_diagnostics'])
    result['whitened_diagnostics'] = _sequence_interpretation(host, result['whitened_diagnostics']) if sequence else {}
    request = host.as_dict(result['request']);raw = host.as_dict(request['numeric'])
    counts = 'observation_count parameter_count covariance_rank covariance_nullity exact_constraint_rank stochastic_parameter_count dof'.split()
    numbers = 'objective physical_sse physical_rmse covariance_scale minimum_covariance_eigenvalue covariance_eigenvalue_cutoff eigen_relative_tolerance symmetry_relative_tolerance constraint_relative_tolerance covariance_asymmetry exact_constraint_error exact_constraint_limit scaled_design_condition'.split()
    for key, value in raw.items():
        if key in counts: raw[key] = int(float(text(value)))
        elif key in numbers: raw[key] = float(text(value))
        elif key in ('coefficients', 'standard_errors'): raw[key] = [float(text(v)) for v in host.as_list(value)]
        elif key == 'covariance': raw[key] = [[float(text(v)) for v in host.as_list(row)] for row in host.as_list(value)]
        elif key == 'observation_signature': raw[key] = _bootstrap_signature(host, value)
        elif key == 'whitened_sequence': raw[key] = result['whitened_diagnostics']['request']['numeric'] if sequence else {}
        else: raw[key] = text(value)
    request['numeric'] = raw
    request['context'] = {k: [text(v) for v in host.as_list(value)] if k in ('parameter_ids', 'parameter_units') else text(value) for k, value in host.as_dict(request['context']).items()}
    result['request'] = request
    return result


def _fit_suggestions(host, raw):
    result = host.as_dict(raw)
    text = lambda value: str(host.tcl.call('format', '%s', value))
    for key in ('api_id', 'schema', 'comparison_status', 'comparison_reason'): result[key] = text(result[key])
    result['api_version'] = int(float(text(result['api_version'])))
    for key in ('suggested_ids', 'assumptions'): result[key] = [text(v) for v in host.as_list(result[key])]
    rows = []
    for item in host.as_list(result['suggestions']):
        row = host.as_dict(item)
        for key in ('id', 'model_id', 'label', 'status', 'reason'): row[key] = text(row[key])
        row['suggested'] = bool(int(float(text(row['suggested']))))
        row['priority'] = int(float(text(row['priority'])))
        row['options'] = {k: float(text(v)) if k == 'period' else int(float(text(v))) for k, v in host.as_dict(row['options']).items()}
        rows.append(row)
    result['suggestions'] = rows
    result['comparison'] = _model_comparison(host, result['comparison']) if host.as_dict(result['comparison']) else {}
    request = host.as_dict(result['request'])
    request['numeric'] = _characteristic_fields(host, request['numeric'])
    request['candidates'] = [{k: text(v) for k, v in host.as_dict(item).items()} for item in host.as_list(request['candidates'])]
    context = host.as_dict(request['context'])
    request['context'] = {k: {a: text(b) for a, b in host.as_dict(v).items()} if k == 'observation_binding' else text(v) for k, v in context.items()}
    entries = []
    for item in host.as_list(request['entries']):
        entry = host.as_dict(item);entry['id'] = text(entry['id']);entry['result'] = _result(host, entry['result'])
        entry['binding'] = {k: text(v) for k, v in host.as_dict(entry['binding']).items()}
        if 'numeric' in entry: entry['numeric'] = _selection_numeric(host, entry['numeric'])
        entries.append(entry)
    request['entries'] = entries;request['criterion'] = text(request['criterion']);result['request'] = request
    return result


def _physical_fields(host, raw):
    result = host.as_dict(raw)
    numeric = {'value', 'minimum', 'maximum', 'lower', 'upper', 'maximum_fraction'}
    boolean = {'enabled', 'lower_inclusive', 'upper_inclusive'}
    integer = {'api_version', 'rule_count', 'evaluated_count', 'advisory_count',
               'invalid_domain_count', 'disabled_count', 'unavailable_count'}
    for key, value in result.items():
        if key in numeric:
            result[key] = float(value)
        elif key in boolean:
            result[key] = bool(int(float(value)))
        elif key in integer:
            result[key] = int(value)
        elif key in ('context', 'domain', 'rule', 'limits'):
            result[key] = _physical_fields(host, value)
        elif key in ('rules', 'checks'):
            result[key] = [_physical_fields(host, v) for v in host.as_list(value)]
        elif key == 'assumptions':
            result[key] = [str(host.tcl.call('format', '%s', v)) for v in host.as_list(value)]
        elif key == 'request':
            request = host.as_dict(value)
            result[key] = {'source': _result(host, request['source']),
                           'rules': [_physical_fields(host, v) for v in host.as_list(request['rules'])],
                           'context': _physical_fields(host, request['context'])}
        else:
            result[key] = str(host.tcl.call('format', '%s', value))
    return result


def _derived_definition(host, raw):
    result = host.as_dict(raw)
    for key in ('id', 'label', 'expression', 'unit'):
        if key in result:
            result[key] = str(host.tcl.call('format', '%s', result[key]))
    constants = []
    for raw_constant in host.as_list(result.get('constants', '')):
        c = host.as_dict(raw_constant)
        constants.append({'id': str(c['id']), 'unit': str(c['unit']), 'value': float(c['value'])})
    result['constants'] = constants
    return result


def _derived_plan(host, raw):
    result = host.as_dict(raw)
    for key in ('api_id', 'source_model_id', 'coefficient_space', 'status', 'reason'):
        result[key] = str(host.tcl.call('format', '%s', result[key]))
    result['api_version'] = int(result['api_version'])
    for key in ('parameter_ids', 'parameter_aliases', 'parameter_units', 'parameter_roles'):
        result[key] = [str(v) for v in host.as_list(result[key])]
    for key in ('parameter_values', 'free_indices'):
        result[key] = NumericArray([float(v) for v in host.as_list(result[key])])
    result['source_covariance'] = _numeric(host, 'source_covariance', result['source_covariance'])
    result['definitions'] = [_derived_definition(host, d) for d in host.as_list(result['definitions'])]
    return result


def _derived_result(host, raw):
    result = host.as_dict(raw)
    result['schema'] = str(result['schema'])
    result['api_version'] = int(result['api_version'])
    request = host.as_dict(result['request'])
    result['request'] = {'source': _result(host, request['source']), 'numeric': _derived_numeric(host, request['numeric'])}
    result['plan'] = _derived_plan(host, result['plan'])
    result['assumptions'] = [str(host.tcl.call('format', '%s', v)) for v in host.as_list(result['assumptions'])]
    rows = []
    for raw_row in host.as_list(result['properties']):
        row = _derived_definition(host, raw_row)
        for key, value in row.items():
            if key in ('value', 'standard_uncertainty'):
                row[key] = float(value)
            elif key != 'constants':
                row[key] = str(host.tcl.call('format', '%s', value))
        rows.append(row)
    result['properties'] = rows
    result['propagation'] = _result(host, result['propagation']) if host.as_dict(result['propagation']) else ''
    return result


def _derived_numeric(host, raw):
    result = host.as_dict(raw)
    result['plan'] = _derived_plan(host, result['plan'])
    result['fit_performed'] = bool(int(result['fit_performed']))
    result['propagation_indices'] = NumericArray([int(float(v)) for v in host.as_list(result['propagation_indices'])])
    rows = []
    for item in host.as_list(result['properties']):
        row = host.as_dict(item)
        for key, value in row.items():
            row[key] = float(value) if key == 'value' else bool(int(value)) if key == 'derivative_valid' else str(host.tcl.call('format', '%s', value))
        rows.append(row)
    result['properties'] = rows
    prop = host.as_dict(result['propagation'])
    if prop:
        for key in ('covariance', 'jacobian', 'input_covariance'):
            prop[key] = _numeric(host, 'source_covariance', prop[key])
        prop['standard_uncertainty'] = NumericArray([float(v) for v in host.as_list(prop['standard_uncertainty'])])
        for key in ('input_count', 'output_count'):
            prop[key] = int(float(prop[key]))
        for key in ('method', 'input_kind'):
            prop[key] = str(host.tcl.call('format', '%s', prop[key]))
    result['propagation'] = prop if prop else ''
    for key in ('numeric_api', 'operation', 'derivative_method'):
        result[key] = str(host.tcl.call('format', '%s', result[key]))
    return result


def _uncertainty(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    for key in ("parameter_ids", "parameter_units"):
        result[key] = host.as_list(result[key])
    correlation = host.as_dict(result["correlation"])
    for key in ("status", "reason", "unit"):
        correlation[key] = str(host.tcl.call("format", "%s", correlation[key]))
    if "value" in correlation:
        correlation["value"] = _numeric(host, "parameter_correlation", correlation["value"])
    result["correlation"] = correlation
    intervals = host.as_dict(result["intervals"])
    for key in ("status", "reason", "distribution", "approximation", "coverage"):
        intervals[key] = str(host.tcl.call("format", "%s", intervals[key]))
    for key in ("lower", "upper", "critical_value", "confidence"):
        if key in intervals:
            intervals[key] = _numeric(host, key, intervals[key])
    result["intervals"] = intervals
    if "provenance" in result:
        result["provenance"] = host.as_dict(result["provenance"])
    return result


def _propagation_basis(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    for key in ("api_id", "kind"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    for key in ("source_parameters", "source_covariance"):
        result[key] = _numeric(host, key, result[key])
    for key in ("query_center", "query_scale"):
        result[key] = float(result[key])
    return result


def _prediction_plan(host, raw):
    result = host.as_dict(raw)
    if "fit_geometry" in result:
        result["fit_geometry"] = str(host.tcl.call("format", "%s", result["fit_geometry"]))
    result["api_version"] = int(result["api_version"])
    result["parameter_plan"] = _plan(host, result["parameter_plan"])
    if "propagation_basis" in result:
        result["propagation_basis"] = _propagation_basis(host, result["propagation_basis"])
    result["all_parameter_values"] = _numeric(host, "source_parameters", result["all_parameter_values"])
    result["free_parameter_indices"] = NumericArray([float(v) for v in host.as_list(result["free_parameter_indices"])])
    result["all_parameter_ids"] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(result["all_parameter_ids"])]
    for key in ("critical_value", "observation_scale"):
        value = str(host.tcl.call("format", "%s", result[key]))
        result[key] = float(value) if value else ""
    for key in ("api_id", "kind", "status", "reason", "response_unit", "orientation", "source_operation", "model_source_sha256", "model_binding_sha256", "observation_noise_policy", "coverage", "assumption"):
        result[key] = str(host.tcl.call("format", "%s", result[key]))
    return result


def _quantity(host, key, raw_item):
    item = host.as_dict(raw_item)
    if "value" in item:
        item["value"] = _numeric(host, key, item["value"])
    if key in ("ci_lower", "ci_upper") and str(host.tcl.call("format", "%s", item["confidence"])):
        item["confidence"] = float(item["confidence"])
    for identity in ("row_ids", "column_ids"):
        if identity in item:
            item[identity] = [str(host.tcl.call("format", "%s", value)) for value in host.as_list(item[identity])]
    if "parameter_ids" in item:
        item["parameter_ids"] = host.as_list(item["parameter_ids"])
    if "element_ids" in item:
        item["element_ids"] = [str(host.tcl.call("format", "%s", value)) for value in host.as_list(item["element_ids"])]
    if key == "quantiles":
        item["probabilities"] = _numeric(host, "quantile_probabilities", item["probabilities"])
    if "output_ids" in item:
        item["output_ids"] = host.as_list(item["output_ids"])
    if "output_index" in item:
        item["output_index"] = int(float(item["output_index"]))
    if key in ("foundation_coefficients", "foundation_coefficient_real", "foundation_coefficient_imaginary", "standard_errors", "output_standard_uncertainties"):
        item["unit"] = host.as_list(item["unit"])
    elif key == "cluster_centers":
        item["unit"] = {"column_units": [str(host.tcl.call("format", "%s", unit)) for unit in host.as_list(host.as_dict(item["unit"])["column_units"])]}
    elif key in ("covariance", "output_covariance", "sample_covariance_real", "sample_covariance_imaginary"):
        item["unit"] = {axis: host.as_list(units) for axis, units in host.as_dict(item["unit"]).items()}
    elif key in ("smoothing_lambda", "smoothing_gcv_score", "cluster_within_ss", "cluster_total_within_ss", "sample_covariance_eigenvalues_real", "sample_covariance_eigenvalues_imaginary", "sse", "component_variance", "variance", "variance_population", "ss_between", "ss_within", "ss_total", "ms_between", "ms_within", "signal_energy_sum", "supplied_noise_energy_sum", "signal_fundamental_bin_power", "signal_dc_bin_power", "signal_harmonic_bin_powers", "signal_noise_bin_power", "signal_noise_floor_bin_power", "signal_distortion_bin_power"):
        item["unit"] = host.as_list(item["unit"])
        if key in ("cluster_within_ss", "cluster_total_within_ss", "sample_covariance_eigenvalues_real", "sample_covariance_eigenvalues_imaginary") and item["unit"] == ["unspecified"]:
            item["unit"] = "unspecified"
    elif key in ("sum_weights", "weighted_sum"):
        parts = host.as_list(item["unit"])
        item["unit"] = parts if len(parts) == 3 and parts[0] == "power" else str(host.tcl.call("format", "%s", item["unit"]))
    else:
        item["unit"] = str(host.tcl.call("format", "%s", item["unit"]))
    for field in ("id", "quantity", "unit_text", "label", "status", "kind", "reason", "definition"):
        if field in item:
            item[field] = str(host.tcl.call("format", "%s", item[field]))
    return item


def _result(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    result["model"] = _model(host, result["model"])
    result["residual"] = host.as_dict(result["residual"])
    result["parameters"] = _parameters(host, result["parameters"])
    result["context"] = _context(host, result["context"])
    result["provenance"] = _provenance(host, result["provenance"])
    result["assumptions"] = host.as_list(result["assumptions"])
    result["solver"] = host.as_dict(result["solver"])
    if "diagnostics" in result["solver"]:
        result["solver"]["diagnostics"] = _solver_receipt(host, result["solver"]["diagnostics"])
    if "converged" in result["solver"]:
        result["solver"]["converged"] = bool(int(result["solver"]["converged"]))
    result["request"] = _request(host, result["request"])
    quantities = {}
    for key, raw_item in host.as_dict(result["quantities"]).items():
        item = _quantity(host, key, raw_item)
        quantities[key] = item
    result["quantities"] = quantities
    if "parameter_uncertainty" in result:
        result["parameter_uncertainty"] = _uncertainty(host, result["parameter_uncertainty"])
    return result


def _table(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    result["row_count"] = int(result["row_count"])
    result["row_ids"] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(result["row_ids"])]
    result["model"] = _model(host, result["model"])
    result["context"] = _context(host, result["context"])
    result["provenance"] = _provenance(host, result["provenance"])
    request = host.as_dict(result["request"])
    request["context"] = _context(host, request["context"])
    request["provenance"] = _provenance(host, request["provenance"])
    request["row_ids"] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(request["row_ids"])]
    request["numerical_columns"] = {key: NumericArray([float(v) for v in host.as_list(values)]) for key, values in host.as_dict(request["numerical_columns"]).items()}
    result["request"] = request
    columns = {}
    for key, column in host.as_dict(result["columns"]).items():
        column = host.as_dict(column)
        column["definition"] = _quantity(host, key, column["definition"])
        column["states"] = [{name: str(host.tcl.call("format", "%s", value)) for name, value in host.as_dict(state).items()} for state in host.as_list(column["states"])]
        if "state" in column:
            column["state"] = int(column["state"])
        else:
            column["state_ids"] = [int(v) for v in host.as_list(column["state_ids"])]
        if "values" in column:
            column["values"] = NumericArray([float(v) for v in host.as_list(column["values"])])
        columns[key] = column
    result["columns"] = columns
    return result


def _binding(host, raw):
    result = host.as_dict(raw)
    result["api_version"] = int(result["api_version"])
    result["row_count"] = int(result["row_count"])
    result["row_start"] = int(result["row_start"])
    result["prototype"] = _result(host, result["prototype"])
    result["column_variables"] = {str(k): str(v) for k, v in host.as_dict(result["column_variables"]).items()}
    seal = host.as_dict(result["seal"])
    if seal:
        schema = []
        for value in host.as_list(seal["variable_schema"]):
            variable = host.as_dict(value)
            variable["rank"] = int(variable["rank"])
            variable["shape"] = [int(v) for v in host.as_list(variable["shape"])]
            variable["dimension_ids"] = [str(v) for v in host.as_list(variable["dimension_ids"])]
            schema.append(variable)
        seal["variable_schema"] = schema
    result["seal"] = seal
    return result


def _resource_reference(host, raw):
    result = host.as_dict(raw)
    result["size_bytes"] = int(result["size_bytes"])
    metadata = host.as_dict(result["metadata"])
    metadata["row_count"] = int(metadata["row_count"])
    schema = []
    for raw_variable in host.as_list(metadata["variable_schema"]):
        variable = host.as_dict(raw_variable)
        variable["rank"] = int(variable["rank"])
        variable["shape"] = [int(v) for v in host.as_list(variable["shape"])]
        variable["dimension_ids"] = [str(v) for v in host.as_list(variable["dimension_ids"])]
        schema.append(variable)
    metadata["variable_schema"] = schema
    result["metadata"] = metadata
    return result


def _resource_binding(host, raw):
    result = host.as_dict(raw)
    for key in ("api_version", "row_count", "row_start"):
        result[key] = int(result[key])
    result["prototype"] = _result(host, result["prototype"])
    result["column_variables"] = {str(k): str(v) for k, v in host.as_dict(result["column_variables"]).items()}
    result["resource"] = _resource_reference(host, result["resource"])
    return result


def _table_transport(value):
    # Octave represents a one-element numeric array as a scalar on its return
    # trip. Keep table fact/value columns in the existing binary64 array path,
    # whose Tcl serialization uses 17 digits, without changing any numeric bit
    # or weakening the CORE's exact captured-value comparison.
    if isinstance(value, dict):
        result = {key: _table_transport(item) for key, item in value.items()}
        if result.get("schema") == "gxtxt.statistical_result.table.v1":
            request = result.get("request", {})
            if isinstance(request, dict) and isinstance(request.get("numerical_columns"), dict):
                for key, item in request["numerical_columns"].items():
                    if isinstance(item, (int, float)) and not isinstance(item, bool):
                        request["numerical_columns"][key] = NumericArray([item])
            if isinstance(result.get("columns"), dict):
                for column in result["columns"].values():
                    if isinstance(column, dict) and isinstance(column.get("values"), (int, float)) and not isinstance(column["values"], bool):
                        column["values"] = NumericArray([column["values"]])
        return result
    if isinstance(value, (list, tuple)):
        return [_table_transport(item) for item in value]
    return value


def _store_columns(host, document, prototype, columns):
    """Stream existing binary64 fact vectors into the canonical Document owner.

    This adapter has no estimator or interpretation policy. The existing CORE
    prototype/binding validation supplies identities and physical units. Lazy
    bridge buffers are read by bounded byte chunks, never by their values getter.
    """
    from gxtxt_scientific_binary_v1 import open_buffer, MAX_BYTES
    import numpy as np
    if not isinstance(columns, dict) or not 1 <= len(columns) <= 128:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Statistical store needs one to 128 captured fact columns")
    count = None
    for value in columns.values():
        if not isinstance(value, NumericArray) or value.dtype != "float64" or sum(int(d) != 1 for d in value.shape) > 1:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Statistical columns require explicit binary64 vectors")
        size = math.prod(value.shape)
        if size < 1 or count is not None and size != count:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Statistical columns require one shared positive row count")
        count = size
    if 8 * count * len(columns) > MAX_BYTES:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Statistical resource exceeds 512 MiB")
    mapping = {key: key for key in columns}
    checked = host.as_dict(host.call("::GX::StatisticsV1::bindColumns", prototype, mapping, count))
    canonical = host.as_dict(checked["column_variables"])
    quantities = host.as_dict(host.as_dict(checked["prototype"])["quantities"])
    schema = [dict(variable_id=variable, unit=host.as_dict(quantities[quantity])["unit"],
                   dtype="float64", rank=1, shape=[count], dimension_ids=["row"])
              for quantity, variable in canonical.items()]
    metadata = dict(format="gxtxt.statistical_facts.float64_column_major_le.v1",
                    row_count=count, variable_schema=schema)
    with ExitStack() as cleanup:
        streams = {}
        # Validate/open every input before allocating an owner-managed writer.
        for quantity in canonical:
            value = columns[quantity]
            if isinstance(value, ResourceNumericArray):
                fd, dtype, actual_count = open_buffer(value.root, value.descriptor)
                stream = cleanup.enter_context(os.fdopen(fd, "rb"))
                if np.dtype(dtype) != np.dtype("<f8") or actual_count != count:
                    raise BridgeError("GXTXT:ScriptBridge:Transport", "Statistical buffer identity changed")
                streams[quantity] = stream
        writer = host.call("::GX::interactiveDocumentResourceOpenWriter", document, metadata)
        try:
            for quantity in canonical:
                remaining = 8 * count
                if quantity in streams:
                    stream = streams[quantity]
                    while remaining:
                        block = stream.read(min(1048576, remaining))
                        if not block:
                            raise BridgeError("GXTXT:ScriptBridge:Transport", "Statistical buffer was truncated")
                        host.tcl.call("::GX::interactiveDocumentResourceAppend", writer, block)
                        remaining -= len(block)
                    if stream.read(1):
                        raise BridgeError("GXTXT:ScriptBridge:Transport", "Statistical buffer length changed")
                else:
                    values = columns[quantity].values
                    for start in range(0, count, 131072):
                        block = np.asarray(values[start:start + 131072], dtype="<f8").tobytes()
                        host.tcl.call("::GX::interactiveDocumentResourceAppend", writer, block)
            resource = host.call("::GX::interactiveDocumentResourceFinalize", writer)
            writer = None
            return _resource_binding(host, host.call("::GX::StatisticsV1::bindResourceColumns", checked["prototype"], resource, canonical, count))
        finally:
            if writer is not None:
                host.call("::GX::interactiveDocumentResourceAbort", writer)


def invoke(host, operation, args):
    args = [_table_transport(item) for item in args]
    expected = _ARGS.get(operation)
    if expected is None or len(args) != len(expected) and not (operation == "nested_f_interpretation" and len(args) == 2 or operation == "bootstrap_plan" and len(args) == 1 or operation == "log_response_interpretation" and len(args) == 2 or operation == "bind_columns" and len(args) == 3 or operation == "bind_resource_columns" and len(args) == 4 or operation == "numeric_model" and len(args) == 1 or operation in ("table_rows", "table_csv_rows") and len(args) == 2 or operation in ("solver_report", "report") and len(args) == 1 or operation == "from_numeric" and 4 <= len(args) <= 6 or operation == "from_numeric_table" and 4 <= len(args) <= 5 or operation == "from_numeric_columns" and 6 <= len(args) <= 7 or operation == "prediction_inference_plan" and 1 <= len(args) <= 3 or operation == "parameter_inference_plan" and len(args) == 1 or operation == "with_parameter_uncertainty" and len(args) == 2):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Invalid statistical semantics operation arguments")
    if operation == "store_columns":
        return _store_columns(host, *args)
    command = {"residual_sequence_interpretation": "residualSequenceInterpretation", "nested_f_plan": "nestedFPlan", "nested_f_interpretation": "nestedFInterpretation", "bootstrap_settings": "bootstrapSettings", "bootstrap_plan": "bootstrapPlan", "bootstrap_interpretation": "bootstrapInterpretation", "influence_plan": "influencePlan", "influence_interpretation": "influenceInterpretation", "log_response_plan": "logResponsePlan", "log_response_interpretation": "logResponseInterpretation", "model_selection_plan": "modelSelectionPlan", "model_comparison": "modelComparison", "from_native_comparison": "fromNativeComparison", "validated_result": "validatedResult", "table_rows": "tableRows", "solver_report": "solverReport", "api_info": "apiInfo", "from_numeric": "fromNumeric", "from_numeric_table": "fromNumericTable", "from_numeric_columns": "fromNumericColumns", "interpret_table": "interpretTable", "table_select": "tableSelect", "table_values": "tableValues", "table_report": "tableReport", "scalar_rows": "scalarRows", "ini_report": "iniReport", "parameter_report": "parameterReport", "parameter_ini_report": "parameterIniReport", "parameter_rows": "parameterRows", "parameter_correlation_report": "parameterCorrelationReport", "publication_metadata": "publicationMetadata", "parameter_inference_plan": "parameterInferencePlan", "with_parameter_uncertainty": "withParameterUncertainty"}.get(operation, operation)
    command = {"prediction_interpretation": "predictionInterpretation", "prediction_inference_plan": "predictionInferencePlan", "numeric_data_fields": "numericDataFields", "table_csv_rows": "tableCsvRows", "numeric_field_map": "numericFieldMap", "numeric_fields": "numericFields", "numeric_model": "numericModel", "numeric_field_elements": "numericFieldElements"}.get(operation, command)
    if operation == "from_numeric" and args[1] in ("generalized_least_squares", "polynomial_gls") and isinstance(args[2], dict):
        original = args[2]
        summary = original.get('gls_summary', original.get('summary', original))
        bounded = {'gls_summary': summary}
        if isinstance(original.get('model'), dict):
            bounded['model'] = {key: value for key, value in original['model'].items() if key in ('parameter_ids', 'parameter_units')}
        args = [*args[:2], bounded, *args[3:]]
    if operation == "from_numeric" and args[1] == "curve_model_fit" and isinstance(args[2], dict) and "knot_summary" in args[2]:
        fields = host.as_dict(host.call("::GX::StatisticsV1::numericFieldMap", args[1]))
        selected = set(fields) | {"knot_summary", "parameters", "p", "solver_receipt", "rmse", "mae", "max_abs_error"}
        args = [*args[:2], {key: value for key, value in args[2].items() if key in selected}, *args[3:]]
    if operation == "from_numeric" and args[1] in ("rational_fit", "rational_residuals", "surface_fit", "surface_residuals", "complex_fit", "complex_residuals", "implicit_fit", "least_squares", "linear_regression", "polynomial_fit", "nonlinear_fit", "dataset_polynomial_fit", "dataset_nonlinear_fit") and isinstance(args[2], dict):
        fields = host.as_dict(host.call("::GX::StatisticsV1::numericFieldMap", args[1]))
        selected = set(fields) | {"rational_summary", "surface_summary", "complex_summary", "implicit_summary", "regional_fit", "response_rmse", "observation_signature", "p", "parameter_values", "coefficients", "parameters", "free_parameter_count", "fixed_mask", "active_bounds", "response_count", "loss", "weight_semantics", "has_intercept", "covariance_scale", "solver", "solver_receipt", "fit_geometry", "converged", "response_variance", "scaled_coefficients", "scaled_covariance", "x_center", "x_scale"}
        if args[1] in ("rational_residuals", "surface_residuals", "complex_residuals"):
            # Keep disallowed training facts visible to the common validator.
            # Silently stripping them would hide an invalid evaluation request.
            selected.update(("rank", "dof", "covariance", "standard_errors", "reduced_chi_squared"))
        if args[1].startswith("dataset_"):
            selected.update(("dataset_id", "x_variable_id", "y_variable_id", "weight_variable_id", "x_unit", "y_unit", "selection_id", "sigma_x_variable_id", "sigma_variable_id", "sigma_x_unit", "sigma_unit", "row_identity"))
        bounded = {key: value for key, value in args[2].items() if key in selected}
        if isinstance(args[2].get("model"), dict):
            bounded["model"] = {key: value for key, value in args[2]["model"].items()
                                if key in ("parameter_ids", "parameter_units", "source_sha256", "binding_sha256")}
        args = [*args[:2], bounded, *args[3:]]
    if operation == "from_numeric" and args[1] in ("foundation.statistics.robust_regression", "foundation.statistics.logistic_regression", "foundation.statistics.glm", "foundation.statistics.kmeans", "foundation.statistics.covariance_diagnostics", "spectral_features", "welch_aggregate", "fft_spectrum_quality", "harmonic_peak_quality", "event_period", "pulse_timing", "signal_correlation") and isinstance(args[2], dict):
        # Distribution arrays remain in binary resources; interpretation needs
        # only the CORE-declared scalar fields and bounded estimator facts.
        fields = host.as_dict(host.call("::GX::StatisticsV1::numericFieldMap", args[1]))
        selected = set(fields) | {"seed", "random_generator", "backend", "backend_version", "start_method", "empty_action", "max_iterations", "convergence", "input_semantics", "exclude_dc", "quantile_definition", "zero_policy", "averaging", "peak_policy", "method", "normalization", "window", "detrend", "fundamental_mode", "guard_bins", "track_harmonics", "exclude_dc_bins", "spur_search", "level_floor", "sample_rate", "input_kind", "peak_resolved"}
        if args[1] in ("foundation.statistics.robust_regression", "foundation.statistics.logistic_regression", "foundation.statistics.glm"):
            selected.discard("coefficients")  # Explicit components preserve complex coefficients.
            selected.update(("family", "link"))
        args = [*args[:2], {key: value for key, value in args[2].items() if key in selected}, *args[3:]]
    if operation == "bind_resource_columns":
        return _resource_binding(host, host.call("::GX::StatisticsV1::bindResourceColumns", *args))
    if operation == "resource_binding_table":
        return _table(host, host.call("::GX::StatisticsV1::resourceBindingTable", *args))
    if operation == "bind_columns":
        return _binding(host, host.call("::GX::StatisticsV1::bindColumns", *args))
    if operation == "binding_table":
        return _table(host, host.call("::GX::StatisticsV1::bindingTable", host.session, *args))
    if operation == "resource_field_elements":
        command = "resourceBindingFieldElements"
    if operation == "prediction_interpretation" and isinstance(args[1], dict):
        selected = {"numeric_api", "operation", "plan", "query_count", "available_count", "unavailable_count", "critical_value", "critical_value_reused", "covariance_roundoff_eigenvalues_clipped", "model_source_sha256", "model_binding_sha256", "model_evaluation_kind"}
        args = [args[0], {key: value for key, value in args[1].items() if key in selected}]
    if operation == "log_response_interpretation" and isinstance(args[1], dict):
        selected = {"schema", "n", "reference", "base", "mean_available", "log_standard_deviation", "log_bias_correction", "interval_kind", "confidence", "interval_available_count", "method"}
        args = [args[0], {key: value for key, value in args[1].items() if key in selected}, *args[2:]]
    if operation == "influence_interpretation" and isinstance(args[1], dict):
        args = [args[0], {key: value for key, value in args[1].items() if key in _INFLUENCE_FIELDS}]
    if operation == "bootstrap_interpretation" and isinstance(args[1], dict):
        args = [args[0], {key: value for key, value in args[1].items() if key in _BOOTSTRAP_FIELDS}]
    if operation == 'profile_interpretation' and isinstance(args[1], dict):
        args = [args[0], args[1].get('summary', args[1])]
    command = {'profile_eligibility':'profileEligibility', 'profile_settings':'profileSettings', 'profile_plan':'profilePlan', 'profile_interpretation':'profileInterpretation', 'profile_report':'profileReport'}.get(operation, command)
    command = {'digitization_interpretation': 'digitizationInterpretation', 'digitization_fit_plan': 'digitizationFitPlan', 'digitization_report': 'digitizationReport', 'gls_interpretation': 'glsInterpretation', 'gls_report': 'glsReport', 'fit_suggestions': 'fitSuggestions', 'fit_suggestions_report': 'fitSuggestionsReport', 'physical_plausibility': 'physicalPlausibility', 'physical_plausibility_report': 'physicalPlausibilityReport', 'derived_properties_plan': 'derivedPropertiesPlan', 'derived_properties_interpretation': 'derivedPropertiesInterpretation', 'derived_properties_report': 'derivedPropertiesReport'}.get(operation, command)
    raw = host.call("::GX::StatisticsV1::" + command, *args)
    if operation == 'profile_eligibility':
        result = host.as_dict(raw); result['api_version'] = int(result['api_version']); return result
    if operation in ('profile_settings', 'profile_plan', 'profile_interpretation') or operation == 'validated_result' and host.as_dict(raw).get('schema') == 'gxtxt.fit_profile_interpretation.v1':
        return _profile_result(host, raw)
    if operation == 'profile_report':
        return str(host.tcl.call('format', '%s', raw))
    if operation in ("digitization_interpretation", "digitization_fit_plan") or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.digitization_interpretation.v1":
        return _digitization_result(host, raw)
    if operation == "digitization_report":
        return str(host.tcl.call("format", "%s", raw))
    if operation == 'gls_interpretation' or operation == 'validated_result' and host.as_dict(raw).get('schema') == 'gxtxt.gls_interpretation.v1':
        return _gls_result(host, raw)
    if operation == 'gls_report':
        return str(host.tcl.call('format', '%s', raw))
    if operation == 'fit_suggestions' or operation == 'validated_result' and host.as_dict(raw).get('schema') == 'gxtxt.fit_suggestions.v1':
        return _fit_suggestions(host, raw)
    if operation == 'fit_suggestions_report':
        return str(host.tcl.call('format', '%s', raw))
    if operation == 'physical_plausibility' or operation == 'validated_result' and host.as_dict(raw).get('schema') == 'gxtxt.physical_plausibility_review.v1':
        return _physical_fields(host, raw)
    if operation == 'physical_plausibility_report':
        return str(host.tcl.call('format', '%s', raw))
    if operation == 'derived_properties_plan':
        return _derived_plan(host, raw)
    if operation == 'derived_properties_interpretation' or operation == 'validated_result' and host.as_dict(raw).get('schema') == 'gxtxt.derived_properties.v1':
        return _derived_result(host, raw)
    if operation == 'derived_properties_report':
        return str(host.tcl.call('format', '%s', raw))
    if operation == "residual_sequence_interpretation" or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.residual_sequence_interpretation.v1":
        return _sequence_interpretation(host, raw)
    if operation == "bootstrap_settings":
        return {key: int(float(value)) if key in ("replicates", "seed") else float(value) if key in ("confidence", "max_seconds") else _bootstrap_text(host, value) for key, value in host.as_dict(raw).items()}
    if operation == "bootstrap_plan":
        return _bootstrap_plan(host, raw)
    if operation == "bootstrap_interpretation" or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.regression_bootstrap_interpretation.v1":
        return _bootstrap_interpretation(host, raw)
    if operation == "influence_plan":
        return _influence_plan(host, raw)
    if operation == "influence_interpretation" or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.regression_influence_interpretation.v1":
        return _influence_interpretation(host, raw)
    if operation == "log_response_plan":
        return _log_plan(host, raw)
    if operation == "log_response_interpretation" or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.log_response_interpretation.v1":
        return _log_interpretation(host, raw)
    if operation == "nested_f_plan":
        return _nested_f_plan(host, raw)
    if operation == "nested_f_interpretation" or operation == "validated_result" and host.as_dict(raw).get("schema") == "gxtxt.nested_f_interpretation.v1":
        return _nested_f(host, raw)
    if operation == "model_selection_plan":
        return _selection_plan(host, raw)
    if operation == "model_comparison":
        return _model_comparison(host, raw)
    if operation == "prediction_inference_plan":
        return _prediction_plan(host, raw)
    if operation == "numeric_data_fields":
        result = host.as_dict(raw);result["api_version"] = int(result["api_version"])
        fields = {}
        for name, value in host.as_dict(result["fields"]).items():
            field = host.as_dict(value)
            field["shape"] = [int(v) for v in host.as_list(field["shape"])]
            for key in ("minimum", "maximum"):
                if key in field: field[key] = int(field[key]) if field["value_kind"] == "integer" else float(field[key])
            if "identity_ids" in field: field["identity_ids"] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(field["identity_ids"])]
            for key in ("column_units", "column_ids", "parameter_ids", "parameter_units"):
                if key in field: field[key] = [str(host.tcl.call("format", "%s", v)) for v in host.as_list(field[key])]
            for key in ("kind", "value_kind", "unit", "label", "definition", "nonfinite_status", "nonfinite_reason", "availability_field", "unavailable_reason"):
                if key in field: field[key] = str(host.tcl.call("format", "%s", field[key]))
            fields[str(name)] = field
        result["fields"] = fields
        return result
    if operation == "numeric_model":
        return _model(host, raw)
    if operation in ("numeric_field_elements", "resource_field_elements"):
        result = host.as_dict(raw)
        cells = []
        for entry in host.as_list(result["cells"]):
            cell = {str(key): str(host.tcl.call("format", "%s", value)) for key, value in host.as_dict(entry).items()}
            for key in ("row", "column"):
                cell[key] = int(cell[key])
            for key in ("value", "probability"):
                if key in cell:
                    cell[key] = float(cell[key])
            cells.append(cell)
        return {"shape": [int(v) for v in host.as_list(result["shape"])], "cells": cells}
    if operation == "numeric_field_map":
        return {str(key): str(value) for key, value in host.as_dict(raw).items()}
    if operation == "numeric_fields":
        return {str(key): _quantity(host, str(host.as_dict(value)['quantity']), value)
                for key, value in host.as_dict(raw).items()}
    if operation == "from_native_comparison":
        return {key: _result(host, value) for key, value in host.as_dict(raw).items()}
    if operation == "table_csv_rows":
        result = host.as_dict(raw)
        result["api_version"] = int(result["api_version"])
        for key in ("columns", "row_ids", "records"):
            result[key] = [str(host.tcl.call("format", "%s", value)) for value in host.as_list(result[key])]
        return result
    if operation == "table_rows":
        rows = []
        for raw_row in host.as_list(raw):
            row = host.as_dict(raw_row)
            cells = {}
            for alias, raw_cell in host.as_dict(row["cells"]).items():
                cell = host.as_dict(raw_cell)
                cells[str(alias)] = _quantity(host, str(cell['quantity']), raw_cell)
            rows.append({"row_id": str(host.tcl.call("format", "%s", row["row_id"])), "cells": cells})
        return rows
    if operation == "scalar_rows":
        rows = []
        for raw_row in host.as_list(raw):
            row = host.as_dict(raw_row)
            rows.append(_quantity(host, str(row['quantity']), raw_row))
        return rows
    if operation in ("from_numeric_table", "from_numeric_columns", "interpret_table", "table_select"):
        return _table(host, raw)
    if operation == "table_values":
        return {key: NumericArray([float(v) for v in host.as_list(values)]) for key, values in host.as_dict(raw).items()}
    if operation == "models":
        return host.as_list(raw)
    if operation == "model":
        return _model(host, raw)
    if operation in ("prediction_interpretation", "interpret", "from_numeric", "with_parameter_uncertainty", "validated_result"):
        if host.as_dict(raw).get("schema") == "gxtxt.model_comparison.v1":
            return _model_comparison(host, raw)
        if host.as_dict(raw).get("schema") == "gxtxt.statistical_result.resource_binding.v1":
            return _resource_binding(host, raw)
        if host.as_dict(raw).get("schema") == "gxtxt.statistical_result.column_binding.v1":
            return _binding(host, raw)
        if host.as_dict(raw).get("schema") == "gxtxt.statistical_result.table.v1":
            return _table(host, raw)
        return _result(host, raw)
    if operation == "parameter_inference_plan":
        return _plan(host, raw)
    if operation == "parameter_rows":
        rows = []
        for item in host.as_list(raw):
            row = host.as_dict(item)
            rows.append({key: float(value) if key in ("value", "standard_error", "confidence", "lower", "upper") else str(host.tcl.call("format", "%s", value)) for key, value in row.items()})
        return rows
    if operation in ("solver_report", "report", "table_report", "ini_report", "parameter_report", "parameter_ini_report", "parameter_correlation_report", "publication_metadata"):
        return str(raw)
    if operation == "quantities":
        return {key: host.as_dict(value) for key, value in host.as_dict(raw).items()}
    result = host.as_dict(raw)
    if operation == "feature":
        result["value"] = float(result["value"])
        return result
    if operation == "validate":
        result["valid"] = bool(int(result["valid"]))
    else:
        result["api_version"] = int(result["api_version"])
        for key in ("operations", "statuses"):
            result[key] = host.as_list(result[key])
    return result


_BOOTSTRAP_FIELDS = {'interval_policy', 'summary_status', 'not_completed_count', 'n', 'next_seed', 'quantile_definition', 'strategy_version', 'summary_message', 'solver_error_count', 'elapsed_seconds', 'rank_failure_count', 'source_parameters', 'parameter_standard_errors', 'simulation_scale_policy', 'attempted_count', 'weight_semantics', 'p', 'messages', 'replicates', 'regular_count', 'schema', 'nonconverged_count', 'source_binding_sha256', 'workspace_bytes_bound', 'successful_count', 'source_model_sha256', 'generator', 'execution_policy', 'simulation_scale', 'nonfinite_count', 'method', 'interval_method', 'parameter_covariance', 'tail_resolution', 'ci_lower', 'normal_transform', 'max_seconds', 'parameter_ids', 'cancellation_policy', 'ci_upper', 'original_fit_count', 'confidence', 'seed', 'observation_signature', 'free_parameter_count', 'source_operation', 'boundary_count'}
def _bootstrap_text(host, value):
    return str(host.tcl.call('format', '%s', value))


def _bootstrap_signature(host, value):
    result = host.as_dict(value)
    for key, value in result.items():
        result[key] = int(float(value)) if key in ('n', 'predictor_count') else float(value) if key in ('log_weight_sum', 'response_offset') else _bootstrap_text(host, value)
    return result


def _bootstrap_plan(host, raw):
    result = host.as_dict(raw)
    integers = {'api_version', 'n', 'p', 'rank', 'dof', 'free_parameter_count', 'replicates', 'seed', 'workspace_bytes_max', 'resample_values_max', 'work_units_max'}
    for key, value in result.items():
        if key in integers:
            result[key] = int(float(value)) if str(value) else ''
        elif key in ('confidence', 'max_seconds', 'residual_scale'):
            result[key] = float(value)
        elif key in ('parameter_ids', 'parameter_units', 'parameter_roles', 'assumptions'):
            result[key] = [_bootstrap_text(host, v) for v in host.as_list(value)]
        elif key == 'source_parameters':
            result[key] = _numeric(host, 'source_parameters', value)
        elif key == 'solver_policy':
            result[key] = _solver_receipt(host, value)
        elif key == 'observation_signature':
            result[key] = _bootstrap_signature(host, value)
        elif key == 'propagation_basis':
            result[key] = _propagation_basis(host, value)
        else:
            result[key] = _bootstrap_text(host, value)
    return result


def _bootstrap_numeric(host, raw):
    result = host.as_dict(raw)
    integers = {'n', 'p', 'free_parameter_count', 'replicates', 'attempted_count', 'successful_count', 'regular_count', 'boundary_count', 'rank_failure_count', 'nonconverged_count', 'nonfinite_count', 'solver_error_count', 'not_completed_count', 'seed', 'next_seed', 'strategy_version', 'original_fit_count', 'workspace_bytes_bound'}
    for key, value in result.items():
        if key in integers:
            result[key] = int(float(value))
        elif key in ('confidence', 'max_seconds', 'elapsed_seconds', 'tail_resolution', 'simulation_scale'):
            result[key] = float(value)
        elif key in ('parameter_ids', 'messages'):
            result[key] = [_bootstrap_text(host, v) for v in host.as_list(value)]
        elif key == 'observation_signature':
            result[key] = _bootstrap_signature(host, value)
        elif key == 'parameter_covariance':
            result[key] = _numeric(host, 'covariance', value)
        elif key in ('source_parameters', 'parameter_standard_errors', 'ci_lower', 'ci_upper'):
            result[key] = NumericArray([float(v) for v in host.as_list(value)])
        else:
            result[key] = _bootstrap_text(host, value)
    return result


def _bootstrap_interpretation(host, raw):
    result = host.as_dict(raw)
    result['api_version'] = int(result['api_version'])
    for key in ('api_id', 'schema', 'status', 'reason'):
        result[key] = _bootstrap_text(host, result[key])
    result['plan'] = _bootstrap_plan(host, result['plan'])
    request = host.as_dict(result['request'])
    result['request'] = {'source_request': _request(host, request['source_request']), 'numeric': _bootstrap_numeric(host, request['numeric'])}
    rows = []
    for row in host.as_list(result['parameters']):
        row = host.as_dict(row)
        rows.append({key: float(value) if key in ('estimate', 'standard_error', 'confidence', 'lower', 'upper') else _bootstrap_text(host, value) for key, value in row.items()})
    result['parameters'] = rows
    covariance = host.as_dict(result['covariance'])
    for key in ('status', 'population'):
        covariance[key] = _bootstrap_text(host, covariance[key])
    for key in ('parameter_ids', 'parameter_units'):
        covariance[key] = [_bootstrap_text(host, v) for v in host.as_list(covariance[key])]
    covariance['value'] = _numeric(host, 'covariance', covariance['value'])
    result['covariance'] = covariance
    for key in ('assumptions', 'warnings'):
        result[key] = [_bootstrap_text(host, v) for v in host.as_list(result[key])]
    return result



def _sequence_interpretation(host, raw):
    result = host.as_dict(raw)
    text = lambda value: str(host.tcl.call('format', '%s', value))
    for key in ('api_id', 'schema', 'autocorrelation_label', 'autocorrelation_unit'): result[key] = text(result[key])
    for key in ('api_version', 'row_count'): result[key] = int(result[key])
    result['assumptions'] = [text(v) for v in host.as_list(result['assumptions'])]
    request = host.as_dict(result['request'])
    request['context'] = {k: text(v) for k, v in host.as_dict(request['context']).items()}
    facts = host.as_dict(request['numeric'])
    counts = 'input_count n omitted_count tie_count positive_count negative_count zero_count runs work_units'.split()
    flags = 'generated_input_positions constant_sequence zero_sequence p_values_computed'.split()
    for key, value in facts.items():
        if key in counts: facts[key] = int(value)
        elif key in flags: facts[key] = bool(int(value))
        elif key in ('runs_expected', 'runs_variance', 'runs_z', 'durbin_watson'): facts[key] = float(value)
        elif key in ('lags', 'lag_pair_count', 'autocorrelation'): facts[key] = [float(v) for v in host.as_list(value)]
        else: facts[key] = text(value)
    request['numeric'] = facts; result['request'] = request
    result['metrics'] = {key: {field: float(value) if field == 'value' else text(value) for field, value in host.as_dict(item).items()} for key, item in host.as_dict(result['metrics']).items()}
    return result
