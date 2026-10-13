"""Run through Script Bridge or build policy_python.json; never copy Session files."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
from gxtxt import gxtxt_api_call, gxtxt_api_has, gxtxt_api_has_operation, gxtxt_context
api = 'EXPERIMENT_DUPLICATION_POLICY_API_v1'
assert gxtxt_api_has(api) and gxtxt_api_has_operation(api, 'validate')
info = gxtxt_api_call(api, 'info', [])
assert int(info['api_version']) == 1
proposal = {'meta.id': 'example.policy', 'config.fields': 'gain;calibration_file',
            'config.gain.type': 'number', 'config.calibration_file.type': 'file',
            'experiment_duplication.api_version': '1',
            'experiment_duplication.config_copy': 'gain',
            'experiment_duplication.config_external': 'calibration_file'}
assert int(gxtxt_api_call(api, 'validate', [proposal])['valid']) == 1
proposal['config.gain.type'] = 'dataset'
assert int(gxtxt_api_call(api, 'validate', [proposal])['valid']) == 0
ctx = gxtxt_context()
module = gxtxt_api_call(api, 'module', [ctx['module_id']])
assert module['status'] == 'supported'
legacy = gxtxt_api_call(api, 'module', ['analysis.statistics.descriptive'])
assert legacy['status'] == 'unsupported'
receipt = gxtxt_api_call('SESSION_EXPERIMENT_API_v1', 'preparation', [])
source = ctx['inputs']['primary']['dataset_id']
rows = int(gxtxt_api_call('CANONICAL_DATASET_API_v2', 'describe', [source])['row_count'])
gain = float(ctx['parameters']['gain'])
Path(ctx['output_dir'], 'result.txt').write_text(f'rows={rows}\ngain={gain}\n', encoding='utf-8')
print('POLICY_AUTHOR_PYTHON_PASS', source, module['status'], receipt)
