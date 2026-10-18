"""Native bdb adapter inside the existing managed Python execution lifecycle."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import bdb,json,os,time,hashlib,uuid,types,sys
from itertools import islice
from pathlib import Path

def safe_value(value,depth=0):
    """Never invoke researcher repr/str/serialization hooks to draw an inspector."""
    kind=type(value);result={'type':type.__getattribute__(kind,'__name__'),'shape':[]};numpy=sys.modules.get('numpy');array_type=vars(numpy).get('ndarray') if numpy is not None else None
    if kind is int and value.bit_length()>1024:
        result['value']=f'Integer ({value.bit_length()} bits; decimal rendering omitted)'
    elif kind in (type(None),bool,int,float,complex):
        result['value']=repr(value)[:512]
    elif kind is str:result.update(value=value[:512],truncated=len(value)>512)
    elif kind in (list,tuple):
        result.update(shape=[len(value)],value=[safe_value(x,depth+1) for x in value[:12]] if depth<2 else 'nested value omitted',truncated=len(value)>12)
    elif kind is dict:
        result.update(shape=[len(value)],value={str(k)[:128]:safe_value(v,depth+1) for k,v in islice(value.items(),12) if type(k) in (str,bool) or type(k) is int and k.bit_length()<1024} if depth<2 else 'nested mapping omitted',truncated=len(value)>12)
    elif kind is array_type:
        result.update(shape=list(value.shape),dtype=str(value.dtype),value=value.flat[:12].tolist() if value.dtype.kind in 'biufc' and value.size else [],truncated=value.size>12)
        # JSON has no complex scalar; retain explicit primitive real/imaginary fields.
        if value.dtype.kind=='c':result['value']=[dict(real=float(x.real),imag=float(x.imag)) for x in value.flat[:12]]
    else:result['value']='Opaque object — no user representation method was called'
    return result

def atomic(path,value):
    temp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    with temp.open('x',encoding='utf-8') as f:json.dump(value,f,ensure_ascii=False,allow_nan=True)
    os.replace(temp,path)

class ManagedDebugger(bdb.Bdb):
    def __init__(self,source,breakpoints):
        super().__init__();self.source=str(Path(source).resolve());self.directory=Path(os.environ['GXTXT_DEBUG_DIRECTORY']);self.token=os.environ['GXTXT_DEBUG_TOKEN'];self.seq=0;self.last_check=0;self.last_command='';self.deadline=time.monotonic()+600
        self.source_sha=hashlib.sha256(Path(source).read_bytes()).hexdigest()
        self.frames=[]
        for line in breakpoints:
            error=self.set_break(self.source,int(line))
            if error:raise ValueError(f'Breakpoint {line}: {error}')
        self.publish('STARTING',line=0)
    def publish(self,state,**values):
        self.seq+=1;self.state=dict(schema='gxtxt.script_debug.v1',backend='python.bdb',state=state,source=self.source,source_sha256=self.source_sha,sequence=self.seq,job_id=os.environ.get('GXTXT_JOB_ID',''),**values);atomic(self.directory/'state.json',self.state)
    def command(self):
        path=self.directory/'command.json'
        try:
            if not path.is_file() or path.stat().st_size>16384:return None
            data=json.loads(path.read_text())
            if data.get('token')!=self.token or data.get('source_sha256')!=self.source_sha:raise ValueError('Debugger command identity mismatch')
            if data.get('id')==self.last_command:return None
            self.last_command=data['id'];return data
        except FileNotFoundError:return None
    def set_continue(self):
        # Keep native tracing active for Pause even when no breakpoint exists.
        self._set_stopinfo(self.botframe,None,-1)
        self.publish('RUNNING',line=0)
    def trace_dispatch(self,frame,event,arg):
        if time.monotonic()>self.deadline:self.set_quit();return None
        if time.monotonic()-self.last_check>.04:
            self.last_check=time.monotonic();command=self.command()
            if command and command['operation']=='pause':self.set_step()
            elif command and command['operation']=='stop':self.set_quit()
        return super().trace_dispatch(frame,event,arg)
    def stack_snapshot(self,frame,selected=0):
        frames=[];cursor=frame
        while cursor is not None and len(frames)<32:
            if str(Path(cursor.f_code.co_filename).resolve())==self.source:frames.append(cursor)
            cursor=cursor.f_back
        self.frames=frames;selected=max(0,min(selected,len(frames)-1));current=frames[selected] if frames else frame
        locals_={name:safe_value(value) for name,value in islice(current.f_locals.items(),128) if type(name) is str and not name.startswith('__')}
        globals_={name:safe_value(value) for name,value in islice(current.f_globals.items(),128) if type(name) is str and not name.startswith('__')}
        stack=[dict(index=i,file=f.f_code.co_filename,line=f.f_lineno,function=f.f_code.co_name) for i,f in enumerate(frames)]
        # Inspection follows the selected native frame; retain the actual stop
        # separately so a caller selection cannot mislabel its locals/arrow.
        return dict(line=current.f_lineno,function=current.f_code.co_name,execution_line=frame.f_lineno,execution_function=frame.f_code.co_name,stack=stack,selected_frame=selected,locals=locals_,globals=globals_,breakpoints=self.get_file_breaks(self.source))
    def user_line(self,frame):
        if str(Path(frame.f_code.co_filename).resolve())!=self.source:return
        self.publish('PAUSED',**self.stack_snapshot(frame))
        while True:
            if time.monotonic()>self.deadline:raise TimeoutError('Paused debugger lease expired after 600 seconds')
            command=self.command()
            if command:
                op=command['operation']
                if op=='frame':self.publish('PAUSED',**self.stack_snapshot(frame,int(command.get('frame',0))))
                elif op=='into':self.set_step();self.publish('CONTINUING',line=frame.f_lineno);return
                elif op=='over':self.set_next(frame);self.publish('CONTINUING',line=frame.f_lineno);return
                elif op=='out':self.set_return(frame);self.publish('CONTINUING',line=frame.f_lineno);return
                elif op=='continue':self.set_continue();return
                elif op=='stop':self.set_quit();return
                else:self.publish('PAUSED',**self.stack_snapshot(frame),diagnostic='Command is unavailable in this stopped state')
            time.sleep(.04)
    def user_return(self,frame,return_value):
        # The next caller line is handled by native bdb return/next semantics.
        pass
    def user_exception(self,frame,exc_info):
        if str(Path(frame.f_code.co_filename).resolve())==self.source:self.publish('EXCEPTION',line=frame.f_lineno,exception_type=exc_info[0].__name__)

def run_debug(code,namespace,source,breakpoints):
    debugger=ManagedDebugger(source,breakpoints)
    try:
        debugger.run(code,namespace,namespace)
        debugger.publish('CANCELLED' if debugger.quitting else 'COMPLETED',line=0)
    except BaseException as exc:
        debugger.publish('FAILED',line=0,error_type=type(exc).__name__)
        raise
