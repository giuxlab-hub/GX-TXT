"""Local configuration, exact source approval and optional service lifecycle."""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import time
import socket
import fcntl
import shutil
import stat
import re

from . import __version__, SDK_VERSION, PROTOCOL_VERSION
from .config import Store, ConfigurationError, framework_info, identifier, private
from .compatibility import declarations


def diagnostic_error(error):
    """Expose controlled CLI errors through SDK task groups without raw logs."""
    if isinstance(error, BaseExceptionGroup):
        leaves=[]
        def visit(group):
            for item in group.exceptions:
                if isinstance(item, BaseExceptionGroup):visit(item)
                elif isinstance(item, ConfigurationError):leaves.append(str(item))
        visit(error)
        if leaves:return '; '.join(dict.fromkeys(leaves))
        return 'MCP transport failed during the authenticated connection. Check the private adapter diagnostic log and selected client grants.'
    return str(error)


def test_tool_error(result, fallback):
    """Keep controlled contract/grant reasons, without copying arbitrary logs."""
    for block in result.content:
        text=getattr(block,'text','')
        match=re.search(r'GXTXT:MCP:(?:ContractIncompatible|SessionDenied|SessionUnavailable|AuthenticationDenied|ContextLost):[^\r\n]+',text)
        if match:return ConfigurationError(match.group(0)[:512])
    return ConfigurationError(fallback)


def process_identity(pid):
    try:
        fields=Path(f'/proc/{int(pid)}/stat').read_text().rsplit(')',1)[1].split()
        if fields[0]=='Z':return ''
        return Path('/proc/sys/kernel/random/boot_id').read_text().strip()+':'+fields[19]
    except (OSError,ValueError,IndexError):return ''


def status(store):
    value=store.public()
    value.update(component_version=__version__,sdk_version=importlib.metadata.version('mcp'),protocol_version=PROTOCOL_VERSION,
                 running=False,state='Disabled' if not value['enabled'] else ('Ready for stdio client' if value['transport']=='stdio' else 'Stopped'))
    try:
        value['framework']=framework_info(value['framework_root']);value['component_state']='Ready'
    except (OSError,ConfigurationError) as error:
        value['component_state']='Error';value['capability_error']=str(error)
    state=store.home/'service.json'
    if state.exists():
        private(state);record=json.loads(state.read_text())
        if process_identity(record['pid'])==record['process']:
            value.update(running=True,state='Running',pid=record['pid'])
        elif value['enabled'] and value['transport']=='streamable-http':value['state']='Stopped or interrupted'
    health=store.home/'health.json'
    if health.exists():
        private(health)
        if health.stat().st_size>65536:raise ConfigurationError('MCP health record exceeds its budget')
        value['health']=json.loads(health.read_text())
    return value


def check(store):
    value=store.read()
    if importlib.metadata.version('mcp')!=SDK_VERSION:raise ConfigurationError('MCP SDK does not match the tested pinned dependency')
    result=declarations(value)
    result.update(component_version=__version__,sdk_version=SDK_VERSION,protocol_version=PROTOCOL_VERSION)
    # Inert original declaration discovery proves the installed binding set,
    # not activation. Actual client/Session calls remain a separate Test.
    return result


def cleanup_contexts(store):
    """Remove only orphaned transport directories with a verified free lease."""
    store.prepare();removed=0
    for path in (store.home/'contexts').glob('context-*'):
        try:
            private(path,directory=True)
            lease=path/'.lease';private(lease)
            descriptor=os.open(lease,os.O_RDWR|os.O_NOFOLLOW|os.O_CLOEXEC)
            try:
                info=os.fstat(descriptor)
                if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o600:continue
                if (info.st_dev,info.st_ino)!=(lease.lstat().st_dev,lease.lstat().st_ino):continue
                try:fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:continue
                shutil.rmtree(path);removed+=1
            finally:os.close(descriptor)
        except (FileNotFoundError,ConfigurationError):continue
    return removed


def start(store):
    value=store.read()
    if not value['enabled']:raise ConfigurationError('Enable the optional service explicitly before Start')
    check(store)
    current=status(store)
    if current['running']:return current
    cleanup_contexts(store)
    if value['transport']=='stdio':return current
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        try:probe.bind((value['host'],value['port']))
        except OSError:raise ConfigurationError('Selected MCP loopback port is already in use') from None
    log=store.home/'service.log'
    with log.open('ab') as stream:
        os.chmod(log,0o600)
        child=subprocess.Popen([sys.executable,str(Path(__file__).parents[1]/'gxtxt-mcp'),
             '--home',str(store.home),'serve','--transport','streamable-http'],
             stdin=subprocess.DEVNULL,stdout=stream,stderr=stream,start_new_session=True)
    identity=process_identity(child.pid)
    if not identity:raise ConfigurationError('MCP service failed to start; inspect its private local diagnostic log')
    state=store.home/'service.json'
    fd=os.open(state,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as stream:json.dump({'pid':child.pid,'process':identity,'transport':'streamable-http'},stream)
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        if child.poll() is not None:
            raise ConfigurationError('MCP service failed during startup; inspect its private service log')
        try:
            with socket.create_connection(('127.0.0.1',value['port']),timeout=.2):break
        except OSError:time.sleep(.05)
    else:
        stop(store)
        raise ConfigurationError('MCP endpoint did not become ready within15seconds')
    return status(store)


def stop(store):
    state=store.home/'service.json'
    if state.exists():
        private(state);record=json.loads(state.read_text())
        if process_identity(record['pid'])==record['process']:
            os.kill(record['pid'],signal.SIGTERM)
            deadline=time.monotonic()+10
            while process_identity(record['pid'])==record['process'] and time.monotonic()<deadline:time.sleep(.05)
            if process_identity(record['pid'])==record['process']:
                raise ConfigurationError('MCP adapter did not stop; retained state identifies only its owned process')
        if state.exists():state.unlink()
    cleanup_contexts(store)
    return status(store)


def emit(result,format='json',error=False):
    if format=='tcl':
        import tkinter
        t=tkinter.Tcl()
        def wire(value):
            if isinstance(value,dict):return t.call('format','%s',t.call('dict','create',*[v for k,item in value.items() for v in (k,wire(item))]))
            if isinstance(value,list):return t.call('format','%s',tuple(wire(v) for v in value))
            if isinstance(value,bool):return '1' if value else '0'
            if value is None:return ''
            return str(value)
        print(wire({'ok':not error,('error' if error else 'result'):result}))
    else:print(json.dumps(result,indent=2),file=sys.stderr if error else sys.stdout)


async def test_connection(store,token,session=''):
    """A real pinned SDK handshake, tools, prompt and authenticated public call."""
    from mcp.client import ClientSession
    from mcp.client.stdio import stdio_client,StdioServerParameters
    from contextlib import AsyncExitStack
    settings=store.read();store.authenticate(token)
    if not settings['enabled']:raise ConfigurationError('Enable MCP before its authenticated Test')
    async with AsyncExitStack() as stack:
        if settings['transport']=='stdio':
            parameters=StdioServerParameters(command=sys.executable,args=[str(Path(__file__).parents[1]/'gxtxt-mcp'),
                '--home',str(store.home),'serve','--transport','stdio'],env=dict(os.environ,GXTXT_MCP_CLIENT_TOKEN=token))
            quiet=stack.enter_context(open(os.devnull,'w'))
            streams=await stack.enter_async_context(stdio_client(parameters,errlog=quiet))
            client=await stack.enter_async_context(ClientSession(*streams,read_timeout_seconds=30))
        else:
            from mcp.client.streamable_http import streamable_http_client
            import httpx2
            http=await stack.enter_async_context(httpx2.AsyncClient(headers={'Authorization':'Bearer '+token},timeout=30))
            streams=await stack.enter_async_context(streamable_http_client(f'http://127.0.0.1:{settings["port"]}/mcp',http_client=http))
            client=await stack.enter_async_context(ClientSession(streams[0],streams[1],read_timeout_seconds=30))
        initialized=await client.initialize()
        if initialized.protocol_version!=PROTOCOL_VERSION:raise ConfigurationError('Server negotiated an untested MCP protocol')
        tools=await client.list_tools();prompts=await client.list_prompts();resources=await client.list_resource_templates()
        if not {'gxtxt_server_info','gxtxt_bridge_call','gxtxt_select_session','gxtxt_search_bridge_apis'}.issubset({v.name for v in tools.tools}):
            raise ConfigurationError('MCP required tool discovery failed')
        if 'gxtxt_scientific_workflow' not in {p.name for p in prompts.prompts}:raise ConfigurationError('MCP scientific-workflow Prompt is missing')
        if 'gxtxt://bridge/catalog/{scope}' not in {str(r.uri_template) for r in resources.resource_templates}:raise ConfigurationError('MCP live catalog Resource is missing')
        info=await client.call_tool('gxtxt_server_info',{})
        if info.is_error:raise test_tool_error(info,'Authenticated server-info call failed')
        result=dict(status='PASS',transport=settings['transport'],protocol_version=initialized.protocol_version,
                    prompt=True,catalog_resource=True,authenticated_server_info=True,live_catalog=False)
        if session:
            selected=await client.call_tool('gxtxt_select_session',{'session':session})
            if selected.is_error:raise test_tool_error(selected,'Test Session is unavailable or unauthorized')
            catalog=await client.call_tool('gxtxt_search_bridge_apis',{'query':'','limit':1})
            if catalog.is_error:raise test_tool_error(catalog,'Original live Script Bridge catalog test failed')
            result['live_catalog']=True
        return result


def reports(store):
    result=[]
    for client in sorted(store.read()['clients']):
        directory=store.home/'reports'/client
        if not directory.exists():continue
        private(directory,directory=True)
        for path in sorted(directory.glob('*.json'))[:128]:
            private(path)
            if path.stat().st_size>1048576:raise ConfigurationError('Staged report exceeds budget')
            report=json.loads(path.read_text())
            result.append({'client_id':client,'report_sha256':path.stem,'api_id':report.get('api_id','unknown'),
                           'operation':report.get('operation','unknown'),'classification':report.get('classification','unknown')})
    return {'reports':result}


def main(argv=None):
    parser=argparse.ArgumentParser(prog='gxtxt-mcp')
    parser.add_argument('--home')
    parser.add_argument('--format',choices=['json','tcl'],default='json')
    commands=parser.add_subparsers(dest='command',required=True)
    init=commands.add_parser('init');init.add_argument('framework');init.add_argument('--python',default='/usr/bin/python3')
    commands.add_parser('info');commands.add_parser('check');commands.add_parser('start');commands.add_parser('stop');commands.add_parser('cleanup')
    testing=commands.add_parser('test');testing.add_argument('--token-stdin',action='store_true');testing.add_argument('--session',default='')
    commands.add_parser('reports')
    reviewfile=commands.add_parser('review-file');reviewfile.add_argument('kind',choices=['request','source','report']);reviewfile.add_argument('path')
    review=commands.add_parser('review-report');review.add_argument('client_id');review.add_argument('report_sha256')
    configure=commands.add_parser('configure');configure.add_argument('--enabled',choices=['true','false']);configure.add_argument('--transport',choices=['stdio','streamable-http']);configure.add_argument('--port',type=int);configure.add_argument('--expected-revision',type=int,required=True)
    add=commands.add_parser('client-add');add.add_argument('client_id')
    grant=commands.add_parser('grant');grant.add_argument('client_id');grant.add_argument('--read',choices=['true','false']);grant.add_argument('--author',choices=['true','false']);grant.add_argument('--run',choices=['true','false']);grant.add_argument('--invoke',choices=['true','false']);grant.add_argument('--session',action='append');grant.add_argument('--clear-sessions',action='store_true')
    revoke=commands.add_parser('revoke');revoke.add_argument('client_id')
    request=commands.add_parser('approve-request');request.add_argument('client_id');request.add_argument('request_file');request.add_argument('--expected-file-sha256')
    source=commands.add_parser('approve-source');source.add_argument('client_id');source.add_argument('identity_file');source.add_argument('--expected-file-sha256')
    report=commands.add_parser('approve-report');report.add_argument('client_id');report.add_argument('report_sha256')
    export=commands.add_parser('export-report');export.add_argument('client_id');export.add_argument('report_sha256');export.add_argument('destination')
    serve=commands.add_parser('serve');serve.add_argument('--transport',choices=['stdio','streamable-http'])
    args=parser.parse_args(argv);store=Store(args.home)
    try:
        if args.command=='init':result=store.initialize(args.framework,args.python)
        elif args.command=='info':result=status(store)
        elif args.command=='check':result=check(store)
        elif args.command=='reports':result=reports(store)
        elif args.command=='review-file':
            path=Path(args.path)
            if path.stat().st_size>1048576:raise ConfigurationError('Review file exceeds1MiB')
            raw=path.read_bytes();record=json.loads(raw)
            result={'kind':args.kind,'file_sha256':hashlib.sha256(raw).hexdigest(),'review_json':json.dumps(record,indent=2,ensure_ascii=False)}
            if args.kind=='source':result['reference']=record.get('reference','')
            if args.kind=='report':result['report_sha256']=hashlib.sha256(json.dumps(record,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        elif args.command=='review-report':
            identifier(args.client_id)
            if len(args.report_sha256)!=64 or any(c not in 'abcdef0123456789' for c in args.report_sha256):raise ConfigurationError('Report digest is invalid')
            path=store.home/'reports'/args.client_id/(args.report_sha256+'.json');private(path)
            if path.stat().st_size>1048576:raise ConfigurationError('Staged report exceeds budget')
            result=json.loads(path.read_text())
        elif args.command=='test':
            check(store)
            token=sys.stdin.readline(257).strip() if args.token_stdin else os.environ.get('GXTXT_MCP_CLIENT_TOKEN','')
            result=asyncio.run(test_connection(store,token,args.session))
        elif args.command=='start':result=start(store)
        elif args.command in {'stop','cleanup'}:result=stop(store)
        elif args.command=='serve':
            from .server import Adapter
            value=store.read()
            if not value['enabled']:raise ConfigurationError('Optional MCP service is disabled')
            check(store)
            transport=args.transport or value['transport']
            token=os.environ.get('GXTXT_MCP_CLIENT_TOKEN') if transport=='stdio' else None
            if transport=='stdio':store.authenticate(token)
            adapter=Adapter(store,token)
            async def run():
                loop=asyncio.get_running_loop()
                task=asyncio.current_task()
                if transport=='stdio':loop.add_signal_handler(signal.SIGTERM,task.cancel)
                try:
                    if transport=='stdio':await adapter.server.run_stdio_async()
                    else:
                        import uvicorn
                        server=uvicorn.Server(uvicorn.Config(adapter.http_app(),host='127.0.0.1',port=value['port'],
                                              log_level='warning',access_log=False,timeout_graceful_shutdown=10))
                        await server.serve()
                finally:await adapter.close()
            service_lock=None
            if transport=='streamable-http':
                service_lock=os.open(store.home/'.service.lock',os.O_WRONLY|os.O_CREAT|os.O_NOFOLLOW,0o600)
                private(store.home/'.service.lock')
                try:fcntl.flock(service_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:raise ConfigurationError('This MCP configuration already has a running service') from None
                state=store.home/'service.json'
                fd=os.open(state,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
                with os.fdopen(fd,'w') as stream:json.dump({'pid':os.getpid(),'process':process_identity(os.getpid()),'transport':transport},stream)
            try:
                try:asyncio.run(run())
                except asyncio.CancelledError:pass
            finally:
                if service_lock is not None:
                    if state.exists() and json.loads(state.read_text()).get('pid')==os.getpid():state.unlink()
                    os.close(service_lock)
            return 0
        else:
            value=store.read();revision=value['revision']
            if args.command=='configure':
                if status(store)['running'] and ((args.transport is not None and args.transport!=value['transport']) or (args.port is not None and args.port!=value['port'])):raise ConfigurationError('Stop MCP before changing its transport or endpoint')
                if args.expected_revision!=revision:raise ConfigurationError('Settings changed; reload before editing')
                if args.enabled=='false':stop(store)
                if args.enabled is not None:value['enabled']=args.enabled=='true'
                if args.transport is not None:value['transport']=args.transport
                if args.port is not None:value['port']=args.port
            else:
                client=identifier(args.client_id)
                if args.command=='client-add':
                    if client in value['clients']:raise ConfigurationError('Client identity already exists')
                    token=secrets.token_urlsafe(48)
                    value['clients'][client]={'token_sha256':hashlib.sha256(token.encode()).hexdigest(),'read':True,
                       'author':False,'run':False,'invoke':False,'sessions':[],'approved_requests':[],
                       'approved_sources':[],'approved_reports':[]}
                elif client not in value['clients']:raise ConfigurationError('Unknown client identity')
                if args.command=='grant':
                    target=value['clients'][client]
                    for field in ('read','author','run','invoke'):
                        if getattr(args,field) is not None:target[field]=getattr(args,field)=='true'
                    if args.session is not None or args.clear_sessions:
                        target['sessions']=[]
                        for name in args.session or []:
                            session=Path(name).resolve(strict=True)
                            if not (session/'metadata/manifest.ini').is_file():raise ConfigurationError('Select an actual canonical Session')
                            target['sessions'].append(str(session))
                elif args.command=='revoke':del value['clients'][client]
                elif args.command=='approve-request':
                    from .bridge import request_digest
                    raw=Path(args.request_file).read_bytes()
                    if len(raw)>1048576:raise ConfigurationError('Request review exceeds1MiB')
                    if args.expected_file_sha256 and hashlib.sha256(raw).hexdigest()!=args.expected_file_sha256:raise ConfigurationError('Request changed after review')
                    request=json.loads(raw)
                    if set(request)!={'api_id','operation','args'}:raise ConfigurationError('Review exactly one typed public API request')
                    digest=request_digest(**request)
                    if digest not in value['clients'][client]['approved_requests']:value['clients'][client]['approved_requests'].append(digest)
                elif args.command=='approve-source':
                    raw=Path(args.identity_file).read_bytes()
                    if len(raw)>1048576:raise ConfigurationError('Source identity review exceeds1MiB')
                    if args.expected_file_sha256 and hashlib.sha256(raw).hexdigest()!=args.expected_file_sha256:raise ConfigurationError('Source identity changed after review')
                    record=json.loads(raw)
                    if set(record)!={'reference','sha256','revision','record_sha256','owner_context'}:
                        raise ConfigurationError('Review the full exact original Registry identity')
                    value['clients'][client]['approved_sources']=[r for r in value['clients'][client]['approved_sources'] if r['reference']!=record['reference']]+[record]
                elif args.command=='approve-report':
                    digest=args.report_sha256
                    if len(digest)!=64 or any(c not in 'abcdef0123456789' for c in digest):raise ConfigurationError('Report digest is invalid')
                    if digest not in value['clients'][client]['approved_reports']:value['clients'][client]['approved_reports'].append(digest)
                elif args.command=='export-report':
                    digest=args.report_sha256
                    if digest not in value['clients'][client]['approved_reports']:raise ConfigurationError('Exact report has not been locally approved')
                    source=store.home/'reports'/client/(digest+'.json');private(source)
                    data=source.read_bytes()
                    if hashlib.sha256(json.dumps(json.loads(data),sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()!=digest:
                        raise ConfigurationError('Local report identity changed')
                    destination=Path(args.destination)
                    fd=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                    with os.fdopen(fd,'wb') as stream:stream.write(data)
                    result={'status':'exported_by_explicit_local_action','report_sha256':digest}
                    emit(result,args.format);return 0
            store.write(value,revision)
            result=store.public()
            if args.command=='client-add':result={'client_id':client,'token':token,'display_once':True,'grants':'Read only, no Sessions, no direct invocation, Author or Run'}
        emit(result,args.format);return 0
    except Exception as error:
        # Source/Session contents and credentials never belong in CLI errors.
        emit(diagnostic_error(error),args.format,error=True);return 1
