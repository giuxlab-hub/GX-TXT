# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixed trusted native target worker, launched only by CORE's managed broker.

No selected source FD/path, publication service or authored command line exists
here. Source slices use the bound CORE channel. Numeric chunks stay local in
precreated write-only CORE buffers and are sealed only by CORE after actor reap.
"""
from __future__ import annotations
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import resource
import stat
import sys
import threading

sys.path.insert(0,str(Path(__file__).resolve().parent))
from gxtxt_native_read_policy_v1 import activate_native_read_policy

FRAME=262144
VALUE=196608
OPERATIONS={1:'source_info',2:'source_read',3:'progress',4:'cancelled',5:'prepare_output',6:'output_write',7:'output_finish',8:'helper_call',9:'scientific_spectrum_parse',10:'scientific_spectrum_read'}
SDK=Path(__file__).resolve().parents[1]/'development/sdk/gxtxt_acquisition_sdk_v1.hpp'

class WorkerError(ValueError):pass

def unique(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise WorkerError('Duplicate native protocol field')
        result[key]=value
    return result

def decode(raw):
    if len(raw)>VALUE:raise WorkerError('Native metadata exceeds its bound')
    value=json.loads(raw.decode('utf-8'),object_pairs_hook=unique,
        parse_constant=lambda _:(_ for _ in ()).throw(WorkerError('Nonfinite metadata')))
    nodes=0
    def visit(v,depth):
        nonlocal nodes
        nodes+=1
        if nodes>32768 or depth>24:raise WorkerError('Native metadata nesting exceeds its bound')
        if v is None or type(v) in {bool,int,float,str}:
            if isinstance(v,str) and '\0' in v:raise WorkerError('Metadata contains NUL')
            if type(v) is int and not -(1<<63)<=v<(1<<63):raise WorkerError('Metadata integer exceeds signed 64-bit range')
        elif isinstance(v,list):
            for item in v:visit(item,depth+1)
        elif isinstance(v,dict):
            for key,item in v.items():
                if not isinstance(key,str) or '\0' in key:raise WorkerError('Invalid metadata key')
                visit(item,depth+1)
        else:raise WorkerError('Metadata requires inert values')
    visit(value,0)
    return value

def wire(value,maximum=FRAME):
    raw=json.dumps(value,allow_nan=False,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    if len(raw)>=maximum:raise WorkerError('Native protocol frame exceeds its bound')
    return raw

def integer(value,label,maximum=(1<<63)-1):
    if type(value) is not int or not 0<=value<=maximum:raise WorkerError('Invalid bounded integer: '+label)
    return value

def sha(value):
    if not isinstance(value,str) or not re.fullmatch('[0-9a-f]{64}',value):raise WorkerError('Invalid SHA-256')
    return value

def system_runtime_closure():
    # Preload the fixed reviewed C++ runtime before confinement. No author search
    # path or loader environment is used; broker starts this process sterile.
    arch={'x86_64':'x86_64-linux-gnu','aarch64':'aarch64-linux-gnu'}.get(platform.machine())
    if arch is None:raise WorkerError('Unsupported native runtime architecture')
    for name in ('libstdc++.so.6','libgcc_s.so.1','libm.so.6','libpthread.so.0'):
        path=(Path('/usr/lib')/arch/name).resolve(strict=True)
        info=path.stat()
        if info.st_uid!=0 or info.st_mode&0o022 or not stat.S_ISREG(info.st_mode):raise WorkerError('Unreviewed system C++ runtime')
        ctypes.CDLL(str(path),mode=os.RTLD_NOW|os.RTLD_GLOBAL)
    paths=set()
    for line in Path('/proc/self/maps').read_text().splitlines():
        parts=line.split(None,5)
        if len(parts)==6 and parts[5].startswith('/'):
            if parts[5].endswith(' (deleted)'):raise WorkerError('Mapped runtime dependency was removed')
            paths.add(Path(parts[5]).resolve(strict=True))
    return [{'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(paths)]

class Worker:
    def __init__(self):
        self.channel=1;self.pending=bytearray();self.sequence=0;self.hello=None
        self.buffers={};self.outputs={};self.failed=False;self.errors=[]
        self.dispatch_lock=threading.RLock()

    def receive(self):
        while b'\n' not in self.pending:
            if len(self.pending)>=FRAME:raise WorkerError('Native input frame exceeds its bound')
            data=os.read(0,min(65536,FRAME-len(self.pending)))
            if not data:raise WorkerError('CORE channel closed before reply')
            self.pending.extend(data)
        raw,rest=self.pending.split(b'\n',1);self.pending=bytearray(rest)
        # Control envelope has a slightly larger bound than its inert payload.
        if len(raw)>=FRAME:raise WorkerError('Native input frame exceeds its bound')
        result=json.loads(raw.decode('utf-8'),object_pairs_hook=unique,
            parse_constant=lambda _:(_ for _ in ()).throw(WorkerError('Nonfinite protocol value')))
        if not isinstance(result,dict):raise WorkerError('Native protocol requires object frames')
        return result

    def send(self,value):
        pending=memoryview(wire(value)+b'\n')
        while pending:
            count=os.write(self.channel,pending)
            if count<=0:raise WorkerError('CORE channel write failed')
            pending=pending[count:]

    def call(self,operation,args):
        if self.failed:raise WorkerError('Prior native capability failed')
        self.sequence+=1
        if self.sequence>262144:raise WorkerError('Native call budget exceeded')
        self.send(dict(kind='host_call',request_id=self.hello['request_id'],sequence=self.sequence,operation=operation,args=args))
        reply=self.receive()
        if set(reply)!={'kind','request_id','sequence','status','result','error'} or reply['kind']!='host_reply' or reply['request_id']!=self.hello['request_id'] or type(reply['sequence']) is not int or reply['sequence']!=self.sequence:
            raise WorkerError('CORE reply/channel sequence differs')
        if reply['status']!='ok':raise WorkerError('CORE refused native Acquisition capability')
        return decode(wire(reply['result'],VALUE))

    def prepare(self,args):
        result=self.call('prepare_output',args)
        if not isinstance(result,dict) or set(result)!={'output_id','variables','_private_buffers'}:raise WorkerError('Malformed CORE output preparation')
        oid=result['output_id']
        if not isinstance(oid,str) or not re.fullmatch('[0-9a-f]{32}',oid) or oid in self.outputs:raise WorkerError('Duplicate/unbound prepared output')
        rows=result['variables'];private=result['_private_buffers']
        if not isinstance(rows,list) or not 1<=len(rows)<=128 or not isinstance(private,list) or len(private)!=len(rows):raise WorkerError('Malformed prepared variables')
        expected={}
        for row in rows:
            if not isinstance(row,dict) or set(row)!={'variable_id','byte_count'} or not isinstance(row['variable_id'],str) or row['variable_id'] in expected:raise WorkerError('Invalid prepared variable')
            expected[row['variable_id']]=integer(row['byte_count'],'byte_count',536870912)
        admitted={}
        for row in private:
            if not isinstance(row,dict) or set(row)!={'variable_id','buffer_id','path','device','inode','expected_bytes'}:raise WorkerError('Invalid private buffer receipt')
            vid=row['variable_id'];path=Path(row['path'])
            if vid not in expected or vid in admitted or row['expected_bytes']!=expected[vid] or not expected[vid]:raise WorkerError('Private buffer count/identity differs')
            if not isinstance(row['buffer_id'],str) or not re.fullmatch('[0-9a-f]{48}',row['buffer_id']) or path!=self.buffer_root/(row['buffer_id']+'.bin'):raise WorkerError('Private buffer escapes exact CORE root')
            fd=os.open(path,os.O_WRONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
            try:
                info=os.fstat(fd);current=os.stat(path,follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size!=0 or info.st_uid!=os.getuid() or (info.st_dev,info.st_ino)!=(row['device'],row['inode']) or (current.st_dev,current.st_ino)!=(info.st_dev,info.st_ino):raise WorkerError('CORE buffer is not its empty ordinary postimage')
                value=dict(fd=fd,path=path,identity=(info.st_dev,info.st_ino),expected=expected[vid],written=0,digest=hashlib.sha256())
                admitted[vid]=value;self.buffers[(oid,vid)]=value;fd=None
            finally:
                if fd is not None:os.close(fd)
        self.outputs[oid]=dict(variables=admitted,finished=False)
        return dict(output_id=oid,variables=rows) # Private paths never enter SDK.

    def write_output(self,args,data):
        if set(args)!={'output_id','variable_id','offset'} or not 1<=len(data)<=65536:raise WorkerError('Malformed native output chunk')
        key=(args['output_id'],args['variable_id']);buffer=self.buffers.get(key)
        if buffer is None or self.outputs[key[0]]['finished'] or args['offset']!=buffer['written'] or len(data)>buffer['expected']-buffer['written']:raise WorkerError('Native output write is not sequential/in range')
        info=os.fstat(buffer['fd']);path=os.stat(buffer['path'],follow_symlinks=False)
        if (info.st_dev,info.st_ino)!=buffer['identity'] or (path.st_dev,path.st_ino)!=buffer['identity'] or info.st_size!=buffer['written']:raise WorkerError('Output buffer changed before write')
        count=len(data);result=self.call('output_write',dict(args,byte_count=count,chunk_sha256=hashlib.sha256(data).hexdigest()))
        if result!=dict(authorized=True,offset=args['offset'],byte_count=count):raise WorkerError('CORE output authorization receipt differs')
        pending=memoryview(data)
        while pending:
            n=os.write(buffer['fd'],pending)
            if n<=0:raise WorkerError('Typed local output write failed')
            pending=pending[n:]
        buffer['digest'].update(data);buffer['written']+=count
        return dict(accepted_bytes=count,next_offset=buffer['written'])

    def finish(self,args):
        if set(args)!={'output_id'} or args['output_id'] not in self.outputs:raise WorkerError('Unbound output completion')
        record=self.outputs[args['output_id']]
        if record['finished']:raise WorkerError('Output completion is not repeatable')
        receipts=[]
        for vid,buffer in record['variables'].items():
            if buffer['written']!=buffer['expected']:raise WorkerError('Output variable is incomplete')
            os.fsync(buffer['fd']);os.close(buffer['fd']);buffer['fd']=None
            receipts.append(dict(variable_id=vid,byte_count=buffer['written'],sha256=buffer['digest'].hexdigest()))
        result=self.call('output_finish',dict(output_id=args['output_id'],variables=receipts))
        if result!=dict(output_id=args['output_id'],state='PROVISIONAL_UNTIL_ACTOR_REAP'):raise WorkerError('CORE provisional receipt differs')
        record['finished']=True
        return result

    def dispatch(self,context,operation,args_pointer,data_pointer,count,response,capacity,used):
        with self.dispatch_lock:
            return self._dispatch(context,operation,args_pointer,data_pointer,count,response,capacity,used)

    def _dispatch(self,context,operation,args_pointer,data_pointer,count,response,capacity,used):
        try:
            if self.failed or operation not in OPERATIONS:raise WorkerError('Unsupported/prior failed native operation')
            args=decode(ctypes.string_at(args_pointer))
            if not isinstance(args,dict):raise WorkerError('Native host arguments require an object')
            if operation==6:
                if not data_pointer or not 1<=count<=65536:raise WorkerError('Typed local chunk exceeds bound')
                result=self.write_output(args,ctypes.string_at(data_pointer,count))
            elif count or data_pointer:raise WorkerError('Only output_write accepts local numeric bytes')
            elif operation==5:result=self.prepare(args)
            elif operation==7:result=self.finish(args)
            else:
                result=self.call(OPERATIONS[operation],args)
                if operation==2:
                    if not isinstance(result,dict) or set(result)!={'offset','byte_count','total_size','eof','bytes_base64'}:raise WorkerError('Malformed CORE source slice')
                    raw=base64.b64decode(result['bytes_base64'],validate=True)
                    if base64.b64encode(raw).decode()!=result['bytes_base64'] or len(raw)!=result['byte_count'] or len(raw)>args['count'] or result['offset']!=args['offset']:raise WorkerError('CORE source slice encoding/count differs')
            encoded=wire(result,VALUE)
            if len(encoded)>=capacity:raise WorkerError('Native reply exceeds SDK buffer')
            ctypes.memmove(response,encoded,len(encoded));used[0]=len(encoded);return 0
        except BaseException as error:
            self.failed=True;self.errors.append(str(error)[:2048]);used[0]=0;return 1

    def bootstrap(self,hello):
        expected={'schema','kind','request_id','phase','qualified_profile','module_snapshot','source_descriptors','config','mapping','limits','_trusted_runtime'}
        if set(hello)!=expected or hello['schema']!='gxtxt.native_acquisition_request.v1' or hello['kind']!='hello' or not isinstance(hello['request_id'],str) or not re.fullmatch('[0-9a-f]{64}',hello['request_id']):raise WorkerError('Invalid trusted native bootstrap/channel')
        if hello['phase'] not in {'recognize','inspect','test','import'} or not isinstance(hello['qualified_profile'],str) or not re.fullmatch('[A-Za-z][A-Za-z0-9_.-]*/[a-z][a-z0-9_-]{0,47}',hello['qualified_profile']):raise WorkerError('Invalid admitted native phase/profile')
        self.hello=hello
        for field in ('config','mapping','limits','module_snapshot'):
            if not isinstance(hello[field],dict):raise WorkerError('Trusted config/mapping/limits/snapshot require inert objects')
            decode(wire(hello[field],VALUE))
        if not hello['module_snapshot']:raise WorkerError('Reviewed module snapshot is required')
        rows=hello['source_descriptors']
        if not isinstance(rows,list) or not 1<=len(rows)<=64:raise WorkerError('Bounded source descriptors required')
        for i,row in enumerate(rows):
            if not isinstance(row,dict) or set(row)!={'source_index','logical_name','size','source_sha256','full_sha_reviewed'} or type(row['source_index']) is not int or row['source_index']!=i or not isinstance(row['logical_name'],str) or not row['logical_name'] or len(row['logical_name'].encode())>1024 or type(row['full_sha_reviewed']) is not bool:raise WorkerError('Invalid public source descriptor')
            integer(row['size'],'source size',2147483648)
            if row['source_sha256'] is not None:sha(row['source_sha256'])
            if hello['phase'] in {'test','import'} and (not row['full_sha_reviewed'] or row['source_sha256'] is None):raise WorkerError('Native import/Test requires fully reviewed source SHA')
        runtime=hello['_trusted_runtime']
        if not isinstance(runtime,dict) or set(runtime)!={'library','binary_sha256','sdk_sha256','buffer_root','native_output_path'}:raise WorkerError('Exact trusted native runtime roles required')
        sha(runtime['binary_sha256']);sha(runtime['sdk_sha256'])
        from gxtxt_acquisition_sdk_compat_v1 import sdk_hash_compatible
        if not sdk_hash_compatible(hashlib.sha256(SDK.read_bytes()).hexdigest(),runtime['sdk_sha256']):raise WorkerError('Current native SDK differs from admitted runtime')
        self.buffer_root=Path(runtime['buffer_root'])
        if not self.buffer_root.is_absolute() or self.buffer_root.resolve(strict=True)!=self.buffer_root:raise WorkerError('Canonical CORE buffer root required')
        log=Path(runtime['native_output_path'])
        if log.parent!=self.buffer_root or not re.fullmatch('[A-Za-z0-9_.-]{1,128}',log.name):raise WorkerError('Native diagnostic output escapes CORE buffer root')
        fd=os.open(log,os.O_WRONLY|os.O_APPEND|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
        try:
            info=os.fstat(fd);current=os.stat(log,follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_uid!=os.getuid() or info.st_size or (info.st_dev,info.st_ino)!=(current.st_dev,current.st_ino):raise WorkerError('Native diagnostics require CORE-created empty ordinary file')
            self.channel=os.dup(1);os.dup2(fd,1);os.dup2(fd,2)
        finally:os.close(fd)
        closure=system_runtime_closure()
        resource.setrlimit(resource.RLIMIT_CPU,(30,30));resource.setrlimit(resource.RLIMIT_AS,(1073741824,1073741824));resource.setrlimit(resource.RLIMIT_FSIZE,(536870912,536870912));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
        guard=activate_native_read_policy({'path':runtime['library'],'sha256':runtime['binary_sha256']},closure,buffer_root=str(self.buffer_root),protocol_fds=(self.channel,))
        guard['before_authored_load']=True
        self.library=ctypes.CDLL(runtime['library'],mode=os.RTLD_NOW|os.RTLD_LOCAL)
        self.entry=self.library.gxtxt_acquisition_invoke_v1
        self.callback_type=ctypes.CFUNCTYPE(ctypes.c_int,ctypes.c_void_p,ctypes.c_uint,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_uint))
        self.callback=self.callback_type(self.dispatch)
        self.entry.argtypes=[ctypes.c_void_p,self.callback_type,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_uint,ctypes.POINTER(ctypes.c_uint)];self.entry.restype=ctypes.c_int
        self.hello=hello
        return dict(kind='ready',request_id=hello['request_id'],binary_sha256=runtime['binary_sha256'],sdk_sha256=runtime['sdk_sha256'],worker_pid=os.getpid(),guard_receipt=guard,factory_identity='gxtxt_acquisition_invoke_v1')

    def run(self):
        hello=self.receive();ready=self.bootstrap(hello);self.send(ready);invoke=self.receive()
        if invoke!=dict(kind='invoke',request_id=hello['request_id'],phase=hello['phase'],qualified_profile=hello['qualified_profile']):raise WorkerError('Invoke differs from admitted channel/profile/phase')
        request=wire({key:hello[key] for key in ('config','mapping','limits','source_descriptors')},VALUE)
        response=ctypes.create_string_buffer(VALUE+1);used=ctypes.c_uint()
        result=self.entry(None,self.callback,hello['qualified_profile'].encode(),hello['phase'].encode(),request,response,len(response),ctypes.byref(used))
        if result or self.failed or used.value>VALUE:raise WorkerError('Native callback failed: '+'; '.join(self.errors or [response.raw[:min(used.value,2048)].decode('utf-8',errors='replace')]))
        value=decode(response.raw[:used.value])
        if not isinstance(value,dict):raise WorkerError('Native result must be an object')
        if any(not output['finished'] for output in self.outputs.values()):raise WorkerError('Native callback left incomplete outputs')
        self.send(dict(kind='complete',request_id=hello['request_id'],phase=hello['phase'],qualified_profile=hello['qualified_profile'],status='completed',result=value,diagnostics=[]))

    def close(self):
        for value in self.buffers.values():
            if value['fd'] is not None:
                try:os.close(value['fd'])
                except OSError:pass
                value['fd']=None

if __name__=='__main__':
    worker=Worker()
    try:worker.run()
    except BaseException as error:
        try:
            worker.send(dict(kind='complete',request_id=(worker.hello or {}).get('request_id',''),phase=(worker.hello or {}).get('phase',''),qualified_profile=(worker.hello or {}).get('qualified_profile',''),status='failed',result=None,diagnostics=[str(error)[:4096]]))
        except BaseException:pass
        sys.exit(1)
    finally:worker.close()
