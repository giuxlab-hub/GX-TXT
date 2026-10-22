# Scientific Execution API

`SCIENTIFIC_EXECUTION_API_v1` is the CORE facade for registered local and remote scientific solver providers. Tcl clients use `::GX::scientificExecution*`; Python and Octave clients use the matching Script Bridge operations. It reuses `SCRIPT_JOB_API_v1`, its durable SQLite journal, guardian, admission policy, owned process tree, Resource Management and publication recovery. It creates no second queue or scheduler. The transient Parallel Execution API remains a separate worker service.

## Provider and client contracts

Result import runs in the registered provider's `module_id` context, scoped by
the existing module-context service. A calling Viewer or Script Bridge retains
its own context after both successful and failed import. This prevents a Viewer
context from replacing the scientific producer identity in Publication v2.
Completed-Job, source revision/SHA, coherent-output, reviewed-owner and atomic
batch rollback checks remain authoritative. A failed publication can be retried
from the same completed Job after correcting its cause; it does not require
another solver execution.

Trusted installed CORE/provider code registers an ID with `scientificExecutionRegister id descriptor`. Required descriptor fields are `module_id`, semantic `version`, framework-relative Python `worker`, configured `tools`, and typed `parameters`. Each parameter has `type` (`integer`, `number`, `boolean`, `string`, `choice`) with applicable default/required/min/max/values. Registration is host-only: scripts cannot submit source paths, executable names, commands, working directories or a provider implementation. Registration is trusted code, not an authorization ceremony for arbitrary uploaded code. `import_command` is an optional trusted domain parser callback. Optional `runtime_files` lists trusted framework-relative native/runtime dependencies; their exact SHA values and the CORE adapter SHA are captured, rechecked at submission and verified by the worker before execution. Changing a dependency refuses that prepared Job rather than changing its science.

`scientificExecutionDiscover` lists registered IDs. `Describe provider` returns actual types, tools and version without private worker paths or callback names. Providers supplied by optional modules become discoverable when those modules activate their public service. `scientificExecutionRegisterBuiltins` registers the small `core.ngspice.rc_transient` provider. The safe CPU/live verification provider exists only when the isolated host sets `GXTXT_SCIENTIFIC_TEST_PROVIDERS=1`.

`Prepare provider parameters resources options` validates typed values, configured tools and exact resource SHA. Resources map semantic aliases to existing `INTERACTIVE_DOCUMENT_RESOURCE_API_v1` receipts. Options can contain `document_id` and `expected_revision`. CORE captures Session origin, Document generation/revision/SHA, resource identities, provider source SHA and bounded immutable input bytes. A preparation token is ephemeral and belongs to the current Session lifetime. Total inline input is limited to 8 MiB; larger materializers require a provider-specific bounded public resource reader rather than a path argument.

`Submit prepared_token` rechecks sources and Document revision and submits the trusted CORE driver through the existing registered Python Script Job path. It returns `job_id`, `state` and `provider_id`. Exact prepared parameters and snapshots participate in the existing admission signature. Identical active work may deduplicate. The preparation token is consumed. At most16 preparations are retained per host Session; `Discard prepared_token` releases an unused preparation without creating a Job. Stale Session preparations are pruned. The reserved Session driver is verified and never silently overwritten.

`Status job`, `Reconnect job`, `Cancel job`, and `Log job offset count previous_receipt?` remain attached to the original Session origin. Status uses genuine QUEUED/PREPARING/RUNNING/FINALIZING/COMPLETED/FAILED/CANCELLED/INTERRUPTED states. Accounting PIDs/start identities describe process ownership, never scientific identity. Log reads use the existing bounded UTF-8 reader. Passing the previous returned `receipt` detects append, replacement/rotation, truncation or same-size rewrite; `cursor_reset` explicitly restarts at zero where needed and `generation` is the actual source identity/change token. Missing/unsafe logs remain unavailable. Closing a Viewer detaches its client; it neither owns the process nor changes result ownership. A recovered interrupted Job is not automatically replayed. CPU admission honors effective affinity and mounted cgroup quotas; memory, temporary storage, process count and threads remain supervisor policies, not provider-owned pools.

## Nonblocking trusted-host remote requests

`::GX::scientificExecutionRemoteCallAsync node session operation arguments callback`
uses the same configured-node request construction and authenticated transport as
`scientificExecutionRemoteCall`. `node` is an enabled Configuration node ID;
`session` is its logical remote Session ID; `operation` is an existing remote
protocol operation; `arguments` is one inert Tcl argument list, not variadic source.
`callback` is a Tcl command prefix receiving the ordinary `{ok 1 result … metrics
…}` or `{ok 0 error … error_code …}` response. Failures from the request owner may
instead carry its timeout/cancellation category. Unknown/disabled nodes or worker
startup failures raise before a request token is returned.

It returns the existing `scriptJobAsync` auxiliary token. The owned client is
bounded to 20 seconds and 64 MiB of response text, attached to the GUI lifetime;
`scriptJobRequestCancel token` cancels that client only. Durable remote Job
cancellation still requires the explicit existing `scientific.cancel` operation.
This facade introduces no Job registry, scheduler, endpoint or Dataset store;
requested operations retain their existing authoritative owners.
Successful responses update the existing transport metrics. This trusted Tcl
host command does not add any restricted C++ or script-language execution grant.
`scientificExecutionApiInfo.host_operation_contracts` exposes the exact host
signature, parameter types and result/lifetime contract to the API Browser;
the primary scientific operation list is unchanged.

## Trusted worker boundary

A trusted worker implements `run(context)`. `parameters` contains typed values; `inputs` maps aliases to verified bytes. `scratch` is the guardian's managed temporary directory and `output` is the existing protected Job output resource. Only trusted provider code sees physical paths.

`context.run(tool, argv, cwd=None)` resolves only a declared configured Runtime tool. It uses an argument list without a shell, restricts working directories to managed scratch, streams stdout/stderr to the existing Job log, and returns `returncode`, up to 1 MiB of merged UTF-8 diagnostic tail, and `truncated`. Nonzero exit raises an error and produces FAILED. Solver exit success alone is not scientific validation.

`publish_output(relative_filename, role, format, columns=None, live=False)` declares a unique bounded role from an owned regular output file. It registers inventory, not an automatic Dataset. `summary(mapping)` supplies an explicit validation classification and actual numerical diagnostics. An optional importer receives `(job_id, output_token, verified_bytes, request)` and uses existing public Publication services. It must validate scientific structure, topology, datatypes and units before publication.

## Outputs, provisional data and immutable adoption

`Outputs job` returns role tokens, stable logical IDs, codec/schema, availability, size and observed generation. It never returns output filenames. The output declaration and observation metadata belong to the existing protected Job resource; there is no shadow Dataset catalog. Unavailable/expired outputs retain Job/logical identity.

`ReadOutput job token offset count generation?` reads at most 1 MiB. `ReadRecords` uses the same arguments and a registered CSV codec; it returns only complete typed records, declared IDs/units, next cursor and completeness. Cursors must start on record boundaries. int64 is validated without conversion through float. Unsupported or changed schema and malformed/nonfinite numerical records are rejected. A generation can change between observation and read; clients must observe again after an explicit stale/changed response.

Observations use descriptor identity, size, nanosecond modification/change times and a hash of the declared format/schema/units/live policy without rescanning or hashing the full output. A monotonic counter records changes; a metadata-only contract change reports `schema_changed`, truncation/replacement is explicit, and append versus in-place rewrite is conservatively reported `append_or_rewrite`. The current local codec covers coherent single CSV files, not arbitrary multi-file CFD time steps. Incomplete final records remain provisional and are excluded from complete-record reads. Live reads do not attach an immutable full-file SHA. Clients should refresh manually or use bounded polling/backoff and visibly distinguish provisional values from archived measurements.

`ImportResults job token request` requires COMPLETED, original Session ownership, complete coherent bytes and a registered scientific importer. Captured Workspace generation/revision/SHA and Dataset revision tokens must still match their current owners, both before output capture and immediately before importer invocation; stale or missing sources raise `GX SCIENTIFIC STALE_SOURCE` before adoption. Historical status, output reads and result descriptions remain available without asserting current-source validity. Its internal bounded capture is at most 16 MiB, with descriptor checks before/after and full SHA. Larger outputs need an approved streaming importer; the table importer applies the same source guard before opening a writer, on each page and before final publication. `FreezeResource job token document_id` optionally captures a terminal coherent output as an immutable content-addressed Document resource, retaining generation/SHA/Job lineage. The caller must retain its receipt in the existing Document payload. Neither operation mutates earlier results. Scientific publication validity is separate from Job COMPLETED.

## Security and limitations

## Canonical electrical circuit provider (dev108 additive extension)

`scientificExecutionCircuitInspect document_id ?parameters?` reads and validates the existing
Native2D diagram Document and inspects its deterministic netlist without creating
a Job. It returns `document` (ID, generation, revision, SHA and owner), provider
ID/version, `analyses`, snapshot `source_sha256`, reviewable `netlist`, typed
`probes`, explicit terminal `net_mapping` and `model_origin`. Supported format is
`gxtxt.native2d.diagram.v1`, catalog `electrical.basic`. The existing diagram
owner remains the sole editable authority.

`scientificExecutionCircuitPrepare document_id parameters ?options?` uses the
same inspection, stores exact snapshot bytes as a managed resource owned by that
Document, then calls the ordinary Scientific Execution preparation. Options are
`node_id`, `remote_session_id`, `expected_generation`, `expected_revision` and
`expected_sha256`. Requested source guards must match. Returned inspection adds
opaque `preparation` and `source_resource`; submit/discard use that token through
the existing methods. Ordinary Submit rechecks the source before admission.
Explicit remote selection never falls back locally. Capability inspection on the
selected node must advertise `core.ngspice.circuit` and an available `spice` tool.

`core.ngspice.circuit@1.0.0` accepts only the bounded managed diagram snapshot:
R/C/L, independent voltage/current sources, explicit ground, diode and NPN.
Names need their device prefix plus 1..31 ASCII letters/digits/underscores and
must be unique ignoring case. Values are finite base-SI numbers. Explicit wire
endpoints join pins/junctions; mere coordinate crossings do not. Identical net
labels join nets ignoring case. All ground symbols are node0. Open device pins,
disconnected floating islands, conflicting names and arbitrary directives are
rejected. This does not prove absence of every singular DC topology; real solver
diagnostics and result validation still apply.

Parameters (all types/bounds/defaults are discoverable with Describe):

| Analysis | Parameters | Raw output |
| --- | --- | --- |
| `op` (default) | none | observation index, node V and independent voltage-source branch A |
| `tran` | `step_seconds` (default1e-5), `stop_seconds` (default.005) | time in seconds, V and A |
| `ac` | `ac_grid` dec/lin/oct, `points` default30, `start_hz` default1, `stop_hz` default100000 | frequency Hz, real/imaginary V and A |
| `dc` | exact independent `source` name, `dc_start` default0, `dc_stop` default5, nonzero progressing `dc_step` default.1 | source value V or A, node V and branch A |

Circuit inspection additively returns `independent_variable` with `id`, `dtype`
and `unit`, from the same provider declaration used by raw output publication:
`index` (unitless) for OP, `time` (s) for transient, `frequency` (Hz) for AC and
`source_value` (V or A according to the actual swept source) for DC. Consumers
must verify this stable Variable identity and aligned canonical rows; they must
not infer the independent coordinate from dropdown state or column order.

Voltage waveform `dc` uses value; `pulse` uses initial/value/delay/rise/rise/width/
period; `sine` uses initial offset/value amplitude/frequency/delay. `ac` is the
small-signal amplitude. Current sources currently provide DC and AC amplitude.
R/C/L values use ohm/F/H. Positive branch current follows ngspice's source sign
convention. Original generic educational diode/NPN parameter cards are supplied
under GPL-3.0-or-later with their exact text in the netlist; these are illustrative
models, not manufacturer-certified parts.

For physical-parameter campaigns, `override_component` is an exact stable diagram
component ID and `override_value` is its finite base-SI scalar value. The admitted
targets are R/C/L and independent voltage/current source `value` attributes; all
normal type/minimum checks still apply. An absent component or unsupported target
is rejected. Inspection shows the parameterized netlist. The canonical diagram
is preserved; original snapshot SHA and captured typed Job parameters jointly
identify each child solve. Existing Parallel Execution/Script Job admission must
coordinate campaigns, without provider-owned pools.

`scientificExecutionImportTable job output_token producer definition callback
?source_guard?` publishes immutable declared CSV columns using the existing
Dataset Publication writer, cooperatively in bounded record pages. Optional guard
has exactly `document_id generation revision sha256` and is checked before opening
the writer and on each page, including final publication. Session lifetime, source
generation, completed Job state and original local Dataset inputs are checked;
cancel or failure aborts the writer. Remote immutable tables can be adopted into
the explicit local Session through the actual protocol. Remote Jobs with Dataset
inputs still require node-authoritative input validation and are refused by this
local adoption path. `ImportResults` keeps its original node-authoritative meaning.
The circuit provider has no Dataset inputs. Provenance in the publication
definition must retain original Job/provider/circuit identities and units.

The Job publishes `waveform` CSV with stable typed column IDs/units and `netlist`
text. Summary contains actual solver/version, analysis, row count, circuit/deck
hashes and model origin. AC output is raw complex parts, without private magnitude
or phase calculation. Public Numeric complex/vector operations must compute any
derived quantities, interpolation, analytical references and error statistics.
No new numerical library or solver launcher/scheduler is introduced. Canonical
publication uses the existing `scientificExecutionImportTable` and Dataset
Publication v2; permanent plots consume those canonical variables through Plot.

This contract does not certify the authored Viewer or every analysis/device
combination. See the evidence-indexed dev108 acceptance matrix for actual tests.

These APIs enforce the declared boundary for compliant clients. GX-TXT's in-process Tcl/Python plugins share OS privileges: this is **not an OS sandbox against hostile code**. Trusted providers can execute native solver code and must be reviewed. Provider-specific parsers, safe arguments and bounded resources remain required. Remote execution uses an authenticated HTTPS compute agent over the same node-local Supervisor. No remote scheduler, shell-command submission or cloud-provider adapter is implied.

The bounded RC provider accepts the documented 1 kΩ/1 µF netlist with a fixed safe grammar and controlled transient options. It does not accept arbitrary ngspice control commands, includes or shell expressions and is not a circuit CAD editor. Electromagnetics uses its own registered domain provider and importer over this same execution authority.

## Compute nodes and destination

`scientificExecutionNodeRegister node_id descriptor` stores an account-local Configuration descriptor containing `endpoint` (HTTPS), `ca_file`, `client_cert`, `client_key`, logical `session_id`, and optional `enabled`. Use Configuration → Execution for registration, capability testing and destination selection. Credential files remain outside scientific Sessions; the key must be private to its owner. Registration is host-only because it configures credentials. `NodeList` returns a redacted list; `NodeInspect node_id` reports actual Linux architecture, cores, registered providers, tool availability and Supervisor policy. Dev108 additively includes `core_apis`: `scientificExecutionCoreCapabilities` inspects the actual public Numeric API version/operation and foundation catalogs, Octave availability, Statistical Result Semantics, Script Job and Parallel Execution contracts. It activates the bundled public Numeric service independently of its optional analysis checkbox. This is installed capability inspection, not scientific execution acceptance; no numerical-library presence probe is performed. Existing clients may ignore the additional field. Python/Octave expose `node_list`, `node_inspect`, and `destination`.

`scientificExecutionDestination ?local|auto|node_id?` persists the destination. An explicit `Prepare` option `node_id` overrides it; `remote_session_id` can select another granted logical Session. Auto chooses an enabled reachable node advertising the requested available provider, otherwise local. A remote preparation retains the local Session lifetime, input SHA and optional Document revision guards. Inputs use bounded SHA-verified managed-resource staging; identical scoped inputs reuse a verified resource. The remote host validates its own registered provider and runtime. Remote preparations retain their nonce receipt until explicit Discard so retries return the same durable Job rather than submitting twice.

Remote IDs have the opaque form `remote/node_id/session_id/job_id`. Existing Status, Reconnect, Cancel, Log, Outputs, ReadOutput, ReadRecords, ImportResults and FreezeResource route through this reference. Generic Script Job describe/inspect/log/cancel/wait also accept it. ImportResults publishes on the authoritative node. FreezeResource captures an immutable output in an explicitly selected local Document. Source generation checks and read limits remain in force. A disconnected endpoint reports `GX REMOTE UNAVAILABLE`; it never fabricates FAILED or silently reexecutes locally. Reconnection uses the same original Supervisor identity. An uncertain admission journal entry refuses duplicate execution and requires operator reconciliation.

## Debian compute-agent operation

Run the installed `core/python/gxtxt_compute_node.py --config CONFIG.json` with the configured Python runtime. The administrator-owned JSON contains `node_id`, `bind`, `port`, `state_root`, `server_cert`, `server_key`, `ca_file`, `sessions` mapping logical IDs to node-local Session directories, and `clients` mapping certificate common names to objects with a `sessions` grant list. Use a dedicated account and private state/configuration. TLS verifies the server CA and hostname and requires a client certificate trusted by the node CA. Certificate identity must also have an explicit grant; knowing a Session ID is insufficient.

The request protocol allows only enumerated CORE operations and logical identities. It accepts no source programs, executable names, shell commands or arbitrary file paths. Framed control data is at most 2 MiB and a message at most 32 MiB; scientific arrays and resources use independently SHA-verified raw binary blocks. Input resources are at most 8 MiB, upload blocks at most 1 MiB, with at most 16 active stages and ten-minute abandoned-stage expiry. The agent owns only transport grants, receipts and preparation references. Existing Supervisor policy owns admission, concurrency, process trees, logs and durable Jobs; existing Publication owns scientific adoption.

Keep the compute agent and its managed workers on the same immutable installed
framework tree. Restart the agent after replacing that tree. A retained interpreter
from different source bytes can correctly refuse Preview preparation because its
expected renderer/source key differs; restart and request the current representation
rather than bypassing that guard. Durable scientific Jobs remain attached to their
Supervisor identity across the agent restart.

### Bounded physical parameter collections

`core.ngspice.circuit` additionally accepts `component_values`, an inert Tcl
dictionary (at most4KiB/eight targets) mapping exact stable component IDs to
finite base-SI values. Only R/C/L/independent V/I value attributes may be
overridden; missing targets, duplicate keys, conflicting single/mapped overrides
and invalid physical minima reject at inspection. The earlier optional
`override_component`/`override_value` pair remains compatible. Source topology,
original values and canonical Document SHA remain unchanged; exact normalized
overrides appear in inspection, Job parameters and solver summaries. No authored
raw netlist directives or code are admitted.

`scientificExecutionCircuitSweepPrepare document baseParameters items ?options?`
accepts1..16 items `{id UNIQUE_ID parameters TYPED_OVERRIDES}`. It validates every
merged parameter set before any Job submission, captures one source guard and
managed original circuit resource, and returns only ordinary Scientific Execution
preparations plus exact item/provider identities. Options match circuit Prepare.
If preparation fails, already prepared handles are discarded; no simulation was
admitted. Explicit values/grids generated by callers must use public Numeric
operations when scientific calculation is required.

`scientificExecutionCircuitSweepSubmit receipt ?options?` coordinates ordinary
Submit calls using existing Parallel Execution. Options: workers, fail_fast,
progress_command, run_id. Callback coordination intentionally reports its actual
serial worker_count/fallback. Every callback returns immediately after ordinary
Job admission; the existing durable Script Job Supervisor alone schedules child
processes under actual destination CPU/RAM/worker policy. No extra scheduler or
thread pool exists. `ADMISSION_FINISHED` describes submission, never successful
physics completion. Per-item errors/not_executed and known canonical Job IDs are
retained in the coordination result; query each real Job for progress, logs,
cancellation, reconnection and completed outputs.

Preparation handles are scoped to the existing process/Session lifetime. Retain
handles on uncertain remote admission for idempotent retry with the original
nonce; do not resubmit a fresh preparation blindly. Persist known durable child
Job references and source/parameter identities in existing Document/Workspace
state. A preparation receipt alone is not durable across application restart.
The caller must discard successful remote preparations after storing their Job
receipts, and explicitly discard abandoned/unsubmitted preparations. Mutating the
source between preparation/submissions rejects; partial admissions remain real
Jobs and must be shown/recovered rather than erased. GUI/SDK exposure and actual
concurrency/scientific acceptance require separate evidence.
