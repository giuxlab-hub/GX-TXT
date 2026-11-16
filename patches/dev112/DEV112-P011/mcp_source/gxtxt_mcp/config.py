"""One protected user-local authority for adapter settings and explicit grants."""
from __future__ import annotations
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import tempfile
import fcntl


class ConfigurationError(ValueError):
    pass


def private(path: Path, *, directory=False):
    info=path.lstat()
    expected=0o700 if directory else 0o600
    if (stat.S_ISLNK(info.st_mode) or
        not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)) or
        stat.S_IMODE(info.st_mode)!=expected or
        hasattr(os,'getuid') and info.st_uid!=os.getuid()):
        raise ConfigurationError('MCP state must be private to its local owner (directories0700, files0600)')


def identifier(value):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]{0,63}',value):
        raise ConfigurationError('Client ID must be a bounded stable identifier')
    return value


def framework_info(root):
    path=Path(root).resolve(strict=True)
    if not (path/'core/python/gxtxt_script_bridge_server.py').is_file():
        raise ConfigurationError('Selected installation has no original Script Bridge')
    # Release labels are diagnostic metadata, never a capability or grant.
    def label(name):
        try:
            with (path/name).open() as stream:
                return stream.read(256).strip() or 'unknown'
        except FileNotFoundError:
            return 'unknown'
    version=label('VERSION.txt')
    patch=label('PATCH_LEVEL.txt')
    return {'version':version,'patch_level':patch,
            'installation_fingerprint':hashlib.sha256(str(path).encode()).hexdigest()}


def validate(value):
    if not isinstance(value,dict) or value.get('schema')!='gxtxt.mcp.configuration.v1':
        raise ConfigurationError('Unsupported MCP configuration schema')
    if set(value)-{'schema','revision','framework_root','python','enabled','transport','host','port','clients','limits'}:
        raise ConfigurationError('Unknown MCP configuration fields')
    if type(value.get('revision')) is not int or value['revision']<1 or type(value.get('enabled')) is not bool:
        raise ConfigurationError('Configuration revision/enabled values are invalid')
    if value.get('transport') not in {'stdio','streamable-http'} or value.get('host')!='127.0.0.1':
        raise ConfigurationError('Use local stdio or Streamable HTTP bound to127.0.0.1')
    if type(value.get('port')) is not int or not 1024<=value['port']<=65535:
        raise ConfigurationError('Loopback port must be1024..65535')
    for key in ('framework_root','python'):
        if not isinstance(value.get(key),str) or not Path(value[key]).is_absolute():
            raise ConfigurationError('Framework and Python identities must be absolute local paths')
    limits=value.get('limits',{})
    allowed={'request_bytes':(1024,4194304),'response_bytes':(65536,16777216),
             'buffer_bytes':(1048576,268435456),'concurrency':(1,16),'timeout_seconds':(1,300)}
    if set(limits)!=set(allowed):raise ConfigurationError('MCP resource limits must be explicit')
    for key,(low,high) in allowed.items():
        if type(limits[key]) is not int or not low<=limits[key]<=high:
            raise ConfigurationError('MCP resource limit is outside its supported bounds')
    if not isinstance(value.get('clients'),dict) or len(value['clients'])>128:
        raise ConfigurationError('Client grants require a bounded dictionary')
    for client,grant in value['clients'].items():
        identifier(client)
        if not isinstance(grant,dict) or set(grant)!={'token_sha256','read','author','run','invoke','sessions','approved_requests','approved_sources','approved_reports'}:
            raise ConfigurationError('Client grants have unknown or missing fields')
        if not isinstance(grant['token_sha256'],str) or not re.fullmatch('[a-f0-9]{64}',grant['token_sha256']):
            raise ConfigurationError('Client credential digest is invalid')
        if any(type(grant[key]) is not bool for key in ('read','author','run','invoke')):
            raise ConfigurationError('Client capabilities must be explicit booleans')
        if not isinstance(grant['sessions'],list) or len(grant['sessions'])>256 or any(not isinstance(p,str) or not Path(p).is_absolute() for p in grant['sessions']):
            raise ConfigurationError('Session grants require exact absolute owner-selected identities')
        if any(not isinstance(grant[key],list) for key in ('approved_requests','approved_sources','approved_reports')):
            raise ConfigurationError('Source/request/report approvals must be explicit lists')
        if any(not isinstance(digest,str) or not re.fullmatch('[a-f0-9]{64}',digest) for digest in grant['approved_requests']+grant['approved_reports']):
            raise ConfigurationError('Approval digest is invalid')
        for source in grant['approved_sources']:
            if not isinstance(source,dict) or set(source)!={'reference','sha256','revision','record_sha256','owner_context'}:
                raise ConfigurationError('Source approval requires the complete original Registry identity')
            if not isinstance(source['reference'],str) or not re.fullmatch(r'(user|session):[A-Za-z0-9_.-]{1,128}',source['reference']):
                raise ConfigurationError('Source approval must name an original Registry reference')
            if any(not isinstance(source[k],str) or not re.fullmatch('[a-f0-9]{64}',source[k]) for k in ('sha256','record_sha256')):
                raise ConfigurationError('Source approval digests are invalid')
            if type(source['revision']) is not int or source['revision']<1:
                raise ConfigurationError('Source approval revision must be positive')
            if not isinstance(source['owner_context'],str) or not 1<=len(source['owner_context'])<=4096:
                raise ConfigurationError('Source approval owner context must be genuine and bounded')
    return value


class Store:
    def __init__(self,home=None):
        default=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))/'gxtxt-mcp'
        self.home=Path(home or os.environ.get('GXTXT_MCP_HOME',default)).absolute()
        self.path=self.home/'configuration.json'

    def prepare(self):
        if not self.home.exists():self.home.mkdir(parents=True,mode=0o700)
        private(self.home,directory=True)
        for name in ('contexts','reports'):
            path=self.home/name
            if not path.exists():path.mkdir(mode=0o700)
            private(path,directory=True)

    def read(self):
        private(self.home,directory=True);private(self.path)
        if self.path.stat().st_size>1048576:raise ConfigurationError('MCP configuration exceeds1MiB')
        return validate(json.loads(self.path.read_text()))

    @contextmanager
    def transaction(self):
        self.prepare()
        lock=self.home/'.configuration.lock'
        fd=os.open(lock,os.O_WRONLY|os.O_CREAT|os.O_NOFOLLOW,0o600)
        try:
            private(lock)
            try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise ConfigurationError('Another local configuration transaction is active') from None
            yield
        finally:os.close(fd)

    def write(self,value,expected_revision=None):
        validate(value)
        with self.transaction():
            if self.path.exists():
                previous=self.read()
                if expected_revision!=previous['revision']:
                    raise ConfigurationError('MCP settings changed; reload before saving')
                value=dict(value,revision=previous['revision']+1)
            elif expected_revision is not None:raise ConfigurationError('MCP settings disappeared')
            fd,name=tempfile.mkstemp(prefix='.configuration-',dir=self.home)
            try:
                os.fchmod(fd,0o600)
                with os.fdopen(fd,'w') as stream:
                    json.dump(value,stream,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
                os.replace(name,self.path)
            finally:
                if os.path.exists(name):os.unlink(name)
        return value

    def initialize(self,root,python='/usr/bin/python3'):
        if self.path.exists():raise ConfigurationError('MCP is already configured')
        root=Path(root).resolve(strict=True)
        # Initializing records a selected installation; Test/Start checks the
        # actual public capabilities. No service is enabled by initialization.
        return self.write({'schema':'gxtxt.mcp.configuration.v1','revision':1,'framework_root':str(root),
                           'python':str(Path(python).resolve(strict=True)),'enabled':False,
                           'transport':'stdio','host':'127.0.0.1','port':8765,'clients':{},
                           'limits':{'request_bytes':1048576,'response_bytes':4194304,'buffer_bytes':67108864,
                                     'concurrency':4,'timeout_seconds':120}})

    def authenticate(self,token):
        if not isinstance(token,str) or not 32<=len(token)<=256:
            raise ConfigurationError('MCP client authentication failed')
        digest=hashlib.sha256(token.encode()).hexdigest()
        value=self.read()
        for name,grant in value['clients'].items():
            if secrets.compare_digest(digest,grant['token_sha256']) and grant['read']:
                return name,value,grant
        raise ConfigurationError('MCP client authentication failed')

    def public(self):
        value=self.read()
        result={key:item for key,item in value.items() if key!='clients'}
        result['clients']={name:{key:item for key,item in grant.items() if key not in {'token_sha256','approved_requests','approved_sources','approved_reports'}}
                           for name,grant in value['clients'].items()}
        return result
