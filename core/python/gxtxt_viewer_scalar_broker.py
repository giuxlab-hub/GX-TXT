# SPDX-License-Identifier: GPL-3.0-or-later
"""Finite transport to the existing scalar Numeric owner, outside author limits.

This owns no numerical implementation, registry or Job state. The same original
broker_message/core path admits every call. Native author limits remain intact.
"""
from pathlib import Path
import ctypes,json,math,os,select,signal,subprocess,sys,threading,time,uuid

sys.path.insert(0,str(Path(__file__).resolve().parent))
from gxtxt_job_supervisor import enable_subreaper,process_identity,process_tree,drain_tree,reap_adopted

SCALAR={4:'array_binary.add',6:'array_unary.sqrt',7:'array_unary.exp'}
OWNED=[]
SCOPE_KEY='GXTXT_VIEWER_SCALAR_SCOPE'

def refresh_owned(record,pid,token):
    if pid==os.getpid() or (record.get('pid_start') and process_identity(pid)==record['pid_start']):
        record['process_identities'].update({str(p):row[2] for p,row in process_tree(pid).items() if p!=os.getpid()})
    # The existing supervisor's exact identity rule also covers adopted nested
    # groups. This ephemeral tag is deliberately NOT a scientific Job identity.
    tag=(SCOPE_KEY+'='+token).encode()
    for path in Path('/proc').glob('[0-9]*/environ'):
        try:
            if path.stat().st_uid==os.getuid() and tag in path.read_bytes().split(b'\0'):
                child=int(path.parent.name);identity=process_identity(child)
                if child!=os.getpid() and identity:record['process_identities'][str(child)]=identity
        except (OSError,ValueError):pass
    # Keep live/zombie identities for drainage; discard completed/reused PIDs
    # before any waitpid, so a long-lived Viewer never reaps a later child.
    for child,start in tuple(record['process_identities'].items()):
        try:same=Path('/proc',child,'stat').read_text().rsplit(')',1)[1].split()[19]==start.rsplit(':',1)[1]
        except (OSError,IndexError):same=False
        if not same:record['process_identities'].pop(child,None)

def close_owned_brokers():
    for broker in tuple(OWNED):
        try:broker.close()
        except Exception:pass

class ScalarBroker:
    def __init__(self,work,source,validation,grants,environment,active):
        enable_subreaper()
        self.active=active;self.token=uuid.uuid4().hex;self.closed=False;self.buffer=b'';self.lock=threading.Lock()
        self.receipt=work/'derived'/('scalar-broker-'+self.token+'.json')
        env=dict(environment);env[SCOPE_KEY]=self.token
        self.errors=(work/'derived'/('scalar-broker-'+self.token+'.stderr')).open('wb')
        blocked=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGTERM,signal.SIGINT})
        try:
            self.child=subprocess.Popen([sys.executable,'-I','-B',str(Path(__file__).resolve()),str(work),str(os.getpid()),self.receipt.name],
                stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors,env=env,start_new_session=True)
            self.active.add(self.child.pid);OWNED.append(self)
            self.record=dict(run_id='compiled_viewer_scalar',job_root='',pid_start=process_identity(self.child.pid),process_identities={str(self.child.pid):process_identity(self.child.pid)})
        finally:signal.pthread_sigmask(signal.SIG_SETMASK,blocked)
        try:
            snapshot={key:validation[key] for key in ('source_sha256','design_sha256','project_sha256','source_tree_sha256','source_manifest') if key in validation}
            self.send(dict(schema='gxtxt.viewer_scalar_broker.v1',source=str(source),snapshot=snapshot,grants=sorted(grants)))
            ready=self.receive(time.monotonic()+5)
            if ready!=dict(ok=True,pid=self.child.pid):raise ValueError('Scalar broker did not admit its frozen source/grants')
        except BaseException:
            self.close();raise
    def send(self,value):
        data=json.dumps(value,allow_nan=False,separators=(',',':')).encode()+b'\n'
        if len(data)>65536:raise ValueError('Scalar broker framing exceeds64KiB')
        self.child.stdin.write(data);self.child.stdin.flush()
    def receive(self,deadline):
        while b'\n' not in self.buffer:
            refresh_owned(self.record,self.child.pid,self.token)
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('Public scalar Numeric request exceeded its existing event budget')
            if not select.select([self.child.stdout],[],[],min(.1,remaining))[0]:continue
            chunk=os.read(self.child.stdout.fileno(),65537)
            if not chunk:raise ValueError('Scalar broker ended before its typed response')
            self.buffer+=chunk
            if len(self.buffer)>65536:raise ValueError('Scalar broker response exceeds64KiB')
        line,self.buffer=self.buffer.split(b'\n',1)
        return json.loads(line)
    def call(self,message,deadline):
        with self.lock:
            if self.closed:raise ValueError('Scalar broker is closed; reopen the Viewer')
            self.send(dict(message=message,deadline=deadline))
            try:result=self.receive(deadline)
            except BaseException:self.close();raise
            if not result.get('ok'):raise ValueError(result.get('error','Scalar Numeric request failed'))
            return result['response'],[],result['numeric_receipts']
    def close(self):
        if self.closed:return
        self.closed=True
        refresh_owned(self.record,self.child.pid,self.token)
        try:
            if self.child.poll() is None:self.child.terminate()
            try:self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:pass
            refresh_owned(self.record,self.child.pid,self.token)
            drained=drain_tree(self.record,self.child.pid,timeout=1)
            if self.child.poll() is None:self.child.kill()
            self.child.wait(timeout=1);reap_adopted(self.record)
            self.cleanup=dict(pid=self.child.pid,reaped=True,descendants_drained=drained,returncode=self.child.returncode)
        finally:
            self.active.discard(self.child.pid)
            if self in OWNED:OWNED.remove(self)
            self.child.stdin.close();self.child.stdout.close();self.errors.close()
    def __enter__(self):return self
    def __exit__(self,*arguments):self.close()

def main():
    import gxtxt_viewer_development as dev
    if len(sys.argv)!=4:raise ValueError('Internal scalar broker requires its owned allocation/parent/receipt')
    work=Path(sys.argv[1]);parent=int(sys.argv[2]);name=sys.argv[3]
    if not work.is_absolute() or work.resolve()!=work or not __import__('re').fullmatch(r'scalar-broker-[0-9a-f]{32}\.json',name):raise ValueError('Invalid scalar broker allocation')
    enable_subreaper();token=os.environ.get(SCOPE_KEY,'')
    if not __import__('re').fullmatch(r'[0-9a-f]{32}',token):raise ValueError('Scalar broker scope is missing')
    record=dict(run_id='compiled_viewer_scalar',job_root='',process_identities={})
    receipt=dict(schema='gxtxt.viewer_scalar_broker.v1',pid=os.getpid(),parent_pid=parent,source_owner_sha256=dev.digest(Path(__file__).read_bytes()),state='STARTING')
    stopping=False
    def stop(signum,frame):
        nonlocal stopping
        if stopping:return
        stopping=True;raise SystemExit(128+signum)
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    # A hard-killed native parent must not leave a trusted CORE helper alive.
    if ctypes.CDLL(None,use_errno=True).prctl(1,signal.SIGTERM,0,0,0)!=0 or os.getppid()!=parent:raise ValueError('Scalar broker parent lifetime ended')
    signal.pthread_sigmask(signal.SIG_UNBLOCK,{signal.SIGTERM,signal.SIGINT})
    try:
        raw=sys.stdin.buffer.readline(65537)
        if len(raw)>65536:raise ValueError('Scalar broker configuration exceeds bound')
        config=json.loads(raw)
        if set(config)!={'schema','source','snapshot','grants'} or config['schema']!='gxtxt.viewer_scalar_broker.v1':raise ValueError('Invalid scalar broker configuration')
        source=Path(config['source']);snapshot=config['snapshot'];grants=config['grants']
        if not source.is_absolute() or source.resolve()!=source:raise ValueError('Scalar source must be the fixed ordinary admitted project root')
        meta=dev.read_project(source,installed=True)
        declared={operation for request in meta['capabilities'] if request.get('api_id')=='NUMERIC_API_v1' and request.get('version')==1 for operation in request['operations']}
        if not isinstance(grants,list) or not set(grants)<=set(SCALAR.values()) or not set(grants)<=declared:raise ValueError('Scalar grants differ from the frozen project')
        def unchanged():
            if not dev.sources_match(source,snapshot) or any(dev.digest((source/n).read_bytes())!=snapshot[k] for n,k in [('project.json','project_sha256'),('design.gxtxt-viewer','design_sha256')]):raise ValueError('Scalar broker source revision changed')
        unchanged();receipt.update(state='READY',snapshot=snapshot,grants=grants)
        dev.SCALAR_BROKER_CONTEXT=dict(token=token,core_requests={})
        dev.write_json(work/'derived'/name,receipt)
        print(json.dumps(dict(ok=True,pid=os.getpid())),flush=True)
        while True:
            raw=sys.stdin.buffer.readline(8193)
            if not raw:break
            try:
                if len(raw)>8192:raise ValueError('Scalar request exceeds8KiB')
                payload=json.loads(raw)
                if set(payload)!={'message','deadline'}:raise ValueError('Invalid scalar request envelope')
                message=payload['message'];deadline=payload['deadline']
                if not isinstance(message,dict) or set(message)!={'request','operation','component','left','right','text'} or type(message['operation'])is not int or message['operation'] not in SCALAR or type(message['request'])is not int or not 1<=message['request']<=64 or message['component']!=0 or message['text']!='':raise ValueError('Only fixed scalar SDK messages are admitted')
                if SCALAR[message['operation']] not in grants or type(deadline) not in {int,float} or not math.isfinite(deadline) or not 0<deadline-time.monotonic()<=13:raise ValueError('Scalar grant or event deadline is invalid')
                unchanged()
                response,operations,numeric=dev.broker_message(work,message,{}, {'NUMERIC_API_v1':set(grants)},deadline)
                unchanged();result=dict(ok=True,response=response,numeric_receipts=numeric)
            except Exception as error:result=dict(ok=False,error=str(error))
            encoded=json.dumps(result,allow_nan=False)
            if len(encoded.encode())>65536:raise ValueError('Scalar response exceeds bound')
            print(encoded,flush=True)
    finally:
        stopping=True;limit=time.monotonic()+1.5
        # A terminating Tcl helper can fork its native backend between samples.
        # Refresh adopted descendants until the whole exact scope is empty.
        while True:
            refresh_owned(record,os.getpid(),token)
            record['process_identities'].pop(str(os.getpid()),None)
            drain_tree(record,None,timeout=.2);reap_adopted(record)
            remaining=[pid for pid in process_tree(os.getpid()) if pid!=os.getpid()]
            if not remaining or time.monotonic()>=limit:break
        receipt.update(state='CLOSED',descendants_drained=not remaining,core_requests=(dev.SCALAR_BROKER_CONTEXT or {}).get('core_requests',{}),remaining_descendants=remaining)
        dev.write_json(work/'derived'/name,receipt)

if __name__=='__main__':main()
