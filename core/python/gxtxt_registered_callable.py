"""Run a declared callable in its existing supervised Script Bridge lifetime."""
# SPDX-License-Identifier: GPL-3.0-or-later
import json
import re
import numpy as np
import gxtxt


def _receipt_value(value, depth=0, budget=None):
    if budget is None:
        budget = [4096]
    budget[0] -= 1
    if depth > 16 or budget[0] < 0:
        raise ValueError('Callable result must be a bounded control receipt; retain scientific arrays with their public resource owner')
    if isinstance(value, np.ndarray):
        if value.size > 64:
            raise ValueError('Callable result arrays exceed the control receipt bound')
        value = value.tolist()
    elif isinstance(value, np.generic):
        value = value.item()
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise ValueError('Callable receipt field names must be strings')
        return {key: _receipt_value(item, depth+1, budget) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_receipt_value(item, depth+1, budget) for item in value]
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    raise ValueError('Callable result is not an inert control receipt')


def execute(namespace, invocation, outdir):
    entry = invocation['entrypoint']
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', entry):
        raise ValueError('Invalid registered callable entrypoint')
    function = namespace.get(entry)
    if not callable(function):
        raise ValueError('Registered callable entrypoint is not defined by its exact source snapshot')
    payload = json.loads(invocation['payload_json'], parse_constant=lambda x: (_ for _ in ()).throw(ValueError('Nonfinite JSON control value')))
    handle = gxtxt.gxtxt_callback_register(function)
    try:
        result = gxtxt.gxtxt_api_call(invocation['consumer_api'], invocation['consumer_operation'], [handle, payload])
        receipt = {'format': 'gxtxt.registered_callable_result.v1',
                   **{key: invocation[key] for key in ('callable_id', 'contract', 'source_sha256', 'revision', 'declaration_sha256', 'consumer_api', 'consumer_operation')},
                   'result': _receipt_value(result)}
        encoded = json.dumps(receipt, ensure_ascii=False, allow_nan=False)
        if len(encoded.encode('utf-8')) > 1048576:
            raise ValueError('Callable result control receipt exceeds 1 MiB')
        with (outdir / 'registered_callable_result.json').open('x', encoding='utf-8') as stream:
            stream.write(encoded + '\n')
    finally:
        gxtxt.gxtxt_callback_release(handle)
