"""Managed native GNU Octave debugger transport; stopped values use JSON sideband."""
# SPDX-License-Identifier: GPL-3.0-or-later
import configparser,contextlib,errno,json,os,pty,re,selectors,signal,subprocess,sys,termios,time,uuid
from pathlib import Path
from gxtxt_python_debug import atomic

def literal(value):return "'"+str(value).replace("'","''")+"'"
def main():
    runtime=Path(sys.argv[1]);command=sys.argv[2:]
    config=configparser.ConfigParser(interpolation=None,strict=False);config.read(runtime)
    directory=Path(os.environ['GXTXT_DEBUG_DIRECTORY']);token=os.environ['GXTXT_DEBUG_TOKEN'];sha=config['config']['script_sha256']
    native=directory/'native_state.json';sequence=0;last_command='';paused=False;buffer=b'';deadline=time.monotonic()+600;pending_capture=False
    master,slave=pty.openpty();settings=termios.tcgetattr(slave);settings[3]&=~(termios.ECHO|termios.ECHONL);termios.tcsetattr(slave,termios.TCSANOW,settings)
    # The existing CORE runner and registered snapshot remain the scientific executor.
    command.insert(1,'--interactive');command.insert(2,'--no-history')
    child=subprocess.Popen(command,stdin=slave,stdout=slave,stderr=subprocess.PIPE,close_fds=True)
    os.close(slave);os.set_blocking(master,False);os.set_blocking(child.stderr.fileno(),False)
    selector=selectors.DefaultSelector();selector.register(master,selectors.EVENT_READ,'stdout');selector.register(child.stderr,selectors.EVENT_READ,'stderr')
    def send(text):os.write(master,(text+'\n').encode('utf-8'))
    def publish(state,**values):
        nonlocal sequence
        sequence+=1;atomic(directory/'state.json',dict(schema='gxtxt.script_debug.v1',backend='gnu_octave_native',state=state,sequence=sequence,source=str(snapshot),source_sha256=sha,job_id=os.environ.get('GXTXT_JOB_ID',''),**values))
    def capture():
        nonlocal pending_capture
        # Query dbstack in the selected native debug context, before entering
        # the observer function (which otherwise reports its own caller frame).
        send("[__gx_dbg_native_stack,__gx_dbg_native_frame]=dbstack('-completenames');gxtxt_debug_capture("+literal(native)+','+literal(token)+','+literal(sha)+",__gx_dbg_native_stack,__gx_dbg_native_frame);clear __gx_dbg_native_stack __gx_dbg_native_frame;");pending_capture=True
    normal_prompt=('GXTXT_'+token+'> ').encode('ascii')
    snapshot=Path(config['runtime']['output_dir'])/'executed_script.m'
    native_heading=re.compile(rb'(?m)^stopped in [^\r\n]+ at line [0-9]+ \['+re.escape(str(snapshot).encode('utf-8'))+rb'\][ \t]*\r?\n')
    def emit(data):
        def diagnostic(match):
            event=dict(source='gnu_octave_debugger',event='native_stop',text=match.group().decode('utf-8',errors='replace'))
            with (Path(config['runtime']['output_dir'])/'diagnostic.log').open('ab',buffering=0) as log:log.write((json.dumps(event,ensure_ascii=False)+'\n').encode('utf-8'))
            return b''
        data=native_heading.sub(diagnostic,data)
        if data:sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
    publish('STARTING',line=0)
    try:
        while child.poll() is None:
            if time.monotonic()>deadline:raise TimeoutError('GNU Octave debugger lease expired')
            for key,_ in selector.select(.04):
                try:raw=os.read(key.fd,65536)
                except OSError as exc:
                    if exc.errno==errno.EIO:raw=b''
                    else:raise
                if not raw:
                    selector.unregister(key.fileobj);continue
                if key.data=='stderr':sys.stderr.buffer.write(raw);sys.stderr.buffer.flush();continue
                buffer+=raw
                # Retain a small suffix so a split native prompt cannot leak or
                # discard preceding program bytes. Only dbstack sideband proves a stop.
                prompt=re.search(rb'(?:^|[\r\n])(?P<prompt>debug>[ \t]*)$',buffer)
                if prompt:
                    prefix=buffer[:prompt.start('prompt')]
                    if prefix:emit(prefix)
                    buffer=b''
                    if not paused and not pending_capture:capture()
                elif normal_prompt not in buffer:
                    newline=buffer.rfind(b'\n')
                    if newline>=0:emit(buffer[:newline+1]);buffer=buffer[newline+1:]
                    elif len(buffer)>16384:emit(buffer[:-256]);buffer=buffer[-256:]
            if pending_capture and native.is_file():
                observed=json.loads(native.read_text());native.unlink()
                if observed.pop('token',None)!=token or observed.get('source_sha256')!=sha:raise ValueError('Native debugger observation identity mismatch')
                if not observed.get('line') or not observed.get('stack'):raise RuntimeError('Native prompt did not yield an actual paused source frame')
                if isinstance(observed.get('stack'),dict):observed['stack']=[observed['stack']]
                observed.setdefault('selected_frame',0)
                observed.pop('state',None);observed.pop('sequence',None);observed.pop('schema',None);observed.pop('backend',None);observed.pop('source_sha256',None)
                publish('PAUSED',**observed);paused=True;pending_capture=False
            control=directory/'command.json'
            if control.is_file():
                message=json.loads(control.read_text())
                if message.get('id')!=last_command:
                    last_command=message['id']
                    if message.get('token')!=token or message.get('source_sha256')!=sha:raise ValueError('Native debugger command identity mismatch')
                    operation=message['operation']
                    if operation=='pause':raise ValueError('Asynchronous Pause is unsupported by this native Octave CLI adapter; no interrupt signal was sent')
                    elif operation=='stop':child.terminate()
                    elif operation=='frame' and paused:
                        frame=int(message.get('frame',0));send('dbdown(100);');
                        if frame:send('dbup('+str(frame)+');')
                        paused=False;capture()
                    elif paused and operation in {'into','over','out','continue'}:
                        send({'into':'dbstep in','over':'dbstep','out':'dbstep out','continue':'dbcont'}[operation]);paused=False;pending_capture=False;publish('RUNNING',line=0)
            report=Path(config['runtime']['output_dir'])/'octave_script_run_report.txt'
            if report.is_file() and buffer.endswith(normal_prompt) and not paused:
                emit(buffer[:-len(normal_prompt)]);buffer=b'';send('exit;')
        if buffer:emit(buffer)
        rc=child.wait();publish('COMPLETED' if rc==0 else 'FAILED',line=0,exit_code=rc);return rc
    finally:
        if child.poll() is None:
            child.terminate()
            with contextlib.suppress(subprocess.TimeoutExpired):child.wait(timeout=2)
            if child.poll() is None:child.kill();child.wait()
        selector.close();os.close(master)
if __name__=='__main__':raise SystemExit(main())
