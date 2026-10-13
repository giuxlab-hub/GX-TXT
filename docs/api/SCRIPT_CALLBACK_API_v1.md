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
