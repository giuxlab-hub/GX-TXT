"""Production codec constants and isolated pure Tcl-argument boundary assertion."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'core/python'))
import gxtxt as client
import gxtxt_script_bridge_server as server


def require(ok):
    if not ok:
        raise ValueError('Null codec constant qualification failed')


def same(actual, expected):
    require(type(actual) is type(expected))
    if isinstance(expected, dict):
        require(set(actual) == set(expected))
        for key in expected:
            same(actual[key], expected[key])
    elif isinstance(expected, list):
        require(len(actual) == len(expected))
        for a, b in zip(actual, expected):
            same(a, b)
    else:
        require(actual == expected)


constants = [None, False, 0, '', [], {}, 'α\0🙂', 18446744073709551615,
             {'null': None, 'values': [False, 0, '', [], {}, None, 'β\0']}]
for value in constants:
    # JSON serialization exercises the real typed-wire boundary as well.
    same(server.decode_value(json.loads(json.dumps(client._pack(value, [])))), value)
    same(client._unpack(json.loads(json.dumps(server.encode_value(value)))), value)
require(server.encode_value(None) == {'kind': 'null'})
require(client._pack(None, []) == {'kind': 'null'})
malformed = [{'kind': 'null', 'value': None}, {'kind': 'null', 'array_id': '0'},
             {'kind': 'null', 'binary_path': '/must-not-be-opened'},
             {'kind': 'NULL'}, {'kind': None}, {}]
for decoder in (server.decode_value, client._unpack):
    for index, wire in enumerate(malformed):
        refused = False
        try:
            decoder(wire)
        except Exception as error:
            if index < 3:
                require(isinstance(error, (server.BridgeError, client.GXTXTBridgeError))
                        and error.identifier == 'GXTXT:ScriptBridge:Transport')
            refused = True
        require(refused)
if client._np is not None:
    refused = False
    try:
        client._pack(client._np.datetime64('NaT'), [])
    except TypeError:
        refused = True
    require(refused)
# MAIN-authorized unit seam: an uninitialized production class receiver ONLY.
# No Host.__init__, configuration, discovery, Tcl interpreter or API invocation.
# The actual method needs no state; no method/algorithm is mocked or copied.
normalizer = object.__new__(server.Host)
for value in (None, [None], {'k': None}):
    refused = False
    try:
        normalizer.tcl_arg(value)
    except server.BridgeError as error:
        require(error.identifier == 'GXTXT:ScriptBridge:InvalidArguments'
                and str(error) == 'null has no generic Tcl argument representation')
        refused = True
    require(refused)
require(normalizer.tcl_arg('None') == 'None')
print(json.dumps({'schema': 'gxtxt.task210.script_bridge_null.constants.v1',
                  'status': 'PASS', 'constants_each_direction': len(constants),
                  'malformed_each_decoder': len(malformed),
                  'normalizer_null_refusals': 3, 'literal_None_text_preserved': True,
                  'Host_initialized': False, 'API_or_provider_invoked': False,
                  'unit_seam': 'UNINITIALIZED_PRODUCTION_RECEIVER_PURE_NORMALIZER_ONLY'}))
