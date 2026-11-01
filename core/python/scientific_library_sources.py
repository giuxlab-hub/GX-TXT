"""Finite Library source discovery/transport using existing credential scopes.

No source data, credentials or connections are stored here. Registered remote
Libraries bind connectors through non-secret config.connector; the sole Manager
and its protected content request lifetime remain authoritative.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import contextlib
import contextvars
import base64
import hashlib
import importlib.util
import ipaddress
import json
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from scientific_library_graph import declarations

_ACCESS=contextvars.ContextVar('library_source_credential_access',default=None)
_LAST={}

def connectors():
    out={}
    for identity,declaration in declarations('library_source_connector').items():
        fields=declaration['fields']
        out[identity]=dict(connector_id=identity,version=declaration['version'],
            library_types=fields.get('library_types','').split(';'),
            record_types=fields.get('record_types','').split(';') if fields.get('record_types') else [],
            authentication=fields.get('authentication','none'),
            persistent_import_available=fields.get('persistence','persistent')=='persistent',
            operations=['search','read_entry'],network_on_discovery=False)
    return out

def resolve(identity):
    declaration=declarations('library_source_connector').get(identity)
    if not declaration:raise ValueError('Source connector is missing or disabled')
    spec=importlib.util.spec_from_file_location('gxtxt_source_'+identity.replace('.','_'),declaration['path'])
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    if getattr(module,'CONNECTOR_ID',None)!=identity:raise ValueError('Source connector identity mismatch')
    return module

@contextlib.contextmanager
def authentication_scope(record,access,framework):
    token=_ACCESS.set(access)
    try:yield
    finally:_ACCESS.reset(token)

def credential_call(callback):
    access=_ACCESS.get()
    if access is None:raise ValueError('Source credentials are locked or not configured')
    return access.with_secret(callback)

def status(record,framework):
    if record.get('mode','managed')=='managed':
        return dict(availability='available',authentication_required=False,authentication_status='not_required',read_only=True)
    identity=record.get('provider_config',{}).get('connector','')
    declaration=connectors().get(identity)
    if declaration is None:return dict(availability='unavailable',reason='Source connector is missing or disabled',authentication_required=False,authentication_status='not_required',read_only=True)
    required=declaration['authentication']!='none'
    return dict(availability='available',read_only=True,authentication_required=required,
        authentication_status=('unlocked' if _ACCESS.get() else 'locked') if required else 'not_required',
        reason='Declared source interface; no live connection check performed')

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        raise ValueError('Source redirected; endpoint requires adapter review')

def request(url, *, allowed_hosts, data=None, headers=None, maximum=8*1024*1024, interval=.25):
    """Bounded HTTPS. Exceptions never retain URL, response body or credentials."""
    parsed=urllib.parse.urlsplit(url)
    if parsed.scheme!='https' or parsed.username or parsed.password or parsed.fragment or parsed.port not in (None,443) or parsed.hostname not in allowed_hosts:
        raise ValueError('Source URL is outside declared HTTPS endpoints')
    try:
        for item in socket.getaddrinfo(parsed.hostname,443,type=socket.SOCK_STREAM):
            if not ipaddress.ip_address(item[4][0]).is_global:raise ValueError('Source resolved to a non-public address')
        remaining=interval-(time.monotonic()-_LAST.get(parsed.hostname,0))
        if remaining>0:time.sleep(remaining)
        _LAST[parsed.hostname]=time.monotonic()
        req=urllib.request.Request(url,data=data,headers=dict({'User-Agent':'GX-TXT/DEV111-P028 ScientificLibrary','Accept':'application/json'},**(headers or {})))
        with urllib.request.build_opener(_NoRedirect).open(req,timeout=8) as response:
            raw=response.read(maximum+1)
            if len(raw)>maximum:raise ValueError('Source response exceeds declared byte limit')
            return raw
    except urllib.error.HTTPError as error:
        raise ValueError('Source HTTP '+str(error.code)+'; request not persisted (rate/auth/source availability)') from None
    except (urllib.error.URLError,TimeoutError,OSError):
        raise ValueError('Source transport unavailable or timed out; request not persisted') from None

def search_entries(record,parameters,framework):
    connector=resolve(record['provider_config']['connector'])
    if parameters.get('continuation'):raise ValueError('Exact source lookup has no continuation')
    query=parameters.get('query','')
    if not isinstance(query,str) or not 1<=len(query)<=500:raise ValueError('Enter a bounded exact identity or supported source query')
    entries=connector.search(query,parameters.get('limit',50))
    return dict(records=entries[:parameters.get('limit',50)],total=len(entries))

def read_entry(record,parameters,framework):
    connector=resolve(record['provider_config']['connector'])
    bundle=connector.read(parameters['entry_id'],parameters.get('options',{}))
    version=connectors()[connector.CONNECTOR_ID]['version']
    bundle['connector_version']=version
    for row in bundle.get('entries',[]):
        row['entry']['provenance'].update(connector_id=connector.CONNECTOR_ID,connector_version=version)
    return dict(entry_id=parameters['entry_id'],metadata=dict(connector_id=connector.CONNECTOR_ID),
        provenance=dict(source_id=connector.CONNECTOR_ID),payload=bundle)

def entry_info(record,parameters,framework):
    result=read_entry(record,parameters,framework)
    return dict(entry_id=result['entry_id'],metadata=result['payload'],provenance=result['provenance'],content_contract='')

def materialize_assets(bundle, options, allowed_hosts):
    """Explicit selected source assets only; unavailable files stay external."""
    if not options.get('download_assets',False):return bundle
    if bundle.get('persistent_import_available') is False:
        raise ValueError(bundle.get('persistence_reason','This source channel supports read-through consultation only'))
    selected=options.get('selected_ids',[])
    if not isinstance(selected,list) or len(selected)>100:raise ValueError('Invalid bounded asset selection')
    budget=8*1024*1024
    for row in bundle['entries']:
        entry=row['entry']
        if entry['entry_id'] not in selected:continue
        for resource in entry.get('resources',[]):
            if resource.get('availability')!='external':continue
            try:
                raw=request(resource['url'],allowed_hosts=allowed_hosts,maximum=min(budget,4*1024*1024),interval=2)
                if raw.startswith(b'%PDF-'):mime='application/pdf';extension='.pdf'
                elif raw.startswith(b'\x89PNG\r\n\x1a\n'):mime='image/png';extension='.png'
                elif raw.startswith(b'\xff\xd8\xff'):mime='image/jpeg';extension='.jpg'
                else:raise ValueError('Source asset is not a supported PDF/PNG/JPEG original')
                budget-=len(raw)
                resource.update(availability='local',media_type=mime,sha256=hashlib.sha256(raw).hexdigest(),size_bytes=len(raw),
                    original_filename=entry['entry_id']+extension,data_base64=base64.b64encode(raw).decode())
            except ValueError as error:
                resource['download_status']='unavailable';resource['diagnostic']=str(error)
    return bundle

def transient_asset(bundle, options, allowed_hosts):
    """Read-through image bytes: RAM-only result, no local/library staging."""
    identity=options.get('transient_asset_entry_id')
    if not identity:return bundle
    selected=[row['entry'] for row in bundle['entries'] if row['entry']['entry_id']==identity]
    if len(selected)!=1:raise ValueError('Select an actual resource from this source response')
    assets=[]
    for resource in selected[0].get('resources',[])[:4]:
        if resource.get('availability')!='external':continue
        raw=request(resource['url'],allowed_hosts=allowed_hosts,maximum=2*1024*1024,interval=2)
        if raw.startswith(b'\x89PNG\r\n\x1a\n'):mime='image/png'
        elif raw.startswith(b'\xff\xd8\xff'):mime='image/jpeg'
        else:raise ValueError('Use the original document link; this transient preview supports actual PNG/JPEG images')
        assets.append(dict(entry_id=identity,role=resource['role'],media_type=mime,sha256=hashlib.sha256(raw).hexdigest(),
            data_base64=base64.b64encode(raw).decode(),availability='transient_memory'))
    bundle['preview_assets']=assets
    return bundle
