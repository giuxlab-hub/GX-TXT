# Viewer Interface Builder API v1

SPDX-License-Identifier: GPL-3.0-or-later

This is the installed `viewer.interface_builder` module's **host activation
contract**, version 1. Its declared entrypoint is `api/builder.tcl`, namespace
`::GX::InterfaceBuilder`, backend `viewer_interface_builder_tk`, Viewer ID
`interface_builder`. CORE owns the design model, component contracts, Preview,
generation and managed requests. The module is the editing client.

## Open and dispatch

Use the existing public Viewer Provider API from a trusted Tcl host:

```tcl
set window [::GX::viewerOpen viewer.interface_builder interface_builder]
```

`viewerOpen moduleId viewerId ?context?` defaults context to an empty dictionary.
It checks the installed provider and presentation enablement, activates this
entrypoint lazily and passes a resolved scene to its registered backend.

| Entry in `::GX::InterfaceBuilder` | Required / optional arguments | Result and effect |
|---|---|---|
| `open ?context?` | optional Tcl dict, default `{}` | Tk path `.gxInterfaceDesigner`; creates the designer and Preview through existing owners, or raises the existing designer and Preview |
| `dispatch operation scene` | backend lifecycle operation string; resolved scene dict | calls `open` with `scene.open_context` or `{}`, returns its window |

The current `open` body accepts but does not inspect context keys. No file,
project, Dataset or Workspace auto-open key is promised. `dispatch` does not
branch on `operation`; it is the Viewer backend adapter, not an arbitrary
command-dispatch service. The existing designer/model is reused during its
process lifetime; opening the Viewer is not a new scientific Workspace commit.

## Authoring contracts and state

Use [Viewer GUI design](VIEWER_GUI_DESIGN_v1.md) for validated inert design
data/model editing, [Viewer GUI Host](VIEWER_GUI_HOST_API_v1.md) for composition,
and [Viewer Development](VIEWER_DEVELOPMENT_API_v1.md) for generation requests.
An action's `diagram_tool {COMPONENT_ID MODE}` property binds its checked
presentation to the existing canonical Native2D controller. Builder validates
the declared target/catalog/mode; the existing SDK command still selects the
tool synchronously. See the design contract for conflicts and lifecycle rules.
`api/icons.tcl` and `api/diagrams.tcl` contribute the designer's native dialogs;
their widget callbacks are not new cross-language API methods.

The designer's command catalog exposes New/Open/Save/Save As, Undo/Redo,
copy/cut/paste, component add/remove/duplicate/layout, validation, Preview,
analysis, import/comparison, Dataset binding, generation and test controls.
These are stateful GUI actions. Calling a procedure merely because it appears
in the module namespace is not a stable headless automation contract. Use the
documented public CORE model/request services for programmatic work and the
installed module manual for native workflows.

Unsaved design transitions use the actual native Yes/No/Cancel review. Cancel
refuses the transition; Yes calls the existing design Save owner and refuses
the transition if the design remains dirty. Save file dialogs can be cancelled.
Closing cancels owned requests/timers/recording/monitoring and destroys its
Preview and designer. Opening/design editing needs Tk; no Session is required
merely to open the designer. Data-bound actions retain their public owner's
Session/source requirements.

## Language, units, limits and errors

This activation API has no registered Python/Octave Script Bridge operations
and no typed `gx::Host` method. Catalog visibility does not grant either access.
There is no generic C++ invoke by family/name. C++ Viewer authors use the
official Workspace/SDK and current reviewed public capabilities. Ordinary C++17
language admission is separate from ownership of scientific data/services.

Context IDs and Tk paths carry no scientific units; design geometry and test
limits belong to the linked CORE owners. This facade declares no independent
numeric/schema/size limit or scientific result shape. Missing/disabled provider,
invalid Viewer context, missing capability and design validation failures
propagate from their existing owner. The GUI `safe method args` callback wrapper
displays failures and returns `{status failed message ...}`; that is not a
uniform result guarantee for public `viewerOpen` (which can raise Tcl errors).

The descriptor has no detailed operation metadata for its individual editing
callbacks. This reference documents actual activation, not proof that every
designer feature, scientific action, test or generated package has passed.
