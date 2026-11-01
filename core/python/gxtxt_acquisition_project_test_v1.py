# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit Development Test, using the existing admitted native request owners.

This trusted author tool owns selection/review. It never registers or installs a
module, opens a Session, or hands provisional scientific buffers to publication.
"""
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat
import tempfile
import time
import zipfile

from gxtxt_acquisition_broker_v1 import AcquisitionNativeBroker
from gxtxt_acquisition_source_v1 import AcquisitionSourceGrant, _identity
from gxtxt_acquisition_output_v1 import AcquisitionOutputBuffers
import gxtxt_acquisition_project_v1 as model
import gxtxt_acquisition_development_v1 as development
from gxtxt_cpp_policy import FRAMEWORK, digest
from gxtxt_job_supervisor import tcl_result


def run(project, request, catalog, core):
    if not isinstance(request,dict) or set(request)-{'schema','expected_revision','profile_id','sources','config'} or request.get('schema')!='gxtxt.acquisition_project_test.v1':
        raise ValueError('Test requires its versioned explicit profile/source selection')
    meta, raw, files = model.state(project)
    description = model.description(meta,raw,files)
    if request.get('expected_revision')!=description['revision']:
        raise ValueError('Project Test requires the exact reviewed source revision; refresh before retrying')
    profile = next((row for row in meta['formats'] if row['id']==request.get('profile_id')), None)
    if profile is None:
        raise ValueError('Select a saved declared format profile for Test')
    selected = request.get('sources')
    if not isinstance(selected,list) or not 1<=len(selected)<=64 or any(not isinstance(path,str) for path in selected) or len(set(selected))!=len(selected):
        raise ValueError('Test requires 1..64 unique explicitly chosen source files')
    values = {field['id']:field['default'] for field in meta.get('config_fields',[])}
    overrides = request.get('config',{})
    if not isinstance(overrides,dict) or set(overrides)-set(values):
        raise ValueError('Test configuration contains undeclared fields')
    values.update(overrides);values['format_profile']=profile['id']
    config = model.typed_config_payload(meta, values)
    exported = development.export(project,catalog)
    if exported.get('status')!='CANDIDATE_EXPORTED':return exported
    if model.state(project)[1:]!=(raw,files):
        raise ValueError('Source project changed while preparing Test')
    package = Path(exported['package'])
    if digest(package.read_bytes())!=exported['sha256']:
        raise ValueError('Test candidate SHA differs')
    with tempfile.TemporaryDirectory(prefix='acquisition-test-',dir=project/'derived/tmp') as temporary:
        temporary = Path(temporary)
        root = temporary/'candidate';root.mkdir(mode=0o700)
        # Read the normal exporter artifact, never a second package generator.
        with zipfile.ZipFile(package) as archive:
            inventory=archive.infolist();names=[item.filename for item in inventory]
            if len(names)!=len(set(names)) or len(names)>512 or sum(item.file_size for item in inventory)>67108864:
                raise ValueError('Test candidate inventory exceeds its bound')
            for item in inventory:
                name=item.filename;mode=item.external_attr>>16
                if name.startswith('/') or '\\' in name or any(part in {'','.','..'} for part in name.split('/')) or mode&0o170000 not in {0,0o100000}:
                    raise ValueError('Test candidate contains unsafe members')
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True)
                with path.open('xb') as stream:stream.write(archive.read(item))
                # Preserve normal package read/execute modes; the worker guard
                # explicitly refuses group/world-writable authored artifacts.
                permissions=mode&0o777 or 0o644
                if permissions&0o022:raise ValueError('Test candidate has writable admitted members')
                path.chmod(permissions)
        admitted = development.installed_inspect(root,temporary/'admission',catalog)
        module_operations = set(admitted['requested'].get('ACQUISITION_HANDLER_PLUGIN_API_v1',[]))
        profile_operations = set(next((row['operations'] for row in profile['capabilities'] if row['api_id']=='ACQUISITION_HANDLER_PLUGIN_API_v1' and str(row['version'])=='1'),[]))
        operations = sorted(module_operations & profile_operations)
        scope = dict(request_id=secrets.token_hex(32),phase='test',module_id=meta['module_id'],
            qualified_profile=meta['module_id']+'/'+profile['id'],session_token='',module_snapshot=dict(
                project_sha256=digest(raw),source_tree_sha256=description['source_tree_sha256'],
                profile_sha256=description['profile_sha256'][profile['id']],manifest_sha256=admitted['manifest_sha256'],
                binary_sha256=admitted['binary_sha256'],config_schema_sha256=model.config_schema_sha256(meta)))
        inspection_scope=dict(scope,request_id=secrets.token_hex(32),phase='inspect')
        recognition_scope=dict(scope,request_id=secrets.token_hex(32),phase='recognize')
        pinned = {project/'project.json':digest(raw),**{project/name:digest(value) for name,value in files.items()}}
        pinned.update({path:digest(path.read_bytes()) for path in root.rglob('*') if path.is_file()})
        fixed = ['gxtxt_acquisition_project_test_v1.py','gxtxt_acquisition_broker_v1.py','gxtxt_acquisition_source_v1.py',
                 'gxtxt_acquisition_output_v1.py','gxtxt_acquisition_native_worker_v1.py','gxtxt_native_read_policy_v1.py',
                 'gxtxt_acquisition_project_v1.py','gxtxt_acquisition_development_v1.py','gxtxt_viewer_development.py',
                 'gxtxt_acquisition_spectrum_v1.py','scientific_spectrum_import.py',
                 'gxtxt_acquisition_sdk_compat_v1.py']
        helper = None
        helper_path = FRAMEWORK/'core/python/gxtxt_acquisition_helper_broker_v1.py'
        if helper_path.is_file():
            fixed += ['gxtxt_acquisition_helper_broker_v1.py','gxtxt_acquisition_helper_worker_v1.py']
        pinned.update({FRAMEWORK/'core/python'/name:digest((FRAMEWORK/'core/python'/name).read_bytes()) for name in fixed})
        for relative in ('core/tcl/acquisition_helper_worker_v1.tcl','core/tcl/native_workspace_api_v1.tcl','core/workspace/libgxtxt_workspace.so',
                         'core/tcl/viewer_development_request.tcl','core/tcl/dataset_publication_api_v2.tcl',
                         'core/tcl/scientific_spectrum_api_v1.tcl','core/tcl/scientific_spectrum_import_api_v1.tcl',
                         'core/tcl/scientific_reference_library_api_v1.tcl'):
            path=FRAMEWORK/relative
            if path.is_file():pinned[path]=digest(path.read_bytes())
        pinned.update({Path(path):sha for path,sha in admitted['runtime_contract'].items()})
        identities = {path:_identity(path.stat(follow_symlinks=False)) for path in pinned}
        deadline = time.monotonic()+60
        def live(actual):
            if actual not in (scope,inspection_scope,recognition_scope) or time.monotonic()>deadline:
                raise ValueError('Project Test request expired')
            for path, expected in identities.items():
                current=path.stat(follow_symlinks=False)
                if not stat.S_ISREG(current.st_mode) or current.st_nlink!=1 or _identity(current)!=expected:
                    raise ValueError('Reviewed Test project/runtime closure changed')
            return True
        sources=[];total=0
        for selected_path in selected:
            live(scope);path=Path(selected_path)
            if not path.is_absolute() or path.resolve(strict=True)!=path:
                raise ValueError('Choose ordinary source files without linked ancestors')
            fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW|os.O_CLOEXEC)
            with os.fdopen(fd,'rb') as stream:
                before=os.fstat(stream.fileno());total+=before.st_size
                if not stat.S_ISREG(before.st_mode) or total>2147483648:
                    raise ValueError('Selected Test sources exceed the ordinary-file/2 GiB bound')
                sha=hashlib.sha256()
                while True:
                    live(scope);chunk=stream.read(65536)
                    if not chunk:break
                    sha.update(chunk)
                if _identity(before)!=_identity(os.fstat(stream.fileno())):
                    raise ValueError('Selected source changed during Test review')
            sources.append(dict(path=str(path),logical_name=path.name,sha256=sha.hexdigest()))
        def definition(declaration):
            live(scope);value=declaration['definition']
            if value['contract'] not in profile['output_contracts'] or value.get('replace_owned') or value.get('producer_version',meta['version'])!=meta['version'] or value.get('publication_module',meta['module_id'])!=meta['module_id']:
                raise ValueError('Test output exceeds its actual producer/profile declaration')
            core(project,'acquisition_test_definition',tcl_result(value))
            return True
        def spectrum_validate(request):
            live(scope)
            index = request['source_index']
            if type(index) is not int or not 0 <= index < len(sources):
                raise ValueError('Test scientific source index differs')
            if request['source_sha256'] != sources[index]['sha256']:
                raise ValueError('Test scientific source SHA differs')
            options = dict(request['options'], source_identity=request['source_identity'])
            value = core(project, 'acquisition_test_spectrum_validation', tcl_result(dict(
                format=request['format'], path=sources[index]['path'], options=options,
                expected_sha256=request['source_sha256'], expected_count=request['row_count'])))
            live(scope)
            import tkinter
            parts = tkinter.Tcl().splitlist(value)
            if len(parts) != 12:
                raise ValueError('Test Spectrum owner returned a malformed projection')
            return dict(zip(parts[::2], parts[1::2]))
        def inspect_phase(phase_scope):
            phase=phase_scope['phase']
            inspection_buffers=temporary/phase;inspection_buffers.mkdir(mode=0o700)
            inspection_log=inspection_buffers/'native.log';inspection_log.touch(mode=0o600,exist_ok=False)
            inspection_runtime=dict(library=admitted['library'],binary_sha256=admitted['binary_sha256'],sdk_sha256=admitted['sdk_sha256'],buffer_root=str(inspection_buffers),native_output_path=str(inspection_log))
            inspection_source=AcquisitionSourceGrant(phase_scope,sources,live)
            try:
                inspection_helper=None
                if helper_path.is_file() and 'helper_call' in operations:
                    from gxtxt_acquisition_helper_broker_v1 import AcquisitionHelperBroker
                    inspection_helper=AcquisitionHelperBroker(phase_scope,root/'source',meta['helpers'],files,live,
                        admitted_operations=operations,runtime_pins={str(path):sha for path,sha in pinned.items()})
                inspector=AcquisitionNativeBroker(phase_scope,inspection_source,None,live,
                    admitted_operations=operations,helper=inspection_helper,
                    spectrum_validator=spectrum_validate,timeout_seconds=60)
                result=inspector.run(inspection_runtime,config,{},dict(slice_bytes=65536,datasets=0,variables=0))
                if result['result'].get('recognized') is not True:
                    raise ValueError('Selected source was not recognized by the actual saved profile')
                return result
            finally:
                inspection_source.close()
        recognition=inspect_phase(recognition_scope)
        inspection=inspect_phase(inspection_scope)
        buffers=temporary/'buffers';buffers.mkdir(mode=0o700)
        source=output=None
        try:
            source=AcquisitionSourceGrant(scope,sources,live)
            output=AcquisitionOutputBuffers(buffers,scope,live,definition)
            if helper_path.is_file() and 'helper_call' in operations:
                from gxtxt_acquisition_helper_broker_v1 import AcquisitionHelperBroker
                helper=AcquisitionHelperBroker(scope,root/'source',meta['helpers'],files,live,
                    admitted_operations=operations,runtime_pins={str(path):sha for path,sha in pinned.items()})
            log=buffers/'native.log';log.touch(mode=0o600,exist_ok=False)
            runtime=dict(library=admitted['library'],binary_sha256=admitted['binary_sha256'],sdk_sha256=admitted['sdk_sha256'],buffer_root=str(buffers),native_output_path=str(log))
            broker=AcquisitionNativeBroker(scope,source,output,live,admitted_operations=operations,
                helper=helper,spectrum_validator=spectrum_validate,timeout_seconds=60)
            result=broker.run(runtime,config,dict(variables=[],dataset_id='project.test',contract=profile['output_contracts'][0]),dict(slice_bytes=65536,datasets=64,variables=128))
            live(scope)
            if any(digest(path.read_bytes())!=sha for path,sha in pinned.items()):
                raise ValueError('Test project/runtime SHA changed before handoff')
            summary=[dict(dataset_id=row['definition']['dataset_id'],contract=row['definition']['contract'],row_count=row['row_count'],
                variables=[dict(variable_id=variable['variable_id'],schema=variable['schema'],sha256=variable['sha256']) for variable in row['variables']]) for row in result['prepared_publications']]
            for item, row in zip(summary, result['prepared_publications']):
                if 'dimensions' in row:
                    item['dimensions'] = row['dimensions']
            report=dict(status='PASS',scope='project_test_only_no_install_no_session_no_publication',
                project_sha256=digest(raw),source_tree_sha256=description['source_tree_sha256'],profile_id=profile['id'],
                config=config,config_sha256=digest(model.encode(config)),candidate_sha256=exported['sha256'],
                actor_reaped=result['actor_reaped'],admission=result['admission'],source_descriptors=result['source_descriptors'],
                recognition=recognition['result'],recognition_actor_reaped=recognition['actor_reaped'],
                inspection=inspection['result'],inspection_actor_reaped=inspection['actor_reaped'],
                native_result=result['result'],discarded_outputs=summary,scientific_acceptance=False,
                session_created=False,module_installed=False,datasets_published=False)
            development.write(project/'derived/acquisition-test.json',report)
            return report
        finally:
            if source is not None:source.close()
            if output is not None:output.close()
