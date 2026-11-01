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
                              ACTIVE_PROCESSES, bounded_command, digest, environment, validate_source,
                              validate_project_sources, source_name)
from gxtxt_project_grant import check_project_root, enforce_project_write
from gxtxt_job_supervisor import request_process_group, tcl_result
import viewer_source_authoring_v1 as source_authoring
import gxtxt_acquisition_project_v1 as acquisition_project

MANUAL_LIMIT_BYTES = POLICY.get('manual_limit_bytes', 65536)
SCALAR_BROKER_CONTEXT=None

_cancelling_children = False
_cancel_exit_code = None
def cancel_children(signum, frame):
    global _cancelling_children, _cancel_exit_code
    if _cancelling_children: return
    _cancelling_children = True
    _cancel_exit_code = 128+signum
    scalar=sys.modules.get('gxtxt_viewer_scalar_broker')
    if scalar is not None:scalar.close_owned_brokers()
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
    record['project_snapshot'].update(source_identity(project_sources(project,meta)))
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
    if SCALAR_BROKER_CONTEXT is not None:env['GXTXT_VIEWER_SCALAR_SCOPE']=SCALAR_BROKER_CONTEXT['token']
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
        blocked=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGTERM,signal.SIGINT}) if SCALAR_BROKER_CONTEXT is not None else None
        try:
            child=subprocess.Popen(command,stdin=null,stdout=output,stderr=errors,
                                   cwd=project,env=project_environment(project),start_new_session=True,
                                   preexec_fn=(lambda:signal.pthread_sigmask(signal.SIG_SETMASK,blocked)) if blocked is not None else None)
            ACTIVE_PROCESSES.add(child.pid)
            if SCALAR_BROKER_CONTEXT is not None:
                from gxtxt_job_supervisor import process_identity
                SCALAR_BROKER_CONTEXT['core_requests'][str(child.pid)]=process_identity(child.pid)
                while len(SCALAR_BROKER_CONTEXT['core_requests'])>256:
                    SCALAR_BROKER_CONTEXT['core_requests'].pop(next(iter(SCALAR_BROKER_CONTEXT['core_requests'])))
        finally:
            if blocked is not None:signal.pthread_sigmask(signal.SIG_SETMASK,blocked)
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

def acquisition_project_target(project):
    path=project/'project.json'
    if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1 or path.stat().st_size>65536:
        return False
    try:
        return json.loads(path.read_bytes().decode('utf-8')).get('schema')==acquisition_project.SCHEMA
    except (ValueError,UnicodeError,AttributeError):
        return False

def read_project(project, *, installed=False, _authoring_payload=None):
    if not installed:
        check_project_root(project)
    if acquisition_project_target(project):
        return acquisition_project.state(project)[0]
    expected={'schema','module_id','version','profile','language','source','design','capabilities','provenance','tests'}
    for name in ('project.json','handlers.cpp','design.gxtxt-viewer'):
        path=project/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1 or path.stat().st_size>4194304:
            raise DevelopmentError('Project requires ordinary bounded '+name,'PROJECT_INVALID')
    meta=json.loads((project/'project.json').read_text())
    if set(meta)-{'source_files'}!=expected or meta['schema']!='gxtxt.viewer_development_project.v1' or meta['language']!='cpp' or meta['source']!='handlers.cpp' or meta['design']!='design.gxtxt-viewer':
        raise DevelopmentError('Unknown/forged project metadata, compiler, source, policy or adapter override','PROJECT_POLICY')
    if meta['profile'] not in POLICY['profiles']: raise DevelopmentError('Unknown trusted author profile','PROJECT_POLICY')
    if len(meta['capabilities'])>16: raise DevelopmentError('Capability request exceeds bound')
    if not isinstance(meta['provenance'],dict) or len(json.dumps(meta['provenance']))>8192:
        raise DevelopmentError('Provenance must be a bounded inert object')
    files=project_sources(project,meta)
    try:source_authoring.validate(project,meta,files,installed,_authoring_payload)
    except source_authoring.authoring.AuthoringError as error:raise DevelopmentError(str(error),'SOURCE_NOTES') from error
    return meta

def project_sources(project,meta=None):
    """Exact project input closure; additional undeclared sources never compile."""
    if meta is None:meta=json.loads((project/'project.json').read_text())
    if meta.get('schema')==acquisition_project.SCHEMA:
        actual,raw,files=acquisition_project.state(project)
        return {name:files[name] for name in actual['source_files']}
    names=meta.get('source_files',['handlers.cpp'])
    if not isinstance(names,list) or not 1<=len(names)<=32 or names[0]!='handlers.cpp' or any(not isinstance(n,str) for n in names) or len(set(names))!=len(names):
        raise DevelopmentError('source_files requires1..32 unique ordered names with handlers.cpp first','PROJECT_SOURCES')
    files={};total=0
    for name in names:
        try:source_name(name)
        except ValueError as error:raise DevelopmentError(str(error),'PROJECT_SOURCES')
        path=project/name
        # Check each ancestor, including installed package sources. resolve()
        # alone would follow and thereby authorize a forged symlinked subtree.
        if any(p.is_symlink() for p in [path,*path.parents] if p!=project.parent) or not path.is_file() or path.stat().st_nlink!=1 or path.stat().st_size>POLICY['source_limit_bytes']:
            raise DevelopmentError('Source must be an ordinary bounded project file: '+name,'PROJECT_SOURCES')
        content=path.read_bytes();total+=len(content)
        if total>1048576:raise DevelopmentError('Project sources exceed1MiB','PROJECT_SOURCES')
        files[name]=content
    return files

def source_identity(files):
    manifest=[dict(path=name,role='entrypoint' if name=='handlers.cpp' else 'header' if name.endswith('.hpp') else 'translation_unit',bytes=len(content),sha256=digest(content)) for name,content in files.items()]
    tree=digest(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode())
    return dict(source_manifest=manifest,source_tree_sha256=tree)

def sources_match(project,report):
    try:
        identity=source_identity(project_sources(project))
        if 'source_tree_sha256' not in report:
            return len(identity['source_manifest'])==1 and identity['source_manifest'][0]['sha256']==report['source_sha256']
        return all(identity[key]==report.get(key) for key in identity)
    except (OSError,ValueError,KeyError,DevelopmentError):return False

def installed_source_manifest(project,report):
    if 'source_manifest' not in report:return  # Compatible historical one-file packages.
    path=project/'SOURCE_MANIFEST.json'
    if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1 or path.stat().st_size>65536:
        raise DevelopmentError('Installed project source manifest is missing or invalid','BINARY_SOURCE_MISMATCH')
    expected={key:report[key] for key in ('source_manifest','source_tree_sha256')}
    if json.loads(path.read_text())!=expected:
        raise DevelopmentError('Installed source manifest differs from the build receipt','BINARY_SOURCE_MISMATCH')

def project_digest(report):
    return digest(json.dumps({key:report[key] for key in ('source_tree_sha256','project_sha256','design_sha256')},sort_keys=True,separators=(',',':')).encode())

def api_catalog(project):
    return _describe_api_catalog(core(project,'api_catalog'))

def _acquisition_catalog(catalog):
    """Target-only metadata projection; never adds Viewer policy operations."""
    result={key:dict(value) for key,value in catalog.items()}
    row=result.get('ACQUISITION_HANDLER_PLUGIN_API_v1',{})
    if row.get('native_protocol')=='gxtxt.native_acquisition_request.v1' and str(row.get('native_protocol_version'))=='1':
        row['allowed_operations']=sorted(dictionary(row.get('native_operation_contracts','')))
    else:row['allowed_operations']=[]
    return result

def _acquisition_browser_catalog(catalog,project):
    import gxtxt_acquisition_cpp_v1 as acquisition_cpp
    before=acquisition_project.state(project);meta,raw,files=before
    desc=acquisition_project.description(meta,raw,files)
    if acquisition_project.state(project)!=before:raise DevelopmentError('Project changed during API discovery','SOURCE_CHANGED')
    projected=_acquisition_catalog(catalog);api=acquisition_cpp.API;available=projected.get(api,{})
    allowed=set(available.get('allowed_operations',[]))
    requested={request['api_id']:request for request in meta['capabilities']}
    declared=requested.get(api,{});operations=set(declared.get('operations',[]))
    supported=(str(available.get('version'))=='1' and str(available.get('available',available.get('enabled','')))=='1')
    admitted=supported and str(declared.get('version'))=='1' and operations.issubset(allowed)
    for key,row in catalog.items():
        row.update(cpp_methods={},cpp_project_status='NOT_REQUESTED',cpp_project_request={},sdk_exposed=False,allowed_operations=[])
    if api in catalog:
        row=catalog[api];row.update(sdk_exposed=True,allowed_operations=sorted(allowed),cpp_project_request=declared,
            cpp_project_status='ADMITTED_REQUEST' if admitted else 'CORE_API_GAP' if not supported else 'CAPABILITY_DENIED')
        row['cpp_methods']=_acquisition_sdk_methods('ADMITTED_REQUEST' if admitted else 'CORE_API_GAP' if not supported else 'CAPABILITY_DENIED', operations)
    return dict(status='SAVED_PROJECT_METADATA',target='acquisition',project=str(project),profile=meta['profile'],
        project_sha256=desc['project_sha256'],source_tree_sha256=desc['source_tree_sha256'],revision=desc['revision'],
        profile_sha256=desc['profile_sha256'],formats=desc['formats'],requests=requested,
        source_validation='not_checked_by_metadata_browser',runtime_grants='not_activated_by_metadata_browser',
        runtime_available=False,availability_reason='Native runtime availability belongs to actual CORE managed Acquisition admission')

def _acquisition_sdk_methods(status='NO_PROJECT', operations=()):
    """Fixed target SDK metadata, never a Viewer capability extension."""
    import gxtxt_acquisition_cpp_v1 as target
    allowed=json.loads(target.POLICY_PATH.read_text())['sdk_calls']
    methods={}
    for result,method,args in re.findall(r'^\s*(SourceDescriptor|SourceChunk|bool|void|PreparedOutput|PreparedReference|AcquisitionValue)\s+(\w+)\(([^;]*)\) const;',target.SDK.read_text(),re.M):
        if method not in allowed:continue
        names=[re.search(r'(\w+)\s*$',arg.strip()).group(1) for arg in args.split(',') if arg.strip()]
        call='host.'+method+'('+', '.join(names)+');'
        methods[method]=dict(signature=result+' gx::AcquisitionHost::'+method+'('+args+') const;',
            scope='AcquisitionHost',example=('auto result = ' if result!='void' else '')+call,
            operation=method,result_type=result,required_capabilities=[target.API+'/'+method],
            required_target='acquisition',sdk_header='core/development/sdk/gxtxt_acquisition_sdk_v1.hpp',
            sdk_sha256=digest(target.SDK.read_bytes()),project_status=('ADMITTED_REQUEST' if method in operations else 'NOT_ADMITTED') if status=='ADMITTED_REQUEST' else status,
            missing_capabilities=[] if status=='ADMITTED_REQUEST' and method in operations else [target.API+'/'+method],
            admission_scope='Acquisition target only; metadata is not source validation, compilation or live capability admission')
    return methods

def _describe_api_catalog(raw):
    catalog={key:dictionary(value) for key,value in dictionary(raw).items()}
    shapes={
        'getLibraryInfo':{'request':{'scope':'registered Library identity through a declared bounded Comparison form'},'result':'CORE pins managed source version and SHA; no native paths or raw library access'},
        'readLibraryEntry':{'request':{'scope':'finite comparison add_library/prepare only, with current source identity and 2..65536 samples in exact pages'},'result':'CORE-owned transient scientific consultation; C++ receives no payload, files or implicit Dataset publication'},
        'comparison_curves':{'request':{'scope':'CORE Comparison controller only; bounded source curves and explicit normalization/offset/denominator policy'},'result':'Numeric-owned raw or display-derived curve; exact finite knots and gaps preserved; C++ receives no arrays'},
        'analysis_command':{'request':{'form':'complete declared generic targeted Analysis section','operation':'discover/submit/status/cancel/candidates/add_candidate','samples':'none; host owns canonical result and source reads'},'result':'next-event bounded typed invocation/result identity and candidate records; existing Standard Analysis queue owns execution; separate current event/module capability required'},
        'comparison_command':{'request':{'form':'declared reciprocal Comparison Plot section','operation':'finite source/method presentation action','samples':'none; CORE reads pinned bounded canonical or read-only managed Library sources'},'result':'next-event immutable status/error/sequence; Numeric owns calculations, Plot v4 the sole renderer; capabilities and current event/package/source admission remain required'},
        'script_library_command':{'request':{'form':'declared Viewer section with exact script_library_components roles','operation':'finite Script Library action','request':'strict typed object, at most 48 KiB; no source bodies, paths or authority'},'result':'next-event immutable result/view receipt; actual native_client_operations, source/record/namespace and event lifetime admission remain required'},
        'scientific_preview_command':{'request':{'form':'declared managed Preview section with scientific_preview_components roles','operation':'discover/page/metadata/source','request':'strict typed object, at most 48 KiB; exact rank-shaped page at most 512 cells'},'result':'next-event immutable source-bound result/view receipt; canonical Dataset and actual native operation admission remain CORE-owned; numeric values preserve exact text'},
        'scientific_frame_bind':{'request':{'viewport':'exact declared frame_view panel index','form':'declared managed Preview section with complete frame controls'},'result':'deferred canonical bounded plane binding through existing CORE Native2D/Numeric owners; no image.raster substitution, authored pixel array or implicit capability'},
        'datasetGroupProducerReviewV1':{'request':{'scope':'registered producer current Session; 0..64 owned Dataset IDs; typed 48 KiB request'},'result':'next-event transient producer receipt; exact opaque full revision strings'},
        'datasetGroupProducerCreateV1':{'request':{'scope':'typed definition plus exact prior producer review; actual owner/namespace/revision/SHA checks'},'result':'explicit owned-existing Group; no Dataset rewriting'},
        'datasetProducerPublishBatchV1':{'request':{'scope':'current reviewed Session token and1..64 ordinary series outputs; optional exact Group requires GroupCreate grant too'},'result':'existing Publicationv2+Group transaction, full rollback, grouping opt-in'},
        'value_set':{'request':{'component':'declared component index','value':'finite number or boolean'},'result':'display applied; no scientific effect'},
        'text_set':{'request':{'component':'declared status/label index','text':'literal UTF-8 <=256 bytes'},'result':'display applied'},
        'document_bind':{'request':{'document':'declared document component index, kind html/pdf/code/table/markdown/uml','dataset_selector':'declared compatible Dataset selector with matching content_kind'},'result':'existing CORE document/PDF/source/paged-table consultation; original Session/source revision, no author filesystem/renderer'},
        'document_command':{'request':{'document':'declared Markdown/UML document component index','operation':'finite kind-specific command; mutation requires editable mode and UML operations require explicit UML_DOCUMENT_API_v1 grants'},'result':'existing DOCUMENT_SOURCE_API_v1 editor operation; producer authority and Session revision checked by its public owner'},
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
    for operation in ('libraryCatalogPage','listLibraryTypes','getProviderCapabilities','getLibraryCapabilities','listLibraryEntries','searchLibraryEntries','libraryEntriesPage','getLibraryEntryInfo','openLibraryViewer','verifyLibrary','installLibrary','updateLibrary','removeLibrary','registerLibrary','unregisterLibrary','invokeLibraryAction'):
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
    shapes.update({
        'value_get':{'request':{'scope':'immutable declared component strings and bounded typed data for the current event'},'result':'UTF-8 event snapshot, no widget or file access'},
        'cad_command':{'request':{'component':'declared cad_sketch index','action':'catalogued shared CAD action ID'},'result':'existing native scientific controller and managed Sketch History'},
        'diagnostics_command':{'request':{'form':'declared STDERR consultation form','operation':'finite archive/status/subscription operation'},'result':'bounded asynchronous typed CORE data; no capture toggles or arbitrary paths'},
        'text_runs':{'request':{'component':'declared read-only log','runs':'bounded JSON text/style runs'},'result':'shared source palette tags, no lexer or GUI evaluation'},
        'table_set':{'request':{'component':'declared read-only table','rows':'bounded JSON rows'},'result':'existing UI Field table presentation'},
    })
    for op in ('cad_sketch_create','cad_sketch_command','cad_sketch_state','cad_action_catalog','cad_action_invoke'):
        shapes[op]={'request':{'scope':'declared cad_sketch component through its finite CAD GUI Host adapter'},'result':'managed native scene, exact geometry and public P017 History owners'}
    for op in ('info','status','meta','read','request','cancel','subscribe','unsubscribe','export'):
        shapes.setdefault(op,{'request':{'scope':'bounded typed diagnostic consultation, cursor or stable record identities'},'result':'optional global archive/status; origin fields retained, capture is Configuration-owned'})
    for key,row in catalog.items():
        row['providers']=[dictionary(value) for value in tkinter.Tcl().splitlist(row.get('providers',''))]
        row['version_conflict']=len({str(p.get('version','')) for p in row['providers']})>1
        if len(row['providers'])>1:row['provider']='';row['provider_selection']='multiple_declaring_owners; inspect provider-qualified declaration'
        if row['version_conflict']:row['version']=''
        allowed=POLICY['capabilities'].get(key)
        row['sdk_exposed']=bool(allowed)
        if key=='VIEWER_DEVELOPMENT_API_v1':
            row['author_tools']={'inspect':{'targets':['handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer','sdk_v1'],'result':'bounded inert UTF-8 content/sha256/bytes; no arbitrary paths'},'api_document':{'request':'api --document catalogued_PUBLIC_API_vN','result':'bounded exact installed public manual; no private file reader'},'manual_asset':{'operations':['list','add','remove'],'input':'logical asset_id and exact source-identical gui_test capture_id; JSON stdin','result':'images/ASSET_ID.png preserved by normal export;32 images,8MiB each,16MiB total; no author paths'},'gui_test':{'requires':'explicit real Workspace attachment; identical normally installed source; current Session','actions':['open','workspace_open','workspace_save','workspace_review','workspace_upgrade','status','close','capture','capture_verify','capture_preview','resize','label','label_apply','label_close','click','choice','list_select','table_select','table_scroll','table_copy','table_page','text','tab','pointer','plot_pointer','key','document_find','document_pointer','document_zoom','pdf_control','pdf_pointer','pdf_key','pdf_resize','pdf_close','property','wire_route','properties_commit','properties_close'],'scope':'assigned Viewer only; no Tcl, widget paths, filesystem destinations or global desktop; not a C++ runtime capability'}}
            row['author_tools']['inspect']['declared_targets']='Every source_files path, bounded to64KiB each; existing one-file default remains handlers.cpp'
            row['author_tools']['project_files']={'operations':['list','add','rename','remove','save_all','note_read','note_identity','note_write','note_asset_read'],'input':'JSON stdin; expected project/file SHA preimages for mutations; note_write uses bounded note_base64 and expected authoring/source revision','result':'same ordered source manifest/composite digest; non-code authoring pointer/notes; no compiler or new registry'}
            row['author_tools']['import_project']={'input':'normal exported ZIP and absent new project destination','result':'exact checked editable sources; no packaged binary execution; explicit Build remains separate'}
        row['allowed_operations']=allowed['operations'] if allowed else []
        if key=='NATIVE_WORKSPACE_API_v1':
            row['operation_shapes']={op:{'request':{'scope':'declared Viewer Workspace only; typed values and exact native generation/revision; no paths, SQL or arbitrary providers'},'result':'immutable event snapshot for reads; owning-thread guarded native lifecycle command after the C++ event; save acceptance and durability remain distinct'} for op in row['allowed_operations']}
        elif key=='UML_DOCUMENT_API_v1':row['operation_shapes']={op:{'request':{'scope':'explicit source-bound UML Document operation through Host.document_bind/command'},'result':'existing shared parser/editor/layout/Document authority; no worker source body, paths or Tcl'} for op in row['allowed_operations']}
        else:row['operation_shapes']={op:shapes[op] for op in row['allowed_operations']}
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
    required['document_command']=('VIEWER_GUI_HOST_API_v1','document_command')
    for method,operation in {'workspace':'get','property':'get','state':'get','status':'status','query':'query','set_property':'set_property','set_state':'set_state','save':'save','save_as':'save_as','rename':'rename','open':'open','close':'close'}.items():
        required[method]=('NATIVE_WORKSPACE_API_v1',operation)
    for method in ('raster_bind','raster_tool','raster_command'):
        required[method]=('VIEWER_GUI_HOST_API_v1',method)
    required['tex_command']=('VIEWER_GUI_HOST_API_v1','tex_command')
    required['em_command']=('VIEWER_GUI_HOST_API_v1','em_command')
    required['workbench_command']=('VIEWER_GUI_HOST_API_v1','workbench_command')
    for method,operation in [('input','value_get'),('data','value_get'),('cad_command','cad_command'),('diagnostics_command','diagnostics_command'),('text_runs','text_runs'),('table','table_set')]:
        required[method]=('VIEWER_GUI_HOST_API_v1',operation)
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
    required['dataset_group_review']=('DATASET_GROUP_API_v1','datasetGroupProducerReviewV1')
    required['dataset_group_create']=('DATASET_GROUP_API_v1','datasetGroupProducerCreateV1')
    required['dataset_producer_result']=('DATASET_GROUP_API_v1','datasetGroupProducerReviewV1')
    required['dataset_publish_batch']=('DATASET_PUBLICATION_API_v2','datasetProducerPublishBatchV1')
    for method in ('script_library_command','script_library_result'):
        required[method]=('SCRIPT_LIBRARY_API_v1','script_library_command')
    for method in ('scientific_preview_command','scientific_preview_result'):
        required[method]=('PREVIEW_COMPONENT_GUI_API_v1','scientific_preview_command')
    required['scientific_frame_bind']=('PREVIEW_COMPONENT_GUI_API_v1','scientific_frame_bind')
    for method in ('analysis_command','analysis_result'):
        required[method]=('MODULE_TARGETED_ANALYSIS_API_v1','analysis_command')
    for method in ('comparison_command','comparison_result'):
        required[method]=('COMPARISON_PLOT_API_v1','comparison_command')
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
    native=set(request['operations']) & {'script_library_command','scientific_preview_command','scientific_frame_bind','comparison_command','analysis_command'}
    if native:
        raw=available.get('native_client_operations',())
        try:implemented=set(tkinter.Tcl().splitlist(raw)) if isinstance(raw,str) else set(raw)
        except (TypeError,tkinter.TclError):return 'CORE_API_GAP'
        if not native.issubset(implemented):return 'CORE_API_GAP'
    return 'ADMITTED_REQUEST'

def _browser_cpp_catalog(catalog, project=None):
    if project is not None and acquisition_project_target(project):
        return _acquisition_browser_catalog(catalog,project)
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
            identity=source_identity(project_sources(project,meta))
            if read_project(project)!=meta or identity!=source_identity(project_sources(project)) or before!={name:digest((project/name).read_bytes()) for name in inputs}:
                raise ValueError('Project changed during reference discovery; refresh its saved metadata')
            context.update(status='SAVED_PROJECT_METADATA',project=str(project),profile=meta['profile'],
                           project_sha256=before['project.json'],source_sha256=before['handlers.cpp'],
                           design_sha256=before['design.gxtxt-viewer'])
            context.update(identity)
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
    prototypes=re.findall(r'^\s*(void|double|const\s+char\s*\*|WorkspaceValue|WorkspaceStatus|Workspace|std::vector<WorkspaceEntry>)\s+(\w+)\(([^;]*)\) const;',SDK.read_text(),re.M)
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
        names=[re.search(r'(\w+)\s*$',arg.split('=',1)[0].strip()).group(1) for arg in arguments.split(',') if arg.strip()]
        scope='Workspace' if method in {'state','property','status','query','set_state','set_property','save','save_as','rename','open','close'} else 'Host'
        call=('host.workspace().' if scope=='Workspace' else 'host.')+method+'('+', '.join(names)+');'
        if result!='void':call='auto result = '+call
        catalog[api]['cpp_methods'][method]={
            'signature':result+' gx::'+scope+'::'+method+'('+arguments+') const;',
            'example':call,'operation':operation,'result_type':result,
            'required_capabilities':[family+'/'+op for family,op in grants],
            'project_status':('ADMITTED_REQUEST' if not missing else 'NOT_ADMITTED') if context['status']=='SAVED_PROJECT_METADATA' else context['status'],
            'missing_capabilities':missing,
            'admission_scope':'saved request/profile/provider policy only; Validate checks source and declared forms; finite action grants are checked at runtime',
            'sdk_sha256':digest(SDK.read_bytes())}
    if 'ACQUISITION_HANDLER_PLUGIN_API_v1' in catalog:
        row=catalog['ACQUISITION_HANDLER_PLUGIN_API_v1']
        row['cpp_methods']=_acquisition_sdk_methods('NO_PROJECT' if project is None else 'TARGET_NOT_ADMITTED')
        row['sdk_exposed']=True
        row['sdk_target']='acquisition'
        row['allowed_operations']=sorted(row['cpp_methods'])
        row['authorization_reason']='AcquisitionHost target only; saved declarations, Validate and live CORE request admission remain separate'
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
    # Always derive this runtime projection from today's actual requests and
    # catalog admission. Saved build/import reports are not grant authority.
    validation.pop('native_client_module',None)
    validation.pop('native_client_grants',None)
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
    if validation.get('workspace_hooks') and not {'get','save'}.issubset(requested.get('NATIVE_WORKSPACE_API_v1',set())):
        raise DevelopmentError('Typed Workspace hooks require the explicit native get/save lifecycle grant','CAPABILITY_DENIED')
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
    uml=[]
    if design is not None:
        for component in tkinter.Tcl().splitlist(design.get('components','')):
            item=dictionary(component)
            if item.get('type')=='document' and dictionary(item.get('properties','')).get('kind')=='uml':uml.append(item)
    if uml:
        admitted=requested.get('UML_DOCUMENT_API_v1',set())
        needed={'umlDocumentRead','umlDocumentParse','umlDocumentLayout'}
        if any(dictionary(item['properties']).get('mode','read_only')=='editable' for item in uml):needed.add('umlDocumentEdit')
        if not needed.issubset(admitted):raise DevelopmentError('UML document lacks explicit operations: '+', '.join(sorted(needed-admitted)),'CAPABILITY_DENIED')
        validation['uml_operations']=sorted(admitted)
    else:validation.pop('uml_operations',None)
    if set(validation['sdk_calls']) & {'dataset_group_review','dataset_group_create','dataset_publish_batch','dataset_producer_result'}:
        validation['dataset_producer_module']=meta['module_id']
        validation['dataset_producer_grants']={api:sorted(requested.get(api,set())) for api in ('DATASET_GROUP_API_v1','DATASET_PUBLICATION_API_v2')}
    native_clients={api:sorted(requested.get(api,set())) for api in ('SCRIPT_LIBRARY_API_v1','PREVIEW_COMPONENT_GUI_API_v1','COMPARISON_PLOT_API_v1','MODULE_TARGETED_ANALYSIS_API_v1')}
    if native_clients['COMPARISON_PLOT_API_v1'] or native_clients['MODULE_TARGETED_ANALYSIS_API_v1']:
        for api in ('SCIENTIFIC_LIBRARY_MANAGER_API_v1','NUMERIC_API_v1','PLOT_DATASET_API_v4'):
            native_clients[api]=sorted(requested.get(api,set()))
    if design is not None and any(native_clients.values()):
        target=design.get('target','viewer')
        if native_clients['MODULE_TARGETED_ANALYSIS_API_v1'] and target!='viewer':raise DevelopmentError('Targeted Analysis admission requires an actual Viewer design','CAPABILITY_DENIED')
        if native_clients['SCRIPT_LIBRARY_API_v1'] and target!='viewer':raise DevelopmentError('Script Library native admission requires an actual Viewer design','CAPABILITY_DENIED')
        if native_clients['PREVIEW_COMPONENT_GUI_API_v1'] and target!='preview':raise DevelopmentError('Scientific native admission requires an actual Preview design','CAPABILITY_DENIED')
        validation['native_client_module']=meta['module_id']
        validation['native_client_grants']=native_clients
    return requested

def acquisition_initialize(project,payload):
    if not isinstance(payload,dict) or set(payload)!={'schema','target','metadata'} or payload['schema']!='gxtxt.development_project_init.v1' or payload['target']!='acquisition':
        raise DevelopmentError('Use the versioned Acquisition project initialization request','PROJECT_REQUEST')
    meta=acquisition_project.defaults(payload['metadata'])
    check_project_root(project,allow_missing=True)
    if project.exists() and any(project.iterdir()):raise DevelopmentError('New project directory must be empty','SOURCE_TARGET')
    project.mkdir(parents=False,exist_ok=True)
    grant=enforce_project_write(project)
    (project/'derived/tmp').mkdir(parents=True,exist_ok=True)
    encoded={'handlers.cpp':acquisition_project.STARTER,'project.json':acquisition_project.encode(meta)}
    def verify():
        actual,raw,files=acquisition_project.state(project)
        if actual!=meta or files!={'handlers.cpp':acquisition_project.STARTER}:raise DevelopmentError('New project readback differs','SOURCE_CHANGED')
        return acquisition_project.description(actual,raw,files)
    description=_publish_project_files(project,encoded,[],verify,expected_prestate={name:None for name in encoded})
    return {'status':'CREATED','target':'acquisition','description':description,'grant':grant,'code_generation_invoked':False}

def acquisition_project_files(project,payload):
    import gxtxt_acquisition_source_notes_v1 as acquisition_notes
    if isinstance(payload,dict) and payload.get('operation') in {'note_read','note_identity','note_write','note_asset_read'}:
        return acquisition_note_request(project,payload)
    result,plan=acquisition_project.prepare_edit(project,payload)
    if plan is None:
        if isinstance(payload,dict) and payload.get('operation')=='describe':
            from gxtxt_acquisition_cpp_v1 import describe as acquisition_description
            return acquisition_description(project,*acquisition_project.state(project))
        return result
    meta,raw,files=acquisition_project.state(project)
    if any(plan['expected_prestate'].get(name)!=content for name,content in dict(files,**{'project.json':raw}).items()):
        raise DevelopmentError('Project changed before Source Note retention','SOURCE_CHANGED')
    candidate=acquisition_project.decode(plan['metadata_raw'])
    moves={payload['relative']:payload['target']} if payload['operation']=='rename' else {}
    candidate=acquisition_notes.source_change(project,meta,files,candidate,plan['files'],moves)
    if candidate!=acquisition_project.decode(plan['metadata_raw']):
        plan['metadata_raw']=plan['encoded']['project.json']=acquisition_project.encode(candidate)
    def verify():
        meta,raw,files=acquisition_project.state(project)
        if raw!=plan['metadata_raw'] or files!=plan['files']:raise DevelopmentError('Source write readback differs','SOURCE_CHANGED')
        from gxtxt_acquisition_cpp_v1 import describe as acquisition_description
        return acquisition_description(project,meta,raw,files)
    description=_publish_project_files(project,plan['encoded'],plan['removed'],verify,expected_prestate=plan['expected_prestate'])
    return {'status':'SAVED','operation':plan['operation'],'description':description,'code_generation_invoked':False}

def acquisition_note_request(project,payload):
    """Existing SOURCE_NOTE client forms plus versioned full-closure requests."""
    import gxtxt_acquisition_source_notes_v1 as notes
    meta,raw,files=acquisition_project.state(project);op=payload['operation']
    common={'operation','relative','file_key','owner_key','expected_project_sha256'}
    extra={'note_read':set(),'note_identity':{'expected_source_sha256','expected_authoring_revision'},
           'note_write':{'expected_source_sha256','expected_authoring_revision','note_base64','asset_plan'},
           'note_asset_read':{'name','start','count','expected_authoring_revision','expected_asset_sha256'}}[op]
    typed='schema' in payload
    if set(payload)-(common|extra|({'schema','expected_revision'} if typed else set())):
        raise DevelopmentError('Unknown Source Note request fields','SOURCE_NOTES')
    desc=acquisition_project.description(meta,raw,files)
    if typed and (payload['schema']!=acquisition_project.EDIT_SCHEMA or payload.get('expected_revision')!=desc['revision']):
        raise DevelopmentError('Project/source closure changed before Source Note operation','SOURCE_CHANGED')
    if ('expected_project_sha256' in payload or not typed and op!='note_read') and payload.get('expected_project_sha256')!=digest(raw):
        raise DevelopmentError('Source Note owning project changed','SOURCE_CHANGED')
    request={key:value for key,value in payload.items() if key not in {'schema','expected_revision'}}
    notes.resolve(project,meta,files,request) # Refuse unsupported Tcl explicitly.
    if op=='note_asset_read':return dict(status='SAVED',**source_authoring.read_asset(project,meta,files,request))
    if op in {'note_identity','note_write'}:
        updated=notes.prepare(project,meta,files,request);content=acquisition_project.encode(updated)
        expected=dict(files,**{'project.json':raw})
        def verify():
            actual,actual_raw,actual_files=acquisition_project.state(project)
            if actual_raw!=content or actual_files!=files:raise DevelopmentError('Source Note pointer readback differs','SOURCE_CHANGED')
            return actual,actual_raw,actual_files
        meta,raw,files=_publish_project_files(project,{'project.json':content},[],verify,expected_prestate=expected)
    result=notes.projection(project,meta,files,request)
    current=acquisition_project.description(meta,raw,files)
    result.update(project_sha256=digest(raw),source_revision=current['source_tree_sha256'],revision=current['revision'],code_generation_invoked=False)
    return result

def initialize(project,module_id, *, preview=False):
    check_project_root(project,allow_missing=True)
    if project.exists() and any(project.iterdir()): raise DevelopmentError('New project directory must be empty')
    project.mkdir(parents=False,exist_ok=True)
    grant=enforce_project_write(project)
    (project/'derived/tmp').mkdir(parents=True,exist_ok=True)
    design=core(project,'new_preview_design' if preview else 'new_design',module_id)
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

def generate_preview(project, request):
    """Explicit Builder generation through this same source/build/export owner.

    Only a fresh project's template is generated. Existing C++ sources,
    metadata, capability requests, notes and manual remain author-owned.
    """
    if not isinstance(request,dict) or set(request)!={'schema','module_id','design'} or request['schema']!='gxtxt.preview_generation.v1' or not isinstance(request['design'],str):
        raise DevelopmentError('Exact managed Preview generation request required','PROJECT_INVALID')
    check_project_root(project,allow_missing=True)
    fresh=not project.exists() or not any(project.iterdir())
    if fresh:
        initialize(project,request['module_id'],preview=True)
    else:
        enforce_project_write(project)
        read_project(project)
    destination=project/'design.gxtxt-viewer'
    original=digest(destination.read_bytes())
    # The layout remains data admitted and saved by the shared CORE model.
    with tempfile.TemporaryDirectory(prefix='preview-design-',dir=project/'derived/tmp') as scratch:
        staged=Path(scratch)/'design.gxtxt-viewer'
        staged.write_text(request['design'],encoding='utf-8')
        design=dictionary(core(project,'validate_design',staged))
        options=dictionary(design.get('preview',''))
        if design.get('target')!='preview' or options.get('runtime')!='managed_cpp' or design['module_id']!=request['module_id']:
            raise DevelopmentError('Generation requires the admitted managed C++ Preview target','PREVIEW_RUNTIME')
        meta=read_project(project)
        if not fresh and (meta['module_id']!=design['module_id'] or meta['version']!=design['version']):
            raise DevelopmentError('Existing C++ project identity/version differs; use its Development Workspace or a new source folder','PROJECT_INVALID')
        components=[dictionary(row) for row in tkinter.Tcl().splitlist(design['components'])]
        if fresh:
            numeric=any(row['type']!='document' for row in components)
            lines=['// SPDX-License-Identifier: GPL-3.0-or-later', '#include <string>',
                   '// Canonical presentation only; CORE owns scientific data and lifecycle.',
                   'void on_event(gx::Host& host, gx::State&, const gx::Event& event) {']
            operations=['value_get']
            capabilities=[]
            if numeric:
                indices={row['id']:index for index,row in enumerate(components,1)}
                for index,row in enumerate(components,1):
                    if row['type']!='plot':continue
                    form=dictionary(row['properties']).get('plot_form')
                    if form not in indices:raise DevelopmentError('Numeric Plot requires its declared source form','PROJECT_INVALID')
                    lines.extend([f'    host.plot_discover({indices[form]});',f'    host.plot_bind({index}, {indices[form]});'])
                capabilities.append(dict(api_id='PLOT_DATASET_API_v4',version=4,operations=['widgetCreate']))
            else:
                operations.append('document_command')
                lines.extend(['    if (event.kind != gx::EventKind::open) return;', '    const std::string selected = host.data();'])
                for index,row in enumerate(components,1):
                    lines.append(f'    if (selected == {json.dumps(row["id"])}) host.document_command({index}, "render");')
            lines.append('}')
            meta.update(module_id=design['module_id'],version=design['version'],
                        profile='scientific_view_v1' if numeric else 'document_view_v1',
                        capabilities=[dict(api_id='VIEWER_GUI_HOST_API_v1',version=1,operations=operations),*capabilities],
                        provenance=dict(template='shared_builder_managed_preview_v1',scientific_source=None),
                        tests=dict(events=[],preview_requires_current_canonical_context=True))
            (project/'handlers.cpp').write_text('\n'.join(lines)+'\n',encoding='utf-8')
            write_json(project/'project.json',meta)
            (project/'MANUAL.md').write_text('# '+design['title']+'\n\nRead-only compiled Preview. CORE supplies the selected canonical Dataset and owns presentation, provenance and lifetime. Generated C++ uses only admitted public host operations. Add custom presentation in the existing C++ Development Workspace; regeneration preserves handwritten sources and capability requests.\n',encoding='utf-8')
        preserved=source_identity(project_sources(project,meta))
        core(project,'builder_design_save',destination,staged,original)
    exported=export_candidate(project)
    if exported.get('status')!='CANDIDATE_EXPORTED':return exported
    if source_identity(project_sources(project,meta))!=preserved:
        raise DevelopmentError('Authored source changed during Preview generation','SOURCE_CHANGED')
    report=dict(status='CANDIDATE_EXPORTED',runtime='managed_cpp',fresh_template=fresh,
                source_tree_sha256=preserved['source_tree_sha256'],design_sha256=digest(destination.read_bytes()),
                package=exported['package'],sha256=exported['sha256'],authored_sources_preserved=True,
                scientific_data_generated=False,independent_acceptance=False)
    write_json(project/'generation-report.json',report)
    return dict(exported,generation_report=str(project/'generation-report.json'))

def import_project(project,package):
    """Recover exact editable sources from the normal exported package.

    This trusted initialization phase runs no authored source or native binary.
    It validates the complete archive before publishing one new project folder;
    the existing project write grant is then installed for subsequent work.
    """
    import io,shutil,stat,zipfile
    check_project_root(project,allow_missing=True)
    if project.exists():raise DevelopmentError('Import requires an absent new project path','SOURCE_TARGET')
    if package is None:raise DevelopmentError('Choose a standard exported Viewer package','SOURCE_TARGET')
    package=package.absolute()
    if package.resolve()!=package or package.is_symlink() or not package.is_file() or package.stat().st_nlink!=1 or package.stat().st_size>33554432:
        raise DevelopmentError('Source package must be an ordinary ZIP within32MiB','SOURCE_TARGET')
    fd=os.open(package,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
    with os.fdopen(fd,'rb') as stream:
        before=os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size>33554432:raise DevelopmentError('Source package is not an ordinary bounded archive','SOURCE_TARGET')
        package_bytes=stream.read(33554433);after=os.fstat(stream.fileno());current=package.stat(follow_symlinks=False)
    identity=lambda info:(info.st_dev,info.st_ino,info.st_size,info.st_mtime_ns,info.st_ctime_ns,info.st_mode,info.st_nlink)
    if len(package_bytes)>33554432 or identity(before)!=identity(after) or identity(after)!=identity(current):raise DevelopmentError('Source package changed while reading','SOURCE_CHANGED')
    with zipfile.ZipFile(io.BytesIO(package_bytes)) as archive:
        members=archive.infolist();names=[item.filename for item in members]
        if len(names)!=len(set(names)) or not 1<=len(names)<=512 or sum(item.file_size for item in members)>67108864:
            raise DevelopmentError('Source package inventory exceeds bounds or contains duplicates','PROJECT_PACKAGE')
        for item in members:
            name=item.filename;mode=item.external_attr>>16
            if name.startswith('/') or '\\' in name or any(part in {'','.', '..'} for part in name.split('/')) or (mode&0o170000 not in {0,0o100000}):
                raise DevelopmentError('Source package contains unsafe paths/member types','PROJECT_PACKAGE')
        payload={item.filename:archive.read(item) for item in members}
    manifest=payload.get('SHA256SUMS.txt')
    if manifest is None:raise DevelopmentError('Source package has no standard checksum inventory','PROJECT_PACKAGE')
    checks={}
    for line in manifest.decode('utf-8').splitlines():
        match=re.fullmatch(r'([0-9a-f]{64})  (.+)',line)
        if not match or match[2] in checks:raise DevelopmentError('Malformed package checksum inventory','PROJECT_PACKAGE')
        checks[match[2]]=match[1]
    if checks!={name:digest(content) for name,content in payload.items() if name not in {'SHA256SUMS','SHA256SUMS.txt'}}:
        raise DevelopmentError('Source package checksum closure differs','PROJECT_PACKAGE')
    if 'source/project.json' in payload:
        metadata=acquisition_project.decode(payload['source/project.json'])
        if isinstance(metadata,dict) and metadata.get('schema')==acquisition_project.SCHEMA:
            from gxtxt_acquisition_development_v1 import import_project_payload
            return import_project_payload(project,payload,digest(package_bytes),enforce_project_write)
    required={'source/project.json','source/handlers.cpp','source/design.gxtxt-viewer','review/build.json'}
    if not required.issubset(payload):raise DevelopmentError('Package has no complete editable C++ project','PROJECT_PACKAGE')
    authoring_payload={name[len('source/authoring/'):]:content for name,content in payload.items() if name.startswith('source/authoring/')}
    sources={name[7:]:content for name,content in payload.items() if name.startswith('source/') and name!='source/SOURCE_MANIFEST.json' and not name.startswith('source/authoring/')}
    for name in sources:
        if name in {'project.json','design.gxtxt-viewer','MANUAL.md','manual-assets.json'} or re.fullmatch(r'manual-assets/[0-9a-f]{64}\.png',name):continue
        try:source_name(name)
        except ValueError:raise DevelopmentError('Unrecognized source-project package member','PROJECT_PACKAGE')
    temporary=Path(tempfile.mkdtemp(prefix='.gxtxt-import-',dir=project.parent));reserved=None
    try:
        for name,content in sources.items():
            target=temporary/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content);target.chmod(0o644)
        meta=read_project(temporary,_authoring_payload=authoring_payload);files=project_sources(temporary,meta)
        allowed={*files,'project.json','design.gxtxt-viewer','MANUAL.md','manual-assets.json'}
        if any(name not in allowed and not name.startswith('manual-assets/') for name in sources):
            raise DevelopmentError('Package includes undeclared project sources','PROJECT_PACKAGE')
        receipt=json.loads(payload['review/build.json'])
        if not sources_match(temporary,receipt.get('validation',{})) or any(digest(sources[name])!=receipt.get('validation',{}).get(key) for name,key in [('project.json','project_sha256'),('design.gxtxt-viewer','design_sha256')]):
            raise DevelopmentError('Package source does not match its build revision','BINARY_SOURCE_MISMATCH')
        if 'source/SOURCE_MANIFEST.json' in payload and json.loads(payload['source/SOURCE_MANIFEST.json'])!=source_identity(files):
            raise DevelopmentError('Packaged source manifest differs','PROJECT_PACKAGE')
        if source_authoring.pointer(meta) is not None:
            try:meta=source_authoring.import_into(temporary,meta,files,authoring_payload)
            except source_authoring.authoring.AuthoringError as error:raise DevelopmentError(str(error),'SOURCE_NOTES') from error
            write_json(temporary/'project.json',meta)
        project.mkdir();reserved=project.stat().st_ino
        # Replacing only our still-empty reservation publishes the complete
        # project at once. A competing populated directory is never removed.
        if project.stat().st_ino!=reserved or any(project.iterdir()):raise DevelopmentError('Import destination changed','SOURCE_CHANGED')
        os.replace(temporary,project);temporary=None
        grant=enforce_project_write(project);(project/'derived/tmp').mkdir(parents=True,exist_ok=True)
        return dict(status='CREATED',project=str(project),grant=grant,**source_identity(files),package_sha256=digest(package_bytes),compiled_artifact_imported=False)
    finally:
        if temporary is not None:shutil.rmtree(temporary)
        if reserved is not None and project.exists() and project.stat().st_ino==reserved and not any(project.iterdir()):project.rmdir()

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

def workspace_callback_contract(meta, design, source_sha256, source_tree_sha256=None):
    """Presentation-only compatibility, independent of exact runtime guards.

    Components retain declaration ordinals, type, parent, scalar defaults and
    every command/scientific reference. Unknown fields remain significant.
    """
    semantic = workspace_callback_semantics(design)
    project = {key: value for key, value in meta.items() if key not in {'version', 'provenance', 'tests'}}
    content = dict(schema='gxtxt.viewer_workspace_callback_contract.v1', source_sha256=source_sha256, project=project, design=semantic)
    if len(meta.get('source_files',[]))>1:
        if source_tree_sha256 is None:raise DevelopmentError('Multifile callback contract requires the entire source revision','PROJECT_SOURCES')
        content['source_tree_sha256']=source_tree_sha256
    return digest(json.dumps(content, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode())

def _library_browser_scope(raw):
    """Typed declarative data, with the same bounds as public GUI Host admission."""
    try:
        scope = dictionary(raw)
        normalized = {}
        for key, encoded in scope.items():
            if key not in {'library_types', 'record_types', 'library_ids', 'provider_ids', 'source_ids'}:
                raise ValueError('Unsupported Library scope dimension')
            values = list(tkinter.Tcl().splitlist(encoded))
            if len(values) > 64 or len(set(values)) != len(values):
                raise ValueError('Library scope requires at most64 unique IDs per dimension')
            for value in values:
                if not value or any(c in value for c in '\x00\r\n'):
                    raise ValueError('Invalid Library scope identity')
                if key == 'source_ids':
                    if len(value) > 512:
                        raise ValueError('Source identity exceeds512 characters')
                elif not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', value):
                    raise ValueError('Library scope requires stable Manager/schema IDs')
            if values:
                normalized[key] = sorted(values)
        if len(json.dumps(normalized, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) > 32768:
            raise ValueError('Library scope exceeds32 KiB')
        return normalized
    except (ValueError, tkinter.TclError, DevelopmentError) as error:
        raise DevelopmentError(str(error), 'RUNTIME_COMPONENT') from error


def _library_browser_groups(components):
    """Final admission; normal Builder edits may retain incomplete draft groups."""
    groups = {}
    scopes = {}
    for component in components:
        if component['type'] != 'library_browser':
            continue
        properties = dictionary(component['properties'])
        page, group = properties.get('page'), properties.get('group')
        if page not in {'records', 'sources', 'manual'} or not group or not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', group):
            raise DevelopmentError('Library pages require a finite page and stable group', 'RUNTIME_COMPONENT')
        pages = groups.setdefault(group, set())
        if page in pages:
            raise DevelopmentError('Duplicate Library Browser group/page', 'RUNTIME_COMPONENT')
        pages.add(page)
        scope = _library_browser_scope(properties.get('scope', ''))
        if group in scopes and scopes[group] != scope:
            raise DevelopmentError('Library Browser pages require the same group scope', 'RUNTIME_COMPONENT')
        scopes[group] = scope
    if len(groups) > 4 or any(pages != {'records', 'sources', 'manual'} for pages in groups.values()):
        raise DevelopmentError('Declare all three Library Browser pages in each bounded group', 'RUNTIME_COMPONENT')
    return groups


def validate(project):
    if acquisition_project_target(project):
        from gxtxt_acquisition_development_v1 import validate as acquisition_validate
        meta,raw,files,report=acquisition_validate(project,_acquisition_catalog(api_catalog(project)))
        return meta,report,{},report.get('requested',{})
    meta=read_project(project)
    files=project_sources(project,meta)
    report=validate_project_sources(files,project/'derived/tmp')
    report.update(source_identity(files))
    admitted=dictionary(core(project,'validate_design',project/'design.gxtxt-viewer','with_catalog'))
    design=dictionary(admitted['design'])
    if 'PLOT_DATASET_API_v3' in dictionary(design.get('requirements', '')):
        raise DevelopmentError('DEPRECATED_PLOT_API: Builder requirements must use PLOT_DATASET_API_v4','DEPRECATED_PLOT_API')
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Project and Builder design identities differ','PROJECT_INVALID')
    report['design_sha256']=digest((project/'design.gxtxt-viewer').read_bytes())
    report['project_sha256']=digest((project/'project.json').read_bytes())
    report['project_digest_sha256']=project_digest(report)
    report['project_profile']=meta['profile']
    report['workspace_callback_contract_sha256']=workspace_callback_contract(meta,design,report['source_sha256'],report.get('source_tree_sha256'))
    catalog=_describe_api_catalog(admitted['catalog'])
    requested=capability_check(project,meta,catalog,report,design)
    components=[dictionary(value) for value in tkinter.Tcl().splitlist(design['components'])]
    _library_browser_groups(components)
    diagrams=[component for component in components if component['type']=='native2d' and dictionary(component['properties']).get('diagram_catalog')]
    rasters=[component for component in components if component['type']=='native2d' and dictionary(component['properties']).get('source_kind')=='raster']
    numeric_forms=[component for component in components if component['type']=='section' and (dictionary(component['properties']).get('numeric_expression') or dictionary(component['properties']).get('numeric_kind'))]
    tex_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('tex_source')]
    em_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('em_parameters')]
    geometry_forms=[component for component in components if component['type']=='section' and dictionary(component['properties']).get('workbench_parameters')]
    sketch_forms=[component for component in components if component['type']=='cad_sketch']
    native_lifecycle={'get','save'}.issubset(requested.get('NATIVE_WORKSPACE_API_v1',set())) and any(c['type']=='workspace' for c in components)
    if report.get('workspace_hooks') and not native_lifecycle:
        raise DevelopmentError('Workspace hooks require a declared native Workspace lifecycle','CAPABILITY_DENIED')
    for component in components:
        catalog_properties=dictionary(component['properties'])
        if component['type']=='cad_sketch' and not {'cad_sketch_create','cad_sketch_command','cad_sketch_state'}.issubset(requested.get('NATIVE2D_API_v1',set())):
            raise DevelopmentError('Editable Sketch requires explicit public create/command/state lifecycle grants','CAPABILITY_DENIED')
        if component['type']=='section' and catalog_properties.get('workbench_parameters'):
            if not {'activateDocument','guiMount','guiInspect'}.issubset(requested.get('WORKBENCH_3D_API_v1',set())):
                raise DevelopmentError('Editable geometry form requires its explicit canonical Workbench3D lifecycle grants','CAPABILITY_DENIED')
        if component['type']=='section' and catalog_properties.get('em_parameters'):
            if not {'defaultModel','validate','loadModel','saveModel','listModels'}.issubset(requested.get('ELECTROMAGNETIC_SIMULATION_API_v1',set())):
                raise DevelopmentError('Declared EM form requires its explicit existing model/default/validation/discovery grants','CAPABILITY_DENIED')
        if component['type']=='section' and catalog_properties.get('catalog_owner')=='scientific_libraries':
            needed={'libraryCatalogPage','getLibraryCapabilities'}
            if catalog_properties.get('catalog_entries'):needed.add('listLibraryEntries')
            if catalog_properties.get('catalog_entry_filter'):needed.update({'searchLibraryEntries','libraryEntriesPage','getLibraryEntryInfo'})
            actions=dictionary(catalog_properties.get('catalog_actions',''))
            if 'register_external' in actions or 'register_remote' in actions:needed.add('getProviderCapabilities')
            if not needed.issubset(requested.get('SCIENTIFIC_LIBRARY_MANAGER_API_v1',set())):
                raise DevelopmentError('Declared Library catalog lacks its explicit discovery/entry/provider grants','CAPABILITY_DENIED')
        if component['type']=='library_browser':
            if not {'libraryCatalogPage','getLibraryCapabilities'}.issubset(requested.get('SCIENTIFIC_LIBRARY_MANAGER_API_v1',set())):
                raise DevelopmentError('Embedded Library pages require explicit public Library discovery grants','CAPABILITY_DENIED')
        if component['type']=='section' and dictionary(component['properties']).get('scientific_probe_diagram'):
            for api, needed in {'SCIENTIFIC_EXECUTION_API_v1':'circuit_prepare','PLOT_DATASET_API_v4':'widgetCreate','NATIVE2D_VIEWPORT_HOST_v1':'diagram_command'}.items():
                if needed not in requested.get(api,set()):
                    raise DevelopmentError('Declared scientific probe requires its existing scoped capability: '+api+'/'+needed,'CAPABILITY_DENIED')
        if component['type']=='section' and dictionary(component['properties']).get('scientific_sweep_axes'):
            _sweep_grants(requested)
        if component['type'] in {'workspace','history'}:
            if not native_lifecycle and (meta['profile'] not in {'document_view_v1','scientific_view_v1'} or not (diagrams or geometry_forms or sketch_forms or (rasters and 'raster_bind' in requested.get('VIEWER_GUI_HOST_API_v1',set())) or (numeric_forms and 'dataset_expression' in requested.get('NUMERIC_API_v1',set())) or (tex_forms and 'tex_command' in requested.get('VIEWER_GUI_HOST_API_v1',set())) or (em_forms and {'validate','loadModel','saveModel','listModels'}.issubset(requested.get('ELECTROMAGNETIC_SIMULATION_API_v1',set()))))):
                raise DevelopmentError('Canonical lifecycle requires a declared canonical diagram/geometry form or an explicitly granted raster, Numeric, TeX or electromagnetic model form; legacy profiles remain read-only','CAPABILITY_DENIED')
            api,required=(('NATIVE_WORKSPACE_API_v1',{'get','save'}) if native_lifecycle else ('SESSION_WORKSPACE_API_v1',{'create','get','update','list'})) if component['type']=='workspace' else ('SCIENTIFIC_RECIPE_API_v1',{'scientificHistoryViewerRecord','scientificHistoryViewerNavigate'})
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
    # Debug symbols intentionally map to original source paths. Relocation
    # requires fresh symbols rather than reusing paths from another project.
    if debug and result.get('debug_source_root')!=str(project):return None
    if result.get('status') != 'BUILT' or not _artifact_dependencies_match(result.get('build_dependencies'), _artifact_dependencies()):
        return None
    if not sources_match(project,result['validation']):
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
        contract = workspace_callback_contract(meta, design, result['validation']['source_sha256'],result['validation'].get('source_tree_sha256'))
        if contract != result['validation'].get('workspace_callback_contract_sha256'):
            return None
        result = dict(result, validation=dict(result['validation'], project_sha256=project_sha256,
                                             design_sha256=design_sha256),
                      metadata_only_project_update=True,
                      original_build_receipt_sha256=digest(receipt.read_bytes()))
        if 'source_tree_sha256' in result['validation']:
            result['validation']['project_digest_sha256']=project_digest(result['validation'])
    for name, expected in result.get('header_dependencies', {}).items():
        role = _artifact_dependency_role(name)
        path = _artifact_dependency_paths()[role] if role is not None else Path(name)
        if not path.is_file() or digest(path.read_bytes()) != expected:
            return None
    if library.is_symlink() or digest(library.read_bytes()) != result['binary_sha256']:
        return None
    return dict(result, code_generation_invoked=False, artifact_reused=True)

def build(project, debug=False):
    if acquisition_project_target(project):
        if debug:raise DevelopmentError('Acquisition native debugging is not admitted by this target','ACQUISITION_DEBUG_UNAVAILABLE')
        from gxtxt_acquisition_development_v1 import build as acquisition_build
        return acquisition_build(project,_acquisition_catalog(api_catalog(project)))
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
    files=project_sources(project,meta)
    if source_identity(files)['source_tree_sha256']!=report['source_tree_sha256']:
        raise DevelopmentError('Project source changed after admission','SOURCE_CHANGED')
    with tempfile.TemporaryDirectory(prefix='build-',dir=project/'derived/tmp') as temporary:
        stage=Path(temporary)
        for name,content in files.items():
            path=stage/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
        fixed=[*FLAGS,('-O0' if debug else '-O1'),('-g3' if debug else '-g0'),'-fPIC','-fvisibility=hidden','-fno-stack-protector',
               '-ffile-prefix-map='+str(stage)+'='+str(project) if debug else '-ffile-prefix-map='+str(stage)+'=.', '-ffile-prefix-map='+str(DEVELOPMENT)+'=sdk']
        if debug:
            # Clang otherwise omits unused SDK aggregate definitions. GDB can
            # name a const Event reference but cannot inspect its real members.
            fixed.append('-fstandalone-debug')
        units=[name for name in files if name.endswith('.cpp')]
        objects=[stage/('author'+str(index)+'.o') for index in range(len(units))]
        dependency_files=[stage/('author'+str(index)+'.d') for index in range(len(units))]
        commands=[[str(COMPILER),*fixed,'-I'+str(stage),'-I'+str(stage/'include'),'-MD','-MF',str(dep),'-include',str(SDK),'-c',str(stage/name),'-o',str(obj)] for name,obj,dep in zip(units,objects,dependency_files)]
        commands += [
            [str(COMPILER),*fixed,'-MD','-MF',str(stage/'adapter.d'),'-I'+str(SDK.parent),'-c',str(SDK.parent/'trusted_adapter_v1.cpp'),'-o',str(stage/'adapter.o')],
            [str(COMPILER),'-shared','-pthread','-Wl,-z,defs','-Wl,--build-id=none',*[str(obj) for obj in objects],str(stage/'adapter.o'),'-lstdc++','-lm','-o',str(stage/'viewer.so')],
        ]
        logs=[]
        for command in commands:
            code,output,errors=bounded_command(command,stage,30)
            logs.append((output+errors).decode(errors='replace').replace(str(stage),'<controlled-build>'))
            if code:
                result={'status':'BUILD_FAILED','code_generation_invoked':True,'validation':report,'log':'\n'.join(logs)}
                write_json(project/'derived/build.json',result);return result
        if not sources_match(project,report) or any(digest((project/name).read_bytes())!=report[key] for name,key in [('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
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
        if debug:result['debug_source_root']=str(project)
        result['build_dependencies'] = _artifact_dependencies()
        headers = {}
        for dependency_file in [*dependency_files,stage/'adapter.d']:
            import shlex
            dependencies = dependency_file.read_text().replace('\\\n', ' ').split(':', 1)[1]
            for name in shlex.split(dependencies):
                path = Path(name).resolve()
                if path.is_relative_to(stage):
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
    elif operation==49:
        if 'analysis_command' not in requested.get('MODULE_TARGETED_ANALYSIS_API_v1',set()):
            raise DevelopmentError('Targeted Analysis lacks its separate capability','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='section' or not properties.get('analysis_module'):
            raise DevelopmentError('Targeted Analysis needs its declared associated form','RUNTIME_COMPONENT')
        try:packet=json.loads(message.get('text',''))
        except (ValueError,TypeError):raise DevelopmentError('Malformed Analysis command','RUNTIME_VALUE')
        if not isinstance(packet,dict) or set(packet)!={'kind','value'} or packet.get('kind')!='object' or not isinstance(packet['value'],dict):
            raise DevelopmentError('Analysis needs a strict typed command','RUNTIME_VALUE')
        fields=packet['value']
        if set(fields)!={'operation','request'} or not isinstance(fields['operation'],dict) or set(fields['operation'])!={'kind','value'} or fields['operation'].get('kind')!='text' or fields['request']!={'kind':'object','value':{}}:
            raise DevelopmentError('Analysis command carries no arbitrary request or paths','RUNTIME_VALUE')
        action=fields['operation'].get('value')
        if action not in POLICY['restricted_native_clients']['analysis_command']['finite_operations']:
            raise DevelopmentError('Unknown finite Analysis command','RUNTIME_VALUE')
        operations.append({'operation':'analysis_command','component':component['id'],'value':action})
    elif operation==48:
        if 'comparison_command' not in requested.get('COMPARISON_PLOT_API_v1',set()):
            raise DevelopmentError('Comparison lacks its explicit admitted capability','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='section' or not properties.get('comparison_target'):
            raise DevelopmentError('Comparison needs its declared associated form','RUNTIME_COMPONENT')
        target=next((c for c in by_index.values() if c['id']==properties['comparison_target']),None)
        if target is None or target['type']!='plot' or dictionary(target['properties']).get('comparison_form')!=component['id']:
            raise DevelopmentError('Comparison Plot association is not reciprocal','RUNTIME_COMPONENT')
        try:packet=json.loads(message.get('text',''))
        except (ValueError,TypeError):raise DevelopmentError('Malformed comparison command','RUNTIME_VALUE')
        if not isinstance(packet,dict) or set(packet)!={'kind','value'} or packet.get('kind')!='object' or not isinstance(packet['value'],dict):
            raise DevelopmentError('Comparison needs a strict typed command','RUNTIME_VALUE')
        fields=packet['value']
        if set(fields)!={'operation','request'} or not isinstance(fields['operation'],dict) or set(fields['operation'])!={'kind','value'} or fields['operation'].get('kind')!='text' or fields['request']!={'kind':'object','value':{}}:
            raise DevelopmentError('Comparison command carries no arbitrary request or samples','RUNTIME_VALUE')
        action=fields['operation'].get('value')
        if action not in POLICY['restricted_native_clients']['comparison_command']['finite_operations']:
            raise DevelopmentError('Unknown finite comparison command','RUNTIME_VALUE')
        if 'widgetCreate' not in requested.get('PLOT_DATASET_API_v4',set()):
            raise DevelopmentError('Comparison lacks its native Plot capability','CAPABILITY_DENIED')
        if action=='prepare' and 'comparison_curves' not in requested.get('NUMERIC_API_v1',set()):
            raise DevelopmentError('Comparison lacks its exact Numeric capability','CAPABILITY_DENIED')
        if action in {'add_library','add_browser','add_opened'} and not {'getLibraryInfo','getLibraryEntryInfo','readLibraryEntry'}.issubset(requested.get('SCIENTIFIC_LIBRARY_MANAGER_API_v1',set())):
            raise DevelopmentError('Read-only Library consultation is not authorized','CAPABILITY_DENIED')
        operations.append({'operation':'comparison_command','component':component['id'],'value':action})
    elif operation in {45,46,47}:
        method={45:'script_library_command',46:'scientific_preview_command',47:'scientific_frame_bind'}[operation]
        api='SCRIPT_LIBRARY_API_v1' if operation==45 else 'PREVIEW_COMPONENT_GUI_API_v1'
        if method not in requested.get(api,set()):raise DevelopmentError('Typed client lacks its explicit public operation capability','CAPABILITY_DENIED')
        property_name='script_library_components' if operation==45 else 'scientific_preview_components'
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='section' or property_name not in properties:
            raise DevelopmentError('Typed client requires its declared component association form','RUNTIME_COMPONENT')
        try:associated=dictionary(properties[property_name])
        except (ValueError,tkinter.TclError):raise DevelopmentError('Malformed typed client component association','RUNTIME_COMPONENT')
        declared={item['id']:item for item in by_index.values()}
        if not associated or len(associated)>64 or any(not re.fullmatch(r'[a-z][a-z0-9_]{0,47}',role) or target not in declared for role,target in associated.items()):
            raise DevelopmentError('Typed client association refers to undeclared components','RUNTIME_COMPONENT')
        if operation==47:
            other=by_index.get(int(left)) if left==int(left) else None
            if right!=0 or message.get('text','') or other is None or other['type']!='panel' or associated.get('frame_view')!=other['id']:
                raise DevelopmentError('Frame binding requires its exact declared canonical plane panel','RUNTIME_COMPONENT')
            operations.append({'operation':method,'component':component['id'],'value':other['id']})
        else:
            if left!=0 or right!=0:raise DevelopmentError('Typed client numeric envelope fields must be zero','RUNTIME_VALUE')
            raw=message.get('text','')
            if not isinstance(raw,str) or len(raw.encode('utf-8'))>49152:raise DevelopmentError('Typed client request exceeds 48 KiB','RUNTIME_VALUE')
            def unique_object(pairs):
                result={}
                for key,value in pairs:
                    if key in result:raise ValueError('Duplicate typed client field')
                    result[key]=value
                return result
            try:envelope=json.loads(raw,object_pairs_hook=unique_object)
            except (ValueError,TypeError):raise DevelopmentError('Typed client request must be strict JSON','RUNTIME_VALUE')
            nodes=[0]
            def decode_client(item,depth=0):
                nodes[0]+=1
                if depth>64 or nodes[0]>8192 or not isinstance(item,dict) or set(item)!={'kind','value'}:raise DevelopmentError('Invalid bounded typed client value','RUNTIME_VALUE')
                kind,value=item['kind'],item['value']
                if kind=='null':valid=value is None
                elif kind=='text':valid=isinstance(value,str) and '\0' not in value
                elif kind=='bool':valid=type(value) is bool
                elif kind=='int':valid=type(value) is int and -(2**63)<=value<2**63
                elif kind=='real':valid=type(value) in (int,float) and math.isfinite(value)
                elif kind=='array':
                    if not isinstance(value,list):raise DevelopmentError('Typed client array mismatch','RUNTIME_VALUE')
                    return [decode_client(child,depth+1) for child in value]
                elif kind=='object':
                    if not isinstance(value,dict) or any(not isinstance(key,str) or '\0' in key for key in value):raise DevelopmentError('Typed client object mismatch','RUNTIME_VALUE')
                    return {key:decode_client(child,depth+1) for key,child in value.items()}
                else:valid=False
                if not valid:raise DevelopmentError('Typed client value does not match its kind','RUNTIME_VALUE')
                return value
            decoded=decode_client(envelope)
            if not isinstance(decoded,dict) or set(decoded)!={'operation','request'} or not isinstance(decoded['operation'],str) or not isinstance(decoded['request'],dict):raise DevelopmentError('Typed client requires operation/request object','RUNTIME_VALUE')
            action=decoded['operation'];request=decoded['request']
            def exact_fields(required,optional=()):
                if set(request)-set(required)-set(optional) or not set(required).issubset(request):raise DevelopmentError('Unknown/missing finite client request fields','RUNTIME_VALUE')
            def integer_field(name,minimum=0,maximum=2**63-1):
                if type(request.get(name)) is not int or not minimum<=request[name]<=maximum:raise DevelopmentError('Client integer field exceeds its exact bound','RUNTIME_VALUE')
            def text_field(name,maximum=4096,empty=False):
                value=request.get(name)
                if not isinstance(value,str) or '\0' in value or (not empty and not value) or len(value.encode('utf-8'))>maximum:raise DevelopmentError('Client identity/text field is invalid','RUNTIME_VALUE')
            def source_identity(draft=False):
                integer_field('expected_revision',0 if draft else 1)
                text_field('expected_sha256',64,True)
                sha=request['expected_sha256']
                if sha and not re.fullmatch(r'[a-f0-9]{64}',sha):raise DevelopmentError('Exact source SHA-256 required','RUNTIME_VALUE')
                if not draft or request['expected_revision']:
                    if not sha:raise DevelopmentError('Saved source requires its exact SHA-256','RUNTIME_VALUE')
                elif sha:raise DevelopmentError('New source draft must have empty baseline SHA','RUNTIME_VALUE')
                if draft:text_field('draft_token')
                else:
                    text_field('reference')
                    if not re.fullmatch(r'(user|session):[A-Za-z][A-Za-z0-9_.-]*',request['reference']):raise DevelopmentError('Qualified Script reference required','RUNTIME_VALUE')
            if operation==45:
                registry=set(POLICY['restricted_native_clients']['script_library_command']['finite_operations'])
                if action not in registry:raise DevelopmentError('Unknown finite Script Library operation','RUNTIME_VALUE')
                if action=='list':
                    exact_fields(('scope','language','query','offset','limit'));integer_field('offset');integer_field('limit',1,100);text_field('query',1024,True)
                    if request['scope'] not in ('all','user','session') or request['language'] not in ('all','python','octave') or len(request['query'])>256:raise DevelopmentError('Invalid Script Library filter','RUNTIME_VALUE')
                elif action in {'new_script','new_project'}:
                    exact_fields(('scope','language'))
                    if request['scope'] not in ('user','session') or request['language'] not in ('python','octave'):raise DevelopmentError('Invalid Script scope/language','RUNTIME_VALUE')
                elif action=='select':
                    exact_fields(('reference','expected_revision','expected_sha256'),('review_owner',));source_identity()
                    if 'review_owner' in request and type(request['review_owner']) is not bool:raise DevelopmentError('Owner review flag must be an actual Boolean','RUNTIME_VALUE')
                elif action in {'copy_record','assign_session','open_workspace','run_review','export','delete'}:
                    exact_fields(('reference','expected_revision','expected_sha256'));source_identity()
                elif action=='save':
                    exact_fields(('draft_token','expected_revision','expected_sha256'));source_identity(True)
                elif action=='source_select':
                    exact_fields(('reference','relative_file','expected_revision','expected_sha256'),('expected_file_sha256',));source_identity();text_field('relative_file',1024)
                    name=request['relative_file']
                    if name.startswith('/') or '\\' in name or any(part in {'','.','..'} for part in name.split('/')) or re.search(r'[\x00-\x1f]',name):raise DevelopmentError('Source file must be an admitted relative roster name','RUNTIME_VALUE')
                    if 'expected_file_sha256' in request and (not isinstance(request['expected_file_sha256'],str) or not re.fullmatch(r'[a-f0-9]{64}',request['expected_file_sha256'])):raise DevelopmentError('Exact file SHA-256 required','RUNTIME_VALUE')
                elif action in {'import_script','import_project'}:
                    exact_fields(('scope',))
                    if request['scope'] not in ('user','session'):raise DevelopmentError('Invalid import scope','RUNTIME_VALUE')
                else:exact_fields(())
            else:
                if action not in {'discover','page','metadata','source'}:raise DevelopmentError('Unknown finite scientific Preview operation','RUNTIME_VALUE')
                if action in {'discover','metadata','source'}:
                    exact_fields((),('offset','limit'))
                    if 'offset' in request:integer_field('offset')
                    if 'limit' in request:integer_field('limit',1,64 if action=='discover' else 50)
                else:
                    exact_fields(('variable_id','starts','counts'));text_field('variable_id',256)
                    starts=request['starts'];counts=request['counts']
                    if not isinstance(starts,list) or not isinstance(counts,list) or len(starts)!=len(counts) or len(starts)>64 or any(type(x) is not int or not 0<=x<2**63 for x in starts+counts):raise DevelopmentError('Exact bounded rank-shaped page required','RUNTIME_VALUE')
                    cells=0 if 0 in counts else 1
                    for count in counts:
                        cells*=count
                        if cells>512:raise DevelopmentError('Scientific page exceeds 512 cells','RUNTIME_VALUE')
            # Deferred owning-thread intent only. Live Session/source/window,
            # actual rank, variable identity and all Registry authority stay CORE.
            operations.append({'operation':method,'component':component['id'],'value':{'command':action,'request':envelope['value']['request']}})
    elif operation in {42,43,44}:
        method,api,grant={42:('review','DATASET_GROUP_API_v1','datasetGroupProducerReviewV1'),
                          43:('create','DATASET_GROUP_API_v1','datasetGroupProducerCreateV1'),
                          44:('publish_batch','DATASET_PUBLICATION_API_v2','datasetProducerPublishBatchV1')}[operation]
        if grant not in requested.get(api,set()):raise DevelopmentError('Dataset producer operation lacks its explicit capability','CAPABILITY_DENIED')
        raw=message.get('text','')
        if len(raw.encode('utf-8'))>49152:raise DevelopmentError('Dataset producer request exceeds 48 KiB; opaque revisions are never truncated','RUNTIME_VALUE')
        try:value=json.loads(raw)
        except (ValueError,TypeError):raise DevelopmentError('Dataset producer request requires a typed value','RUNTIME_VALUE')
        nodes=[0]
        def validate_producer(item,depth=0):
            nodes[0]+=1
            if depth>64 or nodes[0]>8192 or not isinstance(item,dict) or set(item)!={'kind','value'}:raise DevelopmentError('Invalid bounded producer value','RUNTIME_VALUE')
            kind,data=item['kind'],item['value']
            if kind=='null':valid=data is None
            elif kind=='text':valid=isinstance(data,str) and '\0' not in data
            elif kind=='bool':valid=type(data) is bool
            elif kind=='int':valid=type(data) is int and -(2**63)<=data<2**63
            elif kind=='real':valid=type(data) in (int,float) and math.isfinite(data)
            elif kind=='object':
                valid=isinstance(data,dict) and all(isinstance(k,str) and '\0' not in k for k in data)
                if valid:
                    for child in data.values():validate_producer(child,depth+1)
            elif kind=='array':
                valid=isinstance(data,list)
                if valid:
                    for child in data:validate_producer(child,depth+1)
            else:valid=False
            if not valid:raise DevelopmentError('Producer value does not match its declared kind','RUNTIME_VALUE')
        validate_producer(value)
        if method=='review':
            if value['kind']!='array' or len(value['value'])>64 or any(x['kind']!='text' for x in value['value']):raise DevelopmentError('Producer review requires 0..64 Dataset IDs','RUNTIME_VALUE')
        elif method=='create':
            if value['kind']!='object' or set(value['value'])!={'definition','review'}:raise DevelopmentError('Producer Create requires definition and full review','RUNTIME_VALUE')
        else:
            if value['kind']!='object' or set(value['value'])-{'session_token','outputs','dataset_group'} or not {'session_token','outputs'}.issubset(value['value']):raise DevelopmentError('Producer batch requires Session token and outputs','RUNTIME_VALUE')
            outputs=value['value']['outputs']
            if outputs['kind']!='array' or not 1<=len(outputs['value'])<=64:raise DevelopmentError('Producer batch requires1..64 real outputs','RUNTIME_VALUE')
            if 'dataset_group' in value['value'] and 'datasetGroupProducerCreateV1' not in requested.get('DATASET_GROUP_API_v1',set()):raise DevelopmentError('Optional Group creation lacks its explicit capability','CAPABILITY_DENIED')
        operations.append({'operation':'dataset_producer_command','component':'','value':{'command':method,'value':value}})
    elif operation==40:
        command,separator,raw=message.get('text','').partition('\n')
        if not separator or command not in {'set_property','set_state','save','save_as','rename','open','close'}:
            raise DevelopmentError('Unknown typed Viewer Workspace command','RUNTIME_VALUE')
        if command not in requested.get('NATIVE_WORKSPACE_API_v1',set()) or not any(item['type']=='workspace' for item in by_index.values()):
            raise DevelopmentError('Viewer Workspace command requires its explicit grant and declared Workspace component','CAPABILITY_DENIED')
        try:value=json.loads(raw)
        except (ValueError,TypeError):raise DevelopmentError('Workspace command requires a typed value','RUNTIME_VALUE')
        def validate(value,depth=0):
            if depth>64 or not isinstance(value,dict) or set(value)!={'kind','value'}:raise DevelopmentError('Invalid typed Workspace value','RUNTIME_VALUE')
            kind,data=value['kind'],value['value']
            if kind=='null':valid=data is None
            elif kind=='text':valid=isinstance(data,str)
            elif kind=='bool':valid=type(data) is bool
            elif kind=='int':valid=type(data) is int and -(2**63)<=data<2**63
            elif kind=='real':valid=type(data) in (int,float) and math.isfinite(data)
            elif kind in {'object','resource'}:
                valid=isinstance(data,dict) and all(isinstance(k,str) and '\0' not in k for k in data)
                if valid:
                    for child in data.values():validate(child,depth+1)
            elif kind=='array':
                valid=isinstance(data,list)
                if valid:
                    for child in data:validate(child,depth+1)
            else:valid=False
            if not valid:raise DevelopmentError('Workspace value does not match its declared kind','RUNTIME_VALUE')
        validate(value)
        operations.append({'operation':'workspace_command','component':'','value':{'command':command,'value':value}})
    elif operation in {36,37,38,39}:
        method={36:'cad_command',37:'diagnostics_command',38:'text_runs',39:'table_set'}[operation]
        if method not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Typed presentation operation lacks its explicit GUI Host grant','CAPABILITY_DENIED')
        if component is None: raise DevelopmentError('Typed operation requires a declared component','RUNTIME_COMPONENT')
        value=message.get('text','')
        if operation==36:
            actions={'select','rectangle_selection','translate','rotate','mirror','pan','point','line','construction_line','path','polyline','spline','rectangle','circle','arc','ellipse','quadratic_bezier','cubic_bezier','join_points','join_path','compound','separate','split_path','split_composition','dimension','horizontal','vertical','coincident','parallel','perpendicular','tangent','equal_length','equal_radius','fixed','finish','cancel','fit','undo','redo','save'}
            if component['type']!='cad_sketch' or value not in actions:
                raise DevelopmentError('CAD command requires its declared Sketch and a supported action ID','RUNTIME_COMPONENT')
            if 'cad_sketch_command' not in requested.get('NATIVE2D_API_v1',set()):
                raise DevelopmentError('CAD command lacks the shared Sketch service grant','CAPABILITY_DENIED')
        elif operation==37:
            props=dictionary(component['properties'])
            if component['type']!='section' or props.get('diagnostics_owner')!='stderr':
                raise DevelopmentError('Diagnostics requires a declared diagnostic consultation form','RUNTIME_COMPONENT')
            action,separator,payload=value.partition('\n')
            if not separator or action not in {'info','status','meta','read','export','copy','subscribe','unsubscribe','cancel'}:
                raise DevelopmentError('Unsupported diagnostic consultation operation','RUNTIME_VALUE')
            needed={'copy':'read','subscribe':'subscribe','unsubscribe':'unsubscribe'}.get(action,action)
            if needed not in requested.get('STDERR_DIAGNOSTICS_API_v1',set()):
                raise DevelopmentError('Diagnostic operation lacks its exact consultation grant','CAPABILITY_DENIED')
            try: body=json.loads(payload)
            except (ValueError,TypeError): raise DevelopmentError('Diagnostic request must be a bounded JSON object','RUNTIME_VALUE')
            allowed={'cursor','limit','max_bytes','record_ids','request_id','follow'}
            if not isinstance(body,dict) or set(body)-allowed or len(payload.encode('utf-8'))>65536:
                raise DevelopmentError('Diagnostic request has unsupported fields or exceeds bounds','RUNTIME_VALUE')
            if 'record_ids' in body and (not isinstance(body['record_ids'],list) or len(body['record_ids'])>4096 or any(not isinstance(i,str) or len(i)>128 for i in body['record_ids'])):
                raise DevelopmentError('Diagnostic record selection exceeds bounds','RUNTIME_VALUE')
            for key in ('cursor','request_id'):
                if key in body and (not isinstance(body[key],str) or len(body[key])>4096): raise DevelopmentError('Diagnostic cursor/token exceeds bounds','RUNTIME_VALUE')
            for key,maximum in (('limit',4096 if action=='export' else 256),('max_bytes',8388608 if action=='export' else 1048576)):
                if key in body and (type(body[key]) is not int or not 1<=body[key]<=maximum): raise DevelopmentError('Diagnostic page limit exceeds bounds','RUNTIME_VALUE')
            if 'follow' in body and type(body['follow']) is not bool: raise DevelopmentError('Diagnostic follow must be boolean','RUNTIME_VALUE')
            value={'command':action,'request':body}
        elif operation==38:
            if component['type'] not in {'log','text'}: raise DevelopmentError('Styled output requires a declared read-only text/log component','RUNTIME_COMPONENT')
            try: runs=json.loads(value)
            except (ValueError,TypeError): raise DevelopmentError('Styled output must be JSON','RUNTIME_VALUE')
            if not isinstance(runs,dict) or set(runs)-{'replace','runs','autoscroll'} or not isinstance(runs.get('runs'),list) or len(runs['runs'])>512:
                raise DevelopmentError('Styled output exceeds its typed shape','RUNTIME_VALUE')
            for row in runs['runs']:
                if not isinstance(row,dict) or set(row)-{'text','style'} or not isinstance(row.get('text'),str) or row.get('style','normal') not in {'normal','muted','info','warning','error','heading','match'}:
                    raise DevelopmentError('Unsupported text run or presentation style','RUNTIME_VALUE')
            for key in ('replace','autoscroll'):
                if key in runs and type(runs[key]) is not bool: raise DevelopmentError('Text presentation flags must be boolean','RUNTIME_VALUE')
            value=runs
        else:
            if component['type']!='table': raise DevelopmentError('Table output requires a declared read-only table','RUNTIME_COMPONENT')
            try: rows=json.loads(value)
            except (ValueError,TypeError): raise DevelopmentError('Table output must be JSON','RUNTIME_VALUE')
            if not isinstance(rows,list) or len(rows)>1000 or any(not isinstance(row,list) or len(row)>32 or any(not isinstance(cell,str) or len(cell)>4096 for cell in row) for row in rows):
                raise DevelopmentError('Table rows exceed the typed page limits','RUNTIME_VALUE')
            value=rows
        operations.append({'operation':method,'component':component['id'],'value':value})
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
                'working_unit_form','working_plane_form','publish_dataset_form','sketch_create','sketch_open','sketch_close'):
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
            action_grants={'open':'openLibraryViewer','entry_open':'openLibraryViewer','entry_search':'searchLibraryEntries','entry_next':'libraryEntriesPage','entry_previous':'libraryEntriesPage','entry_info':'getLibraryEntryInfo','verify':'verifyLibrary','install':'installLibrary','update':'updateLibrary','remove':'removeLibrary','register_external':'registerLibrary','register_remote':'registerLibrary','unregister':'unregisterLibrary','extra_action':'invokeLibraryAction','browse_records':'getLibraryCapabilities','browse_sources':'getLibraryCapabilities','browse_manual':'getLibraryCapabilities'}
            if action not in action_grants or action_grants[action] not in grants:
                raise DevelopmentError('Catalog action lacks its exact public manager grant','CAPABILITY_DENIED')
            if action.startswith('browse_'):
                group=properties.get('catalog_browser_group')
                groups=_library_browser_groups(by_index.values())
                if not group or group not in groups:
                    raise DevelopmentError('Library page focus requires its complete declared embedded group','RUNTIME_COMPONENT')
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
    elif operation==41:
        if 'document_command' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Document command requires its explicit public GUI Host grant','CAPABILITY_DENIED')
        properties=dictionary(component['properties']) if component is not None else {}
        if component is None or component['type']!='document' or properties.get('kind') not in {'markdown','uml'}:
            raise DevelopmentError('Document command requires a declared Markdown or UML document','RUNTIME_COMPONENT')
        value=message.get('text','')
        readonly={'zoom_in','zoom_out','zoom_reset','open','render','find','copy','select_all','view_source','view_rendered','view_outline','view_properties','view_resources','reset_layout'}
        editable={'new','save_existing','publish_new','undo','redo','replace','cut','paste','heading1','heading2','heading3','bold','italic','inline_code','code_block','bullet_list','numbered_list','table','link','quote','rule','color','insert_image'}
        if properties.get('kind')=='uml':
            readonly={'render','open','find','copy','select_all','zoom_in','zoom_out','zoom_reset','fit','view_source','view_diagram','view_outline','view_properties','view_diagnostics','reset_layout','export_source','export_png','export_svg'}
            editable={'new','new_sequence','save_existing','publish_new','undo','redo','replace','cut','paste','add_class','add_interface','add_participant','add_actor','add_member','add_relation','add_message','add_frame','edit_selected','delete_selected','message_up','message_down','auto_layout'}
            required={'umlDocumentRead','umlDocumentParse','umlDocumentLayout'}
            if value in editable:required.add('umlDocumentEdit')
            if value in {'save_existing','publish_new'}:required.add('umlDocumentWrite')
            if value.startswith('export_'):required.add('umlDocumentExport')
            if not required.issubset(requested.get('UML_DOCUMENT_API_v1',set())):raise DevelopmentError('UML command lacks its explicit public operation grant','CAPABILITY_DENIED')
        if value not in readonly|editable:
            raise DevelopmentError('Unknown finite document command','RUNTIME_VALUE')
        if value in editable and properties.get('mode','read_only')!='editable':
            raise DevelopmentError('Document is read-only','CAPABILITY_DENIED')
        operations.append({'operation':'document_command','component':component['id'],'value':value})
    elif operation==26:
        if 'document_bind' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
            raise DevelopmentError('Read-only document binding is not requested','CAPABILITY_DENIED')
        other=by_index.get(int(left)) if left==int(left) else None
        if component is None or component['type']!='document' or other is None or other['type']!='dataset_selector':
            raise DevelopmentError('Document binding needs declared document and Dataset selector','RUNTIME_COMPONENT')
        kind=dictionary(component['properties']).get('kind')
        if kind not in {'html','pdf','code','table','markdown','uml'} or dictionary(other['properties']).get('content_kind')!=kind:
            raise DevelopmentError('Document selector content_kind must match document kind','RUNTIME_COMPONENT')
        if kind=='uml' and not {'umlDocumentRead','umlDocumentParse','umlDocumentLayout'}.issubset(requested.get('UML_DOCUMENT_API_v1',set())):raise DevelopmentError('UML binding lacks explicit Read/Parse/Layout operations','CAPABILITY_DENIED')
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
    if not sources_match(source_project,validation) or any(digest((source_project/name).read_bytes())!=validation[key] for name,key in [('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]):
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
    operations=[];numeric=[];output_bytes=0;typed_output_bytes=0;deadline=time.monotonic()+POLICY['process_timeout_seconds']
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
                line=process.stdout.readline(197634)
                if not line: break
                frame_bytes=len(line.encode('utf-8'))
                if not line.endswith('\n') or frame_bytes>197633:raise DevelopmentError('Native output frame exceeds its bounded envelope','RUNTIME_OUTPUT')
                message=json.loads(line)
                if not isinstance(message,dict):raise DevelopmentError('Native output frame requires an object','RUNTIME_OUTPUT')
                if message.get('operation') in {42,43,44,45,46,48,49}:
                    typed_output_bytes+=frame_bytes
                    if typed_output_bytes>64*197633:raise DevelopmentError('Typed native output exceeds its 64-frame budget','RUNTIME_OUTPUT')
                else:
                    output_bytes+=frame_bytes
                    if output_bytes>65536:raise DevelopmentError('Native output exceeds 64 KiB','RUNTIME_OUTPUT')
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
                result.update({key:validation[key] for key in ('source_manifest','source_tree_sha256') if key in validation})
        except Exception as error:
            result={'status':'TIMED_OUT' if time.monotonic()>=deadline else 'FAILED','error':str(error),'code':getattr(error,'code','RUNTIME_ERROR'),'operations':[],'state':state}
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
            process.wait(timeout=5)
            ACTIVE_PROCESSES.discard(process.pid)
            process.stdin.close();process.stdout.close()
        if result['status']=='COMPLETED' and (not sources_match(source_project,validation) or any(digest((source_project/name).read_bytes())!=validation[key] for name,key in [('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')])):
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
    if not sources_match(project,report):
        raise DevelopmentError('Viewer project source tree differs from its compiled artifact','BINARY_SOURCE_MISMATCH')
    for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]:
        if digest((project/name).read_bytes())!=report[key]:
            raise DevelopmentError('Viewer source/interface differs from its compiled artifact; install a matching build', 'BINARY_SOURCE_MISMATCH')
    if installed:
        installed_source_manifest(project,report)
        _installed_sdk_compatible(project.parent,built)
    else:
        for path,key in [(SDK,'sdk_sha256'),(DEVELOPMENT/'policy_v1.json','policy_sha256')]:
            if digest(path.read_bytes())!=report[key]:
                raise DevelopmentError('Development artifact dependencies changed; build the current version','BINARY_INCOMPATIBLE')
        if digest((SDK.parent/'trusted_adapter_v1.cpp').read_bytes())!=built['adapter_sha256']:
            raise DevelopmentError('Development adapter changed; build the current version','BINARY_INCOMPATIBLE')
    # Cold metadata admission loads the complete host/catalog before validating
    # the inert design. Leave room for that work within the existing 30-second
    # outer admission and its separate 5-second native probe. Scalar requests
    # retain their shorter deadline; timeout still kills/reaps the owned group.
    admitted=dictionary(core(work,'runtime_design',project/'design.gxtxt-viewer',timeout=20))
    design=dictionary(admitted['design'])
    design['_runtime_diagram_tools']={key:list(tkinter.Tcl().splitlist(value)) for key,value in dictionary(admitted['diagram_tools']).items()}
    if design['module_id']!=meta['module_id'] or design['version']!=meta['version']:
        raise DevelopmentError('Compiled Viewer interface and module identity differ','BINARY_INCOMPATIBLE')
    requested=capability_check(work,meta,_describe_api_catalog(admitted['catalog']),report,design)
    if installed and 'workspace_callback_contract_sha256' not in report:
        # Legacy SDK-v1 packages predate the presentation-compatible Workspace
        # receipt. Derive it only after exact packaged source/interface, native
        # ABI and current capability admission; never rewrite the build receipt.
        # Runtime-only projections are not part of the authored interface.
        report['workspace_callback_contract_sha256']=workspace_callback_contract(
            meta,dictionary(admitted['design']),report['source_sha256'],report.get('source_tree_sha256'))
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
    if acquisition_project_target(root/'source'):
        from gxtxt_acquisition_development_v1 import installed_inspect as acquisition_inspect
        (work/'derived/tmp').mkdir(parents=True,exist_ok=True)
        return acquisition_inspect(root,work,_acquisition_catalog(api_catalog(work)))
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
    installed_source_manifest(root/'source',report)
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
    if acquisition_project_target(project):raise DevelopmentError('Acquisition Test uses the admitted CORE source/buffer request, not a Viewer Preview','ACQUISITION_MANAGED_REQUEST_REQUIRED')
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
    from gxtxt_viewer_native_worker import main as native_event, route_native_output, apply_runtime_limits, disable_native_stderr_capture, native_stderr_capture_active
    record=json.loads((work/'derived/compiled-runtime.json').read_text())
    if record.get('schema')!='gxtxt.compiled_viewer_runtime.v1' or record['root']!=str(root.resolve()):
        raise DevelopmentError('Compiled runtime allocation belongs to another package','RUNTIME_LIFETIME')
    if record.get('kind')=='development':check_project_root(root)
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
        if not sources_match(source_directory,report):
            raise DevelopmentError('Viewer project source tree changed during this lifetime','SOURCE_CHANGED')
        if record['kind']=='installed':installed_source_manifest(source_directory,report)
        for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')]:
            if digest((source_directory/name).read_bytes())!=report[key]:
                raise DevelopmentError('Installed Viewer source/interface changed during this lifetime','SOURCE_CHANGED')
        if _runtime_contract()!=record['runtime_contract']:
            raise DevelopmentError('Viewer SDK/adapter compatibility changed during this lifetime','BINARY_INCOMPATIBLE')
    native_log=work/'derived/native-output.log'
    # This trusted CORE capability maps only the existing global counter page.
    # Open it before the author-write grant; widening that grant to /dev/shm
    # would expose unrelated resources. Author code and the drain thread still
    # execute only AFTER the unchanged project-write restriction is installed.
    from gxtxt_stderr_diagnostics import optional_producer
    capture_producer=optional_producer()
    if record.get('kind')=='development':
        try:enforce_project_write(root)
        except Exception:
            if capture_producer is not None:capture_producer.close()
            raise
    # Trusted public Numeric execution must not inherit native author limits.
    # This conditional transport calls the exact original broker/core owner;
    # its context manager and existing supervisor drain every nested group.
    from contextlib import nullcontext
    from gxtxt_viewer_scalar_broker import ScalarBroker
    scalar_grants=requested.get('NUMERIC_API_v1',set()) & {'array_binary.add','array_unary.sqrt','array_unary.exp'}
    try:scalar_context=ScalarBroker(work,source_directory,report,scalar_grants,project_environment(work),ACTIVE_PROCESSES) if scalar_grants else nullcontext(None)
    except BaseException:
        if capture_producer is not None:capture_producer.close()
        raise
    with scalar_context as scalar_broker:
        protocol=route_native_output(native_log,dict(module_id=record['meta']['module_id'],viewer_id=record['design']['provider_id']),capture_producer,True)
        def send(value):
            print(base64.b64encode(tcl_result(value).encode('utf-8')).decode('ascii'),file=protocol,flush=True)
        unchanged()
        apply_runtime_limits()
        loaded=ctypes.CDLL(str(library))
        send(dict(ok=True,result=dict(status='READY',library=str(library),binary_sha256=built['binary_sha256'],pid=os.getpid(),scalar_broker_pid=(scalar_broker.child.pid if scalar_broker is not None else 0),stderr_diagnostics_active=native_stderr_capture_active())))
        while True:
            line=sys.stdin.readline(2097153)
            if not line:break
            try:
                if len(line.encode('utf-8'))>2097152:raise DevelopmentError('Compiled event exceeds 2 MiB bound','RUNTIME_EVENT')
                payload=json.loads(line)
                if payload=={'control':'diagnostics_stop'}:
                    # CORE-only finite lifecycle message, not a Viewer capability.
                    # No response enters the ordinary event/reply stream.
                    disable_native_stderr_capture();continue
                event=payload['event'];state=payload['state']
                if set(payload)-{'event','state','context','workspace_hook'} or payload.get('workspace_hook','committed') not in {'committed','restore'} or not {'event','state'}.issubset(payload) or set(event)!={'kind','component','value'} or type(event['kind']) is not int or event['kind'] not in range(6) or type(event['component']) is not int or event['component'] not in {0,*components}:
                    raise DevelopmentError('Invalid typed compiled event','RUNTIME_EVENT')
                finite(event['value'])
                if set(state)!={'values','counter'} or len(state['values'])!=16 or type(state['counter']) is not int or not 0<=state['counter']<2**32:
                    raise DevelopmentError('Invalid compiled state','RUNTIME_STATE')
                for value in state['values']:finite(value)
                unchanged();operations=[];numeric=[];deadline=time.monotonic()+POLICY['process_timeout_seconds']
                def broker(message):
                    response,ui,math_receipts=(scalar_broker.call(message,deadline) if scalar_broker is not None and message['operation'] in {4,6,7} else broker_message(work,message,components,requested,deadline,design.get('_runtime_diagram_tools')))
                    operations.extend(ui);numeric.extend(math_receipts)
                    return response
                context=payload.get('context',{})
                if not isinstance(context,dict):raise DevelopmentError('Compiled context requires an object','RUNTIME_EVENT')
                if ('inputs' in context or 'data' in context) and 'value_get' not in requested.get('VIEWER_GUI_HOST_API_v1',set()):
                    raise DevelopmentError('Typed input context is not requested','CAPABILITY_DENIED')
                if 'workspace' in context and 'get' not in requested.get('NATIVE_WORKSPACE_API_v1',set()):
                    raise DevelopmentError('Workspace snapshot context is not requested','CAPABILITY_DENIED')
                if 'producer' in context and 'datasetGroupProducerReviewV1' not in requested.get('DATASET_GROUP_API_v1',set()):
                    raise DevelopmentError('Producer receipt context lacks its explicit review grant','CAPABILITY_DENIED')
                for key,api,grant in (('script_library_result','SCRIPT_LIBRARY_API_v1','script_library_command'),('scientific_preview_result','PREVIEW_COMPONENT_GUI_API_v1','scientific_preview_command'),('comparison_result','COMPARISON_PLOT_API_v1','comparison_command'),('analysis_result','MODULE_TARGETED_ANALYSIS_API_v1','analysis_command')):
                    if key not in context:continue
                    if grant not in requested.get(api,set()):raise DevelopmentError('Typed client receipt lacks its explicit public capability','CAPABILITY_DENIED')
                    if key=='scientific_preview_result' and design.get('target','viewer')!='preview':raise DevelopmentError('Scientific receipt requires an actual Preview design','CAPABILITY_DENIED')
                    value=context[key]
                    if not isinstance(value,dict) or len(json.dumps(value,ensure_ascii=False,allow_nan=False,separators=(',',':')).encode('utf-8'))>49152:raise DevelopmentError('Typed client receipt exceeds its separate 48 KiB bound','RUNTIME_VALUE')
                outcome=native_event(dict(library=str(library),binary_sha256=built['binary_sha256'],event=event,state=state,context=context,workspace_hook=payload.get('workspace_hook')),broker,loaded)
                # A ctypes callback records cancellation as failure instead of
                # unwinding through C++; the managed lifetime must still exit.
                if _cancelling_children:raise SystemExit(_cancel_exit_code or 143)
                unchanged()
                result=dict(status='COMPLETED' if outcome['ok'] else 'FAILED',operations=operations if outcome['ok'] else [],
                            state=outcome['state'] if outcome['ok'] else state,errors=outcome['errors'],numeric_receipts=numeric,
                            source_sha256=report['source_sha256'],design_sha256=report['design_sha256'],project_sha256=report['project_sha256'],
                            **{key:report[key] for key in ('source_manifest','source_tree_sha256') if key in report},
                            binary_sha256=built['binary_sha256'],distributed_library=str(library),runtime_compilation=False,
                            native_output_path=str(native_log),native_output_bytes=native_log.stat().st_size,
                            event=event,execution='persistent compiled C++ worker; existing typed public CORE broker')
                result['workspace_hook_mask']=outcome.get('workspace_hook_mask',0)
                if 'workspace_capture' in outcome:result['workspace_capture']=outcome['workspace_capture']
                write_json(work/'derived/run.json',result)
                send(dict(ok=True,result=result))
            except Exception as error:
                send(dict(ok=False,error=str(error),code=getattr(error,'code','RUNTIME_ERROR')))
        return 0

def test_project(project):
    if acquisition_project_target(project):raise DevelopmentError('Acquisition Test requires the actual CORE managed request and selected-source authority','ACQUISITION_MANAGED_REQUEST_REQUIRED')
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
    if acquisition_project_target(project):
        from gxtxt_acquisition_development_v1 import export as acquisition_export
        return acquisition_export(project,_acquisition_catalog(api_catalog(project)))
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
    target=design.get('target','viewer')
    if target=='preview':
        options=dictionary(design.get('preview',''))
        if options.get('runtime')!='managed_cpp':
            raise DevelopmentError('C++ Preview export requires the managed compiled runtime','PREVIEW_RUNTIME')
        if not tkinter.Tcl().splitlist(design['components']):
            raise DevelopmentError('Compiled Preview export requires a declared presentation component','PREVIEW_RUNTIME')
        connector=f'''# SPDX-License-Identifier: GPL-3.0-or-later
::GX::workbenchExtensionRequireApi VIEWER_DEVELOPMENT_API_v1
namespace eval {namespace} {{variable root [file dirname [file dirname [info script]]]}}
proc {namespace}::preview {{context}} {{return [::GX::viewerDevelopmentPreviewTabs {module} [set {namespace}::root] $context]}}
proc {namespace}::guiMount {{host context}} {{return [::GX::viewerDevelopmentPreviewMount {module} [set {namespace}::root] $host $context]}}
proc {namespace}::guiDispose {{host context reason}} {{::GX::viewerDevelopmentPreviewDispose $host}}
'''
        descriptor+=section('meta',{'api_version':1,'id':module,'kind':'preview','group':'Preview Components','name':design['title'],
                            'version':version,'license':'GPL-3.0-or-later','selectable':1,'default_enabled':1,'core':0,'runner':'service','order':900,
                            'description':'Compiled C++ presentation using public Preview and canonical presentation owners.'})
        fields={'profile':'presentation','runtime':'managed_cpp','api_version':1,'dataset_contracts':options['dataset_contracts'],
                'gui_api_version':1,'gui_public_api':'PREVIEW_COMPONENT_GUI_API_v1'}
        fields.update({key:value for key,value in options.items() if key not in {'runtime','dataset_contracts'}})
        descriptor+=section('preview_provider',fields)
        descriptor+=section('public_apis',{'ids':'PREVIEW_COMPONENT_GUI_API_v1'})
        descriptor+=section('public_api.PREVIEW_COMPONENT_GUI_API_v1',{'api_version':1,'name':'Managed compiled Preview presentation',
                             'entrypoint':'api/viewer.tcl','namespace':namespace,'capabilities':'preview;guiMount;guiDispose',
                             'documentation':'MANUAL.md'})
        html_compatibility=False
    else:
        descriptor+=section('meta',{'api_version':1,'id':module,'kind':'viewer','group':'Viewers','name':design['title'],
                           'version':version,'license':'GPL-3.0-or-later','selectable':1,'default_enabled':1,'core':0,'runner':'service','order':900,
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
    if 'contract_visualizer' in design:
        role=dictionary(design['contract_visualizer'])
        if not all(role.get(key) for key in ('id','contracts','targets')):
            raise DevelopmentError('Contract Visualizer export needs id, contracts and targets','VISUALIZER_DECLARATION')
        targets=set(str(role['targets']).replace(';',' ').split())
        if targets!=({'preview'} if target=='preview' else {'open'}):
            raise DevelopmentError('Contract Visualizer targets must match the authored module target','VISUALIZER_DECLARATION')
        descriptor+=section('contract_visualizers',{'api_version':1,'ids':role['id']})
        fields={key:value for key,value in role.items() if key!='id'}
        if target=='viewer':fields['viewer_id']=provider
        descriptor+=section('contract_visualizer.'+role['id'],fields)
    workspace_contributions=[]
    if any(dictionary(component)['type']=='workspace' for component in tkinter.Tcl().splitlist(design['components'])):
        workspace_id=module.replace('.','_').replace('-','_')+'_'+provider+'_interface_state'
        workspace_contributions.append((workspace_id,{'entrypoint':'api/viewer.tcl','viewer_provider':provider,
            'type':'Restricted C++ Viewer state','schema':'gxtxt.viewer_interface_state.v1','version':1,'accepted_versions':1,
            'validate':'::GX::viewerGuiDesignStateValidate','open':namespace+'::workspaceOpen',
            'native_contract':'NATIVE_WORKSPACE_API_v1','encode':'::GX::viewerGuiWorkspaceEncode','decode':'::GX::viewerGuiWorkspaceDecode',
            'native_required_fields':'schema text values object bindings object choices object visibility object domain_state object design object'}))
    for raw_component in tkinter.Tcl().splitlist(design['components']):
        component=dictionary(raw_component)
        if component['type']=='section' and dictionary(component['properties']).get('tex_source'):
            article_provider=(module+'_'+provider+'_'+component['id']+'_tex_article').replace('.','_').replace('-','_')
            workspace_contributions.append((article_provider,{'entrypoint':'api/viewer.tcl','viewer_provider':provider,
                'type':'LaTeX article','schema':'gxtxt.tex_project.v1','version':1,
                'validate':'::GX::_interactiveDocumentTeXValidate','open':namespace+'::texOpen',
                'native_contract':'NATIVE_WORKSPACE_API_v1','encode':'::GX::nativeWorkspaceTeXEncode',
                'native_required_fields':'source_revision int assets object last_build object last_good_pdf object'}))
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
    files=project_sources(project,meta)
    if not sources_match(project,validation):raise DevelopmentError('Project changed during export','SOURCE_CHANGED')
    payload.update({'source/'+name:content for name,content in files.items()})
    payload['source/SOURCE_MANIFEST.json']=(json.dumps(source_identity(files),indent=2,sort_keys=True)+'\n').encode()
    payload.update({'source/authoring/'+name:raw for name,raw in source_authoring.export(project,meta).items()})
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
    provenance.update(source_identity(files))
    provenance['project_digest_sha256']=validation.get('project_digest_sha256')
    payload['RESTRICTED_VIEWER_PROVENANCE.json']=(json.dumps(provenance,indent=2,sort_keys=True)+'\n').encode()
    owner=FRAMEWORK/'plugins/modules/tool.script_module_builder/runtime/builder.py'
    spec=importlib.util.spec_from_file_location('gxtxt_trusted_package_writer',owner)
    builder=importlib.util.module_from_spec(spec);sys.modules[spec.name]=builder;spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix='candidate-',dir=project/'derived/tmp') as temporary:
        if not sources_match(project,validation) or any(digest((project/name).read_bytes())!=validation[key] for name,key in [('project.json','project_sha256'),('design.gxtxt-viewer','design_sha256')]):
            raise DevelopmentError('Project changed while preparing export; no candidate published','SOURCE_CHANGED')
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
    if acquisition_project_target(project):raise DevelopmentError('Acquisition source edits require revision-bound ProjectFiles save_all','PROJECT_REQUEST')
    limit=MANUAL_LIMIT_BYTES if operation=='save' and filename=='MANUAL.md' else POLICY['source_limit_bytes']
    if len(source)>limit or b'\0' in source:
        raise DevelopmentError('Manual transfer is bounded to 256 KiB UTF-8; C++ source/metadata remain bounded to 64 KiB' if limit==MANUAL_LIMIT_BYTES else 'Developer source/metadata transfer is bounded to 64 KiB UTF-8','SOURCE_BOUND')
    try: source.decode('utf-8')
    except UnicodeDecodeError: raise DevelopmentError('Developer source must be UTF-8','SOURCE_ENCODING')
    if operation=='check_source':
        meta=read_project(project)
        files=project_sources(project,meta)
        if filename not in files:raise DevelopmentError('Choose a declared source file','SOURCE_TARGET')
        files[filename]=source
        report=validate_project_sources(files,project/'derived/tmp')
        report.update(source_identity(files))
        capability_check(project,meta,api_catalog(project),report)
        write_json(project/'derived/import-validation.json',report)
        return report
    if filename not in {'project.json','MANUAL.md'} and filename not in project_sources(project):
        raise DevelopmentError('Only original C++ source/project metadata/manual are author-writable','SOURCE_TARGET')
    for name in ('handlers.cpp','project.json','design.gxtxt-viewer'):
        path=project/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1:
            raise DevelopmentError('Source write requires an existing ordinary developer project','SOURCE_TARGET')
    target=project/filename
    if (target.exists() or target.is_symlink()) and (target.is_symlink() or not target.is_file() or target.stat().st_nlink!=1):
        raise DevelopmentError('Author target must be an ordinary unlinked project file','SOURCE_TARGET')
    # Bad source/JSON remains repairable; full policy validation gates Build/Run.
    with tempfile.NamedTemporaryFile(prefix='.author-source-',dir=target.parent,delete=False) as f:
        f.write(source);stage=Path(f.name)
    os.replace(stage,project/filename)
    return {'status':'SAVED','file':filename,'source_sha256':digest(source),'bytes':len(source),'code_generation_invoked':False}

def inspect_source(project,filename):
    """Existing Workspace browser's fixed source targets, inert and bounded."""
    check_project_root(project)
    if acquisition_project_target(project):
        meta,raw,files=acquisition_project.state(project)
        if filename=='sdk_v1':
            from gxtxt_acquisition_cpp_v1 import SDK as acquisition_sdk
            return inspect_text(acquisition_sdk,filename,65536)
        if filename!='project.json' and filename not in files:raise DevelopmentError('Choose a registered Acquisition project source','SOURCE_TARGET')
        return inspect_text(project/filename,filename,65536)
    targets={name:project/name for name in ('handlers.cpp','project.json','MANUAL.md','design.gxtxt-viewer')}
    targets['sdk_v1']=SDK
    if filename not in targets:
        if filename not in project_sources(project):raise DevelopmentError('Unknown declared developer source target','SOURCE_TARGET')
        targets[filename]=project/filename
    return inspect_text(targets[filename],filename,4194304 if filename=='design.gxtxt-viewer' else MANUAL_LIMIT_BYTES if filename=='MANUAL.md' else 65536)

def _publish_project_files(project,encoded,removed,verify,expected_prestate=None):
    """The existing ProjectFiles atomic publisher; caller holds its grant/lock."""
    def target_check(name):
        path=project/name
        if any(p.is_symlink() for p in [path,*path.parents]) or (path.exists() and (not path.is_file() or path.stat().st_nlink!=1)):
            raise DevelopmentError('Source target/ancestors must be ordinary unlinked project paths','SOURCE_TARGET')
    touched=set(encoded)|set(removed)
    expected=dict(expected_prestate) if expected_prestate is not None else {
        name:(project/name).read_bytes() if (project/name).is_file() else None for name in touched}
    if not touched.issubset(expected):raise DevelopmentError('Publisher prestate is incomplete','SOURCE_CHANGED')
    originals={name:expected[name] for name in touched}
    modes={};owned={}
    def snapshot(name):
        target_check(name);path=project/name
        if not path.exists():return None
        # The same bounded ordinary reader protects against path replacement and FIFOs.
        content=acquisition_project.ordinary_read(project,name,4194304)
        info=path.stat()
        return (content,info.st_dev,info.st_ino)
    def check_expected(name):
        actual=snapshot(name)
        if name in owned:
            matches=actual==owned[name]
        else:matches=(actual[0] if actual is not None else None)==expected[name]
        if not matches:raise DevelopmentError('Source changed before publication: '+name,'SOURCE_CHANGED')
    for name in expected:
        check_expected(name)
        modes[name]=(project/name).stat().st_mode&0o777 if (project/name).exists() else 0o644
    def publish(name,content,guard=True):
        target_check(name)
        target=project/name;target.parent.mkdir(parents=True,exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix='.source-edit-',dir=target.parent,delete=False) as stream:
            stream.write(content);temporary=Path(stream.name)
        try:
            os.chmod(temporary,modes.get(name,0o644))
            staged=temporary.stat()
            if guard:check_expected(name)
            os.replace(temporary,target)
            owned[name]=(content,staged.st_dev,staged.st_ino)
            check_expected(name)
        finally:
            temporary.unlink(missing_ok=True)
    try:
        for name,content in encoded.items():
            if name!='project.json':publish(name,content)
        for name in removed:
            check_expected(name);(project/name).unlink();owned[name]=None
        if 'project.json' in encoded:publish('project.json',encoded['project.json'])
        for name in expected:check_expected(name)
        current=verify()
    except BaseException as error:
        conflicts=[]
        for name in list(owned):
            try:
                if snapshot(name)!=owned[name]:
                    conflicts.append(name);continue
                content=originals[name]
                if content is None:(project/name).unlink(missing_ok=True)
                else:publish(name,content,guard=False)
            except Exception:conflicts.append(name)
        if conflicts:
            raise DevelopmentError('Publication failed; external changes preserved and recovery requires review: '+', '.join(sorted(conflicts)),'SOURCE_RECOVERY_CONFLICT') from error
        raise
    return current

def project_files(project,payload):
    """Source tree edits share the original project metadata and write grant.

    Preflight all bytes/names before publishing. Metadata is published last;
    rollback restores every touched original on an ordinary I/O exception.
    Readers still compare complete input fingerprints before using artifacts.
    """
    import fcntl
    check_project_root(project)
    with (project/'derived/source-edit.lock').open('a+b') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise DevelopmentError('Another source edit is active','PROJECT_BUSY')
        if acquisition_project_target(project):
            try:return acquisition_project_files(project,payload)
            except source_authoring.authoring.AuthoringError as error:raise DevelopmentError(str(error),'SOURCE_NOTES') from error
        meta=read_project(project);files=project_sources(project,meta)
        operation=payload.get('operation') if isinstance(payload,dict) else None
        if operation=='list':
            return dict(status='CATALOG',**source_identity(files),project_sha256=digest((project/'project.json').read_bytes()))
        if payload.get('expected_project_sha256')!=digest((project/'project.json').read_bytes()):
            if operation=='note_read' and 'expected_project_sha256' not in payload:
                result=source_authoring.projection(project,meta,files,payload.get('relative'),payload.get('file_key',''),payload.get('owner_key',''))
                return dict(result,project_sha256=digest((project/'project.json').read_bytes()),source_revision=source_identity(files)['source_tree_sha256'])
            raise DevelopmentError('Project metadata changed; refresh source tree','SOURCE_CHANGED')
        if operation in {'note_read','note_identity','note_write','note_asset_read'}:
            if operation=='note_asset_read':
                return source_authoring.read_asset(project,meta,files,payload)
            if operation!='note_read':
                original=(project/'project.json').read_bytes();mode=(project/'project.json').stat().st_mode&0o777
                try:
                    updated=source_authoring.prepare(project,meta,files,payload)
                    if updated!=meta:
                        write_json(project/'project.json',updated);(project/'project.json').chmod(mode)
                    meta=read_project(project)
                except BaseException:
                    with tempfile.NamedTemporaryFile(prefix='.note-rollback-',dir=project,delete=False) as stream:
                        stream.write(original);temporary=Path(stream.name)
                    temporary.chmod(mode);os.replace(temporary,project/'project.json')
                    raise
            result=source_authoring.projection(project,meta,files,payload.get('relative'),payload.get('file_key',''),payload.get('owner_key',''))
            return dict(result,project_sha256=digest((project/'project.json').read_bytes()),source_revision=source_identity(files)['source_tree_sha256'],code_generation_invoked=False)
        names=list(files);changes={};removed=[]
        if operation=='add':
            name=source_name(payload.get('name'))
            if name in names or (project/name).exists():raise DevelopmentError('Source target already exists','SOURCE_TARGET')
            names.append(name);changes[name]=payload.get('source','')
        elif operation=='remove':
            name=payload.get('name')
            if name not in names or name=='handlers.cpp':raise DevelopmentError('Select an auxiliary source/header to remove','SOURCE_TARGET')
            names.remove(name);removed.append(name)
        elif operation=='rename':
            name=payload.get('name');target=source_name(payload.get('target'))
            if name not in names or name=='handlers.cpp' or target in names or (project/target).exists():raise DevelopmentError('Rename requires an auxiliary source and absent destination','SOURCE_TARGET')
            names[names.index(name)]=target;changes[target]=files[name].decode('utf-8');removed.append(name)
        elif operation=='save_all':
            updates=payload.get('files')
            if not isinstance(updates,dict) or not 1<=len(updates)<=34:raise DevelopmentError('Save All requires bounded file changes','SOURCE_TARGET')
            for name,item in updates.items():
                if name not in {*names,'project.json','MANUAL.md'} or not isinstance(item,dict) or set(item)!={'source','expected_sha256'}:
                    raise DevelopmentError('Save All target is not a declared editable file','SOURCE_TARGET')
                path=project/name;actual=digest(path.read_bytes()) if path.is_file() else None
                if item['expected_sha256']!=actual:raise DevelopmentError('Source changed externally: '+name,'SOURCE_CHANGED')
                changes[name]=item['source']
        else:raise DevelopmentError('Unknown source-tree operation','SOURCE_TARGET')
        encoded={}
        for name,text in changes.items():
            if not isinstance(text,str):raise DevelopmentError('Source must be UTF-8 text','SOURCE_ENCODING')
            content=text.encode('utf-8');limit=MANUAL_LIMIT_BYTES if name=='MANUAL.md' else POLICY['source_limit_bytes']
            if b'\0' in content or len(content)>limit:raise DevelopmentError('Source exceeds its UTF-8 byte bound','SOURCE_BOUND')
            encoded[name]=content
        if not 1<=len(names)<=32 or sum(len(encoded.get(n,files.get(n,b''))) for n in names)>1048576:
            raise DevelopmentError('Project supports at most32files/1MiB','PROJECT_SOURCES')
        if operation!='save_all':
            meta['source_files']=names
            encoded['project.json']=(json.dumps(meta,indent=2,sort_keys=True)+'\n').encode()
        elif 'project.json' in encoded:
            candidate=json.loads(encoded['project.json'])
            if candidate.get('source_files',['handlers.cpp'])!=names:
                raise DevelopmentError('Use source-tree actions to change source_files','PROJECT_SOURCES')
        candidate=json.loads(encoded['project.json']) if 'project.json' in encoded else meta
        next_files={name:encoded.get(name,files.get(name,b'')) for name in names}
        renames={payload['name']:payload['target']} if operation=='rename' else {}
        try:with_notes=source_authoring.source_change(project,meta,files,candidate,next_files,renames)
        except source_authoring.authoring.AuthoringError as error:raise DevelopmentError(str(error),'SOURCE_NOTES') from error
        if with_notes!=candidate:encoded['project.json']=(json.dumps(with_notes,indent=2,sort_keys=True)+'\n').encode()
        def verify():
            current=project_sources(project)
            if any(current[n]!=encoded.get(n,files.get(n)) for n in names):raise DevelopmentError('Source write readback differs','SOURCE_CHANGED')
            return current
        current=_publish_project_files(project,encoded,removed,verify)
        return dict(status='SAVED',operation=operation,**source_identity(current),project_sha256=digest((project/'project.json').read_bytes()),code_generation_invoked=False)

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
    parser.add_argument('operation',choices=['init','generate_preview','project_init','import_project','validate','build','prepare','run','test','export','api','inspect','project_files','manual_asset','save','check_source','grant','facility_request','builder','debug','debug_control','debug_status','gui_test','workspace_upgrade_review','runtime_inspect','runtime_run','runtime_serve','maintenance_init','maintenance_inspect','maintenance_save','maintenance_validate','maintenance_export'])
    parser.add_argument('project',type=Path)
    parser.add_argument('--module-id',default='viewer.restricted_example')
    parser.add_argument('--package',type=Path,help='Standard exported package, used only by import_project initialization')
    parser.add_argument('--event',type=json.loads)
    parser.add_argument('--state',type=json.loads)
    parser.add_argument('--runtime-work',type=Path,help='CORE-owned installed runtime allocation; never a development project')
    parser.add_argument('--breakpoints',type=json.loads,default=[])
    parser.add_argument('--file',default='handlers.cpp')
    parser.add_argument('--target',default='handlers.cpp',help='Declared project file or fixed SDK/manual source target')
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
        if arguments.package is not None and arguments.operation!='import_project':raise DevelopmentError('--package belongs only to import_project','SOURCE_TARGET')
        if arguments.debug_token is not None and (arguments.operation not in {'debug','debug_status','debug_control'} or not re.fullmatch(r'[a-zA-Z0-9_-]{1,96}',arguments.debug_token)):
            raise DevelopmentError('Debugger token must be bounded opaque text on a debugger request','DEBUG_STATE')
        if arguments.operation in {'runtime_inspect','runtime_run','runtime_serve'}:
            if arguments.runtime_work is None or arguments.runtime_work.is_symlink():
                raise DevelopmentError('Installed execution requires its CORE runtime allocation','RUNTIME_LIFETIME')
            work=arguments.runtime_work.absolute()
            if arguments.operation!='runtime_inspect' and acquisition_project_target(project/'source'):
                raise DevelopmentError('Installed Acquisition invokes the fixed CORE broker, not a Viewer event worker','ACQUISITION_MANAGED_REQUEST_REQUIRED')
            if arguments.operation=='runtime_serve':return compiled_serve(project,work)
            result=(installed_inspect(project,work) if arguments.operation=='runtime_inspect'
                    else installed_run(project,work,arguments.event,arguments.state))
        elif arguments.operation.startswith('maintenance_'):
            from gxtxt_viewer_maintenance import dispatch
            raw=sys.stdin.buffer.read(1048577)
            if len(raw)>1048576:raise DevelopmentError('Maintenance request exceeds 1 MiB escaped UTF-8 envelope','REQUEST_LIMIT')
            result=dispatch(arguments.operation,project,json.loads(raw))
        elif arguments.operation=='project_init':
            raw=sys.stdin.buffer.read(65537)
            if len(raw)>65536:raise DevelopmentError('Project initialization exceeds 64 KiB','REQUEST_LIMIT')
            result=acquisition_initialize(project,acquisition_project.decode(raw))
        elif arguments.operation=='generate_preview':
            raw=sys.stdin.buffer.read(2097153)
            if len(raw)>2097152:raise DevelopmentError('Preview design request exceeds 2 MiB','REQUEST_LIMIT')
            result=generate_preview(project,json.loads(raw))
        elif arguments.operation=='init': result=initialize(project,arguments.module_id)
        elif arguments.operation=='import_project':result=import_project(project,arguments.package)
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
            elif arguments.operation=='project_files':
                raw=sys.stdin.buffer.read(8388609)
                if len(raw)>8388608:raise DevelopmentError('Project note request exceeds8MiB','REQUEST_LIMIT')
                request=json.loads(raw)
                note=isinstance(request,dict) and request.get('operation') in {'note_read','note_identity','note_write','note_asset_read'}
                if not note and len(raw)>2097152:raise DevelopmentError('Project edit exceeds2MiB','REQUEST_LIMIT')
                result=project_files(project,request)
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
                if not isinstance(control,dict) or set(control)-{'operation','source_sha256','source_tree_sha256','frame','node_id','inspection_id','offset'} or control.get('operation') not in {'continue','into','over','out','pause','stop','frame','children'}:
                    raise DevelopmentError('Only enumerated native debugger controls are admitted','DEBUG_CONTROL')
                if digest((project/'handlers.cpp').read_bytes())!=control.get('source_sha256'):raise DevelopmentError('Source revision changed; restart Debug','SOURCE_CHANGED')
                snapshot=json.loads((project/'derived/debug/state.json').read_text())
                if not sources_match(project,snapshot) or ('source_tree_sha256' in control and control['source_tree_sha256']!=snapshot.get('source_tree_sha256')):
                    raise DevelopmentError('Project source tree changed; restart Debug','SOURCE_CHANGED')
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
            elif arguments.operation=='run':
                if acquisition_project_target(project):raise DevelopmentError('Acquisition invocation requires the actual CORE managed request','ACQUISITION_MANAGED_REQUEST_REQUIRED')
                result=run(project,arguments.event,arguments.state)
            elif arguments.operation=='test':
                if acquisition_project_target(project):
                    from gxtxt_acquisition_project_test_v1 import run as acquisition_project_test
                    raw=sys.stdin.buffer.read(65537)
                    if len(raw)>65536:raise DevelopmentError('Acquisition Test request exceeds64KiB','REQUEST_LIMIT')
                    result=acquisition_project_test(project,json.loads(raw),_acquisition_catalog(api_catalog(project)),core)
                else:result=test_project(project)
            elif arguments.operation=='api' and acquisition_project_target(project):
                catalog=api_catalog(project);context=_acquisition_browser_catalog(catalog,project)
                result={'status':'CATALOG','apis':catalog,'cpp_context':context,'profiles':['acquisition_v1'],'python_authoring':False}
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
