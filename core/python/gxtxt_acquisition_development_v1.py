# SPDX-License-Identifier: GPL-3.0-or-later
"""Target-specific build/package adapter to the existing Development services."""
from __future__ import annotations
import configparser
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile
from gxtxt_cpp_policy import COMPILER,DEVELOPMENT,FLAGS,FRAMEWORK,bounded_command,digest
import gxtxt_acquisition_cpp_v1 as cpp
import gxtxt_acquisition_project_v1 as model
from gxtxt_acquisition_sdk_compat_v1 import admit_package

class AcquisitionDevelopmentError(ValueError):
    def __init__(self,message,code='ACQUISITION_DEVELOPMENT'):
        super().__init__(message);self.code=code

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    content=model.encode(value)
    with tempfile.NamedTemporaryFile(prefix='.acquisition-',dir=path.parent,delete=False) as stream:
        stream.write(content);stage=Path(stream.name)
    os.replace(stage,path)

def validate(project,catalog):
    meta,raw,files=model.state(project)
    report=cpp.validate(meta,raw,files,project/'derived/tmp',catalog)
    write(project/'derived/acquisition-validation.json',report)
    return meta,raw,files,report

def current(project,report):
    meta,raw,files=model.state(project)
    desc=model.description(meta,raw,files)
    if digest(raw)!=report['project_sha256'] or desc['source_tree_sha256']!=report['source_tree_sha256']:
        raise AcquisitionDevelopmentError('Project source/profile/helper closure changed','SOURCE_CHANGED')
    return meta,raw,files

def build(project,catalog):
    meta,raw,files,report=validate(project,catalog)
    if report['status']!='PASS':return dict(status='REJECTED',validation=report,code_generation_invoked=False)
    with tempfile.TemporaryDirectory(prefix='acquisition-build-',dir=project/'derived/tmp') as name:
        stage=Path(name)
        for relative in meta['source_files']:
            path=stage/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(files[relative])
        generated=cpp.factory(meta);(stage/'factory.cpp').write_bytes(generated)
        fixed=[*FLAGS,'-O1','-g0','-fPIC','-fvisibility=hidden','-fno-stack-protector','-ffile-prefix-map='+str(stage)+'=.','-ffile-prefix-map='+str(DEVELOPMENT)+'=sdk']
        units=[stage/name for name in meta['source_files'] if name.endswith('.cpp')]+[cpp.ADAPTER,stage/'factory.cpp']
        logs=[];objects=[];deps=[]
        for index,unit in enumerate(units):
            obj=stage/('unit'+str(index)+'.o');dep=stage/('unit'+str(index)+'.d');objects.append(obj);deps.append(dep)
            command=[str(COMPILER),*fixed,'-I'+str(stage),'-I'+str(stage/'include'),'-I'+str(cpp.SDK.parent),'-MD','-MF',str(dep),'-include',str(cpp.SDK),'-c',str(unit),'-o',str(obj)]
            code,output,error=bounded_command(command,stage,30);logs.append((output+error).decode(errors='replace').replace(str(stage),'<controlled-build>'))
            if code:
                failed=dict(status='BUILD_FAILED',validation=report,code_generation_invoked=True,log='\n'.join(logs));write(project/'derived/acquisition-build.json',failed);return failed
        code,output,error=bounded_command([str(COMPILER),'-shared','-pthread','-Wl,-z,defs','-Wl,--build-id=none',*[str(p) for p in objects],'-lstdc++','-lm','-o',str(stage/'acquisition.so')],stage,30)
        logs.append((output+error).decode(errors='replace').replace(str(stage),'<controlled-build>'))
        if code:
            failed=dict(status='BUILD_FAILED',validation=report,code_generation_invoked=True,log='\n'.join(logs));write(project/'derived/acquisition-build.json',failed);return failed
        current(project,report)
        for path,key in [(cpp.SDK,'sdk_sha256'),(cpp.POLICY_PATH,'policy_sha256'),(cpp.ADAPTER,'adapter_sha256'),(COMPILER,'compiler_sha256')]:
            if digest(path.read_bytes())!=report[key]:raise AcquisitionDevelopmentError('Target toolchain changed during build; validate/build again','SOURCE_CHANGED')
        headers={}
        for dep in deps:
            for value in shlex.split(dep.read_text().replace('\\\n',' ').split(':',1)[1]):
                path=Path(value).resolve()
                if not path.is_relative_to(stage):headers[str(path)]=digest(path.read_bytes())
        binary=(stage/'acquisition.so').read_bytes()
        result=dict(schema='gxtxt.acquisition_build.v1',status='BUILT',target='acquisition',validation=report,
            binary_sha256=digest(binary),sdk_sha256=digest(cpp.SDK.read_bytes()),policy_sha256=digest(cpp.POLICY_PATH.read_bytes()),
            adapter_sha256=digest(cpp.ADAPTER.read_bytes()),factory_sha256=digest(generated),compiler_sha256=digest(COMPILER.read_bytes()),
            compiler_version='19.1.7',header_dependencies=headers,code_generation_invoked=True,log='\n'.join(logs))
        # Atomic new inode: an existing actor may still map the previous binary.
        with tempfile.NamedTemporaryFile(prefix='.acquisition-binary-',dir=project/'derived',delete=False) as stream:
            stream.write(binary);stage_binary=Path(stream.name)
        os.replace(stage_binary,project/'derived/acquisition.so')
        (project/'derived/acquisition-factory.cpp').write_bytes(generated)
        write(project/'derived/acquisition-build.json',result)
        return result

def section(name,fields):
    lines=['['+name+']']
    for key,value in fields.items():
        value=str(value)
        if any(c in value for c in '\r\n\0'):raise AcquisitionDevelopmentError('Descriptor values must be one line')
        lines.append(key+'='+value)
    return '\n'.join(lines)+'\n\n'

def config_sections(meta):
    fields=model.config_fields_validate(meta.get('config_fields',[]))
    result={'config':dict(fields=';'.join(['format_profile']+[field['id'] for field in fields])),
            'config.format_profile':dict(type='choice',label='Format profile',default=meta['formats'][0]['id'],values=';'.join(p['id'] for p in meta['formats']),required='1')}
    def scalar(value):
        if type(value) is bool:return '1' if value else '0'
        if type(value) is float:return repr(value)
        return str(value)
    for field in fields:
        row={key:scalar(field[key]) for key in ('type','label','default','required')}
        if 'values' in field:row['values']=';'.join(field['values'])
        for key in ('min','max'):
            if key in field:row[key]=scalar(field[key])
        result['config.'+field['id']]=row
    return result

def verify_config_descriptor(meta,descriptor):
    expected=config_sections(meta)
    # Match the existing CORE iniUnescape codec, not ConfigParser interpolation.
    def unescape(value):return value.replace('\\\\','\x01').replace('\\n','\n').replace('\\r','\r').replace('\x01','\\')
    actual={name:{key:unescape(value) for key,value in descriptor[name].items()} for name in descriptor.sections() if name=='config' or name.startswith('config.')}
    if actual!=expected:raise AcquisitionDevelopmentError('Actual Module configuration declaration differs from its source schema/defaults','BINARY_SOURCE_MISMATCH')

def contract_sections(meta):
    declared=model.contract_declarations(meta);result={}
    if declared['input_contracts']:result['inputs']={'contracts':';'.join(declared['input_contracts'])}
    outputs=sorted({value for profile in meta['formats'] for value in profile['output_contracts']})
    model.contract_ids(outputs,'Output contracts',maximum=model.MAX_FORMATS*64)
    result['outputs']={'datasets':';'.join(outputs)}
    if declared['provided_contracts']:
        result['contracts']={'provided':';'.join(row['id'] for row in declared['provided_contracts'])}
        for row in declared['provided_contracts']:
            result['contract.'+row['id']]={'description':row['description'],'parents':';'.join(row['parents'])}
    return result

def verify_contract_descriptor(meta,descriptor):
    expected=contract_sections(meta)
    def unescape(value):return value.replace('\\\\','\x01').replace('\\n','\n').replace('\\r','\r').replace('\x01','\\')
    actual={name:{key:unescape(value) for key,value in descriptor[name].items()} for name in descriptor.sections() if name in {'inputs','outputs','contracts'} or name.startswith('contract.')}
    if actual!=expected:raise AcquisitionDevelopmentError('Actual Contract Registry declarations differ from the source project','BINARY_SOURCE_MISMATCH')

def export(project,catalog):
    built=build(project,catalog)
    if built['status']!='BUILT':return built
    meta,raw,files=current(project,built['validation']);module=meta['module_id'];version=meta['version']
    descriptor='; SPDX-License-Identifier: GPL-3.0-or-later\n'+section('meta',dict(api_version=1,id=module,kind='acquisition',group='Acquisition',name=meta['name'],version=version,license=meta['license'],selectable=1,default_enabled=1,core=0,runner='standard_tcl',description=meta['description'],depends=';'.join(meta['dependencies'])))
    descriptor+=section('runner',dict(handler=module.replace('.','_')+'_managed_cpp_v1'))
    descriptor+=section('acquisition_handler',dict(api_version=1,runtime='managed_cpp',format_profiles_manifest='source/project.json',formats=';'.join(module+'/'+p['id'] for p in meta['formats']),default_profile=meta['formats'][0]['id'],supports_batch=1,supports_external_raw=1,variable_mapping='optional',capabilities='batch;progress;cooperative_async;cancellation;managed_request;consumable_prepared_buffers',file_label=meta['name'],file_patterns=';'.join(sorted({v for p in meta['formats'] for v in p['file_patterns']}))))
    for profile in meta['formats']:
        descriptor+=section('acquisition_format.'+module+'/'+profile['id'],dict(description=profile['name'],mime=';'.join(profile['mime_types']),extensions=';'.join(profile['file_patterns'])))
    for name,fields in config_sections(meta).items():
        # Same wire format as CORE iniEscape; avoids changing regex literals.
        escaped={key:str(value).replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r') for key,value in fields.items()}
        descriptor+=section(name,escaped)
    for name,fields in contract_sections(meta).items():
        descriptor+=section(name,{key:str(value).replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r') for key,value in fields.items()})
    descriptor+=section('documentation',dict(api_version=1,guide='MANUAL.md',changelog='CHANGELOG.md',api_refs='ACQUISITION_HANDLER_PLUGIN_API_v1;VIEWER_DEVELOPMENT_API_v1'))
    package_meta=section('package',dict(api_version=1,id=module,name=meta['name'],version=version,type='module',framework_min=(FRAMEWORK/'VERSION.txt').read_text().strip(),framework_max=''))
    manual=(project/'MANUAL.md').read_bytes() if (project/'MANUAL.md').exists() else ('# '+meta['name']+'\n\nCompiled Acquisition profiles use the managed CORE source/buffer/publication owners.\nSource and helper declarations are included; helper execution requires separate live CORE admission.\nSelect an explicit format profile. Test validates and discards; Import alone may publish.\nThis package requires the matching P032 CORE native Acquisition target, not an older runtime.\n').encode()
    if len(manual)>4194304 or b'\0' in manual:raise AcquisitionDevelopmentError('Manual exceeds bounded UTF-8 text')
    manual.decode('utf-8')
    payload={'module.ini':descriptor.encode(),'plugin-package.ini':package_meta.encode(),'MANUAL.md':manual,
        'CHANGELOG.md':('# '+version+'\n\nCompiled Acquisition target export.\n').encode(),'LICENSE':(FRAMEWORK/'LICENSE').read_bytes(),
        'native/acquisition.so':(project/'derived/acquisition.so').read_bytes(),'native/gxtxt_acquisition_sdk_v1.hpp':cpp.SDK.read_bytes(),
        'native/trusted_acquisition_adapter_v1.cpp':cpp.ADAPTER.read_bytes(),'native/ACQUISITION_SDK_CONTRACT.json':cpp.POLICY_PATH.read_bytes(),
        'native/acquisition-factory.cpp':cpp.factory(meta),'source/project.json':raw,
        'review/build.json':model.encode(built),'review/validation.json':model.encode(built['validation'])}
    payload.update({'source/'+name:content for name,content in files.items()})
    import viewer_source_authoring_v1 as notes
    payload.update({'source/authoring/'+name:content for name,content in notes.export(project,meta).items()})
    inventory={name:dict(sha256=digest(content),size=len(content)) for name,content in sorted(files.items())}
    payload['source/SOURCE_MANIFEST.json']=model.encode(dict(schema='gxtxt.acquisition_source_manifest.v1',files=inventory,source_tree_sha256=built['validation']['source_tree_sha256']))
    provenance=dict(schema='gxtxt.restricted_acquisition_candidate.v1',module_id=module,version=version,binary_sha256=built['binary_sha256'],project_sha256=digest(raw),source_tree_sha256=built['validation']['source_tree_sha256'],sdk_sha256=built['sdk_sha256'],policy_sha256=built['policy_sha256'],runtime='managed_cpp',author_tcl_adapter=False,promotion='normal Plugin Manager only')
    payload['RESTRICTED_ACQUISITION_PROVENANCE.json']=model.encode(provenance)
    owner=FRAMEWORK/'plugins/modules/tool.script_module_builder/runtime/builder.py'
    spec=importlib.util.spec_from_file_location('gxtxt_trusted_acquisition_package_writer',owner);writer=importlib.util.module_from_spec(spec);sys.modules[spec.name]=writer;spec.loader.exec_module(writer)
    with tempfile.TemporaryDirectory(prefix='acquisition-candidate-',dir=project/'derived/tmp') as name:
        current(project,built['validation'])
        package,sha=writer.write_module_zip(payload,module,version,Path(name))
        output=project/'candidates'/sha[:16];output.mkdir(parents=True,exist_ok=True);target=output/package.name
        if target.exists():
            if digest(target.read_bytes())!=sha:raise AcquisitionDevelopmentError('Existing candidate identity differs')
        else:os.link(package,target);package.unlink()
        (output/(target.name+'.sha256')).write_text(sha+'  '+target.name+'\n')
    result=dict(status='CANDIDATE_EXPORTED',target='acquisition',package=str(target),sha256=sha,installed=False,review_required=True,descriptor_text=descriptor,descriptor_sha256=digest(payload['module.ini']),provenance=provenance)
    write(project/'derived/acquisition-candidate.json',result);return result

def installed_inspect(root,work,catalog):
    """Inert package/build/source admission; no CDLL or compilation/probe."""
    root=root.resolve(strict=True)
    fixed=['module.ini','native/acquisition.so','native/gxtxt_acquisition_sdk_v1.hpp','native/trusted_acquisition_adapter_v1.cpp','native/ACQUISITION_SDK_CONTRACT.json','native/acquisition-factory.cpp','review/build.json','source/project.json','source/SOURCE_MANIFEST.json']
    for name in fixed:
        path=root/name
        if not path.is_file() or path.is_symlink() or path.stat().st_nlink!=1 or path.stat().st_size>67108864:raise AcquisitionDevelopmentError('Installed ordinary package member missing/invalid: '+name,'BINARY_MISSING')
    meta,raw,files=model.state(root/'source');built=model.decode((root/'review/build.json').read_bytes())
    report=built.get('validation',{})
    if built.get('schema')!='gxtxt.acquisition_build.v1' or built.get('status')!='BUILT' or report.get('status')!='PASS':raise AcquisitionDevelopmentError('Installed Acquisition has no successful build','BINARY_INCOMPATIBLE')
    current(root/'source',report)
    binary=(root/'native/acquisition.so').read_bytes()
    if binary[:4]!=b'\x7fELF' or digest(binary)!=built['binary_sha256']:raise AcquisitionDevelopmentError('Installed native binary differs','BINARY_INCOMPATIBLE')
    requested_operations = {op for row in meta['capabilities'] for op in row['operations']}
    try:
        sdk_admission = admit_package(root, built, {
            'sdk_sha256': digest(cpp.SDK.read_bytes()),
            'adapter_sha256': digest(cpp.ADAPTER.read_bytes()),
            'policy_sha256': digest(cpp.POLICY_PATH.read_bytes())}, requested_operations)
    except ValueError as error:
        raise AcquisitionDevelopmentError(str(error), 'BINARY_INCOMPATIBLE') from None
    if digest(cpp.factory(meta))!=built['factory_sha256'] or (root/'native/acquisition-factory.cpp').read_bytes()!=cpp.factory(meta):raise AcquisitionDevelopmentError('Finite callback factory differs','BINARY_INCOMPATIBLE')
    inventory=model.decode((root/'source/SOURCE_MANIFEST.json').read_bytes())
    if inventory!=dict(schema='gxtxt.acquisition_source_manifest.v1',files={name:dict(sha256=digest(content),size=len(content)) for name,content in sorted(files.items())},source_tree_sha256=report['source_tree_sha256']):raise AcquisitionDevelopmentError('Distributed source manifest differs','BINARY_SOURCE_MISMATCH')
    descriptor=configparser.ConfigParser(interpolation=None,strict=True);descriptor.read_string((root/'module.ini').read_text())
    if descriptor['meta']['id']!=meta['module_id'] or descriptor['meta']['version']!=meta['version'] or descriptor['meta']['kind']!='acquisition' or descriptor['meta']['runner']!='standard_tcl' or descriptor['acquisition_handler']['runtime']!='managed_cpp' or descriptor['acquisition_handler']['format_profiles_manifest']!='source/project.json':raise AcquisitionDevelopmentError('Native Acquisition descriptor/manifest mismatch','BINARY_INCOMPATIBLE')
    verify_config_descriptor(meta,descriptor)
    verify_contract_descriptor(meta,descriptor)
    # Recheck current actual public declarations without running a compiler.
    available=catalog.get(cpp.API,{})
    requested={row['api_id']:row['operations'] for row in meta['capabilities']}
    if str(available.get('version'))!='1' or str(available.get('available',available.get('enabled','')))!='1' or not set(requested.get(cpp.API,[])).issubset(set(available.get('allowed_operations',[]))):raise AcquisitionDevelopmentError('Current native Acquisition operations unavailable','CAPABILITY_DENIED')
    receipt=dict(schema='gxtxt.acquisition_runtime_admission.v1',status='PASS',target='acquisition',module_id=meta['module_id'],version=meta['version'],module_root=str(root),project_sha256=digest(raw),source_tree_sha256=report['source_tree_sha256'],manifest_sha256=digest((root/'module.ini').read_bytes()),binary_sha256=built['binary_sha256'],library=str(root/'native/acquisition.so'),sdk_sha256=built['sdk_sha256'],policy_sha256=built['policy_sha256'],adapter_sha256=built['adapter_sha256'],build_receipt_sha256=digest((root/'review/build.json').read_bytes()),profiles=meta['formats'],profile_sha256=model.description(meta,raw,files)['profile_sha256'],config_fields=meta.get('config_fields',[]),config_schema_sha256=model.config_schema_sha256(meta),requested=requested,runtime_contract={str(p):digest(p.read_bytes()) for p in [cpp.SDK,cpp.ADAPTER,cpp.POLICY_PATH]},runtime_compilation=False)
    receipt['sdk_admission'] = sdk_admission
    compatibility_owner=Path(__file__).with_name('gxtxt_acquisition_sdk_compat_v1.py')
    receipt['runtime_contract'][str(compatibility_owner)] = digest(compatibility_owner.read_bytes())
    receipt.update(model.contract_declarations(meta));receipt['contract_declarations_sha256']=model.contract_declarations_sha256(meta)
    receipt['contract_declarations_status']='structural declarations only; actual Registry/provider/dependency admission remains CORE-owned'
    work.mkdir(parents=True,exist_ok=True);write(work/'derived/acquisition-runtime.json',receipt)
    return receipt

def import_project_payload(project,payload,package_sha256,enforce_write):
    """Already inventory/checksum-validated ZIP, source only; no DLL/probe/build."""
    import gxtxt_acquisition_source_notes_v1 as notes
    required={'source/project.json','source/handlers.cpp','source/SOURCE_MANIFEST.json','review/build.json','module.ini'}
    if not required.issubset(payload):raise AcquisitionDevelopmentError('Acquisition package lacks its editable source closure','PROJECT_PACKAGE')
    raw=payload['source/project.json'];meta=model.validate(model.decode(raw))
    names={row['relative'] for row in model.roster(meta)}
    files={name:payload.get('source/'+name) for name in names}
    if any(not isinstance(content,bytes) or len(content)>model.MAX_FILE_BYTES or model.source_bytes(content.decode('utf-8'))!=content for content in files.values()):raise AcquisitionDevelopmentError('Acquisition source closure is missing/invalid','PROJECT_PACKAGE')
    if sum(map(len,files.values()))>model.MAX_TEXT_BYTES:raise AcquisitionDevelopmentError('Source closure exceeds 1 MiB','PROJECT_BOUND')
    source_payload={name[7:]:content for name,content in payload.items() if name.startswith('source/')}
    if any(name not in names|{'project.json','SOURCE_MANIFEST.json','MANUAL.md'} and not name.startswith('authoring/') for name in source_payload):raise AcquisitionDevelopmentError('Undeclared source project member','PROJECT_PACKAGE')
    desc=model.description(meta,raw,files);built=model.decode(payload['review/build.json']);report=built.get('validation',{})
    if built.get('schema')!='gxtxt.acquisition_build.v1' or built.get('status')!='BUILT' or report.get('status')!='PASS' or report.get('project_sha256')!=digest(raw) or report.get('source_tree_sha256')!=desc['source_tree_sha256']:
        raise AcquisitionDevelopmentError('Source package does not match its build revision','BINARY_SOURCE_MISMATCH')
    expected=dict(schema='gxtxt.acquisition_source_manifest.v1',files={name:dict(sha256=digest(content),size=len(content)) for name,content in sorted(files.items())},source_tree_sha256=desc['source_tree_sha256'])
    if model.decode(payload['source/SOURCE_MANIFEST.json'])!=expected:raise AcquisitionDevelopmentError('Packaged source manifest differs','PROJECT_PACKAGE')
    descriptor=configparser.ConfigParser(interpolation=None,strict=True);descriptor.read_string(payload['module.ini'].decode('utf-8'))
    if descriptor['meta']['id']!=meta['module_id'] or descriptor['meta']['version']!=meta['version'] or descriptor['meta']['kind']!='acquisition' or descriptor['acquisition_handler']['runtime']!='managed_cpp':raise AcquisitionDevelopmentError('Package target identity differs','PROJECT_PACKAGE')
    verify_config_descriptor(meta,descriptor)
    verify_contract_descriptor(meta,descriptor)
    authoring_payload={name[len('authoring/'):]:content for name,content in source_payload.items() if name.startswith('authoring/')}
    temporary=Path(tempfile.mkdtemp(prefix='.gxtxt-import-',dir=project.parent));reserved=None
    try:
        notes.validate(temporary,meta,files,authoring_payload)
        updated=notes.import_into(temporary,meta,files,authoring_payload)
        for name,content in dict(files,**{'project.json':model.encode(updated) if updated!=meta else raw}).items():
            target=temporary/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content);target.chmod(0o644)
        manual=source_payload.get('MANUAL.md',payload.get('MANUAL.md'))
        if manual is not None:
            if len(manual)>4194304 or b'\0' in manual:raise AcquisitionDevelopmentError('Source manual exceeds its bounded text contract','PROJECT_PACKAGE')
            manual.decode('utf-8');(temporary/'MANUAL.md').write_bytes(manual)
        model.state(temporary)
        project.mkdir();reserved=project.stat().st_ino
        if project.stat().st_ino!=reserved or any(project.iterdir()):raise AcquisitionDevelopmentError('Import destination changed','SOURCE_CHANGED')
        os.replace(temporary,project);temporary=None
        grant=enforce_write(project);(project/'derived/tmp').mkdir(parents=True,exist_ok=True)
        actual,actual_raw,actual_files=model.state(project)
        return dict(status='CREATED',target='acquisition',project=str(project),grant=grant,description=model.description(actual,actual_raw,actual_files),package_sha256=package_sha256,compiled_artifact_imported=False)
    finally:
        if temporary is not None:shutil.rmtree(temporary)
        if reserved is not None and project.exists() and project.stat().st_ino==reserved and not any(project.iterdir()):project.rmdir()
