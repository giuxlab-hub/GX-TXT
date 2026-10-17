"""CORE logarithmic column publication adapter; Numeric alone computes logs."""
# SPDX-License-Identifier: GPL-3.0-or-later
import itertools
import math
import numpy as np
from gxtxt_script_bridge_server import NumericArray


def rows(t):
    if len(t.sources) != 1:
        raise ValueError("Logarithmic columns require one canonical Dataset")
    source = t.sources[0]
    specifications = [t.dictionary(v) for v in t.sequence(t.option('logarithms', ''))]
    if not 1 <= len(specifications) <= 16:
        raise ValueError("Declare 1..16 explicit logarithmic column bindings")
    ids = source['selected_variable_ids']
    t.schema = [dict(v) for v in source['schema']]
    names = set(v['variable_id'] for v in t.schema)
    bindings = []
    for spec in specifications:
        if set(spec) != {'source_variable_id', 'output_variable_id', 'reference'}:
            raise ValueError("Each logarithm requires source_variable_id, output_variable_id and reference")
        original, output = spec['source_variable_id'], spec['output_variable_id']
        if original not in ids or output in names:
            raise ValueError("Logarithms require selected source Variables and distinct new output IDs")
        index = ids.index(original)
        if source['schema'][index]['dtype'] not in ('float32', 'float64'):
            raise ValueError("Logarithmic columns require float32/float64; convert integers explicitly")
        reference = float(spec['reference'])
        if not math.isfinite(reference) or reference <= 0:
            raise ValueError("Logarithmic reference must be finite and positive in the source Variable units")
        t.host.call('::GX::datasetPublicationV2ValidateId', 'variable', output)
        names.add(output)
        unit = source['schema'][index].get('unit', '')
        descriptor = t.field(output, 'float64', '1', 'data')
        descriptor['display_label'] = f"ln({original} / {reference:.17g} {unit})"
        t.schema.append(descriptor)
        bindings.append((index, reference, dict(schema='gxtxt.log_variable_transform.v1',
            provider='math.numeric', operation='log_ratio', base='natural', reference=reference,
            source_dataset_id=source['dataset_id'], source_sha256=source['sha256'],
            source_variable_id=original, source_unit=unit, output_variable_id=output,
            output_unit='1', domain='finite_strictly_positive',
            noise_semantics='additive_errors_in_log_ratio_space')))
    row_id = t.option('row_variable_id', 'log_source_row_ordinal')
    if row_id in names:
        raise ValueError("Logarithmic source-row Variable ID must be new")
    t.host.call('::GX::datasetPublicationV2ValidateId', 'variable', row_id)
    t.schema.append(t.field(row_id, 'uint64'))
    t.logarithm_receipt = dict(schema='gxtxt.logarithmic_transform.v1',
        row_variable_id=row_id, row_identity='original_dataset_zero_based_uint64',
        row_count=source['row_count'], chunk_limit=65536,
        transforms=[binding[2] for binding in bindings])
    records = iter(t.source_rows(source))
    while True:
        block = list(itertools.islice(records, 65536))
        if not block:
            break
        columns = []
        for index, reference, _ in bindings:
            values = np.asarray([math.nan if row[index+2] is None else float(row[index+2]) for row in block], dtype=np.float64)
            result = t.host.modules['NUMERIC_API_v1'].invoke(t.host, 'log_ratio', [NumericArray(values), reference])
            columns.append(np.asarray(result['values'].values).reshape(-1))
        for position, record in enumerate(block):
            yield list(record[2:]) + [column[position] for column in columns] + [int(record[1])]
