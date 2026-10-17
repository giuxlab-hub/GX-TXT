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
def invoke(host, operation, args):
    return _stable.invoke_api(_NativeHost(host), "PLOT_DATASET_API_v3", operation, args)
