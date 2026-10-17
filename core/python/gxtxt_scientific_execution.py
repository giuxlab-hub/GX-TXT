"""Trusted scientific provider adapter inside the existing Script Job guardian.

This is an API boundary for cooperating providers, not a hostile-code sandbox.
No queue, process registry, resource pool or independent Job journal lives here.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import base64
import csv
import fcntl
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
import time
import tkinter

MAX_PAGE = 1048576

def tdict(value):
    parts = tkinter.Tcl().splitlist(value)
    if len(parts) % 2 or len(set(parts[::2])) != len(parts)//2:
        raise ValueError('Invalid inert scientific request dictionary')
    return dict(zip(parts[::2], parts[1::2]))

def tvalue(value):
    if isinstance(value, dict):
        return tkinter._join(tuple(x for k,v in value.items() for x in (str(k),tvalue(v))))
    if isinstance(value, (tuple,list)):
        return tkinter._join(tuple(tvalue(v) for v in value))
    if value is None: return ''
    if isinstance(value, bool): return str(int(value))
    return str(value)

def decode_request(encoded):
    request = tdict(base64.b64decode(encoded,validate=True).decode('utf-8'))
    request['parameters'] = tdict(request['parameters'])
    request['tools'] = tdict(request['tools'])
    request['inputs'] = {k:base64.b64decode(v,validate=True) for k,v in tdict(request['inputs']).items()}
    request['runtime_files'] = tdict(request.get('runtime_files',''))
    request['schema'] = {k:tdict(v) for k,v in tdict(request['schema']).items()}
    for key, value in request['parameters'].items():
        kind = request['schema'][key]['type']
        if kind == 'integer': value = int(value)
        elif kind == 'number': value = float(value)
        elif kind == 'boolean': value = str(value).lower() in ('1','true','yes','on')
        request['parameters'][key] = value
    return request

def safe_file(root, relative):
    path = Path(relative)
    if path.is_absolute() or not path.parts or any(p in ('.','..') for p in path.parts):
        raise ValueError('Output must have a safe relative filename')
    resolved = root / path
    parent=root
    if parent.is_symlink(): raise ValueError('Scientific output symlinks are forbidden')
    for part in path.parts:
        parent=parent/part
        if parent.is_symlink(): raise ValueError('Scientific output symlinks are forbidden')
    if not resolved.resolve().is_relative_to(root.resolve()): raise ValueError('Output escapes Job ownership')
    return resolved

class Context:
    def __init__(self, request, output):
        self.parameters = request['parameters']
        self.inputs = request['inputs']
        self.tools = request['tools']
        self.scratch = Path(os.environ['TMPDIR']).resolve()
        self.output = output.resolve()
        self.request = request
        self.manifest = {'schema':'gxtxt.scientific_job_outputs.v1','provider_id':request['provider_id'],
            'provider_version':request['provider_version'],'worker_sha256':request['worker_sha256'],
            'source_identities':request['source_identities'],'runtime_files':request['runtime_files'],
            'adapter_sha256':request['adapter_sha256'],'outputs':[],'validation':'not_reported'}
        self._save()
    def _save(self):
        target = self.output / 'scientific-outputs.json'
        pending = target.with_suffix('.pending')
        pending.write_text(json.dumps(self.manifest,ensure_ascii=False,sort_keys=True),encoding='utf-8')
        os.replace(pending,target)
    def run(self, tool, argv, cwd=None):
        if tool not in self.tools or not isinstance(argv,(list,tuple)) or len(argv)>256 or any(not isinstance(v,str) or len(v)>8192 or '\x00' in v for v in argv):
            raise ValueError('Unregistered runtime tool or invalid approved argv')
        working = self.scratch if cwd is None else Path(cwd).resolve()
        if not working.is_relative_to(self.scratch): raise ValueError('Solver working directory escapes managed scratch')
        command = [self.tools[tool],*argv]
        print('@@GXTXT_PROGRESS scientific solver stage '+tool,flush=True)
        process = subprocess.Popen(command,cwd=working,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        tail = bytearray(); total=0
        while True:
            chunk=process.stdout.read(8192)
            if not chunk: break
            sys.stdout.buffer.write(chunk);sys.stdout.buffer.flush()
            total+=len(chunk);tail.extend(chunk)
            if len(tail)>MAX_PAGE: del tail[:-MAX_PAGE]
        code=process.wait()
        result={'returncode':code,'stdout':bytes(tail).decode('utf-8','replace'),'truncated':total>MAX_PAGE}
        if code: raise subprocess.CalledProcessError(code,command,output=result['stdout'])
        return result
    def publish_output(self, relative_filename, role, format, columns=None, live=False):
        if not isinstance(role,str) or not role or len(role)>128 or any(o['role']==role for o in self.manifest['outputs']):
            raise ValueError('Output roles must be nonempty and unique')
        path=safe_file(self.output,relative_filename)
        info=path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1: raise ValueError('Output must be an owned regular file')
        item={'role':role,'file':str(path.relative_to(self.output)),'format':format,'columns':columns or [],'live':bool(live)}
        self.manifest['outputs'].append(item);self._save()
        return role
    def summary(self, values):
        if not isinstance(values,dict): raise ValueError('Provider summary must be a typed mapping')
        self.manifest['summary']=values
        self.manifest['validation']=str(values.get('validation','provider_reported'))
        self._save()

def run(encoded):
    import gxtxt
    request=decode_request(encoded)
    adapter=Path(__file__).resolve()
    if hashlib.sha256(adapter.read_bytes()).hexdigest()!=request['adapter_sha256']:
        raise ValueError('CORE scientific adapter changed after preparation')
    framework=adapter.parents[2]
    for relative,expected in request['runtime_files'].items():
        dependency=safe_file(framework,relative)
        if hashlib.sha256(dependency.read_bytes()).hexdigest()!=expected:
            raise ValueError('Scientific native/runtime dependency changed after preparation')
    worker=Path(request['worker'])
    if worker.is_symlink() or hashlib.sha256(worker.read_bytes()).hexdigest()!=request['worker_sha256']:
        raise ValueError('Trusted provider source changed after preparation')
    output=Path(gxtxt.gxtxt_context()['output_dir'])
    context=Context(request,output)
    spec=importlib.util.spec_from_file_location('_gxtxt_trusted_scientific_provider',worker)
    provider=importlib.util.module_from_spec(spec);spec.loader.exec_module(provider)
    provider.run(context)

# Read-only logical output projection; called only by the trusted Tcl CORE.
def output_operation(root, job_id, operation, token='', offset=0, count=65536, generation=''):
    root=Path(root).resolve()
    manifest_path=root/'scientific-outputs.json'
    if not manifest_path.is_file() or manifest_path.is_symlink():
        return {'availability':'unavailable','job_id':job_id,'outputs':[]}
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest.get('schema')!='gxtxt.scientific_job_outputs.v1': raise ValueError('Invalid provider output contract')
    if len(manifest['outputs'])>256: raise ValueError('Too many provider outputs')
    result=[]
    for item in manifest['outputs']:
        identity=job_id+':'+item['role']
        item_token='output-'+hashlib.sha256(identity.encode()).hexdigest()
        if token and item_token!=token: continue
        path=safe_file(root,item['file'])
        descriptor={k:item[k] for k in ('role','format','columns','live')}
        descriptor.update(token=item_token,job_id=job_id,logical_id=identity)
        try:
            fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
        except FileNotFoundError:
            descriptor.update(availability='unavailable');result.append(descriptor);continue
        try:
            before=os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1: raise ValueError('Unsafe provider output')
            schema_sha256=hashlib.sha256(json.dumps(
                {key:item[key] for key in ('format','columns','live')},
                sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')).hexdigest()
            signature=[before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns,before.st_ctime_ns,schema_sha256]
            # Observation metadata belongs to the existing protected Job output resource.
            journal=root/'.scientific-observation.json'
            lock=os.open(root/'.scientific-observation.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
            try:
                fcntl.flock(lock,fcntl.LOCK_EX)
                prior=json.loads(journal.read_text()) if journal.is_file() else {}
                previous=prior.get(item_token,{})
                current=int(previous.get('generation',0))+(signature!=previous.get('signature'))
                old_signature=previous.get('signature',[])
                if not previous: change='initial'
                elif signature==old_signature: change='unchanged'
                elif len(old_signature)!=6 or schema_sha256!=old_signature[5]: change='schema_changed'
                elif signature[1]!=old_signature[1] or signature[2]<old_signature[2]: change='truncated_or_replaced'
                else: change='append_or_rewrite'
                prior[item_token]={'generation':current,'signature':signature}
                pending=journal.with_suffix('.pending');pending.write_text(json.dumps(prior));os.replace(pending,journal)
            finally: os.close(lock)
            descriptor.update(availability='available',source_generation=current,size_bytes=before.st_size,change=change,
                content_class='provisional_live' if item['live'] else 'provider_output')
            if operation in ('read','read_records','freeze'):
                if offset and item['format']=='csv':
                    os.lseek(fd,offset-1,os.SEEK_SET)
                    if os.read(fd,1)!=b'\n': raise ValueError('CSV cursor must start at a complete record boundary')

                if generation and int(generation)!=current: raise ValueError('Stale scientific output generation; observe again')
                limit=16777216 if operation=='freeze' else MAX_PAGE
                if offset<0 or count<1 or count>limit: raise ValueError('Output page exceeds its bounded contract')
                os.lseek(fd,offset,os.SEEK_SET);raw=os.read(fd,count)
                complete=True
                if item['format']=='csv' and raw:
                    end=raw.rfind(b'\n')+1
                    complete=(end==len(raw));raw=raw[:end]
                    if not raw and before.st_size>offset+count: raise ValueError('CSV record exceeds bounded page')
                after=os.fstat(fd)
                if (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns)!=tuple(signature[:5]):
                    raise ValueError('Scientific output changed during snapshot read')
                descriptor.update(bytes_base64=base64.b64encode(raw).decode(),next_offset=offset+len(raw),complete=complete)
                if operation=='read_records':
                    if item['format']!='csv' or not item['columns']: raise ValueError('Output has no registered complete-record CSV codec')
                    parsed=list(csv.reader(io.StringIO(raw.decode('utf-8'))))
                    if offset==0:
                        if not parsed or parsed.pop(0)!=[c['id'] for c in item['columns']]: raise ValueError('Scientific output schema changed')
                    for row in parsed:
                        if len(row)!=len(item['columns']): raise ValueError('Incomplete or malformed scientific record')
                        for value,column in zip(row,item['columns']):
                            kind=column['dtype']
                            if kind=='int64':
                                integer=int(value)
                                if not -(2**63)<=integer<2**63: raise ValueError('int64 record out of range')
                            elif kind=='float64':
                                if not math.isfinite(float(value)): raise ValueError('Nonfinite live scientific value')
                            elif kind!='string': raise ValueError('Unsupported live record datatype')
                    descriptor['records']=parsed
                    descriptor.pop('bytes_base64',None)

                if offset==0 and len(raw)==before.st_size and (operation=='freeze' or not item['live']):
                    descriptor['sha256']=hashlib.sha256(raw).hexdigest()
            result.append(descriptor)
        finally: os.close(fd)
    if token:
        if len(result)!=1: raise ValueError('Unknown or unauthorized scientific output token')
        return result[0]
    return {'availability':'available','job_id':job_id,'provider_id':manifest['provider_id'],
            'validation':manifest.get('validation','not_reported'),'summary':manifest.get('summary',{}),'outputs':result}

if __name__=='__main__':
    try:
        value=output_operation(sys.argv[1],sys.argv[2],sys.argv[3],*(sys.argv[4:5]),
            offset=int(sys.argv[5]) if len(sys.argv)>5 else 0,
            count=int(sys.argv[6]) if len(sys.argv)>6 else 65536,
            generation=sys.argv[7] if len(sys.argv)>7 else '')
        print(tvalue({'ok':True,'result':value}))
    except BaseException as exc:
        print(tvalue({'ok':False,'error':str(exc)}));sys.exit(1)
