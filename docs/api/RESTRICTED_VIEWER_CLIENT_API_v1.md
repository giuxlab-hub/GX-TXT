# Installed C++ Viewer client API v1

SPDX-License-Identifier: GPL-3.0-or-later

`RESTRICTED_VIEWER_CLIENT_API_v1` is the existing stable identifier for trusted
installed C++ Viewer activation. It does not define a separate language or a
generic scientific API. The following providers declare it; retain
the exact module/provider identity when resolving its connector:

| Module | Namespace | Viewer ID | Backend |
|---|---|---|---|
| viewer.circuit_workbench | ::GX::Restricted_viewer_circuit_workbench | circuit_workbench | viewer_circuit_workbench_restricted_cpp_v1 |
| viewer.dataset_table_next | ::GX::Restricted_viewer_dataset_table_next | dataset_table | viewer_dataset_table_next_restricted_cpp_v1 |
| viewer.dev107_restricted_native3d | ::GX::Restricted_viewer_dev107_restricted_native3d | development_example | viewer_dev107_restricted_native3d_restricted_cpp_v1 |
| viewer.electromagnetics_studio | ::GX::Restricted_viewer_electromagnetics_studio | electromagnetics_studio | viewer_electromagnetics_studio_restricted_cpp_v1 |
| viewer.html | ::GX::Restricted_viewer_html | html | viewer_html_restricted_cpp_v1 |
| viewer.pdf_reader | ::GX::Restricted_viewer_pdf_reader | pdf_reader | viewer_pdf_reader_restricted_cpp_v1 |
| viewer.code_dataset | ::GX::Restricted_viewer_code_dataset | code_dataset | viewer_code_dataset_restricted_cpp_v1 |
| viewer.scientific_3d_workbench | ::GX::Restricted_viewer_scientific_3d_workbench | scientific_3d_workbench | viewer_scientific_3d_workbench_restricted_cpp_v1 |
| viewer.scientific_latex | ::GX::Restricted_viewer_scientific_latex | scientific_latex | viewer_scientific_latex_restricted_cpp_v1 |
| viewer.scientific_library_workspace | ::GX::Restricted_viewer_scientific_library_workspace | scientific_library_workspace | viewer_scientific_library_workspace_restricted_cpp_v1 |

Each declares `api/viewer.tcl`. Use the installed public provider, for example:

```tcl
set window [::GX::viewerOpen viewer.circuit_workbench circuit_workbench]
```

This opens its installed application and may invoke its existing runtime
lifecycle. It is not a read-only metadata probe or a scientific validation test.

## Public connector signatures

| Entry | Arguments | Result / effect |
|---|---|---|
| `handlers` in each listed namespace | none | existing `viewerDevelopmentInstalledBindings module provider root` result: design-handler ID dict with command `::GX::viewerDevelopmentInvoke` |
| `dispatch operation scene` in each listed namespace | required lifecycle operation and resolved scene dict | calls `viewerDevelopmentInstalledOpen` for the exact provider/root with `scene.open_context` or `{}`; returns that owner's window |
| `workspaceOpen context` when exported by the provider | required provider-qualified Viewer open-context dictionary (`ViewerOpenContextDictionary`) | calls the same installed-open owner with that context; returns its existing Tk window result |
| `texOpen document` when exported by the provider | existing canonical current-Session TeX Document identity (`TeXDocumentID`) | forwards `{tex_document_id $document}` to the same exact installed-open owner; returns its existing Tk window result |

The current official Export emits these four callbacks and documents their exact
namespaced commands, arguments, parameter types and results in the descriptor's
inert `public_contract`. Existing packages can retain an earlier connector: the
Native3D example declares only `handlers` and `dispatch`; older Code Dataset and
PDF Reader packages declare those plus `workspaceOpen`. Inspect the selected
package's declaration and `api/viewer.tcl` rather than assuming every installed
provider has all four. A newer generated connector takes effect through normal
package installation.

`texOpen` is an activation callback, not a TeX build command or a guarantee of
TeX functionality in that Viewer. Export adds a LaTeX article Workspace
contribution only for a design section declaring `tex_source`; opening that
article also requires the matching provider and the existing complete TeX form.
The canonical Document and its Session remain owned by the existing public
Document/Workspace services. The four-callback declaration grants no additional
Script Bridge or SDK permission.

None of these connectors has a public `open` procedure. `dispatch` does not
branch on operation. Its root is the installed module root, never a caller
argument or interchangeable provider instance.

The existing CORE `viewerDevelopmentInstalledOpen module provider root
?context?` defaults context to `{}`. It checks that root equals the normal
registered module root and requires the normally packaged `native/viewer.so`.
The common installed-open owner checks its exact build/source/interface
correlation, compatible SDK-v1 ABI/adapter mappings and current public grants,
then executes the packaged binary in place. It performs no runtime source AST
validation, source-copy development project or implicit compilation. Missing or
incompatible binaries require a matching precompiled package and fail explicitly.
Installed admission bounds its required package files at16MiB; project source
checks retain their4MiB ordinary-file bound. These are distinct limits.

The existing Resource Management owner allocates temporary runtime receipts;
the existing Script Job auxiliary owner manages the separate duplex compiled
worker and its cancellation/descendants. Short local callbacks return their real
typed plan before Tk dispatches subsequent queued input; scientific work remains
with its existing public asynchronous owners. A recognized Workspace ID context
is normalized by the existing Workspace owner. Original source/state/callback
fingerprints continue to guard Workspace restoration. Consumers must not create
a second source, runtime-artifact, scientific or Workspace authority.

## Exposure, data and failures

This family has no registered Python/Octave Bridge operation, no direct typed
C++ `gx::Host` method and no generic invoke by API name. It is a trusted Tcl
activation connector for C++ authored application logic. C++ integrates only
through the current official SDK/project grants and existing public owners.
The profile's ordinary C++17/C language facilities include classes/templates,
exceptions/allocation, threads and fork/wait as described in
[C/C++ support catalog](CPP_SUPPORT_CATALOG.md). Stable legacy identifiers or UI
wording do not impose a contrary language ban. Canonical scientific data and
lifecycle ownership remains public CORE responsibility.

Handler IDs and Tk paths have no scientific units. Application-specific source,
model, units, numerical uncertainty, output and domain diagnostics are not
specified by this connector. Read the selected module's manual and the real
scientific service contracts. The connector delegates missing/disabled provider,
unregistered root, missing/oversized source, missing/incompatible packaged binary,
public-grant/runtime and
Workspace errors to [Viewer Development](VIEWER_DEVELOPMENT_API_v1.md) and
[Viewer Provider](VIEWER_PROVIDER_API_v1.md). No uniform scientific result schema
or success guarantee is invented here. Catalog presence alone proves neither
current project admission nor scientific/runtime acceptance.
