# Generated Viewer connector API v1

SPDX-License-Identifier: GPL-3.0-or-later

This version-1 module activation contract is shared by two installed providers.
It is not a singleton scientific service. Retain the provider when resolving its
namespace, design, handlers or Viewer ID.

| Module | Namespace | Viewer ID | Backend |
|---|---|---|---|
| viewer.dev107_scientific_xy | ::GX::Generated_viewer_dev107_scientific_xy | scientific_xy | viewer_dev107_scientific_xy_gui |
| viewer.dev107_native3d_embedded | ::GX::Generated_viewer_dev107_native3d_embedded | native3d_embedded | viewer_dev107_native3d_embedded_gui |

Each descriptor owns `api/viewer.tcl` as its entrypoint. Use the existing public
Viewer dispatcher; it lazily activates the selected installed module:

```tcl
set window [::GX::viewerOpen viewer.dev107_scientific_xy scientific_xy]
```

## Exact connector entries

The following signatures exist separately in **each namespace** above.

| Procedure | Arguments/default | Return/effect |
|---|---|---|
| `design` | none | public `viewerGuiDesignRead` result for this provider's installed `gui/design.tcldict` |
| `handlers` | none | dict keyed by design handler ID; each value has `command` and `enabled` Tcl command prefixes for this provider |
| `open ?context?` | Tcl dict default `{}` | composes/raises its provider window through `viewerGuiDesignCompose`, returning the Tk path |
| `workspaceOpen context` | required Workspace context accepted by `viewerGuiDesignWorkspaceOpen` | that existing owner's result; opens this provider/design in runtime mode |
| `dispatch operation scene` | required lifecycle operation and resolved scene dict | `open` with scene's `open_context` or `{}` |

Window paths are `.viewer_dev107_scientific_xy` and
`.viewer_dev107_native3d_embedded`. When a window exists and context has no
`workspace_id`, `open` raises and returns it. With a nonempty Workspace ID it
reviews the current adapter transition through the existing Workspace owner;
refusal returns the current window, otherwise the old window is destroyed and
the requested context is composed. `dispatch` itself does not branch on
operation and does not implement an arbitrary operation router.

Activation checks for the public design composer, loads the provider's generated
defaults and author handlers once per process, and requires the design's public
API families. This connector's activation loop calls
`workbenchExtensionRequireApi` with each API ID; it does not itself enforce the
paired version value. Do not infer a numeric-version admission proof from that
loop. Public design validation/admission is a separate owner.

## Context, limitations and language reachability

The context is forwarded to the existing composition/Workspace owner. Workspace
IDs, provider/schema/generation checks, managed resources, source IDs, units and
scientific result contracts remain with their documented owners:
[Viewer GUI design](VIEWER_GUI_DESIGN_v1.md),
[Viewer GUI Host](VIEWER_GUI_HOST_API_v1.md),
[Session Workspace](SESSION_WORKSPACE_API_v1.md). A handler-prefix dict contains
host callbacks and is not a serialized Script Bridge capability or scientific
result. No generic per-handler argument/result contract is declared here.

This family has no registered Python/Octave Script Bridge operations and no
typed C++ SDK method. Installed catalog visibility is not execution admission.
The Tcl entrypoints belong to trusted Viewer activation/composition; independent
C++ authors use the official Development/SDK path rather than calling Tcl
handler prefixes. Missing CORE design capability, invalid design, missing API,
disabled/uninstalled provider, invalid context and stale/incompatible Workspace
errors retain their existing owner diagnostics. Tk is needed to open a window;
Session requirements depend on the selected design/action/Workspace context.

Neither this connector nor its name validates its authors' numerical results,
Plot dimensionality, rendering, persistence or runtime parity. Consult each
installed module's actual user manual for its own feature/acceptance scope.
