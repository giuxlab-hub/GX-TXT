"""Authenticated-context transport into the original installed Script Bridge."""
from __future__ import annotations
import asyncio
import configparser
import fcntl
import hashlib
import importlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import uuid

from .config import ConfigurationError, private
from .compatibility import runtime
from mcp.server.mcpserver.exceptions import ToolError


class BridgeFailure(ToolError):
    def __init__(self,identifier,message):
        super().__init__(identifier+': '+message)
        self.identifier=identifier


def request_digest(api_id,operation,args):
    payload={'api_id':api_id,'operation':operation,'args':args}
    return hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()


def installed_codec(root):
    """Import the selected installation's exact codec, never a copied codec."""
    directory=str(Path(root)/'core/python')
    if directory not in sys.path:sys.path.insert(0,directory)
    module=importlib.import_module('gxtxt_script_bridge_server')
    if Path(module.ROOT).resolve()!=Path(root).resolve():
        raise ConfigurationError('Restart the MCP adapter after changing its selected installation')
    return module


class BridgeContext:
    def __init__(self,store,settings,client_id,session):
        self.store=store;self.settings=settings;self.client_id=client_id;self.session=str(Path(session).resolve(strict=True))
        self.context_id=uuid.uuid4().hex
        self.directory=Path(tempfile.mkdtemp(prefix='context-',dir=store.home/'contexts'))
        self.directory.chmod(0o700)
        self.lease=os.open(self.directory/'.lease',os.O_RDWR|os.O_CREAT|os.O_EXCL,0o600)
        fcntl.flock(self.lease,fcntl.LOCK_EX|fcntl.LOCK_NB)
        self.buffer=self.directory/'buffers';self.buffer.mkdir(mode=0o700)
        self.runtime=self.directory/'runtime.ini';self.process=None;self.lock=asyncio.Lock()
        self.descriptors={};self.codec=installed_codec(settings['framework_root'])
        self.log=None
        self.tainted=False
        self.response_capacity=None
        self.compatibility_receipt=None

    def authorize(self,grant,digest='',approved_reference=''):
        if self.session not in {str(Path(value).resolve()) for value in grant['sessions']}:
            raise BridgeFailure('GXTXT:MCP:SessionDenied','Selected Session is not authorized for this client')
        if not (Path(self.session)/'metadata/manifest.ini').is_file():
            raise BridgeFailure('GXTXT:MCP:SessionUnavailable','Selected Session is no longer available')
        context={'schema':'gxtxt.direct_bridge_context.v1','client_id':self.client_id,'context_id':self.context_id,
                 'author':str(grant['author']).lower(),'run':str(grant['run']).lower(),
                 'approved_request_sha256':digest if digest in grant['approved_requests'] else ''}
        source=next((record for record in grant['approved_sources'] if record['reference']==approved_reference),None)
        if source:
            for key,value in source.items():context['approved_'+key]=str(value)
        config=configparser.ConfigParser(interpolation=None)
        config['runtime']={'session':self.session,'output_dir':str(self.directory)}
        config['direct_invocation']=context
        fd,name=tempfile.mkstemp(prefix='.runtime-',dir=self.directory)
        try:
            os.fchmod(fd,0o600)
            with os.fdopen(fd,'w') as stream:config.write(stream)
            os.replace(name,self.runtime)
        finally:
            if os.path.exists(name):os.unlink(name)

    async def _start(self):
        if self.process is not None:
            if self.process.returncode is not None:
                raise BridgeFailure('GXTXT:MCP:ContextLost','Original Bridge context exited; select the authorized Session again')
            return
        private(self.runtime);private(self.directory,directory=True)
        self.log=(self.directory/'bridge-stderr.log').open('xb');os.chmod(self.log.name,0o600)
        env=dict(os.environ,GXTXT_BRIDGE_WORKSPACE=str(self.buffer),GXTXT_BRIDGE_TYPED_DESCRIPTORS='1',
                 PYTHONDONTWRITEBYTECODE='1')
        self.response_capacity=self.settings['limits']['response_bytes']
        self.process=await asyncio.create_subprocess_exec(self.settings['python'],'-u',
            str(Path(self.settings['framework_root'])/'core/python/gxtxt_script_bridge_server.py'),str(self.runtime),
            stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=self.log,env=env,
            limit=self.response_capacity)
        response=await self._exchange({'action':'start','execution':{'invocation_profile':'authorized_direct',
                'client_id':self.client_id,'context_id':self.context_id}})
        self._check(response)
        response=self._check(await self._exchange({'action':'info'}))
        try:
            self.compatibility_receipt=runtime(self.codec.decode_value(response['value']))
        except ConfigurationError as error:
            raise BridgeFailure('GXTXT:MCP:ContractIncompatible',str(error)) from None

    @staticmethod
    def _check(response):
        if not response.get('ok'):
            raise BridgeFailure(response.get('identifier','GXTXT:ScriptBridge:Transport'),response.get('message','Original Bridge failed'))
        return response

    async def _exchange(self,request):
        if self.tainted:
            raise BridgeFailure('GXTXT:MCP:OutcomeUnknown','Context has an unresolved operation; reselect after inspecting its original owner')
        payload=json.dumps(request,ensure_ascii=False,separators=(',',':')).encode()+b'\n'
        if len(payload)>self.settings['limits']['request_bytes']:
            raise BridgeFailure('GXTXT:MCP:RequestBudget','Request exceeds the configured control-message budget')
        self.process.stdin.write(payload);await self.process.stdin.drain()
        try:
            line=await asyncio.wait_for(self.process.stdout.readline(),self.settings['limits']['timeout_seconds'])
        except asyncio.TimeoutError:
            # A timeout never reports success or silently replays a mutation.
            self.tainted=True
            raise BridgeFailure('GXTXT:MCP:OutcomeUnknown','Original operation timed out; inspect its owner before retrying') from None
        except ValueError:
            self.tainted=True
            raise BridgeFailure('GXTXT:MCP:ResponseBudget','Original response exceeds this context control budget; use a bounded request or reselect after increasing limits') from None
        if not line:raise BridgeFailure('GXTXT:MCP:ContextLost','Original Bridge closed before returning an outcome')
        # The StreamReader also retains its startup allocation bound. Enforce
        # the current local owner's possibly stricter policy before decoding
        # or exposing any bytes from an already running Bridge context.
        if len(line)>self.settings['limits']['response_bytes']:
            self.tainted=True
            raise BridgeFailure('GXTXT:MCP:ResponseBudget','Original response exceeds the current control budget; inspect its owner before retrying')
        response=json.loads(line)
        self._remember_buffers(response)
        return response

    def _remember_buffers(self,value):
        if isinstance(value,dict):
            if value.get('kind')=='numeric_array' and isinstance(value.get('binary'),dict):
                descriptor=value['binary']
                total=sum(item['byte_count'] for key,item in self.descriptors.items() if key!=descriptor['resource_id'])
                if total+descriptor['byte_count']>self.settings['limits']['buffer_bytes']:
                    raise BridgeFailure('GXTXT:MCP:BufferBudget','Original buffer exceeds this context transport budget')
                self.descriptors[descriptor['resource_id']]=descriptor
            for item in value.values():self._remember_buffers(item)
        elif isinstance(value,list):
            for item in value:self._remember_buffers(item)

    async def request(self,request,grant,approved_reference=''):
        async with self.lock:
            # A queued call never retains rights revoked while waiting for
            # transport capacity or this context's serialized original host.
            settings=self.store.read()
            grant=settings['clients'].get(self.client_id)
            if not settings['enabled'] or grant is None or not grant['read']:
                raise BridgeFailure('GXTXT:MCP:AuthenticationDenied','Client was revoked or the service was disabled while the request waited')
            if settings['framework_root']!=self.settings['framework_root']:
                raise BridgeFailure('GXTXT:MCP:ContextLost','Selected framework changed; reopen the adapter context')
            if request.get('action')=='call' and not grant['invoke']:
                raise BridgeFailure('GXTXT:MCP:InvocationDenied','General invocation grant is no longer active')
            self.settings=dict(self.settings,limits=settings['limits'])
            digest=request_digest(request.get('api_id',''),request.get('operation',''),request.get('args',[]))
            self.authorize(grant,digest,approved_reference)
            await self._start()
            return await self._exchange(request)

    async def metadata(self,action,grant,**fields):
        response=self._check(await self.request(dict(action=action,**fields),grant))
        return self.codec.decode_value(response['value'])

    async def close(self):
        async with self.lock:
            if self.process is not None and self.process.returncode is None:
                try:
                    await self._exchange({'action':'stop'})
                    self.process.stdin.close()
                    await asyncio.wait_for(self.process.wait(),10)
                except (Exception,asyncio.CancelledError):
                    if self.process.returncode is None:
                        self.process.terminate()
                        try:await asyncio.wait_for(self.process.wait(),5)
                        except asyncio.TimeoutError:
                            self.process.kill();await self.process.wait()
            if self.log is not None:self.log.close()
            self.descriptors.clear()
            try:
                if self.directory.exists():shutil.rmtree(self.directory)
            finally:
                if self.lease is not None:
                    os.close(self.lease);self.lease=None
