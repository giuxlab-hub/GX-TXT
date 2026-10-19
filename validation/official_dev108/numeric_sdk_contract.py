"""Compiled bounded Numeric form plans; actual scientific execution is GUI-owned."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import json
import subprocess
import sys

workspace = Path(__file__).resolve().parents[2]
project = Path(sys.argv[1]).resolve()
assert project.parent == workspace/'_private_dev108' and project.name.startswith('numeric-sdk-contract') and not project.exists()
backend = workspace/'_work_gxtxt_dev108/core/python/gxtxt_viewer_development.py'
receipts = []
def call(operation, *arguments, payload=None, accepted=True):
    run = subprocess.run([sys.executable, '-I', '-B', str(backend), operation, str(project), *arguments], input=payload, text=True, capture_output=True, timeout=120)
    response = json.loads(run.stdout)
    receipts.append(dict(operation=operation, returncode=run.returncode, response=response))
    assert (run.returncode == 0) == accepted, response
    return response.get('result', response)
def edit(operation, *arguments):
    return call('builder', payload=json.dumps(dict(operation=operation, arguments=arguments)))
call('init', '--module-id', 'viewer.numeric_sdk_contract')
edit('metadata', 'requirements', {'VIEWER_GUI_HOST_API_v1':1, 'UI_FIELD_API_v1':1, 'NATIVE2D_VIEWPORT_HOST_v1':1, 'NUMERIC_API_v1':1})
components = [
    ('form','section','inspector',dict(title='Numeric controls')),
    ('dataset','dataset_selector','form',dict(label='Dataset')),
    ('variable','choice','form',dict(label='Variable',choices=['time'],default='time')),
    ('expression','field','form',dict(label='Expression',datatype='string',default='t')),
    ('row_start','field','form',dict(label='Start',datatype='integer',default=0)),
    ('row_count','field','form',dict(label='Count',datatype='integer',default=1)),
    ('output_unit','field','form',dict(label='Unit',datatype='string',default='s')),
    ('numeric_status','status','form',dict(text='No result')),
    ('report','log','form',dict(text='No result',height=4)),
    ('statistic','choice','form',dict(label='Statistic',choices=['array_reduce.rms'],default='array_reduce.rms')),
    ('relative_floor','field','form',dict(label='Relative floor',datatype='number',default=1e-12))]
for row,(ident,kind,parent,properties) in enumerate(components):
    edit('add',dict(id=ident,type=kind,parent=parent,properties=properties,layout=dict(row=row+3,column=0,sticky='ew')))
edit('properties','form',dict(numeric_dataset='dataset', numeric_variables=dict(t='variable'), numeric_expression='expression', numeric_start='row_start', numeric_count='row_count', numeric_output_unit='output_unit', numeric_x='variable', numeric_status='numeric_status', numeric_report='report', numeric_statistic='statistic', numeric_observed='variable', numeric_relative_floor='relative_floor'))
meta = json.loads((project/'project.json').read_text())
for request in meta['capabilities']:
    if request['api_id']=='NUMERIC_API_v1':
        request['operations'] += ['dataset_expression','statistics','array_reduce.rms','array_reduce.minimum','array_reduce.maximum','residual_metrics']
meta['capabilities'].append(dict(api_id='DATASET_PUBLICATION_API_v2',version=2,operations=['datasetPublicationV2Finalize']))
call('save','--file','project.json',payload=json.dumps(meta))
source = '''void on_event(gx::Host& host, gx::State&, const gx::Event&) {
    host.numeric_discover(5);
    host.numeric_evaluate(5);
    host.numeric_statistics(5);
    host.numeric_compare(5);
    host.numeric_publish(5,6);
}
'''
call('save',payload=source)
planned=call('run')
assert planned['status']=='COMPLETED' and [o['operation'] for o in planned['operations']]==['numeric_discover','numeric_evaluate','numeric_statistics','numeric_compare','numeric_publish'],planned
for before,after in [('numeric_evaluate(5)','numeric_evaluate(3)'),('numeric_publish(5,6)','numeric_publish(5,3)')]:
    call('save',payload=source.replace(before,after))
    denied=call('run',accepted=False)
    assert denied['status']=='FAILED' and not denied['operations'],denied
call('save',payload=source)
for denied_api,denied_operation in [('NUMERIC_API_v1','array_reduce.minimum'),('NUMERIC_API_v1','dataset_expression'),('DATASET_PUBLICATION_API_v2','datasetPublicationV2Finalize')]:
    denied=json.loads(json.dumps(meta))
    for grant in denied['capabilities']:
        if grant['api_id']==denied_api: grant['operations'].remove(denied_operation)
    call('save','--file','project.json',payload=json.dumps(denied))
    call('validate',accepted=False)
call('save','--file','project.json',payload=json.dumps(meta))
(project/'derived/numeric-sdk-contract.json').write_text(json.dumps(dict(result='PASS_PLANNED_OPERATIONS',receipts=receipts,actual_scientific_execution='separate real GUI test'),indent=2)+'\n')
print('PASS compiled Numeric form plans and explicit capability/component denials; no headless scientific execution claim')
