# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded GDB/MI control of the already admitted Viewer native ABI worker.

No author expressions or debugger command text are accepted. The existing
Development owner admits/builds; its existing Script Job auxiliary request owns
the complete process tree. Numeric/UI callbacks use its exact shared broker.
"""
from pathlib import Path
import json, os, re, selectors, signal, subprocess, sys, time, uuid

class MI:
    def __init__(self,text):self.text=text;self.pos=0
    def value(self):
        s=self.text;i=self.pos
        if i>=len(s):return ''
        if s[i]=='"':
            i+=1
            while i<len(s):
                if s[i]=='\\':i+=2;continue
                if s[i]=='"':break
                i+=1
            result=json.loads(s[self.pos:i+1]);self.pos=i+1;return result
        if s[i] in '[{':
            closing=']' if s[i]=='[' else '}';self.pos+=1;rows=[];mapping={}
            while self.pos<len(s) and s[self.pos]!=closing:
                m=re.match(r'([A-Za-z_][A-Za-z0-9_-]*)=',s[self.pos:])
                if m:
                    self.pos+=len(m[0]);v=self.value()
                    if closing=='}':mapping[m[1]]=v
                    else:rows.append({m[1]:v})
                else:rows.append(self.value())
                if self.pos<len(s) and s[self.pos]==',':self.pos+=1
            self.pos+=1;return mapping if closing=='}' else rows
        end=self.pos
        while end<len(s) and s[end] not in ',]}':end+=1
        result=s[self.pos:end];self.pos=end;return result
    @classmethod
    def fields(cls,text):return cls('{'+text+'}').value()

def debug(project,breakpoints,event,state,debug_token=None):
    import gxtxt_viewer_development as dev
    from gxtxt_cpp_policy import FRAMEWORK,POLICY,ACTIVE_PROCESSES
    from gxtxt_viewer_native_worker import runtime_limits
    if not isinstance(breakpoints,list) or len(breakpoints)>128 or any(type(n)is not int or not 1<=n<=100000 for n in breakpoints):
        raise dev.DevelopmentError('Breakpoints require bounded physical source lines','DEBUG_BREAKPOINTS')
    debug_token=debug_token or uuid.uuid4().hex
    dev.read_project(project)
    channel=project/'derived/debug';channel.mkdir(exist_ok=True)
    initial={'schema':'gxtxt.viewer_cpp_debug.v1','backend':'GDB/MI2','state':'STARTING','debug_token':debug_token,'sequence':0,'frames':[],'locals':[],'errors':[]}
    dev.write_json(channel/'state.json',initial)
    try:built=dev.build(project,debug=True)
    except BaseException as error:
        initial.update(state='CANCELLED' if isinstance(error,(SystemExit,KeyboardInterrupt)) else 'FAILED',errors=[str(error)])
        dev.write_json(channel/'state.json',initial)
        raise
    if built['status']!='BUILT':
        initial.update(state='REJECTED',errors=['Current source was rejected before native execution; inspect compiler/policy diagnostics.'])
        dev.write_json(channel/'state.json',initial)
        return dict(built,debug=initial)
    meta,validation,design,requested=dev.validate(project)
    snapshot={k:validation[k] for k in ('source_sha256','design_sha256','project_sha256')}
    components=[dev.dictionary(v) for v in dev.tkinter.Tcl().splitlist(design['components'])]
    by_index={n+1:c for n,c in enumerate(components)}
    event=event or {'kind':1,'component':4,'value':18.0};state=state or {'values':[0.0]*16,'counter':0}
    if set(event)!={'kind','component','value'} or type(event['kind'])is not int or event['kind']not in range(6) or type(event['component'])is not int or event['component']not in {0,*by_index}:raise dev.DevelopmentError('Invalid native debug event','RUNTIME_EVENT')
    dev.finite(event['value'])
    if set(state)!={'values','counter'} or len(state['values'])!=16 or type(state['counter'])is not int or not 0<=state['counter']<2**32:raise dev.DevelopmentError('Invalid native debug state','RUNTIME_STATE')
    for v in state['values']:dev.finite(v)
    for name in ('command.json','worker-input.json','worker-output.json'):(channel/name).unlink(missing_ok=True)
    dev.write_json(channel/'worker-input.json',dict(library=str(project/'derived/debug-viewer.so'),event=event,state=state))
    current={'schema':'gxtxt.viewer_cpp_debug.v1','backend':'GDB/MI2','state':'STARTING','debug_token':debug_token,**snapshot,'sequence':0,'frames':[],'locals':[],
             'worker_limits':runtime_limits(),'active_wall_seconds':POLICY['process_timeout_seconds'],'paused_lease_seconds':900,
             'capabilities':{'controls':['continue','into','over','out','pause','stop','frame','children'],'pause_supported':True,'variable_children':True,'variable_page_size':64,'variable_depth_limit':8,'variable_node_limit':512},'errors':[], 'operations':[], 'numeric_receipts':[]}
    dev.write_json(channel/'state.json',current)
    command=['/usr/bin/gdb','--nx','--nh','--quiet','--interpreter=mi2',
             '-iex','set auto-load off','-iex','set debuginfod enabled off','-iex','set startup-with-shell off',
             '-iex','set pagination off','-iex','set confirm off','-iex','set print elements 16',
             '--args','/usr/bin/python3','-I','-B',str(FRAMEWORK/'core/python/gxtxt_viewer_native_worker.py'),'--debug-channel',str(channel)]
    selector=selectors.DefaultSelector();pending={};serial=0;buffer=b'';events=[];last_command=None
    deadline=time.monotonic()+900;running_since=None;active_seconds=0.;completed=None
    with (channel/'gdb.log').open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                 cwd=project,env=dev.project_environment(project),start_new_session=True)
        ACTIVE_PROCESSES.add(process.pid);selector.register(process.stdout,selectors.EVENT_READ)
        current['backend_pid']=process.pid
        def emit():
            current['sequence']+=1;dev.write_json(channel/'state.json',current)
        def issue(text,kind='control'):
            nonlocal serial
            serial+=1;pending[serial]=kind;process.stdin.write((str(serial)+text+'\n').encode());process.stdin.flush()
        def clear_variables():
            # Fixed varobjs belong to one authentic stop/frame. Never reuse
            # their children after execution or a selected-frame change.
            for local in current.get('locals',[]):
                if local.get('node_id'):issue('-var-delete '+json.dumps(local['node_id']),'delete_variable')
            current['inspection_id']=current.get('inspection_id',0)+1
            current['locals']=[];current['variable_nodes']={}
        def inspect_locals(frame):
            clear_variables()
            if Path(frame.get('fullname',frame.get('file',''))).name!='handlers.cpp':
                emit();return
            issue('-stack-list-variables --simple-values','locals:'+str(current['inspection_id']))
        def variable_record(value,name,depth):
            count=int(value.get('numchild',0))
            return {'node_id':value['name'],'name':str(name)[:256],
                    'type':str(value.get('type',''))[:256],
                    'value':str(value.get('value','not available'))[:512],
                    'child_count':max(0,count),'children':[],'loaded_count':0,
                    'depth':depth,'inspection_id':current['inspection_id']}
        def add_variable_children(parent,children,offset):
            positions=parent.setdefault('child_offsets',{})
            for index,value in enumerate(children):
                if len(current['variable_nodes'])>=512:
                    parent['children_error']='512 displayed-node limit reached for this stop/frame';break
                record=variable_record(value,value.get('exp',''),parent['depth']+1)
                child=record['node_id'];current['variable_nodes'][child]=record
                positions[child]=offset+index
            parent['children']=sorted(positions,key=positions.get)
        def request_variable_children(parent,scope,offset):
            identity=parent['node_id'];budget=min(64,512-len(current['variable_nodes']))
            parent['children_pending']=True
            if 'native_segments' not in parent:
                issue('-var-list-children --simple-values '+json.dumps(identity)+' '+str(offset)+' '+str(offset+budget),
                      'var:'+json.dumps(['children',scope,identity,offset]));return
            # GDB C++ access qualifiers are presentation pseudo-nodes. Fetch
            # their real fields within this same explicit, bounded expansion.
            jobs=[];position=0;remaining=budget
            for segment in parent['native_segments']:
                count=segment['count'];start=max(0,offset-position)
                if start<count and remaining:
                    amount=min(count-start,remaining)
                    if 'record' in segment:add_variable_children(parent,[segment['record']],position)
                    else:jobs.append((segment['node_id'],start,start+amount,position+start))
                    remaining-=amount
                position+=count
            parent['children_range_end']=offset+budget-remaining
            parent['children_pending_count']=len(jobs)
            for handle,start,end,logical in jobs:
                issue('-var-list-children --simple-values '+json.dumps(handle)+' '+str(start)+' '+str(end),
                      'var:'+json.dumps(['members',scope,identity,logical]))
            if not jobs:
                parent['loaded_count']=parent.pop('children_range_end')
                parent.pop('children_pending',None);parent.pop('children_pending_count',None)
        def variable_response(kind,result,failed):
            action,scope,identity,offset=json.loads(kind[4:])
            if scope!=current.get('inspection_id') or current['state']!='PAUSED':
                if action=='root' and not failed and result.get('name'):
                    issue('-var-delete '+json.dumps(result['name']),'delete_variable')
                return
            if action=='root':
                local=next((v for v in current['locals'] if v['name']==identity),None)
                if local is None:return
                if failed:local['inspection_error']=str(result.get('msg','unavailable'))[:512]
                else:
                    record=variable_record(result,identity,0)
                    if 'value' not in result:record['value']=local.get('value','not available')
                    local.update(record);current['variable_nodes'][record['node_id']]=local
            else:
                parent=current['variable_nodes'].get(identity)
                if not parent:return
                if failed:
                    parent.pop('children_pending',None)
                    parent['children_error']=str(result.get('msg','unavailable'))[:512]
                else:
                    children=[v.get('child',v) for v in result.get('children',[])][:64]
                    def qualifier(value):return value.get('exp') in {'public','private','protected'} and not value.get('type')
                    if action=='children' and offset==0 and len(children)==parent['child_count'] and any(qualifier(value) for value in children):
                        parent['native_segments']=[{'node_id':value['name'],'count':int(value.get('numchild',0))} if qualifier(value) else {'record':value,'count':1} for value in children]
                        parent['child_count']=sum(segment['count'] for segment in parent['native_segments'])
                        request_variable_children(parent,scope,0)
                    else:
                        add_variable_children(parent,children,offset)
                        if action=='members':
                            parent['children_pending_count']-=1
                            if not parent['children_pending_count']:
                                parent['loaded_count']=parent.pop('children_range_end')
                                parent.pop('children_pending',None);parent.pop('children_pending_count',None)
                        else:
                            parent['loaded_count']=offset+len(children);parent.pop('children_pending',None)
                        parent['has_more']=parent['loaded_count']<parent['child_count'] or result.get('has_more')=='1'
                        if not children and parent['has_more']:
                            parent['children_error']='GDB returned no further children for this range'
            emit()
        def changed():
            return any(dev.digest((project/name).read_bytes())!=snapshot[key] for name,key in [('handlers.cpp','source_sha256'),('design.gxtxt-viewer','design_sha256'),('project.json','project_sha256')])
        try:
            issue('-gdb-set breakpoint pending on')
            issue('-gdb-set mi-async on')
            for line in sorted(set(breakpoints)):
                issue('-break-insert -f '+json.dumps(str(project/'handlers.cpp')+':'+str(line)),'breakpoint')
            if not breakpoints:issue('-break-insert -f on_event','breakpoint')
            issue('-exec-run')
            while time.monotonic()<deadline:
                if changed():current['state']='SOURCE_CHANGED';current['errors'].append('Source/design/facilities changed; old binary cancelled');emit();break
                if running_since is not None and active_seconds+time.monotonic()-running_since>POLICY['process_timeout_seconds']:
                    current['state']='TIMED_OUT';current['errors'].append('Active execution budget exceeded');emit();break
                for key,_ in selector.select(.025):
                    chunk=os.read(key.fileobj.fileno(),65536)
                    if not chunk:continue
                    log.write(chunk);log.flush();buffer+=chunk
                    if len(buffer)>1048576:raise ValueError('GDB line exceeds bound')
                    while b'\n' in buffer:
                        raw,buffer=buffer.split(b'\n',1);line=raw.decode(errors='replace').strip()
                        if line.startswith('*running'):
                            if running_since is None:running_since=time.monotonic()
                            clear_variables();current['state']='RUNNING';emit()
                        elif line.startswith('*stopped'):
                            if running_since is not None:active_seconds+=time.monotonic()-running_since;running_since=None
                            detail=MI.fields(line.partition(',')[2]);reason=detail.get('reason','stopped')
                            if reason.startswith('exited'):
                                current['state']='COMPLETED' if reason=='exited-normally' else 'FAILED';current['exit_reason']=reason
                                if reason=='exited-signalled':
                                    current['exit_signal']=detail.get('signal-name','unknown')
                                    current['exit_signal_meaning']=detail.get('signal-meaning','')
                                    current['errors'].append('Native process terminated by '+current['exit_signal']+'; signal alone does not identify a resource-limit cause.')
                                emit();break
                            current.update(state='PAUSED',reason=reason,frame=detail.get('frame',{}),selected_frame=0,frames=[],locals=[])
                            events.append(detail);current['stops']=events[-128:];emit()
                            issue('-stack-list-frames 0 15','frames');inspect_locals(current['frame'])
                        elif re.match(r'^\d+\^',line):
                            m=re.match(r'^(\d+)\^([^,]+),?(.*)$',line);kind=pending.pop(int(m[1]),'control');result=MI.fields(m[3]) if m[3] else {}
                            if kind.startswith('var:'):variable_response(kind,result,m[2]=='error')
                            elif m[2]=='error':current['errors']=(current['errors']+[result.get('msg','GDB control error')])[-16:];emit()
                            elif kind=='frames':
                                current['frames']=[row.get('frame',row) for row in result.get('stack',[])][:16];emit()
                            elif kind=='frame':
                                current['frame']=result.get('frame',{});emit();inspect_locals(current['frame'])
                            elif kind.startswith('locals:'):
                                if int(kind[7:])!=current.get('inspection_id') or current['state']!='PAUSED':continue
                                variables=result.get('variables',[])
                                current['locals']=[]
                                for variable in variables:
                                    name=variable.get('name','')
                                    if name=='host' or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',name):continue
                                    if len(current['locals'])>=32:break
                                    current['locals'].append({'name':name,'type':str(variable.get('type',''))[:256],
                                                              'value':str(variable.get('value','not available'))[:512]})
                                    handle='gxv_'+str(current['inspection_id'])+'_'+str(len(current['locals']))
                                    issue('-var-create '+handle+' * '+json.dumps(name),
                                          'var:'+json.dumps(['root',current['inspection_id'],name,0]))
                                emit()
                output=channel/'worker-output.json'
                if output.exists():
                    if output.is_symlink() or output.stat().st_size>65536:raise ValueError('Invalid native debug protocol output')
                    message=json.loads(output.read_text());output.unlink()
                    if message.get('done'):
                        completed=message;current['native_result']=message;emit()
                    else:
                        if len(current['operations'])+len(current['numeric_receipts'])>=64:raise ValueError('Native callback budget exceeded')
                        response,ops,nums=dev.broker_message(project,message,by_index,requested,time.monotonic()+12)
                        current['operations'].extend(ops);current['numeric_receipts'].extend(nums)
                        dev.write_json(channel/'worker-input.json',response)
                control=channel/'command.json'
                if control.exists():
                    if control.is_symlink() or control.stat().st_size>16384:raise ValueError('Invalid debug control file')
                    data=json.loads(control.read_text());control.unlink()
                    if data.get('source_sha256')!=snapshot['source_sha256']:raise ValueError('Stale debugger control SHA')
                    operation=data.get('operation')
                    if operation=='stop':current['state']='CANCELLED';emit();break
                    if operation=='pause' and current['state']=='RUNNING':issue('-exec-interrupt --all')
                    elif operation=='children' and current['state']=='PAUSED':
                        identity=data.get('node_id');scope=data.get('inspection_id');offset=data.get('offset',0)
                        parent=current.get('variable_nodes',{}).get(identity)
                        if scope!=current.get('inspection_id') or not parent:
                            current['errors']=(current['errors']+['Variable belongs to an earlier stop/frame'])[-16:];emit();continue
                        if type(offset)is not int or offset!=parent['loaded_count'] or parent['depth']>=8 or len(current['variable_nodes'])>=512:
                            parent['children_error']='Variable inspection range/depth/node bound reached';emit();continue
                        if parent.get('children_pending'):continue
                        request_variable_children(parent,scope,offset);emit()
                    elif operation=='frame' and current['state']=='PAUSED':
                        clear_variables()
                        frame=data.get('frame',0)
                        if type(frame)is not int or not 0<=frame<16:raise ValueError('Frame index outside bound')
                        issue('-stack-select-frame '+str(frame));issue('-stack-info-frame','frame')
                        current['selected_frame']=frame;emit()
                    elif operation in {'continue','into','over','out'} and current['state']=='PAUSED':
                        issue({'continue':'-exec-continue','into':'-exec-step','over':'-exec-next','out':'-exec-finish'}[operation])
                        clear_variables();current['state']='CONTINUING';emit()
                    else:current['errors']=(current['errors']+['Control unavailable in current native state'])[-16:];emit()
                if current['state'] in {'COMPLETED','FAILED'}:break
                if process.poll() is not None:current['state']='FAILED';current['errors'].append('GDB exited before native completion');emit();break
            else:current['state']='TIMED_OUT';emit()
        except BaseException:
            if current['state'] not in {'COMPLETED','FAILED','SOURCE_CHANGED','TIMED_OUT'}:current['state']='CANCELLED'
            raise
        finally:
            if process.poll() is None:
                try:issue('-gdb-exit')
                except OSError:pass
                try:process.wait(timeout=.2)
                except subprocess.TimeoutExpired:
                    try:os.killpg(process.pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                    process.wait(timeout=3)
            ACTIVE_PROCESSES.discard(process.pid);selector.close();process.stdin.close();process.stdout.close()
            current['backend_reaped']=True;current['backend_exit_code']=process.returncode
            if current['state']=='COMPLETED' and (not completed or not completed.get('ok')):current['state']='FAILED'
            emit()
    return {'status':current['state'],'debug':current,'source_sha256':snapshot['source_sha256'],'binary_sha256':built['binary_sha256']}
