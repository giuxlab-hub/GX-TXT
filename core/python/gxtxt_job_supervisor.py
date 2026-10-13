#!/usr/bin/env python3
"""Durable LOCAL script-job scheduler; scientific state stays in CORE APIs."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse, configparser, contextlib, fcntl, hashlib, json, os, signal, sqlite3
import subprocess, sys, time, uuid, io, stat
from pathlib import Path
# FUTURE WINDOWS PORTING REQUIREMENT (implementation intentionally deferred):
# LOCAL platform-independent CORE service, never remote job dispatch. Tk is not
# the process owner; closing GUI must not cancel jobs. A Windows adapter must
# run independently with a notification-area tray icon: reopen/focus GUI, inspect
# jobs, cancel selected/all (confirm cancel-all), safely exit supervisor. Reuse
# Job/Resource/Publication authorities and native Job Objects. No mandatory
# Windows service. Logout/shutdown may stop work; recover durable state next run.
ACTIVE=('QUEUED','PREPARING','RUNNING','FINALIZING')
TERMINAL=('COMPLETED','FAILED','CANCELLED','INTERRUPTED')
def root_path(root):
    p=Path(root).absolute()
    if p.is_symlink():raise ValueError('Job root cannot be a symlink')
    p.mkdir(parents=True,exist_ok=True,mode=0o700);st=p.stat()
    if st.st_uid!=os.getuid() or st.st_mode&0o077:raise ValueError('Job root must be owned by this account with mode 0700')
    return p.resolve()
def connect(root):
    c=sqlite3.connect(root/'jobs.sqlite',timeout=10,isolation_level=None);c.row_factory=sqlite3.Row
    c.execute('PRAGMA journal_mode=WAL');c.execute('PRAGMA synchronous=FULL')
    c.execute('CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,signature TEXT,state TEXT,created REAL,started REAL,finished REAL,pid INTEGER,cancel INTEGER DEFAULT 0,record TEXT,error TEXT DEFAULT "")')
    c.execute('CREATE UNIQUE INDEX IF NOT EXISTS active_signature ON jobs(signature) WHERE state IN ("QUEUED","PREPARING","RUNNING","FINALIZING")')
    c.execute('CREATE TABLE IF NOT EXISTS settings(id INTEGER PRIMARY KEY CHECK(id=1),value TEXT)')
    c.execute('INSERT OR IGNORE INTO settings VALUES(1,?)',(json.dumps(dict(max_jobs=1,max_queue=64,threads=1,timeout_seconds=86400,memory_mib=4096,temp_mib=8192,max_processes=64)),))
    return c
def policy(c):return json.loads(c.execute('SELECT value FROM settings').fetchone()[0])
def atomic_json(path,data):
    atomic_text(path,json.dumps(data,sort_keys=True))
def atomic_text(path,text):
    tmp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        with tmp.open('x',encoding='utf-8') as f:f.write(text);f.flush();os.fsync(f.fileno())
        os.replace(tmp,path);fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    finally:
        with contextlib.suppress(FileNotFoundError):tmp.unlink()
def process_identity(pid):
    try:
        fields=Path(f'/proc/{int(pid)}/stat').read_text().rsplit(')',1)[1].split()
        if fields[0]=='Z':return ''
        return Path('/proc/sys/kernel/random/boot_id').read_text().strip()+':'+fields[19]
    except (OSError,ValueError,IndexError):return ''
def enable_subreaper():
    # Local Linux backend only. A future Windows adapter uses Job Objects and
    # the independent supervisor/tray specified above, not a second authority.
    import ctypes
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(36,1,0,0,0)!=0:raise OSError(ctypes.get_errno(),'Cannot enable local child supervision')
def signal_tree(pid,start,sig):
    # POSIX backend boundary. Future Windows uses Job Objects, not PID-only kills.
    if start and process_identity(pid)==start:
        with contextlib.suppress(ProcessLookupError):os.killpg(pid,sig)
def status(row):
    d=json.loads(row['record']);d.update({k:row[k] for k in ('id','state','created','started','finished','pid','cancel','error')})
    if not d.get('script_version'):
        from gxtxt_script_inspection import submission_identity
        submission_identity(d)
    return d
def admit(c,root,r):
    identity={k:r[k] for k in ('session','reference','source_sha256','parameters','execution_inputs')}
    identity['inputs']={k:{f:v for f,v in b.items() if f not in ('label','namespace')} for k,b in r['inputs'].items()}
    signature=hashlib.sha256(json.dumps(identity,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    c.execute('BEGIN IMMEDIATE')
    try:
        existing=c.execute('SELECT * FROM jobs WHERE signature=? AND state IN (?,?,?,?)',(signature,*ACTIVE)).fetchone()
        if existing:
            c.execute('COMMIT');d=status(existing);d['deduplicated']=True;return d
        p=policy(c)
        if c.execute('SELECT count(*) FROM jobs WHERE state IN (?,?,?,?)',ACTIVE).fetchone()[0]>=p['max_queue']:raise ValueError('Script queue admission limit reached')
        target=r.get('output',{}).get('dataset_id','')
        if target:
            for row in c.execute('SELECT * FROM jobs WHERE state IN (?,?,?,?)',ACTIVE):
                other=json.loads(row['record'])
                if other['session']==r['session'] and other.get('output',{}).get('dataset_id')==target:raise ValueError('Output Dataset reserved by active job '+row['id'])
        jobid=r['run_id'];r['policy']=p;r['signature']=signature
        c.execute('INSERT INTO jobs(id,signature,state,created,record) VALUES(?,?,?,?,?)',(jobid,signature,'QUEUED',time.time(),json.dumps(r)));c.execute('COMMIT')
        return status(c.execute('SELECT * FROM jobs WHERE id=?',(jobid,)).fetchone())
    except BaseException:
        if c.in_transaction:c.execute('ROLLBACK')
        raise
def ensure(root):
    # Fast attachment avoids spawning a throwaway daemon for every GUI poll or
    # duplicate submission. The kernel lock remains the final admission guard.
    with open(root/'supervisor.lock','a+b') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        fcntl.flock(lock,fcntl.LOCK_UN)
    log=open(root/'supervisor.log','ab',buffering=0)
    subprocess.Popen([sys.executable,'-B',str(Path(__file__).resolve()),'--root',str(root),'serve'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True,close_fds=True);log.close()
def write_report(r,state,reason):
    cfg=configparser.ConfigParser(interpolation=None)
    cfg['execution']={k:str(v) for k,v in r.items() if isinstance(v,(str,int,float))}
    cfg['execution'].update(status='PASS' if state=='COMPLETED' else state,reason=reason,finished_at=str(time.time()),source_snapshot=r['snapshot'])
    cfg['parameters']={k:str(v) for k,v in r['parameters'].items()}
    text=io.StringIO();cfg.write(text);atomic_text(Path(r['output_dir'])/'execution.ini',text.getvalue())
def physical_memory():
    amount=os.sysconf('SC_PHYS_PAGES')*os.sysconf('SC_PAGE_SIZE')
    for path in ('/sys/fs/cgroup/memory.max','/sys/fs/cgroup/memory/memory.limit_in_bytes'):
        try:
            limit=Path(path).read_text().strip()
            if limit!='max':amount=min(amount,int(limit))
        except (OSError,ValueError):pass
    return amount

def process_tree(pid):
    records={}
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():continue
        try:
            f=(path/'stat').read_text().rsplit(')',1)[1].split()
            records[int(path.name)]=(int(f[1]),int(f[2]),boot+':'+f[19],int(f[21])*os.sysconf('SC_PAGE_SIZE'),int(f[17]),(int(f[11])+int(f[12]))/os.sysconf('SC_CLK_TCK'),f[0])
        except (OSError,ValueError,IndexError):continue
    selected={pid}
    while True:
        more={p for p,v in records.items() if v[0] in selected or v[1]==pid}
        if more<=selected:break
        selected|=more
    return {p:records[p] for p in selected if p in records}

def usage(pid):
    tree={p:v for p,v in process_tree(pid).items() if v[6]!='Z'}
    return dict(rss_bytes=sum(v[3] for v in tree.values()),threads=sum(v[4] for v in tree.values()),processes=len(tree),cpu_seconds=sum(v[5] for v in tree.values()),identities={str(p):v[2] for p,v in tree.items()})

def owned_processes(r,pid):
    identities=dict(r.get('process_identities',{}))
    if pid and r.get('pid_start') and process_identity(pid)==r['pid_start']:
        identities.update({str(p):v[2] for p,v in process_tree(pid).items() if v[6]!='Z'})
    # If a guardian is forcibly killed, adopted descendants may no longer have
    # its PPID or process group. Match this job's inherited local execution
    # identity, never process names or a broad filename pattern.
    job=('GXTXT_JOB_ID='+r['run_id']).encode();root=('GXTXT_JOB_ROOT='+r.get('job_root','')).encode()
    if r.get('job_root'):
        for path in Path('/proc').iterdir():
            if not path.name.isdigit() or int(path.name)==os.getpid():continue
            try:
                if path.stat().st_uid!=os.getuid():continue
                env=(path/'environ').read_bytes().split(b'\0')
                if job in env and root in env:
                    identity=process_identity(path.name)
                    if identity:identities[path.name]=identity
            except (OSError,ValueError):continue
    r['process_identities']=identities
    return {int(p):start for p,start in identities.items() if start and process_identity(p)==start}

def terminate(r,pid,sig):
    identities=owned_processes(r,pid)
    # Nested process groups are still owned descendants. Start tokens prevent
    # PID reuse from targeting an unrelated user's process.
    # Signal descendants before the guardian. The guardian retains the scratch
    # lease and handles SIGTERM while draining its children.
    for child,start in sorted(identities.items(),key=lambda item:item[0]==pid):
        if child==pid and sig==signal.SIGKILL and any(p!=pid and process_identity(p)==s for p,s in identities.items()):continue
        if process_identity(child)==start:
            with contextlib.suppress(ProcessLookupError):os.kill(child,sig)

def reap_adopted(r,exclude=()):
    for child in r.get('process_identities',{}):
        if int(child) in exclude:continue
        with contextlib.suppress(ChildProcessError,ProcessLookupError):os.waitpid(int(child),os.WNOHANG)

def drain_tree(r,pid,timeout=4):
    terminate(r,pid,signal.SIGTERM)
    deadline=time.monotonic()+timeout
    force_at=time.monotonic()+min(1.,timeout/2)
    while time.monotonic()<deadline:
        reap_adopted(r,exclude=(pid,))
        if not owned_processes(r,pid):return True
        if time.monotonic()>=force_at:terminate(r,pid,signal.SIGKILL)
        time.sleep(.03)
    return not owned_processes(r,pid)

def release_resources(r):
    from gxtxt_resource_manager import ResourceManager
    manager=ResourceManager(root=r.get('environment',{}).get('GXTXT_RESOURCE_ROOT'),storage_root=r.get('environment',{}).get('GXTXT_RESOURCE_STORAGE'))
    try:
        if owned_processes(r,r.get('worker_pid')):raise RuntimeError('Worker descendants remain; temporary resources retained')
        if r.get('temporary_resource'):
            manager.release(r['temporary_resource'],state='verified_orphan')
            r['resource_cleanup']=manager.cleanup([r['temporary_resource']])
        manager.observe(r['output_dir'],'script_jobs',category='protected_authoritative',job_id=r['run_id'],session=r['session'],recovery_required=True)
    finally:manager.close()

def publication_recover(r):
    framework=Path(__file__).resolve().parents[2]
    helper=framework/'core/tcl/script_job_recover.tcl'
    result=subprocess.run(['tclsh',str(helper),str(framework),r['session']],env={**os.environ,**r.get('environment',{})},capture_output=True,text=True,timeout=30)
    if result.returncode:raise RuntimeError('Publication recovery failed: '+result.stderr[-2000:])
    r['publication_recovery']='PASS'
    receipts=Path(r['output_dir'])/'published_datasets.json'
    if receipts.is_file():r['published_datasets']=json.loads(receipts.read_text())
    else:r['published_datasets']=[]

def progress(r):
    # Public Bridge progress is written to its diagnostic channel, while native
    # Octave progress uses the runner log. Read bounded tails from both owners.
    import re
    paths = [Path(r['log_path']), Path(r['output_dir'])/'bridge.log']
    paths = sorted((p for p in paths if p.is_file()), key=lambda p:p.stat().st_mtime_ns)
    for path in paths:
        try:
            with path.open('rb') as f:
                f.seek(max(0,os.fstat(f.fileno()).st_size-8192));lines=f.read().decode('utf-8','replace').splitlines()
        except FileNotFoundError:continue
        for line in reversed(lines):
            if line.startswith('@@GXTXT_PROGRESS_V1@@'):
                decode=lambda value:re.sub(r'\\([nrt\\])',lambda m:{'n':'\n','r':'\r','t':'\t','\\':'\\'}[m[1]],value)
                r['progress']={key:decode(value) for key,value in (field.split('=',1) for field in line.split('\t')[1:] if '=' in field)}
                break

def safe_report(r,state,reason):
    try:write_report(r,state,reason)
    except Exception as exc:r['report_error']=str(exc)

def terminal_commit(c,jid,r,state,reason):
    safe_report(r,state,reason)
    c.execute('UPDATE jobs SET state=?,finished=?,record=?,error=? WHERE id=?',
              (state,time.time(),json.dumps(r),reason,jid))

def module_projection(r):
    if not r.get('module_output'):return
    # Projection is derived UI convenience; immutable per-run files are always
    # authoritative. A failed projection cannot corrupt the scientific job.
    import shutil
    dest=Path(r['module_output']);dest.mkdir(parents=True,exist_ok=True)
    with (dest/'.script-result.lock').open('a+b') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        for name in ('execution.ini','python.log','octave.log','python_script_run_report.txt','octave_script_run_report.txt','executed_script.py','executed_script.m'):
            source=Path(r['output_dir'])/name
            if source.is_file():
                tmp=dest/(name+'.'+uuid.uuid4().hex+'.tmp')
                try:
                    shutil.copy2(source,tmp);os.replace(tmp,dest/name)
                finally:
                    with contextlib.suppress(FileNotFoundError):tmp.unlink()
        atomic_json(dest/'script_result.json',dict(run_id=r['run_id'],output_dir=r['output_dir']))

def finish_job(c,jid,r,state,reason,pid):
    r['terminal_intent']=state;r['terminal_reason']=reason
    c.execute('UPDATE jobs SET state="FINALIZING",record=?,error=? WHERE id=?',(json.dumps(r),reason,jid))
    if not drain_tree(r,pid):
        r['recovery_pending']='Worker descendants have not terminated; recovery and resource cleanup deferred'
        c.execute('UPDATE jobs SET record=?,error=? WHERE id=?',(json.dumps(r),r['recovery_pending'],jid))
        return False
    try:publication_recover(r)
    except Exception as exc:
        r['recovery_pending']=str(exc)
        c.execute('UPDATE jobs SET record=?,error=? WHERE id=?',(json.dumps(r),str(exc),jid))
        return False
    r.pop('recovery_pending',None)
    try:release_resources(r)
    except Exception as exc:r['resource_note']=str(exc)
    safe_report(r,state,reason)
    try:module_projection(r)
    except Exception as exc:r['projection_error']=str(exc)
    terminal_commit(c,jid,r,state,reason)
    return True

def recover(c):
    for row in c.execute('SELECT * FROM jobs WHERE state IN ("PREPARING","RUNNING","FINALIZING")').fetchall():
        r=json.loads(row['record']);pid=row['pid']
        # FINALIZING was durably reached after observing the actual worker exit;
        # preserve that outcome across a crash in publication/report cleanup.
        state=r.get('terminal_intent','INTERRUPTED')
        reason=r.get('terminal_reason','Supervisor restarted; interrupted work was not replayed')
        try:finish_job(c,row['id'],r,state,reason,pid)
        except Exception as exc:
            r['recovery_pending']=str(exc)
            c.execute('UPDATE jobs SET state="FINALIZING",record=?,error=? WHERE id=?',(json.dumps(r),str(exc),row['id']))

def temporary_size(path):
    size=0
    if not path:return 0
    for base,dirs,files in os.walk(path,followlinks=False):
        dirs[:]=[d for d in dirs if not os.path.islink(os.path.join(base,d))]
        for name in files:
            try:
                st=os.stat(os.path.join(base,name),follow_symlinks=False)
                if stat.S_ISREG(st.st_mode):size+=st.st_size
            except FileNotFoundError:pass
    return size

def poll_job(c,jid,item):
    proc,r=item['proc'],item['record'];row=c.execute('SELECT * FROM jobs WHERE id=?',(jid,)).fetchone();now=time.time()
    # Poll first: a late Cancel after successful exit must not relabel completed
    # publication as cancelled when no signal was actually requested.
    rc=proc.poll()
    progress(r)
    if rc is None:
        u=usage(proc.pid);r['process_identities']={**r.get('process_identities',{}),**u.pop('identities')};r['usage']=u
        for k in ('rss_bytes','processes','threads'):r['peak_'+k]=max(r.get('peak_'+k,0),u[k])
        limit=''
        if now-row['started']>r['policy']['timeout_seconds']:limit='Job time limit exceeded'
        if u['rss_bytes']>r['policy']['memory_mib']*1024**2:limit='Job memory limit exceeded'
        if u['processes']>r['policy']['max_processes']:limit='Job process limit exceeded'
        if now-item.get('disk_check',0)>2:
            item['disk_check']=now;r['temporary_bytes']=temporary_size(r.get('temp_dir'))
            if r['temporary_bytes']>r['policy']['temp_mib']*1024**2:limit='Job temporary disk limit exceeded'
        if row['cancel'] or limit:
            if 'stop_time' not in item:
                item['stop_time']=now;item['reason']=limit or 'Cancellation requested';item['cancel_signalled']=bool(row['cancel'])
                r['stop_requested_at']=now;r['stop_reason']=item['reason'];r['cancel_signalled']=item['cancel_signalled']
                terminate(r,proc.pid,signal.SIGTERM)
            elif now-item['stop_time']>3:terminate(r,proc.pid,signal.SIGKILL)
        c.execute('UPDATE jobs SET record=? WHERE id=?',(json.dumps(r),jid))
        return False
    item['stream'].close();r['exit_code']=rc
    if row['cancel'] and not item.get('cancel_signalled'):r['late_cancel_request']=True
    state='CANCELLED' if item.get('cancel_signalled') else ('FAILED' if rc or item.get('reason') else 'COMPLETED')
    reason=item.get('reason','' if rc==0 else f'Worker exit status {rc}')
    return finish_job(c,jid,r,state,reason,proc.pid)

def launch_job(c,root,row):
    r=json.loads(row['record']);jid=row['id'];r['job_root']=str(root)
    c.execute('UPDATE jobs SET state="PREPARING",started=?,record=? WHERE id=?',(time.time(),json.dumps(r),jid))
    proc=stream=None
    try:
        if hashlib.sha256(Path(r['snapshot']).read_bytes()).hexdigest()!=r['source_sha256']:raise ValueError('Source snapshot hash mismatch')
        env=dict(os.environ);env.update(r.get('environment',{}));env.update(GXTXT_JOB_ID=jid,GXTXT_JOB_ROOT=str(root),GXTXT_PARALLEL_DEPTH='1',GXTXT_JOB_THREADS=str(r['policy']['threads']),GXTXT_JOB_INTERNAL_THREADS=str(r['policy']['threads']),GXTXT_SUPERVISOR_PID=str(os.getpid()),GXTXT_SUPERVISOR_START=process_identity(os.getpid()),PYTHONUNBUFFERED='1',PYTHONDONTWRITEBYTECODE='1')
        for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS','BLIS_NUM_THREADS'):env[key]=str(r['policy']['threads'])
        stream=open(r['log_path'],'ab',buffering=0)
        command=[sys.executable,'-B',str(Path(__file__).with_name('gxtxt_job_worker.py')),r['runtime'],*r['command']]
        proc=subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT,cwd=r['session'],env=env,start_new_session=True,close_fds=True)
        r['pid_start']=process_identity(proc.pid);r['worker_pid']=proc.pid;r['launched_at']=time.time()
        if not r['pid_start']:raise RuntimeError('Job guardian exited during preparation')
        # Persist the guardian before allocating/issuing its permit. A child in
        # the tiny spawn/record gap cannot execute science and exits on parent
        # loss; a recorded child is explicitly drained by recovery.
        c.execute('UPDATE jobs SET pid=?,record=? WHERE id=?',(proc.pid,json.dumps(r),jid))
        from gxtxt_resource_manager import ResourceManager
        manager=ResourceManager(root=env.get('GXTXT_RESOURCE_ROOT'),storage_root=env.get('GXTXT_RESOURCE_STORAGE'))
        try:
            resource=manager.allocate('script_jobs',job_id=jid,session=r['session'],kind='directory',owner_pid=proc.pid,
                                      expected_bytes=int(r.get('estimated_temporary_bytes',0)),descendant_lease=True)
            r['temporary_resource']=resource['id'];r['temp_dir']=resource['path']
            # Normalize the actual shared authority into the durable request.
            r.setdefault('environment',{})['GXTXT_RESOURCE_ROOT']=str(manager.root)
            r['environment']['GXTXT_RESOURCE_STORAGE']=str(manager.storage)
        finally:manager.close()
        c.execute('UPDATE jobs SET state="RUNNING",record=? WHERE id=?',(json.dumps(r),jid))
        atomic_json(root/(jid+'.permit'),dict(pid=proc.pid,start=r['pid_start'],temp_dir=r['temp_dir'],
                    temp_identity=resource['identity'],resource_id=resource['id'],environment=r['environment']))
        return dict(proc=proc,record=r,stream=stream)
    except Exception as exc:
        reason='Launch failed: '+str(exc)
        if proc is not None:
            drain_tree(r,proc.pid)
            with contextlib.suppress(subprocess.TimeoutExpired):proc.wait(timeout=2)
        if stream is not None:stream.close()
        # Persist before any fallible report or resource cleanup, so no queued
        # restart can duplicate a partially launched worker.
        try:finish_job(c,jid,r,'FAILED',reason,proc.pid if proc else None)
        except Exception as cleanup:
            r['recovery_pending']=str(cleanup);r['terminal_intent']='FAILED';r['terminal_reason']=reason
            c.execute('UPDATE jobs SET state="FINALIZING",record=?,error=? WHERE id=?',(json.dumps(r),str(cleanup),jid))
        return None

def serve(root):
    lock=open(root/'supervisor.lock','a+b')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:return
    enable_subreaper()
    c=connect(root);recover(c);running={};last_session='';idle=time.monotonic();last_recovery=0
    atomic_json(root/'supervisor.json',dict(pid=os.getpid(),pid_start=process_identity(os.getpid()),started=time.time()))
    while True:
        p=policy(c)
        for jid,item in list(running.items()):
            try:
                if poll_job(c,jid,item):del running[jid]
            except Exception as exc:
                r=item['record'];r['supervision_error']=str(exc)
                try:
                    if finish_job(c,jid,r,'FAILED','Job supervision failed: '+str(exc),item['proc'].pid):
                        item['proc'].wait(timeout=2);item['stream'].close();del running[jid]
                except Exception as recovery:
                    r['recovery_pending']=str(recovery)
                    c.execute('UPDATE jobs SET state="FINALIZING",record=?,error=? WHERE id=?',(json.dumps(r),str(recovery),jid))
        # Previously crashed finalizations are retried without replaying the
        # script. Their active output reservation remains until recovery passes.
        if time.monotonic()-last_recovery>2:
            for row in c.execute('SELECT * FROM jobs WHERE state="FINALIZING"').fetchall():
                if row['id'] in running:continue
                r=json.loads(row['record'])
                try:finish_job(c,row['id'],r,r.get('terminal_intent','INTERRUPTED'),r.get('terminal_reason','Interrupted work recovery'),row['pid'])
                except Exception as exc:
                    r['recovery_pending']=str(exc);c.execute('UPDATE jobs SET record=?,error=? WHERE id=?',(json.dumps(r),str(exc),row['id']))
            last_recovery=time.monotonic()
        for row in c.execute('SELECT * FROM jobs WHERE state="QUEUED" AND cancel=1').fetchall():
            terminal_commit(c,row['id'],json.loads(row['record']),'CANCELLED','Cancelled before execution')
        if len(running)<p['max_jobs']:
            rows=c.execute('SELECT * FROM jobs WHERE state="QUEUED" ORDER BY created').fetchall();rows.sort(key=lambda row:json.loads(row['record'])['session']==last_session)
            for row in rows:
                if len(running)>=p['max_jobs']:break
                pending=json.loads(row['record'])
                reserved=sum(item['record']['policy']['memory_mib']*1024**2 for item in running.values())
                cpus=sum(item['record']['policy']['threads'] for item in running.values())
                if reserved+pending['policy']['memory_mib']*1024**2>physical_memory()*.8 or cpus+pending['policy']['threads']>max(1,os.cpu_count() or 1):
                    pending['queue_reason']='Waiting for CPU or memory reservation budget'
                    c.execute('UPDATE jobs SET record=? WHERE id=?',(json.dumps(pending),row['id']))
                    continue
                last_session=pending['session']
                item=launch_job(c,root,row)
                if item is not None:running[row['id']]=item
        pending=c.execute('SELECT count(*) FROM jobs WHERE state IN ("QUEUED","PREPARING","RUNNING","FINALIZING")').fetchone()[0]
        if running or pending:idle=time.monotonic()
        elif time.monotonic()-idle>60:
            # Close the idle-exit/submit race: submit cannot commit while this
            # check runs; release the daemon lock before allowing it to commit.
            c.execute('BEGIN IMMEDIATE')
            try:
                empty=not c.execute('SELECT count(*) FROM jobs WHERE state IN ("QUEUED","PREPARING","RUNNING","FINALIZING")').fetchone()[0]
                if empty:fcntl.flock(lock,fcntl.LOCK_UN)
                c.execute('COMMIT')
            except BaseException:
                c.execute('ROLLBACK');raise
            if empty:break
        time.sleep(.25)
def tcl_result(value):
    import tkinter
    if isinstance(value,dict):return tkinter._join(tuple(x for k,v in value.items() for x in (k,tcl_result(v))))
    if isinstance(value,list):return tkinter._join(tuple(tcl_result(v) for v in value))
    if value is None:return ''
    if isinstance(value,bool):return str(int(value))
    return str(value)
def read_request():
    import tkinter
    t=tkinter.Tcl()
    def d(v):
        a=t.splitlist(v);return dict(zip(a[::2],a[1::2]))
    r=d(sys.stdin.read())
    for key in ('parameters','output','execution_inputs','environment'):r[key]=d(r.get(key,''))
    r['inputs']={k:d(v) for k,v in d(r.get('inputs','')).items()};r['command']=list(t.splitlist(r['command']));return r
def main():
    a=argparse.ArgumentParser();a.add_argument('--root',required=True);a.add_argument('operation');a.add_argument('args',nargs='*');args=a.parse_args();root=root_path(args.root)
    if args.operation=='serve':serve(root);return
    c=connect(root)
    if args.operation=='submit':result=admit(c,root,read_request());ensure(root)
    elif args.operation=='list':result=[status(r) for r in c.execute('SELECT * FROM jobs ORDER BY created DESC LIMIT 100')]
    elif args.operation in ('describe','inspect','log_read'):
        row=c.execute('SELECT * FROM jobs WHERE id=?',(args.args[0],)).fetchone()
        if not row:raise ValueError('Unknown job ID')
        result=status(row)
        if args.operation!='describe':
            from gxtxt_script_inspection import inspect_run, log_read
            if args.operation=='inspect':result=inspect_run(result['session'],result['id'],result)
            else:result=log_read(result['session'],result['id'],result,*args.args[1:])
    elif args.operation in ('inspect_run','run_log_read'):
        from gxtxt_script_inspection import inspect_run, log_read
        session,run_id=args.args[:2]
        row=c.execute('SELECT * FROM jobs WHERE id=?',(run_id,)).fetchone()
        record=status(row) if row else None
        if record and Path(record['session']).resolve()!=Path(session).resolve():record=None
        result=inspect_run(session,run_id,record,verify=args.operation=='inspect_run')
        if args.operation=='run_log_read':result=log_read(session,run_id,result,*args.args[2:])
    elif args.operation=='run_summaries':
        from gxtxt_script_inspection import run_summaries
        result=run_summaries(args.args[0],[status(r) for r in c.execute("SELECT * FROM jobs WHERE json_extract(record,'$.session')=? LIMIT 4096",(str(Path(args.args[0]).resolve()),))])
    elif args.operation=='cancel':
        c.execute('UPDATE jobs SET cancel=1 WHERE id=? AND state IN (?,?,?,?)',(args.args[0],*ACTIVE));result={'cancel_requested':bool(c.execute('SELECT changes()').fetchone()[0])};ensure(root)
    elif args.operation=='recover':ensure(root);result={'recovery_requested':True}
    elif args.operation=='configure':
        p=policy(c)
        for field in args.args:
            k,v=field.split('=',1)
            if k not in p or int(v)<1:raise ValueError('Invalid job policy')
            p[k]=int(v)
        if p['memory_mib']*1024**2>physical_memory()*.8:raise ValueError('Per-job RAM reservation exceeds 80% of physical memory')
        if p['max_jobs']*p['threads']>max(1,os.cpu_count() or 1):raise ValueError('Concurrent thread budget exceeds available CPUs')
        c.execute('UPDATE settings SET value=? WHERE id=1',(json.dumps(p),));result=p
    else:raise ValueError('Unknown Job API operation')
    print(tcl_result(dict(ok=1,result=result)))
if __name__=='__main__':
    os.umask(0o077)
    try:main()
    except Exception as exc:print(tcl_result(dict(ok=0,error=str(exc))));sys.exit(1)
