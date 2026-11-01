"""Static PROVIDED API inventory over an already admitted in-memory source map.

No source imports/eval/execution, filesystem source reads, Registry or runtime
publication. A valid inventory is a declaration projection, never authorization.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import ast
import hashlib
import json
import keyword
from pathlib import PurePosixPath
import re

from script_api_declarations import REQUIREMENT, discover as discover_consumed

SCHEMA = 'gxtxt.script_provided_api_inventory.v1'
DECLARATION_SCHEMA = 'gxtxt.script_api_export.v1'
MARKER = 'gxtxt_api_export'
API_ID = re.compile(r'[A-Z][A-Z0-9_]*_v([1-9][0-9]*)\Z')
IDENTIFIER = re.compile(r'[A-Za-z][A-Za-z0-9_]*\Z')
CAPABILITY = re.compile(r'[A-Za-z][A-Za-z0-9_.:/-]{0,127}\Z')
KINDS = {'null', 'string', 'integer', 'number', 'double', 'boolean', 'array', 'object'}
MAX_FILES, MAX_FILE_BYTES, MAX_BYTES = 256, 4 * 1024**2, 16 * 1024**2
MAX_DECLARATIONS, MAX_OPERATIONS = 256, 512
ANNOTATIONS = {MARKER, 'gxtxt_api_require', 'gxtxt_parameter_declare'}


def _json(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False)


def _sha(value):
    return hashlib.sha256(value).hexdigest()


def _text(value, label, maximum=4096):
    if not isinstance(value, str) or not value or len(value) > maximum or '\x00' in value:
        raise ValueError(f'{label} must be bounded nonempty text without NUL')
    value.encode('utf-8', 'strict')
    return value


def _relative(value, language):
    _text(value, 'source path', 240)
    p = PurePosixPath(value)
    if (p.is_absolute() or str(p) != value or '\\' in value or ':' in value
            or any(not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*', part) or part in {'.', '..'} for part in p.parts)
            or p.suffix != ('.py' if language == 'Python' else '.m')):
        raise ValueError('source path must be a normalized admitted language-relative path')
    return value


def _strings(value, label, pattern=None, maximum=64):
    if not isinstance(value, list) or len(value) > maximum:
        raise ValueError(f'{label} must be a bounded literal list')
    for item in value:
        _text(item, label, 256)
        if pattern and not pattern.fullmatch(item):
            raise ValueError(f'invalid {label}: {item}')
    if len(set(value)) != len(value):
        raise ValueError(f'duplicate {label}')
    return value


def _type(spec, depth=0, field=False):
    if not isinstance(spec, dict) or depth > 8:
        raise ValueError('structured type must be an object with depth <=8')
    allowed = {'kind', 'units', 'description', 'fields', 'items', 'max_items', 'max_length'}
    if field:
        allowed |= {'name', 'required', 'default'}
    if set(spec) - allowed:
        raise ValueError('unknown structured type field')
    kind = spec.get('kind')
    if kind not in KINDS:
        raise ValueError(f'unsupported structured kind: {kind}')
    out = {'kind': kind}
    for key in ('units', 'description'):
        if key in spec:
            out[key] = _text(spec[key], key, 256 if key == 'units' else 4096)
    if 'max_length' in spec:
        if kind != 'string' or type(spec['max_length']) is not int or not 0 <= spec['max_length'] <= 65536:
            raise ValueError('max_length requires string and 0..65536')
        out['max_length'] = spec['max_length']
    if kind == 'array':
        out['items'] = _type(spec.get('items'), depth + 1)
        maximum = spec.get('max_items', 65536)
        if type(maximum) is not int or not 0 <= maximum <= 65536:
            raise ValueError('max_items requires integer 0..65536')
        out['max_items'] = maximum
    elif 'items' in spec or 'max_items' in spec:
        raise ValueError('items/max_items require array')
    if kind == 'object':
        fields = spec.get('fields')
        if not isinstance(fields, list) or len(fields) > 64:
            raise ValueError('object requires <=64 typed fields')
        out['fields'] = [_field(item, depth + 1) for item in fields]
        if len({item['name'] for item in out['fields']}) != len(fields):
            raise ValueError('duplicate object field')
    elif 'fields' in spec:
        raise ValueError('fields requires object')
    return out


def _value(value, spec, depth=0):
    if depth > 8:
        raise ValueError('default exceeds structured depth')
    kind = spec['kind']
    if kind == 'null':
        valid = value is None
    elif kind == 'boolean':
        valid = type(value) is bool
    elif kind == 'integer':
        valid = type(value) is int and -(2**63) <= value < 2**63
    elif kind in {'number', 'double'}:
        import math
        valid = (type(value) is int and -(2**63) <= value < 2**63) or (type(value) is float and math.isfinite(value))
    elif kind == 'string':
        valid = isinstance(value, str) and '\x00' not in value and len(value) <= spec.get('max_length', 65536)
        if valid:
            value.encode('utf-8', 'strict')
    elif kind == 'array':
        valid = isinstance(value, list) and len(value) <= spec['max_items']
        if valid:
            for item in value:
                _value(item, spec['items'], depth + 1)
    else:
        valid = isinstance(value, dict)
        if valid:
            fields = {item['name']: item for item in spec['fields']}
            valid = not (set(value) - set(fields)) and all(not item['required'] or name in value for name, item in fields.items())
            if valid:
                for name, item in value.items():
                    _value(item, fields[name], depth + 1)
    if not valid:
        raise ValueError(f'default does not match finite {kind} type')


def _field(spec, depth=0):
    out = _type(spec, depth, field=True)
    name = spec.get('name')
    if not isinstance(name, str) or not IDENTIFIER.fullmatch(name) or len(name) > 96:
        raise ValueError('typed argument/field needs a bounded identifier')
    required = spec.get('required', True)
    if type(required) is not bool:
        raise ValueError('required must be boolean')
    out.update(name=name, required=required)
    if 'default' in spec:
        _value(spec['default'], out)
        out['default'] = spec['default']
    if not required and 'default' not in out:
        raise ValueError('optional argument/field requires an explicit typed default')
    return out


def _declaration(value, language):
    if not isinstance(value, dict) or set(value) - {'schema', 'id', 'version', 'name', 'operations'}:
        raise ValueError('export requires a literal declaration object with known fields')
    if value.get('schema') != DECLARATION_SCHEMA:
        raise ValueError('unsupported source export schema')
    match = API_ID.fullmatch(value.get('id', '')) if isinstance(value.get('id'), str) else None
    if not match or len(value['id']) > 128 or type(value.get('version')) is not int or int(match[1]) != value['version']:
        raise ValueError('public API ID suffix and positive integer version must agree')
    out = {'schema': DECLARATION_SCHEMA, 'id': value['id'], 'version': value['version'], 'name': value.get('name', value['id']), 'operations': []}
    _text(out['name'], 'API name', 256)
    operations = value.get('operations')
    if not isinstance(operations, list) or not 1 <= len(operations) <= MAX_OPERATIONS:
        raise ValueError('export needs bounded nonempty operations')
    for item in operations:
        allowed = {'id', 'summary', 'implementation', 'arguments', 'result', 'result_contract', 'unit_behavior', 'read_only', 'effects', 'capabilities', 'required_apis'}
        if not isinstance(item, dict) or set(item) - allowed:
            raise ValueError('unknown operation field')
        op = {key: item[key] for key in ('id', 'summary', 'result_contract', 'unit_behavior') if key in item}
        if not isinstance(op.get('id'), str) or not IDENTIFIER.fullmatch(op['id']) or len(op['id']) > 96:
            raise ValueError('operation ID must be a bounded identifier')
        for key in ('summary', 'result_contract', 'unit_behavior'):
            _text(op.get(key), key)
        impl = item.get('implementation')
        if not isinstance(impl, dict) or set(impl) != {'file', 'function'}:
            raise ValueError('implementation requires exactly file/function')
        _relative(impl['file'], language)
        if not isinstance(impl['function'], str) or not re.fullmatch(r'[A-Za-z_]\w*', impl['function'], re.ASCII):
            raise ValueError('implementation function must be a top-level identifier')
        op['implementation'] = dict(impl)
        arguments = item.get('arguments', [])
        if not isinstance(arguments, list) or len(arguments) > 64:
            raise ValueError('arguments must be a bounded ordered list')
        op['arguments'] = [_field(arg) for arg in arguments]
        if len({arg['name'] for arg in op['arguments']}) != len(arguments):
            raise ValueError('duplicate operation argument')
        optional = False
        for arg in op['arguments']:
            if optional and arg['required']:
                raise ValueError('required argument after optional argument')
            optional |= not arg['required']
        op['result'] = _type(item.get('result'))
        if type(item.get('read_only')) is not bool:
            raise ValueError('read_only must be explicit boolean')
        op['read_only'] = item['read_only']
        for key in ('effects', 'capabilities', 'required_apis'):
            if key not in item:
                raise ValueError(f'{key} must be explicit (possibly empty)')
            op[key] = _strings(item[key], key, REQUIREMENT if key == 'required_apis' else CAPABILITY)
        if op['read_only'] and op['effects']:
            raise ValueError('read_only operation cannot declare mutating effects')
        out['operations'].append(op)
    return out


def _literal(node):
    try:
        for item in ast.walk(node):
            if isinstance(item, ast.Dict):
                keys = [ast.literal_eval(key) for key in item.keys]
                if len(set(keys)) != len(keys):
                    raise ValueError('duplicate literal object field')
        return ast.literal_eval(node)
    except (ValueError, TypeError, SyntaxError, RecursionError) as exc:
        raise ValueError('export declaration must be a literal object') from exc


def _python(source, filename):
    tree = ast.parse(source, filename=filename)
    calls, functions, hazards, imports = [], {}, [], []
    bindings = {}
    for item in tree.body:
        names = []
        if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names = [item.name]
        elif isinstance(item, (ast.Assign, ast.AnnAssign)):
            targets = item.targets if isinstance(item, ast.Assign) else [item.target]
            names = [node.id for target in targets for node in ast.walk(target) if isinstance(node, ast.Name)]
        elif isinstance(item, ast.Import):
            names = [alias.asname or alias.name.split('.')[0] for alias in item.names]
        elif isinstance(item, ast.ImportFrom):
            names = [alias.asname or alias.name for alias in item.names]
        for name in names:
            bindings[name] = bindings.get(name, 0) + 1
        if MARKER in names and not (isinstance(item, ast.ImportFrom) and item.module == 'gxtxt' and any(a.name == MARKER and a.asname in (None, MARKER) for a in item.names)):
            raise ValueError('source cannot redefine the export annotation')
    for node in ast.walk(tree):
        if ((isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name == MARKER)
                or (isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store) and node.id == MARKER)
                or (isinstance(node, ast.arg) and node.arg == MARKER)):
            raise ValueError('source cannot shadow the export annotation in any function scope')
        if isinstance(node, ast.ImportFrom) and any(
                (a.name == MARKER and (node.module != 'gxtxt' or node.level != 0 or a.asname not in (None, MARKER)))
                or (a.asname == MARKER and a.name != MARKER) for a in node.names):
            raise ValueError('export annotation must use its canonical unaliased gxtxt binding')
        if isinstance(node, ast.Call) and ((isinstance(node.func, ast.Name) and node.func.id == MARKER) or (isinstance(node.func, ast.Attribute) and node.func.attr == MARKER)):
            if not isinstance(node.func, ast.Name) or len(node.args) != 1 or node.keywords:
                raise ValueError(f'line {node.lineno}: use direct gxtxt_api_export(one literal object)')
            calls.append((node.lineno, _literal(node.args[0])))
    def literal_or_none(node):
        try:
            _json(ast.literal_eval(node))
            return True
        except (ValueError, TypeError, SyntaxError, RecursionError):
            return False
    def annotation_safe(node):
        return node is None or isinstance(node, (ast.Name, ast.Constant))
    def function_header_safe(node):
        annotations = [arg.annotation for arg in node.args.posonlyargs + node.args.args + node.args.kwonlyargs]
        if node.args.vararg: annotations.append(node.args.vararg.annotation)
        if node.args.kwarg: annotations.append(node.args.kwarg.annotation)
        annotations.append(node.returns)
        return not node.decorator_list and all(literal_or_none(x) for x in node.args.defaults + [x for x in node.args.kw_defaults if x is not None]) and all(annotation_safe(x) for x in annotations)
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.setdefault(node.name, []).extend([node] * bindings.get(node.name, 1))
            if not function_header_safe(node):
                hazards.append({'line': node.lineno, 'reason': 'function decorators/defaults/return annotation execute during import'})
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            if isinstance(node, ast.Import):
                imports.extend(alias.name for alias in node.names)
            else:
                prefix = '.' * node.level + (node.module or '')
                imports.append(prefix)
                imports.extend(prefix + ('.' if node.module else '') + alias.name for alias in node.names if alias.name != '*')
        elif isinstance(node, (ast.Assign, ast.AnnAssign)) and getattr(node, 'value', None) is not None and literal_or_none(node.value) and all(isinstance(t, ast.Name) for t in (node.targets if isinstance(node, ast.Assign) else [node.target])):
            if isinstance(node, ast.AnnAssign) and not annotation_safe(node.annotation):
                hazards.append({'line': node.lineno, 'reason': 'annotation executes during import'})
        elif isinstance(node, ast.Expr) and (isinstance(node.value, ast.Constant) or isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name) and node.value.func.id in ANNOTATIONS and all(literal_or_none(arg) for arg in node.value.args) and all(literal_or_none(arg.value) for arg in node.value.keywords)):
            pass
        elif (isinstance(node, ast.If) and not node.orelse and isinstance(node.test, ast.Compare) and isinstance(node.test.left, ast.Name) and node.test.left.id == '__name__' and len(node.test.ops) == 1 and isinstance(node.test.ops[0], ast.Eq) and len(node.test.comparators) == 1 and isinstance(node.test.comparators[0], ast.Constant) and node.test.comparators[0].value == '__main__'):
            pass
        elif isinstance(node, ast.Pass):
            pass
        else:
            hazards.append({'line': node.lineno, 'reason': 'unguarded top-level action is not safe function-module loading'})
    return calls, functions, hazards, imports


def _octave_tokens(source):
    """Literal/comment lexer only; not a replacement Octave syntax compiler."""
    tokens, i, line = [], 0, 1
    while i < len(source):
        char = source[i]
        if char in ' \t\r':
            i += 1; continue
        if char == '\n':
            tokens.append(('newline', '\n', line, i)); line += 1; i += 1; continue
        if source.startswith(('...'), i):
            end = source.find('\n', i)
            if end < 0: break
            line += 1; i = end + 1; continue
        if char in '%#':
            if source.startswith(char + '{', i) and not source[source.rfind('\n', 0, i) + 1:i].strip():
                match = re.search(r'(?m)^\s*' + re.escape(char + '}') + r'\s*(?:\n|$)', source[i + 2:])
                if not match: raise ValueError('unterminated Octave block comment')
                end = i + 2 + match.end(); line += source.count('\n', i, end); i = end; continue
            end = source.find('\n', i); i = len(source) if end < 0 else end; continue
        if char in "'\"":
            # Adjacent identifier/closing delimiter followed by apostrophe is
            # native transpose. Whitespace command-form strings are literals.
            if char == "'" and i and (source[i - 1].isalnum() or source[i - 1] in '_)]}.'):
                tokens.append(('symbol', char, line, i)); i += 1; continue
            start, startline = i, line; i += 1; value = ''
            while i < len(source):
                if source[i] == char:
                    if i + 1 < len(source) and source[i + 1] == char:
                        value += char; i += 2; continue
                    i += 1; break
                if char == '"' and source[i] == '\\':
                    i += 1
                    escapes = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '"': '"', "'": "'"}
                    if i >= len(source) or source[i] not in escapes:
                        raise ValueError('unsupported double-quoted Octave escape; use single-quoted literal JSON')
                    value += escapes[source[i]]; i += 1; continue
                if source[i] == '\n': line += 1
                value += source[i]; i += 1
            else:
                raise ValueError('unterminated Octave string')
            tokens.append(('string', value, startline, start)); continue
        match = re.match(r'[A-Za-z_]\w*', source[i:], re.ASCII)
        if match:
            value = match[0]; tokens.append(('id', value, line, i)); i += len(value); continue
        tokens.append(('symbol', char, line, i)); i += 1
    return tokens


def _octave(source, filename):
    tokens = _octave_tokens(source)
    useful = [token for token in tokens if token[0] != 'newline']
    calls = []
    for i, token in enumerate(useful):
        if token[:2] != ('id', MARKER): continue
        if i and useful[i - 1][1] in {'.', 'function'}:
            raise ValueError('qualified/shadowed Octave export annotation is unsupported')
        if i + 3 >= len(useful) or [useful[i + 1][1], useful[i + 2][0], useful[i + 3][1]] != ['(', 'string', ')']:
            raise ValueError(f'line {token[2]}: export needs exactly one literal JSON string')
        def unique(pairs):
            out = {}
            for key, value in pairs:
                if key in out: raise ValueError('duplicate JSON declaration field')
                out[key] = value
            return out
        value = json.loads(useful[i + 2][1], object_pairs_hook=unique, parse_constant=lambda text: (_ for _ in ()).throw(ValueError('nonfinite JSON literal')))
        calls.append((token[2], value))
    functions, hazards = {}, []
    if useful and useful[0][:2] == ('id', 'function'):
        # Native function-file binding is only its first primary function, whose
        # basename identity is already part of the admitted Project contract.
        start = next(i for i, t in enumerate(tokens) if t[0] != 'newline')
        end = next((i for i in range(start, len(tokens)) if tokens[i][0] == 'newline' or tokens[i][1] == ';'), len(tokens))
        header = ''.join(t[1] for t in tokens[start:end])
        match = re.fullmatch(r'function(?:([A-Za-z_]\w*)=)([A-Za-z_]\w*)\(([^()]*)\)', header, re.ASCII)
        if match and match[2] == PurePosixPath(filename).stem:
            names = match[3].split(',') if match[3] else []
            if all(re.fullmatch(r'[A-Za-z_]\w*', name, re.ASCII) and name not in {'varargin', 'varargout'} for name in names) and len(set(names)) == len(names):
                functions[match[2]] = [{'line': useful[0][2], 'parameters': names, 'signature': f'{match[2]}({", ".join(names)})'}]
        if not functions:
            hazards.append({'line': useful[0][2], 'reason': 'unsupported primary function signature; require filename-matched, one output and finite named arguments'})
    elif useful:
        hazards.append({'line': useful[0][2], 'reason': 'Octave script top-level actions cannot be loaded as a primary function module'})
    if functions:
        stack, delimiters = [], 0
        opens = {'function', 'if', 'for', 'parfor', 'while', 'switch', 'try', 'unwind_protect', 'do'}
        closes = {'end', 'endfunction', 'endif', 'endfor', 'endwhile', 'endswitch', 'end_try_catch', 'end_unwind_protect', 'until'}
        warned = set()
        for kind, value, line, _ in tokens:
            if kind == 'newline': continue
            if kind == 'symbol' and value in '([{': delimiters += 1
            elif kind == 'symbol' and value in ')]}': delimiters = max(0, delimiters - 1)
            if kind == 'id' and not delimiters and value in opens:
                stack.append(value)
            elif kind == 'id' and not delimiters and value in closes:
                if stack: stack.pop()
            elif not stack and value not in {';', ','} and line not in warned:
                hazards.append({'line': line, 'reason': 'unguarded action outside Octave primary/local functions'})
                warned.add(line)
    return calls, functions, hazards, []


def inventory(language, entrypoint, sources):
    """Return deterministic static inventory; errors are data, never publication.

    ``sources`` maps normalized admitted project paths to exact UTF-8 strings or
    bytes. This function never reads those paths from the filesystem.
    """
    result = {'schema': SCHEMA, 'language': language if isinstance(language, str) else '', 'entrypoint': entrypoint if isinstance(entrypoint, str) else '',
              'provided': [], 'operations': [], 'consumed': [], 'files': [],
              'diagnostics': [], 'valid': False, 'declaration_sha256': '', 'discovery_scope': 'static_in_memory_runtime_validation_required'}
    def diagnostic(code, message, file='', line=0, severity='error'):
        result['diagnostics'].append(dict(code=code, message=str(message), file=file, line=line, severity=severity))
    try:
        if language not in {'Python', 'Octave'}:
            raise ValueError('language must be Python or Octave')
        _relative(entrypoint, language)
        if not isinstance(sources, dict) or not 1 <= len(sources) <= MAX_FILES or entrypoint not in sources:
            raise ValueError('require in-memory entrypoint and 1..256 sources')
        total, seen, prefixes, bodies, parsed = 0, set(), {}, {}, {}
        declarations, consumed = [], set()
        for filename, body in sorted(sources.items()):
            _relative(filename, language)
            if filename.casefold() in seen: raise ValueError('case-colliding admitted source path')
            seen.add(filename.casefold())
            parts = PurePosixPath(filename).parts
            for n in range(1, len(parts) + 1):
                prefix = '/'.join(parts[:n]); fold = prefix.casefold()
                if fold in prefixes and prefixes[fold] != prefix: raise ValueError('case-colliding admitted directory')
                prefixes[fold] = prefix
            if not isinstance(body, (str, bytes)):
                raise ValueError('source body must be UTF-8 text/bytes')
            data = body.encode('utf-8', 'strict') if isinstance(body, str) else body
            total += len(data)
            if len(data) > MAX_FILE_BYTES or total > MAX_BYTES: raise ValueError('source size exceeds 4MiB/file or 16MiB/project')
            source = data.decode('utf-8-sig', 'strict')
            if '\x00' in source: raise ValueError('source contains NUL')
            bodies[filename] = source
            record = dict(path=filename, sha256=_sha(data), size=len(data), load_hazards=[])
            result['files'].append(record)
            try:
                calls, functions, hazards, imports = (_python if language == 'Python' else _octave)(source, filename)
                record['load_hazards'] = hazards
                parsed[filename] = dict(functions=functions, hazards=hazards, imports=imports)
                consumed.update(discover_consumed(source, language, filename, project_policy=True))
                for line, value in calls:
                    if len(declarations) >= MAX_DECLARATIONS: raise ValueError('too many export declarations')
                    declarations.append((filename, line, _declaration(value, language)))
            except (ValueError, TypeError, SyntaxError, RecursionError) as exc:
                diagnostic('INVALID_SOURCE_DECLARATION', exc, filename, getattr(exc, 'lineno', 0) or 0)
        result['consumed'] = sorted(consumed)
        groups, versions, operations = {}, {}, {}
        pins = {record['path']: record for record in result['files']}
        modules = {str(PurePosixPath(path).with_suffix('')).replace('/', '.'): path for path in sources}
        modules.update({name[:-9]: path for name, path in list(modules.items()) if name.endswith('.__init__')})
        def unsafe_closure(filename, visited=None):
            visited = set() if visited is None else visited
            if filename in visited: return []
            visited.add(filename)
            info = parsed.get(filename)
            if info is None: return [{'file': filename, 'line': 0, 'reason': 'implementation source did not parse'}]
            found = [dict(item, file=filename) for item in info['hazards']]
            if language == 'Python':
                parts = PurePosixPath(filename).parts[:-1]
                for n in range(1, len(parts) + 1):
                    init = '/'.join(parts[:n]) + '/__init__.py'
                    if init in parsed:
                        found.extend(unsafe_closure(init, visited))
            for module in info['imports']:
                if module.startswith('.'):
                    level = len(module) - len(module.lstrip('.'))
                    package = list(PurePosixPath(filename).parts[:-1])
                    if level > len(package):
                        found.append({'file': filename, 'line': 0, 'reason': 'relative import escapes admitted package context'}); continue
                    module = '.'.join(package[:len(package) - level + 1] + [module.lstrip('.')]).strip('.')
                if module in modules:
                    found.extend(unsafe_closure(modules[module], visited))
                # Importing a submodule also runs admitted package __init__.
                bits = module.split('.')
                for n in range(1, len(bits)):
                    init = '/'.join(bits[:n]) + '/__init__.py'
                    if init in parsed: found.extend(unsafe_closure(init, visited))
            return found
        for filename, line, declaration in declarations:
            api, version = declaration['id'], declaration['version']
            base = api.rsplit('_v', 1)[0]
            if base in versions and versions[base] != version:
                diagnostic('API_VERSION_CONFLICT', f'conflicting source versions for {base}', filename, line)
            versions[base] = version
            if api in groups and groups[api]['name'] != declaration['name']:
                diagnostic('API_METADATA_CONFLICT', f'conflicting API names for {api}', filename, line)
            group = groups.setdefault(api, {key: declaration[key] for key in ('id', 'version', 'name')})
            group.setdefault('operations', [])
            for op in declaration['operations']:
                if len(operations) >= MAX_OPERATIONS:
                    diagnostic('OPERATION_BOUND', 'too many whole-project operations', filename, line); break
                key = (api, op['id'])
                if key in operations:
                    diagnostic('DUPLICATE_OPERATION', f'duplicate {api}:{op["id"]}', filename, line); continue
                impl = op['implementation']; target = impl['file']
                bound = dict(op, api_id=api, api_version=version, declaration_file=filename, declaration_line=line, declaration_file_sha256=pins[filename]['sha256'])
                bound['implementation'] = dict(impl)
                operations[key] = bound
                group['operations'].append(op['id'])
                if target not in parsed:
                    diagnostic('IMPLEMENTATION_MISSING', f'unadmitted implementation file {target}', filename, line); continue
                candidates = parsed[target]['functions'].get(impl['function'], [])
                if len(candidates) != 1:
                    diagnostic('IMPLEMENTATION_AMBIGUOUS', 'require one genuine callable top-level/primary function', target); continue
                node = candidates[0]
                if language == 'Python':
                    components = list(PurePosixPath(target).parts[:-1]) + [PurePosixPath(target).stem]
                    if any(not re.fullmatch(r'[A-Za-z_]\w*', name, re.ASCII) or keyword.iskeyword(name) for name in components):
                        diagnostic('UNIMPORTABLE_IMPLEMENTATION', 'implementation path must name a genuine Python module/package', target); continue
                    bound['implementation']['module'] = '.'.join(components[:-1] if components[-1] == '__init__' else components)
                    args = node.args
                    if isinstance(node, ast.AsyncFunctionDef) or node.decorator_list or args.vararg or args.kwarg or args.kwonlyargs:
                        diagnostic('UNSUPPORTED_SIGNATURE', 'async/decorated/variadic/keyword-only export is unsupported', target, node.lineno); continue
                    names = [arg.arg for arg in args.posonlyargs + args.args]
                    impl_line = node.lineno
                    signature = f'{node.name}({", ".join(names)})'
                    for parameter, default in zip(names[len(names) - len(args.defaults):], args.defaults):
                        declaration_arg = next((a for a in op['arguments'] if a['name'] == parameter), None)
                        if declaration_arg and not declaration_arg['required'] and _json(_literal(default)) != _json(declaration_arg['default']):
                            diagnostic('DEFAULT_MISMATCH', 'declared optional default differs from implementing signature', target, node.lineno)
                else:
                    names, impl_line, signature = node['parameters'], node['line'], node['signature']
                if names != [arg['name'] for arg in op['arguments']]:
                    diagnostic('SIGNATURE_MISMATCH', 'ordered argument names differ from implementation', target, impl_line)
                hazards = unsafe_closure(target)
                for hazard in hazards:
                    diagnostic('UNSAFE_FUNCTION_LOAD', hazard['reason'], hazard['file'], hazard['line'])
                bound['implementation'].update(line=impl_line, sha256=pins[target]['sha256'], signature=signature)
        result['provided'] = [dict(groups[key], operations=sorted(groups[key]['operations'])) for key in sorted(groups)]
        result['operations'] = [operations[key] for key in sorted(operations)]
        # Main scripts with ordinary unguarded Analysis actions remain useful,
        # but must never be used as implicit function loaders. Report them even
        # when all exported operations are implemented in safe helper files.
        for record in result['files']:
            for hazard in record['load_hazards']:
                if not any(d['file'] == record['path'] and d['line'] == hazard['line'] and d['code'] == 'UNSAFE_FUNCTION_LOAD' for d in result['diagnostics']):
                    diagnostic('NON_IMPLEMENTATION_LOAD_HAZARD', hazard['reason'], record['path'], hazard['line'], 'warning')
        result['valid'] = not any(d['severity'] == 'error' for d in result['diagnostics'])
    except (ValueError, TypeError, SyntaxError, UnicodeError, RecursionError) as exc:
        diagnostic('INVALID_SOURCE_INPUT', exc)
    result['diagnostics'].sort(key=lambda d: (d['file'], d['line'], d['code'], d['message']))
    result['declaration_sha256'] = _sha(_json({key: result[key] for key in ('language', 'entrypoint', 'files', 'provided', 'operations', 'consumed')}).encode('utf-8'))
    return result


def discover_project_exports(language, entrypoint, sources):
    """Named public-owner seam; alias of the static in-memory inventory."""
    return inventory(language, entrypoint, sources)
