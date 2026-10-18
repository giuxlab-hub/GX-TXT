# Viewer Development Workspace

Create and edit a restricted C++ Viewer without opening a scientific Session.
Open **Viewers → Interface Tools → Viewer Development Workspace**. The adjacent
Viewer Interface Builder remains the visual design owner; its Component Gallery
supplies display-only examples through the same public native constructors.

## Project workflow

1. Choose **New project** and an existing parent directory. The environment creates
   a new project directory, source skeleton, inert Builder design, facility
   requests and provenance. An existing nonempty project is never overwritten.
2. Edit **C++ handlers** in the shared source editor. Native selection, Copy/Paste,
   Undo/Redo, Find, syntax colors, physical lines and supported folds belong to
   Source Surface. This environment does not offer a C++ native debugger.
3. Save source with **Save / Ctrl+S**. A dirty close asks Save, Discard or Cancel.
   The Builder design and generated reports are read-only here; edit visual
   hierarchy/properties with the existing Interface Builder.
4. Choose **Validate / F5**. This runs the real Clang raw lexer, then resolved AST
   admission and project/facility checks. Validation does not produce object code.
   Diagnostics identify file, physical line, column and reason; double-click a
   diagnostic to select its source line.
5. Choose **Build / F6**. The same validation runs again before a fixed compiler
   command creates the author object and trusted adapter, then links a bounded
   native library. Source, SDK, policy, design, compiler and binary SHA are retained.
6. Choose **Demo / Preview / F7**. Policy is checked before constructing the
   declared interface. C++ events execute in a separate bounded worker. The
   public CORE applies only typed admitted UI operations to the actual Viewer.
   The default Open event creates the same Native2D RAM fixture used by Gallery.
7. Invoke **Run C++ handler** in Preview. The sample uses public Numeric
   `array_binary.add` to convert the synthetic value 18 to 291.15 kelvin, updates
   a numeric readout, writes a constant explanatory label and increments state.
   It creates no scientific Dataset, Workspace or publication.
8. **Test / F8** exercises the compiled handler through the same backend. Inspect
   its explicit event/state/output receipts; a passing source-policy result alone
   is not a native GUI or scientific correctness result.
9. **Export candidate** revalidates/rebuilds and creates a normal Viewer ZIP with
   source, Builder design, trusted facade, SDK contract, native binary, provenance,
   validation/build reports and checksums. Export does not install. Review and
   promotion use the ordinary Plugin Manager.

The bottom notebook separates diagnostics from bounded build/runtime output.
Complete JSON receipts remain in `derived/`; the GUI truncates very long display
logs explicitly. **Cancel** terminates only the request's owned process tree.
Closing a Preview cancels its own native request and releases native children.
Another Preview or the original scientific data is not its cleanup target.

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
same project-write tool grant as CLI. Invalid C++/JSON can be saved for repair,
but cannot pass future Build/Run admission. No code runs on import. The compiler/AST policy must admit source before any
native execution. No authored Tcl hook, build script, external header or alternate
compiler command is accepted. Reopening the same project preserves its original
source bytes. A changed source/design during validation or execution is refused
rather than silently applied to another revision.

## Configure a real event test

`project.json` contains `tests` with 1–8 typed `events`, an `expected_counter` and
an `expected_values` map whose keys are scalar slot indices0–15. The generated
sample runs Open, Invoke18 and Invoke20; expected counter2 and slot0=293.15.
Test compiles and executes those events in order, carrying returned state into
the next bounded worker invocation. Inspect `derived/tests.json` for every
actual event and public Numeric receipt. These developer expectations cannot
change the source policy or replace independent GUI/native acceptance.

## Exact C++ SDK v1

CORE automatically supplies `gxtxt_viewer_sdk_v1.hpp`. Authors write no includes.
The SDK exposes `gx::Host`, `gx::State`, `gx::Event` and `gx::EventKind`. State has
sixteen bounded scalar slots (`values[0]` through `values[15]`) and a uint32
counter. Event has a kind, declared component index and finite scalar value.
The GUI delivers Open(kind0), action Invoke(kind1) and explicitly declared numeric
change_action(kind2) events with the real component index and finite scalar
value. A design field named temperature also supplies its current value to the
sample Invoke action. Other enum values are reserved/test inputs; native picks
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
|---|---|
| `text(component, literal)` | Update a declared label/status with a UTF-8 literal of at most 256 bytes |
| `number(component, value)` | Apply a finite scalar to a compatible declared presentation control |
| `flag(component, value)` | Apply a boolean to a compatible declared presentation control |
| `numeric_add(left, right)` | Call actual public NUMERIC_API_v1 `array_binary.add`; return its finite scalar |
| `numeric_sqrt(value)` | Call public NUMERIC_API_v1 `array_unary.sqrt`; numeric profile, requested capability and finite nonnegative input |
| `demo(component, fixture)` | Bind a matching display-only RAM native fixture: 0 Native2D, 1 Plot, 2 Native3D |

Indices identify components in the exact validated design declaration order,
starting at one. Unknown components, incompatible types, undeclared facilities
and nonfinite/bounded-output violations fail the event. No raw widget path,
framework pointer, Dataset file path, Tcl command or generic expression reaches
the author. SDK implementation pointers remain private and live only in the
isolated worker; no authored library is loaded into the Tk process.

Supported syntax is deliberately small: automatic scalar locals, ordinary scalar
expressions, if/switch/loops, scalar helper functions, fixed event/state references
and enumerated SDK member calls. Array indices must be literal 0..15. Recursive
call graphs, globals, namespace/type definitions, external declarations, function
pointers, casts/address-taking, allocation, lambdas, assembly, exceptions and
unrecognized AST forms are rejected. This is not the full C++ standard library.

There is no authored `#include`, macro/pragma, module/import, precompiled header,
include search path, linker flag, dynamic loading, native GUI toolkit, I/O,
filesystem/network/process facility, stdio/iostream, standard math library or
private scientific fallback. Use approved public numerical facilities for
scientific operations. A missing SDK facility requires CORE review.

## Profiles and API Explorer

**Public APIs** lists the actual installed module API descriptors and registered
CORE discovery entries. It shows provider, version, availability, exposed SDK
subset, allowed operations, request/result shapes and exact authorization reason.
An API may be installed and still be outside the SDK. No generic Invoke-any-API
button is provided.

`synthetic_view_v1` grants the approved GUI/native-demo subset.
`numeric_view_v1` adds the explicitly declared public numerical subset.
Projects request only operations already present in the trusted policy; project
metadata cannot expand that policy. Canonical Workspace/History effects are
outside these initial read-only author profiles; their inert Gallery samples
remain available in Builder. Python authoring is disabled, independently of the
ordinary Python Script Workspace.

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

![Source project, public API subset and actual validation/build controls.](images/workspace.png)

![Compiled C++ numeric change event and the genuine public Native3D RAM viewport.](images/native3d-cpp.png)

![Readable source-policy refusal before any author interface construction.](images/policy-refusal.png)

The Native3D example receives a real numeric change event for31°C and displays
304.15K through public Numeric. Its C++ Open event binds fixture2 through the
same public v2 host used by Gallery/Builder. Orbit/pan/zoom remain native.
The runtime retains exact C++/design/project fingerprints; changing any source
requires reopening Demo. CLI and GUI revalidate before build/run and discard
incomplete/stale output. The common footer distinguishes compiled-event state
from the native viewport's separate rendering state.

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
