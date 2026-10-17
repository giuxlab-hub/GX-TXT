"""Durable Fitter recipe/result bindings; all computation stays with its owner."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray
import importlib.util
from pathlib import Path

_OPS = {
    'surface_create': ('surfaceCreate', ['workspace_name']),
    'surface_preview': ('surfacePreviewSummary', ['workspace_id', 'source', 'recipe', 'options']),
    'surface_accept': ('surfaceAccept', ['workspace_id', 'accepted_name']),
    'surface_reference': ('surfaceResultReference', ['workspace_id', 'fit_id']),
    'surface_info': ('surfaceInfo', ['reference']),
    'surface_query': ('surfaceQuery', ['reference', 'coordinates', 'options']),
    'surface_export': ('surfaceExport', ['reference', 'function_name']),
    'surface_report': ('surfaceReport', ['reference']),
    'surface_residual_page': ('surfaceResidualPage', ['reference', 'start', 'count']),
    'surface_publish': ('surfacePublish', ['reference', 'dataset_id', 'x', 'y', 'options']),
    'surface_plot': ('surfacePlot', ['reference', 'dataset_id', 'style']),
    'surface_recipe_capture': ('surfaceRecipeCapture', ['reference']),
    'surface_recipe_run': ('surfaceRecipeRun', ['encoded_recipe', 'workspace_name', 'accepted_name']),
    'dataset_suggestions': ('datasetSuggestions', ['source_request', 'options', 'references']),
    'registered_query_run': (None, ['callback', 'encoded_request']),
    'result_query': ('resultQuery', ['reference', 'values', 'options']),
    'result_inverse': ('resultInverse', ['reference', 'targets', 'bracket', 'options']),
    'registered_parameter_run': (None, ['callback', 'encoded_request']),
    'recipe_parameter_view': ('recipeParameterView', ['encoded_recipe', 'parameters']),
    'recipe_parameters_set': ('recipeParametersSet', ['encoded_recipe', 'parameters']),
    'global_family_recipe': ('globalFamilyRecipe', ['encoded_fitter_recipe', 'variable_id', 'model_id', 'config', 'scope']),
    'family_members': ('familyMembers', ['dataset_id', 'variable_id']),
    'family_run': ('familyRun', ['encoded_recipe', 'variable_id', 'members', 'workspace_name']),
    'registered_models': ('registeredModels', []),
    'registered_model_describe': ('registeredModelDescribe', ['reference', 'callable_id']),
    'registered_model_declare': ('registeredModelDeclare', ['reference', 'callable_id', 'entrypoint', 'definition']),
    'registered_submit': ('registeredSubmit', ['encoded_recipe', 'workspace_name']),
    'registered_accept': ('registeredAccept', ['preview_reference', 'accepted_name']),
    'registered_preview_reference': ('registeredPreviewReference', ['document_id', 'source_curve_id']),
    'registered_run': (None, ['callback', 'encoded_job']),
    'recipe_capture': ('recipeCapture', ['document_id', 'fit_curve_id']),
    'recipe_validate': ('recipeValidate', ['encoded_recipe']),
    'recipe_run': ('recipeRun', ['encoded_recipe', 'workspace_name', 'accepted_name']),
    'recipe_script': ('recipeScript', ['encoded_recipe', 'language']),
    'result_reference': ('resultReference', ['document_id', 'fit_curve_id']),
    'result_export': ('resultExport', ['reference', 'function_name']),
    'result_profile_page': ('resultProfilePage', ['reference', 'start', 'count']),
    'result_bootstrap_page': ('resultBootstrapPage', ['reference', 'start', 'count']),
    'result_residual_sequence': ('resultResidualSequence', ['reference', 'options']),
    'result_residual_page': ('resultResidualPage', ['reference', 'start', 'count']),
    'result_preprocessing_rows': ('resultPreprocessingRows', ['reference', 'stage', 'start', 'count']),
    'result_influence_page': ('resultInfluencePage', ['reference', 'start', 'count']),
    'result_info': ('resultInfo', ['reference']),
    'plausibility_definitions': ('plausibilityDefinitions', ['reference']),
    'result_plausibility': ('resultPlausibility', ['reference', 'rules']),
    'result_plausibility_publish': ('resultPlausibilityPublishText', ['receipt_utf8', 'dataset_id']),
    'derived_definitions': ('derivedDefinitions', ['reference']),
    'result_derived': ('resultDerived', ['reference', 'definitions']),
    'result_derived_publish': ('resultDerivedPublishText', ['receipt_utf8', 'dataset_id']),
    'model_cards': ('modelCards', []),
    'result_workbench': ('resultWorkbench', ['reference', 'workspace_name']),
    'result_report': ('resultReport', ['reference']),
    'result_nested_f': ('resultNestedF', ['reduced_reference', 'full_reference']),
    'result_parameters_publish': ('resultParametersPublish', ['references', 'dataset_id']),
    'result_publish': ('resultPublish', ['reference', 'dataset_id']),
    'result_retransform': ('resultRetransform', ['reference', 'dataset_id']),
    'template_create': ('templateCreate', ['reference', 'name']),
    'template_list': ('templateList', []),
    'template_inspect': ('templateInspect', ['template_id']),
    'template_bind': ('templateBind', ['template_id', 'dataset_id', 'variable_mapping', 'selection_policy']),
}
REGISTRATION = {
    'api_id': 'DATASET_CURVE_FIT_API_v1', 'api_version': 1,
    'provider_kind': 'module', 'provider_id': 'viewer.dataset_curve_fit',
    'documentation_ref': 'docs/api/DATASET_CURVE_FIT_API_v1.md',
    'capabilities': ['retained_profile_likelihood', 'guarded_rational_fitting', 'physical_surface_fitting', 'retained_surface_queries', 'sampled_surface_publication', 'public_native3d_render', 'model_documentation_cards', 'exact_preprocessing_rows', 'scientific_report', 'retained_model_queries', 'manual_parameter_view', 'safe_formula_recipes', 'implicit_equation_recipes', 'joint_complex_responses', 'residual_sequence', 'global_family_workflow', 'independent_family_fits', 'nested_f_tests', 'accepted_parameter_datasets', 'named_fit_acceptance', 'linked_retained_residuals', 'retained_parameter_bootstrap', 'retained_linear_influence', 'independent_model_export', 'named_fit_templates', 'fit_recipe_replay', 'durable_fit_results', 'validated_statistics', 'dataset_publication'],
    'operations': {name: {'name': name, 'summary': 'Public Fitter ' + name,
        'arguments': [{'name': arg, 'kind': 'public value', 'required': arg != 'accepted_name'} for arg in args],
        'argument_convention': ', '.join(args),
        'result_contract': ('Read-only gxtxt.fitter_model_card.v1 records; no scientific state change' if name == 'model_cards' else 'Inert recipe, durable result reference or validated result metadata')}
        for name, (_, args) in _OPS.items()},
}


def _template(host, raw):
    result = host.as_dict(raw)
    result['producers'] = host.as_dict(result['producers'])
    result['requirements'] = {name: host.as_dict(value) for name, value in host.as_dict(result['requirements']).items()}
    for key in ('region_count', 'manual_row_count'):
        result[key] = int(result[key])
    return result


def invoke(host, operation, args):
    if operation not in _OPS or (len(args) != len(_OPS[operation][1]) and not (operation in ('recipe_run', 'registered_accept') and len(args) == len(_OPS[operation][1]) - 1)):
        raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Invalid Fitter operation arguments')
    host.call('::GX::modulePublicApiActivate', 'viewer.dataset_curve_fit', 'DATASET_CURVE_FIT_API_v1')
    if operation == 'registered_run':
        spec = importlib.util.spec_from_file_location('gxtxt_fitter_registered_consumer', Path(__file__).with_name('registered_model_consumer.py'))
        consumer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(consumer)
        return consumer.run(host, *args)
    if operation == 'registered_parameter_run':
        spec = importlib.util.spec_from_file_location('gxtxt_fitter_parameter_consumer', Path(__file__).with_name('registered_parameter_consumer.py'))
        consumer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(consumer)
        return consumer.run(host, *args)
    if operation == 'registered_query_run':
        spec = importlib.util.spec_from_file_location('gxtxt_fitter_query_consumer', Path(__file__).with_name('registered_query_consumer.py'))
        consumer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(consumer)
        return consumer.run(host, *args)
    if operation == 'surface_query' and isinstance(args[1], NumericArray):
        import numpy as np
        coordinates = args[1]
        if len(coordinates.shape) != 2 or coordinates.shape[1] != 2:
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments', 'Surface coordinates require an N-by-2 array')
        args = list(args)
        args[1] = np.asarray(coordinates.values).reshape(coordinates.shape, order='F').tolist()
    raw = host.call('::GX::DatasetCurveFit::' + _OPS[operation][0], *args)
    if operation.startswith('surface_'):
        return _surface(host, operation, raw)
    if operation == 'dataset_suggestions':
        spec = importlib.util.spec_from_file_location('gxtxt_suggestion_semantics_binding', Path(__file__).resolve().parents[4] / 'core/script_bindings/statistical_result_semantics.py')
        binding = importlib.util.module_from_spec(spec);spec.loader.exec_module(binding)
        result = host.as_dict(raw);result['interpretation'] = binding._fit_suggestions(host, result['interpretation'])
        for key in ('schema', 'report', 'source_receipt_utf8'): result[key] = str(host.tcl.call('format', '%s', result[key]))
        return result
    if operation in ('result_plausibility', 'plausibility_definitions'):
        spec = importlib.util.spec_from_file_location('gxtxt_physical_semantics_binding', Path(__file__).resolve().parents[4] / 'core/script_bindings/statistical_result_semantics.py')
        binding = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(binding)
        result = host.as_dict(raw)
        if operation == 'result_plausibility':
            result['interpretation'] = binding._physical_fields(host, result['interpretation'])
            result['receipt_utf8'] = bytes(result['receipt_utf8']).decode('utf-8')
            result['report'] = str(host.tcl.call('format', '%s', result['report']))
        else:
            result['parameters'] = binding._parameters(host, result['parameters'])
            result['rules'] = [binding._physical_fields(host, rule) for rule in host.as_list(result['rules'])]
            result['context'] = binding._physical_fields(host, result['context'])
            result['omitted_suggestion_count'] = int(result['omitted_suggestion_count'])
        return result
    if operation in ('result_derived', 'derived_definitions'):
        spec = importlib.util.spec_from_file_location('gxtxt_derived_semantics_binding', Path(__file__).resolve().parents[4] / 'core/script_bindings/statistical_result_semantics.py')
        binding = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(binding)
        result = host.as_dict(raw)
        if operation == 'result_derived':
            result['interpretation'] = binding._derived_result(host, result['interpretation'])
            result['receipt_utf8'] = bytes(result['receipt_utf8']).decode('utf-8')
            result['report'] = str(host.tcl.call('format', '%s', result['report']))
        else:
            result['definitions'] = [binding._derived_definition(host, d) for d in host.as_list(result['definitions'])]
            result['parameters'] = binding._parameters(host, result['parameters'])
        return result
    if operation == 'result_workbench':
        result = host.as_dict(raw)
        result['coordinate_units'] = [str(v) for v in host.as_list(result['coordinate_units'])]
        result['parameter_domain'] = NumericArray([float(v) for v in host.as_list(result['parameter_domain'])])
        result['source_reference'] = host.as_dict(result['source_reference'])
        for field in ('independent_resources', 'fit_performed'):
            result[field] = bool(int(result[field]))
        return result
    if operation == 'model_cards':
        return [{**host.as_dict(card), 'documentation_only': True} for card in host.as_list(raw)]
    if operation == 'registered_models':
        return [_registered(host, value) for value in host.as_list(raw)]
    if operation in ('registered_model_describe', 'registered_model_declare'):
        return _registered(host, raw)
    if operation in ('recipe_capture', 'recipe_script', 'global_family_recipe'):
        return raw.decode('utf-8') if isinstance(raw, bytes) else str(raw)
    if operation in ('recipe_parameters_set', 'result_report'):
        return raw.decode('utf-8') if isinstance(raw, bytes) else str(raw)
    if operation == 'recipe_parameter_view':
        result = host.as_dict(raw)
        result['parameter_ids'] = [str(value) for value in host.as_list(result['parameter_ids'])]
        for key in ('current_parameters', 'suggested_parameters', 'lower_bounds', 'upper_bounds', 'translation'):
            result[key] = NumericArray([float(value) for value in host.as_list(result[key])])
        result['fixed_mask'] = NumericArray([int(value) for value in host.as_list(result['fixed_mask'])])
        for key in ('observation_count', 'display_count'):
            result[key] = int(result[key])
        result['nonlinear_optimization'] = bool(int(result['nonlinear_optimization']))
        if 'curve' in result:
            curve = host.as_dict(result['curve'])
            curve['parameters'] = NumericArray([float(value) for value in host.as_list(curve['parameters'])])
            rows = [[float(value) for value in host.as_list(row)] for row in host.as_list(curve['points'])]
            curve['points'] = NumericArray([row[col] for col in range(2) for row in rows], [len(rows), 2])
            curve['display_count'] = int(curve['display_count'])
            curve['nonlinear_optimization'] = bool(int(curve['nonlinear_optimization']))
            curve['accepted'] = bool(int(curve['accepted']))
            result['curve'] = curve
        return result
    if operation == 'template_list':
        return [_template(host, value) for value in host.as_list(raw)]
    if operation in ('template_create', 'template_inspect'):
        return _template(host, raw)
    if operation == 'result_residual_page':
        return _fit_result_pages(host, raw, 'FITTER_RESIDUAL_PAGE_v1', ('residuals', 'source_rows'))
    if operation == 'result_influence_page':
        return _fit_result_pages(host, raw, 'FITTER_INFLUENCE_PAGE_v1', ('diagnostics', 'input_rows', 'source_rows'))
    if operation == 'result_profile_page':
        result = _fit_result_pages(host, raw, 'FITTER_PROFILE_PAGE_v1', ('trial_values', 'trial_parameters', 'trial_status'))
        result['trial_messages_utf8'] = str(host.tcl.call('format', '%s%s', host.tcl.call('dict', 'get', raw, 'trial_messages_utf8'), ''))
        return result
    if operation == 'result_bootstrap_page':
        return _fit_result_pages(host, raw, 'FITTER_BOOTSTRAP_PAGE_v1', ('parameter_samples', 'replicate_status', 'replicate_seed'))
    result = host.as_dict(raw)
    if operation == 'result_preprocessing_rows':
        for field in ('start','total','count'):
            result[field] = int(result[field])
        rows = result['source_rows']
        rows = [rows] if isinstance(rows,int) else host.as_list(rows)
        result['source_rows'] = NumericArray([int(v) for v in rows],dtype='uint64')
        return result
    if operation in ('result_query', 'result_inverse'):
        result['reference'] = host.as_dict(result['reference'])
        result['context'] = host.as_dict(result['context'])
        for field in ('derivative_unit_plan', 'inverse_derivative_unit_plan'):
            plan = host.as_dict(result['context'][field])
            for text in ('schema','status','numerator_unit','denominator_unit','requested_unit','output_unit','dimension_key','reason','offset_policy'):
                plan[text] = str(host.tcl.call('format', '%s%s', plan[text], ''))
            if plan['status'] == 'value':
                plan['scale'] = float(plan['scale'])
                for basis_name in ('numerator_basis', 'denominator_basis', 'output_basis'):
                    basis = host.as_dict(plan[basis_name])
                    for number in ('scale', 'affine_offset'):
                        basis[number] = float(basis[number])
                    for text in ('unit','canonical_unit','dimension_key'):
                        basis[text] = str(host.tcl.call('format', '%s%s', basis[text], ''))
                    plan[basis_name] = basis
            result['context'][field] = plan
        for field in ('query', 'predicted', 'domain', 'translation', 'is_extrapolated', 'derivative', 'derivative_valid', 'inverse_derivative', 'inverse_derivative_valid', 'tangent_x', 'tangent_y', 'tangent_floors', 'model_response_derivative', 'interpreted_derivative', 'interpreted_inverse_derivative', 'interpreted_derivative_valid', 'interpreted_inverse_derivative_valid', 'targets', 'roots', 'valid', 'residual', 'bracket', 'iterations', 'function_evaluations', 'difference_step', 'queries', 'equation_values', 'independent_domain', 'branch_extrapolated'):
            if field in result:
                # Tcl can retain a scalar internal type for a one-element vector.
                values = result[field]
                values = [values] if isinstance(values, (int, float)) else host.as_list(values)
                result[field] = NumericArray([float(value) for value in values])
        if 'points' in result:
            rows = [[float(value) for value in host.as_list(row)] for row in host.as_list(result['points'])]
            result['points'] = NumericArray([row[col] for col in range(2) for row in rows], [len(rows), 2])
        if 'reasons' in result:
            result['reasons'] = host.as_list(result['reasons'])
        for field in ('fit_performed', 'uncertainty_available', 'parametric'):
            if field in result:
                result[field] = bool(int(result[field]))
        if 'response_index' in result:
            result['response_index'] = int(result['response_index'])
        for field in ('x_tolerance', 'response_tolerance', 'difference_relative_tolerance'):
            if field in result:
                result[field] = float(result[field])
        result['exact_query_count'] = int(result['exact_query_count'])
        return result
    if operation in ('result_nested_f', 'result_residual_sequence'):
        return host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1'].invoke(host, 'validated_result', [result])
    if operation in ('family_members', 'family_run'):
        result['api_version'] = int(result['api_version'])
        if operation == 'family_members':
            result['members'] = [str(host.tcl.call('format', '%s', value)) for value in host.as_list(result['members'])]
            result['source_identity'] = host.as_dict(result['source_identity'])
        else:
            members = []
            for value in host.as_list(result['members']):
                member = host.as_dict(value)
                member['member_value'] = str(host.tcl.call('format', '%s', member['member_value']))
                member['reference'] = host.as_dict(member['reference'])
                members.append(member)
            result['members'] = members
        return result
    if operation == 'result_parameters_publish':
        return host.record_publications(result)
    if operation == 'result_retransform':
        result.pop('path', None)
        result['row_count'] = int(result['row_count'])
        return host.record_publications(result)
    if operation == 'result_export':
        return {key: value.decode('utf-8') if isinstance(value, bytes) else str(value) for key, value in result.items()}
    if operation == 'template_bind':
        if isinstance(result['recipe'], bytes):
            result['recipe'] = result['recipe'].decode('ascii')
        result['review'] = host.as_dict(result['review'])
        result['review']['variable_mapping'] = host.as_dict(result['review']['variable_mapping'])
        for key in ('dropped_original_row_picks', 'source_filter_count', 'coordinate_region_count'):
            result['review'][key] = int(result['review'][key])
        for key in ('explicit_preview_required', 'explicit_accept_required'):
            result['review'][key] = bool(int(result['review'][key]))
    if operation == 'result_info':
        result['preprocessing'] = _preprocessing(host,result['preprocessing'])
        domain = host.as_dict(result['output_domain'])
        for field in ('schema','status','reason','reference_basis','boundary_policy','intrinsic_policy','coordinate_space','query_unit'):
            if field in domain:
                domain[field] = str(host.tcl.call('format','%s%s',domain[field],''))
        if domain['status'] == 'value':
            for field in ('row_count','outside_count'):
                domain[field] = int(domain[field])
            domain['reference_domain'] = NumericArray([float(value) for value in str(domain['reference_domain']).split(',')])
        result['output_domain'] = domain
        stats = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']
        result['statistical_results'] = {name: stats.invoke(host, 'validated_result', [host.as_dict(value)])
            for name, value in host.as_dict(result['statistical_results']).items()}
        parameters = str(result['parameters'])
        values = parameters.split(',') if ',' in parameters else host.as_list(result['parameters'])
        result['parameters'] = NumericArray([float(x) for x in values])
        result['reference'] = host.as_dict(result['reference'])
        result['template_binding'] = host.as_dict(result['template_binding'])
        if result['template_binding']:
            result['template_binding']['variable_mapping'] = host.as_dict(result['template_binding']['variable_mapping'])
            result['template_binding']['dropped_original_row_picks'] = int(result['template_binding']['dropped_original_row_picks'])
        if isinstance(result['recipe'], bytes):
            result['recipe'] = result['recipe'].decode('ascii')
        resources = host.as_dict(result['resources'])
        for name, value in resources.items():
            value = host.as_dict(value)
            value['metadata'] = host.as_dict(value['metadata'])
            value['size_bytes'] = int(value['size_bytes'])
            resources[name] = value
        result['resources'] = resources
    return result


def _surface(host, operation, raw):
    def text(value):
        return value.decode('utf-8') if isinstance(value, bytes) else str(host.tcl.call('format', '%s', value))
    def vector(value, dtype='float64'):
        values = [value] if isinstance(value, (int, float)) else host.as_list(value)
        cast = int if dtype.startswith(('int', 'uint')) else float
        return NumericArray([cast(v) for v in values], dtype=dtype)
    def matrix(value, columns):
        import numpy as np
        def parts(row):
            return [row] if isinstance(row, (int, float)) else host.as_list(row)
        values = host.as_list(value)
        if values and all(len(parts(row)) == columns for row in values):
            rows = [[float(v) for v in parts(row)] for row in values]
        else:
            rows = np.asarray([float(v) for v in values]).reshape(-1, columns).tolist()
        a = np.asarray(rows, dtype=float).reshape(-1, columns)
        return NumericArray(a.ravel(order='F'), list(a.shape))
    if operation in ('surface_recipe_capture', 'surface_report'):
        return text(raw)
    if operation == 'surface_residual_page':
        return _fit_result_pages(host, raw, 'FITTER_SURFACE_RESIDUAL_PAGE_v1', ('residuals', 'source_rows'))
    result = host.as_dict(raw)
    if operation == 'surface_export':
        return {key: host.as_dict(value) if key == 'reference' else text(value) for key, value in result.items()}
    if operation == 'surface_create':
        # Workspace payloads remain with their canonical owner.
        return {key: text(result[key]) for key in ('workspace_id', 'provider_id', 'name', 'generation') if key in result}
    if operation in ('surface_accept', 'surface_reference', 'surface_recipe_run', 'surface_plot'):
        return {key: text(value) for key, value in result.items()}
    if 'statistics' in result:
        result['statistics'] = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1'].invoke(host, 'validated_result', [host.as_dict(result['statistics'])])
    if 'reference' in result:
        result['reference'] = host.as_dict(result['reference'])
    if 'domain' in result:
        result['domain'] = matrix(result['domain'], 2)
    for field in ('fit_performed', 'interpolation_performed'):
        if field in result: result[field] = bool(int(result[field]))
    if operation == 'surface_info':
        result['original_shape'] = vector(result['original_shape'], 'uint64')
        result['recipe'] = text(result['recipe'])
        resources = {}
        for name, value in host.as_dict(result['resources']).items():
            ref = host.as_dict(value);ref['size_bytes'] = int(ref['size_bytes'])
            metadata = host.as_dict(ref['metadata'])
            if 'shape' in metadata: metadata['shape'] = vector(metadata['shape'], 'uint64')
            for field in ('column_ids', 'column_units'):
                if field in metadata: metadata[field] = [text(v) for v in host.as_list(metadata[field])]
            ref['metadata'] = metadata;resources[name] = ref
        result['resources'] = resources
    if operation == 'surface_query':
        result['exact_query_count'] = int(result['exact_query_count'])
        for field in ('predicted', 'is_extrapolated'):
            result[field] = vector(result[field])
        for field, width in (('coordinates', 2), ('points', 3)):
            result[field] = matrix(result[field], width)
        for field in ('coordinate_units', 'parameter_ids', 'predictor_ids'):
            result[field] = [text(v) for v in host.as_list(result[field])]
        if 'jacobian' in result:
            result['jacobian'] = matrix(result['jacobian'], len(result['parameter_ids']))
    if operation == 'surface_publish':
        result.pop('path', None)
        receipt = host.as_dict(result['surface'])
        for field in ('reference', 'dataset_identity'): receipt[field] = host.as_dict(receipt[field])
        receipt['shape'] = vector(receipt['shape'], 'uint64')
        receipt['coordinate_units'] = [text(v) for v in host.as_list(receipt['coordinate_units'])]
        for field in ('fit_performed', 'interpolation_performed'): receipt[field] = bool(int(receipt[field]))
        result['surface'] = receipt
        if 'variable_count' in result: result['variable_count'] = int(result['variable_count'])
        return host.record_publications(result)
    return result


def _preprocessing(host, raw):
    result = host.as_dict(raw)
    for field in ('schema','status','reason','row_identity_kind','original_count_status','finite_policy','duplicate_policy','order_policy'):
        if field in result:
            result[field] = str(host.tcl.call('format','%s%s',result[field],''))
    if result['status'] != 'value':
        return result
    for field in ('original_count','filtered_count','finite_count','selected_count','nonfinite_count','selection_excluded_count','fit_count','model_input_count'):
        result[field] = int(result[field])
    if 'region_count' in result:result['region_count'] = int(result['region_count'])
    result['stages'] = host.as_dict(result['stages'])
    result['excluded_ids'] = {str(key):host.as_dict(value) for key,value in host.as_dict(result['excluded_ids']).items()}
    for spec in result['excluded_ids'].values():
        for key in ('start','stop_exclusive'):
            if key in spec:spec[key] = int(spec[key])
    policy = host.as_dict(result['model_policy'])
    policy['removed_terminal_endpoint'] = bool(int(float(policy['removed_terminal_endpoint'])))
    for field in ('observation_count','model_input_count'):
        if field in policy:policy[field] = int(float(policy[field]))
    result['model_policy'] = policy
    if 'coordinate_transform' in result:
        transform = host.as_dict(result['coordinate_transform'])
        for field in ('smoothing','baseline_correction','response_transform'):
            transform[field] = host.as_dict(transform[field])
        transform['source_axes'] = {str(k):host.as_dict(v) for k,v in host.as_dict(transform['source_axes']).items()}
        translation = host.as_dict(transform['translation'])
        for axis in ('u','v'):translation[axis] = host.as_dict(translation[axis])
        transform['translation'] = translation
        result['coordinate_transform'] = transform
    for key in ('source_request','selection_descriptor'):
        result[key] = host.as_dict(result[key])
    source = host.as_dict(result['source'])
    if 'request' in source:
        source['request'] = host.as_dict(source['request'])
        if 'filters' in source['request']:
            source['request']['filters'] = [host.as_dict(v) for v in host.as_list(source['request']['filters'])]
    for field in ('variables','source_identities'):
        if field in source:source[field] = [host.as_dict(v) for v in host.as_list(source[field])]
    for field in ('row_count','display_budget'):
        if field in source:source[field] = int(source[field])
    if 'display_is_scientific_data' in source:source['display_is_scientific_data'] = False
    result['source'] = source
    return result


def _registered(host, raw):
    result = host.as_dict(raw)
    if 'definition' in result:
        definition = host.as_dict(result['definition'])
        for key in ('parameter_ids','parameter_units','predictor_shape','response_shape','parameter_shape'):
            definition[key] = [str(v) for v in host.as_list(definition[key])]
        for key in ('initial','lower_bounds','upper_bounds'):
            definition[key] = NumericArray([float(v) for v in host.as_list(definition[key])])
        if 'fixed_mask' in definition:
            definition['fixed_mask'] = NumericArray([int(v) for v in host.as_list(definition['fixed_mask'])])
        result['definition'] = definition
    if 'revision' in result:
        result['revision'] = int(result['revision'])
    for key in ('declaration',):
        if isinstance(result.get(key), bytes):
            result[key] = result[key].decode('ascii')
    return result


def _fit_result_pages(host, raw, api_id, names):
    import numpy as np
    from gxtxt_scientific_binary_v1 import DTYPES
    stats = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']
    # Preserve Tcl bytearrays inside nested pages; as_dict textifies nested Tcl objects.
    get = lambda value, key: host.tcl.call('dict', 'get', value, key)
    result = {'api_id': api_id, 'api_version': int(get(raw, 'api_version'))}
    result['meaning'] = stats.invoke(host, 'validated_result', [host.as_dict(get(raw, 'meaning'))])
    if bool(int(host.tcl.call('dict', 'exists', raw, 'physical_column_units'))):
        result['physical_column_units'] = [str(v) for v in host.as_list(get(raw, 'physical_column_units'))]
        result['meaning_scope'] = str(get(raw, 'meaning_scope'))
        projection = host.as_dict(get(raw, 'display_projection'))
        if 'reference' in projection:
            projection['reference'] = host.as_dict(projection['reference'])
            projection['reference']['value'] = float(projection['reference']['value'])
        result['display_projection'] = projection
    for name in names:
        nested = get(raw, name)
        page = {str(key): get(nested, key) for key in host.as_list(host.tcl.call('dict', 'keys', nested))}
        columns = [str(v) for v in host.as_list(page['columns'])]
        rows = int(page['row_count']); dtype_name = str(page['dtype'])
        dtype = DTYPES[dtype_name]; payload = page.pop('bytes')
        if rows == 0 and payload == '':
            payload = b''
        if not isinstance(payload, bytes) or len(payload) != rows * len(columns) * np.dtype(dtype).itemsize:
            raise BridgeError('GXTXT:ScriptBridge:Transport', 'Fit result page lost its owned binary shape')
        values = np.frombuffer(payload, dtype=dtype).reshape(rows, len(columns))
        result[name] = {'values': NumericArray(values.ravel(order='F'), [rows, len(columns)], dtype=dtype_name),
                        'columns': columns, 'dtype': dtype_name, 'start': int(page['start']),
                        'row_count': rows, 'total_rows': int(page['total_rows']),
                        'source_sha256': str(page['source_sha256'])}
    return result
