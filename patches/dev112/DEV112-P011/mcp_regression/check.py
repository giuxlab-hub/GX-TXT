"""Real client transport/lifecycle tests using disposable original Sessions."""
from contextlib import AsyncExitStack
import asyncio
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tkinter

root,output=map(lambda v:Path(v).resolve(),sys.argv[1:3])
output.mkdir(mode=0o700)
for key,name in {'XDG_CONFIG_HOME':'config','XDG_CACHE_HOME':'cache','XDG_DATA_HOME':'data','XDG_STATE_HOME':'state',
    'TMPDIR':'tmp','GXTXT_JOB_ROOT':'jobs','GXTXT_RESOURCE_ROOT':'resources','GXTXT_RESOURCE_STORAGE':'storage','GXTXT_INSTALLATION_ROOT':'installation'}.items():
    path=output/name;path.mkdir(mode=0o700);os.environ[key]=str(path)
os.environ['PYTHONDONTWRITEBYTECODE']='1'
adapter_source=Path(__file__).resolve().parents[2]/'integrations/mcp'
sys.path.insert(0,str(adapter_source))
sys.path.insert(0,str(root/'core/python'))
from gxtxt_mcp.config import Store,ConfigurationError
from gxtxt_mcp.server import Boundary
from gxtxt_mcp.cli import cleanup_contexts
from mcp.client import ClientSession
from mcp.client.stdio import stdio_client,StdioServerParameters
from mcp.client.streamable_http import streamable_http_client
import httpx2
import gxtxt_script_bridge_server as codec

# Reuse the same original public Session/Configuration owners as MAIN's fixture.
t=tkinter.Tcl();t.call('set','argv0','__p011_mcp_transport__');t.call('source',str(root/'gxtxt_pipeline.tcl'))
def text(value):return str(t.call('format','%s',value))
fields={'storage.session_root':'sessions','scripts.user_root':'scripts','storage.cache_dir':'product_cache',
        'storage.temp_dir':'product_tmp','diagnostics.stderr_log_directory':'diagnostics'}
for key,name in fields.items():
    path=output/name;path.mkdir(mode=0o700)
    t.call('::GX::configurationRegister',key,('group','MCP test','label',key,'type','path','scope','user','default',str(path)))
    t.call('::GX::configurationSet',key,str(path))
t.call('::GX::configurationSave',tuple(fields),0);t.call('::GX::defaults');t.call('::GX::configurationSave',tuple(fields),1)
t.call('::GX::loadModuleCatalog')
sessions=[text(t.call('::GX::createNewSession','MCP_transport_'+v,'',0)) for v in ('A','B')]
home=output/'mcp';store=Store(home)
launcher=Path(sys.argv[3]).resolve() if len(sys.argv)>3 else adapter_source/'gxtxt-mcp'
launch=[str(launcher)] if len(sys.argv)>3 else [sys.executable,'-B',str(launcher)]
records=[]
def record(name,**data):
    records.append(dict(case=name,**data))
    (output/'PROGRESS.json').write_text(json.dumps(records,indent=2))
def cli(*args,input=None,ok=True):
    done=subprocess.run([*launch,'--home',str(home),*args],input=input,capture_output=True,text=True,timeout=100)
    if ok:assert done.returncode==0,(args,done.stdout,done.stderr)
    else:assert done.returncode!=0,(args,done.stdout)
    return json.loads(done.stdout if done.returncode==0 else done.stderr)
def value(result):
    assert not result.is_error,result
    return result.structured_content if result.structured_content is not None else json.loads(result.content[0].text)
def configure(**changes):
    args=['configure','--expected-revision',str(store.read()['revision'])]
    for k,v in changes.items():args.extend(['--'+k,str(v).lower() if isinstance(v,bool) else str(v)])
    return cli(*args)

cli('init',str(root));assert not store.read()['enabled'] and not store.read()['clients']
record('default_off_no_clients')
cli('start',ok=False)
tokens={client:cli('client-add',client)['token'] for client in ('alpha','beta')}
for client,session in zip(tokens,sessions):cli('grant',client,'--session',session,'--invoke','true')
assert 'token' not in json.dumps(cli('info'))
configure(enabled=True)
compat=cli('check');assert compat['compatibility_basis']=='public_contracts_not_framework_release';assert compat['runtime_verified'] is False;record('capability_declarations',result=compat)
result=cli('test','--token-stdin','--session',sessions[0],input=tokens['alpha']+'\n')
assert result['live_catalog'];record('real_stdio_test',result=result)
cli('test','--token-stdin',input='wrong-token-that-is-long-enough-to-be-a-credential\n',ok=False)

with socket.socket() as listener:
    listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
configure(transport='streamable-http',port=port)
started=cli('start');assert started['running'];record('headless_start',state=started['state'])
configure(transport='stdio',ok=False) if False else None
cli('configure','--expected-revision',str(store.read()['revision']),'--port',str(port+1),ok=False)
result=cli('test','--token-stdin','--session',sessions[0],input=tokens['alpha']+'\n')
assert result['live_catalog'];record('real_http_test',result=result)

async def run():
    url=f'http://127.0.0.1:{port}/mcp'
    async with AsyncExitStack() as stack:
        raw=await stack.enter_async_context(httpx2.AsyncClient(timeout=30))
        headers={'Authorization':'Bearer '+tokens['alpha']}
        async def refusal(name,expected,method='POST',**options):
            response=await raw.request(method,url,**options)
            assert response.status_code==expected,(name,response.status_code,response.text)
            record(name,status=response.status_code)
        await refusal('unauthenticated',401,json={})
        await refusal('wrong_host',403,headers=dict(headers,Host='evil.invalid'),json={})
        await refusal('wrong_origin',403,headers=dict(headers,Origin='https://evil.invalid'),json={})
        await refusal('bad_protocol',400,headers=dict(headers,**{'mcp-protocol-version':'2099-01-01'}),json={})
        offered=await raw.post(url,headers=dict(headers,**{'Content-Type':'application/json','Accept':'application/json, text/event-stream'}),json={'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2099-01-01','capabilities':{},'clientInfo':{'name':'counteroffer','version':'1'}}})
        assert offered.status_code==200,offered.text
        assert offered.json()['result']['protocolVersion']=='2025-11-25',offered.text
        counter=offered.headers['mcp-session-id']
        await raw.delete(url,headers=dict(headers,**{'mcp-session-id':counter,'mcp-protocol-version':'2025-11-25'}))
        record('standard_initialize_supported_counteroffer')
        await refusal('method_put',405,method='PUT',headers=headers)
        await refusal('oversize_declared',413,headers=headers,content=b'x'*(store.read()['limits']['request_bytes']+1))
        async def chunks():
            for _ in range(18):yield b'x'*65536
        await refusal('oversize_chunked',413,headers=headers,content=chunks())
        await refusal('malformed_json',400,headers=dict(headers,**{'Content-Type':'application/json','Accept':'application/json, text/event-stream'}),content=b'{')
        duplicate=[('Authorization','Bearer '+tokens['alpha']),('Authorization','Bearer '+tokens['alpha'])]
        await refusal('duplicate_auth_header',400,headers=duplicate,json={})
        connections=[]
        for client in ('alpha','beta','alpha'):
            session_id=['']
            async def capture(response,box=session_id):
                if response.headers.get('mcp-session-id'):box[0]=response.headers['mcp-session-id']
            http=await stack.enter_async_context(httpx2.AsyncClient(headers={'Authorization':'Bearer '+tokens[client]},timeout=60,event_hooks={'response':[capture]}))
            streams=await stack.enter_async_context(streamable_http_client(url,http_client=http))
            session=await stack.enter_async_context(ClientSession(streams[0],streams[1],read_timeout_seconds=60))
            initialized=await session.initialize();assert initialized.protocol_version=='2025-11-25'
            connections.append((session,session_id))
        a,b,a2=[row[0] for row in connections]
        assert connections[0][1][0] and connections[0][1][0]!=connections[2][1][0]
        selected=value(await a.call_tool('gxtxt_select_session',{'session':sessions[0]}));assert selected['compatibility']['runtime_verified'];record('actual_authorized_direct_contract',receipt=selected['compatibility'])
        value(await b.call_tool('gxtxt_select_session',{'session':sessions[1]}))
        assert (await b.call_tool('gxtxt_select_session',{'session':sessions[0]})).is_error
        assert (await a2.call_tool('gxtxt_search_bridge_apis',{'query':''})).is_error
        record('independent_clients_and_same_client_connections')
        await refusal('foreign_mcp_session',403,headers=dict(headers,**{'mcp-session-id':connections[1][1][0],'mcp-protocol-version':'2025-11-25'}),json={})
        await refusal('missing_session_protocol',400,headers=dict(headers,**{'mcp-session-id':connections[0][1][0]}),json={})
        results=await asyncio.gather(a.call_tool('gxtxt_search_bridge_apis',{'query':'numeric','limit':2}),
                                     b.call_tool('gxtxt_search_bridge_apis',{'query':'script','limit':2}))
        for row in results:value(row)
        record('concurrent_live_catalogs')
        active=set((home/'contexts').glob('*'));assert len(active)>=2
        orphan=home/'contexts/context-abandoned-fixture';orphan.mkdir(mode=0o700)
        lease=orphan/'.lease';lease.write_bytes(b'');lease.chmod(0o600)
        (orphan/'transport-marker').write_text('private transport only')
        assert cleanup_contexts(store)==1 and not orphan.exists()
        assert all(p.exists() for p in active)
        record('free_lease_cleanup_preserves_live_contexts')
        cli('grant','alpha','--clear-sessions')
        assert (await a.call_tool('gxtxt_search_bridge_apis',{'query':''})).is_error
        cli('grant','alpha','--session',sessions[0])
        cli('revoke','beta')
        await refusal('revoked_credential',401,headers={'Authorization':'Bearer '+tokens['beta']},json={})
        record('live_session_and_client_revocation')
        # Test configured concurrency deterministically at the actual ASGI
        # boundary, without submitting any scientific computation.
        entered=asyncio.Event();release=asyncio.Event();messages=[]
        async def blocked(scope,receive,send):
            entered.set();await release.wait()
            await send({'type':'http.response.start','status':200,'headers':[]})
            await send({'type':'http.response.body','body':b'{}'})
        boundary=Boundary(blocked,store,{})
        scope={'type':'http','method':'POST','path':'/mcp','headers':[(b'host',f'127.0.0.1:{port}'.encode()),(b'authorization',('Bearer '+tokens['alpha']).encode())]}
        async def receive():return {'type':'http.request','body':b'{}','more_body':False}
        async def send(v):messages.append(v)
        tasks=[asyncio.create_task(boundary(scope,receive,send)) for _ in range(store.read()['limits']['concurrency'])]
        await entered.wait();await asyncio.sleep(0)
        await boundary(scope,receive,send)
        assert any(v.get('status')==429 for v in messages)
        release.set();await asyncio.gather(*tasks);record('bounded_concurrency_429')

try:
    asyncio.run(run())
    with store.transaction():cli('client-add','locked_writer',ok=False)
    record('configuration_lock_rejects_concurrent_writer')
    old=store.read()['revision'];cli('configure','--expected-revision',str(old-1),'--enabled','false',ok=False)
    assert cli('info')['running'];record('stale_configuration_refused')
    pid=cli('info')['pid'];os.kill(pid,signal.SIGKILL)
    import time
    for _ in range(100):
        if not cli('info')['running']:break
        time.sleep(.05)
    else:raise AssertionError('Crash not detected')
    assert cli('start')['running'];record('crash_detected_restart')
    assert not cli('stop')['running']
    configure(enabled=False);record('normal_stop_default_off_persistence')
    # No credential may reach ordinary logs, Session/source state or reports.
    for path in list((output/'sessions').rglob('*'))+list(home.rglob('*.log')):
        if path.is_file():
            content=path.read_bytes()
            assert all(token.encode() not in content for token in tokens.values()),path
    assert not list((output/'scripts').glob('*'))
    assert not list((home/'contexts').glob('*'))
    record('no_secret_leak_no_generated_source_context_cleanup')
    (output/'RESULT.json').write_text(json.dumps(dict(status='PASS',cases=len(records),records=records,
        launcher=str(launcher),framework=str(root),sessions=sessions),indent=2)+'\n')
    print(json.dumps(dict(status='PASS',cases=len(records))))
finally:
    try:cli('stop')
    except Exception:pass
