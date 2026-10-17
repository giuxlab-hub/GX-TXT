"""Public family workflow adapter; the existing standard runtime owns the work."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_OPS = {'api_info': ('apiInfo', []), 'models': ('models', []), 'run': ('run', ['dataset_id', 'model_id', 'bindings', 'config']),
        'result_info': ('resultInfo', ['reference']),
        'recipe': ('recipe', ['dataset_id', 'model_id', 'bindings', 'config']),
        'recipe_validate': ('recipeValidate', ['encoded']), 'recipe_run': ('recipeRun', ['encoded']),
        'submit': ('submit', ['encoded', 'name']), 'job_result': ('jobResult', ['job_id']), 'results': ('results', [])}
REGISTRATION = dict(api_id='CURVE_FAMILY_API_v1', api_version=1,
    provider_kind='module', provider_id='curvefit.family_global',
    documentation_ref='plugins/modules/curvefit.family_global/CURVE_FAMILY_API_v1.md',
    capabilities=['family_recipes', 'supervised_family_jobs', 'global_family_fit', 'shared_local_fixed_parameters', 'frozen_family_evaluation', 'durable_family_results'],
    operations={name: dict(name=name, summary='Curve Family '+name,
        arguments=[dict(name=arg, kind='public value', required=True) for arg in args],
        argument_convention=', '.join(args), result_contract='Registered models or verified retained family result')
        for name, (_, args) in _OPS.items()})


def _text(host, value):
    return str(host.tcl.call('format', '%s', value))


def _map(host, raw):
    result = host.as_dict(raw)
    for key in ('base_parameter_ids', 'base_parameter_units', 'scopes', 'slot_ids', 'slot_units'):
        result[key] = [_text(host, v) for v in host.as_list(result[key])]
    for key in ('version', 'index_base', 'slot_limit', 'local_member_limit'):
        result[key] = int(result[key])
    result['has_local'] = bool(int(result['has_local']))
    for key in ('member_values', 'slot_base_indices', 'slot_member_indices', 'fixed_mask'):
        result[key] = NumericArray([float(v) for v in host.as_list(result[key])])
    rows = [host.as_list(row) for row in host.as_list(result['parameter_indices'])]
    n, m = len(rows), len(rows[0])
    result['parameter_indices'] = NumericArray([float(rows[i][j]) for j in range(m) for i in range(n)], [n, m])
    return result


def invoke(host, operation, args):
    if operation not in _OPS or len(args) != len(_OPS[operation][1]):
        raise BridgeError('GXTXT:CurveFamily:Arguments', 'Invalid public family arguments')
    if operation in ('run', 'recipe'):
        if not isinstance(args[2], dict) or not isinstance(args[3], dict) or any(not isinstance(v, (str, int, float, bool)) for v in args[3].values()):
            raise BridgeError('GXTXT:CurveFamily:Arguments', 'Bindings and scalar configuration dictionaries are required')
    host.call('::GX::modulePublicApiActivate', 'curvefit.family_global', 'CURVE_FAMILY_API_v1')
    raw = host.call('::GX::CurveFamilyV1::'+_OPS[operation][0], *args)
    if operation == 'recipe':
        return raw.decode('ascii') if isinstance(raw, bytes) else str(raw)
    if operation in ('recipe_validate', 'submit'):
        return host.as_dict(raw)
    if operation == 'results':
        rows = [host.as_dict(row) for row in host.as_list(raw)]
        for row in rows:
            row['reference'] = host.as_dict(row['reference'])
        return rows
    if operation == 'api_info':
        result = host.as_dict(raw)
        result['api_version'] = int(result['api_version'])
        result['operations'] = [_text(host, v) for v in host.as_list(result['operations'])]
        return result
    if operation == 'models':
        rows = [host.as_dict(row) for row in host.as_list(raw)]
        for row in rows:
            row['parameter_ids'] = [_text(host, v) for v in host.as_list(row['parameter_ids'])]
        return rows
    result = host.as_dict(raw)
    result['api_version'] = int(result['api_version'])
    for key in ('reference', 'source_identity', 'files'):
        result[key] = host.as_dict(result[key])
    result['dataset_ids'] = [_text(host, v) for v in host.as_list(result['dataset_ids'])]
    result['publications'] = {key: host.as_dict(value) for key, value in host.as_dict(result['publications']).items()}
    result['parameter_map'] = _map(host, result['parameter_map'])
    statistics = host.modules['STATISTICAL_RESULT_SEMANTICS_API_v1']
    result['statistical_results'] = {key: statistics.invoke(host, 'validated_result', [host.as_dict(value)])
        for key, value in host.as_dict(result['statistical_results']).items()}
    if operation in ('run', 'recipe_run'):
        host.record_publications(result)
    return result
