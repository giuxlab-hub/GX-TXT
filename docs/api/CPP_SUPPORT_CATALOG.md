# Current C/C++ Viewer support catalog

Generated from the installed Development policy, SDK and runtime owners. Open this catalog from **Develop → C/C++ support catalog** in the Viewer Development Workspace. The existing rendered Markdown manual window provides find, links and scrolling.

## Language and ownership

C++17 including C facilities.

functions, pointers/references, classes/structs/enums/unions, inheritance/virtual dispatch/RTTI, overloads/templates, recursion, callbacks/lambdas, malloc/free/new/delete/RAII, containers/algorithms, preprocessing/macros/assert, exceptions, threads/synchronization, fork/wait.

Debian system libc/libstdc++/libm/pthread; extra libraries and compiler options require purpose-specific review

Local project logic/data/concurrency are allowed. Canonical Dataset/Schema/Publication/Session/Workspace/History/Job/scientific Plot remain public CORE responsibilities. Language admission does not approve an architectural bypass.

The compiler performs real Clang parsing and checks the fixed public on_event ABI and typed Host calls. Ordinary local C/C++ functions and standard library facilities supplied by the admitted headers are available, subject to their actual Debian implementation. Headers below are the exact direct-include admission list; transitive system dependencies are supplied by those headers. A new direct header, dependency or compiler/link option requires a concrete purpose and MAIN architectural review. Language availability does not grant a competing canonical store, scheduler or scientific renderer.

## Project source closure

One existing Viewer project contains handlers.cpp plus declared src/**/*.cpp translation units and include/**/*.hpp local headers. source_files is ordered with the unique handlers.cpp entrypoint first, at most32 files/64KiB each/1MiB total. The same official lexer/AST admits every translation unit and local header against an immutable complete source snapshot; fixed SDK linking includes every admitted unit. Source manifests retain path/role/size/SHA plus complete source/project digests. Any declared source/header edit invalidates stale runtime/build/package/debug identities. Literal reviewed includes use # or %: directives with phase2 splices; macro/external/escaped includes, numeric source remapping, trigraph/embed and header-existence queries require review. Ordinary/raw string content is inert. No authored compiler/build hook is available.

Independent Source Surface tabs retain per-file dirty state and Save All preimages; file add/rename/move/remove and checked editable package reimport delegate to the same Development owner. Original GDB/MI frames retain authentic full source names and normalized project_file identities across helper translation units and executable headers. External/native frames stay external; pending breakpoints do not establish an executable stop.

## Admitted headers and review decisions

Exactly 46 explicitly admitted header identities. Each row records facilities and the architectural decision for local project logic; CORE ownership remains authoritative. Admission is not exhaustive functional or platform acceptance.

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
void document_command(unsigned document, const char* operation) const;
void raster_bind(unsigned viewport, unsigned dataset_selector) const;
void raster_tool(unsigned viewport, const char* tool) const;
void raster_command(unsigned viewport, const char* command) const;
void tex_command(unsigned form, const char* operation) const;
void em_command(unsigned form, const char* operation) const;
void workbench_command(unsigned form, const char* operation) const;
const char* input(unsigned component) const;
const char* data() const;
void cad_command(unsigned component, const char* action) const;
void diagnostics_command(unsigned form, const char* operation, const char* request = "{}") const;
void text_runs(unsigned component, const char* runs_json) const;
void table(unsigned component, const char* rows_json) const;
void catalog_refresh(unsigned form) const;
void catalog_inspect(unsigned form) const;
void catalog_action(unsigned form, const char* action) const;
void numeric_discover(unsigned form) const;
void numeric_evaluate(unsigned form) const;
void numeric_statistics(unsigned form) const;
void numeric_compare(unsigned form) const;
void numeric_publish(unsigned form, unsigned dataset_selector) const;
void dataset_group_review(const WorkspaceValue& dataset_ids) const;
void dataset_group_create(const WorkspaceValue& definition, const WorkspaceValue& review) const;
void dataset_publish_batch(const WorkspaceValue& request) const;
WorkspaceValue dataset_producer_result() const;
void script_library_command(unsigned form, const char* operation, const WorkspaceValue& request) const;
const WorkspaceValue* script_library_result() const noexcept;
void scientific_preview_command(unsigned form, const char* operation, const WorkspaceValue& request) const;
const WorkspaceValue* scientific_preview_result() const noexcept;
void scientific_frame_bind(unsigned viewport, unsigned form) const;
void comparison_command(unsigned form, const char* operation) const;
const WorkspaceValue* comparison_result() const noexcept;
void analysis_command(unsigned form, const char* operation) const;
const WorkspaceValue* analysis_result() const noexcept;
void demo(unsigned component, unsigned fixture) const;
Workspace workspace() const;
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

## Scalar Numeric transport

Persistent native author limits remain CPU3s/address-space256MiB/file-size1MiB and wall12s. Explicit scalar add/sqrt/exp grants use a conditional pre-limit trusted transport to the exact original broker_message/core Numeric owner, matching the nonpersistent broker boundary. It is not a numerical implementation, scheduler, registry, compiler or new SDK permission. Bounded typed framing/frozen hashes/exact grants and existing supervisor identities/subreaping drain broker plus CORE groups on normal close, failure, cancellation and parent death. A Viewer without scalar grants starts no child. Domain failure discards event UI/state and permits a later valid event in the same native library. Cancellation cannot unwind through ctypes as an uninitialized success.

## Producer-scoped Dataset Groups

Producer-scoped Dataset Group clients add `Host::dataset_group_review`,
`Host::dataset_group_create`, `Host::dataset_publish_batch` and
`Host::dataset_producer_result` under existing Group v1/Publication v2 explicit
capabilities. They use finite typed requests to the existing owning-thread
producer service, with no Numeric form or hidden component. Requests are at most
48 KiB; Review accepts 0..64 IDs and batches 1..64 outputs. Full revisions remain
opaque UTF-8 strings. Native typed numbers remain finite double/int64; Script
Bridge numeric arrays retain the existing writer's NaN/missing-value policy.
Receipts arrive for the next event and identify operation, status, increasing
sequence and event generation. Failures replace old success with a fresh failed
receipt and null result. Grouped batches require explicit Group Create as well
as Review and Publication; ungrouped batches need no Group Create. Original ABI 1
package binaries remain compatible without rebuild. Full flow and limits are in
[VIEWER_DEVELOPMENT_API_v1](VIEWER_DEVELOPMENT_API_v1.md).

## Finite Script Library and scientific Preview clients

The admitted `script_library_command` / `script_library_result` methods use
[SCRIPT_LIBRARY_API_v1](SCRIPT_LIBRARY_API_v1.md), with actual module, declared
form, event, Session and Registry admission. Source-file read availability is
distinct from canonical writer authority. Restored drafts require explicit
current-owner review before a separate Save; a Workspace never carries that
authority. This host/native interface is not a generic Script Bridge Tcl command.

`scientific_preview_command`, `scientific_preview_result` and
`scientific_frame_bind` are finite clients of
[PREVIEW_COMPONENT_GUI_API_v1](PREVIEW_COMPONENT_GUI_API_v1.md); their typed
contracts are detailed in the
[scientific managed Preview client](SCIENTIFIC_PREVIEW_NATIVE_CLIENT_v1.md).
CORE owns exact canonical reads, scientific scope, plane rendering and temporary
presentation. Method discovery grants no filesystem, mutation or publication
authority. Actual supported operations require their explicit admitted grants.

## Integrated debugger

GDB/MI supports breakpoints, Continue, Step Into/Over/Out, Pause/Stop and stack-frame selection through the managed Development owner. Read-only opaque variable identities provide real struct/array children: all aggregates initially collapsed; click to expand vertical fields/elements, click again to collapse. Children load only on request, in pages of at most64; maximum depth8 and512 displayed nodes per stop/frame. A further page is explicit. Each new stop/frame/continuation invalidates old child identities. Unavailable or optimized-out values retain actual debugger diagnostics. No arbitrary GDB console/expression injection is exposed.

Threads and fork/wait are admitted ordinary project logic. This catalog does not promise additional debugger thread-switch or follow-fork controls: the present enumerated control contract remains authoritative. Authors are encouraged to use the integrated debugger for actual development problems and report reproducible CPP_DEBUGGER_BUGs.

## Generic comparison client

`Host::comparison_command(form, operation)` and `Host::comparison_result()` use
the declared reciprocal Builder Comparison profile. CORE validates actual source
IDs/revisions/SHA/provenance, owns bounded read-only Library consultation, delegates
all numerical preparation to Numeric and mounts the same native Plot v4. No raw
samples, Tcl, paths, administrative commands or implicit Dataset publication are
granted to C++. Request the actual `COMPARISON_PLOT_API_v1/comparison_command`,
`NUMERIC_API_v1/comparison_curves` and Plot `widgetCreate` capabilities. Library
use additionally needs the five explicit read-only discovery/content operations
listed in COMPARISON_PLOT_API_v1.md. Missing grants refuse explicitly. Normal
compiled Workspace lifecycle uses the existing native get/save grant and actual
Workspace component; History retains its separate Recipe grants.

The normal Builder File menu creates the discoverable profile. Source selection
is a Workspace UI draft; the prepared scientific configuration is the existing
PlotSpec. Details and scientific limits: [Comparison API](COMPARISON_PLOT_API_v1.md).

## Synchronization fingerprints

Synchronized by validation/dev111_p035_main/prepare_cpp_support.py from the current explicit inputs below. Its --check mode verifies these generated facts before packaging while retaining the reviewed explanatory sections. This is source/SDK declaration inventory; independent scientific, functional, original-ABI and installed-package acceptance remains in the release evidence.

| Input | SHA256 |
| --- | --- |
| `core/development/policy_v1.json` | `9be634bd797e7d8d04f051129d0ff084cc191fc2215a0958806ebeb3929f055a` |
| `core/development/sdk/gxtxt_viewer_sdk_v1.hpp` | `cadcfcaf2f4e36e5159f782d248478dc4f49101c793564cabeffe30b0b68c816` |
| `core/python/gxtxt_cpp_policy.py` | `0822274b6e3e98ce890eb42be85d916463ff25fbb3bba42a3fb09d4b94f5e5bf` |
| `core/python/gxtxt_viewer_development.py` | `905c74dbbcd8b9a677fbe7e221e744e445f05fb77fcf77f50baa270aa9ecdf37` |
| `core/development/sdk/trusted_adapter_v1.cpp` | `09fffc74b595b05a4ae0ba88be100e1f4631320f5e5d8f19b96a7ac2ca9e345b` |
| `core/python/gxtxt_viewer_native_worker.py` | `8f14c496c9275c59e3e1faa7a3b54eb270639ce82c833bf425c9fc167609de94` |
| `core/python/gxtxt_viewer_scalar_broker.py` | `007748202c53ad9240df5128662f1a8be12969ced73faec35dd22b1181c87324` |
| `core/python/gxtxt_viewer_cpp_debug.py` | `f74968107fbb00830cded8f51b2b233fbb475008f5ae605117ccfcf566ac4931` |
| `plugins/modules/viewer.development_workspace/api/debugger.tcl` | `6e972051776cde4029f120c2b92a48225d318994f3511536c8393f56cbc2ff9d` |
| `plugins/modules/viewer.development_workspace/api/workspace.tcl` | `90c5eac55c4698d29de77c9125fd761374ef6b8865a50a18ec7a65689a9395e3` |
| `plugins/modules/viewer.development_workspace/api/project_files.tcl` | `f21339f2ffe2d3645fce736df02880c7642947962e43c043dd87007bebf8cf55` |
| `core/tcl/viewer_development_api_v1.tcl` | `752c48e0f11de66406fce4c1efed5639e660f46cdaf4965c27ed7306503f9374` |
| `core/tcl/viewer_development_api_browser_v1.tcl` | `3fc519c0d4bf4092f3e631eeaa08246616daed5504c1687d4821054436a55c15` |
| `core/tcl/viewer_development_project_workspace_v1.tcl` | `310b6d9eaa2aee3638ff0b61b436ba8f014f8b7dfc852ffaad86373eddd002a6` |
| `core/tcl/viewer_gui_catalog_v1.tcl` | `d86127b847f7f1ce3a1695f012822b9850916a897030e8056357c18f1b662367` |
| `core/tcl/viewer_gui_design_v1.tcl` | `632f3055ebc0cbdc335f5c906d1b9dd3073b1ff464d75e506fd0ae69a7bc650d` |
| `core/tcl/viewer_gui_document_v1.tcl` | `ecc51d4bbd02ee00b2ec26c84be48ac6a568c2389412816c67b3c009685a0d9c` |
| `core/tcl/viewer_workspace_native_v1.tcl` | `106de5006ebede66f69eb3261ac1f3979dc6bbc434320e7d9c8433b0e16f589c` |
| `core/tcl/workspace_scientific_codecs_v1.tcl` | `0dee1f462b805246d7a0d1bc945c2f1cb51f7c37a3704dd47fc03d571e45b312` |
| `core/tcl/ui_field_api_v1.tcl` | `3c905a59388ebc24383614e92e596acffa88cf4cc0a10ae02163fd6618e099b0` |
| `core/tcl/ui_field_viewer_regions_v1.tcl` | `0cf9be6874e6f7223f6f96aa7cd8032fd3fe3b3b2f671edee1a9306175f2d54a` |
| `core/tcl/viewer_development_request.tcl` | `9119ca97fda8d8d07930124555ae1bbfb632b375d485e2c341c564beba3e54c3` |
| `core/tcl/script_job_api_v1.tcl` | `d829077d0473ad5c3606a4dc6e01378aaf6f22c955713cc93835e47a92bb478e` |
| `core/tcl/plugin_install_api_v1.tcl` | `073ad32036029eb4855de19c2a7f835ef97ed21651a7f6499b0867b388b5636f` |
| `core/tcl/viewer_dataset_producer_v1.tcl` | `08e9c1811e3c694b0d4bfe32797ca26fc014c5bd4e52cf004c8333f0a1981e9e` |
| `core/tcl/dataset_group_api_v1.tcl` | `9157fa531dc85d0e52d663f90886e89e62c59d1374bb79461ffd4dff862ed05f` |
| `core/tcl/dataset_publication_api_v2.tcl` | `821eac96cd9793a50c8c5fcd956b04bac3a7a5656547c5e5855f69b2da976528` |
| `core/python/gxtxt_script_bridge_server.py` | `49159939ec80d4ac775bd3d7cf3e530289c1efcddd7fe8d105901fc716326ac7` |
| `core/tcl/workbench_extension_api_v1.tcl` | `1f572da3c40a2d64650482ef8283d127fa4b47511c319e4830d289cf519ff9d8` |
| `core/tcl/uml_document_api_v1.tcl` | `dc8647a8e9591675ca300ad30f24e94aea351152c37a6a5767b33983bbfe323a` |
| `core/tcl/uml_editor_v1.tcl` | `a79d34c59c7098f823545ace8c86da058d31da816966c3e72e258ffef1b999a4` |
| `core/tcl/document_edit_v1.tcl` | `5591ab755eb37b0ca25fb92c73b4a7f16dc3659f3861bb00b425e6c9ec6801fa` |
| `core/tcl/markdown_navigation_v1.tcl` | `546fdc04abc4e0b56f3f751ee384e4d5f035ec6474d632d0d0b7386a303b5505` |
| `core/tcl/dataset_notes_api_v1.tcl` | `00df9699ca4ed5da7c53667c0a89edef1877b2fbec36477a5cc882bc81b19330` |
| `core/tcl/viewer_development_preview_v1.tcl` | `5b6d6f0fa2ed6fa9aa2df796fbdf30b77f29b4827995a4ca1532806c97a333e1` |
| `app/gui/dataset_preview_live.tcl` | `c81828b71d27c34df951475b4b1f6f9de01c794dd545359d2c0bf141dbef34fb` |
| `core/tcl/dataset_preview_provider_v1.tcl` | `4e4d39172ae2459804b32250f215b2cc57d42eea281c25900555bee80429905a` |
| `core/development/sdk/gxtxt_acquisition_sdk_v1.hpp` | `2a379c29e18f9cf565bb9876bec791eaad7408aec125249b3511067db4cbfe90` |
| `core/development/sdk/trusted_acquisition_adapter_v1.cpp` | `da41f4d7964f2d74184a4464aa41754e8bf5f0d979e4d3b1e200c0aab3d99ee3` |
| `core/development/acquisition_policy_v1.json` | `ad9789192f51e0d28e955411c1d35561cbc1ff73500675892e494616d59d4c6c` |
| `core/python/gxtxt_acquisition_project_v1.py` | `adce5f43b515df084088f7522d96c306c754925deb447baf8e82524527f4ba37` |
| `core/python/gxtxt_acquisition_cpp_v1.py` | `90455714bd62372f36053c53f2e8287f1d07a7a72739b35cfe1fc3ae7fc39947` |
| `core/python/gxtxt_acquisition_development_v1.py` | `8afb746803f79c5c03c0ead71ac193b4ac26bd3885a808dac9267470ac95cf1b` |
| `core/python/gxtxt_acquisition_source_v1.py` | `b095454a30e916ebe97c08984d81fc6314d6d67e22ed081ac35a9498815fe58f` |
| `core/python/gxtxt_acquisition_output_v1.py` | `3ac9896b05610fe2fdaacce58ee3e4f1c851958825574401766a55457b499f28` |
| `core/python/gxtxt_acquisition_broker_v1.py` | `21aa54be4510a3a43206ff8ec40692c8b8758f751ee2113a8fc6e8a29147dbb0` |
| `core/python/gxtxt_acquisition_native_worker_v1.py` | `13b7df1671152fd310df4f848bc1837321689865aa07ac780133cd9168ec0eb6` |
| `core/python/gxtxt_acquisition_host_service_v1.py` | `7451b9eecb21ba3d632ec76bf2bdd507e35f8fef16ee815dbf1cdebb0c862ce9` |
| `core/python/gxtxt_acquisition_helper_broker_v1.py` | `d76c7a886b1f659a378382040d7751066d92429719a7181514a9ff7bd89bca36` |
| `core/python/gxtxt_acquisition_helper_worker_v1.py` | `36aa3eb7aedde00f2ea13c6932b23f3332447d5256a20e67b78c9458e08b875b` |
| `core/python/gxtxt_acquisition_project_test_v1.py` | `c927e8d20181880529464a63d816026d1a41708401fab4720495b6f7f75ac29d` |
| `core/python/gxtxt_preview_generation_v1.py` | `4605667fe7578b12df087907540bc9888156eb7844e499a2afb115fda3cd638c` |
| `core/python/gxtxt_native_read_policy_v1.py` | `5d440c9bc178e0953b5cf7fa9609c777bfbfbd2062e33e0bcd21f7555ba01be3` |
| `core/tcl/acquisition_native_v1.tcl` | `9e11cbaa4bf2bf1831898a468254ac190848774ef8bb8eb635899a887edef95d` |
| `core/tcl/acquisition_publication_v1.tcl` | `30399b54dcd21841fb790a3f5d13c37503a5ca3d8bef9a89691b46898b8aef62` |
| `core/tcl/viewer_development_acquisition_test_v1.tcl` | `0588e29d9e49601164ba2fa71779e0d8ba37a5d2fa51ae98d9ca1397167ffdf3` |
| `core/tcl/viewer_development_preview_numeric_v1.tcl` | `f6aec10429366391504db7f15b93559870ada6fb62410e1ba51f3648d72cb2f4` |
| `core/tcl/viewer_gui_numeric_preview_authoring_v1.tcl` | `84aabe1a4ed309f3a2b2e8be7d42291e3ca887127e36c59cae66f12497e08a93` |
| `core/tcl/configuration_modules_v1.tcl` | `e1b182aa1c8079cc5b78d369223f1bac05943f5d1eff3c80ee9b7187ffd2e39d` |
| `plugins/modules/viewer.development_workspace/api/acquisition_project.tcl` | `2f8509aed452410624fe512f95121bfada356e00c1d6831b544b93a67c3e502d` |
| `app/gui/acquisition_plugin_builder_dialog.tcl` | `f31def6b6bda2307f68e6735bd71c00ec0a2892af89e57f8a3ebbcbe3e093deb` |
| `plugins/modules/viewer.interface_builder/api/builder.tcl` | `411deb9c379009802efcce57460f67fc18af2064cd57de1fcb8419d091171d27` |
| `core/tcl/dataset_preview_gui_v1.tcl` | `9d915dc9a238b4616109fa2d015558d5c2982d6814015739c84a510ea500dce0` |
| `core/tcl/script_library_host_v1.tcl` | `ddc5ce65db13205d5f70adabc812b5c70deaeee743894acc08b2e2961a742c1b` |
| `core/tcl/script_library_launch_v1.tcl` | `588f5463d812fae7bf142c001c1d8de18ee49d2d654a4d3ac5e9be592ad3fbd9` |
| `core/tcl/script_library_history_v1.tcl` | `cc6c553558c32c8fb40ce754b6f13c56ae11468511fd1620b820f95ed5b21dc4` |
| `core/tcl/script_registry_identity_v1.tcl` | `49164eb5fd9d8c52b69742afb497add7b44fbd60244d53e3f648ceb468baca62` |
| `core/tcl/script_registry_transactions_v1.tcl` | `02aa8cf0c8e17fe6012a30226f02167c50d89036849578cc35900843bc82b2da` |
| `core/tcl/viewer_native_clients_v1.tcl` | `d797c2e63ce6f5e2b1c88033583ea52ce1180bd2cf79888bdb2d7ceef6d7c1ee` |
| `core/tcl/viewer_script_library_workspace_v1.tcl` | `396f7e54f7247521687c4c3c840a5f7f9a418908475e5c9412555b6945ad4409` |
| `core/tcl/viewer_scientific_preview_v1.tcl` | `5136021446c4fe514fc6e24cd8c8f584368105090258ed574493708933e78ebe` |
| `core/tcl/script_provided_api_v1.tcl` | `c81de05bff585bdc6a0ee17e93b31d13d01b260efc1c928b3bab79924fd06f86` |
| `core/tcl/script_execution_api_v1.tcl` | `b531865f6767637bae02c4c25629b67c528b621a56f9c7fd3fe4a52de3a5e018` |
| `core/tcl/source_surface_api_v1.tcl` | `2188093a939bb28521a7a93478885c852e60c9c6e28798f3f3cf6d0244878359` |
| `core/tcl/viewer_gui_comparison_presentation_v1.tcl` | `cadbbb6d04ac728f576c735bda5fc1c28259264e537416ef986375367d10b433` |
| `core/tcl/session_workspace_gui_host.tcl` | `368e2571ebc55bbf3c4a9c961825f4f4a5b835790b6f4652f306bff0a4642fe1` |
| `core/tcl/comparison_plot_api_v1.tcl` | `21b5c04164d83028e0d9571e587cc59c5bdeacf350b39ce2df08f2bb342de0b7` |
| `core/tcl/viewer_gui_comparison_v1.tcl` | `1b3e1b4043bbb670c03651d753fd5b4ca0df62dd1f3d313b054e95fdae2557c6` |
| `core/tcl/viewer_gui_comparison_design_v1.tcl` | `1a4524459277b9febb1138e58d2bb587cf4da6e58c434d8830aa9991c1550fae` |
| `plugins/modules/plot.dataset/api/plot_dataset_api_v4.tcl` | `b9cb95bb49589858fa4ee4c8749d9bdc8a81ac0ea87123962952619c1b438b55` |
| `plugins/modules/plot.dataset/api/plot_dataset_api_v2.tcl` | `ceb53b974185b93d6e0e4d9180bb52a65a69bc61a7ac3c5c71b440368caf7df9` |
| `core/tcl/dataset_preview_api_v1.tcl` | `67ef890dacea2e84a0f48be0333d781ce86c0f4bcfa522cab716bc4f7aa2bfb4` |
| `plugins/modules/math.numeric/api/numeric_api_v1.tcl` | `7c9828794e917778d47e8cff2df233ad312f73310054d649fd7a885e1eaf7e13` |
| `plugins/modules/math.numeric/api/octave/gxtxt_numeric_comparison_curves_v1.m` | `43971c85940f7b0baa5bd2ffdcfd2653a06828706a85f1d630ccb83a9c667189` |
| `plugins/modules/math.numeric/runtime/gxtxt_numeric_worker_main.m` | `44010674f4b7fd62abf13be2dcb6340c76e9924035feec23f5f0323da9f7c5f1` |
| `plugins/modules/math.numeric/api/operations_v1.tsv` | `66a80f8d39a476bab7d18fe4e921600904d2c92f40fffd12a9a372062f4a8056` |
| `core/tcl/viewer_gui_analysis_v1.tcl` | `d5f5cfd6fd0d62f759d5a11651d0471618c5d21853dc9d8adc1b48e13a347990` |
| `core/python/scientific_library_graph.py` | `e46a2c1951246383c1e03b5e4ab9c5c5d547d4c4e6df716ade1be47a0d9f1f41` |
| `core/python/scientific_library_manager.py` | `df3dedfd5774001ae5b1774c0b4188bf767d505fb992ad8736e710f23933f869` |
| `core/tcl/scientific_library_browser_v1.tcl` | `323ad5374615aae731a7c10bc123ef6f4fdf7aaafa51f903b233d12ca82c4cb2` |
| `plugins/modules/viewer.interface_builder/api/analysis_profiles.tcl` | `dbad0bf2c13100203622158c9adcf6fc50db605623369d86b0e05aa6f16107a1` |
| `core/tcl/project_experiment_management_v1.tcl` | `081b66943a6adfeabda7a2705e307d066e046da85ace5501d18d21782a67b7b9` |
| `core/tcl/native2d_presentation_v1.tcl` | `dbb597e3051e84c342d969ff3b04444012828096a2be4a42573aca2a6024a986` |
| `core/tcl/scientific_recipe_history.tcl` | `acc68a034433d38dbad27f3a02e245bdfb6687c2b2bff0b0a86fb797f21dbcb0` |

## UML Document client

ABI-v1 `Host.document_bind`/`Host.document_command` (operations26/41) add declared
`kind=uml`, with `mode=read_only|editable` and readonly `pane=diagram|source|metadata`.
The current `document_view_v1` policy admits explicit `UML_DOCUMENT_API_v1` grants:
`umlDocumentRead`, `umlDocumentParse`, `umlDocumentLayout`, `umlDocumentEdit`,
`umlDocumentWrite`, `umlDocumentExport`. Read/Parse/Layout are the minimum; edits,
canonical saves and exports require their corresponding extra operation. A kind
or SDK call-list declaration never supplies a grant. Actual design admission and
each finite native intent enforce them. Same-ID save also retains original
Document producer/grant/Session/full-revision/source-SHA/namespace checks.

C++ routes primary actions; shared CORE owns literal SourceSurface, semantic
parser/editor, Native2D shaped painter, File Publication and typed UML draft
Workspace/History. No source body, Tcl, renderer path or new native ABI is added.
New finite action names and exact bounded subset are documented in
[UML Document API](UML_DOCUMENT_API_v1.md). Existing native Markdown packages and
old ABI signatures remain unchanged; actual old-package smoke and genuine
Builder-authored UML modules are separate acceptance gates.

## Acquisition target (P032 additive)

The genuine `acquisition_v1` target uses a separate
`gxtxt_acquisition_sdk_v1.hpp` and finite compiler-checked free callback factory;
it does not change this catalog's original Viewer SDK or ABI. Module/profile
capabilities name exact operations of `ACQUISITION_HANDLER_PLUGIN_API_v1`:
source_info, source_read, progress, cancelled, prepare_output, output_write,
output_finish, helper_call. Actual CORE admission intersects profile/module/
phase grants. The metadata browser exposes only this target's actual typed
methods and current saved closure, without compiling or activating a grant.

Selected source bytes use a separate live CORE broker; native actors receive no
source paths/FDs. Typed numeric chunks remain local in CORE-created write-only
buffers, with provisional references and existing Publication/RAW/Group owners.
The new target alone requires pre-CDLL Landlock and seccomp process restrictions;
ordinary same-process threads remain supported, fork/process descendants do not.
See [Native Acquisition SDK](NATIVE_ACQUISITION_SDK_v1.md) for exact signatures,
limits, staged-output handshake and actual registered Python/Tcl helper
dispatcher under the same Acquisition Job. Module/profile capabilities and
live roster/source/lease admission remain mandatory; helper presence alone
grants nothing. Source Note and independent runtime qualification stay separate.
Discovery is not functional acceptance or proof of normal installation.
