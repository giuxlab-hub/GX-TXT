# GAP-SPICE-001 / 007 investigation — implementation in progress

The separate author actually encountered missing `schematic_place` and a Builder
`schematic` component rejection. Its subsequent contract review requested an
approved editing profile on the **existing native2d component**, canonical
document receipts, explicit ports and junctions, typed properties and shared
Workspace/History. The request is unresolved until both authoring surfaces expose
that facility and the same restricted developer successfully retests it.

Existing owners inspected: `native2d_geometry_api_v1.tcl`,
`native2d_viewport_host_v1.tcl`, `native2d_presentation_v1.tcl`,
`interactive_document_api_v1.tcl`, `session_workspace_api_v1.tcl`,
`scientific_recipe_history.tcl`, `viewer_gui_design_v1.tcl` and
`docs/api/NATIVE2D_NETWORK_dev065.md`.

The retained network already preserves exact curve constituents and explicit
coincident control-node identity. It must not be replaced or described as absent.
However, its connected geometric compositions do not provide disconnected symbol
instances, typed symbol attributes, named ports, explicit electrical terminals or
net-label semantics. A disconnected schematic must not be forced into a connected
geometric Path, or infer electrical connectivity from matching coordinates.

The compatible extension therefore introduces the inert document **format**
`gxtxt.native2d.diagram.v1` within Interactive Document, with bounded symbol
instances and stable component/pin/junction/wire/label references. This is a format
and additional Native2D operations, not a new API family, registry or persistence
authority. Both electrical and non-electrical flow catalogs use the same model.
Catalogs are bounded original GPL data read as dictionaries, never evaluated.
The existing native scene and public geometry operations project their paths;
`native2DCanvasSnapshot` remains the renderer. Its new optional bounded annotations
and axes visibility are reusable presentation fields with unchanged defaults.

`native2DGeometryDiagramEdit` checks the expected document generation, revision
and SHA, validates the entire proposed transaction, then commits through
`interactiveDocumentUpdate` without yielding between comparison and commit.
Failed validation leaves the canonical document unchanged. Only explicit endpoint
references connect wires. Deleting one terminal removes its own incident edges,
preserving unrelated crossings. Restoration preserves the allocation high-water
counter so a history branch cannot reuse an already allocated object identity.

Evidence: `_private_dev108/diagram-contracts01/result.tcldict` and
`diagram-contracts02/result.tcldict` pass canonical document, non-electrical reuse,
explicit crossing, failed-edit atomicity, stale-source and restore/reopen checks.
These are document checks, not complete GUI or SPICE acceptance. Real viewport
iterations retain initial harness/root-configuration, native snap-argument and
error-message recovery failures in `_private_dev108/gui_diagram01..03`.

Still required: author-facing Builder/SDK admission and independent retest,
actual typed property and full gesture coverage, drag feedback, complete History
and Workspace restoration, simulation/provider bridge, scientific validation and
installed Viewer workflows. No scientific numerical engine is implemented here;
display-coordinate transforms do not compute circuit behavior.

Further GAP001 native wiring review: the existing document `wire.route` field
already represents explicit bend points, but the viewport accepted only two
endpoint clicks. Automatic default routes visibly overlap unrelated components
in ordinary circuits. The compatible extension exposes those same points through
empty-grid clicks while a wire is active, Backspace to remove a pending bend,
and Escape/tool change to cancel. A shared Native2D scene curve projects the
pending route; only the final explicit endpoint commits the existing transaction.
No coordinate crossing becomes a junction and no new renderer is introduced.

## GAP014: restricted author native GUI test entrypoint

The immutable author request79eed182... records an actual tooling boundary:
compiled CLI operation plans have no GUI execution authority. Existing owners
inspected: VIEWER_DEVELOPMENT_API_v1 project/source/build/Preview/installed-open,
its existing debugger command/status project mailbox, VIEWER_GUI_HOST_API_v1
logical component discovery and native Native2D/public Plot controls. Author
raw Tcl, shell, global desktop and widget paths remain denied.

Preferred additive existing Development operation: optional gui_test data mailbox
attached explicitly in the real Workspace to one installed restricted module
whose three source hashes exactly match its project. Alternatives were the
existing CLI plans (insufficient actual GUI) and unrestricted X11 (violates the
author boundary). No separate test daemon, transport family or scientific path
is needed: use the established project command/status pattern. The GUI owner
checks exact request fields, attachment/Session/source identity and declared
component types before fixed native input; author cannot select modules, paths,
Tcl, subprocess arguments or unrelated windows. Receipts capture actual bindings,
canonical references and screenshots; they confer no runtime scientific authority.

The feature is opt-in, cannot be enabled by author CLI, and does not alter
legacy test/run semantics or API version1. Denial/GUI/source/lifecycle tests,
manuals/catalog exposure and actual separate-author retest remain pending;
this is development authorization, not GAP014 closure or acceptance.

Independent handoff review of the author's actual rotated RC circuit found Fit
clipped the R1/value label above the resistor. Screenshot
gui_author_native03/independent_author_detailed_prepare_error.png preserves it.
Native2D fit_all correctly fits geometry, but presentation annotations live
outside geometric bounds. The compatible diagram Viewport Fit command now
merges annotation anchors and actual Sans13 pixel font boxes through existing
Native2D world/device transforms, then fits the combined presentation extent.
No scientific geometry/payload changes or alternate renderer occurs. Other
registered flow/electrical catalogs reuse this correction. Actual two-size
label pixel-bound and cold Workspace GUI checks remain required.
