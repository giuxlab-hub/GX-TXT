#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import ast,importlib.util,json,pathlib,subprocess,sys,time,tkinter
root=pathlib.Path(sys.argv[1]).resolve(); out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(root/'core/python'))
import gxtxt_viewer_development as d
for f in ['gxtxt_viewer_development.py','gxtxt_viewer_native_worker.py']:ast.parse((root/'core/python'/f).read_text())
subprocess.run(['c++','-std=c++17','-fPIC','-c',str(root/'core/development/sdk/trusted_adapter_v1.cpp'),'-o',str(out/'trusted_adapter.o')],check=True)
baseline=pathlib.Path(sys.argv[3]).resolve() if len(sys.argv)>3 else root
module=baseline/'plugins/modules/viewer.scientific_3d_workbench'
d._installed_sdk_compatible(module,json.loads((module/'review/build.json').read_text()))
print('PASS additive SDK admits exact reference artifact',module)
join=tkinter._join
components={1:{'id':'sketch','type':'cad_sketch','properties':''},2:{'id':'diagnostics','type':'section','properties':join(('diagnostics_owner','stderr'))},3:{'id':'messages','type':'log','properties':''},4:{'id':'records','type':'table','properties':''}}
grants={'VIEWER_GUI_HOST_API_v1':{'cad_command','diagnostics_command','text_runs','table_set'},'NATIVE2D_API_v1':{'cad_sketch_command'},'STDERR_DIAGNOSTICS_API_v1':{'read','status'}}
values=[(36,1,'line'),(37,2,'read\n'+json.dumps({'limit':32,'max_bytes':262144})),(38,3,json.dumps({'replace':True,'runs':[{'text':'Real message\n','style':'error'}]})),(39,4,json.dumps([['origin','message']]))]
for op,component,text in values:
 message={'operation':op,'component':component,'request':1,'left':0,'right':0,'text':text}
 response,ops,math=d.broker_message(out,message,components,grants,time.monotonic()+10)
 assert response['ok'] and len(ops)==1
 try:d.broker_message(out,message,components,{},time.monotonic()+10)
 except d.DevelopmentError:pass
 else:raise AssertionError('missing grant accepted')
print('PASS finite CAD/diagnostics/styled-text/table positive and denied-grant contracts')
(out/'result.json').write_text(json.dumps({'status':'PASS','sdk_compile':True,'reference_artifact':str(module),'reference_build':json.loads((module/'review/build.json').read_text()),'typed_broker_cases':4,'gui':False},indent=2)+'\n')
