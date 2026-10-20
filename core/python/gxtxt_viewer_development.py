# SPDX-License-Identifier: GPL-3.0-or-later
"""One project/policy/build/native-runtime backend for the GUI and author CLI."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import os
import re
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

MANUAL_LIMIT_BYTES = POLICY.get('manual_limit_bytes', 65536)

_cancelling_children = False
def cancel_children(signum, frame):
    global _cancelling_children
    if _cancelling_children: return
    _cancelling_children = True
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

def facility_request(project, payload):
    """Project-scoped immutable requests; no second global capability registry."""
    meta=read_project(project)
    required={'schema','request_id','viewer_project','task','public_api_inspected',
              'missing_operation_or_contract','reproduction','why_existing_api_fails',
              'desired_input_output','minimal_acceptance_test','status'}
    if not isinstance(payload,dict) or set(payload)!=required or payload['schema']!='gxtxt.core_api_gap.v1' or payload['status']!='REQUESTED':
        raise DevelopmentError('Use the documented complete CORE_API_GAP request fields','GAP_INVALID')
    if not re.fullmatch(r'GAP-[A-Z0-9-]{1,60}',payload['request_id']) or payload['viewer_project']!=meta['module_id']:
        raise DevelopmentError('Gap identity must belong to this project','GAP_INVALID')
    if not isinstance(payload['public_api_inspected'],list) or not payload['public_api_inspected'] or not all(isinstance(x,str) and len(x)<=128 for x in payload['public_api_inspected']):
        raise DevelopmentError('List the inspected public API identities','GAP_INVALID')
    for key in required-{'public_api_inspected'}:
        if not isinstance(payload[key],str) or not payload[key].strip() or len(payload[key])>8192:
            raise DevelopmentError('Gap fields must be bounded nonempty text','GAP_INVALID')
    path=project/'requests'/(payload['request_id']+'.json')
    if path.exists():
        prior=json.loads(path.read_text())
        if prior['request']!=payload: raise DevelopmentError('An existing request is immutable; use a new request ID','GAP_IMMUTABLE')
        return {'status':'REQUESTED','request_id':payload['request_id'],'sha256':digest(path.read_bytes()),'path':str(path),'unchanged':True}
    record={'request':payload,'project_snapshot':{name:digest((project/name).read_bytes()) for name in ('handlers.cpp','project.json','design.gxtxt-viewer')},
            'ownership':'Project-associated request under VIEWER_DEVELOPMENT_API_v1; CORE owner adjudicates separately.'}
    write_json(path,record)
    return {'status':'REQUESTED','request_id':payload['request_id'],'sha256':digest(path.read_bytes()),'path':str(path),'unchanged':False}

def builder_edit(project, payload):
    """The same model/schema/Undo owner as Interface Builder; never Tcl source."""
    read_project(project)
    if not isinstance(payload,dict) or set(payload)!={'operation','arguments'} or not isinstance(payload['arguments'],list):
        raise DevelopmentError('Builder request requires operation and arguments','BUILDER_REQUEST')
    allowed={'add','property','layout','constraints','bind','remove','duplicate','reparent','reorder','metadata','undo','redo','inspect','icon_import','icon','properties'}
    if payload['operation'] not in allowed or len(payload['arguments'])>5:
        raise DevelopmentError('Unsupported public Builder model operation','BUILDER_REQUEST')
    if payload['operation']=='icon_import':
        if len(payload['arguments'])!=5:raise DevelopmentError('Icon import requires path, ID, title, category, license','BUILDER_REQUEST')
        path=Path(payload['arguments'][0]).absolute()
        if not (path.is_relative_to(project) or path.is_relative_to(FRAMEWORK/'core/assets/icons')):
            raise DevelopmentError('Author icons must be project-owned or shared CORE assets','CAPABILITY_DENIED')
    result=dictionary(core(project,'builder_edit',project/'design.gxtxt-viewer',tcl_result(payload)))
    receipt={'request':payload,'result':result,'design_sha256':digest((project/'design.gxtxt-viewer').read_bytes())}
    write_json(project/'derived/builder-receipt.json',receipt)
    write_json(project/'derived/provenance'/('builder-'+str(time.time_ns())+'.json'),receipt)
    return {'status':'CATALOG' if payload['operation']=='icon' and payload['arguments']==['catalog'] else 'SAVED','builder':result,'design_sha256':digest((project/'design.gxtxt-viewer').read_bytes())}

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
        response_limit=16777216 if operation=='builder_edit' or (operation=='validate_design' and len(arguments)==2 and str(arguments[1])=='with_catalog') else 4194304
        output.seek(0);errors.seek(0);raw=output.read(response_limit+1);err=errors.read(65536)
    if len(raw)>response_limit: raise DevelopmentError('Public CORE response exceeds bound')
    try: response=dictionary(raw.decode())
    except Exception: raise DevelopmentError(err.decode(errors='replace')[-4096:] or 'Invalid public CORE response')
    if code or response.get('ok')!='1':
        message=response.get('error') or err.decode(errors='replace')[-4096:] or 'Public CORE request failed'
        raise DevelopmentError(message,response.get('code','CORE_API_GAP'))
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
    return _describe_api_catalog(core(project,'api_catalog'))

def _describe_api_catalog(raw):
    catalog={key:dictionary(value) for key,value in dictionary(raw).items()}
    shapes={
        'value_set':{'request':{'component':'declared component index','value':'finite number or boolean'},'result':'display applied; no scientific effect'},
        'text_set':{'request':{'component':'declared status/label index','text':'literal UTF-8 <=256 bytes'},'result':'display applied'},
        'describe':{'request':{},'result':'public component contract'},
        'open':{'request':{'component':'declared graphics index','fixture':'0 Native2D, 1 Plot, 2 Native3D'},'result':'inert typed binding operation; actual GUI construction after successful event; no C++ return value'},
        'inspect':{'request':{'component':'declared graphics index'},'result':'public native receipt'},
        'demo_bind':{'request':{'component':'declared Native3D index'},'result':'inert typed binding operation; actual public v2 GUI construction after successful event; no C++ return value'},
        'array_unary.exp':{'request':{'value':'finite real scalar'},'result':'public NUMERIC_API_v1 scalar exponential; finite result required'},
        'array_unary.sqrt':{'request':{'value':'finite nonnegative scalar'},'result':'public NUMERIC_API_v1 scalar values; no Dataset'},
        'array_binary.add':{'request':{'left':'finite scalar','right':'finite scalar'},'result':'public NUMERIC_API_v1 scalar values; no Dataset'},
        'diagram_create':{'request':{'component':'declared Native2D index with diagram_catalog'},'result':'plan to open/create a canonical Interactive Document in the actual GUI Session; no author file access'},
        'widgetCreate':{'request':{'plot':'declared Plot component','form':'declared section with canonical Dataset and variable choices'},'result':'deferred binding through public Plot v4; discovery populates canonical variable choices; no author arrays or renderer'},
        'diagram_command':{'request':{'component':'declared Native2D index','tool':'catalog symbol or select/wire/junction/label/pan/probe','command':'fit/properties/rotate/delete'},'result':'typed operation applied through existing Native2D Viewport Host; gestures commit through Interactive Document and existing Viewer History'},
        'create':{'request':{'scope':'document_view_v1 declared Workspace component only'},'result':'existing Viewer Workspace owner creates only its canonical state; no arbitrary SDK API call'},
        'get':{'request':{'scope':'document_view_v1 declared Workspace component only'},'result':'existing owner opens its saved Viewer state'},
        'update':{'request':{'scope':'document_view_v1 declared Workspace component only'},'result':'existing owner saves with generation/revision/SHA guards'},
        'list':{'request':{'scope':'document_view_v1 declared Workspace component only'},'result':'existing scoped provider Workspace selector'},
        'scientificHistoryViewerRecord':{'request':{'scope':'document_view_v1 declared History component only'},'result':'existing owner captures this Viewer state'},
        'scientificHistoryViewerNavigate':{'request':{'scope':'document_view_v1 declared History component only'},'result':'existing owner restores bounded Undo/Redo; no author callbacks, raw recipes or files'},
    }
    for operation in ('node_list','circuit_prepare','circuit_sweep_prepare','circuit_sweep_submit','submit','status','cancel','reconnect','log','import_table'):
        shapes[operation]={'request':{'scope':'scientific_view_v1 declared scientific section and explicit component indices'},'result':'deferred trusted GUI Host operation through existing Scientific Execution/Script Job/Publication; no raw paths or author Job registry'}
    for operation in ('dataset_expression','array_reduce.rms','array_reduce.minimum','array_reduce.maximum','statistics','residual_metrics','interpolate','complex_unary.magnitude','complex_unary.phase_rad','complex_unary.phase_deg'):
        shapes[operation]={'request':{'scope':'declared Numeric form, explicit canonical Variable IDs, scalar parameters, units and row bounds'},'result':'deferred GUI Host operation through public Numeric; vectors remain Managed Resources in canonical result Documents; no arrays returned to C++'}
    shapes['datasetPublicationV2Finalize']={'request':{'scope':'Numeric result and declared Dataset selector only'},'result':'explicit canonical Dataset transaction; original request/units/source revisions retained; no author paths or writer handles'}
    shapes['uniform_grid']={'request':{'scope':'declared Scientific physical sweep axes, finite SI bounds and count1..4'},'result':'existing public Numeric grid retained by trusted form; no arrays returned to C++'}
    shapes['parallelExecutionExecute']={'request':{'scope':'declared Scientific physical sweep submission only, at most16 cases'},'result':'existing Parallel admission coordination; ordinary Script Job supervisor owns actual simulations, no author callbacks/processes'}
    for key,row in catalog.items():
        allowed=POLICY['capabilities'].get(key)
        row['sdk_exposed']=bool(allowed)
        if key=='VIEWER_DEVELOPMENT_API_v1':
            row['author_tools']={'inspect':{'targets':['handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer','sdk_v1'],'result':'bounded inert UTF-8 content/sha256/bytes; no arbitrary paths'},'api_document':{'request':'api --document catalogued_PUBLIC_API_vN','result':'bounded exact installed public manual; no private file reader'},'manual_asset':{'operations':['list','add','remove'],'input':'logical asset_id and exact source-identical gui_test capture_id; JSON stdin','result':'images/ASSET_ID.png preserved by normal export;32 images,8MiB each,16MiB total; no author paths'},'gui_test':{'requires':'explicit real Workspace attachment; identical normally installed source; current Session','actions':['open','workspace_open','workspace_save','workspace_review','workspace_upgrade','status','close','capture','capture_verify','capture_preview','resize','label','label_apply','label_close','click','choice','text','tab','pointer','plot_pointer','key','property','wire_route','properties_commit','properties_close'],'scope':'assigned Viewer only; no Tcl, widget paths, filesystem destinations or global desktop; not a C++ runtime capability'}}
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
        if not available or str(available.get('version'))!=str(request['version']) or str(available.get('available',available.get('enabled')))!='1':
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
              'numeric_add':('NUMERIC_API_v1','array_binary.add'), 'numeric_sqrt':('NUMERIC_API_v1','array_unary.sqrt'),'numeric_exp':('NUMERIC_API_v1','array_unary.exp'),
              'diagram_open':('NATIVE2D_VIEWPORT_HOST_v1','diagram_create'),
              'diagram_tool':('NATIVE2D_VIEWPORT_HOST_v1','diagram_command'),
              'diagram_command':('NATIVE2D_VIEWPORT_HOST_v1','diagram_command')}
    required['plot_discover']=('PLOT_DATASET_API_v4','widgetCreate')
    required['plot_bind']=('PLOT_DATASET_API_v4','widgetCreate')
    for method in ('numeric_discover','numeric_evaluate'):
        required[method]=('NUMERIC_API_v1','dataset_expression')
    required['numeric_statistics']=('NUMERIC_API_v1','statistics')
    required['numeric_compare']=('NUMERIC_API_v1','residual_metrics')
    required['numeric_publish']=('DATASET_PUBLICATION_API_v2','datasetPublicationV2Finalize')
    for method,operation in zip(('scientific_discover','scientific_prepare','scientific_submit','scientific_status','scientific_cancel','scientific_reconnect','scientific_log','scientific_import'),('node_list','circuit_prepare','submit','status','cancel','reconnect','log','import_table')):
        required[method]=('SCIENTIFIC_EXECUTION_API_v1',operation)
    for method in validation['sdk_calls']:
        api,operation=required[method]
        if operation not in requested.get(api,set()): raise DevelopmentError('SDK call lacks requested authorized capability: '+method,'CAPABILITY_DENIED')
        extra={'numeric_statistics':{'array_reduce.rms','array_reduce.minimum','array_reduce.maximum'},'numeric_compare':{'dataset_expression'}}.get(method,set())
        if not extra.issubset(requested.get('NUMERIC_API_v1',set())):
            raise DevelopmentError('SDK Numeric form needs its complete bounded operation grant: '+method,'CAPABILITY_DENIED')
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
    # Preserve the legacy template's scalar-only grant. New scientific form
    # operations require an explicit author request, never an implicit upgrade.
    for request in meta['capabilities']:
        if request['api_id']=='NUMERIC_API_v1': request['operations']=['array_binary.add','array_unary.sqrt','array_unary.exp']
    (project/'handlers.cpp').write_text(SOURCE)
    (project/'design.gxtxt-viewer').write_text(design+'\n')
    write_json(project/'project.json',meta)
    return {'status':'CREATED','project':str(project),'grant':grant,'source_sha256':digest(SOURCE.encode())}

def workspace_callback_semantics(design):
    """Canonical existing callback semantics; unknown fields stay significant."""
    presentation = {'icon', 'icon_disabled', 'icon_hover', 'icon_selected',
                    'presentation', 'icon_position', 'icon_size', 'icon_spacing',
                    'command_icons'}
    semantic = {key: value for key, value in design.items()
                if key not in {'icons', 'title', 'version', 'geometry', 'origin', 'components'}}
    semantic['components'] = []
    for value in tkinter.Tcl().splitlist(design['components']):
        component = dictionary(value)
        component.pop('layout', None)
        component['properties'] = {key: item for key, item in dictionary(component['properties']).items() if key not in presentation}
        semantic['components'].append(component)
    return semantic

def workspace_callback_contract(meta, design, source_sha256):
    """Presentation-only compatibility, independent of exact runtime guards.

    Components retain declaration ordinals, type, parent, scalar defaults and
    every command/scientific reference. Unknown fields remain significant.
    """
    semantic = workspace_callback_semantics(design)
    project = {key: value for key, value in meta.items() if key not in {'version', 'provenance', 'tests'}}
    content = dict(schema='gxtxt.viewer_workspace_callback_contract.v1', source_sha256=source_sha256, project=project, design=semantic)
    return digest(json.dumps(content, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode())

def _viewer_compile_signal(project, token):
    """Tell the matching GUI request an actual Clang build is starting.

    Never use stdout or stderr: Tcl's managed-job protocol merges both streams.
    The token belongs to this one GUI event, not an arbitrary caller path.
    Signalling is auxiliary and cannot influence build success or failure.
    """
    if token is None:
        return
    try:
        path = project/'derived/tmp'/('viewer-compiling-' + token + '.marker')
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW
        fd = os.open(path, flags, 0o600)
        os.close(fd)
    except OSError:
        pass


def _viewer_compilation_cache_fingerprints(project):
    """Bind a trusted build receipt to all relevant source and toolchain inputs."""
    inputs = {
        'source_sha256': project/'handlers.cpp',
        'design_sha256': project/'design.gxtxt-viewer',
        'project_sha256': project/'project.json',
        'sdk_sha256': SDK,
        'policy_sha256': DEVELOPMENT/'policy_v1.json',
        'compiler_sha256': COMPILER,
        'adapter_sha256': SDK.parent/'trusted_adapter_v1.cpp',
        'toolchain_manifest_sha256': DEVELOPMENT/'toolchain/manifest.json',
        'development_backend_sha256': Path(__file__),
        'cpp_policy_backend_sha256': FRAMEWORK/'core/python/gxtxt_cpp_policy.py',
    }
    return {key: digest(path.read_bytes()) for key, path in inputs.items()}


def _viewer_reusable_build(project):
    """Reuse only the binary described by an exact, intact local build receipt.

    A cache miss falls back to the existing validation and Clang build path.
    Explicit Build/Export and debugger builds are deliberately unaffected.
    """
    receipt_path = project/'derived/build.json'
    binary_path = project/'derived/viewer.so'
    try:
        for path, maximum in ((receipt_path, 1048576), (binary_path, 33554432)):
            if (not path.is_file() or path.is_symlink() or
                    path.stat().st_nlink != 1 or path.stat().st_size > maximum):
                return None
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        if (not isinstance(receipt, dict) or
                receipt.get('schema') != 'gxtxt.viewer_build.v1' or
                receipt.get('status') != 'BUILT' or
                receipt.get('debug_symbols') is not False or
                receipt.get('cache_schema') != 'gxtxt.viewer_compilation_cache.v1'):
            return None
        previous = receipt.get('validation')
        if not isinstance(previous, dict) or previous.get('status') != 'PASS':
            return None
        current = _viewer_compilation_cache_fingerprints(project)
        if receipt.get('cache_fingerprints') != current:
            return None
        for key in ('source_sha256', 'design_sha256', 'project_sha256',
                    'sdk_sha256', 'policy_sha256', 'compiler_sha256'):
            if previous.get(key) != current[key]:
                return None
        if receipt.get('adapter_sha256') != current['adapter_sha256']:
            return None
        if receipt.get('binary_sha256') != digest(binary_path.read_bytes()):
            return None
        return receipt
    except (OSError, ValueError, TypeError, KeyError, UnicodeError):
        return None


def validate(project, reuse_compiled=False):
    meta=read_project(project)
    cached=_viewer_reusable_build(project) if reuse_compiled else None
    report=(dict(cached['validation']) if cached is not None else
            validate_source((project/'handlers.cpp').read_bytes(),project/'derived/tmp'))
    admitted=dictionary(core(project,'validate_design',project/'design.gxtxt-viewer','with_catalog'))
    design=dictionary(admitted['design'])
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Project and Builder design identities differ','PROJECT_INVALID')
    report['design_sha256']=digest((project/'design.gxtxt-viewer').read_bytes())
    report['project_sha256']=digest((project/'project.json').read_bytes())
    report['project_profile']=meta['profile']
    report['workspace_callback_contract_sha256']=workspace_callback_contract(meta,design,report['source_sha256'])
    catalog=_describe_api_catalog(admitted['catalog'])
    requested=capability_check(project,meta,catalog,report)
    components=[dictionary(value) for value in tkinter.Tcl().splitlist(design['components'])]
    diagrams=[component for component in components if component['type']=='native2d' and dictionary(component['properties']).get('diagram_catalog')]
    numeric_forms=[component for component in components if component['type']=='section' and (dictionary(component['properties']).get('numeric_expression') or dictionary(component['properties']).get('numeric_kind'))]
    for component in components:
        if component['type']=='section' and dictionary(component['properties']).get('scientific_probe_diagram'):
            for api, needed in {'SCIENTIFIC_EXECUTION_API_v1':'circuit_prepare','PLOT_DATASET_API_v4':'widgetCreate','NATIVE2D_VIEWPORT_HOST_v1':'diagram_command'}.items():
                if needed not in requested.get(api,set()):
                    raise DevelopmentError('Declared scientific probe requires its existing scoped capability: '+api+'/'+needed,'CAPABILITY_DENIED')
        if component['type']=='section' and dictionary(component['properties']).get('scientific_sweep_axes'):
            _sweep_grants(requested)
        if component['type'] in {'workspace','history'}:
            if meta['profile'] not in {'document_view_v1','scientific_view_v1'} or not (diagrams or (numeric_forms and 'dataset_expression' in requested.get('NUMERIC_API_v1',set()))):
                raise DevelopmentError('Canonical lifecycle requires explicit document_view_v1 and a declared canonical diagram or explicitly granted Numeric form; legacy profiles remain read-only','CAPABILITY_DENIED')
            api,required=('SESSION_WORKSPACE_API_v1',{'create','get','update','list'}) if component['type']=='workspace' else ('SCIENTIFIC_RECIPE_API_v1',{'scientificHistoryViewerRecord','scientificHistoryViewerNavigate'})
            if not required.issubset(requested.get(api,set())):
                raise DevelopmentError('Declared lifecycle component requires explicit scoped capability: '+api,'CAPABILITY_DENIED')
    report['canonical_lifecycle_scope']='declared diagram Viewer state through existing guarded Workspace/History owners' if meta['profile'] in {'document_view_v1','scientific_view_v1'} else 'read-only profiles unchanged'
    write_json(project/'derived/validation.json',report)
    write_json(project/'derived/api-catalog.json',catalog)
    return meta,report,design,requested

def build(project, debug=False):
    return _compile_admitted(project, *validate(project), debug=debug)

def _compile_admitted(project, meta, report, design, requested, debug=False, reuse=False, compile_token=None):
    """Build explicitly, or reuse an identical admitted release binary for events.

    Admission still rechecks the live CORE design and requested capabilities.
    The post-compile source/design/project checks remain mandatory.
    """
    if report['status']!='PASS': return {'status':'REJECTED','validation':report,'code_generation_invoked':False}
    if reuse and not debug:
        cached=_viewer_reusable_build(project)
        if cached is not None and all(
                cached['validation'].get(key)==report.get(key)
                for key in ('source_sha256','design_sha256','project_sha256',
                            'sdk_sha256','policy_sha256','compiler_sha256')):
            return dict(cached, code_generation_invoked=False, cache_hit=True)
    source=(project/'handlers.cpp').read_bytes()
    _viewer_compile_signal(project, compile_token)
    with tempfile.TemporaryDirectory(prefix='build-',dir=project/'derived/tmp') as temporary:
        stage=Path(temporary);author=stage/'handlers.cpp';author.write_bytes(source)
        fixed=[*FLAGS,('-O0' if debug else '-O1'),('-g3' if debug else '-g0'),'-fPIC','-fvisibility=hidden','-fno-stack-protector',
               '-ffile-prefix-map='+str(stage)+'='+str(project) if debug else '-ffile-prefix-map='+str(stage)+'=.', '-ffile-prefix-map='+str(DEVELOPMENT)+'=sdk']
        if debug:
            # Clang otherwise omits unused SDK aggregate definitions. GDB can
            # name a const Event reference but cannot inspect its real members.
            fixed.append('-fstandalone-debug')
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
        (project/('derived/debug-viewer.so' if debug else 'derived/viewer.so')).write_bytes(binary)
        (project/'derived/trusted_adapter_v1.cpp').write_bytes((SDK.parent/'trusted_adapter_v1.cpp').read_bytes())
        result={'schema':'gxtxt.viewer_build.v1','status':'BUILT','code_generation_invoked':True,
                'validation':report,'binary_sha256':digest(binary),'adapter_sha256':digest((SDK.parent/'trusted_adapter_v1.cpp').read_bytes()),
                'compiler_version':'19.1.7','link_policy':'fixed SDK adapter; no author libraries/flags; no undefined symbols',
                'log':'\n'.join(logs),'capabilities':meta['capabilities']}
        result['debug_symbols']=debug
        if not debug:
            fingerprints=_viewer_compilation_cache_fingerprints(project)
            if any(fingerprints.get(key)!=report.get(key) for key in
                   ('source_sha256','design_sha256','project_sha256','sdk_sha256',
                    'policy_sha256','compiler_sha256')) or (
                    fingerprints['adapter_sha256']!=result['adapter_sha256']):
                raise DevelopmentError('Build inputs changed during compilation','SOURCE_CHANGED')
            result['cache_schema']='gxtxt.viewer_compilation_cache.v1'
            result['cache_fingerprints']=fingerprints
            result['cache_hit']=False
        write_json(project/('derived/debug-build.json' if debug else 'derived/build.json'),result)
        return result

def finite(value):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value):
        raise DevelopmentError('SDK numbers must be finite scalar values','RUNTIME_VALUE')
    return value

def _sweep_grants(requested):
    for api,needed in {'SCIENTIFIC_EXECUTION_API_v1':{'circuit_sweep_prepare','circuit_sweep_submit'},'NUMERIC_API_v1':{'uniform_grid'},'PARALLEL_EXECUTION_API_v1':{'parallelExecutionExecute'}}.items():
        if not needed.issubset(requested.get(api,set())):
            raise DevelopmentError('Declared physical sweep requires explicit existing CORE capability: '+api,'CAPABILITY_DENIED')

def broker_message(project,message,by_index,requested,deadline):
    operations=[];numeric=[]
    operation=message['operation'];component=by_index.get(message['component']);left=finite(message['left']);right=finite(message['right'])
    response={'request':message['request'],'ok':True,'value':0.0}
    if operation in {4,6,7}:
        numeric_operation={4:'array_binary.add',6:'array_unary.sqrt',7:'array_unary.exp'}[operation]
        if operation==6 and left<0: raise DevelopmentError('Scalar SDK square root requires a nonnegative real operand','RUNTIME_DOMAIN')
        if numeric_operation not in requested.get('NUMERIC_API_v1',set()): raise DevelopmentError('Numeric facility is not authorized','CAPABILITY_DENIED')
        operands=[left,right] if operation==4 else [left]
        result=dictionary(core(project,{4:'numeric_add',6:'numeric_sqrt',7:'numeric_exp'}[operation],*operands,timeout=max(.1,min(12,deadline-time.monotonic()))))
        values=tkinter.Tcl().splitlist(result['values'])
        if len(values)!=1: raise DevelopmentError('Numeric scalar result shape differs','CORE_RESULT')
        response['value']=finite(float(values[0]));numeric.append({'api_id':'NUMERIC_API_v1','operation':numeric_operation,'left':left,'right':right,'result':response['value']})
    elif operation in {21,22,23,24,25}:
        needed={21:{'dataset_expression'},22:{'dataset_expression'},23:{'statistics','array_reduce.rms','array_reduce.minimum','array_reduce.maximum'},24:{'dataset_expression','residual_metrics'},25:set()}[operation]
        properties=dictionary(component['properties']) if component is not None else {}
        kind=properties.get('numeric_kind','expression')
        if operation==22 and kind=='interpolation': needed=needed|{'interpolate'}
        if operation==22 and kind=='complex_projection': needed=needed|{'complex_unary.magnitude','complex_unary.phase_rad','complex_unary.phase_deg'}
        if not needed.issubset(requested.get('NUMERIC_API_v1',set())) or (operation==25 and 'datasetPublicationV2Finalize' not in requested.get('DATASET_PUBLICATION_API_v2',set())):
            raise DevelopmentError('Declared Numeric facility is not authorized','CAPABILITY_DENIED')
        if component is None or component['type']!='section' or not (properties.get('numeric_expression') or properties.get('numeric_kind')):
            raise DevelopmentError('Numeric operation requires a declared Numeric form section','RUNTIME_COMPONENT')
        target=''
        if operation==25:
            other=by_index.get(int(left)) if left==int(left) else None
            if other is None or other['type']!='dataset_selector': raise DevelopmentError('Numeric publication target must be a declared Dataset selector','RUNTIME_COMPONENT')
            target=other['id']
        operations.append({'operation':{21:'numeric_discover',22:'numeric_evaluate',23:'numeric_statistics',24:'numeric_compare',25:'numeric_publish'}[operation],'component':component['id'],'value':target})
    elif operation in {19,20}:
        if 'widgetCreate' not in requested.get('PLOT_DATASET_API_v4',set()): raise DevelopmentError('Canonical Plot facility is not authorized','CAPABILITY_DENIED')
        if component is None or component['type']!='section' or not dictionary(component['properties']).get('plot_dataset'):
            raise DevelopmentError('Plot binding requires a declared canonical Plot form','RUNTIME_COMPONENT')
        target=''
        if operation==20:
            other=by_index.get(int(left)) if left==int(left) else None
            if other is None or other['type']!='plot': raise DevelopmentError('Plot binding target must be a declared Plot component','RUNTIME_COMPONENT')
            target=other['id']
        operations.append({'operation':'plot_discover' if operation==19 else 'plot_bind','component':component['id'],'value':target})
    elif operation in range(11,19):
        method,needed={11:('scientific_discover','node_list'),12:('scientific_prepare','circuit_prepare'),13:('scientific_submit','submit'),14:('scientific_status','status'),15:('scientific_cancel','cancel'),16:('scientific_reconnect','reconnect'),17:('scientific_log','log'),18:('scientific_import','import_table')}[operation]
        if needed not in requested.get('SCIENTIFIC_EXECUTION_API_v1',set()): raise DevelopmentError('Scientific facility is not authorized','CAPABILITY_DENIED')
        if component is None or component['type']!='section' or dictionary(component['properties']).get('scientific_provider')!='core.ngspice.circuit':
            raise DevelopmentError('Scientific operation needs a declared scientific form section','RUNTIME_COMPONENT')
        if dictionary(component['properties']).get('scientific_sweep_axes'):
            _sweep_grants(requested)
        target=''
        if operation in {12,18}:
            other=by_index.get(int(left)) if left==int(left) else None
            expected='native2d' if operation==12 else 'dataset_selector'
            if other is None or other['type']!=expected: raise DevelopmentError('Scientific source/output component type differs','RUNTIME_COMPONENT')
            if operation==12 and not dictionary(other['properties']).get('diagram_catalog'): raise DevelopmentError('Scientific source needs a declared diagram profile','RUNTIME_COMPONENT')
            target=other['id']
        operations.append({'operation':method,'component':component['id'],'value':target})
    elif operation in {8,9,10}:
        needed='diagram_create' if operation==8 else 'diagram_command'
        if needed not in requested.get('NATIVE2D_VIEWPORT_HOST_v1',set()): raise DevelopmentError('Diagram facility is not authorized','CAPABILITY_DENIED')
        if component is None or component['type']!='native2d': raise DevelopmentError('Diagram requires a declared Native2D component','RUNTIME_COMPONENT')
        properties=dictionary(component['properties'])
        catalog=properties.get('diagram_catalog','')
        if not catalog: raise DevelopmentError('Declare the Native2D diagram_catalog in Builder','CORE_API_GAP')
        if operation==9:
            try: core(project,'diagram_tool_validate',catalog,message['text'])
            except DevelopmentError as error: raise DevelopmentError(str(error),'CAPABILITY_DENIED') from error
        if operation==10 and message['text'] not in {'fit','properties','rotate','delete'}:
            raise DevelopmentError('Unsupported admitted diagram command','CAPABILITY_DENIED')
        operations.append({'operation':{8:'diagram_open',9:'diagram_tool',10:'diagram_command'}[operation],
                           'component':component['id'],'value':message['text'],'catalog':catalog})
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
    return response,operations,numeric

def run(project,event=None,state=None,compile_token=None):
    meta,validation,design,requested=validate(project,reuse_compiled=True)
    built=_compile_admitted(project,meta,validation,design,requested,reuse=True,compile_token=compile_token)
    if built['status']!='BUILT': return built
    if any(digest((project/name).read_bytes())!=validation[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
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
                response,ui_receipts,numeric_receipts=broker_message(project,message,by_index,requested,deadline)
                operations.extend(ui_receipts);numeric.extend(numeric_receipts)
                reply(response)
            if done is None:
                status='TIMED_OUT' if process.poll() is None else 'CRASHED'
                result={'status':status,'exit_code':process.poll(),'operations':[],'numeric_receipts':numeric,'state':state}
            elif not done.get('ok'):
                result={'status':'FAILED','errors':done.get('errors',[]),'operations':[],'state':state}
            else:
                result={'status':'COMPLETED','operations':operations,'numeric_receipts':numeric,'state':done['state'],
                        'source_sha256':validation['source_sha256'],'design_sha256':validation['design_sha256'],'project_sha256':validation['project_sha256'],'binary_sha256':built['binary_sha256'],'event':event,
                        'execution':'compiled restricted C++ in isolated native worker; typed public CORE broker',
                        'compile_cache_hit':bool(built.get('cache_hit',False)),
                        'compiled_this_event':bool(built.get('code_generation_invoked',False))}
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
proc {namespace}::workspaceOpen {{context}} {{return [::GX::viewerDevelopmentInstalledOpen {module} {provider} [set {namespace}::root] $context]}}
::GX::viewerBackendRegister {backend} {namespace}::dispatch
'''
    def section(name,fields):
        return '['+name+']\n'+''.join(str(k)+'='+str(v)+'\n' for k,v in fields.items())+'\n'
    descriptor='; SPDX-License-Identifier: GPL-3.0-or-later\n'
    descriptor+=section('meta',{'api_version':1,'id':module,'kind':'viewer','group':'Viewers','name':design['title'],
                       'version':version,'license':'GPL-3.0-or-later','selectable':0,'default_enabled':1,'core':0,'runner':'service','order':900,
                       'depends':'math.numeric' if 'NUMERIC_API_v1' in requested else '','description':'Restricted C++ Viewer using approved public CORE facilities.'})
    descriptor+=section('viewers',{'api_version':1,'ids':provider})
    descriptor+=section('viewer.'+provider,{'name':design['title'],'backend':backend,'activation_api':'RESTRICTED_VIEWER_CLIENT_API_v1',
                         'gui_design':'gui/design.tcldict','gui_handler_command':namespace+'::handlers',
                         'capabilities':'declarative_gui;restricted_cpp;public_core_broker','semantic_group':'development',
                         'group_title':'Designed Viewers','short_title':design['title']})
    descriptor+=section('public_apis',{'ids':'RESTRICTED_VIEWER_CLIENT_API_v1'})
    descriptor+=section('public_api.RESTRICTED_VIEWER_CLIENT_API_v1',{'api_version':1,'name':'Restricted Viewer client',
                         'entrypoint':'api/viewer.tcl','namespace':namespace,'capabilities':'viewer_backend;viewer_gui_manifest'})
    if any(dictionary(component)['type']=='workspace' for component in tkinter.Tcl().splitlist(design['components'])):
        workspace_id=module.replace('.','_').replace('-','_')+'_'+provider+'_interface_state'
        descriptor+=section('workspaces',{'api_version':1,'ids':workspace_id})
        descriptor+=section('workspace.'+workspace_id,{'entrypoint':'api/viewer.tcl','viewer_provider':provider,
            'type':'Restricted C++ Viewer state','schema':'gxtxt.viewer_interface_state.v1','version':1,'accepted_versions':1,
            'validate':'::GX::viewerGuiDesignStateValidate','open':namespace+'::workspaceOpen'})
    descriptor+=section('documentation',{'api_version':1,'guide':'MANUAL.md',
                         'api_refs':';'.join(sorted({'VIEWER_DEVELOPMENT_API_v1'}|set(requested)|set(dictionary(design['requirements']))))})
    dev108_properties={'component_visibility','visibility_commands','scientific_provider','numeric_dataset','plot_dataset'}
    declared_dev108=any(dev108_properties.intersection(dictionary(dictionary(c)['properties'])) for c in tkinter.Tcl().splitlist(design['components']))
    package_meta=section('package',{'api_version':1,'id':module,'name':design['title'],'version':version,
                                 'type':'module','framework_min':('0.9.8.10-dev-108' if declared_dev108 or design.get('icons') or meta['profile'] in {'document_view_v1','scientific_view_v1'} or set(validation['sdk_calls']) & {'numeric_exp','diagram_open','diagram_tool','diagram_command','numeric_discover','numeric_evaluate','numeric_statistics','numeric_compare','numeric_publish'} else '0.9.8.10-dev-107'),'framework_max':''})
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
    manual_source=project/'MANUAL.md'
    if manual_source.exists() or manual_source.is_symlink():
        if manual_source.is_symlink() or not manual_source.is_file() or manual_source.stat().st_nlink!=1 or manual_source.stat().st_size>MANUAL_LIMIT_BYTES:
            raise DevelopmentError('Manual must be an ordinary project-owned UTF-8 file within 256 KiB','SOURCE_TARGET')
        manual_bytes=manual_source.read_bytes()
        try: manual_bytes.decode('utf-8')
        except UnicodeDecodeError: raise DevelopmentError('Manual must be UTF-8','SOURCE_ENCODING')
        if b'\0' in manual_bytes: raise DevelopmentError('Manual contains a NUL byte','SOURCE_ENCODING')
    else: manual_bytes=manual.encode()
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
        'MANUAL.md':manual_bytes,'LICENSE':(FRAMEWORK/'LICENSE').read_bytes(),
    }
    if manual_source.exists(): payload['source/MANUAL.md']=manual_bytes
    from gxtxt_viewer_icons import package_resources
    payload.update(package_resources(design.get('icons','')))
    from gxtxt_viewer_manual_assets import resources
    manual_resources, manual_inventory = resources(project)
    for reference in re.findall(r'!\[[^\]]*\]\(([^)]+)\)', manual_bytes.decode('utf-8')):
        if reference not in manual_resources:
            raise DevelopmentError('Manual image must name an admitted images/ASSET_ID.png resource', 'MANUAL_ASSET')
    payload.update(manual_resources)
    # Preserve editable originals through the normal source-project export.
    if manual_inventory['assets']:
        payload['source/manual-assets.json'] = (json.dumps(manual_inventory, indent=2, sort_keys=True)+'\n').encode()
        for name, item in manual_inventory['assets'].items():
            payload['source/manual-assets/'+item['sha256']+'.png'] = manual_resources['images/'+name+'.png']
    provenance={'schema':'gxtxt.restricted_viewer_candidate.v1','module_id':module,'version':version,
                'source_sha256':validation['source_sha256'],'design_sha256':validation['design_sha256'],
                'sdk_sha256':validation['sdk_sha256'],'policy_sha256':validation['policy_sha256'],
                'binary_sha256':built['binary_sha256'],'manual_sha256':digest(manual_bytes),'manual_assets':manual_inventory['assets'],'promotion':'official Plugin Manager only',
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
            'installed':False,'review_required':True,'descriptor_text':descriptor,
            'descriptor_sha256':digest(payload['module.ini']),'manual_sha256':digest(manual_bytes),
            'package_metadata_text':package_meta,'package_metadata_sha256':digest(payload['plugin-package.ini']),
            'manual_source':'project/MANUAL.md' if manual_source.exists() else 'legacy_generated_template',
            'descriptor_receipt_scope':'Exact module.ini and plugin-package.ini bytes generated and packaged by the existing Module packaging owner; framework_min belongs to plugin-package.ini'}
    write_json(project/'derived/candidate.json',result)
    return result

def source_transfer(project,operation,filename,source):
    limit=MANUAL_LIMIT_BYTES if operation=='save' and filename=='MANUAL.md' else POLICY['source_limit_bytes']
    if len(source)>limit or b'\0' in source:
        raise DevelopmentError('Manual transfer is bounded to 256 KiB UTF-8; C++ source/metadata remain bounded to 64 KiB' if limit==MANUAL_LIMIT_BYTES else 'Developer source/metadata transfer is bounded to 64 KiB UTF-8','SOURCE_BOUND')
    try: source.decode('utf-8')
    except UnicodeDecodeError: raise DevelopmentError('Developer source must be UTF-8','SOURCE_ENCODING')
    if operation=='check_source':
        meta=read_project(project)
        report=validate_source(source,project/'derived/tmp')
        capability_check(project,meta,api_catalog(project),report)
        write_json(project/'derived/import-validation.json',report)
        return report
    if filename not in {'handlers.cpp','project.json','MANUAL.md'}:
        raise DevelopmentError('Only original C++ source/project metadata/manual are author-writable','SOURCE_TARGET')
    for name in ('handlers.cpp','project.json','design.gxtxt-viewer'):
        path=project/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1:
            raise DevelopmentError('Source write requires an existing ordinary developer project','SOURCE_TARGET')
    target=project/filename
    if (target.exists() or target.is_symlink()) and (target.is_symlink() or not target.is_file() or target.stat().st_nlink!=1):
        raise DevelopmentError('Author target must be an ordinary unlinked project file','SOURCE_TARGET')
    # Bad source/JSON remains repairable; full policy validation gates Build/Run.
    with tempfile.NamedTemporaryFile(prefix='.author-source-',dir=project,delete=False) as f:
        f.write(source);stage=Path(f.name)
    os.replace(stage,project/filename)
    return {'status':'SAVED','file':filename,'source_sha256':digest(source),'bytes':len(source),'code_generation_invoked':False}

def inspect_source(project,filename):
    """Existing Workspace browser's fixed source targets, inert and bounded."""
    check_project_root(project)
    targets={name:project/name for name in ('handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer')}
    targets['sdk_v1']=SDK
    if filename not in targets: raise DevelopmentError('Unknown fixed developer source target','SOURCE_TARGET')
    return inspect_text(targets[filename],filename,4194304 if filename=='design.gxtxt-viewer' else MANUAL_LIMIT_BYTES if filename=='MANUAL.md' else 65536)

def inspect_text(path,identity,limit):
    if path.is_symlink() or not path.is_file() or path.stat().st_nlink!=1 or path.stat().st_size>limit:
        raise DevelopmentError('Inspection requires an ordinary bounded source/document file','SOURCE_TARGET')
    # No parent symlink traversal, path expansion or author-supplied filename.
    if path.absolute()!=path.resolve(): raise DevelopmentError('Linked inspection paths are refused','SOURCE_TARGET')
    with path.open('rb') as stream:
        before=os.fstat(stream.fileno());raw=stream.read(limit+1);after=os.fstat(stream.fileno())
    if len(raw)>limit or (before.st_dev,before.st_ino,before.st_mtime_ns,before.st_size)!=(after.st_dev,after.st_ino,after.st_mtime_ns,after.st_size) or before.st_nlink!=1:
        raise DevelopmentError('Inspection source changed while reading','SOURCE_CHANGED')
    if b'\0' in raw: raise DevelopmentError('Inspection accepts inert UTF-8 text only','SOURCE_ENCODING')
    return {'status':'SAVED','identity':identity,'content':raw.decode('utf-8'),'bytes':len(raw),'sha256':digest(raw),'read_only':True}

def inspect_document(project,identity):
    check_project_root(project)
    # Fixed companion references belong to catalogued owners; their historical
    # filenames need not themselves invent a versioned public API identity.
    companions={
        'VIEWER_GUI_DESIGN_v1':('VIEWER_GUI_HOST_API_v1','VIEWER_GUI_DESIGN_v1.md'),
        'NUMERIC_EXPRESSION_OPERATIONS':('NUMERIC_API_v1','NUMERIC_EXPRESSION_OPERATIONS.md'),
    }
    api=identity.removesuffix('.md')
    if api not in companions and not re.fullmatch(r'[A-Z][A-Z0-9_]*_v[0-9]+(?:\.md)?',identity):
        raise DevelopmentError('Choose a catalogued public API identity, without a path','DOCUMENT_TARGET')
    catalog=api_catalog(project)
    if api in companions:
        owner, filename=companions[api]
        if owner not in catalog:
            raise DevelopmentError('Owning public API is not in the installed catalog','DOCUMENT_TARGET')
        return inspect_text(FRAMEWORK/'docs/api'/filename,api,1048576)
    if api not in catalog: raise DevelopmentError('Public API is not in the installed catalog','DOCUMENT_TARGET')
    meta=catalog[api];declared=meta.get('documentation','')
    provider=meta['provider']
    roots=[FRAMEWORK/'docs/api'] if provider=='CORE' else [FRAMEWORK/'plugins/modules'/provider,FRAMEWORK/'docs/api']
    # Catalog metadata is trusted but never turns this into an arbitrary reader.
    # Legacy descriptors may include docs/ or only a basename.
    candidates=[]
    for base in roots:
        if declared and not Path(declared).is_absolute() and '..' not in Path(declared).parts:
            candidates += [base/declared,base/'docs'/declared]
        candidates += [base/(api+'.md'),base/'docs'/(api+'.md')]
    for path in candidates:
        if path.is_file(): return inspect_text(path,api,1048576)
    raise DevelopmentError('Catalogued public manual is unavailable','DOCUMENT_TARGET')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=['init','validate','build','run','test','export','api','inspect','manual_asset','save','check_source','grant','facility_request','builder','debug','debug_control','debug_status','gui_test','workspace_upgrade_review'])
    parser.add_argument('project',type=Path)
    parser.add_argument('--module-id',default='viewer.restricted_example')
    parser.add_argument('--event',type=json.loads)
    parser.add_argument('--state',type=json.loads)
    parser.add_argument('--breakpoints',type=json.loads,default=[])
    parser.add_argument('--file',choices=['handlers.cpp','project.json','MANUAL.md'],default='handlers.cpp')
    parser.add_argument('--target',choices=['handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer','sdk_v1'],default='handlers.cpp',help='Fixed read-only Workspace source browser target for inspect')
    parser.add_argument('--document',help='Read-only installed public API manual identity for api; paths are refused')
    parser.add_argument('--debug-token',help='Opaque request identity for source-bound debugger status/control; no command text')
    parser.add_argument('--compile-token',help='Opaque GUI build-notification identity for run only')
    parser.add_argument('--tcl',action='store_true',help='Transport the same result through the existing CORE managed-request protocol')
    words=sys.argv[1:];author_command=[]
    if '--' in words:
        split=words.index('--');author_command=words[split+1:];words=words[:split]
    arguments=parser.parse_args(words);project=arguments.project.absolute()
    if author_command and arguments.operation!='grant': parser.error('An author command is accepted only by grant')
    try:
        if arguments.document and arguments.operation!='api': raise DevelopmentError('--document belongs only to api','DOCUMENT_TARGET')
        if arguments.debug_token is not None and (arguments.operation not in {'debug','debug_status','debug_control'} or not re.fullmatch(r'[a-zA-Z0-9_-]{1,96}',arguments.debug_token)):
            raise DevelopmentError('Debugger token must be bounded opaque text on a debugger request','DEBUG_STATE')
        if arguments.compile_token is not None and (arguments.operation!='run' or not re.fullmatch(r'[a-zA-Z0-9_-]{1,96}',arguments.compile_token)):
            raise DevelopmentError('Invalid GUI compile-notice identity','REQUEST_LIMIT')
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
            elif arguments.operation=='inspect': result=inspect_source(project,arguments.target)
            elif arguments.operation=='api' and arguments.document: result=inspect_document(project,arguments.document)
            elif arguments.operation in {'save','check_source'}:
                limit=MANUAL_LIMIT_BYTES if arguments.operation=='save' and arguments.file=='MANUAL.md' else POLICY['source_limit_bytes']
                result=source_transfer(project,arguments.operation,arguments.file,sys.stdin.buffer.read(limit+1))
            elif arguments.operation=='gui_test':
                from gxtxt_viewer_gui_test import gui_test
                raw=sys.stdin.buffer.read(16385)
                if len(raw)>16384:raise DevelopmentError('GUI test action exceeds16KiB','GUI_TEST_REQUEST')
                result=gui_test(project,json.loads(raw))
            elif arguments.operation=='workspace_upgrade_review':
                from gxtxt_viewer_workspace import review
                raw=sys.stdin.buffer.read(8388609)
                if len(raw)>8388608:raise DevelopmentError('Saved declaration review exceeds8MiB','REQUEST_LIMIT')
                result=review(project,json.loads(raw))
            elif arguments.operation=='manual_asset':
                from gxtxt_viewer_manual_assets import manual_asset
                raw=sys.stdin.buffer.read(4097)
                if len(raw)>4096: raise DevelopmentError('Manual resource request exceeds4KiB','MANUAL_ASSET')
                result=manual_asset(project,json.loads(raw))
            elif arguments.operation in {'facility_request','builder'}:
                raw=sys.stdin.buffer.read(65537)
                if len(raw)>65536: raise DevelopmentError('Author request exceeds 64 KiB','REQUEST_LIMIT')
                result=(facility_request if arguments.operation=='facility_request' else builder_edit)(project,json.loads(raw))
            elif arguments.operation=='debug':
                from gxtxt_viewer_cpp_debug import debug
                result=debug(project,arguments.breakpoints,arguments.event,arguments.state,arguments.debug_token)
            elif arguments.operation=='debug_control':
                read_project(project)
                raw=sys.stdin.buffer.read(16385)
                if len(raw)>16384:raise DevelopmentError('Debug control exceeds bound','DEBUG_CONTROL')
                control=json.loads(raw)
                if not isinstance(control,dict) or set(control)-{'operation','source_sha256','frame'} or control.get('operation') not in {'continue','into','over','out','pause','stop','frame'}:
                    raise DevelopmentError('Only enumerated native debugger controls are admitted','DEBUG_CONTROL')
                if digest((project/'handlers.cpp').read_bytes())!=control.get('source_sha256'):raise DevelopmentError('Source revision changed; restart Debug','SOURCE_CHANGED')
                snapshot=json.loads((project/'derived/debug/state.json').read_text())
                if arguments.debug_token is not None and snapshot.get('debug_token')!=arguments.debug_token:raise DevelopmentError('Debugger run identity changed','DEBUG_STATE')
                if snapshot['source_sha256']!=control['source_sha256'] or snapshot['state'] not in {'RUNNING','PAUSED','CONTINUING','STARTING'}:raise DevelopmentError('Debugger is stale or terminal','DEBUG_STATE')
                if control['operation'] not in {'pause','stop'} and snapshot['state']!='PAUSED':raise DevelopmentError('Control requires an actual paused C++ frame','DEBUG_STATE')
                if type(control.get('frame',0))is not int or not 0<=control.get('frame',0)<16:raise DevelopmentError('Frame index outside bound','DEBUG_CONTROL')
                path=project/'derived/debug/command.json'
                if path.exists():raise DevelopmentError('Wait for the pending debugger command','DEBUG_BUSY')
                write_json(path,control);result={'status':'SAVED','operation':control['operation']}
            elif arguments.operation=='debug_status':
                read_project(project)
                path=project/'derived/debug/state.json'
                if not path.exists():result={'status':'SAVED','debug':{'state':'STARTING','sequence':0,'frames':[],'locals':[]}}
                else:
                    if path.is_symlink() or path.stat().st_size>2097152:raise DevelopmentError('Invalid debugger status','DEBUG_STATE')
                    snapshot=json.loads(path.read_text())
                    if arguments.debug_token is not None and snapshot.get('debug_token')!=arguments.debug_token:
                        snapshot={'state':'STARTING','debug_token':arguments.debug_token,'sequence':0,'frames':[],'locals':[],'errors':[]}
                    result={'status':'SAVED','debug':snapshot}
            elif arguments.operation=='run': result=run(project,arguments.event,arguments.state,arguments.compile_token)
            elif arguments.operation=='test': result=test_project(project)
            else: result={'status':'CATALOG','apis':api_catalog(project),'profiles':POLICY['profiles'],'python_authoring':False}
            write_json(project/'derived/project-write-grant.json',grant)
        response={'ok':True,'result':result}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False,allow_nan=False),flush=True)
        return 0 if result.get('status') in {'PASS','CREATED','BUILT','COMPLETED','CATALOG','CANDIDATE_EXPORTED','SAVED','REQUESTED'} else 1
    except Exception as error:
        response={'ok':False,'error':str(error),'code':getattr(error,'code','DEVELOPMENT_ERROR'),'detail':getattr(error,'detail',None)}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False),flush=True)
        return 1

if __name__=='__main__':
    request_process_group()
    signal.signal(signal.SIGTERM,cancel_children)
    signal.signal(signal.SIGINT,cancel_children)
    sys.exit(main())
