# SPDX-License-Identifier: GPL-3.0-or-later
# Run in Script Workspace with two compatible table Datasets `bridge_a` and
# `bridge_b`, each with numeric Variable IDs x/y. Change these logical IDs for
# your Session. Every output is create-only; choose unused public IDs to rerun.
from gxtxt import gxtxt_api_call, gxtxt_api_require

API = 'DATASET_TRANSFORM_API_v1'
gxtxt_api_require(API + '@1:dataset_transform')

def publish(operation, sources, identifier, options=None):
    manifest = {'api_version': 1, 'operation': operation, 'sources': sources,
                'output': {'dataset_id': identifier, 'storage': 'auto'},
                'options': options or {}, 'schema_policy': {}}
    plan = gxtxt_api_call(API, 'plan', [manifest])
    try:
        print(operation, 'planned rows:', plan['row_count'])
        return gxtxt_api_call(API, 'execute', [plan])
    finally:
        gxtxt_api_call(API, 'release_plan', [plan['plan_id']])

# 1. Project columns in the declared order, retaining their schema/metadata.
publish('project_variables', [{'dataset_id': 'bridge_a', 'variable_ids': ['x', 'y']}], 'example_python_projection')
# 2. Concatenate compatible complete rows in explicit source order.
publish('concat_rows', [{'dataset_id': 'bridge_a'}, {'dataset_id': 'bridge_b'}], 'example_python_concat')
# 3. Combine curves into a long family. Grids/counts may differ; no alignment.
publish('curve_bundle', [
    {'dataset_id': 'bridge_a', 'member_id': 'measured', 'x_variable_id': 'x', 'y_variable_id': 'y'},
    {'dataset_id': 'bridge_b', 'member_id': 'reference', 'x_variable_id': 'x', 'y_variable_id': 'y'}],
    'example_python_family', {'representation': 'long'})
# 4. Extract one member, project ordinary X/Y and restore that member's units.
publish('extract_family_member', [{'dataset_id': 'example_python_family', 'variable_ids': ['x', 'y']}],
        'example_python_member', {'members': ['reference']})
print('PYTHON_DATASET_TRANSFORM_EXAMPLES_PASS')
