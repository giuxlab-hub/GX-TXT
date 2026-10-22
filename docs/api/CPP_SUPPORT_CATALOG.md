# Current C/C++ Viewer support catalog

Generated from the installed Development policy, SDK and runtime owners. Open this catalog from **Develop → C/C++ support catalog** in the Viewer Development Workspace. The existing rendered Markdown manual window provides find, links and scrolling.

## Language and ownership

C++17 including C facilities.

functions, pointers/references, classes/structs/enums/unions, inheritance/virtual dispatch/RTTI, overloads/templates, recursion, callbacks/lambdas, malloc/free/new/delete/RAII, containers/algorithms, preprocessing/macros/assert, exceptions, threads/synchronization, fork/wait.

Debian system libc/libstdc++/libm/pthread; extra libraries and compiler options require purpose-specific review

Local project logic/data/concurrency are allowed. Canonical Dataset/Schema/Publication/Session/Workspace/History/Job/scientific Plot remain public CORE responsibilities. Language admission does not approve an architectural bypass.

The compiler performs real Clang parsing and checks the fixed public on_event ABI and typed Host calls. Ordinary local C/C++ functions and standard library facilities supplied by the admitted headers are available, subject to their actual Debian implementation. Headers below are the exact direct-include admission list; transitive system dependencies are supplied by those headers. A new direct header, dependency or compiler/link option requires a concrete purpose and MAIN architectural review. Language availability does not grant a competing canonical store, scheduler or scientific renderer.

## Admitted headers and review decisions

Exactly 46 explicitly admitted header identities. Each row records the facilities/purpose and architectural decision; all are accepted for local project logic, with CORE public ownership retained. Presence here establishes admission, not exhaustive testing of every library function or platform.

| Exact header | Facilities, purpose and architectural review |
| --- | --- |
| `vector` | Reviewed local application containers; canonical Dataset access stays in public CORE |
| `array` | Reviewed local fixed-size application containers |
| `list` | Reviewed local application sequences |
| `deque` | Reviewed local application queues |
| `map` | Reviewed local application key/value state, not a canonical store |
| `unordered_map` | Reviewed local application indexes, not a canonical store |
| `set` | Reviewed local application sets |
| `unordered_set` | Reviewed local application sets |
| `queue` | Reviewed local application traversal/queues, not a CORE Job scheduler |
| `stack` | Reviewed local algorithm/application stacks |
| `memory` | Reviewed RAII and smart pointers for project memory |
| `utility` | Reviewed move/forward/pair facilities |
| `algorithm` | Reviewed local application algorithms; no replacement scientific service |
| `functional` | Reviewed callable wrappers/callbacks |
| `string` | Reviewed project strings; SDK transport remains bounded |
| `string_view` | Reviewed non-owning strings; respect lifetime and SDK transport |
| `tuple` | Reviewed local typed values |
| `type_traits` | Reviewed templates/type introspection |
| `typeinfo` | Reviewed ordinary RTTI/polymorphism |
| `exception` | Reviewed C++ exception lifecycle |
| `stdexcept` | Reviewed project error handling |
| `new` | Reviewed allocation/placement/lifetime |
| `limits` | Reviewed type bounds |
| `thread` | Reviewed local application threads; managed CORE Jobs remain authoritative |
| `mutex` | Reviewed local synchronization |
| `condition_variable` | Reviewed local synchronization |
| `atomic` | Reviewed local synchronization |
| `chrono` | Reviewed local time/duration measurement |
| `cassert` | Reviewed genuine native assertions |
| `assert.h` | Reviewed genuine native assertions |
| `cstddef` | Reviewed size/pointer types |
| `stddef.h` | Reviewed size/pointer types |
| `cstdint` | Reviewed exact-width local types |
| `stdint.h` | Reviewed exact-width local types |
| `cstdlib` | Reviewed allocation/conversion; inspect actual process/file use for CORE ownership |
| `stdlib.h` | Reviewed allocation/conversion; inspect actual process/file use for CORE ownership |
| `cstring` | Reviewed bounded project memory/string handling |
| `string.h` | Reviewed bounded project memory/string handling |
| `cstdio` | Reviewed project-scoped I/O; never private canonical Dataset/Workspace access |
| `stdio.h` | Reviewed project-scoped I/O; never private canonical Dataset/Workspace access |
| `cerrno` | Reviewed native operation diagnostics |
| `errno.h` | Reviewed native operation diagnostics |
| `unistd.h` | Reviewed fork/_exit local process workflow; not a replacement CORE execution service or canonical file bypass |
| `sys/types.h` | Reviewed native pid/type declarations |
| `sys/wait.h` | Reviewed wait/waitpid for own forked child lifecycle |
| `pthread.h` | Reviewed ordinary local thread/synchronization facilities |

## Supported public Host functions

Only these currently compiled SDK methods integrate the C++ author with GX-TXT. Each still requires its explicit compatible project capability, component/form and version. Discovery of another public Tcl/Script API does not admit an arbitrary C++ call.

```cpp
void text(unsigned component, const char* value) const;
void number(unsigned component, double value) const;
void flag(unsigned component, bool value) const;
double numeric_add(double left, double right) const;
double numeric_sqrt(double value) const;
double numeric_exp(double value) const;
void diagram_open(unsigned component) const;
void diagram_tool(unsigned component, const char* tool) const;
void diagram_command(unsigned component, const char* command) const;
void scientific_discover(unsigned form) const;
void scientific_prepare(unsigned diagram, unsigned form) const;
void scientific_submit(unsigned form) const;
void scientific_status(unsigned form) const;
void scientific_cancel(unsigned form) const;
void scientific_reconnect(unsigned form) const;
void scientific_log(unsigned form) const;
void scientific_import(unsigned form, unsigned dataset_selector) const;
void plot_discover(unsigned form) const;
void plot_bind(unsigned plot, unsigned form) const;
void document_bind(unsigned document, unsigned dataset_selector) const;
void raster_bind(unsigned viewport, unsigned dataset_selector) const;
void raster_tool(unsigned viewport, const char* tool) const;
void raster_command(unsigned viewport, const char* command) const;
void tex_command(unsigned form, const char* operation) const;
void em_command(unsigned form, const char* operation) const;
void workbench_command(unsigned form, const char* operation) const;
void catalog_refresh(unsigned form) const;
void catalog_inspect(unsigned form) const;
void catalog_action(unsigned form, const char* action) const;
void numeric_discover(unsigned form) const;
void numeric_evaluate(unsigned form) const;
void numeric_statistics(unsigned form) const;
void numeric_compare(unsigned form) const;
void numeric_publish(unsigned form, unsigned dataset_selector) const;
void demo(unsigned component, unsigned fixture) const;
```

Presentation operations run through the shared GUI Host. Numerical methods use Numeric; canonical diagrams use Native2D/Interactive Document; scientific forms use Scientific Execution/Jobs; scientific graphs use Plot v4. document_bind uses existing HTML/PDF/Source Surface/paged Dataset consultation. catalog_refresh/inspect/action use a declared GUI Host section and the existing Scientific Library Manager, with exact per-action grants; they do not expose a generic invoke or scientific library parser. demo is explicitly a RAM demonstration and cannot establish scientific acceptance.

tex_command uses a complete declared TeX form and finite GUI Host operations. Source Surface, canonical TeX Workspace/Resource, managed native TeX builds, PDF consultation and File Publication retain their existing ownership. Build saves the guarded draft before running the typesetter; installed C++ execution still uses the packaged binary. The additive nonvirtual method/opcode30 preserves old Event/State/Host storage and operations1–29. See VIEWER_GUI_HOST_API_v1 for exact form and lifecycle contracts; source admission is not installed Viewer acceptance.

New Viewer scientific 2D and 3D graphs require PLOT_DATASET_API_v4. PLOT_DATASET_API_v3 is deprecated and denied for new restricted declarations/source/build/export/runtime admission; preserved historical consumers keep their existing compatibility API.

## ABI, compiler and runtime

```text
--no-default-config
-std=c++17
-x
c++
-Werror
-fno-color-diagnostics
-pthread
-isystem
/usr/lib/gcc/x86_64-linux-gnu/14/include
```

The trusted adapter links a shared library with system libstdc++, libm and pthread (-shared -pthread -Wl,-z,defs -lstdc++ -lm). The SDK is automatically supplied. The event handler is void on_event(gx::Host&, gx::State&, const gx::Event&). State has sixteen double slots and one unsigned counter; these are bounded public event transport, not a restriction on ordinary local C++ types or project memory. Host callbacks use bounded finite values/text and enumerated operations.

Development validates and builds once per actual source/build dependency version. Preview, Test and Export reuse the retained binary; closing and reopening an unchanged project does not rebuild it. Installed packages distribute native/viewer.so. Plugin admission verifies that artifact and SDK compatibility; normal installed startup/events load it directly without compiler/linker invocation or a silent rebuild fallback. Missing/incompatible artifacts require a precise error and a compatible package. No development compiler is needed to execute a compatible installed Viewer. Local compiled events use the existing managed persistent worker and apply their public GUI plan before the next queued pointer action; scientific Jobs remain asynchronous.

Current admission/build budgets: source 65536 bytes; compile 30 seconds; active event wall budget 12 seconds. The native worker currently applies CPU3s, address-space256MiB, output-file1MiB and no core dumps. These are actual execution budgets, not a claim of hostile-code security or a general language prohibition. Purpose-specific legitimate workload changes need owner review.

## Integrated debugger

GDB/MI supports breakpoints, Continue, Step Into/Over/Out, Pause/Stop and stack-frame selection through the managed Development owner. Read-only opaque variable identities provide real struct/array children: all aggregates initially collapsed; click to expand vertical fields/elements, click again to collapse. Children load only on request, in pages of at most64; maximum depth8 and512 displayed nodes per stop/frame. A further page is explicit. Each new stop/frame/continuation invalidates old child identities. Unavailable or optimized-out values retain actual debugger diagnostics. No arbitrary GDB console/expression injection is exposed.

Threads and fork/wait are admitted ordinary project logic. This catalog does not promise additional debugger thread-switch or follow-fork controls: the present enumerated control contract remains authoritative. Authors are encouraged to use the integrated debugger for actual development problems and report reproducible CPP_DEBUGGER_BUGs.

## Synchronization fingerprints

Generated by the catalogued integrated-next cpp_support_catalog.py; regenerate on every admitted-header/SDK/compiler/runtime/debugger change, and require --check before final packaging. These fingerprints describe the exact current inputs; scientific/installed acceptance remains in the independent release matrix.

| Input | SHA256 |
| --- | --- |
| `core/development/policy_v1.json` | `b0b8115c624297c86e5eb390d46e5380f2c1494b225c5b8d24a1202dd2f49ca2` |
| `core/development/sdk/gxtxt_viewer_sdk_v1.hpp` | `759849a88f9d615625f0273df021c2bb3f8e6f2c029028a1597a2bd96ac2b1f0` |
| `core/python/gxtxt_cpp_policy.py` | `0f3d450622d930a6d0fbc82fb98ded6776495e9da17085d7701494729c13671f` |
| `core/python/gxtxt_viewer_development.py` | `b30103b3f8b297ac8a1065594e8711eed52ed903593d980eaa15ed4ba8cde897` |
| `core/development/sdk/trusted_adapter_v1.cpp` | `076e08612eba8e1b1ae4990df6485b211ae08d255a7858ea2ecefc882c0d3b66` |
| `core/python/gxtxt_viewer_native_worker.py` | `88d8f65978a61a2726980d8da8bfd44b742636fe55fcbb54c4c0f20ab9e7c034` |
| `core/python/gxtxt_viewer_cpp_debug.py` | `6abca62a74b369ebe694118de8ef3fa26b164b83a99f36a6e3ad2451e378d555` |
| `plugins/modules/viewer.development_workspace/api/debugger.tcl` | `88b5b978cfbc5d38032db2e823dea8dbf47a02eb8c5e8a1565220846ac25b614` |
| `plugins/modules/viewer.development_workspace/api/workspace.tcl` | `4d9885f8b44b4749a75ce611eb5b62bbef850dae6e40ffcf6984598b19510037` |
| `core/tcl/viewer_development_api_v1.tcl` | `cd43bf70687d82a6d960b3f219057880a1b62d6531113ae072dfc4b4286a0c7d` |
| `core/tcl/viewer_development_request.tcl` | `7b2d2d734b3f2d2de828adfdf0a5de616347e864269e0746bfe8241882f69718` |
| `core/tcl/script_job_api_v1.tcl` | `93a54ab8b2669886bf1f1418c1bfc8e3e82b5395e7dd7662a8dee22850dcf88a` |
| `core/tcl/plugin_install_api_v1.tcl` | `f15c80106860effa9e7f3595e7bb72946e86254ceda5a1ae3b31e390fe33b74b` |
