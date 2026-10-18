# Component Gallery and synthetic demonstrations API v1

Discover `VIEWER_COMPONENT_DEMO_API_v1@1` through the normal CORE extension API
catalog. `viewerGuiComponentDemoApiInfo` describes its operations and fixture
version. The owner is `core/tcl/viewer_component_demo_v1.tcl`; construction still
belongs to the actual UI Field, Viewer GUI Host, documentation, Workspace,
History, Native2D, Plot and Native3D owners. The Gallery is a Builder client.

## Discover and extend an example

`viewerGuiComponentDemoCatalog` joins the current
`viewerGuiComponentCapabilities` dictionary to inert example specifications.
Each row contains the exact capability, including API/version/owner, supported
parents, construction command, properties, events, status and limitations. It
does not make an unavailable scientific capability available by drawing a box.
There are 28 available types in dev107, including the genuine Native3D v2 host.

`viewerGuiComponentDemoRegister type specification` registers bounded inert
`properties`, `instructions` and optional `states` for an existing capability.
Unknown fields, missing properties/instructions and specifications over16KiB are
refused. No executable author callback is part of a specification. Add an actual
public capability before registering its demonstration. The registry belongs
to trusted CORE integration; ordinary restricted Viewer projects cannot edit it.
Fixture version1 changes describe sample content, never scientific algorithms.

```tcl
::GX::viewerGuiComponentDemoRegister entry {
    properties {default {Synthetic sample A} width 28}
    instructions {Type a local label and commit with Return. No science runs.}
    states {default selected disabled empty}
}
set catalog [::GX::viewerGuiComponentDemoCatalog]
::GX::viewerGuiComponentDemoOpen entry composite default
```

`viewerGuiComponentDemoDesign type ?standalone|composite?` returns an ordinary
validated inert design. `viewerGuiComponentDemoOpen type ?variant? ?state?`
creates the mapped `.gxComponentDemo` through `viewerGuiDesignCompose` in `demo`
mode. Sample states are default, selected, disabled, empty and invalid; a state
affects only controls for which it has a meaning (invalid is a numeric field
example). A label or native renderer does not pretend to have a disabled entry
state. Reset constructs a fresh deterministic fixture; close releases its real
owners and state. A saved design does not acquire these transient demo values.

## Component inventory and meaningful interaction

| Types | Actual example and owner | Limits |
|---|---|---|
| panel, section | UI Field labelled containers with entry, toggle and choice children | Presentation hierarchy, no acquisition |
| splitter | Native paned window and two useful child panels | Native sash geometry, no source mutation |
| tabs, tab | Native notebook, acquisition controls and summary table | A tab always has its legal tabs parent |
| entry, combobox, checkbutton | UI Field native controls, synthetic strings/options/boolean | Local changed contract |
| field, toggle, choice | UI Field labelled typed controls | Numeric bounds and real validator; no computation handler |
| dataset_selector | Same UI Field selector with explicit demo-only choices | No canonical Dataset catalog lookup in demo |
| label, status | Native labelled/read-only presentation | Display only |
| progress | Native progress presentation at25; Advance changes sample state | No scientific progress or Job ID |
| log | Scrollable bounded illustrative log | Not a Job log |
| list, table | Native selection/list and four-row read-only table | No cell editing, formulas or Worksheet semantics |
| action, command_toolbar | Existing ViewerCommands presentation | Only fixed synthetic Advance/Reset; domain hooks stay disconnected |
| menu, context_menu | Existing native menu owners and legal shell | Explicit synthetic command receipts, no private Tcl dispatch |
| help | Documentation owner sample plus real Builder manual | Documentation links never execute examples |
| workspace | Workspace GUI owner's inert strip/sample inspector | Actual save/open commands disabled; no Workspace record |
| history | History owner's inert Description/History sample | No canonical scientific step or Undo authority |
| native2d | Public `NATIVE2D_TEMPORARY_DISPLAY_API_v1` | Same native scene/hit/drag/presentation owner; RAM only |
| plot | Public `NATIVE_PLOT_DISPLAY_API_v1` using real Plot v4/Cairo | Bounded prepared RAM line/marker model, no Dataset |
| native3d | Public `NATIVE_3D_GUI_HOST_API_v2@2` | Independent real native cube/axes, worker/camera/lifetime |

## Modes, events and boundaries

Design changes the actual Builder model and its bounded Undo/Redo. Demo owns
separate transient values, scene handles and a bounded128-event log. Runtime
Test is a separate explicit connection to matching installed handlers inside
the established marked private fixture. Selecting Demo never connects those
handlers. `viewerGuiDesignCompose ... demo` refuses a nonempty handler dictionary,
does not acquire a scientific Session token and disables real Workspace/History.

The Gallery shows exact capability metadata, instructions, Show example / Try
interaction, Reset, Open public API guide and current synthetic events. Traces
use `author demo_fixture`, empty scientific source identity and no counterfeit
Dataset/Job IDs. Existing GUI Laboratory `structure` and `demo` families inspect
the same actual instance; their assertion scope is explicit. A constructor or
mount PASS does not establish every pointer operation or scientific correctness.

General component icon authoring is not available in this contract. Decorative
glyphs are not claimed as a supported runtime icon property. P0 debugger icons
are a separate documented CORE control contract.

See also [Viewer design](VIEWER_GUI_DESIGN_v1.md),
[temporary Native2D](NATIVE2D_TEMPORARY_DISPLAY_API_v1.md),
[RAM Plot](NATIVE_PLOT_DISPLAY_API_v1.md) and
[independent Native3D](NATIVE_3D_GUI_HOST_API_v2.md).
