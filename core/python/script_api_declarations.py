#!/usr/bin/env python3
"""Discover literal GX-TXT API requirements without executing script source."""
from __future__ import annotations

import ast
from pathlib import Path
import re
import sys
import json
import math

PARAMETER_TYPES = {'string', 'integer', 'double', 'number', 'boolean', 'choice', 'color', 'path', 'file', 'command'}


def tcl(value):
    """Encode inert Tcl data, including nested dictionaries; never Tcl source."""
    if isinstance(value, dict):
        return ' '.join(tcl(str(k)) + ' ' + (tcl(tcl(v)) if isinstance(v,(dict,list,tuple)) else tcl(v)) for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return ' '.join(tcl(tcl(v)) if isinstance(v,(dict,list,tuple)) else tcl(v) for v in value)
    if value is None:
        value = ''
    if isinstance(value, bool):
        value = int(value)
    value = str(value)
    if not value:
        return '{}'
    controls={'\n':r'\n','\r':r'\r','\t':r'\t'}
    return ''.join(controls[c] if c in controls else '\\' + c if c in ' \\{}[]$;"' else c for c in value)


def descriptor(name, kind, options):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
        raise ValueError('Parameter name must be a literal identifier')
    if kind not in PARAMETER_TYPES:
        raise ValueError(f'Unsupported parameter type: {kind}')
    if set(options) - {'required', 'default', 'description', 'values', 'min', 'max', 'alpha', 'allow_inherit'}:
        raise ValueError('Unsupported parameter constraint')
    result = dict(type=kind, required=False, default='', description='', **{})
    result.update(options)
    if type(result['required']) not in (bool, int) or result['required'] not in (0, 1):
        raise ValueError('required must be a literal boolean')
    if not isinstance(result['description'], str) or '\n' in result['description'] or '\r' in result['description']:
        raise ValueError('description must be a single-line literal string')
    value = result['default']
    if isinstance(value,str) and any(c in value for c in '\x00\r\n'):
        raise ValueError('default must be one line without NUL')
    if value != '':
        if kind == 'integer' and (type(value) is not int):
            raise ValueError('integer default must be an integer literal')
        if kind in {'number', 'double'} and (type(value) not in (int, float) or not math.isfinite(value)):
            raise ValueError('numeric default must be finite')
        if kind == 'boolean' and (type(value) not in (bool, int) or value not in (0, 1)):
            raise ValueError('boolean default must be true/false')
    for key in ('min', 'max'):
        if key in result and (kind not in {'integer', 'number', 'double'} or type(result[key]) not in (int, float) or not math.isfinite(result[key])):
            raise ValueError('min/max require finite numeric constraints')
    if 'min' in result and 'max' in result and result['min'] > result['max']:
        raise ValueError('min exceeds max')
    if value != '' and kind in {'integer', 'number', 'double'}:
        if value < result.get('min', -math.inf) or value > result.get('max', math.inf):
            raise ValueError('default is outside min/max')
    if kind == 'choice':
        choices = result.get('values')
        if not isinstance(choices, (list, tuple)) or not choices or not all(isinstance(x, str) for x in choices) or len(set(choices)) != len(choices):
            raise ValueError('choice requires distinct literal string values')
        if value != '' and value not in choices:
            raise ValueError('choice default is absent from values')
    elif 'values' in result:
        raise ValueError('values is supported only for choice parameters')
    for flag in ('alpha','allow_inherit'):
        if flag in result and (type(result[flag]) not in (bool,int) or result[flag] not in (0,1)):
            raise ValueError(f'{flag} must be a literal boolean')
    if 'alpha' in result and kind!='color':raise ValueError('alpha is supported only for color parameters')
    if kind=='color' and value!='' and not re.fullmatch(r'#[0-9A-Fa-f]{6}',str(value)):
        raise ValueError('color default must be #RRGGBB')
    if type(value) not in (str, int, float, bool):
        raise ValueError('default must be a scalar literal')
    return result


def octave_parameter_calls(source):
    """Small lexical reader for native name/value declarations, never eval."""
    token = re.compile(r"\s*(?:(?P<string>'(?:[^']|'')*'|\"(?:[^\"\\]|\\.|\"\")*\")|(?P<number>[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)|(?P<bool>true|false)\b|(?P<symbol>[{},();]))")
    # Mask comments/ordinary strings while retaining offsets for diagnostics.
    i = 0
    while i < len(source):
        if source.startswith(('%{', '#{'), i):
            end = source.find(source[i] + '}', i + 2)
            if end < 0: return
            i = end + 2; continue
        if source[i] in '%#':
            end = source.find('\n', i); i = len(source) if end < 0 else end + 1; continue
        if source[i] in "'\"":
            if source[i]=="'" and i>0 and (source[i-1].isalnum() or source[i-1] in '_)]}.'):
                i+=1;continue  # Native transpose, not the start of a string.
            match = token.match(source, i)
            if match and match.group('string'): i = match.end(); continue
        match = re.match(r'gxtxt_parameter_declare\b', source[i:])
        if match and (i == 0 or not (source[i-1].isalnum() or source[i-1] == '_')):
            line = source.count('\n', 0, i) + 1
            pos = i + match.end(); tokens = []
            while True:
                continuation = re.match(r'\s*\.\.\.[^\n]*(?:\n|$)', source[pos:])
                if continuation:
                    pos += continuation.end()
                    continue
                item = token.match(source, pos)
                if not item: raise ValueError(f'line {line}: declaration arguments must be literal native values')
                pos = item.end(); symbol = item.group('symbol')
                if not tokens and symbol != '(': raise ValueError(f'line {line}: expected declaration call')
                tokens.append(item)
                if symbol == ')': break
            def value_at(n):
                item = tokens[n]
                if item.group('string'):
                    s = item.group('string');value=s[1:-1].replace(s[0]*2,s[0])
                    if s[0]=='"':
                        escapes={'a':'\a','b':'\b','f':'\f','n':'\n','r':'\r','t':'\t','v':'\v','\\':'\\','"':'"',"'":"'"}
                        def unescape(match):
                            char=match.group(1)
                            if char not in escapes:raise ValueError('Unsupported Octave escape in declaration; use a literal single-quoted string')
                            return escapes[char]
                        value=re.sub(r'\\(.)',unescape,value)
                    return value,n+1
                if item.group('number'):
                    s = item.group('number'); return float(s) if any(c in s for c in '.eE') else int(s), n+1
                if item.group('bool'): return item.group('bool') == 'true', n+1
                if item.group('symbol') == '{':
                    values=[]; n+=1
                    while tokens[n].group('symbol') != '}':
                        v,n=value_at(n); values.append(v)
                        if tokens[n].group('symbol') in {',',';'}: n+=1
                        elif tokens[n].group('symbol') != '}': raise ValueError('expected cell separator')
                    return values,n+1
                raise ValueError('expected literal value')
            args=[]; n=1
            while tokens[n].group('symbol') != ')':
                v,n=value_at(n); args.append(v)
                if tokens[n].group('symbol') == ',': n+=1
                elif tokens[n].group('symbol') != ')': raise ValueError(f'line {line}: expected comma')
            if len(args)<2 or len(args)%2: raise ValueError(f'line {line}: use name,type followed by name/value constraints')
            opts={}
            for n in range(2,len(args),2):
                if not isinstance(args[n],str) or args[n] in opts: raise ValueError(f'line {line}: duplicate/invalid option')
                opts[args[n]]=args[n+1]
            yield line,args[0],args[1],opts
            i=pos; continue
        i+=1


def discover_parameters(source, language, filename='<source>'):
    found={}
    if language == 'Python':
        calls=[]
        for node in ast.walk(ast.parse(source, filename=filename)):
            if isinstance(node,ast.ImportFrom) and node.module=='gxtxt' and any(a.name=='gxtxt_parameter_declare' and a.asname not in (None,'gxtxt_parameter_declare') for a in node.names):
                raise ValueError(f'{filename}:{node.lineno}: declaration aliases are unsupported; use gxtxt_parameter_declare directly')
            if isinstance(node,ast.Call) and ((isinstance(node.func,ast.Name) and node.func.id=='gxtxt_parameter_declare') or (isinstance(node.func,ast.Attribute) and node.func.attr=='gxtxt_parameter_declare')):
                try:
                    if len(node.args)!=2 or any(k.arg is None for k in node.keywords): raise ValueError('use two positional literal arguments and literal keyword constraints')
                    options={}
                    for key in node.keywords:
                        if key.arg in options: raise ValueError('duplicate keyword')
                        options[key.arg]=ast.literal_eval(key.value)
                    calls.append((node.lineno,ast.literal_eval(node.args[0]),ast.literal_eval(node.args[1]),options))
                except (ValueError,TypeError,SyntaxError) as exc:
                    raise ValueError(f'{filename}:{node.lineno}: malformed parameter declaration: {exc}') from exc
    elif language == 'Octave': calls=octave_parameter_calls(source)
    else: raise ValueError('Unsupported declaration language')
    for line,name,kind,options in calls:
        try:
            if name in found: raise ValueError(f'duplicate parameter {name}')
            spec=descriptor(name,kind,options)
            spec.update(origin='source',source_file=filename,source_line=line)
            found[name]=spec
        except (ValueError,TypeError) as exc: raise ValueError(f'{filename}:{line}: {exc}') from exc
    return found

REQUIREMENT = re.compile(r"[A-Za-z0-9_]+(?:@[0-9]+)?(?::[A-Za-z0-9._-]+)?(?:\+[A-Za-z0-9_|.-]+)?\Z")
OCTAVE_CALL = re.compile(
    r"gxtxt_api_require\s*\(\s*(\{(?:\s|[,;]|'[^']*'|\"[^\"]*\")*\}|'[^']*'|\"[^\"]*\")\s*\)",
    re.DOTALL,
)
OCTAVE_STRING = re.compile(r"'([^']*)'|\"([^\"]*)\"")


def octave_literal_calls(source: str, project_policy=False):
    """Find literal calls outside Octave comments and quoted source text."""
    i = 0
    block = None
    while i < len(source):
        if block is not None:
            end = source.find(block, i)
            if end < 0:
                return
            i = end + len(block)
            block = None
            continue
        if source.startswith(("%{", "#{"), i) and not source[source.rfind("\n", 0, i) + 1:i].strip():
            block = source[i] + "}"
            i += 2
            continue
        char = source[i]
        if char in "%#":
            end = source.find("\n", i)
            i = len(source) if end < 0 else end + 1
            continue
        if char in "'\"":
            if char=="'" and i>0 and (source[i-1].isalnum() or source[i-1] in '_)]}.'):
                i+=1;continue
            quote = char
            i += 1
            while i < len(source):
                if source[i] == quote:
                    if i + 1 < len(source) and source[i + 1] == quote:
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if project_policy and (i==0 or not (source[i-1].isalnum() or source[i-1] in '_.')):
            loader=re.match(r'(?:addpath|rmpath)\s*\(|(?:source|run|path)\s*\(\s*[\'\"]',source[i:])
            if loader:raise ValueError(f'line {source.count(chr(10),0,i)+1}: project source search paths/loaders are managed by the manifest; use admitted helpers or configured runtime packages')
        if source.startswith("gxtxt_api_require", i) and (i == 0 or not (source[i - 1].isalnum() or source[i - 1] == "_")):
            call = OCTAVE_CALL.match(source, i)
            if call:
                yield call.group(1)
                i = call.end()
                continue
        i += 1


def literals(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)) and all(isinstance(item, str) for item in value):
        return list(value)
    return []


def discover(source: str, language: str, filename='<source>', project_policy=False) -> list[str]:
    found = []
    if language == "Python":
        tree = ast.parse(source,filename=filename)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name) or node.func.id != "gxtxt_api_require" or not node.args:
                continue
            try:
                found.extend(literals(ast.literal_eval(node.args[0])))
            except (ValueError, TypeError, SyntaxError, MemoryError, RecursionError):
                continue
    elif language == "Octave":
        for argument in octave_literal_calls(source,project_policy):
            found.extend(a or b for a, b in OCTAVE_STRING.findall(argument))
    else:
        raise ValueError(f"Unsupported script language: {language}")
    for item in found:
        if not REQUIREMENT.fullmatch(item):
            raise ValueError(f"Invalid literal GX-TXT API requirement: {item}")
    return sorted(set(found))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4, 5):
        raise SystemExit("usage: script_api_declarations.py LANGUAGE SOURCE_PATH")
    code = Path(sys.argv[2]).read_text(encoding="utf-8-sig")
    if len(sys.argv)>=4 and sys.argv[3]=='--parameters':
        values=discover_parameters(code,sys.argv[1],sys.argv[4] if len(sys.argv)==5 else Path(sys.argv[2]).name)
        print(' '.join(tcl(name)+' '+tcl(tcl(spec)) for name,spec in values.items()))
    else:
        print(";".join(discover(code, sys.argv[1])))
