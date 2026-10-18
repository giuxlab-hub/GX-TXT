# SPDX-License-Identifier: GPL-3.0-or-later
"""One project/policy/build/native-runtime backend for the GUI and author CLI."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import tkinter

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gxtxt_cpp_policy import (COMPILER, DEVELOPMENT, FLAGS, FRAMEWORK, POLICY, SDK,
                              ACTIVE_PROCESSES, bounded_command, digest, environment, validate_source)
from gxtxt_project_grant import check_project_root, enforce_project_write
from gxtxt_job_supervisor import request_process_group, tcl_result

def cancel_children(signum, frame):
    for process in tuple(ACTIVE_PROCESSES):
        try: os.killpg(process, signal.SIGKILL)
        except ProcessLookupError: pass
    raise SystemExit(128+signum)

SOURCE = '''// SPDX-License-Identifier: GPL-3.0-or-later
// Restricted SDK v1 is supplied automatically; do not add includes.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.demo(3, 0);
        host.text(2, "Synthetic response; C++ handler uses the public Numeric API.");
    }
    if (event.kind == gx::EventKind::invoke) {
        state.counter += 1;
        state.values[0] = host.numeric_add(event.value, 273.15);
        host.number(1, state.values[0]);
        host.text(2, "Synthetic temperature in kelvin; display only.");
    }
}
'''

class DevelopmentError(Exception):
    def __init__(self, message, code='DEVELOPMENT_ERROR', detail=None):
        super().__init__(message); self.code=code; self.detail=detail

def write_json(path, value):
    path = Path(path);path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False, sort_keys=True)+'\n').encode()
    with tempfile.NamedTemporaryFile(prefix='.development-', dir=path.parent, delete=False) as f:
        f.write(data); stage=Path(f.name)
    os.replace(stage,path)
    return digest(data)

def dictionary(raw):
    words = tkinter.Tcl().splitlist(raw)
    if len(words)%2: raise DevelopmentError('Invalid CORE dictionary response')
    return dict(zip(words[::2],words[1::2]))

def project_environment(project):
    env = environment(project/'derived/tmp')
    (project/'derived/tmp').mkdir(parents=True,exist_ok=True)
    for key in ('XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','XDG_STATE_HOME',
                'GXTXT_INSTALLATION_ROOT','GXTXT_RESOURCE_ROOT','GXTXT_RESOURCE_STORAGE','GXTXT_JOB_ROOT'):
        env[key]=str(project/'derived/host-environment'/key)
    return env

def core(project, operation, *arguments, timeout=12):
    """Fixed trusted helper; project arguments are data, never Tcl programs."""
    command=['/usr/bin/tclsh',str(FRAMEWORK/'core/tcl/viewer_development_request.tcl'),str(FRAMEWORK),operation,*map(str,arguments)]
    with open(os.devnull, 'rb') as null, tempfile.TemporaryFile(dir=project/'derived/tmp') as output, tempfile.TemporaryFile(dir=project/'derived/tmp') as errors:
        child=subprocess.Popen(command,stdin=null,stdout=output,stderr=errors,
                               cwd=project,env=project_environment(project),start_new_session=True)
        ACTIVE_PROCESSES.add(child.pid)
        try: code=child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid,signal.SIGKILL);child.wait();raise DevelopmentError('Public CORE request timed out','CORE_TIMEOUT')
        finally: ACTIVE_PROCESSES.discard(child.pid)
        output.seek(0);errors.seek(0);raw=output.read(4194305);err=errors.read(65536)
    if len(raw)>4194304: raise DevelopmentError('Public CORE response exceeds bound')
    try: response=dictionary(raw.decode())
    except Exception: raise DevelopmentError(err.decode(errors='replace')[-4096:] or 'Invalid public CORE response')
    if code or response.get('ok')!='1': raise DevelopmentError(response.get('error','Public CORE request failed'),'CORE_API_GAP')
    return response['result']

def read_project(project):
    check_project_root(project)
    expected={'schema','module_id','version','profile','language','source','design','capabilities','provenance','tests'}
    for name in ('project.json','handlers.cpp','design.gxtxt-viewer'):
        path=project/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1 or path.stat().st_size>4194304:
            raise DevelopmentError('Project requires ordinary bounded '+name,'PROJECT_INVALID')
    meta=json.loads((project/'project.json').read_text())
    if set(meta)!=expected or meta['schema']!='gxtxt.viewer_development_project.v1' or meta['language']!='cpp' or meta['source']!='handlers.cpp' or meta['design']!='design.gxtxt-viewer':
        raise DevelopmentError('Unknown/forged project metadata, compiler, source, policy or adapter override','PROJECT_POLICY')
    if meta['profile'] not in POLICY['profiles']: raise DevelopmentError('Unknown trusted author profile','PROJECT_POLICY')
    if len(meta['capabilities'])>16: raise DevelopmentError('Capability request exceeds bound')
    if not isinstance(meta['provenance'],dict) or len(json.dumps(meta['provenance']))>8192:
        raise DevelopmentError('Provenance must be a bounded inert object')
    return meta

def api_catalog(project):
    catalog={key:dictionary(value) for key,value in dictionary(core(project,'api_catalog')).items()}
    shapes={
        'value_set':{'request':{'component':'declared component index','value':'finite number or boolean'},'result':'display applied; no scientific effect'},
        'text_set':{'request':{'component':'declared status/label index','text':'literal UTF-8 <=256 bytes'},'result':'display applied'},
        'describe':{'request':{},'result':'public component contract'},
        'open':{'request':{'component':'declared graphics index','fixture':'0 Native2D, 1 Plot, 2 Native3D'},'result':'inert typed binding operation; actual GUI construction after successful event; no C++ return value'},
        'inspect':{'request':{'component':'declared graphics index'},'result':'public native receipt'},
        'demo_bind':{'request':{'component':'declared Native3D index'},'result':'inert typed binding operation; actual public v2 GUI construction after successful event; no C++ return value'},
        'array_unary.sqrt':{'request':{'value':'finite nonnegative scalar'},'result':'public NUMERIC_API_v1 scalar values; no Dataset'},
        'array_binary.add':{'request':{'left':'finite scalar','right':'finite scalar'},'result':'public NUMERIC_API_v1 scalar values; no Dataset'},
    }
    for key,row in catalog.items():
        allowed=POLICY['capabilities'].get(key)
        row['sdk_exposed']=bool(allowed)
        row['allowed_operations']=allowed['operations'] if allowed else []
        row['operation_shapes']={op:shapes[op] for op in row['allowed_operations']}
        row['authorization_reason']='Explicit trusted SDK v1 facility; project must request it' if allowed else 'Installed public API is outside this restricted SDK; request a reviewed CORE facility extension'
    return catalog

def capability_check(project,meta,catalog,validation):
    requested={}
    for request in meta['capabilities']:
        if not isinstance(request,dict) or set(request)!={'api_id','version','operations'} or not isinstance(request['api_id'],str) or type(request['version']) is not int or not isinstance(request['operations'],list) or not all(isinstance(op,str) for op in request['operations']):
            raise DevelopmentError('Capability request shape is not authorized','PROJECT_POLICY')
        api=request['api_id'];policy=POLICY['capabilities'].get(api);available=catalog.get(api)
        if not available or str(available.get('version'))!=str(request['version']) or str(available.get('enabled'))!='1':
            base=api.rsplit('_v',1)[0]
            closest={key:row for key,row in catalog.items() if key.rsplit('_v',1)[0]==base}
            gap={'schema':'gxtxt.core_api_gap.v1','requested':request,'closest_public_owner':available or closest,
                 'required_behavior':'Provide the requested typed, bounded public facility to this SDK',
                 'proposed_contract':'CORE maintainer reviews API/version/operation shapes; author cannot add dependencies or private fallbacks'}
            write_json(project/'derived/CORE_API_GAP.json',gap)
            raise DevelopmentError('Requested public API is missing, disabled or version mismatched','CORE_API_GAP',gap)
        if not policy or api not in POLICY['profiles'][meta['profile']] or request['version']!=policy['version'] or not set(request['operations']).issubset(policy['operations']):
            raise DevelopmentError('Project request is outside the trusted profile: '+api,'CAPABILITY_DENIED')
        if api in requested: raise DevelopmentError('Duplicate capability request','PROJECT_POLICY')
        requested[api]=set(request['operations'])
    required={'text':('VIEWER_GUI_HOST_API_v1','text_set'), 'number':('VIEWER_GUI_HOST_API_v1','value_set'),
              'flag':('VIEWER_GUI_HOST_API_v1','value_set'), 'demo':('VIEWER_COMPONENT_DEMO_API_v1','open'),
              'numeric_add':('NUMERIC_API_v1','array_binary.add'), 'numeric_sqrt':('NUMERIC_API_v1','array_unary.sqrt')}
    for method in validation['sdk_calls']:
        api,operation=required[method]
        if operation not in requested.get(api,set()): raise DevelopmentError('SDK call lacks requested authorized capability: '+method,'CAPABILITY_DENIED')
    return requested

def initialize(project,module_id):
    check_project_root(project,allow_missing=True)
    if project.exists() and any(project.iterdir()): raise DevelopmentError('New project directory must be empty')
    project.mkdir(parents=False,exist_ok=True)
    grant=enforce_project_write(project)
    (project/'derived/tmp').mkdir(parents=True,exist_ok=True)
    design=core(project,'new_design',module_id)
    # CORE validates identity/version before any author file is created.
    definition=dictionary(design)
    meta={'schema':'gxtxt.viewer_development_project.v1','module_id':definition['module_id'],'version':definition['version'],
          'profile':'numeric_view_v1','language':'cpp','source':'handlers.cpp','design':'design.gxtxt-viewer',
          'capabilities':[{'api_id':key,'version':POLICY['capabilities'][key]['version'],'operations':POLICY['capabilities'][key]['operations']}
                          for key in ('VIEWER_GUI_HOST_API_v1','VIEWER_COMPONENT_DEMO_API_v1','NUMERIC_API_v1')],
          'provenance':{'template':'restricted_cpp_viewer_v1','scientific_source':None},
          'tests':{'events':[{'kind':0,'component':0,'value':0.0},{'kind':1,'component':4,'value':18.0},{'kind':1,'component':4,'value':20.0}],'expected_counter':2,'expected_values':{'0':293.15}}}
    (project/'handlers.cpp').write_text(SOURCE)
    (project/'design.gxtxt-viewer').write_text(design+'\n')
    write_json(project/'project.json',meta)
    return {'status':'CREATED','project':str(project),'grant':grant,'source_sha256':digest(SOURCE.encode())}

def validate(project):
    meta=read_project(project)
    report=validate_source((project/'handlers.cpp').read_bytes(),project/'derived/tmp')
    design=dictionary(core(project,'validate_design',project/'design.gxtxt-viewer'))
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Project and Builder design identities differ','PROJECT_INVALID')
    report['design_sha256']=digest((project/'design.gxtxt-viewer').read_bytes())
    report['project_sha256']=digest((project/'project.json').read_bytes())
    report['project_profile']=meta['profile']
    for value in tkinter.Tcl().splitlist(design['components']):
        component=dictionary(value)
        if component['type'] in {'workspace','history'}:
            raise DevelopmentError('Canonical Workspace/History effects are outside the read-only SDK profiles; use their inert B1 samples','CAPABILITY_DENIED')
    catalog=api_catalog(project)
    requested=capability_check(project,meta,catalog,report)
    write_json(project/'derived/validation.json',report)
    write_json(project/'derived/api-catalog.json',catalog)
    return meta,report,design,requested

def build(project):
    meta,report,design,requested=validate(project)
    if report['status']!='PASS': return {'status':'REJECTED','validation':report,'code_generation_invoked':False}
    source=(project/'handlers.cpp').read_bytes()
    with tempfile.TemporaryDirectory(prefix='build-',dir=project/'derived/tmp') as temporary:
        stage=Path(temporary);author=stage/'handlers.cpp';author.write_bytes(source)
        fixed=[*FLAGS,'-O1','-g0','-fPIC','-fvisibility=hidden','-fno-stack-protector',
               '-ffile-prefix-map='+str(stage)+'=.', '-ffile-prefix-map='+str(DEVELOPMENT)+'=sdk']
        commands=[
            [str(COMPILER),*fixed,'-include',str(SDK),'-c',str(author),'-o',str(stage/'author.o')],
            [str(COMPILER),*fixed,'-I'+str(SDK.parent),'-c',str(SDK.parent/'trusted_adapter_v1.cpp'),'-o',str(stage/'adapter.o')],
            [str(COMPILER),'-nostdlib','-shared','-Wl,-z,defs','-Wl,--build-id=none',str(stage/'author.o'),str(stage/'adapter.o'),'-o',str(stage/'viewer.so')],
        ]
        logs=[]
        for command in commands:
            code,output,errors=bounded_command(command,stage,30)
            logs.append((output+errors).decode(errors='replace').replace(str(stage),'<controlled-build>'))
            if code:
                result={'status':'BUILD_FAILED','code_generation_invoked':True,'validation':report,'log':'\n'.join(logs)}
                write_json(project/'derived/build.json',result);return result
        if digest(author.read_bytes())!=report['source_sha256'] or any(digest((project/name).read_bytes())!=report[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
            raise DevelopmentError('Project source/design/facilities changed during controlled build; rebuild explicitly','SOURCE_CHANGED')
        binary=(stage/'viewer.so').read_bytes()
        (project/'derived/viewer.so').write_bytes(binary)
        (project/'derived/trusted_adapter_v1.cpp').write_bytes((SDK.parent/'trusted_adapter_v1.cpp').read_bytes())
        result={'schema':'gxtxt.viewer_build.v1','status':'BUILT','code_generation_invoked':True,
                'validation':report,'binary_sha256':digest(binary),'adapter_sha256':digest((SDK.parent/'trusted_adapter_v1.cpp').read_bytes()),
                'compiler_version':'19.1.7','link_policy':'fixed SDK adapter; no author libraries/flags; no undefined symbols',
                'log':'\n'.join(logs),'capabilities':meta['capabilities']}
        write_json(project/'derived/build.json',result)
        return result

def finite(value):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value):
        raise DevelopmentError('SDK numbers must be finite scalar values','RUNTIME_VALUE')
    return value

def run(project,event=None,state=None):
    built=build(project)
    if built['status']!='BUILT': return built
    meta,validation,design,requested=validate(project)
    if any(built['validation'][key]!=validation[key] for key in ('source_sha256','design_sha256','project_sha256')):
        raise DevelopmentError('Project changed after build; validate/build again','SOURCE_CHANGED')
    components=[dictionary(value) for value in tkinter.Tcl().splitlist(design['components'])]
    by_index={index+1:component for index,component in enumerate(components)}
    event=event or {'kind':1,'component':4,'value':18.0}
    state=state or {'values':[0.0]*16,'counter':0}
    if set(event)!={'kind','component','value'} or type(event['kind']) is not int or type(event['component']) is not int or event['kind'] not in range(6) or event['component'] not in {0,*by_index}:
        raise DevelopmentError('Invalid typed native event','RUNTIME_EVENT')
    finite(event['value'])
    if set(state)!={'values','counter'} or len(state['values'])!=16 or type(state['counter']) is not int or not 0<=state['counter']<2**32:
        raise DevelopmentError('Invalid bounded native state','RUNTIME_STATE')
    for value in state['values']: finite(value)
    command=[sys.executable,'-I','-B',str(FRAMEWORK/'core/python/gxtxt_viewer_native_worker.py')]
    operations=[];numeric=[];output_bytes=0;deadline=time.monotonic()+POLICY['process_timeout_seconds']
    with tempfile.TemporaryFile(dir=project/'derived/tmp') as errors:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,text=True,
                                 encoding='utf-8',bufsize=1,cwd=project,env=project_environment(project),start_new_session=True)
        ACTIVE_PROCESSES.add(process.pid)
        def reply(value): process.stdin.write(json.dumps(value,allow_nan=False)+'\n');process.stdin.flush()
        reply({'library':str(project/'derived/viewer.so'),'event':event,'state':state})
        done=None
        try:
            while time.monotonic()<deadline:
                ready,_,_=select.select([process.stdout],[],[],min(.2,max(0,deadline-time.monotonic())))
                if not ready:
                    if process.poll() is not None: break
                    continue
                line=process.stdout.readline(65537);output_bytes+=len(line.encode())
                if not line: break
                if output_bytes>65536: raise DevelopmentError('Native output exceeds 64 KiB','RUNTIME_OUTPUT')
                message=json.loads(line)
                if message.get('done'): done=message;break
                if len(operations)+len(numeric)>=64: raise DevelopmentError('Native operation count exceeded','RUNTIME_OUTPUT')
                operation=message['operation'];component=by_index.get(message['component']);left=finite(message['left']);right=finite(message['right'])
                response={'request':message['request'],'ok':True,'value':0.0}
                if operation in {4,6}:
                    numeric_operation='array_binary.add' if operation==4 else 'array_unary.sqrt'
                    if operation==6 and left<0: raise DevelopmentError('Scalar SDK square root requires a nonnegative real operand','RUNTIME_DOMAIN')
                    if numeric_operation not in requested.get('NUMERIC_API_v1',set()): raise DevelopmentError('Numeric facility is not authorized','CAPABILITY_DENIED')
                    operands=[left,right] if operation==4 else [left]
                    result=dictionary(core(project,'numeric_add' if operation==4 else 'numeric_sqrt',*operands,timeout=max(.1,min(12,deadline-time.monotonic()))))
                    values=tkinter.Tcl().splitlist(result['values'])
                    if len(values)!=1: raise DevelopmentError('Numeric scalar result shape differs','CORE_RESULT')
                    response['value']=finite(float(values[0]));numeric.append({'api_id':'NUMERIC_API_v1','operation':numeric_operation,'left':left,'right':right,'result':response['value']})
                elif operation in {1,2,3,5}:
                    if component is None: raise DevelopmentError('SDK component is not declared','RUNTIME_COMPONENT')
                    if operation==1 and (component['type'] not in {'label','status'} or len(message['text'].encode())>256): raise DevelopmentError('Text target/value is outside SDK contract','RUNTIME_COMPONENT')
                    if operation in {2,3} and component['type'] not in {'label','status','field','entry','toggle','checkbutton','progress'}: raise DevelopmentError('Value target is outside SDK contract','RUNTIME_COMPONENT')
                    if operation==5:
                        expected={0:'native2d',1:'plot',2:'native3d'}
                        if left not in expected or component['type']!=expected[left]: raise DevelopmentError('Fixture must match its declared native component','RUNTIME_COMPONENT')
                        if left==2 and 'demo_bind' not in requested.get('NATIVE_3D_GUI_HOST_API_v2',set()): raise DevelopmentError('Native3D facility is not authorized','CAPABILITY_DENIED')
                    operations.append({'operation':{1:'text_set',2:'number_set',3:'flag_set',5:'demo_bind'}[operation],
                                       'component':component['id'],'value':message['text'] if operation==1 else left})
                else: raise DevelopmentError('Unknown SDK operation','CAPABILITY_DENIED')
                reply(response)
            if done is None:
                status='TIMED_OUT' if process.poll() is None else 'CRASHED'
                result={'status':status,'exit_code':process.poll(),'operations':[],'numeric_receipts':numeric,'state':state}
            elif not done.get('ok'):
                result={'status':'FAILED','errors':done.get('errors',[]),'operations':[],'state':state}
            else:
                result={'status':'COMPLETED','operations':operations,'numeric_receipts':numeric,'state':done['state'],
                        'source_sha256':validation['source_sha256'],'design_sha256':validation['design_sha256'],'project_sha256':validation['project_sha256'],'binary_sha256':built['binary_sha256'],'event':event,
                        'execution':'compiled restricted C++ in isolated native worker; typed public CORE broker'}
        except Exception as error:
            result={'status':'TIMED_OUT' if time.monotonic()>=deadline else 'FAILED','error':str(error),'code':getattr(error,'code','RUNTIME_ERROR'),'operations':[],'state':state}
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
            process.wait(timeout=5)
            ACTIVE_PROCESSES.discard(process.pid)
            process.stdin.close();process.stdout.close()
        if result['status']=='COMPLETED' and any(digest((project/name).read_bytes())!=validation[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
            result={'status':'SOURCE_CHANGED','operations':[],'state':state,'error':'Project changed during native execution; reopen the Preview'}
        errors.seek(0);result['stderr']=errors.read(65536).decode(errors='replace')
        write_json(project/'derived/run.json',result)
        return result

def test_project(project):
    meta=read_project(project);configuration=meta['tests']
    if not isinstance(configuration,dict) or set(configuration)!={'events','expected_counter','expected_values'} or not isinstance(configuration['events'],list) or not 1<=len(configuration['events'])<=8 or not isinstance(configuration['expected_values'],dict):
        raise DevelopmentError('Test configuration requires 1..8 typed events and explicit state expectations','PROJECT_TESTS')
    state={'values':[0.0]*16,'counter':0};cases=[]
    for index,event in enumerate(configuration['events']):
        result=run(project,event,state)
        cases.append({'id':'event_'+str(index),'event':event,'status':result['status'],'observation':result})
        if result['status']!='COMPLETED':
            report={'schema':'gxtxt.viewer_project_tests.v1','status':'FAILED','cases':cases,'scope':'Actual project-declared compiled event sequence only; not scientific or complete native GUI acceptance'}
            write_json(project/'derived/tests.json',report);return report
        state=result['state']
    failures=[]
    if state['counter']!=configuration['expected_counter']:failures.append('Final state counter differs')
    for key,expected in configuration['expected_values'].items():
        if not key.isdecimal() or not 0<=int(key)<16:raise DevelopmentError('Test state indices must be 0..15','PROJECT_TESTS')
        finite(expected)
        if abs(state['values'][int(key)]-expected)>1e-12:failures.append('Final state slot '+key+' differs')
    report={'schema':'gxtxt.viewer_project_tests.v1','status':'PASS' if not failures else 'FAILED','cases':cases,'state':state,'failures':failures,'scope':'Actual project-declared compiled event/state expectations only; independent source policy always reruns; native appearance is separate'}
    write_json(project/'derived/tests.json',report);return report

def export_candidate(project):
    """Rebuild from admitted source; never trust a project-authored green report."""
    built=build(project)
    if built['status']!='BUILT': return built
    meta,validation,design,requested=validate(project)
    module=meta['module_id'];provider=design['provider_id'];version=meta['version']
    namespace='::GX::Restricted_'+module.replace('.','_')
    backend=module.replace('.','_')+'_restricted_cpp_v1'
    connector=f'''# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted generated facade; author logic is restricted C++ in a separate worker.
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval {namespace} {{variable root [file dirname [file dirname [info script]]]}}
proc {namespace}::handlers {{}} {{return [::GX::viewerDevelopmentInstalledBindings {module} {provider} [set {namespace}::root]]}}
proc {namespace}::dispatch {{operation scene}} {{return [::GX::viewerDevelopmentInstalledOpen {module} {provider} [set {namespace}::root] [::GX::datasetPublicationV2DictDefault $scene open_context {{}}]]}}
::GX::viewerBackendRegister {backend} {namespace}::dispatch
'''
    def section(name,fields):
        return '['+name+']\n'+''.join(str(k)+'='+str(v)+'\n' for k,v in fields.items())+'\n'
    descriptor='; SPDX-License-Identifier: GPL-3.0-or-later\n'
    descriptor+=section('meta',{'api_version':1,'id':module,'kind':'viewer','group':'Viewers','name':design['title'],
                       'version':version,'selectable':0,'default_enabled':1,'core':0,'runner':'service','order':900,
                       'depends':'math.numeric' if 'NUMERIC_API_v1' in requested else '','description':'Restricted C++ Viewer using approved public CORE facilities.'})
    descriptor+=section('viewers',{'api_version':1,'ids':provider})
    descriptor+=section('viewer.'+provider,{'name':design['title'],'backend':backend,'activation_api':'RESTRICTED_VIEWER_CLIENT_API_v1',
                         'gui_design':'gui/design.tcldict','gui_handler_command':namespace+'::handlers',
                         'capabilities':'declarative_gui;restricted_cpp;public_core_broker','semantic_group':'development',
                         'group_title':'Designed Viewers','short_title':design['title']})
    descriptor+=section('public_apis',{'ids':'RESTRICTED_VIEWER_CLIENT_API_v1'})
    descriptor+=section('public_api.RESTRICTED_VIEWER_CLIENT_API_v1',{'api_version':1,'name':'Restricted Viewer client',
                         'entrypoint':'api/viewer.tcl','namespace':namespace,'capabilities':'viewer_backend;viewer_gui_manifest'})
    descriptor+=section('documentation',{'api_version':1,'guide':'MANUAL.md',
                         'api_refs':';'.join(sorted({'VIEWER_DEVELOPMENT_API_v1'}|set(requested)|set(dictionary(design['requirements']))))})
    package_meta=section('package',{'api_version':1,'id':module,'name':design['title'],'version':version,
                                 'type':'module','framework_min':'0.9.8.10-dev-107','framework_max':''})
    manual=f'''# {design['title']}

This ordinary Viewer was authored with the restricted C++ SDK v1. The public CORE
Viewer GUI Host owns its interface; authored native code executes only in a
bounded separate process under the project-write tool grant. No authored Tcl,
private scientific implementation or automatic Dataset publication is included.

Use Run C++ handler to invoke the declared event. RAM fixtures are explicitly
synthetic. The default temperature exercise converts 18 degrees to 291.15 kelvin
through public NUMERIC_API_v1 array_binary.add and updates presentation only.

The package includes exact original C++/Builder source, SDK contract, validation,
build receipts, native binary, trusted C++/Tcl adapters and checksums. Reopen its
source project in Viewer Development Workspace to edit. Visual design remains
owned by Viewer Interface Builder. Runtime revalidates and builds a private copy
against the current trusted SDK; copied project reports cannot authorize code.

Candidate export does not install. Promotion belongs to the normal Plugin Manager.
Python authoring is disabled. This is a cooperative architecture/quality workflow,
with actual project filesystem write denial and bounded processes; it makes no
absolute hostile-native-code or account-wide confinement promise.
'''
    payload={
        'module.ini':descriptor.encode(),'plugin-package.ini':package_meta.encode(),
        'api/viewer.tcl':connector.encode(),'handlers.tcl':b'# Trusted CORE event facade; original author logic is source/handlers.cpp.\n',
        'gui/design.tcldict':(project/'design.gxtxt-viewer').read_bytes(),
        'source/design.gxtxt-viewer':(project/'design.gxtxt-viewer').read_bytes(),
        'source/handlers.cpp':(project/'handlers.cpp').read_bytes(),'source/project.json':(project/'project.json').read_bytes(),
        'native/viewer.so':(project/'derived/viewer.so').read_bytes(),
        'native/trusted_adapter_v1.cpp':(SDK.parent/'trusted_adapter_v1.cpp').read_bytes(),
        'native/gxtxt_viewer_sdk_v1.hpp':SDK.read_bytes(),'native/SDK_CONTRACT.json':(DEVELOPMENT/'policy_v1.json').read_bytes(),
        'review/validation.json':(project/'derived/validation.json').read_bytes(),
        'review/build.json':(project/'derived/build.json').read_bytes(),
        'MANUAL.md':manual.encode(),'LICENSE':(FRAMEWORK/'LICENSE').read_bytes(),
    }
    provenance={'schema':'gxtxt.restricted_viewer_candidate.v1','module_id':module,'version':version,
                'source_sha256':validation['source_sha256'],'design_sha256':validation['design_sha256'],
                'sdk_sha256':validation['sdk_sha256'],'policy_sha256':validation['policy_sha256'],
                'binary_sha256':built['binary_sha256'],'promotion':'official Plugin Manager only',
                'runtime':'VIEWER_DEVELOPMENT_API_v1 separate process', 'author_tcl':False}
    payload['RESTRICTED_VIEWER_PROVENANCE.json']=(json.dumps(provenance,indent=2,sort_keys=True)+'\n').encode()
    owner=FRAMEWORK/'plugins/modules/tool.script_module_builder/runtime/builder.py'
    spec=importlib.util.spec_from_file_location('gxtxt_trusted_package_writer',owner)
    builder=importlib.util.module_from_spec(spec);sys.modules[spec.name]=builder;spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix='candidate-',dir=project/'derived/tmp') as temporary:
        package,sha=builder.write_module_zip(payload,module,version,Path(temporary))
        output=project/'candidates'/sha[:16];output.mkdir(parents=True,exist_ok=True)
        destination=output/package.name
        if destination.exists():
            if digest(destination.read_bytes())!=sha: raise DevelopmentError('Candidate destination identity differs')
        else:
            os.link(package,destination)
            # Remove the temporary link before future project hardlink audits.
            package.unlink()
        (output/(destination.name+'.sha256')).write_text(sha+'  '+destination.name+'\n')
    result={'status':'CANDIDATE_EXPORTED','package':str(destination),'sha256':sha,'provenance':provenance,
            'installed':False,'review_required':True}
    write_json(project/'derived/candidate.json',result)
    return result

def source_transfer(project,operation,filename,source):
    if len(source)>65536 or b'\0' in source:
        raise DevelopmentError('Developer source/metadata transfer is bounded to 64 KiB UTF-8','SOURCE_BOUND')
    try: source.decode('utf-8')
    except UnicodeDecodeError: raise DevelopmentError('Developer source must be UTF-8','SOURCE_ENCODING')
    if operation=='check_source':
        meta=read_project(project)
        report=validate_source(source,project/'derived/tmp')
        capability_check(project,meta,api_catalog(project),report)
        write_json(project/'derived/import-validation.json',report)
        return report
    if filename not in {'handlers.cpp','project.json'}:
        raise DevelopmentError('Only original C++ source/project metadata are author-writable','SOURCE_TARGET')
    for name in ('handlers.cpp','project.json','design.gxtxt-viewer'):
        path=project/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1:
            raise DevelopmentError('Source write requires an existing ordinary developer project','SOURCE_TARGET')
    # Bad source/JSON remains repairable; full policy validation gates Build/Run.
    with tempfile.NamedTemporaryFile(prefix='.author-source-',dir=project,delete=False) as f:
        f.write(source);stage=Path(f.name)
    os.replace(stage,project/filename)
    return {'status':'SAVED','file':filename,'source_sha256':digest(source),'bytes':len(source),'code_generation_invoked':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=['init','validate','build','run','test','export','api','save','check_source','grant'])
    parser.add_argument('project',type=Path)
    parser.add_argument('--module-id',default='viewer.restricted_example')
    parser.add_argument('--event',type=json.loads)
    parser.add_argument('--state',type=json.loads)
    parser.add_argument('--file',choices=['handlers.cpp','project.json'],default='handlers.cpp')
    parser.add_argument('--tcl',action='store_true',help='Transport the same result through the existing CORE managed-request protocol')
    words=sys.argv[1:];author_command=[]
    if '--' in words:
        split=words.index('--');author_command=words[split+1:];words=words[:split]
    arguments=parser.parse_args(words);project=arguments.project.absolute()
    if author_command and arguments.operation!='grant': parser.error('An author command is accepted only by grant')
    try:
        if arguments.operation=='init': result=initialize(project,arguments.module_id)
        else:
            grant=enforce_project_write(project)
            if arguments.operation=='grant':
                command=author_command
                if command[:1]==['--']: command=command[1:]
                if not command: raise DevelopmentError('grant requires -- followed by the author command')
                os.chdir(project);os.execvpe(command[0],command,dict(os.environ))
            (project/'derived/tmp').mkdir(parents=True,exist_ok=True)
            if arguments.operation=='validate': result=validate(project)[1]
            elif arguments.operation=='build': result=build(project)
            elif arguments.operation=='export': result=export_candidate(project)
            elif arguments.operation in {'save','check_source'}: result=source_transfer(project,arguments.operation,arguments.file,sys.stdin.buffer.read(65537))
            elif arguments.operation=='run': result=run(project,arguments.event,arguments.state)
            elif arguments.operation=='test': result=test_project(project)
            else: result={'status':'CATALOG','apis':api_catalog(project),'profiles':POLICY['profiles'],'python_authoring':False}
            write_json(project/'derived/project-write-grant.json',grant)
        response={'ok':True,'result':result}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False,allow_nan=False),flush=True)
        return 0 if result.get('status') in {'PASS','CREATED','BUILT','COMPLETED','CATALOG','CANDIDATE_EXPORTED','SAVED'} else 1
    except Exception as error:
        response={'ok':False,'error':str(error),'code':getattr(error,'code','DEVELOPMENT_ERROR'),'detail':getattr(error,'detail',None)}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False),flush=True)
        return 1

if __name__=='__main__':
    request_process_group()
    signal.signal(signal.SIGTERM,cancel_children)
    signal.signal(signal.SIGINT,cancel_children)
    sys.exit(main())
