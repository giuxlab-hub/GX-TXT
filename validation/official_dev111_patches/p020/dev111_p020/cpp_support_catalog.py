#!/usr/bin/env python3
"""Generate/check public support catalog from actual next policy/SDK/owners."""
from pathlib import Path
import argparse,ast,hashlib,json

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('framework',type=Path)
p.add_argument('--check',action='store_true')
a=p.parse_args()
F=a.framework.resolve()
if not str(F).startswith('/srv/gxtxt/agents/scratch/DEV111-P020-') or not (F/'gxtxt_pipeline.tcl').is_file():
    raise SystemExit('P020 generator requires an explicit isolated P020 scratch framework')
policy_path=F/'core/development/policy_v1.json'
policy=json.loads(policy_path.read_text())
compiler_path=F/'core/python/gxtxt_cpp_policy.py'
flags=next(ast.literal_eval(n.value) for n in ast.parse(compiler_path.read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FLAGS' for t in n.targets))
sdk=F/'core/development/sdk/gxtxt_viewer_sdk_v1.hpp'
signatures=[line.strip() for line in sdk.read_text().splitlines() if line.startswith('    ') and line.strip().endswith(' const;')]
headers=policy['admitted_headers']
lines=['# Current C/C++ Viewer support catalog','',
'Generated from the installed Development policy, SDK and runtime owners. Open this catalog from **Develop → C/C++ support catalog** in the Viewer Development Workspace. The existing rendered Markdown manual window provides find, links and scrolling.','',
'## Language and ownership','',
policy['language_support']['standard']+'.', '',
', '.join(policy['language_support']['features'])+'.','',policy['language_support']['runtime'], '',policy['language_support']['ownership'], '',
'The compiler performs real Clang parsing and checks the fixed public on_event ABI and typed Host calls. Ordinary local C/C++ functions and standard library facilities supplied by the admitted headers are available, subject to their actual Debian implementation. Headers below are the exact direct-include admission list; transitive system dependencies are supplied by those headers. A new direct header, dependency or compiler/link option requires a concrete purpose and MAIN architectural review. Language availability does not grant a competing canonical store, scheduler or scientific renderer.','',
'## Admitted headers and review decisions','',
f'Exactly {len(headers)} explicitly admitted header identities. Each row records the facilities/purpose and architectural decision; all are accepted for local project logic, with CORE public ownership retained. Presence here establishes admission, not exhaustive testing of every library function or platform.','',
'| Exact header | Facilities, purpose and architectural review |','| --- | --- |']
lines += [f'| `{name}` | {decision} |' for name,decision in headers.items()]
lines += ['', '## Supported public Host functions','',
'Only these currently compiled SDK methods integrate the C++ author with GX-TXT. Each still requires its explicit compatible project capability, component/form and version. Discovery of another public Tcl/Script API does not admit an arbitrary C++ call.','', '```cpp',*signatures,'```','',
'Presentation operations run through the shared GUI Host. Numerical methods use Numeric; canonical diagrams use Native2D/Interactive Document; scientific forms use Scientific Execution/Jobs; scientific graphs use Plot v4. document_bind uses existing HTML/PDF/Source Surface/paged Dataset consultation. catalog_refresh/inspect/action use a declared GUI Host section and the existing Scientific Library Manager, with exact per-action grants; they do not expose a generic invoke or scientific library parser. demo is explicitly a RAM demonstration and cannot establish scientific acceptance.','',
'tex_command uses a complete declared TeX form and finite GUI Host operations. Source Surface, canonical TeX Workspace/Resource, managed native TeX builds, PDF consultation and File Publication retain their existing ownership. Build saves the guarded draft before running the typesetter; installed C++ execution still uses the packaged binary. The additive nonvirtual method/opcode30 preserves old Event/State/Host storage and operations1–29. See VIEWER_GUI_HOST_API_v1 for exact form and lifecycle contracts; source admission is not installed Viewer acceptance.','',
'New Viewer scientific 2D and 3D graphs require PLOT_DATASET_API_v4. PLOT_DATASET_API_v3 is deprecated and denied for new restricted declarations/source/build/export/runtime admission; preserved historical consumers keep their existing compatibility API.','',
'## ABI, compiler and runtime','',
'```text',*flags,'```','',
'The trusted adapter links a shared library with system libstdc++, libm and pthread (-shared -pthread -Wl,-z,defs -lstdc++ -lm). The SDK is automatically supplied. The event handler is void on_event(gx::Host&, gx::State&, const gx::Event&). State has sixteen double slots and one unsigned counter; these are bounded public event transport, not a restriction on ordinary local C++ types or project memory. Host callbacks use bounded finite values/text and enumerated operations.','',
'Development validates and builds once per actual source/build dependency version. Preview, Test and Export reuse the retained binary; closing and reopening an unchanged project does not rebuild it. Installed packages distribute native/viewer.so. Plugin admission verifies that artifact and SDK compatibility; normal installed startup/events load it directly without compiler/linker invocation or a silent rebuild fallback. Missing/incompatible artifacts require a precise error and a compatible package. No development compiler is needed to execute a compatible installed Viewer. Local compiled events use the existing managed persistent worker and apply their public GUI plan before the next queued pointer action; scientific Jobs remain asynchronous.','',
f"Current admission/build budgets: source {policy['source_limit_bytes']} bytes; compile {policy['compile_timeout_seconds']} seconds; active event wall budget {policy['process_timeout_seconds']} seconds. The native worker currently applies CPU3s, address-space256MiB, output-file1MiB and no core dumps. These are actual execution budgets, not a claim of hostile-code security or a general language prohibition. Purpose-specific legitimate workload changes need owner review.", '',
'## Integrated debugger','',
'GDB/MI supports breakpoints, Continue, Step Into/Over/Out, Pause/Stop and stack-frame selection through the managed Development owner. Read-only opaque variable identities provide real struct/array children: all aggregates initially collapsed; click to expand vertical fields/elements, click again to collapse. Children load only on request, in pages of at most64; maximum depth8 and512 displayed nodes per stop/frame. A further page is explicit. Each new stop/frame/continuation invalidates old child identities. Unavailable or optimized-out values retain actual debugger diagnostics. No arbitrary GDB console/expression injection is exposed.','',
'Threads and fork/wait are admitted ordinary project logic. This catalog does not promise additional debugger thread-switch or follow-fork controls: the present enumerated control contract remains authoritative. Authors are encouraged to use the integrated debugger for actual development problems and report reproducible CPP_DEBUGGER_BUGs.','',
'## Synchronization fingerprints','',
'Generated by the catalogued DEV111-P020 cpp_support_catalog.py; regenerate on every admitted-header/SDK/compiler/runtime/debugger change, and require --check before final packaging. These fingerprints describe the exact current inputs; scientific/installed acceptance remains in the independent release matrix.','', '| Input | SHA256 |','| --- | --- |']
for relative in ['core/development/policy_v1.json','core/development/sdk/gxtxt_viewer_sdk_v1.hpp','core/python/gxtxt_cpp_policy.py','core/python/gxtxt_viewer_development.py','core/development/sdk/trusted_adapter_v1.cpp','core/python/gxtxt_viewer_native_worker.py','core/python/gxtxt_viewer_cpp_debug.py','plugins/modules/viewer.development_workspace/api/debugger.tcl','plugins/modules/viewer.development_workspace/api/workspace.tcl','core/tcl/viewer_development_api_v1.tcl','core/tcl/viewer_development_request.tcl','core/tcl/script_job_api_v1.tcl','core/tcl/plugin_install_api_v1.tcl']:
    lines.append(f'| `{relative}` | `{hashlib.sha256((F/relative).read_bytes()).hexdigest()}` |')
content='\n'.join(lines)+'\n'
target=F/'docs/api/CPP_SUPPORT_CATALOG.md'
if a.check:
    if not target.is_file() or target.read_text()!=content:raise SystemExit('STALE_SUPPORT_CATALOG: regenerate from actual owners before packaging')
    print('PASS_CURRENT_SUPPORT_CATALOG')
else:
    target.write_text(content)
    print(json.dumps({'path':str(target),'headers':len(headers),'host_functions':len(signatures),'sha256':hashlib.sha256(content.encode()).hexdigest()}))
