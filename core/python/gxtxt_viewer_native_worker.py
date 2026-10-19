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

CHANNEL = Path(sys.argv[2]) if len(sys.argv)==3 and sys.argv[1]=='--debug-channel' else None

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
    if CHANNEL is None:print(json.dumps(value, allow_nan=False, separators=(',', ':')), flush=True)
    else:
        stage=CHANNEL/'worker-output.pending'
        stage.write_text(json.dumps(value,allow_nan=False))
        os.replace(stage,CHANNEL/'worker-output.json')

def runtime_limits():
    return dict(cpu_seconds=3, address_space_bytes=256*1024**2, file_size_bytes=1024**2, core_dump_bytes=0)

def main():
    limits=runtime_limits()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_AS, (limits['address_space_bytes'], limits['address_space_bytes']))
    resource.setrlimit(resource.RLIMIT_CPU, (limits['cpu_seconds'], limits['cpu_seconds']))
    resource.setrlimit(resource.RLIMIT_FSIZE, (limits['file_size_bytes'], limits['file_size_bytes']))
    request = receive(65537)
    library = ctypes.CDLL(str(Path(request['library']).resolve()))
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
            send({'request':count, 'operation':operation, 'component':component,
                  'left':left, 'right':right, 'text':message})
            response = receive(8193)
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
    send({'done':True, 'ok':not errors and code == 0, 'errors':errors, 'abi_result':code,
          'state':{'values':values, 'counter':state.counter}, 'sdk_calls':count})

if __name__ == '__main__':
    try: main()
    except Exception as error:
        send({'done':True, 'ok':False, 'errors':[str(error)]});sys.exit(1)
