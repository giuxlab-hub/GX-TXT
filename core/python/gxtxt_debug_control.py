"""Sideband controls owned and authorized by the existing Script Job supervisor."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib,json,os,secrets,uuid
from pathlib import Path

def capabilities(language):
    if language not in ('Python','Octave'):raise ValueError('Native debugger language must be Python or Octave')
    controls=['continue','into','over','out','frame','stop']
    if language=='Python':controls.append('pause')
    reason='' if language=='Python' else 'The managed GNU Octave CLI adapter has no verified asynchronous Pause. Interrupting can terminate a loop; use native breakpoints, steps or Stop.'
    return dict(language=language,backend='python.bdb' if language=='Python' else 'gnu_octave_native',controls=controls,pause_supported=language=='Python',pause_reason=reason)

def prepare(record,environment):
    directory=Path(record['output_dir'])/'debug';directory.mkdir(mode=0o700)
    token=secrets.token_hex(32);record['debug_directory']=str(directory);record['debug_token']=token
    environment.update(GXTXT_DEBUG_DIRECTORY=str(directory),GXTXT_DEBUG_TOKEN=token)

def inspect(record):
    directory=Path(record['output_dir'])/'debug';path=directory/'state.json'
    if directory.is_symlink() or path.is_symlink():raise ValueError('Unsafe debugger state path')
    if not path.is_file():return dict(state='STARTING' if record['state'] in ('QUEUED','PREPARING','RUNNING') else record['state'],source_sha256=record['source_sha256'],sequence=0,capabilities=capabilities(record['language']))
    if path.stat().st_size>2097152:raise ValueError('Debugger state exceeded 2 MiB')
    result=json.loads(path.read_text())
    if result.get('source_sha256')!=record['source_sha256']:raise ValueError('Debugger source revision mismatch')
    if record['state'] in ('COMPLETED','FAILED','CANCELLED','INTERRUPTED'):result['state']=record['state']
    result['capabilities']=capabilities(record['language'])
    return result

def control(record,operation,source_sha256,frame=0):
    if record.get('origin')=='core_service' or not record.get('debug'):raise ValueError('This is not a user-initiated Debug Job')
    if source_sha256!=record['source_sha256']:raise ValueError('Stale debugger command source SHA')
    state=inspect(record)
    if operation not in {'into','over','out','continue','pause','frame','stop'}:raise ValueError('Unsupported debugger control')
    supported=capabilities(record['language'])
    if operation not in supported['controls']:raise ValueError(supported['pause_reason'] or 'Unsupported native debugger control')
    if operation=='pause' and state['state'] not in ('RUNNING','CONTINUING'):raise ValueError('Pause requires actual native running state')
    if operation not in {'pause','stop'} and state['state']!='PAUSED':raise ValueError('This debugger command requires an actual paused frame')
    if record['state'] not in ('RUNNING','PREPARING'):raise ValueError('Debug Job is no longer running')
    if not 0<=int(frame)<32:raise ValueError('Frame index must be 0..31')
    value=dict(operation=operation,source_sha256=source_sha256,frame=int(frame),token=record['debug_token'],id=uuid.uuid4().hex)
    directory=Path(record['debug_directory']);temporary=directory/(value['id']+'.pending')
    with temporary.open('x',encoding='utf-8') as f:json.dump(value,f)
    os.replace(temporary,directory/'command.json')
    return dict(accepted=True,operation=operation,state=state['state'],source_sha256=source_sha256)
