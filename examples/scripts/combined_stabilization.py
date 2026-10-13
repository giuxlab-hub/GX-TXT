"""Run once in a disposable Session through GX-TXT's Python Script Workspace."""
from gxtxt import gxtxt_api_require, gxtxt_api_call
import numpy as np

for requirement in ('NUMERIC_API_v1@1:math.numeric', 'DATASET_PUBLICATION_API_v2@2:dataset_publication',
                    'PLOT_DATASET_API_v3@3:plot.dataset', 'GRAPH_WORKFLOW_API_v1@1:graph_workflow',
                    'GRAPH_NOTES_API_v1@1:graph_notes', 'GRAPH_METADATA_API_v1@1:graph_metadata',
                    'PLOT_ANNOTATION_API_v1@1:plot_annotation'):
    gxtxt_api_require(requirement)
x = np.linspace(0, 1, 20)
model = gxtxt_api_call('NUMERIC_API_v1', 'curve_model_fit', ['pchip', x, x**2, {}])
curve = gxtxt_api_call('NUMERIC_API_v1', 'curve_model_evaluate', [model, np.linspace(0, 1, 1000)])
gxtxt_api_call('DATASET_PUBLICATION_API_v2', 'publish_series', [{
    'dataset_id': 'example_combined_python', 'contract': 'table.generic', 'storage': 'csv',
    'x_values': curve['x'], 'y_values': curve['y'],
    'x_variable': {'variable_id': 'x', 'name': 'x', 'unit': 's', 'semantic_role': 'time'},
    'y_variable': {'variable_id': 'y', 'name': 'y', 'unit': 'V', 'semantic_role': 'voltage'},
    'structured_metadata': {'processing.model': 'pchip', 'experimental.sample': 'example'}}])
spec = gxtxt_api_call('PLOT_DATASET_API_v3', 'new_spec', ['plot.dataset.xy', 'Published PCHIP example'])
spec['panels'][0]['series'] = [{'id': 'fit', 'dataset_id': 'example_combined_python',
                              'x_variable_id': 'x', 'y_variable_id': 'y', 'axis': 'left'}]
ref = gxtxt_api_call('PLOT_DATASET_API_v3', 'create_plot', [spec, 'variant'])
mid, gid, vid = ref['module_id'], ref['graph_id'], ref['variant_id']
gxtxt_api_call('GRAPH_WORKFLOW_API_v1', 'presentation_set', [mid, gid, vid, {'xy_aspect_mode': 'xy_equal', 'background': 'transparent'}])
gxtxt_api_call('PLOT_DATASET_API_v3', 'render', [ref])
gxtxt_api_call('GRAPH_NOTES_API_v1', 'write', [ref, '# PCHIP\nTwenty training points, 1000 output points.'])
gxtxt_api_call('GRAPH_METADATA_API_v1', 'update', [ref, {'fit.model': 'pchip', 'experimental.sample': 'example'}])
doc = gxtxt_api_call('PLOT_ANNOTATION_API_v1', 'add', [mid, gid, vid, {'type': 'text', 'x': 0.2, 'y': 0.8, 'text': 'PCHIP'}])
id = doc['objects'][-1]['id']
gxtxt_api_call('PLOT_ANNOTATION_API_v1', 'update', [mid, gid, vid, id, {'text': 'Explicit published fit'}])
print('Created', ref)
