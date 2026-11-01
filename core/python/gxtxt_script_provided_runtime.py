"""Provided function admission/projection inside the existing Script Job runner.

Static inspection never executes source. Execution is called only by the normal
language runner after its supervised immutable Project snapshot was admitted.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import configparser
import hashlib
import importlib
import json
from pathlib import Path
import sys
from script_api_exports import inventory, _value
from script_project import manifest, safe_read, relative, verify
from script_api_declarations import tcl

MAX_CONTROL = 1048576

def _pairs(items):
    result = {}
    for key, value in items:
        if key in result: raise ValueError('Duplicate provided API JSON field')
        result[key] = value
    return result

def loads(text):
    if len(text.encode('utf-8')) > MAX_CONTROL: raise ValueError('Provided API control exceeds1MiB')
    return json.loads(text, object_pairs_hook=_pairs,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError('Nonfinite provided API JSON')))

def dumps(value):
    text = json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(',', ':'))
    if len(text.encode('utf-8')) > MAX_CONTROL: raise ValueError('Provided API control exceeds1MiB')
    return text

def _ordinary(root, name, maximum=MAX_CONTROL):
    path = root
    if root.is_symlink() or not root.is_dir(): raise ValueError('Provided module root must be ordinary')
    from pathlib import PurePosixPath
    p = PurePosixPath(name)
    if p.is_absolute() or str(p) != name or not name or any(x in {'.', '..'} for x in p.parts) or '\\' in name:
        raise ValueError('Unsafe provided module path')
    for part in p.parts:
        path = path / part
        if path.is_symlink(): raise ValueError('Provided module links are forbidden')
    if not path.is_file() or path.stat().st_size > maximum: raise ValueError('Missing or oversized provided module file')
    return path.read_bytes()

def inspect_package(root, module_id, api_id, operation, arguments_json):
    root = Path(root)
    descriptor = _ordinary(root, 'module.ini')
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read_string(descriptor.decode('utf-8'))
    if cfg['meta']['id'] != module_id: raise ValueError('Provided module identity differs')
    script = cfg['script'];language = script['language']
    entry = relative(script['provided_entrypoint'], language)
    declared_raw = _ordinary(root, script['provided_manifest'])
    declared_sha = hashlib.sha256(declared_raw).hexdigest()
    if declared_sha != script['provided_manifest_sha256']: raise ValueError('Provided operation manifest SHA differs')
    declared = loads(declared_raw.decode('utf-8'))
    sources = {}
    for record in declared.get('files', []):
        name = relative(record['path'], language)
        if name in sources: raise ValueError('Duplicate provided source path')
        sources[name] = _ordinary(root / 'bundle', name, 4194304)
    actual = inventory(language, entry, sources)
    if not actual['valid'] or not actual['provided'] or actual != declared:
        raise ValueError('Provided manifest differs from its exact static source inventory')
    # Every language source in the normal bundle checksum owner must be in the
    # declaration closure; arbitrary assets retain the ordinary bundle owner.
    bundle_inventory = _ordinary(root, script.get('bundle_inventory', 'bundle/SHA256SUMS'))
    suffix = '.py' if language == 'Python' else '.m'
    listed = {}
    for line in bundle_inventory.decode('utf-8').splitlines():
        if not line: continue
        sha, sep, name = line.partition('  ')
        if not sep or name in listed or len(sha) != 64: raise ValueError('Invalid bundle inventory')
        raw = _ordinary(root / 'bundle', name, 16777216)
        if hashlib.sha256(raw).hexdigest() != sha: raise ValueError('Bundle source/asset SHA differs')
        listed[name] = sha
    if {name for name in listed if name.endswith(suffix)} != set(sources): raise ValueError('Provided source closure omits bundled language source')
    project, consumed, _ = manifest(language, entry, sources)
    matches = [op for op in actual['operations'] if op['api_id'] == api_id and op['id'] == operation]
    if len(matches) != 1: raise ValueError('Provided API operation is not declared uniquely')
    op = matches[0];arguments = normalize_arguments(loads(arguments_json), op)
    declared_required = [token.strip() for token in script.get('required_apis', '').replace(',', ';').split(';') if token.strip()]
    required = sorted(set(consumed + op['required_apis'] + declared_required))
    pins = dict(descriptor_sha256=hashlib.sha256(descriptor).hexdigest(),
                provided_manifest_sha256=declared_sha, bundle_inventory_sha256=hashlib.sha256(bundle_inventory).hexdigest(),
                project_sha256=project['sha256'])
    from gxtxt_script_bridge_server import encode_value
    octave_plan = dict(function=op['implementation']['function'], file=op['implementation']['file'], result_type=op['result'],
                       arguments_wire=[encode_value(arguments[field['name']]) for field in op['arguments']])
    return dict(octave_plan_json=dumps(octave_plan), language=language, entrypoint=entry, project_sha256=project['sha256'],
                sources={name: raw.decode('utf-8') for name, raw in sources.items()},
                required_apis=';'.join(required), pins=pins, manifest_json=dumps(actual), operation_schema=op,
                request_json=dumps(dict(schema='gxtxt.script_provided_invocation.v1', module_id=module_id,
                    api_id=api_id, operation=operation, arguments=arguments, pins=pins)))

def bridge_arguments_json(values, operation):
    """Project admitted Bridge control values through the declared argument type.

    This adapter grants no authority and opens no arbitrary files. Resource
    arrays retain the existing Bridge reader and are bounded before loading.
    """
    from gxtxt_script_bridge_server import NumericArray
    import math
    budget = [262144]
    def shape_fits(spec, shape):
        if not shape: return spec['kind'] != 'array'
        return (spec['kind'] == 'array' and shape[0] <= spec['max_items']
                and shape_fits(spec['items'], shape[1:]))
    def convert(value, spec, depth=0):
        budget[0] -= 1
        if depth > 8 or budget[0] < 0: raise ValueError('Provided argument structure exceeds declared depth/node bound')
        if isinstance(value, NumericArray):
            shape = value.shape
            if (spec['kind'] != 'array' or not shape or len(shape) > 8
                    or any(type(n) is not int or n < 0 for n in shape)):
                raise ValueError('Numeric Bridge array requires its actual declared array shape')
            count = math.prod(shape)
            if spec['items']['kind'] != 'array':
                if sum(n > 1 for n in shape) > 1 or count > spec['max_items']:
                    raise ValueError('Declared control vector cannot erase a matrix shape or exceed its bound')
            elif not shape_fits(spec, shape):
                raise ValueError('Numeric Bridge matrix differs from the declared nested array shape/bounds')
            if count > 65536 or count > budget[0]: raise ValueError('Provided control array exceeds its bounded control budget; use its scientific resource owner')
            raw = value.values
            if spec['items']['kind'] == 'array':
                if not hasattr(raw, 'reshape'): raise ValueError('Typed nested Bridge arrays require their existing native adapter')
                value = raw.reshape(shape, order='F').tolist()
            else: value = raw.tolist() if hasattr(raw, 'tolist') else list(raw)
        if spec['kind'] == 'object' and isinstance(value, dict):
            fields = {field['name']: field for field in spec['fields']}
            if set(value) - set(fields): raise ValueError('Unknown provided object argument field')
            value = {name: convert(item, fields[name], depth+1) for name, item in value.items()}
        elif spec['kind'] == 'array' and isinstance(value, list):
            if len(value) > spec['max_items']: raise ValueError('Provided argument array exceeds its declared bound')
            value = [convert(item, spec['items'], depth+1) for item in value]
        _value(value, spec)
        return value
    if not isinstance(values, dict): raise ValueError('Provided arguments require a field object')
    fields = {field['name']: field for field in operation['arguments']}
    if set(values) - set(fields): raise ValueError('Unknown provided operation argument')
    converted = {name: convert(value, fields[name]) for name, value in values.items()}
    return dumps(normalize_arguments(converted, operation))

def normalize_arguments(arguments, operation):
    if not isinstance(arguments, dict): raise ValueError('Provided API requires an argument object')
    definitions = {field['name']: field for field in operation['arguments']}
    if set(arguments) - set(definitions): raise ValueError('Unknown provided API argument')
    result = {}
    for name, field in definitions.items():
        if name in arguments: value = arguments[name]
        elif not field['required']: value = field['default']
        else: raise ValueError('Missing provided API argument: ' + name)
        _value(value, field);result[name] = value
    return result

def frozen_operation(config, project):
    section = config['provided_api'];request = loads(section['request_json'])
    if request.get('schema') != 'gxtxt.script_provided_invocation.v1': raise ValueError('Unsupported provided invocation')
    if request['pins']['project_sha256'] != project['sha256']: raise ValueError('Provided Project snapshot changed')
    root = Path(config['script_project']['project_root'])
    sources = {record['path']: safe_read(root, record['path']) for record in project['files']}
    actual = inventory(project['language'], project['entrypoint'], sources)
    if not actual['valid'] or dumps(actual) != section['manifest_json']: raise ValueError('Frozen provided manifest/source differs')
    operations = [op for op in actual['operations'] if op['api_id'] == request['api_id'] and op['id'] == request['operation']]
    if len(operations) != 1: raise ValueError('Frozen provided operation is unavailable')
    op = operations[0];arguments = normalize_arguments(request['arguments'], op)
    return request, op, arguments

def execute_python(config, project, outdir):
    if project is None: raise ValueError('Provided operation requires an exact Project snapshot')
    request, op, arguments = frozen_operation(config, project)
    import builtins
    sentinel = object();previous = getattr(builtins, 'gxtxt_api_export', sentinel)
    builtins.gxtxt_api_export = lambda declaration: None
    try:
        module = importlib.import_module(op['implementation']['module'])
        function = getattr(module, op['implementation']['function'])
        if not callable(function): raise ValueError('Declared provided function is not callable')
        result = function(*(arguments[field['name']] for field in op['arguments']))
        _value(result, op['result'])
        receipt = dict(schema='gxtxt.script_provided_result.v1', module_id=request['module_id'],
                       api_id=request['api_id'], operation=request['operation'], pins=request['pins'], result=result)
        encoded = dumps(receipt)
        with (outdir / 'provided_api_result.json').open('x', encoding='utf-8') as stream: stream.write(encoded+'\n')
    finally:
        if previous is sentinel: del builtins.gxtxt_api_export
        else: builtins.gxtxt_api_export = previous

def read_octave_result(runtime):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(runtime, encoding='utf-8')
    project, _, _ = verify(Path(config['script_project']['project_manifest']).parent)
    request, op, _ = frozen_operation(config, project)
    outdir = Path(config['runtime']['output_dir'])
    raw = _ordinary(outdir, 'provided_api_result_wire.json')
    from gxtxt_script_bridge_server import decode_value
    result = decode_value(loads(raw.decode('utf-8')))
    _value(result, op['result'])
    encoded = dumps(dict(schema='gxtxt.script_provided_result.v1', module_id=request['module_id'],
                         api_id=request['api_id'], operation=request['operation'], pins=request['pins'], result=result))
    path = outdir / 'provided_api_result.json'
    try:
        with path.open('x', encoding='utf-8') as stream: stream.write(encoded+'\n')
    except FileExistsError:
        if _ordinary(outdir, path.name).decode('utf-8') != encoded+'\n': raise ValueError('Provided result receipt already occupied')
    return encoded

def main():
    action = sys.argv[1]
    if action == 'inspect':
        if len(sys.argv) != 6: raise ValueError('Expected module root, ID, API and operation')
        print(tcl(inspect_package(*sys.argv[2:], sys.stdin.read(MAX_CONTROL+1))))
    elif action == 'read_octave_result' and len(sys.argv) == 3:
        print(read_octave_result(sys.argv[2]))
    else: raise ValueError('Unknown provided runtime preparation action')

if __name__ == '__main__': main()
