# GX-TXT Parallel Execution API v1

License: GNU GPL v3 or later

## Purpose

Parallel Execution API v1 is the public CORE coordinator for **independent work items**. It provides one framework-owned place for worker-count policy, serial fallback, bounded process concurrency, deterministic result association, progress, cancellation, errors and cleanup.

The API coordinates execution only. It does **not** define a Dataset, Publication, Table Stream, FFT, CFD or other scientific result format. Consumers continue to use the existing GX-TXT scientific APIs for their inputs and outputs.

The public contract is backend-neutral. A worker may ultimately run Tcl-side code, GNU Octave, Python or another executable through an adapter supplied by the consumer. The API does not define `parallel = Octave`.

## Discovery

The implementation is loaded from:

```text
core/tcl/parallel_execution_api_v1.tcl
```

Public discovery:

```tcl
::GX::parallelExecutionApiInfo
```

returns a dictionary containing at least:

```text
api_name = Parallel Execution API
api_version = 1
work_item_identity = id
operation_kinds = callback process
nested_policy = serial
result_order = input
```

The API contract version is independent from the GX-TXT release number.

## CORE worker policy

The current CORE policy is intentionally conservative:

```text
enabled                      1
default_workers              2
max_workers                  4
recommended_internal_threads 1
```

Read or update the central policy with:

```tcl
::GX::parallelExecutionConfigure
::GX::parallelExecutionConfigure [dict create default_workers 2 max_workers 4]
```

Configuration is validated transactionally. A rejected configuration does not leave a partially modified CORE policy.

An explicit worker request above `max_workers` is rejected. CORE does not automatically consume every logical CPU.

## Work items

`parallelExecutionExecute` accepts a Tcl list of work-item dictionaries. Every item requires a unique, non-empty `id`:

```tcl
set items [list \
    [dict create id item-001 dataset_id ds1 member_id w0001] \
    [dict create id item-002 dataset_id ds1 member_id w0002]]
```

The API does not require a full Dataset payload in a work item. Consumers are expected to pass compact identities, selections, ranges and parameters where possible. This keeps the public architecture suitable for large scientific data without forcing per-worker Dataset duplication.

## Operation kinds

### `callback`

A callback operation executes a Tcl command prefix in the current interpreter:

```tcl
set operation [dict create \
    kind callback \
    command ::MyModule::runOne]
```

The command is invoked as:

```text
command work_item execution_context
```

Its return value becomes the item result.

In-process callbacks are intentionally **serial**. If a caller requests more than one worker, CORE resolves the run to one worker and reports:

```text
fallback_reason = callback_in_process
```

This avoids pretending that Tcl callbacks sharing one interpreter are independent concurrent workers.

### `process`

A process operation uses a command-builder prefix:

```tcl
set operation [dict create \
    kind process \
    command_builder ::MyModule::buildWorkerCommand \
    result_parser ::MyModule::parseWorkerResult]
```

The builder is invoked as:

```text
command_builder work_item execution_context
```

and returns an argv list, for example:

```tcl
return [list octave-cli --quiet --no-gui worker.m --member $memberId]
```

The command is executed directly as argv, not through a shell. GX-TXT writes the argv/environment request to a framework-owned temporary file and uses the internal Python launcher:

```text
core/python/parallel_process_exec_v1.py
```

The launcher calls `execvpe()` with `shell=False` semantics. User-derived arguments that happen to contain Tcl/shell pipeline characters are therefore still arguments and are not reinterpreted as `|`, `>`, `2>@1` or similar syntax.

The process backend requires Python 3, which is part of the existing GX-TXT runtime environment. The worker itself does **not** have to be Python.

`result_parser` is optional. When present, it is called as:

```text
result_parser raw_stdout work_item execution_context
```

If absent, raw stdout is returned as the item value. Worker stderr is retained separately in the item result.

Optional operation fields:

```text
environment   dictionary of worker environment additions
process_group boolean, default 1
```

On POSIX systems the internal launcher creates a separate process group when requested, allowing cancellation to terminate the active worker group rather than only the top process.

## Execution context

Worker callbacks/builders receive a context dictionary containing at least:

```text
api_version
run_id
item_id
index
worker_count
parallel_depth
recommended_internal_threads
```

Process workers also receive two CORE-owned environment values:

```text
GXTXT_PARALLEL_DEPTH
GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS
```

`recommended_internal_threads` is a generic execution-policy hint. CORE does not hard-code OpenBLAS, FFTW, Octave or another backend-specific setting. A backend adapter may translate the recommendation to the controls appropriate for that backend.

## Execute

Public entry point:

```tcl
::GX::parallelExecutionExecute $items $operation $options
```

Supported options:

```text
workers          auto | serial | positive integer
fail_fast        boolean, default 0
progress_command command prefix, optional
run_id           caller-supplied unique run identity, optional
environment      dictionary merged into process-worker environment
```

`workers=auto` uses the central `default_workers`, bounded by the number of work items and `max_workers`.

`workers=serial` is equivalent to `workers=1`.

Serial execution is a normal supported mode, not an error or degraded result.

## Deterministic result association

Workers may complete in any order, but the returned `results` list is always aligned with the input item order.

Example:

```text
input order:      A B C D
completion order: C A D B
results order:    A B C D
```

Each result dictionary contains:

```text
index
id
state
```

and, depending on state:

```text
value
error
error_code
stdout
stderr
reason
```

Item states are:

```text
success
error
cancelled
not_executed
```

The top-level run result includes a diagnostic `completion_order`, but callers must use item IDs / the deterministic `results` list for scientific association.

## Run lifecycle

Public run states are:

```text
pending
running
completed
failed
cancelled
```

A run is `completed` only when all required work completed successfully.

If any executed item fails, the overall state is `failed`.

If cancellation is requested, the overall state is `cancelled`; partially executed work is never presented as a normal full success.

Runtime status is available through:

```tcl
::GX::parallelExecutionStatus $runId
```

Completed runtime summaries may be discarded explicitly with:

```tcl
::GX::parallelExecutionRelease $runId
```

Parallel worker runtime is disposable in-memory/temporary state. It is not authoritative Project, Experiment, Dataset or Publication state.

## Per-item errors and fail-fast

By default, item errors are collected and other already-independent work may continue:

```text
fail_fast = 0
```

With:

```text
fail_fast = 1
```

CORE stops scheduling additional pending items after an error. Already active process workers are allowed to reach a controlled terminal state. Unscheduled items are returned explicitly as `not_executed` with reason `fail_fast`.

Failed items are never silently omitted.

## Progress

`progress_command` receives framework-generated progress dictionaries compatible with the existing GX-TXT Progress API shape:

```text
state
mode=determinate
stage=parallel_execution
current
total
module_id=core.parallel
run_id
item_id
message
```

A GUI consumer may therefore use an adapter such as `::GX::progressPublish`, while a headless consumer may collect the same events without touching Tk widgets.

Progress callbacks are advisory. An error in a reporting callback cannot change scientific result ordering or worker cleanup.

## Cancellation

Create or choose a run ID, then request cancellation with:

```tcl
::GX::parallelExecutionCancel $runId
```

Cancellation semantics are:

```text
request cancellation
→ stop scheduling new work
→ terminate active process workers where safely supported
→ mark active work cancelled
→ mark unscheduled work not_executed
→ return overall state cancelled
```

For an in-process callback operation, cancellation is observed between callback items; a callback that performs a long blocking operation must provide its own cooperative checkpoints if it needs sub-item interruption.

## Nested parallelism

Uncontrolled nested worker pools are not allowed.

A Parallel Execution call made while already inside a Parallel Execution context resolves to one worker and reports:

```text
fallback_reason = nested_parallelism
```

Process workers receive `GXTXT_PARALLEL_DEPTH`, so a worker that loads the same public API also observes the nesting policy.

This prevents accidental patterns such as:

```text
N outer workers × N inner workers
```

from becoming the default behavior.

## Serial fallback

If CORE parallel execution is disabled centrally, a request for multiple process workers falls back to one worker and reports:

```text
fallback_reason = parallel_disabled
```

The same logical work and deterministic result association are preserved.

A process operation still requires its process runtime (currently Python 3 for the internal safe argv launcher). Missing infrastructure required to execute the operation itself is an explicit error, not a fabricated successful serial result.

## Generic example

```tcl
proc buildWorker {item context} {
    return [list my-worker \
        --dataset [dict get $item dataset_id] \
        --member  [dict get $item member_id]]
}

proc parseWorker {stdout item context} {
    return [string trim $stdout]
}

set items [list \
    [dict create id m1 dataset_id dataset-7 member_id member-001] \
    [dict create id m2 dataset_id dataset-7 member_id member-002]]

set operation [dict create \
    kind process \
    command_builder buildWorker \
    result_parser parseWorker]

set run [::GX::parallelExecutionExecute \
    $items $operation [dict create workers auto]]

if {[dict get $run state] ne "completed"} {
    error "parallel workload did not complete"
}

foreach result [dict get $run results] {
    puts "[dict get $result id]: [dict get $result value]"
}
```

The example deliberately uses generic Dataset/member references. Parallel Execution API v1 does not open the Dataset or publish scientific results itself.

## Public `standard_octave` binding

GX-TXT 0.9.7.73 exposes the same CORE Parallel Execution API v1 coordinator to normal `standard_octave` modules. The binding is an adapter to the already-active CORE scheduler; it does **not** instantiate a second scheduler and does not use the Octave `parallel` package.

The primary public helper is:

```octave
result = gxtxt_parallel_execute_v1(items, options);
```

Discovery is available through:

```octave
info = gxtxt_parallel_execution_info_v1();
```

An active run with a caller-supplied stable run ID can be cancelled through:

```octave
changed = gxtxt_parallel_cancel_v1(run_id);
```

All three helpers are located in `core/octave/io` and are intended for modules using the standard Octave runtime.

### Binding lifecycle

When GX-TXT starts a `standard_octave` module, CORE creates a loopback-only authenticated binding endpoint for that module run. The Octave helpers connect to that endpoint through a small Tcl transport client. Scheduling remains inside the main GX-TXT CORE interpreter:

```text
standard_octave
      ↓
public Octave helper
      ↓
loopback authenticated transport
      ↓
active CORE Parallel Execution API v1
      ↓
safe process workers
```

The transport client only forwards protocol records. It does not source Parallel Execution API v1 and cannot schedule workers by itself.

The endpoint is removed when the module finishes or is stopped. If the Octave caller disappears while a parallel run is active, the connection loss requests cancellation through the same CORE coordinator so worker processes and temporary runtime state are not orphaned.

### Work-item model

`items` is a struct array or cell array of structs. Each item contains:

```text
id    stable caller-supplied work-item ID
argv  executable followed by argv elements
```

Example:

```octave
items = { ...
  struct('id','item_a','argv',{{'octave-cli','--quiet','worker.m','--member','a'}}), ...
  struct('id','item_b','argv',{{'octave-cli','--quiet','worker.m','--member','b'}}) ...
};
```

The public interface never accepts a shell command string. `argv` is handed to the existing CORE `kind=process` execution path and therefore keeps the same safe argv launcher and no-shell semantics as Tcl callers.

Work-item IDs must be non-empty and unique inside one request.

### Worker selection

`options.workers` accepts the same public values as the Tcl API:

```text
auto
serial
positive integer
```

Examples:

```octave
r1 = gxtxt_parallel_execute_v1(items, struct('workers','serial'));
r2 = gxtxt_parallel_execute_v1(items, struct('workers','auto'));
r3 = gxtxt_parallel_execute_v1(items, struct('workers',2));
```

`auto` uses the current CORE policy. An explicit integer remains subject to the current `max_workers`. The Octave helper does not duplicate worker-count calculation or clamp a request locally.

If central parallel execution is disabled or nested execution requires fallback, the existing CORE resolution policy remains authoritative and the returned summary exposes `worker_count` and `fallback_reason`.

### Options

The binding currently accepts:

```text
workers      auto | serial | positive integer
fail_fast    scalar boolean
run_id       optional stable caller-supplied Parallel Execution run ID
environment  optional struct or N-by-2 name/value cell array
```

Worker environment names are validated. CORE-owned binding endpoint variables are injected after caller additions so nested standard-Octave workers remain connected to the same coordinator and cannot redirect the binding endpoint through `options.environment`.

### Deterministic result association

Physical completion order does not change logical result order.

For input:

```text
item_a
item_b
item_c
```

workers may physically finish as:

```text
item_c
item_a
item_b
```

but `result.results` remains:

```text
item_a
item_b
item_c
```

`result.completion_order` is available only as a diagnostic of physical completion.

Each returned item preserves the existing CORE state/error model and exposes:

```text
index
id
state
value
stdout
stderr
error
error_code
reason
exit_status
```

`exit_status` is `0` for successful process work, the process exit status when CORE reports `CHILDSTATUS`, or empty when no process exit status applies. `error_code` is not replaced by an Octave-specific status scheme.

The top-level result includes the existing run summary fields such as:

```text
run_id
state
requested_workers
worker_count
fallback_reason
total
completed
success_count
error_count
cancelled_count
not_executed_count
completion_order
results
```

### Progress

The shared CORE coordinator remains the source of work-item progress. Progress records are transported to the Octave helper and re-emitted through the existing GX-TXT Progress API helper functions.

Progress therefore remains based on CORE's completed/processed item counts and uses the existing `parallel_execution` stage. No Octave-only progress counter or second progress protocol is introduced.

### Cancellation

Framework cancellation reaches the active CORE scheduler directly before the normal analysis process stop path is completed.

For cooperative programmatic cancellation, choose a stable run ID:

```octave
opts = struct('workers','auto','run_id','my-work-17');
result = gxtxt_parallel_execute_v1(items, opts);
```

and another cooperating caller may request:

```octave
gxtxt_parallel_cancel_v1('my-work-17');
```

Cancellation uses `::GX::parallelExecutionCancel`; it is not implemented by killing arbitrary worker PIDs from Octave. The execution result retains CORE's explicit `cancelled` and `not_executed` item states and top-level `state='cancelled'` when the caller remains present to receive the summary.

If the executing Octave process itself is terminated, loss of its authenticated transport also requests CORE cancellation. Cleanup therefore remains CORE-owned even when no Octave caller remains to receive the final summary.

### Nested parallel execution

Workers inherit the same authenticated binding endpoint as well as CORE's `GXTXT_PARALLEL_DEPTH` value. If a worker invokes `gxtxt_parallel_execute_v1` again, the request reaches the **same active coordinator**. The existing nested policy therefore applies without a private worker pool:

```text
worker_count = 1
fallback_reason = nested_parallelism
```

This is the same behavior as nested Tcl callers.

### Internal numerical threads

Parallel Execution API v1 continues to set:

```text
GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS
```

in every process worker environment according to the current CORE policy. The discovery helper also reports:

```text
recommended_internal_threads
```

The binding does not contain FFTW-, BLAS-, FFT- or solver-specific thread logic. Numerical workers decide how to apply the generic recommendation to their own libraries.

### Cleanup

Success, per-item failure, cancellation, caller disappearance and module stop all retain the existing CORE cleanup path. The shared coordinator owns:

```text
worker process termination
temporary request files
stderr capture files
gxtxt-parallel-* temporary runtime directories
run state cleanup
```

The standard-Octave transport endpoint itself is scoped to the module run and is closed when that run ends.

### Small generic example

```octave
items = { ...
  struct('id','a','argv',{{'python3','worker.py','a','12'}}), ...
  struct('id','b','argv',{{'python3','worker.py','b','34'}}) ...
};

options = struct();
options.workers = 'auto';
options.run_id = 'example-independent-work';

run = gxtxt_parallel_execute_v1(items, options);

if (!strcmp(run.state,'completed'))
  error('Parallel work did not complete successfully');
endif

for i = 1:numel(run.results)
  item = run.results{i};
  fprintf('%s: %s', item.id, item.stdout);
endfor
```

The worker may be an Octave, Python or other controlled executable selected by the module. The binding itself is language- and scientific-domain-neutral.

## Current non-consumers

GX-TXT 0.9.7.73 provides the public execution infrastructure and its `standard_octave` binding. This does not automatically parallelize existing scientific consumers.

The following remain unchanged and are **not** parallelized by this release:

```text
analysis.fft_spectrum
Temporal Set FFT processing
math.numeric
spectrogram
CFD workflows
```

Consumer migration is a separate Remaining Work item.
