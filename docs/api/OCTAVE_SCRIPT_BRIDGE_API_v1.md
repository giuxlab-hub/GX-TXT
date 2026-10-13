# Octave Script Bridge API v1

SPDX-License-Identifier: GPL-3.0-or-later

`OCTAVE_SCRIPT_BRIDGE_API_v1` lets a user-authored GNU Octave `.m` script
discover and call GX-TXT public APIs registered for script use. The
`analysis.octave_script` runner starts and stops the bridge around each user
script. Scripts should not call those lifecycle functions themselves.

## Stable Octave functions

```octave
info = gxtxt_bridge_info();
apis = gxtxt_api_list();
yes = gxtxt_api_has(api_id);
descriptor = gxtxt_api_describe(api_id);
yes = gxtxt_api_has_operation(api_id, operation);
yes = gxtxt_api_require(requirements);
result = gxtxt_api_call(api_id, operation, args);
context = gxtxt_context();
handle = gxtxt_callback_register(function_handle);
gxtxt_callback_release(handle);
```

`args` is a cell array of positional values. Operation names, argument
conventions and result conventions belong to the corresponding public API
manual. `gxtxt_api_describe` returns the API ID, version, provider kind and
ID, documentation reference, and operation descriptors with name, summary,
argument convention and result convention. `gxtxt_api_list` returns a cell
of scalar API descriptor structs and lists only registered script-callable
APIs. An unregistered API makes `gxtxt_api_has` return false and a call fail.
Each operation descriptor now includes structured `arguments` with name,
kind and required status, plus `result_contract`, summary, API version,
provider identity, capabilities and `script_available`. Provider manuals own
operation-specific options, enumerations and unit behavior. The current
machine-readable coverage/status inventory is
[`SCRIPT_BRIDGE_COVERAGE_v1.json`](SCRIPT_BRIDGE_COVERAGE_v1.json).
The execution-scoped callable contract is [Script Callback API v1](SCRIPT_CALLBACK_API_v1.md).

```octave
if (!gxtxt_api_has('NUMERIC_API_v1'))
  error('This script requires NUMERIC_API_v1');
endif
if (!gxtxt_api_has_operation('NUMERIC_API_v1', 'array_binary'))
  error('The required numerical operation is unavailable');
endif
a = struct('kind', 'vector', 'value', [1; 2; 3]);
b = struct('kind', 'scalar', 'value', 4);
r = gxtxt_api_call('NUMERIC_API_v1', 'array_binary', {'multiply', a, b});
```

The bridge has no API-specific dispatch table. Each public API provider owns
its script binding and its operation metadata. Installing another registered
provider makes that API available on the next bridge start without changing
bridge code. A provider can be CORE or an installed module.
Module bindings are accepted only when their owning `module.ini` declares the
exact public API ID and version. A duplicate, stale, or incomplete binding
fails Bridge startup with a diagnostic.

## Required API declarations

The Script Workspace `required_apis` field is checked before the research
script runs. It accepts semicolon or comma separated declarations in these
forms:

```text
CANONICAL_DATASET_API_v2
PLOT_DATASET_API_v3@3
PLOT_DATASET_API_v3@3:plot.dataset+plotspec|render
```

The suffixes require exact API version, provider ID, and one or more
capabilities. A script may also call `gxtxt_api_require` with a cell of
declarations or scalar structs containing `api_id`, optional `api_version`,
`provider_kind`, `provider_id`, and `capabilities`. A missing identity or
capability raises an explicit error. Validation precedes scientific execution
in the standard script runner.

## Research workflow services

The Bridge currently binds Canonical Dataset, Variable Schema, Metadata,
Selection, Temporal Set lifecycle, Table Stream, Dataset and completed-file
Publication, Unit Registry, NUMERIC_API, Plot Dataset v2/v3, Graph Series
lifecycle, Graph Workflow state, Level Scale presentation, Contract Registry
reads, Plot Variant discovery, Viewer Provider scene/layer services, Native 3D
source identity, Interactive Document reads, Session inspection/commit, Project
inspection, progress, parallel resource policy, Scientific Reference Library reads/ranking, public
documentation, semantics and module API discovery. `PLOT_DATASET_API_v3` is
the current plot facade; `upsert_plot` scopes the provider key to the running
script module and returns a persistent Plot reference. The public Viewer
Provider creates scientific scenes and layers without native protocol calls.

The test workflows under `validation/gxtxt_script_bridge/` show complete
Dataset/numeric/publication/plot, Temporal Set/parallel and Viewer scripts.
Parallel callback/process command builders and live Native 3D renderer
controls remain host-side because they require host-owned command prefixes or
a live GUI. The Script Bridge exposes parallel resource limits and the
framework still manages the script process cancellation lifecycle.

## Values and transport

The bridge transports UTF-8 strings, logical and numeric scalars, numeric
vectors and matrices with shape, empty numeric arrays, cells, scalar
structs, lists of structs, nested combinations of these values, and opaque
UTF-8 tokens. Numeric arrays above 10,000 elements use a private typed
binary block. Strings, empty arrays, empty cells and empty structs remain
distinct. A script receives ordinary Octave values and does not manage
transport files.

## Execution context

`gxtxt_context()` returns `bridge_api_id`, `bridge_api_version`,
`module_id`, `run_id`, `operation`, `script_name`, `script_sha256`,
`arguments_raw`, `output_dir`, and `inputs`. Each input alias has its alias/source ID,
selected `dataset_id`, and contract/kind when available. Dataset IDs are
stable logical bindings; the context omits Session and Dataset storage
paths. `output_dir` is the current framework-owned script execution directory
for completed files intended for public file publication. An optional source
can have an empty Dataset ID. Python consumes the same provider bindings
through the [Python Script Client](PYTHON_SCRIPT_CLIENT_v1.md).

The module runner calls `gxtxt_script_bridge_start(runtime_config_path,
execution_metadata)` once before executing the exact script snapshot and
`gxtxt_script_bridge_stop()` during success or error cleanup. A second start
while active fails. After stop, all normal bridge calls fail with
`GXTXT:ScriptBridge:NotActive` until the next start. Open managed Dataset
publication writers are aborted on bridge stop.

## Errors and public boundary

Unknown APIs and operations, invalid arguments, transport faults, and
provider failures raise Octave errors. The stable bridge identifiers are
`GXTXT:ScriptBridge:NotActive`, `UnknownAPI`, `UnknownOperation`,
`InvalidArguments`, `Transport`, and `RemoteError`. A provider error cannot
be mistaken for an empty successful result. Diagnostic messages include the
API ID and operation when applicable.

`gxtxt_api_call` accepts only exact API and operation names from the
provider-owned registry. It cannot evaluate Tcl, source files, call an
arbitrary `::GX::*` command, or invoke a private CORE operation. This
restriction applies to the bridge; it is not an Octave process sandbox.

## Provider maintenance

A script binding registers `api_id`, `api_version`, `provider_kind`,
`provider_id`, `documentation_ref`, and operation descriptors. Each
descriptor declares at least `name`, `summary`, `argument_convention`, and
`result_convention`. A CORE API owns its binding under
`core/script_bindings/`; a module API owns its binding under its module's
`api/` directory. The API's own manual must document every script-callable
operation. The bridge manual describes the stable generic transport and
does not enumerate installed provider APIs.

## GX-TXT dev-037 operation coverage and nested values

The authoritative `SCRIPT_BRIDGE_COVERAGE_v1.json` records public operations individually as `script_callable`, `intentionally_host_only`, `intentionally_not_script_safe`, or `not_yet_bridged`. Non-callable operations include reasons. `validation/dev037_bridge/coverage_consistency.py` compares the registered Bridge operations with that inventory, the seven public Tcl provider surfaces completed in dev-037, and 15 other current public API manuals. Provider-owned bindings expose one operation name and positional argument schema to both Octave/MATLAB and Python through the same typed transport. The dev-037 Plot Dataset v3 and changed CORE bindings use recursive Tcl dictionary/list normalization before typed encoding, including render/rerender artifacts and Temporal Set members. Other provider bindings retain their own documented result conversion. Public lifecycle and ownership rules remain in the corresponding API manuals.

## Combined stabilization additions (dev-051)

Both Python and Octave clients can call graph `presentation_set` (2-D/3-D aspect and background), Plot Annotation CRUD, Graph Notes and Graph Metadata, Dataset `publish_series`, completed-file `publish_auto`, and Numerical `curve_model_fit`, `curve_model_evaluate`, `curve_model_project`. Provider registrations remain the callable authority; see the regenerated coverage JSON and `examples/scripts/combined_stabilization.py` / `.m`. Portable Resource import/export remains host-only. SB-014 detached snapshot/path operations remain deferred.

Namespaced metadata keys are preserved exactly. In Octave use dynamic fields, for example `metadata.('experimental.sample')`; the response decoder disables JSON field-name rewriting. Tcl dictionary keys are serialized as their string identity, including annotation `id`.

```octave
ref = struct('kind','provider','module_id','plot.dataset','graph_id','plot.dataset.xy','variant_id','p0001');
gxtxt_api_call('GRAPH_WORKFLOW_API_v1','presentation_set',{'plot.dataset','plot.dataset.xy','p0001',struct('xy_aspect_mode','xy_equal','background','transparent')});
gxtxt_api_call('GRAPH_NOTES_API_v1','write',{ref,'# Measured response'});
gxtxt_api_call('PLOT_ANNOTATION_API_v1','add',{'plot.dataset','plot.dataset.xy','p0001',struct('type','text','x',0.2,'y',0.8,'text','Fit')});
```


Dev092: native integer scalar arguments retain integer transport. Integer receipts
below flintmax keep the existing double convention; larger int64/uint64 identities
round-trip exactly as native integer scalars, including Native2D constituent IDs.

## dev093 local bulk transport

The public v1 API and complete default results are retained. Large arrays use
scoped binary buffers and a per-job Octave context through the existing provider
bindings. See `docs/api/SCIENTIFIC_BINARY_TRANSPORT_dev093.md` for shape, dtype,
resource limits, optional Signal uniform grids/result projection and output bindings.
