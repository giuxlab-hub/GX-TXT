"""Public GX-TXT researcher script client for provider-owned public APIs.

The framework activates this module before executing a registered Python
script. Importing it outside a GX-TXT run is allowed; calls explain that the
Bridge is inactive. Scientific packages remain owned by the configured Python
runtime, not by this client.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

try:
    import numpy as _np
except ImportError:
    _np = None


class GXTXTBridgeError(RuntimeError):
    def __init__(self, identifier: str, message: str):
        self.identifier = identifier
        super().__init__(f"{identifier}: {message}")


_process = None
_stderr = None
_callbacks = {}
_in_callback = False
_callback_temporary = []
_callback_arrays = {}
_buffer_root = None
_buffer_resource = None
_buffer_manager = None


class CallbackHandle:
    def __init__(self, identifier):
        self.id = identifier


def _pack(value, temporary, depth=0):
    if depth > 32:
        raise GXTXTBridgeError("GXTXT:ScriptBridge:InvalidArguments", "value nesting exceeds 32")
    if _np is not None and isinstance(value, _np.generic):
        value = value.item()
    if isinstance(value, CallbackHandle):
        return {"kind": "callback", "id": value.id}
    if isinstance(value, bool):
        return {"kind": "logical", "value": value}
    if isinstance(value, int):
        return {"kind": "integer_scalar", "value": str(value)}
    if isinstance(value, float):
        return {"kind": "numeric_scalar", "value": format(value, ".17g")}
    if isinstance(value, str):
        return {"kind": "string", "value": value}
    if _np is not None and isinstance(value, complex):
        value = _np.asarray(value).reshape(1, 1)
    if _np is not None and isinstance(value, _np.ndarray):
        if value.dtype.kind not in "biufc":
            raise TypeError("GX-TXT numeric arrays need boolean, integer, floating or complex values")
        array = _np.asarray(value)
        shape = list(array.shape)
        if array.ndim == 1:
            shape.append(1)
        result = {"kind": "numeric_array", "shape": shape}
        if array.size > 64 or array.dtype.name != 'float64':
            if _buffer_root is not None:
                from gxtxt_scientific_binary_v1 import write_buffer
                descriptor = write_buffer(_buffer_root, array)
                temporary.append(str(_buffer_root / descriptor["resource_id"]))
                result["binary"] = descriptor
                return result
            if array.dtype.name != 'float64':
                raise GXTXTBridgeError('GXTXT:ScriptBridge:Transport', 'typed arrays require an active managed Bridge')
            fd, path = tempfile.mkstemp(prefix="gxtxt-script-argument-", suffix=".bin")
            with os.fdopen(fd, "wb") as stream:
                stream.write(array.tobytes(order="F"))
            temporary.append(path)
            result["binary_path"] = path
        else:
            result["values"] = [format(float(v), ".17g") for v in array.ravel(order="F")]
        return result
    if isinstance(value, dict):
        return {"kind": "struct", "fields": {str(k): _pack(v, temporary, depth + 1) for k, v in value.items()}}
    if isinstance(value, (list, tuple)):
        return {"kind": "cell", "items": [_pack(v, temporary, depth + 1) for v in value]}
    raise TypeError(f"GX-TXT cannot transport {type(value).__name__}")


def _unpack(wire, depth=0, arrays=None):
    if arrays is None: arrays = {}
    if depth > 32:
        raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", "result nesting exceeds 32")
    kind = wire["kind"]
    if kind == 'numeric_array_ref':
        if wire.get('array_id') not in arrays:
            raise GXTXTBridgeError('GXTXT:ScriptBridge:Transport', 'unknown response array reference')
        return arrays[wire['array_id']]
    if kind == "string":
        return wire["value"]
    if kind == "logical":
        return bool(wire["value"])
    if kind == "integer_scalar":
        return int(wire["value"])
    if kind == "numeric_scalar":
        return float(wire["value"])
    if kind == "numeric_array":
        shape = tuple(int(v) for v in wire["shape"])
        count = math.prod(shape)
        if "binary" in wire:
            if _buffer_root is None:
                raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", "binary result has no owned workspace")
            from gxtxt_scientific_binary_v1 import read_buffer
            descriptor = wire["binary"]
            if descriptor.get("shape") != list(shape):
                raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", "binary result shape mismatch")
            array = read_buffer(_buffer_root, descriptor)
            (_buffer_root / descriptor["resource_id"]).unlink()
            return _remember_array(wire, array, arrays)
        if "binary_path" in wire:
            path = Path(wire["binary_path"])
            try:
                data = path.read_bytes()
                if len(data) != count * 8:
                    raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", "numeric payload length mismatch")
                values = _np.frombuffer(data, dtype="<f8").copy() if _np is not None else struct.unpack("<" + "d" * count, data)
            finally:
                path.unlink(missing_ok=True)
        else:
            values = [float(v) for v in wire["values"]]
        if _np is not None:
            return _remember_array(wire, _np.asarray(values, dtype=float).reshape(shape, order="F"), arrays)
        if len(shape) == 2 and shape[1] > 1:
            return _remember_array(wire, [[values[row + shape[0] * col] for col in range(shape[1])] for row in range(shape[0])], arrays)
        return _remember_array(wire, list(values), arrays)
    if kind in ("cell", "struct_array"):
        return [_unpack(v, depth + 1, arrays) for v in wire["items"]]
    if kind == "struct":
        return {k: _unpack(v, depth + 1, arrays) for k, v in wire["fields"].items()}
    raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", f"unknown result kind {kind}")


def _remember_array(wire, value, arrays):
    if 'array_id' in wire:
        key = wire['array_id']
        if not isinstance(key, str) or key in arrays or len(arrays) >= 65536:
            raise GXTXTBridgeError('GXTXT:ScriptBridge:Transport', 'invalid response array identity')
        arrays[key] = value
    return value


def _request(action, **fields):
    if _in_callback:
        raise GXTXTBridgeError("GXTXT:ScriptCallback:Reentrant", "a callback cannot start a nested Bridge request")
    if _process is None or _process.poll() is not None:
        raise GXTXTBridgeError("GXTXT:ScriptBridge:NotActive", "Script Bridge is not active")
    request = {"action": action, **fields}
    try:
        _process.stdin.write(json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n")
        _process.stdin.flush()
        while True:
            line = _process.stdout.readline()
            if not line:
                raise RuntimeError("Bridge server closed its response channel")
            response = json.loads(line)
            if response.get("event") == "callback_invoke":
                _serve_callback(response)
                continue
            if response.get('event') in ('callback_arguments_release', 'callback_buffers_release'):
                _release_callback_storage(response)
                continue
            break
    except (BrokenPipeError, OSError, ValueError, RuntimeError) as exc:
        raise GXTXTBridgeError("GXTXT:ScriptBridge:Transport", str(exc)) from exc
    for path in _callback_temporary:
        Path(path).unlink(missing_ok=True)
    _callback_temporary.clear()
    if not response.get("ok"):
        raise GXTXTBridgeError(response.get("identifier", "GXTXT:ScriptBridge:RemoteError"), response.get("message", "Bridge call failed"))
    return _unpack(response["value"])


def _release_callback_storage(event):
    ids = set(event['ids'])
    if event['event'] == 'callback_arguments_release':
        for identifier in ids:
            _callback_arrays.pop(identifier, None)
    else:
        retained = []
        for path in _callback_temporary:
            if Path(path).name in ids:
                Path(path).unlink(missing_ok=True)
            else:
                retained.append(path)
        _callback_temporary[:] = retained


def _callback_argument(wire, owner):
    if wire.get('kind') != 'callback_array':
        return _unpack(wire)
    identifier = wire['id']
    if 'value' in wire:
        if identifier in _callback_arrays:
            raise GXTXTBridgeError('GXTXT:ScriptCallback:Transport', 'Repeated constant argument definition')
        value = _unpack(wire['value'])
        if _np is None or not isinstance(value, _np.ndarray):
            raise GXTXTBridgeError('GXTXT:ScriptCallback:Transport', 'Constant argument is not a typed numeric array')
        value.setflags(write=False)
        _callback_arrays[identifier] = (owner, value)
    if identifier not in _callback_arrays or _callback_arrays[identifier][0] != owner:
        raise GXTXTBridgeError('GXTXT:ScriptCallback:Transport', 'Unknown or foreign constant callback argument')
    return _callback_arrays[identifier][1]


def _serve_callback(event):
    global _in_callback
    identifier = event.get("id", "")
    temporary = []
    try:
        function = _callbacks.get(identifier)
        if function is None:
            raise GXTXTBridgeError("GXTXT:ScriptCallback:UnknownCallback", "callback is no longer registered")
        _in_callback = True
        result = function(*[_callback_argument(arg, identifier) for arg in event["args"]])
        payload = {"action": "callback_result", "id": identifier, "ok": True,
                   "value": _pack(result, temporary)}
    except BaseException as exc:
        payload = {"action": "callback_result", "id": identifier, "ok": False,
                   "identifier": exc.identifier if isinstance(exc, GXTXTBridgeError) else "GXTXT:ScriptCallback:Error",
                   "message": f"{type(exc).__name__}: {exc}"}
    finally:
        _in_callback = False
    _callback_temporary.extend(temporary)
    _process.stdin.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    _process.stdin.flush()


def _activate(runtime_path, execution):
    global _process, _stderr, _buffer_root, _buffer_resource, _buffer_manager
    if _process is not None:
        raise GXTXTBridgeError("GXTXT:ScriptBridge:InvalidArguments", "Script Bridge is already active")
    runtime_path = Path(runtime_path)
    server = Path(__file__).resolve().parents[1] / "gxtxt_script_bridge_server.py"
    try:
        from gxtxt_resource_manager import ResourceManager
        _buffer_manager = ResourceManager()
        _buffer_resource = _buffer_manager.allocate("script_bridge", kind="directory", job_id=os.environ.get("GXTXT_JOB_ID", ""))
        _buffer_root = Path(_buffer_resource["path"])
    except ImportError:
        _buffer_root = Path(tempfile.mkdtemp(prefix="gxtxt-script-buffers-", dir=runtime_path.parent))
    environment = os.environ.copy()
    environment["GXTXT_BRIDGE_WORKSPACE"] = str(_buffer_root)
    environment["GXTXT_BRIDGE_TYPED_DESCRIPTORS"] = "1"
    environment["GXTXT_BRIDGE_CLIENT_OWNS_RESOURCE"] = "1"
    _stderr = open(runtime_path.parent / "bridge.log", "w", encoding="utf-8")
    _process = subprocess.Popen([sys.executable, "-u", str(server), str(runtime_path)],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=_stderr, text=True, encoding="utf-8", env=environment)
    try:
        _request("start", execution=execution)
    except BaseException:
        _deactivate()
        raise


def _deactivate():
    global _process, _stderr, _buffer_root, _buffer_resource, _buffer_manager
    if _process is None:
        return
    try:
        if _process.poll() is None:
            try:
                _request("stop")
            except GXTXTBridgeError:
                pass
        _process.stdin.close()
        _process.stdout.close()
        try:
            _process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _process.terminate()
            _process.wait(timeout=5)
    finally:
        _callbacks.clear()
        _callback_arrays.clear()
        for path in _callback_temporary:
            Path(path).unlink(missing_ok=True)
        _callback_temporary.clear()
        _process = None
        _stderr.close()
        _stderr = None
        if _buffer_resource is not None:
            _buffer_manager.release(_buffer_resource["id"])
            _buffer_manager.cleanup([_buffer_resource["id"]])
        elif _buffer_root is not None:
            import shutil
            shutil.rmtree(_buffer_root)
        _buffer_root = _buffer_resource = _buffer_manager = None


def gxtxt_bridge_info():
    return _request("info")


def gxtxt_context():
    return _request("context")


def gxtxt_api_list():
    return _request("list")


def gxtxt_api_has(api_id):
    return _request("has", api_id=api_id)


def gxtxt_api_describe(api_id):
    return _request("describe", api_id=api_id)


def gxtxt_api_has_operation(api_id, operation):
    return _request("has_operation", api_id=api_id, operation=operation)


_REQUIREMENT = re.compile(r"^([A-Za-z0-9_]+)(?:@([0-9]+))?(?::([A-Za-z0-9._-]+))?(?:\+([A-Za-z0-9_|.-]+))?$")


def gxtxt_api_require(requirements):
    if isinstance(requirements, (str, dict)):
        requirements = [requirements]
    normalized = []
    for item in requirements:
        if isinstance(item, str):
            match = _REQUIREMENT.fullmatch(item.strip())
            if match is None:
                raise GXTXTBridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid required API declaration: {item}")
            api_id, version, provider, capabilities = match.groups()
            item = {"api_id": api_id}
            if version is not None:
                item["api_version"] = int(version)
            if provider is not None:
                item["provider_id"] = provider
            if capabilities is not None:
                item["capabilities"] = capabilities.split("|")
        if not isinstance(item, dict) or "api_id" not in item:
            raise GXTXTBridgeError("GXTXT:ScriptBridge:InvalidArguments", "API requirement needs api_id")
        normalized.append(item)
    temporary = []
    try:
        return _request("require", requirements=[_pack(item, temporary) for item in normalized])
    finally:
        for path in temporary:
            Path(path).unlink(missing_ok=True)


def gxtxt_api_call(api_id, operation, args=None):
    if args is None:
        args = []
    if not isinstance(args, (list, tuple)):
        raise TypeError("GX-TXT API arguments must be a list or tuple")
    temporary = []
    try:
        return _request("call", api_id=api_id, operation=operation,
                        args=[_pack(item, temporary) for item in args])
    finally:
        for path in temporary:
            Path(path).unlink(missing_ok=True)


def gxtxt_callback_register(function):
    if not callable(function):
        raise TypeError("callback registration requires a callable")
    identifier = _request("callback_register")
    _callbacks[identifier] = function
    return CallbackHandle(identifier)


def gxtxt_callback_release(handle):
    if not isinstance(handle, CallbackHandle):
        raise TypeError("callback release requires a CallbackHandle")
    _request("callback_release", id=handle.id)
    _callbacks.pop(handle.id, None)
    for identifier, (owner, value) in list(_callback_arrays.items()):
        if owner == handle.id:
            del _callback_arrays[identifier]


__all__ = ["GXTXTBridgeError", "gxtxt_bridge_info", "gxtxt_context", "gxtxt_api_list",
           "gxtxt_api_has", "gxtxt_api_describe", "gxtxt_api_has_operation",
           "gxtxt_api_require", "gxtxt_api_call", "CallbackHandle",
           "gxtxt_callback_register", "gxtxt_callback_release"]
