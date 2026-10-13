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
`gxtxt_api_has` and `gxtxt_api_has_operation` check availability. These are
the same provider-owned descriptors and operations used by Octave. The
machine-readable [coverage inventory](SCRIPT_BRIDGE_COVERAGE_v1.json) marks
availability for both languages. A future provider supplies one binding.
See [Script Callback API v1](SCRIPT_CALLBACK_API_v1.md) for functions passed
to mathematical operations.

`gxtxt_api_call(api_id, operation, args)` takes a positional Python list or
tuple. API and operation names must be registered. Unknown/private APIs,
unsupported operations, argument errors and provider failures raise
`GXTXTBridgeError` with a stable identifier and a useful message. Calls
outside an active GX-TXT run raise `GXTXT:ScriptBridge:NotActive`.

## Values

The client carries UTF-8 strings, booleans, integers, floating-point
scalars, dictionaries, lists, nested values and numeric vectors/matrices.
Numeric arrays returned by public APIs are NumPy `ndarray` values when NumPy
is installed in the configured runtime. Without NumPy they are Python lists;
the script may convert them itself. NumPy arrays passed to an operation keep
their shape, including column-major matrix transport compatible with Octave.
Arrays over 10,000 elements reuse the Bridge's private little-endian float64
binary payload. A script never manages transport files. Integer scalars retain
integer identity; numeric array transport uses float64, as in the existing
Bridge contract.

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
CANONICAL_DATASET_API_v2@2;PLOT_DATASET_API_v3@3:plot.dataset+plotspec
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
graphs use `PLOT_DATASET_API_v3`; progress uses `PROGRESS_API_v1`.

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

The public v1 API and complete default results are retained. Large arrays use
scoped binary buffers and a per-job Octave context through the existing provider
bindings. See `docs/api/SCIENTIFIC_BINARY_TRANSPORT_dev093.md` for shape, dtype,
resource limits, optional Signal uniform grids/result projection and output bindings.
