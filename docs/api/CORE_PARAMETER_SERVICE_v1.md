# CORE Parameter Service v1 — dev-065

The portable C99 library `core/parameters/gx_parameters.c` is the sole new named
numeric-expression authority. It has no Tcl, UI, filesystem or process dependency.
CMake builds its static library and the host Tcl adapter (matching Tcl
headers/library required). Linux is built and tested; Windows uses the same C99
sources and CMake project, but no Windows binary is included or claimed tested.

## C contract

Include `gx_parameters.h`. `gp_create(session)` allocates a context with a borrowed
Session parent; destroy local contexts before their parent with `gp_destroy`.
`gp_define(context,name,formula)` creates or updates by stable, case-sensitive name.
`gp_remove` stages deletion. `gp_recalculate` validates/evaluates the full batch;
`gp_lookup` and `gp_evaluate` recalculate before returning a finite double.
`gp_count`, `gp_name`, `gp_formula`, `gp_dependencies` enumerate sorted names and
borrowed strings. `gp_diagnostic` returns the last failure explanation. Names,
formulas and dependency strings remain owned by the context. Mutation invalidates
borrowed pointers. C return values are 1 success / 0 failure. C mutations are
staged: hosts build and validate a candidate, then publish it on success.

Names are ASCII identifiers, at most 127 characters. `pi`, `e`, and `session` are
reserved. Expressions support decimal/scientific literals, parentheses, unary
signs, `+ - * / ^`; power is right-associative, before unary minus (`-2^2 = -4`).
Functions: sqrt, abs, sin, cos, tan, asin, acos, atan, exp, log, log10, floor, ceil,
min, max, pow, atan2. Trigonometric inputs/outputs use radians. Local names resolve
in the current context; `session.name` explicitly reads the Session parent.
Session expressions use ordinary local names. No other namespace lookup, Tcl
substitution, scripting, assignment, conditionals or implicit unit conversion is
performed. Unknown names, cycles, division by zero, invalid arity/syntax/domain and
non-finite results fail with diagnostics. Deterministic sorted traversal plus DFS
colors evaluates dependencies. Limits: 4096 parameters, 4096 expression characters,
128 expression/dependency nesting depth. Dependency receipts contain direct names;
repeated references can repeat in the native list (the Bridge normalizes duplicates).

## Host and module APIs

`::GX::parameterModuleRegister definitions` must run during trusted module
activation/dispatch. Existing Dataset Private Metadata module identity supplies
the owner and capability automatically. There is no namespace argument.
Definitions map name to a dict containing `formula` and optional `label`,
`description`, `unit`, `type` (number/integer), `min`, `max`, `editable`.
Unit is descriptive metadata; each consumer must explicitly define its numeric
unit convention. The existing Unit Registry retains conversion authority.

`parameterContext capability ?workspace_id?` creates a Session-bound handle.
`parameterContextInfo`, `parameterDefinitions`, `parameterList`,
`parameterEvaluate handle expression`, `parameterSet handle name definition` and
`parameterDelete handle name` provide lifecycle operations. Declared defaults are
merged with canonical saved state; declared parameters cannot be deleted, and
noneditable parameters cannot be changed. User-created parameters support deletion
when no remaining expression depends on them. Framework-generated handles reject
foreign Workspace ownership, stale Sessions and another active module's identity.
These are host/module capability boundaries, not a sandbox for malicious Tcl
plugins with arbitrary process access.

Session administration is `parameterSessionSet`, `parameterSessionDelete`,
`parameterSessionDefinitions`, `parameterSessionList`, `parameterSessionEvaluate`.
Active module callbacks cannot administer Session parameters. List includes formula,
value and dependencies; invalid edits return diagnostics and retain prior state.
Session/module state lives in Manifest `[core_parameters]`; Workspace state lives
in canonical Interactive Document `payload.workspace_metadata.parameters`.
There is no second parameter document store. Existing provider saves preserve this
metadata. Session changes validate dependent stored parameter definitions; open
consumers subscribe for atomic recalculation. Closed Workbench geometry recalculates
when reopened. Invalid saved geometry bindings report an error rather than silently
ignoring the expression.

`parameterSubscribe handle callback` registers a consumer. CORE invokes listeners
for the same Workspace scope even when another handle changed it. A successful
callback returns a rollback command; errors restore parameters and canonical
Workspace payloads plus already-applied consumers. `parameterUnsubscribe` removes
it. `parameterApplyDimensions handle native_scene rule_expression_dict` evaluates
all bindings and calls the reusable Native2D atomic dimension batch. Workbench
keeps expression bindings in existing constraint records; Native2D owns the solve.

## Workspace actions and exposure

`SESSION_ACTION_PROVIDER_API_v1` now also reads `[workspace_actions] api_version=1`
and `ids`, with `[workspace_action.ID]` fields `provider`, `public_api`, `command`,
`name`. `sessionWorkspaceActions workspace_id` discovers trusted owner/provider
actions. `sessionWorkspaceActionInvoke workspace_id action_id` activates the
module, establishes its automatic parameter context and dispatches
`command workspace_id context_handle` under trusted identity. Existing
`SESSION_WORKSPACE_API_v1` opening establishes/validates the context too.
Workbench's Parameters action uses this same infrastructure as Session Workspaces
Actions. No second provider registry was introduced.

Python/Octave Script Bridge API `CORE_PARAMETER_SERVICE_v1` exposes only
`session_list`, `session_evaluate(expression)`, `workspace_list(workspace_id)`,
`workspace_evaluate(workspace_id,expression)`. It returns values/records, never
administrative handles. Registration, ownership, mutation, subscriptions, Workspace
UI dispatch and native scene mutation adapters remain host/module-only. Unknown
operations fail. Genuine Python and Octave execution is covered in the release
report.

## Compatibility audit

The pre-existing module descriptor/configuration parameter controls and execution
schemas remain authoritative for module settings; they are not reinterpreted as
formulas. The Unit Registry's constrained `x` conversion grammar and its scientific
conversion semantics remain unchanged. Curve Fit model expressions remain in their
existing fitting backend. New named sketch/Workspace/Session expressions all use
this C service. Existing numeric dimension entry and explicit unit conversion are
retained by the Workbench adapter; no private Workbench evaluator is introduced.

`parameterBindingsSet handle expressions` records generic consumer expression bindings in the same Workspace metadata. CORE validates these for closed consumers too, so removing a referenced parameter fails before corrupting a saved binding. Workbench publishes its dimensional expressions through this reusable operation.

## dev071 historical read scopes

`parameterReadView context definitions ?sessionDefinitions?` installs a temporary,
context-bound read overlay for historical inspection. Public parameter evaluation
and listing see that state; writes reject until `parameterReadViewClose context`.
The live shared Session definitions are not replaced. Session lifecycle invalidates
these overlays. Curve Workbench uses them while browsing Scientific Recipe states
and closes them before returning to latest or accepting an explicit restart.
