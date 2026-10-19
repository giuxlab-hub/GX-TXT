# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import json, subprocess, shutil
w=Path(__file__).resolve().parents[2]; p=w/'_private_dev108/plot-series-sdk02'; assert not p.exists();p.mkdir()
for name in ('handlers.cpp','project.json','design.gxtxt-viewer'):shutil.copy2(w/'_private_dev108/netlist-sdk01'/name,p/name)
backend=w/'_work_gxtxt_dev108/core/python/gxtxt_viewer_development.py'; receipts=[]
def edit(op,*args,accepted=True):
 payload=dict(operation=op,arguments=list(args))
 r=subprocess.run(['/usr/bin/python3','-I','-B',str(backend),'builder',str(p)],input=json.dumps(payload),text=True,capture_output=True,timeout=120)
 answer=json.loads(r.stdout);receipts.append(dict(request=payload,response=answer));assert answer['ok']==accepted,answer
 return answer.get('result')
refs={}
for ident,kind,props in [
 ('series_selected','choice',dict(label='Selected series',choices=['selected_source'],default='selected_source')),
 ('series_label','field',dict(label='Series label',datatype='string',default='Comparison')),
 ('series_axis','choice',dict(label='Axis',choices=['left','right'],default='left')),
 ('series_enabled','toggle',dict(label='Enabled',default=1)),
 ('series_panel','choice',dict(label='Panel',choices=['main'],default='main')),
 ('series_panel_title','field',dict(label='New panel title',datatype='string',default='Comparison panel')),
 ('series_report','log',dict(height=6,text='Discover actual canonical series.'))]:
 edit('add',dict(id=ident,type=kind,parent='inspector',properties=props,layout=dict(row=10+len(refs),column=0,sticky='ew')));refs[ident]=1
commands={}
for op in ('refresh','load','add','update','remove','up','down','panel_add','panel_remove','panel_up','panel_down'):
 action='series_'+op; ident=action+'_button'
 edit('add',dict(id=ident,type='action',parent='inspector',properties=dict(label=op,action=action),layout=dict(row=20+len(commands),column=0,sticky='ew')))
 edit('bind',ident,action,'presentation');commands[action]=op
props=dict(plot_series='series_selected',plot_series_label='series_label',plot_series_axis='series_axis',plot_series_enabled='series_enabled',plot_panel='series_panel',plot_panel_title='series_panel_title',plot_series_target='plot',plot_series_status='series_report',plot_series_commands=commands)
for bad in [dict(plot_series='series_selected'),dict(props,plot_series_target='graphics'),dict(props,plot_series_axis='series_panel'),dict(props,plot_series_commands=dict(series_add='invalid')),dict(props,plot_series_commands=dict(fit='add')),dict(props,plot_series='y'),dict(props,plot_panel='series_selected')]:
 before=(p/'design.gxtxt-viewer').read_bytes(); edit('properties','plot_form',bad,accepted=False);assert (p/'design.gxtxt-viewer').read_bytes()==before
edit('properties','plot_form',props)
before=(p/'design.gxtxt-viewer').read_bytes();edit('bind','series_add_button','series_add','mutating',accepted=False);assert (p/'design.gxtxt-viewer').read_bytes()==before
(p/'derived/plot-series-admission.json').write_text(json.dumps(dict(status='PASS_PUBLIC_SERIES_DECLARATION_ADMISSION_ONLY',receipts=receipts),indent=2)+'\n')
print(p/'derived/plot-series-admission.json')
