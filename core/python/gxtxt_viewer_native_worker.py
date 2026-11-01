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

# Isolated (-I) entrypoints omit their script directory from module search.
# Resolve trusted sibling CORE helpers from this fixed runtime owner only.
sys.path.insert(0, str(Path(__file__).resolve().parent))

CHANNEL = Path(sys.argv[2]) if len(sys.argv)==3 and sys.argv[1]=='--debug-channel' else None
PROTOCOL_STREAM = None
STDERR_ROUTE = None

def native_stderr_capture_active():
    return STDERR_ROUTE is not None and STDERR_ROUTE['active']

def disable_native_stderr_capture():
    """Trusted runtime cleanup; restore the original file, without a restart."""
    global STDERR_ROUTE
    route=STDERR_ROUTE
    if route is None:return
    with route['lock']:
        if route['original'] is not None:os.dup2(route['original'],2)
        route['active']=False
    STDERR_ROUTE=None

def route_native_output(path, origin=None, producer=None, producer_prepared=False):
    """Keep normal C/C++ stdout/stderr out of the typed control channel."""
    global PROTOCOL_STREAM, STDERR_ROUTE
    PROTOCOL_STREAM=os.fdopen(os.dup(sys.stdout.fileno()),'w',encoding='utf-8',buffering=1)
    descriptor=os.open(path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
    try:
        os.dup2(descriptor,1)
        from gxtxt_stderr_diagnostics import optional_producer, emit_chunks
        if not producer_prepared:producer=optional_producer()
        if producer is None:
            os.dup2(descriptor,2)
        else:
            # Only enabled capture adds this actual STDERR channel. Its reader
            # retains the original native-output log and makes bounded optional
            # nonblocking copies; no Tk widget is accessed from this thread.
            import threading
            reader,writer=os.pipe()
            original=os.dup(descriptor)
            os.dup2(writer,2);os.close(writer)
            context=dict(source='native_viewer',component='ViewerDevelopment',api_id='VIEWER_DEVELOPMENT_API_v1',operation='compiled_worker',process_id=os.getpid(),stream='stderr')
            context.update(origin or {})
            route=dict(lock=threading.Lock(),original=original,active=True)
            STDERR_ROUTE=route
            def drain_native_stderr():
                try:
                    while True:
                        chunk=os.read(reader,32768)
                        if not chunk:break
                        try:
                            remaining=memoryview(chunk)
                            while remaining:remaining=remaining[os.write(original,remaining):]
                        except OSError:
                            # The existing native log's output/resource limits
                            # must not stop draining the producer's STDERR pipe.
                            pass
                        if route['active']:emit_chunks(producer,chunk,**context)
                finally:
                    os.close(reader)
                    with route['lock']:
                        os.close(original);route['original']=None;route['active']=False
                    producer.close()
            threading.Thread(target=drain_native_stderr,name='gxtxt-native-stderr',daemon=True).start()
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
    typed=isinstance(value,dict) and value.get('operation') in {42,43,44,45,46,48}
    encoded=json.dumps(value,allow_nan=False,ensure_ascii=not typed,separators=(',',':'))
    if typed and len(encoded.encode('utf-8'))>197632:raise ValueError('Typed native frame exceeds its 193 KiB envelope bound')
    if CHANNEL is None:print(encoded,file=PROTOCOL_STREAM or sys.stdout,flush=True)
    else:
        stage=CHANNEL/'worker-output.pending'
        stage.write_text(encoded,encoding='utf-8')
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
    context=request.get('context',{})
    if not isinstance(context,dict) or set(context)-{'inputs','data','workspace','producer','script_library_result','scientific_preview_result','comparison_result','analysis_result'}:raise ValueError('Invalid typed Viewer input context')
    for key in ('script_library_result','scientific_preview_result','comparison_result','analysis_result'):
        if key in context and (not isinstance(context[key],dict) or len(json.dumps(context[key],ensure_ascii=False,allow_nan=False,separators=(',',':')).encode('utf-8'))>49152):raise ValueError('Typed client receipt exceeds its separate 48 KiB bound')
    if isinstance(context.get('workspace'),dict) and {'script_library_result','scientific_preview_result','comparison_result','analysis_result'} & set(context['workspace']):raise ValueError('Reserved client receipts require their explicit owning-thread context')
    inputs=context.get('inputs',[]);data=context.get('data','')
    if not isinstance(inputs,list) or len(inputs)>512 or any(not isinstance(v,str) or '\x00' in v or len(v.encode('utf-8'))>4096 for v in inputs) or not isinstance(data,str) or len(data.encode('utf-8'))>1048576:
        raise ValueError('Viewer input context exceeds its bounds')
    if sum(len(v.encode('utf-8')) for v in inputs)>1048576:raise ValueError('Viewer input values exceed 1 MiB')
    setter=getattr(library,'gxtxt_viewer_context_v1',None)
    if setter is not None:
        encoded=[v.encode('utf-8') for v in inputs];values=(ctypes.c_char_p*len(encoded))(*encoded);payload=data.encode('utf-8')
        setter.argtypes=[ctypes.c_uint,ctypes.POINTER(ctypes.c_char_p),ctypes.c_char_p,ctypes.c_uint];setter.restype=ctypes.c_int
        if setter(len(encoded),values,payload,len(payload)):raise ValueError('Native Viewer rejected input context')
    elif inputs or data:raise ValueError('This Viewer artifact has no admitted typed-input extension; rebuild it in Development')
    workspace_setter=getattr(library,'gxtxt_viewer_workspace_context_v1',None)
    if workspace_setter is not None:
        nodes=[]
        def flatten(value,parent=0,key='',depth=0,typed=False):
            if depth>64 or len(nodes)>=8192:raise ValueError('Workspace context exceeds bounds')
            if typed:
                if not isinstance(value,dict) or set(value)!={'kind','value'} or value['kind'] not in {'null','text','bool','int','real','object','array','resource'}:raise ValueError('Invalid typed Workspace context')
                declared=value['kind'];value=value['value']
            else:declared=None
            if value is None:kind,scalar=0,''
            elif isinstance(value,str):kind,scalar=1,value
            elif type(value) is bool:kind,scalar=2,'1' if value else '0'
            elif type(value) is int:
                if not -(2**63)<=value<2**63:raise ValueError('Workspace integer exceeds int64')
                kind,scalar=3,str(value)
            elif type(value) is float:
                if not math.isfinite(value):raise ValueError('Workspace real must be finite')
                kind,scalar=4,repr(value)
            elif isinstance(value,dict):kind,scalar=(7 if declared=='resource' else 5),''
            elif isinstance(value,list):kind,scalar=6,''
            else:raise ValueError('Unsupported Workspace snapshot type')
            index=len(nodes);nodes.append((parent,kind,key.encode('utf-8'),scalar.encode('utf-8')))
            if declared is not None and kind!={'null':0,'text':1,'bool':2,'int':3,'real':4,'object':5,'array':6,'resource':7}[declared]:
                if declared=='real' and kind==3:kind,scalar=4,repr(float(value));nodes[index]=(parent,kind,key.encode('utf-8'),scalar.encode('utf-8'))
                else:raise ValueError('Workspace snapshot kind mismatch')
            if kind in (5,7):
                for name,item in value.items():
                    if not isinstance(name,str) or '\0' in name:raise ValueError('Invalid Workspace field name')
                    flatten(item,index,name,depth+1,typed or (depth==0 and name in {'state','properties'}))
            if kind==6:
                for item in value:flatten(item,index,'',depth+1,typed)
        workspace=dict(context.get('workspace',{}))
        if 'producer' in context:workspace['dataset_producer']=context['producer']
        for key in ('script_library_result','scientific_preview_result','comparison_result','analysis_result'):
            if key in context:workspace[key]=context[key]
        flatten(workspace)
        if sum(len(row[2])+len(row[3]) for row in nodes)>1048576:raise ValueError('Workspace snapshot exceeds 1 MiB')
        count=len(nodes);parents=(ctypes.c_uint*count)(*(r[0] for r in nodes));kinds=(ctypes.c_uint*count)(*(r[1] for r in nodes));keys=(ctypes.c_char_p*count)(*(r[2] for r in nodes));texts=(ctypes.c_char_p*count)(*(r[3] for r in nodes));sizes=(ctypes.c_uint*count)(*(len(r[3]) for r in nodes))
        workspace_setter.argtypes=[ctypes.c_uint,ctypes.POINTER(ctypes.c_uint),ctypes.POINTER(ctypes.c_uint),ctypes.POINTER(ctypes.c_char_p),ctypes.POINTER(ctypes.c_char_p),ctypes.POINTER(ctypes.c_uint)];workspace_setter.restype=ctypes.c_int
        if workspace_setter(count,parents,kinds,keys,texts,sizes):raise ValueError('Native Viewer rejected Workspace context')
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
            maximum=49152 if operation in {42,43,44,45,46,48} else (131072 if operation in {37,38,39,40} else 256)
            if len(message.encode()) > maximum: raise ValueError('Native SDK text exceeds its operation bound')
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
        except BaseException as error:
            # Python cancellation must never unwind through libffi into C++.
            # ctypes would otherwise return an uninitialized scalar and omit
            # the failure, allowing a cancelled callback to look successful.
            if len(errors)<16:
                message=str(error) or type(error).__name__
                if operation in {42,43,44}:message='dataset_producer.'+{42:'review',43:'create',44:'publish_batch'}[operation]+': '+message
                if operation in {45,46,47,48}:message={45:'script_library_command',46:'scientific_preview_command',47:'scientific_frame_bind',48:'comparison_command'}[operation]+': '+message
                errors.append(message)
            return 0.0
    callback = callback_type(dispatch)
    entry = library.gxtxt_viewer_event_v1
    entry.argtypes = [ctypes.c_void_p, callback_type, ctypes.POINTER(State), ctypes.POINTER(Event)]
    entry.restype = ctypes.c_int
    hook_entry=getattr(library,'gxtxt_viewer_workspace_hook_v1',None)
    hook_flags=getattr(library,'gxtxt_viewer_workspace_hooks_v1',None)
    hook_mask=int(hook_flags()) if hook_flags else 0
    def workspace_hook(operation):
        if hook_entry is None:raise ValueError('Compiled Viewer lacks the Workspace hook ABI')
        output=ctypes.create_string_buffer(1048576);used=ctypes.c_uint()
        hook_entry.argtypes=[ctypes.c_uint,ctypes.c_void_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_uint)];hook_entry.restype=ctypes.c_int
        if hook_entry(operation,output,len(output),ctypes.byref(used)) or used.value>len(output):raise ValueError('Workspace hook failed or exceeded bounds')
        response=json.loads(output.raw[:used.value].decode('utf-8'))
        if not response.get('ok'):raise ValueError(response.get('error','Workspace hook rejected its value'))
        return response
    captured=None;code=0
    try:
        if request.get('workspace_hook')=='committed':workspace_hook(2)
        elif request.get('workspace_hook')=='restore':workspace_hook(1)
        else:
            if event.kind==0 and hook_mask&4 and context.get('workspace',{}).get('id'):workspace_hook(1)
            code=entry(None, callback, ctypes.byref(state), ctypes.byref(event))
            if not errors and code==0 and hook_mask&1:captured=workspace_hook(0)['value']
    except Exception as error:errors.append(str(error));code=1
    values = list(state.values)
    if not all(math.isfinite(value) for value in values): errors.append('Nonfinite native state')
    result={'done':True, 'ok':not errors and code == 0, 'errors':errors, 'abi_result':code,
            'state':{'values':values, 'counter':state.counter}, 'sdk_calls':count}
    result['workspace_hook_mask']=hook_mask
    if captured is not None:result['workspace_capture']=captured
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
