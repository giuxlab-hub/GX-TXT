# Viewer Development Workspace

Create and edit a restricted C++ Viewer without opening a scientific Session.
Open **Viewers → Interface Tools → Viewer Development Workspace**. The adjacent
Viewer Interface Builder remains the visual design owner; its Component Gallery
supplies display-only examples through the same public native constructors.

## Project workflow

1. Choose **New project** and an existing parent directory. The environment creates
   a new project directory, source skeleton, inert Builder design, facility
   requests and provenance. An existing nonempty project is never overwritten.
2. Edit **handlers.cpp**, additional **src/*.cpp** units and **include/*.hpp** headers in independent source tabs. Native selection, Copy/Paste,
   Undo/Redo, Find, syntax colors, physical lines and supported folds belong to
   Source Surface. The separate C++ debugger runs admitted source through the fixed compiler and real GDB/MI backend.
3. Save the current source with **Save / Ctrl+S**, or commit every changed tab with **Save All / Ctrl+Shift+S**. A dirty close asks Save, Discard or Cancel.
   The Builder design and generated reports are read-only here; edit visual
   hierarchy/properties with the existing Interface Builder.
4. Choose **Validate** (Develop menu or toolbar; F5 starts/continues Debug). This runs the real Clang raw lexer, then resolved AST
   admission and project/facility checks. Validation does not produce object code.
   Diagnostics identify file, physical line, column and reason; double-click a
   diagnostic to select its source line.
5. Choose **Build / F6**. An unchanged successful artifact is reused after checking
   its source, design, project, SDK, policy, compiler, adapter, build recipe and
   recorded header dependencies. Missing or changed inputs require fresh admission,
   compilation and linking through the same Build owner. Build receipts retain
   those fingerprints and the binary SHA; reuse reports `artifact_reused=1` and
   `code_generation_invoked=0`.
6. Choose **Demo / Preview / F7**. Preview prepares the same source-bound artifact;
   an unchanged build does not invoke the compiler again. C++ events execute in
   one separate bounded worker for that Preview's lifetime. The public CORE
   applies the typed admitted local UI plan before returning to queued input.
   The default Open event creates the same Native2D RAM fixture used by Gallery.
7. Invoke **Run C++ handler** in Preview. The sample uses public Numeric
   `array_binary.add` to convert the synthetic value 18 to 291.15 kelvin, updates
   a numeric readout, writes a constant explanatory label and increments state.
   It creates no scientific Dataset, Workspace or publication.
8. **Test / F8** exercises the compiled handler through the same backend. Inspect
   its explicit event/state/output receipts; a passing source-policy result alone
   is not a native GUI or scientific correctness result.
9. **Export candidate** uses the same source-bound artifact, building it through
   the existing owner if inputs are missing or changed, and creates a normal
   Viewer ZIP with source, Builder design, trusted facade, SDK contract, native
   binary, provenance, validation/build reports and checksums. Export does not
   install. Review and promotion use the ordinary Plugin Manager.

The bottom notebook separates diagnostics from bounded build/runtime output.
Complete JSON receipts remain in `derived/`; the GUI truncates very long display
logs explicitly. **Cancel** terminates only the request's owned process tree.
Closing a Preview cancels its own native request and releases native children.
Another Preview or the original scientific data is not its cleanup target.
Build publishes a new binary inode atomically, so an existing Preview can keep
its old mapping during a new Build. A source change still invalidates that
Preview's callbacks; reopen Preview for the new revision. F7 normally replaces
the Development Workspace's tracked Preview. Installed Viewers execute their
distributed binary without invoking the development compiler.

## Files and preservation

- `handlers.cpp`: original hand-authored C++; regeneration/build never replaces it.
- `project.json`: inert identity, language/profile, approved capability requests
  and provenance. Extra compiler, policy, include, dependency or adapter flags fail.
- `design.gxtxt-viewer`: the existing inert Builder schema, not executable Tcl.
- `derived/validation.json`, `build.json`, `run.json`: independently produced
  reports. Editing a report cannot authorize a future build, run or export.
- `derived/viewer.so` and `trusted_adapter_v1.cpp`: generated artifacts, separate
  from original source. Stale binaries are never run after source rejection.
- `candidates/<package-hash>/`: ordinary review packages and SHA-256 files.

Project imports first pass the actual Clang raw lexer/resolved AST and facility
checks; rejected imports do not replace the editor buffer. Source Save uses the
same project-write tool grant as CLI. Incomplete C++ can be saved for repair.
Save All requires well-formed project metadata and retains its existing source_files
list; use the tree actions to change that list. Invalid source cannot pass future
Build/Run admission. No code runs on import. The compiler/AST policy must admit source before any
native execution. No authored Tcl hook, build script, external header or alternate
compiler command is accepted. Reopening the same project preserves its original
source bytes. A changed source/design during validation or execution is refused
rather than silently applied to another revision.


## Multifile source tree and portable projects

![Actual GDB Step Into at an executable project header, with its own source tab and physical execution arrow.](images/multifile-debug-header.png)

The project tree shows handlers.cpp, nested src/ translation units and include/
headers. **New file** creates an empty source or a header with pragma once.
**Add file** copies a selected ordinary UTF-8 .cpp/.hpp into a chosen project-relative
name. **Rename / move** preserves exact file bytes; update include statements
explicitly. **Remove** asks before deleting an auxiliary file; handlers.cpp is
the mandatory entrypoint and cannot be renamed or removed. Failed operations
retain the existing source tree. Names containing traversal or linked ancestors
are refused. Projects admit at most32 source/header files,64KiB each and1MiB total.

At narrow widths, source tabs use a selector with the complete relative file
names. Scroll the project tree horizontally to read long nested filenames.
The File menu retains New file, Add file, Rename / move, Remove and Close tab
when their duplicate toolbar buttons do not fit. SDK, Profile, API Browser and
the diagnostic pages keep their existing native page selection.
If the inline API reference is taller than its page, use its outer scrollbar to
reach the remaining reference controls. Keyboard focus brings those controls
into view; the reference's own lists and text keep their normal scrolling.

Select a file to open its independent shared Source Surface tab. Switching files
preserves unsaved text, Undo, selection and scroll position. A star marks each
changed tab. **Close tab / Ctrl+W** offers Save/Discard/Cancel for that file.
Save All checks every changed file's inspected SHA before publishing the batch;
a concurrent external edit refuses the operation and retains all buffers.
Ordinary I/O failure restores prior touched bytes/modes; no crash-atomic promise
is made. Validate/Build/Preview/Test/Export save every changed tab first.

All source/header bytes participate in the complete source manifest and composite
project identity. A helper/header edit invalidates the previous Build/Preview and
source-bound Debug execution. The original fixed compiler admits each translation
unit and its local headers, then links all units with the trusted SDK adapter.
Diagnostics navigate the actual file, line and column; generated reports and
Builder design remain read-only. Every source tab is part of this one project,
not another installed program.

Breakpoints in all open source/header tabs are submitted together against one
frozen whole-project revision. GDB Step Into/Out and Call Stack selection open
the actual helper/header/caller tab and place its execution arrow. SDK/system
frames remain external. A nonexecutable header breakpoint can stay pending or
resolve to a different instruction; only actual GDB observations establish a stop.
Stop before changing the active breakpoint set.

**File → Import project package…** reads a normal exported Viewer ZIP and creates
a separate editable project in a chosen parent folder. The source/design/project
manifest and authored manual/assets are checked against the package checksums
and build receipt before the complete folder is published. Existing destinations
are preserved. Import runs no authored code and loads no packaged native binary;
use explicit Build under current admission before Run. Export includes exact
sources/headers and their source manifest alongside the genuine compiled binary.
Install the exported module separately through the ordinary Plugin Manager.

The CLI uses the same owners:

```sh
printf '{"operation":"list"}\n' | core/bin/gxtxt-viewer-dev project_files /absolute/projects/thermometer
core/bin/gxtxt-viewer-dev import_project /absolute/projects/imported --package /absolute/packages/viewer.zip
```

The project_files operation reads a JSON object on stdin; use operation list,
then the returned expected_project_sha256 for add/rename/remove/save_all. Full
request shapes are in the public Viewer Development API manual.

## Configure a real event test

`project.json` contains `tests` with 1–8 typed `events`, an `expected_counter` and
an `expected_values` map whose keys are scalar slot indices0–15. The generated
sample runs Open, Invoke18 and Invoke20; expected counter2 and slot0=293.15.
Test uses the source-bound build artifact and executes those events in order,
carrying returned state into the next bounded worker invocation. An unchanged
artifact is reused; missing or changed inputs require the normal Build owner.
Inspect `derived/tests.json` for every
actual event and public Numeric receipt. These developer expectations cannot
change the source policy or replace independent GUI/native acceptance.

## Exact C++ SDK v1

CORE automatically supplies `gxtxt_viewer_sdk_v1.hpp`. Authors may include the explicitly reviewed C/C++ headers in the [current support catalog](../../../docs/api/CPP_SUPPORT_CATALOG.md).
The SDK exposes `gx::Host`, `gx::State`, `gx::Event` and `gx::EventKind`. State has
sixteen bounded scalar slots (`values[0]` through `values[15]`) and a uint32
counter. Event has a kind, declared component index and finite scalar value.
The GUI delivers Open(kind0), action Invoke(kind1) and explicitly declared numeric
change_action(kind2) events with the real component index and finite scalar
value. For legacy template compatibility, an exact design field ID `temperature`
still supplies its current value to Invoke. New generic projects should use
declared action `event_value` and explicit numeric change_action controls;
without that legacy field, an unvalued action receives0. Other enum values are reserved/test inputs; native picks
remain public host event traces rather than automatically delivered C++ events.
The strict entrypoint is:

```cpp
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::invoke) {
        state.counter += 1;
        state.values[0] = host.numeric_add(event.value, 273.15);
        host.number(1, state.values[0]);
        host.text(2, "Synthetic temperature in kelvin; display only.");
    }
}
```

The automatically supplied Host methods are:

| Method | Exact effect |
| --- | --- |
| `text(unsigned component, const char* value)` | Set declared label/status text, bounded UTF-8 literal. |
| `number(unsigned component, double value)` | Set a compatible presentation value; finite scalar only. |
| `flag(unsigned component, bool value)` | Set a compatible boolean presentation control. |
| `numeric_add(double left, double right)` | Public Numeric array_binary.add; finite scalar result. |
| `numeric_sqrt(double value)` | Public Numeric array_unary.sqrt; explicit grant and nonnegative scalar. |
| `numeric_exp(double value)` | Public Numeric array_unary.exp; explicit grant and finite scalar. |
| `diagram_open(unsigned component)` | Bind/create a declared canonical diagram through the existing document owner. |
| `diagram_tool(unsigned component, const char* tool)` | Select an explicitly admitted catalog/edit tool in the shared viewport. |
| `diagram_command(unsigned component, const char* command)` | Invoke bounded existing properties/rotate/delete/fit and editing commands. |
| `scientific_discover(unsigned form)` | Read approved local/registered destination capabilities into the declared form. |
| `scientific_prepare(unsigned diagram, unsigned form)` | Validate the canonical diagram and form; retain deterministic netlist/source receipt. |
| `scientific_submit(unsigned form)` | Submit that guarded preparation through existing Scientific Execution/Script Job. |
| `scientific_status(unsigned form)` | Read the exact current Job state/progress. |
| `scientific_cancel(unsigned form)` | Request cancellation of the exact owned Job; completion is asynchronous. |
| `scientific_reconnect(unsigned form)` | Reconnect the same durable Job without resubmitting. |
| `scientific_log(unsigned form)` | Read bounded actual Job/provider log; offline errors remain visible. |
| `scientific_import(unsigned form, unsigned dataset_selector)` | Publish completed result through canonical Dataset services and set its selector. |
| `plot_discover(unsigned form)` | Read canonical Dataset/Variable metadata for declared waveform controls. |
| `plot_bind(unsigned plot, unsigned form)` | Bind explicit X/Y variables to the existing public Plot owner. |
| `document_bind(unsigned document, unsigned dataset_selector)` | Bind compatible canonical HTML/PDF/Code/Table through the existing read-only CORE owner. |
| `numeric_discover(unsigned form)` | Read actual canonical variables/units without changing explicit row counts. |
| `numeric_evaluate(unsigned form)` | Use declared public Numeric profile; retain immutable canonical result. |
| `numeric_statistics(unsigned form)` | Run the explicitly selected public reduction/statistics and persist its result. |
| `numeric_compare(unsigned form)` | Compare selected observed/reference rows with explicit relative floor via Numeric. |
| `numeric_publish(unsigned form, unsigned dataset_selector)` | Publish captured values/X/units/provenance into the canonical Dataset owner. |
| `demo(unsigned component, unsigned fixture)` | Display-only RAM fixture:0 Native2D,1 Plot,2 Native3D; no scientific source. |

Indices identify components in the exact validated design declaration order,
starting at one. Unknown components, incompatible types, undeclared facilities
and nonfinite/bounded-output violations fail the event. No raw widget path,
framework pointer, Dataset file path, Tcl command or generic expression reaches
the author. SDK implementation pointers remain private and live only in the
isolated worker; no authored library is loaded into the Tk process.

Ordinary C++17 project logic is supported: author-defined types, pointers and
references, templates, virtual functions/RTTI, recursion, callbacks, lambdas,
allocation/RAII, macros/assertions, exceptions, reviewed standard containers and
local threads/fork/wait. Literal0..15 indices apply to the fixed **SDK State
transport**, not ordinary project arrays. Canonical scientific ownership remains
with public Dataset/Schema/Publication, Workspace/History/Recovery, Jobs and Plot.
A private replacement for one of those owners must be corrected through its
existing public API. Extra direct headers/libraries/flags need concrete purpose
and review. Read **Develop → C/C++ support catalog** for exact admitted headers,
Host functions, actual budgets and synchronization fingerprints.

## Profiles and API Browser

Use the **API Browser** tab beside SDK and Profile in the right reference
notebook. **View → API Browser tab** shows or hides that tab. The same Browser is available in Python and GNU Octave Script
Workspaces. Its internal divider shares space between API declarations and
reference text; the project tree keeps the full left-column height. Searching
and reading declarations require neither a scientific Session nor a C++ project.

Family rows describe the actual installed public declarations. Separate provider
children retain distinct declaring owners and versions. SDK exposure, allowed
operations, declared request/result shapes and authorization reasons are shown
where declared. An installed API may still be outside the C++ SDK or unavailable
to the current runtime/project; presence is not permission to invoke it.

Registered Python/Octave operation children show the owner's argument kinds,
required/optional flags, declared conventions/context and result contract. Their
language examples require an active managed Script Bridge. They do not provide
a C++ invoke-any-API method. Undeclared signatures remain explicitly unknown;
consult the owner manual and the C/C++ support catalog for admitted Host methods.

In the C++ Workspace, **Host::method · C++** children show the exact installed
SDK declaration, typed call pattern and required capabilities. Opening a saved
project, saving `project.json`, or pressing Refresh compares its explicit requests
with the same provider/version/profile admission used by Validate.
`ADMITTED_REQUEST` describes that saved request only; Validate must still check
source and declared forms, and runtime checks each finite action. `NOT_REQUESTED`
and `NOT_ADMITTED` explain why an installed facility is unavailable to this
project. A Script Bridge operation in this editor shows its actual C++ mapping,
where one exists, or says explicitly that there is no direct C++ SDK method.
Python and Octave editors show their respective managed Bridge syntax.

The selected reference follows Session open/switch/close using the cached
catalog, without another metadata worker or scientific Job. A Session does not
activate a script. Narrow editors retain readable list/detail panes; their
divider adapts to the actual font size while retaining the Explorer.
Use Select All/Copy in the focused reference, and **Manual** for
the existing Documentation Browser. A manual can be unavailable; its name alone
does not establish a complete reference for every operation. Browsing does not
execute a provider operation, start a Script/Job or change source text.

`synthetic_view_v1` grants the approved GUI/native-demo subset.
`numeric_view_v1` adds the explicitly declared public numerical subset.
Projects request only operations already present in the trusted policy; project
metadata cannot expand that policy. Canonical Workspace/History effects are
outside these initial read-only author profiles; their inert Gallery samples
remain available in Builder. The explicitly admitted `document_view_v1` and
`scientific_view_v1` profiles add declared canonical diagram or Numeric-form
Workspace/History contracts; they require exact public capabilities and source
guards. Existing read-only profiles retain their restrictions. Python authoring
is disabled independently of the ordinary Python Script Workspace.

For missing/disabled/version-mismatched public capabilities, validation creates
`derived/CORE_API_GAP.json` with the requested API/version/operations, closest
known owner and a CORE-maintainer contract request. An installed but unauthorized
operation is **CAPABILITY_DENIED**. Neither condition adds a dependency or uses a
private fallback. After an authorized CORE SDK extension, revalidate explicitly.

## Shared CLI for human developers and agents

The CLI executes the identical policy, compiler, runner, public broker and package
writer as the GUI. Run from the framework directory with an absolute project path:

```sh
core/bin/gxtxt-viewer-dev init /absolute/projects/thermometer --module-id viewer.thermometer
core/bin/gxtxt-viewer-dev validate /absolute/projects/thermometer
core/bin/gxtxt-viewer-dev build /absolute/projects/thermometer
core/bin/gxtxt-viewer-dev run /absolute/projects/thermometer --event '{"kind":1,"component":4,"value":18.0}'
core/bin/gxtxt-viewer-dev test /absolute/projects/thermometer
core/bin/gxtxt-viewer-dev export /absolute/projects/thermometer
core/bin/gxtxt-viewer-dev api /absolute/projects/thermometer
```

JSON results are machine-readable. GUI transport uses `--tcl` over the existing
managed-request protocol, with the same underlying result fields and hashes.
There is no looser agent mode. The packaged Clang 19.1.7 driver requires the tested
Debian libclang-cpp19/LLVM19 and ordinary native system runtime libraries. Its
compiler SHA, package provenance and copyright are under `core/development/toolchain`.
No private task-workspace compiler path is required by a distributed project.

A trusted launcher can give an external author this explicit process-tree grant:

```sh
core/bin/gxtxt-viewer-dev grant /absolute/projects/thermometer -- /bin/bash --noprofile --norc
```

The kernel Landlock grant permits file-content writes, creates/removes and
truncation only beneath that real project directory, while retaining necessary
read access to the fixed SDK/compiler/runtime. Symlinks, hardlinks, special files
and protected project roots are refused. Tested writes to CORE, SDK/policy,
canonical archives and restore assets return EACCES. No sudo or new system
account is required. The GUI backend uses the same grant for build/run work.

This is an explicit tool grant on that process and its descendants, not a claim
that every shell of the existing account is restricted. Landlock does not cover
all filesystem metadata operations; no hostile-native-code certification is
claimed. Compiler/native processes also have finite time, address-space, output
and process-group cleanup limits. See the independent release evidence for the
actual denial/crash/timeout cases, rather than treating source-policy PASS as an
absolute operating-system security guarantee.

The implementation uses the real [Clang AST](https://clang.llvm.org/docs/IntroductionToTheClangAST.html)
and Linux [Landlock](https://docs.kernel.org/userspace-api/landlock.html) interfaces;
its guarantees remain limited to the exact tested project/profile and mechanisms.

## Native GUI walkthrough

![Multifile source tree, independent tabs and actual validation/build controls.](images/multifile-project.png)

![Compiled C++ numeric change event and the genuine public Native3D RAM viewport.](images/native3d-cpp.png)

![Readable source-policy refusal before any author interface construction.](images/policy-refusal.png)

The Native3D example receives a real numeric change event for31°C and displays
304.15K through public Numeric. Its C++ Open event binds fixture2 through the
same public v2 host used by Gallery/Builder. Orbit/pan/zoom remain native.
The runtime retains exact C++/design/project fingerprints; changing any source
requires reopening Demo. CLI and GUI check the source-bound artifact before
build/run, require fresh admission and compilation for changed inputs, and reject
incomplete/stale output. The common footer distinguishes compiled-event state
from the native viewport's separate rendering state.

### Trusted scalar Numeric calls

The native C++ library remains loaded across events. Explicit scalar Numeric
add/sqrt/exp calls use a bounded trusted transport to the same public Numeric
owner; the numerical service does not inherit C++ author memory/CPU/file limits.
The native author budgets remain unchanged. Domain errors discard that event's
UI/state updates, and a later valid request can recover in the same Viewer.
Viewers without scalar grants start no scalar transport. Normal Close, failure
and cancellation drain/reap the owned broker and CORE helper groups.

## Complete copyable source projects

The installed `examples/temperature_native2d/` and
`examples/temperature_native3d/` directories each contain the original
`handlers.cpp`, inert `design.gxtxt-viewer` and exact `project.json` facility/test
manifest. Copy a directory into your writable workspace before opening it.
Both use the same public Numeric conversion and actual renderer owners described
above; neither publishes a Dataset. Read each README for the expected first value.

For a generated catalogue tile, choose a concise design title or set the normal
Viewer descriptor's `short_title` during authorized package review. The full
Viewer name remains available in its title, catalogue tooltip and module metadata.
The official examples use concise captions; their original source designs and
C++ handler bytes remain intact.

## Real restricted C++ debugging

The debugger controls the **actual admitted C++ project source tree**, compiled by the same
fixed Clang19/SDK/AST owner as normal Build/Run. Debug uses `-O0 -g3 -fstandalone-debug` and explicit
source path mapping; GDB/MI runs the same separate native ABI worker. Numeric and
SDK calls retain the exact normal admission/public broker contracts. Debugger
execution and its returned operation plan are distinct from a scientific GUI
submission; no scientific Job is implied by inspecting a scalar event. There is no arbitrary GDB
console or expression evaluator. Compiler options and dependencies remain explicitly reviewed; ordinary project-local process facilities are documented in the support catalog.

Open a declared source/header tab, Save All, wait for source structure, set a breakpoint in the
compact red-dot gutter or with F9, then choose Start Debug. A yellow arrow marks
the actual selected native source line; its lane is separate from folding and
physical line numbers. A hollow red dot is disabled. Blank/comments are refused;
GDB may relocate a requested non-executable C++ line to its actual instruction.
Check the native stop line rather than assuming every source line has code.
Breakpoints are locked during the active immutable Debug snapshot; Stop before
changing them. Source/design/facility changes cancel stale binary execution.

| Control / shortcut | Native meaning |
| --- | --- |
| Run / Ctrl+F5 | Execute the admitted event through the normal bounded worker. On the tested Debian XFWM desktop Ctrl+F5 is reserved for workspace5: use the native Run button or focus it and press Space. The intercepted shortcut is not certified here. |
| Start Debug / F5 | Admit/build the current source and start genuine GDB; while paused F5 continues. |
| Continue | Resume to the next actual breakpoint, failure or completion. |
| Pause | Asynchronously interrupt the running native inferior through GDB/MI. Very short events can finish before Pause arrives. |
| Step Into / F11 | Execute the next source step, entering a real called function. |
| Step Over / F10 | Execute the current statement without entering a called function. |
| Step Out / Shift+F11 | Finish the actual selected executing function and stop in its caller. |
| Stop / Shift+F5 | Cancel the owned managed debugger/native process tree. |
| F9 / Ctrl+Shift+F9 | Toggle / clear editable source breakpoints before a Debug Job starts. |
| Build F6 / Demo F7 / Test F8 | Existing authoring stages; distinct from scientific execution. |

![Actual admitted C++ breakpoint, red dot and distinct execution arrow.](images/debug-breakpoint.png)

The lower **Call Stack** contains actual native function/file/line identities.
Select a permitted frame to inspect its genuine local values and source line;
inspection is not program execution. **Variables** initially shows each struct
or array as one collapsed row. Click its row or disclosure arrow to inspect real
members/elements vertically; click again to collapse. Keyboard Right/Left and
Space also operate the tree. Nested aggregates remain collapsed until requested.
Large arrays retrieve at most64 children per explicit request; use **Load next
members…** for another page. Inspection is limited to depth8 and512 displayed
nodes per stop/frame. New stops, selected frames and continuation discard prior
child identities and expansion state. Values come from GDB, not invented source
evaluation. A value before assignment can be unavailable
or uninitialized; Step Over the assignment before interpreting it. Trusted ABI
and interpreter frames can appear in the native stack. The **Build / runtime
output** tab retains actual structured diagnostics and execution receipts;
**Diagnostics** rows still navigate the source.

![Actual Step Into inside the scalar helper.](images/debug-into.png)
![Actual native call stack after Step Out.](images/debug-stack.png)

Use **View** to hide/reopen Debugger toolbar, Call Stack, Variables, Output and
Diagnostics without destroying source. Source and API panes remain ordinary
splitter panels. Resize or use a narrow window, then restore panels before
claiming layout recovery. Closing cancels the owned active backend. Active
execution remains bounded by the existing CPU/wall policy; paused inspection is
limited to 15 minutes. Stop/timeout/crash discards partial authored UI operations.

![Actual paused debugger at a narrow viewport.](images/debug-narrow.png)

### Worked restricted C++ project

Create a project, use Builder to declare a status/label at component2, then save:

```cpp
int increment(int value) {
    int next = value + 1;
    return next;
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    int first = 2;
    int second = increment(first);
    state.counter = second;
    host.text(2, "Native C++ execution completed");
}
```

This scalar control fixture demonstrates debugger mechanics, not scientific
computation. Break on the call to `increment`, Start, Into, inspect `value`,
Over, Out, then Continue. Observe `state.counter=3` in the actual native result.
For scientific framework operations, use the explicitly admitted public Numeric/Math/Stats SDK contracts. Ordinary local C/C++ computation remains available; new dependencies require review against public scientific ownership.

### Author SDK, Builder and CORE-gap handshake

The same approved CLI supplies `api`, `save`, `check_source`, `validate`, `build`,
`run`, `test`, `export`, `builder`, `facility_request`, `debug`, `debug_status`,
`debug_control`. All post-init stages enforce the existing Linux Landlock
project-write tool grant. This is actual process-tree write confinement, not an
account-wide or hostile-code guarantee. The current allowlist is authoritative;
installed public APIs not admitted to this SDK are discovery only.

`builder` reads typed JSON operation/arguments on stdin and invokes the same
public model/validation/Undo/Redo as the GUI. For example:
`{"operation":"metadata","arguments":["title","Circuit Workbench"]}`.
Icon import uses the same bounded safe PNG/SVG resource owner; logical IDs,
hashes/license and bytes survive export as relative `resources/icons` assets.
For command toolbars, menus and context menus, select the existing command in
Builder's typed Icon Library **Command target** control, then Assign. The
container's `command_icons` dictionary binds resources to its existing action
IDs; icon edits retain those callbacks and true enabled/disabled state. Use the
Builder integrated manual's command-icon walkthrough for supported native menu
states, presentation restrictions, previews and generated/installed examples.
Action `event_value` is an optional explicit finite scalar payload. Unvalued
actions deliver0; changed scalar fields deliver their normalized current value.
The temperature template explicitly declares18; its retained exact-ID
`temperature` field compatibility supplies the current value when present.
Generic projects without that legacy field use explicit payloads/default0.

A missing admitted function must produce a real denied call and a project
`CORE_API_GAP` via `facility_request`. The public API manual defines all required
fields. Requests under `requests/` are immutable and include source/design hashes;
same-ID identical submissions are idempotent, altered submissions are rejected.
The CORE maintainer investigates existing owners, extends the minimal shared
contract and allowlist, then the same author reruns the same failure. Do not
write private Tcl, files, solver processes, math, renderer or queue fallbacks.

Help → Developer manual / F1 opens this integrated reference. Help → About uses
the common documentation service and current installed descriptor metadata.

### Native worker limits, failures and Session scope

The current trusted native worker policy is3 CPU seconds,256MiB address space,
1MiB file output and zero core dump. Debug adds12 seconds of active wall time
and a900-second paused inspection lease. CPU can terminate an admitted busy loop
before the active-wall limit. The actual snapshot/Build-runtime output records
effective policy, state and backend reason. A SIGKILL alone proves a signal,
not which resource limit caused it; the GUI states this explicitly. Read the
diagnostic instead of relabeling every signal a timeout. COMPLETED means normal
completion, CANCELLED means managed Stop/close, REJECTED means source admission
failed before execution, FAILED carries native/backend errors; TIMED_OUT requires
an actual recorded timeout. Stop waits for owned worker/backend cleanup; old
stack/locals/arrows clear and reopening starts neutral.

The scalar C++ debug project is independent of a scientific Session. Switching
Sessions does not turn its admitted local scalar run into a scientific callback.
Installed scientific Viewer operations remain separately Session/source guarded.
The debugger does not grant a GDB console, arbitrary evaluation or direct I/O.

![Actual native signal failure and truthful limit diagnostics at doubled logical scaling.](images/debug-signal.png)

### Read-only inspection, installed native testing and illustrated export

The Source browser opens project files and the supplied SDK. Approved CLI
`inspect --target` accepts declared C++ source/header files, `project.json`, `MANUAL.md`,
`design.gxtxt-viewer`, or `sdk_v1`; it returns exact UTF-8/bytes/SHA and never
executes the inspected text. `api --document VIEWER_GUI_HOST_API_v1` reads a
catalogued public manual without an arbitrary path. Discovery is not a runtime
capability grant; required public operations must also be explicitly admitted
in project metadata and the current SDK/AST policy.

The fixed Numeric companion is available through
`api --document NUMERIC_EXPRESSION_OPERATIONS` (optional `.md` suffix). It returns
the exact installed `NUMERIC_API_v1` expression-operation manual, including
grammar, functions, units and constants such as `pi/e`. The existing fixed
`VIEWER_GUI_DESIGN_v1` companion likewise belongs to its GUI Host owner. These
are enumerated public documents, not new API identities or arbitrary linked-file
readers; unknown/private paths remain denied.

Ordinary C++ troubleshooting can use approved `debug`, `debug_status` and
`debug_control` directly: set practical breakpoints, inspect actual execution
state/stack/locals and step/continue through the documented structured operations.
Wait for actual PAUSED/command completion and keep the source/token guards. A
Viewer author need not manipulate or capture the graphical debugger to diagnose
their own C++ problem. A reproducible infrastructure failure belongs to the
Development Workspace owner; retry the original public operation after its fix.
Public GUI status also returns bounded `host_error/error_code` for an early
compiled-request failure, so a completed scientific Job is not mistaken for a
solver failure. After a diagnosed presentation/infrastructure correction, retry
Poll/Publish on the original Job rather than submitting another simulation.

1. Save/Validate/Build/Test the restricted project, then Export its ordinary ZIP.
   Use normal Plugin Manager Install/Update and honor restart-required status.
2. In a dedicated new private GUI-test Session open the same project in
   Development Workspace. Develop → **Enable installed native GUI testing**
   explicitly attaches only its source-identical normally installed Viewer.
   Fixture designation is a trusted administrator/GUI-laboratory action; author
   code cannot designate original user Sessions or global desktop access.
3. Approved `gui_test` JSON operations include open/status/close, capture,
   logical component click/tab/choice/text, bounded diagram pointer/key/property
   and public Plot-point probing. They perform real native input, guarded by
   source/design/project hashes, attachment identity and Session lifetime.
   Focus scrolling reveals notebook headers/controls before clicking. Hidden,
   clipped, occluded, unrelated or stale targets fail explicitly; no raw Tcl,
   widget path, arbitrary desktop coordinate or outside-Viewer input is admitted.
4. `gui_test capture` returns a genuine PNG capture UUID with owner/Session/source
   receipt. `gui_test` request `{"operation":"capture_preview","capture_id":"UUID"}`
   verifies that live RAM-issued capture and delivers its original PNG as bounded
   `image_content` MIME/base64, SHA, dimensions, source/Session and geometry.
   Preview accepts no file path and is limited to2MiB/4096px; it renders original
   pixels without image processing. Unknown/stale/changed captures fail. While
   that attachment is live and unchanged, add a manual image with
   `manual_asset` JSON `{"operation":"add","asset_id":"circuit-native","capture_id":"UUID"}`.
   Only RAM-issued matching native receipts are accepted; manually forging a
   project receipt cannot admit a file. `list` inspects admitted inventory;
   `remove` removes a binding while retaining historical content bytes.
5. Save inert UTF-8 MANUAL.md through approved `save --file MANUAL.md` (at most
   256KiB, no NUL; ordinary C++ source/project metadata remain64KiB), referring
   to `![Caption](images/circuit-native.png)`. Allowed PNGs are bounded to4096²,
   8MiB each,32 images/16MiB aggregate; symlinks, altered SHA/codec, stale sources
   and external references fail. Historical admitted images keep original
   capture source/version provenance; captions must state that version honestly.
6. Export normally. Existing Module packaging includes exact guide/PNG resources,
   inventory/provenance and license. Install/update with Plugin Manager; restart
   and open Help to inspect figures, full-size links and narrow rendering. A
   packaged image is not evidence that the updated GUI itself has been tested.

![Actual Develop menu exposing installed native GUI testing.](images/development-native-menu.png)

Project reparent preserves all existing SDK declaration positions, including a
control moved into a later-declared parent. Builder hierarchy/Preview derive
construction order; duplicate appends new identities, remove changes indices,
and sibling reorder is a signed layout step. Review structural changes before
building. Existing Numeric sections support explicit expression/interpolation/
complex-projection profiles through the same five methods; API manuals define
typed controls, operation grants, units, explicit row ranges, immutable results,
statistics/comparison/publication and saved restore without recomputation.

Plot forms can reference typed `plot_x_scale`/`plot_y_scale` choices linear/log;
the existing Plot owner validates domains and preserves the last valid frame on
failure. No authored logarithm is needed. Existing source-bound GUI status exposes
bounded native Plot axes/rectangle/tick metadata for real pointer interpretation.
Scientific forms can declare one/two physical sweep axes (component,start,stop,
count,read-only SI unit), enabled/case/admission-worker/fail-fast controls. Public
Numeric creates bounded grids and existing Scientific/Parallel/Script Job services
own actual cases, progress, cancellation and canonical publication. Request the
explicit documented sweep grants; no C++ worker pool or raw array API is exposed.
Restored Job panels identify saved references/last-observed states; Reconnect
reads the same authoritative Jobs without resubmitting. See the public GUI Host
contract for every typed reference and limit.

Use `debug`, `debug_status`, `debug_control` programmatically when they simplify
real C++ troubleshooting. Keep the long-lived Debug request running, poll actual
state/sequence, then send an admitted step/frame/continue/pause/stop with exact
source SHA and optional matching run token. Stack/locals are real backend values.
Report a concise reproducible `CPP_DEBUGGER_BUG` to the CORE owner for correction
and retry of that same operation. Ordinary troubleshooting requires no artificial
exercise or graphical-debugger screenshot; independent GUI QA stays separate.

### Review a saved Workspace after an additive project upgrade

Use **Develop → Review saved Workspace upgrade…** with a saved project and open
Session. Select the earlier canonical Workspace and click **Review selected**.
Inspect the original ID, preserved component count and exact appended controls.
**Create upgraded copy** is enabled only after successful review; it creates a
separately named Workspace, leaving the original payload/revision unchanged.
Close exits the dialog; changing selection disables Apply until another review.
No simulation runs. Normal Workspace export/import copies notes, preview and
nested resources; its archive is added to the original managed resource store.

![Actual independently checked review dialog at its600x400 minimum: original/new canonical rows, scrollable report at the end and all three reachable buttons.](images/workspace-upgrade.png)

This intentionally narrow policy requires unchanged C++ bytes, profile, grants,
existing declaration ordinals, defaults and callback/scientific semantics. It
currently admits explicit existing Diagram/Plot probe links with a new inert
voltage/current selector, inert presentation controls and reserved navigation
commands. Every retained History state, including redo, is checked; C++ values
and counter remain intact. Changed source, unknown forms/bindings, stale Session,
changed original/source, malformed History or a resource/commit failure rejects
the copy. Any failed new allocation is removed. Older scientific states retain
their provenance and any legitimate stale status; copying never certifies old
results against an edited source.

Open the new ID through normal Session Workspaces. Restricted authors use the
same public `gui_test` operations `workspace_review` with `workspace_id`, then
`workspace_upgrade` with the returned live `review_id`, then `workspace_open`
with the returned new ID. An old exact-mismatch `workspace_open` still rejects.
Tokens belong to the current GUI process/Session/project/original revision; a
new review of that pair replaces its prior token. No author migration scripts,
private payload rewrites or new scientific jobs are required. General C++ source
changes need an independently supported compatibility path.

New saved native states include a trusted callback-contract digest. Icon/layout/
version-only changes can preserve Workspace identity and callbacks; actual C++,
grants, action payload, scalar defaults or component identities remain strict.
Live edited projects still require Close/reopen; old Workspaces without the
digest retain exact-snapshot compatibility. No scientific source guard is removed.

## Declared visibility, canonical source inspection and waveform editing

These controls compose existing public Builder, GUI Host, Configuration, Plot,
History and Workspace owners. A declared presentation handler is dispatched by
the existing host; it does not need an authored C++ pane/series renderer, a new
SDK method, arbitrary Tcl, file access or another execution framework. Existing
scientific/diagram grants still apply to the source and result being inspected.
See `VIEWER_GUI_HOST_API_v1` for exact admission and `VIEWER_DEVELOPMENT_API_v1`
for the constrained author tools. API discovery alone grants no operation.

### Typed wire editing and uninterrupted History branches

Select an existing wire stroke and open Properties. Start/End terminal choices
refer to existing stable component pins or explicit junctions. The ordered bend
table exposes typed X/Y fields, Add/Replace/Remove and Move up/down. Add inserts
after the selected row, or appends without a selection. Close discards unapplied
draft changes; Apply commits one guarded canonical route edit with the same wire
ID. The body scrolls and buttons wrap at the480x320 minimum dialog size.
The canonical route supports128 finite bends within+/-1000000 display units;
initial wire drawing retains its64 pending-point bound. Crossings and bends
cannot create implicit electrical junctions. An external source change while
Properties is open requires closing/reopening before Apply.

Invalid values, duplicate component names, invalid endpoints/equal endpoints,
malformed routes and stale sources are refused before a History branch can
discard redo. A valid older-state edit still asks to branch; accepting preserves
the current native editor, selection and focus so the next keyboard edit works.
Cancelling preserves the exact source/History and produces no Tk background
error. Ordinary Undo/Redo/navigation continue to restore their snapshots and may
clear transient selection. Rapid wire end/start clicks at a common explicit
junction remain routing input; only Select-mode double-click opens Properties.

Approved author CLI `gui_test` uses the same public `property` fields `start`,
`end`, `point_x`, `point_y`. `wire_route` accepts `component` and `command`
`add/replace/remove/up/down`, or `command:select` with integer zero-based
`index:0..127`. It clicks the actual owned controls/Tree row and accepts no widget
path or arbitrary route payload. `status.properties.COMPONENT` reports only the
mapped owned wire editor's source receipt, stable ID, typed draft/choices and
visible error. `properties_commit` and `properties_close` click Apply/Close.
Undo/Redo and normal saved Workspace restore retain committed bends/topology.
See `NATIVE_2D_GEOMETRY_API_v1`, `NATIVE2D_VIEWPORT_HOST_v1` and
`VIEWER_DEVELOPMENT_API_v1` for exact operations and source guards.

### Builder checked View controls and retained layout

Select the declared component in Builder and edit its public properties. A
`toggle` or native `checkbutton` declares `component_visibility TARGET_ID` and an
explicit boolean `default`; omit `change_action`. An ordinary `action` can use
the same property with its own distinct presentation handler. For a `menu`,
`context_menu` or `command_toolbar`, declare `visibility_commands` as a mapping
from an existing action ID to the target component ID. Every mapped action must
occur in that surface's `actions`, and its handler must have `effect presentation`.
For example, declare a panel `source_panel`, a toggle with
`component_visibility source_panel` and `default 1`, and a View menu containing
`view_source` with `visibility_commands {view_source source_panel}`. Declare
`view_source` as a presentation handler accepting `{window action}`. The public
Builder JSON route uses the same property validator; inspect its capabilities
before supplying typed property values.

A command has one consistent target even when presented in multiple surfaces.
Multiple booleans for the same target must agree on their default. References to
undeclared/foreign targets, mutating handlers, reserved Undo/Redo/Fit/Zoom IDs or
Workspace/History/Help/command surfaces are rejected. A contradictory declaration
is an error, not a hidden preference. Ordinary command icons, callbacks and true
native enablement retain their behavior; check state means declared visibility,
not command enablement or whichever notebook tab currently happens to be mapped.

Preview and the generated/installed host synchronize boolean values and checked
View/context rows. Hide/show retains the same grid/pack children, notebook pages
and split-pane members in their original order. It keeps widget/native handles,
field values, bindings and scientific source authority. Hiding moves focus out
of hidden content; showing does not steal focus or select an optional notebook
tab unnecessarily. An accepted native boolean/action/menu input records one
ordinary History step. Programmatic restoration synchronizes the committed field
baseline without an authored callback or an extra History step. Undo/Redo and
normal Workspace Save/Open retain visibility; saved state takes precedence over
new-design defaults. Keep a reachable control outside hidden content to show it
again, then test both narrow layout and keyboard focus.

The corresponding public host calls are
`viewerGuiDesignComponentVisible window component boolean` and
`viewerGuiDesignComponentVisibleGet window component`. The latter reports
explicit presentation visibility even for an unselected notebook page. Normal
Module generation records the necessary package compatibility metadata, including a
design without icons.

![Actual cold-opened generic Builder-generated visibility fixture with checked native View rows. This validates shared presentation controls, not restricted Circuit author adoption.](images/declared-visibility.png)

### A distinct canonical source/netlist pane

For an existing circuit Scientific `section` with
`scientific_provider core.ngspice.circuit`, declare all three references:

| Section property | Required declared control |
| --- | --- |
| `scientific_netlist` | A separate read-only `log`; it must differ from the changing scientific Job log. |
| `scientific_netlist_diagram` | The existing `electrical.basic` Native2D component supplying canonical source identity. |
| `scientific_netlist_action` | Its own presentation handler, bound to an ordinary action/menu control. |

The host intercepts that handler and calls
`viewerGuiDesignScientificNetlist window form` through public
`scientificExecutionCircuitInspect`. Press the declared Inspect action explicitly.
With an admitted Job/sweep, it reconstructs the **selected case's** actual
parameters using the same registered converter/version. It checks original
source ID/generation/revision/SHA, provider, Job/case and published canonical
Dataset association/integrity. Current form edits do not relabel a completed
case. Without a Job, inspection uses current declared form parameters. The pane
identifies source/provider/version, parameters, Job and Dataset; its deck is a
validated canonical reconstruction, not a fetched remote artifact or simulation.

The complete deck is limited to32KiB; excess is rejected rather than silently
truncated. Foreign/missing case/publication, changed source/provider or invalid
circuit produces an explicit error while retaining scientific identities. A
changed selection makes an older cache stale until explicit Inspect. The bounded
`scientific_netlists` domain record stores validated context and full text through
normal Workspace/History. Restore displays it only if current canonical context
still matches, otherwise a stale/unavailable explanation. Undo to a state with no
saved inspection clears the old deck; Redo can restore its valid saved cache.
Save/Open, Undo/Redo and hide/show never call the converter, Numeric, submission,
status polling or remote protocol automatically. Keep this read-only pane and
its visibility independent of the Job log and waveform.

![Actual fresh generic source/netlist fixture, restored at820x600 before Inspect: selected retained case parameters and original Job/Dataset provenance. This is not installed restricted-author adoption.](images/canonical-netlist.png)

### Complete declared Plot series/panel profile

Start with a normal Plot form and its canonical Dataset/X/Y/Discover/Bind controls.
Add the following complete profile on its `section`; partial profiles reject:

| Property | Type / role |
| --- | --- |
| `plot_series` | Choice/combobox of current stable trace IDs. |
| `plot_series_label` | String field/entry for the selected trace label. |
| `plot_series_axis` | Choice/combobox with exactly `left right`. |
| `plot_series_enabled` | Toggle/checkbutton selecting trace enablement. |
| `plot_panel` | Choice/combobox of current canonical panel IDs. |
| `plot_panel_title` | String field/entry for a new panel title. |
| `plot_series_target` | The declared Plot whose `plot_form` points back to this section. |
| `plot_series_commands` | Existing action ID to one fixed operation below. |
| `plot_series_status` (optional) | Separate read-only log/label/status with exact canonical IDs and summary. |

All editor controls must be distinct from each other and Dataset/X/Y/probe/
axis-scale controls. Omit their `change_action`: edits stage choices until an
explicit command. Each command is a unique fixed operation with a distinct
presentation handler; it cannot collide with visibility/netlist handlers or
reserved Undo/Redo/Fit/Zoom. Ordinary action/menu/toolbar controls present those
handlers. `viewerGuiDesignPlotSeries window form operation` uses the existing
bound PlotSpec; it has no separate trace store.

| Fixed operation | Exact workflow |
| --- | --- |
| `refresh` | After first Bind, derive current trace/panel choices and summary. It does not add or replace a trace. |
| `load` | Select a stable trace ID and load its actual Dataset/X/Y, label, axis, enabled state and panel into controls; the plotted trace is unchanged. |
| `add` | Select a canonical Dataset, Discover actual variables, choose X/Y, target panel, label, axis and enabled state; retain earlier traces and allocate a distinct `trace_N` ID. |
| `update` | Apply staged source/label/axis/enabled/panel values to the selected ID, preserving its style and unrelated fields. Choose a different target panel here to move the trace. |
| `remove` | Remove the selected trace; removal of the final trace is refused. |
| `up` | Move the selected trace one place earlier within its current panel; the boundary rejects. |
| `down` | Move the selected trace one place later within its current panel; the boundary rejects. |
| `panel_add` | Use the supplied title to append a distinct `panel_N`; select it and Update a trace to populate it. |
| `panel_remove` | Remove only an empty, unannotated panel while another panel remains. |
| `panel_up` | Move the selected complete panel earlier; the boundary rejects. |
| `panel_down` | Move the selected complete panel later; the boundary rejects. |

A changed Enabled checkbox alone stages a value; **Update** applies it to the
selected trace. This differs from `component_visibility`, whose boolean input
immediately hides/shows its target. Refresh/Load can change saved editor controls
and use ordinary History, while coherent trace edits are one accepted History
step. Normal Save/Open preserves the PlotSpec and editor controls; Undo/Redo uses
the same authoritative state. Limits are32 traces,8 panels and single-line
labels/titles of at most160 characters, without newline/NUL.

Plot v4 validates real canonical Dataset/Variable IDs, shared X semantics,
physical unit conversion and the native model before accepting a replacement.
Put voltage/current on different left/right axes or separate panels; incompatible
same-axis units fail without replacing the prior valid specification/frame.
Automatic axis labels derive from actual variables/units, including `i_v1 (A)`;
explicit PlotSpec presentation remains owned by the existing Plot APIs. Keep
Dataset/variable IDs in the summary when two traces use the same display label.
Source-point probes continue to return exact canonical row/values/units; they do
not infer rows by reading screen pixels. These edits do not calculate vectors,
submit Jobs, retrieve remote results or admit arbitrary author scripts.

![Canonical series fixture with retained voltage traces and right-axis i_v1 (A).](images/canonical-series-axes.png)
![Canonical series fixture at820x600: two panels and a shared bottom time axis.](images/canonical-series-panels.png)

### Canonical schematic-to-waveform selection

A complete circuit Scientific section can declare `scientific_probe_diagram`,
`scientific_probe_plot` and `scientific_probe_mode`: the existing electrical
Native2D component, canonical Plot with its `plot_form`, and choice/combobox with
exactly `voltage current`. Use the admitted Diagram Probe tool and click a real
terminal/junction. The shared host verifies current source generation/revision/
SHA, selected completed Job/case, registered CircuitInspect mapping and published
Dataset/Variable provenance. Voltage maps the actual node to V; current uses the
actual independent-voltage-source branch in A. Ground voltage, unavailable device
current, missing variables, foreign publications and stale source report errors
and retain the earlier waveform. Split-complex AC requires an explicit public
Numeric projection; the probe does not compute magnitude/phase implicitly.

For a completed AC publication, the same endpoint click resolves the actual
frequency and split real/imaginary pair into the existing AC Numeric form.
`AC_SOURCE_SELECTED` identifies its Dataset, original Job, physical unit and
exact Variable IDs. The previous Plot/computed result stays valid. In **AC result**
review the preserved explicit row start/count and projection, then choose
Evaluate, Publish and Bind to display that selected signal. Magnitude is V/A;
phase is rad/deg. Selection itself performs no calculation or publication and
does not relabel a real part as magnitude. With one compatible complex form
the reference is inferred; multiple forms need the typed optional Scientific
`scientific_probe_ac_form` reference to the intended `complex_projection`
section. Missing/ambiguous forms, incompatible pair/frequency units or shapes,
ground/unavailable current and stale source retain prior valid selections.

Portable Session import preserves immutable Numeric results. Reopen the imported
Session normally in the Workspace Manager: restoration checks the same Dataset
ID, complete persisted record and metadata checksum, result owner and immutable
Document identity, plus the scientific source guard. Only the carrier directory
may change. No vector is recalculated and no Job is submitted. Changed inputs
still require a new explicit Evaluate. Subsequent statistics, comparison and
publication bind a temporary operation request to the current Session and keep
strict current-source checks; the original stored result/provenance is untouched.

The existing scoped grants are `SCIENTIFIC_EXECUTION_API_v1.circuit_prepare`,
`NATIVE2D_VIEWPORT_HOST_v1.diagram_command` and
`PLOT_DATASET_API_v4.widgetCreate`. History/Workspace retain canonical source,
Job, Dataset, Variable and mode; no new endpoint/vector accessor, process or
scientific authority is granted.

### Native source cursor, view navigation and recovery

Declare ordinary presentation handlers with reserved IDs `fit`, `zoom_in` and
`zoom_out` to expose existing Fit/Zoom actions. The host navigates compatible
retained views, including canonical Plot panels; these are view commands, not
scientific callbacks. A Plot with a declared form uses the same native source hit and canonical one-row
read as ordinary probing. Release on a real computed point to show exact row,
values and units and place a persistent crosshair. The host stores two existing
PlotSpec `reference_line` annotations, `__gx_source_cursor_x` and
`__gx_source_cursor_y`, on that series' actual left/right axis; no authored overlay
or numerical calculation is used. Non-source/blank hits leave it unchanged.
Wheel zoom, middle-button pan, declared Fit/Zoom and resize retain the cursor.
Focus the Plot and press **Escape** to clear only these two reserved annotations;
Undo restores and Redo clears them. An ordinary new Dataset/variable **Bind**
clears the old cursor as part of the new binding. Invalid logarithmic domains
retain the previous valid frame and report the reason; correct controls and Bind
again rather than assuming a blank frame is a new scientific result.

Save/Open retains canonical cursor lines and current Plot binding. On cold
restore, the readout explicitly says no canonical row has been reselected;
release on a computed point to inspect current exact source text. Saved lines
alone are not proof that a row was freshly inspected. Public trusted callers use
`viewerGuiDesignPlotCursor window plot device_x device_y` and
`viewerGuiDesignPlotCursorClear window plot`. Restricted authors use the existing
declared presentation controls and bounded source-bound `gui_test` gestures;
only Escape is admitted for a mapped, unobscured, bound declared Plot, with no
active pan. Other Plot keys/foreign/hidden/stale targets remain denied. A warm
GUI owner receipt does not certify fresh external CLI projection of every field.

![Canonical Workspace restore: saved crosshair and explicit no-row-reselected readout. Reopen performs no computation or simulation.](images/canonical-source-cursor.png)

### Discover shared original icons through the approved tools

In **Icon Library → Add shared icon…**, choose a declared original source from the shared
catalog. Its category/license come from the distributed catalog and the actual
source SHA is checked before import. **Import** remains available for other
owned PNG/safe-SVG files. Assign a normal icon and optional state variants using
the existing typed controls; imported images become ordinary project resources.
The library includes electrical devices, selection/wiring/junction/probe tools,
Undo/Redo, Fit/Zoom and debugger controls. Preserve accessible action text and
tooltips, and inspect actual normal/disabled/selected states at the target size.

Restricted authors discover these same sources with this exact Builder request:

```json
{"operation":"icon","arguments":["catalog"]}
```

Read `builder.catalog.icons` for IDs, titles, category, license, admitted source
paths, SHA256, format and dimensions. Use a returned path with the existing
five-argument `icon_import`, then apply typed component icon properties.
Discovery takes no path or extra argument and changes no design/Undo/Redo file;
the ordinary request provenance receipt is retained. It grants no filesystem
reader or new C++ capability. Invalid/missing/linked catalog assets fail clearly.

Builder retains its existing50-step Undo/Redo model. The complete persisted
history has a separate512MiB ceiling so a legal icon-rich design is not mistaken
for an oversized single design; each design remains bounded to4MiB. Normal
Builder inspection and Undo/Redo preserve every retained state. Before committing
an edit, CORE checks the design, history and response sizes; ordinary write
failures restore the original design/history files and report the error. There
is no crash-atomicity claim or manual history-deletion recovery step. Restricted
Builder response limits are16MiB at CORE/64MiB through the GUI request transport;
ordinary source/C++ limits and runtime SDK permissions remain unchanged.

![Actual native Add shared icon chooser lists the29 original distributed sources.](images/shared-icon-sources.png)
![Actual imported Voltage resource retains its declared title, Electrical category, license, source SHA and four native state previews.](images/shared-icon-metadata.png)
![Shared Builder Preview glyphs at16/24 pixels with normal and disabled native control states.](images/shared-icon-native-sizes.png)

Safe SVG group paint is normalized before the existing bounded decoder, including
inherited fill/stroke and paint opacity; group opacity and transforms retain
their meaning. Original source bytes/SHA remain exact. Previously imported blank
PNGs are persisted resources: reimport the same source through ordinary Import
and replace its existing logical resource via the public icon owner, retaining
bindings. A repaint or theme change does not repair an already admitted PNG.

### Reviewed additive Workspace copies and validation scope

An exact-snapshot mismatch still refuses ordinary Open. For supported additive
presentation changes use Development **Develop → Review saved Workspace
upgrade…**, inspect **Review selected**, then **Create upgraded copy**. Review is
read-only; Apply creates a separate canonical Workspace with lineage. Close the
assigned Viewer before source-bound `workspace_review`, `workspace_upgrade` and
`workspace_open` requests. The full Development manual describes unchanged
source/profile/grants/ordinals, all retained History states, live review-token
lifetime, stale-source/resource failures and explicit managed archive side
effects. Arbitrary C++ evolution is not an automatic compatible upgrade.

### Save only the assigned Workspace through approved tools

After editing a restored Viewer, finish any compiled callback and pointer/pan
gesture, then pass this exact JSON object to `gui_test PROJECT`:

```json
{"operation":"workspace_save"}
```

There are **no extra fields**. Do not supply a target Workspace ID, title, notes,
path, serialized payload, widget, provider or foreign window. The source/Session-
bound Development owner calls the same public
`sessionWorkspaceViewerAction ... save` as the assigned Viewer's ordinary
Workspace menu. A declared normal Session Workspace lifecycle must already
exist; this operation does not create another persistence service or bypass its
normal confirmation, changed-source, stale-Workspace, History-branch and commit
checks. Busy execution, an unfinished pointer gesture, stale attachment/Session
or foreign target fails explicitly. No new C++ runtime capability is granted.

Inspect the returned `workspace_id` and canonical `workspace_stamp` (ID,
generation, revision and SHA), alongside actual values/bindings/domain state.
The stamp comes from the saved canonical Workspace, not from submitted author
content. To check persistence, close this assigned Viewer with the existing
`close` operation, use `workspace_open` with that returned canonical ID and wait
for the real compiled restored state. Verify exact source/Job/Dataset/Plot,
visibility, netlist cache, cursor, C++ and History identities; reopening reads
saved results rather than resimulating or submitting again. A Save failure is
not a completed commit; retain the error and recover through the normal owner.

### Inert manual bounds and exact illustrated export

Approved `save --file MANUAL.md` and `inspect --target MANUAL.md` allow at most
**256KiB** of inert UTF-8 without NUL. `handlers.cpp` and `project.json` source/
metadata transfers remain bounded to **64KiB**. Ordinary-file/no-link/project-
write guards and the existing admitted relative PNG rules remain unchanged.
Oversize, invalid encoding/NUL, links or arbitrary targets reject while retaining
the earlier saved guide. Normal export preserves exact guide bytes in installed
`MANUAL.md` and `source/MANUAL.md`; the inert guide does not grant runtime I/O or
execute source. The current SDK policy uses `manual_limit_bytes=262144`. The manual remains inert
and source/package checksums preserve its exact authored bytes. A screenshot or
successful Save does not establish scientific correctness or complete release
acceptance; inspect the actual operation and public persistence receipts.

## Readable API reference with larger Appearance fonts

The right **API Browser** tab uses the shared reference browser. Search and
surface selection stay above the API list; **Refresh** reloads declarations.
**Manual**, **Previous** and **Next** share a responsive footer with full
tooltips. Select a list row to read its scrollable reference below the sash.
Successful searches release the status row; pending requests, errors and empty
results keep visible status feedback.

Resize the sash to divide list and details. The layout retains three API rows
and four reference text lines, plus Diagnostics' heading, one row and scrollbars.
The ordinary-font minimum client is 980×650. A larger saved Appearance font
requires a taller measured minimum window; attempts to resize below that height
are clamped by the window manager. Captions and source fonts retain the selected
size. A taller window gives Diagnostics more space. Save Appearance changes and
restart GX-TXT normally to apply the chosen font.

![API Browser with persisted Appearance18: native family/method glyphs, selected real SDK reference and source remain readable at the measured taller minimum window.](images/api-browser-readable-rows.png)

API Browser family and method rows use the existing shared UI Field inspection
font and row padding. The native row height follows the saved Appearance font,
and the three-row minimum uses those actual rows. This does not autosize the
Browser's declared columns on queries or replace a deliberate horizontal pan.

Project file dialogs use the shared UI Field requested geometry and screen bounds, including larger Appearance fonts. The file-name entry and Add/Rename/Cancel actions follow their font sizes; no fixed220-pixel height is imposed.


## Per-file Markdown Notes — DEV111-P030

Use the primary **Edit → Edit Notes** command for the selected source file.
**View → Show Notes** hides or shows the same adjacent note page; it retains the
draft and its Undo/search state. Notes use the shared Markdown editor with Source,
Rendered, Outline, Properties and Resources views. Insert images through its
existing image command. Source and Rendered have independent selection and copy.
Find and Focus Source act on the selected note. Python/Octave temporarily give
Notes the source region and restore the prior code panels when returning to code.

Explicit Save publishes the note as a canonical Markdown Dataset in the current
Session. Without a Session, Save retains an explicit local note; attach it when a
Session is available. Save All and portable Project export preserve per-file
notes and their PNG resources through the existing source-owner snapshot.
Save As/Save Copy create fresh source/note identities and preserve the original.
Notes do not change source code, build inputs or scientific execution hashes.
If another editor changes the source or note, saving refuses and retains the
draft; review the current revision or use Publish New to preserve a separate copy.

Opening an associated note from the Dataset Browser returns to that exact file's
Notes page when its source remains available. Otherwise Documents opens the same
canonical Dataset. Associated Source is read-only and shows only the exact
matching source, with an explicit diagnostic if it has changed or disappeared.

![Notes associated with the actual C++ source file, alongside the existing SDK reference.](images/p030-notes.png)

Notes associated with the actual C++ source file, alongside the existing SDK reference.

Formatting is in **Edit → Note format**, including headings, emphasis, code,
lists, tables, links, quotes, rules and text color. **Edit → Note images** opens
the shared PNG chooser and provides Replace/Remove for the selected managed
resource. **View → Note panes and zoom** controls Source, Rendered preview,
Outline, Properties and Resources independently, with zoom and layout reset.
These groups act on the currently selected note and are unavailable on code
pages. Portable images remain read-only until explicit Session attachment.

## Acquisition plugin source projects

The CSV recipe editor remains the simple INI workflow. Its File menu can also
open the adjacent **Acquisition Plugin Builder**. In that window, File → New
project chooses a parent directory; fill the Module ID, version, name, license
and declared dependencies, then File → Save project metadata. The normal
Development service creates a genuine Acquisition project (`project.json` and
registered C++ source), without a Viewer canvas/design or an invented parser.
Opening an existing project validates its actual target and source closure before
replacing the displayed context. No scientific Session is required for authoring.

Project → Add profile declares a module-local profile ID, human name and
`text`/`binary` source kind. Its published identity is `MODULE/PROFILE`. Filename
patterns and MIME hints are not content-recognition proof. Bind Recognize,
Inspect and Import to registered source files and actual qualified C++ symbols;
fill output contracts and profile dependencies. Capability and limit declarations
use the shared Source Surface's typed JSON editor. The normal backend checks
structure; only a matching current AST receipt can make a callback
`validated_ast`. Unknown contract strings remain declarations, not fabricated
compatibility. There may be zero profiles in an unfinished project, but real
Build/Export requires eligible saved callbacks. Source registration alone never
means a parser has compiled, a helper has executed or a Dataset has been imported.

Module metadata also supports typed capabilities, provenance and test declarations.
In Module metadata, **Edit configuration fields…** declares an ordered JSON array
of up to32 scalar settings. Each field supplies `id`, `type`, `label`, `default`
and `required`. Types are `string`, `integer`, `number`, `double`, `boolean` and
`choice`; choices also supply `values`, and numeric fields may supply `min`/`max`.
For example, `{"id":"enabled","type":"boolean","label":"Enabled","default":true,"required":false}`
uses a JSON Boolean. The generated `format_profile` setting is reserved. Keep
draft retains the declaration locally; Save project metadata persists it through
the same whole-project revision checks. Missing fields in an older source project
appear as an empty array. Actual Module settings/defaults and their persistence
remain with the normal framework configuration owner.

**Edit input Contract declarations…** retains an ordered JSON array of literal
IDs, for example `["table.generic","model/step"]`. **Edit provided Contract
declarations…** retains definitions with exactly `id`, `description` and `parents`
(an ID array). Up to64 input IDs and64 definitions are supported within the
existing source-size limits. Keep draft and Save project metadata use the same
typed editor and revision checks. Duplicate IDs, self-parents and local cycles
refuse without replacing the saved source. Unknown external parent IDs remain
declared data. These source declarations do not insert entries into the active
Registry: CORE decides installed providers, dependencies, compatibility and actual
scientific Dataset admission. An older project without either field reads as [].

The shared JSON source editor keeps Find/Replace collapsed initially. Its Edit
menu or Ctrl+F/H reveals the same search controls; Escape returns to source.
Arrays display one encoded item per line, preserving typed values. Invalid JSON
shows its refusal in the dialog and retains the text for repair; semantic field
errors refuse Save without replacing the saved project or discarding the draft.
Save metadata and Save profile are distinct primary actions. Unsaved changes in
the other form remain local drafts. New/Open/Refresh/Close review changed drafts;
Yes starts the current form's asynchronous Save and keeps the context for review,
No discards the reviewed local changes, and Cancel keeps editing. A stale full
project revision/file/profile SHA refuses without replacing the current buffers.
Refresh explicitly reviews and reloads the saved project; it never silently
retries a stale mutation against a newer context.

File → Open source workspace delegates to the existing Development Workspace.
Its File menu adds/imports/renames/removes registered C++ translation units,
headers and typed Tcl/Python helpers. Use `src/*.cpp`, `include/*.hpp`,
`helpers/*.tcl` or `helpers/*.py`, with explicit helper ID and entrypoint for
scripts. The existing policy permits32 compiled files plus32 helpers,64KiB per
file and1MiB total registered text. The shared Source Surface preserves exact
UTF-8, BOM and CRLF bytes and provides the existing selection/clipboard/search
and source-tab behavior. Opening and cancelling an Add dialog does not save a
changed source; Apply first saves current changed sources through the same CAS
owner. Source rename preserves bytes and lets the owner update declared profile
file bindings atomically. Removing a still-referenced file refuses; change its
profile bindings explicitly first. Save All preflights the whole registered
closure, so an external helper edit can correctly refuse a save of another file.
An outside edit or recovery conflict preserves buffers and explains the refusal.

Source notes are enabled only when the target/backend and that exact source row
admit the existing Source Note service. An unavailable target must show its actual
reason; it must not create a second note store or label a Tcl helper as C++.
Registered C++ sources/headers and Python helpers use their actual language and
the same Source Note owner. Tcl helpers retain editable source but do not offer
Notes. Select the note page before using Save source (Ctrl+S): it saves that
note, without replacing the source code. Without a Session this saves a local
project draft; in an applicable Session an explicit Save creates or updates the
canonical source-associated Markdown Dataset. Save All also snapshots canonical
notes and their managed images for the existing source-project portability owner.
Closing or switching projects reviews unsaved note buffers. A stale whole source/
helper revision refuses without silently retargeting the note or discarding text.
While a Note is selected, the existing workspace temporarily collapses the SDK
reference pane and hides diagnostics and the duplicate code Find row. Returning
to code restores their prior layout and focus; optional reference-tab choices,
code buffers, Undo and queries are retained. The Note's own Find controls start
collapsed: Edit → Find or Ctrl+F reveals them, and Edit → Replace in Note or
Ctrl+H reveals the same replacement controls. Escape from Source or any Find/
Replace control collapses that row and returns focus to the Note source without
clearing its query or changing the text.
Run → Validate checks the actual saved project and callbacks; changed declaration
forms use the existing Save/Discard/Cancel review before a request starts. A
matching current AST receipt enables Build and Export candidate. Build uses the
normal Acquisition toolchain, and Export candidate uses the ordinary package
writer; its actual package path appears in status. The selected profile remains
selected through this refresh. Status shows the first compiler diagnostic; full
diagnostics and output are available through File → Open source workspace in its
existing Diagnostics and Build / runtime output panels. A refused validation
does not make a profile eligible or replace a previous candidate package.

The SDK tab uses the fixed readonly current-target inspector: Acquisition SDK v1
for an Acquisition project, and the original Viewer header on a Viewer project.
Its bytes and SHA are checked before display. An unavailable inspector reports
that state instead of substituting a Viewer header. The API Browser binds the
saved Acquisition project to its declared capability requests. In a current
catalog its eight AcquisitionHost method references identify the actual target
header and distinguish requested/admitted reference metadata from unrequested
methods. This reference admission is separate from source/AST validation, Build
and active runtime grants. No Viewer design is required for an Acquisition
reference context. Trusted maintenance stays an unbound reference catalog. Test/
runtime buttons remain disabled when the actual backend reports unavailable;
compiled code or a normal candidate ZIP is not proof of native runtime admission.

Actual parser recognition/inspection, selected RAW grants, progress/cancellation,
full Test, typed outputs, publication/rollback, Group and independently installable
package/Preview admission remain with the existing CORE Acquisition and restricted
Development/toolchain services. A profile's public permissions and dependencies
are declarations until those services admit them. The GUI never supplies an
actor override, arbitrary compiler command, source read grant or canonical write
path. Follow the actual backend diagnostics and ordinary Module install workflow;
this source-project screen is not a vendor-format compatibility claim.

### Acquisition project Test (P032)

The primary **Run → Test** command in Acquisition Plugin Builder and **Develop → Test**
in its C++ source Workspace share one CORE selection/configuration dialog. Choose
1–64 ordinary files, an actual saved format profile and typed configuration.
Configuration values here are transient Test overrides of the declared defaults;
they do not change ModuleCfg, Configuration or a Session Manifest. Cancel keeps
source and drafts. Changed source revisions refuse and require a fresh review.

`VIEWER_DEVELOPMENT_API_v1` retains its `test` operation. For an Acquisition target
its `request_json` uses `gxtxt.acquisition_project_test.v1` with `expected_revision`
(from public ProjectFiles `describe`), `profile_id`, absolute chosen `sources`,
and optional typed `config`. The complete request is bounded to64KiB; files are
bounded to2GiB aggregate and the actual native Test to60seconds after admission.
No private Tcl command is required. `project_test_available` is distinct from the
Viewer-style `runtime_available` flag; Acquisition has no synthetic Viewer Demo.

Test uses the existing normal candidate exporter and distributed native admission
without installing/registering the module. The same Source Grant checks full SHA,
the existing guarded broker executes the actual compiled callbacks, and the same
typed buffer owner verifies/seals then discards provisional outputs after reap.
No Session, Registry entry, Dataset, Dataset Group or scientific publication is
created. The current producer/profile/config/source closure remains pinned;
foreign profiles, stale revisions, unknown config, FIFO/linked sources, protected
producer replacement and malformed output identity refuse. The private
`derived/acquisition-test.json` reports actual guard, configuration and source
identities, discarded output schema/SHA and reap; it explicitly does not certify
scientific correctness or final installed-module behavior. Normal Plugin Manager
admission and real canonical import/rollback/GUI acceptance remain separate.

Before source-Workspace Test, the existing public ProjectFiles description is
refreshed so saved profiles and configuration from the other Builder window are
current. This adopts metadata only when module identity and registered source
closure are unchanged. Source/Notes widgets, local drafts, Undo and layout remain
in place. Test retains its explicit Save All/CAS behavior for local source edits.
An outside source/roster or module identity change refuses with review/reopen
guidance; it never silently reloads a draft.
