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

def validate_source(source: bytes, directory: Path) -> dict:
    report = {'schema': 'gxtxt.cpp_validation.v1', 'profile': POLICY['profile'],
              'source_sha256': digest(source), 'sdk_sha256': digest(SDK.read_bytes()),
              'policy_sha256': digest((DEVELOPMENT / 'policy_v1.json').read_bytes()),
              'compiler_sha256': digest(COMPILER.read_bytes()), 'compiler_version': '19.1.7',
              'status': 'REJECTED', 'code_generation_invoked': False,
              'stages': [], 'diagnostics': [], 'functions': [], 'sdk_calls': []}
    def reject(message, offset=0, code='CPP_POLICY'):
        prefix = source[:offset]
        report['diagnostics'].append({'file': 'handlers.cpp', 'line': prefix.count(b'\n') + 1,
                                      'column': len(prefix.rsplit(b'\n', 1)[-1]) + 1,
                                      'code': code, 'message': message})
    if len(source) > POLICY['source_limit_bytes'] or b'\0' in source:
        reject('Source exceeds 64 KiB or contains NUL'); return report
    try:
        source.decode('utf-8')
    except UnicodeDecodeError:
        reject('Source must be UTF-8'); return report
    if digest(COMPILER.read_bytes()) != json.loads((DEVELOPMENT / 'toolchain/manifest.json').read_text())['driver_sha256']:
        reject('Trusted compiler identity changed'); return report
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='validate-', dir=directory) as scratch:
        scratch = Path(scratch); authored = scratch / 'handlers.cpp'; authored.write_bytes(source)
        code, _, tokens = bounded_command([str(COMPILER), *FLAGS, '-Xclang', '-dump-raw-tokens', '-fsyntax-only', str(authored)], scratch)
        report['stages'].append('clang_raw_lexer')
        # Ordinary language facilities are not framework ownership violations.
        # Direct header admission is explicit; their implementation dependencies
        # remain the selected system toolchain's responsibility.
        admitted_headers = set(POLICY.get('admitted_headers', {}))
        for match in re.finditer(rb'(?m)^\s*#\s*include\s*[<"]([^>"\n]+)[>"]', source):
            header = match.group(1).decode('utf-8')
            if header not in admitted_headers:
                reject('Header requires architectural review: '+header, match.start(), 'CPP_HEADER_NOT_ADMITTED')
        for match in re.finditer(rb'PLOT_DATASET_API_v3|PlotDatasetAPIv3|plot_dataset_api_v3', source, re.I):
            reject('DEPRECATED_PLOT_API: use admitted PLOT_DATASET_API_v4 operations', match.start(), 'DEPRECATED_PLOT_API')
        if code or report['diagnostics']:
            if code and not report['diagnostics']: reject(tokens.decode(errors='replace')[-8192:], code='CPP_LEXER')
            return report
        code, raw_ast, errors = bounded_command([str(COMPILER), *FLAGS, '-include', str(SDK), '-Xclang', '-ast-dump=json', '-fsyntax-only', str(authored)], scratch)
        report['stages'].append('clang_resolved_ast')
        if code:
            diagnostic = errors.decode(errors='replace').replace(str(authored), 'handlers.cpp').replace(str(SDK), 'gxtxt_viewer_sdk_v1.hpp')
            for match in re.finditer(r'handlers.cpp:(\d+):(\d+): (?:fatal )?error: ([^\n]+)', diagnostic):
                report['diagnostics'].append({'file': 'handlers.cpp', 'line': int(match[1]), 'column': int(match[2]), 'code': 'CPP_PARSE', 'message': match[3]})
            if not report['diagnostics']: reject(diagnostic[-8192:], code='CPP_PARSE')
            return report
        tree = json.loads(raw_ast)
        trusted = [n for n in tree.get('inner', []) if n.get('loc', {}).get('includedFrom')]
        sdk_members = {}
        for root in trusted:
            if root.get('kind') == 'NamespaceDecl' and root.get('name') == 'gx':
                sdk_members.update({n['id']: n for n in walk(root) if n['kind'] in {'FieldDecl', 'CXXMethodDecl', 'EnumConstantDecl'}})
        authored_nodes = [n for n in tree.get('inner', []) if n.get('loc') and not n['loc'].get('includedFrom')]
        functions = [n for n in authored_nodes if n['kind'] == 'FunctionDecl']
        entries = [n for n in functions if n.get('name') == 'on_event' and any(c.get('kind') == 'CompoundStmt' for c in n.get('inner', []))]
        if len(entries) != 1 or entries[0].get('type', {}).get('qualType') != 'void (gx::Host &, gx::State &, const gx::Event &)':
            reject('Define exactly void on_event(gx::Host&, gx::State&, const gx::Event&)')
        used_sdk = set()
        for root in authored_nodes:
            for node in walk(root):
                kind = node['kind']
                at = node.get('range', {}).get('begin', {}).get('offset', 0)
                if kind == 'MemberExpr':
                    target = sdk_members.get(node.get('referencedMemberDecl'), {})
                    if target.get('kind') == 'CXXMethodDecl':
                        if target.get('name') not in POLICY['allowed_sdk_calls']:
                            reject('Method is outside the admitted public SDK', at)
                        else:
                            used_sdk.add(target['name'])
        report['functions'] = sorted({n.get('name','') for n in functions})
        report['sdk_calls'] = sorted(used_sdk)
        report['language_support'] = POLICY.get('language_support', {})
        report['admitted_headers'] = sorted(admitted_headers)
        report['architecture_review'] = 'Language admission is not approval of alternate canonical Dataset/Job/Workspace/Plot ownership; review author data flows separately.'
        report['author_ast_kinds'] = sorted({n['kind'] for root in authored_nodes for n in walk(root)})
        if not report['diagnostics']: report['status'] = 'PASS'
    return report
