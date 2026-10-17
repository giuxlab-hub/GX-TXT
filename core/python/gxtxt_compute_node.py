"""Debian compute agent: authenticated projection of existing CORE authorities.

The HTTP loop admits no shell, scripts, filesystem paths or executable names.
Scientific Jobs belong exclusively to the existing node-local Job Supervisor.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse
import configparser
import hashlib
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import math
import os
from pathlib import Path
import platform
import sqlite3
import ssl
import uuid
import time
import _tkinter
import numpy as np
from gxtxt_remote_transport import MAX_BODY, pack, unpack
from gxtxt_script_bridge_server import Host

class Node:
    def __init__(self, config):
        self.config = config
        self.root = Path(config['state_root']).resolve(); self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        # These are installation/user configuration, never Session credentials.
        for name in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'GXTXT_JOB_ROOT', 'GXTXT_RESOURCE_ROOT'):
            os.environ[name] = str(self.root / name)
        self.hosts = {}; self.digests = {}; self.stages = {}
        self.db = sqlite3.connect(self.root / 'remote_requests.sqlite')
        self.db.execute('CREATE TABLE IF NOT EXISTS requests (client TEXT, nonce TEXT, fingerprint TEXT, state TEXT, job TEXT, PRIMARY KEY(client,nonce))')
        self.db.execute('CREATE TABLE IF NOT EXISTS resources (client TEXT, session TEXT, fingerprint TEXT, reference TEXT, PRIMARY KEY(client,session,fingerprint))')
        self.db.commit()

    def host(self, client, session):
        grants = self.config['clients'].get(client, {})
        if session not in grants.get('sessions', []): raise ValueError('Client is not authorized for this Session')
        if session not in self.config['sessions']: raise ValueError('Unknown authorized Session')
        if session not in self.hosts:
            path = Path(self.config['sessions'][session]).resolve()
            runtime = self.root / ('runtime_' + hashlib.sha256(session.encode()).hexdigest() + '.ini')
            cfg = configparser.ConfigParser(interpolation=None)
            cfg['runtime'] = dict(session=str(path), module_id='core.scientific_execution', run_id='compute-node')
            with runtime.open('w') as f: cfg.write(f)
            host = Host(runtime)
            host.call('::GX::scientificExecutionRegisterBuiltins')
            self.hosts[session] = host
        return self.hosts[session]

    def identity(self, host, dataset):
        host.call('::GX::loadDatasetRegistry', host.session)
        path = Path(str(host.call('::GX::datasetResolvePath', host.session, dataset)))
        stamp = path.stat(); key = (str(path), stamp.st_ino, stamp.st_size, stamp.st_mtime_ns)
        if key not in self.digests:
            with path.open('rb') as stream: digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            self.digests = {k:v for k,v in self.digests.items() if k[0] != str(path)}
            self.digests[key] = digest
        expected = str(host.call('::GX::datasetField', dataset, 'canonical_sha256', ''))
        if expected and expected != self.digests[key]: raise ValueError('Authoritative Dataset integrity mismatch')
        revision = str(host.call('format', '%s', host.call('::GX::datasetRevisionToken', dataset, host.session)))
        return hashlib.sha256((revision + '\0' + self.digests[key]).encode()).hexdigest()

    def dispatch(self, client, request, blobs=()):
        operation = request.get('operation'); args = request.get('arguments', [])
        if not isinstance(args, list) or len(args) > 12 or any(not isinstance(a, str) for a in args):
            raise ValueError('Invalid scoped CORE remote arguments')
        session = request.get('session_id', '')
        if operation == 'sessions':
            return dict(result=self.config['clients'].get(client, {}).get('sessions', [])), []
        host = self.host(client, session)
        text = lambda value: str(host.call('format', '%s', value))
        for token, stage in list(self.stages.items()):
            if time.monotonic()-stage['touched']>600:
                try:self.host(stage['client'],stage['session']).call('::GX::interactiveDocumentResourceAbort',stage['writer'])
                except Exception:pass
                del self.stages[token]
        if operation == 'resource.lookup' and len(args)==3:
            fingerprint=hashlib.sha256(('\0'.join(args)).encode()).hexdigest()
            prior=self.db.execute('SELECT reference FROM resources WHERE client=? AND session=? AND fingerprint=?',(client,session,fingerprint)).fetchone()
            if prior:
                try:
                    host.call('::GX::interactiveDocumentResourceInfo',prior[0])
                    return dict(result=prior[0]),[]
                except Exception:
                    self.db.execute('DELETE FROM resources WHERE client=? AND session=? AND fingerprint=?',(client,session,fingerprint));self.db.commit()
            return dict(result=''),[]
        if operation == 'resource.open':
            if len(args)!=3 or len(self.stages)>=16 or not 0<=int(args[2])<=8388608:
                raise ValueError('Remote staged input exceeds managed resource limits')
            document=host.as_dict(host.call('::GX::interactiveDocumentCreate','core.scientific_execution','managed_remote_input','binary',1,{}))
            writer=host.call('::GX::interactiveDocumentResourceOpenWriter',document['id'],args[0])
            token='stage-'+uuid.uuid4().hex
            self.stages[token]=dict(client=client,session=session,writer=writer,sha256=args[1],size=int(args[2]),offset=0,touched=time.monotonic(),fingerprint=hashlib.sha256(('\0'.join(args)).encode()).hexdigest())
            return dict(result=token),[]
        if operation.startswith('resource.'):
            if not args or args[0] not in self.stages: raise ValueError('Unknown remote resource stage')
            stage=self.stages[args[0]]
            if (stage['client'],stage['session'])!=(client,session): raise ValueError('Resource belongs to another grant')
            if operation=='resource.append' and len(args)==2 and len(blobs)==1:
                raw=blobs[0]
                if len(raw)>1048576 or int(args[1])!=stage['offset'] or stage['offset']+len(raw)>stage['size']:
                    raise ValueError('Invalid staged resource block offset/size')
                host.tcl.call('::GX::interactiveDocumentResourceAppend',stage['writer'],raw)
                stage['offset']+=len(raw);stage['touched']=time.monotonic()
                return dict(result=stage['offset']),[]
            if operation=='resource.finalize' and len(args)==1:
                if stage['offset']!=stage['size']: raise ValueError('Incomplete remote input')
                reference=host.call('::GX::interactiveDocumentResourceFinalize',stage['writer'])
                parsed=host.as_dict(reference)
                if str(parsed['sha256'])!=stage['sha256'] or int(parsed['size_bytes'])!=stage['size']:
                    raise ValueError('Staged input SHA/size disagrees with its source')
                self.db.execute('INSERT OR REPLACE INTO resources VALUES (?,?,?,?)',(client,session,stage['fingerprint'],text(reference)));self.db.commit()
                del self.stages[args[0]]
                return dict(result=reference),[]
            if operation=='resource.abort' and len(args)==1:
                host.call('::GX::interactiveDocumentResourceAbort',stage['writer']);del self.stages[args[0]]
                return dict(result='aborted'),[]
            raise ValueError('Unsupported managed resource operation')
        if blobs: raise ValueError('This operation does not accept arbitrary binary uploads')
        if operation == 'capabilities':
            providers = []
            for provider in host.as_list(host.call('::GX::scientificExecutionDiscover')):
                d = host.as_dict(host.call('::GX::scientificExecutionDescribe', provider)); tools = {}
                for tool in host.as_list(d['tools']):
                    try: tools[str(tool)] = bool(host.call('::GX::runtimeToolResolve', tool))
                    except Exception: tools[str(tool)] = False
                providers.append(dict(provider_id=str(provider), version=str(d['version']), available=all(tools.values()), tools=tools))
            import gxtxt_job_supervisor as supervisor
            c = supervisor.connect(supervisor.root_path(os.environ['GXTXT_JOB_ROOT']))
            policy = supervisor.policy(c); c.close()
            return dict(result=host.tcl_arg(dict(node_id=self.config['node_id'], os=platform.system(), architecture=platform.machine(), cores=os.cpu_count(), providers=[host.tcl_arg(p) for p in providers], policy=policy))), []
        if operation == 'dataset.catalog':
            entries = []
            for dataset in host.as_list(host.call('::GX::datasetRegistryIds')):
                revision = self.identity(host, dataset)
                fields = host.call('array', 'get', '::GX::datasetRegistry', str(dataset) + ',*')
                parsed = host.as_dict(fields)
                fields = {k[len(str(dataset))+1:]:v for k,v in parsed.items()}
                for name in ('path', 'source_raw', 'structured_metadata_file'): fields.pop(name, None)
                handle = None
                try:
                    handle = host.call('::GX::datasetAccessOpen', host.session, dataset)
                    metadata = host.call('::GX::datasetAccessMetadata', handle)
                except Exception:
                    metadata = host.tcl_arg(dict(dataset_id=str(dataset), variables=[], capabilities={}, availability='metadata_only'))
                finally:
                    if handle is not None: host.call('::GX::datasetAccessClose', handle)
                metadata_values=host.call('::GX::datasetMetadataRead',host.session,dataset)
                entries.append(host.tcl_arg(dict(dataset_id=str(dataset), revision=revision, fields=fields, metadata=metadata, metadata_values=metadata_values, coordinate_context=host.call('::GX::_datasetCoordinateStored',host.session,dataset))))
            return dict(result=host.tcl_arg(entries)), []
        if operation.startswith('dataset.'):
            if len(args) < 2: raise ValueError('Dataset ID and source revision required')
            dataset, expected, *bounds = args
            if expected != self.identity(host, dataset): raise ValueError('Remote Dataset source revision changed; refresh its catalog')
            if operation == 'dataset.preview' and len(bounds)==1:
                key=host.call('::GX::datasetPreviewCacheKey',dataset,bounds[0])
                result=host.call('::GX::datasetPreviewCacheRead',dataset,key)
                if not str(result):
                    state=host.as_dict(host.call('::GX::datasetPreviewCacheStatus',key))
                    if str(state['status'])=='error': raise ValueError(str(state.get('message','Remote Preview preparation failed')))
                    if str(state['status'])!='preparing': host.call('::GX::datasetPreviewCacheRequest',dataset,bounds[0])
                    return dict(pending=True,key=str(key)),[]
                blocks=[];artifacts=[]
                if int(host.call('dict','exists',result,'digitizer','images')):
                    images=host.as_dict(host.call('dict','get',result,'digitizer','images'))
                    for image_id,image in images.items():
                        info=host.as_dict(image);name='image_'+str(len(artifacts))+'.png'
                        raw=Path(str(info['path'])).read_bytes()
                        if len(raw)>2097152: raise ValueError('Remote image derivative exceeds 2 MiB')
                        artifacts.append(dict(image_id=image_id,name=name,block=len(blocks)))
                        blocks.append(raw)
                        result=host.call('dict','replace',result,'digitizer',host.call('dict','replace',host.call('dict','get',result,'digitizer'),'images',host.call('dict','replace',host.call('dict','get',result,'digitizer','images'),image_id,host.call('dict','replace',image,'path',name))))
                if int(host.call('dict','exists',result,'media_artifact','path')):
                    media=host.call('dict','get',result,'media_artifact')
                    raw=Path(str(host.call('dict','get',media,'path'))).read_bytes()
                    if len(raw)>2097152:raise ValueError('Remote media derivative exceeds 2 MiB')
                    name='image_'+str(len(artifacts))+'.png'
                    artifacts.append(dict(target='media_artifact',name=name,block=len(blocks)));blocks.append(raw)
                    result=host.call('dict','replace',result,'media_artifact',host.call('dict','replace',media,'path',name))
                if expected!=self.identity(host,dataset): raise ValueError('Remote source changed during Preview preparation')
                index=len(blocks);blocks.append(text(result).encode())
                return dict(result_block=index,artifacts=artifacts),blocks
            handle = host.call('::GX::datasetAccessOpen', host.session, dataset)
            try:
                if operation == 'dataset.metadata':
                    return dict(result=host.call('::GX::datasetAccessMetadata', handle)), []
                if operation == 'dataset.range' and len(bounds) == 3:
                    ids, start, count = bounds
                    if not 0 <= int(count) <= 65536: raise ValueError('Remote range count must be bounded to 65536')
                    data = host.as_dict(host.call('::GX::datasetAccessReadRange', handle, ids, start, count))
                elif operation == 'dataset.hyperslab' and len(bounds) == 3:
                    variable, starts, counts = bounds
                    shape = [int(v) for v in host.as_list(counts)]
                    if any(v < 0 for v in shape) or math.prod(shape) > 65536: raise ValueError('Remote hyperslab exceeds 65536 elements')
                    data = {variable:host.call('::GX::datasetAccessReadHyperslab', handle, variable, starts, counts)}
                else: raise ValueError('Unsupported remote Dataset operation')
                arrays = []; blobs = []
                for variable, raw in data.items():
                    item = host.as_dict(raw); values = host.as_list(item.pop('values'))
                    dtype_name=str(item['dtype'])
                    dtype = None if dtype_name in ('string','object') else np.dtype(dtype_name).newbyteorder('<')
                    if dtype is None or dtype.kind not in 'biuf':
                        # Text stays UTF-8 control data; numerical columns alone
                        # use raw typed blocks, including exact int64/uint64.
                        blob = json.dumps([str(v) for v in values], ensure_ascii=False).encode()
                        arrays.append(dict(variable_id=variable, text=True, block=len(blobs), receipt=text(host.tcl_arg(item))))
                    else:
                        missing = [i for i,v in enumerate(values) if str(v) == '']
                        if missing and dtype.kind not in 'f': raise ValueError('Missing integer values require a nullable provider contract')
                        converted = [str(v).lower() in ('1','true') if dtype.kind=='b' else ('nan' if str(v)=='' else str(v)) for v in values]
                        blob = np.asarray(converted, dtype=dtype).tobytes()
                        shape = [int(v) for v in str(item['shape']).split(';')]
                        if math.prod(shape) != len(values): raise ValueError('Remote shape/value mismatch')
                        arrays.append(dict(variable_id=variable, dtype=dtype.str, shape=shape, block=len(blobs), missing=missing, receipt=text(host.tcl_arg(item))))
                    blobs.append(blob)
                if expected != self.identity(host, dataset): raise ValueError('Dataset changed during bounded read')
                return dict(arrays=arrays, source_revision=expected), blobs
            finally: host.call('::GX::datasetAccessClose', handle)
        commands = {'scientific.prepare':('::GX::scientificExecutionPrepare', 4),
                    'job.describe':('::GX::scriptJobDescribe',1),
                    'job.inspect':('::GX::scriptJobInspect',1),
                    'job.log_read':('::GX::scriptJobLogRead',4),
                    'scientific.discard':('::GX::scientificExecutionDiscard', 1),
                    'scientific.status':('::GX::scientificExecutionStatus', 1),
                    'scientific.cancel':('::GX::scientificExecutionCancel', 1),
                    'scientific.log':('::GX::scientificExecutionLog', 4),
                    'scientific.outputs':('::GX::scientificExecutionOutputs', 1),
                    'scientific.read_output':('::GX::scientificExecutionReadOutput', 5),
                    'scientific.read_records':('::GX::scientificExecutionReadRecords', 5),
                    'scientific.import_results':('::GX::scientificExecutionImportResults', 3)}
        if operation=='scientific.freeze_output' and len(args)==5:
            status=host.as_dict(host.call('::GX::scientificExecutionStatus',args[0]))
            if str(status['state']) not in ('COMPLETED','FAILED','CANCELLED','INTERRUPTED'):raise ValueError('Only terminal scientific output can be frozen')
            return dict(result=host.call('::GX::_scientificExecutionOutput',args[0],'freeze',*args[1:])),[]
        if operation == 'scientific.submit':
            if len(args) != 1: raise ValueError('Submit requires a prepared token')
            nonce = request.get('nonce', '')
            if not nonce or len(nonce) > 128: raise ValueError('Durable submission nonce required')
            fingerprint = hashlib.sha256((session + '\0' + args[0]).encode()).hexdigest()
            prior = self.db.execute('SELECT fingerprint,state,job FROM requests WHERE client=? AND nonce=?', (client,nonce)).fetchone()
            if prior:
                if prior[0] != fingerprint: raise ValueError('Submission nonce was reused with different source identity')
                if prior[1] == 'completed': return dict(result=prior[2]), []
                raise ValueError('Submission outcome requires recovery; retry cannot create a duplicate Job')
            self.db.execute('INSERT INTO requests VALUES (?,?,?,?,?)',(client,nonce,fingerprint,'admitting','')); self.db.commit()
            result = text(host.call('::GX::scientificExecutionSubmit', args[0]))
            self.db.execute('UPDATE requests SET state=?,job=? WHERE client=? AND nonce=?',('completed',result,client,nonce));self.db.commit()
            return dict(result=result), []
        if operation not in commands or len(args) != commands[operation][1]: raise ValueError('Unregistered CORE remote operation')
        if operation.startswith(('scientific.','job.')) and operation not in ('scientific.prepare','scientific.discard'):
            job = host.as_dict(host.call('::GX::scriptJobDescribe',args[0]))
            # Grants bind both remote Session and the existing durable Job.
            if str(job['session']) != host.session: raise ValueError('Job belongs to another Session')
        return dict(result=host.call(commands[operation][0], *args)), []

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);args=parser.parse_args()
    config=json.loads(Path(args.config).read_text());node=Node(config)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass  # No request bodies or credentials in HTTP logs.
        def do_POST(self):
            try:
                self.connection.settimeout(15)
                if self.path != '/rpc': raise ValueError('Unknown CORE endpoint')
                length=int(self.headers.get('Content-Length','-1'))
                if not 0 < length <= MAX_BODY: raise ValueError('Invalid bounded request size')
                certificate=self.connection.getpeercert()
                client=next(v for section in certificate['subject'] for k,v in section if k=='commonName')
                if client not in config['clients']: raise ValueError('Client identity is not registered')
                request, blobs=unpack(self.rfile.read(length))
                result, blocks=node.dispatch(client,request,blobs)
                if 'result' in result and request.get('session_id'):
                    host=node.host(client,request['session_id'])
                    try:binary=host.call('dict','get',result['result'],'bytes_base64')
                    except Exception:binary=None
                    if binary is not None:
                        import base64
                        raw=base64.b64decode(str(binary),validate=True)
                        result['result']=host.call('dict','replace',result['result'],'bytes_base64','')
                        result['binary_field']='bytes_base64';result['binary_block']=len(blocks);blocks.append(raw)
                if 'result' in result: result['result']=str(node.host(client, request['session_id']).call('format','%s',result['result'])) if request.get('session_id') else json.dumps(result['result'])
                result.update(ok=True,node_id=config['node_id'])
                body=pack(result,blocks)
            except Exception as error:
                message=str(error)
                code='GX REMOTE REQUEST_FAILED'
                if 'revision changed' in message or 'source changed' in message:code='GX REMOTE STALE_SOURCE'
                elif 'integrity' in message or 'SHA/size' in message:code='GX REMOTE INTEGRITY'
                elif 'authorized' in message or 'another grant' in message or 'Client identity' in message:code='GX REMOTE DENIED'
                body=pack(dict(ok=False,node_id=config['node_id'],error=message,error_code=code))
            self.send_response(200);self.send_header('Content-Type','application/vnd.gxtxt.core-rpc');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    class Server(HTTPServer):
        def service_actions(self):
            # Existing CORE asynchronous Job callbacks run between RPCs. Heavy
            # Preview preparation belongs to the same node-local Supervisor.
            for host in list(node.hosts.values()):
                for _ in range(8):
                    if not host.tcl.dooneevent(_tkinter.DONT_WAIT):break
    server=Server((config.get('bind','127.0.0.1'),int(config['port'])),Handler)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(config['server_cert'],config['server_key']);context.load_verify_locations(config['ca_file']);context.verify_mode=ssl.CERT_REQUIRED
    server.socket=context.wrap_socket(server.socket,server_side=True)
    print(json.dumps(dict(ready=True,node_id=config['node_id'],port=server.server_port)),flush=True)
    server.serve_forever(poll_interval=.05)

if __name__=='__main__': main()
