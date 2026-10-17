#!/usr/bin/env python3
"""CORE transport shared by the Octave and Python script clients.

Bindings are loaded from API-owned files. This transport has no API-specific
dispatch and never accepts a Tcl command name from an Octave caller.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import configparser
import contextlib
import importlib.util
import json
import math
import os
import select
from pathlib import Path
import struct
import sys
import tempfile
import tkinter
import _tkinter
import traceback
import uuid

try:
    import numpy as np
except ImportError:
    np = None


ROOT = Path(__file__).resolve().parents[2]
sys.modules.setdefault("gxtxt_script_bridge_server", sys.modules[__name__])


class CallbackArgument:
    """One consumer-owned constant inside a live callback evaluation sequence."""
    def __init__(self, reference, value):
        self.owner = reference.identifier
        self.value = value
        self.identifier = uuid.uuid4().hex
        self.sent = False
        self.active = True


def _callback_resource_ids(value):
    if isinstance(value, ResourceNumericArray):
        return {value.descriptor['resource_id']}
    if isinstance(value, dict):
        return set().union(*(_callback_resource_ids(v) for v in value.values()))
    if isinstance(value, (list, tuple)):
        return set().union(*(_callback_resource_ids(v) for v in value))
    return set()


class BridgeError(Exception):
    def __init__(self, identifier: str, message: str):
        super().__init__(message)
        self.identifier = identifier


class NumericArray:
    def __init__(self, values, shape=None, dtype=None):
        # Legacy list adapters describe double vectors. Typed source buffers
        # carry their own dtype; scientific casts belong to the math owner.
        if np is not None:
            if dtype is None and not isinstance(values, np.ndarray): dtype = '<f8'
            if dtype == 'bool' and not isinstance(values, np.ndarray):
                # NumPy considers every nonempty string true, including "0".
                tokens = [str(v).lower() for v in values]
                if any(v not in ('0', '1', 'false', 'true') for v in tokens):
                    raise ValueError('invalid canonical boolean token')
                values = [v in ('1', 'true') for v in tokens]
            self.values = np.asarray(values, dtype=dtype).reshape(-1)
            self.dtype = self.values.dtype.name
        else:
            if dtype not in (None, 'float64', '<f8'):
                raise BridgeError('GXTXT:ScriptBridge:Dependency', 'typed arrays require NumPy')
            self.values = [float(v) for v in values]; self.dtype = 'float64'
        self.shape = list(shape if shape is not None else [len(self.values), 1])
        if math.prod(self.shape) != len(self.values):
            raise ValueError("numeric array shape does not match its values")


def numeric_column_tokens(values, dtype):
    """Adapt canonical text cells without conflating missing cells with NaN.

    Float placeholders are NaN and the optional exact missing mask accompanies
    the array. Integer and boolean columns require nonmissing representable
    values; there is no fabricated integer sentinel.
    """
    missing = [str(v).strip() == '' for v in values]
    mask = None
    if any(missing):
        if dtype not in ('float32', 'float64'):
            raise BridgeError('GXTXT:ScriptBridge:Transport', 'Missing integer/boolean cells need a nullable storage contract')
        values = ['nan' if absent else value for value, absent in zip(values, missing)]
        mask = NumericArray(missing, dtype='bool')
    return NumericArray(values, dtype=dtype), mask


class CallbackRef:
    def __init__(self, identifier):
        self.identifier = identifier


class ResourceNumericArray(NumericArray):
    """CORE-owned lazy buffer; a response can forward it without materializing."""
    def __init__(self, host, resource):
        resource = host.as_dict(resource)
        descriptor = {k:resource[k] for k in ('dtype','endian','order','resource_id')}
        descriptor.update({k:int(resource[k]) for k in ('version','count','byte_count')})
        descriptor['shape'] = [int(x) for x in str(resource['shape']).split(';')]
        self._initialize(resource['resource_root'], descriptor)

    @classmethod
    def from_descriptor(cls, root, descriptor):
        value = cls.__new__(cls)
        value._initialize(root, descriptor)
        return value

    def _initialize(self, root, descriptor):
        scope = os.environ.get('GXTXT_BRIDGE_WORKSPACE')
        if not scope or Path(root).resolve() != Path(scope).resolve():
            raise BridgeError('GXTXT:ScriptBridge:Transport', 'Dataset buffer is outside the execution scope')
        from gxtxt_scientific_binary_v1 import validate_buffer
        validate_buffer(root, descriptor)
        self.root = Path(scope)
        self.shape = list(descriptor['shape'])
        self.dtype = descriptor['dtype']
        self.descriptor = dict(descriptor, shape=self.shape)
        self._values = None

    @property
    def values(self):
        if self._values is None:
            from gxtxt_scientific_binary_v1 import read_buffer
            self._values = read_buffer(self.root, self.descriptor).ravel(order='F')
        return self._values


def decode_value(value):
    if not isinstance(value, dict) or "kind" not in value:
        raise BridgeError("GXTXT:ScriptBridge:Transport", "missing typed bridge value")
    kind = value["kind"]
    if kind == "callback":
        return CallbackRef(str(value["id"]))
    if kind == "string":
        return str(value["value"])
    if kind == "logical":
        return bool(value["value"])
    if kind == "integer_scalar":
        return int(value["value"])
    if kind == "numeric_scalar":
        return float(value["value"])
    if kind == "numeric_array":
        shape = [int(x) for x in value["shape"]]
        if "binary" in value:
            from gxtxt_scientific_binary_v1 import wire_descriptor
            descriptor = wire_descriptor(value['binary'])
            root = os.environ.get("GXTXT_BRIDGE_WORKSPACE")
            if not root or descriptor.get("shape") != value['shape']:
                raise BridgeError("GXTXT:ScriptBridge:Transport", "binary argument scope or shape mismatch")
            return ResourceNumericArray.from_descriptor(root, descriptor)
        if "binary_path" in value:
            path = Path(value["binary_path"])
            if path.is_symlink() or not path.is_file() or (hasattr(os, 'getuid') and path.stat().st_uid != os.getuid()):
                raise BridgeError("GXTXT:ScriptBridge:Transport", "legacy numeric resource owner/type mismatch")
            scope = os.environ.get("GXTXT_BRIDGE_WORKSPACE")
            if scope and path.parent.resolve() != Path(scope).resolve():
                raise BridgeError("GXTXT:ScriptBridge:Transport", "numeric resource escapes owned workspace")
            if path.stat().st_size != 8 * math.prod(shape):
                raise BridgeError("GXTXT:ScriptBridge:Transport", "binary numeric payload length mismatch")
            raw = path.read_bytes()
            values = np.frombuffer(raw, dtype="<f8") if np is not None else struct.unpack("<" + "d" * math.prod(shape), raw)
        else:
            values = [float(v) for v in value["values"]]
        return NumericArray(values, shape)
    if kind == "cell":
        return [decode_value(v) for v in value["items"]]
    if kind == "struct":
        return {k: decode_value(v) for k, v in value["fields"].items()}
    if kind == "struct_array":
        return [decode_value(v) for v in value["items"]]
    raise BridgeError("GXTXT:ScriptBridge:Transport", f"unsupported bridge value kind {kind}")


def encode_value(value, arrays=None):
    if arrays is None: arrays = {}
    if isinstance(value, NumericArray):
        key = id(value)
        if key in arrays:
            return {'kind': 'numeric_array_ref', 'array_id': arrays[key]}
        array_id = str(len(arrays)); arrays[key] = array_id
        result = {"kind": "numeric_array", "shape": value.shape, 'array_id': array_id}
        if isinstance(value, ResourceNumericArray) and os.environ.get('GXTXT_BRIDGE_TYPED_DESCRIPTORS') == '1':
            result['binary'] = value.descriptor
            return result
        if len(value.values) > 64 or value.dtype != 'float64':
            scope = os.environ.get("GXTXT_BRIDGE_WORKSPACE")
            if scope and np is not None and os.environ.get("GXTXT_BRIDGE_TYPED_DESCRIPTORS") == "1":
                from gxtxt_scientific_binary_v1 import write_buffer
                result["binary"] = write_buffer(scope, value.values.reshape(value.shape, order="F"))
                return result
            if value.dtype != 'float64':
                raise BridgeError('GXTXT:ScriptBridge:Transport', 'typed result requires descriptor-capable client')
            fd, path = tempfile.mkstemp(prefix="gxtxt-script-result-", suffix=".bin", dir=scope)
            with os.fdopen(fd, "wb") as stream:
                stream.write(value.values.tobytes() if np is not None else struct.pack("<" + "d" * len(value.values), *value.values))
            result["binary_path"] = path
        else:
            result["values"] = [format(v, ".17g") for v in value.values]
        return result
    if isinstance(value, bool):
        return {"kind": "logical", "value": value}
    if isinstance(value, int):
        return {"kind": "integer_scalar", "value": str(value)}
    if isinstance(value, float):
        return {"kind": "numeric_scalar", "value": format(value, ".17g")}
    if isinstance(value, str):
        return {"kind": "string", "value": value}
    if isinstance(value, dict):
        return {"kind": "struct", "fields": {str(k): encode_value(v, arrays) for k, v in value.items()}}
    if isinstance(value, (tuple, list)):
        return {"kind": "cell", "items": [encode_value(v, arrays) for v in value]}
    raise BridgeError("GXTXT:ScriptBridge:Transport", f"unsupported provider result type {type(value).__name__}")


class Host:
    def __init__(self, runtime_path: Path):
        if not runtime_path.is_file():
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "runtime configuration does not exist")
        self.runtime_path = runtime_path.resolve()
        self.config = configparser.ConfigParser(interpolation=None, strict=False)
        self.config.optionxform = str
        with self.runtime_path.open(encoding="utf-8") as stream:
            self.config.read_file(stream)
        self.core_service = self.config.get("runtime", "core_service", fallback="")
        if self.core_service not in ("", "statistical_result_semantics", "scientific_presentation"):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "unknown stateless CORE service")
        self.session = self.config.get("runtime", "session", fallback="")
        if (self.session and not Path(self.session).is_dir()) or (not self.core_service and not self.session):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "runtime Session is unavailable")
        self.module_id = self.config.get("runtime", "module_id", fallback="")
        self.run_id = self.config.get("runtime", "run_id", fallback="") or uuid.uuid4().hex
        self.operation = self.config.get("runtime", "operation", fallback="run")
        self.tcl = tkinter.Tcl()
        with contextlib.redirect_stdout(sys.stderr):
            self.tcl.call("set", "argv0", "__not_main__")
            self.tcl.call("source", str(ROOT / "gxtxt_pipeline.tcl"))
            self.tcl.call("::GX::defaults")
            self.tcl.call("::GX::loadModuleCatalog")
            self.tcl.call("set", "::GX::currentSession", self.session)
            if not self.core_service or (self.core_service == "scientific_presentation" and self.session):
                manifest = Path(self.session) / "metadata" / "manifest.ini"
                if manifest.is_file():
                    self.tcl.call("::GX::loadManifest", str(manifest))
                self.tcl.call("::GX::loadDatasetRegistry", self.session)
            self.tcl.call("set", "::GX::currentSession", self.session)
            # Tcl writes to the process descriptor directly; Python's
            # redirect_stdout cannot protect the JSON response channel.
            self.tcl.eval('''
                rename ::puts ::GX::BridgeOriginalPuts
                proc ::puts {args} {
                    set channelIndex 0
                    if {[lindex $args 0] eq "-nonewline"} {set channelIndex 1}
                    if {[llength $args] == $channelIndex + 1} {
                        set args [linsert $args $channelIndex stderr]
                    } elseif {[lindex $args $channelIndex] eq "stdout"} {
                        lset args $channelIndex stderr
                    }
                    tailcall ::GX::BridgeOriginalPuts {*}$args
                }
            ''')
        self.bindings = {}
        self.modules = {}
        self.handles = {}
        self._bridge_resource = None
        scope = os.environ.get("GXTXT_BRIDGE_WORKSPACE")
        if scope and os.environ.get("GXTXT_BRIDGE_CLIENT_OWNS_RESOURCE") != "1":
            try:
                from gxtxt_resource_manager import ResourceManager
                self._bridge_resource_manager = ResourceManager()
                # The client owns this scope; observation never authorizes deletion.
                self._bridge_resource = self._bridge_resource_manager.observe(scope, "script_bridge", category="temporary", job_id=self.run_id, session=self.session)
            except ImportError:
                pass
        self.callbacks = set()
        self.callback_resources = set()
        self._discover()

    def _discover(self):
        files = list(sorted((ROOT / "core" / "script_bindings").glob("*.py")))
        files += list(sorted((ROOT / "plugins" / "modules").glob("*/api/script_bridge_binding.py")))
        files += list(sorted((ROOT / "plugins" / "modules").glob("*/api/script_bridge_binding_v[0-9]*.py")))
        if self.core_service:
            # Same registration and invocation as real Jobs, without Session
            # creation, callback registration or a numerical worker.
            files = [ROOT / "core" / "script_bindings" / "statistical_result_semantics.py"]
            if self.core_service == "scientific_presentation":
                files.append(ROOT / "core" / "script_bindings" / "dataset_metadata.py")
        for index, path in enumerate(files):
            name = f"gxtxt_script_binding_{index}"
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            registrations = getattr(module, "REGISTRATIONS", None)
            if registrations is None:
                registrations = [module.REGISTRATION]
            for registration in registrations:
                descriptor = dict(registration)
                api_id = descriptor["api_id"]
                if self.core_service == "scientific_presentation" and api_id == "STATISTICAL_RESULT_SEMANTICS_API_v1":
                    descriptor["operations"] = {key: value for key, value in descriptor["operations"].items() if key != "store_columns"}
                if self.core_service == "scientific_presentation" and api_id == "DATASET_METADATA_API_v1":
                    allowed = {"coordinate_snapshot_values", "coordinate_snapshot_view_range", "coordinate_snapshot_affine_plan"}
                    if self.session:
                        allowed.update({"coordinate_read", "coordinate_inspect", "coordinate_validate"})
                    descriptor["operations"] = {key: value for key, value in descriptor["operations"].items() if key in allowed}
                if api_id in self.bindings:
                    raise BridgeError("GXTXT:ScriptBridge:Transport", f"duplicate script binding {api_id}")
                for key in ("api_version", "provider_kind", "provider_id", "documentation_ref", "operations"):
                    if key not in descriptor:
                        raise BridgeError("GXTXT:ScriptBridge:Transport", f"incomplete script binding {api_id}: {key}")
                if descriptor["provider_kind"] == "module":
                    provider = descriptor["provider_id"]
                    module_dir = ROOT / "plugins" / "modules" / provider
                    if path.parent.parent != module_dir:
                        raise BridgeError("GXTXT:ScriptBridge:Transport", f"binding ownership mismatch for {api_id}")
                    declared = configparser.ConfigParser(interpolation=None)
                    declared.read(module_dir / "module.ini", encoding="utf-8")
                    section = f"public_api.{api_id}"
                    ids = declared.get("public_apis", "ids", fallback="").split(";")
                    if api_id not in ids or not declared.has_section(section):
                        raise BridgeError("GXTXT:ScriptBridge:Transport", f"{provider} does not declare {api_id}")
                    actual_version = declared.getint(section, "api_version", fallback=-1)
                    if actual_version != descriptor["api_version"]:
                        raise BridgeError("GXTXT:ScriptBridge:Transport", f"API version mismatch for {api_id}")
                    descriptor["capabilities"] = [item for item in declared.get(section, "capabilities", fallback="").split(";") if item]
                descriptor.setdefault("capabilities", [])
                descriptor["script_available"] = True
                for op_id, op in descriptor["operations"].items():
                    if (not isinstance(op, dict) or op.get("name") != op_id or
                        "arguments" not in op or "result_contract" not in op or "summary" not in op):
                        raise BridgeError("GXTXT:ScriptBridge:Transport", f"invalid operation descriptor {api_id}/{op_id}")
                self.bindings[api_id] = descriptor
                self.modules[api_id] = module

    def require(self, requirements):
        if not isinstance(requirements, list):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "requirements must be a cell/list")
        for item in requirements:
            if isinstance(item, str):
                item = {"api_id": item}
            if not isinstance(item, dict) or not item.get("api_id"):
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "each API requirement needs api_id")
            api_id = item["api_id"]
            descriptor = self.bindings.get(api_id)
            if descriptor is None:
                raise BridgeError("GXTXT:ScriptBridge:UnknownAPI", f"required script-callable API is unavailable: {api_id}")
            for key in ("api_version", "provider_kind", "provider_id"):
                if key in item and (float(item[key]) != float(descriptor[key]) if key == "api_version" else str(item[key]) != str(descriptor[key])):
                    requested = int(item[key]) if key == "api_version" else item[key]
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"required {api_id} {key}={requested} is unavailable (found {descriptor[key]})")
            requested = item.get("capabilities", [])
            if isinstance(requested, str):
                requested = [requested]
            for capability in requested:
                if capability not in descriptor["capabilities"]:
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"required {api_id} capability is unavailable: {capability}")
        return True

    def tcl_arg(self, value):
        if np is not None and isinstance(value, np.ndarray):
            # Legacy provider adapters may pass the NumericArray buffer onward.
            # Preserve its full shape instead of NumPy's abbreviated text display.
            value = NumericArray(value.ravel(order="F"), list(value.shape))
        if isinstance(value, _tkinter.Tcl_Obj):
            return value
        if isinstance(value, NumericArray):
            flat = value.values
            text_number = (lambda x: str(int(x))) if value.dtype.startswith(('int', 'uint')) or value.dtype == 'bool' else (lambda x: '-0.0' if value.dtype.startswith('float') and x == 0 and math.copysign(1.0, float(x)) < 0 else format(x, '.17g'))
            if len(value.shape) == 2 and value.shape[0] > 1 and value.shape[1] > 1:
                rows, columns = value.shape
                return tuple(tuple(text_number(flat[r + rows * c]) for c in range(columns)) for r in range(rows))
            return tuple(text_number(v) for v in flat)
        if isinstance(value, dict):
            fields = []
            for key, item in value.items():
                fields.extend((str(key), self.tcl_arg(item)))
            return tuple(fields)
        if isinstance(value, (list, tuple)):
            return tuple(self.tcl_arg(item) for item in value)
        if isinstance(value, bool):
            return "1" if value else "0"
        if isinstance(value, float) and value == 0 and math.copysign(1.0, value) < 0:
            return "-0.0"
        if isinstance(value, float) and math.isfinite(value) and value.is_integer():
            return str(int(value))
        return str(value)

    def dataset_private_context(self):
        """Bind metadata writes to the CORE runtime identity, never RPC arguments."""
        if not hasattr(self, "_dataset_private_owner"):
            if not self.module_id:
                raise BridgeError("GXTXT:ScriptBridge:Ownership", "private metadata writes require a runtime module identity")
            self._dataset_private_owner = self.as_dict(
                self.call("::GX::_datasetPrivateModuleContext", self.module_id))
        return self._dataset_private_owner

    def call(self, command, *args):
        return self.tcl.call(command, *(self.tcl_arg(arg) for arg in args))

    def as_list(self, value):
        return list(self.tcl.splitlist(value))

    def as_dict(self, value):
        parts = self.as_list(value)
        if len(parts) % 2:
            raise BridgeError("GXTXT:ScriptBridge:RemoteError", "public API returned an invalid dictionary")
        return {self.tcl.call("format", "%s", parts[i]): self.tcl.call("format", "%s", parts[i + 1])
                if isinstance(parts[i + 1], _tkinter.Tcl_Obj) else parts[i + 1]
                for i in range(0, len(parts), 2)}

    def normalize(self, value):
        """Preserve nested Tcl dict/list types across the script transport."""
        if isinstance(value, _tkinter.Tcl_Obj):
            if value.typename == "dict":
                keys = self.tcl.call("dict", "keys", value)
                return {str(self.tcl.call("format", "%s", key)): self.normalize(self.tcl.call("dict", "get", value, key))
                        for key in self.tcl.splitlist(keys)}
            if value.typename == "list":
                return [self.normalize(item) for item in self.tcl.splitlist(value)]
            return str(value)
        if isinstance(value, (tuple, list)):
            return [self.normalize(item) for item in value]
        if isinstance(value, dict):
            return {str(key): self.normalize(item) for key, item in value.items()}
        return value

    def persist_manifest(self, action):
        manifest = Path(self.session) / "metadata" / "manifest.ini"
        self.call("::GX::writeManifest", str(manifest))
        (manifest.parent / ".script_bridge_graph_update").write_text(action + "\n", encoding="ascii")

    def context(self, execution):
        inputs = {}
        parameters = {}
        for section in self.config.sections():
            if section.startswith("script_parameter.") and section.count(".") == 1:
                name = section.split(".", 1)[1]
                kind = self.config.get(section, "type", fallback="string")
                value = self.config.get(section, "value", fallback="")
                if kind == "integer" and value != "":
                    value = int(value)
                elif kind in ("number", "double") and value != "":
                    value = float(value)
                elif kind == "boolean":
                    value = value.lower() in ("1", "true", "yes", "on")
                parameters[name] = value
                continue
            if not section.startswith("analysis_source.") or section.count(".") != 1:
                continue
            alias = section.split(".", 1)[1]
            inputs[alias] = {"alias": alias,
                             "source_id": self.config.get(section, "source_id", fallback=alias),
                             "dataset_id": self.config.get(section, "dataset_id", fallback=""),
                             "contract": self.config.get(section, "kind", fallback="")}
        for section in self.config.sections():
            if not section.startswith("repeatable_config.") or section.count(".") != 1:
                continue
            name = section.split(".", 1)[1]
            rows = [row for row in self.config.get(section, "rows", fallback="").split(";") if row]
            columns = [column for column in self.config.get(section, "columns", fallback="").split(";") if column]
            parameters[name] = [
                {"row_id": row, **{column: self.config.get(f"{section}.{row}", column, fallback="")
                                   for column in columns}}
                for row in rows
            ]
        for section in self.config.sections():
            if section.startswith("job_input."):
                alias = section[len("job_input."):]
                inputs[alias] = {"alias": alias, **dict(self.config.items(section))}
                if "revision_base64" in inputs[alias]:
                    inputs[alias]["revision"] = base64.b64decode(inputs[alias].pop("revision_base64"), validate=True).decode("utf-8")
        output = dict(self.config.items("job_output")) if self.config.has_section("job_output") else {}
        if "replace_owned" in output:
            output["replace_owned"] = output["replace_owned"].lower() in ("1", "true", "yes", "on")
        return {"output": output, "bridge_api_id": "OCTAVE_SCRIPT_BRIDGE_API_v1", "bridge_api_version": 1,
                "module_id": self.module_id, "run_id": self.run_id, "operation": self.operation,
                "script_language": self.config.get("config", "script_language", fallback="Octave"),
                "output_dir": self.config.get("runtime", "output_dir", fallback=""),
                "bundle_dir": self.config.get("config", "bundle_dir", fallback=""),
                "public_operation": self.config.get("config", "public_operation", fallback=""),
                "script_name": execution["script_name"],
                "script_sha256": execution["script_sha256"],
                "arguments_raw": execution["arguments_raw"], "parameters": parameters,
                "inputs": inputs}

    def record_publications(self, receipt):
        """Provider bindings report committed receipts, never requested outputs."""
        ids = []
        if isinstance(receipt, dict):
            if receipt.get("dataset_id"): ids.append(str(receipt["dataset_id"]))
            ids.extend(str(x) for x in receipt.get("dataset_ids", []))
        if not ids: return receipt
        output = Path(self.config.get("runtime", "output_dir", fallback=str(self.runtime_path.parent)))
        path = output / "published_datasets.json"
        existing = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
        merged = list(dict.fromkeys(existing + ids))
        temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(merged, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        return receipt

    def validate_inputs(self):
        # Input aliases are immutable submission snapshots. Revision authority
        # remains CORE Dataset Publication/Registry, never a Bridge sidecar.
        for section in self.config.sections():
            if section.startswith("job_input."):
                dataset_id = self.config.get(section, "dataset_id")
                revision = self.config.get(section, "revision")
                if self.config.has_option(section, "revision_base64"):
                    revision = base64.b64decode(self.config.get(section, "revision_base64"), validate=True).decode("utf-8")
                token = self.call("::GX::datasetRevisionToken", dataset_id, self.session)
                current = str(self.tcl.call("format", "%s", token))
                if current != revision:
                    raise BridgeError("GXTXT:ScriptBridge:StaleInput", f"Dataset input {section[10:]} changed after submission")

    def cleanup(self):
        self.callbacks.clear()
        # Observed Octave client buffers remain client-owned; normal client
        # shutdown removes them. The manager reconciles observation/liveness.
        self._bridge_resource = None
        worker = self.handles.pop("scientific_binary_worker", None)
        if worker is not None:
            worker.close()
        for module in self.modules.values():
            if hasattr(module, "cleanup"):
                module.cleanup(self)

    def _callback_event(self, event):
        sys.__stdout__.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.__stdout__.flush()

    @contextlib.contextmanager
    def callback_argument(self, reference, value):
        if not isinstance(reference, CallbackRef) or reference.identifier not in self.callbacks:
            raise BridgeError('GXTXT:ScriptCallback:UnknownCallback', 'Cannot retain an argument for an expired callback')
        if not isinstance(value, NumericArray):
            raise BridgeError('GXTXT:ScriptCallback:InvalidArguments', 'Constant callback arguments must be typed numeric arrays')
        argument = CallbackArgument(reference, value)
        try:
            yield argument
        finally:
            argument.active = False
            if argument.sent:
                self._callback_event({'event': 'callback_arguments_release', 'ids': [argument.identifier]})

    def release_callback_values(self, value):
        # Only the originating client deletes files it allocated for callback
        # outputs. Borrowed arguments and unrelated scientific resources remain.
        ids = _callback_resource_ids(value) & self.callback_resources
        if ids:
            self._callback_event({'event': 'callback_buffers_release', 'ids': sorted(ids)})
            self.callback_resources.difference_update(ids)

    def invoke_callback(self, reference, *args):
        if not isinstance(reference, CallbackRef) or reference.identifier not in self.callbacks:
            raise BridgeError("GXTXT:ScriptCallback:UnknownCallback", "callback is unknown, released, or belongs to another execution")
        encoded = []
        for arg in args:
            if isinstance(arg, CallbackArgument):
                if not arg.active or arg.owner != reference.identifier:
                    raise BridgeError('GXTXT:ScriptCallback:InvalidArguments', 'Constant argument belongs to another callback')
                wire = {'kind': 'callback_array', 'id': arg.identifier}
                if not arg.sent:
                    wire['value'] = encode_value(arg.value)
                    arg.sent = True
                encoded.append(wire)
            else:
                encoded.append(encode_value(arg))
        self._callback_event({"event": "callback_invoke", "id": reference.identifier, "args": encoded})
        if not select.select([sys.stdin], [], [], 120)[0]:
            self.callbacks.discard(reference.identifier)
            raise BridgeError("GXTXT:ScriptCallback:Timeout", "callback evaluation timed out")
        line = sys.stdin.readline()
        if not line:
            self.callbacks.discard(reference.identifier)
            raise BridgeError("GXTXT:ScriptCallback:Transport", "script runtime closed during callback")
        try:
            response = json.loads(line)
            if response.get("action") != "callback_result" or response.get("id") != reference.identifier:
                raise ValueError("callback response identity mismatch")
            if not response.get("ok"):
                raise BridgeError(response.get("identifier", "GXTXT:ScriptCallback:Error"),
                                  response.get("message", "callback failed"))
            result = decode_value(response["value"])
            self.callback_resources.update(_callback_resource_ids(result))
            return result
        except (ValueError, KeyError) as exc:
            raise BridgeError("GXTXT:ScriptCallback:Transport", str(exc)) from exc


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: gxtxt_script_bridge_server.py <runtime-config>")
    host = Host(Path(sys.argv[1]))
    active = False
    execution = None
    for line in sys.stdin:
        # A new top-level request follows the client's cleanup of all previous
        # callback output files. Keep no stale lease identifiers between calls.
        host.callback_resources.clear()
        request = {}
        try:
            request = json.loads(line)
            action = request.get("action", "")
            if host.core_service and action not in ("start","stop","info","list","require","has","describe","has_operation","call"):
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "stateless CORE service does not expose execution or callback actions")
            if action == "start":
                if active:
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "bridge is already active")
                execution = request.get("execution")
                if not isinstance(execution, dict) or any(k not in execution for k in ("script_name", "script_sha256", "arguments_raw")):
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "execution metadata is incomplete")
                active = True
                value = True
            elif not active:
                raise BridgeError("GXTXT:ScriptBridge:NotActive", "Script Bridge is not active")
            elif action == "stop":
                host.cleanup()
                active = False
                value = True
            elif action == "callback_register":
                identifier = uuid.uuid4().hex
                host.callbacks.add(identifier)
                value = identifier
            elif action == "callback_release":
                identifier = str(request.get("id", ""))
                if identifier not in host.callbacks:
                    raise BridgeError("GXTXT:ScriptCallback:UnknownCallback", "callback is unknown, released, or belongs to another execution")
                host.callbacks.remove(identifier)
                value = True
            elif action == "info":
                value = {"api_id": "OCTAVE_SCRIPT_BRIDGE_API_v1", "api_version": 1,
                         "transport_version": 2, "binary_descriptor_versions": [1, 2], "active": True,
                         "callback_api_id": "SCRIPT_CALLBACK_API_v1", "callback_api_version": 1,
                         "supported_languages": ["Octave", "Python"],
                         "registered_api_count": len(host.bindings)}
                value["execution_profile"] = "stateless_core_service" if host.core_service else "module_execution"
                value["callbacks_supported"] = not bool(host.core_service)
                value['callback_constant_arguments'] = not bool(host.core_service)
                value['callback_output_release'] = not bool(host.core_service)
                if host.core_service:
                    value["session_bound"] = bool(host.session)
                    value["core_service"] = host.core_service
                    value.pop("callback_api_id")
                    value.pop("callback_api_version")
            elif action == "context":
                value = host.context(execution)
            elif action == "list":
                value = [{k: v for k, v in descriptor.items() if k != "operations"}
                         for descriptor in host.bindings.values()]
            elif action == "require":
                value = host.require([decode_value(item) for item in request.get("requirements", [])])
            elif action in ("has", "describe", "has_operation", "call"):
                api_id = request.get("api_id", "")
                if action == "has":
                    value = api_id in host.bindings
                elif api_id not in host.bindings:
                    raise BridgeError("GXTXT:ScriptBridge:UnknownAPI", f"unknown script-callable API {api_id}")
                elif action == "describe":
                    value = host.bindings[api_id]
                else:
                    operation = request.get("operation", "")
                    descriptor = host.bindings[api_id]
                    if action == "has_operation":
                        value = operation in descriptor["operations"]
                    elif operation not in descriptor["operations"]:
                        raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", f"{api_id}/{operation} is not registered")
                    else:
                        host.validate_inputs()
                        args = [decode_value(arg) for arg in request.get("args", [])]
                        try:
                            with contextlib.redirect_stdout(sys.stderr):
                                module = host.modules[api_id]
                                if hasattr(module, "invoke_api"):
                                    value = module.invoke_api(host, api_id, operation, args)
                                else:
                                    value = module.invoke(host, operation, args)
                        except BridgeError:
                            raise
                        except Exception as exc:
                            raise BridgeError("GXTXT:ScriptBridge:RemoteError", f"{api_id}/{operation}: {exc}") from exc
            else:
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"unknown bridge action {action}")
            response = {"ok": True, "value": encode_value(value)}
        except BridgeError as exc:
            response = {"ok": False, "identifier": exc.identifier, "message": str(exc)}
        except Exception as exc:
            print(traceback.format_exc(), file=sys.stderr)
            response = {"ok": False, "identifier": "GXTXT:ScriptBridge:Transport", "message": str(exc)}
        sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        if request.get("action") == "stop":
            break
    host.cleanup()


if __name__ == "__main__":
    main()
