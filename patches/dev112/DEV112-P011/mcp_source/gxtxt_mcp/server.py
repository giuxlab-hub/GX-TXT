"""MCP protocol, client isolation and diagnostics; GX-TXT owns every API call."""
from __future__ import annotations
import asyncio
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import time
import tempfile

from mcp.server import MCPServer
from mcp.server.mcpserver import Context
from mcp.server.transport_security import TransportSecuritySettings
from mcp_types.version import HANDSHAKE_PROTOCOL_VERSIONS

from . import __version__, SDK_VERSION, PROTOCOL_VERSION
from .bridge import BridgeContext, BridgeFailure
from .config import Store, ConfigurationError, framework_info
from .compatibility import declarations

GUIDANCE=('Discover the currently available GX-TXT Script Bridge APIs and prefer compatible public scientific operations '
          'before writing equivalent numerical algorithms or using external scientific libraries. Inspect exact arguments, '
          'results, units, constraints and active Session. Use gxtxt_bridge_call for one-off calls without generating a Script. '
          'Use original registered supervised Python/Octave Script Projects for reusable programs. If an API is absent, '
          'host-only or incompatible, record the reason and use a suitable fallback. Never access private files, databases '
          'or undocumented dispatchers. Prepare a reviewable local diagnostic for an actual API/transport gap. '
          'This prompt is guidance, not an authorization grant; clients may require explicit prompt selection.')
CLASSIFICATIONS={'MISSING_SAFE_BINDING','KNOWN_HOST_ONLY','TRANSPORT_TYPE_SHAPE','DESCRIPTOR_DRIFT',
                 'CALL_RUNTIME_FAILURE','INSUFFICIENT_EVIDENCE'}


class Adapter:
    def __init__(self,store=None,stdio_token=None):
        self.store=store or Store();self.settings=self.store.read();self.stdio_token=stdio_token
        self.contexts={};self.sessions={};self.pending_reports={}
        self.selection_lock=asyncio.Lock()
        self.capacity=asyncio.Semaphore(self.settings['limits']['concurrency'])
        self.compatibility=declarations(self.settings)
        self.server=MCPServer('GX-TXT',version=__version__,instructions=GUIDANCE,log_level='WARNING')
        self._register()

    def identity(self,ctx):
        if ctx.protocol_version not in HANDSHAKE_PROTOCOL_VERSIONS:
            raise BridgeFailure('GXTXT:MCP:ProtocolDenied','This adapter requires an SDK-supported MCP handshake protocol: '+', '.join(HANDSHAKE_PROTOCOL_VERSIONS))
        request=ctx.request_context.request
        if request is None:
            token=self.stdio_token
            connection='stdio'
        else:
            value=request.headers.get('authorization','')
            token=value[7:] if value.startswith('Bearer ') else ''
            connection=request.headers.get('mcp-session-id','')
            if not connection:raise ConfigurationError('MCP connection identity is missing')
        try:client,settings,grant=self.store.authenticate(token)
        except ConfigurationError as error:
            raise BridgeFailure('GXTXT:MCP:AuthenticationDenied',str(error)) from None
        if not settings['enabled']:raise BridgeFailure('GXTXT:MCP:Disabled','MCP service is disabled')
        if settings['framework_root']!=self.settings['framework_root']:
            raise BridgeFailure('GXTXT:MCP:RestartRequired','Restart MCP after selecting another GX-TXT installation')
        return (client,connection),settings,grant

    def current(self,ctx):
        key,settings,grant=self.identity(ctx)
        if key not in self.contexts:raise BridgeFailure('GXTXT:MCP:NoSession','Select an authorized Session for this connection first')
        context=self.contexts[key]
        if context.session not in {str(Path(value).resolve()) for value in grant['sessions']}:
            raise BridgeFailure('GXTXT:MCP:SessionDenied','Selected Session grant has been revoked')
        return key,context,settings,grant

    async def catalog(self,ctx):
        _,context,_,grant=self.current(ctx)
        return await context.metadata('list',grant)

    async def describe(self,ctx,api_id):
        _,context,_,grant=self.current(ctx)
        return await context.metadata('describe',grant,api_id=api_id)

    def _register(self):
        server=self.server

        @server.tool(description='Read actual adapter/framework identity and capability status. '+GUIDANCE)
        async def gxtxt_server_info(ctx:Context)->dict:
            key,settings,grant=self.identity(ctx)
            info=framework_info(settings['framework_root'])
            info['compatibility']=self.compatibility
            if key in self.contexts:
                info['runtime_compatibility']=self.contexts[key].compatibility_receipt
            info.update(component_version=__version__,sdk_version=SDK_VERSION,protocol_version=PROTOCOL_VERSION,
                        enabled=settings['enabled'],client_id=key[0],session_selected=key in self.contexts,
                        grants={name:grant[name] for name in ('read','author','run','invoke')},
                        prompt='gxtxt_scientific_workflow',catalog='gxtxt://bridge/catalog/current',
                        source_approval_count=len(grant['approved_sources']),issue_reports='local_review_only')
            return info

        @server.tool(description='Bind an owner-authorized Session to this authenticated MCP connection only; desktop Current Session is unchanged.')
        async def gxtxt_select_session(session:str,ctx:Context)->dict:
            key,settings,grant=self.identity(ctx)
            try:selected=str(Path(session).resolve(strict=True))
            except (OSError,ValueError):raise BridgeFailure('GXTXT:MCP:SessionUnavailable','Select an existing authorized canonical Session') from None
            if selected not in {str(Path(value).resolve()) for value in grant['sessions']}:
                raise BridgeFailure('GXTXT:MCP:SessionDenied','Session is not in this client explicit grants')
            async with self.selection_lock:
                # A queued selection must use current grants. Preserve an
                # existing valid context until its replacement is admitted.
                key,settings,grant=self.identity(ctx)
                if selected not in {str(Path(value).resolve()) for value in grant['sessions']}:
                    raise BridgeFailure('GXTXT:MCP:SessionDenied','Session grant was revoked before selection')
                if not (Path(selected)/'metadata/manifest.ini').is_file():
                    raise BridgeFailure('GXTXT:MCP:SessionUnavailable','Selected Session is no longer available')
                previous=self.contexts.get(key)
                if (previous is not None and previous.session==selected and not previous.tainted and
                    previous.settings['framework_root']==settings['framework_root'] and
                    (previous.process is None or previous.process.returncode is None) and
                    (previous.response_capacity is None or settings['limits']['response_bytes']<=previous.response_capacity)):
                    return {'status':'selected','context_id':previous.context_id,'desktop_session_changed':False}
                if previous is None and len(self.contexts)>=128:
                    raise BridgeFailure('GXTXT:MCP:ContextBudget','Adapter context budget reached')
                context=BridgeContext(self.store,settings,key[0],selected)
                try:
                    context.authorize(grant)
                    await context._start()
                    if previous is not None:
                        await previous.close()
                except BaseException:
                    await context.close()
                    raise
                self.contexts[key]=context
                return {'status':'selected','context_id':context.context_id,'desktop_session_changed':False,
                        'compatibility':context.compatibility_receipt}

        @server.tool(description='Forward exact api_id/operation/typed args to ANY actually exported original Script Bridge API. No generated Script, copied scientific dispatcher or API subset. Explicit general invocation grant applies; original owners enforce their contracts and source Author/Run approvals. '+GUIDANCE)
        async def gxtxt_bridge_call(api_id:str,operation:str,args:list[dict],ctx:Context,approved_reference:str='')->dict:
            _,context,_,grant=self.current(ctx)
            if not grant['invoke']:raise BridgeFailure('GXTXT:MCP:InvocationDenied','General direct invocation requires an explicit local grant')
            if not api_id or not operation or len(api_id)>128 or len(operation)>128 or len(args)>256:
                raise BridgeFailure('GXTXT:MCP:InvalidArguments','Bounded exact API/operation/typed argument identities are required')
            async with self.capacity:
                response=await context.request({'action':'call','api_id':api_id,'operation':operation,'args':args},grant,approved_reference)
            return {'bridge_response':response,'transport_context':context.context_id}

        @server.tool(description='Search the original currently available Bridge catalog with bounded pagination; static declarations never imply runtime callability. '+GUIDANCE)
        async def gxtxt_search_bridge_apis(query:str,ctx:Context,offset:int=0,limit:int=20)->dict:
            if len(query)>256 or not 0<=offset<=10000 or not 1<=limit<=100:
                raise BridgeFailure('GXTXT:MCP:InvalidArguments','Search bounds are invalid')
            rows=[]
            for row in await self.catalog(ctx):
                if not query or query.casefold() in json.dumps(row,ensure_ascii=False).casefold():rows.append(row)
                else:
                    descriptor=await self.describe(ctx,row['api_id'])
                    if query.casefold() in json.dumps(descriptor,ensure_ascii=False).casefold():rows.append(row)
            return {'source':'original_live_script_bridge','total':len(rows),'offset':offset,'entries':rows[offset:offset+limit]}

        @server.tool(description='Describe exact original live API arguments/results/provider availability; unknown attributes remain unknown. '+GUIDANCE)
        async def gxtxt_describe_bridge_api(api_id:str,ctx:Context,operation:str='')->dict:
            descriptor=await self.describe(ctx,api_id)
            if operation:
                if operation not in descriptor['operations']:
                    raise BridgeFailure('GXTXT:ScriptBridge:UnknownOperation','Exact operation is not registered by the original Bridge')
                descriptor=dict(descriptor,operations={operation:descriptor['operations'][operation]})
            return descriptor

        @server.resource('gxtxt://bridge/catalog/{scope}',mime_type='application/json',description='Use scope=current for the bounded actual available API catalog in this connection; no copied catalog database.')
        async def catalog_resource(scope:str,ctx:Context)->str:
            if scope!='current':raise BridgeFailure('GXTXT:MCP:InvalidArguments','Catalog scope is this authenticated current connection')
            return json.dumps({'source':'original_live_script_bridge','entries':await self.catalog(ctx)},ensure_ascii=False)

        @server.resource('gxtxt://scientific-workflow',mime_type='text/plain',description='Public API-first guidance; this resource grants no execution rights.')
        def workflow_resource()->str:return GUIDANCE

        @server.resource('gxtxt://bridge/api/{api_id}',mime_type='application/json',description='Exact installed public operation descriptor from original Script Bridge discovery.')
        async def api_resource(api_id:str,ctx:Context)->str:
            return json.dumps(await self.describe(ctx,api_id),ensure_ascii=False)

        @server.resource('gxtxt://bridge/buffer/{resource_id}/{offset}/{count}',mime_type='application/json',description='Bounded opaque bytes from an original Bridge descriptor belonging to this exact client context.')
        async def buffer_resource(resource_id:str,offset:int,count:int,ctx:Context)->str:
            _,context,_,_=self.current(ctx)
            descriptor=context.descriptors.get(resource_id)
            if descriptor is None or not 0<=offset<=descriptor['byte_count'] or not 1<=count<=262144:
                raise BridgeFailure('GXTXT:MCP:BufferDenied','Buffer is unknown, foreign, released or outside the bounded byte range')
            owner=__import__('gxtxt_scientific_binary_v1')
            fd,_,_=owner.open_buffer(context.buffer,descriptor)
            try:data=os.pread(fd,min(count,descriptor['byte_count']-offset),offset)
            finally:os.close(fd)
            return json.dumps({'descriptor':descriptor,'offset':offset,'byte_count':len(data),'bytes_base64':base64.b64encode(data).decode(),
                               'eof':offset+len(data)==descriptor['byte_count']})

        @server.prompt(name='gxtxt_scientific_workflow',description='Discover and prefer existing scientific public APIs; use exact original contracts, Session ownership and approved source execution.')
        def scientific_prompt()->str:return GUIDANCE

        @server.tool(description='Prepare a local reviewable provisional API diagnostic with default redaction. Arguments, paths, Dataset names/values, private source and raw logs are never accepted or copied. No automatic publication. Persistence needs a separate local approval.')
        async def gxtxt_report_api_issue(api_id:str,operation:str,classification:str,observed_state:str,ctx:Context,error_id:str='')->dict:
            key,settings,_=self.identity(ctx)
            if classification not in CLASSIFICATIONS or observed_state not in {'unavailable','host_only','rejected','type_shape_failure','descriptor_mismatch','runtime_failure','unknown'}:
                raise BridgeFailure('GXTXT:MCP:InvalidArguments','Use a documented provisional classification and observed state')
            for value in (api_id,operation,error_id):
                if len(value)>128 or not re.fullmatch(r'[A-Za-z0-9_:.-]*',value):
                    raise BridgeFailure('GXTXT:MCP:InvalidArguments','Only public identities and stable error identifiers belong in a default-redacted report')
            try:
                descriptor=await self.describe(ctx,api_id)
                descriptor_revision='sha256:'+hashlib.sha256(json.dumps(descriptor,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
            except BridgeFailure:
                descriptor={'api_id':api_id,'availability':'unavailable_or_not_yet_admitted','provider':'unknown'}
                descriptor_revision='unknown'
            expected=descriptor.get('operations',{}).get(operation,'unknown')
            operation_revision='unknown' if expected=='unknown' else 'sha256:'+hashlib.sha256(json.dumps(expected,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
            report={'schema':'gxtxt.mcp.api_issue.v1','framework':framework_info(settings['framework_root']),
                    'api_id':api_id,'operation':operation,'provider':descriptor.get('provider_id','unknown'),
                    'api_version':descriptor.get('api_version','unknown'),'provider_version':descriptor.get('provider_version','unknown'),
                    'descriptor_revision':descriptor_revision,'operation_revision':operation_revision,
                    'client_type':'MCP','classification':classification,'provisional':True,'observed_state':observed_state,
                    'error_id':error_id,'exposed_state':'registered' if operation in descriptor.get('operations',{}) else 'unavailable',
                    'expected_contract':expected,
                    'reproduction':'Discover the exact public API and operation in an authorized disposable Session; use independently reviewed synthetic arguments. Original arguments and logs are omitted.',
                    'redaction':{'private_paths':True,'credentials':True,'hostnames':True,'source':True,'session_contents':True,'dataset_names_and_values':True},
                    'scientific_algorithm_fault_claim':False,'remote_publication':False}
            encoded=json.dumps(report,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
            digest=hashlib.sha256(encoded).hexdigest()
            if (key,digest) not in self.pending_reports and len(self.pending_reports)>=128:
                raise BridgeFailure('GXTXT:MCP:ReportBudget','Review or release staged reports before preparing more')
            self.pending_reports[(key,digest)]=report
            return {'report_sha256':digest,'report':report,'persisted':False,'local_approval_required':True}

        @server.tool(description='Persist only an exact already previewed, redacted report after separate local CLI approval of its digest. Never publishes or exports automatically.')
        async def gxtxt_persist_api_issue(report_sha256:str,ctx:Context)->dict:
            key,_,grant=self.identity(ctx)
            report=self.pending_reports.get((key,report_sha256))
            if report is None or report_sha256 not in grant['approved_reports']:
                raise BridgeFailure('GXTXT:MCP:ReportApprovalRequired','This exact report needs separate local approval')
            client=self.store.home/'reports'/key[0]
            if not client.exists():client.mkdir(mode=0o700)
            path=client/(report_sha256+'.json')
            fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'w') as stream:json.dump(report,stream,indent=2);stream.write('\n')
            return {'status':'persisted_locally','report_sha256':report_sha256,'remote_publication':False}

    async def close(self):
        for context in list(self.contexts.values()):await context.close()
        self.contexts.clear();self.pending_reports.clear()

    def http_app(self):
        settings=self.store.read()
        app=self.server.streamable_http_app(json_response=True,max_request_body_size=settings['limits']['request_bytes'],
            max_sessions=128,session_idle_timeout=1800,
            transport_security=TransportSecuritySettings(allowed_hosts=[f'127.0.0.1:{settings["port"]}'],
                allowed_origins=[f'http://127.0.0.1:{settings["port"]}']))
        return Boundary(app,self.store,self.sessions,self)


class Boundary:
    """Authenticated, bounded local HTTP; original owners keep API policy."""
    def __init__(self,app,store,sessions,adapter=None):
        self.app=app;self.store=store;self.sessions=sessions;self.adapter=adapter
        self.active=0;self.activity={};self.inflight={}
        self.error_count=0;self.last_error={};self.health_written=0

    async def __call__(self,scope,receive,send):
        if scope['type']=='lifespan':
            cleanup=asyncio.create_task(self.cleanup())
            try:return await self.app(scope,receive,send)
            finally:
                cleanup.cancel()
                try:await cleanup
                except asyncio.CancelledError:pass
        if scope['type']!='http':return await self.app(scope,receive,send)
        async def refuse(status):
            self.error_count+=1;self.last_error={'http_status':status,'time_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
            self.health()
            await send({'type':'http.response.start','status':status,
                        'headers':[(b'content-type',b'application/json'),(b'cache-control',b'no-store')]})
            await send({'type':'http.response.body','body':b'{"error":"MCP boundary refused this request"}'})
        status=None;headers={};session=None
        try:
            for key,value in scope.get('headers',[]):
                key=key.decode('ascii').lower();value=value.decode('latin-1')
                if key in headers and key in {'authorization','host','origin','mcp-session-id','mcp-protocol-version','content-length'}:
                    status=400
                headers[key]=value
            token=headers.get('authorization','')
            client,settings,_=self.store.authenticate(token[7:] if token.startswith('Bearer ') else '')
            if not settings['enabled']:status=503
            elif scope.get('path')!='/mcp':status=404
            elif scope['method'] not in {'GET','POST','DELETE'}:status=405
            elif headers.get('host')!=f'127.0.0.1:{settings["port"]}':status=403
            elif 'origin' in headers and headers['origin']!=f'http://127.0.0.1:{settings["port"]}':status=403
            elif 'mcp-protocol-version' in headers and headers['mcp-protocol-version'] not in HANDSHAKE_PROTOCOL_VERSIONS:status=400
            elif int(headers.get('content-length','0'))<0:status=400
            elif int(headers.get('content-length','0'))>settings['limits']['request_bytes']:status=413
            session=headers.get('mcp-session-id')
            if session and self.sessions.get(session)!=client:status=403
            if session and 'mcp-protocol-version' not in headers:status=400
        except ConfigurationError:status=401
        except (ValueError,UnicodeError):status=400
        if status is not None:return await refuse(status)
        counted=scope['method']=='POST'
        if counted and self.active>=settings['limits']['concurrency']:return await refuse(429)
        if counted:self.active+=1
        if session:
            self.activity[session]=time.monotonic()
            self.inflight[session]=self.inflight.get(session,0)+1
        try:
            # Buffer only the configured bounded control message. SDK schema and
            # JSON-RPC validation still run unchanged after this boundary.
            body=bytearray()
            if scope['method']=='POST':
                try:
                    async with asyncio.timeout(min(30,settings['limits']['timeout_seconds'])):
                        while True:
                            message=await receive()
                            if message['type']=='http.disconnect':return
                            body.extend(message.get('body',b''))
                            if len(body)>settings['limits']['request_bytes']:return await refuse(413)
                            if not message.get('more_body',False):break
                except TimeoutError:return await refuse(408)
                # The standard SDK validates JSON-RPC and negotiates initialize
                # protocolVersion, including its supported counteroffer. HTTP
                # header validation above remains a separate transport guard.
            consumed=False;response_status=0
            async def bounded_receive():
                nonlocal consumed
                if not consumed and scope['method']=='POST':
                    consumed=True
                    return {'type':'http.request','body':bytes(body),'more_body':False}
                return await receive()
            async def response(message):
                nonlocal response_status
                if message['type']=='http.response.start':
                    response_status=message['status']
                    for key,value in message.get('headers',[]):
                        if key.lower()==b'mcp-session-id':
                            self.sessions[value.decode()]=client
                            self.activity[value.decode()]=time.monotonic()
                await send(message)
            await self.app(scope,bounded_receive,response)
            if session and scope['method']=='DELETE' and 200<=response_status<300:
                self.sessions.pop(session,None)
                if self.adapter is not None:
                    context=self.adapter.contexts.get((client,session))
                    if context is not None:
                        await context.close()
                        self.adapter.contexts.pop((client,session),None)
                    for key in list(self.adapter.pending_reports):
                        if key[0]==(client,session):self.adapter.pending_reports.pop(key,None)
        finally:
            if counted:self.active-=1
            if session:
                self.inflight[session]=max(0,self.inflight.get(session,1)-1)
                if session in self.sessions:self.activity[session]=time.monotonic()
            self.health()

    def health(self):
        # Bounded, rate-limited status only: no credentials, remote headers,
        # request bodies, paths, source or Session information is recorded.
        if time.monotonic()-self.health_written<1:return
        self.health_written=time.monotonic()
        value={'schema':'gxtxt.mcp.health.v1','boundary_refusals':self.error_count,
               'last_boundary_error':self.last_error,'active_connections':len(self.sessions),
               'active_control_requests':self.active}
        descriptor,name=tempfile.mkstemp(prefix='.health-',dir=self.store.home)
        try:
            os.fchmod(descriptor,0o600)
            with os.fdopen(descriptor,'w') as stream:json.dump(value,stream)
            os.replace(name,self.store.home/'health.json')
        finally:
            if os.path.exists(name):os.unlink(name)

    async def cleanup(self):
        while True:
            await asyncio.sleep(60)
            try:clients=self.store.read()['clients']
            except (OSError,ConfigurationError):clients={}
            for session,client in list(self.sessions.items()):
                if self.inflight.get(session,0):continue
                if client not in clients or not clients[client]['read'] or time.monotonic()-self.activity.get(session,0)>1800:
                    self.sessions.pop(session,None);self.activity.pop(session,None);self.inflight.pop(session,None)
                    if self.adapter is not None:
                        context=self.adapter.contexts.get((client,session))
                        if context is not None:
                            await context.close()
                            self.adapter.contexts.pop((client,session),None)
                        for key in list(self.adapter.pending_reports):
                            if key[0]==(client,session):self.adapter.pending_reports.pop(key,None)
