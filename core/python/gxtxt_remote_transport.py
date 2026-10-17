"""Authenticated bounded CORE RPC framing; no scientific dispatch or scheduler."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import hashlib
import http.client
import json
import os
from pathlib import Path
import ssl
import struct
import sys
import tkinter
from urllib.parse import urlsplit

MAX_BODY = 32 * 1024 * 1024
MAX_CONTROL = 2 * 1024 * 1024
class RemoteOperationError(ValueError):
    def __init__(self,message,code='GX REMOTE REQUEST_FAILED'):
        super().__init__(message);self.code=code

def pack(control, blobs=()):
    data = dict(control)
    data['blocks'] = [dict(size=len(b), sha256=hashlib.sha256(b).hexdigest()) for b in blobs]
    header = json.dumps(data, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode()
    result = struct.pack('!I', len(header)) + header + b''.join(blobs)
    if len(header) > MAX_CONTROL or len(result) > MAX_BODY:
        raise ValueError('CORE remote message exceeds bounded transport limits')
    return result

def unpack(body):
    if not 4 <= len(body) <= MAX_BODY:
        raise ValueError('Invalid CORE remote message size')
    size = struct.unpack('!I', body[:4])[0]
    if not 0 < size <= MAX_CONTROL or size + 4 > len(body):
        raise ValueError('Invalid CORE remote control frame')
    control = json.loads(body[4:4+size]); offset = size + 4; blobs = []
    for block in control.pop('blocks', []):
        length = block['size']
        if not isinstance(length, int) or length < 0 or offset + length > len(body):
            raise ValueError('Invalid CORE remote binary block')
        raw = body[offset:offset+length]; offset += length
        if hashlib.sha256(raw).hexdigest() != block['sha256']:
            raise ValueError('CORE remote block integrity failure')
        blobs.append(raw)
    if offset != len(body):
        raise ValueError('Unexpected trailing remote data')
    return control, blobs

def exchange(node, request, blobs=()):
    url = urlsplit(node['endpoint'])
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Compute node requires an explicit HTTPS endpoint')
    key = Path(node['client_key'])
    if os.name == 'posix' and key.stat().st_mode & 0o077:
        raise ValueError('Compute client key must be private to its owner')
    context = ssl.create_default_context(cafile=node['ca_file'])
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(node['client_cert'], key)
    connection = http.client.HTTPSConnection(url.hostname, url.port or 443, context=context, timeout=8)
    body = pack(request, blobs)
    try:
        connection.request('POST', (url.path or '/rpc'), body, {'Content-Type': 'application/vnd.gxtxt.core-rpc'})
        response = connection.getresponse()
        length = int(response.getheader('Content-Length', '-1'))
        if response.status != 200 or not 0 < length <= MAX_BODY:
            raise ValueError('Compute node refused the bounded authenticated request')
        data = response.read(length + 1)
        if len(data) != length:
            raise ValueError('Incomplete CORE remote response')
        result, blocks = unpack(data)
        if result.get('node_id') != node['node_id']:
            raise RemoteOperationError('Compute node identity disagrees with configured identity','GX REMOTE AUTHENTICATION')
        if not result.get('ok'):
            raise RemoteOperationError(result.get('error', 'Remote operation failed'),result.get('error_code','GX REMOTE REQUEST_FAILED'))
        return result, blocks, dict(sent_bytes=len(body), received_bytes=len(data))
    finally:
        connection.close()

def tcl_dict(tcl, value):
    parts = tcl.splitlist(value)
    if len(parts) % 2: raise ValueError('Expected a CORE dictionary')
    return dict(zip(parts[::2], parts[1::2]))

def tcl_value(tcl, value):
    if isinstance(value, dict):
        return tcl.call('dict', 'create', *[v for k, item in value.items() for v in (k, tcl_value(tcl, item))])
    if isinstance(value, (list, tuple)): return tuple(tcl_value(tcl, v) for v in value)
    if isinstance(value, bool): return int(value)
    if value is None: return ''
    return value

def main():
    tcl = tkinter.Tcl()
    try:
        request = tcl_dict(tcl, sys.stdin.read(MAX_CONTROL + 1))
        node = tcl_dict(tcl, request.pop('node'))
        artifact_directory=request.pop('artifact_directory',None)
        request['arguments'] = list(tcl.splitlist(request.get('arguments', '')))
        input_blocks = []
        if 'payload_base64' in request:
            import base64
            input_blocks.append(base64.b64decode(request.pop('payload_base64'), validate=True))
        result, blocks, metrics = exchange(node, request, input_blocks)
        if result.get('pending'):
            import time
            deadline=time.monotonic()+240
            while result.get('pending'):
                if time.monotonic()>deadline:raise RemoteOperationError('Remote Preview preparation timed out','GX REMOTE TIMEOUT')
                time.sleep(.2)
                result,blocks,measured=exchange(node,request,input_blocks)
                for key,value in measured.items():metrics[key]+=value
        if 'result_block' in result:
            result['result'] = blocks[result['result_block']].decode('utf-8')
            if result.get('artifacts'):
                import re
                if not artifact_directory: raise ValueError('No authorized local Preview artifact destination')
                directory=Path(artifact_directory)
                if not directory.is_dir() or any(p.is_symlink() for p in (directory,*directory.parents)):
                    raise ValueError('Unsafe local Preview artifact directory')
                for artifact in result['artifacts']:
                    name=artifact['name']
                    if not re.fullmatch(r'image_[0-9]+\.png',name): raise ValueError('Invalid derived image filename')
                    path=directory/name;raw=blocks[artifact['block']]
                    if path.is_symlink() or len(raw)>2097152: raise ValueError('Unsafe or oversized derived image')
                    temporary=path.with_suffix('.pending')
                    with temporary.open('xb') as stream:stream.write(raw)
                    temporary.replace(path)
                    if artifact.get('target')=='media_artifact':
                        media=tcl.call('dict','get',result['result'],'media_artifact')
                        result['result']=tcl.call('format','%s',tcl.call('dict','replace',result['result'],'media_artifact',tcl.call('dict','replace',media,'path',str(path))))
                        continue
                    parsed=result['result'];digitizer=tcl.call('dict','get',parsed,'digitizer')
                    images=tcl.call('dict','get',digitizer,'images');info=tcl.call('dict','get',images,artifact['image_id'])
                    info=tcl.call('dict','replace',info,'path',str(path))
                    images=tcl.call('dict','replace',images,artifact['image_id'],info)
                    digitizer=tcl.call('dict','replace',digitizer,'images',images)
                    result['result']=tcl.call('format','%s',tcl.call('dict','replace',parsed,'digitizer',digitizer))
        if 'binary_field' in result:
            import base64
            result['result']=tcl.call('format','%s',tcl.call('dict','replace',result['result'],result['binary_field'],base64.b64encode(blocks[result['binary_block']]).decode()))
        if 'arrays' in result:
            import numpy as np
            items = {}
            for array in result['arrays']:
                raw = blocks[array['block']]
                if array.get('text'):
                    item = tcl_dict(tcl, array['receipt']);item['values'] = json.loads(raw)
                    items[array['variable_id']] = item
                    continue
                dtype = np.dtype(array['dtype'])
                shape = array['shape']
                if dtype.kind not in 'biuf' or dtype.itemsize * __import__('math').prod(shape) != len(raw):
                    raise ValueError('Invalid typed remote Dataset array')
                values = np.frombuffer(raw, dtype=dtype)
                strings = [str(int(v)) if dtype.kind in 'biu' else repr(float(v)) for v in values]
                for index in array.get('missing', []): strings[index] = ''
                item = tcl_dict(tcl, array['receipt'])
                item['values'] = strings
                import base64
                item['binary_block'] = dict(__gxtxt_binary_block=1, dtype=dtype.name, endian='little', shape=';'.join(str(v) for v in shape), byte_count=len(raw), base64=base64.b64encode(raw).decode())
                items[array['variable_id']] = item
            result['result'] = tcl_value(tcl, items)
        output = tcl_value(tcl, dict(ok=1, result=result.get('result', ''), metrics=metrics))
    except RemoteOperationError as error:
        output = tcl_value(tcl, dict(ok=0,error=str(error),error_code=error.code))
    except (OSError, ValueError, ssl.SSLError, http.client.HTTPException) as error:
        output = tcl_value(tcl, dict(ok=0, error=str(error), error_code='GX REMOTE UNAVAILABLE'))
    print(tcl.call('format', '%s', output))

if __name__ == '__main__': main()
