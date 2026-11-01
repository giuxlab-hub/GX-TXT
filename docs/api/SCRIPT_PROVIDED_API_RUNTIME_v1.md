# Source-declared packaged Script functions v1

This additive pathway extends the existing Script Module, Script Execution and
Managed Job owners. Static inventory alone remains read-only and grants no
execution rights. The installed module must be enabled, declare the exact API
and version, and supply a SHA-pinned `script.provided_manifest` and original
`script.provided_entrypoint`. The manifest is the deterministic
`gxtxt.script_provided_api_inventory.v1` over every admitted language source in
the normal bundle. CORE recomputes it before submission and in fresh Job
preparation. Distinct APIs may have the same operation name.

`::GX::scriptModuleProvidedApiInvokeJson module api operation argumentsJson`
accepts an exact JSON argument object and returns the actual declared structured
result as JSON. `scriptModuleApiInvoke` retains its old manual-package behavior;
for source-declared packages it uses the same manifest's argument schemas to
encode a Tcl dictionary. Generated normal Script Bridge bindings pass JSON to
preserve nested arrays/objects and integer, boolean and floating distinctions.
Both paths validate required/default arguments, unknown fields, finite types,
shapes/bounds, implementation identity and source hashes. Control messages and
results are bounded to 1 MiB. Scientific arrays belong to their existing public
resource owners.

The existing `scriptExecutionPrepare` and Script Job request owner accept an
optional package invocation. They freeze a normal immutable Project snapshot,
retain package/descriptor/manifest/bundle/source hashes in execution identity,
run the same import preflight and launch the existing Python/Octave runner under
the unchanged Supervisor. Parent/child wait leases, cancellation, quotas, logs,
process draining and Job inspection remain with that owner. This is an actual
function call to the declared admitted implementation, without running the
whole Analysis entrypoint. Consumed APIs still go through normal Script Bridge
preflight and capability admission; declaration metadata grants no additional
Registry, filesystem, Dataset or administrative authority.

Python uses the existing Project import guard. Octave uses the existing Project
path/SHA verification, exact function-file resolution and existing Bridge value
codec, including decimal integer transport. The inert `gxtxt_api_export` marker
never registers APIs at runtime. CORE validates actual result structure before
returning it and rejects stale Session/package identities, missing receipts,
wrong result types, disabled modules and failed/cancelled Jobs explicitly.

Implementation author qualification: 19 component checks use synthetic source
packages, actual Python/Octave functions and shared Project/codec owners. They
are not normal installation, genuine Builder, Managed Job, independent consumer
or independent GUI acceptance. Those release gates remain open until separately
recorded on the final candidate. Original fixture01 missed the Octave IO path;
fixture02 used INI delimiter whitespace inconsistent with the maintained runtime
writer. Both failures remain preserved; fixture03 passes.

## Bridge arrays and compatibility admission

`bridge_arguments_json(values, operation)` in the maintained CORE provided-runtime
adapter projects existing `NumericArray`/`ResourceNumericArray` control carriers
through the actual declared argument schema. Ordinary Octave row/column vectors
can satisfy a declared scalar array; a genuine matrix cannot silently become a
vector. Declared nested arrays preserve actual shape and native F-order values.
Integer and boolean storage retain their exact scalar types; floating values are
not coerced into integers. Bounds are checked before lazy resource materialization;
control arrays are limited to65536 cells and the same1MiB JSON envelope. Scientific
payloads retain their existing resource owners.

CORE `SCRIPT_EXECUTION_API_v1` advertises additive compatibility capabilities
`provided_function_jobs_v1` and `provided_bridge_control_arrays_v1`. Generated
bindings require these capabilities before invocation, import the adapter lazily
and refuse unavailable CORE explicitly; discovery must remain safe on older CORE.
This metadata grants no new generic dispatch or mutation authority. Source,
operation and descriptor consumed requirements are all retained for normal Job
preflight. Old manual `public_api` packages retain their original route.

Independent A69 exposed the original generated binding's plain JSON serializer
rejecting legitimate Octave numeric-vector carriers. Its failure and original
packages remain immutable. The shared adapter has12 scoped author component
checks; corrected normal Builder packages and independent end-to-end retakes are
required before declaring this correction accepted. Early author30/32 packages
exercised two APIs in one declaration file/one implementation helper; the final
owner gate of multiple distinct helper declarations/functions remains separate.

A package may advertise disjoint legacy manual public API operations and source-derived provided functions together. The host dispatches only an exact `(api_id, operation)` member of the SHA-verified provided manifest through the function Job path. A declared legacy operation retains the existing packaged Analysis wrapper and its real Analysis source requirements. Unknown operations and damaged manifests refuse; the presence of a provided manifest does not convert unrelated legacy calls into function invocations.
