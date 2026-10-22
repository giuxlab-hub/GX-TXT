# SPDX-License-Identifier: GPL-3.0-or-later
"""Trusted isolated ABI runner. Native author code is never loaded by Tk."""
from __future__ import annotations
import ctypes
import json
import math
from pathlib import Path
import resource
import sys
import os
import time
import hashlib

CHANNEL = Path(sys.argv[2]) if len(sys.argv)==3 and sys.argv[1]=='--debug-channel' else None
PROTOCOL_STREAM = None

def route_native_output(path):
    """Keep normal C/C++ stdout/stderr out of the typed control channel."""
    global PROTOCOL_STREAM
    PROTOCOL_STREAM=os.fdopen(os.dup(sys.stdout.fileno()),'w',encoding='utf-8',buffering=1)
    descriptor=os.open(path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
    try:
        os.dup2(descriptor,1);os.dup2(descriptor,2)
    finally:os.close(descriptor)
    return PROTOCOL_STREAM

def receive(limit):
    if CHANNEL is None:return json.loads(sys.stdin.readline(limit))
    path=CHANNEL/'worker-input.json'
    while not path.exists():time.sleep(.01)
    if path.is_symlink() or path.stat().st_size>limit:raise ValueError('Invalid debugger worker input')
    result=json.loads(path.read_text());path.unlink();return result

class State(ctypes.Structure):
    _fields_ = [('values', ctypes.c_double*16), ('counter', ctypes.c_uint)]

class Event(ctypes.Structure):
    _fields_ = [('kind', ctypes.c_int), ('component', ctypes.c_uint), ('value', ctypes.c_double)]

def send(value):
    if CHANNEL is None:print(json.dumps(value, allow_nan=False, separators=(',', ':')),file=PROTOCOL_STREAM or sys.stdout,flush=True)
    else:
        stage=CHANNEL/'worker-output.pending'
        stage.write_text(json.dumps(value,allow_nan=False))
        os.replace(stage,CHANNEL/'worker-output.json')

def runtime_limits():
    return dict(cpu_seconds=3, address_space_bytes=256*1024**2, file_size_bytes=1024**2, core_dump_bytes=0)

def apply_runtime_limits():
    limits=runtime_limits()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_AS, (limits['address_space_bytes'], limits['address_space_bytes']))
    consumed=resource.getrusage(resource.RUSAGE_SELF)
    cpu_limit=math.ceil(consumed.ru_utime+consumed.ru_stime)+limits['cpu_seconds']
    resource.setrlimit(resource.RLIMIT_CPU, (cpu_limit, resource.RLIM_INFINITY))
    resource.setrlimit(resource.RLIMIT_FSIZE, (limits['file_size_bytes'], limits['file_size_bytes']))

def main(request=None, broker=None, loaded_library=None):
    apply_runtime_limits()
    request = receive(65537) if request is None else request
    if broker is None and CHANNEL is None and request.get('native_output_path'):
        route_native_output(request['native_output_path'])
    path=Path(request['library'])
    if path.is_symlink() or not path.is_file():
        raise ValueError('Compiled Viewer binary is missing; install or build a matching artifact')
    if 'binary_sha256' in request and hashlib.sha256(path.read_bytes()).hexdigest()!=request['binary_sha256']:
        raise ValueError('Compiled Viewer binary changed before native execution')
    library = loaded_library or ctypes.CDLL(str(path.resolve()))
    state = State((ctypes.c_double*16)(*request['state']['values']), request['state']['counter'])
    event = Event(request['event']['kind'], request['event']['component'], request['event']['value'])
    errors = []; count = 0
    callback_type = ctypes.CFUNCTYPE(ctypes.c_double, ctypes.c_void_p, ctypes.c_uint,
                                    ctypes.c_uint, ctypes.c_double, ctypes.c_double, ctypes.c_char_p)
    def dispatch(context, operation, component, left, right, text):
        nonlocal count
        try:
            count += 1
            if count > 64 or not math.isfinite(left) or not math.isfinite(right):
                raise ValueError('Native SDK operation count/value exceeds bounds')
            message = text.decode('utf-8', errors='strict') if text else ''
            if len(message.encode()) > 256: raise ValueError('Native SDK text exceeds 256 bytes')
            call={'request':count, 'operation':operation, 'component':component,
                  'left':left, 'right':right, 'text':message}
            if broker is None:
                send(call)
                response = receive(8193)
            else:
                response = broker(call)
            if response.get('request') != count or not response.get('ok'):
                raise ValueError(response.get('error', 'Invalid SDK broker response'))
            value = float(response.get('value', 0))
            if not math.isfinite(value): raise ValueError('Nonfinite SDK broker response')
            return value
        except Exception as error:
            if len(errors)<16: errors.append(str(error))
            return 0.0
    callback = callback_type(dispatch)
    entry = library.gxtxt_viewer_event_v1
    entry.argtypes = [ctypes.c_void_p, callback_type, ctypes.POINTER(State), ctypes.POINTER(Event)]
    entry.restype = ctypes.c_int
    code = entry(None, callback, ctypes.byref(state), ctypes.byref(event))
    values = list(state.values)
    if not all(math.isfinite(value) for value in values): errors.append('Nonfinite native state')
    result={'done':True, 'ok':not errors and code == 0, 'errors':errors, 'abi_result':code,
            'state':{'values':values, 'counter':state.counter}, 'sdk_calls':count}
    if broker is None:send(result)
    return result

if __name__ == '__main__':
    try:
        if len(sys.argv)==3 and sys.argv[1]=='--probe':
            # Inherit the already managed admission group. A hard root shutdown
            # must include a constructor/probe that has not returned yet.
            apply_runtime_limits()
            probe=ctypes.CDLL(str(Path(sys.argv[2]).resolve()))
            probe.gxtxt_viewer_event_v1
            print('Compiled Viewer ABI entry and runtime libraries loaded',flush=True)
        else:main()
    except Exception as error:
        send({'done':True, 'ok':False, 'errors':[str(error)]});sys.exit(1)
