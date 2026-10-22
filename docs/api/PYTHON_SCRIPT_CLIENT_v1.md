# Python Script Client v1

SPDX-License-Identifier: GPL-3.0-or-later

`analysis.python_script` runs registered Session `.py` scripts with the
configured `runtime.python`. Import the public `gxtxt` package from the
script. The framework activates and closes its Bridge; user code does not
start a server or reference Tcl, private paths or provider binding files.

For compatibility, Bridge metadata retains the historical
`OCTAVE_SCRIPT_BRIDGE_API_v1` ID. Its provider bindings and transport are
shared by Octave and Python; `supported_languages` and the context's
`script_language` identify the available clients and current execution.

```python
from gxtxt import (
    gxtxt_context, gxtxt_bridge_info, gxtxt_api_list, gxtxt_api_has,
    gxtxt_api_describe, gxtxt_api_has_operation, gxtxt_api_require,
    gxtxt_api_call, GXTXTBridgeError,
    gxtxt_callback_register, gxtxt_callback_release,
)

context = gxtxt_context()
gxtxt_api_require("CANONICAL_DATASET_API_v2@2")
datasets = gxtxt_api_call("CANONICAL_DATASET_API_v2", "list", [])
```

`gxtxt_api_list()` and `gxtxt_api_describe(api_id)` provide machine-readable
provider identity, version, capabilities and structured operation arguments.
`gxtxt_api_has` and `gxtxt_api_has_operation` check registration in the active
Bridge. They do not prove a provider's external runtime is configured, that
the operation accepts the present scientific inputs, or that it is admitted
to the restricted C++ SDK. These are
the same provider-owned descriptors and operations used by Octave. The
machine-readable [coverage inventory](SCRIPT_BRIDGE_COVERAGE_v1.json) records
version-qualified coverage for both languages; use the current Bridge descriptor
for the actual installed registration. A future provider supplies one binding.
See [Script Callback API v1](SCRIPT_CALLBACK_API_v1.md) for functions passed
to mathematical operations.

`gxtxt_api_call(api_id, operation, args)` takes a positional Python list or
tuple. API and operation names must be registered. Unknown/private APIs,
unsupported operations, argument errors and provider failures raise
`GXTXTBridgeError` with a stable identifier and a useful message. Calls
outside an active GX-TXT run raise `GXTXT:ScriptBridge:NotActive`.

## Values

The client carries UTF-8 strings, booleans, exact integer scalars, floating-point
scalars, dictionaries, lists and nested values. Supported NumPy numeric arrays
include boolean, integer, floating-point and complex values. In an active managed
Bridge, arrays with more than 64 elements, or a dtype other than `float64`, use
the existing typed binary descriptor transport. Small `float64` arrays may use
inline values. A one-dimensional NumPy input is represented as a column array;
matrix shape and column-major logical order remain explicit.

The current dtype/shape/exact-integer/complex contract is
[scientific binary descriptor v2](SCIENTIFIC_BINARY_TRANSPORT_v2.md).
The dev093 transport page describes its historical predecessor. Do not infer
that current arrays always narrow to float64. The configured runtime and
operation still determine which input dtypes and scientific shapes are accepted.
Ordinary legacy float64 results can fall back to Python lists when NumPy is
absent; that fallback is not a promise that all typed/complex operations work
without their required runtime support. Scripts do not manage transport files.

```python
import numpy as np

ctx = gxtxt_context()
dataset_id = ctx["inputs"]["primary"]["dataset_id"]
description = gxtxt_api_call("CANONICAL_DATASET_API_v2", "describe", [dataset_id])
block = gxtxt_api_call("CANONICAL_DATASET_API_v2", "read_range",
                       [dataset_id, ["v0001"], 0, int(description["row_count"])])
values = np.asarray(block["v0001"]["values"]).reshape(-1)
```

Each API's own manual defines its operation arguments. The client transports
values and does not import internal GX-TXT implementation modules.

## Required APIs and provenance

Script Registry `required_apis` is checked before Python source executes.
Use semicolon-separated declarations:

```text
CANONICAL_DATASET_API_v2@2;PLOT_DATASET_API_v4@4:plot.dataset+plotspec
```

The optional `@version`, `:provider_id` and `+capability|capability` clauses
require exact matches. `gxtxt_api_require` also accepts Python dictionaries
with `api_id`, `api_version`, `provider_kind`, `provider_id` and
`capabilities`, or a list of declarations. The Session owns an exact source
snapshot with stable ID, language, semantic version, revision and SHA-256;
each execution verifies and records those values, required APIs, actual
Python executable/version, available NumPy/SciPy versions and results.
Editing a user script cannot change its assigned Session copy.

## Outputs and resource policy

`gxtxt_context()` includes Analysis input aliases, typed script parameters,
run identity and `output_dir`. Write a completed scientific file inside that
framework-owned directory and call
`DATASET_FILE_PUBLICATION_API_v1/publish` to retain it as a Canonical Dataset
with source lineage. Structured Datasets use `DATASET_PUBLICATION_API_v2`;
new or rebuilt Viewer scientific 2D/3D graphs use `PLOT_DATASET_API_v4`;
v3 remains deprecated historical compatibility and is denied to new restricted
C++ Viewer authoring. Progress uses `PROGRESS_API_v1`.

Read `PARALLEL_EXECUTION_API_v1/resources` before creating a Python pool:

```python
policy = gxtxt_api_call("PARALLEL_EXECUTION_API_v1", "resources", [])
workers = min(requested, int(policy["default_workers"]),
              int(policy["max_workers"])) if policy["enabled"] else 1
```

`concurrent.futures`, `multiprocessing` and optional researcher libraries
remain normal Python choices. Bound their worker counts, close pools, and use
the serial branch when workers is one. The Bridge exposes policy, never
arbitrary host command execution. The configured runtime supplies optional
scientific packages; a missing import produces the normal Python traceback.

The acceptance example is
[the published Python Script Bridge example](../../examples/scripts/combined_stabilization.py).

## dev093 local bulk transport

The public v1 client calls and complete default results are retained. Large arrays
use scoped binary buffers and a per-job Octave context through existing provider
bindings. The dev093 history describes
that implementation's resource limits, optional Signal uniform grids/result
projection and output bindings. The current additive dtype contract is
[scientific binary descriptor v2](SCIENTIFIC_BINARY_TRANSPORT_v2.md).
