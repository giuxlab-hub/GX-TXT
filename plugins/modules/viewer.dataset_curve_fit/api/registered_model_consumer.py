"""Registered Fitter orchestration over CORE rows/resources and public Numeric.

Only this host adapter sees the temporary CORE numeric-input descriptor. Its
files are mapped inside curveSourceWithNumericInput and never reach user code.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import uuid
import numpy as np
from gxtxt_script_bridge_server import BridgeError, NumericArray, CallbackRef


def _wire(value):
    value = np.asarray(value)
    if value.ndim == 1:
        value = value.reshape(-1, 1)
    return NumericArray(value.ravel(order='F'), list(value.shape))


def _array(value):
    return value.values.reshape(value.shape, order='F') if isinstance(value, NumericArray) else np.asarray(value)


def run(host, callback, payload):
    if not isinstance(callback, CallbackRef) or not isinstance(payload, str):
        raise BridgeError('GXTXT:Fitter:RegisteredModel', 'A registered Job requires its live callback and inert recipe envelope')
    identity = host.modules['SCRIPT_EXECUTION_API_v1'].invoke(host, 'current_callable', [])
    prepared = host.as_dict(host.call('::GX::DatasetCurveFit::_registeredPrepare', payload, identity))
    key = str(prepared['key'])
    fit = host.as_dict(prepared['fit'])
    options = host.as_dict(fit['options'])
    registered = host.as_dict(prepared['registered'])
    definition = host.as_dict(registered['definition'])
    document = str(prepared['document_id'])
    command = '::GX::DatasetCurveFit::registeredInput_' + uuid.uuid4().hex
    captured = {}

    def consume(raw_input, raw_binding):
        try:
            captured['report'] = _compute(host, callback, host.as_dict(raw_input),
                host.as_dict(raw_binding), fit, options, registered, definition, document)
        except BaseException as error:
            captured['error'] = error
        return ''

    host.tcl.createcommand(command, consume)
    try:
        host.call('::GX::DatasetCurveFit::_registeredWithInput', key, command)
        if 'error' in captured:
            raise captured['error']
        report, model, query, bootstrap_input = captured['report']
        report = host.as_dict(host.call('::GX::DatasetCurveFit::_registeredInterpret', key, report))
        _bootstrap(host, document, report, model, bootstrap_input, options)
        _prediction(host, document, report, model, query, options)
        result = host.as_dict(host.call('::GX::DatasetCurveFit::_registeredFinish', key, report))
        return {name: (False if name == 'accepted' else str(value)) for name, value in result.items()}
    finally:
        host.tcl.tk.deletecommand(command)
        host.call('::GX::DatasetCurveFit::close', key)


def _compute(host, callback, source, binding, fit, options, registered, definition, document):
    numeric = host.modules['NUMERIC_API_v1']
    resources = host.modules['MANAGED_RESOURCE_API_v1']
    mapped = []

    def call(operation, *args):
        return numeric.invoke(host, operation, list(args))

    def rows(descriptor, field, dtype, columns=1):
        count = int(descriptor['row_count'])
        array = np.memmap(str(descriptor[field]), mode='r', dtype=dtype, shape=(count, columns))
        mapped.append(array)
        return array

    def store(values, columns, fmt, role):
        return resources.invoke(host, 'write_numeric', [document, columns, _wire(values), {'format':fmt, 'role':role}])

    try:
        if source['api_id'] != 'CURVE_SOURCE_NUMERIC_INPUT_v1':
            raise ValueError('Expected the CORE exact numeric input contract')
        training = host.as_dict(source['training']) if fit['scope'] == 'selected' else source
        physical = rows(source, 'xy_file', '<f8', 2)
        train = rows(training, 'xy_file', '<f8', 2)
        source_rows = rows(source, 'source_rows_file', '<u8')
        train_rows = rows(training, 'source_rows_file', '<u8')
        source_rows_resource = store(source_rows, ['source_row_ordinal'], 'uint64_le', 'source_rows')
        report = {'model':'registered', 'parametric':0, 'source_n':len(physical), 'exact_source_rows':len(physical),
                  'display_is_scientific_data':0, 'residual_stride':4, 'source_rows_resource':source_rows_resource}
        weights = np.ones(len(train), dtype=float)
        solver = {'response_shape':'column', 'lower_bounds':_wire([float(v) for v in host.as_list(definition['lower_bounds'])]),
                  'upper_bounds':_wire([float(v) for v in host.as_list(definition['upper_bounds'])])}
        if 'fixed_mask' in definition:
            solver['fixed_mask'] = _wire([float(v) for v in host.as_list(definition['fixed_mask'])])
        policy = host.as_dict(host.call('::GX::DatasetCurveFit::_registeredSolverOptions', definition, options))
        for field in ('solver', 'method'):
            solver[field] = str(policy[field])
        solver['max_function_evaluations'] = int(policy['max_function_evaluations'])
        for field in ('function_tolerance', 'gradient_tolerance', 'parameter_tolerance'):
            solver[field] = float(policy[field])
        if policy['parameter_scales']:
            solver['parameter_scales'] = _wire([float(v) for v in host.as_list(policy['parameter_scales'])])
        if binding:
            companions = host.as_dict(training['companion_columns'])
            column = host.as_dict(companions['measurement'])
            original = rows(dict(column, row_count=len(train)), 'file', '<f8').ravel()
            converted = original * float(binding['scale_factor'])
            finite = np.isfinite(converted)
            kind = str(binding['kind'])
            if not np.all(finite) and binding['nonfinite'] != 'omit':
                raise ValueError('Nonfinite training measurement; choose explicit omission to retain its row receipt')
            if np.any(converted[finite] < 0) or (kind == 'sigma' and np.any(converted[finite] == 0)):
                raise ValueError('Sigma must be positive; relative precision must be nonnegative')
            used = finite & (converted > 0)
            effective = np.zeros(len(train), dtype=float)
            effective[used] = 1/converted[used]**2 if kind == 'sigma' else converted[used]
            if not np.all(np.isfinite(effective)):
                raise ValueError('Effective measurement precision is outside finite binary64 range')
            report['measurement_binding'] = binding
            report['measurement_selection'] = {'kind':kind, 'nonfinite_policy':str(binding['nonfinite']),
                'scale_factor':float(binding['scale_factor']), 'input_count':len(train), 'fit_count':int(np.count_nonzero(used)),
                'omitted_nonfinite_count':int(np.count_nonzero(~finite)), 'zero_precision_count':int(np.count_nonzero(finite & ~used)),
                'weight_semantics':'inverse_variance' if kind == 'sigma' else 'relative'}
            report['measurement_resource'] = store(np.column_stack((original, converted, effective, used)),
                ['original_measurement','converted_measurement','effective_weight','used_for_fit'], 'float64_interleaved_le','training_measurement')
            report['measurement_rows_resource'] = store(train_rows, ['source_row_ordinal'], 'uint64_le','measurement_rows')
            train = train[used]
            train_rows = train_rows[used]
            weights = effective[used]
            solver['sigma' if kind == 'sigma' else 'weights'] = _wire(converted[used])
            report['training_rows_resource'] = store(train_rows, ['source_row_ordinal'], 'uint64_le','training_rows')
        order = [1,0] if options.get('orientation','y_of_x') == 'x_of_y' else [0,1]
        x,y = train[:,order[0]],train[:,order[1]]
        training_receipt = call('positive_translation', _wire(x), {'mode':'off'})
        training_domain = _array(training_receipt['original_bounds']).ravel()
        report['training_domain'] = ','.join(format(float(v), '.17g') for v in training_domain)
        report['training_domain_basis'] = 'exact_eligible_observations'
        sx,sy = physical[:,order[0]],physical[:,order[1]]
        domain = fit['domain']
        if domain == 'source':
            query = np.unique(sx)
        else:
            lo,hi,count = host.as_list(domain)
            query = _array(call('uniform_grid',float(lo),float(hi),int(count),{'mode':'count'})['x']).ravel()
        if len(query) < 2:
            raise ValueError('Registered model output needs at least two distinct independent values')
        for axis, values in [('u',np.concatenate((x,sx,query))),('v',np.concatenate((y,sy)))]:
            spec = host.as_dict(options.get('translation_'+axis, 'mode off delta 0'))
            translation = call('positive_translation',_wire(values),{'mode':str(spec['mode']),'delta':float(spec.get('delta',0))})
            report['translation_algorithm'] = str(translation['algorithm'])
            for field in ('mode','delta','margin','original_bounds','transformed_bounds'):
                value = translation[field]
                if isinstance(value, NumericArray):
                    value = ','.join(format(v,'.17g') for v in value.values)
                report['translation_'+axis+'_'+field] = value
        du,dv = report['translation_u_delta'],report['translation_v_delta']
        if definition['predictor_domain'] == 'positive_real' and min(np.min(x+du),np.min(sx+du),np.min(query+du)) <= 0:
            raise ValueError('Registered model requires strictly positive translated predictors throughout training and evaluation')
        raw = call('nonlinear_fit',_wire(x+du),_wire(y+dv),callback,
                   _wire([float(v) for v in host.as_list(fit['initial'])]),solver)
        parameters = _array(raw['parameters']).ravel()
        state = {'kind':'registered_callback','schema_version':1,'parameters':raw['parameters'],
            'parameter_ids':[str(v) for v in host.as_list(definition['parameter_ids'])],
            'parameter_units':[str(v) for v in host.as_list(definition['parameter_units'])],
            'source_sha256':str(registered['source_sha256']),'binding_sha256':str(registered['declaration_sha256']),
            'predictor_domain':str(definition['predictor_domain']),
            'lower_bounds':solver['lower_bounds'],'upper_bounds':solver['upper_bounds'],
            'fixed_mask':raw['fixed_mask'],
            'initial_parameters':_wire([float(v) for v in host.as_list(fit['initial'])]),
            'solver':('scipy.optimize.least_squares' if raw['solver']=='least_squares' else str(raw['solver'])),
            'iterations':raw['iterations'],'converged':raw['converged'],
            'exitflag':raw['exitflag'],'function_evaluations':raw['function_evaluations'],'message':raw['solver_message']}
        live = dict(state, callback=callback)
        prediction = _array(call('nonlinear_evaluate',live,_wire(query+du))['predicted']).ravel()-dv
        source_prediction = _array(call('nonlinear_evaluate',live,_wire(sx+du))['predicted']).ravel()-dv
        train_prediction = _array(raw['predicted']).ravel()-dv
        geometry = np.column_stack((prediction,query)) if order[0] else np.column_stack((query,prediction))
        operand = lambda values: {'kind':'vector','value':_wire(values)}
        below = call('array_compare','less_than',operand(query),{'kind':'scalar','value':float(training_domain[0])})['values']
        above = call('array_compare','greater_than',operand(query),{'kind':'scalar','value':float(training_domain[1])})['values']
        outside = _array(call('array_mask','logical_or',{'kind':'vector','value':below},{'kind':'vector','value':above})['values']).ravel()
        outside_count = _array(call('array_reduce','count_true',operand(outside))['values']).ravel()[0]
        report['output_extrapolated_count'] = int(outside_count)
        report['output_domain_resource'] = store(np.column_stack((query,outside)),['fit_query','is_extrapolated'],'float64_interleaved_le','fitted_output_domain')
        report['preview_geometry_resource'] = store(geometry,['x','y'],'native2d.float64_xy_le_v1','registered_preview')
        report['preview_residual_plot_resource'] = store(np.column_stack((sx,sy-source_prediction)),['x','y'],'native2d.float64_xy_le_v1','registered_residual_plot')
        residual_columns = ['source_x','source_y','fitted_x','x_residual'] if order[0] else ['source_x','source_y','fitted_y','y_residual']
        report['residual_resource'] = store(np.column_stack((physical,source_prediction,sy-source_prediction)),residual_columns,'float64_interleaved_le','registered_residual')
        report['residual_columns'] = ','.join(residual_columns)
        report['comparison_rows_resource'] = store(train_rows,['source_row_ordinal'],'uint64_le','comparison_rows')
        policy = call('fit_input_policy','registered',state)
        policy.update(observation_count=len(train_rows),model_input_count=len(train_rows))
        report['model_input_policy'] = policy
        report['preprocessing_model_rows_resource'] = report['comparison_rows_resource']
        known = {field:report[field] for field in ('source_rows_resource','comparison_rows_resource','preprocessing_model_rows_resource')}
        captured = host.as_dict(host.call('::GX::DatasetCurveFit::_preprocessingCapture',document,source,training,known,policy))
        # Tcl captures owned resource references; restore their host dictionary
        # form before subsequent Python consumers access hash/shape metadata.
        for field, value in captured.items():
            if field.endswith('_resource'):
                value = host.as_dict(value)
                value['metadata'] = host.as_dict(value['metadata'])
            report[field] = value
        report['comparison_input'] = {'source_sha256':str(host.call('::GX::sha256File',source['xy_file'])),
                                      'rows_sha256':report['comparison_rows_resource']['sha256']}
        signature = call('fit_observation_signature',_wire(y),_wire(weights),dv,_wire(x))
        raw['observation_signature'] = call('fit_observation_signature',_wire(y+dv),_wire(weights),_wire([]),_wire(x+du))
        facts = {'fit':{k:v for k,v in raw.items() if k not in ('predicted','residuals','weighted_residuals','jacobian')},
                 'physical_observation_signature':signature}
        for role,observed,predicted in [('training',y,train_prediction),('evaluation',sy,source_prediction)]:
            metrics = call('residual_metrics',_wire(observed),_wire(predicted),{})
            facts[role] = {field:metrics[field] for field in ('n','rmse','mae','max_abs_error','response_variance')}
            facts[role]['r_squared'] = metrics['r2']
        if binding:
            facts['training']['r_squared'] = raw['r_squared']
            facts['training']['response_variance'] = raw['response_variance']
        report.update(parameters=','.join(format(v,'.17g') for v in parameters),registered_model_state=state,
                      numeric_statistics=facts,output_n=len(query),converged=raw['converged'],
                      grid_kind='source' if domain == 'source' else 'range',residual_convention='observed_minus_fitted',
                      export_domain=','.join(format(v,'.17g') for v in (query[0],query[-1])),model_state_json='')
        receipt = host.as_dict(host.call('::GX::DatasetCurveFit::_outputDomainAttach',
            {key:report[key] for key in ('output_n','output_extrapolated_count','training_domain','training_domain_basis')}))
        report['output_domain'] = host.as_dict(receipt['output_domain'])
        # These owned arrays must outlive the temporary mapped CORE source.
        bootstrap_input = (_wire(x+du), _wire(y+dv), _wire(weights.copy())) if options.get('bootstrap') else None
        return report, live, query, bootstrap_input
    finally:
        for array in mapped:
            array._mmap.close()


def _bootstrap(host, document, report, model, inputs, options):
    """Keep bootstrap science in CORE/Numeric and retain its three typed ledgers."""
    if inputs is None:
        return
    statistics = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']
    numeric = host.modules['NUMERIC_API_v1']
    meanings = host.as_dict(report['statistical_results'])
    source = meanings['training']
    settings = host.as_dict(options['bootstrap'])
    plan = statistics.invoke(host, 'bootstrap_plan', [source, settings])
    if plan['status'] != 'value':
        raise BridgeError('GXTXT:Fitter:Bootstrap', plan['reason'])
    predictors, response, weights = inputs
    input_options = {} if plan['weight_semantics'] == 'unweighted' else {'weights': weights}
    raw = numeric.invoke(host, 'fit_bootstrap', [model, predictors, response, plan, input_options])
    receipt = {key: value for key, value in raw.items()
               if key not in ('parameter_samples', 'replicate_status', 'replicate_seed')}
    meaning = host.call('::GX::StatisticsV1::bootstrapInterpretation', source, receipt)
    meanings['bootstrap'] = meaning
    report['statistical_results'] = meanings
    exact = host.as_dict(host.as_dict(meaning)['request'])['numeric']
    digest = str(host.call('::GX::DatasetCurveFit::_numericStateDigest', exact))
    binding = host.as_dict(report['observation_binding'])
    resources = host.modules['MANAGED_RESOURCE_API_v1']
    for field, array, columns, role in (
            ('bootstrap_parameters_resource', 'parameter_samples', plan['parameter_ids'], 'parameter_bootstrap_draws'),
            ('bootstrap_status_resource', 'replicate_status', ['replicate_status'], 'parameter_bootstrap_status'),
            ('bootstrap_seed_resource', 'replicate_seed', ['replicate_seed'], 'parameter_bootstrap_seed')):
        metadata = dict(role=role, numeric_receipt_sha256=digest,
                        source_sha256=binding['source_sha256'], training_rows_sha256=binding['rows_sha256'])
        report[field] = resources.invoke(host, 'write_numeric', [document, columns, raw[array], metadata])


def _prediction(host, document, report, model, query, options):
    """Adapt existing CORE inference and Numeric propagation to owned resources."""
    kind = str(options.get('prediction_band', 'none'))
    if kind == 'none':
        return
    statistics = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']
    meanings = host.as_dict(report['statistical_results'])
    source = meanings['training']
    confidence = float(options.get('confidence', .95))
    plan = statistics.invoke(host, 'prediction_inference_plan', [source, kind, confidence])
    # Keep the CORE's exact Tcl representation for persisted validation.
    report['prediction_plan'] = host.call('::GX::StatisticsV1::predictionInferencePlan', source, kind, confidence)
    if plan['status'] != 'value':
        return
    numeric = host.modules['NUMERIC_API_v1']
    settings = {field: _wire([float(v) for v in host.as_list(options[field])])
                for field in ('prediction_sigma', 'prediction_weights') if options.get(field)}
    prediction = numeric.invoke(host, 'prediction_uncertainty', [model,
        _wire(query + float(report['translation_u_delta'])), plan, settings])
    arrays = ('predicted', 'lower', 'upper', 'mean_standard_error', 'standard_error',
              'observation_standard_deviation', 'bounds_available')
    values = {field: _array(prediction[field]).ravel() for field in arrays}
    for field in ('predicted', 'lower', 'upper'):
        values[field] = values[field] - float(report['translation_v_delta'])
    available = values['bounds_available'].astype(bool)
    if (not np.all(np.isfinite(values['predicted'])) or
            any(not np.all(np.isfinite(values[field][available])) for field in ('lower', 'upper'))):
        raise ValueError('Physical interval coordinates are not finitely representable')
    receipt = {k: v for k, v in prediction.items() if k not in (*arrays, 'query_index')}
    meanings['prediction'] = host.call('::GX::StatisticsV1::predictionInterpretation', source, receipt)
    report['statistical_results'] = meanings
    report['prediction_display_note'] = ('Boundary curves show the recorded pointwise interval; '
        'they do not form a simultaneous confidence region')
    resources = host.modules['MANAGED_RESOURCE_API_v1']
    def store(data, columns, fmt, role):
        return resources.invoke(host, 'write_numeric', [document, columns, _wire(data), {'format': fmt, 'role': role}])
    report['prediction_resource'] = store(np.column_stack((query, *(values[field] for field in arrays))),
        ['prediction_query', 'prediction_mean', 'prediction_lower', 'prediction_upper',
         'prediction_mean_se', 'prediction_se', 'prediction_noise_sd', 'prediction_available'],
        'float64_interleaved_le', 'registered_prediction')
    selected = np.flatnonzero(available)
    if len(selected):
        gaps = np.r_[0, np.diff(selected) > 1].astype(np.uint8)
        report['prediction_gap_resource'] = store(gaps, ['break_before'], 'native2d.uint8_break_before_v1', 'prediction_gaps')
        for boundary in ('lower', 'upper'):
            columns = (values[boundary][available], query[available]) if report['orientation'] == 'x_of_y' else (query[available], values[boundary][available])
            report['prediction_' + boundary + '_resource'] = store(np.column_stack(columns), ['x', 'y'],
                'native2d.float64_xy_le_v1', 'prediction_' + boundary)
