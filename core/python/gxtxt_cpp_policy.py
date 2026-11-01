# SPDX-License-Identifier: GPL-3.0-or-later
"""Clang raw-lexer and resolved-AST policy, before any author code generation."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import tempfile

FRAMEWORK = Path(__file__).resolve().parents[2]
DEVELOPMENT = FRAMEWORK / 'core/development'
POLICY = json.loads((DEVELOPMENT / 'policy_v1.json').read_text())
COMPILER = DEVELOPMENT / 'toolchain/clang-19'
SDK = DEVELOPMENT / 'sdk/gxtxt_viewer_sdk_v1.hpp'
FLAGS = ['--no-default-config', '-std=c++17', '-x', 'c++', '-Werror', '-fno-color-diagnostics',
         '-pthread', '-isystem', '/usr/lib/gcc/x86_64-linux-gnu/14/include']
ACTIVE_PROCESSES = set()

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def walk(node):
    yield node
    for child in node.get('inner', []):
        if child:
            yield from walk(child)

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (3 * 1024**3, 3 * 1024**3))
    resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
    resource.setrlimit(resource.RLIMIT_FSIZE, (256 * 1024**2, 256 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

def environment(directory: Path):
    # No CPATH, compiler/plugin search, loader preload or author build flags.
    return {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8',
            'TMPDIR': str(directory), 'HOME': str(directory)}

def bounded_command(command, directory: Path, timeout=25):
    with open(os.devnull, 'rb') as null, tempfile.TemporaryFile(dir=directory) as stdout, tempfile.TemporaryFile(dir=directory) as stderr:
        process = subprocess.Popen(command, cwd=directory, env=environment(directory),
                                   stdin=null, stdout=stdout, stderr=stderr,
                                   start_new_session=True, preexec_fn=limits)
        ACTIVE_PROCESSES.add(process.pid)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise ValueError('Controlled Clang operation exceeded its time budget')
        finally:
            ACTIVE_PROCESSES.discard(process.pid)
        stdout.seek(0); stderr.seek(0)
        output, errors = stdout.read(256 * 1024**2 + 1), stderr.read(256 * 1024**2 + 1)
        if max(len(output), len(errors)) > 256 * 1024**2:
            raise ValueError('Controlled Clang output exceeded its bound')
        return code, output, errors

def source_name(name):
    """A bounded project name, never a compiler option or filesystem grant."""
    if not isinstance(name, str) or len(name)>160 or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_./-]*',name):
        raise ValueError('Source path must be a normalized project-relative name')
    if any(part in {'','.', '..'} for part in name.split('/')):
        raise ValueError('Source path traversal and empty components are forbidden')
    if name!='handlers.cpp' and not (name.startswith('src/') and name.endswith('.cpp') or name.startswith('include/') and name.endswith('.hpp')):
        raise ValueError('Use handlers.cpp, src/*.cpp or include/*.hpp')
    return name

def source_includes(files):
    """Review literal directives before Clang can open any authored include.

    Preprocessing line splices and comments are normalized first. Macro includes
    and source-location spoofing are deliberately outside this fixed recipe.
    """
    diagnostics=[]
    admitted=set(POLICY.get('admitted_headers',{}))
    for name,source in files.items():
        if len(source)>POLICY['source_limit_bytes'] or b'\0' in source:
            diagnostics.append(dict(file=name,line=1,column=1,code='CPP_SOURCE_BOUND',message='Source exceeds64KiB or contains NUL'));continue
        try:text=source.decode('utf-8')
        except UnicodeDecodeError:
            diagnostics.append(dict(file=name,line=1,column=1,code='CPP_ENCODING',message='Source must be UTF-8'));continue
        # C++ phase2 removes splices before recognizing comments/directives.
        # Preserve the physical map so policy errors still name the real line.
        original=text;positions=[];characters=[];position=0
        while position<len(original):
            splice=re.match(r'\\\r?\n',original[position:]) if original[position]=='\\' else None
            if splice:position+=len(splice[0]);continue
            positions.append(position);characters.append(original[position]);position+=1
        text=''.join(characters)
        lexical=r'(?:u8|u|U|L)?R"([^ ()\\\t\r\n]{0,16})\(.*?\)\1"|(?:u8|u|U|L)?"(?:\\.|[^"\\])*"|(?:u8|u|U|L)?\'(?:\\.|[^\'\\])*\'|/\*.*?\*/|//[^\n]*'
        comments=list(text);code=list(text)
        for token in re.finditer(lexical,text,flags=re.S):
            comment=token[0].startswith(('/*','//'))
            for index in range(token.start(),token.end()):
                if text[index]=='\n':continue
                code[index]=' ' if comment else '@'
                if comment:comments[index]=' '
        comments=''.join(comments);code=''.join(code)
        def diagnostic(message,offset):
            physical=positions[offset] if offset<len(positions) else 0
            prefix=original[:physical]
            diagnostics.append(dict(file=name,line=prefix.count('\n')+1,column=len(prefix.rsplit('\n',1)[-1].encode())+1,code='CPP_HEADER_NOT_ADMITTED',message=message))
        for query in re.finditer(r'\b__has_include(?:_next)?\b',code):
            diagnostic('Header existence queries require architectural review',query.start())
        for match in re.finditer(r'(?m)^[ \t\v\f\r]*(#|%:|\?\?=)[ \t\v\f\r]*([A-Za-z_][A-Za-z0-9_]*|[0-9]+)([^\n]*)',code):
            directive=match[2];argument=comments[match.start(3):match.end(3)].strip()
            if directive not in {'include','include_next','import','embed','line'} and not directive.isdecimal() and match[1]!='??=':continue
            error=None
            header=re.fullmatch(r'([<"])([^>"\n]+)[>"]\s*',argument)
            if match[1]=='??=' or directive!='include' or not header:
                error='Only literal admitted include directives are supported; source remapping is forbidden'
            elif header[2] not in admitted:
                relative=header[2]
                if header[1]!='"' or any(p in {'','.', '..'} for p in relative.split('/')) or '\\' in relative:
                    error='Header requires architectural review: '+relative
                else:
                    candidates=[(Path(name).parent/relative).as_posix(),relative,'include/'+relative]
                    if not any(candidate in files and candidate.startswith('include/') for candidate in candidates):
                        error='Missing or undeclared project header: '+relative
            if error:
                diagnostic(error,match.start(1))
    return diagnostics

def validate_project_sources(files, directory):
    report=None
    for name,source in files.items():
        if not name.endswith('.cpp'):continue
        part=validate_source(source,directory,filename=name,source_files=files)
        if report is None:report=part
        else:
            for key in ('diagnostics','functions','sdk_calls','workspace_hooks','author_ast_kinds'):
                report[key]=report.get(key,[])+part.get(key,[])
            report['stages']+=part['stages']
            if part['status']!='PASS':report['status']='REJECTED'
    for key in ('functions','sdk_calls','workspace_hooks','author_ast_kinds'):
        report[key]=sorted(set(report.get(key,[])))
    return report

def validate_source(source: bytes, directory: Path, *, filename='handlers.cpp', source_files=None) -> dict:
    files=source_files or {filename:source}
    report = {'schema': 'gxtxt.cpp_validation.v1', 'profile': POLICY['profile'],
              'source_sha256': digest(source), 'sdk_sha256': digest(SDK.read_bytes()),
              'policy_sha256': digest((DEVELOPMENT / 'policy_v1.json').read_bytes()),
              'compiler_sha256': digest(COMPILER.read_bytes()), 'compiler_version': '19.1.7',
              'status': 'REJECTED', 'code_generation_invoked': False,
              'stages': [], 'diagnostics': [], 'functions': [], 'sdk_calls': []}
    def reject(message, offset=0, code='CPP_POLICY', at_file=None):
        at_file=at_file or filename
        prefix = files.get(at_file,source)[:offset]
        report['diagnostics'].append({'file': at_file, 'line': prefix.count(b'\n') + 1,
                                      'column': len(prefix.rsplit(b'\n', 1)[-1]) + 1,
                                      'code': code, 'message': message})
    report['diagnostics']=source_includes(files)
    if report['diagnostics']:return report
    try:
        source.decode('utf-8')
    except UnicodeDecodeError:
        reject('Source must be UTF-8'); return report
    if digest(COMPILER.read_bytes()) != json.loads((DEVELOPMENT / 'toolchain/manifest.json').read_text())['driver_sha256']:
        reject('Trusted compiler identity changed'); return report
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='validate-', dir=directory) as scratch:
        scratch = Path(scratch)
        for name,content in files.items():
            source_name(name);path=scratch/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
        authored=scratch/filename
        local_flags=['-I'+str(scratch),'-I'+str(scratch/'include')]
        code, _, tokens = bounded_command([str(COMPILER), *FLAGS, '-Xclang', '-dump-raw-tokens', '-fsyntax-only', str(authored)], scratch)
        report['stages'].append('clang_raw_lexer')
        # Ordinary language facilities are not framework ownership violations.
        # Direct header admission is explicit; their implementation dependencies
        # remain the selected system toolchain's responsibility.
        admitted_headers = set(POLICY.get('admitted_headers', {}))
        for match in re.finditer(rb'PLOT_DATASET_API_v3|PlotDatasetAPIv3|plot_dataset_api_v3', source, re.I):
            reject('DEPRECATED_PLOT_API: use admitted PLOT_DATASET_API_v4 operations', match.start(), 'DEPRECATED_PLOT_API')
        if code or report['diagnostics']:
            if code and not report['diagnostics']: reject(tokens.decode(errors='replace')[-8192:], code='CPP_LEXER')
            return report
        code, raw_ast, errors = bounded_command([str(COMPILER), *FLAGS, *local_flags, '-include', str(SDK), '-Xclang', '-ast-dump=json', '-fsyntax-only', str(authored)], scratch)
        report['stages'].append('clang_resolved_ast')
        if code:
            diagnostic = errors.decode(errors='replace').replace(str(scratch)+'/', '').replace(str(SDK), 'gxtxt_viewer_sdk_v1.hpp')
            for match in re.finditer(r'([^\s:]+):([0-9]+):([0-9]+): (?:fatal )?error: ([^\n]+)', diagnostic):
                report['diagnostics'].append({'file': match[1], 'line': int(match[2]), 'column': int(match[3]), 'code': 'CPP_PARSE', 'message': match[4]})
            if not report['diagnostics']: reject(diagnostic[-8192:], code='CPP_PARSE')
            return report
        tree = json.loads(raw_ast)
        root_locations={};location=None
        for node in tree.get('inner',[]):
            location=node.get('loc',{}).get('file',location)
            root_locations[id(node)]=location
        trusted = [n for n in tree.get('inner', []) if root_locations[id(n)]==str(SDK)]
        sdk_members = {}
        for root in trusted:
            if root.get('kind') == 'NamespaceDecl' and root.get('name') == 'gx':
                sdk_members.update({n['id']: n for n in walk(root) if n['kind'] in {'FieldDecl', 'CXXMethodDecl', 'EnumConstantDecl'}})
        # Clang elides repeated filenames. Carry the top-level source location
        # forward, retaining project headers as authored rather than SDK trust.
        authored_nodes=[];authored_files={};location=None
        for node in tree.get('inner',[]):
            loc=node.get('loc',{});location=loc.get('file',location)
            if location and Path(location).is_relative_to(scratch) and Path(location).relative_to(scratch).as_posix() in files:
                authored_nodes.append(node)
                authored_files[id(node)]=Path(location).relative_to(scratch).as_posix()
        functions = [n for n in authored_nodes if n['kind'] == 'FunctionDecl']
        entries = [n for n in functions if n.get('name') == 'on_event' and any(c.get('kind') == 'CompoundStmt' for c in n.get('inner', []))]
        if (filename=='handlers.cpp' and (len(entries)!=1 or authored_files.get(id(entries[0]))!='handlers.cpp' or entries[0].get('type',{}).get('qualType')!='void (gx::Host &, gx::State &, const gx::Event &)')) or (filename!='handlers.cpp' and entries):
            reject('Define exactly void on_event(gx::Host&, gx::State&, const gx::Event&)')
        used_sdk = set()
        hook_names={'on_workspace_capture','on_workspace_validate','on_workspace_restore','on_workspace_committed'}
        declarations={node['id']:node for node in walk(tree) if node.get('id')}
        trusted_hooks={node['id'] for root in trusted if root.get('kind')=='NamespaceDecl' and root.get('name')=='gx' for node in walk(root) if node.get('kind')=='FunctionDecl' and node.get('name') in hook_names}
        workspace_hooks=set()
        for root in authored_nodes:
            for node in walk(root):
                kind = node['kind']
                at = node.get('range', {}).get('begin', {}).get('offset', 0)
                if kind=='FunctionDecl' and node.get('name') in hook_names and any(child.get('kind')=='CompoundStmt' for child in node.get('inner',[])):
                    previous=node.get('previousDecl');seen=set()
                    while previous and previous not in trusted_hooks and previous not in seen:
                        seen.add(previous);previous=declarations.get(previous,{}).get('previousDecl')
                    if previous not in trusted_hooks:reject('Implement the declared gx Workspace hook signature',at,at_file=authored_files[id(root)])
                    else:workspace_hooks.add(node['name'])
                if kind == 'MemberExpr':
                    target = sdk_members.get(node.get('referencedMemberDecl'), {})
                    if target.get('kind') == 'CXXMethodDecl':
                        if target.get('name') not in POLICY['allowed_sdk_calls']:
                            reject('Method is outside the admitted public SDK', at,at_file=authored_files[id(root)])
                        else:
                            used_sdk.add(target['name'])
        report['functions'] = sorted({n.get('name','') for n in functions})
        report['sdk_calls'] = sorted(used_sdk)
        report['workspace_hooks'] = sorted(workspace_hooks)
        report['language_support'] = POLICY.get('language_support', {})
        report['admitted_headers'] = sorted(admitted_headers)
        report['architecture_review'] = 'Language admission is not approval of alternate canonical Dataset/Job/Workspace/Plot ownership; review author data flows separately.'
        report['author_ast_kinds'] = sorted({n['kind'] for root in authored_nodes for n in walk(root)})
        if not report['diagnostics']: report['status'] = 'PASS'
    return report
