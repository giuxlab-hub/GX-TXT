# SPDX-License-Identifier: GPL-3.0-or-later
"""Acquisition target adapter to the existing fixed Clang lexer/AST/build owner.

No compiler selection, flags, source paths or executable are authored metadata.
Viewer policy/SDK/entry checks are deliberately untouched.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import tempfile
from gxtxt_cpp_policy import COMPILER,DEVELOPMENT,FLAGS,bounded_command,digest,source_includes,walk
import gxtxt_acquisition_project_v1 as model

SDK=DEVELOPMENT/'sdk/gxtxt_acquisition_sdk_v1.hpp'
ADAPTER=SDK.parent/'trusted_acquisition_adapter_v1.cpp'
POLICY_PATH=DEVELOPMENT/'acquisition_policy_v1.json'
API='ACQUISITION_HANDLER_PLUGIN_API_v1'

def describe(project,meta,raw,files):
    """Inert current-receipt projection, never Build/native authority.

    Source projects are editable, including derived reports. Every Build reruns
    AST/capability checks; matching metadata is solely a frontend eligibility hint.
    """
    result=model.description(meta,raw,files)
    result['validation_status']='unvalidated'
    try:
        content=model.ordinary_read(project,'derived/acquisition-validation.json',1048576)
        report=model.decode(content)
        expected={(p[phase]['file'],p[phase]['symbol'].removeprefix('::')) for p in meta['formats'] for phase in ('recognize','inspect','import')}
        signature='gx::AcquisitionResult(gx::AcquisitionHost&,const gx::AcquisitionRequest&)'
        if not isinstance(report,dict) or report.get('schema')!='gxtxt.acquisition_cpp_validation.v1' or report.get('status')!='PASS' or report.get('code_generation_invoked') is not False or not expected:
            return result
        pins={'project_sha256':result['project_sha256'],'source_tree_sha256':result['source_tree_sha256'],
              'source_sha256':digest(files['handlers.cpp']),'sdk_sha256':digest(SDK.read_bytes()),
              'policy_sha256':digest(POLICY_PATH.read_bytes()),'adapter_sha256':digest(ADAPTER.read_bytes()),
              'factory_sha256':digest(factory(meta)),
              'compiler_sha256':json.loads((DEVELOPMENT/'toolchain/manifest.json').read_text())['driver_sha256']}
        if any(report.get(key)!=value for key,value in pins.items()):return result
        bindings=report.get('bindings')
        if not isinstance(bindings,list) or len(bindings)!=len(expected) or len(bindings)>96:return result
        admitted=set()
        for row in bindings:
            if not isinstance(row,dict) or set(row)!={'file','symbol','signature'} or row['signature']!=signature or not isinstance(row['file'],str) or not isinstance(row['symbol'],str):return result
            admitted.add((row['file'],row['symbol']))
        if admitted!=expected or report.get('diagnostics')!=[]:return result
        for row in result['files']:
            row['validated_entrypoints']=sorted(symbol for file,symbol in admitted if file==row['relative'])
            if row['validated_entrypoints']:row['binding_status']='validated_ast'
        result.update(validation_status='matching_current_ast_receipt',validation_sha256=digest(content),
                      validation_authority='frontend_metadata_only; Build reruns actual compiler and capability admission')
    except (OSError,ValueError,KeyError,TypeError):
        pass # Repairable/stale/absent derived data must not block source consultation.
    return result

def factory(meta):
    declarations=[];seen=set()
    for profile in meta['formats']:
        for phase in ('recognize','inspect','import'):
            symbol=profile[phase]['symbol'].removeprefix('::')
            if symbol in seen:continue
            seen.add(symbol);parts=symbol.split('::')
            declarations.append(''.join('namespace '+p+' {' for p in parts[:-1])+'gx::AcquisitionResult '+parts[-1]+'(gx::AcquisitionHost&,const gx::AcquisitionRequest&);'+'}'*(len(parts)-1))
    lines=['#include "gxtxt_acquisition_sdk_v1.hpp"','#include <stdexcept>',*declarations,
           'namespace gx {AcquisitionResult acquisition_dispatch_v1(const std::string& profile,const std::string& phase,AcquisitionHost& host,const AcquisitionRequest& request){']
    for profile in meta['formats']:
        lines.append('if(profile=='+json.dumps(meta['module_id']+'/'+profile['id'])+'){')
        for phase in ('recognize','inspect','import'):
            test='phase=="import"||phase=="test"' if phase=='import' else 'phase=="'+phase+'"'
            lines.append('if('+test+')return ::'+profile[phase]['symbol'].removeprefix('::')+'(host,request);')
        lines.append('}')
    lines.append('throw std::runtime_error("Compiled profile/phase is not admitted");}}')
    return ('\n'.join(lines)+'\n').encode()

def validate(meta,raw,files,directory,catalog):
    policy=json.loads(POLICY_PATH.read_text());compiled={name:content for name,content in files.items() if name in meta['source_files']}
    report=dict(schema='gxtxt.acquisition_cpp_validation.v1',profile='acquisition_v1',status='REJECTED',code_generation_invoked=False,
        project_sha256=digest(raw),source_tree_sha256=model.description(meta,raw,files)['source_tree_sha256'],
        source_sha256=digest(files['handlers.cpp']),sdk_sha256=digest(SDK.read_bytes()),policy_sha256=digest(POLICY_PATH.read_bytes()),
        compiler_sha256=digest(COMPILER.read_bytes()),compiler_version='19.1.7',diagnostics=[],functions=[],sdk_calls=[],stages=[],bindings=[])
    report['adapter_sha256']=digest(ADAPTER.read_bytes())
    report['contract_declarations_sha256']=model.contract_declarations_sha256(meta)
    def reject(message,code='ACQUISITION_POLICY',file='project.json'):
        report['diagnostics'].append(dict(file=file,line=1,column=1,code=code,message=message))
    if not meta['formats']:reject('Validate/Build/Export requires at least one real format profile','PROJECT_PROFILE');return report
    try:
        for profile in meta['formats']:model.contract_ids(profile['output_contracts'],'Output contracts')
    except model.ProjectError as error:
        reject(str(error),'PROJECT_CONTRACT');return report
    requested={}
    available=catalog.get(API,{})
    advertised=set(available.get('allowed_operations',[]))
    if str(available.get('version'))!='1' or str(available.get('available',available.get('enabled','')))!='1':
        reject('Current public Acquisition API v1 is unavailable','CORE_API_GAP');return report
    allowed=set(policy['sdk_calls'])
    def capabilities(rows):
        result={}
        for request in rows:
            api=request['api_id'];ops=set(request['operations'])
            if api!=API or str(request['version'])!='1' or not ops.issubset(allowed) or not ops.issubset(advertised):
                reject('Capability requires actual supported Acquisition API operations','CAPABILITY_DENIED');continue
            result[api]=ops
        return result
    requested=capabilities(meta['capabilities']);moduleops=requested.get(API,set())
    for profile in meta['formats']:
        grants=capabilities(profile['capabilities']).get(API,set())
        if not grants.issubset(moduleops):reject('Profile operations exceed module declaration: '+profile['id'],'CAPABILITY_DENIED')
    report['requested']={key:sorted(value) for key,value in requested.items()}
    report['diagnostics']+=source_includes(compiled)
    if digest(COMPILER.read_bytes())!=json.loads((DEVELOPMENT/'toolchain/manifest.json').read_text())['driver_sha256']:reject('Trusted compiler identity changed')
    if report['diagnostics']:return report
    directory.mkdir(parents=True,exist_ok=True)
    definitions=set();used=set();functions=set()
    bindings={(p[k]['file'],p[k]['symbol'].removeprefix('::')) for p in meta['formats'] for k in ('recognize','inspect','import')}
    with tempfile.TemporaryDirectory(prefix='acquisition-validate-',dir=directory) as name:
        stage=Path(name)
        for relative,content in compiled.items():
            path=stage/relative;path.parent.mkdir(parents=True,exist_ok=True)
            checks=[]
            for boundfile,symbol in bindings:
                if boundfile==relative:checks.append('static_assert(__is_same(decltype(&::'+symbol+'),gx::AcquisitionResult(*)(gx::AcquisitionHost&,const gx::AcquisitionRequest&)),"Acquisition callback signature mismatch");')
            path.write_bytes(content+b'\n'+('\n'.join(checks)+'\n').encode())
        for relative in compiled:
            if not relative.endswith('.cpp'):continue
            path=stage/relative
            status,_,tokens=bounded_command([str(COMPILER),*FLAGS,'-Xclang','-dump-raw-tokens','-fsyntax-only',str(path)],stage)
            report['stages'].append('clang_raw_lexer:'+relative)
            if status:reject(tokens.decode(errors='replace')[-8192:],'CPP_LEXER',relative);continue
            status,ast,errors=bounded_command([str(COMPILER),*FLAGS,'-I'+str(stage),'-I'+str(stage/'include'),'-include',str(SDK),'-Xclang','-ast-dump=json','-fsyntax-only',str(path)],stage)
            report['stages'].append('clang_resolved_ast:'+relative)
            if status:
                reject(errors.decode(errors='replace').replace(str(stage)+'/', '')[-8192:],'CPP_PARSE',relative);continue
            tree=json.loads(ast);location=None;authored=[];members={}
            for node in tree.get('inner',[]):
                location=node.get('loc',{}).get('file',location)
                if location==str(SDK):
                    members.update({n['id']:n for n in walk(node) if n.get('kind')=='CXXMethodDecl' and n.get('id')})
                if location and Path(location).is_relative_to(stage):
                    source=Path(location).relative_to(stage).as_posix()
                    if source in compiled:authored.append((node,source))
            def visit(node,scope,file):
                kind=node.get('kind');nextscope=scope
                if kind=='NamespaceDecl' and node.get('name'):nextscope=scope+[node['name']]
                if kind=='FunctionDecl' and node.get('name') and any(child.get('kind')=='CompoundStmt' for child in node.get('inner',[])):
                    symbol='::'.join(scope+[node['name']]);functions.add(symbol);definitions.add((file,symbol))
                if kind=='MemberExpr':
                    target=members.get(node.get('referencedMemberDecl'),{})
                    if target:
                        method=target.get('name')
                        if method not in allowed:reject('Unsupported Acquisition SDK member: '+str(method),'CAPABILITY_DENIED',file)
                        else:used.add(method)
                for child in node.get('inner',[]):visit(child,nextscope,file)
            for node,file in authored:visit(node,[],file)
    for file,symbol in sorted(bindings):
        if (file,symbol) not in definitions:reject('Binding is not a defined free callback in its declared file: '+symbol,'CALLBACK_BINDING',file)
        else:report['bindings'].append(dict(file=file,symbol=symbol,signature='gx::AcquisitionResult(gx::AcquisitionHost&,const gx::AcquisitionRequest&)'))
    if not used.issubset(moduleops):reject('Authored SDK calls lack module capability: '+', '.join(sorted(used-moduleops)),'CAPABILITY_DENIED')
    report.update(functions=sorted(functions),sdk_calls=sorted(used),factory_sha256=digest(factory(meta)))
    if not report['diagnostics']:report['status']='PASS'
    return report
