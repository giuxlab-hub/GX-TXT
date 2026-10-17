# Script Callback API v1

SPDX-License-Identifier: GPL-3.0-or-later

`SCRIPT_CALLBACK_API_v1` provides one execution-scoped callback contract for
registered GNU Octave and Python scripts. The public functions are
`gxtxt_callback_register(callable)` and `gxtxt_callback_release(handle)`.
`gxtxt_bridge_info()` reports the callback API ID and version. A handle is
opaque and can be passed as an argument or a field in `gxtxt_api_call`.

```octave
rhs = gxtxt_callback_register(@(t,y) -2*y);
r = gxtxt_api_call('NUMERIC_API_v1','foundation', ...
    {'ode','solve',rhs,[0 1],1,struct('reltol',1e-8)});
gxtxt_callback_release(rhs);
```

```python
from gxtxt import gxtxt_api_call, gxtxt_callback_register, gxtxt_callback_release
rhs = gxtxt_callback_register(lambda t, y: -2*y)
r = gxtxt_api_call("NUMERIC_API_v1", "foundation",
                   ["ode", "solve", rhs, [0., 1.], [1.], {"reltol": 1e-8}])
gxtxt_callback_release(rhs)
```

The Bridge registers an unpredictable callback ID with its live server for
this run. It sends only typed scalar/vector/matrix arguments and receives
typed results. No callback source or interpreter command is serialized.
The server requests evaluations on the existing script process channel;
the callback runs in the originating language runtime. Multiple evaluations
use that same channel and runtime. Callback IDs are checked against the
current run, and release or script shutdown clears them. A released, unknown
or prior-run ID raises `GXTXT:ScriptCallback:UnknownCallback`.

Callback exceptions retain their Octave identifier when supplied; Python
exceptions become `GXTXT:ScriptCallback:Error` with class and message.
`GXTXTBridgeError("GXTXT:ScriptCallback:Cancelled", "reason")` in Python or
`error('GXTXT:ScriptCallback:Cancelled','reason')` in Octave aborts repeated
evaluation. A callback evaluation that does not answer within 120 seconds
fails with `GXTXT:ScriptCallback:Timeout`. Framework script cancellation
terminates the run and its server. Nested Bridge calls from inside a callback
are rejected because the original API call is still in progress.

`NUMERIC_API_v1` accepts handles for foundation ODE RHS, optional ODE
progress/cancel hooks, constrained objective/nonlinear constraint/gradient,
and calculus gradient/Jacobian/Hessian/directional source functions. Its
`nonlinear_fit`, `dataset_nonlinear_fit`, `root_find`, `minimize_1d`, and
`minimize` operations also accept registered handles. A nonlinear constraint
callback returns a struct/dict with `equality` and `inequality` arrays;
inequalities are nonnegative when satisfied. Scalar objectives return a
finite real scalar. ODE RHS returns one finite value per state component.
Model fits return one prediction per observation. Invalid types or shapes
raise `GXTXT:Numeric:*` errors.

The provider's script callback solver uses SciPy in the configured Python
runtime (RK45, SLSQP, bounded/scalar solvers and least squares). Direct
Octave calls retain their existing Octave backend. The callback path is
serial and has a round trip for each evaluation; it suits researcher scale
ODEs, fits and optimizations, but scripts should avoid tiny callbacks over
millions of evaluations. Large numeric values use the existing binary typed
transport. No process or interpreter is created per evaluation.

In dev097, a declared callable in the existing Script Registry can be selected by
a supervised Job. The runner registers its entrypoint after executing the exact
source snapshot, invokes a declared public consumer, and releases the handle.
`SCRIPT_EXECUTION_API_v1/current_callable` exposes its verified provenance and
inert scientific declaration. Consumers retain results under Dataset/Workspace
ownership, never the transient callback handle. See the Script Execution and
Script Job APIs for the host submission and bounded receipt contract.

## Bounded callback data lifetime (dev097)

CORE host adapters may use `host.callback_argument(handle, numeric_array)` as a
context manager for an unchanged argument across an evaluation sequence. The
originating runtime receives its typed array once; subsequent calls refer to
that execution-scoped argument. Python receives a read-only NumPy array; Octave
uses its ordinary copy-on-write numeric value. Leaving the context releases the
cached value, including on errors. Foreign or expired argument handles reject.
This is an internal CORE transport contract, not a second public model registry.

After a consumer materializes a callback result, it calls
`host.release_callback_values(result)`. CORE sends only resource IDs back to the
originating runtime, which deletes only matching files in its own callback-output
allocation list. It does not delete original arguments or unrelated resources.
General Script result descriptor ownership and binary versions remain unchanged.
Callback caches and output files are also cleared by normal callback/runtime
teardown; the existing Job Supervisor owns process-tree cancellation and cleanup.

The existing Numeric callback fitting path uses these adapters: unchanged
predictors are transported once, and each consumed prediction is released before
the next evaluation. ODE, calculus and constrained vector results use the same
output-release helper. Scientific algorithms and statistical interpretation do
not move into CORE transport.
