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
FLAGS = ['--no-default-config', '-std=c++17', '-x', 'c++', '-nostdinc', '-nostdinc++', '-fno-builtin',
         '-fno-exceptions', '-fno-rtti', '-Werror', '-fno-color-diagnostics']
SCALARS = {'void', 'bool', 'char', 'int', 'unsigned int', 'long', 'unsigned long',
           'long long', 'unsigned long long', 'float', 'double', 'gx::EventKind'}
ALLOWED_NODES = set('FunctionDecl ParmVarDecl VarDecl DeclStmt CompoundStmt ReturnStmt IfStmt ForStmt WhileStmt DoStmt BreakStmt ContinueStmt SwitchStmt CaseStmt DefaultStmt NullStmt IntegerLiteral FloatingLiteral CXXBoolLiteralExpr CharacterLiteral StringLiteral ImplicitCastExpr BinaryOperator CompoundAssignOperator UnaryOperator ParenExpr ConditionalOperator ArraySubscriptExpr MemberExpr DeclRefExpr CXXMemberCallExpr CallExpr ConstantExpr'.split())
SAFE_CASTS = {'LValueToRValue', 'IntegralCast', 'IntegralToFloating', 'FloatingToIntegral',
              'FloatingCast', 'IntegralToBoolean', 'FloatingToBoolean', 'NoOp',
              'FunctionToPointerDecay', 'ArrayToPointerDecay'}
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
    resource.setrlimit(resource.RLIMIT_FSIZE, (32 * 1024**2, 32 * 1024**2))
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
        output, errors = stdout.read(32 * 1024**2 + 1), stderr.read(32 * 1024**2 + 1)
        if max(len(output), len(errors)) > 32 * 1024**2:
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
        for match in re.finditer(rb"(?m)^(\w+) '([^\n]*)'.*?Loc=<[^\n]*?:(\d+):(\d+)>", tokens):
            kind, spelling, line, column = match.groups()
            if kind in {b'hash', b'hashhash'} or (kind == b'raw_identifier' and (spelling.startswith(b'_') or spelling in {b'extern', b'asm', b'__asm', b'__asm__', b'import', b'module'})):
                offset = sum(len(row) for row in source.splitlines(keepends=True)[:int(line)-1]) + int(column)-1
                reject('Author preprocessing, includes, modules, assembly and external declarations are unavailable', offset, 'CPP_PREPROCESSOR')
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
        sdk_nodes = [n for root in trusted for n in walk(root)]
        sdk_members = {n['id']: n for n in sdk_nodes if n['kind'] in {'FieldDecl', 'CXXMethodDecl', 'EnumConstantDecl'}}
        authored_nodes = [n for n in tree.get('inner', []) if n.get('loc') and not n['loc'].get('includedFrom')]
        functions = {n.get('id'): n for n in authored_nodes if n['kind'] == 'FunctionDecl'}
        names = {n.get('name'): n for n in functions.values()}
        if len(names)!=len(functions): reject('Overloaded author functions are outside this profile')
        entry = names.get('on_event')
        if not entry or entry.get('type', {}).get('qualType') != 'void (gx::Host &, gx::State &, const gx::Event &)':
            reject('Define exactly void on_event(gx::Host&, gx::State&, const gx::Event&)')
        calls = {name: set() for name in names}
        used_sdk = set()
        for root in authored_nodes:
            offset = root.get('loc', {}).get('offset', 0)
            if root['kind'] != 'FunctionDecl' or not any(n['kind'] == 'CompoundStmt' for n in root.get('inner', [])):
                reject('Author top level contains function definitions only; no redeclarations, globals, namespaces, types or hooks', offset); continue
            name = root.get('name', '')
            if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}',name) or (name != 'on_event' and any(x in root.get('type', {}).get('qualType', '') for x in ('gx::', '*', '&', '[', '.', '...'))):
                reject('Helper functions use ordinary scalar parameters/results and nonreserved names', offset)
            if root.get('storageClass') not in {None, 'static'} or root.get('variadic'):
                reject('Unsupported function linkage or variadic declaration', offset)
            for node in walk(root):
                kind = node['kind']; children = node.get('inner', []); begin = node.get('range', {}).get('begin', {})
                at = begin.get('offset', node.get('loc', {}).get('offset', offset))
                if kind not in ALLOWED_NODES:
                    reject('Unsupported C++ AST construct: ' + kind, at); continue
                if kind in {'VarDecl', 'ParmVarDecl'}:
                    typ = node.get('type', {}).get('desugaredQualType', node.get('type', {}).get('qualType', ''))
                    entry_parameter = kind == 'ParmVarDecl' and root is entry and typ in {'gx::Host &', 'gx::State &', 'const gx::Event &'}
                    if (typ.removeprefix('const ') not in SCALARS and not entry_parameter) or node.get('storageClass'):
                        reject('Only automatic scalar locals and the fixed entrypoint references are available', at)
                    if node.get('name', '').startswith('_'): reject('Reserved names are unavailable', at)
                if kind == 'UnaryOperator' and node.get('opcode') not in {'+', '-', '!', '~', '++', '--'}:
                    reject('Address-taking, dereference and unsupported unary operations are unavailable', at)
                if kind in {'BinaryOperator', 'CompoundAssignOperator'} and node.get('type', {}).get('qualType') not in SCALARS:
                    reject('Author operators act on scalar values only', at)
                if kind == 'ImplicitCastExpr' and node.get('castKind') not in SAFE_CASTS:
                    reject('Unsupported implicit type conversion', at)
                if kind == 'StringLiteral' and len(node.get('value', '').encode()) > POLICY['string_limit_bytes'] + 2:
                    reject('SDK strings are limited to 256 UTF-8 bytes', at)
                if kind == 'MemberExpr':
                    target = sdk_members.get(node.get('referencedMemberDecl'), {})
                    allowed = set(POLICY['allowed_sdk_calls'] + POLICY['allowed_state_members'] + POLICY['allowed_event_members'])
                    if node.get('isArrow') or target.get('name') not in allowed:
                        reject('Only enumerated SDK methods/state/event fields are available', at)
                if kind == 'ArraySubscriptExpr':
                    base = list(walk(children[0])); index = children[1]
                    if index['kind'] != 'IntegerLiteral' or not 0 <= int(index['value']) < POLICY['state_values'] or not any(n.get('kind') == 'MemberExpr' and n.get('name') == 'values' for n in base):
                        reject('State array indices must be literal integers 0..15', at)
                if kind == 'DeclRefExpr':
                    target = node.get('referencedDecl', {}); target_id = target.get('id')
                    if target['kind'] == 'FunctionDecl' and target_id not in functions:
                        reject('Function is outside the resolved author/SDK call graph: ' + target.get('name', '?'), at)
                    if target['kind'] == 'EnumConstantDecl' and target_id not in sdk_members:
                        reject('Only SDK event constants are available', at)
                if kind == 'CallExpr':
                    refs = [n.get('referencedDecl', {}) for n in walk(children[0]) if n['kind'] == 'DeclRefExpr']
                    if len(refs) != 1 or refs[0].get('id') not in functions:
                        reject('Indirect/native/unresolved function calls are unavailable', at)
                    else: calls[name].add(refs[0]['name'])
                if kind == 'CXXMemberCallExpr':
                    target = children[0]
                    if target['kind'] != 'MemberExpr' or target.get('referencedMemberDecl') not in sdk_members or target.get('name') not in POLICY['allowed_sdk_calls']:
                        reject('Method is outside the curated SDK', at)
                    else:
                        used_sdk.add(target['name'])
                        if target['name'] == 'text' and not any(n['kind'] == 'StringLiteral' for n in walk(children[-1])):
                            reject('Host.text accepts a bounded literal string only', at)
        def cyclic(name, trail):
            if name in trail: return True
            return any(cyclic(child, trail | {name}) for child in calls.get(name, ()))
        if any(cyclic(name, set()) for name in calls): reject('Recursive author call graphs are unavailable')
        report['functions'] = sorted(names)
        report['sdk_calls'] = sorted(used_sdk)
        report['resolved_call_graph'] = {key: sorted(value) for key, value in sorted(calls.items())}
        report['author_ast_kinds'] = sorted({n['kind'] for root in authored_nodes for n in walk(root)})
        if not report['diagnostics']: report['status'] = 'PASS'
    return report
