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
// Public SDK v1 is supplied automatically; reviewed standard headers are supported.
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
        source=payload['arguments'][0]
        if isinstance(source,dict):
            if set(source)!={'source_format','source'} or source['source_format']!='svg' or not isinstance(source['source'],str) or len(source['source'].encode('utf-8'))>262144:
                raise DevelopmentError('Inline icon source requires bounded SVG text','BUILDER_REQUEST')
        else:
            if not isinstance(source,str):raise DevelopmentError('Icon source requires an owned path or inline SVG','BUILDER_REQUEST')
            path=Path(source).absolute()
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

def _core_timeout_evidence(project, command, child, output, errors, started, timeout, cleanup):
    """Keep bounded developer evidence; never replace the original timeout."""
    detail={'pid':child.pid,'timeout_seconds':timeout,'elapsed_seconds':time.monotonic()-started,
            'cleanup':cleanup,'scope':'Owned request only; descendant retirement is not certified.'}
    try:
        parent=project/'derived/diagnostics'
        if (project/'derived').resolve()!=project/'derived':
            raise ValueError('Linked diagnostic parent')
        parent.mkdir(mode=0o700,exist_ok=True)
        if parent.resolve()!=parent or not parent.is_dir():
            raise ValueError('Ordinary project diagnostic directory required')
        folder=parent/('core-timeout-'+str(time.time_ns())+'-'+str(child.pid))
        folder.mkdir(mode=0o700)
        streams={}
        for name,stream in (('stdout',output),('stderr',errors)):
            stream.seek(0,os.SEEK_END);total=stream.tell()
            stream.seek(0);prefix=stream.read(1048576)
            stream.seek(max(0,total-65536));tail=stream.read(65536)
            for suffix,raw in (('prefix',prefix),('tail',tail)):
                path=folder/(name+'.'+suffix+'.bin')
                fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
                with os.fdopen(fd,'wb') as target:
                    target.write(raw);target.flush();os.fsync(target.fileno())
            streams[name]={'bytes':total,'sha256':digest(prefix) if total<=len(prefix) else None,
                           'prefix_sha256':digest(prefix),'tail_sha256':digest(tail),'prefix_bytes':len(prefix),
                           'tail_offset':max(0,total-len(tail)),'tail_bytes':len(tail),
                           'complete_in_prefix':total<=len(prefix)}
        record=dict(detail,schema='gxtxt.development.core_timeout.v1',command=command,cwd=str(project),
                    streams=streams,source_sha256={name:digest((FRAMEWORK/name).read_bytes()) for name in
                    ('core/python/gxtxt_viewer_development.py','core/tcl/viewer_development_request.tcl')})
        path=folder/'receipt.json';write_json(path,record)
        with path.open('rb') as stream:os.fsync(stream.fileno())
        for directory in (folder,parent):
            fd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
            try:os.fsync(fd)
            finally:os.close(fd)
        detail['diagnostics']=str(path)
    except Exception as error:
        detail['diagnostic_error']=str(error)[:1024]
    return detail

def core(project, operation, *arguments, timeout=12):
    """Fixed trusted helper; project arguments are data, never Tcl programs."""
    command=['/usr/bin/tclsh',str(FRAMEWORK/'core/tcl/viewer_development_request.tcl'),str(FRAMEWORK),operation,*map(str,arguments)]
    with open(os.devnull, 'rb') as null, tempfile.TemporaryFile(dir=project/'derived/tmp') as output, tempfile.TemporaryFile(dir=project/'derived/tmp') as errors:
        child=subprocess.Popen(command,stdin=null,stdout=output,stderr=errors,
                               cwd=project,env=project_environment(project),start_new_session=True)
        ACTIVE_PROCESSES.add(child.pid)
        started=time.monotonic()
        try: code=child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            cleanup={'signal':'SIGKILL','known_owned_group':child.pid,'reaped':False}
            try:os.killpg(child.pid,signal.SIGKILL)
            except ProcessLookupError:cleanup['signal_result']='group_already_absent'
            except OSError as error:cleanup['signal_error']=str(error)
            try:
                cleanup['returncode']=child.wait(timeout=3)
                cleanup['reaped']=True
            except subprocess.TimeoutExpired:cleanup['reap_error']='Owned child did not exit within cleanup bound'
            except OSError as error:cleanup['reap_error']=str(error)
            detail=_core_timeout_evidence(project,command,child,output,errors,started,timeout,cleanup)
            raise DevelopmentError('Public CORE request timed out','CORE_TIMEOUT',detail)
        finally:
            if child.returncode is not None:ACTIVE_PROCESSES.discard(child.pid)
        response_limit=16777216 if operation in {'builder_edit','runtime_design'} or (operation=='validate_design' and len(arguments)==2 and str(arguments[1])=='with_catalog') else 4194304
        output.seek(0);errors.seek(0);raw=output.read(response_limit+1);err=errors.read(65536)
    if len(raw)>response_limit: raise DevelopmentError('Public CORE response exceeds bound')
    try: response=dictionary(raw.decode())
    except Exception: raise DevelopmentError(err.decode(errors='replace')[-4096:] or 'Invalid public CORE response')
    if code or response.get('ok')!='1':
        message=response.get('error') or err.decode(errors='replace')[-4096:] or 'Public CORE request failed'
        raise DevelopmentError(message,response.get('code','CORE_API_GAP'))
    return response['result']

def read_project(project, *, installed=False):
    if not installed:
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
        'document_bind':{'request':{'document':'declared document component index, kind html/pdf/code/table','dataset_selector':'declared compatible Dataset selector with matching content_kind'},'result':'existing CORE read-only document/PDF/source/paged-table consultation; original Session/source revision, no author filesystem/renderer'},
        'raster_bind':{'request':{'viewport':'declared native2d component with source_kind raster','dataset_selector':'declared canonical selector with content_kind raster'},'result':'canonical image.raster admission into existing Native2D Document/Resource owner; original bytes/identity/units, no author path or pixel array'},
        'raster_tool':{'request':{'viewport':'declared raster Native2D component','tool':'select/rectangle/polygon/annotation/move/rotate/pivot/pan'},'result':'local shared Native2D controller tool; geometry stays in the existing native owner'},
        'raster_command':{'request':{'viewport':'declared raster Native2D component','command':'fit/cancel/finish/delete_roi/delete_annotation or panel_open/panel_close/editor_apply/editor_cancel:declared_section_id'},'result':'finite existing native controller or declared anchored UI Field operation, original Document and History lifetime checks'},
        'tex_command':{'request':{'form':'complete declared TeX article section index','operation':'new/open/save/build/rebuild/cancel/preview/diagnostic_open/import_assets/remove_asset/export_tex/export_pdf/export_assets/refresh/import_source'},'result':'existing Document/Resource/SourceSurface/managed native TeX/PDF/FilePublication owners; explicit build only, no author source store or renderer'},
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
        'export':{'request':{'scope':'complete declared EM form; finite duplicate/Workspace manager action; current original em_models Document only'},'result':'existing Workspace export retains original nested managed resources; no C++ path or package bytes'},
        'import':{'request':{'scope':'complete declared EM form; finite duplicate/Workspace manager action only'},'result':'existing Workspace import with normal names/dialogs and resource ownership; no C++ path or arbitrary payload'},
        'em_command':{'request':{'scope':'complete declared EM model section index plus finite operation; exact EM service grants required'},'result':'deferred original native EM/Workspace/Job/Plot service action; no model arrays or execution paths returned to C++'},
        'workbench_command':{'request':{'scope':'complete declared canonical geometry section index; finite lifecycle and public Workbench3D purpose-form commands'},'result':'original Workbench3D Document, editable Native3D v1 host and semantic History; no author geometry/model/renderer or Tcl dispatcher'},
        'transform_form':{'request':{'scope':'scientific_view_v1 declared baseline_correct form; explicit create_corrected/cancel/inspect/discover actions, even without SDK calls'},'result':'deferred existing responsive Transform and canonical publication; no authored manifest, callback, arrays or SDK method'},
        'pcb_source_form':{'request':{'scope':'document_view_v1 declared eagle_pair_fixed_v1 import-only form; explicit import_pair/refresh/inspect/cancel through existing reserved GUI actions, including empty SDK callers'},'result':'existing CORE canonical Document/Resource immutable source snapshot; normal chooser only, no SDK method, authored paths, new renderer or Script grant'},
        'execute_responsive':{'request':{'scope':'declared baseline_correct form and explicit Create corrected Dataset only'},'result':'existing single-output responsive Transform with precommit cancellation; no implicit preview or private Job'},
        'provenance':{'request':{'scope':'actual committed output of the owned baseline_correct form'},'result':'canonical transform provenance and effective baseline receipt'},
        'open_page':{'request':{'scope':'Host::em_command(form, runtime) only; fixed existing Runtime page'},'result':'ordinary Configuration navigation; no configuration mutation or widget paths returned to C++'},
        'cellFieldProfileSpec':{'request':{'scope':'finite EM profile or publish_charts; actual canonical field roles'},'result':'source-bound scatter of actual stored cell-centroid samples at all Y; no interpolation or arrays returned to C++'},
        'upsertPlotFromSpec':{'request':{'scope':'finite EM publish_charts; stable installed Viewer producer and actual Dataset identity'},'result':'two independent retained Graph/Variants through existing Plot owner; no author spec/file path'},
        'render':{'request':{'scope':'finite EM publish_charts and its two source-bound Graphs'},'result':'existing native Plot rendering and scientific revision checks'},
        'widgetExport':{'request':{'scope':'finite EM export_field; current declared field Plot and normal Save dialog'},'result':'existing native PNG/SVG/PDF export; no author path or renderer'},
        'publish_bundle':{'request':{'scope':'finite EM export_field; explicit user destination and existing Plot writer'},'result':'existing complete-file publication with normal overwrite policy; no arbitrary author writer or destination'},
        'cell_field_bind':{'request':{'scope':'declared Native3D target on a complete EM field form; Host::em_command(form, field_3d), exact Plot v4 and EM fieldDescribe grants'},'result':'same canonical linked triangles and cell values through existing Native3D renderer; planar XY with Z=0, no interpolation, 3D solve or CAD volume'},
        'scientificHistoryViewerRecord':{'request':{'scope':'document_view_v1 declared History component only'},'result':'existing owner captures this Viewer state'},
        'scientificHistoryViewerNavigate':{'request':{'scope':'document_view_v1 declared History component only'},'result':'existing owner restores bounded Undo/Redo; no author callbacks, raw recipes or files'},
    }
    for operation in ('node_list','circuit_prepare','circuit_sweep_prepare','circuit_sweep_submit','submit','status','cancel','reconnect','log','import_table'):
        shapes[operation]={'request':{'scope':'scientific_view_v1 declared scientific section and explicit component indices'},'result':'deferred trusted GUI Host operation through existing Scientific Execution/Script Job/Publication; no raw paths or author Job registry'}
    for operation in ('libraryCatalogPage','getProviderCapabilities','getLibraryCapabilities','listLibraryEntries','openLibraryViewer','verifyLibrary','installLibrary','updateLibrary','removeLibrary','registerLibrary','unregisterLibrary','invokeLibraryAction'):
        shapes[operation]={'request':{'scope':'declared catalog_owner=scientific_libraries section; actual selected registry IDs; operation-specific explicit project grant'},'result':'deferred typed catalog presentation/action through existing CORE ScientificLibraryManager; capability/availability gating and normal shared administrative dialogs; no author registry, provider invocation or filesystem access'}
    for operation in ('dataset_expression','array_reduce.rms','array_reduce.minimum','array_reduce.maximum','statistics','residual_metrics','interpolate','complex_unary.magnitude','complex_unary.phase_rad','complex_unary.phase_deg'):
        shapes[operation]={'request':{'scope':'declared Numeric form, explicit canonical Variable IDs, scalar parameters, units and row bounds'},'result':'deferred GUI Host operation through public Numeric; vectors remain Managed Resources in canonical result Documents; no arrays returned to C++'}
    shapes['datasetPublicationV2Finalize']={'request':{'scope':'Numeric result and declared Dataset selector only'},'result':'explicit canonical Dataset transaction; original request/units/source revisions retained; no author paths or writer handles'}
    shapes['uniform_grid']={'request':{'scope':'declared Scientific physical sweep axes, finite SI bounds and count1..4'},'result':'existing public Numeric grid retained by trusted form; no arrays returned to C++'}
    for operation in ('defaultModel','validate','saveModel','listModels','loadModel','runAsync','jobStatus','jobLog','cancel','resultDescribe','resultPreview','publish','fieldDescribe'):
        if operation not in shapes:
            shapes[operation]={'request':{'scope':'complete declared electromagnetic model section; exact finite em_command action and explicit native service grants'},'result':'existing native EM validation/model Workspace/managed Gmsh-GetDP Job/canonical publication/exact field owner; no raw source payload, process, renderer or path from C++'}
    shapes['parallelExecutionExecute']={'request':{'scope':'declared Scientific physical sweep submission only, at most16 cases'},'result':'existing Parallel admission coordination; ordinary Script Job supervisor owns actual simulations, no author callbacks/processes'}
    for operation in ('activateDocument','guiMount','guiInspect','selectionSet','guiCommand'):
        shapes[operation]={'request':{'scope':'complete declared editable3d geometry form through workbench_command only'},'result':'original Workbench3D canonical lifecycle and finite geometry command; no arbitrary owner dispatch'}
    for key,row in catalog.items():
        row['providers']=[dictionary(value) for value in tkinter.Tcl().splitlist(row.get('providers',''))]
        row['version_conflict']=len({str(p.get('version','')) for p in row['providers']})>1
        if len(row['providers'])>1:row['provider']='';row['provider_selection']='multiple_declaring_owners; inspect provider-qualified declaration'
        if row['version_conflict']:row['version']=''
        allowed=POLICY['capabilities'].get(key)
        row['sdk_exposed']=bool(allowed)
        if key=='VIEWER_DEVELOPMENT_API_v1':
            row['author_tools']={'inspect':{'targets':['handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer','sdk_v1'],'result':'bounded inert UTF-8 content/sha256/bytes; no arbitrary paths'},'api_document':{'request':'api --document catalogued_PUBLIC_API_vN','result':'bounded exact installed public manual; no private file reader'},'manual_asset':{'operations':['list','add','remove'],'input':'logical asset_id and exact source-identical gui_test capture_id; JSON stdin','result':'images/ASSET_ID.png preserved by normal export;32 images,8MiB each,16MiB total; no author paths'},'gui_test':{'requires':'explicit real Workspace attachment; identical normally installed source; current Session','actions':['open','workspace_open','workspace_save','workspace_review','workspace_upgrade','status','close','capture','capture_verify','capture_preview','resize','label','label_apply','label_close','click','choice','list_select','table_select','table_scroll','table_copy','table_page','text','tab','pointer','plot_pointer','key','document_find','document_pointer','document_zoom','pdf_control','pdf_pointer','pdf_key','pdf_resize','pdf_close','property','wire_route','properties_commit','properties_close'],'scope':'assigned Viewer only; no Tcl, widget paths, filesystem destinations or global desktop; not a C++ runtime capability'}}
        row['allowed_operations']=allowed['operations'] if allowed else []
        row['operation_shapes']={op:shapes[op] for op in row['allowed_operations']}
        if key=='ELECTROMAGNETIC_SIMULATION_API_v1':
            row['operation_shapes']={op:{'request':{'scope':'complete declared EM model form; Host::em_command(form, finite_action), explicit native service grants'},'result':'original EM model/managed FEM Job/retained log/canonical publication/exact node-cell field service; no source payload, process or file path returned to C++'} for op in row['allowed_operations']}
        if key=='WORKBENCH_3D_API_v1':
            row['operation_shapes']={op:{'request':{'scope':'complete declared editable3d geometry form through workbench_command only'},'result':'original viewer.3d_workbench/workbench_3d scientific owner; one editable host, exact Document identity and native geometry resources'} for op in row['allowed_operations']}
        if key=='DATASET_TRANSFORM_API_v1':
            row['sdk_exposed']=False
            row['operation_shapes']={op:{'request':{'scope':'exact declared baseline_correct form; captured execution only for cancel'},'result':'existing responsive canonical Transform/provenance owner; no Script responsive grant or new SDK method'} for op in row['allowed_operations']}
        row['authorization_reason']='Explicit trusted SDK v1 facility; project must request it' if allowed else 'Installed public API is outside this restricted SDK; request a reviewed CORE facility extension'
        if key=='DATASET_TRANSFORM_API_v1':row['authorization_reason']='Finite declared baseline_correct GUI form only; scientific profile and exact grants; no authored SDK method'
    return catalog

def _sdk_required():
    required={'text':('VIEWER_GUI_HOST_API_v1','text_set'), 'number':('VIEWER_GUI_HOST_API_v1','value_set'),
              'flag':('VIEWER_GUI_HOST_API_v1','value_set'), 'demo':('VIEWER_COMPONENT_DEMO_API_v1','open'),
              'numeric_add':('NUMERIC_API_v1','array_binary.add'), 'numeric_sqrt':('NUMERIC_API_v1','array_unary.sqrt'),'numeric_exp':('NUMERIC_API_v1','array_unary.exp'),
              'diagram_open':('NATIVE2D_VIEWPORT_HOST_v1','diagram_create'),
              'diagram_tool':('NATIVE2D_VIEWPORT_HOST_v1','diagram_command'),
              'diagram_command':('NATIVE2D_VIEWPORT_HOST_v1','diagram_command')}
    required['document_bind']=('VIEWER_GUI_HOST_API_v1','document_bind')
    for method in ('raster_bind','raster_tool','raster_command'):
        required[method]=('VIEWER_GUI_HOST_API_v1',method)
    required['tex_command']=('VIEWER_GUI_HOST_API_v1','tex_command')
    required['em_command']=('VIEWER_GUI_HOST_API_v1','em_command')
    required['workbench_command']=('VIEWER_GUI_HOST_API_v1','workbench_command')
    required['catalog_refresh']=('SCIENTIFIC_LIBRARY_MANAGER_API_v1','libraryCatalogPage')
    required['catalog_inspect']=('SCIENTIFIC_LIBRARY_MANAGER_API_v1','getLibraryCapabilities')
    # The actual finite catalog_action is checked against its exact operation
    # grant at runtime, in addition to the form's read/discovery grant.
    required['catalog_action']=('SCIENTIFIC_LIBRARY_MANAGER_API_v1','getLibraryCapabilities')
    required['plot_discover']=('PLOT_DATASET_API_v4','widgetCreate')
    required['plot_bind']=('PLOT_DATASET_API_v4','widgetCreate')
    for method in ('numeric_discover','numeric_evaluate'):
        required[method]=('NUMERIC_API_v1','dataset_expression')
    required['numeric_statistics']=('NUMERIC_API_v1','statistics')
    required['numeric_compare']=('NUMERIC_API_v1','residual_metrics')
    required['numeric_publish']=('DATASET_PUBLICATION_API_v2','datasetPublicationV2Finalize')
    for method,operation in zip(('scientific_discover','scientific_prepare','scientific_submit','scientific_status','scientific_cancel','scientific_reconnect','scientific_log','scientific_import'),('node_list','circuit_prepare','submit','status','cancel','reconnect','log','import_table')):
        required[method]=('SCIENTIFIC_EXECUTION_API_v1',operation)
    return required

def _sdk_extra(method):
    return {'numeric_statistics':{'array_reduce.rms','array_reduce.minimum','array_reduce.maximum'},'numeric_compare':{'dataset_expression'}}.get(method,set())

def _capability_admission(meta, request, catalog):
    """Read-only request admission, shared by validation and reference metadata."""
    if not isinstance(request,dict) or set(request)!={'api_id','version','operations'} or not isinstance(request['api_id'],str) or type(request['version']) is not int or not isinstance(request['operations'],list) or not all(isinstance(op,str) for op in request['operations']):
        return 'PROJECT_POLICY'
    api=request['api_id'];policy=POLICY['capabilities'].get(api);available=catalog.get(api)
    if api=='PLOT_DATASET_API_v3' or (api.startswith('PLOT_DATASET') and request['version']==3):
        return 'DEPRECATED_PLOT_API'
    if not available or available.get('version_conflict') or str(available.get('version'))!=str(request['version']) or str(available.get('available',available.get('enabled')))!='1':
        return 'CORE_API_GAP'
    if not policy or api not in POLICY['profiles'][meta['profile']] or request['version']!=policy['version'] or not set(request['operations']).issubset(policy['operations']):
        return 'CAPABILITY_DENIED'
    if api=='VIEWER_GUI_HOST_API_v1' and 'pcb_source_form' in request['operations'] and meta['profile']!='document_view_v1':
        return 'CAPABILITY_DENIED'
    return 'ADMITTED_REQUEST'

def _browser_cpp_catalog(catalog, project=None):
    # Reference discovery is inert: no validate_source, source execution,
    # compiler, build receipt update or grant file is involved.
    context={'status':'NO_PROJECT','source_validation':'not_checked_by_metadata_browser',
             'runtime_grants':'not_activated_by_metadata_browser'}
    meta=None;requests={}
    if project is not None:
        try:
            meta=read_project(project)
            inputs=('project.json','handlers.cpp','design.gxtxt-viewer')
            before={name:digest((project/name).read_bytes()) for name in inputs}
            if read_project(project)!=meta or before!={name:digest((project/name).read_bytes()) for name in inputs}:
                raise ValueError('Project changed during reference discovery; refresh its saved metadata')
            context.update(status='SAVED_PROJECT_METADATA',project=str(project),profile=meta['profile'],
                           project_sha256=before['project.json'],source_sha256=before['handlers.cpp'],
                           design_sha256=before['design.gxtxt-viewer'])
            for request in meta['capabilities']:
                if not isinstance(request,dict) or not isinstance(request.get('api_id'),str):
                    context['status']='PROJECT_POLICY';continue
                api=request['api_id']
                if api in requests:
                    requests[api]={'request':request,'status':'DUPLICATE_REQUEST'}
                    context['status']='PROJECT_POLICY'
                else:
                    requests[api]={'request':request,'status':_capability_admission(meta,request,catalog)}
        except (DevelopmentError, OSError, ValueError, TypeError) as error:
            context.update(status='PROJECT_UNAVAILABLE',reason=str(error));meta=None;requests={}
    for api in requests:
        if api not in catalog:
            catalog[api]={'api_id':api,'available':False,'enabled':False,
                          'metadata_error':'Requested API has no installed declaration; no provider is inferred'}
    for api,row in catalog.items():
        request=requests.get(api)
        row['cpp_project_status']=request['status'] if request else ('NOT_REQUESTED' if meta else context['status'])
        row['cpp_project_request']=request['request'] if request else {}
        row['cpp_methods']={}
    required=_sdk_required()
    prototypes=re.findall(r'^\s*(void|double)\s+(\w+)\(([^;]*)\) const;',SDK.read_text(),re.M)
    for result,method,arguments in prototypes:
        if method not in required:continue
        api,operation=required[method]
        if api not in catalog:continue
        grants=[(api,operation)]+[('NUMERIC_API_v1',op) for op in sorted(_sdk_extra(method))]
        missing=[]
        for family,op in grants:
            requested=requests.get(family,{})
            if requested.get('status')!='ADMITTED_REQUEST' or op not in requested.get('request',{}).get('operations',[]):
                missing.append(family+'/'+op)
        names=[re.search(r'(\w+)\s*$',arg).group(1) for arg in arguments.split(',') if arg.strip()]
        call='host.'+method+'('+', '.join(names)+');'
        if result!='void':call=result+' result = '+call
        catalog[api]['cpp_methods'][method]={
            'signature':result+' gx::Host::'+method+'('+arguments+') const;',
            'example':call,'operation':operation,'result_type':result,
            'required_capabilities':[family+'/'+op for family,op in grants],
            'project_status':('ADMITTED_REQUEST' if not missing else 'NOT_ADMITTED') if context['status']=='SAVED_PROJECT_METADATA' else context['status'],
            'missing_capabilities':missing,
            'admission_scope':'saved request/profile/provider policy only; Validate checks source and declared forms; finite action grants are checked at runtime',
            'sdk_sha256':digest(SDK.read_bytes())}
    return context

def _transform_form_admission(meta,design,validation,requested,catalog):
    """Declared mutating actions require admission independently of sdk_calls."""
    # A source-transfer check is not a live interface admission. Preserve its
    # source-only behavior; Validate and compiled/installed admission pass the
    # actual authoritative design and must generate the complete proof.
    if design is None:return {}
    forms=[]
    for value in tkinter.Tcl().splitlist(design['components']):
        component=dictionary(value);properties=dictionary(component['properties'])
        if 'transform_kind' in properties:
            if component['type']!='section' or properties['transform_kind']!='baseline_correct':
                raise DevelopmentError('Only a declared baseline_correct Transform form is admitted','RUNTIME_COMPONENT')
            forms.append(component['id'])
    if not forms:return {}
    needed={'VIEWER_GUI_HOST_API_v1':{'transform_form'},
            'DATASET_TRANSFORM_API_v1':{'execute_responsive','cancel','provenance'},
            'PLOT_DATASET_API_v4':{'widgetCreate'}}
    if meta['profile']!='scientific_view_v1':
        raise DevelopmentError('Baseline Transform forms require scientific_view_v1','CAPABILITY_DENIED')
    for api,operations in needed.items():
        if not operations.issubset(requested.get(api,set())):
            raise DevelopmentError('Declared Transform form lacks its explicit grant: '+api,'CAPABILITY_DENIED')
    available=set(tkinter.Tcl().splitlist(catalog['DATASET_TRANSFORM_API_v1'].get('operations','')))
    if not needed['DATASET_TRANSFORM_API_v1'].issubset(available):
        raise DevelopmentError('Current Transform host contract lacks responsive/cancel/provenance metadata','CORE_API_GAP')
    return dict(schema='gxtxt.viewer_transform_admission.v1',profile=meta['profile'],forms=forms,
                source_sha256=validation['source_sha256'],design_sha256=validation['design_sha256'],
                project_sha256=validation['project_sha256'],
                grants={api:sorted(operations) for api,operations in needed.items()})

def _pcb_source_form_admission(meta,design,validation,requested,catalog):
    """A declared import form needs proof independently of compiled SDK calls."""
    if design is None:return {}
    forms=[];commands={};controls={}
    for raw in tkinter.Tcl().splitlist(design['components']):
        component=dictionary(raw);properties=dictionary(component['properties'])
        if not any(key.startswith('pcb_') for key in properties):continue
        if {key for key in properties if key.startswith('pcb_')}!={'pcb_source_kind','pcb_sources','pcb_status','pcb_inspector','pcb_commands'}:
            raise DevelopmentError('PCB source form requires exactly its five closed properties','RUNTIME_COMPONENT')
        if component['type']!='section' or properties.get('pcb_source_kind')!='eagle_pair_fixed_v1':
            raise DevelopmentError('Only the declared fixed-pair import section is admitted','RUNTIME_COMPONENT')
        form=component['id'];forms.append(form)
        commands[form]=dictionary(properties['pcb_commands'])
        controls[form]={key:properties[key] for key in ('pcb_sources','pcb_status','pcb_inspector')}
    if not forms:return {}
    if meta['profile']!='document_view_v1':
        raise DevelopmentError('PCB source forms require document_view_v1','CAPABILITY_DENIED')
    if 'pcb_source_form' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
        raise DevelopmentError('PCB source form lacks its explicit finite host grant','CAPABILITY_DENIED')
    # The owner metadata is checked at runtime as well; a requested operation
    # alone cannot manufacture a completed form or a native capture facility.
    owner=catalog.get('VIEWER_GUI_HOST_API_v1',{})
    if str(owner.get('available',owner.get('enabled')))!='1':
        raise DevelopmentError('Current Viewer GUI host is unavailable','CORE_API_GAP')
    metadata={'pcb_source_form_kind':'eagle_pair_fixed_v1',
              'pcb_source_form_profile':'document_view_v1',
              'pcb_source_form_capability':'pcb_source_form',
              'pcb_source_form_entrypoint':'viewerGuiDesignAction',
              'pcb_source_form_implicit_import':'0',
              'pcb_source_form_scope':'import_only_completed_canonical_snapshots',
              'pcb_source_form_native_projection':'0'}
    if any(str(owner.get(key))!=value for key,value in metadata.items()):
        raise DevelopmentError('Current CORE metadata does not admit this finite PCB source form','CORE_API_GAP')
    try: advertised=tuple(tkinter.Tcl().splitlist(owner.get('pcb_source_form_commands','')))
    except (tkinter.TclError,TypeError):
        raise DevelopmentError('Current CORE PCB command metadata is malformed','CORE_API_GAP')
    if advertised!=('import_pair','refresh','inspect','cancel'):
        raise DevelopmentError('Current CORE PCB command metadata is incompatible','CORE_API_GAP')
    return dict(schema='gxtxt.viewer_pcb_source_admission.v1',profile=meta['profile'],
                module_id=design['module_id'],provider_id=design['provider_id'],
                kind='eagle_pair_fixed_v1',forms=forms,commands=commands,controls=controls,
                source_sha256=validation['source_sha256'],design_sha256=validation['design_sha256'],
                project_sha256=validation['project_sha256'],
                backend_sha256=digest(Path(__file__).read_bytes()),
                grants={'VIEWER_GUI_HOST_API_v1':['pcb_source_form']})

def capability_check(project,meta,catalog,validation,design=None):
    requested={}
    for request in meta['capabilities']:
        admission=_capability_admission(meta,request,catalog)
        if admission=='PROJECT_POLICY':
            raise DevelopmentError('Capability request shape is not authorized','PROJECT_POLICY')
        api=request['api_id'];policy=POLICY['capabilities'].get(api);available=catalog.get(api)
        if admission=='DEPRECATED_PLOT_API':
            raise DevelopmentError('DEPRECATED_PLOT_API: new Viewer plotting requires PLOT_DATASET_API_v4/widgetCreate','DEPRECATED_PLOT_API')
        if admission=='CORE_API_GAP':
            base=api.rsplit('_v',1)[0]
            closest={key:row for key,row in catalog.items() if key.rsplit('_v',1)[0]==base}
            gap={'schema':'gxtxt.core_api_gap.v1','requested':request,'closest_public_owner':available or closest,
                 'required_behavior':'Provide the requested typed, bounded public facility to this SDK',
                 'proposed_contract':'CORE maintainer reviews API/version/operation shapes; author cannot add dependencies or private fallbacks'}
            write_json(project/'derived/CORE_API_GAP.json',gap)
            raise DevelopmentError('Requested public API is missing, disabled or version mismatched','CORE_API_GAP',gap)
        if admission=='CAPABILITY_DENIED':
            raise DevelopmentError('Project request is outside the trusted profile: '+api,'CAPABILITY_DENIED')
        if api in requested: raise DevelopmentError('Duplicate capability request','PROJECT_POLICY')
        requested[api]=set(request['operations'])
    required=_sdk_required()
    for method in validation['sdk_calls']:
        api,operation=required[method]
        if operation not in requested.get(api,set()): raise DevelopmentError('SDK call lacks requested authorized capability: '+method,'CAPABILITY_DENIED')
        extra=_sdk_extra(method)
        if not extra.issubset(requested.get('NUMERIC_API_v1',set())):
            raise DevelopmentError('SDK Numeric form needs its complete bounded operation grant: '+method,'CAPABILITY_DENIED')
    admission=_transform_form_admission(meta,design,validation,requested,catalog)
    if admission:validation['transform_form_admission']=admission
    else:validation.pop('transform_form_admission',None)
    admission=_pcb_source_form_admission(meta,design,validation,requested,catalog)
    if admission:validation['pcb_source_form_admission']=admission
    else:validation.pop('pcb_source_form_admission',None)
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
    # The fixed template requests only its value/text host operations and
    # legacy scalar Numeric grant. New forms require an explicit author request.
    for request in meta['capabilities']:
        if request['api_id']=='VIEWER_GUI_HOST_API_v1': request['operations']=['value_set','text_set']
        elif request['api_id']=='NUMERIC_API_v1': request['operations']=['array_binary.add','array_unary.sqrt','array_unary.exp']
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
                if key not in {'icons', 'title', 'version', 'geometry', 'origin', 'components', 'catalog'}}
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

def validate(project):
    meta=read_project(project)
    report=validate_source((project/'handlers.cpp').read_bytes(),project/'derived/tmp')
    admitted=dictionary(core(project,'validate_design',project/'design.gxtxt-viewer','with_catalog'))
    design=dictionary(admitted['design'])
    if 'PLOT_DATASET_API_v3' in dictionary(design.get('requirements', '')):
        raise DevelopmentError('DEPRECATED_PLOT_API: Builder requirements must use PLOT_DATASET_API_v4','DEPRECATED_PLOT_API')
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Project and Builder design identities differ','PROJECT_INVALID')
    report['design_sha256']=digest((project/'design.gxtxt-viewer').read_bytes())
    report['project_sha256']=digest((project/'project.json').read_bytes())
    report['project_profile']=meta['profile']
    report['workspace_callback_contract_sha256']=workspace_callback_contract(meta,design,report['source_sha256'])
    catalog=_describe_api_catalog(admitted['catalog'])
    requested=capability_check(project,meta,catalog,report,design)
    components=[dictionary(value) for value in tkinter.Tcl().splitlist(design['components'])]
    diagrams=[component for component in components if component['type']=='native2d' and dictionary(component['properties']).get('diagram_catalog')]
    rasters=[component for component in components if component['type']=='native2d' and dictionary(component['properties']).get('source_kind')=='raster']
    numeric_forms=[component for component in components if component['type']=='section' and (dictionary(component['properties']).get('numeric_expression') or dictionary(component['properties']).get('numeric_kind'))]
    tex_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('tex_source')]
    em_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('em_parameters')]
    geometry_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('workbench_parameters')]
    for component in components:
        catalog_properties=dictionary(component['properties'])
        if component['type']=='section' and catalog_properties.get('workbench_parameters'):
            if not {'activateDocument','guiMount','guiInspect'}.issubset(requested.get('WORKBENCH_3D_API_v1',set())):
                raise DevelopmentError('Editable geometry form requires its explicit canonical Workbench3D lifecycle grants','CAPABILITY_DENIED')
        if component['type']=='section' and catalog_properties.get('em_parameters'):
            if not {'defaultModel','validate','loadModel','saveModel','listModels'}.issubset(requested.get('ELECTROMAGNETIC_SIMULATION_API_v1',set())):
                raise DevelopmentError('Declared EM form requires its explicit existing model/default/validation/discovery grants','CAPABILITY_DENIED')
        if component['type']=='section' and catalog_properties.get('catalog_owner')=='scientific_libraries':
            needed={'libraryCatalogPage','getLibraryCapabilities'}
            if catalog_properties.get('catalog_entries'):needed.add('listLibraryEntries')
            actions=dictionary(catalog_properties.get('catalog_actions',''))
            if 'register_external' in actions or 'register_remote' in actions:needed.add('getProviderCapabilities')
            if not needed.issubset(requested.get('SCIENTIFIC_LIBRARY_MANAGER_API_v1',set())):
                raise DevelopmentError('Declared Library catalog lacks its explicit discovery/entry/provider grants','CAPABILITY_DENIED')
        if component['type']=='section' and dictionary(component['properties']).get('scientific_probe_diagram'):
            for api, needed in {'SCIENTIFIC_EXECUTION_API_v1':'circuit_prepare','PLOT_DATASET_API_v4':'widgetCreate','NATIVE2D_VIEWPORT_HOST_v1':'diagram_command'}.items():
                if needed not in requested.get(api,set()):
                    raise DevelopmentError('Declared scientific probe requires its existing scoped capability: '+api+'/'+needed,'CAPABILITY_DENIED')
        if component['type']=='section' and dictionary(component['properties']).get('scientific_sweep_axes'):
            _sweep_grants(requested)
        if component['type'] in {'workspace','history'}:
            if meta['profile'] not in {'document_view_v1','scientific_view_v1'} or not (diagrams or geometry_forms or (rasters and 'raster_bind' in requested.get('VIEWER_GUI_HOST_API_v1',set())) or (numeric_forms and 'dataset_expression' in requested.get('NUMERIC_API_v1',set())) or (tex_forms and 'tex_command' in requested.get('VIEWER_GUI_HOST_API_v1',set())) or (em_forms and {'validate','loadModel','saveModel','listModels'}.issubset(requested.get('ELECTROMAGNETIC_SIMULATION_API_v1',set())))):
                raise DevelopmentError('Canonical lifecycle requires a declared canonical diagram/geometry form or an explicitly granted raster, Numeric, TeX or electromagnetic model form; legacy profiles remain read-only','CAPABILITY_DENIED')
            api,required=('SESSION_WORKSPACE_API_v1',{'create','get','update','list'}) if component['type']=='workspace' else ('SCIENTIFIC_RECIPE_API_v1',{'scientificHistoryViewerRecord','scientificHistoryViewerNavigate'})
            if not required.issubset(requested.get(api,set())):
                raise DevelopmentError('Declared lifecycle component requires explicit scoped capability: '+api,'CAPABILITY_DENIED')
    report['canonical_lifecycle_scope']='declared canonical Viewer state through existing guarded Workspace/History owners' if meta['profile'] in {'document_view_v1','scientific_view_v1'} else 'read-only profiles unchanged'
    write_json(project/'derived/validation.json',report)
    write_json(project/'derived/api-catalog.json',catalog)
    return meta,report,design,requested

def _artifact_dependency_paths():
    paths = [SDK, SDK.parent/'trusted_adapter_v1.cpp', DEVELOPMENT/'policy_v1.json',
             COMPILER, DEVELOPMENT/'toolchain/manifest.json']
    return {path.relative_to(FRAMEWORK).as_posix(): path for path in paths}

def _artifact_dependency_role(name):
    """Resolve a current role or a historical absolute framework prefix."""
    if not isinstance(name, str):
        return None
    for role in _artifact_dependency_paths():
        if name == role or (Path(name).is_absolute() and name.endswith('/'+role)):
            return role
    return None

def _artifact_dependencies_match(previous, current):
    if not isinstance(previous, dict) or not isinstance(previous.get('files'), dict):
        return False
    files = {}
    for name, checksum in previous['files'].items():
        role = _artifact_dependency_role(name)
        if role is None or role in files:
            return False
        files[role] = checksum
    return dict(previous, files=files) == current

def _artifact_dependencies():
    """Build inputs, checked without executing a compiler on a reuse path."""
    import inspect
    return dict(files={role:digest(path.read_bytes()) for role,path in _artifact_dependency_paths().items()},
                flags=list(FLAGS),recipe_sha256=digest(inspect.getsource(_compile_admitted).encode()),
                validation_owner_sha256=digest((FRAMEWORK/'core/python/gxtxt_cpp_policy.py').read_bytes()))

def _built_artifact(project, *, debug=False):
    receipt = project/('derived/debug-build.json' if debug else 'derived/build.json')
    library = project/('derived/debug-viewer.so' if debug else 'derived/viewer.so')
    if not receipt.is_file() or not library.is_file():
        return None
    result = json.loads(receipt.read_text())
    if result.get('status') != 'BUILT' or not _artifact_dependencies_match(result.get('build_dependencies'), _artifact_dependencies()):
        return None
    if digest((project/'handlers.cpp').read_bytes()) != result['validation']['source_sha256']:
        return None
    project_sha256 = digest((project/'project.json').read_bytes())
    design_sha256 = digest((project/'design.gxtxt-viewer').read_bytes())
    metadata_update = (project_sha256 != result['validation']['project_sha256'] or
                       design_sha256 != result['validation']['design_sha256'])
    if metadata_update:
        # Package metadata and presentation do not participate in code generation.
        # The existing callback contract retains ordinals, types, defaults,
        # scientific references and unknown fields; semantic changes invalidate.
        meta = read_project(project)
        design = dictionary((project/'design.gxtxt-viewer').read_text())
        if meta['module_id'] != design['module_id'] or meta['version'] != design['version']:
            return None
        contract = workspace_callback_contract(meta, design, result['validation']['source_sha256'])
        if contract != result['validation'].get('workspace_callback_contract_sha256'):
            return None
        result = dict(result, validation=dict(result['validation'], project_sha256=project_sha256,
                                             design_sha256=design_sha256),
                      metadata_only_project_update=True,
                      original_build_receipt_sha256=digest(receipt.read_bytes()))
    for name, expected in result.get('header_dependencies', {}).items():
        role = _artifact_dependency_role(name)
        path = _artifact_dependency_paths()[role] if role is not None else Path(name)
        if not path.is_file() or digest(path.read_bytes()) != expected:
            return None
    if library.is_symlink() or digest(library.read_bytes()) != result['binary_sha256']:
        return None
    return dict(result, code_generation_invoked=False, artifact_reused=True)

def build(project, debug=False):
    previous = _built_artifact(project, debug=debug)
    if previous is not None:
        return previous
    return _compile_admitted(project, *validate(project), debug=debug)

def _compile_admitted(project, meta, report, design, requested, debug=False):
    """Compile only this request's freshly validated in-memory admission.

    No project-authored report or previous binary can supply this context.
    The post-compile source/design/project checks below remain mandatory.
    """
    if report['status']!='PASS': return {'status':'REJECTED','validation':report,'code_generation_invoked':False}
    source=(project/'handlers.cpp').read_bytes()
    with tempfile.TemporaryDirectory(prefix='build-',dir=project/'derived/tmp') as temporary:
        stage=Path(temporary);author=stage/'handlers.cpp';author.write_bytes(source)
        fixed=[*FLAGS,('-O0' if debug else '-O1'),('-g3' if debug else '-g0'),'-fPIC','-fvisibility=hidden','-fno-stack-protector',
               '-ffile-prefix-map='+str(stage)+'='+str(project) if debug else '-ffile-prefix-map='+str(stage)+'=.', '-ffile-prefix-map='+str(DEVELOPMENT)+'=sdk']
        if debug:
            # Clang otherwise omits unused SDK aggregate definitions. GDB can
            # name a const Event reference but cannot inspect its real members.
            fixed.append('-fstandalone-debug')
        commands=[
            [str(COMPILER),*fixed,'-MD','-MF',str(stage/'author.d'),'-include',str(SDK),'-c',str(author),'-o',str(stage/'author.o')],
            [str(COMPILER),*fixed,'-MD','-MF',str(stage/'adapter.d'),'-I'+str(SDK.parent),'-c',str(SDK.parent/'trusted_adapter_v1.cpp'),'-o',str(stage/'adapter.o')],
            [str(COMPILER),'-shared','-pthread','-Wl,-z,defs','-Wl,--build-id=none',str(stage/'author.o'),str(stage/'adapter.o'),'-lstdc++','-lm','-o',str(stage/'viewer.so')],
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
        target=project/('derived/debug-viewer.so' if debug else 'derived/viewer.so')
        # A live Preview may still map the preceding inode. Publish a new inode
        # atomically instead of truncating the binary underneath that worker.
        with tempfile.NamedTemporaryFile(prefix='.viewer-',dir=target.parent,delete=False) as stream:
            stream.write(binary);stage_binary=Path(stream.name)
        os.replace(stage_binary,target)
        (project/'derived/trusted_adapter_v1.cpp').write_bytes((SDK.parent/'trusted_adapter_v1.cpp').read_bytes())
        result={'schema':'gxtxt.viewer_build.v1','status':'BUILT','code_generation_invoked':True,
                'validation':report,'binary_sha256':digest(binary),'adapter_sha256':digest((SDK.parent/'trusted_adapter_v1.cpp').read_bytes()),
                'compiler_version':'19.1.7','link_policy':'fixed SDK adapter; reviewed system C/C++ runtime, math and pthread; no undefined symbols; extra libraries/options require review',
                'log':'\n'.join(logs),'capabilities':meta['capabilities']}
        result['debug_symbols']=debug
        result['build_dependencies'] = _artifact_dependencies()
        headers = {}
        for dependency_file in (stage/'author.d', stage/'adapter.d'):
            import shlex
            dependencies = dependency_file.read_text().replace('\\\n', ' ').split(':', 1)[1]
            for name in shlex.split(dependencies):
                path = Path(name).resolve()
                if path == author.resolve():
                    continue
                headers[str(path)] = digest(path.read_bytes())
        result['header_dependencies'] = headers
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

def broker_message(project,message,by_index,requested,deadline,tool_catalog=None):
    operations=[];numeric=[]
    operation=message['operation'];component=by_index.get(message['component']);left=finite(message['left']);right=finite(message['right'])
    pcb_owned=set()
    for declared in by_index.values():
        p=dictionary(declared['properties'])
        if p.get('pcb_source_kind')=='eagle_pair_fixed_v1':
            pcb_owned.add(declared['id'])
            pcb_owned.update(p[key] for key in ('pcb_sources','pcb_status','pcb_inspector'))
    # Scalar Numeric messages carry dummy component0; they address no widget.
    # Preserve their existing grant/domain checks independently of form order.
    if operation not in {4,6,7} and component is not None and component['id'] in pcb_owned:
        raise DevelopmentError('PCB source controls belong to the admitted CORE form, not authored SDK operations','CAPABILITY_DENIED')
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
    elif operation==32:
        if 'workbench_command' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Geometry form commands are not requested','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        fields={'workbench_parameters','workbench_viewport','workbench_documents','workbench_objects','workbench_unit','workbench_status'}
        if component is None or component['type']!='section' or not fields.issubset(properties):
            raise DevelopmentError('Geometry commands require a complete declared canonical geometry form','RUNTIME_COMPONENT')
        action=message.get('text','')
        grants={'refresh':{'guiInspect'},'inspect':{'guiInspect'},'new':{'activateDocument','guiMount','guiInspect'},'open':{'activateDocument','guiMount','guiInspect'},
                'primitive':{'guiCommand','guiInspect'},'select':{'selectionSet','guiInspect'},'save':{'guiCommand','guiInspect'},'undo':{'guiCommand','guiInspect'},'redo':{'guiCommand','guiInspect'},'close':{'guiCommand','guiInspect'}}
        for form_action in (
                'import_dataset_form','combine_form','extrusion_targets_form','mesh_pair_form',
                'details_form','measurement_form','constraint_form','measurements_manager',
                'constraints_manager','organization_manager','comparison_manager','texture_form',
                'texture_clear','export_form','recipe_manager','extensions_manager','documents_manager',
                'translate_form','rotate_form','scale_form','reset_transform_form','tessellate_form',
                'mesh_clean_form','mesh_weld_form','mesh_orient_form','brep_heal_form',
                'mesh_seam_form','mesh_lod_form','mesh_boundaries_form','mesh_intersections_form',
                'align_three_points_form','clip_form','clip_cap_form','section_profile_form',
                'duplicate_object','group_create','group_duplicate','group_ungroup','group_translate_form',
                'group_rotate_form','group_scale_form','planar_section','planar_projection',
                'preview_accept','preview_cancel','profile_source_form','extrusion_form',
                'working_unit_form','working_plane_form','publish_dataset_form'):
            grants[form_action]={'guiCommand','guiInspect'}
        if action not in grants:
            raise DevelopmentError('Unsupported finite canonical geometry command','RUNTIME_VALUE')
        if not grants[action].issubset(requested.get('WORKBENCH_3D_API_v1',set())):
            raise DevelopmentError('Geometry action lacks its exact public Workbench3D grants','CAPABILITY_DENIED')
        operations.append({'operation':'workbench_command','component':component['id'],'value':action})
    elif operation==31:
        if 'em_command' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('EM form commands are not requested','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='section' or not {'em_parameters','em_models','em_status','em_log','em_output_id','em_dataset'}.issubset(properties):
            raise DevelopmentError('EM commands require a complete declared electromagnetic model form','RUNTIME_COMPONENT')
        action=message.get('text','')
        action_grants={'refresh':{'listModels'},'new_electric':{'defaultModel'},'new_magnetic':{'defaultModel'},
                       'validate':{'validate'},'open':{'loadModel'},'save':{'saveModel'},'duplicate':{'saveModel','loadModel'},
                       'run':{'saveModel','runAsync','jobStatus'},'status':{'jobStatus'},'cancel':{'jobStatus','cancel'},
                       'jobs':{'loadModel','jobStatus'},'reconnect':{'loadModel','jobStatus'},'log':{'jobStatus','jobLog'},'results':{'jobStatus','resultDescribe','resultPreview'},
                       'workspaces':{'loadModel','saveModel'},'rename':{'loadModel'},
                       'publish':{'jobStatus','publish'},'field':{'fieldDescribe'},'field_3d':{'fieldDescribe'},
                       'profile':{'fieldDescribe'},'publish_charts':{'fieldDescribe'},'export_field':{'fieldDescribe'},'runtime':set()}
        if action not in action_grants:
            raise DevelopmentError('Unsupported finite electromagnetic model command','RUNTIME_VALUE')
        if not action_grants[action].issubset(requested.get('ELECTROMAGNETIC_SIMULATION_API_v1',set())):
            raise DevelopmentError('EM action lacks its exact public service grants','CAPABILITY_DENIED')
        if action in {'field','field_3d'} and 'widgetCreate' not in requested.get('PLOT_DATASET_API_v4',set()):
            raise DevelopmentError('Exact field presentation requires public Plot v4','CAPABILITY_DENIED')
        if action=='field_3d' and ('cell_field_bind' not in requested.get('NATIVE_3D_GUI_HOST_API_v2',set()) or 'em_field_native3d' not in properties):
            raise DevelopmentError('Planar 3D field requires its declared Native3D component and exact cell_field_bind grant','CAPABILITY_DENIED')
        plot_grants={'profile':{'widgetCreate','cellFieldProfileSpec'},'publish_charts':{'cellFieldProfileSpec','upsertPlotFromSpec','render'},'export_field':{'widgetExport'}}
        if not plot_grants.get(action,set()).issubset(requested.get('PLOT_DATASET_API_v4',set())):
            raise DevelopmentError('EM presentation action lacks its exact public Plot v4 grants','CAPABILITY_DENIED')
        if action=='profile' and 'em_profile_plot' not in properties:
            raise DevelopmentError('Actual sample profile requires its declared Plot component','RUNTIME_COMPONENT')
        if action=='export_field' and ('em_field_plot' not in properties or 'publish_bundle' not in requested.get('FILE_PUBLICATION_API_v1',set())):
            raise DevelopmentError('Native field export requires its declared field Plot and File Publication grant','CAPABILITY_DENIED')
        if action=='runtime' and 'open_page' not in requested.get('CONFIGURATION_API_v1',set()):
            raise DevelopmentError('Runtime navigation requires the public Configuration open_page grant','CAPABILITY_DENIED')
        if action in {'duplicate','workspaces'} and not {'export','import'}.issubset(requested.get('SESSION_WORKSPACE_API_v1',set())):
            raise DevelopmentError('Model duplication requires the existing resource-preserving Workspace export/import grants','CAPABILITY_DENIED')
        if action=='workspaces' and not {'create','get','update','list'}.issubset(requested.get('SESSION_WORKSPACE_API_v1',set())):
            raise DevelopmentError('Model Workspace controls require the existing complete Workspace grants','CAPABILITY_DENIED')
        if action=='rename' and 'update' not in requested.get('SESSION_WORKSPACE_API_v1',set()):
            raise DevelopmentError('Model renaming requires the existing Workspace update grant','CAPABILITY_DENIED')
        operations.append({'operation':'em_command','component':component['id'],'value':action})
    elif operation==30:
        if 'tex_command' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('TeX form commands are not requested','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        required_form={'tex_source','tex_pdf','tex_projects','tex_assets','tex_diagnostics','tex_log','tex_status','tex_info','tex_source_status','tex_pdf_status'}
        if component is None or component['type']!='section' or not required_form.issubset(properties):
            raise DevelopmentError('TeX commands require a complete declared article form','RUNTIME_COMPONENT')
        action=message.get('text','')
        if action not in {'new','open','save','build','rebuild','cancel','preview','diagnostic_open','import_assets','remove_asset','export_tex','export_pdf','export_assets','refresh','import_source'}:
            raise DevelopmentError('Unsupported finite TeX form command','RUNTIME_VALUE')
        operations.append({'operation':'tex_command','component':component['id'],'value':action})
    elif operation in {27,28,29}:
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='section' or properties.get('catalog_owner')!='scientific_libraries':
            raise DevelopmentError('Catalog operations require a declared Scientific Libraries section','RUNTIME_COMPONENT')
        grants=requested.get('SCIENTIFIC_LIBRARY_MANAGER_API_v1',set())
        needed={27:'libraryCatalogPage',28:'getLibraryCapabilities'}.get(operation,'getLibraryCapabilities')
        action=''
        if operation==29:
            action=message.get('text','')
            action_grants={'open':'openLibraryViewer','entry_open':'openLibraryViewer','verify':'verifyLibrary','install':'installLibrary','update':'updateLibrary','remove':'removeLibrary','register_external':'registerLibrary','register_remote':'registerLibrary','unregister':'unregisterLibrary','extra_action':'invokeLibraryAction'}
            if action not in action_grants or action_grants[action] not in grants:
                raise DevelopmentError('Catalog action lacks its exact public manager grant','CAPABILITY_DENIED')
        if needed not in grants:raise DevelopmentError('Catalog discovery capability is not requested','CAPABILITY_DENIED')
        operations.append({'operation':{27:'catalog_refresh',28:'catalog_inspect',29:'catalog_action'}[operation],'component':component['id'],'value':action})
    elif operation in {33,34,35}:
        method={33:'raster_bind',34:'raster_tool',35:'raster_command'}[operation]
        if method not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Raster operation lacks its explicit public GUI Host grant','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='native2d' or properties.get('source_kind')!='raster':
            raise DevelopmentError('Raster operation requires a declared Native2D source_kind raster component','RUNTIME_COMPONENT')
        if operation==33:
            other=by_index.get(int(left)) if left==int(left) else None
            if other is None or other['type']!='dataset_selector' or dictionary(other['properties']).get('content_kind')!='raster':
                raise DevelopmentError('Raster binding requires a declared canonical raster Dataset selector','RUNTIME_COMPONENT')
            value=other['id']
        else:
            value=message.get('text','')
            admitted={34:{'select','rectangle','polygon','annotation','move','rotate','pivot','pan'},35:{'fit','cancel','finish','delete_roi','delete_annotation'}}[operation]
            anchored = re.fullmatch(r'(panel_open|panel_close|editor_apply|editor_cancel):([a-z][a-z0-9_]*)', value) if operation==35 else None
            if anchored:
                section = next((c for c in by_index.values() if c['id']==anchored[2]), None)
                panel = dictionary(section['properties']) if section is not None else {}
                anchor = dictionary(panel.get('viewport_anchor',''))
                if section is None or section['type']!='section' or anchor.get('viewport')!=component['id']:
                    raise DevelopmentError('Anchored command requires its own declared raster section','RUNTIME_COMPONENT')
                if anchored[1]=='editor_apply' and (anchor.get('target')!='annotation' or not panel.get('annotation_fields')):
                    raise DevelopmentError('Apply requires declared native annotation property fields','RUNTIME_COMPONENT')
            elif value not in admitted:
                raise DevelopmentError('Raster intent is outside the finite public controller contract','RUNTIME_VALUE')
        operations.append({'operation':method,'component':component['id'],'value':value})
    elif operation==26:
        if 'document_bind' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Read-only document binding is not requested','CAPABILITY_DENIED')
        other=by_index.get(int(left)) if left==int(left) else None
        if component is None or component['type']!='document' or other is None or other['type']!='dataset_selector':
            raise DevelopmentError('Document binding needs declared document and Dataset selector','RUNTIME_COMPONENT')
        kind=dictionary(component['properties']).get('kind')
        if kind not in {'html','pdf','code','table'} or dictionary(other['properties']).get('content_kind')!=kind:
            raise DevelopmentError('Document selector content_kind must match document kind','RUNTIME_COMPONENT')
        operations.append({'operation':'document_bind','component':component['id'],'value':other['id']})
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
            if tool_catalog is not None:
                if message['text'] not in tool_catalog.get(catalog,[]):
                    raise DevelopmentError('Tool is not exposed by the declared public diagram catalog','CAPABILITY_DENIED')
            else:
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

def run(project,event=None,state=None, *, admission=None, work=None):
    if admission is None:
        built=build(project)
        if built['status']!='BUILT': return built
        meta,validation,design,requested=_admit_compiled(project, built, project)
        library=project/'derived/viewer.so'
    else:
        meta,validation,design,requested,built,library=admission
    source_project=project
    project=work or project
    if any(digest((source_project/name).read_bytes())!=validation[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
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
        reply({'library':str(library),'binary_sha256':built['binary_sha256'],'native_output_path':str(project/'derived/native-output.log'),'event':event,'state':state})
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
                response,ui_receipts,numeric_receipts=broker_message(project,message,by_index,requested,deadline,design.get('_runtime_diagram_tools'))
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
                        'execution':'compiled restricted C++ in isolated native worker; typed public CORE broker'}
        except Exception as error:
            result={'status':'TIMED_OUT' if time.monotonic()>=deadline else 'FAILED','error':str(error),'code':getattr(error,'code','RUNTIME_ERROR'),'operations':[],'state':state}
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
            process.wait(timeout=5)
            ACTIVE_PROCESSES.discard(process.pid)
            process.stdin.close();process.stdout.close()
        if result['status']=='COMPLETED' and any(digest((source_project/name).read_bytes())!=validation[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
            result={'status':'SOURCE_CHANGED','operations':[],'state':state,'error':'Project changed during native execution; reopen the Preview'}
        errors.seek(0);result['stderr']=errors.read(65536).decode(errors='replace')
        write_json(project/'derived/run.json',result)
        return result

def _runtime_contract():
    return {str(path):digest(path.read_bytes()) for path in
            (SDK,SDK.parent/'trusted_adapter_v1.cpp',DEVELOPMENT/'policy_v1.json')}

def _installed_sdk_compatible(root, built):
    """SDK v1 permits additive methods; compare its real ABI, not header age."""
    report=built['validation']
    for name,expected in [('gxtxt_viewer_sdk_v1.hpp',report['sdk_sha256']),
                          ('trusted_adapter_v1.cpp',built['adapter_sha256']),
                          ('SDK_CONTRACT.json',report['policy_sha256'])]:
        path=root/'native'/name
        if not path.is_file() or path.is_symlink() or digest(path.read_bytes())!=expected:
            raise DevelopmentError('Distributed SDK/build receipt mismatch: '+name,'BINARY_INCOMPATIBLE')
    contract=json.loads((root/'native/SDK_CONTRACT.json').read_text())
    if contract.get('sdk_version')!=POLICY['sdk_version']:
        raise DevelopmentError('Distributed Viewer uses another native SDK ABI version','BINARY_INCOMPATIBLE')
    old=(root/'native/gxtxt_viewer_sdk_v1.hpp').read_text();current=SDK.read_text()
    normalize=lambda value:re.sub(r'\s+','',value)
    for pattern in [r'enum class EventKind\s*\{[^}]+\}',r'struct Event\s*\{[^}]+\}',
                    r'struct State\s*\{[^}]+\}',r'private:\s*(.*?)friend struct HostAccess;']:
        left=re.search(pattern,old,re.S);right=re.search(pattern,current,re.S)
        if not left or not right or normalize(left.group())!=normalize(right.group()):
            raise DevelopmentError('Distributed Viewer Event/State/Host ABI is incompatible','BINARY_INCOMPATIBLE')
    old_adapter=(root/'native/trusted_adapter_v1.cpp').read_text()
    current_adapter=(SDK.parent/'trusted_adapter_v1.cpp').read_text()
    pattern=r'(?:void|double) Host::([a-z_]+)\([^{}]*\) const\s*\{[^{}]*\}'
    current_methods={match.group(1):normalize(match.group()) for match in re.finditer(pattern,current_adapter)}
    for match in re.finditer(pattern,old_adapter):
        if current_methods.get(match.group(1))!=normalize(match.group()):
            raise DevelopmentError('Distributed SDK operation changed incompatibly: '+match.group(1),'BINARY_INCOMPATIBLE')
    entry=r'extern "C".*?int gxtxt_viewer_event_v1\(.*?\n\}'
    left=re.search(entry,old_adapter,re.S);right=re.search(entry,current_adapter,re.S)
    if not left or not right or normalize(left.group())!=normalize(right.group()):
        raise DevelopmentError('Distributed Viewer C entry ABI is incompatible','BINARY_INCOMPATIBLE')

def _admit_compiled(project, built, work, *, installed=False):
    """Compatibility and public service admission; never C++ source validation."""
    meta=read_project(project, installed=installed)
    report=dict(built['validation'])
    if built.get('status')!='BUILT' or report.get('status')!='PASS':
        raise DevelopmentError('Viewer has no successful compiled build receipt; build it in Development Workspace', 'BINARY_MISSING')
    for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]:
        if digest((project/name).read_bytes())!=report[key]:
            raise DevelopmentError('Viewer source/interface differs from its compiled artifact; install a matching build', 'BINARY_SOURCE_MISMATCH')
    if installed:
        _installed_sdk_compatible(project.parent,built)
    else:
        for path,key in [(SDK,'sdk_sha256'),(DEVELOPMENT/'policy_v1.json','policy_sha256')]:
            if digest(path.read_bytes())!=report[key]:
                raise DevelopmentError('Development artifact dependencies changed; build the current version','BINARY_INCOMPATIBLE')
        if digest((SDK.parent/'trusted_adapter_v1.cpp').read_bytes())!=built['adapter_sha256']:
            raise DevelopmentError('Development adapter changed; build the current version','BINARY_INCOMPATIBLE')
    admitted=dictionary(core(work,'runtime_design',project/'design.gxtxt-viewer'))
    design=dictionary(admitted['design'])
    design['_runtime_diagram_tools']={key:list(tkinter.Tcl().splitlist(value)) for key,value in dictionary(admitted['diagram_tools']).items()}
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Compiled Viewer interface and module identity differ','BINARY_INCOMPATIBLE')
    requested=capability_check(work,meta,_describe_api_catalog(admitted['catalog']),report,design)
    return meta,report,design,requested

def installed_admission(root, work):
    """Use the distributed binary in place. No source copy, grant or compiler."""
    root=root.resolve()
    for name in ('native/viewer.so','review/build.json','source/project.json','source/handlers.cpp','source/design.gxtxt-viewer','gui/design.tcldict'):
        path=root/name
        if not path.is_file() or path.is_symlink() or path.stat().st_size>16777216:
            raise DevelopmentError('Installed Viewer is missing its ordinary bounded '+name+'; reinstall its precompiled package','BINARY_MISSING')
    library=root/'native/viewer.so'
    built=json.loads((root/'review/build.json').read_text())
    binary=library.read_bytes()
    if binary[:4]!=b'\x7fELF' or digest(binary)!=built.get('binary_sha256'):
        raise DevelopmentError('Installed Viewer binary does not match its build receipt; reinstall the package','BINARY_INCOMPATIBLE')
    if (root/'gui/design.tcldict').read_bytes()!=(root/'source/design.gxtxt-viewer').read_bytes():
        raise DevelopmentError('Installed Viewer interface differs from its compiled source interface','BINARY_SOURCE_MISMATCH')
    work.mkdir(parents=True,exist_ok=True)
    (work/'derived/tmp').mkdir(parents=True,exist_ok=True)
    admitted=_admit_compiled(root/'source',built,work,installed=True)
    # Loading may run ordinary C++ initializers. Probe only after admission and
    # under the same bounded auxiliary process/descendant owner as other native
    # requests; never load an author library in the installer or Tk process.
    from gxtxt_job_supervisor import auxiliary_request_run
    probe=auxiliary_request_run([sys.executable,'-I','-B',str(FRAMEWORK/'core/python/gxtxt_viewer_native_worker.py'),'--probe',str(library)],timeout_seconds=5,max_bytes=8192)
    if probe['returncode']:
        raise DevelopmentError('Installed Viewer binary/runtime libraries cannot load: '+probe['output']+'; install a compatible precompiled package','BINARY_INCOMPATIBLE')
    return (*admitted,built,library)

def installed_inspect(root, work):
    meta,report,design,requested,built,library=installed_admission(root,work)
    record=dict(schema='gxtxt.compiled_viewer_runtime.v1', root=str(root.resolve()),
                meta=meta, validation=report, design=design,
                requested={key:sorted(value) for key,value in requested.items()},
                build=built, library=str(library))
    record['source_directory']=str(root.resolve()/'source')
    record['kind']='installed'
    record['runtime_contract']=_runtime_contract()
    write_json(work/'derived/compiled-runtime.json',record)
    return dict(report,status='PASS',binary_sha256=built['binary_sha256'],
                library=str(library),runtime_compilation=False)

def installed_run(root, work, event, state):
    record=json.loads((work/'derived/compiled-runtime.json').read_text())
    if record.get('schema')!='gxtxt.compiled_viewer_runtime.v1' or record['root']!=str(root.resolve()):
        raise DevelopmentError('Installed runtime lifetime does not match this package','RUNTIME_LIFETIME')
    library=root/'native/viewer.so';built=record['build'];report=record['validation']
    if not library.is_file() or library.is_symlink() or digest(library.read_bytes())!=built['binary_sha256']:
        raise DevelopmentError('Installed compiled binary changed; close and reinstall the matching package','BINARY_INCOMPATIBLE')
    if _runtime_contract()!=record['runtime_contract']:
        raise DevelopmentError('Runtime SDK/adapter contract changed; install a compatible precompiled Viewer','BINARY_INCOMPATIBLE')
    admission=(record['meta'],report,record['design'],
               {key:set(value) for key,value in record['requested'].items()},built,library)
    result=run(root/'source',event,state,admission=admission,work=work)
    result.update(runtime_compilation=False,distributed_library=str(library))
    return result

def prepare_preview(project):
    built=build(project)
    if built['status']!='BUILT':return built
    meta,report,design,requested=_admit_compiled(project,built,project)
    write_json(project/'derived/compiled-runtime.json',dict(
        schema='gxtxt.compiled_viewer_runtime.v1',root=str(project.resolve()),kind='development',
        source_directory=str(project.resolve()),library=str(project/'derived/viewer.so'),
        meta=meta,validation=report,design=design,requested={key:sorted(value) for key,value in requested.items()},build=built,runtime_contract=_runtime_contract()))
    return dict(report,status='PASS',binary_sha256=built['binary_sha256'],artifact_reused=built.get('artifact_reused',False))

def compiled_serve(root, work):
    """One managed lifetime, one distributed library load, short local RPCs.

    Scientific SDK operations remain typed plans applied by their existing GUI
    owners. No native author code is loaded in Tk and no compiler is reachable.
    """
    import base64
    import ctypes
    from gxtxt_viewer_native_worker import main as native_event, route_native_output, apply_runtime_limits
    record=json.loads((work/'derived/compiled-runtime.json').read_text())
    if record.get('schema')!='gxtxt.compiled_viewer_runtime.v1' or record['root']!=str(root.resolve()):
        raise DevelopmentError('Compiled runtime allocation belongs to another package','RUNTIME_LIFETIME')
    if record.get('kind')=='development':enforce_project_write(root)
    elif record.get('kind')!='installed':raise DevelopmentError('Unknown compiled runtime kind','RUNTIME_LIFETIME')
    library=Path(record['library']);source_directory=Path(record['source_directory'])
    expected_library=root/('native/viewer.so' if record['kind']=='installed' else 'derived/viewer.so')
    if library!=expected_library or source_directory!=(root/'source' if record['kind']=='installed' else root):
        raise DevelopmentError('Compiled artifact location differs from its declared lifetime','RUNTIME_LIFETIME')
    built=record['build'];report=record['validation']
    design=record['design'];requested={key:set(value) for key,value in record['requested'].items()}
    components={index+1:dictionary(item) for index,item in enumerate(tkinter.Tcl().splitlist(design['components']))}
    def unchanged():
        if digest(library.read_bytes())!=built['binary_sha256']:
            raise DevelopmentError('Distributed Viewer binary changed; close and reinstall its matching package','BINARY_INCOMPATIBLE')
        for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]:
            if digest((source_directory/name).read_bytes())!=report[key]:
                raise DevelopmentError('Installed Viewer source/interface changed during this lifetime','SOURCE_CHANGED')
        if _runtime_contract()!=record['runtime_contract']:
            raise DevelopmentError('Viewer SDK/adapter compatibility changed during this lifetime','BINARY_INCOMPATIBLE')
    native_log=work/'derived/native-output.log'
    protocol=route_native_output(native_log)
    def send(value):
        print(base64.b64encode(tcl_result(value).encode('utf-8')).decode('ascii'),file=protocol,flush=True)
    unchanged()
    apply_runtime_limits()
    loaded=ctypes.CDLL(str(library))
    send(dict(ok=True,result=dict(status='READY',library=str(library),binary_sha256=built['binary_sha256'],pid=os.getpid())))
    while True:
        line=sys.stdin.readline(65537)
        if not line:break
        try:
            if len(line.encode('utf-8'))>65536:raise DevelopmentError('Compiled event exceeds bound','RUNTIME_EVENT')
            payload=json.loads(line);event=payload['event'];state=payload['state']
            if set(payload)!={'event','state'} or set(event)!={'kind','component','value'} or type(event['kind']) is not int or event['kind'] not in range(6) or type(event['component']) is not int or event['component'] not in {0,*components}:
                raise DevelopmentError('Invalid typed compiled event','RUNTIME_EVENT')
            finite(event['value'])
            if set(state)!={'values','counter'} or len(state['values'])!=16 or type(state['counter']) is not int or not 0<=state['counter']<2**32:
                raise DevelopmentError('Invalid compiled state','RUNTIME_STATE')
            for value in state['values']:finite(value)
            unchanged();operations=[];numeric=[];deadline=time.monotonic()+POLICY['process_timeout_seconds']
            def broker(message):
                response,ui,math_receipts=broker_message(work,message,components,requested,deadline,design.get('_runtime_diagram_tools'))
                operations.extend(ui);numeric.extend(math_receipts)
                return response
            outcome=native_event(dict(library=str(library),binary_sha256=built['binary_sha256'],event=event,state=state),broker,loaded)
            unchanged()
            result=dict(status='COMPLETED' if outcome['ok'] else 'FAILED',operations=operations if outcome['ok'] else [],
                        state=outcome['state'] if outcome['ok'] else state,errors=outcome['errors'],numeric_receipts=numeric,
                        source_sha256=report['source_sha256'],design_sha256=report['design_sha256'],project_sha256=report['project_sha256'],
                        binary_sha256=built['binary_sha256'],distributed_library=str(library),runtime_compilation=False,
                        native_output_path=str(native_log),native_output_bytes=native_log.stat().st_size,
                        event=event,execution='persistent compiled C++ worker; existing typed public CORE broker')
            write_json(work/'derived/run.json',result)
            send(dict(ok=True,result=result))
        except Exception as error:
            send(dict(ok=False,error=str(error),code=getattr(error,'code','RUNTIME_ERROR')))
    return 0

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

def _manifest_value(value):
    """Write the manifest's existing iniEscape convention, including Tcl lists."""
    return str(value).replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r')


def _installed_public_contract(namespace):
    """Inert syntax for the exact facade emitted by this export owner."""
    context = ('Trusted generated host callback for this exact installed provider. '
               'Existing public CORE owners retain Session/Workspace lifetime, '
               'packaged-binary compatibility and admission checks. This declaration '
               'does not activate the provider or grant Script/SDK operations.')
    signatures = {
        'handlers': ({}, 'HandlerPrefixDictionary',
                     'Declared handler IDs mapped to trusted generated command/enabled prefixes.'),
        'dispatch': ({'operation': ('LifecycleOperation', 'Resolved Viewer lifecycle operation.'),
                      'scene': ('ViewerSceneDictionary', 'Host-resolved scene; its open_context is forwarded.')},
                     'TkWindowPath', 'Existing installed-open result for the provider and scene context.'),
        'workspaceOpen': ({'context': ('ViewerOpenContextDictionary',
                                      'Existing provider-qualified saved Workspace open context.')},
                          'TkWindowPath', 'Existing installed-open result with canonical Workspace association.'),
        'texOpen': ({'document': ('TeXDocumentID', 'Existing canonical TeX document identity.')},
                    'TkWindowPath', 'Existing installed-open result with tex_document_id context.'),
    }
    operations = {}
    for name, (parameters, result_type, description) in signatures.items():
        operations[name] = dict(command=namespace+'::'+name,
                                arguments=' '.join(parameters),
                                parameters={key: dict(type=kind, description=about)
                                            for key, (kind, about) in parameters.items()},
                                result=dict(type=result_type, description=description),
                                context=context)
    return tcl_result(dict(schema='gxtxt.public_api_documentation.v1',
                           purpose='Exact generated installed Viewer facade syntax; compiled runtime uses the distributed native binary.',
                           context=context, operations=operations))


def export_candidate(project):
    """Export the current source-bound artifact; build only changed inputs."""
    built=build(project)
    if built['status']!='BUILT': return built
    meta,validation,design,requested=_admit_compiled(project,built,project)
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
proc {namespace}::texOpen {{document}} {{return [::GX::viewerDevelopmentInstalledOpen {module} {provider} [set {namespace}::root] [dict create tex_document_id $document]]}}
::GX::viewerBackendRegister {backend} {namespace}::dispatch
'''
    def section(name,fields):
        return '['+name+']\n'+''.join(str(k)+'='+_manifest_value(v)+'\n' for k,v in fields.items())+'\n'
    descriptor='; SPDX-License-Identifier: GPL-3.0-or-later\n'
    descriptor+=section('meta',{'api_version':1,'id':module,'kind':'viewer','group':'Viewers','name':design['title'],
                       'version':version,'license':'GPL-3.0-or-later','selectable':0,'default_enabled':1,'core':0,'runner':'service','order':900,
                       'depends':'math.numeric' if 'NUMERIC_API_v1' in requested else '','description':'Restricted C++ Viewer using approved public CORE facilities.'})
    descriptor+=section('viewers',{'api_version':1,'ids':provider})
    catalog=dictionary(design.get('catalog',''))
    descriptor+=section('viewer.'+provider,{'name':design['title'],'backend':backend,'activation_api':'RESTRICTED_VIEWER_CLIENT_API_v1',
                         'gui_design':'gui/design.tcldict','gui_handler_command':namespace+'::handlers',
                         'capabilities':'declarative_gui;restricted_cpp;public_core_broker','semantic_group':catalog.get('semantic_group','development'),
                         'group_title':catalog.get('group_title','Interface Tools'),'short_title':catalog.get('short_title',design['title']),
                         'icon':('resources/icons/'+catalog['icon']+'.png') if catalog.get('icon') else ''})
    # Rebuilding the existing HTML identity must preserve its public rendering
    # facade. This trusted adapter still delegates to the CORE document owner;
    # it grants no extra C++ capability and accepts no authored Tcl.
    html_compatibility=module=='viewer.html' and provider=='html'
    descriptor+=section('public_apis',{'ids':'RESTRICTED_VIEWER_CLIENT_API_v1'+(';HTML_VIEWER_API_v1' if html_compatibility else '')})
    descriptor+=section('public_api.RESTRICTED_VIEWER_CLIENT_API_v1',{'api_version':1,'name':'Restricted Viewer client',
                         'entrypoint':'api/viewer.tcl','namespace':namespace,'capabilities':'viewer_backend;viewer_gui_manifest',
                         'public_contract':_installed_public_contract(namespace)})
    if html_compatibility:
        descriptor+=section('public_api.HTML_VIEWER_API_v1',{'api_version':1,'name':'Native HTML presentation','entrypoint':'api/html.tcl','namespace':'::GX::HTMLViewer','capabilities':'render;headless_model;viewer_backend','documentation':'docs/api/HTML_VIEWER_API_v1.md'})
    workspace_contributions=[]
    if any(dictionary(component)['type']=='workspace' for component in tkinter.Tcl().splitlist(design['components'])):
        workspace_id=module.replace('.','_').replace('-','_')+'_'+provider+'_interface_state'
        workspace_contributions.append((workspace_id,{'entrypoint':'api/viewer.tcl','viewer_provider':provider,
            'type':'Restricted C++ Viewer state','schema':'gxtxt.viewer_interface_state.v1','version':1,'accepted_versions':1,
            'validate':'::GX::viewerGuiDesignStateValidate','open':namespace+'::workspaceOpen'}))
    for raw_component in tkinter.Tcl().splitlist(design['components']):
        component=dictionary(raw_component)
        if component['type']=='section' and dictionary(component['properties']).get('tex_source'):
            article_provider=(module+'_'+provider+'_'+component['id']+'_tex_article').replace('.','_').replace('-','_')
            workspace_contributions.append((article_provider,{'entrypoint':'api/viewer.tcl','viewer_provider':provider,
                'type':'LaTeX article','schema':'gxtxt.tex_project.v1','version':1,
                'validate':'::GX::_interactiveDocumentTeXValidate','open':namespace+'::texOpen'}))
    if workspace_contributions:
        descriptor+=section('workspaces',{'api_version':1,'ids':';'.join(key for key,_ in workspace_contributions)})
        for key,contribution in workspace_contributions:descriptor+=section('workspace.'+key,contribution)
    descriptor+=section('documentation',{'api_version':1,'guide':'MANUAL.md',
                         'api_refs':';'.join(sorted({'VIEWER_DEVELOPMENT_API_v1'}|set(requested)|set(dictionary(design['requirements']))))})
    dev108_properties={'component_visibility','visibility_commands','scientific_provider','numeric_dataset','plot_dataset'}
    declared_dev108=any(dev108_properties.intersection(dictionary(dictionary(c)['properties'])) for c in tkinter.Tcl().splitlist(design['components']))
    package_meta=section('package',{'api_version':1,'id':module,'name':design['title'],'version':version,
                                 'type':'module','framework_min':(FRAMEWORK/'VERSION.txt').read_text().strip(),'framework_max':''})
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
owned by Viewer Interface Builder. Installed runtime verifies compatibility and
executes the distributed native/viewer.so directly; no development compiler is
required. Build a changed source version in the Development Workspace.

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
    if built.get('metadata_only_project_update'):
        # Preserve the original genuine compilation receipt alongside the current
        # metadata admission. Neither Test nor Export recompiles the same binary.
        payload['review/original-build.json'] = payload['review/build.json']
        payload['review/build.json'] = json.dumps(built, sort_keys=True, indent=2).encode()+b'\n'
        payload['review/validation.json'] = json.dumps(validation, sort_keys=True, indent=2).encode()+b'\n'
    if html_compatibility:
        payload['api/html.tcl']=b'# SPDX-License-Identifier: GPL-3.0-or-later\nsource [file join $::GX::scriptDir core tcl html_viewer_api_v1.tcl]\n'
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
        'CPP_SUPPORT_CATALOG':('VIEWER_DEVELOPMENT_API_v1','CPP_SUPPORT_CATALOG.md'),
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
    if sys.argv[1:2] == ['--api-browser-tcl']:
        metadata_parser=argparse.ArgumentParser(description='Read-only installed API and saved project reference')
        metadata_parser.add_argument('--project',type=Path)
        metadata_arguments=metadata_parser.parse_args(sys.argv[2:])
        # Existing discovery/SDK decoration owners, without a project or fake
        # Session. Operations are described, never executed by this request.
        with tempfile.TemporaryDirectory(prefix='gxtxt-api-metadata-') as temporary:
            result=subprocess.run(['/usr/bin/tclsh',str(FRAMEWORK/'core/tcl/viewer_development_request.tcl'),str(FRAMEWORK),'api_catalog'],capture_output=True,timeout=15,env=environment(Path(temporary)))
            if result.returncode or len(result.stdout)>4194304:
                raise DevelopmentError('Installed API declarations could not be discovered','API_CATALOG')
            envelope=dictionary(result.stdout.decode())
            if envelope.get('ok')!='1':raise DevelopmentError(envelope.get('error','API discovery failed'),'API_CATALOG')
            catalog=_describe_api_catalog(envelope['result'])
        from gxtxt_script_bridge_server import discover_registrations
        registrations,_=discover_registrations()
        for api,descriptor in registrations.items():
            if api not in catalog:
                catalog[api]={'api_id':api,'version':descriptor['api_version'],'provider':descriptor['provider_id'],'providers':[],'sdk_exposed':False,'allowed_operations':[],'documentation':descriptor['documentation_ref']}
            catalog[api]['script_descriptor']=descriptor
        project=metadata_arguments.project.absolute() if metadata_arguments.project is not None else None
        context=_browser_cpp_catalog(catalog,project)
        print(tcl_result({'ok':True,'result':{'schema':'gxtxt.api_browser_catalog.v1','apis':catalog,'script_languages':['Python','Octave'],'execution_context':'inactive_metadata_only','cpp_context':context,'operation_invocations':0}}),flush=True)
        return 0
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=['init','validate','build','prepare','run','test','export','api','inspect','manual_asset','save','check_source','grant','facility_request','builder','debug','debug_control','debug_status','gui_test','workspace_upgrade_review','runtime_inspect','runtime_run','runtime_serve','maintenance_init','maintenance_inspect','maintenance_save','maintenance_validate','maintenance_export'])
    parser.add_argument('project',type=Path)
    parser.add_argument('--module-id',default='viewer.restricted_example')
    parser.add_argument('--event',type=json.loads)
    parser.add_argument('--state',type=json.loads)
    parser.add_argument('--runtime-work',type=Path,help='CORE-owned installed runtime allocation; never a development project')
    parser.add_argument('--breakpoints',type=json.loads,default=[])
    parser.add_argument('--file',choices=['handlers.cpp','project.json','MANUAL.md'],default='handlers.cpp')
    parser.add_argument('--target',choices=['handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer','sdk_v1'],default='handlers.cpp',help='Fixed read-only Workspace source browser target for inspect')
    parser.add_argument('--document',help='Read-only installed public API manual identity for api; paths are refused')
    parser.add_argument('--debug-token',help='Opaque request identity for source-bound debugger status/control; no command text')
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
        if arguments.operation in {'runtime_inspect','runtime_run','runtime_serve'}:
            if arguments.runtime_work is None or arguments.runtime_work.is_symlink():
                raise DevelopmentError('Installed execution requires its CORE runtime allocation','RUNTIME_LIFETIME')
            work=arguments.runtime_work.absolute()
            if arguments.operation=='runtime_serve':return compiled_serve(project,work)
            result=(installed_inspect(project,work) if arguments.operation=='runtime_inspect'
                    else installed_run(project,work,arguments.event,arguments.state))
        elif arguments.operation.startswith('maintenance_'):
            from gxtxt_viewer_maintenance import dispatch
            raw=sys.stdin.buffer.read(1048577)
            if len(raw)>1048576:raise DevelopmentError('Maintenance request exceeds 1 MiB escaped UTF-8 envelope','REQUEST_LIMIT')
            result=dispatch(arguments.operation,project,json.loads(raw))
        elif arguments.operation=='init': result=initialize(project,arguments.module_id)
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
            elif arguments.operation=='prepare': result=prepare_preview(project)
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
                if not isinstance(control,dict) or set(control)-{'operation','source_sha256','frame','node_id','inspection_id','offset'} or control.get('operation') not in {'continue','into','over','out','pause','stop','frame','children'}:
                    raise DevelopmentError('Only enumerated native debugger controls are admitted','DEBUG_CONTROL')
                if digest((project/'handlers.cpp').read_bytes())!=control.get('source_sha256'):raise DevelopmentError('Source revision changed; restart Debug','SOURCE_CHANGED')
                snapshot=json.loads((project/'derived/debug/state.json').read_text())
                if arguments.debug_token is not None and snapshot.get('debug_token')!=arguments.debug_token:raise DevelopmentError('Debugger run identity changed','DEBUG_STATE')
                if snapshot['source_sha256']!=control['source_sha256'] or snapshot['state'] not in {'RUNNING','PAUSED','CONTINUING','STARTING'}:raise DevelopmentError('Debugger is stale or terminal','DEBUG_STATE')
                if control['operation'] not in {'pause','stop'} and snapshot['state']!='PAUSED':raise DevelopmentError('Control requires an actual paused C++ frame','DEBUG_STATE')
                if type(control.get('frame',0))is not int or not 0<=control.get('frame',0)<16:raise DevelopmentError('Frame index outside bound','DEBUG_CONTROL')
                if control['operation']=='children':
                    node=control.get('node_id');inspection=control.get('inspection_id');offset=control.get('offset',0)
                    if not isinstance(node,str) or len(node)>256 or node not in snapshot.get('variable_nodes',{}):
                        raise DevelopmentError('Select an actual debugger-reported variable node','DEBUG_VARIABLE')
                    parent=snapshot['variable_nodes'][node]
                    if type(inspection)is not int or inspection!=snapshot.get('inspection_id') or type(offset)is not int or offset!=parent.get('loaded_count',0):
                        raise DevelopmentError('Variable stop/frame or child range changed; refresh inspection','DEBUG_VARIABLE')
                    if parent.get('depth',0)>=8 or len(snapshot.get('variable_nodes',{}))>=512:
                        raise DevelopmentError('Variable inspection depth/node bound reached','DEBUG_VARIABLE')
                elif set(control)&{'node_id','inspection_id','offset'}:
                    raise DevelopmentError('Variable identity belongs only to children control','DEBUG_CONTROL')
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
            elif arguments.operation=='run': result=run(project,arguments.event,arguments.state)
            elif arguments.operation=='test': result=test_project(project)
            else: result={'status':'CATALOG','apis':api_catalog(project),'profiles':POLICY['profiles'],'python_authoring':False}
            write_json(project/'derived/project-write-grant.json',grant)
        response={'ok':True,'result':result}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False,allow_nan=False),flush=True)
        return 0 if result.get('status') in {'PASS','CREATED','BUILT','COMPLETED','CATALOG','CANDIDATE_EXPORTED','SAVED','REQUESTED','REVIEWED_INERT_ADDITIVE_UPGRADE','MAINTENANCE_READY','LEXICALLY_COMPLETE','INCOMPLETE','MAINTENANCE_CANDIDATE_EXPORTED'} else 1
    except Exception as error:
        response={'ok':False,'error':str(error),'code':getattr(error,'code','DEVELOPMENT_ERROR'),'detail':getattr(error,'detail',None)}
        print(tcl_result(response) if arguments.tcl else json.dumps(response,ensure_ascii=False),flush=True)
        return 1

if __name__=='__main__':
    request_process_group()
    signal.signal(signal.SIGTERM,cancel_children)
    signal.signal(signal.SIGINT,cancel_children)
    sys.exit(main())
