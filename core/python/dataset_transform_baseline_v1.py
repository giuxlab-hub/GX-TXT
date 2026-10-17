"""Dataset Transform baseline publication adapter; Numeric owns all estimation."""
# SPDX-License-Identifier: GPL-3.0-or-later
import math
import numpy as np
from gxtxt_script_bridge_server import NumericArray


def rows(transform):
    t = transform
    if len(t.sources) != 1:
        raise ValueError("Baseline correction requires one canonical spectrum")
    source = t.sources[0]
    ids = source['selected_variable_ids']
    x_id, y_id = (t.option(key, source.get(key, '')) for key in ('x_variable_id', 'y_variable_id'))
    if x_id == y_id or x_id not in ids or y_id not in ids:
        raise ValueError("Baseline correction requires distinct selected X/Y Variable IDs")
    xi, yi = ids.index(x_id), ids.index(y_id)
    for i in (xi, yi):
        if source['schema'][i]['dtype'] not in ('float32', 'float64'):
            raise ValueError("Baseline axes require float32/float64; convert integer coordinates explicitly")
    n = source['row_count']
    if not 1 <= n <= 2000000:
        raise ValueError("Baseline correction supports at most 2000000 selected rows")
    opts = t.dictionary(t.option('baseline_options', ''))
    allowed = {'method', 'lambda', 'p', 'max_iterations', 'tolerance', 'grid_policy', 'nonfinite', 'value', 'estimator', 'degree'}
    if set(opts) - allowed:
        raise ValueError("Unknown baseline option: " + ', '.join(sorted(set(opts) - allowed)))
    for key in ('lambda', 'p', 'max_iterations', 'tolerance', 'value', 'degree'):
        if key in opts:
            opts[key] = float(opts[key])
    opts.setdefault('method', 'asls')
    if opts['method'] not in ('asls', 'constant', 'linear', 'polynomial'):
        raise ValueError("Dataset correction supports asls, constant, linear or polynomial")
    x, y = np.empty(n), np.empty(n)
    for pos, record in enumerate(t.source_rows(source)):
        for target, index in ((x, xi), (y, yi)):
            cell = record[index+2]
            target[pos] = math.nan if cell is None else float(cell)
    # Invoke the registered provider through its one data-only implementation.
    # Binary vectors never enter the bounded Tcl manifest or its result receipt.
    result = t.host.modules['NUMERIC_API_v1'].invoke(t.host, 'baseline', [NumericArray(x), NumericArray(y), opts])
    estimator = result['estimator']
    if opts['method'] == 'asls' and not estimator['converged']:
        raise ValueError("AsLS did not converge; change settings before publishing corrected data")
    base = np.full(n, np.nan);corrected = np.full(n, np.nan)
    positions = np.asarray(result['source_row_positions'].values, dtype=np.int64) - 1
    base[positions] = result['baseline'].values
    corrected[positions] = result['corrected'].values
    outputs = {key: t.option(key+'_variable_id', default) for key, default in (
        ('baseline', 'baseline'), ('corrected', 'corrected_y'), ('row', 'baseline_source_row_ordinal'))}
    t.schema = [dict(v) for v in source['schema']]
    if len(set(outputs.values())) != 3 or set(outputs.values()).intersection(v['variable_id'] for v in t.schema):
        raise ValueError("Baseline, corrected and source-row Variable IDs must be distinct and new")
    unit = source['schema'][yi].get('unit', '')
    t.schema += [t.field(outputs['baseline'], 'float64', unit, 'data'),
                 t.field(outputs['corrected'], 'float64', unit, 'data'),
                 t.field(outputs['row'], 'uint64')]
    facts = {key: value for key, value in estimator.items() if not isinstance(value, NumericArray)}
    t.baseline_receipt = {'schema': 'gxtxt.baseline_transform.v1', 'provider': 'math.numeric',
        'source_dataset_id': source['dataset_id'], 'source_sha256': source['sha256'],
        'x_variable_id': x_id, 'original_y_variable_id': y_id,
        **{key+'_variable_id': value for key, value in outputs.items()},
        'row_identity': 'original_dataset_zero_based_uint64', 'method': opts['method'],
        'original_n': n, 'estimated_n': len(positions), 'omitted_n': n-len(positions),
        'options': opts, 'estimator': facts,
        'uncertainty_policy': 'baseline_treated_as_fixed_no_baseline_estimation_uncertainty'}
    for pos, record in enumerate(t.source_rows(source)):
        # Preserve all original columns and rows, including excluded positions.
        yield list(record[2:]) + [base[pos], corrected[pos], int(record[1])]
