"""Negative network/protocol checks against the campaign-owned live TLS agent."""
from pathlib import Path
import http.client
import json
import ssl
import sys

framework, output = (Path(p).resolve() for p in sys.argv[1:])
sys.path.insert(0, str(framework/'core/python'))
from gxtxt_remote_transport import exchange, pack, unpack, RemoteOperationError
cfg=json.loads((output/'node.json').read_text())
node=dict(node_id='localhost',endpoint=f'https://localhost:{cfg["port"]}/rpc',
          ca_file=str(output/'tls/ca.pem'),client_cert=str(output/'tls/client.pem'),
          client_key=str(output/'tls/client.key'))
checks=[]
def refused(label, request, selected=None):
    try:exchange(selected or node, request)
    except (ValueError,OSError,ssl.SSLError,http.client.HTTPException) as error:
        checks.append(dict(check=label,error_type=type(error).__name__,error=str(error)));return
    raise AssertionError(label+' was accepted')
base=dict(session_id='node-science',arguments=[])
refused('Unregistered operation cannot execute code',dict(base,operation='exec',arguments=['touch /tmp/untrusted']))
refused('Certificate grant rejects another logical Session',dict(base,operation='dataset.catalog',session_id='not-granted'))
refused('Stale Dataset revision refuses data read',dict(base,operation='dataset.range',arguments=['remote_big','0'*64,'exact','0','1']))
refused('Configured node identity is authenticated',dict(base,operation='capabilities'),dict(node,node_id='another-node'))
context=ssl.create_default_context(cafile=node['ca_file'])
connection=http.client.HTTPSConnection('localhost',cfg['port'],context=context,timeout=5)
try:
    connection.request('POST','/rpc',pack(dict(base,operation='capabilities')))
    connection.getresponse().read()
except (OSError,ssl.SSLError,http.client.HTTPException):checks.append(dict(check='Client certificate is mandatory'))
else:raise AssertionError('Unauthenticated client was accepted')
finally:connection.close()
damaged=bytearray(pack(dict(base,operation='resource.append',arguments=['fake','0']),[b'abc']));damaged[-1]^=1
context.load_cert_chain(node['client_cert'],node['client_key'])
connection=http.client.HTTPSConnection('localhost',cfg['port'],context=context,timeout=5)
try:
    connection.request('POST','/rpc',bytes(damaged),{'Content-Type':'application/vnd.gxtxt.core-rpc'})
    response=connection.getresponse();result,_=unpack(response.read())
    assert not result['ok'] and 'integrity' in result['error'].lower(),result
    checks.append(dict(check='Corrupt raw binary block is rejected before CORE mutation'))
finally:connection.close()
(output/'security.json').write_text(json.dumps(dict(status='PASS',checks=checks),indent=2)+'\n')
print('PASS',len(checks),'authenticated protocol boundary checks')
