# Viewer GUI Integration Manifest v1

This public **host-only** Tcl API composes
existing GUI authorities. It has no Script Bridge widget API, second registry,
scientific state, renderer, command model, execution scheduler or Workspace format.
Discover with `::GX::viewerGuiHostApiInfo` and require through the existing
Workbench Extension API's public API resolver. The first complete consumer is
`viewer.replicate_curve_analysis`; Worksheet consumes its shared command adapter.

`viewerGuiManifestValidate manifest` checks the schema, installed Viewer identity,
existing command IDs and supported canvas owner. `viewerGuiCompose manifest`
returns named `toolbar`, `inspector`, `canvas`, `footer`, `status`, `menus` slots.
`viewerGuiActionsMount window frame ?commandIds?` mounts an existing command catalog.
Callbacks belong to the Viewer and execute under its existing Session guard.

Required manifest fields:

| Field | Contract |
| --- | --- |
| schema | `gxtxt.viewer_gui_manifest.v1` |
| viewer_id | Registered module of kind `viewer` |
| provider_id | Existing Viewer/Workspace provider identity |
| window, title | Tcl widget path and English title |
| handlers | Existing Viewer command IDs → `command`, optional `enabled`/`applicable` callbacks |

Optional fields are `geometry`, `guard`, `workspace`, `history`, `history_record`,
`canvas`, `canvas_mount`, `inspector_width`, `toolbar_actions`, `menus` and
`context_actions`. Unknown fields fail. `canvas` declares `api_id` from
`PLOT_DATASET_API_v4`, `NATIVE2D_VIEWPORT_HOST_v1`, or
`NATIVE_3D_GUI_HOST_API_v1`. This declaration chooses an owner, not a new renderer.
The Plot module is activated through public module activation. Other owners are
mounted by their existing host callback via `canvas_mount canvasSlot`; a declaration
alone does not instantiate a scientific scene. Workspace and History callbacks
use their existing host contracts unchanged. Saved History may be supplied via
`history_record`. No job runs as a consequence of composition.

`menus` is an ordered list of `{label English-title actions {command-id - ...}}`
descriptors; `-` separates groups. `toolbar_actions` and `context_actions` select
registered commands. All menu/toolbar/shortcut enablement uses Viewer Commands.
`viewerGuiContextMount window widget` attaches the composed context menu to a
scientific host created after composition. `viewerGuiSelectionAttach window
widget ?event?` refreshes both menus and toolbar when the consumer's native
selection changes; `viewerGuiActionsRefresh window` handles domain state changes.
`inspector_width` is the initial splitter position (200–600 pixels); users can
drag the normal pane sash without rebuilding scientific geometry.

Dialog composition uses UI Field's `uiFieldDialogCreate`,
`uiFieldDialogPresent` and `uiFieldDialogClose`. Focus and optional grabs wait
for actual mapping and release on Unmap. This is GUI-only lifecycle state and
does not add a persistent authority or Script Bridge widget protocol.

| Responsibility | Sole existing owner / additive extension |
| --- | --- |
| Generic regions, scrollable inspector | UI Field: `uiFieldViewerShellCreate` |
| Actions, key configuration, applicability, enablement | Configuration / ViewerCommands; one catalog and consumer selection |
| Toolbar placement | UI Field controls layout; ViewerCommands widget adapter |
| Workspace menu/lifecycle | Session Workspace Viewer Host |
| History/Description and Undo/Redo | Scientific Recipe History host |
| Contained selector | UI Field: `uiFieldSelectorWithinViewer` |
| Context menu placement | UI Menu: `uiMenuPopup` |
| Scientific canvas | Public Native2D, Native3D or Plot v4 host |
| Help | Documentation Browser |

`uiFieldSelectorWithinViewer combobox viewer` preserves the combobox's values,
textvariable and `<<ComboboxSelected>>` semantics. It composes a native listbox
and scrollbar inside the Viewer, prefers available space above/below, clamps to
the client area and adjusts on resize. Enter/pointer commits; Escape dismisses;
Tab restores normal traversal. Opening does not select a History action. It uses
no global ttk private popdown modifications. Destroy releases bindings/grab.
Debian local X11 acceptance is recorded; Windows, remote X11 and alternate DPI/
theme combinations require their own platform acceptance and are not claimed PASS.
