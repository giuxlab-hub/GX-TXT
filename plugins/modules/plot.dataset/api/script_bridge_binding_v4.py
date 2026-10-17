"""Native Plot Dataset v4 registration, retaining the established Script Bridge contracts."""
from importlib.util import spec_from_file_location, module_from_spec
from pathlib import Path
from copy import deepcopy
_spec = spec_from_file_location("gxtxt_plot_stable_script_contract", Path(__file__).with_name("script_bridge_binding.py"))
_stable = module_from_spec(_spec)
_spec.loader.exec_module(_stable)
REGISTRATION = deepcopy(_stable.V3_REGISTRATION)
REGISTRATION.update(api_id="PLOT_DATASET_API_v4", api_version=4, documentation_ref="docs/api/PLOT_DATASET_API_v4.md")
class _NativeHost:
    def __init__(self, host): self._host=host
    def __getattr__(self, key): return getattr(self._host,key)
    def call(self, command, *args):
        if command == "::GX::modulePublicApiActivate" and args == ("plot.dataset", "PLOT_DATASET_API_v3"):
            return self._host.call(command, "plot.dataset", "PLOT_DATASET_API_v4")
        if command.startswith("::GX::PlotDatasetAPIv3::"):
            command=command.replace("::GX::PlotDatasetAPIv3::", "::GX::PlotDatasetAPIv4::", 1)
        return self._host.call(command,*args)

# Additive exact-cell spec construction. Stable v1/v2/v3 registrations and the
# original v4 operations retain their existing implementation and signatures.
REGISTRATION["operations"]["cell_field_spec"] = {
    "name": "cell_field_spec", "summary": "Construct an exact cell-associated triangular field specification",
    "arguments": [{"name": name, "kind": kind, "required": name != "title"}
                  for name, kind in (("dataset_id", "string"), ("x_variable_id", "string"),
                                     ("y_variable_id", "string"), ("binding", "struct"), ("title", "string"))],
    "result_contract": "PlotSpec with explicit GXTXT_CELL_FIELD_BINDING_v1; no interpolation"}


def _cell_fields(host, value):
    if isinstance(value, dict):
        for key in tuple(value):
            if key == "cell_field" and not isinstance(value[key], dict):
                binding = host.as_dict(value[key])
                if "node_variable_ids" in binding:
                    binding["node_variable_ids"] = host.as_list(binding["node_variable_ids"])
                value[key] = binding
            else:
                value[key] = _cell_fields(host, value[key])
    elif isinstance(value, list):
        value = [_cell_fields(host, item) for item in value]
    return value


def invoke(host, operation, args):
    if operation == "cell_field_spec":
        from gxtxt_script_bridge_server import BridgeError
        if len(args) not in (4, 5) or any(not isinstance(value, str) for value in args[:3]) or not isinstance(args[3], dict) or len(args) == 5 and not isinstance(args[4], str):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "cell_field_spec requires three identity strings, a typed binding and optional title")
        host.call("::GX::modulePublicApiActivate", "plot.dataset", "PLOT_DATASET_API_v4")
        return _cell_fields(host, _stable._plot_spec(host, host.call("::GX::PlotDatasetAPIv4::cellFieldSpec", *args)))
    return _cell_fields(host, _stable.invoke_api(_NativeHost(host), "PLOT_DATASET_API_v3", operation, args))
